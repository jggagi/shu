#!/usr/bin/env python3
"""Give the retained seller's pale trouser legs a readable painted-street edge.

This derives native SVG from Shu's original six-pose SVG. It changes only the
two trouser strokes per frame; original feet, other curves and anchors remain.
No image model, network service, dependency or raster conversion is used.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "assets/art/shanxia_polish/tea-seller-life.svg"
OUTPUT = ROOT / "assets/art/town_painted_street/tea-seller-life.svg"
SOURCE = OUTPUT.with_name("palette-source.json")
OUTLINE = "#918774"
TROUSER = "#d5ccb0"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    original = INPUT.read_text(encoding="utf-8")
    result = original
    for x in (32, 46):
        curve = f'M{x} 82 L{x}.0 99.0'
        previous = f'<path d="{curve}" stroke="#e9e1cb" stroke-width="7"/>'
        if result.count(previous) != 6:
            raise SystemExit(f"Expected exactly six unchanged leg strokes at x={x}")
        replacement = (
            f'<path d="{curve}" stroke="{OUTLINE}" stroke-width="9"/>'
            f'<path d="{curve}" stroke="{TROUSER}" stroke-width="7"/>'
        )
        result = result.replace(previous, replacement)
    # Reversibility proves that every byte outside the twelve native leg
    # strokes, including each shoe contour and pose, is retained unchanged.
    restored = result
    for x in (32, 46):
        curve = f'M{x} 82 L{x}.0 99.0'
        replacement = (
            f'<path d="{curve}" stroke="{OUTLINE}" stroke-width="9"/>'
            f'<path d="{curve}" stroke="{TROUSER}" stroke-width="7"/>'
        )
        previous = f'<path d="{curve}" stroke="#e9e1cb" stroke-width="7"/>'
        restored = restored.replace(replacement, previous)
    if restored != original:
        raise SystemExit("Unexpected edit outside the twelve trouser strokes")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(result, encoding="utf-8")
    metadata = {
        "asset": "tea-seller-life.svg",
        "purpose": "Read pale trouser legs against pale paving in the fixed painted street",
        "provider": "nativeSVG",
        "author": "Shu project original procedural SVG, derived locally by Codex",
        "license": "Original Shu project asset; no third-party image incorporated",
        "input": {"path": str(INPUT.relative_to(ROOT)), "sha256": digest(INPUT)},
        "generator": {"path": str(Path(__file__).resolve().relative_to(ROOT)), "sha256": digest(Path(__file__))},
        "output": {"path": str(OUTPUT.relative_to(ROOT)), "sha256": digest(OUTPUT)},
        "frame_size": [80, 112],
        "frame_count": 6,
        "foot_anchor": [40, 104],
        "changes": {"native_leg_strokes": 12, "original_width": 7, "outline_width": 9,
                    "outline_color": OUTLINE, "inner_width": 7, "inner_color": TROUSER},
        "preserved": ["source SVG bytes outside twelve trouser strokes", "shoe curves", "foot anchors",
                      "head", "torso", "working sleeves", "hands", "cups", "pose order", "80x112 frame contract"],
        "validation": {"exact_reverse_to_source": restored == original},
        "reproduce": "python3 tools/build_town_painted_characters.py",
    }
    SOURCE.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": metadata["output"], "source": str(SOURCE.relative_to(ROOT)),
                      "frame_count": 6, "exact_reverse_to_source": restored == original}, ensure_ascii=False))


if __name__ == "__main__":
    main()
