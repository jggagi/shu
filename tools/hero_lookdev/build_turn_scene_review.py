#!/usr/bin/env python3
"""Prepare an isolated Godot scene for comparing two 60- or 120-frame turn clips.

Example:
  python3 tools/hero_lookdev/build_turn_scene_review.py \
    --old-frames /abs/frames-v5 --new-frames /abs/frames-refined \
    --out-root /abs/existing/output --anchor-x 512 --anchor-y 900

Use --dry-run to validate inputs and print hashes/reproduction arguments without
creating a stage or resizing frames. A normal run creates a new stage only; it
does not start Godot import, export, a renderer, or a browser.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import uuid
import zlib
from pathlib import Path
from typing import Any


SOURCE_SIZE = (1000, 1000)
CELL_SIZE = (512, 512)
FPS = 30
FRAME_COUNT = 60
FRAME_COUNT_CHOICES = (60, 120)
ATLAS_COLUMNS = 5
ATLAS_ROWS = 5
FRAMES_PER_ATLAS = ATLAS_COLUMNS * ATLAS_ROWS

PROJECT = '''config_version=5
[application]
config/name="后山 · 持剑动作与色调"
config/version="0.1.0-jiang-turn-review"
run/main_scene="res://scenes/demos/jiang_turn_review.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
[display]
window/size/viewport_width=1440
window/size/viewport_height=900
window/size/window_width_override=1152
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.93,0.90,0.83,1)
'''

SCRIPT_FILES = (
    "scripts/demo_state.gd",
    "scripts/environment_presenter.gd",
    "scripts/back_mountain_training.gd",
    "scripts/back_mountain_environment.gd",
    "scripts/back_mountain_lighting.gd",
    "scripts/back_mountain_ambient_life.gd",
    "scripts/ambient_life_presenter.gd",
    "scripts/ambient_cat_motion.gd",
    "scripts/hero_lookdev/turn_scene_review.gd",
)
DATA_FILES = (
    "assets/data/rules.json",
    "assets/data/tea-full-source.json",
    "assets/data/back_mountain_training.json",
    "assets/data/back_mountain_environment.json",
    "assets/data/back_mountain_lighting.json",
    "assets/data/back_mountain_ambient_life.json",
)
ART_FILES = (
    "assets/art/back_mountain_training/far.png",
    "assets/art/back_mountain_training/mid.png",
    "assets/art/back_mountain_training/near.png",
)
FONT_FILES = (
    "assets/fonts/ShuTurnReviewSerif.ttf",
    "assets/fonts/source-turn-review.json",
    "assets/fonts/ShuBackMountainSerif.ttf",
    "assets/fonts/ShuDemoSerif.ttf",
    "assets/fonts/OFL-Serif.txt",
)
SHADER_FILES = (
    "assets/shaders/back_mountain_cloud.gdshader",
    "assets/shaders/back_mountain_cloud_shadow.gdshader",
    "assets/shaders/back_mountain_contact_shadow.gdshader",
    "assets/shaders/back_mountain_environment_art.gdshader",
    "assets/shaders/back_mountain_hair_wind.gdshader",
    "assets/shaders/back_mountain_mist.gdshader",
    "assets/shaders/back_mountain_near_wind.gdshader",
    "assets/shaders/back_mountain_rain.gdshader",
    "assets/shaders/back_mountain_sun.gdshader",
    "assets/shaders/waterfall_flow.gdshader",
)


class BuildError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def png_info(path: Path) -> dict[str, Any]:
    with path.open("rb") as stream:
        header = stream.read(29)
    if len(header) < 29 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise BuildError(f"Not a readable PNG with an IHDR header: {path}")
    width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(">IIBBBBB", header[16:29])
    if (width, height) != SOURCE_SIZE:
        raise BuildError(f"Expected a 1000x1000 source frame, got {width}x{height}: {path}")
    if bit_depth != 8 or color_type != 6 or compression != 0 or filter_method != 0 or interlace != 0:
        raise BuildError(f"Expected non-interlaced 8-bit RGBA PNG: {path}")
    return {"width": width, "height": height, "bit_depth": bit_depth, "color_type": color_type}


def validate_frame_dir(path_value: str, label: str, frame_count: int = FRAME_COUNT) -> tuple[Path, list[dict[str, str]]]:
    raw_path = Path(path_value).expanduser()
    if not raw_path.is_absolute():
        raise BuildError(f"--{label}-frames must be an absolute path: {path_value}")
    try:
        directory = raw_path.resolve(strict=True)
    except FileNotFoundError as exc:
        raise BuildError(f"--{label}-frames directory does not exist: {raw_path}") from exc
    if not directory.is_dir():
        raise BuildError(f"--{label}-frames must be a directory: {directory}")
    expected_names = {f"frame-{index:04d}.png" for index in range(1, frame_count + 1)}
    frame_candidates = {
        item.name
        for item in directory.iterdir()
        if item.name.startswith("frame-") and item.suffix.lower() == ".png"
    }
    if frame_candidates != expected_names:
        raise BuildError(
            f"--{label}-frames must contain exactly {frame_count} sequential frame PNGs; "
            f"found {len(frame_candidates)} candidate(s)"
        )
    records: list[dict[str, str]] = []
    missing: list[str] = []
    for index in range(1, frame_count + 1):
        filename = f"frame-{index:04d}.png"
        frame_path = directory / filename
        if not frame_path.is_file() or frame_path.is_symlink():
            missing.append(filename)
            continue
        png_info(frame_path)
        records.append({"name": filename, "sha256": sha256_file(frame_path)})
    if missing:
        preview = ", ".join(missing[:6])
        remaining = len(missing) - min(6, len(missing))
        suffix = f" and {remaining} more" if remaining else ""
        raise BuildError(
            f"--{label}-frames needs all {frame_count} frames named frame-0001.png "
            f"through frame-{frame_count:04d}.png; missing: {preview}{suffix}"
        )
    return directory, records


def validate_out_root(path_value: str) -> Path:
    raw_path = Path(path_value).expanduser()
    if not raw_path.is_absolute():
        raise BuildError(f"--out-root must be an absolute path: {path_value}")
    try:
        root = raw_path.resolve(strict=True)
    except FileNotFoundError as exc:
        raise BuildError(f"--out-root must already exist: {raw_path}") from exc
    if not root.is_dir():
        raise BuildError(f"--out-root must be an existing directory: {root}")
    return root


def selected_ffmpeg() -> str:
    executable = shutil.which("ffmpeg")
    if executable:
        return executable
    homebrew_path = Path("/opt/homebrew/bin/ffmpeg")
    if homebrew_path.is_file():
        return str(homebrew_path)
    raise BuildError("ffmpeg was not found; install is out of scope. Add the existing ffmpeg executable to PATH and retry.")


def copy_file(repository: Path, stage: Path, relative_path: str, hashes: dict[str, str]) -> None:
    source = repository / relative_path
    if not source.is_file():
        raise BuildError(f"Required allowlisted input is missing: {relative_path}")
    destination = stage / relative_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    hashes[relative_path] = sha256_file(source)


def atlas_command(ffmpeg: str, frame_dir: Path, start_number: int, frame_count: int, atlas_path: Path) -> list[str]:
    video_filter = (
        "format=rgba,scale=512:512:flags=lanczos,format=rgba,"
        "tile=5x5:nb_frames=25:padding=0:margin=0:color=black@0"
    )
    return [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-nostdin",
        "-filter_threads",
        "1",
        "-start_number",
        str(start_number),
        "-i",
        str(frame_dir / "frame-%04d.png"),
        "-vf",
        video_filter,
        "-frames:v",
        "1",
        "-pix_fmt",
        "rgba",
        "-f",
        "image2",
        str(atlas_path),
    ]


def run_atlas(ffmpeg: str, frame_dir: Path, start_number: int, frame_count: int, atlas_path: Path) -> None:
    result = subprocess.run(atlas_command(ffmpeg, frame_dir, start_number, frame_count, atlas_path), text=True, capture_output=True)
    if result.returncode != 0:
        details = result.stderr.strip() or "ffmpeg returned no diagnostic text"
        raise BuildError(f"Could not build atlas starting at frame {start_number}: {details}")
    if not atlas_path.is_file():
        raise BuildError(f"ffmpeg completed without writing the expected atlas: {atlas_path}")
    with atlas_path.open("rb") as stream:
        header = stream.read(29)
    if len(header) < 29 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise BuildError(f"ffmpeg output is not a PNG atlas: {atlas_path}")
    width, height, bit_depth, color_type, _compression, _filter, _interlace = struct.unpack(">IIBBBBB", header[16:29])
    if (width, height, bit_depth, color_type) != (2560, 2560, 8, 6):
        raise BuildError(f"Expected a 2560x2560 RGBA atlas, got {width}x{height} depth={bit_depth} type={color_type}: {atlas_path}")


def write_variant_manifest(
    stage: Path,
    variant: str,
    frame_records: list[dict[str, str]],
    anchor_x: float,
    anchor_y: float,
    frame_count: int,
) -> dict[str, str]:
    destination = stage / "assets" / "art" / "jiang_turn_review" / variant
    destination.mkdir(parents=True, exist_ok=True)
    frames: list[dict[str, Any]] = []
    atlas_paths: dict[int, str] = {}
    for index, source_record in enumerate(frame_records):
        page = index // FRAMES_PER_ATLAS
        cell = index % FRAMES_PER_ATLAS
        atlas_name = f"atlas-{page:02d}.png"
        atlas_path = f"res://assets/art/jiang_turn_review/{variant}/{atlas_name}"
        atlas_paths[page] = atlas_path
        x = (cell % ATLAS_COLUMNS) * CELL_SIZE[0]
        y = (cell // ATLAS_COLUMNS) * CELL_SIZE[1]
        frames.append({
            "path": atlas_path,
            "region": [x, y, CELL_SIZE[0], CELL_SIZE[1]],
            "source_frame": source_record["name"],
            "source_sha256": source_record["sha256"],
        })
    anchor = [anchor_x * CELL_SIZE[0] / SOURCE_SIZE[0], anchor_y * CELL_SIZE[1] / SOURCE_SIZE[1]]
    manifest = {
        "version": 1,
        "variant": variant,
        "fps": FPS,
        "frame_count": frame_count,
        "duration_seconds": frame_count / FPS,
        "source_size": list(SOURCE_SIZE),
        "cell_size": list(CELL_SIZE),
        "atlas_columns": ATLAS_COLUMNS,
        "atlas_rows": ATLAS_ROWS,
        "frames_per_atlas": FRAMES_PER_ATLAS,
        "atlas_pages": [atlas_paths[index] for index in range((frame_count + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS)],
        "anchor_source_px": [anchor_x, anchor_y],
        "anchor_resized_px": anchor,
        "frames": frames,
    }
    manifest_path = destination / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"manifest": manifest_path.relative_to(stage).as_posix(), "manifest_sha256": sha256_file(manifest_path)}


def tree_hash(files: dict[str, str]) -> str:
    content = "\n".join(f"{path}\t{files[path]}" for path in sorted(files)) + "\n"
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def build_stage(args: argparse.Namespace, root: Path, old_dir: Path, new_dir: Path,
                old_frames: list[dict[str, str]], new_frames: list[dict[str, str]], out_root: Path) -> dict[str, Any]:
    ffmpeg = selected_ffmpeg()
    stage = out_root / f"stage-{uuid.uuid4().hex[:12]}"
    stage.mkdir(exist_ok=False)
    source_hashes: dict[str, str] = {}
    allowlist = ("scenes/demos/jiang_turn_review.tscn", *SCRIPT_FILES, *DATA_FILES, *ART_FILES, *FONT_FILES, *SHADER_FILES)
    for relative_path in allowlist:
        copy_file(root, stage, relative_path, source_hashes)
    tool_relative = "tools/hero_lookdev/build_turn_scene_review.py"
    copy_file(root, stage, tool_relative, source_hashes)
    (stage / "project.godot").write_text(PROJECT, encoding="utf-8")
    source_hashes["project.godot"] = sha256_file(stage / "project.godot")

    frame_sources = {"old": old_frames, "refined": new_frames}
    frame_dirs = {"old": old_dir, "refined": new_dir}
    variants: dict[str, Any] = {}
    atlas_page_count = (args.frame_count + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS
    for variant, records in frame_sources.items():
        variant_dir = stage / "assets" / "art" / "jiang_turn_review" / variant
        variant_dir.mkdir(parents=True, exist_ok=True)
        atlas_records: list[dict[str, str]] = []
        for page in range(atlas_page_count):
            start = page * FRAMES_PER_ATLAS + 1
            count = min(FRAMES_PER_ATLAS, args.frame_count - (start - 1))
            atlas_path = variant_dir / f"atlas-{page:02d}.png"
            run_atlas(ffmpeg, frame_dirs[variant], start, count, atlas_path)
            atlas_records.append({"path": atlas_path.relative_to(stage).as_posix(), "sha256": sha256_file(atlas_path)})
        manifest_record = write_variant_manifest(stage, variant, records, args.anchor_x, args.anchor_y, args.frame_count)
        variants[variant] = {
            "source_directory": str(frame_dirs[variant]),
            "source_frames": records,
            "atlases": atlas_records,
            **manifest_record,
        }

    files: dict[str, str] = {}
    for path in sorted(stage.rglob("*")):
        if path.is_file() and path.name != "build-info.json":
            files[path.relative_to(stage).as_posix()] = sha256_file(path)
    reproduction_args = [
        "python3", str(root / tool_relative),
        "--old-frames", str(old_dir),
        "--new-frames", str(new_dir),
        "--out-root", str(out_root),
        "--anchor-x", str(args.anchor_x),
        "--anchor-y", str(args.anchor_y),
        "--frame-count", str(args.frame_count),
    ]
    receipt = {
        "status": "STAGE_PREPARED",
        "stage": str(stage),
        "godot_project": "res://scenes/demos/jiang_turn_review.tscn",
        "frame_contract": {
            "source_size": list(SOURCE_SIZE),
            "source_format": "8-bit RGBA PNG",
            "resized_cell_size": list(CELL_SIZE),
            "fps": FPS,
            "frame_count": args.frame_count,
            "duration_seconds": args.frame_count / FPS,
            "atlas_grid": [ATLAS_COLUMNS, ATLAS_ROWS],
            "atlas_pages_per_variant": atlas_page_count,
            "anchor_source_px": [args.anchor_x, args.anchor_y],
            "anchor_resized_px": [args.anchor_x * CELL_SIZE[0] / SOURCE_SIZE[0], args.anchor_y * CELL_SIZE[1] / SOURCE_SIZE[1]],
            "scene_foot_anchor": [1010.0, 565.0],
            "scene_actor_scale": 0.62,
        },
        "ffmpeg": ffmpeg,
        "source_hashes": source_hashes,
        "variants": variants,
        "stage_files": files,
        "stage_content_sha256": tree_hash(files),
        "reproduction_args": reproduction_args,
        "godot_import_export_run": False,
        "browser_qa_run": False,
    }
    (stage / "build-info.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"status": "STAGE_PREPARED", "stage": str(stage), "stage_content_sha256": receipt["stage_content_sha256"], "variant_frame_counts": {key: len(value["source_frames"]) for key, value in variants.items()}}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old-frames", required=True, help="Absolute directory with sequentially named 1000x1000 RGBA frames")
    parser.add_argument("--new-frames", required=True, help="Absolute directory with sequentially named 1000x1000 RGBA frames")
    parser.add_argument("--frame-count", type=int, choices=FRAME_COUNT_CHOICES, default=FRAME_COUNT, help="shared clip length at 30 fps (default: 60)")
    parser.add_argument("--out-root", required=True, help="Existing absolute output directory; a new stage subdirectory is created")
    parser.add_argument("--anchor-x", type=float, default=512.0, help="Shared anchor x coordinate in the 1000x1000 source frames")
    parser.add_argument("--anchor-y", type=float, default=900.0, help="Shared anchor y coordinate in the 1000x1000 source frames")
    parser.add_argument("--dry-run", action="store_true", help="Validate both frame sets and print hashes without writing output")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if not (0.0 <= args.anchor_x <= SOURCE_SIZE[0] and 0.0 <= args.anchor_y <= SOURCE_SIZE[1]):
            raise BuildError("--anchor-x and --anchor-y must be within the 1000x1000 source frame")
        root = Path(__file__).resolve().parents[2]
        old_dir, old_frames = validate_frame_dir(args.old_frames, "old", args.frame_count)
        new_dir, new_frames = validate_frame_dir(args.new_frames, "new", args.frame_count)
        out_root = validate_out_root(args.out_root)
        if args.dry_run:
            result = {
                "status": "DRY_RUN_VALIDATED",
                "frame_count": args.frame_count,
                "duration_seconds": args.frame_count / FPS,
                "old_frames": {"directory": str(old_dir), "count": len(old_frames), "sha256": old_frames},
                "new_frames": {"directory": str(new_dir), "count": len(new_frames), "sha256": new_frames},
                "source_anchor_px": [args.anchor_x, args.anchor_y],
                "resized_anchor_px": [args.anchor_x * CELL_SIZE[0] / SOURCE_SIZE[0], args.anchor_y * CELL_SIZE[1] / SOURCE_SIZE[1]],
                "out_root": str(out_root),
                "next_step": "Remove --dry-run to create a new isolated stage; Godot import/export remains a separate step.",
            }
        else:
            result = build_stage(args, root, old_dir, new_dir, old_frames, new_frames, out_root)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except BuildError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
