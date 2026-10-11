"""Check clean-matte asset preservation and known backdrop removal without inference."""
from pathlib import Path
import copy, hashlib, json
import numpy as np
from PIL import Image

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    root=Path(__file__).resolve().parents[1]
    old=root/'assets/art/sword_image_driven_v1'; new=root/'assets/art/sword_image_clean_matte_v1'
    a=json.loads((old/'atlas.json').read_text()); b=json.loads((new/'atlas.json').read_text())
    source=json.loads((new/'source.json').read_text()); checks=[]
    def check(ok,label):
        checks.append({'ok':bool(ok),'label':label})
        if not ok:raise AssertionError(label)
    for name in ('fps','frame_count','duration','width','height'):
        check(a[name]==b[name],name+' remains exact')
    check(sha(old/'source.mp4')==a['source_video_sha256']==source['original_video_sha256'],'original clip SHA preserved')
    check(sha(old/'atlas.json')==source['original_manifest_sha256'],'source manifest SHA preserved')
    check(sha(root/'assets/data/sword_image_matte_cleanup.json')==source['authored_regions_sha256'],'reviewed region metadata SHA matches')
    pages={}
    for name in sorted(old.glob('atlas-*.png')):
        original=np.array(Image.open(name)); clean=np.array(Image.open(new/name.name))
        check(original.shape==clean.shape,'atlas cell layout fixed: '+name.name)
        check(np.array_equal(original[:,:,:3],clean[:,:,:3]),'entire atlas RGB exact: '+name.name)
        check(np.all(clean[:,:,3]<=original[:,:,3]),'alpha never adds new backdrop: '+name.name)
        check(sha(new/name.name)==b['files_sha256']['res://'+str((new/name.name).relative_to(root))],'clean atlas receipt hash: '+name.name)
        pages[name.name]=(original,clean)
    for i,(original,clean) in enumerate(zip(a['frames'],b['frames'])):
        left=copy.deepcopy(original);right=copy.deepcopy(clean);left.pop('path');right.pop('path')
        check(left==right,'frame geometry/anchor metadata exact: %d'%i)
        x,y,w,h=original['region'];oldpage,newpage=pages[Path(original['path']).name]
        rgba=oldpage[y:y+h,x:x+w]; result=newpage[y:y+h,x:x+w]
        check(np.array_equal(rgba[:,155:],result[:,155:]),'face/hands/sword right region exact: %d'%i)
        check(np.array_equal(rgba[:180],result[:180]),'upper hair region exact: %d'%i)
        check(np.array_equal(rgba[420:],result[420:]),'lower robe/feet region exact: %d'%i)
        if i<24:check(np.array_equal(rgba,result),'early pose entirely exact: %d'%i)
        if i==35:
            check(all(result[py,px,3]==rgba[py,px,3] for px,py in [(17,282),(20,280),(12,285)]),'frame35 flying ribbon keeps original opacity')
        if i==40:
            check(rgba[235:245,10:30,3].min()==255,'known original backdrop pocket fully opaque')
            check(result[235:245,10:30,3].mean()<16,'known backdrop pocket now nearly transparent')
            for px,py,label in [(80,230,'hair/ribbon'),(17,282,'flying ribbon'),(87,386,'robe')]:
                check(int(result[py,px,3])>=int(rgba[py,px,3])-16,'audited foreground retained: '+label)
    print('SWORD_IMAGE_MATTE_ASSETS: %d checks, 0 failures'%len(checks))
if __name__=='__main__':main()
