"""Build only the animation lab in a fresh staging project, leaving main intact."""
import argparse,hashlib,json,shutil,subprocess,time
from pathlib import Path
PROJECT='''config_version=5
[application]
config/name="蜀山 · 动作方案对照"
config/version="0.1.0-animation-options-lab"
run/main_scene="res://scenes/demos/animation_lab.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
[display]
window/size/viewport_width=1440
window/size/viewport_height=900
window/size/window_width_override=1152
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
[editor]
import/use_multiple_threads=false
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.93,0.90,0.83,1)
'''
EXPORT='''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
script_export_mode=2
[preset.0.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
'''
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--godot',default='godot');parser.add_argument('--stage-only',action='store_true');parser.add_argument('--preview',action='store_true',help='Stage before sequence renders finish, with explicit pending label');args=parser.parse_args()
 root=Path(__file__).resolve().parents[1];base=root/'.local/build/animation-options-lab';base.mkdir(parents=True,exist_ok=True)
 stage=base/('stage-'+time.strftime('%Y%m%d-%H%M%S'));stage.mkdir(exist_ok=False)
 files=[root/'tests/animation_lab_test.gd',*root.glob('scripts/animation_lab/*.gd'),*root.glob('scripts/animation_lab/*.uid'),root/'scenes/demos/animation_lab.tscn',*root.glob('assets/data/animation_lab/*.json'),root/'assets/fonts/ShuAnimationLabSerif.ttf',root/'assets/fonts/source-animation-lab.json',root/'assets/fonts/OFL-Serif.txt',root/'assets/art/animation_lab/source.json',root/'assets/art/animation_lab/model.glb',root/'assets/art/animation_lab/atlas.json',root/'assets/art/animation_lab/blender-source.json',*root.glob('assets/art/animation_lab/*_?.png'),*[root/f'assets/art/back_mountain_training/{name}.png' for name in ['far','mid','near']],root/'assets/art/back_mountain_training/source.json']
 hashes={}
 for source in files:
  if args.preview and not source.is_file() and source.name == 'atlas.json':continue
  if not source.is_file():raise SystemExit(f'Required lab file absent: {source.relative_to(root)}')
  relative=source.relative_to(root);destination=stage/relative;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,destination);hashes[str(relative)]=hashlib.sha256(source.read_bytes()).hexdigest()
 (stage/'project.godot').write_text(PROJECT);(stage/'export_presets.cfg').write_text(EXPORT)
 (base/'latest-stage.txt').write_text(str(stage)+'\n')
 receipt={'stage':str(stage),'base_sha':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'source_hashes':hashes,'web_verified':False,'cost_rmb':0}
 if not args.stage_only:
  out=base/'web';out.mkdir(exist_ok=True)
  for label,command in [('import',[args.godot,'--headless','--path',str(stage),'--editor','--import']),('export',[args.godot,'--headless','--path',str(stage),'--export-release','Web',str(out/'index.html')])]:
   with (base/f'{label}.log').open('w') as log:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
   receipt[label+'_exit']=result.returncode
   if result.returncode:raise SystemExit(f'{label} failed; see {base}/{label}.log')
  receipt['web_files']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()}
 (base/'build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'stage':str(stage),'files':len(hashes),'web':str(base/'web') if not args.stage_only else None}))
if __name__=='__main__':main()
