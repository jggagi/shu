"""Stage or build one isolated hero-martial Back Mountain review."""
import argparse
import hashlib
import json
import runpy
import shutil
import subprocess
import uuid
from pathlib import Path


SHOT_CONFIG = {
    "sword": {
        "shot_id": "jiang-sword-horizontal-return-v1",
        "scene": "scenes/demos/hero_martial_sword.tscn",
        "asset_dir": "assets/art/hero_martial_v1/jiang-sword-horizontal-return-v1",
        "title": "江砚秋 · 后山横抹回剑",
    },
    "fist": {
        "shot_id": "jiang-fist-straight-punch-v1",
        "scene": "scenes/demos/hero_martial_fist.tscn",
        "asset_dir": "assets/art/hero_martial_v1/jiang-fist-straight-punch-v1",
        "title": "江砚秋 · 后山站桩冲拳",
    },
}

LEGACY_SCENE = "scenes/demos/sword_image_back_mountain.tscn"
LEGACY_TEST_PREFIX = "sword_image_pilot"
LEGACY_PACKAGE_DIRS = {
    "assets/art/sword_image_driven_v1",
    "assets/art/sword_image_clean_matte_v1",
}
LEGACY_EXPORT_FILTER = 'exclude_filter="tests/*,assets/art/sword_image_driven_v1/source.mp4"'
REVIEW_EXPORT_FILTER = 'exclude_filter="tests/*,**/source.mp4"'


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def legacy_builder(root: Path) -> dict:
    path = root / "tools/sword_image_driven/build_pilot.py"
    return runpy.run_path(str(path))


def selected_files(root: Path, shot: str, legacy_files: list[Path]) -> list[Path]:
    config = SHOT_CONFIG[shot]
    scene = root / config["scene"]
    test = root / "tests/hero_martial_review_test.gd"
    package = root / config["asset_dir"]
    manifest_path = package / "atlas.json"
    source_path = package / "source.json"
    required = [
        scene,
        test,
        manifest_path,
        source_path,
        root / "assets/fonts/ShuHeroMartialSerif.ttf",
        root / "assets/fonts/source-hero-martial.json",
    ]
    if not package.is_dir():
        raise SystemExit(f"Missing selected package: {package.relative_to(root)}")
    atlas_pages = sorted(package.glob("atlas-*.png"))
    if not atlas_pages:
        raise SystemExit(f"No atlas pages in {package.relative_to(root)}")
    required.extend(atlas_pages)
    missing = [path for path in required if not path.is_file()]
    if missing:
        raise SystemExit("Missing input: " + ", ".join(str(path.relative_to(root)) for path in missing))

    manifest = json.loads(manifest_path.read_text())
    source = json.loads(source_path.read_text())
    if manifest.get("shot_id") != config["shot_id"] or source.get("shot_id") != config["shot_id"]:
        raise SystemExit(f"Selected package identity does not match {shot}")
    page_paths = {path.relative_to(root).as_posix() for path in atlas_pages}
    for frame in manifest.get("frames", []):
        resource_path = frame.get("path", "")
        if not resource_path.startswith("res://"):
            raise SystemExit(f"Invalid atlas resource path: {resource_path}")
        rel_page = resource_path.removeprefix("res://")
        if rel_page not in page_paths:
            raise SystemExit(f"Missing atlas page referenced by manifest: {resource_path}")

    selected: dict[str, Path] = {}
    for path in legacy_files:
        relative = path.relative_to(root)
        rel = relative.as_posix()
        if rel == LEGACY_SCENE:
            continue
        if any(rel == directory or rel.startswith(directory + "/") for directory in LEGACY_PACKAGE_DIRS):
            continue
        if relative.parts and relative.parts[0] == "tests" and relative.name.startswith(LEGACY_TEST_PREFIX):
            continue
        if relative.name == "source.mp4":
            continue
        selected[rel] = path

    for path in required:
        selected[path.relative_to(root).as_posix()] = path
    return [selected[key] for key in sorted(selected)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shot", choices=sorted(SHOT_CONFIG), default="sword")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--stage-only", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    config = SHOT_CONFIG[args.shot]
    legacy = legacy_builder(root)
    files = selected_files(root, args.shot, legacy["pilot_dependencies"](root))

    run_id = uuid.uuid4().hex[:10]
    output = args.output.expanduser().resolve()
    stage = output / "stage" / f"{args.shot}-{run_id}"
    web = output / "Web" / f"{args.shot}-{run_id}"
    receipt_path = output / f"{args.shot}-{run_id}-receipt.json"
    stage.mkdir(parents=True, exist_ok=False)

    source_hashes: dict[str, str] = {}
    staged_hashes: dict[str, str] = {}
    for source in files:
        relative = source.relative_to(root)
        destination = stage / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        source_hash = sha(source)
        shutil.copy2(source, destination)
        destination_hash = sha(destination)
        if source_hash != destination_hash or sha(source) != source_hash:
            raise SystemExit(f"Input changed or copy hash mismatch: {relative.as_posix()}")
        source_hashes[relative.as_posix()] = source_hash
        staged_hashes[relative.as_posix()] = destination_hash

    old_main = "res://scenes/demos/sword_image_back_mountain.tscn"
    new_main = "res://" + config["scene"]
    project = legacy["PROJECT"]
    if project.count(old_main) != 1:
        raise SystemExit("Legacy project template main scene changed unexpectedly")
    project = project.replace(old_main, new_main)
    project = project.replace("江砚秋 · 后山转身挥剑", config["title"])
    export_preset = legacy["EXPORT"]
    if LEGACY_EXPORT_FILTER not in export_preset:
        raise SystemExit("Legacy export template filter changed unexpectedly")
    export_preset = export_preset.replace(LEGACY_EXPORT_FILTER, REVIEW_EXPORT_FILTER)
    (stage / "project.godot").write_text(project)
    (stage / "export_presets.cfg").write_text(export_preset)
    staged_hashes["project.godot"] = sha(stage / "project.godot")
    staged_hashes["export_presets.cfg"] = sha(stage / "export_presets.cfg")

    source_videos = [path.relative_to(stage).as_posix() for path in stage.rglob("source.mp4")]
    if source_videos:
        raise SystemExit("Source video must not enter review staging: " + ", ".join(source_videos))

    receipt = {
        "schema_version": 1,
        "shot": args.shot,
        "shot_id": config["shot_id"],
        "scene": config["scene"],
        "main_scene": new_main,
        "stage": str(stage),
        "web": None,
        "stage_only": args.stage_only,
        "godot_command": args.godot,
        "source_mp4_staged": False,
        "export_excludes_source_mp4": "**/source.mp4" in export_preset,
        "project_settings": {
            "engine_feature": "4.7",
            "renderer": "gl_compatibility",
            "editor_import_multiple_threads": False,
            "web_thread_support": False,
        },
        "source_hashes": source_hashes,
        "staged_hashes": staged_hashes,
        "build_steps": {},
        "repo_project_files_modified": False,
    }
    # Preserve the frozen input receipt even when a later engine process is interrupted.
    receipt["status"] = "staged"
    receipt_path.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n")

    if not args.stage_only:
        web.mkdir(parents=True, exist_ok=False)
        logs = output / "logs"
        logs.mkdir(parents=True, exist_ok=True)
        steps = [
            ("import", [args.godot, "--headless", "--path", str(stage), "--editor", "--import"]),
            ("web_export", [args.godot, "--headless", "--path", str(stage), "--export-release", "Web", str(web / "index.html")]),
        ]
        for label, command in steps:
            log_path = logs / f"{args.shot}-{run_id}-{label}.log"
            with log_path.open("w") as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
            receipt["build_steps"][label] = {"command": command, "exit_code": result.returncode, "log": str(log_path)}
            if result.returncode != 0 or "ERROR:" in log_path.read_text(errors="replace"):
                receipt["status"] = "failed"
                receipt_path.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n")
                raise SystemExit(f"Failed {label}; see {log_path}")
        receipt["status"] = "built"
        receipt["web"] = str(web)
        receipt["web_hashes"] = {
            path.relative_to(web).as_posix(): sha(path)
            for path in sorted(web.rglob("*"))
            if path.is_file()
        }
    else:
        receipt["status"] = "staged"

    receipt_path.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"status": receipt["status"], "shot": args.shot, "stage": str(stage), "web": receipt["web"], "receipt": str(receipt_path)}))


if __name__ == "__main__":
    main()
