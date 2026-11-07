#!/usr/bin/env python3
"""Extend Shu's native-vector seller with six foot-stable cup-work poses.

The existing authoring function supplies the unchanged head, body, apron and
feet. Only the two working sleeves, hands, cup and small cloth are replaced.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from build_town_hd2d_characters import person

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art/shanxia_polish"
BASE_TOOL = ROOT / "tools/build_town_hd2d_characters.py"
BASE_ATLAS = ROOT / "assets/art/shanxia_hd2d/tea-seller-walk.svg"
CELL = [80,112]
FOOT = [40,104]

# The sample holds its own centre of gravity: head, torso and contact feet never move.
POSES = [
    {"id":"hold_rest", "cup_y":58.0, "cup_angle":0.0, "cloth_x":45.4, "cloth_y":61.1, "cloth_angle":-7.0},
    {"id":"hold_lift", "cup_y":56.8, "cup_angle":-1.0, "cloth_x":45.1, "cloth_y":59.6, "cloth_angle":-4.0},
    {"id":"hold_ready", "cup_y":55.5, "cup_angle":-2.0, "cloth_x":44.5, "cloth_y":58.3, "cloth_angle":-1.0},
    {"id":"wipe_right", "cup_y":55.7, "cup_angle":-1.0, "cloth_x":44.8, "cloth_y":56.9, "cloth_angle":-15.0},
    {"id":"wipe_across", "cup_y":55.7, "cup_angle":-1.0, "cloth_x":42.7, "cloth_y":56.0, "cloth_angle":16.0},
    {"id":"wipe_return", "cup_y":56.1, "cup_angle":0.0, "cloth_x":46.1, "cloth_y":58.1, "cloth_angle":-9.0},
]

OLD_ARMS = '<path d="M29 45 Q23 45 22 55 L25 66 Q31 70 37 64 L35 59 L30 58 L32 49Z M50 46 Q57 46 58 55 L55 65 Q50 69 43 63 L45 58 L51 58 L48 50Z" fill="#a38b69"/><path d="M27 60 L34 58 L37 63 L30 67Z M46 58 L53 60 L50 66 L43 63Z" fill="#e5d9bb"/>'
OLD_PROPS = '<path d="M35 58 L36 65 Q40 68 44 65 L45 58Z" fill="#d1dcd2" stroke="#7b8e84" stroke-width=".8"/><ellipse cx="40" cy="58" rx="5" ry="1.6" fill="#f0ede0" stroke="#7b8e84" stroke-width=".8"/><path d="M42 60 L47 59 L48 64 L43 64Z" fill="#f1e9d3" stroke="#bdb49a" stroke-width=".65"/><path d="M33 61 Q36 59 37 62 L37 65 Q33 67 32 64Z M47 61 Q43 60 43 63 Q43 67 47 66Z" fill="url(#skin)" stroke-width=".7"/>'


def arms(pose: dict) -> str:
    cy = pose['cup_y']
    rx, ry = pose['cloth_x']+2.2, pose['cloth_y']+3.1
    return (
        f'<path d="M29 45 Q23 45 22 54 L25 {cy+6.5:.2f} '
        f'Q29 {cy+10:.2f} 35 {cy+6:.2f} L35 {cy+1:.2f} '
        f'L30 {cy:.2f} L32 49Z" fill="#a38b69"/>'
        f'<path d="M50 46 Q57 47 58 54 '
        f'L{rx+4:.2f} {ry+3:.2f} Q{rx+1:.2f} {ry+6:.2f} {rx-4:.2f} {ry+1:.2f} '
        f'L{rx-2:.2f} {ry-3:.2f} L51 56 L48 50Z" fill="#a38b69"/>'
        f'<path d="M27 {cy+2:.2f} L33 {cy:.2f} L36 {cy+5:.2f} '
        f'L30 {cy+8:.2f}Z" fill="#e5d9bb"/>'
        f'<path d="M{rx-3.5:.2f} {ry-3:.2f} L{rx+3.2:.2f} {ry-1:.2f} '
        f'L{rx+1:.2f} {ry+5:.2f} L{rx-5:.2f} {ry+1:.2f}Z" fill="#e5d9bb"/>'
        f'<path d="M25 51 Q24 55 28 {cy+3:.2f} M55 52 L{rx+2:.2f} {ry-1:.2f}" '
        'fill="none" stroke="#c7b493" stroke-width=".65"/>'
    )


def props(pose: dict) -> str:
    cy, angle = pose['cup_y'], pose['cup_angle']
    clothx,clothy,clothangle = pose['cloth_x'],pose['cloth_y'],pose['cloth_angle']
    rx,ry=clothx+2.2,clothy+3.1
    return (
        # The support palm sits below the vessel; the cup rim stays below the chin.
        f'<path d="M32.8 {cy+3.2:.2f} Q35.4 {cy+1.5:.2f} 36.7 {cy+4:.2f} '
        f'L36.7 {cy+7:.2f} Q33.6 {cy+9:.2f} 32 {cy+6.2:.2f}Z" '
        'fill="url(#skin)" stroke-width=".7"/>'
        f'<g transform="rotate({angle} 40 {cy})">'
        f'<path d="M35 {cy} L36 {cy+7:.2f} Q40 {cy+10:.2f} 44 {cy+7:.2f} '
        f'L45 {cy}Z" fill="#d1dcd2" stroke="#7b8e84" stroke-width=".8"/>'
        f'<path d="M36.5 {cy+2:.2f} L37.2 {cy+6:.2f}" stroke="#edf0df" '
        'stroke-width=".7" fill="none"/>'
        f'<ellipse cx="40" cy="{cy}" rx="5" ry="1.6" fill="#f0ede0" '
        'stroke="#7b8e84" stroke-width=".8"/>'
        f'<path d="M36.5 {cy+.1:.2f} Q40 {cy-1.2:.2f} 43.4 {cy+.1:.2f}" '
        'fill="none" stroke="#b6bda7" stroke-width=".55"/></g>'
        # A folded cloth crosses the rim only in the three wiping poses.
        f'<g transform="translate({clothx:.2f} {clothy:.2f}) rotate({clothangle})">'
        '<path d="M-3.8 -2 L2.5 -2.8 L4 2.9 L1.9 4.3 L-3.1 3.2Z" '
        'fill="#f1e9d3" stroke="#bdb49a" stroke-width=".65"/>'
        '<path d="M-2.3 -.4 L1.7 -1.1 M-1.8 1.2 L2.5 .4" '
        'stroke="#c4cdbb" stroke-width=".6" fill="none"/></g>'
        f'<path d="M{rx+1.8:.2f} {ry-1.7:.2f} '
        f'Q{rx-1.8:.2f} {ry-3.2:.2f} {rx-2.5:.2f} {ry-.1:.2f} '
        f'Q{rx-3.2:.2f} {ry+3.3:.2f} {rx+.7:.2f} {ry+3.2:.2f} '
        f'Q{rx+3.2:.2f} {ry+2:.2f} {rx+1.8:.2f} {ry-1.7:.2f}Z" '
        'fill="url(#skin)" stroke-width=".7"/>'
        f'<path d="M{rx-.6:.2f} {ry-.3:.2f} L{rx+1:.2f} {ry+.2:.2f}" '
        'stroke="#b58c70" stroke-width=".5" fill="none"/>'
    )


def seller(pose: dict) -> str:
    base=person('down',0,False)
    if base.count(OLD_ARMS)!=1 or base.count(OLD_PROPS)!=1:
        raise SystemExit('Base seller authoring blocks changed; inspect identity before replacing pose parts')
    return base.replace(OLD_ARMS,arms(pose)).replace(OLD_PROPS,props(pose))


def sheet() -> str:
    output=[
        '<svg xmlns="http://www.w3.org/2000/svg" width="480" height="112" viewBox="0 0 480 112">',
        '<title>Shu original tea seller cup-work poses</title>',
        '<desc>Six 80x112 frames, foot anchor40,104. Head, apron, torso and feet remain unchanged; only working sleeves, hands, cup and cloth change.</desc>',
        '<defs>',
        '<linearGradient id="robe" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#b49b78"/><stop offset="1" stop-color="#957b5d"/></linearGradient>',
        '<linearGradient id="skin" x1="0" y1="0" x2=".2" y2="1"><stop stop-color="#f6dfba"/><stop offset="1" stop-color="#e8be98"/></linearGradient>',
        '<linearGradient id="apron" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#e3d7b8"/><stop offset="1" stop-color="#cbbb96"/></linearGradient>',
        '</defs>',
    ]
    for i,pose in enumerate(POSES):
        output.append(f'<g transform="translate({i*80} 0)">{seller(pose)}</g>')
    return ''.join(output)+'</svg>\n'


def main() -> None:
    OUT.mkdir(parents=True,exist_ok=True)
    data=sheet().encode('utf-8')
    (OUT/'tea-seller-life.svg').write_bytes(data)
    source={
        'title':'Shu original tea seller small cup-work gesture',
        'date':'2026-10-29',
        'author':'Codex, authored for Shu',
        'method':'Native SVG extension of the existing original town seller. Exact shared head/body/apron/feet authoring; replacement working sleeve/hand/cup/cloth vectors only. No raster image generation or external image inputs.',
        'license':'Project-original; no third-party character or image assets copied',
        'generator':'tools/build_town_tea_seller_life.py',
        'generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'base_generator':'tools/build_town_hd2d_characters.py',
        'base_generator_sha256':hashlib.sha256(BASE_TOOL.read_bytes()).hexdigest(),
        'base_walk_sheet':'res://assets/art/shanxia_hd2d/tea-seller-walk.svg',
        'base_walk_sheet_sha256':hashlib.sha256(BASE_ATLAS.read_bytes()).hexdigest(),
        'file':'res://assets/art/shanxia_polish/tea-seller-life.svg',
        'sha256':hashlib.sha256(data).hexdigest(),
        'bytes':len(data),
        'canvas':[480,112],
        'cell_size':CELL,
        'foot_anchor':FOOT,
        'anchor_origin':'top-left of each cropped frame, pixels',
        'recommended_world_height':1.55,
        'facing':'down; standing work pose only; legacy walk sheet still supplies all walking/directions',
        'frames':[dict(index=i,id=pose['id'],crop=[i*80,0,80,112],foot_anchor=FOOT) for i,pose in enumerate(POSES)],
        'timing':{'period_seconds':14.0,'gesture_start_seconds':2.0,'gesture_duration_seconds':3.0,'time_authority':'caller existing ambient_elapsed; helper owns no clock, game state or persistence'},
        'presentation_notes':'Cup stays below chin; cloth wipes the held cup, not the counter. No head/body bobbing and no moving contact feet. Caller freezes ambient_elapsed during Static/Busy; helper samples that same frozen phase.',
        'status':'implementation candidate; rendered vector inspection, in-scene and user visual acceptance pending',
    }
    (OUT/'tea-seller-life-source.json').write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'atlas':source['file'],'sha256':source['sha256'],'bytes':len(data),'frames':6,'cell_size':CELL,'foot_anchor':FOOT},indent=2))


if __name__=='__main__':
    main()
