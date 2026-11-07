"""Build the ambush-only OFL font from the project's pinned original source."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE_SHA = "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    args = parser.parse_args()
    if hashlib.sha256(args.source.read_bytes()).hexdigest() != SOURCE_SHA:
        raise SystemExit("Expected the existing pinned Noto Serif SC source")
    paths = sorted((ROOT / "addons/cultivation_mode").glob("ambush*.gd"))
    paths += sorted((ROOT / "addons/cultivation_mode").glob("martial*.gd"))
    paths += sorted(p for p in (ROOT / "assets/data/martial_workshop").glob("**/*.json") if p.name != "source-workshop.json")
    paths += sorted((ROOT / "games/shu_mountain_ambush").glob("*.json"))
    chars = set(range(32, 127)) | {ord(c) for p in paths for c in p.read_text() if ord(c) >= 32}
    font = instantiateVariableFont(TTFont(args.source), {"wght": 550}, inplace=True)
    missing = chars - set(font.getBestCmap())
    if missing:
        raise SystemExit(f"Source missing glyphs: {sorted(missing)}")
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    operation = subset.Subsetter(options=options)
    operation.populate(unicodes=chars)
    operation.subset(font)
    family = "Shu Ambush Serif"
    names = {1: family, 2: "Regular", 3: family + " v01", 4: family,
             6: "ShuAmbushSerif-Regular", 16: family, 17: "Regular", 21: family, 22: "Regular"}
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    output = ROOT / "assets/fonts/ShuAmbushSerif.ttf"
    font.save(output)
    if chars - set(TTFont(output).getBestCmap()):
        raise SystemExit("Derived font coverage failure")
    metadata = {
        "SourceURL": "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf",
        "SourceSHA256": SOURCE_SHA, "License": "SIL Open Font License 1.1",
        "LicenseFile": "OFL-Serif.txt", "DerivedName": family, "WeightAxisValue": 550,
        "Tool": "fontTools " + fontTools.__version__,
        "DerivedSHA256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "RequiredCodepoints": sorted(chars), "MissingCodepoints": [],
        "Inputs": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
    }
    (ROOT / "assets/fonts/source-ambush.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"glyphs": len(chars), "bytes": output.stat().st_size, "coverage": "PASS"}))


if __name__ == "__main__":
    main()
