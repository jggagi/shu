"""Export an isolated standalone courtyard Web snapshot with pinned Godot, no main-scene edits."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    version = subprocess.check_output([args.godot, '--version'], text=True).strip()
    if version != '4.7.2.stable.official.ed1daf0bf':
        raise SystemExit('Expected pinned Godot 4.7.2 stable: '+version)
    source = root / '.local/build/courtyard-source'
    web = root / '.local/build/courtyard-web'
    source.mkdir(parents=True, exist_ok=True)
    web.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for folder in ['assets', 'scripts', 'scenes']:
        for path in (root/folder).rglob('*'):
            if not path.is_file(): continue
            rel = path.relative_to(root)
            target = source/rel
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(path,target)
            hashes[str(rel)] = hashlib.sha256(path.read_bytes()).hexdigest()
    for name in ['project.godot','export_presets.cfg','.engine-version']:
        shutil.copy2(root/name,source/name)
    project = (source/'project.godot').read_text()
    project = project.replace('run/main_scene="res://scenes/main.tscn"','run/main_scene="res://scenes/demos/mountain_gate_courtyard.tscn"')
    project = project.replace('config/name="蜀山行记 · 听雨廊环境 v1"','config/name="蜀 · 山门庭院 v1"')
    project = project.replace('config/version="0.1.10-tingyu-environment-local"','config/version="courtyard-v1-local"')
    (source/'project.godot').write_text(project)
    subprocess.run([args.godot,'--headless','--path',str(source),'--editor','--import'],check=True)
    subprocess.run([args.godot,'--headless','--path',str(source),'--export-release','Web',str(web/'index.html')],check=True)
    sha = subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
    (web/'build-info.json').write_text(json.dumps({'scene':'mountain-gate-courtyard','version':'courtyard-v1-local','engine':version,'base_commit':sha,'uncommitted_slice':True,'standalone_main_scene':'res://scenes/demos/mountain_gate_courtyard.tscn','source_sha256':hashes},ensure_ascii=False,indent=2)+'\n')
    print('Standalone Web export:',web)

if __name__ == '__main__':main()
