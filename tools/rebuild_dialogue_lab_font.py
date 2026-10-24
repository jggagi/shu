"""Build an OFL subset for the isolated dialogue lab using the pinned local font."""
import argparse
import hashlib
import json
from pathlib import Path
import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE_SHA = '050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9'

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    if hashlib.sha256(args.source.read_bytes()).hexdigest() != SOURCE_SHA:
        raise SystemExit('Pinned font hash mismatch')
    paths = sorted(p for folder in ['scripts/dialogue_tools_lab','games/dialogue_tools_sample','addons/cultivation_mode'] for p in (ROOT / folder).rglob('*') if p.suffix in ['.gd','.json','.dialogue','.dtl','.tscn','.tres','.dch'])
    chars = set(range(32,127)) | {ord(c) for p in paths for c in p.read_text() if ord(c)>=32}
    font = instantiateVariableFont(TTFont(args.source), {'wght':550}, inplace=True)
    if chars - set(font.getBestCmap()):
        raise SystemExit('Source lacks required glyphs')
    options = subset.Options()
    options.name_IDs=['*'];options.name_languages=['*'];options.name_legacy=True
    s = subset.Subsetter(options=options);s.populate(unicodes=chars);s.subset(font)
    family = 'Shu Dialogue Lab Serif'
    names={1:family,2:'Regular',3:family+' v010',4:family,6:'ShuDialogueLabSerif-Regular',16:family,17:'Regular',21:family,22:'Regular'}
    for rec in font['name'].names:
        if rec.nameID in names:
            rec.string=names[rec.nameID].encode(rec.getEncoding())
    output=ROOT/'assets/fonts/ShuDialogueLabSerif.ttf';font.save(output)
    if chars-set(TTFont(output).getBestCmap()):
        raise SystemExit('Subset lacks required glyphs')
    receipt={'SourceURL':'https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf','SourceSHA256':SOURCE_SHA,'License':'SIL Open Font License 1.1','LicenseFile':'OFL-Serif.txt','DerivedName':family,'DerivedSHA256':hashlib.sha256(output.read_bytes()).hexdigest(),'Tool':'fontTools '+fontTools.__version__,'RequiredCodepoints':sorted(chars),'MissingCodepoints':[],'Inputs':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
    (ROOT/'assets/fonts/source-dialogue-lab.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'glyphs':len(chars),'bytes':output.stat().st_size,'coverage':'PASS'}))
