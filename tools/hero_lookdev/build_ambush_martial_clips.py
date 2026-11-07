#!/usr/bin/env python3
"""Author two short attacks on a copy of the approved Jiang skeleton.

Run with the existing Blender, not an addon or a downloaded animation:
  blender --disable-autoexec --background --python-exit-code 1 --python THIS -- \
    --base assets/art/mountain_ambush/jiang-approved.glb \
    --out assets/art/mountain_ambush/jiang-martial-clips.glb \
    --blend .local/sources/jiang-martial-clips-20261025/candidate.blend

Only the original rig is exported, with one three-vertex skin carrier so Godot
imports a real Skeleton3D. No source character meshes, materials or images are
duplicated into the runtime asset. The carrier is never attached to the actor.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

BASE_SHA = "e8d74b2e0be789f272597aa6f7fc268f57851bb669ed43d97e2efa91c3860e27"
DURATION = 0.32
FPS = 100
SOURCE_ENDS = [0.0, 0.065, 0.13, 0.225, 0.32]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


def two_bone(a, pole, end, l1, l2):
    delta = end - a
    distance = max(abs(l1 - l2) + 1e-6, min(l1 + l2 - 1e-6, delta.length))
    axis = delta.normalized()
    side = pole - a - axis * (pole - a).dot(axis)
    if side.length < 1e-7:
        side = axis.cross(Vector((1, 0, 0)))
    side.normalize()
    x = (l1 * l1 - l2 * l2 + distance * distance) / (2.0 * distance)
    return a + axis * x + side * math.sqrt(max(0.0, l1 * l1 - x * x)), a + axis * distance


def set_segment(rig, name, start, end, orientation=None):
    rest = rig.data.bones[name]
    q = orientation
    if q is None:
        q = (rest.tail_local - rest.head_local).rotation_difference(end - start) @ rest.matrix_local.to_quaternion()
    rig.pose.bones[name].matrix = Matrix.LocRotScale(start, q, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def sword_landmarks(rig, sword):
    ids = set()
    for poly in sword.data.polygons:
        material = sword.data.materials[poly.material_index]
        if "Steel" in material.name or "Edge" in material.name:
            ids.update(poly.vertices)
    points = np.array([sword.data.vertices[i].co[:] for i in sorted(ids)])
    mean = points.mean(axis=0)
    _, vectors = np.linalg.eigh(np.cov(points.T))
    direction = vectors[:, -1]
    if direction[1] > 0.0:
        direction *= -1.0
    along = (points - mean) @ direction
    base = points[along <= along.min() + 0.004].mean(axis=0)
    tip = points[along >= along.max() - 0.004].mean(axis=0)
    inverse = rig.data.bones["hand.R"].matrix_local.inverted()
    return {"base": Vector(base), "tip": Vector(tip),
            "hand_base": inverse @ Vector(base), "hand_tip": inverse @ Vector(tip),
            "selected_materials": [m.name for m in sword.data.materials if "Steel" in m.name or "Edge" in m.name]}


def interpolate_controls(keys, time):
    for index in range(len(SOURCE_ENDS) - 1):
        if time <= SOURCE_ENDS[index + 1] + 1e-8:
            t = smooth((time - SOURCE_ENDS[index]) / (SOURCE_ENDS[index + 1] - SOURCE_ENDS[index]))
            a, b = keys[index], keys[index + 1]
            return {name: (Vector(a[name]).lerp(Vector(b[name]), t) if isinstance(a[name], tuple)
                           else a[name] * (1.0 - t) + b[name] * t) for name in a}
    return keys[-1]


def control(yaw, lean, shift, right, direction, left, step):
    return {"yaw": yaw, "lean": lean, "shift": shift, "right": right,
            "direction": direction, "left": left, "step": step}


def author_clip(rig, name, neutral, neutral_world, landmarks, keys):
    scene = bpy.context.scene
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    samples = []
    neutral_axis = (neutral_world["hand.R"] @ landmarks["hand_tip"] - neutral_world["hand.R"] @ landmarks["hand_base"]).normalized()
    lengths = {side: [(neutral_world["forearm." + side].translation - neutral_world["upper_arm." + side].translation).length,
                       (neutral_world["hand." + side].translation - neutral_world["forearm." + side].translation).length] for side in ["R", "L"]}
    leg_lengths = {side: [(neutral_world["shin." + side].translation - neutral_world["thigh." + side].translation).length,
                           (neutral_world["foot." + side].translation - neutral_world["shin." + side].translation).length] for side in ["R", "L"]}
    for frame in range(33):
        time = frame / FPS
        scene.frame_set(frame)
        for bone in rig.pose.bones:
            bone.matrix_basis = neutral[bone.name]
        bpy.context.view_layer.update()
        c = interpolate_controls(keys, time)
        if frame not in [0, 32]:
            pivot = neutral_world["pelvis"].translation
            yaw = math.radians(c["yaw"])
            lean = math.radians(c["lean"])
            transform = Matrix.Translation(c["shift"]) @ Matrix.Translation(pivot) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Translation(-pivot)
            rig.pose.bones["pelvis"].matrix = transform @ neutral_world["pelvis"]
            bpy.context.view_layer.update()
            chest = rig.pose.bones["chest"]
            chest.matrix = Matrix.LocRotScale(chest.head.copy(), Quaternion((1, 0, 0), lean) @ chest.matrix.to_quaternion(), Vector((1, 1, 1)))
            bpy.context.view_layer.update()
            head = rig.pose.bones["head"]
            head.matrix = Matrix.LocRotScale(head.head.copy(), Quaternion((0, 0, 1), -yaw * 0.70) @ head.matrix.to_quaternion(), Vector((1, 1, 1)))
            bpy.context.view_layer.update()
            for side in ["R", "L"]:
                hip = rig.pose.bones["thigh." + side].head.copy()
                ankle = neutral_world["foot." + side].translation.copy()
                if side == "L":
                    ankle.y += c["step"]
                    # Lift the advancing/retracting foot; it is grounded at contact.
                    ankle.z += 0.045 * math.sin(math.pi * min(time / 0.13, 1.0)) if time <= 0.13 else 0.035 * math.sin(math.pi * max(0.0, (time - 0.225) / 0.095))
                knee, actual_ankle = two_bone(hip, hip + Vector((0.0, -0.30, -0.35)), ankle, *leg_lengths[side])
                set_segment(rig, "thigh." + side, hip, knee)
                set_segment(rig, "shin." + side, knee, actual_ankle)
                foot = neutral_world["foot." + side].copy()
                foot.translation = actual_ankle
                rig.pose.bones["foot." + side].matrix = foot
                bpy.context.view_layer.update()
            for side, key in [("R", "right"), ("L", "left")]:
                shoulder = rig.pose.bones["upper_arm." + side].head.copy()
                goal = Vector(c[key]) + Vector(c["shift"])
                pole = shoulder + Vector((-0.30 if side == "R" else 0.30, 0.12, -0.25))
                elbow, wrist = two_bone(shoulder, pole, goal, *lengths[side])
                set_segment(rig, "upper_arm." + side, shoulder, elbow)
                set_segment(rig, "forearm." + side, elbow, wrist)
                if side == "R":
                    q = neutral_axis.rotation_difference(Vector(c["direction"]).normalized()) @ neutral_world["hand.R"].to_quaternion()
                else:
                    q = neutral_world["hand.L"].to_quaternion()
                rig.pose.bones["hand." + side].matrix = Matrix.LocRotScale(wrist, q, Vector((1, 1, 1)))
                bpy.context.view_layer.update()
        for bone in rig.pose.bones:
            bone.rotation_mode = "QUATERNION"
            for channel in ["location", "rotation_quaternion", "scale"]:
                bone.keyframe_insert(channel, frame=frame)
        hand = rig.pose.bones["hand.R"].matrix
        base = hand @ landmarks["hand_base"]
        tip = hand @ landmarks["hand_tip"]
        samples.append({"source_seconds": time, "blade_base": list(base), "blade_tip": list(tip),
                        "foot_R": list(rig.pose.bones["foot.R"].head), "foot_L": list(rig.pose.bones["foot.L"].head),
                        "hand_grip_length": (tip - base).length})
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, action)
    track.mute = True
    rig.animation_data.action = None
    return {"name": name, "seconds": DURATION, "source_contact_seconds": 0.13,
            "frames": [0, 32], "fps": FPS, "samples": samples,
            "first_last_blade_error": (Vector(samples[0]["blade_tip"]) - Vector(samples[-1]["blade_tip"])).length,
            "root_motion": "None on actor/rig node; local pelvis and analytical planted-foot IK only"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--blend", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if sha(args.base) != BASE_SHA:
        raise RuntimeError("Approved source GLB hash differs")
    if len({args.base.resolve(), args.out.resolve(), args.blend.resolve()}) != 3:
        raise RuntimeError("Source and outputs must be separate")
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
    neutral = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
    neutral_world = {b.name: b.matrix.copy() for b in rig.pose.bones}
    landmarks = sword_landmarks(rig, bpy.data.objects["JiangRightGrip_Jian"])
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    rig.animation_data.action = None
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = 0
    scene.frame_end = 32
    rest_axis = (neutral_world["hand.R"] @ landmarks["hand_tip"] - neutral_world["hand.R"] @ landmarks["hand_base"]).normalized()
    neutral_key = control(0., 0., (0., 0., 0.), tuple(neutral_world["hand.R"].translation), tuple(rest_axis), tuple(neutral_world["hand.L"].translation), 0.)
    pierce = [neutral_key,
              control(-12., -3., (0., 0.025, -0.018), (-0.29, -0.13, 1.24), (-0.12, -0.96, 0.12), (0.34, -0.10, 1.10), -0.055),
              control(8., 8., (0., -0.065, -0.028), (-0.13, -0.54, 1.29), (0., -1., 0.015), (0.32, 0.035, 1.22), -0.16),
              control(10., 5., (0., -0.04, -0.018), (-0.17, -0.47, 1.27), (0.05, -0.99, -0.025), (0.34, -0.01, 1.15), -0.16), neutral_key]
    sweep = [neutral_key,
             control(-34., 4., (0.015, 0.01, -0.070), (-0.43, -0.13, 1.20), (-0.95, -0.30, 0.03), (0.34, -0.21, 1.24), -0.035),
             control(18., 6., (-0.015, -0.025, -0.060), (-0.11, -0.48, 1.18), (0., -1., 0.025), (0.34, 0.04, 1.31), -0.07),
             control(48., 2., (-0.015, -0.015, -0.035), (0.29, -0.27, 1.24), (0.93, -0.36, 0.045), (0.18, 0.11, 1.25), -0.07), neutral_key]
    clips = [author_clip(rig, "CloudPierce", neutral, neutral_world, landmarks, pierce),
             author_clip(rig, "ReturningSweep", neutral, neutral_world, landmarks, sweep)]
    for b in rig.pose.bones:
        b.matrix_basis = neutral[b.name]
    scene.frame_set(0)
    bpy.context.view_layer.update()
    # Keep original meshes only in the local review Blend, never in exported GLB.
    bpy.ops.wm.save_as_mainfile(filepath=str(args.blend.resolve()))
    data = bpy.data.meshes.new("AnimationSkinCarrier")
    data.from_pydata([(0, 0, 0), (0.00001, 0, 0), (0, 0.00001, 0)], [], [(0, 1, 2)])
    carrier = bpy.data.objects.new("AnimationSkinCarrier", data)
    scene.collection.objects.link(carrier)
    carrier.vertex_groups.new(name="pelvis").add([0, 1, 2], 1., "REPLACE")
    carrier.modifiers.new("Skeleton import carrier", "ARMATURE").object = rig
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [rig, carrier]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(args.out.resolve()), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=False, export_materials="NONE", export_texcoords=False,
        export_normals=False, export_animations=True, export_animation_mode="NLA_TRACKS",
        export_frame_range=False, export_force_sampling=True, export_nla_strips=True,
        export_skins=True, export_def_bones=False, export_cameras=False, export_lights=False)
    raw = args.out.read_bytes()
    length = struct.unpack_from("<I", raw, 12)[0]
    gltf = json.loads(raw[20:20 + length])
    if len(gltf.get("meshes", [])) != 1 or len(gltf.get("materials", [])) or len(gltf.get("images", [])):
        raise RuntimeError("Animation asset unexpectedly contains source visual payload")
    # Godot's default 30fps bake is not exact at the authored .13s contact.
    # Preserve the 100fps short clip through import, including immutable bones.
    profile = args.out.with_suffix(args.out.suffix + ".import")
    profile_text = profile.read_text() if profile.is_file() else '[remap]\nimporter="scene"\ntype="PackedScene"\n\n[params]\n'
    for key, value in [("animation/fps", "100"), ("animation/remove_immutable_tracks", "false")]:
        pattern = r"(?m)^" + re.escape(key) + r"=.*$"
        if re.search(pattern, profile_text):
            profile_text = re.sub(pattern, key + "=" + value, profile_text)
        else:
            profile_text += key + "=" + value + "\n"
    profile.write_text(profile_text)
    def yup(point):
        return [point.x, point.z, -point.y]
    report = {"status": "new authored combat animation candidates, pending visual playtest", "author": "Codex for Shu; local Blender original choreography",
        "license": "Original project animation; approved model/rig retained", "blender": bpy.app.version_string,
        "source_glb": str(args.base), "source_glb_sha256": BASE_SHA, "source_glb_sha256_after": sha(args.base),
        "source_blend_unmodified": True, "new_cloud_calls": 0, "new_paid_calls": 0,
        "builder": str(Path(__file__).relative_to(Path(__file__).resolve().parents[2])), "builder_sha256": sha(__file__),
        "output_sha256": sha(args.out), "bytes": args.out.stat().st_size,
        "godot_import": {"profile": str(profile), "profile_sha256": sha(profile), "animation_fps": 100,
                         "remove_immutable_tracks": False, "required": True,
                         "reason": "30fps resampling caused up to8mm support-foot drift;100fps CPU probe preserves contacts"},
        "animations": clips, "bone_names": [b.name for b in rig.data.bones],
        "carrier": {"meshes": 1, "triangles": 1, "vertices": 3, "materials": 0, "images": 0,
                    "reason": "Makes Godot import a Skeleton3D; loader copies animations and frees the entire temporary scene"},
        "weapon_landmarks": {"space": "Original GLB mesh coordinates, Y up/+Z forward", "bone": "hand.R",
            "base": yup(landmarks["base"]), "tip": yup(landmarks["tip"]), "method": "PCA of actual original steel/edge material vertices, center of 4mm endpoint bands", "materials": landmarks["selected_materials"]},
        "gltf_clips": [{"name": a["name"], "channels": len(a["channels"]),
             "seconds": max(gltf["accessors"][s["input"]]["max"][0] for s in a["samplers"])} for a in gltf["animations"]]}
    args.out.with_name("source-martial-clips.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print("MARTIAL_CLIPS", json.dumps({"asset": str(args.out), "sha256": report["output_sha256"], "bytes": report["bytes"], "clips": report["gltf_clips"], "weapon_landmarks": report["weapon_landmarks"]}), flush=True)


if __name__ == "__main__":
    main()
