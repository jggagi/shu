#!/usr/bin/env python3
"""Package the standalone idle-to-sword-action review scene.

Inputs are 1000x1000 8-bit RGBA PNGs named frame-0001.png onward. A normal
run writes a new UUID stage under an existing absolute --out-root. It does not
start Godot, import resources, export a build, or launch a renderer. --dry-run
checks both frame sets and reports their hashes without writing a stage.

Example:
  python3 tools/hero_lookdev/build_sword_cycle_review.py \
    --idle-frames /abs/idle-frames --action-frames /abs/action-frames \
    --out-root /abs/existing/output --dry-run
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
from pathlib import Path
from typing import Any


SOURCE_SIZE = (1000, 1000)
CELL_SIZE = (512, 512)
FPS = 30
IDLE_FRAME_COUNT = 60
ACTION_FRAME_COUNT = 180
ATLAS_COLUMNS = 5
ATLAS_ROWS = 5
FRAMES_PER_ATLAS = ATLAS_COLUMNS * ATLAS_ROWS
ANCHOR_SOURCE = (478.95962, 911.13357)
FOOT_ANCHOR = (1010.0, 565.0)
ACTOR_SCALE = 0.62

PROJECT = '''config_version=5
[application]
config/name="后山 · 江砚秋练剑"
config/version="0.1.0-jiang-sword-cycle-review"
run/main_scene="res://scenes/demos/jiang_sword_cycle.tscn"
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
    "scripts/hero_lookdev/sword_cycle_review.gd",
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
	"assets/fonts/ShuSwordCycleSerif.ttf",
	"assets/fonts/source-sword-cycle.json",
    "assets/fonts/OFL-Serif.txt",
)
SHADER_FILES = (
    "assets/shaders/back_mountain_cloud.gdshader",
    "assets/shaders/back_mountain_cloud_shadow.gdshader",
    "assets/shaders/back_mountain_environment_art.gdshader",
    "assets/shaders/back_mountain_mist.gdshader",
    "assets/shaders/back_mountain_near_wind.gdshader",
    "assets/shaders/back_mountain_rain.gdshader",
    "assets/shaders/back_mountain_sun.gdshader",
    "assets/shaders/waterfall_flow.gdshader",
)
QA_FILES = (
    "tools/hero_lookdev/validate_sword_cycle_scene.gd",
)


class BuildError(RuntimeError):
    """Expected input or packaging failure."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def png_info(path: Path) -> dict[str, int]:
    with path.open("rb") as stream:
        header = stream.read(29)
    if len(header) < 29 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise BuildError(f"Not a PNG with a readable IHDR header: {path}")
    width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(">IIBBBBB", header[16:29])
    if (width, height) != SOURCE_SIZE:
        raise BuildError(f"Expected a 1000x1000 source frame, got {width}x{height}: {path}")
    if (bit_depth, color_type, compression, filter_method, interlace) != (8, 6, 0, 0, 0):
        raise BuildError(f"Expected non-interlaced 8-bit RGBA PNG: {path}")
    return {"width": width, "height": height, "bit_depth": bit_depth, "color_type": color_type}


def validate_frame_dir(path_value: str, label: str, expected_count: int) -> tuple[Path, list[dict[str, str]]]:
    raw_path = Path(path_value).expanduser()
    if not raw_path.is_absolute():
        raise BuildError(f"--{label}-frames must be an absolute path: {path_value}")
    try:
        directory = raw_path.resolve(strict=True)
    except FileNotFoundError as exc:
        raise BuildError(f"--{label}-frames directory does not exist: {raw_path}") from exc
    if not directory.is_dir():
        raise BuildError(f"--{label}-frames must be a directory: {directory}")

    expected_names = {f"frame-{index:04d}.png" for index in range(1, expected_count + 1)}
    frame_candidates = {
        item.name
        for item in directory.iterdir()
        if item.name.startswith("frame-") and item.suffix.lower() == ".png"
    }
    if frame_candidates != expected_names:
        raise BuildError(
            f"--{label}-frames must contain exactly {expected_count} sequential frame PNGs; "
            f"found {len(frame_candidates)} candidate(s)"
        )

    records: list[dict[str, str]] = []
    missing: list[str] = []
    for index in range(1, expected_count + 1):
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
        raise BuildError(f"--{label}-frames is missing regular files: {preview}{suffix}")
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
    raise BuildError("ffmpeg was not found; installation is out of scope. Add the existing executable to PATH and retry.")


def copy_file(repository: Path, stage: Path, relative_path: str, hashes: dict[str, str]) -> None:
    source = repository / relative_path
    if not source.is_file():
        raise BuildError(f"Required allowlisted scene input is missing: {relative_path}")
    destination = stage / relative_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    hashes[relative_path] = sha256_file(source)


def atlas_command(ffmpeg: str, frame_dir: Path, start_number: int, atlas_path: Path) -> list[str]:
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


def run_atlas(ffmpeg: str, frame_dir: Path, start_number: int, atlas_path: Path) -> None:
    result = subprocess.run(atlas_command(ffmpeg, frame_dir, start_number, atlas_path), text=True, capture_output=True)
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


def write_clip_manifest(stage: Path, clip: str, records: list[dict[str, str]]) -> dict[str, str]:
    frame_count = IDLE_FRAME_COUNT if clip == "idle" else ACTION_FRAME_COUNT
    destination = stage / "assets" / "art" / "jiang_sword_cycle" / clip
    destination.mkdir(parents=True, exist_ok=True)
    atlas_paths: dict[int, str] = {}
    frames: list[dict[str, Any]] = []
    for index, source_record in enumerate(records):
        page = index // FRAMES_PER_ATLAS
        cell = index % FRAMES_PER_ATLAS
        atlas_name = f"atlas-{page:02d}.png"
        atlas_path = f"res://assets/art/jiang_sword_cycle/{clip}/{atlas_name}"
        atlas_paths[page] = atlas_path
        frames.append({
            "path": atlas_path,
            "region": [
                (cell % ATLAS_COLUMNS) * CELL_SIZE[0],
                (cell // ATLAS_COLUMNS) * CELL_SIZE[1],
                CELL_SIZE[0],
                CELL_SIZE[1],
            ],
            "source_frame": source_record["name"],
            "source_sha256": source_record["sha256"],
        })
    anchor_resized = [ANCHOR_SOURCE[0] * CELL_SIZE[0] / SOURCE_SIZE[0], ANCHOR_SOURCE[1] * CELL_SIZE[1] / SOURCE_SIZE[1]]
    manifest = {
        "version": 1,
        "clip_name": clip,
        "fps": FPS,
        "frame_count": frame_count,
        "duration_seconds": frame_count / FPS,
        "source_size": list(SOURCE_SIZE),
        "source_format": "8-bit RGBA PNG",
        "cell_size": list(CELL_SIZE),
        "atlas_columns": ATLAS_COLUMNS,
        "atlas_rows": ATLAS_ROWS,
        "frames_per_atlas": FRAMES_PER_ATLAS,
        "atlas_pages": [atlas_paths[index] for index in range((frame_count + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS)],
        "anchor_source_px": list(ANCHOR_SOURCE),
        "anchor_resized_px": anchor_resized,
        "scene_foot_anchor": list(FOOT_ANCHOR),
        "actor_scale": ACTOR_SCALE,
        "frames": frames,
    }
    manifest_path = destination / "frames.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"manifest": manifest_path.relative_to(stage).as_posix(), "manifest_sha256": sha256_file(manifest_path)}


def tree_hash(files: dict[str, str]) -> str:
    content = "\n".join(f"{path}\t{files[path]}" for path in sorted(files)) + "\n"
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def build_stage(args: argparse.Namespace, root: Path, idle_dir: Path, action_dir: Path,
                idle_records: list[dict[str, str]], action_records: list[dict[str, str]], out_root: Path) -> dict[str, Any]:
    ffmpeg = selected_ffmpeg()
    stage = out_root / f"stage-{uuid.uuid4().hex[:12]}"
    stage.mkdir(exist_ok=False)
    source_hashes: dict[str, str] = {}
    allowlist = (
        "scenes/demos/jiang_sword_cycle.tscn",
        *SCRIPT_FILES,
        *DATA_FILES,
        *ART_FILES,
        *FONT_FILES,
        *SHADER_FILES,
        *QA_FILES,
    )
    for relative_path in allowlist:
        copy_file(root, stage, relative_path, source_hashes)
    tool_relative = "tools/hero_lookdev/build_sword_cycle_review.py"
    copy_file(root, stage, tool_relative, source_hashes)
    (stage / "project.godot").write_text(PROJECT, encoding="utf-8")
    source_hashes["project.godot"] = sha256_file(stage / "project.godot")

    clip_records = {"idle": idle_records, "action": action_records}
    clip_dirs = {"idle": idle_dir, "action": action_dir}
    clips: dict[str, Any] = {}
    for clip, records in clip_records.items():
        clip_dir = stage / "assets" / "art" / "jiang_sword_cycle" / clip
        clip_dir.mkdir(parents=True, exist_ok=True)
        atlas_pages: list[dict[str, str]] = []
        page_count = (len(records) + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS
        for page in range(page_count):
            start = page * FRAMES_PER_ATLAS + 1
            atlas_path = clip_dir / f"atlas-{page:02d}.png"
            run_atlas(ffmpeg, clip_dirs[clip], start, atlas_path)
            atlas_pages.append({"path": atlas_path.relative_to(stage).as_posix(), "sha256": sha256_file(atlas_path)})
        manifest = write_clip_manifest(stage, clip, records)
        clips[clip] = {
            "source_directory": str(clip_dirs[clip]),
            "source_frames": records,
            "atlases": atlas_pages,
            **manifest,
        }

    files: dict[str, str] = {}
    for path in sorted(stage.rglob("*")):
        if path.is_file() and path.name != "build-info.json":
            files[path.relative_to(stage).as_posix()] = sha256_file(path)
    reproduction_args = [
        "python3", str(root / tool_relative),
        "--idle-frames", str(idle_dir),
        "--action-frames", str(action_dir),
        "--out-root", str(out_root),
    ]
    receipt = {
        "status": "STAGE_PREPARED",
        "stage": str(stage),
        "godot_project": "res://scenes/demos/jiang_sword_cycle.tscn",
        "frame_contract": {
            "source_size": list(SOURCE_SIZE),
            "source_format": "8-bit RGBA PNG",
            "cell_size": list(CELL_SIZE),
            "fps": FPS,
            "idle_frames": IDLE_FRAME_COUNT,
            "idle_duration_seconds": IDLE_FRAME_COUNT / FPS,
            "action_frames": ACTION_FRAME_COUNT,
            "action_duration_seconds": ACTION_FRAME_COUNT / FPS,
            "atlas_grid": [ATLAS_COLUMNS, ATLAS_ROWS],
            "idle_atlas_pages": (IDLE_FRAME_COUNT + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS,
            "action_atlas_pages": (ACTION_FRAME_COUNT + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS,
            "anchor_source_px": list(ANCHOR_SOURCE),
            "anchor_resized_px": [ANCHOR_SOURCE[0] * CELL_SIZE[0] / SOURCE_SIZE[0], ANCHOR_SOURCE[1] * CELL_SIZE[1] / SOURCE_SIZE[1]],
            "scene_foot_anchor": list(FOOT_ANCHOR),
            "scene_actor_scale": ACTOR_SCALE,
            "settle_seconds": 0.25,
        },
        "ffmpeg": ffmpeg,
        "source_hashes": source_hashes,
        "clips": clips,
        "stage_files": files,
        "stage_content_sha256": tree_hash(files),
        "reproduction_args": reproduction_args,
        "godot_import_export_run": False,
        "browser_qa_run": False,
    }
    (stage / "build-info.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {
        "status": "STAGE_PREPARED",
        "stage": str(stage),
        "stage_content_sha256": receipt["stage_content_sha256"],
        "clip_frame_counts": {key: len(value["source_frames"]) for key, value in clips.items()},
        "atlas_pages": {key: len(value["atlases"]) for key, value in clips.items()},
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--idle-frames", required=True, help="Absolute directory with 60 sequential 1000x1000 RGBA PNGs")
    parser.add_argument("--action-frames", required=True, help="Absolute directory with 180 sequential 1000x1000 RGBA PNGs")
    parser.add_argument("--out-root", required=True, help="Existing absolute output directory; a new stage is created")
    parser.add_argument("--dry-run", action="store_true", help="Validate frames and report hashes without writing output")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        root = Path(__file__).resolve().parents[2]
        idle_dir, idle_records = validate_frame_dir(args.idle_frames, "idle", IDLE_FRAME_COUNT)
        action_dir, action_records = validate_frame_dir(args.action_frames, "action", ACTION_FRAME_COUNT)
        out_root = validate_out_root(args.out_root)
        if args.dry_run:
            result = {
                "status": "DRY_RUN_VALIDATED",
                "fps": FPS,
                "idle": {"directory": str(idle_dir), "frame_count": len(idle_records), "duration_seconds": IDLE_FRAME_COUNT / FPS, "frames": idle_records},
                "action": {"directory": str(action_dir), "frame_count": len(action_records), "duration_seconds": ACTION_FRAME_COUNT / FPS, "frames": action_records},
                "source_anchor_px": list(ANCHOR_SOURCE),
                "resized_anchor_px": [ANCHOR_SOURCE[0] * CELL_SIZE[0] / SOURCE_SIZE[0], ANCHOR_SOURCE[1] * CELL_SIZE[1] / SOURCE_SIZE[1]],
                "out_root": str(out_root),
                "next_step": "Remove --dry-run to create a new isolated stage; Godot import/export remains separate.",
            }
        else:
            result = build_stage(args, root, idle_dir, action_dir, idle_records, action_records, out_root)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except BuildError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
