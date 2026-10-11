"""Focused Blender smoke test for the bounded legacy Jiang character builder.

Run: Blender -b --factory-startup --python tests/sword_jiang_legacy_character_smoke.py -- --repo PATH
This creates only an in-memory 31-bone CMU rig and four skinned character meshes.
"""
import importlib.util
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError("could not load " + str(path))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    separator = sys.argv.index("--") if "--" in sys.argv else len(sys.argv)
    args = sys.argv[separator + 1:]
    if len(args) != 2 or args[0] != "--repo":
        raise SystemExit("usage: --repo PATH")
    repo = Path(args[1]).resolve()
    converter = load("jiang_legacy_smoke_cmu_motion", repo / "tools/sword_mocap/cmu_motion.py")
    shared = load("jiang_legacy_smoke_shared", repo / "tools/sword_mocap/make_study.py")
    character = load("jiang_legacy_smoke_character", repo / "tools/sword_jiang/legacy_character.py")

    skeleton = converter.parse_asf(repo / "assets/data/sword_mocap/source/02.asf")
    channels = {"root": (0, 0, 0, 0, 0, 0)}
    channels.update({bone.name: tuple(0 for _ in bone.dofs)
                     for bone in skeleton.bones if bone.dofs})
    rest = converter.solve_frame(skeleton, converter.MotionFrame(1, channels))
    for bone in rest.values():
        bone["head"] = list(Vector(bone["head"]) * 0.70)
        bone["tail"] = list(Vector(bone["tail"]) * 0.70)
    specs = converter.sample_file(repo / "assets/data/sword_mocap/source/02.asf",
                                  repo / "assets/data/sword_mocap/source/02_09.amc",
                                  stride=2)["bones"]

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    armature = shared.make_rig(specs, rest)
    before_bones = {
        bone.name: (tuple(float(x) for x in bone.head_local),
                    tuple(float(x) for x in bone.tail_local))
        for bone in armature.data.bones
    }
    receipt = character.build_character(armature, rest)

    require(len(armature.data.bones) == 31, "the source CMU skeleton must remain exactly 31 bones")
    require(set(before_bones) == {bone.name for bone in armature.data.bones},
            "the original CMU bone names changed")
    require(len(receipt["objects"]) == 4, "expected exactly four weighted character mesh objects")
    require(receipt["objects"] == ["JiangBody", "JiangGarment", "JiangFace", "JiangHair"],
            "character object contract changed")
    require(receipt["vertex_count"] <= 24000, "base geometry exceeds 24,000 vertices")
    require(receipt["vertex_count"] > 1000, "character geometry unexpectedly sparse")
    require(receipt["identity"]["name"] == "江砚秋", "character identity is missing")
    require(receipt["cloth_weights"]["all_normalized"], "reported weights are not normalized")
    require(receipt["cloth_weights"]["max_observed_influences"] <= 4,
            "character exceeds four influences per vertex")
    require(receipt["identity"]["robe_panels_reach_near_knee"],
            "the receipt does not record the extended robe panels")

    bone_names = set(before_bones)
    observed_vertices = 0
    observed_max_influences = 0
    observed_max_sum_error = 0.0
    for object_name in receipt["objects"]:
        obj = bpy.data.objects[object_name]
        require(obj.type == "MESH", object_name + " is not a mesh")
        require(obj.parent == armature, object_name + " is not parented to the source rig")
        require(all(abs(float(scale) - 1.0) < 1.0e-7 for scale in obj.scale),
                object_name + " uses object scaling")
        require(any(mod.type == "ARMATURE" and mod.object == armature for mod in obj.modifiers),
                object_name + " lacks the source armature modifier")
        modifier = next(mod for mod in obj.modifiers if mod.type == "ARMATURE")
        require(not modifier.use_deform_preserve_volume,
                "dual-quaternion skinning must remain disabled")
        require(obj.data.color_attributes.get("JiangWash") is not None,
                object_name + " is missing its fixed vertex-color attribute")
        group_map = {group.index: group.name for group in obj.vertex_groups}
        require(set(group_map.values()).issubset(bone_names),
                object_name + " added non-CMU bone groups")
        for vertex in obj.data.vertices:
            require(all(math.isfinite(float(axis)) for axis in vertex.co),
                    object_name + " has a non-finite vertex")
            influences = [(group_map[item.group], float(item.weight))
                          for item in vertex.groups]
            require(0 < len(influences) <= 4, object_name + " has invalid influence count")
            require(all(name in bone_names and math.isfinite(weight) and weight > 0.0
                        for name, weight in influences),
                    object_name + " has invalid weight groups or values")
            total = sum(weight for _, weight in influences)
            error = abs(total - 1.0)
            require(error < 1.0e-5, object_name + " has non-normalized vertex weights")
            observed_vertices += 1
            observed_max_influences = max(observed_max_influences, len(influences))
            observed_max_sum_error = max(observed_max_sum_error, error)

    require(observed_vertices <= 24000, "evaluated mesh objects exceed the base vertex budget")
    require(all(abs(float(scale) - 1.0) < 1.0e-7 for scale in armature.scale),
            "source armature scale changed")
    for bone in armature.data.bones:
        expected_head, expected_tail = before_bones[bone.name]
        require((Vector(expected_head) - bone.head_local).length < 1.0e-8,
                bone.name + " head changed during character construction")
        require((Vector(expected_tail) - bone.tail_local).length < 1.0e-8,
                bone.name + " tail changed during character construction")

    for side, name in (("left", "lhand"), ("right", "rhand")):
        expected = (Vector(rest[name]["head"]) + Vector(rest[name]["tail"])) * 0.5
        actual = Vector(receipt["landmarks"]["closed_fist_centers_m"][side])
        require((expected - actual).length < 1.0e-8,
                side + " closed fist is not at the CMU hand midpoint")
    expected_face = Vector(rest["head"]["head"]) + Vector((0.0, 0.0, 0.06))
    actual_face = Vector(receipt["identity"]["face_center_m"])
    require((expected_face - actual_face).length < 1.0e-8,
            "face center differs from the approved placement")
    require([round(float(x), 6) for x in receipt["identity"]["face_radii_m"]]
            == [0.2, 0.17, 0.23], "face proportions differ from the character contract")

    report = {
        "status": "PASS",
        "bone_count": len(armature.data.bones),
        "mesh_objects": receipt["objects"],
        "vertex_count": observed_vertices,
        "max_influences": observed_max_influences,
        "max_weight_sum_error": observed_max_sum_error,
        "face_center_error_m": (expected_face - actual_face).length,
        "closed_fist_center_error_m": 0.0,
        "unit_object_scales": True,
        "preserve_volume": False,
    }
    print("JIANG_LEGACY_CHARACTER_SMOKE " + json.dumps(report, ensure_ascii=False, sort_keys=True),
          flush=True)


if __name__ == "__main__":
    main()
