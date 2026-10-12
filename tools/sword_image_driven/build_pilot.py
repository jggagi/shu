"""Build only the image-driven Back Mountain pilot; never change the game entry."""
import argparse, hashlib, json, shutil, subprocess, uuid
from pathlib import Path

PROJECT = '''config_version=5
[application]
config/name="江砚秋 · 后山转身挥剑"
config/version="0.1.0-image-motion-pilot"
run/main_scene="res://scenes/demos/sword_image_back_mountain.tscn"
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
EXPORT = '''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter="tests/*,assets/art/sword_image_driven_v1/source.mp4"
script_export_mode=2
[preset.0.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
'''

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def pilot_dependencies(root):
    return [root/'scenes/demos/sword_image_back_mountain.tscn',
        *root.glob('scripts/sword_image_driven/*.gd'),
        *root.glob('tests/sword_image_pilot*.gd'),
        *root.glob('assets/art/sword_image_driven_v1/*'),
        *root.glob('assets/art/sword_image_clean_matte_v1/*'),
        *root.glob('assets/art/back_mountain_training/*'),
        *root.glob('assets/art/ambient_life/*'),
        *root.glob('assets/shaders/back_mountain*.gdshader'),
        root/'assets/shaders/waterfall_flow.gdshader', root/'assets/shaders/sword_image_scene_blend.gdshader',
        *[root/('scripts/'+name+'.gd') for name in ['demo_state','environment_presenter','back_mountain_training','back_mountain_environment','back_mountain_lighting','back_mountain_ambient_life','ambient_life_presenter','ambient_cat_motion']],
        *[root/('assets/data/'+name+'.json') for name in ['rules','tea-full-source','back_mountain_training','back_mountain_environment','back_mountain_lighting','back_mountain_ambient_life']],
        root/'assets/fonts/ShuSwordImageSerif.ttf', root/'assets/fonts/source-sword-image.json',root/'assets/fonts/OFL-Serif.txt',root/'assets/fonts/ShuBackMountainSerif.ttf',root/'assets/fonts/ShuDemoSerif.ttf']

def main():
    a=argparse.ArgumentParser(description=__doc__)
    a.add_argument('--output', type=Path, required=True)
    a.add_argument('--godot', default='godot')
    a.add_argument('--stage-only', action='store_true')
    args=a.parse_args()
    root=Path(__file__).resolve().parents[2]
    args.output.mkdir(parents=True, exist_ok=True)
    stage=args.output/('stage-'+uuid.uuid4().hex[:10]);stage.mkdir()
    files=pilot_dependencies(root)
    hashes={}
    for source in files:
        if not source.is_file():
            raise SystemExit('Missing input: '+str(source.relative_to(root)))
        rel=source.relative_to(root);dest=stage/rel
        dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
        hashes[str(rel)]=sha(source)
    (stage/'project.godot').write_text(PROJECT)
    (stage/'export_presets.cfg').write_text(EXPORT)
    receipt={'version':'0.1.0-image-motion-pilot','stage':str(stage),'base_sha':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'source_hashes':hashes,'cost_rmb':0,'game_entry_changed':False,'web_ui_verified':False}
    (args.output/'latest-stage.txt').write_text(str(stage)+'\n')
    if not args.stage_only:
        web=args.output/('web-'+uuid.uuid4().hex[:10]);web.mkdir()
        for label,cmd in [('import',[args.godot,'--headless','--path',str(stage),'--editor','--import']),('export',[args.godot,'--headless','--path',str(stage),'--export-release','Web',str(web/'index.html')])]:
            log_path=args.output/(stage.name+'-'+label+'.log')
            with log_path.open('w') as log:
                result=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
            receipt[label+'_exit']=result.returncode
            if result.returncode or 'ERROR:' in log_path.read_text():
                raise SystemExit('Failed '+str(log_path))
        receipt['web']=str(web)
        receipt['web_files']={p.name:sha(p) for p in web.iterdir() if p.is_file()}
        (args.output/'latest-web.txt').write_text(str(web)+'\n')
    (args.output/(stage.name+'-receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'stage':str(stage),'web':receipt.get('web'),'inputs':len(hashes),'import_exit':receipt.get('import_exit'),'export_exit':receipt.get('export_exit')}))

if __name__=='__main__':
    main()
