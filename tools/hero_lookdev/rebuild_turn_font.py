"""Build the dedicated serif subset used by the Jiang turn scene review."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import unicodedata
from pathlib import Path

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


EXPECTED_SOURCE_SHA256 = "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"
SOURCE_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf"
DERIVED_NAME = "Shu Turn Review Serif"
WEIGHT = 550


def _required_codepoints(source_text: str) -> set[int]:
    """Include printable source characters and the complete requested ASCII range."""
    codepoints = {
        ord(character)
        for character in source_text
        if not unicodedata.category(character).startswith("C")
    }
    codepoints.update(range(32, 127))
    return codepoints


def _check_refresh_ownership(font_path: Path, metadata_path: Path) -> None:
    if not font_path.exists() or not metadata_path.exists():
        raise SystemExit("Refusing partial existing font output; both owned files are required")
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Refusing unreadable existing metadata: {error}") from error
    if (
        metadata.get("SourceSHA256") != EXPECTED_SOURCE_SHA256
        or metadata.get("DerivedName") != DERIVED_NAME
    ):
        raise SystemExit("Refusing to replace an output not owned by this turn-review builder")
    current_hash = hashlib.sha256(font_path.read_bytes()).hexdigest()
    if current_hash != metadata.get("DerivedSHA256"):
        raise SystemExit("Refusing to replace a font changed outside its source record")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="Pinned NotoSerifSC variable font")
    parser.add_argument(
        "--refresh-owned",
        action="store_true",
        help="replace outputs only when their existing metadata and font hash match this builder",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    source_path = args.source.expanduser()
    try:
        source_bytes = source_path.read_bytes()
    except OSError as error:
        raise SystemExit(f"Cannot read font source {source_path}: {error}") from error
    source_sha256 = hashlib.sha256(source_bytes).hexdigest()
    if source_sha256 != EXPECTED_SOURCE_SHA256:
        raise SystemExit(f"Unexpected font source SHA256: {source_sha256}")

    review_source = root / "scripts/hero_lookdev/turn_scene_review.gd"
    license_path = root / "assets/fonts/OFL-Serif.txt"
    font_path = root / "assets/fonts/ShuTurnReviewSerif.ttf"
    metadata_path = root / "assets/fonts/source-turn-review.json"
    if not review_source.is_file():
        raise SystemExit(f"Missing review script: {review_source}")
    if not license_path.is_file():
        raise SystemExit(f"Missing OFL license text: {license_path}")

    if font_path.exists() or metadata_path.exists():
        if not args.refresh_owned:
            raise SystemExit("Refusing existing turn-review font output; use --refresh-owned only for verified owned files")
        _check_refresh_ownership(font_path, metadata_path)

    codepoints = _required_codepoints(review_source.read_text(encoding="utf-8"))
    font = TTFont(io.BytesIO(source_bytes))
    font = instantiateVariableFont(font, {"wght": WEIGHT}, inplace=True)

    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)

    names = {
        1: DERIVED_NAME,
        2: "Regular",
        3: f"{DERIVED_NAME} v1",
        4: DERIVED_NAME,
        6: "ShuTurnReviewSerif-Regular",
        16: DERIVED_NAME,
        17: "Regular",
        21: DERIVED_NAME,
        22: "Regular",
    }
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())

    missing = sorted(codepoints.difference(font.getBestCmap()))
    if missing:
        raise SystemExit("Missing glyphs: " + ", ".join(f"U+{codepoint:04X}" for codepoint in missing))
    if font["OS/2"].usWeightClass != WEIGHT:
        raise SystemExit(f"Unexpected instantiated weight: {font['OS/2'].usWeightClass}")

    output_buffer = io.BytesIO()
    font.save(output_buffer)
    derived_bytes = output_buffer.getvalue()
    derived_sha256 = hashlib.sha256(derived_bytes).hexdigest()
    metadata = {
        "SourceURL": SOURCE_URL,
        "SourceFile": source_path.name,
        "SourceSHA256": source_sha256,
        "License": "SIL Open Font License 1.1",
        "LicenseFile": "OFL-Serif.txt",
        "DerivedName": DERIVED_NAME,
        "WeightAxisValue": WEIGHT,
        "Tool": f"fontTools {fontTools.__version__}",
        "DerivedSHA256": derived_sha256,
        "Codepoints": len(codepoints),
        "RequiredCodepoints": [f"U+{codepoint:04X}" for codepoint in sorted(codepoints)],
        "MissingCodepoints": missing,
    }

    font_path.write_bytes(derived_bytes)
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Built {font_path.name}: {len(codepoints)} codepoints, weight {WEIGHT}, no missing glyphs")
    print(f"Source SHA256:  {source_sha256}")
    print(f"Derived SHA256: {derived_sha256}")


if __name__ == "__main__":
    main()
