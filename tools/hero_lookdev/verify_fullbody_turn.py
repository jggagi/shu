#!/usr/bin/env python3
"""Verify a saved Jiang full-body turn project without saving or rendering it.

Run against an already-saved project with Blender's automatic script execution
disabled, for example::

    blender --disable-autoexec --background /abs/path/jiang-fullbody-turn.blend --python /abs/path/verify_fullbody_turn.py -- --report /abs/path/new-verification.json

The report path must be absolute, end in .json, have an existing parent
directory, and not already exist. The verifier restores the scene's original
frame after checking frames 1 through 60. It never resets, saves, or renders.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import traceback
from pathlib import Path
from typing import Any


EXPECTED_MESHES = (
    "JiangFullbody",
    "JiangApprovedHead",
    "JiangRightGrip_HandGrip",
    "JiangRightGrip_Jian",
)
RIG_NAME = "JiangRig"
FPS = 30
FRAME_START = 1
FRAME_END = 60
TEXTURE_COUNT = 6
TEXTURE_SIZE = (4096, 4096)
WEIGHT_TOLERANCE = 1.0e-6
INVARIANT_TOLERANCE = 1.0e-5
CAMERA_MARGIN_MIN_PX = 16.0
FOOT_LIFT_MIN_M = 0.04


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--report",
        required=True,
        type=Path,
        help="absolute path for a new JSON verification report",
    )
    return parser


def blender_script_args(argv: list[str]) -> list[str]:
    """Return arguments after Blender's ``--`` separator, if present."""
    if "--" in argv:
        return argv[argv.index("--") + 1 :]
    return argv[1:]


def json_float(value: Any) -> float:
    result = float(value)
    if not math.isfinite(result):
        raise ValueError("non-finite number cannot be written to JSON")
    return result


def record_check(
    report: dict[str, Any],
    name: str,
    passed: bool,
    evidence: Any,
    failure: str,
) -> None:
    report.setdefault("checks", {})[name] = {
        "status": "PASS" if passed else "FAIL",
        "evidence": evidence,
    }
    if not passed:
        report.setdefault("errors", []).append(failure)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def numpy_matrix(matrix: Any, np: Any) -> Any:
    return np.asarray(
        [[float(matrix[row][column]) for column in range(4)] for row in range(4)],
        dtype=np.float64,
    )


def transform_points(points: Any, matrix: Any, np: Any) -> Any:
    # Avoid Accelerate/BLAS floating-status warnings for finite small matrices.
    return np.einsum('ij,kj->ik', points, matrix[:3, :3], optimize=False) + matrix[:3, 3]


def mesh_coordinates(mesh: Any, np: Any) -> Any:
    flat = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get("co", flat)
    return flat.reshape((-1, 3)).astype(np.float64, copy=False)


def rest_geometry_record(mesh: Any, np: Any) -> tuple[dict[str, Any], Any]:
    coordinates = mesh_coordinates(mesh, np)
    loop_vertex_indices = np.empty(len(mesh.loops), dtype=np.int32)
    if len(mesh.loops):
        mesh.loops.foreach_get("vertex_index", loop_vertex_indices)
    polygon_loop_totals = np.empty(len(mesh.polygons), dtype=np.int32)
    if len(mesh.polygons):
        mesh.polygons.foreach_get("loop_total", polygon_loop_totals)

    digest = hashlib.sha256()
    digest.update(np.asarray(
        [len(mesh.vertices), len(mesh.polygons), len(mesh.loops)], dtype="<u8"
    ).tobytes())
    digest.update(coordinates.astype("<f4", copy=False).tobytes(order="C"))
    digest.update(polygon_loop_totals.astype("<i4", copy=False).tobytes(order="C"))
    digest.update(loop_vertex_indices.astype("<i4", copy=False).tobytes(order="C"))

    finite = bool(np.isfinite(coordinates).all()) and len(coordinates) > 0
    record: dict[str, Any] = {
        "vertices": len(mesh.vertices),
        "polygons": len(mesh.polygons),
        "loops": len(mesh.loops),
        "rest_geometry_sha256": digest.hexdigest(),
        "coordinates_finite": finite,
    }
    if finite:
        record["local_bounds"] = {
            "min": [json_float(x) for x in coordinates.min(axis=0)],
            "max": [json_float(x) for x in coordinates.max(axis=0)],
        }
    return record, coordinates


def packed_image_files(image: Any) -> list[Any]:
    single = getattr(image, "packed_file", None)
    if single is not None:
        return [single]
    packed_files = getattr(image, "packed_files", None)
    if packed_files is None:
        return []
    return [packed for packed in packed_files if packed is not None]


def texture_record(image: Any) -> dict[str, Any]:
    packed_files = packed_image_files(image)
    parts: list[dict[str, Any]] = []
    digest = hashlib.sha256()
    total_bytes = 0
    for index, packed in enumerate(packed_files):
        raw = bytes(packed.data)
        digest.update(index.to_bytes(4, "little", signed=False))
        digest.update(len(raw).to_bytes(8, "little", signed=False))
        digest.update(raw)
        total_bytes += len(raw)
        parts.append({
            "index": index,
            "filepath": str(getattr(packed, "filepath", "")),
            "bytes": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest(),
        })
    return {
        "name": image.name,
        "size": [int(image.size[0]), int(image.size[1])],
        "packed": bool(packed_files),
        "packed_bytes": total_bytes,
        "packed_sha256": digest.hexdigest() if packed_files else None,
        "packed_parts": parts,
    }


def find_drivers(bpy: Any) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []
    visited: set[int] = set()
    for prop in bpy.data.bl_rna.properties:
        if getattr(prop, "type", None) != "COLLECTION":
            continue
        try:
            collection = getattr(bpy.data, prop.identifier)
            items = iter(collection)
        except (AttributeError, TypeError, RuntimeError):
            continue
        for datablock in items:
            animation_data = getattr(datablock, "animation_data", None)
            if animation_data is None:
                continue
            try:
                pointer = int(datablock.as_pointer())
            except (AttributeError, TypeError, RuntimeError):
                pointer = id(datablock)
            if pointer in visited:
                continue
            visited.add(pointer)
            for curve in animation_data.drivers:
                driver = curve.driver
                found.append({
                    "datablock_type": getattr(datablock, "bl_rna", None).identifier
                    if getattr(datablock, "bl_rna", None) is not None else type(datablock).__name__,
                    "datablock": getattr(datablock, "name_full", getattr(datablock, "name", "")),
                    "data_path": curve.data_path,
                    "array_index": int(curve.array_index),
                    "driver_type": driver.type,
                    "expression": getattr(driver, "expression", ""),
                })
    return found


def weight_record(obj: Any, rig: Any, tolerance: float) -> dict[str, Any]:
    groups = list(obj.vertex_groups)
    group_names = [group.name for group in groups]
    failures = 0
    max_weight_error = 0.0
    bad_examples: list[int] = []
    expected_group = groups[0] if len(groups) == 1 else None
    for vertex in obj.data.vertices:
        memberships = list(vertex.groups)
        valid = len(memberships) == 1 and expected_group is not None
        if valid:
            membership = memberships[0]
            valid = membership.group == expected_group.index
            error = abs(float(membership.weight) - 1.0)
            max_weight_error = max(max_weight_error, error)
            valid = valid and error <= tolerance
        if not valid:
            failures += 1
            if len(bad_examples) < 12:
                bad_examples.append(int(vertex.index))

    armature_modifiers = [modifier for modifier in obj.modifiers if modifier.type == "ARMATURE"]
    modifier_targets = [modifier.object.name if modifier.object is not None else None
                        for modifier in armature_modifiers]
    return {
        "groups": group_names,
        "vertices": len(obj.data.vertices),
        "bad_vertex_count": failures,
        "bad_vertex_examples": bad_examples,
        "max_weight_error": json_float(max_weight_error),
        "armature_modifier_count": len(armature_modifiers),
        "armature_modifier_targets": modifier_targets,
        "parent": obj.parent.name if obj.parent is not None else None,
        "pass": (
            group_names == ["hand.R"]
            and failures == 0
            and len(armature_modifiers) == 1
            and armature_modifiers[0].object == rig
        ),
    }


def verify_project(bpy: Any, np: Any, report_path: Path) -> dict[str, Any]:
    report: dict[str, Any] = {
        "status": "FAIL",
        "report_path": str(report_path),
        "errors": [],
        "checks": {},
        "source": {},
        "scene": {},
        "textures": [],
        "meshes": {},
        "animation": {},
        "camera_review": {},
        "geometry_hashes": {},
    }

    blend_raw = bpy.data.filepath
    blend_path = Path(blend_raw).expanduser() if blend_raw else None
    blend_exists = bool(
        blend_path
        and blend_path.is_absolute()
        and blend_path.suffix.lower() == ".blend"
        and blend_path.is_file()
    )
    blend_hash = sha256_file(blend_path) if blend_exists else None
    report["source"].update({
        "blend_path": str(blend_path) if blend_path else None,
        "blend_exists": blend_exists,
        "blend_bytes": blend_path.stat().st_size if blend_exists else None,
        "blend_sha256": blend_hash,
    })
    record_check(
        report,
        "saved_blend_exists",
        blend_exists,
        report["source"],
        "The currently open Blender project is not an existing saved absolute .blend file.",
    )

    scene = bpy.context.scene
    if scene is None:
        record_check(report, "scene_available", False, None, "No active Blender scene is available.")
        return report
    report["scene"].update({
        "name": scene.name,
        "frame_start": int(scene.frame_start),
        "frame_end": int(scene.frame_end),
        "fps": int(scene.render.fps),
        "fps_base": json_float(scene.render.fps_base),
        "effective_fps": json_float(scene.render.fps / scene.render.fps_base),
        "frame_count_inclusive": int(scene.frame_end - scene.frame_start + 1),
        "duration_seconds": json_float(
            (scene.frame_end - scene.frame_start + 1) * scene.render.fps_base / scene.render.fps
        ),
    })
    frame_timing_pass = (
        scene.render.fps == FPS
        and abs(float(scene.render.fps_base) - 1.0) <= 1.0e-8
        and scene.frame_start == FRAME_START
        and scene.frame_end == FRAME_END
    )
    record_check(
        report,
        "scene_30fps_frames_1_to_60",
        frame_timing_pass,
        report["scene"],
        "Scene timing must be 30 fps, fps_base 1, frames 1 through 60 (2 seconds).",
    )

    scene_objects = list(scene.objects)
    mesh_objects_in_scene = [obj for obj in scene_objects if obj.type == "MESH"]
    actual_mesh_names = sorted(obj.name for obj in mesh_objects_in_scene)
    global_mesh_names = sorted(obj.name for obj in bpy.data.objects if obj.type == "MESH")
    expected_mesh_set = set(EXPECTED_MESHES)
    record_check(
        report,
        "four_expected_meshes_only",
        len(mesh_objects_in_scene) == len(EXPECTED_MESHES)
        and set(actual_mesh_names) == expected_mesh_set
        and set(global_mesh_names) == expected_mesh_set,
        {"expected": list(EXPECTED_MESHES), "scene_objects": actual_mesh_names,
         "all_project_mesh_objects": global_mesh_names},
        "Scene must contain exactly the four expected mesh objects.",
    )
    meshes: dict[str, Any] = {}
    for name in EXPECTED_MESHES:
        obj = bpy.data.objects.get(name)
        if obj is not None and obj.type == "MESH" and obj in scene_objects:
            meshes[name] = obj
    missing_meshes = [name for name in EXPECTED_MESHES if name not in meshes]
    record_check(
        report,
        "expected_meshes_available",
        not missing_meshes,
        {"available": sorted(meshes), "missing": missing_meshes},
        "One or more required mesh objects are missing or not in the active scene.",
    )

    armature_objects = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    armature_data = list(bpy.data.armatures)
    rig = bpy.data.objects.get(RIG_NAME)
    rig_pass = (
        len(armature_objects) == 1
        and len(armature_data) == 1
        and rig is not None
        and rig.type == "ARMATURE"
        and rig.name in scene.objects
    )
    rig_evidence: dict[str, Any] = {
        "armature_objects": [obj.name for obj in armature_objects],
        "armature_datablocks": [data.name for data in armature_data],
        "expected_name": RIG_NAME,
    }
    if rig is not None and rig.type == "ARMATURE":
        rig_evidence["bones"] = len(rig.data.bones)
        rig_evidence["bone_names"] = sorted(bone.name for bone in rig.data.bones)
        rig_pass = rig_pass and len(rig.data.bones) == 22
        rig_pass = rig_pass and rig.data.name in {data.name for data in armature_data}
    else:
        rig_evidence["bones"] = None
        rig_pass = False
    report["scene"]["rig"] = rig_evidence
    record_check(
        report,
        "single_jiang_rig_with_22_bones",
        rig_pass,
        rig_evidence,
        "Expected exactly one armature object/data block named JiangRig with 22 bones.",
    )

    font_objects = [obj.name for obj in bpy.data.objects if obj.type == "FONT"]
    font_curves = [curve.name for curve in bpy.data.curves if curve.type == "FONT"]
    text_pass = not font_objects and not font_curves
    report["scene"]["text_objects"] = font_objects
    report["scene"]["text_curve_datablocks"] = font_curves
    record_check(
        report,
        "no_text_objects",
        text_pass,
        {"font_objects": font_objects, "font_curve_datablocks": font_curves},
        "The saved scene must not contain Text objects or Font curve datablocks.",
    )

    drivers = find_drivers(bpy)
    report["scene"]["drivers"] = drivers
    record_check(
        report,
        "no_drivers",
        not drivers,
        {"count": len(drivers), "items": drivers},
        "The saved project contains one or more driver F-curves.",
    )

    images = [image for image in bpy.data.images
              if image.type != "RENDER_RESULT" and image.name != "Render Result"]
    texture_records: list[dict[str, Any]] = []
    texture_hash_errors: list[str] = []
    for image in images:
        try:
            texture_records.append(texture_record(image))
        except Exception as exc:  # Keep evidence for other images and write a failure report.
            texture_hash_errors.append(f"{image.name}: {type(exc).__name__}: {exc}")
    report["textures"] = texture_records
    texture_count_pass = len(images) == TEXTURE_COUNT
    texture_shape_pass = all(tuple(item["size"]) == TEXTURE_SIZE for item in texture_records)
    texture_packed_pass = len(texture_records) == len(images) and all(
        item["packed"] and item["packed_sha256"] for item in texture_records
    )
    texture_pass = texture_count_pass and texture_shape_pass and texture_packed_pass and not texture_hash_errors
    report["source"]["packed_texture_hash_errors"] = texture_hash_errors
    record_check(
        report,
        "six_packed_4096_textures",
        texture_pass,
        {
            "expected_count": TEXTURE_COUNT,
            "actual_count": len(images),
            "expected_size": list(TEXTURE_SIZE),
            "all_dimensions_match": texture_shape_pass,
            "all_packed_and_hashed": texture_packed_pass,
            "hash_errors": texture_hash_errors,
            "textures": texture_records,
        },
        "Expected six packed 4096x4096 model textures with readable packed bytes.",
    )

    rest_coords: dict[str, Any] = {}
    geometry_ok = True
    for name, obj in meshes.items():
        try:
            geometry, coordinates = rest_geometry_record(obj.data, np)
            report["meshes"][name] = {
                "object_type": obj.type,
                "data_name": obj.data.name,
                "vertex_groups": [group.name for group in obj.vertex_groups],
                "modifiers": [
                    {"name": modifier.name, "type": modifier.type,
                     "object": modifier.object.name if getattr(modifier, "object", None) else None}
                    for modifier in obj.modifiers
                ],
                **geometry,
            }
            rest_coords[name] = coordinates
            geometry_ok = geometry_ok and geometry["coordinates_finite"]
        except Exception as exc:
            geometry_ok = False
            report.setdefault("errors", []).append(
                f"Could not inspect rest geometry for {name}: {type(exc).__name__}: {exc}"
            )
    record_check(
        report,
        "rest_geometry_finite_and_hashed",
        geometry_ok and len(rest_coords) == len(EXPECTED_MESHES),
        {name: {key: value for key, value in mesh.items()
                if key in {"vertices", "polygons", "loops", "rest_geometry_sha256", "coordinates_finite", "local_bounds"}}
         for name, mesh in report["meshes"].items()},
        "Every expected mesh must have non-empty finite rest geometry and a geometry hash.",
    )
    report["geometry_hashes"] = {
        name: mesh.get("rest_geometry_sha256") for name, mesh in report["meshes"].items()
    }

    if rig is not None and rig.type == "ARMATURE":
        weight_results: dict[str, Any] = {}
        for name in ("JiangRightGrip_HandGrip", "JiangRightGrip_Jian"):
            obj = meshes.get(name)
            if obj is None:
                continue
            try:
                weight_results[name] = weight_record(obj, rig, WEIGHT_TOLERANCE)
            except Exception as exc:
                weight_results[name] = {"pass": False, "error": f"{type(exc).__name__}: {exc}"}
        report["animation"]["grip_weights"] = weight_results
        weights_pass = set(weight_results) == {
            "JiangRightGrip_HandGrip", "JiangRightGrip_Jian"
        } and all(item.get("pass") for item in weight_results.values())
        record_check(
            report,
            "rigid_hand_and_sword_hand_R_weights",
            weights_pass,
            weight_results,
            "Both grip meshes must have only hand.R, weight 1 on every vertex, and one armature modifier targeting JiangRig.",
        )
    else:
        record_check(
            report,
            "rigid_hand_and_sword_hand_R_weights",
            False,
            None,
            "Grip weights cannot be checked because JiangRig is unavailable.",
        )

    camera = scene.camera
    camera_valid = camera is not None and camera.type == "CAMERA" and camera.data.type == "ORTHO"
    if camera_valid:
        render = scene.render
        resolution_x = int(render.resolution_x * render.resolution_percentage / 100)
        resolution_y = int(render.resolution_y * render.resolution_percentage / 100)
        view_frame = camera.data.view_frame(scene=scene)
        frame_xy = np.asarray([[float(point.x), float(point.y)] for point in view_frame], dtype=np.float64)
        frame_bounds = {
            "min_x": float(frame_xy[:, 0].min()),
            "max_x": float(frame_xy[:, 0].max()),
            "min_y": float(frame_xy[:, 1].min()),
            "max_y": float(frame_xy[:, 1].max()),
        }
        camera_description = {
            "name": camera.name,
            "type": camera.data.type,
            "ortho_scale": json_float(camera.data.ortho_scale),
            "resolution": [resolution_x, resolution_y],
            "frame_bounds_camera_local": frame_bounds,
            "clip_start": json_float(camera.data.clip_start),
            "clip_end": json_float(camera.data.clip_end),
        }
    else:
        resolution_x = resolution_y = 0
        frame_bounds = None
        camera_description = {
            "name": camera.name if camera is not None else None,
            "type": camera.data.type if camera is not None else None,
        }
    report["camera_review"]["camera"] = camera_description
    record_check(
        report,
        "orthographic_review_camera",
        camera_valid,
        camera_description,
        "An orthographic active scene camera is required for frame-margin checks.",
    )

    required_for_frames = (
        rig is not None
        and rig.type == "ARMATURE"
        and all(name in meshes and name in rest_coords for name in EXPECTED_MESHES)
        and camera_valid
    )
    if not required_for_frames:
        record_check(
            report,
            "all_60_frame_evaluation",
            False,
            {"evaluated_frames": 0},
            "Frame evaluation skipped because a required mesh, rig, rest mesh, or orthographic camera is missing.",
        )
        return report

    original_frame = int(scene.frame_current)
    original_subframe = float(scene.frame_subframe)
    frame_records: list[dict[str, Any]] = []
    invariant_distances: dict[str, list[float]] = {
        "hand_vertex_0_to_sword_vertex_0": [],
        "sword_vertex_0_to_rest_max_z_tip": [],
        "head_vertex_0_to_vertex_minus_1": [],
    }
    support_foot_heads: list[list[float]] = []
    left_foot_heads: list[list[float]] = []
    body_min_z: list[float] = []
    camera_margin_frames: list[dict[str, Any]] = []
    evaluated_counts: dict[str, int] = {}
    frame_eval_error: str | None = None
    blade_tip_index = int(np.argmax(rest_coords["JiangRightGrip_Jian"][:, 2]))
    blade_tip_rest_local = rest_coords["JiangRightGrip_Jian"][blade_tip_index]
    report["animation"]["selected_vertices"] = {
        "hand_vertex_0": 0,
        "sword_vertex_0": 0,
        "sword_rest_max_z_tip_vertex": blade_tip_index,
        "sword_rest_max_z_tip_local": [json_float(x) for x in blade_tip_rest_local],
        "head_vertex_0": 0,
        "head_vertex_minus_1": len(rest_coords["JiangApprovedHead"]) - 1,
        "grip_tip_selection_semantics": "vertex with maximal local rest-mesh Z",
    }

    try:
        for frame in range(FRAME_START, FRAME_END + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            depsgraph = bpy.context.evaluated_depsgraph_get()
            evaluated: dict[str, Any] = {}
            world_coords: dict[str, Any] = {}
            frame_mesh_bounds: dict[str, Any] = {}
            all_world: list[Any] = []
            finite_frame = True

            for name, obj in meshes.items():
                evaluated_obj = obj.evaluated_get(depsgraph)
                evaluated_mesh = evaluated_obj.to_mesh()
                try:
                    coords = mesh_coordinates(evaluated_mesh, np)
                    evaluated_counts.setdefault(name, len(coords))
                    if len(coords) != len(rest_coords[name]):
                        report.setdefault("errors", []).append(
                            f"{name} evaluated vertex count changed at frame {frame}."
                        )
                        finite_frame = False
                    world_matrix = numpy_matrix(evaluated_obj.matrix_world, np)
                    points = transform_points(coords, world_matrix, np)
                    if not np.isfinite(points).all():
                        finite_frame = False
                        report.setdefault("errors", []).append(
                            f"{name} has non-finite evaluated world coordinates at frame {frame}."
                        )
                        continue
                    evaluated[name] = coords
                    world_coords[name] = points
                    all_world.append(points)
                    frame_mesh_bounds[name] = {
                        "min": [json_float(value) for value in points.min(axis=0)],
                        "max": [json_float(value) for value in points.max(axis=0)],
                    }
                finally:
                    evaluated_obj.to_mesh_clear()

            frame_records.append({"frame": frame, "world_bounds": frame_mesh_bounds})
            body_points = world_coords.get("JiangFullbody")
            if body_points is not None and len(body_points):
                body_min_z.append(json_float(body_points[:, 2].min()))

            if all(name in world_coords for name in EXPECTED_MESHES):
                hand_points = world_coords["JiangRightGrip_HandGrip"]
                sword_points = world_coords["JiangRightGrip_Jian"]
                head_points = world_coords["JiangApprovedHead"]
                if len(hand_points) and len(sword_points) > blade_tip_index and len(head_points) >= 2:
                    invariant_distances["hand_vertex_0_to_sword_vertex_0"].append(
                        float(np.linalg.norm(hand_points[0] - sword_points[0]))
                    )
                    invariant_distances["sword_vertex_0_to_rest_max_z_tip"].append(
                        float(np.linalg.norm(sword_points[0] - sword_points[blade_tip_index]))
                    )
                    invariant_distances["head_vertex_0_to_vertex_minus_1"].append(
                        float(np.linalg.norm(head_points[0] - head_points[-1]))
                    )
                else:
                    finite_frame = False
                    report.setdefault("errors", []).append(
                        f"Selected invariant vertices are unavailable at frame {frame}."
                    )

            if rig is not None:
                evaluated_rig = rig.evaluated_get(depsgraph)
                pose_bones = evaluated_rig.pose.bones
                support = pose_bones.get("foot.R")
                left = pose_bones.get("foot.L")
                if support is None or left is None:
                    report.setdefault("errors", []).append(
                        "Expected foot.R and foot.L pose bones are missing."
                    )
                    finite_frame = False
                else:
                    rig_world = evaluated_rig.matrix_world
                    support_world = rig_world @ support.head
                    left_world = rig_world @ left.head
                    support_foot_heads.append([float(x) for x in support_world])
                    left_foot_heads.append([float(x) for x in left_world])

            frame_camera: dict[str, Any] = {"frame": frame, "finite": finite_frame}
            if camera_valid and all_world:
                world = np.concatenate(all_world, axis=0)
                evaluated_camera = camera.evaluated_get(depsgraph)
                camera_inverse = numpy_matrix(evaluated_camera.matrix_world.inverted(), np)
                camera_points = transform_points(world, camera_inverse, np)
                x_min, x_max = frame_bounds["min_x"], frame_bounds["max_x"]
                y_min, y_max = frame_bounds["min_y"], frame_bounds["max_y"]
                frame_width = x_max - x_min
                frame_height = y_max - y_min
                if frame_width <= 0.0 or frame_height <= 0.0 or resolution_x <= 0 or resolution_y <= 0:
                    raise ValueError("Camera frame or render resolution is degenerate")
                horizontal = (camera_points[:, 0] - x_min) / frame_width * resolution_x
                vertical = (camera_points[:, 1] - y_min) / frame_height * resolution_y
                margins = {
                    "left": float(horizontal.min()),
                    "right": float((resolution_x - horizontal).min()),
                    "bottom": float(vertical.min()),
                    "top": float((resolution_y - vertical).min()),
                }
                depth = -camera_points[:, 2]
                clipped = (depth < camera.data.clip_start) | (depth > camera.data.clip_end)
                frame_camera.update({
                    "margins_px": {key: json_float(value) for key, value in margins.items()},
                    "minimum_margin_px": json_float(min(margins.values())),
                    "camera_depth_range": [json_float(depth.min()), json_float(depth.max())],
                    "behind_or_clipped_vertices": int(clipped.sum()),
                    "world_vertices_checked": int(len(world)),
                })
                camera_margin_frames.append(frame_camera)
            else:
                frame_camera["minimum_margin_px"] = None
                camera_margin_frames.append(frame_camera)
            frame_records[-1]["camera"] = frame_camera

        record_check(
            report,
            "all_60_frame_evaluation",
            len(frame_records) == FRAME_END - FRAME_START + 1
            and len(body_min_z) == FRAME_END - FRAME_START + 1
            and all(frame.get("camera", {}).get("finite", False) for frame in frame_records)
            and not any("non-finite" in error or "vertex count changed" in error
                        for error in report.get("errors", [])),
            {"evaluated_frames": len(frame_records), "per_mesh_evaluated_vertex_counts": evaluated_counts},
            "All 60 frames must evaluate with stable vertex counts and finite world coordinates.",
        )
    except Exception as exc:
        frame_eval_error = f"{type(exc).__name__}: {exc}"
        report.setdefault("errors", []).append(f"Frame evaluation failed: {frame_eval_error}")
    finally:
        scene.frame_set(original_frame, subframe=original_subframe)
        bpy.context.view_layer.update()

    report["animation"]["frames"] = frame_records
    report["animation"]["frame_evaluation_error"] = frame_eval_error
    report["animation"]["evaluated_vertex_counts"] = evaluated_counts

    invariant_report: dict[str, Any] = {}
    invariants_pass = True
    for name, values in invariant_distances.items():
        if len(values) != FRAME_END - FRAME_START + 1:
            item = {
                "samples": len(values),
                "threshold_m": INVARIANT_TOLERANCE,
                "pass": False,
                "reason": "Expected one distance sample for each of 60 frames.",
            }
            invariants_pass = False
        else:
            drifts = [abs(value - values[0]) for value in values]
            max_index = int(np.argmax(drifts))
            maximum = float(drifts[max_index])
            item = {
                "samples": len(values),
                "frame_1_distance_m": json_float(values[0]),
                "max_abs_drift_m": json_float(maximum),
                "max_drift_frame": FRAME_START + max_index,
                "threshold_m": INVARIANT_TOLERANCE,
                "pass": maximum < INVARIANT_TOLERANCE,
            }
            invariants_pass = invariants_pass and item["pass"]
        invariant_report[name] = item
    report["animation"]["distance_invariants"] = invariant_report
    record_check(
        report,
        "grip_sword_and_head_distance_invariants",
        invariants_pass,
        invariant_report,
        "Grip, sword-tip, and approved-head fixed-vertex distances must drift less than 1e-5 m.",
    )

    if support_foot_heads and len(support_foot_heads) == FRAME_END - FRAME_START + 1:
        support = np.asarray(support_foot_heads, dtype=np.float64)
        support_drift = np.linalg.norm(support - support[0], axis=1)
        support_max = float(support_drift.max())
        support_item = {
            "bone": "foot.R",
            "world_head_frame_1": [json_float(x) for x in support[0]],
            "max_world_head_drift_m": json_float(support_max),
            "max_drift_frame": FRAME_START + int(np.argmax(support_drift)),
            "threshold_m": INVARIANT_TOLERANCE,
            "pass": support_max < INVARIANT_TOLERANCE,
        }
    else:
        support_item = {"bone": "foot.R", "samples": len(support_foot_heads),
                        "threshold_m": INVARIANT_TOLERANCE, "pass": False}
    if left_foot_heads and len(left_foot_heads) == FRAME_END - FRAME_START + 1:
        left = np.asarray(left_foot_heads, dtype=np.float64)
        lift = left[:, 2] - left[0, 2]
        left_item = {
            "bone": "foot.L",
            "world_head_frame_1": [json_float(x) for x in left[0]],
            "maximum_upward_lift_m": json_float(max(0.0, float(lift.max()))),
            "maximum_lift_frame": FRAME_START + int(np.argmax(lift)),
            "required_lift_m": FOOT_LIFT_MIN_M,
            "pass": float(lift.max()) > FOOT_LIFT_MIN_M,
        }
    else:
        left_item = {"bone": "foot.L", "samples": len(left_foot_heads),
                     "required_lift_m": FOOT_LIFT_MIN_M, "pass": False}
    report["animation"]["support_foot"] = support_item
    report["animation"]["left_step_foot"] = left_item
    record_check(
        report,
        "right_support_foot_head_stable",
        support_item["pass"],
        support_item,
        "foot.R pose-head world position must drift less than 1e-5 m across the turn.",
    )
    record_check(
        report,
        "left_foot_head_lifts",
        left_item["pass"],
        left_item,
        "foot.L pose-head must rise more than 0.04 m above its frame-1 height.",
    )

    if body_min_z:
        body_min_range = {
            "min_of_frame_min_z_m": json_float(min(body_min_z)),
            "max_of_frame_min_z_m": json_float(max(body_min_z)),
            "frame_1_min_z_m": json_float(body_min_z[0]),
            "semantics": "range of JiangFullbody vertex minima; not an exact ground-contact assertion",
        }
    else:
        body_min_range = {"samples": 0, "semantics": "not available"}
    report["animation"]["body_min_z_range"] = body_min_range

    valid_margin_frames = [item for item in camera_margin_frames
                           if item.get("minimum_margin_px") is not None]
    if (
        len(camera_margin_frames) == FRAME_END - FRAME_START + 1
        and len(valid_margin_frames) == FRAME_END - FRAME_START + 1
    ):
        minimum_frame = min(valid_margin_frames, key=lambda item: item["minimum_margin_px"])
        global_margin = float(minimum_frame["minimum_margin_px"])
        camera_clipped = sum(int(frame.get("behind_or_clipped_vertices", 0)) for frame in camera_margin_frames)
        camera_result = {
            "frame_count": len(camera_margin_frames),
            "minimum_margin_px": json_float(global_margin),
            "minimum_margin_frame": int(minimum_frame["frame"]),
            "minimum_frame_side_margins_px": minimum_frame["margins_px"],
            "clipped_or_behind_vertex_samples": camera_clipped,
            "threshold_px_strictly_greater_than": CAMERA_MARGIN_MIN_PX,
            "pass": global_margin > CAMERA_MARGIN_MIN_PX and camera_clipped == 0,
            "per_frame": camera_margin_frames,
        }
    else:
        camera_result = {
            "frame_count": len(camera_margin_frames),
            "valid_margin_frame_count": len(valid_margin_frames),
            "threshold_px_strictly_greater_than": CAMERA_MARGIN_MIN_PX,
            "pass": False,
            "per_frame": camera_margin_frames,
        }
    report["camera_review"].update(camera_result)
    record_check(
        report,
        "all_meshes_within_camera_margins",
        camera_result["pass"],
        {key: value for key, value in camera_result.items() if key != "per_frame"},
        "Every mesh vertex must remain in front of the camera, unclipped, and more than 16 px inside all frame edges.",
    )

    report["status"] = "PASS" if not report["errors"] else "FAIL"
    report["summary"] = {
        "checks_passed": sum(item["status"] == "PASS" for item in report["checks"].values()),
        "checks_failed": sum(item["status"] == "FAIL" for item in report["checks"].values()),
        "error_count": len(report["errors"]),
        "visual_review": "not performed by this automated verifier",
    }
    return report


def validate_report_destination(path: Path) -> Path:
    if not path.is_absolute():
        raise ValueError("--report must be an absolute path")
    if path.suffix.lower() != ".json":
        raise ValueError("--report must have a .json extension")
    normalized = path.expanduser().resolve(strict=False)
    if normalized.exists():
        raise FileExistsError(f"Refusing to overwrite existing report: {normalized}")
    if not normalized.parent.is_dir():
        raise FileNotFoundError(f"Report parent directory does not exist: {normalized.parent}")
    return normalized


def write_new_report(path: Path, report: dict[str, Any]) -> None:
    payload = json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    with path.open("x", encoding="utf-8") as stream:
        stream.write(payload)


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    arguments = parser.parse_args(blender_script_args(sys.argv if argv is None else argv))
    try:
        report_path = validate_report_destination(arguments.report)
    except Exception as exc:
        parser.error(str(exc))

    try:
        import bpy
        import numpy as np

        report = verify_project(bpy, np, report_path)
    except Exception as exc:
        report = {
            "status": "FAIL",
            "report_path": str(report_path),
            "errors": [f"Verifier execution failed: {type(exc).__name__}: {exc}"],
            "traceback": traceback.format_exc(),
            "checks": {},
        }
    try:
        write_new_report(report_path, report)
    except Exception as exc:
        print(f"Could not write verification report: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({"status": report["status"], "report": str(report_path),
                      "errors": report.get("errors", [])}, ensure_ascii=False))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
