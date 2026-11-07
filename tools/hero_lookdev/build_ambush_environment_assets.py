#!/usr/bin/env python3
"""Package selected CC0 Quaternius Standard models for the Songfeng slice.

Runs with the existing Python/Pillow installation, not a renderer or generator.
Preserves source topology/UVs and packages embedded resized original textures.
The official free ZIP is immutable and hash-pinned. No network or paid downloads.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import struct
import sys
import zipfile

from PIL import Image, __version__ as PILLOW_VERSION

ARCHIVE_SHA = "298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9"
SELECTION = [
    ("rock-a", "Rock_Medium_1", "horizontal_extent", 1024, [0.82, 0.86, 0.78]),
    ("rock-b", "Rock_Medium_3", "horizontal_extent", 1024, [0.82, 0.86, 0.78]),
    ("grass-a", "Grass_Common_Short", "height", 512, [0.72, 0.78, 0.66]),
    ("grass-b", "Grass_Wispy_Short", "height", 512, [0.72, 0.78, 0.66]),
    ("stone-step", "RockPath_Square_Small_2", "horizontal_extent", 512, [0.82, 0.84, 0.78]),
    ("pine-source", "Pine_5", "height", 512, [0.78, 0.74, 0.66]),
]


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_member(model_path: str, uri: str) -> str:
    value = PurePosixPath(uri)
    if value.is_absolute() or ".." in value.parts or "\\" in uri or ":" in uri:
        raise ValueError("Unsafe source resource URI: " + uri)
    return str(PurePosixPath(model_path).parent / value)


def write_glb(path: Path, document: dict, binary: bytearray) -> None:
    document["buffers"] = [{"byteLength": len(binary)}]
    encoded = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    payload = bytes(binary) + b"\0" * (-len(binary) % 4)
    size = 12 + 8 + len(encoded) + 8 + len(payload)
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, size)
                     + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
                     + struct.pack("<II", len(payload), 0x004E4942) + payload)


def reduce_texture(raw: bytes, cap: int) -> tuple[bytes, list[int], list[int]]:
    with Image.open(io.BytesIO(raw)) as original:
        original.load()
        before = list(original.size)
        if max(original.size) <= cap:
            return raw, before, before
        image = original.copy()
        image.thumbnail((cap, cap), Image.Resampling.LANCZOS)
        output = io.BytesIO()
        image.save(output, format="PNG", optimize=True)
        return output.getvalue(), before, list(image.size)


def package_one(archive: zipfile.ZipFile, output: Path, selection: tuple) -> dict:
    identifier, model_name, policy, texture_cap, tint = selection
    model_path = "glTF/" + model_name + ".gltf"
    model_bytes = archive.read(model_path)
    document = json.loads(model_bytes)
    original_generator = document.get("asset", {}).get("generator", "unknown")
    if document.get("skins") or document.get("animations"):
        raise ValueError("Only the reviewed static source models are supported")
    if len(document["nodes"]) != 1 or any(k in document["nodes"][0] for k in ["matrix", "translation", "rotation", "scale", "children"]):
        raise ValueError("Reviewed source node must have identity transform")
    if document["scenes"][document.get("scene", 0)]["nodes"] != [0]:
        raise ValueError("Reviewed source must use its single mesh node")
    minimum = [float("inf")] * 3
    maximum = [float("-inf")] * 3
    triangle_count = 0
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) != 4:
                raise ValueError("Expected triangle geometry")
            accessor = document["accessors"][primitive["attributes"]["POSITION"]]
            minimum = [min(a, b) for a, b in zip(minimum, accessor["min"])]
            maximum = [max(a, b) for a, b in zip(maximum, accessor["max"])]
            triangle_count += document["accessors"][primitive["indices"]]["count"] // 3
    dimensions = [b - a for a, b in zip(minimum, maximum)]
    denominator = max(dimensions[0], dimensions[2]) if policy == "horizontal_extent" else dimensions[1]
    if denominator <= 0:
        raise ValueError("Source asset has zero normalization extent")
    factor = 1.0 / denominator
    origin = [(minimum[0] + maximum[0]) / 2, minimum[1], (minimum[2] + maximum[2]) / 2]
    document["nodes"].append({"name": "Songfeng_" + identifier, "children": [0],
                              "scale": [factor] * 3, "translation": [-v * factor for v in origin]})
    document["scenes"][document.get("scene", 0)]["nodes"] = [1]
    binary = bytearray()
    buffer_offsets = []
    dependencies = []
    for buffer in document["buffers"]:
        binary.extend(b"\0" * (-len(binary) % 4))
        buffer_offsets.append(len(binary))
        member = source_member(model_path, buffer["uri"])
        raw = archive.read(member)
        if len(raw) != buffer["byteLength"]:
            raise ValueError("Source geometry buffer length mismatch")
        binary.extend(raw)
        dependencies.append({"path": member, "sha256": digest(raw), "bytes": len(raw)})
    for view in document.get("bufferViews", []):
        view["byteOffset"] = buffer_offsets[view["buffer"]] + view.get("byteOffset", 0)
        view["buffer"] = 0
    image_records = []
    for image in document.get("images", []):
        member = source_member(model_path, image["uri"])
        raw = archive.read(member)
        encoded, before, after = reduce_texture(raw, texture_cap)
        filename = re.sub(r"[^a-z0-9]+", "-", Path(member).stem.lower()).strip("-") + f"-{texture_cap}.png"
        texture_path = output / "textures" / filename
        if texture_path.exists() and texture_path.read_bytes() != encoded:
            raise ValueError("Texture output name collision")
        texture_path.write_bytes(encoded)
        binary.extend(b"\0" * (-len(binary) % 4))
        offset = len(binary)
        binary.extend(encoded)
        view_index = len(document["bufferViews"])
        document["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(encoded)})
        image.pop("uri")
        image["mimeType"] = "image/png"
        image["bufferView"] = view_index
        image_records.append({"source_path": member, "source_sha256": digest(raw), "source_dimensions": before,
                              "path": "textures/" + filename, "dimensions": after, "bytes": len(encoded),
                              "sha256": digest(encoded), "embedded": True,
                              "processing": "Original pixels/alpha, resized with Lanczos only; no generated or repainted art"})
    material_records = []
    for material in document.get("materials", []):
        original = copy.deepcopy(material)
        pbr = material.setdefault("pbrMetallicRoughness", {})
        selected_tint = [0.62, 0.72, 0.65] if material.get("name") == "Leaves_Pine" else tint
        source_tint = pbr.get("baseColorFactor", [1, 1, 1, 1])
        pbr["baseColorFactor"] = [source_tint[i] * selected_tint[i] for i in range(3)] + [source_tint[3]]
        pbr["metallicFactor"] = 0
        pbr["roughnessFactor"] = 0.95
        material["doubleSided"] = True
        if identifier.startswith("grass") or material.get("name") == "Leaves_Pine":
            material["alphaMode"] = "MASK"
            material["alphaCutoff"] = 0.35
        material_records.append({"name": material.get("name"), "source": original, "runtime": copy.deepcopy(material)})
    document["asset"]["generator"] = "Shu CC0 environment packer; original " + original_generator
    document["asset"]["copyright"] = "Quaternius, CC0 1.0 Universal; local normalization/material adaptation for Shu"
    final_path = output / (identifier + ".glb")
    write_glb(final_path, document, binary)
    return {"id": identifier, "path": final_path.name, "source_path": model_path,
            "source_sha256": digest(model_bytes), "source_dependencies": dependencies,
            "source_generator": original_generator, "triangles": triangle_count,
            "bytes": final_path.stat().st_size, "sha256": digest(final_path.read_bytes()),
            "coordinates": {"up": "+Y", "pivot": "ground Y=0, XZ bounding-box midpoint",
                            "normalization": "maximum horizontal X/Z extent = 1" if policy == "horizontal_extent" else "height = 1",
                            "source_min": minimum, "source_max": maximum, "uniform_scale": factor,
                            "source_pivot": origin, "normalized_dimensions_xyz": [v * factor for v in dimensions]},
            "images": image_records, "materials": material_records,
            "geometry_processing": "No retopology, decimation, UV or vertex changes; one explicit uniform parent transform"}


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=root / ".local/sources/songfeng-environment/Stylized Nature MegaKit[Standard].zip")
    parser.add_argument("--output", type=Path, default=root / "assets/art/mountain_ambush/environment")
    args = parser.parse_args()
    raw_archive = args.archive.read_bytes()
    if digest(raw_archive) != ARCHIVE_SHA:
        raise ValueError("Expected the reviewed official free Standard archive")
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "textures").mkdir(exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(raw_archive)) as archive:
        for name in archive.namelist():
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or "\\" in name:
                raise ValueError("Unsafe archive path")
        if archive.testzip() is not None:
            raise ValueError("Archive CRC failure")
        license_bytes = archive.read("License_Standard.txt")
        if b"CC0 1.0 Universal" not in license_bytes:
            raise ValueError("Expected original CC0 license")
        (args.output / "License_Quaternius_CC0.txt").write_bytes(license_bytes)
        assets = [package_one(archive, args.output, entry) for entry in SELECTION]
    acquisition_path = args.archive.parent / "acquisition.json"
    acquisition = json.loads(acquisition_path.read_text()) if acquisition_path.is_file() else {}
    runtime_bytes = sum(p.stat().st_size for p in args.output.rglob("*") if p.is_file() and p.suffix in [".glb", ".png"])
    if runtime_bytes > 10_000_000:
        raise ValueError("Selected GLBs plus texture copies exceed the 10 MB budget")
    manifest = {"status": "Songfeng environment slice candidate; not user-approved artwork", "author": "Quaternius",
                "source_pack": "Stylized Nature MegaKit Standard (68 free source models)", "license": "CC0-1.0",
                "license_url": "https://creativecommons.org/publicdomain/zero/1.0/", "license_file": "License_Quaternius_CC0.txt",
                "acquisition": acquisition, "archive_sha256": ARCHIVE_SHA, "archive_bytes": len(raw_archive),
                "builder": "tools/hero_lookdev/build_ambush_environment_assets.py", "builder_sha256": digest(Path(__file__).read_bytes()),
                "tools": {"python": sys.version.split()[0], "pillow": PILLOW_VERSION},
                "rebuild": "python3 tools/hero_lookdev/build_ambush_environment_assets.py", "runtime_bytes_glb_and_textures": runtime_bytes,
                "cost_usd": 0, "new_generated_images": 0, "new_installs": 0,
                "material_adaptation": "Embedded original resized textures, matte roughness, mild linear base-color multiplier, alpha-tested double-sided foliage",
                "source_integrity": "Original ZIP and extracted source files are not modified", "assets": assets}
    (args.output / "source-environment.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"assets": [{"id": a["id"], "bytes": a["bytes"], "triangles": a["triangles"], "dimensions": a["coordinates"]["normalized_dimensions_xyz"]} for a in assets], "total_bytes_glb_and_textures": runtime_bytes}, indent=2))


if __name__ == "__main__":
    main()
