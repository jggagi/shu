#!/usr/bin/env python3
"""Package a completed generated clip into transparent frames and an atlas.

This wrapper reuses the repository's offline CPU ISNet-Anime helpers while
keeping each hero-martial shot in a separate resource namespace.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
from fractions import Fraction
from typing import Any


SCRIPT_VERSION = "1.0.0"
SHOT_IDS = frozenset({
    "jiang-sword-horizontal-return-v1",
    "jiang-staff-forward-thrust-v1",
    "jiang-fist-straight-punch-v1",
})
ASSET_ROOT = Path("assets/art/hero_martial_v1")
PROTECTED_ASSETS = (
    Path("assets/art/sword_image_driven_v1"),
    Path("assets/art/sword_image_clean_matte_v1"),
)
ATLAS_COLUMNS = 4
ATLAS_ROWS = 3
ATLAS_PADDING = 4
MIN_SOURCE_DIMENSION = 256
MAX_SOURCE_DIMENSION = 2048
MAX_FRAME_COUNT = 1000
MIN_DURATION_SECONDS = 2.0
MAX_DURATION_SECONDS = 30.0
MAX_DURATION_ERROR_SECONDS = 0.001
MAX_CFR_INTERVAL_ERROR_SECONDS = 0.0001
SHA256_PATTERN = re.compile(r"[0-9a-fA-F]{64}\Z")
FRAME_NAME = "frame-{index:05d}.png"
ATLAS_NAME = "atlas-{page:03d}.png"


class PackageError(RuntimeError):
    """An input, media, inference, or output validation failure."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _valid_sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or SHA256_PATTERN.fullmatch(value) is None:
        raise PackageError(f"{label} must be a 64-character SHA-256 hex digest")
    return value.lower()


def validate_shot_id(shot_id: str) -> None:
    if shot_id not in SHOT_IDS:
        raise PackageError(f"Unsupported shot id: {shot_id}")


def validate_job_record(
    record: Any, *, shot_id: str, source_sha256: str, record_path: Path
) -> dict[str, Any]:
    """Validate the successful job receipt without copying arbitrary fields."""
    if not isinstance(record, dict):
        raise PackageError("Job record must be a JSON object")
    if record.get("status") != "SUCCEEDED":
        raise PackageError("Job record status must be SUCCEEDED")
    task_id = record.get("task_id")
    if not isinstance(task_id, str) or not task_id.strip():
        raise PackageError("Job record task_id must be a non-empty string")
    if record.get("shot_id") != shot_id:
        raise PackageError("Job record shot_id does not match --shot-id")
    job_source_sha256 = _valid_sha256(record.get("source_sha256"), "Job source_sha256")
    if job_source_sha256 != source_sha256.lower():
        raise PackageError("Job record source_sha256 does not match the selected video")

    def optional_label(name: str) -> str:
        value = record.get(name)
        return value.strip() if isinstance(value, str) and value.strip() else "unknown"

    inputs = record.get("inputs")
    if inputs is not None and not isinstance(inputs, dict):
        raise PackageError("Job inputs must be an object when provided")
    input_hashes = {}
    for field in ("reference", "video"):
        entry = (inputs or {}).get(field)
        if entry is None:
            input_hashes[field] = "unknown"
        elif not isinstance(entry, dict):
            raise PackageError(f"Job {field} input must be an object")
        else:
            input_hashes[field] = _valid_sha256(entry.get("sha256"), f"Job {field} input hash")

    return {
        "status": "SUCCEEDED",
        "provider": optional_label("provider"),
        "task_id": task_id.strip(),
        "model_title": optional_label("model_title"),
        "mode": optional_label("mode"),
        "quality": optional_label("quality"),
        "shot_id": shot_id,
        "source_sha256": job_source_sha256,
        "record_sha256": sha256_file(record_path),
        "input_hashes": input_hashes,
    }


def _parse_rate(value: Any, label: str) -> Fraction:
    if not isinstance(value, str) or not value:
        raise PackageError(f"ffprobe omitted {label}")
    try:
        rate = Fraction(value)
    except (ValueError, ZeroDivisionError) as exc:
        raise PackageError(f"Invalid ffprobe {label}: {value!r}") from exc
    if rate <= 0:
        raise PackageError(f"ffprobe {label} must be positive")
    return rate


def validate_frame_timestamps(
    timestamp_records: Any, *, frame_count: int, fps: Fraction
) -> list[float]:
    if not isinstance(timestamp_records, list) or len(timestamp_records) != frame_count:
        count = len(timestamp_records) if isinstance(timestamp_records, list) else 0
        raise PackageError(
            f"Expected {frame_count} decoded frame timestamps, got {count}"
        )
    timestamps: list[float] = []
    for index, record in enumerate(timestamp_records):
        if not isinstance(record, dict):
            raise PackageError(f"Invalid decoded frame timestamp record at frame {index}")
        try:
            timestamp = float(record["best_effort_timestamp_time"])
        except (KeyError, TypeError, ValueError) as exc:
            raise PackageError(f"Missing frame timestamp at frame {index}") from exc
        if not math.isfinite(timestamp):
            raise PackageError(f"Non-finite frame timestamp at frame {index}")
        timestamps.append(timestamp)

    expected_interval = 1.0 / float(fps)
    for index, (left, right) in enumerate(zip(timestamps, timestamps[1:])):
        interval = right - left
        if interval <= 0 or abs(interval - expected_interval) > MAX_CFR_INTERVAL_ERROR_SECONDS:
            raise PackageError(
                f"Decoded timestamps are not CFR within 0.1 ms at frames {index} and {index + 1}"
            )
    return timestamps


def validate_source_probe(
    probe: Any, timestamp_probe: Any
) -> dict[str, Any]:
    if not isinstance(probe, dict):
        raise PackageError("ffprobe returned an unexpected source-media result")
    streams = probe.get("streams")
    if not isinstance(streams, list) or len(streams) != 1 or not isinstance(streams[0], dict):
        raise PackageError("Expected exactly one selected video stream")
    stream = streams[0]
    if stream.get("codec_name") != "h264":
        raise PackageError(f"Source video must use H.264; got {stream.get('codec_name')!r}")
    try:
        width = int(stream["width"])
        height = int(stream["height"])
        frame_count = int(stream["nb_read_frames"])
        duration = float(probe["format"]["duration"])
    except (KeyError, TypeError, ValueError) as exc:
        raise PackageError("ffprobe omitted required source geometry or timing fields") from exc
    if (
        width <= 0 or height <= 0
        or width % 2 or height % 2
        or not MIN_SOURCE_DIMENSION <= width <= MAX_SOURCE_DIMENSION
        or not MIN_SOURCE_DIMENSION <= height <= MAX_SOURCE_DIMENSION
    ):
        raise PackageError(
            "Source dimensions must be positive even values from 256 to 2048; "
            f"got {width}x{height}"
        )
    if not 1 <= frame_count <= MAX_FRAME_COUNT:
        raise PackageError(f"Source frame count must be 1 to {MAX_FRAME_COUNT}; got {frame_count}")
    if not math.isfinite(duration) or not MIN_DURATION_SECONDS <= duration <= MAX_DURATION_SECONDS:
        raise PackageError(
            f"Source duration must be 2 to 30 seconds; got {duration:g} seconds"
        )

    average_rate = _parse_rate(stream.get("avg_frame_rate"), "average frame rate")
    nominal_rate = _parse_rate(stream.get("r_frame_rate"), "nominal frame rate")
    if average_rate != nominal_rate:
        raise PackageError(
            f"Average and nominal frame rates disagree: {average_rate} vs {nominal_rate}"
        )
    fps = float(average_rate)
    expected_duration = frame_count / fps
    if abs(duration - expected_duration) > MAX_DURATION_ERROR_SECONDS:
        raise PackageError(
            "Source duration does not match frame_count/fps within 1 ms: "
            f"duration={duration:g}, expected={expected_duration:g}"
        )
    frames = timestamp_probe.get("frames") if isinstance(timestamp_probe, dict) else None
    timestamps = validate_frame_timestamps(frames, frame_count=frame_count, fps=average_rate)
    return {
        "codec": "h264",
        "width": width,
        "height": height,
        "fps": fps,
        "fps_rational": f"{average_rate.numerator}/{average_rate.denominator}",
        "frame_count": frame_count,
        "duration_seconds": duration,
        "cell_width": width // 2,
        "cell_height": height // 2,
        "timestamps": timestamps,
    }


def _paths_overlap(left: Path, right: Path) -> bool:
    return left == right or left in right.parents or right in left.parents


def validate_destinations(
    *, repo_root: Path, shot_id: str, output: Path, assets: Path,
    input_paths: list[Path],
) -> tuple[Path, Path]:
    """Check output isolation without creating either destination or parent."""
    validate_shot_id(shot_id)
    root = repo_root.resolve()
    output_argument = output.expanduser().absolute()
    assets_argument = assets.expanduser().absolute()
    if output_argument.exists() or output_argument.is_symlink():
        raise PackageError(f"Refusing existing external output: {output_argument}")
    if assets_argument.exists() or assets_argument.is_symlink():
        raise PackageError(f"Refusing existing shot assets: {assets_argument}")
    output_path = output_argument.resolve(strict=False)
    assets_path = assets_argument.resolve(strict=False)
    expected_assets = (root / ASSET_ROOT / shot_id).resolve(strict=False)
    if assets_path != expected_assets:
        raise PackageError(
            f"--assets must equal the per-shot path {root / ASSET_ROOT / shot_id}"
        )
    if root not in assets_path.parents:
        raise PackageError("Shot assets must resolve inside the repository")
    if output_path == root or root in output_path.parents or output_path in root.parents:
        raise PackageError("--output must be outside and disjoint from the repository")
    if output_path.exists() or output_path.is_symlink():
        raise PackageError(f"Refusing existing external output: {output_path}")
    if assets_path.exists() or assets_path.is_symlink():
        raise PackageError(f"Refusing existing shot assets: {assets_path}")
    if _paths_overlap(output_path, assets_path):
        raise PackageError("External output and shot assets must not overlap")

    protected = [root / relative for relative in PROTECTED_ASSETS]
    for protected_path in protected:
        if _paths_overlap(assets_path, protected_path) or _paths_overlap(output_path, protected_path):
            raise PackageError(f"Destination overlaps a protected original asset: {protected_path}")
    resolved_inputs = [path.expanduser().resolve(strict=False) for path in input_paths]
    for destination in (output_path, assets_path):
        for source in resolved_inputs:
            if _paths_overlap(destination, source):
                raise PackageError(f"Destination overlaps an input file: {source}")
    return output_path, assets_path


def _run_checked(command: list[str], label: str) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(command, text=True, capture_output=True, check=False)
    except OSError as exc:
        raise PackageError(f"Could not run {label}: {exc}") from exc
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "no tool output")[-4000:]
        raise PackageError(f"{label} failed (exit {result.returncode}):\n{detail}")
    return result


def _tool_version(tool: Path) -> str:
    result = _run_checked([str(tool), "-version"], f"{tool.name} version check")
    lines = (result.stdout or result.stderr).splitlines()
    if not lines or not lines[0].strip():
        raise PackageError(f"{tool.name} returned an empty version")
    return lines[0].strip()


def _probe_source(ffprobe: Path, video: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    media = _run_checked(
        [
            str(ffprobe), "-v", "error", "-count_frames", "-select_streams", "v:0",
            "-show_entries",
            "stream=codec_name,width,height,avg_frame_rate,r_frame_rate,nb_read_frames:format=duration",
            "-of", "json", str(video),
        ],
        "source ffprobe",
    )
    timestamps = _run_checked(
        [
            str(ffprobe), "-v", "error", "-select_streams", "v:0", "-show_frames",
            "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", str(video),
        ],
        "source timestamp ffprobe",
    )
    try:
        return json.loads(media.stdout), json.loads(timestamps.stdout)
    except json.JSONDecodeError as exc:
        raise PackageError("ffprobe returned invalid JSON for the source video") from exc


def _load_helpers(repo_root: Path) -> Any:
    module_path = repo_root / "tools/sword_image_driven/package_generated_clip.py"
    spec = importlib.util.spec_from_file_location("shu_existing_clip_packager", module_path)
    if spec is None or spec.loader is None:
        raise PackageError("Could not load the existing offline clip-processing helpers")
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except ImportError as exc:
        raise PackageError(f"Existing clip-processing dependencies are unavailable: {exc}") from exc
    return module


def _composite_review(helper: Any, rgba_path: Path, destination: Path) -> None:
    with helper.Image.open(rgba_path) as frame:
        rgba = frame.convert("RGBA")
    background = helper.Image.new(
        "RGBA", rgba.size, (*helper.REVIEW_BACKGROUND, 255)
    )
    background.alpha_composite(rgba)
    background.convert("RGB").save(destination, format="PNG")


def package_clip(
    *, video: Path, job_record_path: Path, model: Path, expected_model_sha256: str,
    output: Path, assets: Path, ffmpeg: Path, ffprobe: Path,
) -> dict[str, Any]:
    repo_root = Path(__file__).resolve().parents[2]
    video = video.expanduser().resolve(strict=True)
    job_record_path = job_record_path.expanduser().resolve(strict=True)
    model = model.expanduser().resolve(strict=True)
    ffmpeg = ffmpeg.expanduser().resolve(strict=True)
    ffprobe = ffprobe.expanduser().resolve(strict=True)
    output_path, assets_path = validate_destinations(
        repo_root=repo_root,
        shot_id=assets.expanduser().name,
        output=output,
        assets=assets,
        input_paths=[video, job_record_path, model, ffmpeg, ffprobe],
    )
    shot_id = assets_path.name
    for path, label in (
        (video, "source video"), (job_record_path, "job record"),
        (model, "ONNX model"), (ffmpeg, "ffmpeg"), (ffprobe, "ffprobe"),
    ):
        if not path.is_file():
            raise PackageError(f"Missing {label}: {path}")

    expected_model_sha256 = _valid_sha256(expected_model_sha256, "--expected-model-sha256")
    source_sha256 = sha256_file(video)
    actual_model_sha256 = sha256_file(model)
    if actual_model_sha256 != expected_model_sha256:
        raise PackageError("ONNX model SHA-256 does not match --expected-model-sha256")
    try:
        job_data = json.loads(job_record_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PackageError(f"Could not read job record JSON: {exc}") from exc
    job = validate_job_record(
        job_data, shot_id=shot_id, source_sha256=source_sha256,
        record_path=job_record_path,
    )

    media_probe, timestamp_probe = _probe_source(ffprobe, video)
    source = validate_source_probe(media_probe, timestamp_probe)
    ffmpeg_version = _tool_version(ffmpeg)
    ffprobe_version = _tool_version(ffprobe)

    # All stdlib/path/media/hash validation completes before output creation.
    helper_path = repo_root / "tools/sword_image_driven/package_generated_clip.py"
    helper_hash = sha256_file(helper_path)
    helper = _load_helpers(repo_root)
    session = helper.create_session(model)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    assets_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.mkdir(exist_ok=False)
    raw_dir = output_path / "raw"
    rgba_dir = output_path / "rgba"
    atlas_dir = output_path / "atlas"
    review_dir = output_path / "review"
    for directory in (raw_dir, rgba_dir, atlas_dir, review_dir):
        directory.mkdir(exist_ok=False)

    _run_checked(
        [
            str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
            "-i", str(video), "-map", "0:v:0", "-fps_mode", "passthrough",
            "-start_number", "0", "-frames:v", str(source["frame_count"]),
            str(raw_dir / "frame-%05d.png"),
        ],
        "source frame extraction",
    )
    raw_frames = sorted(raw_dir.glob("frame-*.png"))
    if len(raw_frames) != source["frame_count"]:
        raise PackageError(
            f"Expected {source['frame_count']} extracted frames, found {len(raw_frames)}"
        )

    cell_size = (source["cell_width"], source["cell_height"])
    atlas_width = ATLAS_COLUMNS * (cell_size[0] + 2 * ATLAS_PADDING)
    atlas_height = ATLAS_ROWS * (cell_size[1] + 2 * ATLAS_PADDING)
    frame_records: list[dict[str, Any]] = []
    frame_metrics: list[dict[str, Any]] = []
    for index, raw_path in enumerate(raw_frames):
        expected_name = FRAME_NAME.format(index=index)
        if raw_path.name != expected_name:
            raise PackageError(f"Unexpected extracted frame name: {raw_path.name}")
        with helper.Image.open(raw_path) as raw_image:
            raw_image.load()
            source_rgb = raw_image.convert("RGB")
        if source_rgb.size != (source["width"], source["height"]):
            raise PackageError(f"{raw_path.name} dimensions differ from ffprobe")
        predicted_mask = helper.predict_mask(session, source_rgb)
        alpha_source = helper.trim_alpha(predicted_mask)
        edge_contacts = helper.edge_contacts(alpha_source)
        rgb_cell = source_rgb.resize(cell_size, helper.Image.Resampling.LANCZOS)
        alpha_cell = helper.Image.fromarray(alpha_source).resize(
            cell_size, helper.Image.Resampling.LANCZOS
        )
        rgba = rgb_cell.convert("RGBA")
        rgba.putalpha(alpha_cell)
        corner_alpha = helper.verify_zero_corners(rgba, raw_path.name)
        rgba_path = rgba_dir / expected_name
        rgba.save(rgba_path, format="PNG")
        cell_alpha = helper.np.asarray(alpha_cell, dtype=helper.np.uint8)
        anchor, support_bbox, figure_bbox = helper.foot_contact(cell_alpha)
        rgba_hash = helper.sha256_file(rgba_path)
        frame_records.append({
            "path": "",
            "region": [ATLAS_PADDING, ATLAS_PADDING, cell_size[0], cell_size[1]],
            "source_anchor_px": anchor,
            "foot_bbox": support_bbox,
            "source_edge_contacts": edge_contacts,
        })
        frame_metrics.append({
            "index": index,
            "raw_sha256": helper.sha256_file(raw_path),
            "rgba_sha256": rgba_hash,
            "alpha_nonzero_pixels": int(helper.np.count_nonzero(cell_alpha)),
            "alpha_opaque_pixels": int(helper.np.count_nonzero(cell_alpha == 255)),
            "alpha_coverage": round(float(helper.np.count_nonzero(cell_alpha)) / cell_alpha.size, 6),
            "source_anchor_px": anchor,
            "foot_bbox": support_bbox,
            "figure_bbox": figure_bbox,
            "source_edge_contacts": edge_contacts,
            "alpha_corner_values": corner_alpha,
        })
        if index == 0 or (index + 1) % 10 == 0 or index + 1 == source["frame_count"]:
            print(f"processed frame {index + 1}/{source['frame_count']}", flush=True)

    sample_indices = [
        int(math.floor(sample * (source["frame_count"] - 1) / 4.0 + 0.5))
        for sample in range(5)
    ]
    review_records: list[dict[str, Any]] = []
    for sample_index, frame_index in enumerate(sample_indices):
        review_path = review_dir / f"composite-{sample_index:02d}-frame-{frame_index:05d}.png"
        _composite_review(helper, rgba_dir / FRAME_NAME.format(index=frame_index), review_path)
        review_records.append({"sample": sample_index, "frame": frame_index, "file": review_path.name})

    frames_per_page = ATLAS_COLUMNS * ATLAS_ROWS
    page_count = math.ceil(source["frame_count"] / frames_per_page)
    atlas_paths: list[Path] = []
    for page_index in range(page_count):
        atlas = helper.Image.new("RGBA", (atlas_width, atlas_height), (0, 0, 0, 0))
        first = page_index * frames_per_page
        last = min(first + frames_per_page, source["frame_count"])
        for frame_index in range(first, last):
            within_page = frame_index - first
            column = within_page % ATLAS_COLUMNS
            row = within_page // ATLAS_COLUMNS
            x = column * (cell_size[0] + 2 * ATLAS_PADDING) + ATLAS_PADDING
            y = row * (cell_size[1] + 2 * ATLAS_PADDING) + ATLAS_PADDING
            rgba_path = rgba_dir / FRAME_NAME.format(index=frame_index)
            with helper.Image.open(rgba_path) as frame_image:
                rgba_frame = frame_image.convert("RGBA")
            atlas.paste(rgba_frame, (x, y))
            resource_path = (
                f"res://{ASSET_ROOT.as_posix()}/{shot_id}/"
                f"{ATLAS_NAME.format(page=page_index)}"
            )
            frame_records[frame_index]["path"] = resource_path
            frame_records[frame_index]["region"] = [x, y, cell_size[0], cell_size[1]]
        atlas_path = atlas_dir / ATLAS_NAME.format(page=page_index)
        atlas.save(atlas_path, format="PNG")
        atlas_paths.append(atlas_path)

    if helper.sha256_file(video) != source_sha256:
        raise PackageError("Source video changed during packaging")
    if helper.sha256_file(model) != actual_model_sha256:
        raise PackageError("ONNX model changed during packaging")
    if helper.sha256_file(job_record_path) != job["record_sha256"]:
        raise PackageError("Job record changed during packaging")
    if helper.sha256_file(helper_path) != helper_hash:
        raise PackageError("Processing helper changed during packaging")

    assets_path.mkdir(exist_ok=False)
    source_copy = assets_path / "source.mp4"
    shutil.copyfile(video, source_copy)
    if helper.sha256_file(source_copy) != source_sha256:
        raise PackageError("Copied source.mp4 does not match the selected generated clip")
    files_sha256: dict[str, str] = {}
    for atlas_path in atlas_paths:
        copied_atlas = assets_path / atlas_path.name
        shutil.copyfile(atlas_path, copied_atlas)
        files_sha256[
            f"res://{ASSET_ROOT.as_posix()}/{shot_id}/{atlas_path.name}"
        ] = helper.sha256_file(copied_atlas)
    files_sha256[
        f"res://{ASSET_ROOT.as_posix()}/{shot_id}/source.mp4"
    ] = helper.sha256_file(source_copy)

    manifest = {
        "schema_version": 1,
        "shot_id": shot_id,
        "source_width": source["width"],
        "source_height": source["height"],
        "cell_scale": 0.5,
        "fps": source["fps"],
        "fps_rational": source["fps_rational"],
        "frame_count": source["frame_count"],
        "duration": source["duration_seconds"],
        "width": cell_size[0],
        "height": cell_size[1],
        "frames": frame_records,
        "files_sha256": files_sha256,
        "source_video_sha256": source_sha256,
    }
    (assets_path / "atlas.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    source_metadata = {
        "schema_version": 1,
        "tool": {"name": Path(__file__).name, "version": SCRIPT_VERSION,
                 "sha256": helper.sha256_file(Path(__file__))},
        "shot_id": shot_id,
        "quality_acceptance": "pending",
        "generation_job": job,
        "source": {
            "basename": video.name,
            "sha256": source_sha256,
            "codec": source["codec"],
            "width": source["width"],
            "height": source["height"],
            "fps": source["fps"],
            "fps_rational": source["fps_rational"],
            "frame_count": source["frame_count"],
            "duration_seconds": source["duration_seconds"],
            "frame_timestamps_cfr_verified": True,
        },
        "segmentation": {
            "model_filename": model.name,
            "model_sha256": actual_model_sha256,
            "expected_model_sha256": expected_model_sha256,
            "execution_provider": "CPUExecutionProvider",
            "network_access_used": False,
        },
        "packaging": {
            "interpolation": False,
            "crop": False,
            "cell_scale": 0.5,
            "cell_width": cell_size[0],
            "cell_height": cell_size[1],
            "atlas_columns": ATLAS_COLUMNS,
            "atlas_rows": ATLAS_ROWS,
            "atlas_padding_px": ATLAS_PADDING,
            "atlas_width": atlas_width,
            "atlas_height": atlas_height,
            "atlas_pages": page_count,
            "review_samples": review_records,
        },
        "toolchain": {
            "ffmpeg": ffmpeg_version,
            "ffprobe": ffprobe_version,
            "python": sys.version.split()[0],
            "numpy": helper.np.__version__,
            "onnxruntime": helper.ort.__version__,
            "pillow": helper.Image.__version__,
            "processing_helper_sha256": helper_hash,
        },
    }
    (assets_path / "source.json").write_text(
        json.dumps(source_metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    metrics = {
        "validation": {
            "source_video_sha256": source_sha256,
            "model_sha256": actual_model_sha256,
            "source_frame_count": source["frame_count"],
            "rgba_frame_count": len(list(rgba_dir.glob("frame-*.png"))),
            "source_media": {
                "codec": source["codec"],
                "width": source["width"],
                "height": source["height"],
                "fps": source["fps"],
                "frame_count": source["frame_count"],
                "duration_seconds": source["duration_seconds"],
            },
            "timestamp_cfr_verified": True,
            "source_video_unchanged": True,
            "model_unchanged": True,
            "source_copy_byte_identical": True,
            "alpha_corners_all_zero": all(
                all(value == 0 for value in frame["alpha_corner_values"])
                for frame in frame_metrics
            ),
        },
        "frame_metrics": frame_metrics,
        "review_samples": review_records,
        "atlas_sha256": {
            path.name: helper.sha256_file(assets_path / path.name) for path in atlas_paths
        },
    }
    (output_path / "metrics.json").write_text(
        json.dumps(metrics, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return {
        "shot_id": shot_id,
        "assets": str(assets_path),
        "external_output": str(output_path),
        "frame_count": source["frame_count"],
        "fps": source["fps"],
        "duration_seconds": source["duration_seconds"],
        "atlas_pages": page_count,
        "source_video_sha256": source_sha256,
        "model_sha256": actual_model_sha256,
    }


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", required=True, type=Path, help="Completed generated H.264 MP4")
    parser.add_argument("--job-record", required=True, type=Path, help="Successful local job record JSON")
    parser.add_argument("--model", required=True, type=Path, help="Existing local ISNet-Anime ONNX model")
    parser.add_argument("--expected-model-sha256", required=True, help="Approved model SHA-256")
    parser.add_argument("--output", required=True, type=Path, help="New external work directory")
    parser.add_argument("--assets", required=True, type=Path, help="Exact per-shot repository asset directory")
    parser.add_argument("--ffmpeg", required=True, type=Path, help="ffmpeg executable")
    parser.add_argument("--ffprobe", required=True, type=Path, help="ffprobe executable")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = make_parser().parse_args(argv)
    try:
        result = package_clip(
            video=args.video,
            job_record_path=args.job_record,
            model=args.model,
            expected_model_sha256=args.expected_model_sha256,
            output=args.output,
            assets=args.assets,
            ffmpeg=args.ffmpeg,
            ffprobe=args.ffprobe,
        )
    except (PackageError, OSError, ValueError, subprocess.SubprocessError, RuntimeError) as exc:
        print(f"package_clip: ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
