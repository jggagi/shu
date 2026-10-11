"""Focused Blender 4.5.9 smoke test for the procedural Jiang character.

Run: Blender -b --python tests/sword_jiang_character_smoke.py -- --repo PATH
This creates only an in-memory CMU rig and four skinned character meshes.
"""
import importlib.util
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
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
    converter = load("jiang_smoke_cmu_motion", repo / "tools/sword_mocap/cmu_motion.py")
    shared = load("jiang_smoke_shared", repo / "tools/sword_mocap/make_study.py")
    character = load("jiang_smoke_character", repo / "tools/sword_jiang/character.py")

    skeleton = converter.parse_asf(repo / "assets/data/sword_mocap/source/02.asf")
    channels = {"root": (0, 0, 0, 0, 0, 0)}
    channels.update({bone.name: tuple(0 for _ in bone.dofs) for bone in skeleton.bones if bone.dofs})
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
    receipt = character.build_character(armature, rest)

    require(len(armature.data.bones) == 31, "the existing CMU skeleton must remain 31 bones")
    require(len(receipt["objects"]) == 4, "expected body, garment, face and hair objects")
    require(receipt["vertex_count"] > 1000, "character geometry unexpectedly sparse")
    require(receipt["identity"]["name"] == "江砚秋", "character identity is missing")
    require(receipt["cloth_weights"]["all_normalized"], "reported weights are not normalized")
    require(receipt["cloth_weights"]["max_observed_influences"] <= 4,
            "character exceeds four influences per vertex")

    bone_names = {bone.name for bone in armature.data.bones}
    observed_vertices = 0
    observed_max_influences = 0
    observed_max_sum_error = 0.0
    for object_name in receipt["objects"]:
        obj = bpy.data.objects[object_name]
        require(obj.type == "MESH", object_name + " is not a mesh")
        require(obj.parent == armature, object_name + " is not parented to the source rig")
        require(obj.scale.length > 0.0 and all(abs(s - 1.0) < 1.0e-7 for s in obj.scale),
                object_name + " uses object scaling")
        require(any(mod.type == "ARMATURE" and mod.object == armature for mod in obj.modifiers),
                object_name + " lacks the source armature modifier")
        modifier = next(mod for mod in obj.modifiers if mod.type == "ARMATURE")
        require(not modifier.use_deform_preserve_volume, "dual-quaternion skinning must remain disabled")
        require(obj.data.color_attributes.get("JiangWash") is not None,
                object_name + " is missing its fixed vertex-color attribute")
        group_map = {group.index: group.name for group in obj.vertex_groups}
        require(set(group_map.values()).issubset(bone_names), object_name + " added non-CMU bone groups")
        for vertex in obj.data.vertices:
            influences = [(group_map[item.group], item.weight) for item in vertex.groups]
            require(0 < len(influences) <= 4, object_name + " has invalid influence count")
            require(all(name in bone_names for name, _ in influences), object_name + " has unknown weight group")
            total = sum(weight for _, weight in influences)
            error = abs(total - 1.0)
            require(error < 1.0e-5, object_name + " has non-normalized vertex weights")
            observed_vertices += 1
            observed_max_influences = max(observed_max_influences, len(influences))
            observed_max_sum_error = max(observed_max_sum_error, error)

    for side, name in (("left", "lhand"), ("right", "rhand")):
        expected = (Vector(rest[name]["head"]) + Vector(rest[name]["tail"])) * 0.5
        actual = Vector(receipt["landmarks"]["closed_fist_centers_m"][side])
        require((expected - actual).length < 1.0e-8, side + " closed fist is not at the CMU hand midpoint")
    expected_face = Vector(rest["head"]["head"]) + Vector((0.0, 0.0, 0.06))
    actual_face = Vector(receipt["identity"]["face_center_m"])
    require((expected_face - actual_face).length < 1.0e-8, "face center differs from the approved placement")
    require([round(x, 6) for x in receipt["identity"]["face_radii_m"]] == [0.2, 0.17, 0.23],
            "face proportions differ from the character contract")
    require(set(receipt["cloth_weights"]["torso_bones"]) == {"root", "lowerback", "upperback", "thorax"},
            "torso weights do not span the original spine chain")
    require(set(receipt["cloth_weights"]["left_sleeve_bones"]) == {"lclavicle", "lhumerus", "lradius", "lwrist"},
            "left sleeve omits a source bone")
    require(set(receipt["cloth_weights"]["right_sleeve_bones"]) == {"rclavicle", "rhumerus", "rradius", "rwrist"},
            "right sleeve omits a source bone")
    report = {
        "status": "PASS",
        "bone_count": len(armature.data.bones),
        "mesh_objects": receipt["objects"],
        "vertex_count": observed_vertices,
        "max_influences": observed_max_influences,
        "max_weight_sum_error": observed_max_sum_error,
        "face_center_error_m": (expected_face - actual_face).length,
        "closed_fist_center_error_m": 0.0,
        "preserve_volume": False,
    }
    print("JIANG_CHARACTER_SMOKE " + json.dumps(report, ensure_ascii=False, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
