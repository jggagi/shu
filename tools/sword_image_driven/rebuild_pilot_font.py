"""Create a separate OFL font subset; preserve all existing fonts."""
import argparse, hashlib, json
from pathlib import Path
import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
EXPECTED='050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9'
def main():
    a=argparse.ArgumentParser();a.add_argument('source',type=Path);a.add_argument('--refresh-owned',action='store_true');args=a.parse_args()
    root=Path(__file__).resolve().parents[2]
    actual=hashlib.sha256(args.source.read_bytes()).hexdigest()
    if actual!=EXPECTED:raise SystemExit('Unexpected OFL font source')
    out=root/'assets/fonts/ShuSwordImageSerif.ttf';meta=root/'assets/fonts/source-sword-image.json'
    if out.exists() or meta.exists():
        if not args.refresh_owned or not out.exists() or not meta.exists():raise SystemExit('Refusing existing font output')
        previous=json.loads(meta.read_text())
        if previous.get('SourceSHA256')!=EXPECTED or previous.get('DerivedName')!='Shu Image Motion Serif':raise SystemExit('Not the owned pilot font')
        if hashlib.sha256(out.read_bytes()).hexdigest()!=previous.get('DerivedSHA256'):raise SystemExit('Pilot font changed outside its source record')
    texts=[p.read_text() for p in (root/'scripts/sword_image_driven').glob('*.gd')]+[(root/'assets/data/rules.json').read_text()]
    chars={ord(c) for c in ''.join(texts) if ord(c)>=32}|set(range(32,127))
    f=instantiateVariableFont(TTFont(args.source),{'wght':550},inplace=True)
    opts=subset.Options();opts.name_IDs=['*'];opts.name_languages=['*'];opts.name_legacy=True
    sub=subset.Subsetter(options=opts);sub.populate(unicodes=chars);sub.subset(f)
    family='Shu Image Motion Serif'
    names={1:family,2:'Regular',3:family+' v1',4:family,6:'ShuImageMotionSerif-Regular',16:family,17:'Regular',21:family,22:'Regular'}
    for record in f['name'].names:
        if record.nameID in names:record.string=names[record.nameID].encode(record.getEncoding())
    missing=sorted(chars-set(f.getBestCmap()))
    if missing:raise SystemExit('Missing glyphs '+str(missing))
    f.save(out)
    meta.write_text(json.dumps({'Source':'https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf','SourceSHA256':actual,'License':'SIL Open Font License 1.1','LicenseFile':'OFL-Serif.txt','DerivedName':family,'Tool':'fontTools '+fontTools.__version__,'DerivedSHA256':hashlib.sha256(out.read_bytes()).hexdigest(),'Codepoints':len(chars),'MissingCodepoints':missing},indent=2)+'\n')
    print('Font',len(chars),'codepoints, no missing glyphs')
if __name__=='__main__':main()
