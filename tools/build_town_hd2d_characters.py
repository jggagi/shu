"""Author original vector full-body four-direction walk sheets, without cloud art.

Every cell has the same foot anchor. The atlas is a native SVG asset imported by
Godot; it does not reuse indoor portraits, sword-camera frames or Chengping art.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/art/shanxia_hd2d"
DIRECTIONS = ["down", "up", "left", "right"]
CELL = (80, 112)


def person(direction: str, frame: int, player: bool) -> str:
    side = direction in ["left", "right"]
    back = direction == "up"
    swing = [0, 5, 0, -5][frame]
    bob = [0, -1, 0, -1][frame]
    robe = "#668d99" if player else "#987c5c"
    dark = "#3f6370" if player else "#6e5944"
    light = "#9cb8bf" if player else "#c1a581"
    hair, skin, line = "#3c3b35", "#e8c9a1", "#4e514a"
    p = [f'<g stroke="{line}" stroke-width="1.25" stroke-linejoin="round" stroke-linecap="round">']
    if direction == "left":
        p.append('<g transform="translate(80 0) scale(-1 1)">')
    # Legs and shoes are always visible beneath the hem, in all four views.
    for index, x in enumerate([31, 46] if not side else [34, 44]):
        stride = swing if index == 0 else -swing
        p.append(f'<path d="M{x} 82 L{x+stride*.35} {98-abs(stride)*.35}" stroke="#e6dfc8" stroke-width="8"/>')
        p.append(f'<path d="M{x+stride*.35-4} {101-abs(stride)*.35} Q{x+stride*.35+2} {98-abs(stride)*.35} {x+stride*.35+8} {101-abs(stride)*.35} L{x+stride*.35+8} {104-abs(stride)*.35} L{x+stride*.35-4} {104-abs(stride)*.35}Z" fill="{hair}"/>')
    p.append(f'<g transform="translate(0 {bob})">')
    if back and player:
        p.append('<path d="M31 45 Q20 57 23 89 L55 90 Q59 63 48 45Z" fill="#b2c0b8"/>')
    p.append(f'<path d="M29 43 Q40 39 51 43 L56 73 L60 88 Q40 94 20 88 L24 73Z" fill="{robe}"/>')
    p.append(f'<path d="M40 47 L40 89 L57 87 L51 49Z" fill="{dark}" stroke="none" opacity=".65"/>')
    p.append(f'<path d="M27 72 L22 87 M33 73 L30 88 M46 73 L51 88" fill="none" stroke="{light}"/>')
    # Two sleeves and hands use opposing travel, rather than a translated body.
    for index, x in enumerate([26, 54]):
        dy = swing * (.7 if index == 0 else -.7)
        outward = -1 if index == 0 else 1
        p.append(f'<path d="M{x} 46 Q{x+outward*5} 50 {x+outward*8} {64+dy} L{x+outward*1} {68+dy} L{x-outward*3} 54Z" fill="{robe}"/>')
        p.append(f'<path d="M{x+outward*8} {63+dy} L{x+outward*1} {67+dy}" stroke="{light}" stroke-width="3"/>')
        p.append(f'<ellipse cx="{x+outward*5}" cy="{70+dy}" rx="3.2" ry="4" fill="{skin}"/>')
    if not back:
        p.append('<path d="M30 44 L40 57 L48 44 L44 42 L39 51 L34 42Z" fill="#e5ddc5"/>')
    p.append('<path d="M25 65 Q40 68 55 65 L55 71 Q40 73 25 71Z" fill="#d2c39f"/>')
    p.append('<path d="M44 68 L49 68 L53 84 L47 81Z" fill="#b7a786"/>')
    if not player:
        p.append('<path d="M30 50 L48 50 L53 84 Q40 88 28 84Z" fill="#d5c7a4"/>')
        p.append('<path d="M34 74 L45 74 L46 81 L34 81Z" fill="#b1a183"/>')
    # A full head, bun and directional silhouette; back view hides the face.
    p.append(f'<ellipse cx="40" cy="29" rx="16" ry="18" fill="{hair}"/>')
    if back:
        p.append('<path d="M30 28 Q40 38 50 28 L51 42 Q41 49 29 42Z" fill="#363a34"/>')
        if player:
            p.append('<path d="M42 32 Q49 43 43 55" fill="none" stroke="#343b35" stroke-width="6"/>')
    elif side:
        p.append(f'<path d="M38 17 Q50 14 52 28 L58 33 L52 36 Q51 45 41 45 L35 38Z" fill="{skin}"/>')
        p.append(f'<path d="M31 20 Q38 10 49 16 L52 23 L44 22 L41 31 L36 34 L34 43 L28 37Z" fill="{hair}"/>')
        p.append('<path d="M49 29 L51 29" stroke="#45443c" stroke-width="2"/>')
        p.append('<path d="M50 39 L53 38" fill="none" stroke="#ad8465"/>')
        p.append(f'<ellipse cx="37" cy="33" rx="3.5" ry="4.5" fill="{skin}"/>')
    else:
        p.append(f'<path d="M27 25 Q40 18 53 25 L52 38 Q48 47 40 48 Q32 47 28 38Z" fill="{skin}"/>')
        p.append(f'<path d="M25 26 Q23 13 40 12 Q57 15 55 29 L48 23 L43 27 L37 22 L30 28Z" fill="{hair}"/>')
        p.append('<path d="M31 31 L36 31 M44 31 L49 31" fill="none" stroke="#5a4e3e"/>')
        p.append('<ellipse cx="34" cy="34" rx="1.3" ry="1.8" fill="#3b403b" stroke="none"/><ellipse cx="46" cy="34" rx="1.3" ry="1.8" fill="#3b403b" stroke="none"/>')
        p.append('<path d="M38 41 Q40 42 43 40" fill="none" stroke="#a77e62"/>')
    p.append(f'<ellipse cx="39" cy="10" rx="6.5" ry="5" fill="{hair}"/>')
    band = "#d9dac0" if player else "#75654e"
    p.append(f'<path d="M26 22 Q40 17 54 22" fill="none" stroke="{band}" stroke-width="3"/>')
    if player:
        p.append(f'<path d="M27 22 L20 38 L25 36 L25 42 L31 24Z" fill="{band}" stroke="none"/>')
    p.append('</g>')
    if direction == "left":
        p.append('</g>')
    p.append('</g>')
    return ''.join(p)


def sheet(player: bool) -> str:
    output = ['<svg xmlns="http://www.w3.org/2000/svg" width="320" height="448" viewBox="0 0 320 448">']
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
