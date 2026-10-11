"""Check source motion, generated resources, and protected checkouts without Godot."""
from pathlib import Path
import hashlib,json,math,struct
ROOT=Path(__file__).resolve().parents[2]
checks=0
def check(value,message):
 global checks
 checks+=1
 if not value:raise AssertionError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 data=json.loads((ROOT/'assets/data/animation_lab/motion.json').read_text())
 for clip,frames in data['clips'].items():
  check(len(frames)==121,clip+' sample count')
  for index,frame in enumerate(frames):
   check(abs(frame['at']-index/30)<1e-8,'shared sample clock')
   for name,p in frame['joints'].items():
    check(all(math.isfinite(x) for x in p) if isinstance(p,list) else math.isfinite(p),'finite joint '+name)
   for bone in data['bones']:
    if bone['name']=='weapon':continue
    initial=frames[0]['joints'];current=frame['joints']
    check(abs(math.dist(initial[bone['head']],initial[bone['tail']])-math.dist(current[bone['head']],current[bone['tail']]))<1e-7,'physical bone length '+bone['name'])
   if clip=='staff':
    j=frame['joints'];v=[j['hand_R'][k]+(j['tip'][k]-j['hand_R'][k])*.34/1.12 for k in range(3)]
    check(math.dist(j['hand_L'],v)<1e-8,'two hands on staff')
  check(frames[0]['joints']==frames[-1]['joints'],'closed loop '+clip)
 manifest=json.loads((ROOT/'assets/art/animation_lab/atlas.json').read_text())
 for clip,entries in manifest['clips'].items():
  check(len(entries)==120,'real sequence length')
  for entry in entries:
   path=ROOT/entry['path'].removeprefix('res://');check(path.is_file(),'atlas present')
   x,y,w,h=entry['region'];check(w==384 and h==384 and 0<=x<=1920 and 0<=y<=1536,'fixed atlas region')
 blob=(ROOT/'assets/art/animation_lab/model.glb').read_bytes()
 check(blob[:4]==b'glTF','GLB header')
 size,kind=struct.unpack_from('<II',blob,12);gltf=json.loads(blob[20:20+size])
 check({a['name'] for a in gltf['animations']}=={'thrust','cut','staff'},'three actual exported actions')
 check(len(gltf['skins'])==1 and len(gltf['skins'][0]['joints'])==14,'real exported skeleton')
 receipt=json.loads((ROOT/'assets/art/animation_lab/blender-source.json').read_text())
 check(sha(ROOT/'assets/data/animation_lab/motion.json') in json.dumps(receipt),'current source in provenance')
 protected=ROOT/'.local/qa/animation-options-lab/protected-before.json'
 protected_count=0
 if protected.exists():
  for checkout,files in json.loads(protected.read_text()).items():
   for path,digest in files.items():
    check(sha(Path(checkout)/path)==digest,'protected file changed '+checkout+'/'+path);protected_count+=1
 print(json.dumps({'checks':checks,'failures':0,'protected_files_unchanged':protected_count,'result':'PASS'}))
if __name__=='__main__':main()
