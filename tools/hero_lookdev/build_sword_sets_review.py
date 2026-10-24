#!/usr/bin/env python3
"""Package five named sword routines into an isolated review scene.

Inputs are five directories of 180 sequential 1000x1000 8-bit RGBA PNGs plus
one shared 60-frame idle directory. A normal run delegates the first idle/action
package to the existing single-action builder, then adds the remaining four
actions and a runtime catalog to that fresh UUID stage. It does not start
Godot, import resources, export a build, or launch a renderer.

Example:
  python3 tools/hero_lookdev/build_sword_sets_review.py \
    --idle-frames /abs/idle-frames --catalog /abs/sword-sets.json \
    --out-root /abs/existing/output --dry-run
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any


ACTION_FRAME_COUNT = 180
IDLE_FRAME_COUNT = 60
FPS = 30
ATLAS_COLUMNS = 5
ATLAS_ROWS = 5
FRAMES_PER_ATLAS = ATLAS_COLUMNS * ATLAS_ROWS
SET_COUNT = 5
SET_FONT_FILES = (
	"assets/fonts/ShuSwordSetsSerif.ttf",
	"assets/fonts/source-sword-sets.json",
)
SET_TOOL_FILES = (
	"tools/hero_lookdev/build_sword_sets_review.py",
	"tools/hero_lookdev/rebuild_sword_sets_font.py",
	"tools/hero_lookdev/validate_sword_sets_scene.gd",
)
SLUG_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class BuildError(RuntimeError):
	"""Expected input or packaging failure."""


def load_single_builder() -> Any:
	sys.dont_write_bytecode = True
	builder_path = Path(__file__).resolve().with_name("build_sword_cycle_review.py")
	spec = importlib.util.spec_from_file_location("sword_cycle_review_builder", builder_path)
	if spec is None or spec.loader is None:
		raise BuildError(f"Could not load existing single-action builder: {builder_path}")
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	return module


def sha256_file(path: Path) -> str:
	digest = hashlib.sha256()
	with path.open("rb") as stream:
		for chunk in iter(lambda: stream.read(1024 * 1024), b""):
			digest.update(chunk)
	return digest.hexdigest()


def validate_catalog(path_value: str, builder: Any) -> tuple[Path, bytes, list[dict[str, Any]]]:
	raw_path = Path(path_value).expanduser()
	if not raw_path.is_absolute():
		raise BuildError(f"--catalog must be an absolute path: {path_value}")
	try:
		catalog_path = raw_path.resolve(strict=True)
		catalog_bytes = catalog_path.read_bytes()
		catalog_value = json.loads(catalog_bytes.decode("utf-8"))
	except FileNotFoundError as error:
		raise BuildError(f"--catalog does not exist: {raw_path}") from error
	except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
		raise BuildError(f"--catalog is not readable UTF-8 JSON: {error}") from error
	if not catalog_path.is_file():
		raise BuildError(f"--catalog must be a regular file: {catalog_path}")
	if not isinstance(catalog_value, dict) or set(catalog_value) != {"version", "sets"}:
		raise BuildError("Input catalog must contain exactly version and sets")
	if type(catalog_value["version"]) is not int or catalog_value["version"] != 1:
		raise BuildError("Input catalog version must be 1")
	sets_value = catalog_value["sets"]
	if not isinstance(sets_value, list) or len(sets_value) != SET_COUNT:
		raise BuildError(f"Input catalog must contain exactly {SET_COUNT} sets")

	sets: list[dict[str, Any]] = []
	seen_ids: set[str] = set()
	for index, set_value in enumerate(sets_value):
		if not isinstance(set_value, dict) or set(set_value) != {"id", "label", "description", "frames_directory", "phases"}:
			raise BuildError(f"Catalog set {index + 1} must contain exactly id, label, description, frames_directory, and phases")
		set_id = set_value["id"]
		label = set_value["label"]
		description = set_value["description"]
		frames_directory = set_value["frames_directory"]
		if not isinstance(set_id, str) or not SLUG_PATTERN.fullmatch(set_id) or set_id in seen_ids:
			raise BuildError(f"Catalog set {index + 1} needs a unique safe slug ID")
		if not isinstance(label, str) or not label.strip():
			raise BuildError(f"Catalog set {set_id} needs a nonempty label")
		if not isinstance(description, str) or not description.strip():
			raise BuildError(f"Catalog set {set_id} needs a nonempty description")
		if not isinstance(frames_directory, str):
			raise BuildError(f"Catalog set {set_id} frames_directory must be an absolute path")
		try:
			resolved_directory, frame_records = builder.validate_frame_dir(frames_directory, f"set-{set_id}", ACTION_FRAME_COUNT)
		except BuildError:
			raise
		except Exception as error:
			raise BuildError(f"Could not validate frames for set {set_id}: {error}") from error
		phases_value = set_value["phases"]
		if not isinstance(phases_value, list) or not phases_value:
			raise BuildError(f"Catalog set {set_id} needs ordered phases")
		phases: list[dict[str, Any]] = []
		previous_start = 0
		for phase_index, phase_value in enumerate(phases_value):
			if not isinstance(phase_value, dict) or set(phase_value) != {"start_frame", "label"}:
				raise BuildError(f"Phase {phase_index + 1} in set {set_id} must contain exactly start_frame and label")
			start_frame = phase_value["start_frame"]
			phase_label = phase_value["label"]
			if type(start_frame) is not int or start_frame <= previous_start or start_frame > ACTION_FRAME_COUNT:
				raise BuildError(f"Phases in set {set_id} must have strictly increasing starts in 1..{ACTION_FRAME_COUNT}")
			if not isinstance(phase_label, str) or not phase_label.strip():
				raise BuildError(f"Phase {phase_index + 1} in set {set_id} needs a nonempty label")
			phases.append({"start_frame": start_frame, "label": phase_label})
			previous_start = start_frame
		if phases[0]["start_frame"] != 1:
			raise BuildError(f"Phases in set {set_id} must start at frame 1")
		seen_ids.add(set_id)
		sets.append({
			"id": set_id,
			"label": label,
			"description": description,
			"frames_directory": resolved_directory,
			"source_frames": frame_records,
			"phases": phases,
		})
	return catalog_path, catalog_bytes, sets


def validate_idle(path_value: str, builder: Any) -> tuple[Path, list[dict[str, str]]]:
	try:
		return builder.validate_frame_dir(path_value, "idle", IDLE_FRAME_COUNT)
	except builder.BuildError as error:
		raise BuildError(str(error)) from error


def write_action_set(stage: Path, ffmpeg: str, set_data: dict[str, Any], clip_name: str, builder: Any) -> dict[str, Any]:
	clip_directory = stage / "assets" / "art" / "jiang_sword_cycle" / clip_name
	clip_directory.mkdir(parents=True, exist_ok=True)
	atlas_pages: list[dict[str, str]] = []
	page_count = (ACTION_FRAME_COUNT + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS
	for page in range(page_count):
		start_number = page * FRAMES_PER_ATLAS + 1
		atlas_path = clip_directory / f"atlas-{page:02d}.png"
		builder.run_atlas(ffmpeg, set_data["frames_directory"], start_number, atlas_path)
		atlas_pages.append({"path": atlas_path.relative_to(stage).as_posix(), "sha256": sha256_file(atlas_path)})
	manifest = builder.write_clip_manifest(stage, clip_name, set_data["source_frames"])
	return {
		"source_directory": str(set_data["frames_directory"]),
		"source_frames": set_data["source_frames"],
		"atlases": atlas_pages,
		**manifest,
	}


def validate_set_font_assets(root: Path, catalog_bytes: bytes) -> None:
	font_path = root / SET_FONT_FILES[0]
	metadata_path = root / SET_FONT_FILES[1]
	license_path = root / "assets/fonts/OFL-Serif.txt"
	if not font_path.is_file() or not metadata_path.is_file() or not license_path.is_file():
		raise BuildError("Sword-sets font, source record, and OFL license must exist before packaging")
	try:
		metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
	except (OSError, json.JSONDecodeError) as error:
		raise BuildError(f"Sword-sets font source record is unreadable: {error}") from error
	if metadata.get("CatalogSHA256") != hashlib.sha256(catalog_bytes).hexdigest():
		raise BuildError("Sword-sets font was not built from this exact input catalog")
	player_path = root / "scripts/hero_lookdev/sword_cycle_review.gd"
	if metadata.get("PlayerSourceSHA256") != sha256_file(player_path):
		raise BuildError("Sword-sets font source record does not match the current player script")
	if metadata.get("DerivedSHA256") != sha256_file(font_path):
		raise BuildError("Sword-sets font differs from its source record")


def build_sets_stage(root: Path, idle_dir: Path, idle_records: list[dict[str, str]],
					 catalog_path: Path, catalog_bytes: bytes, sets: list[dict[str, Any]],
					 out_root: Path, builder: Any) -> dict[str, Any]:
	validate_set_font_assets(root, catalog_bytes)
	first_set = sets[0]
	args = argparse.Namespace(idle_frames=str(idle_dir), action_frames=str(first_set["frames_directory"]), out_root=str(out_root))
	initial = builder.build_stage(
		args,
		root,
		idle_dir,
		first_set["frames_directory"],
		idle_records,
		first_set["source_frames"],
		out_root,
	)
	stage = Path(initial["stage"])
	build_info_path = stage / "build-info.json"
	receipt = json.loads(build_info_path.read_text(encoding="utf-8"))
	ffmpeg = str(receipt["ffmpeg"])
	clips: dict[str, Any] = receipt["clips"]
	set_records: list[dict[str, Any]] = []
	for index, set_data in enumerate(sets):
		clip_name = "action" if index == 0 else f"action-{set_data['id']}"
		if index == 0:
			clip_record = clips["action"]
		else:
			clip_record = write_action_set(stage, ffmpeg, set_data, clip_name, builder)
			clips[clip_name] = clip_record
		manifest_relative = str(clip_record["manifest"])
		set_records.append({
			"id": set_data["id"],
			"label": set_data["label"],
			"description": set_data["description"],
			"manifest_path": "res://" + manifest_relative,
			"clip_name": clip_name,
			"phases": set_data["phases"],
		})

	sets_catalog = {"version": 1, "sets": set_records}
	sets_catalog_path = stage / "assets/art/jiang_sword_cycle/sets.json"
	sets_catalog_path.parent.mkdir(parents=True, exist_ok=True)
	sets_catalog_path.write_text(json.dumps(sets_catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

	source_hashes: dict[str, str] = receipt["source_hashes"]
	for relative_path in (*SET_FONT_FILES, *SET_TOOL_FILES):
		builder.copy_file(root, stage, relative_path, source_hashes)

	receipt["clips"] = clips
	receipt["sets"] = set_records
	receipt["input_catalog"] = {
		"path": str(catalog_path),
		"sha256": hashlib.sha256(catalog_bytes).hexdigest(),
	}
	receipt["inputs"] = {
		"idle_frames": {
			"directory": str(idle_dir),
			"frame_count": len(idle_records),
			"frames": idle_records,
		},
		"catalog": receipt["input_catalog"],
		"action_sets": [
			{
				"id": item["id"],
				"directory": str(item["frames_directory"]),
				"frame_count": len(item["source_frames"]),
				"frames": item["source_frames"],
			}
			for item in sets
		],
	}
	receipt["frame_contract"].update({
		"action_sets": SET_COUNT,
		"action_frames_per_set": ACTION_FRAME_COUNT,
		"action_duration_seconds_per_set": ACTION_FRAME_COUNT / FPS,
		"input_frame_count": IDLE_FRAME_COUNT + SET_COUNT * ACTION_FRAME_COUNT,
		"total_atlas_pages": (
			(IDLE_FRAME_COUNT + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS
			+ SET_COUNT * ((ACTION_FRAME_COUNT + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS)
		),
		"action_atlas_pages_per_set": (ACTION_FRAME_COUNT + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS,
	})
	receipt["reproduction_args"] = [
		"python3",
		str(root / "tools/hero_lookdev/build_sword_sets_review.py"),
		"--idle-frames",
		str(idle_dir),
		"--catalog",
		str(catalog_path),
		"--out-root",
		str(out_root),
	]
	receipt["source_hashes"] = source_hashes

	stage_files: dict[str, str] = {}
	for path in sorted(stage.rglob("*")):
		if path.is_file() and path.name != "build-info.json":
			stage_files[path.relative_to(stage).as_posix()] = sha256_file(path)
	receipt["stage_files"] = stage_files
	receipt["stage_content_sha256"] = builder.tree_hash(stage_files)
	build_info_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	page_counts = {name: len(item["atlases"]) for name, item in clips.items()}
	return {
		"status": "STAGE_PREPARED",
		"stage": str(stage),
		"stage_content_sha256": receipt["stage_content_sha256"],
		"set_count": len(set_records),
		"input_frame_count": receipt["frame_contract"]["input_frame_count"],
		"atlas_pages": page_counts,
		"total_atlas_pages": receipt["frame_contract"]["total_atlas_pages"],
		"set_ids": [item["id"] for item in set_records],
	}


def build_parser() -> argparse.ArgumentParser:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--idle-frames", required=True, help="Absolute directory with 60 sequential 1000x1000 RGBA PNGs")
	parser.add_argument("--catalog", required=True, help="Absolute input catalog containing exactly five named action sets")
	parser.add_argument("--out-root", required=True, help="Existing absolute output directory; a new stage is created")
	parser.add_argument("--dry-run", action="store_true", help="Validate every input frame and report hashes without writing output")
	return parser


def main(argv: list[str] | None = None) -> int:
	args = build_parser().parse_args(argv)
	try:
		builder = load_single_builder()
		root = Path(__file__).resolve().parents[2]
		idle_dir, idle_records = validate_idle(args.idle_frames, builder)
		catalog_path, catalog_bytes, sets = validate_catalog(args.catalog, builder)
		out_root = builder.validate_out_root(args.out_root)
		if args.dry_run:
			result = {
				"status": "DRY_RUN_VALIDATED",
				"fps": FPS,
				"idle": {
					"directory": str(idle_dir),
					"frame_count": len(idle_records),
					"duration_seconds": IDLE_FRAME_COUNT / FPS,
					"frames": idle_records,
				},
				"sets": [
					{
						"id": item["id"],
						"label": item["label"],
						"description": item["description"],
						"directory": str(item["frames_directory"]),
						"frame_count": len(item["source_frames"]),
						"duration_seconds": ACTION_FRAME_COUNT / FPS,
						"atlas_pages": (ACTION_FRAME_COUNT + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS,
						"phases": item["phases"],
						"frames": item["source_frames"],
					}
					for item in sets
				],
				"input_catalog_sha256": hashlib.sha256(catalog_bytes).hexdigest(),
				"total_input_frames": IDLE_FRAME_COUNT + SET_COUNT * ACTION_FRAME_COUNT,
				"total_atlas_pages": (
					(IDLE_FRAME_COUNT + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS
					+ SET_COUNT * ((ACTION_FRAME_COUNT + FRAMES_PER_ATLAS - 1) // FRAMES_PER_ATLAS)
				),
				"out_root": str(out_root),
				"next_step": "Remove --dry-run to create a new isolated stage; Godot import/export remains separate.",
			}
		else:
			result = build_sets_stage(root, idle_dir, idle_records, catalog_path, catalog_bytes, sets, out_root, builder)
		print(json.dumps(result, ensure_ascii=False, indent=2))
		return 0
	except (RuntimeError, OSError, ValueError, KeyError) as error:
		print(f"ERROR: {error}", file=sys.stderr)
		return 2


if __name__ == "__main__":
	raise SystemExit(main())
