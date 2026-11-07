#!/usr/bin/env python3
"""Blender CPU compiler for recipe-authored 22-bone workshop motions.

This script has no move IDs. Three templates share a planted-foot pose-key
solver. The exported GLB carries one clip and a tiny Skin carrier; the existing
profile provides the visible character, weapon and optional open palm.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import sys
import bpy
from mathutils import Matrix, Quaternion, Vector


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def helper(name):
    path = Path(__file__).with_name(name)
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


palm_math = helper("build_ambush_palm_clips.py")
sword_math = helper("build_ambush_martial_clips.py")


def yup(point):
    return [float(point.x), float(point.z), float(-point.y)]


def interpolate(keys, time):
    for a, b in zip(keys, keys[1:]):
        if time <= b["t"] + 1e-9:
            amount = palm_math.smooth((time - a["t"]) / (b["t"] - a["t"]))
            return {name: Vector(a[name]).lerp(Vector(b[name]), amount) if isinstance(a[name], list)
                    else a[name] * (1 - amount) + b[name] * amount for name in a if name != "t"}
    return keys[-1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--profiles", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--blend", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    recipe = json.loads(args.recipe.read_text())
    move = recipe["move"]
    profile = json.loads(args.profiles.read_text())["profiles"][move["profile"]]
    source = args.root / profile["source_asset"].removeprefix("res://")
    if sha(source) != profile["source_sha256"]:
        raise RuntimeError("Immutable source SHA mismatch")
    if recipe["template"] not in {"sword_path", "palm_sweep", "palm_guard"}:
        raise RuntimeError("Unknown authoring template")
    for path in [args.out, args.blend, args.report]:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.resolve() == source.resolve():
            raise RuntimeError("Source cannot be an output")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    if [b.name for b in rig.data.bones] != profile["bone_names"]:
        raise RuntimeError("Profile bone contract mismatch")
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    rig.animation_data.action = bpy.data.actions["Idle"]
    scene = bpy.context.scene
    scene.frame_set(0)
    bpy.context.view_layer.update()
    neutral = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
    world = {b.name: b.matrix.copy() for b in rig.pose.bones}
    rests = {b.name: [list(row) for row in b.matrix_local] for b in rig.data.bones}
    parents = {b.name: b.parent.name if b.parent else None for b in rig.data.bones}
    landmarks = None
    if recipe["template"] == "sword_path":
        landmarks = sword_math.sword_landmarks(rig, bpy.data.objects["JiangRightGrip_Jian"])
        axis = (world["hand.R"] @ landmarks["hand_tip"] - world["hand.R"] @ landmarks["hand_base"]).normalized()
    else:
        axis = Vector((0, -1, 0))
    keys = []
    for original in recipe["motion"]["keys"]:
        key = dict(original)
        for name, bone in [("left", "hand.L"), ("right", "hand.R")]:
            if key[name] == "neutral":
                key[name] = list(world[bone].translation)
        if key["right_direction"] == "neutral":
            key["right_direction"] = list(axis)
        keys.append(key)
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    rig.animation_data.action = None
    fps = recipe["motion"]["fps"]
    seconds = move["animation"]["source_seconds"]
    scene.render.fps = fps
    scene.frame_start = 0
    scene.frame_end = round(seconds * fps)
    clip = move["animation"]["clip"]
    action = bpy.data.actions.new(clip)
    rig.animation_data.action = action
    lengths = {side: {"arm": [(world["forearm." + side].translation - world["upper_arm." + side].translation).length,
        (world["hand." + side].translation - world["forearm." + side].translation).length],
        "leg": [(world["shin." + side].translation - world["thigh." + side].translation).length,
        (world["foot." + side].translation - world["shin." + side].translation).length]} for side in ["L", "R"]}
    upright = Matrix(((1., 0., 0.), (0., 0., -1.), (0., 1., 0.))).to_quaternion()
    max_foot, max_wrist, right_rotation = 0., 0., 0.
    samples = []
    for frame in range(scene.frame_end + 1):
        time = frame / fps
        scene.frame_set(frame)
        for bone in rig.pose.bones:
            bone.matrix_basis = neutral[bone.name]
        bpy.context.view_layer.update()
        control = interpolate(keys, time)
        if frame not in [0, scene.frame_end]:
            pivot = world["pelvis"].translation
            transform = Matrix.Translation(control["shift"]) @ Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(control["hip_yaw"]), 4, "Z") @ Matrix.Translation(-pivot)
            rig.pose.bones["pelvis"].matrix = transform @ world["pelvis"]
            bpy.context.view_layer.update()
            chest = rig.pose.bones["chest"]
            rotation = Quaternion((0, 0, 1), math.radians(control["chest_yaw"])) @ Quaternion((1, 0, 0), math.radians(control["lean"])) @ chest.matrix.to_quaternion()
            chest.matrix = Matrix.LocRotScale(chest.head.copy(), rotation, Vector((1, 1, 1)))
            bpy.context.view_layer.update()
            head = rig.pose.bones["head"]
            head.matrix = Matrix.LocRotScale(head.head.copy(), Quaternion((0, 0, 1), math.radians(-control["hip_yaw"] * .7)) @ head.matrix.to_quaternion(), Vector((1, 1, 1)))
            bpy.context.view_layer.update()
            for side in ["L", "R"]:
                hip = rig.pose.bones["thigh." + side].head.copy()
                ankle = world["foot." + side].translation.copy()
                knee, foot = palm_math.two_bone(hip, hip + Vector((0, -.32, -.40)), ankle, *lengths[side]["leg"])
                palm_math.segment(rig, "thigh." + side, hip, knee)
                palm_math.segment(rig, "shin." + side, knee, foot)
                foot_transform = world["foot." + side].copy()
                foot_transform.translation = foot
                rig.pose.bones["foot." + side].matrix = foot_transform
                bpy.context.view_layer.update()
                shoulder = rig.pose.bones["upper_arm." + side].head.copy()
                goal = Vector(control["left" if side == "L" else "right"])
                if side == "R" and recipe["template"] != "sword_path":
                    goal += Vector(control["shift"]) * .30
                pole = shoulder + Vector((.33, -.10, -.23) if side == "L" else (-.30, .10, -.22))
                elbow, wrist = palm_math.two_bone(shoulder, pole, goal, *lengths[side]["arm"])
                max_wrist = max(max_wrist, (wrist - goal).length)
                palm_math.segment(rig, "upper_arm." + side, shoulder, elbow)
                palm_math.segment(rig, "forearm." + side, elbow, wrist)
                rotation = world["hand." + side].to_quaternion()
                if side == "L":
                    rotation = rotation.slerp(Quaternion((0, 0, 1), math.radians(control["palm_yaw"])) @ upright, control["palm_open"])
                elif recipe["template"] == "sword_path":
                    rotation = axis.rotation_difference(Vector(control["right_direction"]).normalized()) @ rotation
                rig.pose.bones["hand." + side].matrix = Matrix.LocRotScale(wrist, rotation, Vector((1, 1, 1)))
                bpy.context.view_layer.update()
        for bone in rig.pose.bones:
            bone.rotation_mode = "QUATERNION"
            for channel in ["location", "rotation_quaternion", "scale"]:
                bone.keyframe_insert(channel, frame=frame)
        foot_drift = max((rig.pose.bones["foot." + s].head - world["foot." + s].translation).length for s in ["L", "R"])
        max_foot = max(max_foot, foot_drift)
        right = rig.pose.bones["hand.R"].matrix
        right_rotation = max(right_rotation, right.to_quaternion().rotation_difference(world["hand.R"].to_quaternion()).angle)
        sample = {"seconds": time, "palm_center": yup(rig.pose.bones["hand.L"].matrix @ Vector((0, .055, .018))),
                  "left_wrist": yup(rig.pose.bones["hand.L"].head), "right_wrist": yup(right.translation),
                  "hip": yup(rig.pose.bones["pelvis"].head), "foot_drift_m": foot_drift}
        if landmarks:
            sample.update(blade_base=yup(right @ landmarks["hand_base"]), blade_tip=yup(right @ landmarks["hand_tip"]))
        samples.append(sample)
    track = rig.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, 0, action)
    track.mute = True
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis = neutral[bone.name]
    scene.frame_set(0)
    bpy.context.view_layer.update()
    # Full source meshes remain editable in a local-only Blend. Runtime export
    # explicitly selects only the unchanged rig and a three-vertex Skin carrier.
    bpy.ops.wm.save_as_mainfile(filepath=str(args.blend.resolve()))
    mesh = bpy.data.meshes.new("WorkshopAnimationCarrier")
    mesh.from_pydata([(0, 0, 0), (.00001, 0, 0), (0, .00001, 0)], [], [(0, 1, 2)])
    carrier = bpy.data.objects.new("WorkshopAnimationCarrier", mesh)
    scene.collection.objects.link(carrier)
    carrier.parent = rig
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
    data = args.out.read_bytes()
    gltf = json.loads(data[20:20 + struct.unpack_from("<I", data, 12)[0]])
    checks = {
        "original_source_unchanged": sha(source) == profile["source_sha256"],
        "same_22_bones_and_parents": len(rig.data.bones) == 22 and parents == {b.name: b.parent.name if b.parent else None for b in rig.data.bones},
        "source_bind_rest_unchanged": rests == {b.name: [list(row) for row in b.matrix_local] for b in rig.data.bones},
        "feet_planted_under_10um": max_foot < .00001,
        "arm_targets_reachable_under_1mm": max_wrist < .001,
        "one_clip_with_expected_name": len(gltf.get("animations", [])) == 1 and gltf["animations"][0]["name"] == clip,
        "clip_duration_matches": abs(max(gltf["accessors"][s["input"]]["max"][0] for s in gltf["animations"][0]["samplers"]) - seconds) < 1e-5,
        "carrier_only_no_visual_copy": len(gltf.get("meshes", [])) == 1 and not gltf.get("materials") and not gltf.get("images"),
        "skin_has_original_22_joints": len(gltf["skins"][0]["joints"]) == 22,
        "no_actor_node_animation": all(gltf["nodes"][c["target"]["node"]]["name"] in profile["bone_names"] for c in gltf["animations"][0]["channels"]),
        "right_sword_orientation_stable_for_palms": recipe["template"] == "sword_path" or right_rotation < .001,
    }
    report = {"schema_version": 1, "status": "CPU invariants passed; in-scene artistic acceptance is a separate review",
        "author": "Codex for Shu; original local pose-key choreography", "license": profile["source_license"],
        "source": {"asset": profile["source_asset"], "sha256": profile["source_sha256"], "after_sha256": sha(source)},
        "builder": {"path": "tools/hero_lookdev/build_workshop_motions.py", "sha256": sha(__file__), "blender": bpy.app.version_string},
        "recipe_sha256": sha(args.recipe), "template": recipe["template"],
        "editable_blend": {"path": str(args.blend), "sha256": sha(args.blend)},
        "output": {"path": str(args.out), "sha256": sha(args.out), "bytes": len(data)},
        "clip": {"name": clip, "seconds": seconds, "fps": fps, "contact_seconds": recipe["motion"]["contact"], "frames": scene.frame_end + 1},
        "rig": {"names": profile["bone_names"], "parents": parents, "rest_matrices_blender": rests},
        "measurements": {"max_foot_drift_m": max_foot, "max_wrist_residual_m": max_wrist, "max_right_hand_rotation_radians": right_rotation},
        "checks": checks, "all_pass": all(checks.values()), "samples": samples,
        "import": {"fps": 100, "remove_immutable_tracks": False, "optimizer": False},
        "hand": "Provided by profile.hand_variants; not duplicated in animation-only payload",
        "limitations": ["Rigid open hand has no finger bones", "Original robe/hair weights; no cloth simulation", "CPU invariants are not visual approval"],
        "cloud_calls": 0, "paid_calls": 0, "new_installs": 0,
        "optional_tool_notice": "Blender optional MeshOptimizer library unavailable; compression is neither requested nor used"}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("WORKSHOP_MOTION", json.dumps({"clip": clip, "sha256": sha(args.out), "checks": checks, "measurements": report["measurements"]}), flush=True)
    if not all(checks.values()):
        raise RuntimeError("Motion invariant failure: " + repr(checks))


if __name__ == "__main__":
    main()
