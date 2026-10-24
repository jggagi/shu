"""Build the scene-specific Noto Serif SC subset for the sword-set review."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import unicodedata
from pathlib import Path

EXPECTED_SOURCE_SHA256 = "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"
SOURCE_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf"
DERIVED_NAME = "Shu Sword Sets Serif"
WEIGHT = 550


def sha256_bytes(value: bytes) -> str:
	return hashlib.sha256(value).hexdigest()


def required_codepoints(source_text: str) -> set[int]:
	codepoints = {
		ord(character)
		for character in source_text
		if not unicodedata.category(character).startswith("C")
	}
	codepoints.update(range(32, 127))
	return codepoints


def check_refresh_ownership(font_path: Path, metadata_path: Path) -> None:
	if not font_path.exists() or not metadata_path.exists():
		raise SystemExit("Refusing partial existing sword-sets font output")
	try:
		metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
	except (OSError, json.JSONDecodeError) as error:
		raise SystemExit(f"Refusing unreadable existing font metadata: {error}") from error
	if metadata.get("SourceSHA256") != EXPECTED_SOURCE_SHA256 or metadata.get("DerivedName") != DERIVED_NAME:
		raise SystemExit("Refusing to replace font output not owned by this builder")
	if sha256_bytes(font_path.read_bytes()) != metadata.get("DerivedSHA256"):
		raise SystemExit("Refusing to replace a font changed outside its source record")


def main() -> None:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--source", required=True, type=Path, help="Pinned local NotoSerifSC variable font")
	parser.add_argument("--catalog", required=True, type=Path, help="Absolute input sword-set catalog JSON")
	parser.add_argument("--refresh-owned", action="store_true", help="replace only this builder's unchanged font and metadata")
	args = parser.parse_args()
	try:
		import fontTools
		from fontTools import subset
		from fontTools.ttLib import TTFont
		from fontTools.varLib.instancer import instantiateVariableFont
	except ImportError as error:
		raise SystemExit("fontTools is required to build the font; installation is out of scope") from error

	root = Path(__file__).resolve().parents[2]
	source_path = args.source.expanduser()
	catalog_path = args.catalog.expanduser()
	if not source_path.is_absolute() or not catalog_path.is_absolute():
		raise SystemExit("--source and --catalog must be absolute paths")
	try:
		source_bytes = source_path.read_bytes()
		catalog_bytes = catalog_path.read_bytes()
		catalog_text = catalog_bytes.decode("utf-8")
	except (OSError, UnicodeDecodeError) as error:
		raise SystemExit(f"Cannot read font source or catalog: {error}") from error
	if sha256_bytes(source_bytes) != EXPECTED_SOURCE_SHA256:
		raise SystemExit(f"Unexpected font source SHA256: {sha256_bytes(source_bytes)}")
	try:
		json.loads(catalog_text)
	except json.JSONDecodeError as error:
		raise SystemExit(f"Input catalog is not valid JSON: {error}") from error

	review_source = root / "scripts/hero_lookdev/sword_cycle_review.gd"
	license_path = root / "assets/fonts/OFL-Serif.txt"
	font_path = root / "assets/fonts/ShuSwordSetsSerif.ttf"
	metadata_path = root / "assets/fonts/source-sword-sets.json"
	if not review_source.is_file() or not license_path.is_file():
		raise SystemExit("Sword-set review source or OFL license file is missing")
	if font_path.exists() or metadata_path.exists():
		if not args.refresh_owned:
			raise SystemExit("Refusing existing sword-sets font output; use --refresh-owned only for owned files")
		check_refresh_ownership(font_path, metadata_path)

	player_bytes = review_source.read_bytes()
	player_text = player_bytes.decode("utf-8")
	codepoints = required_codepoints(player_text + "\n" + catalog_text)
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
		6: "ShuSwordSetsSerif-Regular",
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
		raise SystemExit(f"Unexpected instantiated font weight: {font['OS/2'].usWeightClass}")

	buffer = io.BytesIO()
	font.save(buffer)
	derived_bytes = buffer.getvalue()
	metadata = {
		"SourceURL": SOURCE_URL,
		"SourceFile": source_path.name,
		"SourceSHA256": EXPECTED_SOURCE_SHA256,
		"CatalogFile": catalog_path.name,
		"CatalogSHA256": sha256_bytes(catalog_bytes),
		"PlayerSourceSHA256": sha256_bytes(player_bytes),
		"License": "SIL Open Font License 1.1",
		"LicenseFile": "OFL-Serif.txt",
		"DerivedName": DERIVED_NAME,
		"WeightAxisValue": WEIGHT,
		"Tool": f"fontTools {fontTools.__version__}",
		"DerivedSHA256": sha256_bytes(derived_bytes),
		"Codepoints": len(codepoints),
		"RequiredCodepoints": [f"U+{codepoint:04X}" for codepoint in sorted(codepoints)],
		"MissingCodepoints": missing,
	}
	font_path.write_bytes(derived_bytes)
	metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print(f"Built {font_path.name}: {len(codepoints)} codepoints, weight {WEIGHT}, no missing glyphs")
	print(f"Source SHA256:  {EXPECTED_SOURCE_SHA256}")
	print(f"Catalog SHA256: {metadata['CatalogSHA256']}")
	print(f"Derived SHA256: {metadata['DerivedSHA256']}")


if __name__ == "__main__":
	main()
