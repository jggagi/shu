#!/usr/bin/env python3
"""Verify the four-second Jiang sword phrase in the already-open Blender file.

Example::

    blender --disable-autoexec --background /abs/path/jiang-sword-phrase.blend --python /abs/path/verify_sword_phrase.py -- --report /abs/path/new-report.json --baseline-report /abs/path/refined-v2/verification-v3.json

This read-only verifier does not reset, save, or render the scene. It restores
the current frame after evaluating frames 1 through 120. It checks structural,
geometric, motion-path, floor, and camera evidence; it does not certify visual
or artistic acceptance.
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


FPS = 30
FRAME_START = 1
FRAME_END = 120
TEXTURE_COUNT = 6
TEXTURE_SIZE = (4096, 4096)
WEIGHT_TOLERANCE = 0.001
INVARIANT_TOLERANCE_M = 1.0e-5
SUPPORT_BOOT_MIN_Z_M = -0.008
SUPPORT_BALL_REST = (-0.19, -0.22, 0.006)
FACE_Y_MAX = 0.05
FACE_Z_MIN = 1.7
REAR_HAIR_Y_MIN = 0.12
REAR_HAIR_Z_MIN = 1.35
BOOT_REST_Z_MAX = 0.20
SWORD_MAX_DISPLACEMENT_MIN_M = 0.35
SWORD_RISE_MIN_M = 0.15
SWORD_FALL_MIN_M = 0.20
LEFT_FOOT_LIFT_MIN_M = 0.04
LEFT_FOOT_FORWARD_MIN_M = 0.10
LEFT_BOOT_FINAL_MAX_ABS_Z_M = 0.008
LEFT_HAND_WRIST_REST = (0.435, -0.15, 1.02)
LEFT_HAND_DIRECTION_POINT = (0.46, -0.16, 0.91)
LEFT_HAND_RADIAL_MAX_M = 0.105
LEFT_HAND_LENGTH_MAX_M = 0.235
LEFT_HAND_MIN_AXIAL_M = 0.04

PHASES = (
    {"name": "ready", "start_frame": 1, "end_frame": 18, "time_interval": "[0.00, 0.60)s"},
    {"name": "windup", "start_frame": 19, "end_frame": 45, "time_interval": "[0.60, 1.50)s"},
    {"name": "diagonal_cut", "start_frame": 46, "end_frame": 58, "time_interval": "[1.50, 1.92)s"},
    {"name": "follow", "start_frame": 59, "end_frame": 77, "time_interval": "[1.92, 2.55)s"},
    {"name": "recover", "start_frame": 78, "end_frame": 108, "time_interval": "[2.55, 3.60)s"},
    {"name": "hold_end", "start_frame": 109, "end_frame": 120, "time_interval": "[3.60, 4.00)s"},
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--report", required=True, type=Path,
                        help="absolute path for a new JSON verification report")
    parser.add_argument("--baseline-report", required=True, type=Path,
                        help="absolute path to the passing refined-v2 verification-v3.json")
    return parser


def script_args(argv: list[str]) -> list[str]:
    if "--" in argv:
        return argv[argv.index("--") + 1:]
    return argv[1:]


def load_module(name: str, path: Path) -> Any:
    if not path.is_file():
        raise FileNotFoundError(f"Required shared verifier is missing: {path}")
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load shared verifier from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_helpers() -> tuple[Any, Any]:
    sys.dont_write_bytecode = True
    directory = Path(__file__).resolve().parent
    base = load_module("jiang_fullbody_verifier_helpers", directory / "verify_fullbody_turn.py")
    refined = load_module("jiang_refined_verifier_helpers", directory / "verify_refined_turn.py")
    return base, refined


def safe_float(value: Any) -> float | None:
    result = float(value)
    return result if math.isfinite(result) else None


def finite_vector(values: Any, np: Any) -> bool:
    return bool(np.isfinite(np.asarray(values, dtype=np.float64)).all())


def canonical_sha256(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"),
                          ensure_ascii=False, allow_nan=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def read_baseline(path: Path, helpers: Any) -> tuple[dict[str, Any], Path, str]:
    if not path.is_absolute():
        raise ValueError("--baseline-report must be an absolute path")
    resolved = path.expanduser().resolve(strict=True)
    if not resolved.is_file() or resolved.suffix.lower() != ".json":
        raise ValueError("--baseline-report must name an existing JSON file")
    data = json.loads(resolved.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("baseline report must contain a JSON object")
    return data, resolved, helpers.sha256_file(resolved)


def baseline_fingerprints(baseline: dict[str, Any]) -> tuple[dict[str, str], dict[str, str]]:
    source = baseline.get("source", {})
    geometry_raw = source.get("rest_geometry_sha256_by_mesh", {}) if isinstance(source, dict) else {}
    geometry = {
        str(name): str(digest)
        for name, digest in geometry_raw.items()
        if isinstance(name, str) and isinstance(digest, str)
    } if isinstance(geometry_raw, dict) else {}
    textures_raw = baseline.get("textures", [])
    textures: dict[str, str] = {}
    if isinstance(textures_raw, list):
        for item in textures_raw:
            if isinstance(item, dict) and isinstance(item.get("name"), str) and isinstance(item.get("packed_sha256"), str):
                textures[item["name"]] = item["packed_sha256"]
    return geometry, textures


def bone_rest_record(armature: Any, np: Any) -> tuple[dict[str, Any], str | None]:
    bones: list[dict[str, Any]] = []
    finite = True
    for bone in sorted(armature.data.bones, key=lambda item: item.name):
        head = [float(value) for value in bone.head_local]
        tail = [float(value) for value in bone.tail_local]
        matrix = [[float(bone.matrix_local[row][column]) for column in range(4)]
                  for row in range(4)]
        finite = (finite and finite_vector(head, np) and finite_vector(tail, np)
                  and finite_vector(matrix, np))
        bones.append({
            "name": bone.name,
            "parent": bone.parent.name if bone.parent else None,
            "head_local": head,
            "tail_local": tail,
            "matrix_local": matrix,
            "use_connect": bool(bone.use_connect),
        })
    payload = {"armature": armature.name, "bones": bones}
    digest = canonical_sha256(payload) if finite else None
    return {"bone_count": len(bones), "bones": bones, "sha256": digest, "finite": finite}, digest


def camera_record(scene: Any, camera: Any, np: Any) -> tuple[dict[str, Any], str | None, Any, Any, list[int]]:
    resolution = [
        int(scene.render.resolution_x * scene.render.resolution_percentage / 100),
        int(scene.render.resolution_y * scene.render.resolution_percentage / 100),
    ]
    if camera is None or camera.type != "CAMERA":
        return {"name": None, "type": None, "resolution": resolution}, None, None, None, resolution
    matrix = [[float(camera.matrix_world[row][column]) for column in range(4)] for row in range(4)]
    payload = {
        "name": camera.name,
        "type": camera.data.type,
        "matrix_world": matrix,
        "clip_start": float(camera.data.clip_start),
        "clip_end": float(camera.data.clip_end),
        "lens": float(camera.data.lens),
        "ortho_scale": float(camera.data.ortho_scale),
        "shift_x": float(camera.data.shift_x),
        "shift_y": float(camera.data.shift_y),
        "resolution": resolution,
        "fps": int(scene.render.fps),
        "fps_base": float(scene.render.fps_base),
    }
    finite = finite_vector(matrix, np) and all(
        math.isfinite(value) for value in (
            payload["clip_start"], payload["clip_end"], payload["lens"],
            payload["ortho_scale"], payload["shift_x"], payload["shift_y"],
            payload["fps_base"],
        )
    )
    digest = canonical_sha256(payload) if finite else None
    camera_frame = camera.data.view_frame(scene=scene) if camera.data.type == "ORTHO" else None
    bounds = None
    if camera_frame is not None:
        frame_xy = np.asarray([[float(vertex.x), float(vertex.y)] for vertex in camera_frame], dtype=np.float64)
        if finite_vector(frame_xy, np):
            bounds = {
                "min_x": float(frame_xy[:, 0].min()), "max_x": float(frame_xy[:, 0].max()),
                "min_y": float(frame_xy[:, 1].min()), "max_y": float(frame_xy[:, 1].max()),
            }
    return payload | {"frame_bounds_camera_local": bounds}, digest, camera_frame, bounds, resolution


def record_distance_invariant(values: list[float], meaning: str) -> dict[str, Any]:
    if len(values) != FRAME_END or not all(math.isfinite(value) for value in values):
        return {"samples": len(values), "threshold_m": INVARIANT_TOLERANCE_M,
                "meaning": meaning, "pass": False,
                "reason": "Expected 120 finite distance samples."}
    drifts = [abs(value - values[0]) for value in values]
    maximum_index = max(range(len(drifts)), key=drifts.__getitem__)
    maximum = drifts[maximum_index]
    return {
        "samples": len(values),
        "frame_1_distance_m": values[0],
        "maximum_absolute_drift_m": maximum,
        "maximum_drift_frame": maximum_index + 1,
        "threshold_m": INVARIANT_TOLERANCE_M,
        "meaning": meaning,
        "pass": maximum < INVARIANT_TOLERANCE_M,
    }


def phase_summary(sword_tip: list[list[float]], np: Any) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    if len(sword_tip) != FRAME_END:
        return [{**phase, "samples": 0, "pass": False} for phase in PHASES]
    points = np.asarray(sword_tip, dtype=np.float64)
    for phase in PHASES:
        start = phase["start_frame"] - 1
        end = phase["end_frame"]
        segment = points[start:end]
        origin = points[0]
        displacement = np.linalg.norm(segment - origin, axis=1)
        summaries.append({
            **phase,
            "samples": len(segment),
            "first_tip_world": [float(value) for value in segment[0]],
            "last_tip_world": [float(value) for value in segment[-1]],
            "maximum_displacement_from_frame_1_m": float(displacement.max()),
            "pass": bool(np.isfinite(segment).all()),
        })
    return summaries


def verify_phrase(bpy: Any, np: Any, helpers: Any, refined: Any,
                  report_path: Path, baseline: dict[str, Any], baseline_path: Path,
                  baseline_hash: str) -> dict[str, Any]:
    report: dict[str, Any] = {
        "status": "FAIL", "report_path": str(report_path),
        "baseline": {}, "source": {}, "scene": {}, "checks": {},
        "errors": [], "textures": [], "meshes": {}, "weights": {},
        "animation": {}, "camera_review": {},
    }

    blend_raw = bpy.data.filepath
    blend_path = Path(blend_raw).expanduser() if blend_raw else None
    blend_exists = bool(blend_path and blend_path.is_absolute()
                        and blend_path.suffix.lower() == ".blend" and blend_path.is_file())
    baseline_geometry, baseline_textures = baseline_fingerprints(baseline)
    expected_names = set(helpers.EXPECTED_MESHES)
    baseline_ready = (
        baseline.get("status") == "PASS"
        and set(baseline_geometry) == expected_names
        and len(baseline_textures) == TEXTURE_COUNT
        and all(len(value) == 64 for value in baseline_geometry.values())
        and all(len(value) == 64 for value in baseline_textures.values())
    )
    report["baseline"] = {
        "path": str(baseline_path), "sha256": baseline_hash,
        "status": baseline.get("status"),
        "saved_blend_path": baseline.get("source", {}).get("saved_blend_path")
        if isinstance(baseline.get("source"), dict) else None,
        "saved_blend_sha256": baseline.get("source", {}).get("saved_blend_sha256")
        if isinstance(baseline.get("source"), dict) else None,
        "geometry_hashes": baseline_geometry,
        "texture_hashes": baseline_textures,
    }
    report["source"].update({
        "saved_blend_path": str(blend_path) if blend_path else None,
        "saved_blend_bytes": blend_path.stat().st_size if blend_exists else None,
        "saved_blend_sha256": helpers.sha256_file(blend_path) if blend_exists else None,
        "baseline_report_sha256": baseline_hash,
        "rest_geometry_sha256_by_mesh": {},
        "texture_sha256_by_name": {},
    })
    helpers.record_check(report, "saved_blend_exists", blend_exists, report["source"],
                         "The open Blender project must be an existing saved .blend file.")
    helpers.record_check(report, "passing_baseline_report_available", baseline_ready,
                         {key: report["baseline"][key] for key in ("status", "geometry_hashes", "texture_hashes")},
                         "Baseline must be a passing refined-v2 verification-v3 report with four geometry and six texture hashes.")

    scene = bpy.context.scene
    if scene is None:
        helpers.record_check(report, "scene_available", False, None, "No active Blender scene is available.")
        return report
    scene_info = {
        "name": scene.name,
        "frame_start": int(scene.frame_start),
        "frame_end": int(scene.frame_end),
        "fps": int(scene.render.fps),
        "fps_base": safe_float(scene.render.fps_base),
        "duration_seconds": safe_float(
            (scene.frame_end - scene.frame_start + 1)
            * float(scene.render.fps_base) / max(1.0, float(scene.render.fps))
        ),
        "resolution": [
            int(scene.render.resolution_x * scene.render.resolution_percentage / 100),
            int(scene.render.resolution_y * scene.render.resolution_percentage / 100),
        ],
    }
    report["scene"] = scene_info
    scene_ok = (
        scene.frame_start == FRAME_START and scene.frame_end == FRAME_END
        and scene.render.fps == FPS and abs(float(scene.render.fps_base) - 1.0) < 1.0e-8
    )
    helpers.record_check(report, "scene_30fps_120_frames", scene_ok, scene_info,
                         "Phrase must use frames 1-120 at 30 fps (4.0 seconds).")

    scene_objects = list(scene.objects)
    scene_mesh_names = sorted(obj.name for obj in scene_objects if obj.type == "MESH")
    all_mesh_names = sorted(obj.name for obj in bpy.data.objects if obj.type == "MESH")
    exact_meshes = (len(scene_mesh_names) == 4 and set(scene_mesh_names) == expected_names
                    and set(all_mesh_names) == expected_names)
    helpers.record_check(report, "four_expected_meshes", exact_meshes,
                         {"expected": sorted(expected_names), "scene": scene_mesh_names,
                          "all_project_meshes": all_mesh_names},
                         "Project must contain only the four expected Jiang mesh objects.")
    meshes = {
        name: bpy.data.objects[name] for name in helpers.EXPECTED_MESHES
        if bpy.data.objects.get(name) is not None
        and bpy.data.objects[name].type == "MESH" and bpy.data.objects[name] in scene_objects
    }
    helpers.record_check(report, "expected_meshes_available", len(meshes) == 4,
                         {"available": sorted(meshes), "missing": sorted(expected_names - set(meshes))},
                         "One or more required meshes are missing from the active scene.")

    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    armature_data = list(bpy.data.armatures)
    rig = bpy.data.objects.get(helpers.RIG_NAME)
    rig_ok = (len(armatures) == 1 and len(armature_data) == 1 and rig is not None
              and rig.type == "ARMATURE" and rig in scene_objects and len(rig.data.bones) == 22)
    bone_record: dict[str, Any] = {"bone_count": None, "bones": [], "sha256": None, "finite": False}
    if rig is not None and rig.type == "ARMATURE":
        bone_record, _ = bone_rest_record(rig, np)
        rig_ok = rig_ok and bone_record["finite"]
    report["source"]["rest_bones_sha256"] = bone_record["sha256"]
    report["scene"]["armature"] = {
        "objects": [obj.name for obj in armatures],
        "datablocks": [data.name for data in armature_data],
        "name": rig.name if rig is not None else None,
        "bones": bone_record["bone_count"],
        "rest_bones_sha256": bone_record["sha256"],
    }
    helpers.record_check(report, "single_22_bone_jiang_rig", rig_ok,
                         report["scene"]["armature"],
                         "Expected one JiangRig and one finite 22-bone armature datablock.")

    text_objects = [obj.name for obj in bpy.data.objects if obj.type == "FONT"]
    text_curves = [curve.name for curve in bpy.data.curves if curve.type == "FONT"]
    helpers.record_check(report, "no_global_text", not text_objects and not text_curves,
                         {"objects": text_objects, "curves": text_curves},
                         "No Blender Text/Font datablocks are expected.")
    drivers = helpers.find_drivers(bpy)
    helpers.record_check(report, "no_drivers", not drivers,
                         {"count": len(drivers), "items": drivers},
                         "No Blender driver F-curves are expected.")

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
    current_texture_hashes = {item["name"]: item["packed_sha256"] for item in textures
                              if item.get("packed_sha256")}
    report["source"]["texture_sha256_by_name"] = current_texture_hashes
    texture_shape_ok = (
        len(images) == TEXTURE_COUNT and len(textures) == TEXTURE_COUNT
        and all(tuple(item["size"]) == TEXTURE_SIZE and item["packed"] and item["packed_sha256"]
                for item in textures) and not texture_errors
    )
    helpers.record_check(report, "six_packed_4096_textures", texture_shape_ok,
                         {"texture_hash_errors": texture_errors, "textures": textures},
                         "Expected six readable packed 4096x4096 images.")
    texture_match = (set(current_texture_hashes) == set(baseline_textures)
                     and all(current_texture_hashes.get(name) == digest
                             for name, digest in baseline_textures.items()))
    helpers.record_check(report, "packed_texture_payloads_match_baseline", texture_match,
                         {"baseline": baseline_textures, "current": current_texture_hashes},
                         "All six packed image payload hashes must match refined-v2 baseline.")

    rest_coords: dict[str, Any] = {}
    weight_arrays: dict[str, Any] = {}
    weight_indices: dict[str, dict[str, int]] = {}
    all_weights_ok = True
    all_geometry_ok = True
    geometry_records: dict[str, Any] = {}
    for name, obj in meshes.items():
        try:
            geometry, coords = helpers.rest_geometry_record(obj.data, np)
            rest_coords[name] = coords
            geometry_records[name] = geometry
            report["meshes"][name] = {
                "data_name": obj.data.name,
                "rest_geometry": geometry,
                "vertex_groups": [group.name for group in obj.vertex_groups],
                "uv_layers": [layer.name for layer in obj.data.uv_layers],
            }
            all_geometry_ok = all_geometry_ok and geometry["coordinates_finite"]
            weight_record, matrix, group_index = refined.weight_sum_record(obj, np, WEIGHT_TOLERANCE)
            report["weights"][name] = weight_record
            weight_arrays[name] = matrix
            weight_indices[name] = group_index
            all_weights_ok = all_weights_ok and weight_record["pass"]
        except Exception as exc:
            report["errors"].append(f"Could not inspect {name}: {type(exc).__name__}: {exc}")
            all_geometry_ok = False
            all_weights_ok = False
    current_geometry = {name: item.get("rest_geometry_sha256")
                        for name, item in geometry_records.items()}
    report["source"]["rest_geometry_sha256_by_mesh"] = current_geometry
    helpers.record_check(report, "rest_geometry_finite_and_hashed",
                         len(rest_coords) == 4 and all_geometry_ok,
                         current_geometry,
                         "All four rest meshes must have finite coordinates and SHA256 hashes.")
    helpers.record_check(report, "rest_geometry_matches_baseline",
                         set(current_geometry) == expected_names
                         and set(baseline_geometry) == expected_names
                         and all(current_geometry.get(name) == baseline_geometry.get(name)
                                 for name in expected_names),
                         {"baseline": baseline_geometry, "current": current_geometry},
                         "All four rest-mesh geometry hashes must match refined-v2 baseline.")
    helpers.record_check(report, "all_weights_finite_and_normalized", len(weight_arrays) == 4 and all_weights_ok,
                         report["weights"],
                         "All mesh vertex weights must be finite, nonnegative, and sum to 1 within 0.001.")

    hand_sword_weights: dict[str, Any] = {}
    if rig is not None and rig.type == "ARMATURE":
        for name in ("JiangRightGrip_HandGrip", "JiangRightGrip_Jian"):
            if name in meshes:
                hand_sword_weights[name] = helpers.weight_record(meshes[name], rig, 1.0e-6)
    grip_weights_ok = (set(hand_sword_weights) == {"JiangRightGrip_HandGrip", "JiangRightGrip_Jian"}
                       and all(item["pass"] for item in hand_sword_weights.values()))
    helpers.record_check(report, "hand_and_sword_only_hand_R", grip_weights_ok,
                         hand_sword_weights,
                         "Hand and sword must each have only unit hand.R weights and one modifier targeting JiangRig.")

    head_name, body_name = "JiangApprovedHead", "JiangFullbody"
    head_data, body_data = rest_coords.get(head_name), rest_coords.get(body_name)
    head_weights, body_weights = weight_arrays.get(head_name), weight_arrays.get(body_name)
    head_indices, body_indices = weight_indices.get(head_name, {}), weight_indices.get(body_name, {})
    face_ids = np.asarray([], dtype=np.int64)
    face_pair: tuple[int, int] | None = None
    if head_data is not None and head_weights is not None:
        face_ids = np.flatnonzero((head_data[:, 1] < FACE_Y_MAX) & (head_data[:, 2] > FACE_Z_MIN))
        face_pair = refined.farthest_face_pair(face_ids, head_data, np)
    if face_pair is not None and head_name in meshes:
        face_weights = refined.selected_group_record(
            [group.name for group in meshes[head_name].vertex_groups], head_weights,
            head_indices, face_ids, "head", 0.001, np,
        )
        face_weights.update({
            "selection": f"rest y<{FACE_Y_MAX}, z>{FACE_Z_MIN}; excludes neck bridge",
            "invariant_pair_vertices": list(face_pair),
        })
    else:
        face_weights = {"selected_vertices": int(len(face_ids)), "pass": False,
                        "reason": "Could not select two front-face vertices."}
    report["weights"]["front_face"] = face_weights
    helpers.record_check(report, "front_face_weighted_entirely_to_head", face_weights.get("pass", False),
                         face_weights,
                         "All selected face vertices must be 100% head-weighted and provide an invariant pair.")

    body_indices = weight_indices.get(body_name, {})
    support_boot_ids = np.asarray([], dtype=np.int64)
    left_boot_ids = np.asarray([], dtype=np.int64)
    boot_selections: dict[str, Any] = {}
    if body_data is not None and body_weights is not None:
        for side, group_name, side_mask in (
            ("R", "foot.R", body_data[:, 0] < 0.0),
            ("L", "foot.L", body_data[:, 0] >= 0.0),
        ):
            selected = np.flatnonzero((body_data[:, 2] < BOOT_REST_Z_MAX) & side_mask)
            boot_selections[side] = refined.selected_group_record(
                [group.name for group in meshes[body_name].vertex_groups], body_weights,
                body_indices, selected, group_name, WEIGHT_TOLERANCE, np,
            )
        if "foot.R" in body_indices:
            support_boot_ids = np.flatnonzero(
                (body_data[:, 2] < BOOT_REST_Z_MAX) & (body_data[:, 0] < 0.0)
                & (body_weights[:, body_indices["foot.R"]] >= 1.0 - WEIGHT_TOLERANCE)
            )
        if "foot.L" in body_indices:
            left_boot_ids = np.flatnonzero(
                (body_data[:, 2] < BOOT_REST_Z_MAX) & (body_data[:, 0] >= 0.0)
                & (body_weights[:, body_indices["foot.L"]] >= 1.0 - WEIGHT_TOLERANCE)
            )
    boot_weight_pass = len(boot_selections) == 2 and all(item["pass"] for item in boot_selections.values())
    report["weights"]["boots"] = boot_selections
    helpers.record_check(report, "sole_vertices_rigid_to_each_foot", boot_weight_pass,
                         {"sides": boot_selections, "right_support_vertices": int(len(support_boot_ids)),
                          "left_step_vertices": int(len(left_boot_ids))},
                         "All body vertices below rest z 0.2 m must be rigidly weighted to their side's foot.")

    left_hand_ids = np.asarray([], dtype=np.int64)
    left_hand_vertex_pair: tuple[int, int] | None = None
    left_hand_weights: dict[str, Any]
    if body_data is not None and body_weights is not None:
        wrist = np.asarray(LEFT_HAND_WRIST_REST, dtype=np.float64)
        direction_delta = np.asarray(LEFT_HAND_DIRECTION_POINT, dtype=np.float64) - wrist
        direction_length = float(np.linalg.norm(direction_delta))
        if direction_length > 1.0e-12 and math.isfinite(direction_length):
            direction = direction_delta / direction_length
            deltas = body_data - wrist
            along = np.einsum("ij,j->i", deltas, direction, optimize=False)
            radial = deltas - along[:, None] * direction
            radial_distance = np.linalg.norm(radial, axis=1)
            distance_from_wrist = np.linalg.norm(deltas, axis=1)
            left_hand_ids = np.flatnonzero(
                (body_data[:, 0] > 0.31)
                & (radial_distance < LEFT_HAND_RADIAL_MAX_M)
                & (distance_from_wrist < LEFT_HAND_LENGTH_MAX_M)
                & (along > LEFT_HAND_MIN_AXIAL_M)
            )
            left_hand_vertex_pair = refined.farthest_face_pair(left_hand_ids, body_data, np)
            left_hand_weights = refined.selected_group_record(
                [group.name for group in meshes[body_name].vertex_groups], body_weights,
                body_indices, left_hand_ids, "hand.L", WEIGHT_TOLERANCE, np,
            )
            left_hand_weights.update({
                "selection": {
                    "wrist_rest_local": list(LEFT_HAND_WRIST_REST),
                    "direction_point_rest_local": list(LEFT_HAND_DIRECTION_POINT),
                    "x_greater_than": 0.31,
                    "radial_distance_less_than_m": LEFT_HAND_RADIAL_MAX_M,
                    "distance_from_wrist_less_than_m": LEFT_HAND_LENGTH_MAX_M,
                    "axial_distance_greater_than_m": LEFT_HAND_MIN_AXIAL_M,
                },
                "sample_vertex_indices": [int(index) for index in left_hand_ids[:12]],
                "weight_bad_vertex_count": left_hand_weights.get("bad_vertex_count"),
                "invariant_pair_vertices": list(left_hand_vertex_pair) if left_hand_vertex_pair else None,
                "pair_selection_method": "two-pass farthest-vertex estimate",
            })
        else:
            left_hand_weights = {"group": "hand.L", "selected_vertices": 0,
                                 "pass": False, "reason": "Left-hand selection axis is degenerate."}
    else:
        left_hand_weights = {"group": "hand.L", "selected_vertices": 0,
                             "pass": False, "reason": "Full-body rest geometry or weights are unavailable."}
    report["weights"]["left_hand"] = left_hand_weights

    camera = scene.camera
    camera_info, camera_hash, _camera_frame, camera_bounds, resolution = camera_record(scene, camera, np)
    report["camera_review"]["camera"] = camera_info
    report["source"]["camera_sha256"] = camera_hash
    camera_ok = camera is not None and camera.type == "CAMERA" and camera.data.type == "ORTHO" and camera_bounds is not None
    helpers.record_check(report, "orthographic_camera_available", camera_ok, camera_info,
                         "An orthographic camera with finite frame bounds is required.")

    required_pose = ("foot.R", "foot.L")
    pose_ok = rig is not None and rig.type == "ARMATURE" and all(name in rig.pose.bones for name in required_pose)
    helpers.record_check(report, "required_foot_pose_bones", pose_ok,
                         {name: bool(rig and rig.type == "ARMATURE" and name in rig.pose.bones)
                          for name in required_pose},
                         "Expected foot.R and foot.L pose bones are required.")

    required = (
        rig is not None and rig.type == "ARMATURE" and camera_ok and pose_ok
        and all(name in meshes and name in rest_coords for name in helpers.EXPECTED_MESHES)
        and face_pair is not None and len(support_boot_ids) > 0 and len(left_boot_ids) > 0
        and "JiangRightGrip_HandGrip" in rest_coords and "JiangRightGrip_Jian" in rest_coords
    )
    if not required:
        helpers.record_check(report, "all_120_frame_evaluation", False, {"evaluated_frames": 0},
                             "Frame evaluation skipped because required meshes, rig, camera, or reference vertices are unavailable.")
        report["summary"] = {
            "checks_passed": sum(item["status"] == "PASS" for item in report["checks"].values()),
            "checks_failed": sum(item["status"] == "FAIL" for item in report["checks"].values()),
            "error_count": len(report["errors"]),
            "visual_review": "not performed by this verifier",
        }
        return report

    sword_data = rest_coords["JiangRightGrip_Jian"]
    sword_tip_index = int(np.argmax(sword_data[:, 2]))
    sword_tip_rest = [float(value) for value in sword_data[sword_tip_index]]
    report["animation"]["selected_references"] = {
        "sword_tip_vertex_index": sword_tip_index,
        "sword_tip_rest_local": sword_tip_rest,
        "support_ball_rest_armature": list(SUPPORT_BALL_REST),
        "front_face_vertices": int(len(face_ids)),
        "front_face_pair": list(face_pair),
        "forward_axis_semantics": "world-space direction from rear upper-hair centroid toward the front-face centroid at frame 1",
    }

    # In the new authoring contract the four mesh rest coordinates stay fixed;
    # this vector is a stable model-space reference used to measure the step.
    rear_ids = np.flatnonzero((head_data[:, 1] > REAR_HAIR_Y_MIN)
                              & (head_data[:, 2] > REAR_HAIR_Z_MIN))
    if not len(rear_ids):
        helpers.record_check(report, "forward_axis_available", False, {"rear_vertices": 0},
                             "Could not derive the initial anatomical forward axis from front face and rear hair.")
        forward_axis = None
    else:
        forward_axis = None

    original_frame = int(scene.frame_current)
    original_subframe = float(scene.frame_subframe)
    frame_records: list[dict[str, Any]] = []
    hand_grip_distances: list[float] = []
    sword_length_distances: list[float] = []
    face_pair_distances: list[float] = []
    left_hand_pair_distances: list[float] = []
    support_ball_positions: list[list[float]] = []
    sword_tip_positions: list[list[float]] = []
    left_foot_heads: list[list[float]] = []
    left_foot_tails: list[list[float]] = []
    support_boot_minima: list[dict[str, Any]] = []
    left_boot_minima: list[dict[str, Any]] = []
    body_minima: list[float] = []
    camera_frames: list[dict[str, Any]] = []
    evaluated_counts: dict[str, int] = {}
    frame_error: str | None = None
    forward_axis_record: list[float] | None = None
    from mathutils import Vector
    support_point = Vector(SUPPORT_BALL_REST)

    try:
        for frame_number in range(FRAME_START, FRAME_END + 1):
            scene.frame_set(frame_number)
            bpy.context.view_layer.update()
            depsgraph = bpy.context.evaluated_depsgraph_get()
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
                        report["errors"].append(f"{name} evaluated topology changed at frame {frame_number}.")
                    matrix_world = helpers.numpy_matrix(evaluated_obj.matrix_world, np)
                    points = helpers.transform_points(coords, matrix_world, np)
                    if not np.isfinite(points).all():
                        frame_finite = False
                        report["errors"].append(f"{name} has non-finite evaluated coordinates at frame {frame_number}.")
                        continue
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
                body_minima.append(float(body_points[:, 2].min()))
                boot_z = body_points[support_boot_ids, 2]
                min_index = int(np.argmin(boot_z))
                boot_min = float(boot_z[min_index])
                support_boot_minima.append({
                    "frame": frame_number,
                    "min_world_z_m": boot_min,
                    "vertex_index": int(support_boot_ids[min_index]),
                    "pass": boot_min >= SUPPORT_BOOT_MIN_Z_M,
                })
                if len(left_boot_ids) and max(left_boot_ids) < len(body_points):
                    left_boot_z = body_points[left_boot_ids, 2]
                    left_boot_min_index = int(np.argmin(left_boot_z))
                    left_boot_minima.append({
                        "frame": frame_number,
                        "min_world_z_m": float(left_boot_z[left_boot_min_index]),
                        "vertex_index": int(left_boot_ids[left_boot_min_index]),
                    })
                if left_hand_vertex_pair is not None and max(left_hand_vertex_pair) < len(body_points):
                    left_hand_pair_world = body_points[list(left_hand_vertex_pair)]
                    left_hand_pair_distances.append(float(np.linalg.norm(
                        left_hand_pair_world[0] - left_hand_pair_world[1]
                    )))

            hand_points = world_meshes.get("JiangRightGrip_HandGrip")
            sword_points = world_meshes.get("JiangRightGrip_Jian")
            head_points = world_meshes.get(head_name)
            if hand_points is not None and sword_points is not None and head_points is not None:
                if len(hand_points) and len(sword_points) > sword_tip_index:
                    hand_grip_distances.append(float(np.linalg.norm(hand_points[0] - sword_points[0])))
                    sword_length_distances.append(float(np.linalg.norm(
                        sword_points[sword_tip_index] - sword_points[0]
                    )))
                    face_pair_distances.append(float(np.linalg.norm(
                        head_points[face_pair[0]] - head_points[face_pair[1]]
                    )))
                    sword_tip_positions.append([float(value) for value in sword_points[sword_tip_index]])
                else:
                    frame_finite = False
                    report["errors"].append(f"Selected hand, sword, or face vertices missing at frame {frame_number}.")
            else:
                frame_finite = False
                report["errors"].append(f"One or more required evaluated meshes are missing at frame {frame_number}.")

            evaluated_rig = rig.evaluated_get(depsgraph)
            pose_bones = evaluated_rig.pose.bones
            support_bone = pose_bones.get("foot.R")
            left_bone = pose_bones.get("foot.L")
            support_world: list[float] | None = None
            left_head_world: list[float] | None = None
            left_tail_world: list[float] | None = None
            if support_bone is not None:
                armature_point = (
                    support_bone.matrix
                    @ rig.data.bones["foot.R"].matrix_local.inverted()
                    @ support_point
                )
                support_value = evaluated_rig.matrix_world @ armature_point
                support_values = [float(value) for value in support_value]
                if finite_vector(support_values, np):
                    support_world = support_values
                    support_ball_positions.append(support_values)
                else:
                    frame_finite = False
                    report["errors"].append(f"Support-ball reference is non-finite at frame {frame_number}.")
            else:
                frame_finite = False
                report["errors"].append(f"foot.R is missing at frame {frame_number}.")
            if left_bone is not None:
                left_head = evaluated_rig.matrix_world @ left_bone.head
                left_tail = evaluated_rig.matrix_world @ left_bone.tail
                left_head_values = [float(value) for value in left_head]
                left_tail_values = [float(value) for value in left_tail]
                if finite_vector(left_head_values, np) and finite_vector(left_tail_values, np):
                    left_head_world = left_head_values
                    left_tail_world = left_tail_values
                    left_foot_heads.append(left_head_world)
                    left_foot_tails.append(left_tail_world)
                else:
                    frame_finite = False
                    report["errors"].append(f"foot.L has non-finite endpoints at frame {frame_number}.")
            else:
                frame_finite = False
                report["errors"].append(f"foot.L is missing at frame {frame_number}.")

            if frame_number == FRAME_START and head_points is not None and len(face_ids) and len(rear_ids):
                direction = head_points[face_ids].mean(axis=0) - head_points[rear_ids].mean(axis=0)
                direction_norm = float(np.linalg.norm(direction))
                if direction_norm > 1.0e-8 and math.isfinite(direction_norm):
                    forward_axis = direction / direction_norm
                    forward_axis_record = [float(value) for value in forward_axis]
                else:
                    frame_finite = False
                    report["errors"].append("Could not derive a finite initial anatomical forward axis.")

            camera_frame: dict[str, Any] = {"frame": frame_number, "finite": frame_finite}
            if all_world and camera_ok:
                points_world = np.concatenate(all_world, axis=0)
                evaluated_camera = camera.evaluated_get(depsgraph)
                camera_inverse = helpers.numpy_matrix(evaluated_camera.matrix_world.inverted(), np)
                camera_points = helpers.transform_points(points_world, camera_inverse, np)
                if not np.isfinite(camera_points).all():
                    frame_finite = False
                    camera_frame.update({"finite": False, "projection_finite": False,
                                         "minimum_margin_px": None})
                    report["errors"].append(f"Camera projection is non-finite at frame {frame_number}.")
                else:
                    left, right = camera_bounds["min_x"], camera_bounds["max_x"]
                    bottom, top = camera_bounds["min_y"], camera_bounds["max_y"]
                    width, height = right - left, top - bottom
                    if width <= 0.0 or height <= 0.0:
                        raise ValueError("Orthographic camera frame is degenerate")
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
                        "clipped_or_behind_vertices": int(clipped.sum()),
                        "world_vertex_count": int(len(points_world)),
                    })
            else:
                camera_frame["minimum_margin_px"] = None
            camera_frame["finite"] = bool(frame_finite and camera_frame.get("finite", True))
            camera_frames.append(camera_frame)
            frame_records.append({
                "frame": frame_number,
                "world_bounds_by_mesh": mesh_bounds,
                "body_min_world_z_m": body_minima[-1] if body_minima else None,
                "support_boot_min_world_z_m": support_boot_minima[-1].get("min_world_z_m") if support_boot_minima else None,
                "sword_tip_world": sword_tip_positions[-1] if sword_tip_positions else None,
                "support_ball_world": support_world,
                "left_foot_head_world": left_head_world,
                "left_foot_tail_world": left_tail_world,
                "camera": camera_frame,
                "finite": frame_finite,
            })

        all_frames_ok = (
            len(frame_records) == FRAME_END
            and all(record["finite"] for record in frame_records)
            and len(body_minima) == FRAME_END
            and len(support_boot_minima) == FRAME_END
            and len(camera_frames) == FRAME_END
            and all(len(values) == FRAME_END for values in (
                hand_grip_distances, sword_length_distances, face_pair_distances,
                support_ball_positions, sword_tip_positions, left_foot_heads, left_foot_tails,
            ))
        )
        helpers.record_check(report, "all_120_frames_finite", all_frames_ok,
                             {"evaluated_frames": len(frame_records),
                              "evaluated_vertex_counts": evaluated_counts,
                              "all_coordinates_finite": all(record["finite"] for record in frame_records)},
                             "All 120 frames must evaluate finite mesh geometry, bone references, and camera projections.")
    except Exception as exc:
        frame_error = f"{type(exc).__name__}: {exc}"
        report["errors"].append(f"Frame evaluation failed: {frame_error}")
    finally:
        scene.frame_set(original_frame, subframe=original_subframe)
        bpy.context.view_layer.update()

    report["animation"]["frame_evaluation_error"] = frame_error
    report["animation"]["frames"] = frame_records
    report["animation"]["evaluated_vertex_counts"] = evaluated_counts
    try:
        report["animation"]["frame_data_sha256"] = canonical_sha256(frame_records) if frame_records else None
    except (TypeError, ValueError):
        report["animation"]["frame_data_sha256"] = None
    report["animation"]["phase_windows"] = phase_summary(sword_tip_positions, np)
    report["animation"]["forward_axis_world_frame_1"] = forward_axis_record

    hand_grip = record_distance_invariant(hand_grip_distances,
                                          "distance between JiangRightGrip_HandGrip vertex 0 and sword vertex 0")
    sword_length = record_distance_invariant(sword_length_distances,
                                             "distance between sword vertex 0 and the maximum-rest-Z tip vertex")
    face_pair = record_distance_invariant(face_pair_distances,
                                          "distance between two head-weighted front-face vertices")
    left_hand_distance = record_distance_invariant(
        left_hand_pair_distances,
        "distance between the farthest selected left-hand region vertices weighted to hand.L",
    )
    left_hand_result = {
        "weights": left_hand_weights,
        "pair_vertices": list(left_hand_vertex_pair) if left_hand_vertex_pair else None,
        "distance_invariant": left_hand_distance,
        "pass": bool(left_hand_weights.get("pass", False) and left_hand_distance["pass"]),
    }
    report["animation"]["left_hand_stability"] = left_hand_result
    helpers.record_check(report, "left_hand_rigid_to_hand_L_and_stable", left_hand_result["pass"],
                         left_hand_result,
                         "Selected left-hand vertices must be fully hand.L-weighted and retain pair distance within 1e-5 m.")
    report["animation"]["distance_invariants"] = {
        "hand_to_sword": hand_grip, "sword_length": sword_length, "front_face_pair": face_pair,
    }
    helpers.record_check(report, "hand_sword_and_face_rigid_distances", hand_grip["pass"]
                         and sword_length["pass"] and face_pair["pass"],
                         report["animation"]["distance_invariants"],
                         "Grip, sword length, and front-face pair distances must drift less than 1e-5 m.")

    if len(support_ball_positions) == FRAME_END:
        positions = np.asarray(support_ball_positions, dtype=np.float64)
        drift = np.linalg.norm(positions - positions[0], axis=1)
        maximum_index = int(np.argmax(drift))
        ball_result = {
            "formula": "pose_bone.matrix @ rest_bone.matrix_local.inverted() @ rest_reference",
            "rest_armature_point": list(SUPPORT_BALL_REST),
            "frame_1_world": [float(value) for value in positions[0]],
            "maximum_world_drift_m": float(drift[maximum_index]),
            "maximum_drift_frame": maximum_index + 1,
            "threshold_m": INVARIANT_TOLERANCE_M,
            "pass": float(drift[maximum_index]) < INVARIANT_TOLERANCE_M,
        }
    else:
        ball_result = {"samples": len(support_ball_positions),
                       "threshold_m": INVARIANT_TOLERANCE_M, "pass": False}
    report["animation"]["right_support_ball"] = ball_result
    helpers.record_check(report, "right_support_ball_fixed", ball_result["pass"], ball_result,
                         "Right foot ball reference must remain fixed; ankle movement is allowed.")

    if len(left_foot_heads) == FRAME_END and len(left_foot_tails) == FRAME_END:
        heads = np.asarray(left_foot_heads, dtype=np.float64)
        tails = np.asarray(left_foot_tails, dtype=np.float64)
        maximum_head_lift = float((heads[:, 2] - heads[0, 2]).max())
        maximum_toe_lift = float((tails[:, 2] - tails[0, 2]).max())
        forward_end = None
        if forward_axis_record is not None:
            forward_axis = np.asarray(forward_axis_record, dtype=np.float64)
            forward_end = float(np.einsum("i,i->", tails[-1] - tails[0], forward_axis,
                                          optimize=False))
        foot_result = {
            "frame_1_ankle_head_world": [float(value) for value in heads[0]],
            "frame_120_ankle_head_world": [float(value) for value in heads[-1]],
            "frame_1_toe_tail_world": [float(value) for value in tails[0]],
            "frame_120_toe_tail_world": [float(value) for value in tails[-1]],
            "maximum_ankle_head_lift_m": maximum_head_lift,
            "maximum_toe_tail_lift_m": maximum_toe_lift,
            "maximum_lift_m": max(maximum_head_lift, maximum_toe_lift),
            "minimum_lift_required_m": LEFT_FOOT_LIFT_MIN_M,
            "frame_120_forward_displacement_m": forward_end,
            "minimum_forward_displacement_required_m": LEFT_FOOT_FORWARD_MIN_M,
            "forward_axis_world": forward_axis_record,
            "pass": max(maximum_head_lift, maximum_toe_lift) > LEFT_FOOT_LIFT_MIN_M
            and forward_end is not None and forward_end > LEFT_FOOT_FORWARD_MIN_M,
        }
    else:
        foot_result = {"ankle_samples": len(left_foot_heads), "toe_samples": len(left_foot_tails), "pass": False}
    report["animation"]["left_step"] = foot_result
    helpers.record_check(report, "left_step_lifts_and_finishes_forward", foot_result["pass"], foot_result,
                         "Left foot must lift more than 0.04 m and finish more than 0.10 m forward of its start.")

    if len(sword_tip_positions) == FRAME_END:
        tips = np.asarray(sword_tip_positions, dtype=np.float64)
        displacements = np.linalg.norm(tips - tips[0], axis=1)
        peak_height_index = int(np.argmax(tips[:, 2]))
        maximum_displacement = float(displacements.max())
        total_path = float(np.linalg.norm(np.diff(tips, axis=0), axis=1).sum())
        rise = float(tips[:, 2].max() - tips[0, 2])
        fall = float(tips[peak_height_index, 2] - tips[-1, 2])
        sword_motion = {
            "rest_local_tip": sword_tip_rest,
            "frame_1_world_tip": [float(value) for value in tips[0]],
            "peak_height_world_tip": [float(value) for value in tips[peak_height_index]],
            "frame_120_world_tip": [float(value) for value in tips[-1]],
            "maximum_displacement_from_frame_1_m": maximum_displacement,
            "cumulative_path_length_m": total_path,
            "peak_height_frame": peak_height_index + 1,
            "rise_above_frame_1_m": rise,
            "fall_from_peak_to_frame_120_m": fall,
            "minimum_displacement_required_m": SWORD_MAX_DISPLACEMENT_MIN_M,
            "minimum_rise_required_m": SWORD_RISE_MIN_M,
            "minimum_fall_required_m": SWORD_FALL_MIN_M,
            "pass": maximum_displacement > SWORD_MAX_DISPLACEMENT_MIN_M
            and rise > SWORD_RISE_MIN_M and fall > SWORD_FALL_MIN_M,
            "semantics": "rise is peak tip world Z above frame 1; fall is peak tip world Z above frame 120",
        }
    else:
        sword_motion = {"samples": len(sword_tip_positions), "pass": False}
    report["animation"]["sword_tip_motion"] = sword_motion
    helpers.record_check(report, "sword_tip_motion_has_rise_and_fall", sword_motion["pass"], sword_motion,
                         "Sword tip must move over 0.35 m, rise over 0.15 m, then fall over 0.20 m by frame 120.")

    boot_pass = len(support_boot_minima) == FRAME_END and all(
        item["min_world_z_m"] >= SUPPORT_BOOT_MIN_Z_M for item in support_boot_minima
    )
    worst_boot = min(support_boot_minima, key=lambda item: item["min_world_z_m"], default=None)
    report["animation"]["right_support_boot_min_z"] = {
        "threshold_m": SUPPORT_BOOT_MIN_Z_M,
        "per_frame": support_boot_minima,
        "worst": worst_boot,
        "pass": boot_pass,
        "semantics": "minimum world Z among rest z<0.2 m body vertices fully weighted to foot.R",
    }
    helpers.record_check(report, "right_support_boot_stays_above_floor_tolerance", boot_pass,
                         {"threshold_m": SUPPORT_BOOT_MIN_Z_M, "worst": worst_boot,
                          "samples": len(support_boot_minima)},
                         "Right support-boot minimum world Z must remain at or above -0.008 m in every frame.")

    left_boot_all_above = (
        len(left_boot_minima) == FRAME_END
        and all(item["min_world_z_m"] >= SUPPORT_BOOT_MIN_Z_M for item in left_boot_minima)
    )
    final_left_boot = left_boot_minima[-1] if len(left_boot_minima) == FRAME_END else None
    left_boot_landing_pass = (
        left_boot_all_above and final_left_boot is not None
        and abs(final_left_boot["min_world_z_m"]) <= LEFT_BOOT_FINAL_MAX_ABS_Z_M
    )
    left_boot_landing = {
        "selection": "rest JiangFullbody vertices with x>=0, z<0.2 m, and 100% foot.L weight",
        "selected_vertex_count": int(len(left_boot_ids)),
        "thresholds_m": {
            "all_frame_minimum_z_at_least": SUPPORT_BOOT_MIN_Z_M,
            "final_frame_minimum_z_absolute_at_most": LEFT_BOOT_FINAL_MAX_ABS_Z_M,
        },
        "per_frame_minima": left_boot_minima,
        "final_frame": final_left_boot,
        "worst_minimum": min(left_boot_minima, key=lambda item: item["min_world_z_m"], default=None),
        "all_frames_above_floor_tolerance": left_boot_all_above,
        "pass": left_boot_landing_pass,
        "semantics": "Positive final min Z is allowed up to 0.008 m; no selected left-boot vertex may fall below -0.008 m.",
    }
    report["animation"]["left_boot_final_landing"] = left_boot_landing
    helpers.record_check(report, "left_boot_lands_at_final_frame", left_boot_landing_pass,
                         left_boot_landing,
                         "Selected left-boot minimum Z must stay at least -0.008 m throughout and finish within +/-0.008 m of zero.")

    valid_camera = [item for item in camera_frames if item.get("minimum_margin_px") is not None]
    camera_pass = (len(valid_camera) == FRAME_END
                   and all(item["minimum_margin_px"] > helpers.CAMERA_MARGIN_MIN_PX for item in valid_camera)
                   and all(item.get("clipped_or_behind_vertices") == 0 for item in valid_camera))
    worst_camera = min(valid_camera, key=lambda item: item["minimum_margin_px"], default=None)
    report["camera_review"].update({
        "frame_count": len(camera_frames),
        "valid_margin_frame_count": len(valid_camera),
        "minimum_margin_px": worst_camera.get("minimum_margin_px") if worst_camera else None,
        "minimum_margin_frame": worst_camera.get("frame") if worst_camera else None,
        "threshold_px_strictly_greater_than": helpers.CAMERA_MARGIN_MIN_PX,
        "per_frame": camera_frames,
        "pass": camera_pass,
    })
    helpers.record_check(report, "all_meshes_inside_camera_margins", camera_pass,
                         {key: value for key, value in report["camera_review"].items() if key != "per_frame"},
                         "Every evaluated mesh vertex must remain more than 16 px inside the camera frame and unclipped.")

    report["animation"]["body_min_world_z_range"] = {
        "minimum_of_frame_minima_m": min(body_minima) if body_minima else None,
        "maximum_of_frame_minima_m": max(body_minima) if body_minima else None,
        "frame_1_minimum_m": body_minima[0] if body_minima else None,
        "semantics": "full-body mesh vertex minima; not an exact ground-contact assertion",
    }
    report["status"] = "PASS" if not report["errors"] else "FAIL"
    report["summary"] = {
        "checks_passed": sum(item["status"] == "PASS" for item in report["checks"].values()),
        "checks_failed": sum(item["status"] == "FAIL" for item in report["checks"].values()),
        "error_count": len(report["errors"]),
        "visual_review": "not performed by this verifier",
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
        helpers, refined = load_helpers()
        report_path = helpers.validate_report_destination(args.report)
    except Exception as exc:
        parser.error(str(exc))
    try:
        baseline, baseline_path, baseline_hash = read_baseline(args.baseline_report, helpers)
    except Exception as exc:
        failure = {
            "status": "FAIL", "report_path": str(report_path),
            "errors": [f"Could not read baseline report: {type(exc).__name__}: {exc}"],
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
        report = verify_phrase(bpy, np, helpers, refined, report_path,
                               baseline, baseline_path, baseline_hash)
    except Exception as exc:
        report = {
            "status": "FAIL", "report_path": str(report_path),
            "baseline_report_path": str(baseline_path),
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
