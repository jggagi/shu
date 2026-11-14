"""Derive deterministic RGBA architecture layers from the original Qwen atlas.
No generation or network. Pure-background colour matting; preserve source RGB
away from the boundary. The downloaded original remains unchanged.
"""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'art/source/chengdu-illustrated-street-20261112/architecture.png'
OUT=ROOT/'assets/art/chengdu_illustrated_street_20261112'
BOXES={
 'tea_shop':(16,112,710,738), 'two_storey':(750,26,1355,740),
 'workshop':(1370,180,2035,738), 'courtyard_tree':(20,742,700,1505),
 'home':(735,885,1350,1500), 'corner_shop':(1410,880,2010,1510)}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run():
 OUT.mkdir(parents=True,exist_ok=True)
 im=Image.open(SOURCE).convert('RGB');rows={}
 for name,box in BOXES.items():
  rgb=np.asarray(im.crop(box)).astype(float)
  # Pink background is identifiable by hue, including holes in tree foliage.
  # Use a broad hue key, then reconstruct edge RGB against the measured matte.
  background=np.median(rgb[:12].reshape(-1,3),axis=0)
  # Key by magenta hue independently of brightness: dark magenta outlines
  # must not survive as opaque rims, particularly around tiny tree leaves.
  strength=np.minimum(rgb[...,0],rgb[...,2])-rgb[...,1]
  magenta_hue=rgb[...,0]>rgb[...,2]*.85
  alpha=np.where(magenta_hue,np.clip((10.0-strength)/8.0,0,1),1.0)
  alpha=np.where(alpha<.08,0,alpha)
  cleaned=rgb.copy()
  edge=(alpha>0)&(alpha<.999)
  cleaned[edge,2]=np.minimum(cleaned[edge,2],cleaned[edge,1]*1.1)
  cleaned[edge,0]=np.minimum(cleaned[edge,0],cleaned[edge,1]*1.35)
  a=np.round(alpha*255).astype('uint8')
  mask=a>32;ys,xs=np.where(mask)
  assert len(xs)>10000,name
  crop=(max(int(xs.min())-4,0),max(int(ys.min())-4,0),min(int(xs.max())+5,a.shape[1]),min(int(ys.max())+5,a.shape[0]))
  rgba=np.dstack([np.round(cleaned).astype('uint8'),a]);cut=Image.fromarray(rgba).crop(crop)
  # A four-pixel edge dilation supplies RGB beneath transparent texels for mipmaps.
  arr=np.asarray(cut).copy();opaque=arr[...,3]>32
  from PIL import ImageFilter
  for channel in range(3):
   dilated=np.asarray(Image.fromarray(np.where(opaque,arr[...,channel],0).astype('uint8')).filter(ImageFilter.MaxFilter(9)))
   arr[...,channel]=np.where(opaque,arr[...,channel],dilated)
  cut=Image.fromarray(arr);dest=OUT/(name+'.png');cut.save(dest)
  a=np.asarray(cut)[...,3];yy,xx=np.where(a>128)
  contact=(yy>=yy.max()-6);anchor_x=float(np.median(xx[contact]))
  rows[name]={'path':'res://'+str(dest.relative_to(ROOT)),'source_box':list(box),'crop':list(crop),'size':list(cut.size),'anchor_px':[anchor_x,float(yy.max())],'alpha_zero':int((a==0).sum()),'alpha_partial':int(((a>0)&(a<255)).sum()),'alpha_opaque':int((a==255).sum()),'sha256':sha(dest)}
 result={'schema_version':1,'source':str(SOURCE.relative_to(ROOT)),'source_sha256':sha(SOURCE),'method':'Measured magenta colour matte; edge unmixing; preserved interior RGB; 4px RGB dilation; explicit per-cell rectangles and bottom contact anchors. Original provider PNG unchanged.','layers':rows}
 (OUT/'layers.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({k:v['size'] for k,v in rows.items()}))
if __name__=='__main__':run()
