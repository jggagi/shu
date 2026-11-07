"""Author original native-SVG town characters without external character art.

Keep the 80x112 four-direction walk contract and foot anchor. The tea seller's
cup and folded cloth describe a standing work pose, not a new wipe animation.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/art/shanxia_hd2d"
DIRECTIONS = ["down", "up", "left", "right"]
CELL = (80, 112)
BASELINE = {
    "commit": "7c992c578b1fe4a1624c769812425b38080771d3",
    "authoring_tool_sha256": "6b5c6680f2b481f37024ffc3621399fd0fea66fac7f0068bb1518178e82bdaab",
    "source_json_sha256": "98ce749dba38b5caab9e74f35760215a83aff35f76b9cc1407344e0a82b3ad01",
    "files": {
        "res://assets/art/shanxia_hd2d/player-walk.svg": "db27a6c07a1cfd24409867a943d3b45872f2a826e4a852ebcb544335c456bed7",
        "res://assets/art/shanxia_hd2d/tea-seller-walk.svg": "5dc58e3c40720fe99981bfe8e0534bf20d73368a1eb735f9e69794231f458fdd",
    },
}


def person(direction: str, frame: int, player: bool) -> str:
    side, back = direction in ["left", "right"], direction == "up"
    swing, bob = [0, 4, 0, -4][frame], [0, -.7, 0, -.7][frame]
    robe, shade, light = ("#7399b0", "#587d96", "#abc6d2") if player else ("#a38b69", "#8b7256", "#c7b493")
    hair = "#4c433d"
    p = ['<g stroke="#676055" stroke-width=".9" stroke-linejoin="round" stroke-linecap="round">']
    if direction == "left":
        p.append('<g transform="translate(80 0) scale(-1 1)">')
    # One foot always contacts y=104; the other travels and lifts slightly.
    for index, x in enumerate([32, 46] if not side else [35, 43]):
        stride = swing if index == 0 else -swing
        lift, foot = max(0, -stride) * .32, x + stride * .45
        p.append(f'<path d="M{x} 82 L{foot} {99-lift}" stroke="#e9e1cb" stroke-width="7"/>')
        p.append(f'<path d="M{foot-4} {99-lift} Q{foot+1} {97-lift} {foot+7} {100-lift} L{foot+8} {103-lift} Q{foot+2} {105-lift} {foot-5} {103-lift}Z" fill="#514c48"/>')
        p.append(f'<path d="M{foot-3} {102-lift} L{foot+6} {102-lift}" stroke="#b7aa91" stroke-width=".7"/>')
    p.append(f'<g transform="translate(0 {bob})">')
    p.append('<path d="M32 59 L49 59 L54 89 Q41 94 27 89Z" fill="#ede4cd"/>')
    if side:
        p.append('<path d="M34 42 Q42 38 49 44 L51 69 Q50 78 56 87 Q44 93 28 89 L31 69Z" fill="url(#robe)"/>')
        p.append(f'<path d="M34 53 Q40 67 34 87 L30 89 Q35 72 31 59Z" fill="{shade}" stroke="none" opacity=".45"/>')
        p.append(f'<path d="M42 72 Q44 80 48 88 M36 76 L35 88" fill="none" stroke="{light}"/>')
    else:
        p.append('<path d="M29 43 Q40 39 51 43 L54 68 Q55 78 60 87 Q51 92 40 90 Q29 93 21 87 L26 68Z" fill="url(#robe)"/>')
        p.append(f'<path d="M43 51 Q48 63 46 73 L53 88 L58 87 L51 67 L50 48Z" fill="{shade}" stroke="none" opacity=".45"/>')
        p.append(f'<path d="M29 73 L25 86 M34 76 L32 89 M45 75 L49 87" fill="none" stroke="{light}"/>')
        p.append(f'<path d="M40 73 L40 88 M27 63 L26 68" fill="none" stroke="{shade}" opacity=".6" stroke-width=".65"/>')
    if player:
        # Sleeves move against each other instead of translating the whole body.
        for index, x in enumerate([29, 50] if side else [27, 53]):
            dy, sign = swing * (.65 if index == 0 else -.65), -1 if index == 0 else 1
            if side and index == 0:
                sign, x = 1, 35
            p.append(f'<path d="M{x} 46 Q{x+sign*4} 49 {x+sign*7} {62+dy} L{x+sign*3} {68+dy} L{x-sign*4} {65+dy} L{x-sign*3} 53Z" fill="{robe}"/>')
            p.append(f'<path d="M{x+sign*7} {62+dy} Q{x+sign*2} {66+dy} {x-sign*3} {64+dy} L{x-sign*3} {68+dy} L{x+sign*3} {71+dy} L{x+sign*7} {66+dy}Z" fill="#eee4cb"/>')
            p.append(f'<path d="M{x+sign*3} {69+dy} Q{x+sign*7} {69+dy} {x+sign*5} {74+dy} Q{x+sign*1} {76+dy} {x-sign*1} {72+dy}Z" fill="url(#skin)"/>')
            p.append(f'<path d="M{x} 53 L{x+sign*2} {59+dy}" stroke="{light}" fill="none" stroke-width=".7"/>')
    elif back:
        for x, sign in [(27, -1), (53, 1)]:
            p.append(f'<path d="M{x} 46 Q{x+sign*7} 53 {x+sign*8} 65 L{x} 70 L{x-sign*4} 56Z" fill="{robe}"/>')
            p.append(f'<ellipse cx="{x+sign*3}" cy="70" rx="3" ry="3.5" fill="url(#skin)"/>')
    else:
        p.append(f'<path d="M29 45 Q23 45 22 55 L25 66 Q31 70 37 64 L35 59 L30 58 L32 49Z M50 46 Q57 46 58 55 L55 65 Q50 69 43 63 L45 58 L51 58 L48 50Z" fill="{robe}"/>')
        p.append('<path d="M27 60 L34 58 L37 63 L30 67Z M46 58 L53 60 L50 66 L43 63Z" fill="#e5d9bb"/>')
    if not back:
        if side:
            p.append('<path d="M40 42 L45 47 L43 58 L39 52 L36 45Z" fill="#f2e7cf"/><path d="M43 47 L47 43 L49 47 L44 58" fill="#d9d3bd"/>')
        else:
            p.append('<path d="M30 44 L36 41 L41 49 L47 42 L51 45 L40 60Z" fill="#f2e7cf"/><path d="M32 46 L40 55 L47 46" fill="none" stroke="#c7c4ae" stroke-width=".8"/>')
    p.append('<path d="M26 66 Q40 69 54 66 L54 71 Q41 74 25 71Z" fill="#e4d8b6"/>')
    if player:
        p.append('<path d="M43 69 Q48 68 49 71 L51 83 L47 82 L46 74 L43 74Z" fill="#e9dfc6"/><path d="M43 69 L44 74 L40 73 L40 70Z" fill="#c2bd9f" stroke-width=".6"/>')
    elif back:
        p.append('<path d="M32 45 L35 66 M48 45 L46 66" stroke="#e3d7b9" stroke-width="3"/><path d="M39 69 L32 75 L38 75 L41 70 L46 76 L50 73 L43 69" fill="#e5d9bb" stroke-width=".65"/>')
    else:
        # Linen, pocket stitching and a folded cloth establish the tea seller.
        p.append('<path d="M34 51 Q41 53 47 51 L48 64 L54 85 Q41 90 28 85 L32 64Z" fill="url(#apron)"/><path d="M34 52 L34 47 M46 52 L47 47 M30 83 Q41 87 51 83" fill="none" stroke="#f2e8ce" stroke-width="1.1"/>')
        p.append('<path d="M35 73 Q40 74 46 73 L45 80 Q40 82 35 80Z" fill="#c4b794" stroke="#b0a17f" stroke-width=".7"/><path d="M29 64 L29 78 L35 80 L36 65Z" fill="#eee6d0" stroke="#bdb49a" stroke-width=".7"/><path d="M31 69 L34 70 M31 73 L34 74" stroke="#b8c4b9" stroke-width=".8"/>')
        cx = 44 if side else 40
        p.append(f'<path d="M{cx-5} 58 L{cx-4} 65 Q{cx} 68 {cx+4} 65 L{cx+5} 58Z" fill="#d1dcd2" stroke="#7b8e84" stroke-width=".8"/><ellipse cx="{cx}" cy="58" rx="5" ry="1.6" fill="#f0ede0" stroke="#7b8e84" stroke-width=".8"/>')
        p.append(f'<path d="M{cx+2} 60 L{cx+7} 59 L{cx+8} 64 L{cx+3} 64Z" fill="#f1e9d3" stroke="#bdb49a" stroke-width=".65"/><path d="M{cx-7} 61 Q{cx-4} 59 {cx-3} 62 L{cx-3} 65 Q{cx-7} 67 {cx-8} 64Z M{cx+7} 61 Q{cx+3} 60 {cx+3} 63 Q{cx+3} 67 {cx+7} 66Z" fill="url(#skin)" stroke-width=".7"/>')
    # Warm skin, tapered hair locks and soft cheek colour remain readable small.
    p.append(f'<path d="M24 28 Q23 13 37 11 Q55 10 57 28 L53 41 Q41 49 28 41Z" fill="{hair}"/>')
    if back:
        p.append('<path d="M27 26 Q40 33 53 26 L52 40 Q41 49 28 40Z" fill="#574b40" stroke="none"/><path d="M30 23 Q28 32 33 38 M35 22 Q32 32 38 42 M42 23 Q46 33 43 42 M49 25 Q52 32 48 38" fill="none" stroke="#746556" stroke-width=".7"/>')
        if player:
            p.append('<path d="M42 33 Q48 43 43 55 L39 53 Q43 43 39 36Z" fill="#51453c"/><path d="M42 39 Q46 47 42 51" fill="none" stroke="#7c6a57" stroke-width=".7"/>')
    elif side:
        p.append('<path d="M38 20 Q48 16 52 27 L55 31 L58 33 L53 36 Q52 43 45 46 Q39 46 35 40 L33 29Z" fill="url(#skin)" stroke="#a58c6f" stroke-width=".7"/>')
        p.append(f'<path d="M28 23 Q28 13 41 13 Q50 13 54 23 L48 22 L45 25 L40 22 Q40 29 35 34 L33 43 L29 39 L30 31 L26 32Z" fill="{hair}"/>')
        p.append('<path d="M31 21 Q35 16 41 17 M32 25 Q36 22 38 20" fill="none" stroke="#7b6b58" stroke-width=".8"/><path d="M48 29 Q50 28 52 29" fill="none" stroke="#695244" stroke-width=".8"/><ellipse cx="50.3" cy="32" rx="1.25" ry="1.8" fill="#463f36" stroke="none"/><ellipse cx="50" cy="36.5" rx="2.5" ry="1.2" fill="#dba08b" opacity=".55" stroke="none"/><path d="M49 40 Q51 41 53 39.5" fill="none" stroke="#af7f66" stroke-width=".7"/>')
        p.append('<ellipse cx="36" cy="33" rx="3" ry="4" fill="url(#skin)" stroke="#a58c6f" stroke-width=".7"/><path d="M35.5 32 Q38 31 37 35" fill="none" stroke="#bd987b" stroke-width=".6"/>')
    else:
        p.append('<path d="M27 26 Q40 20 53 26 L52 36 Q50 44 40 47 Q30 44 28 36Z" fill="url(#skin)" stroke="#a58c6f" stroke-width=".7"/>')
        p.append(f'<path d="M25 27 Q23 15 36 12 Q52 10 56 25 L51 29 L49 24 L44 27 L40 23 L35 27 L33 23 L28 31Z" fill="{hair}"/>')
        p.append('<path d="M29 20 Q35 15 40 16 M44 17 Q49 17 51 21 M28 24 L32 21" fill="none" stroke="#7d6c59" stroke-width=".8"/><path d="M31 31 Q34 30 37 31 M43 31 Q46 30 49 31" fill="none" stroke="#755d49" stroke-width=".85"/>')
        p.append('<ellipse cx="34.5" cy="34" rx="1.5" ry="2" fill="#483f35" stroke="none"/><ellipse cx="45.5" cy="34" rx="1.5" ry="2" fill="#483f35" stroke="none"/><circle cx="34.1" cy="33.3" r=".45" fill="#fff3d8" stroke="none"/><circle cx="45.1" cy="33.3" r=".45" fill="#fff3d8" stroke="none"/>')
        p.append('<ellipse cx="30.5" cy="38" rx="3" ry="1.3" fill="#dc9f8a" opacity=".52" stroke="none"/><ellipse cx="49.5" cy="38" rx="3" ry="1.3" fill="#dc9f8a" opacity=".52" stroke="none"/><path d="M39 37 L40 38 M37.5 41 Q40 43 43 40.5" fill="none" stroke="#ad8065" stroke-width=".7"/>')
        if not player:
            p.append('<path d="M37 39 Q40 38 43 39 M39 44 L42 44" fill="none" stroke="#746252" stroke-width=".8"/>')
    p.append(f'<path d="M33 12 Q30 5 38 5 Q45 3 47 9 L45 14Z" fill="{hair}"/><path d="M35 9 Q39 6 43 9" fill="none" stroke="#7d6c59" stroke-width=".7"/>')
    band = "#e5dfc6" if player else "#c0aa84"
    p.append(f'<path d="M26 22 Q40 17 54 22" fill="none" stroke="{band}" stroke-width="2.4"/>')
    if player:
        p.append(f'<path d="M27 22 Q23 28 23 39 L27 36 L28 41 L31 24Z" fill="{band}" stroke="#bdbca5" stroke-width=".5"/><path d="M28 26 L25 34" fill="none" stroke="#f7f0dc" stroke-width=".7"/>')
    p.append('</g>')
    if direction == "left":
        p.append('</g>')
    p.append('</g>')
    return ''.join(p)


def sheet(player: bool) -> str:
    start, end = ("#8aaec0", "#61869f") if player else ("#b49b78", "#957b5d")
    output = ['<svg xmlns="http://www.w3.org/2000/svg" width="320" height="448" viewBox="0 0 320 448">', '<defs>',
              f'<linearGradient id="robe" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="{start}"/><stop offset="1" stop-color="{end}"/></linearGradient>',
              '<linearGradient id="skin" x1="0" y1="0" x2=".2" y2="1"><stop stop-color="#f6dfba"/><stop offset="1" stop-color="#e8be98"/></linearGradient>',
              '<linearGradient id="apron" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#e3d7b8"/><stop offset="1" stop-color="#cbbb96"/></linearGradient>', '</defs>']
    for row, direction in enumerate(DIRECTIONS):
        for column in range(4):
            output.append(f'<g transform="translate({column*80} {row*112})">{person(direction,column,player)}</g>')
    return ''.join(output) + '</svg>\n'


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    for filename, player in [("player-walk.svg", True), ("tea-seller-walk.svg", False)]:
        (DEST / filename).write_text(sheet(player))
    metadata = {
        "origin": "project-original code-authored vector art, 2026-10-24",
        "authoring_tool": "tools/build_town_hd2d_characters.py",
        "license": "Project-original; no third-party character or image assets copied",
        "identity": "Shu Jiang Yanqiu: blue/teal robe, pale sash and headband; town tea seller: brown clothes and apron",
        "cell_size": list(CELL), "columns": 4, "directions": DIRECTIONS,
        "frames_per_direction": 4, "foot_anchor": [40, 104],
        "purpose": "Full-body billboard characters for a real 3D town; distance-driven walking, fixed foot anchor",
        "not_used": "waist-up indoor portraits, fixed practice atlases, Chengping character sprites",
        "files": {"res://assets/art/shanxia_hd2d/" + p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted(DEST.glob("*.svg"))},
        "authoring_tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "revisions": [{
            "date": "2026-10-28",
            "description": "Original SVG revision: warm face and hair detail, blue robe and cream collar, gentler folds; tea seller holds a cup and cloth in the standing work pose. Existing four-direction walk contract retained; no independent wiping animation.",
            "baseline": BASELINE,
        }],
    }
    license_path = DEST / "GODOT-VIEWPORT-LICENSE.txt"
    if not license_path.is_file() or hashlib.sha256(license_path.read_bytes()).hexdigest() != "0339177149b474f7ff676d32218ecb3a8f2538955610023c3769763720d09e4c":
        raise SystemExit("Missing or changed pinned Godot viewport MIT notice")
    metadata["viewport_license"] = {
        "path": "res://assets/art/shanxia_hd2d/GODOT-VIEWPORT-LICENSE.txt",
        "sha256": hashlib.sha256(license_path.read_bytes()).hexdigest(),
        "scope": "Godot MIT SubViewport composition portion only; original adapted Chengping code uses explicit user authorization",
    }
    (DEST / "source.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({"atlases": 2, "directions": 4, "frames_per_direction": 4, "cell_size": CELL}))


if __name__ == "__main__":
    main()
