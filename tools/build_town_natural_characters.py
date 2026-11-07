#!/usr/bin/env python3
"""Author Shu's original, foot-stable natural town cast as native SVG.

This generator writes only assets/art/town_natural_characters. It never rewrites
legacy sheets. No raster generator, third-party artwork or network is involved.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art/town_natural_characters"
DIRECTIONS = ["down", "up", "left", "right"]
CELL = [80, 112]
FOOT = [40, 104]
INPUTS = [
    "tools/build_town_hd2d_characters.py", "tools/build_town_tea_seller_life.py",
    "tools/build_town_tea_patron.py", "tools/build_town_painted_characters.py",
    "assets/art/shanxia_hd2d/player-walk.svg", "assets/art/shanxia_hd2d/tea-seller-walk.svg",
    "assets/art/shanxia_hd2d/source.json", "assets/art/shanxia_polish/tea-seller-life.svg",
    "assets/art/shanxia_polish/tea-seller-life-source.json",
    "assets/art/shanxia_polish/tea-patron.svg", "assets/art/shanxia_polish/tea-patron-source.json",
    "assets/art/town_painted_street/tea-seller-life.svg",
    "assets/art/town_painted_street/palette-source.json",
]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def n(value: float) -> str:
    return f"{value:.3f}".rstrip("0").rstrip(".") or "0"


def path(d: str, fill: str, stroke: str | None = None, width: float = .65, extra: str = "") -> str:
    edge = f' stroke="{stroke}" stroke-width="{n(width)}"' if stroke else ' stroke="none"'
    return f'<path d="{d}" fill="{fill}"{edge}{extra}/>'


def line(d: str, colour: str, width: float = .65, opacity: float = 1) -> str:
    return path(d, "none", colour, width, f' opacity="{n(opacity)}"')


def ellipse(cx: float, cy: float, rx: float, ry: float, fill: str, stroke: str | None = None, width: float = .6) -> str:
    edge = f' stroke="{stroke}" stroke-width="{n(width)}"' if stroke else ' stroke="none"'
    return f'<ellipse cx="{n(cx)}" cy="{n(cy)}" rx="{n(rx)}" ry="{n(ry)}" fill="{fill}"{edge}/>'


def defs() -> str:
    return ('<defs>'
        '<linearGradient id="blue-robe" x1="0" y1="0" x2=".85" y2=".9"><stop stop-color="#9aafaf"/><stop offset=".46" stop-color="#859fa6"/><stop offset="1" stop-color="#66818d"/></linearGradient>'
        '<linearGradient id="brown-robe" x1="0" y1="0" x2=".9" y2="1"><stop stop-color="#b0a084"/><stop offset="1" stop-color="#8f8067"/></linearGradient>'
        '<linearGradient id="skin" x1="0" y1="0" x2=".75" y2="1"><stop stop-color="#efd9b9"/><stop offset=".7" stop-color="#e6c9a3"/><stop offset="1" stop-color="#d5b28c"/></linearGradient>'
        '<linearGradient id="linen" x1="0" y1="0" x2=".9" y2="1"><stop stop-color="#ede5cf"/><stop offset="1" stop-color="#cfc4a8"/></linearGradient>'
        '<linearGradient id="apron" x1="0" y1="0" x2=".85" y2="1"><stop stop-color="#ded3b3"/><stop offset="1" stop-color="#bdae8e"/></linearGradient>'
        '<linearGradient id="patron-robe" x1="0" y1="0" x2=".9" y2="1"><stop stop-color="#9cab98"/><stop offset="1" stop-color="#788e80"/></linearGradient>'
        '<linearGradient id="patron-skin" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#efd9b9"/><stop offset="1" stop-color="#d9b891"/></linearGradient>'
        '</defs>')


def head(direction: str, blink: bool = False, hair_sway: float = 0, merchant: bool = False) -> str:
    """A 31px crown-to-jaw head, with a short neck below the jaw."""
    back, side = direction == "up", direction in ("left", "right")
    o = []
    # Neck stays behind the short chin shadow instead of joining cheek to robe.
    o.append(path("M36 36 L44 36 L45 45 Q40 48 35 44Z", "#d9ba95", "#bfa98d", .55))
    o.append(path("M36 37 Q40 41 44 37 L44.5 41.5 Q39 44 35.5 41Z", "#ba9b7d"))
    o.append(path("M28 23 Q27 12 38 10.5 Q50 9 53 20 L52 32 Q48 40 39 40.5 Q30 39 28.5 32Z", "#514b42", "#514b42", .55))
    o.append(path("M35 12 Q31.5 6.5 38 6.7 Q45.5 5.6 46 11.8 L43 15Z", "#514b42"))
    o.append(line("M36 10 Q40 7.6 43 10", "#837663", .65, .7))
    if back:
        o.append(path("M30 22 Q40 29 51 22 L50 33 Q44 40.5 35 38.6 L30 33Z", "#605548"))
        o.append(line("M33 20 Q31 28 35 33 M38 20 Q36 30 40 36 M45 20 Q49 28 46 34", "#8c7c66", .65, .7))
        o.append(path(f"M41 33 Q{n(47+hair_sway)} 42 {n(42+hair_sway)} 52 L{n(38+hair_sway)} 50 Q42 42 38.5 35Z", "#5e5144"))
        o.append(line(f"M42 38 Q{n(44+hair_sway)} 45 {n(41+hair_sway)} 48", "#8d7d64", .55, .65))
    elif side:
        o.append(path("M38 17 Q47 14 50 23 L51.5 27 L55 29 L51.3 31.1 Q50 37 44 39.5 Q37.5 39 35 34 L33.5 25Z", "url(#skin)", "#b9a386", .55))
        o.append(path("M29 23 Q29 13 39.5 12 Q48 11.5 51.5 21 L46.5 20.5 L43 23 L39 21.5 Q39 27 34.5 31 L33.5 38 L30 35 L30.5 27 L27.5 28Z", "#514b42"))
        o.append(path("M47 34 Q49 36.5 51 33 L50 36 Q47 39 43 39.5 L40 38Z", "#d4b28f"))
        o.append(line("M32 20 Q35 16.5 40 16 M31.5 24 L35 20.5", "#8d7c65", .65, .75))
        o.append(ellipse(36.3, 28.7, 2.25, 3.15, "#e7c8a1", "#c2a480", .5))
        o.append(line("M35.7 28 Q37.5 27 37 30", "#bd9c79", .5))
        o.append(line("M45.2 25.6 Q47.4 24.8 49.2 25.6", "#82705a", .7))
        if blink:
            o.append(line("M46.2 28 Q47.4 29.1 49 28", "#66584a", .85))
        else:
            o.append(ellipse(47.6, 28, .9, 1.45, "#584c3d"))
            o.append(ellipse(47.4, 27.55, .23, .32, "#f6e8cc"))
        o.append(ellipse(48.1, 32.2, 1.8, .8, "#d7a68d"))
        o.append(line("M46.6 35.5 Q48.6 36.6 50.4 35", "#af8d73", .55))
    else:
        o.append(path("M30 22 Q40 17.3 50.5 22.2 L49.6 31 Q47.8 38 40.2 40 Q32.2 37.6 30.5 31.1Z", "url(#skin)", "#c2aa8b", .55))
        o.append(path("M46 24 Q49 28 48.2 32.5 Q46.5 36.5 40.2 40 L43.5 39.7 Q49 37 50.2 31.5 L50.5 24Z", "#d7b68f"))
        o.append(path("M28.4 24 Q27 14.5 37.2 12 Q48.8 10 52.2 21.5 L48 25 L46 21.1 L42.3 24 L39.5 20.8 L35.5 24 L33.8 21.4 L30 27Z", "#514b42"))
        o.append(line("M31.5 19.5 Q35.8 15.4 40.2 16 M44 16.6 Q48 17 49 20", "#8e7d65", .65, .7))
        o.append(line("M33.4 26.2 Q35.5 25.2 37.5 26 M43 26 Q45.5 25.2 47.4 26.1", "#8a725a", .65))
        if blink:
            o.append(line("M33.8 29 Q35.4 30.3 37.1 29 M43.3 29 Q45 30.2 46.8 28.9", "#6b5947", .85))
        else:
            o.append(ellipse(35.4, 28.9, 1.02, 1.52, "#594c3c"))
            o.append(ellipse(45, 28.9, .98, 1.5, "#594c3c"))
            o.append(ellipse(35.15, 28.45, .28, .36, "#f7ebd1"))
            o.append(ellipse(44.75, 28.45, .26, .34, "#f7ebd1"))
        o.append(ellipse(32.5, 32.9, 2.2, .85, "#d9ad91"))
        o.append(ellipse(47.2, 32.9, 2, .8, "#d6a58a"))
        o.append(line("M39.5 31.2 L40.3 32.2 M38.2 35.5 Q40.7 36.9 42.7 35.1", "#b08c6c", .55))
        if merchant:
            o.append(line("M38.2 34 Q40.3 33.2 42.3 34 M39.8 38.2 L42 37.9", "#88705a", .6))
    band = "#c6b18e" if merchant else "#e4dfc8"
    o.append(line("M29.6 20.2 Q40.3 16.1 51.1 20.6", band, 1.8))
    if not merchant:
        o.append(path(f"M30 20.2 Q{n(26+hair_sway)} 25.3 {n(26.8+hair_sway)} 35.5 L{n(29.5+hair_sway)} 33.5 L{n(30.6+hair_sway)} 37.5 L33 22Z", "#e6e1cc", "#c1bba2", .4))
        o.append(line(f"M30 24 L{n(28.3+hair_sway)} 31.5", "#f2edd8", .75))
    return ''.join(o)


def leg(index: int, travel: float, lift: float, side: bool, back: bool, idle: bool = False) -> str:
    base = (37.5 if index == 0 else 42.5) if side else (33.6 if index == 0 else 46)
    foot_x = base + (travel if side else travel * .095)
    # Supporting sole stays on the authored y104 ground line. The recovering
    # foot folds at the knee rather than moving the whole character upward.
    sole = 104 - lift
    hip_x = 36.2 if index == 0 else 44
    knee_x = (hip_x + foot_x) * .5 + (2.5 + lift*.32 if side else (-1 if index == 0 else 1) * lift*.18)
    knee_y = 90.3 - lift*.40
    shade = "#b8b9a5" if index == 0 else "#d4d1b9"
    p = [path(f"M{n(hip_x-3)} 81 L{n(hip_x+3)} 81 Q{n(knee_x+3)} {n(knee_y-1)} {n(foot_x+2.8)} {n(sole-4.2)} L{n(foot_x-3)} {n(sole-4.2)} Q{n(knee_x-3)} {n(knee_y+1)} {n(hip_x-3)} 81Z", shade, "#9c9f8d", .55)]
    p.append(line(f"M{n(hip_x+.2)} 84 Q{n(knee_x+.7)} {n(knee_y)} {n(foot_x+.2)} {n(sole-6.3)}", "#ede4ca" if index else "#c9cdb6", .65, .75))
    if side:
        p.append(path(f"M{n(foot_x-3.8)} {n(sole-6)} L{n(foot_x+2.7)} {n(sole-5.6)} Q{n(foot_x+4.5)} {n(sole-2.4)} {n(foot_x+8.3)} {n(sole-1.7)} L{n(foot_x+8.7)} {n(sole-.4)} Q{n(foot_x+2.3)} {n(sole)} {n(foot_x-4)} {n(sole-.4)}Z", "#5d5a50", "#686458", .55))
        p.append(line(f"M{n(foot_x-2.5)} {n(sole-1.2)} L{n(foot_x+6.8)} {n(sole-1.2)}", "#b7ac90", .65))
    elif back:
        p.append(path(f"M{n(foot_x-3.5)} {n(sole-6.7)} L{n(foot_x+3.6)} {n(sole-6.5)} L{n(foot_x+4.6)} {n(sole-.5)} Q{n(foot_x)} {n(sole+.1)} {n(foot_x-4.1)} {n(sole-.5)}Z", "#615e52", "#777264", .55))
        p.append(line(f"M{n(foot_x-2.9)} {n(sole-4.5)} L{n(foot_x+3.1)} {n(sole-4.5)}", "#b6ab90", .6))
    else:
        toe = (-.8 if index == 0 else 1.2) if idle else travel*.035
        p.append(path(f"M{n(foot_x-3.2)} {n(sole-6.4)} L{n(foot_x+3.3)} {n(sole-6)} Q{n(foot_x+6+toe)} {n(sole-3.8)} {n(foot_x+5.8+toe)} {n(sole-.7)} Q{n(foot_x+.3)} {n(sole+.1)} {n(foot_x-4.9+toe)} {n(sole-.7)} Q{n(foot_x-5.5+toe)} {n(sole-4)} {n(foot_x-3.2)} {n(sole-6.4)}Z", "#5d5b50", "#726e5f", .55))
        p.append(line(f"M{n(foot_x-3.1+toe)} {n(sole-1.5)} Q{n(foot_x+.4)} {n(sole-.8)} {n(foot_x+4.4+toe)} {n(sole-1.5)}", "#c1b496", .65))
    return ''.join(p)


def sleeve(shoulder_x: float, hand_x: float, hand_y: float, far: bool = False, side: bool = False) -> str:
    shoulder_y = 46.2 if far else 45.5
    elbow_x = shoulder_x + (hand_x-shoulder_x)*.58
    elbow_y = 59.5
    colour = "#728b92" if far else "url(#blue-robe)"
    p = [path(f"M{n(shoulder_x-3.6)} {n(shoulder_y)} Q{n(elbow_x-5)} {n(elbow_y-3)} {n(hand_x-4.6)} {n(hand_y-4.5)} Q{n(hand_x)} {n(hand_y-1.3)} {n(hand_x+4.3)} {n(hand_y-4)} L{n(elbow_x+4.1)} {n(elbow_y-2)} Q{n(shoulder_x+4.8)} {n(shoulder_y-1)} {n(shoulder_x-3.6)} {n(shoulder_y)}Z", colour, "#748a8a", .65)]
    p.append(path(f"M{n(hand_x-4.5)} {n(hand_y-5)} Q{n(hand_x)} {n(hand_y-2.5)} {n(hand_x+4.1)} {n(hand_y-4.4)} L{n(hand_x+4)} {n(hand_y-.8)} Q{n(hand_x)} {n(hand_y+1)} {n(hand_x-4.2)} {n(hand_y-1)}Z", "url(#linen)", "#c0baa1", .5))
    p.append(path(f"M{n(hand_x-2.5)} {n(hand_y-.2)} Q{n(hand_x+1.8)} {n(hand_y-1.3)} {n(hand_x+2.6)} {n(hand_y+2.1)} L{n(hand_x+1.8)} {n(hand_y+5)} Q{n(hand_x-1.5)} {n(hand_y+5.6)} {n(hand_x-2.5)} {n(hand_y+2)}Z", "url(#skin)", "#bda788", .5))
    p.append(line(f"M{n(shoulder_x-1)} {n(shoulder_y+6)} Q{n(elbow_x-1.2)} {n(elbow_y)} {n(hand_x-1.7)} {n(hand_y-7)}", "#b5c2b6" if not far else "#95aca8", .65, .9))
    return ''.join(p)


def player(direction: str, column: int) -> str:
    side, back = direction in ("left", "right"), direction == "up"
    idle = column >= 8
    phase = column if not idle else 0
    theta = phase * math.tau / 8
    travel = [20, 10, 0, -10, -20, -16, 0, 16]
    lifts = [0, 0, 0, 0, 0, 6, 8, 4]
    t0, t1 = (0, 0) if idle else (travel[phase], travel[(phase+4)%8])
    l0, l1 = (0, 0) if idle else (lifts[phase], lifts[(phase+4)%8])
    breath = [0, -.25, -.5, 0][column-8] if idle else 0
    bob = 0 if idle else [0, .65, 0, -.65, 0, .65, 0, -.65][phase]
    sway = .25 if idle else math.sin(theta)*.42
    lag = 0 if idle else math.sin(theta-math.pi/4)
    arm = 0 if idle else math.cos(theta)
    o = ['<g stroke-linecap="round" stroke-linejoin="round">']
    if direction == "left":
        o.append('<g transform="translate(80 0) scale(-1 1)">')
    # The leg nearer the viewer is painted last; this reverses at each pass.
    order = [0, 1] if t0 <= t1 else [1, 0]
    for i in order:
        o.append(leg(i, (t0,t1)[i], (l0,l1)[i], side, back, idle))
    o.append(f'<g transform="translate({n(sway)} {n(bob)})">')
    if side:
        o.append(sleeve(36, 36-arm*7.4, 69+abs(arm)*.55+breath, True, True))
    else:
        o.append(sleeve(29, 27-arm*.9, 70.7+arm*3.1+breath, True))
    # Tail and skirt follow, rather than matching, the arm/leg extremes.
    if side:
        o.append(path(f"M35 68 L46 67 Q{n(50+lag*1.2)} 79 {n(54+lag*1.5)} 91 Q41 94.3 28 91.4 L31 77Z", "url(#blue-robe)", "#708787", .7))
        o.append(path(f"M34 72 Q32.5 82 {n(30+lag*.4)} 90.8 Q36 92.5 40 92 L39 72Z", "#728a91"))
        o.append(path(f"M44 75 Q{n(48+lag)} 83 {n(51+lag)} 91 L47 92 L41 76Z", "#a2b6b3"))
    else:
        o.append(path(f"M29 67 L50 67 L52 77 Q{n(55+lag)} 84 {n(57+lag*.8)} 91 Q48 94 40 92 Q30 95 23 91 L27 77Z", "url(#blue-robe)", "#708887", .65))
        o.append(path(f"M41 70 Q44 81 42 92 Q50 94 {n(57+lag*.8)} 91 L51 76 L48 69Z", "#6d8790"))
        o.append(path("M30 73 Q28 84 26 90 Q31 92 34 92 L36 73Z", "#9bb3b1"))
    o.append(line(f"M32 77 Q31 86 {n(29+lag*.4)} 90 M43 78 L{n(47+lag*.6)} 90", "#bac8bc", .7, .9))
    o.append(line(f"M38 78 Q37 85 {n(38+lag*.25)} 91", "#667f88", .55, .8))
    # Chest breathes by less than half a source pixel; its leg group is outside
    # this transform, so neither foot nor the actor origin is displaced.
    o.append(f'<g transform="translate(0 {n(breath)})">')
    if side:
        o.append(path("M34 44 Q40.5 41 46.5 44.5 L48.5 59.5 L47 71.5 Q40 74 31 71 L32 58Z", "url(#blue-robe)", "#748b8a", .65))
        o.append(path("M43 46 Q47.8 52.5 47.2 64 L46 71.7 L41 72 L40 52Z", "#6d8790"))
        o.append(path("M34 46 L39 43 L43 46 L40 60 L35 54Z", "url(#linen)"))
        o.append(line("M39 46 L39 55", "#b9b69f", .6))
    else:
        o.append(path("M29.5 44 Q35.2 41.5 39.8 43 Q45 41.5 50.5 44 L51.2 56 L50.2 70.5 Q40 74 27.8 70.5 L28.8 56Z", "url(#blue-robe)", "#758c8a", .65))
        o.append(path("M44.2 45 Q47.7 56 45.5 64 L49.4 70.5 L51 69.5 L50 47Z", "#698590"))
        o.append(path("M30.5 45 Q33 50 31 60 L29 69 L33.7 71 L36.3 49Z", "#a6bab6"))
        if not back:
            o.append(path("M31 44 L36.5 41 L40.6 47.5 L45.3 41.5 L49.2 44 L40 61Z", "url(#linen)"))
            o.append(line("M33.8 45 L40.2 55 L46.4 45", "#c0bca1", .65))
            o.append(line("M40.4 57 L40.4 65", "#b8c4b6", .65))
        else:
            o.append(line("M32 46 Q39 43.5 47 46 M38.7 47 L39.7 65", "#b4c4b7", .65))
    o.append(path("M28.8 66.5 Q40 69.4 50.4 66.5 L50 71 Q40.2 74 28.4 71Z", "url(#linen)", "#bcb69a", .5))
    o.append(path(f"M42.7 69 L46.4 70.5 L{n(49+lag*.8)} 83.2 L{n(45.5+lag*.8)} 82 L43.7 74.2 L40.9 73.1Z", "#ded8bd", "#b4b59e", .45))
    o.append(line("M30.2 68.4 Q39.8 70.4 48.7 68.4", "#f0e6cd", .65))
    o.append('</g>')
    if side:
        o.append(sleeve(44.5, 44.5+arm*7.5 if not idle else 46, 70.4-abs(arm)*.35+breath, False, True))
    else:
        o.append(sleeve(50, 53+arm*.9 if not idle else 53.6, 71-arm*3.1+breath, False))
    o.append(f'<g transform="translate(0 {n(breath*.45)})">{head(direction, column == 11, lag*.55)}</g>')
    o.append('</g>')
    if direction == "left":
        o.append('</g>')
    o.append('</g>')
    return ''.join(o)


def player_sheet() -> str:
    p = ['<svg xmlns="http://www.w3.org/2000/svg" width="960" height="448" viewBox="0 0 960 448">',
         '<title>Shu original natural town player</title>',
         '<desc>Four directions, eight complete walk phases followed by neutral, two restrained upper-body breathing poses and a blink. Every cell is 80 by112, foot anchor40,104.</desc>', defs()]
    for row, direction in enumerate(DIRECTIONS):
        for column in range(12):
            p.append(f'<g id="player-{direction}-{column}" transform="translate({column*80} {row*112})">{player(direction,column)}</g>')
    return ''.join(p)+'</svg>\n'


def merchant_sheet() -> tuple[str, list[str]]:
    # Importing these authoring functions does not call their guarded main or
    # write a legacy product. Their six working hand/cup poses remain the source
    # of truth while the independently drawn head and weight-bearing body change.
    import build_town_tea_seller_life as original
    p = ['<svg xmlns="http://www.w3.org/2000/svg" width="480" height="112" viewBox="0 0 480 112">',
         '<title>Shu original natural tea seller</title>',
         '<desc>Six original cup-work hand poses with a newly drawn, relaxed brown-clothed adult seller. Cell80,112 and ground anchor40,104. Original cup and hand trajectories retained.</desc>', defs()]
    for index, pose in enumerate(original.POSES):
        p.append(f'<g id="natural-seller-{index}" transform="translate({index*80} 0)" stroke-linecap="round" stroke-linejoin="round">')
        # An almost straight support leg and a slightly relaxed second knee are
        # visible below the apron. Feet remain outside all upper-body groups.
        p.append(path("M30.7 80.5 L38.2 81 L37.3 91.5 L36.8 99 L30.5 99 L30.7 90Z", "#d1ccb3", "#a8aa94", .6))
        p.append(path("M42.5 81 L49.4 80.5 Q48.2 89 48.7 91 L47.3 99 L41.2 99 L42.6 91 L41.4 87Z", "#c2c0a8", "#a2a38d", .6))
        p.append(line("M33.5 86 L33.5 95 M45.2 88 L44.7 96", "#e9dfc4", .7))
        p.append(path("M30.2 97.5 L36.6 97.3 Q39.2 99.4 39.1 103.3 Q33.6 104.2 28.4 103.4 Q27.8 100.4 30.2 97.5Z", "#635e51", "#77715e", .55))
        p.append(path("M41.9 97.3 L47.5 97.4 Q51.5 99.5 52.6 102.3 L52.5 103.4 Q46.8 104.1 40.4 103.4 L40.5 99.5Z", "#5e5b50", "#77715e", .55))
        p.append(line("M29.9 102.3 Q34 103.1 37.6 102.4 M42 102.3 L50.9 102.3", "#b9ad8f", .7))
        p.append(path("M28.7 44.5 Q34.7 41.8 39.2 43 Q45.8 41.4 50.3 44.5 L52.2 67 Q51.8 77.7 56.6 89 Q45.3 93 39.4 91 Q29.6 93.2 24.7 89 L28.3 68Z", "url(#brown-robe)", "#8e826c", .65))
        p.append(path("M43.5 45 Q49 57 46.6 69 L51 89.8 L55.4 89.3 L51.3 67 L49.5 46Z", "#887b64"))
        p.append(path("M30.1 46 Q32.3 55 29.6 68 L27 88.6 L32 90 L35.2 59 L34.1 44Z", "#c1af8e"))
        # The neck is now explicit and the jaw has an underside shadow, making
        # the retained cup work feel supported by shoulders rather than a doll.
        p.append(path("M31.8 44.3 L36.7 41 L40.3 48.4 L45.2 41.6 L49 44.7 L40 61Z", "url(#linen)"))
        p.append(line("M34.7 45.8 L40.3 55 L46.3 45.8", "#bfb79c", .6))
        # Original working sleeves keep exactly the authored arm/cup endpoints.
        arms = original.arms(pose).replace('#a38b69','url(#brown-robe)').replace('#c7b493','#c7b99b').replace('#e5d9bb','#e1d8bf')
        p.append(f'<g stroke="#998d75" stroke-width=".6">{arms}</g>')
        p.append(path("M33.6 50.7 Q40.6 52.9 47.1 50.9 L47.9 65.2 L53 86.7 Q41.6 91.7 28.8 87 L32.2 65Z", "url(#apron)", "#b1a68a", .6))
        p.append(path("M43.7 54.5 Q45 68 47.2 76 L50.1 87.4 L53 86.6 L47.9 65.2 L47.1 50.9Z", "#b9ac8c"))
        p.append(path("M34.3 54 Q35 68 32.7 84.8 L35.6 87.6 L39.1 61 L38.4 53Z", "#e7ddc0"))
        p.append(line("M34.3 50.9 L34 46.8 M46.7 51.1 L46.6 47.5 M31.5 84 Q41.8 88.8 50.1 85.6", "#eee4c8", .9))
        p.append(path("M35.3 73.1 Q40.3 74.2 45.9 73.1 L45.4 80 Q40.4 81.9 35.5 80Z", "#c0b28f", "#ad9f7e", .5))
        p.append(line("M36.7 75 Q40.3 76 44.5 74.8", "#e2d5b6", .65))
        p.append(path("M29 64 L29 78 L35 80 L36 65Z", "#e8dfc6", "#b5ad90", .5))
        p.append(line("M31 69 L34 70 M31 73 L34 74", "#b0bcab", .6))
        props = original.props(pose).replace('#7b8e84','#87958a').replace('stroke-width=".8"','stroke-width=".65"').replace('#bdb49a','#bfb59a')
        p.append(f'<g stroke="#ad977b" stroke-width=".55">{props}</g>')
        p.append(head('down', False, 0, True))
        p.append('</g>')
    return ''.join(p)+'</svg>\n', [x['id'] for x in original.POSES]


def patron_sheet() -> tuple[str, list[str]]:
    import build_town_tea_patron as original
    p = ['<svg xmlns="http://www.w3.org/2000/svg" width="192" height="96" viewBox="0 0 192 96">',
         '<title>Shu original natural seated tea patron</title>',
         '<desc>The three original cup poses retain exact seat31,58 and foot32,80. Local-colour outlines and broad warm/cool planes soften the original seated silhouette without moving its contact geometry.</desc>', defs()]
    for index, pose in enumerate(original.POSES):
        p.append(f'<g id="natural-patron-{index}" transform="translate({index*64} 0)" stroke-linecap="round" stroke-linejoin="round">')
        # Seat and sole curves are used unchanged. Different edge colours divide
        # trouser, robe, skin and hair instead of one black enclosing contour.
        p.append(f'<g stroke="#a2aa94" stroke-width=".6">{original.LEGS}</g>')
        p.append(f'<g stroke="#7d9282" stroke-width=".6">{original.BODY}</g>')
        p.append(path("M23 36 Q25 42 23.7 49 L26.1 55 L34.5 58.6 L39 60.9 Q28 62.2 21 58.7 L20 48Z", "#aab6a0"))
        p.append(path("M34.1 37.5 Q38 42 37.6 48.5 L43.5 56.4 L41.8 60.7 L37.1 58.5 L32.9 47.2Z", "#6f897b"))
        p.append(line("M24 42 Q23.4 49 27.1 54.6 M30.6 55 Q35.4 57.4 39.5 57.8", "#bec8ac", .75))
        # A small neck plane sits under the unchanged jaw and behind the hands.
        p.append(path("M28.7 32.5 L34.7 33.3 L35.2 37.5 L32 41.8 L28.4 38.4Z", "#c5aa88"))
        arms = original.hands_and_cup(pose).replace('#7f9385','#859a87').replace('#b4c0ad','#bdc8ae').replace('#7b8e84','#8b9a8b').replace('stroke-width=".7"','stroke-width=".55"')
        h = original.HEAD_ART.replace('#4c433d','#595043').replace('#a58c6f','#b59e7f').replace('#463f36','#5a4e3d').replace('#7b6b58','#95836a').replace('stroke-width=".7"','stroke-width=".55"')
        p.append(f'<g stroke="#84755f" stroke-width=".55">{h}</g>')
        # A warm side-of-face shadow and a broken lit cheek rim add volume while
        # keeping the original head/cup relation and fixed seat intact.
        p.append(path("M42.3 15.8 L44.8 20.4 L47 21 L50 23 L46 26 Q45 33 39 35 L35.8 34.6 Q42.7 32.3 43.8 26.3Z", "#d2b18c"))
        p.append(line("M31.8 14.1 Q37.8 11.7 41.3 15 M28 28.3 Q29.3 32.6 34.7 33.3", "#efdfbf", .75))
        p.append(f'<g stroke="#95a18d" stroke-width=".55">{arms}</g>')
        p.append('</g>')
    return ''.join(p)+'</svg>\n', [x['id'] for x in original.POSES]


def write_asset(filename: str, data: str) -> dict:
    destination = OUT / filename
    destination.write_text(data, encoding="utf-8")
    return {"path": str(destination.relative_to(ROOT)), "sha256": sha(destination), "bytes": destination.stat().st_size}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--player-only", action="store_true", help="Write the first review sample and its provenance only")
    args = parser.parse_args()
    before = {p: sha(ROOT/p) for p in INPUTS}
    OUT.mkdir(parents=True, exist_ok=True)
    files = {"player": write_asset("player-motion.svg", player_sheet())}
    merchant_poses, patron_poses = [], []
    if not args.player_only:
        merchant_svg, merchant_poses = merchant_sheet()
        patron_svg, patron_poses = patron_sheet()
        files["tea_seller"] = write_asset("tea-seller-life.svg", merchant_svg)
        files["tea_patron"] = write_asset("tea-patron.svg", patron_svg)
    metadata = {
        "title": "Shu original natural town cast", "date": "2026-10-30", "provider": "nativeSVG",
        "author": "Original vector drawing and motion authored for Shu by Codex",
        "license": "Project-original; no external character artwork, model or commercial game asset copied",
        "method": "New head, neck, shoulder/chest/sleeve/skirt silhouettes; local-colour fine edges, warm shadow planes; native SVG motion construction. No raster generation, image editing or network call.",
        "generator": {"path": str(Path(__file__).resolve().relative_to(ROOT)), "sha256": sha(Path(__file__))},
        "legacy_inputs": [{"path": p, "sha256": digest, "role": "original project identity and anchored pose reference"} for p,digest in before.items()],
        "files": files,
        "player": {"frame_size": CELL, "atlas_size": [960,448], "columns": 12, "rows": 4, "directions": DIRECTIONS,
            "foot_anchor": FOOT, "anchor_origin": "top-left of cropped frame, source pixels", "world_height": 1.55,
            "walk_frames": list(range(8)), "idle_frames": [8,9,10,11],
            "presentation_tuning": {"B_walk_speed_logical_per_second": 150, "cycle_distance_logical": 90, "distance_per_phase_logical": 11.25, "cycle_seconds_at_B_speed": .6, "side_foot_travel_source_px": [20,10,0,-10,-20,-16,0,16], "recovering_foot_lift_source_px": [0,0,0,0,0,6,8,4], "scope": "Runtime integration target supplied by root; engine QA and actual stance slip still require real game capture"},
            "walk_pose_order": ["left_contact", "left_down_right_recover", "left_support_right_pass", "left_toe_right_reach", "right_contact", "right_down_left_recover", "right_support_left_pass", "right_toe_left_reach"],
            "idle_pose_order": ["relaxed_neutral", "upper_body_breathe_in", "upper_body_breathe_peak", "blink"],
            "contact": "At least one authored supporting shoe reaches the y104 source ground line in every walk pose. Recovering foot folds at knee; root foot anchor never translates.",
            "breathing": "Leg paths are byte-identical in all four idle poses. Only upper-body geometry moves: chest <=0.5px, head <=0.225px. No whole-person vertical transform while idle.",
            "proportion": "Approximately3.1 crown-to-jaw head lengths from crown to sole; short neck, jaw shadow and relaxed asymmetry. Cloth/headband follow the step by a half phase.",
            "time_authority": "Runtime supplies real walked distance for walk phases and existing frozen/resumed ambient_elapsed for idle; SVG owns no state or clock"},
        "tea_seller": {"frame_size": [80,112], "atlas_size": [480,112], "columns": 6, "rows": 1,
            "foot_anchor": [40,104], "anchor_origin": "top-left of cropped frame, source pixels", "world_height": 1.55,
            "pose_order": merchant_poses, "facing": "down; original adult brown-clothed male seller, fine moustache retained",
            "working_pose_contract": "Original sleeves/hands/cup/cloth trajectory coordinates and order retained from original generator; new short-neck head, relaxed torso/apron and locally coloured shadows. No shoulder/hand/cup group translations.",
            "time_authority": "existing seller life frame_index_at(stage ambient_elapsed), period14s"},
        "tea_patron": {"frame_size": [64,96], "atlas_size": [192,96], "columns": 3, "rows": 1,
            "seat_anchor": [31,58], "foot_anchor": [32,80], "head_anchor": [33,20],
            "anchor_origin": "top-left of cropped frame, source pixels", "world_height": 1.10,
            "pose_order": patron_poses, "facing": "seated profile facing right",
            "contact_contract": "Exact original leg and seated body curves, transforms and source anchors retained. Local-colour edges and broad cloth/neck/face planes added without translating seat, feet or hand/cup trajectory.",
            "time_authority": "existing patron life frame_index_at(stage ambient_elapsed), period12s"},
        "preservation": {"legacy_inputs_unchanged": before == {p:sha(ROOT/p) for p in INPUTS}, "writes_only": "assets/art/town_natural_characters/*"},
        "status": "candidate; original vector source and legacy byte preservation checked; actual Godot scene motion, contact, occlusion and user visual acceptance pending",
    }
    (OUT/"source.json").write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding="utf-8")
    print(json.dumps({"files":files,"source":"assets/art/town_natural_characters/source.json","legacy_inputs_unchanged":metadata["preservation"]["legacy_inputs_unchanged"]},ensure_ascii=False,indent=2))


if __name__ == "__main__":
    main()
