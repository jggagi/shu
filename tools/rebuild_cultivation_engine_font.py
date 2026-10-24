"""Subset the existing pinned OFL source for engine UI and both content packs."""
from pathlib import Path
import argparse
import hashlib
import json
import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE_SHA = "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    args = parser.parse_args()
    if hashlib.sha256(args.source.read_bytes()).hexdigest() != SOURCE_SHA:
        raise SystemExit("Unexpected font source; preserve the pinned source/version")
    paths = sorted(p for folder in ["addons/cultivation_mode", "games"]
                   for p in (ROOT / folder).rglob("*") if p.suffix in {".gd", ".json"})
    inputs = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    chars = set(range(32, 127)) | {ord(c) for p in paths for c in p.read_text() if ord(c) >= 32}
    font = instantiateVariableFont(TTFont(args.source), {"wght": 550}, inplace=True)
    required_missing = sorted(chars - set(font.getBestCmap()))
    if required_missing:
        raise SystemExit("Missing codepoints in source: " + repr(required_missing))
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    sub = subset.Subsetter(options=options)
    sub.populate(unicodes=chars)
    sub.subset(font)
    family = "Shu Cultivation Engine Serif"
    names = {1: family, 2: "Regular", 3: family + " v021", 4: family,
             6: "ShuCultivationEngineSerif-Regular", 16: family, 17: "Regular", 21: family, 22: "Regular"}
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    out = ROOT / "assets/fonts/ShuCultivationEngineSerif.ttf"
    font.save(out)
    if chars - set(TTFont(out).getBestCmap()):
        raise SystemExit("Derived font missing required glyphs")
    metadata = {"SourceURL": "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf",
                "SourceSHA256": SOURCE_SHA, "License": "SIL Open Font License 1.1", "LicenseFile": "OFL-Serif.txt",
                "DerivedName": family, "WeightAxisValue": 550, "Tool": "fontTools " + fontTools.__version__,
                "DerivedSHA256": hashlib.sha256(out.read_bytes()).hexdigest(), "RequiredCodepoints": sorted(chars),
                "MissingCodepoints": [], "Inputs": inputs}
    (ROOT / "assets/fonts/source-cultivation-engine.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"glyphs": len(chars), "bytes": out.stat().st_size, "coverage": "PASS"}))

if __name__ == "__main__":
    main()
