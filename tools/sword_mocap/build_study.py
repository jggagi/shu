"""Stage/export only the independent sword mocap comparison. No main-project edits."""
import argparse,hashlib,json,shutil,subprocess,time
from pathlib import Path
PROJECT='''config_version=5
[application]
config/name="蜀山 · 真人动作对照"
config/version="0.1.0-sword-mocap-study"
run/main_scene="res://scenes/demos/sword_mocap_comparison.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
[display]
window/size/viewport_width=1152
window/size/viewport_height=720
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
exclude_filter="tests/*,assets/data/sword_mocap/pose_reference.json"
script_export_mode=2
[preset.0.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
'''
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 a=argparse.ArgumentParser(description=__doc__);a.add_argument('--output',type=Path,required=True);a.add_argument('--godot',default='godot');a.add_argument('--stage-only',action='store_true');args=a.parse_args()
 root=Path(__file__).resolve().parents[2];base=args.output;base.mkdir(parents=True,exist_ok=True)
 stage=base/('stage-'+time.strftime('%Y%m%d-%H%M%S'));stage.mkdir(exist_ok=False)
 files=[root/'scenes/demos/sword_mocap_comparison.tscn',*root.glob('scripts/sword_mocap/*.gd'),*root.glob('tests/sword_mocap*gd'),*root.glob('assets/art/sword_mocap/*'),root/'assets/data/sword_mocap/study.json',root/'assets/data/sword_mocap/pose_reference.json',root/'assets/fonts/ShuSwordMocapSerif.ttf',root/'assets/fonts/source-sword-mocap.json',root/'assets/fonts/OFL-Serif.txt',*[root/f'assets/art/back_mountain_training/{name}.png' for name in ['far','mid','near']]]
 hashes={}
 for source in files:
  if not source.is_file():raise SystemExit('Missing asset '+str(source.relative_to(root)))
  relative=source.relative_to(root);dest=stage/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest);hashes[str(relative)]=sha(source)
 (stage/'project.godot').write_text(PROJECT);(stage/'export_presets.cfg').write_text(EXPORT)
 (base/'latest-stage.txt').write_text(str(stage)+'\n')
 receipt={'stage':str(stage),'version':'0.1.0-sword-mocap-study','base_sha':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'source_hashes':hashes,'source_dirty':True,'cost_rmb':0,'web_ui_verified':False}
 if not args.stage_only:
  web=base/('web-'+time.strftime('%Y%m%d-%H%M%S'));web.mkdir(exist_ok=False)
  for label,cmd in [('import',[args.godot,'--headless','--path',str(stage),'--editor','--import']),('export',[args.godot,'--headless','--path',str(stage),'--export-release','Web',str(web/'index.html')])]:
   if label=='import':
    config=stage/'assets/art/sword_mocap/study.glb.import';text=config.read_text()
    if 'animation/fps=60' not in text or '"optimizer/enabled": false' not in text or '"compression/enabled": false' not in text:raise SystemExit('Missing faithful animation import settings')
    receipt['animation_import_fps']=60;receipt['animation_optimizer']=False;receipt['animation_compression']=False
   logpath=base/(stage.name+'-'+label+'.log')
   with logpath.open('w') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
   receipt[label+'_exit']=r.returncode
   if r.returncode or 'SCRIPT ERROR:' in logpath.read_text() or 'ERROR:' in logpath.read_text():raise SystemExit(str(logpath)+' failed')
  receipt['web']=str(web);receipt['web_files']={p.name:sha(p) for p in web.iterdir() if p.is_file()}
  (base/'latest-web.txt').write_text(str(web)+'\n')
 (base/'build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
if __name__=='__main__':main()
