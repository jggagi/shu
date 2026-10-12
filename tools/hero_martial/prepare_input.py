#!/usr/bin/env python3
"""Package one supplied character reference and numbered motion-guide frames.

The tool copies the reference PNG byte-for-byte and encodes the supplied PNG
sequence as an H.264 guide. It does not generate, interpolate, or retarget poses.
"""
from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from typing import Any


SCRIPT_VERSION = "1.0.0"
REFERENCE_NAME = "reference.png"
VIDEO_NAME = "motion-guide.mp4"
REFERENCE_MAX_BYTES = 5_000_000
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SHOT_ID_PATTERN = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
FRAME_NAME_PATTERN = re.compile(r"frame-([0-9]{4})\.png\Z")


class PackageError(RuntimeError):
    """An input, encoding, or output validation failure."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def png_dimensions(path: Path) -> tuple[int, int]:
    """Read and validate the PNG signature and complete IHDR chunk."""
    try:
        with path.open("rb") as stream:
            header = stream.read(33)
    except OSError as exc:
        raise PackageError(f"Could not read PNG header for {path.name}: {exc}") from exc
    if (
        len(header) != 33
        or header[:8] != PNG_SIGNATURE
        or struct.unpack(">I", header[8:12])[0] != 13
        or header[12:16] != b"IHDR"
    ):
        raise PackageError(f"Not a valid PNG IHDR: {path.name}")
    expected_crc = struct.unpack(">I", header[29:33])[0]
    if zlib.crc32(header[12:29]) & 0xFFFFFFFF != expected_crc:
        raise PackageError(f"Invalid PNG IHDR checksum: {path.name}")
    width, height = struct.unpack(">II", header[16:24])
    if width <= 0 or height <= 0:
        raise PackageError(f"Invalid PNG dimensions: {path.name}")
    return width, height


def validate_shot_id(shot_id: str) -> None:
    if not SHOT_ID_PATTERN.fullmatch(shot_id):
        raise PackageError(
            "Invalid --shot-id; use lowercase letters, digits, and single internal hyphens"
        )


def inspect_sources(reference: Path, frames_dir: Path, fps: int) -> dict[str, Any]:
    """Validate supplied PNGs and return path-free, hashed source records."""
    if not isinstance(fps, int) or isinstance(fps, bool) or fps not in (15, 30):
        raise PackageError("FPS must be 15 or 30")
    if not reference.is_file():
        raise PackageError(f"Reference PNG does not exist: {reference}")
    reference_bytes = reference.stat().st_size
    if reference_bytes >= REFERENCE_MAX_BYTES:
        raise PackageError(f"Reference PNG must be smaller than 5 MB ({reference_bytes} bytes)")
    reference_width, reference_height = png_dimensions(reference)
    reference_sha256 = sha256_file(reference)

    if not frames_dir.is_dir():
        raise PackageError(f"Frames directory does not exist: {frames_dir}")
    try:
        candidates = [
            path for path in frames_dir.iterdir()
            if path.name.startswith("frame-") and path.suffix.lower() == ".png"
        ]
    except OSError as exc:
        raise PackageError(f"Could not list frame directory: {exc}") from exc
    if not candidates:
        raise PackageError("No numbered frame PNGs found")

    numbered: dict[int, Path] = {}
    for path in candidates:
        match = FRAME_NAME_PATTERN.fullmatch(path.name)
        if match is None:
            raise PackageError(f"Frame name must be frame-NNNN.png: {path.name}")
        index = int(match.group(1))
        if index in numbered:
            raise PackageError(f"Duplicate frame index: {index}")
        numbered[index] = path

    indices = sorted(numbered)
    if indices != list(range(len(indices))):
        raise PackageError("Frame sequence must be consecutive and start at frame-0000.png")
    frame_count = len(indices)
    duration_seconds = frame_count / fps
    if not 2.0 <= duration_seconds <= 8.0:
        raise PackageError(
            f"Frame sequence duration must be 2 to 8 seconds; got {duration_seconds:g} seconds"
        )

    frame_records: list[dict[str, Any]] = []
    source_width: int | None = None
    source_height: int | None = None
    for index in indices:
        path = numbered[index]
        if not path.is_file():
            raise PackageError(f"Frame is not a regular file: {path.name}")
        width, height = png_dimensions(path)
        if width % 2 or height % 2 or not (256 <= width <= 1024 and 256 <= height <= 1024):
            raise PackageError(
                f"Frame dimensions must be even and between 256 and 1024: "
                f"{path.name} is {width}x{height}"
            )
        if source_width is None:
            source_width, source_height = width, height
        elif (width, height) != (source_width, source_height):
            raise PackageError(
                f"Frame geometry changed at {path.name}: {width}x{height}, "
                f"expected {source_width}x{source_height}"
            )
        frame_records.append({
            "index": index,
            "filename": path.name,
            "sha256": sha256_file(path),
        })

    assert source_width is not None and source_height is not None
    return {
        "reference": {
            "source_path": reference,
            "source_basename": reference.name,
            "sha256": reference_sha256,
            "bytes": reference_bytes,
            "width": reference_width,
            "height": reference_height,
        },
        "source_motion": {
            "source_fps": fps,
            "frame_count": frame_count,
            "duration_seconds": round(duration_seconds, 9),
            "width": source_width,
            "height": source_height,
            "frames": frame_records,
        },
        "frame_paths": [numbered[index] for index in indices],
    }


def run_checked(command: list[str], label: str) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(command, text=True, capture_output=True, check=False)
    except OSError as exc:
        raise PackageError(f"Could not run {label}: {exc}") from exc
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "no tool output")[-4000:]
        raise PackageError(f"{label} failed (exit {result.returncode}):\n{detail}")
    return result


def resolve_tool(explicit: Path | None, name: str) -> Path:
    candidate = explicit if explicit is not None else shutil.which(name)
    if candidate is None:
        raise PackageError(f"{name} was not found on PATH; pass --{name}")
    path = Path(candidate).expanduser().absolute()
    if not path.is_file():
        raise PackageError(f"{name} executable does not exist: {path}")
    return path


def tool_version(tool: Path) -> str:
    result = run_checked([str(tool), "-version"], f"{tool.name} version check")
    lines = (result.stdout or result.stderr).splitlines()
    if not lines or not lines[0].strip():
        raise PackageError(f"{tool.name} returned an empty version")
    return lines[0].strip()


def probe_video(ffprobe: Path, video: Path) -> dict[str, Any]:
    result = run_checked(
        [
            str(ffprobe), "-v", "error", "-count_frames",
            "-show_entries",
            "stream=index,codec_type,codec_name,width,height,pix_fmt,avg_frame_rate,"
            "r_frame_rate,nb_frames,nb_read_frames:format=duration,size",
            "-of", "json", str(video),
        ],
        f"ffprobe {video.name}",
    )
    try:
        parsed = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise PackageError(f"ffprobe returned invalid JSON for {video.name}") from exc
    if not isinstance(parsed, dict):
        raise PackageError(f"ffprobe returned an unexpected result for {video.name}")
    return parsed


def parse_frame_rate(value: str) -> float:
    try:
        numerator, denominator = value.split("/", 1)
        top = int(numerator)
        bottom = int(denominator)
        if bottom == 0:
            raise ValueError("zero denominator")
        return top / bottom
    except (AttributeError, ValueError, ZeroDivisionError) as exc:
        raise PackageError(f"Invalid ffprobe frame rate: {value!r}") from exc


def validate_video(
    info: dict[str, Any], video: Path, fps: int, frame_count: int,
    expected_width: int, expected_height: int,
) -> dict[str, Any]:
    streams = info.get("streams")
    if not isinstance(streams, list) or len(streams) != 1:
        count = len(streams) if isinstance(streams, list) else 0
        raise PackageError(f"Expected exactly one video stream, got {count}")
    stream = streams[0]
    if not isinstance(stream, dict) or stream.get("codec_type") != "video":
        raise PackageError("Expected the single stream to be video")
    try:
        width = int(stream["width"])
        height = int(stream["height"])
        actual_frames = int(stream["nb_read_frames"])
        duration = float(info["format"]["duration"])
    except (KeyError, TypeError, ValueError) as exc:
        raise PackageError("ffprobe omitted required video timing or geometry fields") from exc
    actual_fps = parse_frame_rate(str(stream.get("avg_frame_rate", "")))
    nominal_fps = parse_frame_rate(str(stream.get("r_frame_rate", "")))
    expected_duration = frame_count / fps
    if (
        stream.get("codec_name") != "h264"
        or stream.get("pix_fmt") != "yuv420p"
        or width != expected_width
        or height != expected_height
        or actual_frames != frame_count
        or not math.isclose(actual_fps, fps, rel_tol=0, abs_tol=0.001)
        or not math.isclose(nominal_fps, fps, rel_tol=0, abs_tol=0.001)
        or not math.isclose(duration, expected_duration, rel_tol=0, abs_tol=0.001)
    ):
        raise PackageError(
            "Encoded video does not match the requested contract: "
            f"codec={stream.get('codec_name')}, pixel_format={stream.get('pix_fmt')}, "
            f"size={width}x{height}, avg_fps={actual_fps:g}, "
            f"nominal_fps={nominal_fps:g}, frames={actual_frames}, "
            f"duration={duration:g}"
        )
    return {
        "file": VIDEO_NAME,
        "sha256": sha256_file(video),
        "bytes": video.stat().st_size,
        "codec": stream["codec_name"],
        "pixel_format": stream["pix_fmt"],
        "width": width,
        "height": height,
        "fps": fps,
        "frame_count": actual_frames,
        "duration_seconds": round(duration, 9),
    }


def encode_video(
    ffmpeg: Path, frames_dir: Path, output: Path, fps: int, frame_count: int
) -> None:
    run_checked(
        [
            str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
            "-framerate", str(fps), "-start_number", "0",
            "-i", str(frames_dir / "frame-%04d.png"),
            "-map", "0:v:0", "-an", "-frames:v", str(frame_count),
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-fps_mode", "passthrough",
            "-movflags", "+faststart", "-f", "mp4", str(output),
        ],
        f"encode {VIDEO_NAME}",
    )


def _atomic_rename_no_replace(source: Path, destination: Path) -> None:
    """Atomically publish a sibling directory without replacing a racing target."""
    if destination.exists() or destination.is_symlink():
        raise PackageError(f"Refusing existing output path: {destination}")
    if sys.platform == "darwin":
        libc = ctypes.CDLL(None, use_errno=True)
        try:
            rename_exclusive = libc.renamex_np
        except AttributeError as exc:
            raise PackageError("Atomic exclusive directory rename is unavailable") from exc
        rename_exclusive.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        rename_exclusive.restype = ctypes.c_int
        result = rename_exclusive(os.fsencode(source), os.fsencode(destination), 0x00000004)
    elif sys.platform.startswith("linux"):
        libc = ctypes.CDLL(None, use_errno=True)
        try:
            rename_no_replace = libc.renameat2
        except AttributeError as exc:
            raise PackageError("Atomic exclusive directory rename is unavailable") from exc
        rename_no_replace.argtypes = [
            ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint,
        ]
        rename_no_replace.restype = ctypes.c_int
        result = rename_no_replace(-100, os.fsencode(source), -100, os.fsencode(destination), 1)
    elif os.name == "nt":
        # Windows os.rename is an atomic same-volume move and fails if dst exists.
        try:
            os.rename(source, destination)
            return
        except FileExistsError as exc:
            raise PackageError(f"Refusing existing output path: {destination}") from exc
    else:
        raise PackageError(f"Atomic no-overwrite publication is unsupported on {sys.platform}")

    if result != 0:
        error_number = ctypes.get_errno()
        if error_number == errno.EEXIST:
            raise PackageError(f"Refusing existing output path: {destination}")
        raise OSError(error_number, os.strerror(error_number), str(destination))


def _cleanup_owned_temp(temp_dir: Path, generated_paths: list[Path]) -> None:
    cleanup_errors: list[str] = []
    for path in reversed(generated_paths):
        try:
            if path.is_file() or path.is_symlink():
                path.unlink()
        except OSError as exc:
            cleanup_errors.append(f"{path.name}: {exc}")
    try:
        temp_dir.rmdir()
    except FileNotFoundError:
        pass
    except OSError as exc:
        # Leave unexpected files/directories untouched rather than removing
        # anything this invocation did not create.
        cleanup_errors.append(f"{temp_dir.name}: {exc}")
    if cleanup_errors:
        raise PackageError("Could not fully clean invocation temporary files: " + "; ".join(cleanup_errors))


def prepare_package(
    shot_id: str,
    reference: Path,
    frames_dir: Path,
    fps: int,
    output: Path,
    ffmpeg: Path | None = None,
    ffprobe: Path | None = None,
) -> dict[str, Any]:
    output = Path(os.path.abspath(Path(output).expanduser()))
    if output.exists() or output.is_symlink():
        raise PackageError(f"Refusing existing output path: {output}")
    validate_shot_id(shot_id)

    reference = Path(reference).expanduser()
    frames_dir = Path(frames_dir).expanduser()
    sources = inspect_sources(reference, frames_dir, fps)
    ffmpeg_path = resolve_tool(ffmpeg, "ffmpeg")
    ffprobe_path = resolve_tool(ffprobe, "ffprobe")
    ffmpeg_version = tool_version(ffmpeg_path)
    ffprobe_version = tool_version(ffprobe_path)

    output.parent.mkdir(parents=True, exist_ok=True)
    temp_dir = Path(tempfile.mkdtemp(prefix=f".{output.name}.tmp-", dir=output.parent))
    generated_paths: list[Path] = []
    published = False
    try:
        reference_copy = temp_dir / REFERENCE_NAME
        generated_paths.append(reference_copy)
        shutil.copyfile(sources["reference"]["source_path"], reference_copy)
        if sha256_file(reference_copy) != sources["reference"]["sha256"]:
            raise PackageError("Copied reference does not match the selected source bytes")

        video_path = temp_dir / VIDEO_NAME
        generated_paths.append(video_path)
        source_motion = sources["source_motion"]
        encode_video(ffmpeg_path, frames_dir, video_path, fps, source_motion["frame_count"])
        probed = probe_video(ffprobe_path, video_path)
        video_record = validate_video(
            probed, video_path, fps, source_motion["frame_count"],
            source_motion["width"], source_motion["height"],
        )
        run_checked(
            [
                str(ffmpeg_path), "-hide_banner", "-v", "error", "-nostdin", "-xerror",
                "-i", str(video_path), "-map", "0:v:0", "-f", "null", "-",
            ],
            f"full decode {VIDEO_NAME}",
        )
        video_record["decode_verified"] = True

        if sha256_file(sources["reference"]["source_path"]) != sources["reference"]["sha256"]:
            raise PackageError("Reference PNG changed during preparation")
        for path, record in zip(sources["frame_paths"], source_motion["frames"]):
            if sha256_file(path) != record["sha256"]:
                raise PackageError(f"Source frame changed during preparation: {path.name}")

        metadata = {
            "schema_version": 1,
            "tool_version": SCRIPT_VERSION,
            "shot_id": shot_id,
            "reference": {
                "file": REFERENCE_NAME,
                "source_basename": sources["reference"]["source_basename"],
                "sha256": sha256_file(reference_copy),
                "bytes": reference_copy.stat().st_size,
                "width": sources["reference"]["width"],
                "height": sources["reference"]["height"],
            },
            "source_motion": {
                "source_fps": source_motion["source_fps"],
                "frame_count": source_motion["frame_count"],
                "duration_seconds": source_motion["duration_seconds"],
                "width": source_motion["width"],
                "height": source_motion["height"],
                "frames": source_motion["frames"],
            },
            "videos": [video_record],
            "toolchain": {
                "ffmpeg": ffmpeg_version,
                "ffprobe": ffprobe_version,
            },
        }
        metadata_path = temp_dir / "metadata.json"
        generated_paths.append(metadata_path)
        with metadata_path.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(metadata, stream, ensure_ascii=False, indent=2)
            stream.write("\n")

        _atomic_rename_no_replace(temp_dir, output)
        published = True
        return metadata
    finally:
        if not published:
            _cleanup_owned_temp(temp_dir, generated_paths)


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shot-id", required=True, help="Stable lowercase shot identifier")
    parser.add_argument("--reference", required=True, type=Path, help="Supplied reference PNG")
    parser.add_argument("--frames-dir", required=True, type=Path, help="Numbered guide PNG directory")
    parser.add_argument("--fps", required=True, type=int, choices=(15, 30))
    parser.add_argument("--output", required=True, type=Path, help="New package directory")
    parser.add_argument("--ffmpeg", type=Path, default=None, help="ffmpeg executable (default: PATH lookup)")
    parser.add_argument("--ffprobe", type=Path, default=None, help="ffprobe executable (default: PATH lookup)")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    try:
        result = prepare_package(
            args.shot_id, args.reference, args.frames_dir, args.fps, args.output,
            args.ffmpeg, args.ffprobe,
        )
    except (PackageError, OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
