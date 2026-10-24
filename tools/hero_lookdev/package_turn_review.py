#!/usr/bin/env python3
"""Package 60-, 120- or 180-frame transparent Jiang Yanqiu sword-action clips."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from fractions import Fraction
from pathlib import Path
from typing import Any


FPS = 30
FRAME_COUNT = 60
FRAME_PATTERN = re.compile(r"^frame-(\d{4})\.png$")
FRAME_PREFIX = "frame-"
FRAME_SUFFIX = ".png"
SELECTED_FRAMES = (1, 9, 17, 25, 33, 41, 49, 60)
WARM_GRAY = "0xe5e0d5"
DEFAULT_FFMPEG = Path("/opt/homebrew/bin/ffmpeg")
DEFAULT_FFPROBE = Path("/opt/homebrew/bin/ffprobe")
MODEL_FILENAME = "jiang-fullbody-turn.blend"
VIDEO_FILENAME = "turn-preview.mp4"
CONTACT_SHEET_FILENAME = "contact-sheet.png"
METADATA_FILENAME = "metadata.json"
MANIFEST_FILENAME = "sha256-manifest.json"


class PackageError(RuntimeError):
    """A fail-closed input, encoding, or package validation error."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def file_record(path: Path, relative_to: Path | None = None) -> dict[str, Any]:
    name = path.relative_to(relative_to).as_posix() if relative_to else str(path)
    return {"path": name, "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def require_absolute_path(path: Path, label: str) -> Path:
    expanded = path.expanduser()
    if not expanded.is_absolute():
        raise PackageError(f"{label} must be an absolute path: {path}")
    return expanded


def validate_inputs(args: argparse.Namespace) -> tuple[Path, Path, Path, list[Path], tuple[int, int]]:
    frame_count = args.frame_count
    frames_dir = require_absolute_path(args.frames_dir, "--frames-dir")
    blend = require_absolute_path(args.blend, "--blend")
    output = require_absolute_path(args.output, "--output")

    if frames_dir.is_symlink() or not frames_dir.is_dir():
        raise PackageError(f"--frames-dir must be an existing regular directory: {frames_dir}")
    if blend.is_symlink() or not blend.is_file() or blend.suffix.lower() != ".blend":
        raise PackageError(f"--blend must be an existing regular .blend file: {blend}")
    if output.exists() or output.is_symlink():
        raise PackageError(f"Refusing to overwrite existing output: {output}")
    if not output.parent.is_dir():
        raise PackageError(f"Output parent directory must already exist: {output.parent}")

    resolved_frames = frames_dir.resolve()
    resolved_output = output.parent.resolve() / output.name
    if resolved_output == resolved_frames or resolved_frames in resolved_output.parents:
        raise PackageError("Output must be outside the source frames directory")

    expected = [frames_dir / f"frame-{index:04d}.png" for index in range(1, frame_count + 1)]
    frame_like = [
        item for item in frames_dir.iterdir()
        if item.name.startswith(FRAME_PREFIX) and item.suffix.lower() == FRAME_SUFFIX
    ]
    if len(frame_like) != frame_count or {item.name for item in frame_like} != {item.name for item in expected}:
        names = ", ".join(sorted(item.name for item in frame_like)[:8])
        raise PackageError(
            f"Expected exactly frame-0001.png through frame-{frame_count:04d}.png; "
            f"found {len(frame_like)} frame PNG candidate(s): {names}"
        )
    for path in expected:
        if path.is_symlink() or not path.is_file():
            raise PackageError(f"Frame must be a regular file: {path}")

    image_size: tuple[int, int] | None = None
    try:
        from PIL import Image
    except ImportError as exc:
        raise PackageError(
            "Pillow is required to validate RGBA frames and make the contact sheet; "
            "run with an existing Python interpreter that has Pillow installed"
        ) from exc

    for path in expected:
        try:
            with Image.open(path) as image:
                if image.format != "PNG" or image.mode != "RGBA":
                    raise PackageError(f"Frame must be an RGBA PNG: {path.name} (mode={image.mode})")
                if getattr(image, "n_frames", 1) != 1:
                    raise PackageError(f"Animated PNG input is not supported: {path.name}")
                image.load()
                size = image.size
                if size[0] <= 0 or size[1] <= 0 or size[0] % 2 or size[1] % 2:
                    raise PackageError(f"Frame dimensions must be positive and even: {path.name} {size}")
                if image.getchannel("A").getextrema()[1] == 0:
                    raise PackageError(f"Frame has an empty alpha channel: {path.name}")
        except PackageError:
            raise
        except Exception as exc:
            raise PackageError(f"Could not decode {path.name}: {exc}") from exc
        if image_size is None:
            image_size = size
        elif size != image_size:
            raise PackageError(f"All frames must have equal dimensions; {path.name} is {size}, expected {image_size}")

    assert image_size is not None
    return frames_dir, blend, output, expected, image_size


def validate_executable(path: Path, label: str) -> Path:
    executable = require_absolute_path(path, label)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise PackageError(f"{label} must name an existing executable file: {executable}")
    return executable


def run_checked(command: list[str], label: str) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout)[-5000:]
        raise PackageError(f"{label} failed (exit {result.returncode}):\n{detail}")
    return result


def tool_version(path: Path, label: str) -> str:
    result = run_checked([str(path), "-version"], f"{label} version check")
    return (result.stdout.splitlines() or ["unknown"])[0].strip()


def copy_verified(
    source: Path,
    destination: Path,
    expected_sha256: str,
    package_root: Path,
) -> dict[str, Any]:
    with source.open("rb") as source_stream, destination.open("xb") as destination_stream:
        shutil.copyfileobj(source_stream, destination_stream)
    copied_sha256 = sha256_file(destination)
    if copied_sha256 != expected_sha256:
        raise PackageError(f"Copy hash mismatch for {source.name}")
    return file_record(destination, package_root)


def composite_video(
    ffmpeg: Path,
    frames_dir: Path,
    output_path: Path,
    image_size: tuple[int, int],
    frame_count: int,
) -> None:
    width, height = image_size
    duration_seconds = frame_count / FPS
    background = f"color=c={WARM_GRAY}:s={width}x{height}:r={FPS}:d={duration_seconds:.6f}"
    command = [
        str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
        "-framerate", str(FPS), "-start_number", "1",
        "-i", str(frames_dir / "frame-%04d.png"),
        "-f", "lavfi", "-i", background,
        "-filter_complex", "[1:v][0:v]overlay=0:0:format=auto:shortest=1,format=yuv420p[v]",
        "-map", "[v]", "-an",
        "-c:v", "libx264", "-preset", "medium", "-crf", "18",
        "-pix_fmt", "yuv420p", "-r", str(FPS), "-fps_mode", "cfr",
        "-frames:v", str(frame_count), "-t", f"{duration_seconds:.6f}",
        "-movflags", "+faststart", str(output_path),
    ]
    run_checked(command, "FFmpeg H.264 encoding")


def probe_video(ffprobe: Path, path: Path) -> dict[str, Any]:
    command = [
        str(ffprobe), "-v", "error", "-count_frames",
        "-show_entries",
        "stream=codec_type,codec_name,width,height,pix_fmt,avg_frame_rate,r_frame_rate,nb_read_frames,duration:"
        "format=duration,size",
        "-of", "json", str(path),
    ]
    result = run_checked(command, "FFprobe validation")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise PackageError("FFprobe returned invalid JSON") from exc


def parse_rate(value: str) -> Fraction:
    try:
        return Fraction(value)
    except (ValueError, ZeroDivisionError) as exc:
        raise PackageError(f"Invalid frame rate reported by FFprobe: {value!r}") from exc


def validate_probe_result(result: dict[str, Any], image_size: tuple[int, int], frame_count: int) -> None:
    streams = result.get("streams")
    if not isinstance(streams, list) or len(streams) != 1:
        raise PackageError("Expected one silent video stream and no audio or other streams")
    stream = streams[0]
    if stream.get("codec_type") != "video" or stream.get("codec_name") != "h264":
        raise PackageError(f"Expected H.264 video stream; FFprobe reported {stream}")
    if (stream.get("width"), stream.get("height")) != image_size:
        raise PackageError(f"Encoded dimensions differ from the source frames: {stream}")
    if stream.get("pix_fmt") != "yuv420p":
        raise PackageError(f"Expected yuv420p video; FFprobe reported {stream.get('pix_fmt')!r}")
    if parse_rate(str(stream.get("avg_frame_rate", "0/0"))) != FPS:
        raise PackageError(f"Expected {FPS} fps; FFprobe reported {stream.get('avg_frame_rate')!r}")
    try:
        read_frames = int(stream.get("nb_read_frames", -1))
    except (TypeError, ValueError):
        read_frames = -1
    if read_frames != frame_count:
        raise PackageError(f"Expected {frame_count} frames; FFprobe reported {stream.get('nb_read_frames')!r}")
    duration = result.get("format", {}).get("duration") or stream.get("duration")
    try:
        duration_value = float(duration)
    except (TypeError, ValueError) as exc:
        raise PackageError(f"FFprobe did not report video duration: {duration!r}") from exc
    duration_seconds = frame_count / FPS
    if not math.isclose(duration_value, duration_seconds, rel_tol=0.0, abs_tol=1e-6):
        raise PackageError(f"Expected exactly {duration_seconds:.1f} seconds; FFprobe reported {duration_value}")


def selected_frames(frame_count: int) -> tuple[int, ...]:
    if frame_count == FRAME_COUNT:
        return SELECTED_FRAMES
    return tuple(round(1 + index * (frame_count - 1) / 7) for index in range(8))


def create_contact_sheet(
    frame_paths: list[Path], output_path: Path, image_size: tuple[int, int], frame_count: int
) -> None:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError as exc:
        raise PackageError("Pillow is required to create the contact sheet") from exc

    columns, rows = 4, 2
    cell_width, cell_height = 330, 390
    margin, gap, label_height = 24, 18, 34
    sheet = Image.new(
        "RGB",
        (margin * 2 + columns * cell_width + (columns - 1) * gap,
         margin * 2 + rows * cell_height + (rows - 1) * gap),
        (229, 224, 213),
    )
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    by_number = {index: frame_paths[index - 1] for index in range(1, frame_count + 1)}
    box_width = cell_width - 28
    box_height = cell_height - label_height - 20
    for tile, number in enumerate(selected_frames(frame_count)):
        column, row = tile % columns, tile // columns
        left = margin + column * (cell_width + gap)
        top = margin + row * (cell_height + gap)
        draw.rounded_rectangle(
            (left, top, left + cell_width, top + cell_height),
            radius=10,
            fill=(247, 244, 237),
            outline=(206, 199, 187),
            width=1,
        )
        path = by_number[number]
        with Image.open(path) as source:
            frame = source.convert("RGBA")
            frame.thumbnail((box_width, box_height), Image.Resampling.LANCZOS)
        background = Image.new("RGBA", frame.size, (229, 224, 213, 255))
        background.alpha_composite(frame)
        x = left + (cell_width - frame.width) // 2
        y = top + 8 + (box_height - frame.height) // 2
        sheet.paste(background.convert("RGB"), (x, y))
        label = f"Frame {number:04d}"
        label_box = draw.textbbox((0, 0), label, font=font)
        label_x = left + (cell_width - (label_box[2] - label_box[0])) // 2
        draw.text((label_x, top + cell_height - label_height), label, fill=(57, 52, 45), font=font)
    sheet.save(output_path, format="PNG", optimize=False)


def viewer_html(image_size: tuple[int, int], frame_count: int) -> str:
    width, height = image_size
    duration_label = f"{frame_count / FPS:g}秒"
    action_label = "持剑转身" if frame_count == 60 else "起势—出剑—收势"
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>江砚秋 · {duration_label}{action_label}</title>
  <style>
    :root {{ color-scheme: light; font-family: system-ui, sans-serif; color: #39342d; background: #e5e0d5; }}
    body {{ max-width: 1100px; margin: 0 auto; padding: 24px; }}
    h1 {{ margin: 0 0 8px; font-size: 1.55rem; }}
    p {{ margin: 0 0 18px; }}
    video {{ display: block; width: min(100%, {width}px); max-height: 72vh; margin: 0 auto 24px; background: #e5e0d5; }}
    .frame-review {{ display: grid; grid-template-columns: minmax(0, 1fr); gap: 12px; }}
    .frame-stage {{ display: grid; place-items: center; min-height: 260px; padding: 12px; background: #f7f4ed; border: 1px solid #cec7bb; border-radius: 10px; }}
    .frame-stage img {{ display: block; max-width: 100%; max-height: 72vh; width: auto; height: auto; background: #e5e0d5; object-fit: contain; }}
    .controls {{ display: flex; align-items: center; gap: 10px; }}
    .controls input {{ flex: 1; }}
    button {{ padding: 7px 12px; }}
    output {{ min-width: 92px; text-align: right; font-variant-numeric: tabular-nums; }}
  </style>
</head>
<body>
  <h1>江砚秋 · {duration_label}{action_label}</h1>
  <p>全身动作片段 · 可正常播放、半速查看或逐帧检查。动作结束后可重播。</p>
  <div class="controls"><button id="play-normal" type="button">正常播放</button><button id="play-slow" type="button">半速播放</button></div>
  <video controls preload="metadata" src="{VIDEO_FILENAME}" aria-label="{duration_label}{action_label}预览"></video>
  <section class="frame-review" aria-label="透明帧审阅">
    <div class="frame-stage"><img id="frame-image" src="frames/frame-0001.png" width="{width}" height="{height}" alt="Transparent animation frame 1 of {frame_count}"></div>
    <div class="controls">
      <button id="previous" type="button">上一帧</button>
      <input id="frame-slider" type="range" min="1" max="{frame_count}" value="1" step="1" aria-label="选择帧">
      <button id="next" type="button">下一帧</button>
      <output id="frame-label" for="frame-slider">第 1 / {frame_count} 帧</output>
    </div>
  </section>
  <script>
    const slider = document.getElementById('frame-slider');
    const image = document.getElementById('frame-image');
    const label = document.getElementById('frame-label');
    const video = document.querySelector('video');
    function replay(speed) {{ video.currentTime = 0; video.playbackRate = speed; video.play(); }}
    document.getElementById('play-normal').addEventListener('click', () => replay(1));
    document.getElementById('play-slow').addEventListener('click', () => replay(.5));
    function showFrame(value) {{
      const frame = Math.max(1, Math.min({frame_count}, Number(value)));
      slider.value = String(frame);
      image.src = `frames/frame-${{String(frame).padStart(4, '0')}}.png`;
      image.alt = `第 ${{frame}} / {frame_count} 张透明帧`;
      label.value = `第 ${{frame}} / {frame_count} 帧`;
      label.textContent = label.value;
    }}
    slider.addEventListener('input', () => showFrame(slider.value));
    document.getElementById('previous').addEventListener('click', () => showFrame(Number(slider.value) - 1));
    document.getElementById('next').addEventListener('click', () => showFrame(Number(slider.value) + 1));
  </script>
</body>
</html>
"""


def write_json_new(path: Path, value: Any) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def package(args: argparse.Namespace) -> dict[str, Any]:
    frames_dir, blend, output, source_frames, image_size = validate_inputs(args)
    frame_count = args.frame_count
    duration_seconds = frame_count / FPS
    ffmpeg = validate_executable(args.ffmpeg, "--ffmpeg")
    ffprobe = validate_executable(args.ffprobe, "--ffprobe")
    source_blend_record = file_record(blend)
    source_frame_records = {path.name: file_record(path) for path in source_frames}

    output.mkdir()
    try:
        copied_frames_dir = output / "frames"
        copied_frames_dir.mkdir()
        copied_frames = []
        for source in source_frames:
            record = copy_verified(
                source,
                copied_frames_dir / source.name,
                source_frame_records[source.name]["sha256"],
                output,
            )
            copied_frames.append(record)

        model_copy = copy_verified(blend, output / MODEL_FILENAME, source_blend_record["sha256"], output)
        video_path = output / VIDEO_FILENAME
        composite_video(ffmpeg, copied_frames_dir, video_path, image_size, frame_count)
        probe_result = probe_video(ffprobe, video_path)
        validate_probe_result(probe_result, image_size, frame_count)
        packaged_frame_paths = [copied_frames_dir / source.name for source in source_frames]
        chosen_frames = selected_frames(frame_count)
        create_contact_sheet(packaged_frame_paths, output / CONTACT_SHEET_FILENAME, image_size, frame_count)
        viewer_path = output / "index.html"
        with viewer_path.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(viewer_html(image_size, frame_count))

        metadata = {
            "schema_version": 1,
            "fps": FPS,
            "frame_count": frame_count,
            "duration_seconds": duration_seconds,
            "clip_semantics": ("single action with matching neutral endpoints" if frame_count == 180
                               else "single action, not seamless loop"),
            "source": {
                "frames_directory": str(frames_dir),
                "frames": source_frame_records,
                "frame_bytes_total": sum(record["bytes"] for record in source_frame_records.values()),
                "blend": source_blend_record,
                "image_size": list(image_size),
            },
            "package": {
                "model_copy": model_copy,
                "video": file_record(video_path, output),
                "contact_sheet": file_record(output / CONTACT_SHEET_FILENAME, output),
                "viewer": file_record(viewer_path, output),
                "frames": copied_frames,
            },
            "encoding": {
                "codec": "H.264",
                "pixel_format": "yuv420p",
                "crf": 18,
                "background": "#E5E0D5",
                "audio": "none",
                "ffmpeg_path": str(ffmpeg),
                "ffmpeg_version": tool_version(ffmpeg, "FFmpeg"),
                "ffprobe_path": str(ffprobe),
                "ffprobe_version": tool_version(ffprobe, "FFprobe"),
                "ffprobe_result": probe_result,
            },
            "contact_sheet_frames": list(chosen_frames),
        }
        write_json_new(output / METADATA_FILENAME, metadata)

        manifest_entries = []
        for path in sorted(output.rglob("*")):
            if path.is_file() and path != output / MANIFEST_FILENAME:
                manifest_entries.append(file_record(path, output))
        write_json_new(output / MANIFEST_FILENAME, {
            "algorithm": "SHA-256",
            "files": manifest_entries,
        })
        return metadata
    except Exception:
        if output.is_dir() and not output.is_symlink():
            shutil.rmtree(output)
        raise


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames-dir", type=Path, required=True, help="absolute directory with sequentially named RGBA frames")
    parser.add_argument("--frame-count", type=int, choices=(60, 120, 180), default=60, help="number of frames at 30 fps (default: 60)")
    parser.add_argument("--blend", type=Path, required=True, help="absolute path to the existing Blender project")
    parser.add_argument("--output", type=Path, required=True, help="absolute path to a new package directory")
    parser.add_argument("--ffmpeg", type=Path, default=DEFAULT_FFMPEG, help=f"FFmpeg executable (default: {DEFAULT_FFMPEG})")
    parser.add_argument("--ffprobe", type=Path, default=DEFAULT_FFPROBE, help=f"FFprobe executable (default: {DEFAULT_FFPROBE})")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(argv)
        metadata = package(args)
    except (PackageError, OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({"status": "DONE", "output": str(args.output.expanduser()),
                      "frames": metadata["frame_count"], "duration_seconds": metadata["duration_seconds"]},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
