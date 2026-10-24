#!/usr/bin/env python3
"""Verify a refined Jiang turn in the already-open saved Blender project.

Example::

    blender --disable-autoexec --background /abs/path/jiang-turn-refined.blend --python /abs/path/verify_refined_turn.py -- --report /abs/path/new-check.json --refinement-report /abs/path/refinement-report.json

This verifier does not reset, save, or render. It restores the scene's current
frame after evaluating the 60-frame turn. The report path must be new; the
refinement report must already exist. A passing automated report is not a
substitute for root's independent visual review.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import sys
import traceback
from pathlib import Path
from typing import Any


SUPPORT_BALL_REST = (-0.19, -0.22, 0.006)
FACE_Y_MAX = 0.05
FACE_Z_MIN = 1.7
BOOT_Z_MAX = 0.20
SUPPORT_BOOT_MIN_Z = -0.008
WEIGHT_SUM_TOLERANCE = 0.001
FACE_WEIGHT_TOLERANCE = 0.001
SWORD_LENGTH_RANGE = (0.70, 1.20)
TORSO_LEAD_RANGE_DEGREES = (6.0, 10.0)
FOLLOW_ACTIVE_DEGREES = 0.25
FOLLOW_SETTLE_DEGREES = 0.50
FINAL_TURN_DEGREES = 115.0
FINAL_TURN_TOLERANCE_DEGREES = 1.0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--report", required=True, type=Path,
                        help="absolute path for a new JSON verification report")
    parser.add_argument("--refinement-report", required=True, type=Path,
                        help="absolute path to the existing refinement-report.json")
    return parser


def script_args(argv: list[str]) -> list[str]:
    if "--" in argv:
        return argv[argv.index("--") + 1 :]
    return argv[1:]


def load_base_helpers() -> Any:
    """Load shared read-only hash and Blender inspection helpers."""
    source = Path(__file__).with_name("verify_fullbody_turn.py")
    if not source.is_file():
        raise FileNotFoundError(f"Shared verifier helpers are missing: {source}")
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("jiang_fullbody_verifier_helpers", source)
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load shared verifier helpers from {source}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_refinement_report(path: Path) -> tuple[dict[str, Any], str]:
    if not path.is_absolute():
        raise ValueError("--refinement-report must be an absolute path")
    resolved = path.expanduser().resolve(strict=True)
    if not resolved.is_file() or resolved.suffix.lower() != ".json":
        raise ValueError("--refinement-report must name an existing JSON file")
    data = json.loads(resolved.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("refinement report must contain a JSON object")
    return data, resolved.as_posix()


def vertex_weight_matrix(obj: Any, np: Any) -> tuple[list[str], Any, dict[str, Any]]:
    groups = list(obj.vertex_groups)
    names_by_index = {int(group.index): group.name for group in groups}
    column_count = max(names_by_index, default=-1) + 1
    weights = np.zeros((len(obj.data.vertices), column_count), dtype=np.float64)
    unknown_memberships = 0
    for vertex in obj.data.vertices:
        for assignment in vertex.groups:
            group_index = int(assignment.group)
            if group_index not in names_by_index:
                unknown_memberships += 1
                continue
            weights[vertex.index, group_index] = float(assignment.weight)
    ordered_names = [names_by_index[index] for index in sorted(names_by_index)]
    details = {
        "unknown_memberships": unknown_memberships,
        "group_indices": {name: index for index, name in names_by_index.items()},
    }
    return ordered_names, weights, details


def weight_sum_record(obj: Any, np: Any, tolerance: float) -> tuple[dict[str, Any], Any, dict[str, int]]:
    names, weights, details = vertex_weight_matrix(obj, np)
    finite = bool(np.isfinite(weights).all())
    nonnegative = bool((weights >= -1.0e-8).all())
    sums = weights.sum(axis=1) if len(weights) else np.asarray([], dtype=np.float64)
    max_sum_error = float(np.max(np.abs(sums - 1.0))) if len(sums) else math.inf
    bad = np.flatnonzero((np.abs(sums - 1.0) > tolerance) | ~np.isfinite(sums))
    group_index = {name: int(index) for name, index in details["group_indices"].items()}
    active_counts = {
        name: int(np.count_nonzero(weights[:, group_index[name]] > 1.0e-6))
        for name in names
    }
    record = {
        "group_names": names,
        "vertices": len(obj.data.vertices),
        "finite": finite,
        "nonnegative": nonnegative,
        "max_weight_sum_error": max_sum_error if math.isfinite(max_sum_error) else None,
        "bad_sum_vertex_count": int(len(bad)),
        "bad_sum_examples": [int(index) for index in bad[:12]],
        "unknown_memberships": details["unknown_memberships"],
        "active_vertex_counts": active_counts,
        "pass": (
            len(obj.data.vertices) > 0
            and finite
            and nonnegative
            and len(bad) == 0
            and details["unknown_memberships"] == 0
        ),
    }
    return record, weights, group_index


def selected_group_record(
    group_names: list[str],
    weights: Any,
    group_index: dict[str, int],
    selected: Any,
    expected_name: str,
    tolerance: float,
    np: Any,
) -> dict[str, Any]:
    selected_ids = [int(index) for index in selected]
    if expected_name not in group_index:
        return {
            "group": expected_name,
            "selected_vertices": len(selected_ids),
            "pass": False,
            "reason": "Expected vertex group is missing.",
        }
    if not selected_ids:
        return {
            "group": expected_name,
            "selected_vertices": 0,
            "pass": False,
            "reason": "No vertices matched the rest-space selection.",
        }
    values = weights[selected_ids]
    expected_column = group_index[expected_name]
    target = values[:, expected_column]
    other = np_sum_excluding(values, expected_column)
    finite = np.isfinite(target) & np.isfinite(other)
    error = np.abs(target - 1.0)
    failures = int(np.count_nonzero(~finite | (error > tolerance) | (other > tolerance)))
    return {
        "group": expected_name,
        "selected_vertices": len(selected_ids),
        "finite": bool(finite.all()),
        "weight_min": float(target.min()) if finite.all() else None,
        "weight_max": float(target.max()) if finite.all() else None,
        "maximum_other_group_weight_sum": float(other.max()) if finite.all() else None,
        "bad_vertex_count": failures,
        "sample_vertex_indices": selected_ids[:12],
        "pass": failures == 0,
    }


def np_sum_excluding(values: Any, column: int) -> Any:
    # Small helper kept NumPy-agnostic at call sites; values is a 2-D ndarray.
    if values.shape[1] <= 1:
        return values[:, 0] * 0.0
    return values.sum(axis=1) - values[:, column]


def farthest_face_pair(face_ids: Any, coordinates: Any, np: Any) -> tuple[int, int] | None:
    if len(face_ids) < 2:
        return None
    first = int(face_ids[0])
    distances = np.linalg.norm(coordinates[face_ids] - coordinates[first], axis=1)
    second = int(face_ids[int(np.argmax(distances))])
    distances = np.linalg.norm(coordinates[face_ids] - coordinates[second], axis=1)
    third = int(face_ids[int(np.argmax(distances))])
    if second == third:
        alternatives = [int(index) for index in face_ids if int(index) != second]
        if not alternatives:
            return None
        third = alternatives[0]
    return second, third


def quat_components(quaternion: Any) -> list[float]:
    return [float(quaternion.w), float(quaternion.x), float(quaternion.y), float(quaternion.z)]


def twist_yaw_degrees(quaternion: Any) -> float:
    """Extract the quaternion twist about armature-space Z, wrapped to +/-180 degrees."""
    norm = math.hypot(float(quaternion.w), float(quaternion.z))
    if norm < 1.0e-12:
        return 0.0
    angle = math.degrees(2.0 * math.atan2(float(quaternion.z) / norm,
                                         float(quaternion.w) / norm))
    return (angle + 180.0) % 360.0 - 180.0


def quaternion_angle_degrees(quaternion: Any) -> float:
    """Return the shortest full 3-D rotation angle represented by a quaternion."""
    components = quat_components(quaternion)
    norm = math.sqrt(sum(component * component for component in components))
    if norm < 1.0e-12:
        return 0.0
    cosine = min(1.0, max(-1.0, abs(components[0] / norm)))
    return math.degrees(2.0 * math.acos(cosine))


def rotation_delta(pose_bones: Any, rest_bones: Any, bone_name: str,
                   parent_name: str | None = None) -> Any:
    bone_delta = (
        pose_bones[bone_name].matrix
        @ rest_bones[bone_name].matrix_local.inverted()
    ).to_quaternion()
    if parent_name is None:
        return bone_delta
    parent_delta = (
        pose_bones[parent_name].matrix
        @ rest_bones[parent_name].matrix_local.inverted()
    ).to_quaternion()
    return parent_delta.inverted() @ bone_delta


def summarize_motion(series: dict[str, list[float]], np: Any) -> dict[str, Any]:
    output: dict[str, Any] = {}
    for name, values in series.items():
        if not values:
            output[name] = {"samples": 0, "pass": False}
            continue
        peak_idx = int(np.argmax(np.abs(values)))
        output[name] = {
            "samples": len(values),
            "frame_1_degrees": float(values[0]),
            "peak_abs_degrees": float(abs(values[peak_idx])),
            "peak_signed_degrees": float(values[peak_idx]),
            "peak_frame": peak_idx + 1,
            "frame_60_degrees": float(values[-1]),
        }
    return output


def verify_refined_project(
    bpy: Any,
    np: Any,
    helpers: Any,
    report_path: Path,
    refinement_path: Path,
    refinement_data: dict[str, Any],
) -> dict[str, Any]:
    report: dict[str, Any] = {
        "status": "FAIL",
        "report_path": str(report_path),
        "refinement_report": {},
        "source": {},
        "checks": {},
        "errors": [],
        "textures": [],
        "meshes": {},
        "weights": {},
        "animation": {},
        "camera_review": {},
    }

    blend_raw = bpy.data.filepath
    blend_path = Path(blend_raw).expanduser() if blend_raw else None
    blend_exists = bool(blend_path and blend_path.is_absolute()
                        and blend_path.suffix.lower() == ".blend" and blend_path.is_file())
    blend_hash = helpers.sha256_file(blend_path) if blend_exists else None
    report["source"].update({
        "saved_blend_path": str(blend_path) if blend_path else None,
        "saved_blend_bytes": blend_path.stat().st_size if blend_exists else None,
        "saved_blend_sha256": blend_hash,
        "refinement_report_path": str(refinement_path),
        "refinement_report_sha256": helpers.sha256_file(refinement_path),
    })
    helpers.record_check(report, "saved_blend_exists", blend_exists, report["source"],
                         "The currently open project must be an existing saved .blend file.")

    refinement_frames = refinement_data.get("frames", [])
    refinement_indices = [frame.get("frame") for frame in refinement_frames
                          if isinstance(frame, dict)]
    refinement_report_ok = (
        refinement_data.get("status") == "BUILT_AWAITING_VISUAL_REVIEW"
        and len(refinement_frames) == 60
        and refinement_indices == list(range(1, 61))
        and refinement_data.get("camera_unchanged") is True
        and refinement_data.get("source_texture_pixels_modified") is False
        and isinstance(refinement_data.get("source_sha256"), str)
        and len(refinement_data.get("source_sha256", "")) == 64
    )
    report["refinement_report"] = {
        "status": refinement_data.get("status"),
        "source_blend": refinement_data.get("source_blend"),
        "source_sha256": refinement_data.get("source_sha256"),
        "camera_unchanged": refinement_data.get("camera_unchanged"),
        "source_texture_pixels_modified": refinement_data.get("source_texture_pixels_modified"),
        "reported_frame_count": len(refinement_frames),
        "reported_weight_metrics": refinement_data.get("weights"),
        "automated_visual_status": "awaiting separate visual review",
    }
    helpers.record_check(
        report, "refinement_report_matches_60_frame_candidate", refinement_report_ok,
        report["refinement_report"],
        "The refinement report must describe a built 60-frame candidate with unchanged camera/source texture pixels and a source hash.",
    )

    scene = bpy.context.scene
    if scene is None:
        helpers.record_check(report, "scene_available", False, None, "No active Blender scene is available.")
        return report
    scene_metadata = {
        "name": scene.name,
        "frame_start": int(scene.frame_start),
        "frame_end": int(scene.frame_end),
        "fps": int(scene.render.fps),
        "fps_base": float(scene.render.fps_base),
        "resolution": [
            int(scene.render.resolution_x * scene.render.resolution_percentage / 100),
            int(scene.render.resolution_y * scene.render.resolution_percentage / 100),
        ],
    }
    report["scene"] = scene_metadata
    timing_ok = (
        scene.frame_start == 1 and scene.frame_end == 60
        and scene.render.fps == 30 and abs(float(scene.render.fps_base) - 1.0) < 1.0e-8
    )
    helpers.record_check(report, "scene_30fps_frames_1_to_60", timing_ok, scene_metadata,
                         "The candidate scene must use 30 fps and frames 1 through 60.")

    scene_objects = list(scene.objects)
    meshes_in_scene = [obj for obj in scene_objects if obj.type == "MESH"]
    mesh_names = sorted(obj.name for obj in meshes_in_scene)
    global_mesh_names = sorted(obj.name for obj in bpy.data.objects if obj.type == "MESH")
    expected_meshes = set(helpers.EXPECTED_MESHES)
    exact_meshes = (
        len(mesh_names) == 4 and set(mesh_names) == expected_meshes
        and set(global_mesh_names) == expected_meshes
    )
    helpers.record_check(
        report, "four_expected_meshes", exact_meshes,
        {"expected": sorted(expected_meshes), "scene_meshes": mesh_names,
         "all_project_meshes": global_mesh_names},
        "Candidate must contain only the four expected Jiang mesh objects.",
    )
    meshes = {
        name: bpy.data.objects[name]
        for name in helpers.EXPECTED_MESHES
        if bpy.data.objects.get(name) is not None
        and bpy.data.objects[name].type == "MESH"
        and bpy.data.objects[name] in scene_objects
    }
    helpers.record_check(
        report, "expected_meshes_available", len(meshes) == 4,
        {"available": sorted(meshes), "missing": sorted(expected_meshes - set(meshes))},
        "One or more required mesh objects are missing from the active scene.",
    )

    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    armature_data = list(bpy.data.armatures)
    rig = bpy.data.objects.get(helpers.RIG_NAME)
    rig_ok = (
        len(armatures) == 1 and len(armature_data) == 1
        and rig is not None and rig.type == "ARMATURE" and rig in scene_objects
        and len(rig.data.bones) == 22
    )
    rig_evidence = {
        "objects": [obj.name for obj in armatures],
        "datablocks": [data.name for data in armature_data],
        "name": rig.name if rig is not None else None,
        "bones": len(rig.data.bones) if rig is not None and rig.type == "ARMATURE" else None,
        "bone_names": sorted(bone.name for bone in rig.data.bones)
        if rig is not None and rig.type == "ARMATURE" else [],
    }
    helpers.record_check(report, "single_22_bone_jiang_rig", rig_ok, rig_evidence,
                         "Expected one JiangRig object and armature datablock with 22 bones.")

    font_objects = [obj.name for obj in bpy.data.objects if obj.type == "FONT"]
    font_curves = [curve.name for curve in bpy.data.curves if curve.type == "FONT"]
    helpers.record_check(report, "no_text_objects", not font_objects and not font_curves,
                         {"font_objects": font_objects, "font_curves": font_curves},
                         "Candidate contains unexpected Text/Font objects.")
    drivers = helpers.find_drivers(bpy)
    helpers.record_check(report, "no_drivers", not drivers,
                         {"count": len(drivers), "items": drivers},
                         "Candidate contains unexpected driver F-curves.")

    images = [image for image in bpy.data.images
              if image.type != "RENDER_RESULT" and image.name != "Render Result"]
    textures: list[dict[str, Any]] = []
    texture_errors: list[str] = []
    for image in images:
        try:
            textures.append(helpers.texture_record(image))
        except Exception as exc:
            texture_errors.append(f"{image.name}: {type(exc).__name__}: {exc}")
    report["textures"] = textures
    texture_ok = (
        len(images) == 6 and len(textures) == len(images)
        and all(tuple(texture["size"]) == (4096, 4096) and texture["packed"]
                and texture["packed_sha256"] for texture in textures)
        and not texture_errors
    )
    helpers.record_check(
        report, "six_packed_4096_textures", texture_ok,
        {"expected_count": 6, "actual_count": len(images), "texture_hash_errors": texture_errors,
         "textures": textures},
        "Candidate must contain exactly six packed 4096x4096 textures with readable packed bytes.",
    )

    rest_coords: dict[str, Any] = {}
    weight_arrays: dict[str, Any] = {}
    weight_indices: dict[str, dict[str, int]] = {}
    all_weights_ok = True
    geometry_ok = True
    for name, obj in meshes.items():
        try:
            geometry, coords = helpers.rest_geometry_record(obj.data, np)
            report["meshes"][name] = {
                "data_name": obj.data.name,
                "rest_geometry": geometry,
                "vertex_groups": [group.name for group in obj.vertex_groups],
                "rest_uv_layers": [layer.name for layer in obj.data.uv_layers],
            }
            rest_coords[name] = coords
            geometry_ok = geometry_ok and geometry["coordinates_finite"]
            weights, matrix, group_index = weight_sum_record(obj, np, WEIGHT_SUM_TOLERANCE)
            report["weights"][name] = weights
            weight_arrays[name] = matrix
            weight_indices[name] = group_index
            all_weights_ok = all_weights_ok and weights["pass"]
        except Exception as exc:
            report.setdefault("errors", []).append(
                f"Could not inspect {name}: {type(exc).__name__}: {exc}"
            )
            geometry_ok = False
            all_weights_ok = False
    geometry_hashes = {
        name: info.get("rest_geometry", {}).get("rest_geometry_sha256")
        for name, info in report["meshes"].items()
    }
    report["source"]["rest_geometry_sha256_by_mesh"] = geometry_hashes
    helpers.record_check(
        report, "rest_geometry_finite_and_hashed",
        len(rest_coords) == 4 and geometry_ok,
        geometry_hashes,
        "All four mesh rest geometries must be finite and hashed.",
    )
    helpers.record_check(
        report, "all_vertex_weights_finite_and_normalized",
        len(weight_arrays) == 4 and all_weights_ok,
        report["weights"],
        "Every mesh vertex must have finite nonnegative weights summing to 1 within 0.001.",
    )

    grip_weight_results: dict[str, Any] = {}
    if rig is not None and rig.type == "ARMATURE":
        for name in ("JiangRightGrip_HandGrip", "JiangRightGrip_Jian"):
            if name in meshes:
                grip_weight_results[name] = helpers.weight_record(meshes[name], rig, 1.0e-6)
    grip_weights_ok = (
        set(grip_weight_results) == {"JiangRightGrip_HandGrip", "JiangRightGrip_Jian"}
        and all(item["pass"] for item in grip_weight_results.values())
    )
    helpers.record_check(
        report, "rigid_hand_and_sword_hand_R", grip_weights_ok, grip_weight_results,
        "Hand and sword must each use only hand.R at weight 1 with one modifier targeting JiangRig.",
    )

    body_name = "JiangFullbody"
    head_name = "JiangApprovedHead"
    body_data = rest_coords.get(body_name)
    head_data = rest_coords.get(head_name)
    body_weights = weight_arrays.get(body_name)
    head_weights = weight_arrays.get(head_name)
    body_indices = weight_indices.get(body_name, {})
    head_indices = weight_indices.get(head_name, {})

    face_ids = np.asarray([], dtype=np.int64)
    face_pair: tuple[int, int] | None = None
    if head_data is not None and head_weights is not None:
        face_ids = np.flatnonzero((head_data[:, 1] < FACE_Y_MAX) & (head_data[:, 2] > FACE_Z_MIN))
        face_pair = farthest_face_pair(face_ids, head_data, np)
    if face_pair is not None and head_weights is not None:
        face_weight = selected_group_record(
            [group.name for group in meshes[head_name].vertex_groups], head_weights,
            head_indices, face_ids, "head", FACE_WEIGHT_TOLERANCE, np,
        )
        face_weight["selection"] = f"rest y < {FACE_Y_MAX} m and z > {FACE_Z_MIN} m; excludes lower neck bridge"
        face_weight["invariant_pair_vertices"] = list(face_pair)
        face_weight["invariant_pair_rest_coordinates"] = [
            [float(x) for x in head_data[index]] for index in face_pair
        ]
    else:
        face_weight = {"selected_vertices": int(len(face_ids)), "pass": False,
                       "reason": "Could not select two face vertices outside the neck bridge."}
    report["weights"]["face_rigid_subset"] = face_weight
    helpers.record_check(
        report, "front_face_vertices_rigid_to_head", face_weight.get("pass", False),
        face_weight,
        "Every rest-space face vertex must be weight 1 to head; two suitable vertices are required for its invariant.",
    )

    pony_result: dict[str, Any]
    if head_weights is not None and "ponytail" in head_indices and head_data is not None:
        pony_w = head_weights[:, head_indices["ponytail"]]
        rear_mask = (head_data[:, 1] > 0.12) & (head_data[:, 2] > 1.35)
        active = (pony_w > 0.001) & rear_mask
        head_w = head_weights[:, head_indices["head"]] if "head" in head_indices else np.zeros_like(pony_w)
        blended = active & (head_w > 0.001)
        pony_result = {
            "ponytail_group_active_vertices": int(np.count_nonzero(pony_w > 0.001)),
            "rear_hair_vertices_with_ponytail_weight": int(np.count_nonzero(active)),
            "rear_hair_vertices_weighted_to_both_head_and_ponytail": int(np.count_nonzero(blended)),
            "maximum_ponytail_weight": float(pony_w.max()) if len(pony_w) else 0.0,
            "maximum_head_weight_on_active_rear_hair": float(
                head_w[active].max()
            ) if np.any(active) else None,
            "pass": bool(np.any(active) and np.any(blended)),
        }
    else:
        pony_result = {"pass": False, "reason": "Head/ponytail groups or geometry missing."}
    report["weights"]["rear_ponytail"] = pony_result
    helpers.record_check(report, "rear_ponytail_weighted", pony_result["pass"], pony_result,
                         "Ponytail group must have active weights on rear upper-hair vertices.")

    skirt_names = ("skirt.front.R", "skirt.front.L", "skirt.back.R", "skirt.back.L")
    skirt_activation: dict[str, Any] = {}
    if body_weights is not None:
        for name in skirt_names:
            if name in body_indices:
                values = body_weights[:, body_indices[name]]
                skirt_activation[name] = {
                    "active_vertices": int(np.count_nonzero(values > 0.001)),
                    "maximum_weight": float(values.max()) if len(values) else 0.0,
                    "pass": bool(np.any(values > 0.001)),
                }
            else:
                skirt_activation[name] = {"active_vertices": 0, "maximum_weight": 0.0, "pass": False}
    skirt_groups_ok = all(item["pass"] for item in skirt_activation.values()) and len(skirt_activation) == 4
    report["weights"]["skirt_panels"] = skirt_activation
    helpers.record_check(report, "four_skirt_panel_groups_active", skirt_groups_ok,
                         skirt_activation, "All four skirt panel groups must exist and carry nonzero weights.")

    boot_selections: dict[str, Any] = {}
    support_boot_ids: Any = np.asarray([], dtype=np.int64)
    if body_data is not None and body_weights is not None:
        for side, foot_group, side_mask in (
            ("R", "foot.R", body_data[:, 0] < 0.0),
            ("L", "foot.L", body_data[:, 0] >= 0.0),
        ):
            selected = np.flatnonzero((body_data[:, 2] < BOOT_Z_MAX) & side_mask)
            result = selected_group_record(
                [group.name for group in meshes[body_name].vertex_groups], body_weights,
                body_indices, selected, foot_group, WEIGHT_SUM_TOLERANCE, np,
            )
            result["rest_selection"] = f"z < {BOOT_Z_MAX} m and {side} side of body centerline"
            boot_selections[side] = result
        if "foot.R" in body_indices:
            support_boot_ids = np.flatnonzero(
                (body_data[:, 2] < BOOT_Z_MAX)
                & (body_data[:, 0] < 0.0)
                & (body_weights[:, body_indices["foot.R"]] >= 1.0 - WEIGHT_SUM_TOLERANCE)
            )
    boot_weights_ok = len(boot_selections) == 2 and all(item["pass"] for item in boot_selections.values())
    report["weights"]["sole_boots"] = boot_selections
    report["weights"]["support_boot_vertex_count"] = int(len(support_boot_ids))
    helpers.record_check(report, "sole_vertices_rigid_to_each_foot", boot_weights_ok,
                         {"sides": boot_selections, "support_boot_vertex_count": int(len(support_boot_ids))},
                         "Every body vertex with rest z below 0.2 m must be fully weighted to its side's foot group.")

    sword_data = rest_coords.get("JiangRightGrip_Jian")
    sword_dimensions: dict[str, Any] = {"pass": False, "reason": "Sword rest geometry unavailable."}
    sword_tip_index: int | None = None
    if sword_data is not None and len(sword_data) > 1 and np.isfinite(sword_data).all():
        minimum = sword_data.min(axis=0)
        maximum = sword_data.max(axis=0)
        extents = maximum - minimum
        diagonal = float(np.linalg.norm(extents))
        centered = sword_data - sword_data.mean(axis=0)
        covariance = np.einsum("ki,kj->ij", centered, centered, optimize=False) / max(1, len(centered))
        eigenvalues, eigenvectors = np.linalg.eigh(covariance)
        long_axis = eigenvectors[:, int(np.argmax(eigenvalues))]
        projections = np.einsum("ij,j->i", centered, long_axis, optimize=False)
        principal_length = float(projections.max() - projections.min())
        sword_tip_index = int(np.argmax(sword_data[:, 2]))
        dimensions_ok = (
            min(SWORD_LENGTH_RANGE) <= principal_length <= max(SWORD_LENGTH_RANGE)
            and float(extents.max()) > 0.50
            and bool((extents > 1.0e-5).all())
        )
        sword_dimensions = {
            "rest_local_bounds_min": [float(value) for value in minimum],
            "rest_local_bounds_max": [float(value) for value in maximum],
            "rest_local_aabb_dimensions_m": [float(value) for value in extents],
            "aabb_diagonal_m": diagonal,
            "principal_axis": [float(value) for value in long_axis],
            "principal_axis_length_m": principal_length,
            "maximum_rest_z_blade_tip_vertex_index": sword_tip_index,
            "blade_tip_vertex_rest_local": [float(value) for value in sword_data[sword_tip_index]],
            "expected_principal_length_range_m": list(SWORD_LENGTH_RANGE),
            "pass": dimensions_ok,
        }
    report["meshes"].setdefault("JiangRightGrip_Jian", {})["sword_dimensions"] = sword_dimensions
    helpers.record_check(report, "sword_dimensions_non_degenerate", sword_dimensions["pass"],
                         sword_dimensions,
                         "Sword principal length must be 0.70-1.20 m with finite noncollapsed bounds.")

    camera = scene.camera
    camera_ok = camera is not None and camera.type == "CAMERA" and camera.data.type == "ORTHO"
    if camera_ok:
        resolution = scene_metadata["resolution"]
        frame = camera.data.view_frame(scene=scene)
        xy = np.asarray([[float(v.x), float(v.y)] for v in frame], dtype=np.float64)
        camera_bounds = {
            "min_x": float(xy[:, 0].min()), "max_x": float(xy[:, 0].max()),
            "min_y": float(xy[:, 1].min()), "max_y": float(xy[:, 1].max()),
        }
        camera_info = {
            "name": camera.name, "type": camera.data.type,
            "ortho_scale": float(camera.data.ortho_scale), "resolution": resolution,
            "frame_bounds_camera_local": camera_bounds,
            "clip_start": float(camera.data.clip_start), "clip_end": float(camera.data.clip_end),
        }
    else:
        resolution = [0, 0]
        camera_bounds = None
        camera_info = {"name": camera.name if camera else None,
                       "type": camera.data.type if camera else None}
    report["camera_review"]["camera"] = camera_info
    helpers.record_check(report, "orthographic_camera_available", camera_ok, camera_info,
                         "An orthographic camera is required for all-frame margin checks.")

    required = (
        rig is not None and rig.type == "ARMATURE" and camera_ok
        and all(name in meshes and name in rest_coords for name in helpers.EXPECTED_MESHES)
        and body_weights is not None and head_weights is not None and face_pair is not None
        and sword_tip_index is not None and len(support_boot_ids) > 0
    )
    if not required:
        helpers.record_check(report, "all_60_frame_evaluation", False,
                             {"evaluated_frames": 0},
                             "Frame evaluation skipped because required meshes, rig, camera, or selected vertices are missing.")
        report["status"] = "FAIL"
        report["summary"] = {"checks_failed": sum(c["status"] == "FAIL" for c in report["checks"].values()),
                             "error_count": len(report["errors"]),
                             "visual_review": "not performed by this automated verifier"}
        return report

    rest_bones = rig.data.bones
    required_pose_bones = ("pelvis", "chest", "head", "ponytail", "skirt.front.R",
                           "skirt.front.L", "skirt.back.R", "skirt.back.L", "foot.R", "foot.L")
    pose_bone_presence = {name: name in rig.pose.bones for name in required_pose_bones}
    helpers.record_check(report, "required_secondary_pose_bones", all(pose_bone_presence.values()),
                         pose_bone_presence, "One or more required torso, head, skirt, hair, or foot bones are missing.")

    original_frame = int(scene.frame_current)
    original_subframe = float(scene.frame_subframe)
    frame_records: list[dict[str, Any]] = []
    invariant_values: list[float] = []
    sword_length_values: list[float] = []
    face_pair_values: list[float] = []
    support_reference_values: list[list[float]] = []
    left_foot_heads: list[list[float]] = []
    boot_minima: list[dict[str, Any]] = []
    body_min_z: list[float] = []
    camera_frame_metrics: list[dict[str, Any]] = []
    relative_angle_series: dict[str, list[float]] = {
        "pelvis_absolute": [], "chest_relative_to_pelvis": [],
        "head_relative_to_chest": [], "ponytail_relative_to_head": [],
        "skirt_front_R_relative_to_pelvis": [],
        "skirt_front_L_relative_to_pelvis": [],
        "skirt_back_R_relative_to_pelvis": [],
        "skirt_back_L_relative_to_pelvis": [],
    }
    relative_yaw_series: dict[str, list[float]] = {
        name: [] for name in relative_angle_series
    }
    absolute_series: dict[str, list[float]] = {
        name: [] for name in ("pelvis", "chest", "head", "ponytail",
                              "skirt.front.R", "skirt.front.L", "skirt.back.R", "skirt.back.L")
    }
    evaluated_counts: dict[str, int] = {}
    frame_error: str | None = None
    support_point = None
    from mathutils import Vector
    support_point = Vector(SUPPORT_BALL_REST)

    try:
        for frame_number in range(1, 61):
            scene.frame_set(frame_number)
            bpy.context.view_layer.update()
            depsgraph = bpy.context.evaluated_depsgraph_get()
            evaluated_meshes: dict[str, Any] = {}
            world_meshes: dict[str, Any] = {}
            all_world: list[Any] = []
            mesh_bounds: dict[str, Any] = {}
            frame_finite = True

            for name, obj in meshes.items():
                evaluated_obj = obj.evaluated_get(depsgraph)
                evaluated_mesh = evaluated_obj.to_mesh()
                try:
                    coords = helpers.mesh_coordinates(evaluated_mesh, np)
                    evaluated_counts.setdefault(name, int(len(coords)))
                    if len(coords) != len(rest_coords[name]):
                        frame_finite = False
                        report["errors"].append(f"{name} evaluated vertex count changed at frame {frame_number}.")
                    object_world = helpers.numpy_matrix(evaluated_obj.matrix_world, np)
                    points = helpers.transform_points(coords, object_world, np)
                    if not np.isfinite(points).all():
                        frame_finite = False
                        report["errors"].append(f"{name} has non-finite evaluated coordinates at frame {frame_number}.")
                        continue
                    evaluated_meshes[name] = coords
                    world_meshes[name] = points
                    all_world.append(points)
                    mesh_bounds[name] = {
                        "min": [float(value) for value in points.min(axis=0)],
                        "max": [float(value) for value in points.max(axis=0)],
                    }
                finally:
                    evaluated_obj.to_mesh_clear()

            body_points = world_meshes.get("JiangFullbody")
            if body_points is not None and len(body_points):
                body_min_z.append(float(body_points[:, 2].min()))
                if len(support_boot_ids) and int(support_boot_ids.max()) < len(body_points):
                    boot_z = body_points[support_boot_ids, 2]
                    local_idx = int(np.argmin(boot_z))
                    minimum = float(boot_z[local_idx])
                    boot_minima.append({
                        "frame": frame_number,
                        "min_world_z_m": minimum,
                        "worst_vertex_index": int(support_boot_ids[local_idx]),
                        "pass": minimum >= SUPPORT_BOOT_MIN_Z,
                    })
                else:
                    boot_minima.append({"frame": frame_number, "min_world_z_m": None, "pass": False})

            if all(name in world_meshes for name in helpers.EXPECTED_MESHES):
                hand_points = world_meshes["JiangRightGrip_HandGrip"]
                sword_points = world_meshes["JiangRightGrip_Jian"]
                head_points = world_meshes[head_name]
                if len(hand_points) and len(sword_points) > sword_tip_index:
                    invariant_values.append(float(np.linalg.norm(hand_points[0] - sword_points[0])))
                    sword_length_values.append(float(np.linalg.norm(
                        sword_points[sword_tip_index] - sword_points[0]
                    )))
                    face_pair_values.append(float(np.linalg.norm(
                        head_points[face_pair[0]] - head_points[face_pair[1]]
                    )))
                else:
                    frame_finite = False
                    report["errors"].append(f"Selected grip or face vertices unavailable at frame {frame_number}.")

            evaluated_rig = rig.evaluated_get(depsgraph)
            pose_bones = evaluated_rig.pose.bones
            support_bone = pose_bones.get("foot.R")
            left_bone = pose_bones.get("foot.L")
            if support_bone is not None:
                rest_matrix = rest_bones["foot.R"].matrix_local
                support_armature_point = support_bone.matrix @ rest_matrix.inverted() @ support_point
                support_world_point = evaluated_rig.matrix_world @ support_armature_point
                support_reference_values.append([float(x) for x in support_world_point])
            else:
                frame_finite = False
                report["errors"].append(f"foot.R pose bone missing at frame {frame_number}.")
            if left_bone is not None:
                left_world_head = evaluated_rig.matrix_world @ left_bone.head
                left_foot_heads.append([float(x) for x in left_world_head])
            else:
                frame_finite = False
                report["errors"].append(f"foot.L pose bone missing at frame {frame_number}.")

            pose_rotations: dict[str, Any] = {}
            relation_specs = {
                "pelvis_absolute": ("pelvis", None),
                "chest_relative_to_pelvis": ("chest", "pelvis"),
                "head_relative_to_chest": ("head", "chest"),
                "ponytail_relative_to_head": ("ponytail", "head"),
                "skirt_front_R_relative_to_pelvis": ("skirt.front.R", "pelvis"),
                "skirt_front_L_relative_to_pelvis": ("skirt.front.L", "pelvis"),
                "skirt_back_R_relative_to_pelvis": ("skirt.back.R", "pelvis"),
                "skirt_back_L_relative_to_pelvis": ("skirt.back.L", "pelvis"),
            }
            for label, (bone_name, parent_name) in relation_specs.items():
                if bone_name not in pose_bones or bone_name not in rest_bones:
                    frame_finite = False
                    continue
                delta = rotation_delta(pose_bones, rest_bones, bone_name, parent_name)
                components = quat_components(delta)
                if not all(math.isfinite(component) for component in components):
                    frame_finite = False
                    report["errors"].append(
                        f"{bone_name} has a non-finite rotation at frame {frame_number}."
                    )
                    continue
                angle = quaternion_angle_degrees(delta)
                yaw = twist_yaw_degrees(delta)
                relative_angle_series[label].append(angle)
                relative_yaw_series[label].append(yaw)
                pose_rotations[label] = {
                    "full_rotation_angle_degrees": angle,
                    "twist_yaw_degrees": yaw,
                    "delta_quaternion_wxyz": components,
                }
            for bone_name in absolute_series:
                if bone_name not in pose_bones or bone_name not in rest_bones:
                    continue
                delta = rotation_delta(pose_bones, rest_bones, bone_name)
                components = quat_components(delta)
                if all(math.isfinite(component) for component in components):
                    absolute_series[bone_name].append(twist_yaw_degrees(delta))
                else:
                    frame_finite = False
                    report["errors"].append(
                        f"{bone_name} has a non-finite absolute rotation at frame {frame_number}."
                    )

            camera_frame: dict[str, Any] = {"frame": frame_number, "finite": frame_finite}
            if all_world and camera_ok:
                world_points = np.concatenate(all_world, axis=0)
                evaluated_camera = camera.evaluated_get(depsgraph)
                camera_inverse = helpers.numpy_matrix(evaluated_camera.matrix_world.inverted(), np)
                camera_points = helpers.transform_points(world_points, camera_inverse, np)
                if not np.isfinite(camera_points).all():
                    camera_frame["finite"] = False
                    camera_frame["minimum_margin_px"] = None
                    camera_frame["projection_finite"] = False
                    frame_finite = False
                    report["errors"].append(
                        f"Camera projection contains non-finite coordinates at frame {frame_number}."
                    )
                    camera_frame_metrics.append(camera_frame)
                    frame_records.append({
                        "frame": frame_number,
                        "world_bounds": mesh_bounds,
                        "body_min_z_m": body_min_z[-1] if body_min_z else None,
                        "support_boot_min_z_m": boot_minima[-1].get("min_world_z_m") if boot_minima else None,
                        "support_ball_world": support_reference_values[-1] if support_reference_values else None,
                        "relative_rotations": pose_rotations,
                        "camera": camera_frame,
                    })
                    continue
                left, right = camera_bounds["min_x"], camera_bounds["max_x"]
                bottom, top = camera_bounds["min_y"], camera_bounds["max_y"]
                width, height = right - left, top - bottom
                if width <= 0 or height <= 0:
                    raise ValueError("Orthographic camera view frame is degenerate")
                horizontal = (camera_points[:, 0] - left) / width * resolution[0]
                vertical = (camera_points[:, 1] - bottom) / height * resolution[1]
                margins = {
                    "left": float(horizontal.min()),
                    "right": float((resolution[0] - horizontal).min()),
                    "bottom": float(vertical.min()),
                    "top": float((resolution[1] - vertical).min()),
                }
                depth = -camera_points[:, 2]
                clipped = (depth < camera.data.clip_start) | (depth > camera.data.clip_end)
                camera_frame.update({
                    "side_margins_px": margins,
                    "minimum_margin_px": float(min(margins.values())),
                    "depth_range_m": [float(depth.min()), float(depth.max())],
                    "clipped_or_behind_vertex_samples": int(clipped.sum()),
                    "world_vertex_count": int(len(world_points)),
                })
                camera_frame_metrics.append(camera_frame)
            else:
                camera_frame["minimum_margin_px"] = None
                camera_frame_metrics.append(camera_frame)
            frame_records.append({
                "frame": frame_number,
                "world_bounds": mesh_bounds,
                "body_min_z_m": body_min_z[-1] if body_min_z else None,
                "support_boot_min_z_m": boot_minima[-1].get("min_world_z_m") if boot_minima else None,
                "support_ball_world": support_reference_values[-1] if support_reference_values else None,
                "relative_rotations": pose_rotations,
                "camera": camera_frame,
            })

        all_frames_ok = (
            len(frame_records) == 60
            and len(body_min_z) == 60
            and len(boot_minima) == 60
            and len(support_reference_values) == 60
            and len(left_foot_heads) == 60
            and all(item["finite"] for item in camera_frame_metrics)
            and all(len(values) == 60 for values in relative_angle_series.values())
            and all(len(values) == 60 for values in relative_yaw_series.values())
        )
        helpers.record_check(report, "all_60_frame_evaluation", all_frames_ok,
                             {"evaluated_frames": len(frame_records),
                              "evaluated_vertex_counts": evaluated_counts,
                              "all_coordinates_finite": all(item["finite"] for item in camera_frame_metrics)},
                             "All 60 frames must evaluate with finite geometry, bones, and camera projections.")
    except Exception as exc:
        frame_error = f"{type(exc).__name__}: {exc}"
        report["errors"].append(f"Frame evaluation failed: {frame_error}")
    finally:
        scene.frame_set(original_frame, subframe=original_subframe)
        bpy.context.view_layer.update()

    report["animation"]["frames"] = frame_records
    report["animation"]["frame_evaluation_error"] = frame_error
    report["animation"]["evaluated_vertex_counts"] = evaluated_counts

    def distance_check(name: str, values: list[float], description: str) -> dict[str, Any]:
        if len(values) != 60:
            return {"samples": len(values), "threshold_m": 1.0e-5, "pass": False,
                    "reason": "Expected a sample for each frame."}
        drifts = [abs(value - values[0]) for value in values]
        maximum_index = int(np.argmax(drifts))
        return {
            "samples": len(values),
            "frame_1_distance_m": float(values[0]),
            "max_abs_drift_m": float(drifts[maximum_index]),
            "max_drift_frame": maximum_index + 1,
            "threshold_m": 1.0e-5,
            "meaning": description,
            "pass": float(drifts[maximum_index]) < 1.0e-5,
        }

    sword_hand_distance = distance_check(
        "hand_to_sword", invariant_values, "distance between hand vertex 0 and sword vertex 0"
    )
    sword_length_distance = distance_check(
        "sword_vertex_0_to_max_rest_z_tip", sword_length_values,
        "distance between sword vertex 0 and the rest-space maximum-Z blade-tip vertex",
    )
    face_pair_distance = distance_check(
        "front_face_pair", face_pair_values,
        "distance between two head-weighted face vertices selected from rest y<0.05,z>1.7",
    )
    report["animation"]["distance_invariants"] = {
        "hand_vertex_0_to_sword_vertex_0": sword_hand_distance,
        "sword_length_rigid": sword_length_distance,
        "front_face_rigid_pair": face_pair_distance,
    }
    helpers.record_check(
        report, "hand_sword_and_face_distance_invariants",
        sword_hand_distance["pass"] and sword_length_distance["pass"] and face_pair_distance["pass"],
        report["animation"]["distance_invariants"],
        "Hand/sword grip, sword length, and selected rigid face-pair distances must drift less than 1e-5 m.",
    )

    if len(support_reference_values) == 60:
        support_array = np.asarray(support_reference_values, dtype=np.float64)
        support_drift = np.linalg.norm(support_array - support_array[0], axis=1)
        support_max_idx = int(np.argmax(support_drift))
        support_result = {
            "rest_reference_armature_point": list(SUPPORT_BALL_REST),
            "formula": "pose_bone.matrix @ rest_bone.matrix_local.inverted() @ rest_reference",
            "frame_1_world": [float(value) for value in support_array[0]],
            "maximum_world_drift_m": float(support_drift[support_max_idx]),
            "maximum_drift_frame": support_max_idx + 1,
            "threshold_m": 1.0e-5,
            "pass": float(support_drift[support_max_idx]) < 1.0e-5,
        }
    else:
        support_result = {"samples": len(support_reference_values), "threshold_m": 1.0e-5,
                          "pass": False}
    report["animation"]["right_foot_ball_reference"] = support_result
    helpers.record_check(report, "right_foot_ball_reference_fixed", support_result["pass"],
                         support_result,
                         "The right support-foot ball reference must drift less than 1e-5 m; ankle motion is allowed.")

    if len(left_foot_heads) == 60:
        left_array = np.asarray(left_foot_heads, dtype=np.float64)
        lift = left_array[:, 2] - left_array[0, 2]
        lift_idx = int(np.argmax(lift))
        left_result = {
            "frame_1_world_head": [float(value) for value in left_array[0]],
            "maximum_upward_head_lift_m": float(max(0.0, lift[lift_idx])),
            "maximum_lift_frame": lift_idx + 1,
            "required_lift_m": 0.04,
            "pass": float(lift[lift_idx]) > 0.04,
        }
    else:
        left_result = {"samples": len(left_foot_heads), "required_lift_m": 0.04,
                       "pass": False}
    report["animation"]["left_step_foot"] = left_result
    helpers.record_check(report, "left_foot_head_lifts", left_result["pass"], left_result,
                         "The left foot pose-head must lift more than 0.04 m above frame 1.")

    boot_pass = len(boot_minima) == 60 and all(
        item.get("min_world_z_m") is not None and item["min_world_z_m"] >= SUPPORT_BOOT_MIN_Z
        for item in boot_minima
    )
    worst_boot = min(
        (item for item in boot_minima if item.get("min_world_z_m") is not None),
        key=lambda item: item["min_world_z_m"], default=None,
    )
    report["animation"]["support_boot_min_z"] = {
        "threshold_m": SUPPORT_BOOT_MIN_Z,
        "per_frame": boot_minima,
        "worst": worst_boot,
        "pass": boot_pass,
        "semantics": "minimum world Z among JiangFullbody vertices below rest z 0.2 m weighted fully to foot.R",
    }
    helpers.record_check(report, "support_boot_stays_above_floor_tolerance", boot_pass,
                         {"threshold_m": SUPPORT_BOOT_MIN_Z, "worst": worst_boot,
                          "samples": len(boot_minima)},
                         "Right support-boot minimum world Z must remain at or above -0.008 m in every frame.")

    if body_min_z:
        report["animation"]["body_min_z_range"] = {
            "minimum_of_frame_min_z_m": float(min(body_min_z)),
            "maximum_of_frame_min_z_m": float(max(body_min_z)),
            "frame_1_min_z_m": float(body_min_z[0]),
            "per_frame": body_min_z,
            "semantics": "body mesh bounds only; not treated as an exact ground-contact assertion",
        }

    motion_summary = summarize_motion(relative_angle_series, np)
    relative_yaw_summary = summarize_motion(relative_yaw_series, np)
    absolute_summary = summarize_motion(absolute_series, np)
    lead_values = [chest - pelvis for chest, pelvis in zip(absolute_series["chest"], absolute_series["pelvis"])]
    if lead_values:
        lead_index = int(np.argmax(lead_values))
        lead_result = {
            "maximum_torso_over_pelvis_yaw_lead_degrees": float(lead_values[lead_index]),
            "peak_frame": lead_index + 1,
            "expected_range_degrees": list(TORSO_LEAD_RANGE_DEGREES),
            "pass": TORSO_LEAD_RANGE_DEGREES[0] <= lead_values[lead_index] <= TORSO_LEAD_RANGE_DEGREES[1],
            "per_frame_degrees": lead_values,
        }
    else:
        lead_result = {"samples": 0, "expected_range_degrees": list(TORSO_LEAD_RANGE_DEGREES), "pass": False}
    final_pelvis = absolute_series["pelvis"][-1] if absolute_series["pelvis"] else None
    final_turn_ok = final_pelvis is not None and abs(abs(final_pelvis) - FINAL_TURN_DEGREES) <= FINAL_TURN_TOLERANCE_DEGREES
    relative_follow_names = tuple(
        name for name in relative_angle_series if name != "pelvis_absolute"
    )
    follow_active = all(
        motion_summary[name].get("peak_abs_degrees", 0.0) > FOLLOW_ACTIVE_DEGREES
        for name in relative_follow_names
    )
    follow_settled = all(
        abs(motion_summary[name].get("frame_60_degrees", math.inf)) < FOLLOW_SETTLE_DEGREES
        for name in relative_follow_names
    )
    follow_result = {
        "relative_rotation_summary": motion_summary,
        "relative_yaw_summary": relative_yaw_summary,
        "absolute_yaw_summary": absolute_summary,
        "torso_lead": lead_result,
        "final_pelvis_yaw_degrees": final_pelvis,
        "expected_final_turn_degrees": FINAL_TURN_DEGREES,
        "final_turn_tolerance_degrees": FINAL_TURN_TOLERANCE_DEGREES,
        "final_turn_pass": final_turn_ok,
        "intentional_follow_nonzero_pass": follow_active,
        "secondary_follow_settles_by_frame_60_pass": follow_settled,
        "motion_semantics": "authored bone motion evaluated from pose; no cloth or hair simulation claimed",
        "follow_threshold_semantics": "intentional follow and settle use full 3-D quaternion angle magnitude; armature-space Z yaw is reported separately",
        "per_frame_relative_rotations": [
            {"frame": frame["frame"], "rotation_twists": frame["relative_rotations"]}
            for frame in frame_records
        ],
        "pass": lead_result["pass"] and follow_active and follow_settled and final_turn_ok,
    }
    report["animation"]["measured_relative_rotations"] = follow_result
    helpers.record_check(report, "torso_lead_and_authored_follow_settle", follow_result["pass"],
                         {key: value for key, value in follow_result.items()
                          if key not in {"per_frame_relative_rotations", "relative_rotation_summary", "absolute_yaw_summary"}},
                         "Torso lead must peak at 6-10 degrees, secondary follow must be nonzero and settled by frame 60, and pelvis must finish the 115-degree turn.")

    valid_camera_frames = [item for item in camera_frame_metrics
                           if item.get("minimum_margin_px") is not None]
    camera_pass = (
        len(valid_camera_frames) == 60
        and all(item["minimum_margin_px"] > helpers.CAMERA_MARGIN_MIN_PX for item in valid_camera_frames)
        and all(item.get("clipped_or_behind_vertex_samples") == 0 for item in valid_camera_frames)
    )
    worst_camera = min(valid_camera_frames, key=lambda item: item["minimum_margin_px"], default=None)
    report["camera_review"].update({
        "frame_count": len(camera_frame_metrics),
        "valid_margin_frame_count": len(valid_camera_frames),
        "minimum_margin_px": worst_camera["minimum_margin_px"] if worst_camera else None,
        "minimum_margin_frame": worst_camera["frame"] if worst_camera else None,
        "worst_frame_side_margins_px": worst_camera.get("side_margins_px") if worst_camera else None,
        "per_frame": camera_frame_metrics,
        "threshold_px_strictly_greater_than": helpers.CAMERA_MARGIN_MIN_PX,
        "pass": camera_pass,
    })
    helpers.record_check(report, "all_meshes_within_camera_margins", camera_pass,
                         {key: value for key, value in report["camera_review"].items() if key != "per_frame"},
                         "Every mesh vertex must remain unclipped and more than 16 px inside every camera-frame edge.")

    report["status"] = "PASS" if not report["errors"] else "FAIL"
    report["summary"] = {
        "checks_passed": sum(check["status"] == "PASS" for check in report["checks"].values()),
        "checks_failed": sum(check["status"] == "FAIL" for check in report["checks"].values()),
        "error_count": len(report["errors"]),
        "visual_review": "not performed by this automated verifier",
    }
    return report


def write_report_new(path: Path, report: dict[str, Any]) -> None:
    payload = json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    with path.open("x", encoding="utf-8") as stream:
        stream.write(payload)


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(script_args(sys.argv if argv is None else argv))
    try:
        helpers = load_base_helpers()
        report_path = helpers.validate_report_destination(args.report)
    except Exception as exc:
        parser.error(str(exc))
    try:
        refinement_data, refinement_path_str = read_refinement_report(args.refinement_report)
        refinement_path = Path(refinement_path_str)
    except Exception as exc:
        failure = {
            "status": "FAIL", "report_path": str(report_path),
            "errors": [f"Could not read refinement report: {type(exc).__name__}: {exc}"],
            "checks": {},
        }
        try:
            write_report_new(report_path, failure)
        except Exception as write_exc:
            print(f"Could not write report: {type(write_exc).__name__}: {write_exc}", file=sys.stderr)
            return 2
        print(json.dumps({"status": "FAIL", "report": str(report_path),
                          "errors": failure["errors"]}, ensure_ascii=False))
        return 1

    try:
        import bpy
        import numpy as np
        report = verify_refined_project(bpy, np, helpers, report_path, refinement_path, refinement_data)
    except Exception as exc:
        report = {
            "status": "FAIL", "report_path": str(report_path),
            "refinement_report_path": str(refinement_path),
            "errors": [f"Verifier execution failed: {type(exc).__name__}: {exc}"],
            "traceback": traceback.format_exc(), "checks": {},
        }
    try:
        write_report_new(report_path, report)
    except Exception as exc:
        print(f"Could not write report: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({"status": report["status"], "report": str(report_path),
                      "errors": report.get("errors", [])}, ensure_ascii=False))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
