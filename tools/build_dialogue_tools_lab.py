"""Stage the isolated, pinned dialogue-tool comparison without changing the game."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def stage(output: Path, reuse: Path | None) -> dict:
    if not output.is_absolute() or (not output.is_dir() and not output.parent.is_dir()):
        raise SystemExit('output must be absolute with an existing parent directory')
    output.mkdir(exist_ok=True)
    target = output / ('stage-' + uuid.uuid4().hex[:12])
    target.mkdir()
    inputs: dict[str, str] = {}
    import_sidecars: dict[str, str] = {}
    staged_hashes: dict[str, str] = {}
    def copy(source: Path, rel: Path | None = None):
        if source.is_symlink() or not source.is_file():
            raise SystemExit('Invalid input: ' + str(source))
        rel = rel or source.relative_to(ROOT)
        digest = sha(source)
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        prior = reuse / rel if reuse else None
        if prior and prior.is_file() and prior.stat().st_dev == dest.parent.stat().st_dev and sha(prior) == digest:
            subprocess.run(['/bin/cp', '-c', str(prior), str(dest)], check=True)
        else:
            shutil.copy2(source, dest)
        if sha(dest) != digest:
            raise SystemExit('Stage hash mismatch')
        inputs[str(source.relative_to(ROOT))] = digest
        staged_hashes[str(rel)] = digest
    for folder in ['scripts/dialogue_tools_lab', 'games/dialogue_tools_sample', 'addons/cultivation_mode']:
        for path in sorted((ROOT / folder).rglob('*')):
            if path.is_file() and path.suffix in ['.gd', '.json', '.dialogue', '.dtl', '.dch', '.tscn', '.tres', '.md']:
                copy(path)
    for path in sorted((ROOT / 'tests').glob('dialogue_tools_lab_*.gd')):
        copy(path)
    for path in sorted((ROOT / 'tests').glob('mentor_voice_*.gd')):
        copy(path)
    for path in sorted((ROOT / 'assets/audio/mentor_pause').iterdir()):
        if path.suffix in ['.wav', '.json']:
            copy(path)
    copy(ROOT / 'trunk/mentor-slow-half-step.json')
    # Plugin importers replace .dialogue/.dtl resources on export. Preserve
    # byte-identical literal text for the runtime compiler evaluation.
    literal_sources = {'scripts/dialogue_tools_lab/mentor_dm.txt': 'scripts/dialogue_tools_lab/mentor.dialogue',
                       'scripts/dialogue_tools_lab/mentor_dialogic.txt': 'scripts/dialogue_tools_lab/mentor.dtl'}
    for dest, source in literal_sources.items():
        copy(ROOT / source, Path(dest))
    for name in ['dialogue_manager', 'dialogic']:
        plugin = ROOT / 'third_party/dialogue_tools_lab' / name
        for path in sorted((plugin / 'addons' / name).rglob('*')):
            if path.is_file():
                if path.suffix == '.import':
                    # Official icon UIDs are referenced directly by plugin scripts.
                    # Preserve their initial metadata; Godot may rewrite this cache.
                    dest = target / path.relative_to(plugin)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, dest)
                    import_sidecars[str(path.relative_to(ROOT))] = sha(path)
                else:
                    copy(path, path.relative_to(plugin))
        for name_ in ['LICENSE', 'README.md', 'source.json']:
            if (plugin / name_).is_file():
                copy(plugin / name_)
        if not (plugin / 'LICENSE').is_file() and not (plugin / 'addons' / name / 'LICENSE').is_file():
            raise SystemExit('Missing original plugin license: ' + name)
    for rel in ['scenes/demos/dialogue_tools_trial.tscn', 'assets/fonts/ShuDialogueLabSerif.ttf',
                'assets/fonts/source-dialogue-lab.json', 'assets/fonts/OFL-Serif.txt',
                'assets/art/weather3/tingyu-clean-v3.png', 'assets/art/weather3/source.json',
                'assets/art/v2/jiang-yanqiu-v2.png', 'assets/art/v2/ye-zhixian-v2.png',
                'assets/art/v2/desk-v2.png', 'assets/art/v2/source.json', '.engine-version',
                'tools/rebuild_dialogue_lab_font.py', 'tools/build_dialogue_tools_lab.py']:
        copy(ROOT / rel)
    # Reuse only import sidecars/cache for byte-identical art, not editor state.
    if reuse:
        import re
        for rel, digest in staged_hashes.items():
            source = reuse / rel
            sidecar = reuse / (rel + '.import')
            if source.is_file() and sha(source) == digest and sidecar.is_file():
                shutil.copy2(sidecar, target / (rel + '.import'))
                for imported in re.findall(r'res://(\.godot/imported/[^"\n]+)', sidecar.read_text()):
                    p = reuse / imported
                    d = target / imported
                    if p.is_file() and not d.exists():
                        d.parent.mkdir(parents=True, exist_ok=True)
                        subprocess.run(['/bin/cp', '-c', str(p), str(d)], check=True)
        prior_info = reuse / 'build-info.json'
        if prior_info.is_file() and (reuse / '.engine-version').read_bytes() == (ROOT / '.engine-version').read_bytes():
            prior_hashes = json.loads(prior_info.read_text()).get('source_hashes', {})
            plugin_inputs = {k: v for k, v in inputs.items() if k.startswith('third_party/dialogue_tools_lab/') and '/addons/' in k}
            if plugin_inputs and all(prior_hashes.get(k) == v for k, v in plugin_inputs.items()):
                # Derived UID/class indices from the same engine and plugin sources;
                # no editor state, settings or export cache is carried across.
                for rel in ['.godot/uid_cache.bin', '.godot/global_script_class_cache.cfg']:
                    p = reuse / rel
                    if p.is_file():
                        d = target / rel
                        d.parent.mkdir(parents=True, exist_ok=True)
                        subprocess.run(['/bin/cp', '-c', str(p), str(d)], check=True)
    (target / 'project.godot').write_text('''config_version=5
[application]
config/name="慢半步 · 有声师徒"
config/version="0.2.0-mentor-voice"
run/main_scene="res://scenes/demos/dialogue_tools_trial.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
config/use_custom_user_dir=true
config/custom_user_dir_name="shu-mentor-voice-demo"
[autoload]
DialogueManager="*res://addons/dialogue_manager/dialogue_manager.gd"
Dialogic="*res://addons/dialogic/Core/DialogicGameHandler.gd"
[display]
window/size/viewport_width=1440
window/size/viewport_height=900
window/size/window_width_override=1152
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
[gui]
theme/custom_font="res://assets/fonts/ShuDialogueLabSerif.ttf"
[editor]
; Godot 4.7.2 can crash when importing the bundled fonts concurrently.
import/use_multiple_threads=false
[editor_plugins]
enabled=PackedStringArray("res://addons/dialogue_manager/plugin.cfg", "res://addons/dialogic/plugin.cfg")
[dialogic]
save/autosave=false
layout/end_behaviour=0
text/letter_speed=0.025
choices/delay=0.2
[input]
dialogic_default_action={"deadzone":0.5,"events":[Object(InputEventKey,"physical_keycode":32),Object(InputEventMouseButton,"button_index":1)]}
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.93,0.90,0.83,1)
''')
    (target / 'export_presets.cfg').write_text('''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="*.json,*.dialogue,*.dtl,*.dch,*.txt"
exclude_filter="tests/*,trunk/*,build-info.json,*.md,third_party/*,*.cs,addons/dialogue_manager/example_balloon/ExampleBalloon.tscn,addons/dialogue_manager/example_balloon/SmallExampleBalloon.tscn,addons/dialogue_manager/nodes/dialogue_label/DialogueLabel.tscn"
export_path=""
script_export_mode=2
[preset.0.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/export_icon=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
''')
    (target / 'web').mkdir()
    notice = ['This local evaluation includes the following third-party software and fonts.',
              'Dialogue Manager v4.1.0 — https://github.com/nathanhoad/godot_dialogue_manager',
              (ROOT / 'third_party/dialogue_tools_lab/dialogue_manager/addons/dialogue_manager/LICENSE').read_text(),
              'Dialogic 2.0-alpha-20 — https://github.com/dialogic-godot/dialogic',
              (ROOT / 'third_party/dialogue_tools_lab/dialogic/LICENSE').read_text(),
              'Shu Dialogue Lab Serif, derived from Noto Serif SC',
              (ROOT / 'assets/fonts/OFL-Serif.txt').read_text()]
    (target / 'web/THIRD_PARTY_NOTICES.txt').write_text('\n\n'.join(notice))
    receipt = {'stage': str(target), 'source_root': str(ROOT), 'source_hashes': inputs,
               'import_sidecar_source_hashes': import_sidecars,
               'generated_literals': literal_sources,
               'entry': 'res://scenes/demos/dialogue_tools_trial.tscn',
               'scope': 'Isolated real Dialogue Manager / Dialogic trial; existing game, catalog and saves unchanged',
               'plugins': [json.loads((ROOT / 'third_party/dialogue_tools_lab' / n / 'source.json').read_text()) for n in ['dialogue_manager','dialogic']]}
    (target / 'build-info.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+'\n')
    return {'stage': str(target), 'source_files': len(inputs)}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reuse-stage', type=Path)
    args = parser.parse_args()
    print(json.dumps(stage(args.output, args.reuse_stage)))
