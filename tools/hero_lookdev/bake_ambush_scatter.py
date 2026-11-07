#!/usr/bin/env python3
"""Bake real ProtonScatter modifiers in an isolated, disposable Godot project.

No plugin, demo mesh, or demo texture is copied into the game's runtime tree.
The fixed archive can be fetched from SOURCE_URL if the local source is absent.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

COMMIT = "7198cc00078ebde61307578137c3f35223c6e438"
SOURCE_URL = f"https://github.com/HungryProton/scatter/archive/{COMMIT}.zip"
ZIP_SHA256 = "485295fa4a97cb54bcd20d1b1304ed8a2fc0b28fe3215a07be62d26df9208d5f"
SEED = 20261024
GODOT_SOURCE = Path(__file__).with_suffix(".gd").read_text()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args: list[str], logfile: Path) -> dict:
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    logfile.write_text(result.stdout)
    issues = [line for line in result.stdout.splitlines()
              if re.search(r"SCRIPT ERROR|^\s*ERROR:|^\s*WARNING:", line)]
    if result.returncode or issues:
        raise RuntimeError(f"Godot authoring failed: {args}\n{result.stdout}")
    return {"command": args, "exit_code": result.returncode,
            "issues": issues, "log": str(logfile)}


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-zip", type=Path,
                        default=root / ".local/sources/proton-scatter-7198cc0/source.zip")
    parser.add_argument("--authoring-dir", type=Path,
                        default=root / ".local/tools/songfeng-scatter-authoring")
    parser.add_argument("--godot", default="/opt/agent-creator/godot/bin/godot")
    args = parser.parse_args()
    archive = args.source_zip.resolve()
    if not archive.is_file():
        raise FileNotFoundError(f"Fetch {SOURCE_URL} to {archive}; expected SHA256 {ZIP_SHA256}")
    if sha(archive) != ZIP_SHA256:
        raise ValueError("The fixed ProtonScatter source archive hash does not match")
    project = args.authoring_dir.resolve()
    project.mkdir(parents=True, exist_ok=True)
    prefix = f"scatter-{COMMIT}/addons/proton_scatter/"
    copied_hashes: dict[str, str] = {}
    with zipfile.ZipFile(archive) as source:
        for info in source.infolist():
            if not info.filename.startswith(prefix) or info.is_dir():
                continue
            relative = Path(info.filename[len(prefix):])
            if ".." in relative.parts or relative.is_absolute():
                raise ValueError("Unsafe source archive path")
            # The demo includes separately licensed assets; none are needed to bake.
            if relative.parts[0] == "demos":
                continue
            dest = project / "addons/proton_scatter" / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(source.read(info))
            copied_hashes[dest.relative_to(project).as_posix()] = sha(dest)
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Songfeng Scatter Authoring"\n'
        'config/features=PackedStringArray("4.7", "GL Compatibility")\n'
        '[songfeng_authoring]\nonly=true\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    (project / "bake.gd").write_text(GODOT_SOURCE)
    commands = [run([args.godot, "--headless", "--path", str(project),
                     "--editor", "--import", "--quit"], project / "import.log")]
    outputs: list[Path] = []
    for index in range(2):
        output = project / f"baked-{index}.json"
        commands.append(run([args.godot, "--headless", "--path", str(project),
                             "--script", "res://bake.gd", "--", str(output)],
                            project / f"bake-{index}.log"))
        outputs.append(output)
    if outputs[0].read_bytes() != outputs[1].read_bytes():
        raise AssertionError("The same plugin seed did not produce identical output")
    layout = json.loads(outputs[0].read_text())
    rows = layout["instances"]
    assert len(rows) == 52 and len(rows) <= 100
    assert sum(row["kind"] == "grass" for row in rows) == 36
    assert sum(row["kind"] == "rock" for row in rows) == 16
    for row in rows:
        x, y, z = row["at"]
        assert not (abs(x) < 5.6 and abs(z) < 4.4)
        assert 5.8 <= abs(x) <= 8.2 and -7.0 <= z <= 5.5
        assert not (z > 2.0 and -6.0 < x < 6.0)
        assert abs(y) < 1e-6
        low, high = (0.25, 0.45) if row["kind"] == "grass" else (0.15, 0.35)
        assert low - 1e-6 <= row["scale"] <= high + 1e-6
    target = root / "assets/art/mountain_ambush/environment"
    target.mkdir(parents=True, exist_ok=True)
    layout_path = target / "scatter-layout.json"
    layout_path.write_text(json.dumps(layout, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    license_path = target / "PROTON-LICENSE.txt"
    license_path.write_bytes((project / "addons/proton_scatter/LICENSE").read_bytes())
    receipt = {
        "tool": "ProtonScatter", "author": "HungryProton", "license": "MIT",
        "repository": "https://github.com/HungryProton/scatter", "commit": COMMIT,
        "source_url": SOURCE_URL, "source_archive_sha256": ZIP_SHA256,
        "source_archive_bytes": archive.stat().st_size,
        "license_path": license_path.relative_to(root).as_posix(),
        "license_sha256": sha(license_path),
        "authoring_project": project.relative_to(root).as_posix() if project.is_relative_to(root) else str(project),
        "authoring_only": True,
        "excluded": "All addon/demos files, including Textures.com demo assets; no plugin in game runtime",
        "recipe": {"seed": SEED, "rock_seed_offset": 997,
                   "api": "ProtonScatterModifierStack.start_update(scatter, scatter.domain)",
                   "domain": "Two original ProtonScatterPathShape ribbons plus negative ProtonScatterBoxShape",
                   "modifiers": ["Create Inside (Random)", "Edit Scale (Multiply)", "Randomize Transforms"],
                   "central_exclusion": {"abs_x_less_than": 5.6, "abs_z_less_than": 4.4},
                   "counts": {"grass": 36, "rock": 16}},
        "output": layout_path.relative_to(root).as_posix(),
        "output_sha256": sha(layout_path), "instances": len(rows),
        "validation": {"two_bakes_byte_identical": True, "central_exclusion": True,
                       "negative_box_overrides_positive_path": True,
                       "roadside_bounds": True, "scale_ranges": True, "no_foreground_center": True},
        "source_hashes": {p.relative_to(root).as_posix(): sha(p) for p in [Path(__file__), Path(__file__).with_suffix(".gd")]},
        "plugin_files_copied_without_modification": copied_hashes,
        "reproduce": "python3 tools/hero_lookdev/bake_ambush_scatter.py",
        "commands_receipt": (project / "commands.json").relative_to(root).as_posix() if project.is_relative_to(root) else str(project / "commands.json"),
    }
    (project / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
    (target / "source-scatter.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"instances": len(rows), "output_sha256": sha(layout_path),
                      "two_bakes_byte_identical": True, "authoring_project": str(project)}))


if __name__ == "__main__":
    main()
