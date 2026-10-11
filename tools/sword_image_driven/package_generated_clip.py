#!/usr/bin/env python3
"""Build an offline transparent-frame and atlas package from a generated clip.

The tool decodes the supplied clip, runs the already-installed local ISNet-Anime
ONNX model on CPU, appends its alpha mask to the original RGB pixels, and writes
a fixed-size atlas plus provenance. It never downloads a model or calls a
network service.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from typing import Any

import numpy as np
import onnxruntime as ort
from PIL import Image
import scipy
from scipy import ndimage


SCRIPT_VERSION = "1.0.0"
SOURCE_WIDTH = 768
SOURCE_HEIGHT = 1152
SOURCE_FPS = 25
FRAME_COUNT = 61
DURATION_SECONDS = 2.44
FRAME_WIDTH = 384
FRAME_HEIGHT = 576
ATLAS_COLUMNS = 4
ATLAS_ROWS = 3
ATLAS_PAD = 4
ATLAS_CELL_STRIDE_X = FRAME_WIDTH + 2 * ATLAS_PAD
ATLAS_CELL_STRIDE_Y = FRAME_HEIGHT + 2 * ATLAS_PAD
ATLAS_WIDTH = ATLAS_COLUMNS * ATLAS_CELL_STRIDE_X
ATLAS_HEIGHT = ATLAS_ROWS * ATLAS_CELL_STRIDE_Y
REVIEW_INDICES = (0, 15, 28, 40, 60)
REVIEW_BACKGROUND = (0xE5, 0xE0, 0xD5)
MEAN = (0.485, 0.456, 0.406)
STD = (1.0, 1.0, 1.0)
MODEL_INPUT_SIZE = (1024, 1024)
ALPHA_LOW = 8
ALPHA_HIGH = 247
FOOT_THRESHOLD = 128
FOOT_BOTTOM_BAND_FRACTION = 0.30
FOOT_SUPPORT_ROWS_CELL = 8
SOURCE_COORDINATE_SCALE = 2


class PackageError(RuntimeError):
    """An input, processing, or output validation failure."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_checked(command: list[str], label: str) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout)[-4000:]
        raise PackageError(f"{label} failed (exit {result.returncode}):\n{detail}")
    return result


def tool_version(tool: Path) -> str:
    result = run_checked([str(tool), "-version"], f"{tool.name} version check")
    return (result.stdout.splitlines() or ["unknown"])[0].strip()


def probe_video(ffprobe: Path, path: Path) -> dict[str, Any]:
    result = run_checked(
        [
            str(ffprobe),
            "-v", "error",
            "-count_frames",
            "-select_streams", "v:0",
            "-show_entries",
            "stream=codec_name,width,height,avg_frame_rate,r_frame_rate,nb_frames,nb_read_frames:"
            "format=duration,size",
            "-of", "json",
            str(path),
        ],
        f"ffprobe {path.name}",
    )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise PackageError(f"ffprobe returned invalid JSON for {path.name}") from exc


def fraction_value(value: str) -> float:
    numerator, denominator = value.split("/", 1)
    return float(numerator) / float(denominator)


def validate_source_video(info: dict[str, Any]) -> None:
    streams = info.get("streams", [])
    if len(streams) != 1:
        raise PackageError(f"Expected one selected video stream, got {len(streams)}")
    stream = streams[0]
    frame_count = int(stream.get("nb_read_frames", "-1"))
    rate = fraction_value(stream.get("avg_frame_rate", "0/1"))
    duration = float(info.get("format", {}).get("duration", "nan"))
    if (
        stream.get("codec_name") != "h264"
        or int(stream.get("width", 0)) != SOURCE_WIDTH
        or int(stream.get("height", 0)) != SOURCE_HEIGHT
        or frame_count != FRAME_COUNT
        or not math.isclose(rate, SOURCE_FPS, rel_tol=0, abs_tol=0.001)
        or not math.isclose(duration, DURATION_SECONDS, rel_tol=0, abs_tol=0.001)
    ):
        raise PackageError(
            "Source media does not match the approved clip contract: "
            f"stream={stream}, duration={duration}"
        )


def create_session(model_path: Path) -> ort.InferenceSession:
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    session = ort.InferenceSession(
        str(model_path),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )
    if session.get_providers() != ["CPUExecutionProvider"]:
        raise PackageError(f"Expected CPUExecutionProvider only: {session.get_providers()}")
    if len(session.get_inputs()) != 1 or not session.get_outputs():
        raise PackageError("Unexpected ONNX model input/output contract")
    return session


def predict_mask(session: ort.InferenceSession, image: Image.Image) -> Image.Image:
    # Match rembg's installed dis_anime normalization while avoiding its
    # session/model downloader: RGB, Lanczos 1024 square, divide by max pixel,
    # subtract RGB means, NCHW float32.
    resized = image.convert("RGB").resize(MODEL_INPUT_SIZE, Image.Resampling.LANCZOS)
    image_array = np.asarray(resized)
    scale = max(float(np.max(image_array)), 1e-6)
    image_array = image_array / scale
    normalized = np.zeros(image_array.shape, dtype=np.float64)
    for channel in range(3):
        normalized[:, :, channel] = (image_array[:, :, channel] - MEAN[channel]) / STD[channel]
    tensor = np.expand_dims(normalized.transpose((2, 0, 1)), 0).astype(np.float32)
    output = session.run(None, {session.get_inputs()[0].name: tensor})[0]
    if output.ndim != 4 or output.shape[0] != 1 or output.shape[1] < 1:
        raise PackageError(f"Unexpected segmentation output shape: {output.shape}")
    prediction = output[:, 0, :, :]
    maximum = float(np.max(prediction))
    minimum = float(np.min(prediction))
    if not math.isfinite(maximum) or not math.isfinite(minimum):
        raise PackageError("Segmentation output contains non-finite values")
    if maximum <= minimum:
        normalized_mask = np.zeros_like(prediction, dtype=np.float32)
    else:
        normalized_mask = (prediction - minimum) / (maximum - minimum)
    normalized_mask = np.squeeze(normalized_mask)
    if normalized_mask.shape != MODEL_INPUT_SIZE:
        raise PackageError(f"Unexpected mask dimensions: {normalized_mask.shape}")
    mask_image = Image.fromarray((normalized_mask * 255).astype("uint8"))
    return mask_image.resize(image.size, Image.Resampling.LANCZOS)


def trim_alpha(mask: Image.Image) -> np.ndarray:
    values = np.asarray(mask, dtype=np.uint8).astype(np.float32)
    trimmed = (values - ALPHA_LOW) * (255.0 / (ALPHA_HIGH - ALPHA_LOW))
    return np.clip(trimmed, 0, 255).astype(np.uint8)


def foot_contact(alpha: np.ndarray) -> tuple[list[int], list[int], list[int]]:
    # Work from the saved 384x576 alpha plane. Coordinates are doubled back to
    # native 768x1152 source pixels for the manifest/runtime contract.
    binary = alpha >= FOOT_THRESHOLD
    band_start = int(math.floor(alpha.shape[0] * (1.0 - FOOT_BOTTOM_BAND_FRACTION)))
    labels, count = ndimage.label(binary[band_start:, :])
    if count < 1:
        raise PackageError("No thresholded figure component found in the bottom 30%")
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    largest = int(np.argmax(sizes))
    relative_ys, xs = np.nonzero(labels == largest)
    if xs.size == 0:
        raise PackageError("Could not locate the largest bottom-band figure component")

    component_ys = relative_ys + band_start
    min_x = int(xs.min())
    max_x = int(xs.max())
    min_y = int(component_ys.min())
    max_y = int(component_ys.max())
    full_bbox = [
        min_x * SOURCE_COORDINATE_SCALE,
        min_y * SOURCE_COORDINATE_SCALE,
        (max_x - min_x + 1) * SOURCE_COORDINATE_SCALE,
        (max_y - min_y + 1) * SOURCE_COORDINATE_SCALE,
    ]

    support_start = max(band_start, max_y - FOOT_SUPPORT_ROWS_CELL + 1)
    support = component_ys >= support_start
    support_xs = xs[support]
    support_ys = component_ys[support]
    if support_xs.size == 0:
        raise PackageError("Could not locate support pixels in the component's final 16 source rows")
    support_min_x = int(support_xs.min())
    support_max_x = int(support_xs.max())
    support_min_y = int(support_ys.min())
    anchor = [
        int(round((support_min_x + support_max_x) * SOURCE_COORDINATE_SCALE / 2.0)),
        max_y * SOURCE_COORDINATE_SCALE,
    ]
    support_bbox = [
        support_min_x * SOURCE_COORDINATE_SCALE,
        support_min_y * SOURCE_COORDINATE_SCALE,
        (support_max_x - support_min_x + 1) * SOURCE_COORDINATE_SCALE,
        (max_y - support_min_y + 1) * SOURCE_COORDINATE_SCALE,
    ]
    return anchor, support_bbox, full_bbox


def edge_contacts(alpha: np.ndarray) -> dict[str, bool]:
    visible = alpha > 0
    return {
        "left": bool(np.any(visible[:, 0])),
        "right": bool(np.any(visible[:, -1])),
        "top": bool(np.any(visible[0, :])),
        "bottom": bool(np.any(visible[-1, :])),
    }


def save_json_exclusive(path: Path, value: dict[str, Any]) -> None:
    encoded = (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    with path.open("xb") as stream:
        stream.write(encoded)


def checked_new_directory(path: Path, label: str) -> None:
    if path.exists() or path.is_symlink():
        raise PackageError(f"Refusing existing {label} destination: {path}")
    if not path.parent.is_dir():
        raise PackageError(f"Parent directory for {label} does not exist: {path.parent}")
    path.mkdir(exist_ok=False)


def verify_zero_corners(image: Image.Image, label: str) -> list[int]:
    alpha = np.asarray(image.convert("RGBA"))[:, :, 3]
    corners = [
        int(alpha[0, 0]),
        int(alpha[0, -1]),
        int(alpha[-1, 0]),
        int(alpha[-1, -1]),
    ]
    if any(value != 0 for value in corners):
        raise PackageError(f"Nonzero alpha at {label} corners: {corners}")
    return corners


def build(args: argparse.Namespace) -> dict[str, Any]:
    video = args.video.expanduser().absolute()
    model = args.model.expanduser().absolute()
    output = args.output.expanduser().absolute()
    assets = args.assets.expanduser().absolute()
    ffmpeg = args.ffmpeg.expanduser().absolute()
    ffprobe = args.ffprobe.expanduser().absolute()

    for path, label in (
        (video, "source video"),
        (model, "ONNX model"),
        (ffmpeg, "ffmpeg"),
        (ffprobe, "ffprobe"),
    ):
        if not path.is_file():
            raise PackageError(f"Missing {label}: {path}")
    if output == assets or output in assets.parents or assets in output.parents:
        raise PackageError("External build output and repository asset paths must be separate")
    for path, label in ((output, "external build"), (assets, "repository asset")):
        if path.exists() or path.is_symlink():
            raise PackageError(f"Refusing existing {label} destination: {path}")

    source_hash_before = sha256_file(video)
    model_hash_before = sha256_file(model)
    video_info = probe_video(ffprobe, video)
    validate_source_video(video_info)
    ffmpeg_version = tool_version(ffmpeg)
    ffprobe_version = tool_version(ffprobe)

    checked_new_directory(output, "external build")
    raw_dir = output / "raw"
    rgba_dir = output / "rgba"
    atlas_dir = output / "atlas"
    review_dir = output / "review"
    for path in (raw_dir, rgba_dir, atlas_dir, review_dir):
        path.mkdir(exist_ok=False)

    extract_command = [
        str(ffmpeg),
        "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
        "-i", str(video),
        "-map", "0:v:0",
        "-fps_mode", "passthrough",
        "-start_number", "0",
        "-frames:v", str(FRAME_COUNT),
        str(raw_dir / "frame-%05d.png"),
    ]
    run_checked(extract_command, "source frame extraction")
    raw_frames = sorted(raw_dir.glob("frame-*.png"))
    if len(raw_frames) != FRAME_COUNT:
        raise PackageError(f"Expected {FRAME_COUNT} decoded frames, found {len(raw_frames)}")

    session = create_session(model)
    frame_records: list[dict[str, Any]] = []
    metrics_frames: list[dict[str, Any]] = []
    corner_values: list[list[int]] = []
    for index, raw_path in enumerate(raw_frames):
        if raw_path.name != f"frame-{index:05d}.png":
            raise PackageError(f"Unexpected extracted frame name: {raw_path.name}")
        with Image.open(raw_path) as raw:
            source_rgb = raw.convert("RGB")
        if source_rgb.size != (SOURCE_WIDTH, SOURCE_HEIGHT):
            raise PackageError(f"{raw_path.name} dimensions are {source_rgb.size}")
        mask = predict_mask(session, source_rgb)
        alpha_source = trim_alpha(mask)
        contacts = edge_contacts(alpha_source)

        rgb_cell = source_rgb.resize((FRAME_WIDTH, FRAME_HEIGHT), Image.Resampling.LANCZOS)
        alpha_cell = Image.fromarray(alpha_source).resize(
            (FRAME_WIDTH, FRAME_HEIGHT), Image.Resampling.LANCZOS
        )
        rgba = rgb_cell.convert("RGBA")
        rgba.putalpha(alpha_cell)
        corners = verify_zero_corners(rgba, raw_path.name)
        corner_values.append(corners)
        rgba_path = rgba_dir / raw_path.name
        rgba.save(rgba_path, format="PNG")
        if rgba.mode != "RGBA" or rgba.size != (FRAME_WIDTH, FRAME_HEIGHT):
            raise PackageError(f"Processed frame contract failed for {rgba_path.name}")

        alpha_cell_array = np.asarray(alpha_cell, dtype=np.uint8)
        anchor, bbox, full_component_bbox = foot_contact(alpha_cell_array)
        metrics_frames.append(
            {
                "index": index,
                "alpha_nonzero_pixels": int(np.count_nonzero(alpha_cell_array)),
                "alpha_opaque_pixels": int(np.count_nonzero(alpha_cell_array == 255)),
                "alpha_coverage": round(float(np.count_nonzero(alpha_cell_array)) / alpha_cell_array.size, 6),
                "source_anchor_px": anchor,
                "foot_bbox": bbox,
                "bottom_band_component_bbox_source_px": full_component_bbox,
                "source_edge_contacts": contacts,
                "rgba_sha256": sha256_file(rgba_path),
            }
        )
        frame_records.append(
            {
                "path": "",
                "region": [
                    ATLAS_PAD,
                    ATLAS_PAD,
                    FRAME_WIDTH,
                    FRAME_HEIGHT,
                ],
                "source_anchor_px": anchor,
                "foot_bbox": bbox,
                "source_edge_contacts": contacts,
            }
        )
        if index in REVIEW_INDICES:
            background = Image.new("RGBA", (FRAME_WIDTH, FRAME_HEIGHT), (*REVIEW_BACKGROUND, 255))
            background.alpha_composite(rgba)
            background.convert("RGB").save(
                review_dir / f"composite-frame-{index:03d}.png",
                format="PNG",
            )
        if index == 0 or (index + 1) % 5 == 0 or index + 1 == FRAME_COUNT:
            print(f"processed frame {index + 1}/{FRAME_COUNT}", flush=True)

    if sha256_file(video) != source_hash_before:
        raise PackageError("The selected source video changed during processing")
    if sha256_file(model) != model_hash_before:
        raise PackageError("The local ONNX model changed during processing")

    page_count = math.ceil(FRAME_COUNT / (ATLAS_COLUMNS * ATLAS_ROWS))
    atlas_paths: list[Path] = []
    for page_index in range(page_count):
        atlas = Image.new("RGBA", (ATLAS_WIDTH, ATLAS_HEIGHT), (0, 0, 0, 0))
        first = page_index * ATLAS_COLUMNS * ATLAS_ROWS
        last = min(first + ATLAS_COLUMNS * ATLAS_ROWS, FRAME_COUNT)
        for frame_index in range(first, last):
            within_page = frame_index - first
            column = within_page % ATLAS_COLUMNS
            row = within_page // ATLAS_COLUMNS
            x = column * ATLAS_CELL_STRIDE_X + ATLAS_PAD
            y = row * ATLAS_CELL_STRIDE_Y + ATLAS_PAD
            frame_path = rgba_dir / f"frame-{frame_index:05d}.png"
            with Image.open(frame_path) as frame:
                rgba_frame = frame.convert("RGBA")
            if rgba_frame.size != (FRAME_WIDTH, FRAME_HEIGHT):
                raise PackageError(f"Incorrect RGBA frame size: {frame_path.name}")
            atlas.paste(rgba_frame, (x, y))
            frame_records[frame_index]["path"] = (
                f"res://assets/art/sword_image_driven_v1/atlas-{page_index:03d}.png"
            )
            frame_records[frame_index]["region"] = [x, y, FRAME_WIDTH, FRAME_HEIGHT]
        atlas_path = atlas_dir / f"atlas-{page_index:03d}.png"
        atlas.save(atlas_path, format="PNG")
        atlas_paths.append(atlas_path)

    source_copy_hash = source_hash_before
    checked_new_directory(assets, "repository asset")
    source_copy = assets / "source.mp4"
    shutil.copyfile(video, source_copy)
    if sha256_file(source_copy) != source_hash_before or source_copy.stat().st_size != video.stat().st_size:
        raise PackageError("Packaged source.mp4 is not byte-identical to the selected clip")

    files_sha256: dict[str, str] = {}
    for atlas_path in atlas_paths:
        destination = assets / atlas_path.name
        shutil.copyfile(atlas_path, destination)
        files_sha256[f"res://assets/art/sword_image_driven_v1/{atlas_path.name}"] = sha256_file(destination)
    files_sha256["res://assets/art/sword_image_driven_v1/source.mp4"] = sha256_file(source_copy)
    if files_sha256["res://assets/art/sword_image_driven_v1/source.mp4"] != source_copy_hash:
        raise PackageError("source.mp4 hash differs from the original video hash")

    manifest = {
        "schema_version": 1,
        "fps": SOURCE_FPS,
        "frame_count": FRAME_COUNT,
        "duration": DURATION_SECONDS,
        "width": FRAME_WIDTH,
        "height": FRAME_HEIGHT,
        "frames": frame_records,
        "files_sha256": files_sha256,
        "source_video_sha256": source_hash_before,
    }
    save_json_exclusive(assets / "atlas.json", manifest)

    source_metadata = {
        "schema_version": 1,
        "packager": {
            "name": "package_generated_clip.py",
            "version": SCRIPT_VERSION,
            "offline": True,
            "network_access_used": False,
        },
        "source": {
            "basename": video.name,
            "sha256": source_hash_before,
            "codec": video_info["streams"][0]["codec_name"],
            "width": SOURCE_WIDTH,
            "height": SOURCE_HEIGHT,
            "fps": SOURCE_FPS,
            "frame_count": FRAME_COUNT,
            "duration_seconds": DURATION_SECONDS,
            "reported_lineage": {
                "provider": "ModelScope",
                "model_family": "Wan",
                "verification": "User-reported lineage; generation job, exact model/version, prompt, and seed were not independently verified.",
            },
            "user_feedback": "User said the generated effect looked good.",
        },
        "segmentation": {
            "model_filename": model.name,
            "model_sha256": model_hash_before,
            "runtime": "ONNX Runtime",
            "execution_provider": "CPUExecutionProvider",
            "session_threads": {
                "intra_op": 2,
                "inter_op": 1,
                "execution_mode": "ORT_SEQUENTIAL",
            },
            "preprocessing": {
                "color": "RGB",
                "resize": list(MODEL_INPUT_SIZE),
                "resize_filter": "Lanczos",
                "normalization": "float pixel array divided by max pixel value; subtract RGB means",
                "mean": list(MEAN),
                "std": list(STD),
                "tensor": "NCHW float32 with batch dimension",
                "prediction": "first output, channel zero; min-max normalized; Lanczos resized to source frame size",
            },
            "alpha_trim": {
                "below": ALPHA_LOW,
                "above": ALPHA_HIGH,
                "formula": "(mask - 8) * 255 / (247 - 8), clipped to [0, 255], uint8 truncation",
            },
        },
        "packaging": {
            "rgb_art": "Original decoded RGB is retained; only alpha is added, then RGB and alpha are resized together to the fixed frame cell.",
            "temporal_policy": {
                "fps": SOURCE_FPS,
                "frame_count": FRAME_COUNT,
                "duration_seconds": DURATION_SECONDS,
                "interpolation": False,
                "crossfade": False,
                "loop_synthesis": False,
                "per_frame_crop_or_scale": False,
            },
            "atlas": {
                "columns": ATLAS_COLUMNS,
                "rows": ATLAS_ROWS,
                "padding_px": ATLAS_PAD,
                "page_width": ATLAS_WIDTH,
                "page_height": ATLAS_HEIGHT,
                "page_count": page_count,
            },
            "foot_coordinates": "Threshold the 384x576 alpha at 128, select the largest connected component in its bottom 30%, and derive support from its final 8 cell rows (16 native source pixels). source_anchor_px is the support-pixel midpoint at the component's lowest row; source_anchor_px and foot_bbox coordinates are doubled to native 768x1152 source pixels. foot_bbox is the support bounds.",
        },
        "processing_cost": {
            "local_packaging_usd": 0,
            "upstream_generation_cost": "Not verified.",
        },
        "software_versions": {
            "python": platform.python_version(),
            "numpy": np.__version__,
            "pillow": Image.__version__,
            "scipy": scipy.__version__,
            "onnxruntime": ort.__version__,
            "ffmpeg": tool_version(ffmpeg),
            "ffprobe": tool_version(ffprobe),
        },
    }
    save_json_exclusive(assets / "source.json", source_metadata)

    manifest_path = assets / "atlas.json"
    loaded_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if len(loaded_manifest.get("frames", [])) != FRAME_COUNT:
        raise PackageError("Manifest frame count validation failed")
    for index, record in enumerate(loaded_manifest["frames"]):
        page_name = Path(record["path"]).name
        page_path = assets / page_name
        if not page_path.is_file():
            raise PackageError(f"Manifest points to missing atlas page: {page_name}")
        x, y, width, height = record["region"]
        if (width, height) != (FRAME_WIDTH, FRAME_HEIGHT):
            raise PackageError(f"Manifest region has incorrect cell dimensions at frame {index}")
        if x < 0 or y < 0 or x + width > ATLAS_WIDTH or y + height > ATLAS_HEIGHT:
            raise PackageError(f"Manifest region lies outside atlas at frame {index}")
        with Image.open(page_path) as page:
            if page.mode != "RGBA" or page.size != (ATLAS_WIDTH, ATLAS_HEIGHT):
                raise PackageError(f"Atlas page contract failed: {page_name}")
    for resource_path, expected_hash in files_sha256.items():
        resource = assets / Path(resource_path).name
        if not resource.is_file() or sha256_file(resource) != expected_hash:
            raise PackageError(f"Packaged resource SHA-256 validation failed: {resource.name}")

    if len(list(raw_dir.glob("frame-*.png"))) != FRAME_COUNT:
        raise PackageError("External raw-frame count validation failed")
    if len(list(rgba_dir.glob("frame-*.png"))) != FRAME_COUNT:
        raise PackageError("External RGBA-frame count validation failed")
    for path in sorted(rgba_dir.glob("frame-*.png")):
        with Image.open(path) as frame:
            if frame.mode != "RGBA" or frame.size != (FRAME_WIDTH, FRAME_HEIGHT):
                raise PackageError(f"External frame is not 384x576 RGBA: {path.name}")
            verify_zero_corners(frame, path.name)

    if sha256_file(video) != source_hash_before:
        raise PackageError("Final source video SHA-256 differs from its initial hash")
    if sha256_file(source_copy) != source_hash_before:
        raise PackageError("Packaged source.mp4 does not match the source video")

    metrics = {
        "validation": {
            "source_video_sha256_before": source_hash_before,
            "source_video_sha256_after": sha256_file(video),
            "packaged_source_sha256": sha256_file(source_copy),
            "source_unchanged": True,
            "source_mp4_byte_identical": True,
            "raw_frame_count": len(raw_frames),
            "rgba_frame_count": len(list(rgba_dir.glob("frame-*.png"))),
            "all_rgba_dimensions": [FRAME_WIDTH, FRAME_HEIGHT],
            "all_rgba_modes": ["RGBA"],
            "alpha_corners_all_zero": True,
            "atlas_pages": len(atlas_paths),
            "atlas_dimensions": [ATLAS_WIDTH, ATLAS_HEIGHT],
            "manifest_regions_valid": True,
            "manifest_resources_exist_and_hash": True,
            "network_calls": 0,
            "new_dependencies_installed": 0,
        },
        "frame_metrics": metrics_frames,
        "review_files": [
            f"review/composite-frame-{index:03d}.png" for index in REVIEW_INDICES
        ],
        "atlas_sha256": {
            atlas_path.name: sha256_file(assets / atlas_path.name)
            for atlas_path in atlas_paths
        },
    }
    save_json_exclusive(output / "metrics.json", metrics)
    return {
        "assets": str(assets),
        "external_output": str(output),
        "frame_count": FRAME_COUNT,
        "atlas_pages": page_count,
        "source_video_sha256": source_hash_before,
        "model_sha256": model_hash_before,
        "atlas_sha256": metrics["atlas_sha256"],
        "review_files": metrics["review_files"],
    }



def reanchor_saved_package(assets: Path, output: Path) -> dict[str, Any]:
    assets = assets.expanduser().absolute()
    output = output.expanduser().absolute()
    manifest_path = assets / "atlas.json"
    source_path = assets / "source.json"
    rgba_dir = output / "rgba"
    if not manifest_path.is_file() or not source_path.is_file() or not rgba_dir.is_dir():
        raise PackageError("Reanchor mode requires the existing package manifest, source metadata, and RGBA frames")
    initial_manifest_bytes = manifest_path.read_bytes()
    initial_source_bytes = source_path.read_bytes()
    initial_manifest = json.loads(initial_manifest_bytes)
    source_metadata = json.loads(initial_source_bytes)
    if len(initial_manifest.get("frames", [])) != FRAME_COUNT:
        raise PackageError("Existing manifest does not contain the expected 61 frames")

    initial_backup_manifest = output / "atlas-initial.json"
    initial_backup_source = output / "source-initial.json"
    for path, data in (
        (initial_backup_manifest, initial_manifest_bytes),
        (initial_backup_source, initial_source_bytes),
    ):
        with path.open("xb") as stream:
            stream.write(data)
    if initial_backup_manifest.read_bytes() != initial_manifest_bytes:
        raise PackageError("Initial manifest backup is not byte-identical")
    if initial_backup_source.read_bytes() != initial_source_bytes:
        raise PackageError("Initial source metadata backup is not byte-identical")

    immutable_hashes: dict[str, str] = {}
    for resource_path, expected_hash in initial_manifest["files_sha256"].items():
        resource = assets / Path(resource_path).name
        if not resource.is_file() or sha256_file(resource) != expected_hash:
            raise PackageError(f"Immutable packaged resource failed pre-calibration hash: {resource.name}")
        immutable_hashes[resource.name] = expected_hash
    rgba_paths = [rgba_dir / f"frame-{index:05d}.png" for index in range(FRAME_COUNT)]
    rgba_hashes: dict[str, str] = {}
    diagnostics: list[dict[str, Any]] = []
    calibrated_manifest = json.loads(initial_manifest_bytes)
    for index, rgba_path in enumerate(rgba_paths):
        if not rgba_path.is_file():
            raise PackageError(f"Missing saved RGBA frame for calibration: {rgba_path.name}")
        rgba_hashes[rgba_path.name] = sha256_file(rgba_path)
        with Image.open(rgba_path) as frame:
            frame = frame.convert("RGBA")
            if frame.size != (FRAME_WIDTH, FRAME_HEIGHT):
                raise PackageError(f"Calibration frame has incorrect size: {rgba_path.name}")
            alpha = np.asarray(frame, dtype=np.uint8)[:, :, 3]
        anchor, support_bbox, full_bbox = foot_contact(alpha)
        calibrated_manifest["frames"][index]["source_anchor_px"] = anchor
        calibrated_manifest["frames"][index]["foot_bbox"] = support_bbox
        diagnostics.append(
            {
                "index": index,
                "source_anchor_px": anchor,
                "foot_bbox": support_bbox,
                "bottom_band_component_bbox_source_px": full_bbox,
                "rgba_sha256": rgba_hashes[rgba_path.name],
            }
        )

    source_metadata["anchor_calibration"] = {
        "method": "Derived from the saved 384x576 RGBA alpha frames; no segmentation was rerun.",
        "threshold": FOOT_THRESHOLD,
        "bottom_band_fraction": FOOT_BOTTOM_BAND_FRACTION,
        "support_rows_cell": FOOT_SUPPORT_ROWS_CELL,
        "support_rows_source_pixels": FOOT_SUPPORT_ROWS_CELL * SOURCE_COORDINATE_SCALE,
        "source_coordinate_scale": SOURCE_COORDINATE_SCALE,
    }
    source_metadata["packaging"]["foot_coordinates"] = (
        "Threshold the 384x576 alpha at 128, select the largest connected component in its bottom 30%, "
        "and derive support from its final 8 cell rows (16 native source pixels). source_anchor_px is "
        "the support-pixel midpoint at the component's lowest row; source_anchor_px and foot_bbox "
        "coordinates are doubled to native 768x1152 source pixels. foot_bbox is the support bounds."
    )

    calibrated_manifest_path = output / "atlas-calibrated.json"
    calibrated_source_path = output / "source-calibrated.json"
    calibrated_metrics_path = output / "metrics-calibrated.json"
    save_json_exclusive(calibrated_manifest_path, calibrated_manifest)
    save_json_exclusive(calibrated_source_path, source_metadata)
    calibrated_metrics = {
        "calibration": {
            "source": "saved processed-v1/rgba/frame-*.png alpha planes",
            "inference_rerun": False,
            "frames": FRAME_COUNT,
            "support_rows_cell": FOOT_SUPPORT_ROWS_CELL,
            "support_rows_source_pixels": FOOT_SUPPORT_ROWS_CELL * SOURCE_COORDINATE_SCALE,
            "source_coordinate_scale": SOURCE_COORDINATE_SCALE,
            "initial_manifest_sha256": hashlib.sha256(initial_manifest_bytes).hexdigest(),
            "initial_source_metadata_sha256": hashlib.sha256(initial_source_bytes).hexdigest(),
            "immutable_resource_hashes_before": immutable_hashes,
            "rgba_hashes_before": rgba_hashes,
        },
        "frame_anchors": diagnostics,
    }
    save_json_exclusive(calibrated_metrics_path, calibrated_metrics)

    # The parent explicitly authorized replacing only these two newly created
    # asset metadata files. Atlas PNGs, frame PNGs, and source.mp4 stay intact.
    manifest_path.write_text(
        json.dumps(calibrated_manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    source_path.write_text(
        json.dumps(source_metadata, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    if sha256_file(manifest_path) != sha256_file(calibrated_manifest_path):
        raise PackageError("Installed calibrated manifest differs from external calibrated metadata")
    if sha256_file(source_path) != sha256_file(calibrated_source_path):
        raise PackageError("Installed calibrated source metadata differs from external metadata")
    for name, expected_hash in immutable_hashes.items():
        if sha256_file(assets / name) != expected_hash:
            raise PackageError(f"Immutable packaged resource changed during calibration: {name}")
    for path in rgba_paths:
        if sha256_file(path) != rgba_hashes[path.name]:
            raise PackageError(f"Saved RGBA frame changed during calibration: {path.name}")

    return {
        "calibrated_manifest": str(manifest_path),
        "calibrated_source": str(source_path),
        "external_initial_manifest": str(initial_backup_manifest),
        "external_initial_source": str(initial_backup_source),
        "external_calibrated_metadata": [
            str(calibrated_manifest_path),
            str(calibrated_source_path),
            str(calibrated_metrics_path),
        ],
        "frames": FRAME_COUNT,
        "inference_rerun": False,
        "immutable_resources_unchanged": True,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", required=True, type=Path, help="Approved generated MP4")
    parser.add_argument("--model", required=True, type=Path, help="Existing local ISNet-Anime ONNX file")
    parser.add_argument("--output", required=True, type=Path, help="New external processed-v1 directory")
    parser.add_argument("--assets", required=True, type=Path, help="New repository asset directory")
    parser.add_argument("--ffmpeg", required=True, type=Path, help="ffmpeg executable")
    parser.add_argument("--ffprobe", required=True, type=Path, help="ffprobe executable")
    parser.add_argument("--reanchor-existing", action="store_true", help="Recalibrate existing saved RGBA frames without inference")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        result = reanchor_saved_package(args.assets, args.output) if args.reanchor_existing else build(args)
    except (PackageError, OSError, ValueError, RuntimeError) as exc:
        print(f"package_generated_clip: ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
