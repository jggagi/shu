"""Build the standalone demo's serif subset; uses existing fontTools, no installation.
Usage: python tools/rebuild_back_mountain_font.py <original NotoSerifSC variable font>
"""
from pathlib import Path
import argparse
import hashlib
import json
import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

SOURCE_SHA256 = "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("font_source", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if hashlib.sha256(args.font_source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise SystemExit("Unexpected source SHA256")
    files = [root / "scripts/back_mountain_training.gd", root / "scripts/back_mountain_ambient_life.gd", root / "scripts/demo_state.gd",
             root / "assets/data/rules.json", root / "assets/data/back_mountain_training.json"]
    chars = {ord(c) for p in files for c in p.read_text(encoding="utf-8") if ord(c) >= 32}
    chars |= set(range(32, 127))
    font = instantiateVariableFont(TTFont(args.font_source), {"wght": 550}, inplace=True)
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    sub = subset.Subsetter(options=options)
    sub.populate(unicodes=chars)
    sub.subset(font)
    names = {1:"Shu Back Mountain Serif", 2:"Regular", 3:"ShuBackMountainSerif Demo",
             4:"Shu Back Mountain Serif", 6:"ShuBackMountainSerif-Regular",
             16:"Shu Back Mountain Serif", 17:"Regular", 21:"Shu Back Mountain Serif", 22:"Regular"}
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    missing = sorted(chars - set(font.getBestCmap()))
    if missing:
        raise SystemExit(f"Missing codepoints: {missing}")
    out = root / "assets/fonts/ShuBackMountainSerif.ttf"
    font.save(out)
    record = {"Source":"https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf",
              "SourceSHA256":SOURCE_SHA256, "Name":"Noto Serif SC",
              "License":"SIL Open Font License 1.1", "LicenseFile":"OFL-Serif.txt",
              "DerivedName":"Shu Back Mountain Serif", "Codepoints":len(chars),
              "Modifications":"Subset to standalone back mountain controller/ambient adapter/state/data; weight 550; renamed.",
              "Tool":"fontTools " + fontTools.__version__,
              "Rebuild":"python tools/rebuild_back_mountain_font.py <source-font>",
              "DerivedSHA256":hashlib.sha256(out.read_bytes()).hexdigest()}
    (root / "assets/fonts/source-back-mountain.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"BACK_MOUNTAIN_FONT: {len(chars)} codepoints; coverage PASS; {out.stat().st_size} bytes")
if __name__ == "__main__":
    main()
