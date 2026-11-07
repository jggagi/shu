#!/usr/bin/env python3
"""Author an original seated Shu tea patron as three native SVG poses.

This is a newly drawn seated body, bent thighs and hanging lower legs. It does
not import or transform the standing town character authoring function. Only
the original project's palette and fine face/cloth line treatment are shared.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/art/shanxia_polish"
STYLE_TOOL = ROOT / "tools/build_town_hd2d_characters.py"
STYLE_SHEET = ROOT / "assets/art/shanxia_hd2d/tea-seller-walk.svg"
CELL = [64, 96]
FOOT = [32, 80]
SEAT = [31, 58]
HEAD = [33, 20]
WORLD_HEIGHT = 1.10
LEG_SCALE_Y = 22.0 / 36.0
POSES = [
    {"id": "cup_rest", "cup": [44.5, 49.0]},
    {"id": "cup_raise", "cup": [46.0, 39.0]},
    {"id": "cup_sip", "cup": [47.0, 29.0]},
]

# All three sections are inserted byte-identically into every pose. Changes
# remain in the working sleeves, hands and cup, without moving the seated body.
LEGS = (
    f'<g data-part="fixed-legs" fill="#d4d0bc" transform="translate(0 58) scale(1 {LEG_SCALE_Y:.17g}) translate(0 -58)">'
    '<path d="M24 56 Q32 56 39 60 Q42 62 42 68 L40 86 L34 86 L34 70 L23 66Z" '
    'fill="#a9afa0"/>'
    '<path d="M32 57 Q39 57 44 61 Q47 63 47 69 L45 88 L38 88 L39 70 L28 66Z"/>'
    '<path d="M36 72 L35 84 M42 73 L41 86" fill="none" stroke="#a7ad9e" stroke-width=".7"/>'
    '<path d="M34 84 L40 84 L43 88 Q48 89 48 92 L34 92 Q31 91 33 87Z" fill="#514c48"/>'
    '<path d="M38 87 L45 87 L48 90 Q53 90 53 93 Q48 94 38 94 L36 92Z" fill="#494a43"/>'
    '<path d="M34 90 L45 90 M39 92 L50 92" fill="none" stroke="#b7aa91" stroke-width=".7"/>'
    '</g>'
)
BODY = (
    '<g data-part="fixed-body">'
    '<path d="M23 36 Q30 32 36 36 L38 49 Q43 52 45 58 L42 64 '
    'Q31 64 21 59 L20 48Z" fill="url(#patron-robe)"/>'
    '<path d="M23 40 Q22 48 26 56 L38 60 L42 63 Q28 63 21 59 L20 48Z" '
    'fill="#687d73" opacity=".55" stroke="none"/>'
    '<path d="M24 48 L27 56 M29 52 Q34 56 40 57 M34 55 L42 59" '
    'fill="none" stroke="#a8b6a4" stroke-width=".7"/>'
    '<path d="M29 35 L34 33 L38 38 L33 48 L28 41Z" fill="#eee5ce"/>'
    '<path d="M34 37 L35 43 L31 47" fill="none" stroke="#c2c4ad" stroke-width=".7"/>'
    '<path d="M22 50 Q29 54 38 51 L40 55 Q31 58 22 54Z" fill="#c7c2a7"/>'
    '<path d="M33 54 L36 56 L36 63 L33 61 L32 56Z" fill="#d9d2b8" stroke-width=".65"/>'
    '</g>'
)
HEAD_ART = (
    '<g data-part="fixed-head">'
    '<path d="M18 20 Q15 10 24 7 Q37 2 43 13 L46 25 L41 35 '
    'Q29 40 20 32Z" fill="#4c433d"/>'
    '<path d="M30 12 Q40 9 44 17 L47 21 L50 23 L46 26 Q45 33 39 35 '
    'Q31 36 26 30 L25 21Z" fill="url(#patron-skin)" stroke="#a58c6f" stroke-width=".7"/>'
    '<path d="M18 20 Q17 9 29 6 Q40 5 44 14 L39 13 L36 17 L31 15 '
    'Q30 24 25 28 L24 35 L19 32 L20 24 L16 25Z" fill="#4c433d"/>'
    '<path d="M24 8 Q20 3 26 2 Q33 1 35 6 L33 10Z" fill="#4c433d"/>'
    '<path d="M25 6 Q28 3 31 5 M21 15 Q25 10 31 11 M21 19 L26 15" '
    'fill="none" stroke="#7b6b58" stroke-width=".75"/>'
    '<path d="M20 14 Q29 10 40 13" fill="none" stroke="#b7b19a" stroke-width="1.6"/>'
    '<ellipse cx="26.2" cy="25.3" rx="2.8" ry="3.6" fill="url(#patron-skin)" '
    'stroke="#a58c6f" stroke-width=".7"/>'
    '<path d="M25.5 24 Q28 23 27 27" fill="none" stroke="#bd987b" stroke-width=".6"/>'
    '<path d="M38.5 20 Q41 19 43 20" fill="none" stroke="#695244" stroke-width=".8"/>'
    '<ellipse cx="41.5" cy="22.8" rx="1.15" ry="1.55" fill="#463f36" stroke="none"/>'
    '<circle cx="41.2" cy="22.2" r=".34" fill="#fff3d8" stroke="none"/>'
    '<ellipse cx="42.2" cy="27.2" rx="2.3" ry="1.05" fill="#dba08b" opacity=".45" stroke="none"/>'
    '<path d="M43.5 30 Q45 31 46.5 29" fill="none" stroke="#af7f66" stroke-width=".65"/>'
    '</g>'
)


def hands_and_cup(pose: dict) -> str:
    cx, cy = pose["cup"]
    return (
        '<g data-part="working-arms">'
        f'<path d="M26 37 Q22 40 25 47 L{cx-6:.2f} {cy+8:.2f} '
        f'Q{cx-2:.2f} {cy+12:.2f} {cx+1:.2f} {cy+8:.2f} '
        f'L{cx:.2f} {cy+4:.2f} L30 45 L32 39Z" fill="#7f9385"/>'
        f'<path d="M{cx-7:.2f} {cy+6:.2f} L{cx-2:.2f} {cy+4:.2f} '
        f'L{cx+1:.2f} {cy+8:.2f} L{cx-4:.2f} {cy+10:.2f}Z" fill="#e1dcc4"/>'
        f'<path d="M{cx-3:.2f} {cy+6:.2f} Q{cx:.2f} {cy+5:.2f} {cx+2:.2f} {cy+7:.2f} '
        f'L{cx+2:.2f} {cy+10:.2f} Q{cx-3:.2f} {cy+11:.2f} {cx-5:.2f} {cy+8:.2f}Z" '
        'fill="url(#patron-skin)" stroke-width=".65"/>'
        f'<path d="M33 37 Q39 37 41 44 L{cx+3:.2f} {cy+2:.2f} '
        f'Q{cx+7:.2f} {cy+5:.2f} {cx+3:.2f} {cy+9:.2f} '
        f'L{cx-1:.2f} {cy+6:.2f} L35 48 L30 43Z" fill="url(#patron-robe)"/>'
        f'<path d="M{cx+1:.2f} {cy+1:.2f} L{cx+5:.2f} {cy+3:.2f} '
        f'L{cx+2:.2f} {cy+8:.2f} L{cx-2:.2f} {cy+5:.2f}Z" fill="#e1dcc4"/>'
        f'<path d="M{cx-4:.2f} {cy:.2f} L{cx-3:.2f} {cy+6:.2f} '
        f'Q{cx:.2f} {cy+8:.2f} {cx+3:.2f} {cy+6:.2f} L{cx+4:.2f} {cy:.2f}Z" '
        'fill="#b7c7b8" stroke="#7b8e84" stroke-width=".7"/>'
        f'<ellipse cx="{cx:.2f}" cy="{cy:.2f}" rx="4" ry="1.25" fill="#e8e8d8" '
        'stroke="#7b8e84" stroke-width=".7"/>'
        f'<ellipse cx="{cx:.2f}" cy="{cy:.2f}" rx="2.6" ry=".65" fill="#6d8068" stroke="none"/>'
        f'<path d="M{cx+3:.2f} {cy+2:.2f} Q{cx+6:.2f} {cy:.2f} {cx+6:.2f} {cy+4:.2f} '
        f'Q{cx+6:.2f} {cy+6:.2f} {cx+3:.2f} {cy+5:.2f}" fill="none" '
        'stroke="#8b9e90" stroke-width="1.1"/>'
        f'<path d="M{cx+2:.2f} {cy+3:.2f} Q{cx+5:.2f} {cy+2:.2f} {cx+5:.2f} {cy+5:.2f} '
        f'Q{cx+4:.2f} {cy+8:.2f} {cx+1:.2f} {cy+7:.2f}Z" '
        'fill="url(#patron-skin)" stroke-width=".65"/>'
        '<path d="M27 42 Q27 46 30 47 M36 41 L39 44" fill="none" '
        'stroke="#b4c0ad" stroke-width=".65"/>'
        '</g>'
    )


def sheet() -> str:
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="192" height="96" viewBox="0 0 192 96">',
        '<title>Shu original seated tea patron</title>',
        '<desc>Three fixed-seat side-facing poses: rest, raise cup, sip. Native original vector art.</desc>',
        '<defs><linearGradient id="patron-robe" x1="0" y1="0" x2=".8" y2="1">'
        '<stop stop-color="#94a493"/><stop offset="1" stop-color="#778b7e"/></linearGradient>',
        '<linearGradient id="patron-skin" x1="0" y1="0" x2=".2" y2="1">'
        '<stop stop-color="#f6dfba"/><stop offset="1" stop-color="#e8be98"/></linearGradient></defs>',
    ]
    for index, pose in enumerate(POSES):
        parts.append(f'<g id="{pose["id"]}" transform="translate({index*64} 0)" '
                     'stroke="#676055" stroke-width=".85" stroke-linejoin="round" stroke-linecap="round">')
        parts.extend([LEGS, BODY, HEAD_ART, hands_and_cup(pose), '</g>'])
    return ''.join(parts) + '</svg>\n'


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    output = DEST / "tea-patron.svg"
    output.write_text(sheet(), encoding="utf-8")
    metadata = {
        "title": "Shu original seated tea patron",
        "date": "2026-10-29",
        "author": "Codex, authored for Shu",
        "method": "New native SVG seated silhouette, bent thighs and hanging shins; original face and cloth vectors. No standing-pose transform, raster generation or external art inputs.",
        "license": "Project-original; no third-party character or image assets copied",
        "generator": "tools/build_town_tea_patron.py",
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "style_reference": "assets/art/shanxia_hd2d/tea-seller-walk.svg",
        "style_reference_sha256": hashlib.sha256(STYLE_SHEET.read_bytes()).hexdigest(),
        "style_reference_generator": "tools/build_town_hd2d_characters.py",
        "style_reference_generator_sha256": hashlib.sha256(STYLE_TOOL.read_bytes()).hexdigest(),
        "file": "res://assets/art/shanxia_polish/tea-patron.svg",
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "bytes": output.stat().st_size,
        "canvas": [192, 96], "cell_size": CELL,
        "facing": "seated profile facing right",
        "foot_anchor": FOOT, "seat_anchor": SEAT, "head_anchor": HEAD,
        "anchor_origin": "top-left of each cropped frame, pixels",
        "recommended_world_height": WORLD_HEIGHT,
        "placement_notes": "Align the source seat anchor to the bench top. Leg geometry alone is compressed about seat y58 to a 22px seat-to-foot separation for the fixed-Y seated billboard and raised stone platform; head, torso, hands and cup remain unchanged. World-height hint is a starting value; the host calibrates actual fixed-Y scale/contact in-scene. No standing sprite or grounded seat geometry is included.",
        "leg_calibration": {"pivot_y": 58, "scale_y": LEG_SCALE_Y,
                            "original_foot_anchor": [32, 94], "foot_anchor": FOOT,
                            "original_svg_sha256": "ee4bf87efc4d3e2a3e2f5d3e30fdae0d048668816da49e4630c6442fb1a848ea",
                            "original_leg_group_sha256": "01c43fdf75d4bbaf489bc35a23e11e21f4419e6894be3d82b5269c48ae3de16e",
                            "scope": "Seated lower-body group only; calibrated for the fixed-Y camera and bench/platform height. Original seated silhouette retained; head/body/working hand-cup vectors are unchanged."},
        "fixed_parts_sha256": {name: hashlib.sha256(part.encode()).hexdigest()
                               for name, part in [("legs", LEGS), ("body", BODY), ("head", HEAD_ART)]},
        "frames": [{"index": index, "id": pose["id"], "crop": [index*64, 0, 64, 96],
                    "foot_anchor": FOOT, "seat_anchor": SEAT, "head_anchor": HEAD,
                    "cup_rim_center": pose["cup"]} for index, pose in enumerate(POSES)],
        "timing": {"period_seconds": 12.0, "gesture_start_seconds": 7.0,
                   "gesture_duration_seconds": 2.2,
                   "time_authority": "caller existing ambient_elapsed; helper owns no clock, game state or persistence"},
        "status": "implementation candidate; source XML and reproducibility checked; real scene scale, seat contact, occlusion and user acceptance pending",
    }
    (DEST / "tea-patron-source.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding="utf-8")
    print(json.dumps({"frames": 3, "cell": CELL, "seat_anchor": SEAT, "foot_anchor": FOOT,
                      "sha256": metadata["sha256"]}))


if __name__ == "__main__":
    main()
