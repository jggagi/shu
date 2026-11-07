#!/usr/bin/env python3
"""Author Shu's transparent native-vector willow; no external image inputs."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art/shanxia_polish"
WIDTH, HEIGHT = 768, 896
FOOT = [384, 870]
PALETTE = ("#536d53", "#667c59", "#7b8a60", "#8c9569", "#a1a579")


def point(curve: tuple[tuple[float, float], ...], t: float) -> tuple[float, float]:
    s = 1 - t
    return tuple(s**3 * curve[0][i] + 3*s*s*t*curve[1][i] +
                 3*s*t*t*curve[2][i] + t**3*curve[3][i] for i in (0, 1))


def leaf(body: list[str], x: float, y: float, dx: float, dy: float,
         width: float, color: str, opacity: float) -> None:
    length = math.hypot(dx, dy)
    nx, ny = -dy / length * width, dx / length * width
    tipx, tipy = x + dx, y + dy
    body.append(
        f'<path d="M{x:.2f},{y:.2f} '
        f'Q{x+dx*.36+nx:.2f},{y+dy*.36+ny:.2f} {tipx:.2f},{tipy:.2f} '
        f'Q{x+dx*.51-nx*.65:.2f},{y+dy*.51-ny*.65:.2f} {x:.2f},{y:.2f}Z" '
        f'fill="{color}" opacity="{opacity:.3f}"/>'
    )


def spray(body: list[str], x: float, y: float, drift: float, length: float,
          seed: int, front: bool = False) -> None:
    rng = random.Random(seed)
    curve = ((x,y), (x + drift*.65,y+length*.13),
             (x+drift+rng.uniform(-16,16),y+length*.65), (x+drift,y+length))
    branch_width = rng.uniform(.65,1.4) if front else rng.uniform(.55,1.0)
    body.append(
        f'<path d="M{x:.2f},{y:.2f} C{curve[1][0]:.2f},{curve[1][1]:.2f} '
        f'{curve[2][0]:.2f},{curve[2][1]:.2f} {curve[3][0]:.2f},{curve[3][1]:.2f}" '
        f'fill="none" stroke="{rng.choice(("#65704e", "#7a8056", "#5a6d50"))}" '
        f'stroke-width="{branch_width:.2f}" stroke-opacity=".62" stroke-linecap="round"/>'
    )
    count = max(10, int(length/7.0))
    for i in range(count):
        t = (i + rng.uniform(.1,.8)) / count
        px, py = point(curve, t)
        size = rng.uniform(.85,1.15) * (1.0-t*.42)
        # Alternating leaves are long and narrow, all hanging below their stem.
        sides = (-1,1) if rng.random() > .16 else (rng.choice((-1,1)),)
        for side in sides:
            dx = side*rng.uniform(6,13)*size + drift*.035
            dy = rng.uniform(12,23)*size
            color = rng.choice(PALETTE[1:] if front else PALETTE[:4])
            leaf(body, px, py, dx, dy, rng.uniform(1.8,3.4)*size,
                 color, rng.uniform(.75,.98) if front else rng.uniform(.58,.84))


def build() -> str:
    rng = random.Random(28102811)
    body = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="768" height="896" viewBox="0 0 768 896">',
        '<title>Shu original riverside willow</title>',
        '<desc>Transparent native vector tree with asymmetric drooping foliage. Foot anchor 384,870. Original branches and leaf paths, no third-party artwork.</desc>',
        '<defs><linearGradient id="trunk" x1="0" y1="0" x2="1" y2="0">'
        '<stop stop-color="#565e4c"/><stop offset=".38" stop-color="#8b866e"/>'
        '<stop offset=".66" stop-color="#999077"/><stop offset="1" stop-color="#6c7059"/>'
        '</linearGradient></defs>',
        # Keep the canvas useful at a 3.5 m card height while retaining the exact foot anchor.
        '<g transform="translate(-38.4 -191.4) scale(1.1 1.22)">',
    ]
    # Broken, translucent washes group the leaflets without a solid canopy disc.
    washes = [
        ("M155,299 L179,263 198,270 216,236 236,254 253,221 274,248 298,227 312,254 343,246 353,282 332,324 303,310 281,343 252,325 224,345 199,317 171,326Z", "#7c8c65", .19),
        ("M353,235 L374,212 390,224 409,196 430,227 456,215 474,245 500,238 516,269 548,276 541,323 512,336 490,318 461,341 435,316 410,334 392,303 369,306Z", "#7c8c65", .17),
        ("M523,313 L544,280 570,302 591,288 608,317 637,313 649,342 671,347 654,381 629,376 606,406 580,387 553,398 535,369Z", "#7c8c65", .16),
        ("M105,332 Q153,281 205,299 Q236,255 303,285 Q335,252 398,279 Q432,246 488,279 Q533,264 573,304 Q629,277 671,331 L646,447 Q595,489 558,455 Q495,499 455,459 Q398,490 355,454 Q308,495 265,464 Q207,495 171,443 Q120,459 105,332Z", "#69815b", .12),
        ("M172,377 Q230,338 278,376 Q322,353 363,396 L342,501 Q303,525 266,490 Q218,530 183,485Z", "#83925f", .105),
        ("M419,351 Q466,302 524,342 Q584,315 632,355 L620,476 Q569,513 529,473 Q473,499 432,453Z", "#778961", .10),
    ]
    for path,color,opacity in washes:
        body.append(f'<path d="{path}" fill="{color}" opacity="{opacity}"/>')
    # Rear foliage hangs at unequal heights; the left curtain is longer and denser.
    groups = [
        (116,271,6,145,60), (177,233,9,210,86),
        (247,204,10,248,92), (316,194,8,221,80),
        (390,185,9,206,84), (467,207,9,249,83),
        (537,245,10,258,84), (605,281,8,215,78),
        (656,315,5,154,45), (177,344,7,278,79),
        (269,362,7,292,71), (491,347,7,241,87),
    ]
    for group_index,(gx,gy,count,length,spread) in enumerate(groups):
        for i in range(count):
            x = gx+(i/(count-1)-.5)*spread+rng.uniform(-8,8)
            y = gy+rng.uniform(-15,26)
            spray(body,x,y,rng.uniform(-28,25),length*rng.uniform(.66,1.08),
                  10000+group_index*100+i)
    # Main trunk is an authored silhouette, not a uniform cylinder or black outline.
    body.append('<path d="M353,871 Q367,849 370,808 Q376,756 372,704 '
                'Q368,649 373,599 Q376,546 391,508 Q402,472 402,441 '
                'Q396,403 406,369 L420,351 Q411,397 426,438 '
                'Q436,470 424,517 Q405,566 405,609 Q403,655 408,704 '
                'Q414,753 407,807 Q405,850 425,870 Q405,866 389,870 '
                'Q372,867 353,871Z" fill="url(#trunk)"/>')
    branches = [
        ("M393,597 Q360,538 318,505 Q269,464 243,418 Q220,369 175,320 Q155,297 122,288",15),
        ("M393,563 Q348,511 330,462 Q311,409 275,371 Q255,345 218,333",11),
        ("M409,516 Q455,459 492,430 Q547,388 593,374 Q635,355 662,354",14),
        ("M414,470 Q438,420 438,380 Q437,334 465,297 Q489,268 529,251",12),
        ("M405,421 Q379,374 347,337 Q314,298 276,281 Q241,263 215,265",9),
        ("M413,375 Q405,334 382,300 Q354,258 348,218",7),
        ("M334,467 Q305,450 274,448 Q225,442 191,458",5),
        ("M486,436 Q521,436 541,454 Q558,473 570,510",5),
        ("M456,313 Q445,275 423,244 Q406,221 381,211",4),
        ("M264,450 Q242,396 204,380 Q175,366 148,372",5),
        ("M588,375 Q604,340 598,310 Q594,291 575,276",4),
    ]
    for path,width in branches:
        body.append(f'<path d="{path}" fill="none" stroke="#75765d" '
                    f'stroke-width="{width}" stroke-linecap="round"/>')
        body.append(f'<path d="{path}" fill="none" stroke="#a09b7a" '
                    f'stroke-width="{max(1,width*.23):.2f}" stroke-opacity=".48" stroke-linecap="round"/>')
    # Longitudinal bark washes and slender fibres follow the trunk's bend.
    body.extend([
        '<path d="M382,859 Q394,794 389,732 Q383,665 390,607 Q390,554 408,507 Q423,469 414,422" fill="none" stroke="#b3aa87" stroke-width="5" opacity=".38"/>',
        '<path d="M373,846 Q384,792 380,730 Q375,652 383,599 Q385,562 399,526" fill="none" stroke="#535e49" stroke-width="2.2" opacity=".58"/>',
        '<path d="M401,843 Q407,802 401,748 Q397,696 399,653" fill="none" stroke="#505b47" stroke-width="2.2" opacity=".5"/>',
        '<path d="M389,645 Q378,630 383,612 Q391,597 398,610 Q405,628 389,645" fill="#5e6751" opacity=".56"/>',
        '<path d="M388,636 Q383,626 390,617 Q398,625 388,636" fill="none" stroke="#aaa080" stroke-width="1.7" opacity=".62"/>',
        '<path d="M357,868 Q369,855 375,842 M420,868 Q402,857 400,843" fill="none" stroke="#a49d7c" stroke-width="2.2" opacity=".45"/>',
    ])
    for i in range(39):
        y = rng.uniform(541,854)
        # Centreline near this trunk height, with fine discontinuous bark fibres.
        center = 390 + math.sin(y*.016)*5
        x = center+rng.uniform(-12,13)
        body.append(f'<path d="M{x:.2f},{y:.2f} q{rng.uniform(-3,3):.2f},'
                    f'{rng.uniform(3,7):.2f} {rng.uniform(-2,2):.2f},{rng.uniform(9,24):.2f}" '
                    'fill="none" stroke="#4d5b47" stroke-opacity=".28" stroke-width=".85"/>')
    # Foreground curtains cross selected boughs, leaving the central trunk readable.
    front_groups = [
        (149,294,6,274,71), (224,269,7,283,74),
        (298,251,6,228,72), (350,283,5,194,60),
        (428,234,6,205,71), (500,273,7,276,75),
        (570,313,7,272,80), (630,337,5,208,55),
        (204,409,4,220,55), (284,422,4,252,49),
    ]
    for group_index,(gx,gy,count,length,spread) in enumerate(front_groups):
        for i in range(count):
            x=gx+(i/(count-1)-.5)*spread+rng.uniform(-6,6)
            y=gy+rng.uniform(-15,20)
            spray(body,x,y,rng.uniform(-26,28),length*rng.uniform(.72,1.04),
                  20000+group_index*100+i,True)
    # Short sprays break the upper silhouette into actual small pointed leaves.
    for i in range(33):
        t=i/32
        x=113+t*524+rng.uniform(-8,8)
        y=280-math.sin(t*math.pi)*98+rng.uniform(-13,13)
        spray(body,x,y,rng.uniform(-16,17),rng.uniform(45,88),30000+i,True)
    body.append('</g></svg>')
    return "\n".join(body)+"\n"


def main() -> None:
    OUT.mkdir(parents=True,exist_ok=True)
    data=build().encode('utf-8')
    (OUT/'willow.svg').write_bytes(data)
    source={
        "title":"Shu original native-vector willow",
        "date":"2026-10-28",
        "author":"Codex, authored for Shu",
        "method":"Original native SVG vector illustration: authored asymmetric trunk and bough silhouettes, deterministic cubic drooping stems, individual lanceolate leaflets and low-opacity foliage washes. No raster image generation or third-party image inputs.",
        "license":"Original project art; same use and distribution terms as Shu project art. No additional third-party asset license.",
        "generator":"tools/build_town_willow.py",
        "generator_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "external_image_inputs":[],
        "file":"res://assets/art/shanxia_polish/willow.svg",
        "sha256":hashlib.sha256(data).hexdigest(),
        "bytes":len(data),
        "canvas":[WIDTH,HEIGHT],
        "foot_anchor":FOOT,
        "anchor_origin":"top-left canvas; pixels",
        "recommended_world_height":3.5,
        "presentation_notes":"Preserve aspect ratio. Transparent canvas, no painted ground shadow. Foot anchor drives placement. Intended for a camera-facing card in the existing mixed scene; use restrained modulation, not a thick outline or bright green tint. Inspect actual character/tree scale and occlusion before acceptance.",
        "status":"implementation candidate; native SVG illustration, in-scene and user visual acceptance pending",
    }
    (OUT/'willow-source.json').write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({"file":source['file'],"sha256":source['sha256'],"bytes":len(data),"canvas":[WIDTH,HEIGHT],"foot_anchor":FOOT},indent=2))


if __name__=='__main__':
    main()
