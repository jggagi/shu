#!/usr/bin/env python3
"""Derive a realtime GLB from the approved, immutable warm Jiang source.

Run with the existing Blender, with autoexec disabled::
  blender --disable-autoexec --background --python-exit-code 1 --python export_ambush_jiang.py -- \
    --input /absolute/jiang-sword-phrase.blend --output /absolute/jiang-approved.glb

The source is hash-pinned and never saved. Its original texture saturation is
baked through emission, and its spatial warm multiplier is retained as COLOR_0;
no replacement character is generated. The source rig, UVs and authored
animation are retained, with the original skin weights normalized to GLTF's
four-influence realtime convention.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys
import time

import bpy
import numpy as np
from mathutils import Vector

SOURCE_SHA256 = "9aa7c926103f58b664427b2400601001562ff9a436b153c9b46d0c9241de6e65"
TARGETS = {"JiangApprovedHead": 40000, "JiangFullbody": 30000,
           "JiangRightGrip_HandGrip": 3500, "JiangRightGrip_Jian": 1702}
BAKE_SIZES = {"JiangApprovedHead": 2048, "JiangFullbody": 2048}


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(part)
    return value.hexdigest()


def triangles(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def log(message: str) -> None:
    print("JIANG_EXPORT " + message, flush=True)


def ensure_ocio(args) -> dict:
    """Use the existing Blender LUTs with its installed OCIO library version.

    Fedora's installed Blender 5.2 config declares OCIO 2.5 while its runtime
    links 2.4. That otherwise silently falls back and gamma-encodes baked maps
    incorrectly. Only new 2.5 ICC/interchange *metadata* is omitted; every color
    transform and LUT is unchanged. This is a per-process workspace cache, never
    a system config/preferences modification.
    """
    source = Path(bpy.utils.resource_path("SYSTEM")) / "datafiles/colormanagement/config.ocio"
    if not source.is_file():
        raise RuntimeError("Cannot locate Blender's bundled color configuration")
    text = source.read_text()
    match = re.search(r"ocio_profile_version:\s*([0-9]+)\.([0-9]+)", text)
    supported = tuple(bpy.app.ocio.version[:2])
    declared = (int(match[1]), int(match[2])) if match else supported
    if declared <= supported:
        return {"bundled_config": str(source), "bundled_sha256": sha256(source),
                "library_version": bpy.app.ocio.version_string, "compatibility_copy": False}
    cache = Path.cwd() / ".local/qa/ambush-characters/ocio-compat"
    cache.mkdir(parents=True, exist_ok=True)
    destination = cache / "config.ocio"
    compatible = text.replace(match[0], "ocio_profile_version: %d.%d" % supported, 1)
    compatible = re.sub(r"(?m)^    interop_id:.*\n", "", compatible)
    compatible = re.sub(r"(?m)^    interchange:\n(?:      .*\n)+", "", compatible)
    compatible = compatible.replace('search_path: "icc:luts:filmic"',
        'search_path: "%s"' % ":".join(str(source.parent / name) for name in ("icc", "luts", "filmic")), 1)
    destination.write_text(compatible)
    if os.environ.get("OCIO") != str(destination):
        log("restarting only this export process with the compatible bundled color transforms")
        environment = os.environ.copy()
        environment["OCIO"] = str(destination)
        command = [bpy.app.binary_path, "--disable-autoexec", "--background", "--python-exit-code", "1", "--python",
                   str(Path(__file__).resolve()), "--"] + sys.argv[sys.argv.index("--") + 1:]
        os.execve(command[0], command, environment)
    return {"bundled_config": str(source), "bundled_sha256": sha256(source),
            "library_version": bpy.app.ocio.version_string, "compatibility_copy": True,
            "workspace_config_sha256": sha256(destination),
            "change": "version declaration and unsupported ICC metadata only; all transforms/LUTs retained"}


def bake_warm_base_color(obj, size: int) -> dict:
    """Bake only the original HSV operation on a full-square UV plane.

    The source has overlapping/tiny UV islands. Baking its spatial WarmGain to
    those UVs loses information. Keep that gain as standard linear COLOR_0;
    baking HSV independently of model UV topology is equivalent to the source
    texture -> HSV -> per-vertex multiplication and avoids black island seams.
    """
    records = []
    for material in obj.data.materials:
        tree = material.node_tree
        shader = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
        warm = any(n.type == "VERTEX_COLOR" and n.layer_name == "JiangWarmGain" for n in tree.nodes)
        if not warm:
            continue
        source_hsv = next(n for n in tree.nodes if n.type == "HUE_SAT")
        source_texture = source_hsv.inputs["Color"].links[0].from_node
        work = material.copy()
        work.name = material.name + "_TemporaryHSVPlane"
        work_tree = work.node_tree
        work_hsv = work_tree.nodes[source_hsv.name]
        output = next(n for n in work_tree.nodes if n.type == "OUTPUT_MATERIAL")
        destination = bpy.data.images.new(
            obj.name + "_SaturatedBaseColor",
            width=size, height=size,
            alpha=False, float_buffer=False)
        destination.colorspace_settings.name = "sRGB"
        bake_node = work_tree.nodes.new("ShaderNodeTexImage")
        bake_node.image = destination
        bake_node.select = True
        work_tree.nodes.active = bake_node
        emission = work_tree.nodes.new("ShaderNodeEmission")
        emission.inputs["Strength"].default_value = 1.0
        work_tree.links.new(work_hsv.outputs["Color"], emission.inputs["Color"])
        work_tree.links.new(emission.outputs[0], output.inputs["Surface"])
        bpy.ops.object.select_all(action="DESELECT")
        bpy.ops.mesh.primitive_plane_add(size=2.0)
        plane = bpy.context.object
        plane.data.materials.append(work)
        log("baking source HSV, preserving WarmGain as COLOR_0: " + obj.name)
        bpy.ops.object.bake(type="EMIT", use_clear=True, margin=0)
        bpy.data.objects.remove(plane, do_unlink=True)
        bpy.data.materials.remove(work)
        destination.pack()
        node = tree.nodes.new("ShaderNodeTexImage")
        node.image = destination
        tree.links.new(node.outputs["Color"], shader.inputs["Base Color"])
        records.append({"material": material.name, "texture_size": size,
                        "source_image": source_texture.image.name,
                        "saturation": float(source_hsv.inputs["Saturation"].default_value)})
    return {"object": obj.name, "method": "Original texture HSV emission bake on full UV square; original WarmGain retained as linear COLOR_0",
            "excludes": ["lighting", "AO", "shadow", "view transform"], "materials": records}


def reduce_mesh(obj, target: int) -> dict:
    before = triangles(obj)
    original_vertices = len(obj.data.vertices)
    gain = obj.data.color_attributes.get("JiangWarmGain")
    if gain:
        source_colors = np.empty(len(gain.data) * 4, dtype=np.float32)
        gain.data.foreach_get("color", source_colors)
        source_colors = source_colors.reshape((-1, 4))
        indices = np.empty(len(obj.data.loops), dtype=np.int32)
        obj.data.loops.foreach_get("vertex_index", indices)
        corner_colors = source_colors[indices].copy()
        # Neck is already a solid warm material and did not use the source
        # vertex multiplier. White there prevents applying its warmth twice.
        for polygon in obj.data.polygons:
            material = obj.data.materials[polygon.material_index]
            used_gain = any(n.type == "VERTEX_COLOR" and n.layer_name == "JiangWarmGain"
                            for n in material.node_tree.nodes)
            if not used_gain:
                corner_colors[polygon.loop_start:polygon.loop_start + polygon.loop_total] = 1.0
        obj.data.color_attributes.remove(gain)
        color = obj.data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
        color.data.foreach_set("color", corner_colors.ravel())
        obj.data.color_attributes.active_color = color
        obj.data.color_attributes.render_color_index = obj.data.color_attributes.find("Color")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if before > target:
        decimate = obj.modifiers.new("Realtime derivative, source remains immutable", "DECIMATE")
        decimate.decimate_type = "COLLAPSE"
        decimate.ratio = float(target) / float(before)
        decimate.use_collapse_triangulate = True
        # Collapse rest geometry, never the deformed pose. Keep the original
        # Armature modifier and all skinning groups for GLTF export.
        index = list(obj.modifiers).index(decimate)
        bpy.ops.object.modifier_move_to_index(modifier=decimate.name, index=0)
        bpy.ops.object.modifier_apply(modifier=decimate.name)
    return {"name": obj.name, "source_vertices": original_vertices,
            "source_triangles": before, "derived_vertices": len(obj.data.vertices),
            "derived_triangles": triangles(obj), "target_triangles": target,
            "uv_layers": [layer.name for layer in obj.data.uv_layers],
            "vertex_groups": len(obj.vertex_groups)}


def conventional_handle_material() -> dict:
    """Keep the source wrap's existing two-color palette, at its mean.

    Only the subpixel procedural grain of the grip is simplified; the original
    weapon/hand meshes, brass, blade and rigid hand.R attachment are retained.
    """
    material = bpy.data.materials["JiangRightGrip_DarkBlueHandleWrap"]
    tree = material.node_tree
    shader = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
    ramp = next(n for n in tree.nodes if n.type == "VALTORGB")
    colors = [list(element.color) for element in ramp.color_ramp.elements]
    base = shader.inputs["Base Color"]
    for link in list(base.links):
        tree.links.remove(link)
    base.default_value = tuple(sum(c[i] for c in colors) / len(colors) for i in range(4))
    for link in list(shader.inputs["Normal"].links):
        tree.links.remove(link)
    return {"material": material.name, "source_ramp_colors_linear": colors,
            "derived_mean_linear": list(base.default_value),
            "simplification": "Only subpixel procedural grip grain; source palette preserved."}


def duplicate_idle_action(rig, original) -> None:
    """A real static skeleton pose from authored frame 1, not a new model pose."""
    bpy.context.scene.frame_set(1)
    values = {b.name: (b.location.copy(), b.rotation_quaternion.copy(), b.scale.copy()) for b in rig.pose.bones}
    action = bpy.data.actions.new("Idle")
    rig.animation_data.action = action
    for frame in (1, 13):
        for name, (location, rotation, scale) in values.items():
            bone = rig.pose.bones[name]
            bone.location = location
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = rotation
            bone.scale = scale
            for channel in ("location", "rotation_quaternion", "scale"):
                bone.keyframe_insert(channel, frame=frame)
    idle_track = rig.animation_data.nla_tracks.new()
    idle_track.name = "Idle"
    idle_track.strips.new("Idle", 1, action)
    rig.animation_data.action = original
    original.name = "ApprovedSwordPhrase"
    original_track = rig.animation_data.nla_tracks.new()
    original_track.name = "ApprovedSwordPhrase"
    original_track.strips.new("ApprovedSwordPhrase", 1, original)
    # NLA exporter reads the two discrete tracks, not their blended sum.
    rig.animation_data.action = None
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    bpy.context.scene.frame_set(1)


def read_glb(path: Path) -> dict:
    raw = path.read_bytes()
    length, kind = struct.unpack_from("<II", raw, 12)
    if kind != 0x4E4F534A:
        raise RuntimeError("Missing GLB JSON chunk")
    return json.loads(raw[20:20 + length])


def describe_glb(path: Path, gltf: dict) -> dict:
    """Read the actual serialized payload; do not infer success from settings."""
    raw = path.read_bytes()
    json_length = struct.unpack_from("<I", raw, 12)[0]
    binary_offset = 28 + json_length
    images = []
    for image in gltf.get("images", []):
        view = gltf["bufferViews"][image["bufferView"]]
        start = binary_offset + view.get("byteOffset", 0)
        payload = raw[start:start + view["byteLength"]]
        size = list(struct.unpack(">II", payload[16:24])) if payload[:8] == b"\x89PNG\r\n\x1a\n" else None
        images.append({"name": image.get("name"), "mime_type": image.get("mimeType"),
                       "size": size, "bytes": len(payload),
                       "sha256": hashlib.sha256(payload).hexdigest()})
    clips = []
    for action in gltf.get("animations", []):
        clips.append({"name": action.get("name"), "duration_seconds": max(
            gltf["accessors"][sampler["input"]].get("max", [0])[0]
            for sampler in action["samplers"])})
    return {"textures": images, "animation_clips": clips,
            "scene_root_names": [gltf["nodes"][index].get("name")
                                 for index in gltf["scenes"][gltf["scene"]]["nodes"]],
            "has_color_0": any("COLOR_0" in primitive["attributes"]
                               for mesh in gltf.get("meshes", []) for primitive in mesh["primitives"]),
            "skin_weight_policy": "Original rig/groups; GLTF top four influences per vertex normalized"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--replace-derived", action="store_true",
                        help="Atomically replace only a prior derivative with matching source provenance")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    source = args.input.resolve()
    output = args.output.resolve()
    report_path = args.report.resolve() if args.report else output.with_suffix(".json")
    if not args.input.is_absolute() or not args.output.is_absolute() or source == output:
        raise RuntimeError("Explicit distinct absolute source/output required")
    if (not output.parent.is_dir() or source.suffix != ".blend" or output.suffix != ".glb"
            or report_path.suffix != ".json" or report_path in (source, output)):
        raise RuntimeError("Distinct source Blend, output GLB and JSON report in an existing directory required")
    if sha256(source) != SOURCE_SHA256:
        raise RuntimeError("Source is not the recorded approved warm model")
    if output.exists() and (not args.replace_derived or not report_path.is_file()
            or json.loads(report_path.read_text()).get("source_sha256") != SOURCE_SHA256):
        raise RuntimeError("Refusing an existing derivative; choose a new output then review it")
    color_management = ensure_ocio(args)
    started = time.time()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    scene.frame_set(1)
    rig = bpy.data.objects["JiangRig"]
    if len(rig.data.bones) != 22 or set(TARGETS) != {o.name for o in scene.objects if o.type == "MESH"}:
        raise RuntimeError("Approved four-mesh/22-bone source contract changed")
    original = rig.animation_data.action
    report = {"source_sha256": SOURCE_SHA256, "source_bytes": source.stat().st_size,
              "source_record": "docs/image-motion/jiang-sword-cycle-20261023.md",
              "blender": bpy.app.version_string, "new_cloud_calls": 0,
              "source_overwritten": False, "new_character_design": False,
              "bone_names": [b.name for b in rig.data.bones],
              "color_management": color_management,
              "source_animation_frames": list(original.frame_range), "fps": scene.render.fps,
              "palette_bakes": [], "meshes": [], "textures": []}
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 8
    scene.render.bake.use_selected_to_active = False
    for name, size in BAKE_SIZES.items():
        report["palette_bakes"].append(bake_warm_base_color(bpy.data.objects[name], size))
    for image in list(bpy.data.images):
        if image.type == "RENDER_RESULT" or "SaturatedBaseColor" in image.name:
            continue
        # Only connected PBR images enter the GLB. The baked source base colors
        # remain orphan inputs and are not exported.
        if image.size[0] > 1024 or image.size[1] > 1024:
            image.scale(1024, 1024)
            image.pack()
    report["grip_material"] = conventional_handle_material()
    rig.data.pose_position = "REST"
    for name, target in TARGETS.items():
        log("reducing " + name)
        report["meshes"].append(reduce_mesh(bpy.data.objects[name], target))
    rig.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    total = sum(row["derived_triangles"] for row in report["meshes"])
    if not 30000 <= total <= 80000:
        raise RuntimeError("Derived geometry outside reviewed 30k-80k triangle budget")
    duplicate_idle_action(rig, original)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [rig] + [bpy.data.objects[name] for name in TARGETS]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    temporary = output.with_name(output.stem + ".working.glb")
    log("exporting " + str(temporary))
    bpy.ops.export_scene.gltf(
        filepath=str(temporary), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=False, export_texcoords=True,
        export_vertex_color="NAME", export_vertex_color_name="Color", export_all_vertex_colors=False,
        export_normals=True, export_tangents=False, export_materials="EXPORT",
        export_image_format="AUTO", export_animations=True,
        export_animation_mode="NLA_TRACKS", export_frame_range=False,
        export_force_sampling=True, export_nla_strips=True,
        export_skins=True, export_def_bones=False, export_all_influences=False,
        export_cameras=False, export_lights=False)
    gltf = read_glb(temporary)
    joints = [gltf["nodes"][i].get("name", "") for skin in gltf.get("skins", []) for i in skin["joints"]]
    if len(joints) != 22 or set(joints) != set(report["bone_names"]):
        raise RuntimeError("Export did not retain the original 22-bone rig")
    report["exported_animation_names"] = [a.get("name", "") for a in gltf.get("animations", [])]
    report.update(describe_glb(temporary, gltf))
    if not report["has_color_0"]:
        raise RuntimeError("Export dropped the approved source's spatial warm multiplier COLOR_0")
    if not {"Idle", "ApprovedSwordPhrase"}.issubset(set(report["exported_animation_names"])):
        raise RuntimeError("Both authored and neutral animation clips must be present")
    report["exported_mesh_count"] = len(gltf.get("meshes", []))
    report["exported_image_count"] = len(gltf.get("images", []))
    report["exported_material_count"] = len(gltf.get("materials", []))
    report["coordinate_contract"] = {"gltf_up": "+Y", "gltf_front_expected": "+Z from Blender -Y",
                                      "normalization": "none; preserve original model and use battle adapter"}
    report["derived_triangles"] = total
    report["source_sha256_after"] = sha256(source)
    if report["source_sha256_after"] != SOURCE_SHA256:
        raise RuntimeError("Immutable source changed")
    os.replace(temporary, output)
    report["glb_sha256"] = sha256(output)
    report["glb_bytes"] = output.stat().st_size
    report["elapsed_seconds"] = round(time.time() - started, 3)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    log(json.dumps({"status": "PASS", "triangles": total, "bytes": report["glb_bytes"],
                    "animations": report["exported_animation_names"], "elapsed": report["elapsed_seconds"]}))


if __name__ == "__main__":
    main()
