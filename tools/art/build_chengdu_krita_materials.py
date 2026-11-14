#!/usr/bin/env python3
"""Build the bounded Chengdu material study as editable ORA, then export in Krita.

No image service or model is called. The source sheets remain unchanged. Pillow
prepares explicit source/correction layers; Krita opens that layered document and
performs the production PNG and KRA export. Supply an existing Krita binary with
--krita; a pinned portable AppImage is documented in material-source.json.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from PIL import Image, ImageFilter, ImageOps, ImageStat

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "art/source/chengdu-blender-kit-20261110"
OUTPUT_DIR = ROOT / "assets/art/chengdu_blender_kit_20261110"
QA_DIR = ROOT / ".local/qa/chengdu-blender-kit-20261110"
SIZE = 1024
X = [0, 341, 682, 1024]
Y = [0, 512, 1024]
PADDING = 16
# Original project Qwen material sheets, not external library assets.
SPECS = [
    ("plaster", "assets/art/chengdu_crafted_street/plaster.png", None, (197, 183, 155), 17.0, 1.8),
    ("wood", "assets/art/chengdu_concept_finish/surfaces.png", (512, 512, 1024, 1024), (100, 73, 48), 19.0, 1.1),
    ("roof", "assets/art/chengdu_crafted_street/roof.png", None, (101, 116, 113), 15.0, 1.0),
    ("stone", "assets/art/chengdu_crafted_street/paving.png", None, (157, 147, 126), 15.0, 1.2),
    ("leaf", "assets/art/chengdu_concept_finish/foliage.png", (328, 328, 696, 696), (133, 141, 91), 13.0, 5.0),
    ("ceramic", "assets/art/chengdu_crafted_street/plaster.png", (192, 192, 832, 832), (185, 205, 190), 7.0, 3.5),
]

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def png_bytes(image: Image.Image) -> bytes:
    data = io.BytesIO()
    image.save(data, format="PNG")
    return data.getvalue()

def padded(tile: Image.Image, width: int, height: int) -> Image.Image:
    """Replicate edge pixels into gutters so linear sampling cannot pick a neighbour."""
    out = Image.new("RGBA", (width, height))
    out.paste(tile, (PADDING, PADDING))
    tw, th = tile.size
    out.paste(tile.crop((0, 0, 1, th)).resize((PADDING, th)), (0, PADDING))
    out.paste(tile.crop((tw-1, 0, tw, th)).resize((PADDING, th)), (PADDING+tw, PADDING))
    out.paste(out.crop((0, PADDING, width, PADDING+1)).resize((width, PADDING)), (0, 0))
    out.paste(out.crop((0, PADDING+th-1, width, PADDING+th)).resize((width, PADDING)), (0, PADDING+th))
    return out

def prepare() -> tuple[Path, dict]:
    for d in (SOURCE_DIR, OUTPUT_DIR, QA_DIR):
        d.mkdir(parents=True, exist_ok=True)
    base = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    paint = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glaze = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    tiles = []
    for i, (name, rel, crop, target, spread, blur) in enumerate(SPECS):
        row, col = divmod(i, 3)
        left, top, right, bottom = X[col], Y[row], X[col+1], Y[row+1]
        width, height = right-left, bottom-top
        inner_width, inner_height = width-2*PADDING, height-2*PADDING
        source_path = ROOT / rel
        source = Image.open(source_path).convert("RGB")
        if crop:
            source = source.crop(crop)
        # Exclude source magenta key gaps before making the leaf pigment patch.
        # This is a surface colour texture, not an extracted tree silhouette.
        if name == "leaf":
            pixels = list(source.getdata())
            valid = [p for p in pixels if not (p[0]-p[1] > 25 and p[2]-p[1] > 25)]
            mean = tuple(round(sum(p[c] for p in valid)/len(valid)) for c in range(3))
            source.putdata([mean if p[0]-p[1] > 25 and p[2]-p[1] > 25 else p for p in pixels])
        fitted = ImageOps.fit(source, (inner_width, inner_height), method=Image.Resampling.LANCZOS)
        grey = fitted.convert("L").filter(ImageFilter.GaussianBlur(blur))
        stat = ImageStat.Stat(grey)
        mean_luma, deviation = stat.mean[0], max(1.0, stat.stddev[0])
        colours = []
        for value in grey.getdata():
            # Retain the actual source structures with a quiet, shared value range.
            delta = max(-2.1, min(2.1, (value-mean_luma)/deviation))*spread
            colours.append(tuple(max(0, min(255, round(c+delta))) for c in target)+(215,))
        corrected = Image.new("RGBA", grey.size)
        corrected.putdata(colours)
        base.paste(Image.new("RGBA", (width, height), target+(255,)), (left, top))
        paint.paste(padded(corrected, width, height), (left, top))
        broad = Image.new("RGBA", (inner_width, inner_height))
        # Restrained, deterministic vertical pigment glaze. No random noise layer.
        broad.putdata([(57, 61, 48, round(4 + 9*(y/max(1,inner_height-1))**2))
                       for y in range(inner_height) for _ in range(inner_width)])
        glaze.paste(padded(broad, width, height), (left, top))
        rect = [left+PADDING, top+PADDING, inner_width, inner_height]
        tiles.append({
            "name": name, "cell_pixels": [left, top, width, height],
            "inner_rect_pixels": rect,
            "uv_png_top_left_centres": [(left+PADDING+.5)/SIZE, (top+PADDING+.5)/SIZE,
                                         (right-PADDING-.5)/SIZE, (bottom-PADDING-.5)/SIZE],
            "source": rel, "source_sha256": sha(source_path), "source_crop_ltrb": crop,
            "palette_rgb": list(target), "luma_spread": spread, "blur_source_pixels": blur,
            "source_key_handling": "replace magenta gaps with mean valid leaf pigment before luminance conversion" if name == "leaf" else None,
        })
    merged = Image.alpha_composite(Image.alpha_composite(base, paint), glaze)
    layers = [("Broad restrained shadow glaze", glaze),
              ("Existing project pigment structure, palette unified", paint),
              ("Shared six-material base palette", base)]
    image_xml = ET.Element("image", {"version": "0.0.3", "w": str(SIZE), "h": str(SIZE), "name": "Chengdu Blender material study"})
    stack = ET.SubElement(image_xml, "stack", {"name": "root"})
    ora = SOURCE_DIR / "materials.ora"
    with zipfile.ZipFile(ora, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("mimetype", "image/openraster", compress_type=zipfile.ZIP_STORED)
        for i, (name, layer) in enumerate(layers):
            src = f"data/layer{i:02d}.png"
            ET.SubElement(stack, "layer", {"name": name, "src": src, "x": "0", "y": "0", "opacity": "1.0", "visibility": "visible", "composite-op": "svg:src-over"})
            archive.writestr(src, png_bytes(layer))
        archive.writestr("stack.xml", ET.tostring(image_xml, encoding="utf-8", xml_declaration=True))
        archive.writestr("mergedimage.png", png_bytes(merged))
        archive.writestr("Thumbnails/thumbnail.png", png_bytes(merged.resize((256,256), Image.Resampling.LANCZOS)))
    merged.save(QA_DIR / "atlas-layer-preview.png")
    metadata = {
        "schema_version": 1,
        "asset": "Original Shu Blender tea-shop and tree six-material study",
        "author": "Codex-directed offline composition of existing original Shu project artwork",
        "rights": "Existing original project Qwen art; provider terms apply. No third-party texture-library licence is claimed. New correction layers and modelling are project work.",
        "method": "Deterministic source crop, quiet luminance transfer to a shared palette, three editable OpenRaster layers; actual Krita document import and production exports follow.",
        "new_cloud_generation_calls": 0,
        "original_source_png_modified": False,
        "source_provenance": ["assets/art/chengdu_concept_finish/source.json", "assets/art/chengdu_crafted_street/source.json"],
        "atlas": {"size": [SIZE,SIZE], "columns": 3, "rows": 2, "padding_pixels": PADDING,
                  "pixel_origin": "top-left", "cell_boundaries_x": X, "cell_boundaries_y": Y,
                  "uv_contract": "Use inner centre bounds only. Blender UV V=1-PNG_V; glTF exporter flips V to image-space, so Godot should not flip V again. No repeating or sampling across tile boundaries.", "tiles": tiles},
        "editable_source": {"path": ora.relative_to(ROOT).as_posix(), "sha256": sha(ora), "layers_top_to_bottom": [name for name,_ in layers]},
        "limitations": ["This is reproducible offline colour/material compositing, not a claim of new human-painted brush strokes.",
                         "Atlas colour is opaque; transparent art-layer composition is retained in ORA/KRA. Tree volume comes from the separate 3D mesh.",
                         "Texture colour and model relief must be reviewed in the actual game camera before any city-wide expansion."],
    }
    return ora, metadata

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--krita", type=Path, required=True, help="Existing Krita/AppRun executable; no installation is performed")
    args = parser.parse_args()
    krita = args.krita.expanduser().resolve()
    if not krita.is_file():
        raise SystemExit(f"Krita executable not found: {krita}")
    ora, metadata = prepare()
    env = os.environ.copy()
    env.setdefault("QT_QPA_PLATFORM", "xcb")
    for name, folder in (("XDG_CONFIG_HOME","config"),("XDG_DATA_HOME","data"),("XDG_CACHE_HOME","cache")):
        location = ROOT / ".local/tools/krita/profile" / folder
        location.mkdir(parents=True, exist_ok=True)
        env[name] = str(location)
    version = subprocess.run([str(krita), "--version"], env=env, text=True, capture_output=True, timeout=60)
    if version.returncode:
        raise SystemExit(version.stderr)
    logs = []
    outputs = [OUTPUT_DIR/"painted-atlas.png", SOURCE_DIR/"materials.kra"]
    for output in outputs:
        command = [str(krita), "--nosplash", "--export", "--export-filename", str(output), str(ora)]
        run = subprocess.run(command, env=env, text=True, capture_output=True, timeout=180)
        log = {"command": [part.replace(str(ROOT)+"/", "") for part in command],
               "exit_code": run.returncode, "stdout": run.stdout.replace(str(ROOT), "."), "stderr": run.stderr.replace(str(ROOT), "."),
               "output": output.relative_to(ROOT).as_posix()}
        logs.append(log)
        (QA_DIR/(output.suffix.lstrip(".")+"-krita-export.log")).write_text(run.stdout+"\n"+run.stderr)
        if run.returncode or not output.is_file():
            (QA_DIR/"krita-export-receipt.json").write_text(json.dumps(logs, indent=2)+"\n")
            raise SystemExit(f"Krita export failed: {output.name}, exit {run.returncode}")
    atlas = Image.open(outputs[0]); atlas.load()
    if atlas.size != (SIZE,SIZE):
        raise SystemExit(f"Unexpected Krita PNG dimensions: {atlas.size}")
    metadata["software"] = {"name": "Krita", "version_output": version.stdout.strip(),
                             "official_page": "https://krita.org/en/download/",
                             "software_licence": "GNU GPL v3 (tool only; project artwork retains its own provenance)",
                             "appimage_url": "https://download.kde.org/stable/krita/5.3.4.1/krita-5.3.4.1-x86_64.AppImage",
                             "appimage_sha256": "e315dfb3da81cdb8bddc4bb3fcd4d9bacd0630fc7065d8ed07de758b267573f0",
                             "official_sha256_url": "https://download.kde.org/stable/krita/5.3.4.1/krita-5.3.4.1-x86_64.AppImage.sha256",
                             "scope": "Project-local portable application, CLI --export over the existing Xwayland display (this AppImage ships xcb only), isolated project-local XDG config/data/cache; no global installation or system settings changed."}
    metadata["reproduction"] = {"script": Path(__file__).relative_to(ROOT).as_posix(),
                                "command": "DISPLAY=<existing X11 display> XAUTHORITY=<existing session auth> QT_QPA_PLATFORM=xcb python tools/art/build_chengdu_krita_materials.py --krita .local/tools/krita/squashfs-root/AppRun",
                                "script_sha256": sha(Path(__file__)),
                                "export_commands": logs}
    metadata["outputs"] = [{"path": p.relative_to(ROOT).as_posix(), "sha256": sha(p), "bytes": p.stat().st_size} for p in outputs]
    metadata["png_inspection"] = {"mode": atlas.mode, "size": list(atlas.size),
                                  "alpha_extrema": list(atlas.getchannel("A").getextrema()) if "A" in atlas.getbands() else None,
                                  "krita_export_vs_ora_composite_max_difference": max(ImageStat.Stat(__import__("PIL.ImageChops", fromlist=["difference"]).difference(atlas.convert("RGBA"), Image.open(QA_DIR/"atlas-layer-preview.png").convert("RGBA"))).extrema, key=lambda p:p[1])[1]}
    (OUTPUT_DIR/"material-source.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+"\n")
    (QA_DIR/"krita-export-receipt.json").write_text(json.dumps(logs, ensure_ascii=False, indent=2)+"\n")
    print(json.dumps({"version": metadata["software"]["version_output"], "outputs": metadata["outputs"], "inspection": metadata["png_inspection"]}, indent=2))

if __name__ == "__main__":
    main()
