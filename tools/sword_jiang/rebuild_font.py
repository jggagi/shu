"""Build a separate OFL subset for this lab without changing any existing font."""
from pathlib import Path
import argparse,hashlib,json
import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
EXPECTED='050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9'
def main():
 a=argparse.ArgumentParser();a.add_argument('source',type=Path);a.add_argument('--style',choices=['original','legacy'],default='original');args=a.parse_args();root=Path(__file__).resolve().parents[2]
 actual=hashlib.sha256(args.source.read_bytes()).hexdigest()
 if actual!=EXPECTED:raise SystemExit('Source font differs from existing verified OFL source: '+actual)
 asset_id='sword_jiang_legacy' if args.style=='legacy' else 'sword_jiang'
 derived='Shu Sword Jiang Legacy Serif' if args.style=='legacy' else 'Shu Sword Jiang Serif'
 basename='ShuSwordJiangLegacySerif' if args.style=='legacy' else 'ShuSwordJiangSerif'
 texts=[(root/'scripts/sword_mocap/comparison.gd').read_text(),(root/f'scenes/demos/{asset_id}_comparison.tscn').read_text(),(root/'assets/data/sword_mocap/study.json').read_text()]
 chars={ord(c) for c in ''.join(texts) if ord(c)>=32}|set(range(32,127))
 f=instantiateVariableFont(TTFont(args.source),{'wght':550},inplace=True);o=subset.Options();o.name_IDs=['*'];o.name_languages=['*'];o.name_legacy=True
 sub=subset.Subsetter(options=o);sub.populate(unicodes=chars);sub.subset(f)
 names={1:derived,2:'Regular',3:derived+' v1',4:derived,6:basename+'-Regular',16:derived,17:'Regular',21:derived,22:'Regular'}
 for r in f['name'].names:
  if r.nameID in names:r.string=names[r.nameID].encode(r.getEncoding())
 missing=sorted(chars-set(f.getBestCmap()))
 if missing:raise SystemExit('Missing glyphs '+str(missing))
 out=root/f'assets/fonts/{basename}.ttf';f.save(out)
 meta={'Source':'https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf','SourceSHA256':actual,'License':'SIL Open Font License 1.1','LicenseFile':'OFL-Serif.txt','DerivedName':derived,'Tool':'fontTools '+fontTools.__version__,'DerivedSHA256':hashlib.sha256(out.read_bytes()).hexdigest(),'Codepoints':len(chars),'MissingCodepoints':missing}
 (root/('assets/fonts/source-sword-jiang-legacy.json' if args.style=='legacy' else 'assets/fonts/source-sword-jiang.json')).write_text(json.dumps(meta,indent=2)+'\n');print('FONT',len(chars),'glyphs',out.stat().st_size,'bytes, no missing glyphs')
if __name__=='__main__':main()
