"""Rebuild the independent scene serif subset with existing fontTools."""
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
    texts = (root / "scripts/stream_teahouse.gd").read_text(encoding="utf-8")
    chars = {ord(c) for c in texts if ord(c) >= 32} | set(range(32,127))
    font = instantiateVariableFont(TTFont(args.font_source), {"wght": 550}, inplace=True)
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    sub = subset.Subsetter(options=options)
    sub.populate(unicodes=chars)
    sub.subset(font)
    names = {1:"Shu Stream Teahouse Serif",2:"Regular",3:"ShuStreamTeahouseSerif v1",
             4:"Shu Stream Teahouse Serif",6:"ShuStreamTeahouseSerif-Regular",
             16:"Shu Stream Teahouse Serif",17:"Regular",21:"Shu Stream Teahouse Serif",22:"Regular"}
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    missing = sorted(chars - set(font.getBestCmap()))
    if missing:
        raise SystemExit(f"Missing codepoints: {missing}")
    output = root / "assets/fonts/ShuStreamTeahouseSerif.ttf"
    font.save(output)
    meta = {"Source":"https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf",
            "SourceSHA256":SOURCE_SHA256,"Name":"Noto Serif SC","License":"SIL Open Font License 1.1",
            "LicenseFile":"OFL-Serif.txt","DerivedName":"Shu Stream Teahouse Serif",
            "Modifications":"Subset to stream_teahouse.gd UI; static weight 550; renamed.",
            "Codepoints":len(chars),"Tool":"fontTools " + fontTools.__version__,
            "Rebuild":"python tools/rebuild_stream_teahouse_font.py <source-font>",
            "DerivedSHA256":hashlib.sha256(output.read_bytes()).hexdigest()}
    (root / "assets/fonts/source-stream-teahouse.json").write_text(json.dumps(meta,indent=2)+"\n")
    print(f"STREAM_TEAHOUSE_FONT: {len(chars)} codepoints; coverage PASS")
if __name__ == "__main__":
    main()
