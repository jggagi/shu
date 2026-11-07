#!/usr/bin/env python3
"""Author a planted, whole-body palm strike on the immutable Tinglan rig.

Run with the existing Blender in background mode. The new GLB contains only
the matching 22-bone skeleton, one original five-finger open hand, and one
1.45-second animation. Original character meshes/textures are not duplicated.
The editable local Blend retains the complete original model for review.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

SOURCE_SHA = "cdbec85183a9e2d452546c6a5a1a164c854042c9a2f4f783b5d184c750d5856b"
FPS = 100
SECONDS = 1.45
CONTACT = 0.56
HAND_NAME = "TinglanOpenPalm"
CLIP_NAME = "TinglanPalm"
TIMES = [0.0, 0.38, CONTACT, 0.75, 1.05, SECONDS]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def smooth(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def yup(point):
    return [float(point.x), float(point.z), float(-point.y)]


def two_bone(origin, pole, goal, first, second):
    delta = goal - origin
    distance = min(first + second - 1e-7, max(abs(first - second) + 1e-7, delta.length))
    axis = delta.normalized()
    side = pole - origin - axis * (pole - origin).dot(axis)
    if side.length < 1e-7:
        side = axis.cross(Vector((1, 0, 0)))
    side.normalize()
    along = (first * first - second * second + distance * distance) / (2.0 * distance)
    return origin + axis * along + side * math.sqrt(max(0.0, first * first - along * along)), origin + axis * distance


def segment(rig, name, start, end):
    rest = rig.data.bones[name]
    rotation = (rest.tail_local - rest.head_local).rotation_difference(end - start) @ rest.matrix_local.to_quaternion()
    rig.pose.bones[name].matrix = Matrix.LocRotScale(start, rotation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def tube(vertices, faces, points, radii, segments=12, flatten=1.0):
    start = len(vertices)
    points = [Vector(p) for p in points]
    for i, point in enumerate(points):
        axis = (points[min(i + 1, len(points) - 1)] - points[max(0, i - 1)]).normalized()
        reference = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((0, 1, 0))
        horizontal = axis.cross(reference).normalized()
        vertical = axis.cross(horizontal).normalized()
        for j in range(segments):
            angle = math.tau * j / segments
            vertices.append(tuple(point + radii[i] * (horizontal * math.cos(angle) + vertical * math.sin(angle) * flatten)))
    for i in range(len(points) - 1):
        for j in range(segments):
            a = start + i * segments + j
            b = start + i * segments + (j + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    faces.append(tuple(start + j for j in reversed(range(segments))))
    faces.append(tuple(start + (len(points) - 1) * segments + j for j in range(segments)))


def ellipsoid(vertices, faces, center, radii, segments=20, rings=10):
    start = len(vertices)
    for i in range(rings + 1):
        latitude = -math.pi / 2 + math.pi * i / rings
        for j in range(segments):
            angle = math.tau * j / segments
            vertices.append((center[0] + radii[0] * math.cos(latitude) * math.cos(angle), center[1] + radii[1] * math.cos(latitude) * math.sin(angle), center[2] + radii[2] * math.sin(latitude)))
    for i in range(rings):
        for j in range(segments):
            a = start + i * segments + j
            b = start + i * segments + (j + 1) % segments
            faces.append((a, b, b + segments, a + segments))


def open_hand(rig):
    vertices, faces = [], []
    ellipsoid(vertices, faces, (0, 0.046, 0), (0.039, 0.047, 0.017))
    tube(vertices, faces, [(0, -0.023, 0), (0, 0.016, 0), (0, 0.045, 0)], [0.031, 0.034, 0.032], 20, 0.62)
    tips = []
    # Four extended, gently spread fingers lie in the palm plane. None are
    # curled into the two-finger pose used by the original interrupt model.
    for x, length, spread in [(-0.028, 0.096, -0.012), (-0.009, 0.112, -0.004), (0.011, 0.105, 0.005), (0.030, 0.082, 0.013)]:
        tip = (x + spread, 0.073 + length, -0.001)
        points = [(x, 0.071, 0), (x + spread * 0.35, 0.073 + length * 0.42, 0.001), (x + spread * 0.75, 0.073 + length * 0.78, 0), tip]
        tube(vertices, faces, points, [0.0095, 0.009, 0.0078, 0.0045], 12, 0.84)
        tips.append(tip)
    thumb_tip = (-0.086, 0.084, -0.002)
    tube(vertices, faces, [(-0.031, 0.026, 0), (-0.055, 0.043, 0), (-0.075, 0.066, -0.001), thumb_tip], [0.014, 0.012, 0.009, 0.005], 12, 0.88)
    tips.append(thumb_tip)
    rest = rig.data.bones["hand.L"].matrix_local
    mesh = bpy.data.meshes.new(HAND_NAME)
    mesh.from_pydata([rest @ Vector(p) for p in vertices], [], faces)
    mesh.update()
    obj = bpy.data.objects.new(HAND_NAME, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = rig
    for poly in mesh.polygons:
        poly.use_smooth = True
    # The unchanged original candidate has this flat skin material already.
    material = next(m for m in bpy.data.materials if m.name.startswith("Tinglan warm skin"))
    mesh.materials.append(material)
    obj.vertex_groups.new(name="hand.L").add(list(range(len(vertices))), 1.0, "REPLACE")
    obj.modifiers.new("Original Tinglan skeleton", "ARMATURE").object = rig
    return obj, {"name": HAND_NAME, "bone": "hand.L", "all_vertex_weights": 1.0,
                 "finger_count": 5, "per_finger_animation": False,
                 "palm_center_bone_local": [0, 0.055, 0.018], "palm_normal_bone_local": [0, 0, 1],
                 "fingers_axis_bone_local": [0, 1, 0], "fingertips_bone_local": tips,
                 "vertices": len(vertices), "polygon_count": len(faces),
                 "material": material.name, "world_mesh_coordinates": "original rig rest coordinates; do not offset twice"}


def controls(neutral_world):
    left = tuple(neutral_world["hand.L"].translation)
    return [
        {"hip_yaw": 0., "chest_yaw": 0., "lean": 0., "shift": (0., 0., 0.), "left": left, "open": 0., "palm_yaw": 0.},
        {"hip_yaw": 20., "chest_yaw": 7., "lean": -2., "shift": (0., 0.025, -0.065), "left": (0.20, -0.205, 1.32), "open": 1., "palm_yaw": 15.},
        {"hip_yaw": -17., "chest_yaw": -7., "lean": 7., "shift": (0.015, -0.090, -0.042), "left": (0.235, -0.760, 1.36), "open": 1., "palm_yaw": 0.},
        {"hip_yaw": -20., "chest_yaw": -4., "lean": 5., "shift": (0.012, -0.075, -0.028), "left": (0.240, -0.735, 1.34), "open": 1., "palm_yaw": -4.},
        {"hip_yaw": -7., "chest_yaw": 0., "lean": 1., "shift": (0., -0.005, -0.015), "left": (0.28, -0.260, 1.24), "open": 0.65, "palm_yaw": 0.},
        {"hip_yaw": 0., "chest_yaw": 0., "lean": 0., "shift": (0., 0., 0.), "left": left, "open": 0., "palm_yaw": 0.},
    ]


def interpolate(keys, time):
    for index in range(len(TIMES) - 1):
        if time <= TIMES[index + 1] + 1e-8:
            amount = smooth((time - TIMES[index]) / (TIMES[index + 1] - TIMES[index]))
            return {name: Vector(keys[index][name]).lerp(Vector(keys[index + 1][name]), amount) if isinstance(keys[index][name], tuple) else keys[index][name] * (1 - amount) + keys[index + 1][name] * amount for name in keys[index]}
    return keys[-1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--blend", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if sha(args.base) != SOURCE_SHA:
        raise RuntimeError("Immutable Tinglan source hash differs")
    if len({args.base.resolve(), args.out.resolve(), args.blend.resolve()}) != 3:
        raise RuntimeError("Source and output paths must be distinct")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.base.resolve()))
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    rig.animation_data.action = bpy.data.actions["Idle"]
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    neutral = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
    neutral_world = {bone.name: bone.matrix.copy() for bone in rig.pose.bones}
    rests = {bone.name: [list(row) for row in bone.matrix_local] for bone in rig.data.bones}
    parents = {bone.name: bone.parent.name if bone.parent else None for bone in rig.data.bones}
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    rig.animation_data.action = None
    hand, hand_info = open_hand(rig)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = 0
    scene.frame_end = round(SECONDS * FPS)
    action = bpy.data.actions.new(CLIP_NAME)
    rig.animation_data.action = action
    keys = controls(neutral_world)
    limbs = {}
    for side in ["L", "R"]:
        limbs[side] = {"arm": [(neutral_world["forearm." + side].translation - neutral_world["upper_arm." + side].translation).length, (neutral_world["hand." + side].translation - neutral_world["forearm." + side].translation).length], "leg": [(neutral_world["shin." + side].translation - neutral_world["thigh." + side].translation).length, (neutral_world["foot." + side].translation - neutral_world["shin." + side].translation).length]}
    palm_upright = Matrix(((1., 0., 0.), (0., 0., -1.), (0., 1., 0.))).to_quaternion()
    samples, pose_samples = [], []
    max_foot_drift = 0.0
    max_wrist_residual = 0.0
    for frame in range(scene.frame_end + 1):
        time = frame / FPS
        scene.frame_set(frame)
        for bone in rig.pose.bones:
            bone.matrix_basis = neutral[bone.name]
        bpy.context.view_layer.update()
        control = interpolate(keys, time)
        if frame not in [0, scene.frame_end]:
            pivot = neutral_world["pelvis"].translation
            transform = Matrix.Translation(control["shift"]) @ Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(control["hip_yaw"]), 4, "Z") @ Matrix.Translation(-pivot)
            rig.pose.bones["pelvis"].matrix = transform @ neutral_world["pelvis"]
            bpy.context.view_layer.update()
            chest = rig.pose.bones["chest"]
            rotation = Quaternion((0, 0, 1), math.radians(control["chest_yaw"])) @ Quaternion((1, 0, 0), math.radians(control["lean"])) @ chest.matrix.to_quaternion()
            chest.matrix = Matrix.LocRotScale(chest.head.copy(), rotation, Vector((1, 1, 1)))
            bpy.context.view_layer.update()
            head = rig.pose.bones["head"]
            head.matrix = Matrix.LocRotScale(head.head.copy(), Quaternion((0, 0, 1), math.radians(-control["hip_yaw"] * 0.7)) @ head.matrix.to_quaternion(), Vector((1, 1, 1)))
            bpy.context.view_layer.update()
            for side in ["L", "R"]:
                hip = rig.pose.bones["thigh." + side].head.copy()
                ankle = neutral_world["foot." + side].translation.copy()
                knee, foot = two_bone(hip, hip + Vector((0, -0.32, -0.40)), ankle, *limbs[side]["leg"])
                segment(rig, "thigh." + side, hip, knee)
                segment(rig, "shin." + side, knee, foot)
                transform = neutral_world["foot." + side].copy()
                transform.translation = foot
                rig.pose.bones["foot." + side].matrix = transform
                bpy.context.view_layer.update()
                shoulder = rig.pose.bones["upper_arm." + side].head.copy()
                if side == "L":
                    goal = Vector(control["left"])
                    pole = shoulder + Vector((0.33, -0.10, -0.23))
                else:
                    goal = neutral_world["hand.R"].translation + Vector(control["shift"]) * 0.30
                    pole = shoulder + Vector((-0.30, 0.10, -0.22))
                elbow, wrist = two_bone(shoulder, pole, goal, *limbs[side]["arm"])
                max_wrist_residual = max(max_wrist_residual, (wrist - goal).length)
                segment(rig, "upper_arm." + side, shoulder, elbow)
                segment(rig, "forearm." + side, elbow, wrist)
                rotation = neutral_world["hand." + side].to_quaternion()
                if side == "L":
                    target = Quaternion((0, 0, 1), math.radians(control["palm_yaw"])) @ palm_upright
                    rotation = rotation.slerp(target, control["open"])
                rig.pose.bones["hand." + side].matrix = Matrix.LocRotScale(wrist, rotation, Vector((1, 1, 1)))
                bpy.context.view_layer.update()
        for bone in rig.pose.bones:
            bone.rotation_mode = "QUATERNION"
            for channel in ["location", "rotation_quaternion", "scale"]:
                bone.keyframe_insert(channel, frame=frame)
        palm = rig.pose.bones["hand.L"].matrix
        right = rig.pose.bones["hand.R"].matrix
        foot_drift = max((rig.pose.bones["foot." + side].head - neutral_world["foot." + side].translation).length for side in ["L", "R"])
        max_foot_drift = max(max_foot_drift, foot_drift)
        samples.append({"seconds": time, "palm_center": yup(palm @ Vector(hand_info["palm_center_bone_local"])), "palm_normal": yup((palm.to_3x3() @ Vector((0, 0, 1))).normalized()), "wrist": yup(palm.translation), "elbow": yup(rig.pose.bones["forearm.L"].head), "hip": yup(rig.pose.bones["pelvis"].head), "foot_L": yup(rig.pose.bones["foot.L"].head), "foot_R": yup(rig.pose.bones["foot.R"].head), "right_wrist": yup(right.translation), "right_hand_rotation": list(right.to_quaternion()), "hip_yaw_degrees": control["hip_yaw"], "chest_additional_yaw_degrees": control["chest_yaw"], "foot_drift_m": foot_drift})
        if frame in [0, 38, 56, 75, 105, 145]:
            pose_samples.append({"seconds": time, "bones": {bone.name: [list(row) for row in bone.matrix_basis] for bone in rig.pose.bones}})
    track = rig.animation_data.nla_tracks.new()
    track.name = CLIP_NAME
    track.strips.new(CLIP_NAME, 0, action)
    track.mute = True
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis = neutral[bone.name]
    scene.frame_set(0)
    bpy.context.view_layer.update()
    # Preserve editable original meshes in the local Blend, with only the new
    # left hand displayed. They are excluded from the actual resource export.
    for name in ["TinglanRelaxedHand", "TinglanPointingHand"]:
        bpy.data.objects[name].hide_render = True
        bpy.data.objects[name].hide_viewport = True
    bpy.ops.wm.save_as_mainfile(filepath=str(args.blend.resolve()))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [rig, hand]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(args.out.resolve()), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=False, export_materials="EXPORT", export_texcoords=False,
        export_normals=True, export_animations=True, export_animation_mode="NLA_TRACKS",
        export_frame_range=False, export_force_sampling=True, export_nla_strips=True,
        export_skins=True, export_def_bones=False, export_cameras=False, export_lights=False)
    data = args.out.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    if len(gltf.get("meshes", [])) != 1 or gltf["meshes"][0]["name"] != HAND_NAME or len(gltf.get("images", [])) or len(gltf.get("animations", [])) != 1 or len(gltf["skins"][0]["joints"]) != 22:
        raise RuntimeError("Palm resource must contain only matching rig, clip and open-hand visual payload")
    if sha(args.base) != SOURCE_SHA:
        raise RuntimeError("Original source changed")
    first, last = pose_samples[0]["bones"], pose_samples[-1]["bones"]
    boundary = max(abs(first[name][i][j] - last[name][i][j]) for name in first for i in range(4) for j in range(4))
    checks = {"original_unchanged": True, "bones_22": len(rig.data.bones) == 22,
        "source_rest_and_parent_unchanged": rests == {b.name: [list(row) for row in b.matrix_local] for b in rig.data.bones} and parents == {b.name: b.parent.name if b.parent else None for b in rig.data.bones},
        "boundary_pose_exact": boundary == 0., "planted_feet_under_10um": max_foot_drift < 1e-5,
        "reachable_arm_targets_under_1mm": max_wrist_residual < 0.001,
        "contact_palm_faces_forward": Vector(samples[56]["palm_normal"]).dot(Vector((0, 0, 1))) > 0.999,
        "no_source_character_mesh_copy": len(gltf["meshes"]) == 1, "no_images": not gltf.get("images"),
        "one_1_45s_clip": gltf["animations"][0]["name"] == CLIP_NAME}
    report = {"schema": 1, "status": "Authored dedicated open-palm animation candidate; CPU invariants checked, in-scene visual review pending",
        "author": "Codex for Shu; original local choreography and five-finger open-hand geometry", "license": "Original project animation/hand derivative; existing Tinglan technical-source terms retained",
        "builder": "tools/hero_lookdev/build_ambush_palm_clips.py", "builder_sha256": sha(__file__), "blender": bpy.app.version_string,
        "source": {"path": str(args.base), "sha256": SOURCE_SHA, "after_sha256": sha(args.base), "original_meshes_textures_rig_unchanged": True},
        "editable_blend": {"path": str(args.blend), "sha256": sha(args.blend)},
        "output": {"path": str(args.out), "bytes": len(data), "sha256": sha(args.out)},
        "clip": {"name": CLIP_NAME, "fps": FPS, "seconds": SECONDS, "frames": [0, scene.frame_end], "contact_seconds": CONTACT,
            "phases": [{"name": "sink_and_coil", "from": 0, "to": 0.38}, {"name": "palm_drive", "from": 0.38, "to": CONTACT}, {"name": "follow_through", "from": CONTACT, "to": 0.75}, {"name": "settle", "from": 0.75, "to": SECONDS}],
            "root_motion": "No actor/rig translation or rotation tracks; local pelvis loading with both original foot transforms planted", "samples": samples},
        "hand": hand_info, "bones": {"names": [b.name for b in rig.data.bones], "rest_matrices_blender": rests, "parents": parents},
        "godot_integration": {"animation_library_suggestion": "Palm", "clip_id_suggestion": "Palm/TinglanPalm", "hand_mesh_name": HAND_NAME,
            "skeleton": "Copy animation tracks by identical bone name onto original Skeleton3D; copy only hand Mesh/Skin onto a new MeshInstance3D using original skeleton path; free temporary source scene",
            "hand_visibility": "Only during this clip: show TinglanOpenPalm; hide TinglanRelaxedHand and TinglanPointingHand. Keep TinglanRightGrip and TinglanJian visible.",
            "scale": "Hand mesh uses original source rest coordinates; place under same model scale/origin as existing skinned meshes, with identity transform. Do not multiply source calibration twice.",
            "palm_origin": "original skeleton.global_transform * bone_global_pose(hand.L) * Vector3(0,0.055,0.018)",
            "import_animation_fps": 100, "remove_immutable_tracks": False, "import_profile_required": True,
            "import_subresources": {"nodes": {"PATH:AnimationPlayer": {"optimizer/enabled": False}}},
            "import_optimizer_reason": "Default optimizer removed dense IK keys and caused 1.68mm foot drift; disabled optimizer CPU probe reduces this to1.65um.",
            "floating_point_tolerances": {"rest_or_skin_max_m": 0.00002, "idle_boundary_max_component_error": 0.00005},
            "import_profile_owner": "Root integration; builder intentionally writes only its assigned GLB/manifest paths, no .import sidecar",
            "frame_clock": "One-to-one real source seconds, contact .56s; do not apply the existing .13s sword-hit nonlinear retiming"},
        "measurements": {"boundary_max_matrix_error": boundary, "max_planted_foot_drift_m": max_foot_drift, "max_wrist_target_residual_m": max_wrist_residual,
            "palm_coil_to_contact_distance_m": (Vector(samples[56]["palm_center"]) - Vector(samples[38]["palm_center"])).length},
        "validation": {"checks": checks, "all_pass": all(checks.values()), "gpu_render": "Not performed by asset author; root owns serial scene review", "runtime_import": "Pending separate CPU Godot rig/clip/skin probe"},
        "new_cloud_calls": 0, "new_paid_calls": 0, "new_installs": 0,
        "authoring_tool_notice": "Blender reports its optional MeshOptimizer library unavailable at startup. MeshOptimizer compression is not requested or used; standard uncompressed GLB export completes. Early unparented-hand export warning was corrected by parenting the new hand to the original rig.",
        "limitations": ["Rigid five-finger open hand bound to hand.L; no separate finger bones or animated finger joints.", "Original conservative robe/hair weights retained; no cloth simulation.", "Numerical pose checks do not establish naturalness or final visual acceptance."]}
    args.out.with_name("source-palm-clips.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if not all(checks.values()):
        raise RuntimeError("Palm clip CPU invariants failed: " + repr(checks))
    print("PALM_CLIP", json.dumps({"path": str(args.out), "sha256": sha(args.out), "bytes": len(data), "checks": checks, "measurements": report["measurements"]}), flush=True)


if __name__ == "__main__":
    main()
