"""Subset existing OFL Noto Serif SC source for the isolated animation lab."""
from pathlib import Path
import argparse,hashlib,json
import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
SHA='050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9'
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',type=Path);args=parser.parse_args()
 if hashlib.sha256(args.source.read_bytes()).hexdigest()!=SHA:raise SystemExit('Unrecognized source font')
 root=Path(__file__).resolve().parents[2]
 text=''.join(p.read_text() for p in (root/'scripts/animation_lab').glob('*.gd'))+'蜀山动作方案对照弓步直刺转身斜劈双手棍法'
 chars={ord(c) for c in text if ord(c)>=32}|set(range(32,127))
 font=instantiateVariableFont(TTFont(args.source),{'wght':550},inplace=True)
 options=subset.Options();options.name_IDs=['*'];options.name_languages=['*'];options.name_legacy=True
 sub=subset.Subsetter(options=options);sub.populate(unicodes=chars);sub.subset(font)
 names={1:'Shu Animation Lab Serif',2:'Regular',3:'ShuAnimationLabSerif v1',4:'Shu Animation Lab Serif',6:'ShuAnimationLabSerif-Regular',16:'Shu Animation Lab Serif',17:'Regular',21:'Shu Animation Lab Serif',22:'Regular'}
 for record in font['name'].names:
  if record.nameID in names:record.string=names[record.nameID].encode(record.getEncoding())
 if chars-set(font.getBestCmap()):raise SystemExit('Font coverage incomplete')
 out=root/'assets/fonts/ShuAnimationLabSerif.ttf';font.save(out)
 meta={'Source':'https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf','SourceSHA256':SHA,'License':'SIL Open Font License 1.1','LicenseFile':'OFL-Serif.txt','DerivedName':names[1],'Codepoints':len(chars),'Tool':'fontTools '+fontTools.__version__,'DerivedSHA256':hashlib.sha256(out.read_bytes()).hexdigest(),'Rebuild':'python tools/animation_lab/rebuild_font.py <source-font>'}
 (out.parent/'source-animation-lab.json').write_text(json.dumps(meta,indent=2)+'\n');print('LAB_FONT',len(chars),'codepoints; coverage PASS')
if __name__=='__main__':main()
