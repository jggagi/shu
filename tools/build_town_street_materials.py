#!/usr/bin/env python3
"""Author the original, seamless SVG surfaces for Shu's tea-street slice.

No external images, AI image calls, dependencies, or runtime noise are used.
The small variations are deterministic vector brush shapes, not baked lighting.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art/shanxia_polish/materials"
SIZE = 512


def svg(body: list[str], defs: str = "") -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" '
        'viewBox="0 0 512 512">\n'
        '<title>Shu original tea-street architectural material</title>\n'
        '<desc>Original vector surface, deterministic authored shapes; no third-party pixels.</desc>\n'
        f"<defs>{defs}</defs>\n" + "\n".join(body) + "\n</svg>\n"
    )


def wrap_shape(body: list[str], shape: str, x: float, y: float) -> None:
    """Copy a brush dab across both edges, preserving repeat continuity."""
    for dx in (-SIZE, 0, SIZE):
        for dy in (-SIZE, 0, SIZE):
            # The largest authored brush has radius < 80 px. Omit wholly clipped copies.
            if -80 <= x + dx <= SIZE + 80 and -80 <= y + dy <= SIZE + 80:
                body.append(f'<g transform="translate({x + dx:.2f} {y + dy:.2f})">{shape}</g>')


def wash(body: list[str], rng: random.Random, count: int, colors: tuple[str, ...],
         radius: tuple[float, float], opacity: float) -> None:
    for _ in range(count):
        x, y = rng.random() * SIZE, rng.random() * SIZE
        rx, ry = rng.uniform(*radius), rng.uniform(*radius) * 0.58
        points = []
        for j in range(11):
            angle = j * math.tau / 11
            rough = rng.uniform(0.78, 1.1)
            points.append((math.cos(angle) * rx * rough, math.sin(angle) * ry * rough))
        path = "M" + " L".join(f"{a:.2f},{b:.2f}" for a, b in points) + "Z"
        color = rng.choice(colors)
        shape = "".join(
            f'<path d="{path}" fill="{color}" opacity="{opacity / 3:.3f}" '
            f'transform="scale({scale})"/>'
            for scale in (1.0, 0.81, 0.62)
        )
        wrap_shape(body, shape, x, y)


def roof() -> str:
    rng = random.Random(2810281)
    body = ['<rect width="512" height="512" fill="#52605b"/>']
    defs = (
        '<linearGradient id="barrel"><stop stop-color="#526560"/>'
        '<stop offset=".24" stop-color="#70817a"/>'
        '<stop offset=".53" stop-color="#7e8d83"/>'
        '<stop offset=".84" stop-color="#63756e"/>'
        '<stop offset="1" stop-color="#4d615b"/></linearGradient>'
    )
    for row in range(-1, 9):
        # Rows outside the tile use the same authored variation as their counterpart.
        for column in range(16):
            local = random.Random((row % 8) * 133 + column * 29 + 932)
            x, y = column * 64, row * 64
            inset = local.uniform(0, 2)
            body.append('<g transform="scale(.5 1)">')
            body.append(
                f'<path d="M{x},{y} Q{x+31},{y+2.5} {x+64},{y} '
                f'L{x+64-inset:.2f},{y+62} Q{x+32},{y+67} {x+inset:.2f},{y+62}Z" '
                'fill="url(#barrel)"/>'
            )
            tint = local.choice(("#b7b49a", "#485c56", "#97a694"))
            body.append(
                f'<path d="M{x+4},{y+2} Q{x+24},{y+19} {x+5},{y+59} '
                f'Q{x+26},{y+64} {x+49},{y+60} L{x+52},{y+3}Z" '
                f'fill="{tint}" opacity="{local.uniform(.025,.095):.3f}"/>'
            )
            body.append(
                f'<path d="M{x+1},{y+61.5} Q{x+32},{y+68} {x+63},{y+61.5}" '
                'fill="none" stroke="#3d514c" stroke-opacity=".47" stroke-width="2.3"/>'
            )
            body.append(
                f'<path d="M{x+7},{y+61} Q{x+30},{y+65.5} {x+56},{y+61.8}" '
                'fill="none" stroke="#b4b9a2" stroke-opacity=".33" stroke-width="1.35"/>'
            )
            # Fine brushmarks stop well short of tile joints; roof stays legible at distance.
            for _ in range(3):
                bx = x + local.uniform(13, 49)
                by = y + local.uniform(8, 45)
                body.append(
                    f'<path d="M{bx:.2f},{by:.2f} q-1,6 0,{local.uniform(5,14):.2f}" '
                    'fill="none" stroke="#c0c4ab" stroke-opacity=".12" stroke-width=".8"/>'
                )
            body.append('</g>')
    wash(body, rng, 11, ("#7c8a57", "#9b9b69"), (3, 12), .18)
    return svg(body, defs)


def plaster() -> str:
    rng = random.Random(2810282)
    body = ['<rect width="512" height="512" fill="#ded8c5"/>']
    wash(body, rng, 78, ("#a9aa92", "#eee6cd", "#bfb296"), (12, 71), .075)
    wash(body, rng, 210, ("#969c87", "#fff3d8", "#b9af99"), (1, 7), .075)
    for _ in range(240):
        x, y = rng.uniform(0, 512), rng.uniform(0, 512)
        color = rng.choice(("#7c887c", "#fff3d7"))
        body.append(f'<path d="M{x:.2f},{y:.2f} l{rng.uniform(.7,2):.2f},-.3" '
                    f'stroke="{color}" stroke-opacity=".13" stroke-width=".7"/>')
    # Only a few hairline remnants; broad unbroken plaster is the main read.
    for x, y in ((118, 112), (387, 359)):
        body.append(f'<path d="M{x},{y} l-2,9 3,8 -1,13 4,7" '
                    'fill="none" stroke="#8e9685" stroke-opacity=".18" stroke-width=".7"/>')
    return svg(body)


def timber() -> str:
    rng = random.Random(2810283)
    body = ['<rect width="512" height="512" fill="#66553d"/>']
    # Every wave is periodic in Y. Each strip is duplicated at X edges.
    for index in range(55):
        center = index * 512 / 55
        width = rng.uniform(1.1, 5.8)
        phase = rng.random() * math.tau
        amplitude = rng.uniform(1.2, 5.0)
        points = [(center + math.sin(j / 32 * math.tau + phase) * amplitude,
                   j * 16) for j in range(33)]
        path = "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in points)
        color = rng.choice(("#a28457", "#3b3b2e", "#c2a170"))
        opacity = rng.uniform(.08,.22)
        for dx in (-512, 0, 512):
            body.append(f'<path d="{path}" transform="translate({dx} 0)" '
                        f'fill="none" stroke="{color}" '
                        f'stroke-opacity="{opacity:.3f}" stroke-width="{width:.2f}"/>')
    # Narrow worn fibres, rather than high contrast decorative rings.
    for _ in range(150):
        x, y = rng.random() * 512, rng.random() * 512
        height = rng.uniform(4, 29)
        shape = (f'<path d="M0,0 q1.6,{height*.4:.2f} .3,{height:.2f}" '
                 f'fill="none" stroke="{rng.choice(("#c2ac78", "#3c3d2e"))}" '
                 f'stroke-opacity="{rng.uniform(.08,.18):.3f}" stroke-width=".7"/>')
        wrap_shape(body, shape, x, y)
    for x, y in ((114, 125), (343, 368)):
        for w, h, alpha in ((14, 38, .12), (9, 26, .16), (4, 13, .21)):
            body.append(f'<path d="M{x},{y-h} Q{x+w},{y-4} {x},{y+h} '
                        f'Q{x-w},{y+4} {x},{y-h}" fill="none" '
                        f'stroke="#302f24" stroke-width="1.2" stroke-opacity="{alpha}"/>')
    return svg(body)


def flagstone() -> str:
    rng = random.Random(2810284)
    body = ['<rect width="512" height="512" fill="#798173"/>']
    # Unequal courses with no four-corner intersections. Shapes crossing an edge repeat.
    widths = ((176, 144, 192), (132, 224, 156), (208, 156, 148), (156, 188, 168))
    offsets = (0, -65, -130, -42)
    colors = ("#9ca696", "#a2ab9c", "#a7ad9e", "#98a392", "#a6ae9b")
    for row in range(4):
        left = offsets[row]
        for col, width in enumerate(widths[row]):
            local = random.Random(row * 100 + col * 41 + 105)
            x, y = left + 3, row * 128 + 3
            w, h = width - 6, 122
            corners = [(x+5,y+1),(x+w-5,y),(x+w,y+6),(x+w-1,y+h-6),
                       (x+w-7,y+h),(x+5,y+h-1),(x,y+h-7),(x+1,y+6)]
            path = "M" + " L".join(f"{a:.2f},{b:.2f}" for a,b in corners) + "Z"
            color = local.choice(colors)
            marks = []
            for _ in range(17):
                px, py = local.uniform(x+9,x+w-9), local.uniform(y+9,y+h-9)
                rx, ry = local.uniform(3,16), local.uniform(1.5,7)
                marks.append(f'<ellipse cx="{px:.2f}" cy="{py:.2f}" rx="{rx:.2f}" '
                             f'ry="{ry:.2f}" fill="{local.choice(("#d7d5b6", "#536f61"))}" '
                             f'opacity="{local.uniform(.025,.065):.3f}"/>')
            for dx in (-512, 0, 512):
                body.append(f'<g transform="translate({dx} 0)">')
                body.append(f'<path d="{path}" fill="{color}"/>')
                body.append(f'<path d="M{x+6},{y+2} L{x+w-7},{y+1} {x+w-2},{y+7}" '
                            'fill="none" stroke="#d7d7bb" stroke-opacity=".30" stroke-width="2"/>')
                body.append(f'<path d="M{x+6},{y+h-1} L{x+w-7},{y+h} {x+w-1},{y+h-7}" '
                            'fill="none" stroke="#596e61" stroke-opacity=".26" stroke-width="2"/>')
                body.extend(marks)
                body.append('</g>')
            left += width
    # Small soft lichen patches are infrequent and stay at the same scale as the stone wear.
    wash(body, rng, 16, ("#7d8d62", "#a9aa71"), (2, 8), .14)
    return svg(body)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    generators = {
        "roof-gray-teal.svg": roof,
        "plaster-ivory.svg": plaster,
        "timber-honey.svg": timber,
        "flagstone-graygreen.svg": flagstone,
    }
    files = {}
    for name, generator in generators.items():
        data = generator().encode("utf-8")
        (OUT / name).write_bytes(data)
        files[name] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data), "size": [512,512]}
    source = {
        "title": "Shu original tea-street architectural surfaces",
        "date": "2026-10-28",
        "author": "Codex, authored for Shu",
        "method": "Original native SVG vector construction; deterministic brush shapes and curves; no raster image generation or third-party artwork",
        "license": "Original project art; same use and distribution terms as Shu project art. No additional third-party asset license.",
        "generator": "tools/build_town_street_materials.py",
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "external_image_inputs": [],
        "style_constraints": ["Shu Chinese-painting palette", "restrained surface wear", "no painted directional lighting", "repeatable surface scale"],
        "status": "implementation candidate; rendered asset review only, in-scene and user visual acceptance pending",
        "texture_usage": {
            "albedo_modulation": "Use white (#ffffff) for authored palette, or very restrained warm/cool modulation. Existing saturated dark material colors would double-tint and crush details.",
            "filter": "linear with mipmaps; repeat enabled",
            "roof-gray-teal.svg": "16 narrow barrel-tile columns by 8 tiers per repeat. X goes across ridges; Y goes from ridge toward eave. Initial target repeat footprint: width 2.4 m, slope 2.4 m (each tile approx 0.15 m wide, 0.3 m slope length); adapt to authored roof proportions.",
            "plaster-ivory.svg": "One repeat per approximately 2.5 m wall patch. Mottling is intentionally very low contrast; do not increase contrast to make it look textured.",
            "timber-honey.svg": "Grain runs along image Y. One repeat approximately 0.5 m across grain and 2.5 m along grain. Rotate UVs for horizontal beams.",
            "flagstone-graygreen.svg": "Four unequal 128 px courses, three unequal stones per course. One repeat approximately 2.4 m square gives 0.6 m courses; initial path repeat can use 2.0-2.4 m square."
        },
        "files": files,
    }
    (OUT / "source.json").write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUT), "files": files}, indent=2))


if __name__ == "__main__":
    main()
