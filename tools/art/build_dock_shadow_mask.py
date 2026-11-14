"""Build a receiver mask from authored dry shore and solid props, not artwork."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[2]
source = ROOT / "assets/data/dock-corner-layout.json"
data = json.loads(source.read_text())
mask = Image.new("L", (1280, 720), 0)
draw = ImageDraw.Draw(mask)
draw.polygon([tuple(p) for p in data["shore_polygon"]], fill=255)
for rect in data["solid_props"]:
    if rect == [337, 298, 28, 24]:  # Keeper footprint receives its own shadow.
        continue
    x, y, width, height = rect
    draw.rectangle((x, y, x + width, y + height), fill=0)
soft = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.0))
mask = ImageChops.multiply(mask, soft)
out = ROOT / "assets/masks/dock_shadows/ground.png"
out.parent.mkdir(parents=True, exist_ok=True)
mask.save(out)
record = {"author": "Shu original procedural dry-shore receiver mask", "license": "Original project layout-derived mask; no external artwork", "source_hashes": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [source, Path(__file__), out]}, "scope": "Dry shore including steps, excluding building/solid props, keeper footprint retained"}
(out.parent / "source.json").write_text(json.dumps(record, indent=2) + "\n")
