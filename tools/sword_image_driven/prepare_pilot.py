#!/usr/bin/env python3
"""Package existing Jiang motion renders and the approved reference image as offline inputs.

This tool only copies the reference PNG and encodes already-rendered PNG frames.
It does not render a model, call a network service, or run image/video inference.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

SCRIPT_VERSION = "1.0.0"
REFERENCE_FILENAME = "sword-standing-reference-v1.png"
EXPECTED_REFERENCE_SHA256 = "ac78cfceaf99dfff64f9dc48a54cee5561e4b1715e06152073a2ecf53833dcb3"
REFERENCE_MAX_BYTES = 5_000_000
VIDEO_MAX_BYTES = 200_000_000
FRAME_WIDTH = 384
FRAME_HEIGHT = 384
SOURCE_FPS = 60
FIRST_SAMPLE = 0
LAST_SAMPLE = 144
SAMPLE_COUNT = LAST_SAMPLE - FIRST_SAMPLE + 1
LOW_RATE_STEP = 4
BACKGROUND = "0xe5e0d5"


class PilotError(RuntimeError):
    """A fail-closed validation or encoding error."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def png_header(path: Path) -> dict[str, int]:
    with path.open("rb") as stream:
        header = stream.read(26)
    if len(header) < 26 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise PilotError(f"Not a valid PNG header: {path.name}")
    width, height = struct.unpack(">II", header[16:24])
    if width <= 0 or height <= 0:
        raise PilotError(f"Invalid PNG dimensions: {path.name}")
    return {"width": width, "height": height, "color_type": header[25]}


def run_checked(command: list[str], label: str) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout)[-4000:]
        raise PilotError(f"{label} failed (exit {result.returncode}):\n{detail}")
    return result


def tool_version(tool: Path) -> str:
    result = run_checked([str(tool), "-version"], f"{tool.name} version check")
    return (result.stdout.splitlines() or ["unknown"])[0].strip()


def probe_media(ffprobe: Path, path: Path, count_frames: bool = False) -> dict:
    command = [str(ffprobe), "-v", "error"]
    if count_frames:
        command.append("-count_frames")
    command.extend([
        "-show_entries",
        "stream=codec_name,width,height,pix_fmt,avg_frame_rate,r_frame_rate,nb_read_frames:"
        "format=duration,size",
        "-of", "json", str(path),
    ])
    result = run_checked(command, f"ffprobe {path.name}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise PilotError(f"ffprobe returned invalid JSON for {path.name}") from exc


def fraction_value(value: str) -> float:
    numerator, denominator = value.split("/", 1)
    return float(numerator) / float(denominator)


def decode_check(ffmpeg: Path, path: Path) -> None:
    run_checked([
        str(ffmpeg), "-hide_banner", "-v", "error", "-nostdin",
        "-i", str(path), "-f", "null", "-",
    ], f"decode {path.name}")


def encode_video(
    ffmpeg: Path,
    frames_dir: Path,
    temp_output: Path,
    fps: int,
    expected_frames: int,
    low_rate: bool,
) -> None:
    if low_rate:
        graph = (
            "[0:v]select='not(mod(n,4))',setpts=N/(15*TB),format=rgba[fg];"
            f"color=c={BACKGROUND}:s={FRAME_WIDTH}x{FRAME_HEIGHT}:r=15[bg];"
            "[bg][fg]overlay=shortest=1:eof_action=pass:repeatlast=0:format=auto,"
            "format=yuv420p[outv]"
        )
    else:
        graph = (
            "[0:v]format=rgba[fg];"
            f"color=c={BACKGROUND}:s={FRAME_WIDTH}x{FRAME_HEIGHT}:r=60[bg];"
            "[bg][fg]overlay=shortest=1:eof_action=pass:repeatlast=0:format=auto,"
            "format=yuv420p[outv]"
        )
    command = [
        str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
        "-framerate", str(SOURCE_FPS), "-start_number", str(FIRST_SAMPLE),
        "-i", str(frames_dir / "frame-%04d.png"),
        "-filter_complex", graph, "-map", "[outv]", "-an",
        "-frames:v", str(expected_frames),
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
        "-pix_fmt", "yuv420p", "-r", str(fps), "-fps_mode", "cfr",
        "-movflags", "+faststart", "-f", "mp4", str(temp_output),
    ]
    run_checked(command, f"encode {temp_output.name}")


def validate_video(
    ffprobe: Path,
    path: Path,
    expected_fps: int,
    expected_frames: int,
) -> dict:
    if not path.is_file():
        raise PilotError(f"Missing encoded video: {path.name}")
    size = path.stat().st_size
    if size <= 0 or size >= VIDEO_MAX_BYTES:
        raise PilotError(f"Video size outside allowed range: {path.name} ({size} bytes)")
    info = probe_media(ffprobe, path, count_frames=True)
    streams = info.get("streams", [])
    if len(streams) != 1:
        raise PilotError(f"Expected one video stream in {path.name}")
    stream = streams[0]
    actual_frames = int(stream.get("nb_read_frames", "-1"))
    actual_rate = fraction_value(stream.get("avg_frame_rate", "0/1"))
    duration = float(info.get("format", {}).get("duration", "nan"))
    if (
        stream.get("codec_name") != "h264"
        or stream.get("width") != FRAME_WIDTH
        or stream.get("height") != FRAME_HEIGHT
        or stream.get("pix_fmt") != "yuv420p"
        or actual_frames != expected_frames
        or not math.isclose(actual_rate, expected_fps, rel_tol=0, abs_tol=0.001)
        or not (2.0 <= duration < 3.0)
    ):
        raise PilotError(
            f"Video validation failed for {path.name}: "
            f"frames={actual_frames}, rate={actual_rate}, duration={duration}, stream={stream}"
        )
    return {
        "codec": stream["codec_name"],
        "width": stream["width"],
        "height": stream["height"],
        "pixel_format": stream["pix_fmt"],
        "fps": stream["avg_frame_rate"],
        "frame_count": actual_frames,
        "duration_seconds": duration,
        "size_bytes": size,
        "sha256": sha256_file(path),
    }


def write_json_exclusive(path: Path, value: dict) -> None:
    encoded = (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    with path.open("xb") as stream:
        stream.write(encoded)


def build(args: argparse.Namespace) -> dict:
    frames_dir = args.frames_dir.expanduser().absolute()
    reference = args.reference.expanduser().absolute()
    output = args.output.expanduser().absolute()
    ffmpeg = args.ffmpeg.expanduser().absolute()
    ffprobe = args.ffprobe.expanduser().absolute()

    if not frames_dir.is_dir():
        raise PilotError(f"Frame directory does not exist: {frames_dir}")
    if not reference.is_file():
        raise PilotError(f"Reference image does not exist: {reference}")
    for tool in (ffmpeg, ffprobe):
        if not tool.is_file():
            raise PilotError(f"Tool does not exist: {tool}")

    repo_root = Path(__file__).resolve().parents[2]
    qa_receipt = repo_root / ".local/qa/sword-image-driven-v1/input-validation.json"
    if output.exists() or output.is_symlink():
        raise PilotError(f"Refusing existing output path: {output}")
    if qa_receipt.exists() or qa_receipt.is_symlink():
        raise PilotError(f"Refusing existing QA receipt: {qa_receipt}")

    ref_size = reference.stat().st_size
    if ref_size >= REFERENCE_MAX_BYTES:
        raise PilotError(f"Reference image exceeds 5 MB: {ref_size} bytes")
    ref_header = png_header(reference)
    reference_hash = sha256_file(reference)
    if reference_hash != EXPECTED_REFERENCE_SHA256:
        raise PilotError(
            f"Reference SHA-256 mismatch: expected {EXPECTED_REFERENCE_SHA256}, got {reference_hash}"
        )

    frame_records = []
    frame_paths = []
    for sample_index in range(FIRST_SAMPLE, LAST_SAMPLE + 1):
        path = frames_dir / f"frame-{sample_index:04d}.png"
        if not path.is_file():
            raise PilotError(f"Missing source frame {path.name}")
        header = png_header(path)
        if (header["width"], header["height"]) != (FRAME_WIDTH, FRAME_HEIGHT):
            raise PilotError(
                f"Source frame size mismatch: {path.name} is "
                f"{header['width']}x{header['height']}, expected {FRAME_WIDTH}x{FRAME_HEIGHT}"
            )
        source_amc_frame = 1 + 2 * sample_index
        frame_records.append({
            "sample_index": sample_index,
            "source_amc_frame": source_amc_frame,
            "source_time_seconds": round(sample_index / SOURCE_FPS, 9),
            "filename": path.name,
            "sha256": sha256_file(path),
        })
        frame_paths.append(path)

    ref_probe = probe_media(ffprobe, reference)
    ref_streams = ref_probe.get("streams", [])
    if (
        len(ref_streams) != 1
        or ref_streams[0].get("codec_name") != "png"
        or ref_streams[0].get("width") != ref_header["width"]
        or ref_streams[0].get("height") != ref_header["height"]
    ):
        raise PilotError(f"ffprobe rejected reference PNG: {ref_probe}")
    ffmpeg_version = tool_version(ffmpeg)
    ffprobe_version = tool_version(ffprobe)
    decode_check(ffmpeg, reference)

    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir(exist_ok=False)
    ref_copy = output / REFERENCE_FILENAME
    shutil.copyfile(reference, ref_copy)
    if sha256_file(ref_copy) != reference_hash:
        raise PilotError("Copied reference does not match the selected reference bytes")

    encoded = {}
    configs = [
        ("motion-guide.mp4", 60, SAMPLE_COUNT, False),
        ("motion-guide-15fps.mp4", 15, len(range(FIRST_SAMPLE, LAST_SAMPLE + 1, LOW_RATE_STEP)), True),
    ]
    for name, fps, count, low_rate in configs:
        with tempfile.TemporaryDirectory(prefix=".encode-", dir=output) as temporary:
            temporary_path = Path(temporary) / name
            encode_video(ffmpeg, frames_dir, temporary_path, fps, count, low_rate)
            info = validate_video(ffprobe, temporary_path, fps, count)
            decode_check(ffmpeg, temporary_path)
            final_path = output / name
            os.link(temporary_path, final_path)
            encoded[name] = info

    if sha256_file(reference) != reference_hash:
        raise PilotError("Selected reference image changed during preparation")
    current_frame_hashes = [sha256_file(path) for path in frame_paths]
    if current_frame_hashes != [item["sha256"] for item in frame_records]:
        raise PilotError("One or more source frames changed during preparation")

    encoded["motion-guide.mp4"]["source_sample_indices"] = list(
        range(FIRST_SAMPLE, LAST_SAMPLE + 1)
    )
    encoded["motion-guide-15fps.mp4"]["source_sample_indices"] = list(
        range(FIRST_SAMPLE, LAST_SAMPLE + 1, LOW_RATE_STEP)
    )
    metadata = {
        "schema_version": 1,
        "tool_version": SCRIPT_VERSION,
        "generated_image_video": False,
        "inference_used": False,
        "cost_rmb": 0,
        "reference": {
            "filename": REFERENCE_FILENAME,
            "source_basename": reference.name,
            "sha256": reference_hash,
            "bundle_sha256": sha256_file(ref_copy),
            "size_bytes": ref_size,
            "width": ref_header["width"],
            "height": ref_header["height"],
            "unchanged_byte_for_byte": True,
        },
        "source_motion": {
            "source_basename_pattern": "frame-%04d.png",
            "sample_range_inclusive": [FIRST_SAMPLE, LAST_SAMPLE],
            "sample_count": SAMPLE_COUNT,
            "fps": SOURCE_FPS,
            "motion_span_seconds": LAST_SAMPLE / SOURCE_FPS,
            "frame_size": [FRAME_WIDTH, FRAME_HEIGHT],
            "background_hex": "#e5e0d5",
            "source_amc_fps": 120,
            "source_amc_frames_inclusive": [1, 1 + 2 * LAST_SAMPLE],
            "frames": frame_records,
        },
        "videos": encoded,
        "toolchain": {
            "ffmpeg": ffmpeg_version,
            "ffprobe": ffprobe_version,
            "encoder": "libx264",
            "network_used": False,
            "model_rendered": False,
        },
    }
    metadata_path = output / "metadata.json"
    write_json_exclusive(metadata_path, metadata)

    receipt = {
        "status": "validated",
        "tool_version": SCRIPT_VERSION,
        "bundle_directory": output.name,
        "reference_sha256": reference_hash,
        "reference_copy_sha256": sha256_file(ref_copy),
        "reference_unchanged_byte_for_byte": True,
        "source_frame_count": SAMPLE_COUNT,
        "source_frame_hashes": {item["filename"]: item["sha256"] for item in frame_records},
        "source_frames_unchanged_during_run": True,
        "videos": encoded,
        "metadata_sha256": sha256_file(metadata_path),
        "generated_image_video": False,
        "inference_used": False,
        "cost_rmb": 0,
    }
    qa_receipt.parent.mkdir(parents=True, exist_ok=True)
    write_json_exclusive(qa_receipt, receipt)
    return receipt


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames-dir", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--ffprobe", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        receipt = build(parse_args(sys.argv[1:] if argv is None else argv))
    except (PilotError, OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(receipt, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
