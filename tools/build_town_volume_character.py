#!/usr/bin/env python3
"""Derive town idle/walk skeletal clips from Shu's approved warm Jiang GLB.

Run using the existing Blender, with script auto-execution disabled. The exact
approved runtime GLB is the only input; it is never overwritten. Mesh topology,
UVs, weights, six packed textures and the original 22-bone rest rig are retained.
Only the independent sword object is omitted. The complete right grip/hand stays.

Walking uses alternating support/swing trajectories and analytical two-bone IK.
The support ankle moves backward by exactly the virtual actor travel; it is not
a sinusoidal knee wiggle. The consumer samples Walk by real travel distance.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

BASE_SHA = "e8d74b2e0be789f272597aa6f7fc268f57851bb669ed43d97e2efa91c3860e27"
ORIGINAL_BLEND_SHA = "9aa7c926103f58b664427b2400601001562ff9a436b153c9b46d0c9241de6e65"
FPS = 60
WALK_FRAMES = 48
IDLE_FRAMES = 192
STRIDE = 1.40
STANCE = 0.56
FLOOR = 0.000216
KEEP = {"JiangApprovedHead", "JiangFullbody", "JiangRightGrip_HandGrip"}
CLIP_NAMES = {"Idle": "TownIdle", "Walk": "TownWalk"}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_glb(path):
    raw = Path(path).read_bytes()
    length, kind = struct.unpack_from("<II", raw, 12)
    if kind != 0x4E4F534A:
        raise RuntimeError("Missing GLB JSON chunk")
    return raw, json.loads(raw[20:20 + length]), 28 + length


def texture_payloads(path):
    raw, gltf, binary = read_glb(path)
    result = []
    for image in gltf.get("images", []):
        view = gltf["bufferViews"][image["bufferView"]]
        start = binary + view.get("byteOffset", 0)
        payload = raw[start:start + view["byteLength"]]
        result.append({"name": image.get("name"), "size": list(struct.unpack(">II", payload[16:24])),
                       "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()})
    return result


def restore_original_model_payloads(source, output):
    """Preserve exact serialized source geometry/colors after Blender roundtrip.

    Blender imports glTF colors into BYTE_COLOR, so a roundtrip can lose color
    precision even without an authored edit. The topology/order is unchanged;
    restore each retained accessor and original inverse-bind/rest transforms.
    Only the new skeletal animation buffers remain newly authored.
    """
    original_raw, original, original_base = read_glb(source)
    result_raw, result, result_base = read_glb(output)
    binary = bytearray(result_raw[result_base:])
    restored = []
    sizes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
    dimensions = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

    def restore_accessor(before_index, after_index, label):
        before = original["accessors"][before_index]
        after = result["accessors"][after_index]
        if any(before[key] != after[key] for key in ("componentType", "count", "type")):
            raise RuntimeError("Roundtrip changed accessor layout: " + label)
        size = sizes[before["componentType"]] * dimensions[before["type"]]
        a = original["bufferViews"][before["bufferView"]]
        b = result["bufferViews"][after["bufferView"]]
        a_start = original_base + a.get("byteOffset", 0) + before.get("byteOffset", 0)
        b_start = b.get("byteOffset", 0) + after.get("byteOffset", 0)
        for index in range(before["count"]):
            a_offset = a_start + index * a.get("byteStride", size)
            b_offset = b_start + index * b.get("byteStride", size)
            binary[b_offset:b_offset + size] = original_raw[a_offset:a_offset + size]
        for key in ("min", "max", "normalized"):
            if key in before:
                after[key] = copy.deepcopy(before[key])
            else:
                after.pop(key, None)
        restored.append(label)

    before_nodes = {node["name"]: node for node in original["nodes"] if "mesh" in node}
    for node in result["nodes"]:
        if "mesh" not in node:
            continue
        source_mesh = original["meshes"][before_nodes[node["name"]]["mesh"]]
        result_mesh = result["meshes"][node["mesh"]]
        if len(source_mesh["primitives"]) != len(result_mesh["primitives"]):
            raise RuntimeError("Roundtrip changed source surfaces")
        for surface, (before, after) in enumerate(zip(source_mesh["primitives"], result_mesh["primitives"])):
            if set(before["attributes"]) != set(after["attributes"]):
                raise RuntimeError("Roundtrip changed source attributes")
            for attribute in before["attributes"]:
                restore_accessor(before["attributes"][attribute], after["attributes"][attribute],
                                 "%s/%d/%s" % (node["name"], surface, attribute))
            restore_accessor(before["indices"], after["indices"], "%s/%d/indices" % (node["name"], surface))
    for before, after in zip(original["skins"], result["skins"]):
        source_names = [original["nodes"][i]["name"] for i in before["joints"]]
        result_names = [result["nodes"][i]["name"] for i in after["joints"]]
        if source_names != result_names:
            raise RuntimeError("Source skin joint ordering changed")
        restore_accessor(before["inverseBindMatrices"], after["inverseBindMatrices"], "source_inverse_bind_matrices")
        for before_index, after_index in zip(before["joints"], after["joints"]):
            for key in ("matrix", "translation", "rotation", "scale"):
                if key in original["nodes"][before_index]:
                    result["nodes"][after_index][key] = copy.deepcopy(original["nodes"][before_index][key])
                else:
                    result["nodes"][after_index].pop(key, None)
    encoded = json.dumps(result, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    encoded += b" " * (-len(encoded) % 4)
    binary += b"\0" * (-len(binary) % 4)
    glb = (struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(binary))
           + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
           + struct.pack("<II", len(binary), 0x004E4942) + binary)
    output.write_bytes(glb)
    return {"exact_source_accessors_restored": restored, "source_rest_joint_transforms_restored": 22,
            "reason": "Avoid Blender BYTE_COLOR precision loss and normal/position float roundtrip changes; retain original source buffers without gamma/color/geometry edits"}


def two_bone(a, pole, end, upper, lower):
    delta = end - a
    requested = delta.length
    distance = min(upper + lower - 1e-6, max(abs(upper - lower) + 1e-6, requested))
    axis = delta.normalized()
    side = pole - a - axis * (pole - a).dot(axis)
    if side.length < 1e-7:
        raise RuntimeError("Ambiguous IK pole")
    side.normalize()
    along = (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
    knee = a + axis * along + side * math.sqrt(max(0.0, upper * upper - along * along))
    return knee, a + axis * distance, abs(requested - distance)


def set_segment(rig, name, start, end, orientation=None):
    rest = rig.data.bones[name]
    rotation = orientation or ((rest.tail_local - rest.head_local).rotation_difference(end - start)
                               @ rest.matrix_local.to_quaternion())
    rig.pose.bones[name].matrix = Matrix.LocRotScale(start, rotation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def foot_path(phase):
    """Blender -Y is forward. Return y offset, clearance and support state."""
    p = phase % 1.0
    half_support = STRIDE * STANCE * 0.5
    if p <= STANCE:
        return -half_support + STRIDE * p, 0.0, True
    s = (p - STANCE) / (1.0 - STANCE)
    # Hermite endpoint derivatives match the backward support velocity. The
    # unweighted foot finishes pushing off, advances, then settles at contact.
    tangent = STRIDE * (1.0 - STANCE)
    y = ((2*s**3 - 3*s*s + 1) * half_support
         + (s**3 - 2*s*s + s) * tangent
         + (-2*s**3 + 3*s*s) * -half_support
         + (s**3 - s*s) * tangent)
    lift = 0.115 * math.sin(math.pi * s) ** 2
    return y, lift, False


def pose(rig, mode, phase):
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    walk = mode == "Walk"
    angle = phase * math.tau
    if walk:
        # The body is lowest at double support and rises over the planted leg.
        # Reversing this phase would produce a crouched passing position.
        shift = Vector((0.028 * math.cos(angle), 0.0, -0.070 - 0.035 * math.cos(2*angle)))
        yaw = math.radians(2.4) * math.cos(angle)
        lean = math.radians(2.0)
    else:
        shift = Vector((0.005 * math.sin(angle), 0.0, -0.030 + 0.0020 * math.sin(angle)))
        yaw = math.radians(0.35) * math.sin(angle)
        lean = math.radians(0.25) * math.sin(angle)
    pelvis = rig.data.bones["pelvis"].matrix_local
    pivot = pelvis.translation
    hip_lowering = 0.0
    if walk:
        provisional = (Matrix.Translation(shift) @ Matrix.Translation(pivot)
                       @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(lean, 4, "X")
                       @ Matrix.Translation(-pivot))
        for side, side_phase in (("R", phase), ("L", phase + .5)):
            ankle = rig.data.bones["foot." + side].head_local.copy()
            forward, clearance, _ = foot_path(side_phase)
            ankle += Vector((0, forward, clearance))
            hip = provisional @ rig.data.bones["thigh." + side].head_local
            maximum_length = (rig.data.bones["thigh." + side].length
                              + rig.data.bones["shin." + side].length - .003)
            horizontal_squared = (ankle.x - hip.x)**2 + (ankle.y - hip.y)**2
            maximum_z = ankle.z + math.sqrt(maximum_length**2 - horizontal_squared)
            hip_lowering = max(hip_lowering, hip.z - maximum_z)
        # At the end of push-off the foot briefly remains behind the body.
        # Limit the authored hip rise to the actual source leg's reach instead
        # of moving the supporting foot or extending the source bone lengths.
        shift.z -= hip_lowering
    transform = (Matrix.Translation(shift) @ Matrix.Translation(pivot)
                 @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(lean, 4, "X")
                 @ Matrix.Translation(-pivot))
    rig.pose.bones["pelvis"].matrix = transform @ pelvis
    bpy.context.view_layer.update()
    chest = rig.pose.bones["chest"]
    chest.matrix = Matrix.LocRotScale(chest.head, Quaternion((0, 0, 1), -yaw * 0.65)
                                     @ chest.matrix.to_quaternion(), Vector((1, 1, 1)))
    bpy.context.view_layer.update()
    head = rig.pose.bones["head"]
    head.matrix = Matrix.LocRotScale(head.head, Quaternion((0, 0, 1), -yaw * 0.30)
                                    @ head.matrix.to_quaternion(), Vector((1, 1, 1)))
    bpy.context.view_layer.update()
    metrics = {"phase": phase, "feet": {}, "max_ik_error_m": 0.0,
               "authored_hip_height_reach_limit_m": hip_lowering}
    for side, side_phase in (("R", phase), ("L", phase + 0.5)):
        hip = rig.pose.bones["thigh." + side].head.copy()
        rest = rig.data.bones["foot." + side]
        ankle = rest.head_local.copy()
        if walk:
            offset, lift, support = foot_path(side_phase)
            ankle.y += offset
            ankle.z += lift
        else:
            support = True
        upper = rig.data.bones["thigh." + side].length
        lower = rig.data.bones["shin." + side].length
        knee, actual, error = two_bone(hip, hip + Vector((0, -0.7, -0.3)), ankle, upper, lower)
        metrics["max_ik_error_m"] = max(metrics["max_ik_error_m"], error)
        set_segment(rig, "thigh." + side, hip, knee)
        set_segment(rig, "shin." + side, knee, actual)
        # Flat, consistently oriented soles throughout support. No per-frame
        # re-grounding from the changing lowest rendered vertex.
        foot = rest.matrix_local.copy()
        foot.translation = actual
        rig.pose.bones["foot." + side].matrix = foot
        bpy.context.view_layer.update()
        metrics["feet"][side] = {"support": support, "ankle": list(actual),
                                 "virtual_actor_forward": STRIDE * phase if walk else 0.0}
    for side, sign, side_phase in (("R", -1, phase), ("L", 1, phase + 0.5)):
        shoulder = rig.pose.bones["upper_arm." + side].head.copy()
        swing = 0.155 * math.cos(side_phase * math.tau) if walk else 0.005 * math.sin(angle)
        wrist = Vector((sign * 0.335 + shift.x * 0.7, -0.13 + swing,
                        (1.015 if walk else 0.985) + shift.z
                        + (0.015 * (1 - math.cos(2*angle)) if walk else 0.0)))
        pole = shoulder + Vector((sign * 0.28, 0.17, -0.24))
        elbow, actual, error = two_bone(shoulder, pole, wrist,
            rig.data.bones["upper_arm." + side].length, rig.data.bones["forearm." + side].length)
        metrics["max_ik_error_m"] = max(metrics["max_ik_error_m"], error)
        set_segment(rig, "upper_arm." + side, shoulder, elbow)
        set_segment(rig, "forearm." + side, elbow, actual)
        # The hand follows the forearm continuously; the original complete
        # grip stays skinned to hand.R after the independent sword is omitted.
        direction = (actual - elbow).normalized()
        set_segment(rig, "hand." + side, actual,
                    actual + direction * rig.data.bones["hand." + side].length)
    for side, sign in (("R", -1), ("L", 1)):
        thigh = rig.pose.bones["thigh." + side]
        swing = math.atan2(-(thigh.tail.y - thigh.head.y), -(thigh.tail.z - thigh.head.z))
        for section in ("front", "back"):
            bone = rig.pose.bones["skirt." + section + "." + side]
            factor = 0.34 if section == "front" else 0.26
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = Quaternion((1, 0, 0), swing * factor)
    hair = rig.pose.bones["ponytail"]
    hair.rotation_mode = "QUATERNION"
    hair.rotation_quaternion = Quaternion((1, 0, 0), (0.014 if walk else 0.004) * math.sin(angle))
    bpy.context.view_layer.update()
    return metrics


def author_action(rig, name, frames):
    action = bpy.data.actions.new(CLIP_NAMES[name])
    rig.animation_data.action = action
    samples = []
    for frame in range(frames + 1):
        bpy.context.scene.frame_set(frame)
        samples.append(pose(rig, name, frame / frames))
        for bone in rig.pose.bones:
            bone.rotation_mode = "QUATERNION"
            for channel in ("location", "rotation_quaternion", "scale"):
                bone.keyframe_insert(channel, frame=frame)
    # Match endpoints exactly; Blender exports sampled local bone transforms.
    return action, samples


def validate_deformed_contacts(rig, objects, walk_samples):
    """Measure actual evaluated boot vertices, not only analytical ankle goals."""
    body = next(o for o in objects if o.name == "JiangFullbody")
    original = np.empty(len(body.data.vertices) * 3, dtype=np.float32)
    body.data.vertices.foreach_get("co", original)
    original = original.reshape((-1, 3))
    boots = {side: np.flatnonzero((original[:, 2] < .32) & (original[:, 0] * sign > .05))
             for side, sign in (("R", -1), ("L", 1))}
    soles = {side: np.flatnonzero((original[:, 2] < .035) & (original[:, 0] * sign > .05))
             for side, sign in (("R", -1), ("L", 1))}
    samples = []
    support_reference = {}
    maximum_lock_error = 0.0
    maximum_floor_error = 0.0
    boundary = {}
    rig.animation_data.action = bpy.data.actions[CLIP_NAMES["Walk"]]
    for frame in range(WALK_FRAMES + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        coordinates = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get("co", coordinates)
        coordinates = coordinates.reshape((-1, 3))
        row = {"frame": frame, "phase": frame/WALK_FRAMES, "feet": {}}
        for side, offset in (("R", 0), ("L", .5)):
            support = walk_samples[frame]["feet"][side]["support"]
            minimum = float(coordinates[boots[side], 2].min())
            record = {"support": support, "actual_boot_min_z_m": minimum,
                      "floor_error_m": minimum - FLOOR if support else None}
            if support:
                maximum_floor_error = max(maximum_floor_error, abs(minimum - FLOOR))
                virtual_world = coordinates[soles[side]].copy()
                virtual_world[:, 1] -= STRIDE * frame/WALK_FRAMES
                contact_id = (side, int(math.floor(frame/WALK_FRAMES + offset + 1e-8)))
                if contact_id not in support_reference:
                    support_reference[contact_id] = virtual_world
                drift = float(np.linalg.norm(virtual_world - support_reference[contact_id], axis=1).max())
                maximum_lock_error = max(maximum_lock_error, drift)
                record["actual_sole_maximum_world_vertex_drift_m"] = drift
            row["feet"][side] = record
        if frame in (0, WALK_FRAMES):
            boundary[frame] = coordinates.copy()
        samples.append(row)
        evaluated.to_mesh_clear()
    loop_error = float(np.linalg.norm(boundary[0] - boundary[WALK_FRAMES], axis=1).max())
    if maximum_floor_error > .001 or maximum_lock_error > .001 or loop_error > .00001:
        raise RuntimeError("Actual boot contact/loop check failed: %r" %
                           (maximum_floor_error, maximum_lock_error, loop_error))
    return {"frames": WALK_FRAMES + 1, "evaluated_mesh": "JiangFullbody",
            "sole_vertex_counts": {side: len(ids) for side, ids in soles.items()},
            "maximum_supported_boot_floor_error_m": maximum_floor_error,
            "maximum_supported_sole_world_vertex_drift_m": maximum_lock_error,
            "complete_body_loop_endpoint_maximum_vertex_error_m": loop_error,
            "source_floor_m": FLOOR, "samples": samples,
            "policy": "No per-frame mesh grounding. Sole samples retain original rest-mesh identities and include actual evaluated skinning; virtual actor translation only cancels the declared forward stride."}


def add_review_scene(rig, objects, out):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 8
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("Town review neutral world")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.78, 0.79, 0.75, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast" if "Medium High Contrast" in [i.name for i in scene.bl_rna.properties] else "None"
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    bpy.ops.object.camera_add(location=(0, -5, 2.4))
    camera = bpy.context.object
    camera.name = "Town asset review camera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.55
    scene.camera = camera
    bpy.ops.object.light_add(type="AREA", location=(-3, -4, 5))
    key = bpy.context.object
    key.data.energy = 330
    key.data.shape = "DISK"
    key.data.size = 4
    key.rotation_euler = (Vector((0, 0, 1)) - key.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, FLOOR - 0.002))
    plane = bpy.context.object
    mat = bpy.data.materials.new("Review only matte floor")
    mat.diffuse_color = (0.62, 0.62, 0.54, 1)
    plane.data.materials.append(mat)
    renders = []
    for mode, phase, view in [("Idle", 0, "front"), ("Idle", 0, "side"), ("Idle", 0, "back"),
                              ("Walk", 0, "side"), ("Walk", .25, "side"), ("Walk", .5, "side"),
                              ("Walk", .75, "side"), ("Walk", .25, "front"), ("Walk", .25, "back")]:
        rig.animation_data.action = bpy.data.actions[CLIP_NAMES[mode]]
        scene.frame_set(round(phase * (WALK_FRAMES if mode == "Walk" else IDLE_FRAMES)))
        camera.location = {"front": Vector((0, -5, 2.45)), "side": Vector((5, 0, 2.2)),
                           "back": Vector((0, 5, 2.45))}[view]
        camera.rotation_euler = (Vector((0, -0.05, 1.05)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = out / ("%s-%03d-%s.png" % (mode.lower(), round(phase * 100), view))
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        renders.append(str(path))
    return renders


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--review", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    source = args.input.resolve()
    output = args.output.resolve()
    review = args.review.resolve()
    if source == output or sha(source) != BASE_SHA or output.exists():
        raise RuntimeError("Use the exact approved source and a new distinct output")
    output.parent.mkdir(parents=True, exist_ok=True)
    review.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=str(source))
    rig = next(o for o in scene.objects if o.type == "ARMATURE")
    objects = [o for o in scene.objects if o.type == "MESH" and o.name in KEEP]
    if len(objects) != 3 or len(rig.data.bones) != 22:
        raise RuntimeError("Approved three-character-mesh/22-bone contract changed")
    for obj in list(scene.objects):
        if obj != rig and obj not in objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    rig.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    rig.animation_data_create()
    idle, idle_samples = author_action(rig, "Idle", IDLE_FRAMES)
    walk, walk_samples = author_action(rig, "Walk", WALK_FRAMES)
    max_error = max(s["max_ik_error_m"] for s in idle_samples + walk_samples)
    if max_error > 0.000005:
        raise RuntimeError("Daily targets exceed source limb lengths: %.8f" % max_error)
    contact_validation = validate_deformed_contacts(rig, objects, walk_samples)
    (review / "actual-boot-contacts.json").write_text(json.dumps(contact_validation, indent=2) + "\n")
    for action in (idle, walk):
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        track.strips.new(action.name, 0, action)
        track.mute = True
    rig.animation_data.action = None
    scene.frame_start = 0
    scene.frame_end = IDLE_FRAMES
    pose(rig, "Idle", 0.0)
    blend = review / "jiang-town-daily.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [rig] + objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=False, export_texcoords=True,
        export_vertex_color="NAME", export_vertex_color_name="Color", export_all_vertex_colors=False,
        export_normals=True, export_tangents=False, export_materials="EXPORT",
        export_image_format="AUTO", export_animations=True, export_animation_mode="NLA_TRACKS",
        export_frame_range=False, export_force_sampling=True, export_nla_strips=True,
        export_skins=True, export_def_bones=False, export_all_influences=False,
        export_cameras=False, export_lights=False)
    exact_source_payloads = restore_original_model_payloads(source, output)
    original_textures = texture_payloads(source)
    result_textures = texture_payloads(output)
    if sorted(t["sha256"] for t in original_textures) != sorted(t["sha256"] for t in result_textures):
        raise RuntimeError("GLB roundtrip unexpectedly changed texture payloads")
    (review / "motion-samples.json").write_text(json.dumps({"Idle": idle_samples, "Walk": walk_samples}, indent=2) + "\n")
    renders = add_review_scene(rig, objects, review)
    _, gltf, _ = read_glb(output)
    report = {"asset_id": "town-volume-jiang-daily-20261030", "status": "candidate-awaiting-town-playtest",
        "author": "Shu project local skeletal animation; original approved Jiang model identity preserved",
        "source": {"path": str(source), "sha256": BASE_SHA, "bytes": source.stat().st_size,
            "original_approved_blend_sha256": ORIGINAL_BLEND_SHA,
            "approval_record": "docs/P3_JIANG_MODEL_REUSE.md in retained mountain-ambush worktree",
            "original_provenance": "docs/image-motion/jiang-fullbody-turn-20261022.md",
            "license": "Existing user-authorized Tencent Hunyuan model use terms and original project hand/sword authorship retained; no new third-party asset, no CC0 claim"},
        "identity": "Original warm skin, brown high ponytail, blue/ivory clothing and source body proportions; no new face or costume",
        "hand_and_weapon": "Only separate sword omitted. Complete original right closed grip/hand retained; daily right fist remains a known source limitation.",
        "coordinate_contract": {"gltf_up": "+Y", "gltf_front": "+Z", "blender_up": "+Z", "blender_front": "-Y", "source_floor_m": FLOOR,
            "source_neutral_height_record_m": 2.096427, "root_motion": "none; consumer owns real locomotion and yaw"},
        "walk_cycle_source_distance": STRIDE,
        "clips": {"TownIdle": {"fps": FPS, "frames_including_endpoint": IDLE_FRAMES + 1, "seconds": IDLE_FRAMES/FPS,
            "motion": "Relaxed low shoulders and arms, very small shared-clock chest/head/pelvis breathing; both soles remain planted"},
            "TownWalk": {"fps": FPS, "frames_including_endpoint": WALK_FRAMES + 1, "seconds": WALK_FRAMES/FPS,
            "full_cycle_steps": 2, "source_distance_per_cycle_m": STRIDE, "support_fraction_per_foot": STANCE,
            "nominal_unscaled_speed_m_s": STRIDE/(WALK_FRAMES/FPS),
            "consumer_sampling": "phase = actual_world_distance / (1.40 * uniform_model_scale); animation_seconds = fract(phase) * 0.8",
            "motion": "Piecewise linear stationary-world support ankles; Hermite swing and 11.5cm clearance; analytical two-bone legs, contralateral arms, small pelvis/chest twist and cloth follow-through"}},
        "preserved": {"bone_count": 22, "mesh_node_names": sorted(KEEP), "source_textures_byte_identical": True,
            "source_meshes_weights_uv_edited": False, "all_texture_sha256": result_textures,
            "exact_source_geometry_payloads": exact_source_payloads},
        "godot_import": {"profile": "res://assets/art/town_volume_character/jiang-town.glb.import",
            "animation_fps": FPS, "optimizer_enabled": False, "animation_compression_enabled": False,
            "policy": "Use the versioned full import profile beside the GLB; profile is a separate Godot-generated resource setting, not generated by Blender."},
        "limits": ["Right hand remains the original complete closed fist", "No fingers, facial rig, cloth physics, toe bones or dynamic foot IK",
            "Distance calibration assumes uniform root scale and near-straight local locomotion; turn contact still needs real scene review", "Godot/native/Web integration not performed by this asset generator"],
        "tool": {"path": "tools/build_town_volume_character.py", "sha256": sha(Path(__file__).resolve()), "blender": bpy.app.version_string},
        "new_cloud_calls": 0, "new_downloads": 0, "new_installs": 0, "source_overwritten": False, "source_sha256_after": sha(source),
        "result": {"path": "assets/art/town_volume_character/jiang-town.glb", "sha256": sha(output), "bytes": output.stat().st_size,
            "triangles": sum(gltf["accessors"][p["indices"]]["count"]//3 for m in gltf["meshes"] for p in m["primitives"]),
            "animations": [a["name"] for a in gltf.get("animations", [])], "max_analytic_ik_error_m": max_error,
            "actual_contacts": {k: v for k, v in contact_validation.items() if k != "samples"}},
        "qa": {"saved_editable_blend": str(blend), "renders": renders, "frame_samples": str(review/"motion-samples.json"),
            "actual_game_verification": "not performed by asset generator", "user_acceptance": "pending"}}
    (output.parent / "source.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    (review / "authoring-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("TOWN_VOLUME_CHARACTER", json.dumps(report["result"]))


if __name__ == "__main__":
    main()
