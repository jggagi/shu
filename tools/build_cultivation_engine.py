"""Stage an isolated v0.2 engine preview; never change the formal game entry.

Standard library only. Run import/export against the returned directory with
the pinned Godot and the workstation build wrapper.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENTRY = "scenes/demos/cultivation_engine_v02_tea.tscn"
DEFAULT_TITLE = "养成引擎 · 归剑问天 v0.2"
DEFAULT_APP_VERSION = "0.2.1"
DEFAULT_USER_DIR = "shu-cultivation-engine-v02-tea"

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def validate_entry(entry: str) -> str:
    if not entry or "\\" in entry:
        raise SystemExit("--entry must be a relative scenes/demos .tscn path")
    path = Path(entry)
    parts = path.parts
    if (path.is_absolute() or path.as_posix() != entry or ".." in parts
            or len(parts) < 3 or parts[:2] != ("scenes", "demos") or path.suffix != ".tscn"):
        raise SystemExit("--entry must be a relative scenes/demos .tscn path")
    scene = ROOT.joinpath(*parts)
    if scene.is_symlink() or not scene.is_file():
        raise SystemExit("--entry must name an existing repository scene: " + entry)
    try:
        repo_root = ROOT.resolve()
        demos_root = (ROOT / "scenes" / "demos").resolve(strict=True)
        resolved_scene = scene.resolve(strict=True)
    except OSError:
        raise SystemExit("--entry must name an existing repository scene: " + entry)
    if not demos_root.is_relative_to(repo_root) or not resolved_scene.is_relative_to(demos_root):
        raise SystemExit("--entry must resolve inside the repository scenes/demos directory")
    return path.as_posix()

def stage(output: Path, reuse_stage: Path | None = None,
          entry: str = DEFAULT_ENTRY, title: str = DEFAULT_TITLE,
          app_version: str = DEFAULT_APP_VERSION, user_dir: str = DEFAULT_USER_DIR) -> dict:
    if not output.is_absolute() or not output.is_dir():
        raise SystemExit("--output must be an existing absolute build directory")
    entry = validate_entry(entry)
    if not title or not app_version or not user_dir:
        raise SystemExit("--title, --app-version and --user-dir must be non-empty")
    resource_entry = "res://" + entry
    reuse_hashes = {}
    if reuse_stage is not None:
        if sys.platform != "darwin" or not reuse_stage.is_absolute() or not (reuse_stage / "build-info.json").is_file():
            raise SystemExit("--reuse-stage requires an existing local macOS APFS stage")
        if reuse_stage.stat().st_dev != output.stat().st_dev:
            raise SystemExit("APFS reuse must stay on the same development volume")
        reuse_hashes = json.loads((reuse_stage / "build-info.json").read_text())["source_hashes"]
        if reuse_hashes.get(".engine-version") != sha(ROOT / ".engine-version"):
            raise SystemExit("Reuse stage engine version mismatch")
    target = output / ("stage-" + uuid.uuid4().hex[:12])
    paths = [ROOT / entry]
    # The regression scripts preload retained engine entry scenes.
    paths.extend((ROOT / "scenes/demos").glob("cultivation_engine_v0*.tscn"))
    for folder in ["addons/cultivation_mode", "games"]:
        paths.extend(p for p in (ROOT / folder).rglob("*") if p.suffix in {".gd", ".json"})
    paths += [ROOT / "assets/fonts/ShuCultivationEngineSerif.ttf",
              ROOT / "assets/fonts/source-cultivation-engine.json", ROOT / "assets/fonts/OFL-Serif.txt"]
    paths += [ROOT / "tools/build_cultivation_engine.py", ROOT / "tools/rebuild_cultivation_engine_font.py",
              ROOT / ".engine-version", ROOT / "addons/cultivation_mode/README.md", ROOT / "games/README.md"]
    if entry == "scenes/demos/cultivation_engine_v02_mentor.tscn":
        paths += [ROOT / "trunk/mentor-slow-half-step.json", ROOT / "trunk/mentor-practice-report.json",
                  ROOT / "assets/audio/mentor_pause/manifest.json",
                  ROOT / "assets/audio/mentor_practice_report/manifest.json"]
    paths.extend(p for p in (ROOT / "tests").glob("cultivation_engine_*.gd"))
    def resources(value):
        if isinstance(value, dict):
            for child in value.values():
                yield from resources(child)
        elif isinstance(value, list):
            for child in value:
                yield from resources(child)
        elif isinstance(value, str) and value.startswith("res://assets/"):
            yield ROOT / value.removeprefix("res://")
    provenance = ["assets/art/v2/source.json", "assets/art/weather3/source.json",
                  "assets/art/back_mountain_training/source.json", "assets/art/stream_teahouse/source.json",
                  "assets/art/courtyard/source.json", "assets/art/jiang_sword_cycle/source-formal.json",
                  "assets/art/jiang_sword_cycle/sets.json", "assets/data/sword_manuals.json",
                  "assets/art/tea/source.json"]
    paths.extend(ROOT / rel for rel in provenance)
    # Motion JSON references more JSON before reaching texture pages. Follow
    # resource values transitively, rather than assuming a one-level closure.
    visited = set()
    pending = list(paths)
    while pending:
        path = pending.pop()
        if path in visited:
            continue
        visited.add(path)
        if path.suffix == ".json":
            for resource in resources(json.loads(path.read_text())):
                if resource not in visited:
                    pending.append(resource)
    paths = sorted(visited)
    hashes = {}
    for source in paths:
        if source.is_symlink() or not source.is_file():
            raise SystemExit("Missing or symlinked input: " + str(source))
        hashes[source.relative_to(ROOT).as_posix()] = sha(source)
    target.mkdir()
    for rel, digest in sorted(hashes.items()):
        source = ROOT / rel
        if sha(source) != digest:
            raise SystemExit("Source changed during stage: " + rel)
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        previous = reuse_stage / rel if reuse_stage is not None else None
        if previous is not None and reuse_hashes.get(rel) == digest and previous.is_file() and sha(previous) == digest:
            subprocess.run(["/bin/cp", "-c", str(previous), str(dest)], check=True)
        else:
            shutil.copy2(source, dest)
        if sha(dest) != digest:
            raise SystemExit("Stage mismatch: " + rel)
    cache_files = 0
    if reuse_stage is not None:
        # Reuse rebuildable import data, never editor state or another live project.
        # Godot still validates source MD5 and reimports changed/new resources.
        for previous in (reuse_stage / ".godot/imported").glob("*"):
            if not previous.is_file() or previous.is_symlink():
                continue
            dest = target / ".godot/imported" / previous.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["/bin/cp", "-c", str(previous), str(dest)], check=True)
            if sha(previous) != sha(dest):
                raise SystemExit("Import clone mismatch: " + previous.name)
            cache_files += 1
        for rel, digest in hashes.items():
            previous = reuse_stage / (rel + ".import")
            if reuse_hashes.get(rel) == digest and previous.is_file() and not previous.is_symlink():
                shutil.copy2(previous, target / (rel + ".import"))
    project = f'''config_version=5
[application]
config/name={json.dumps(title, ensure_ascii=False)}
config/version={json.dumps(app_version, ensure_ascii=False)}
run/main_scene={json.dumps(resource_entry, ensure_ascii=False)}
config/features=PackedStringArray("4.7", "GL Compatibility")
config/use_custom_user_dir=true
config/custom_user_dir_name={json.dumps(user_dir, ensure_ascii=False)}
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
    (target / "project.godot").write_text(project)
    preset = '''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter="tests/*,build-info.json,*.md"
export_path=""
script_export_mode=2
[preset.0.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/export_icon=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
'''
    (target / "export_presets.cfg").write_text(preset)
    (target / "web").mkdir()
    runtime = {r: h for r, h in hashes.items() if r.startswith("addons/cultivation_mode/")}
    runtime_digest = hashlib.sha256(json.dumps(runtime, sort_keys=True).encode()).hexdigest()
    scope = ("v0.2 Tea A/B objects and safe checkpoints plus five motions; formal full Tea retained"
             if entry == DEFAULT_ENTRY else "v0.2 custom entry preview: " + resource_entry)
    catalog_match = re.search(r'^catalog_path\s*=\s*("(?:[^"\\]|\\.)*")\s*$', (ROOT / entry).read_text(), re.MULTILINE)
    catalog_path = json.loads(catalog_match.group(1)) if catalog_match else "res://games/catalog.json"
    if not catalog_path.startswith("res://games/") or ".." in catalog_path or "\\" in catalog_path or not catalog_path.endswith(".json"):
        raise SystemExit("Entry catalog must be a games JSON resource")
    catalog = json.loads((ROOT / catalog_path.removeprefix("res://")).read_text())
    receipt = {"stage": str(target), "source_root": str(ROOT), "entry": resource_entry,
               "title": title, "app_version": app_version, "user_dir": user_dir,
               "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
               "source_dirty": True, "source_hashes": hashes, "runtime_hashes": runtime,
               "shared_runtime_digest": runtime_digest,
               "catalog": catalog_path,
               "packs": [json.loads((ROOT / row["manifest"].removeprefix("res://")).read_text())["id"] for row in catalog],
               "scope": scope,
               "cache_reuse": {"stage": str(reuse_stage) if reuse_stage else "", "import_files": cache_files,
                               "method": "same-volume APFS clone; source hashes verified; changed sources reimported"}}
    (target / "build-info.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    (output / (target.name + "-receipt.json")).write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    return {"stage": str(target), "files": len(hashes), "shared_runtime_digest": runtime_digest}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--reuse-stage", type=Path, help="Optional same-volume APFS source/import reuse; no editor state copied")
    parser.add_argument("--entry", default=DEFAULT_ENTRY,
                        help="Repository-relative scene under scenes/demos (default: %(default)s)")
    parser.add_argument("--title", default=DEFAULT_TITLE, help="Staged application title")
    parser.add_argument("--app-version", default=DEFAULT_APP_VERSION, help="Staged application version")
    parser.add_argument("--user-dir", default=DEFAULT_USER_DIR, help="Staged Godot custom user directory name")
    args = parser.parse_args()
    print(json.dumps(stage(args.output, args.reuse_stage, args.entry, args.title,
                           args.app_version, args.user_dir)))
