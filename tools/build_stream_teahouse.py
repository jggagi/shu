"""Export the isolated Streamside Tea Pavilion, preserving the main project's entry point.
Usage: python tools/build_stream_teahouse.py --godot <Godot 4.7.2 binary>
Builds Web and Windows under .local/build/stream-teahouse/.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

FILES = [
    "scenes/demos/stream_teahouse.tscn",
    "scripts/stream_teahouse.gd", "scripts/stream_teahouse_cat.gd",
    "scripts/environment_presenter.gd", "scripts/tingyu_cat_desk_motion.gd",
    "scripts/cat_resident_motion.gd",
    "assets/data/stream_teahouse.json",
    "assets/shaders/stream_grade.gdshader", "assets/shaders/stream_atmosphere.gdshader",
    "assets/shaders/stream_water.gdshader",
    "assets/shaders/stream_waterfall.gdshader", "assets/shaders/stream_waterfall_mist.gdshader",
    "assets/art/stream_teahouse/stream-teahouse-v1.png",
    "assets/art/stream_teahouse/source.json",
    "assets/art/ambient_life/orange-cat-painterly-v2.png",
    "assets/art/ambient_life/orange-cat-layout-v2.json",
    "assets/art/ambient_life/tingyu-cat-desk-v1.png",
    "assets/art/ambient_life/tingyu-cat-desk-layout-v1.json",
    "assets/art/ui/cat-pet-cursor-v2.svg", "assets/art/icon.svg",
    "assets/fonts/ShuStreamTeahouseSerif.ttf",
    "assets/fonts/source-stream-teahouse.json",
    "assets/fonts/OFL-Serif.txt", "assets/GODOT-LICENSE.txt", "assets/GODOT-NOTICES.txt",
]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    expected = (root / ".engine-version").read_text().strip()
    version = subprocess.check_output([args.godot, "--version"], text=True).strip()
    if not version.startswith(expected + ".stable"):
        raise SystemExit(f"Expected Godot {expected}.stable, got {version}")
    output = root / ".local/build/stream-teahouse"
    stage = output / "project"
    stage.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for relative in FILES:
        source = root / relative
        target = stage / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        hashes[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
    project = (root / "project.godot").read_text()
    project = project.replace('res://scenes/main.tscn', 'res://scenes/demos/stream_teahouse.tscn')
    project = project.replace('config/name="蜀山行记 · 听雨廊环境 v1"', 'config/name="溪边茶亭 · 独立试玩 v1.3"')
    project = project.replace('config/version="0.1.10-tingyu-environment-local"', 'config/version="0.1.3-stream-teahouse-local"')
    (stage / "project.godot").write_text(project, encoding="utf-8")
    (stage / "export_presets.cfg").write_text((root / "export_presets.cfg").read_text()
        .replace("Shu - Cultivation Demo", "Shu - Streamside Tea Pavilion")
        .replace("Shu - Return Sword Demo", "Shu - Streamside Tea Pavilion"), encoding="utf-8")
    subprocess.run([args.godot, "--headless", "--editor", "--path", str(stage), "--import"], check=True)
    for preset, folder, filename in [
        ("Web", "web", "index.html"),
        ("Windows Desktop", "windows", "StreamTeahouse.exe"),
    ]:
        destination = output / folder
        destination.mkdir(parents=True, exist_ok=True)
        subprocess.run([args.godot, "--headless", "--path", str(stage),
                        "--export-release", preset, str(destination / filename)], check=True)
        licenses = destination / "licenses"
        licenses.mkdir(exist_ok=True)
        for relative in ["assets/fonts/OFL-Serif.txt", "assets/GODOT-LICENSE.txt", "assets/GODOT-NOTICES.txt"]:
            shutil.copy2(root / relative, licenses / Path(relative).name)
    receipt = {"engine": version, "main_scene": "res://scenes/demos/stream_teahouse.tscn",
               "source_files_sha256": hashes,
               "scope": "isolated local Web and Windows exports; no main-project changes or publication"}
    (output / "build-info.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"STREAM_TEAHOUSE_BUILD: Web and Windows exported to {output}")

if __name__ == "__main__":
    main()
