"""Build a separate OFL subset for this lab without changing any existing font."""
from pathlib import Path
import argparse,hashlib,json
import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
EXPECTED='050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9'
def main():
 a=argparse.ArgumentParser();a.add_argument('source',type=Path);args=a.parse_args();root=Path(__file__).resolve().parents[2]
 actual=hashlib.sha256(args.source.read_bytes()).hexdigest()
 if actual!=EXPECTED:raise SystemExit('Source font differs from existing verified OFL source: '+actual)
 texts=[p.read_text() for p in (root/'scripts/sword_mocap').glob('*.gd')]+[(root/'assets/data/sword_mocap/study.json').read_text()]
 chars={ord(c) for c in ''.join(texts) if ord(c)>=32}|set(range(32,127))
 f=instantiateVariableFont(TTFont(args.source),{'wght':550},inplace=True);o=subset.Options();o.name_IDs=['*'];o.name_languages=['*'];o.name_legacy=True
 sub=subset.Subsetter(options=o);sub.populate(unicodes=chars);sub.subset(f)
 names={1:'Shu Sword Motion Serif',2:'Regular',3:'Shu Sword Motion Serif v1',4:'Shu Sword Motion Serif',6:'ShuSwordMotionSerif-Regular',16:'Shu Sword Motion Serif',17:'Regular',21:'Shu Sword Motion Serif',22:'Regular'}
 for r in f['name'].names:
  if r.nameID in names:r.string=names[r.nameID].encode(r.getEncoding())
 missing=sorted(chars-set(f.getBestCmap()))
 if missing:raise SystemExit('Missing glyphs '+str(missing))
 out=root/'assets/fonts/ShuSwordMocapSerif.ttf';f.save(out)
 meta={'Source':'https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf','SourceSHA256':actual,'License':'SIL Open Font License 1.1','LicenseFile':'OFL-Serif.txt','DerivedName':'Shu Sword Motion Serif','Tool':'fontTools '+fontTools.__version__,'DerivedSHA256':hashlib.sha256(out.read_bytes()).hexdigest(),'Codepoints':len(chars),'MissingCodepoints':missing}
 (root/'assets/fonts/source-sword-mocap.json').write_text(json.dumps(meta,indent=2)+'\n');print('FONT',len(chars),'glyphs',out.stat().st_size,'bytes, no missing glyphs')
if __name__=='__main__':main()
