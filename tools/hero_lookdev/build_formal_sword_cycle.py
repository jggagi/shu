"""Stage the real cultivation host with the approved five sword combinations.

Copies the transitive local resource closure into a new external build directory.
No downloads, installs, engine invocation, or source checkout changes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEXT_SUFFIXES = {'.gd', '.tscn', '.tres', '.json', '.godot', '.gdshader'}
RESOURCE = re.compile(r'res://([^\s\"\'\)]+)')


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage(output: Path) -> dict:
    if not output.is_absolute() or not output.is_dir():
        raise SystemExit('--output must be an existing absolute directory')
    target = output / ('stage-' + uuid.uuid4().hex[:12])
    pending = [ROOT / 'project.godot', ROOT / 'scenes/main.tscn',
               ROOT / 'assets/fonts/source-cultivation-sword.json',
               ROOT / 'assets/fonts/OFL-Serif.txt', ROOT / 'assets/art/jiang_sword_cycle/source-formal.json']
    for name in ['formal_sword_cycle_test', 'formal_sword_cycle_render', 'state_test',
                 'sword_training_state_test', 'cultivation_scene_routing_test', 'tea_full_state_test']:
        check_path = ROOT / ('tests/' + name + '.gd')
        if check_path.is_file():
            pending.append(check_path)
    files: dict[str, str] = {}
    while pending:
        source = pending.pop()
        if source.is_symlink() or not source.exists():
            raise SystemExit('Missing or symlinked runtime dependency: ' + str(source))
        if source.is_dir():
            pending.extend(p for p in source.rglob('*') if p.is_file() and p.suffix not in {'.import', '.uid'})
            continue
        rel = source.relative_to(ROOT).as_posix()
        if rel in files:
            continue
        files[rel] = sha(source)
        if source.suffix in TEXT_SUFFIXES:
            for match in RESOURCE.findall(source.read_text()):
                # QA output destinations are not runtime inputs.
                if match.startswith('.local/'):
                    continue
                if '%' in match:
                    prefix = match.split('%', 1)[0]
                    directory = ROOT / (prefix.rstrip('/') if prefix.endswith('/') else str(Path(prefix).parent))
                    if directory.is_dir():
                        pending.append(directory)
                    else:
                        raise SystemExit('Missing dynamic resource directory: ' + str(directory))
                    continue
                pending.append(ROOT / match)
    target.mkdir()
    for rel, digest in sorted(files.items()):
        source = ROOT / rel
        assert sha(source) == digest, 'Source changed during staging: ' + rel
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
        assert sha(dest) == digest
    preset = (ROOT / 'export_presets.cfg').read_text()
    preset = preset.replace('include_filter=""', 'include_filter="*.json"')
    preset = preset.replace('exclude_filter="', 'exclude_filter="build-info.json,')
    (target / 'export_presets.cfg').write_text(preset)
    (target / 'web').mkdir()
    receipt = {'stage': str(target), 'source_root': str(ROOT),
               'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
               'source_hashes': files, 'source_dirty': True, 'entry': 'res://scenes/main.tscn',
               'cloud_calls': 0, 'user_five_motion_approved': True, 'formal_loop_user_acceptance': 'pending'}
    (target / 'build-info.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    (output / (target.name + '-receipt.json')).write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    return {'stage': str(target), 'files': len(files)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    print(json.dumps(stage(parser.parse_args().output)))
