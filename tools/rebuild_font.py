"""Regenerate the D01 serif subset; development dependency: existing fontTools (version recorded in source-serif.json)."""
from pathlib import Path
import argparse
import hashlib
import json

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

SOURCE_SHA256 = '050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('font_source', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if hashlib.sha256(args.font_source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise SystemExit('Unexpected source font SHA256; review source/version before updating')
    texts = [p.read_text(encoding='utf-8') for folder in ['scripts', 'assets/data'] for p in (root / folder).rglob('*') if p.suffix in ['.gd', '.json']]
    texts.append((root / 'project.godot').read_text(encoding='utf-8'))
    chars = {ord(c) for c in ''.join(texts) if ord(c) >= 32} | set(range(32,127))
    font = instantiateVariableFont(TTFont(args.font_source), {'wght': 550}, inplace=True)
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_languages = ['*']
    options.name_legacy = True
    sub = subset.Subsetter(options=options)
    sub.populate(unicodes=chars)
    sub.subset(font)
    renamed = {1:'Shu Demo Serif', 2:'Regular', 3:'Shu Demo Serif D01', 4:'Shu Demo Serif', 6:'ShuDemoSerif-Regular', 16:'Shu Demo Serif', 17:'Regular', 21:'Shu Demo Serif', 22:'Regular'}
    for record in font['name'].names:
        if record.nameID in renamed:
            record.string = renamed[record.nameID].encode(record.getEncoding())
    out = root / 'assets/fonts/ShuDemoSerif.ttf'
    font.save(out)
    present = set(font.getBestCmap())
    missing = sorted(c for c in chars if c not in present)
    if missing:
        raise SystemExit(f'Missing codepoints: {missing}')
    metadata = {'Source':'https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf', 'Name':'Noto Serif SC', 'SourceSHA256':SOURCE_SHA256, 'License':'SIL Open Font License 1.1', 'LicenseFile':'OFL-Serif.txt', 'DerivedName':'Shu Demo Serif', 'Modifications':'Subset to D01 current code/data characters, static weight 550, renamed family.', 'Tool':'fontTools ' + fontTools.__version__, 'Codepoints':len(chars), 'DerivedSHA256':hashlib.sha256(out.read_bytes()).hexdigest()}
    (root / 'assets/fonts/source-serif.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(f'Serif subset: {len(chars)} codepoints; coverage PASS; {out.stat().st_size} bytes')

if __name__ == '__main__':
    main()
