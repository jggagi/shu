"""Build the isolated OFL font subset used by hero-martial review scenes."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


EXPECTED_SOURCE_SHA256 = "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"
SOURCE_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf"
FAMILY_NAME = "Shu Hero Martial Serif"
TOOL_VERSION = "1.0.1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def collect_codepoints(root: Path) -> set[int]:
    script_dir = root / "scripts/sword_image_driven"
    scene_paths = [
        root / "scenes/demos/hero_martial_sword.tscn",
        root / "scenes/demos/hero_martial_fist.tscn",
    ]
    text_paths = sorted(script_dir.glob("*.gd")) + scene_paths + [root / "assets/data/rules.json"]
    missing_inputs = [path for path in text_paths if not path.is_file()]
    if missing_inputs:
        names = ", ".join(path.relative_to(root).as_posix() for path in missing_inputs)
        raise SystemExit(f"Missing glyph source files: {names}")

    text = "".join(path.read_text(encoding="utf-8") for path in text_paths)
    return {ord(char) for char in text if ord(char) >= 32} | set(range(32, 127))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="the verified Noto Serif SC variable font")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    source = args.source.expanduser().resolve()
    output_dir = root / "assets/fonts"
    output_font = output_dir / "ShuHeroMartialSerif.ttf"
    output_record = output_dir / "source-hero-martial.json"
    if output_font.exists() or output_record.exists():
        raise SystemExit("Refusing existing hero-martial font output")

    if not source.is_file():
        raise SystemExit(f"Font source does not exist: {args.source}")
    source_hash = sha256_file(source)
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise SystemExit("Unexpected OFL font source SHA256")

    license_path = output_dir / "OFL-Serif.txt"
    if not license_path.is_file():
        raise SystemExit("Missing assets/fonts/OFL-Serif.txt")

    codepoints = collect_codepoints(root)
    font = instantiateVariableFont(TTFont(source), {"wght": 550}, inplace=True)
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)

    names = {
        1: FAMILY_NAME,
        2: "Regular",
        3: FAMILY_NAME + " v1",
        4: FAMILY_NAME,
        6: "ShuHeroMartialSerif-Regular",
        16: FAMILY_NAME,
        17: "Regular",
        21: FAMILY_NAME,
        22: "Regular",
    }
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())

    missing = sorted(codepoints - set(font.getBestCmap()))
    if missing:
        raise SystemExit("Missing glyph codepoints: " + ", ".join(str(codepoint) for codepoint in missing))

    # Detect source changes while the subset was being prepared.
    if sha256_file(source) != source_hash:
        raise SystemExit("Font source changed while building the subset")

    font.save(output_font)
    derived_hash = sha256_file(output_font)
    record = {
        "Source": SOURCE_URL,
        "SourceSHA256": source_hash,
        "License": "SIL Open Font License 1.1",
        "LicenseFile": "OFL-Serif.txt",
        "DerivedName": FAMILY_NAME,
        "DerivedSHA256": derived_hash,
        "Tool": f"fontTools {fontTools.__version__}",
        "ToolVersion": TOOL_VERSION,
        "Codepoints": len(codepoints),
        "MissingCodepoints": missing,
        "RebuildCommandTemplate": "python3 tools/hero_martial/rebuild_review_font.py <verified-source.ttf>",
        "RebuildWorkingDirectory": "repository root",
        "OutputPolicy": "Existing font/record outputs are refused; preserve them before rebuilding in an isolated checkout.",
    }
    output_record.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {output_font.relative_to(root)} ({len(codepoints)} codepoints; no missing glyphs)")


if __name__ == "__main__":
    main()
