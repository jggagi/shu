"""Build one OFL font subset covering the cultivation host and five sword clips."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import unicodedata
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[2]
PINNED_SHA = '050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9'
NAME = 'Shu Cultivation Sword Serif'


def main(source: Path, refresh: bool) -> None:
    content = source.read_bytes()
    assert hashlib.sha256(content).hexdigest() == PINNED_SHA
    font_path = ROOT / 'assets/fonts/ShuCultivationSwordSerif.ttf'
    record_path = ROOT / 'assets/fonts/source-cultivation-sword.json'
    if font_path.exists() or record_path.exists():
        assert refresh and font_path.is_file() and record_path.is_file()
        old = json.loads(record_path.read_text())
        assert old['DerivedName'] == NAME and old['SourceSHA256'] == PINNED_SHA
        assert hashlib.sha256(font_path.read_bytes()).hexdigest() == old['DerivedSHA256']
    inputs = sorted([*ROOT.glob('scripts/*.gd'),
                     ROOT / 'scripts/hero_lookdev/formal_sword_practice.gd',
                     *ROOT.glob('assets/data/*.json'), ROOT / 'assets/art/jiang_sword_cycle/sets.json'])
    inputs_hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    text = '\n'.join(p.read_text() for p in inputs)
    codes = {ord(c) for c in text if not unicodedata.category(c).startswith('C')} | set(range(32, 127))
    font = instantiateVariableFont(TTFont(io.BytesIO(content)), {'wght': 550}, inplace=True)
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_languages = ['*']
    options.name_legacy = True
    ss = subset.Subsetter(options=options)
    ss.populate(unicodes=codes)
    ss.subset(font)
    missing = codes.difference(font.getBestCmap())
    assert not missing, sorted(missing)
    for record in font['name'].names:
        names = {1: NAME, 2: 'Regular', 3: NAME + ' v1', 4: NAME,
                 6: 'ShuCultivationSwordSerif-Regular', 16: NAME, 17: 'Regular', 21: NAME, 22: 'Regular'}
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    dest = io.BytesIO()
    font.save(dest)
    data = dest.getvalue()
    font_path.write_bytes(data)
    meta = {'SourceURL': 'https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf',
            'SourceSHA256': PINNED_SHA, 'DerivedName': NAME, 'DerivedSHA256': hashlib.sha256(data).hexdigest(),
            'License': 'SIL Open Font License 1.1', 'LicenseFile': 'OFL-Serif.txt', 'WeightAxisValue': 550,
            'RequiredCodepoints': sorted(codes), 'MissingCodepoints': [], 'Inputs': inputs_hashes}
    record_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'font': str(font_path), 'glyphs': len(codes), 'bytes': len(data), 'sha256': meta['DerivedSHA256']}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--refresh-owned', action='store_true')
    args = parser.parse_args()
    main(args.source, args.refresh_owned)
