#!/usr/bin/env python3
"""Read-only verifier for the saved Jiang sword action and idle cycles.

Example::

    blender --background --disable-autoexec --threads 4 --python \
        /abs/path/verify_sword_cycle.py -- --action /abs/action.blend \
        --idle /abs/idle.blend --approved /abs/approved.blend \
        --baseline-report /abs/verification-v1.json --report /abs/new-report.json

The script opens the approved file, action, and idle sequentially. It never
saves or renders a Blender file. Each scene's original current frame is
restored after evaluation. The report validates structure, palette identity,
evaluated geometry, motion invariants, and camera margins; it does not replace
visual review.
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
APPROVED_FRAME_END = 120
ACTION_FRAME_END = 180
IDLE_FRAME_END = 60
CUT_FRAMES = range(46, 59)
EXPECTED_APPROVED_SHA256 = "9aa7c926103f58b664427b2400601001562ff9a436b153c9b46d0c9241de6e65"
EXPECTED_TEXTURE_COUNT = 6
EXPECTED_TEXTURE_SIZE = (4096, 4096)
WEIGHT_TOLERANCE = 0.001
RIGID_DISTANCE_TOLERANCE_M = 1.0e-5
BOUNDARY_GEOMETRY_TOLERANCE_M = 1.0e-6
SUPPORT_BALL_TOLERANCE_M = 0.004
BOOT_FLOOR_TOLERANCE_M = -0.008
FINAL_SOLE_TOLERANCE_M = 0.008
LEFT_LIFT_MIN_M = 0.04
LEFT_FORWARD_MIN_M = 0.10
CAMERA_MARGIN_MIN_PX = 16.0
SUPPORT_BALL_REST = (-0.19, -0.22, 0.006)
FACE_Y_MAX = 0.05
FACE_Z_MIN = 1.7
REAR_HAIR_Y_MIN = 0.12
REAR_HAIR_Z_MIN = 1.35
BOOT_REST_Z_MAX = 0.20
LEFT_HAND_WRIST_REST = (0.435, -0.15, 1.02)
LEFT_HAND_DIRECTION_POINT = (0.46, -0.16, 0.91)
LEFT_HAND_RADIAL_MAX_M = 0.105
LEFT_HAND_LENGTH_MAX_M = 0.235
LEFT_HAND_MIN_AXIAL_M = 0.04
REQUIRED_MESHES = (
    "JiangFullbody",
    "JiangApprovedHead",
    "JiangRightGrip_HandGrip",
    "JiangRightGrip_Jian",
)
REQUIRED_RIG = "JiangRig"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--action", required=True, type=Path,
                        help="absolute path to the new 180-frame action .blend")
    parser.add_argument("--idle", required=True, type=Path,
                        help="absolute path to the new 60-frame idle .blend")
    parser.add_argument("--approved", required=True, type=Path,
                        help="absolute path to the approved warm v4 .blend")
    parser.add_argument("--baseline-report", required=True, type=Path,
                        help="absolute path to the passing warm v4 verification-v1.json")
    parser.add_argument("--report", required=True, type=Path,
                        help="absolute path for a new JSON report")
    return parser


def script_args(argv: list[str]) -> list[str]:
    if "--" in argv:
        return argv[argv.index("--") + 1:]
    return argv[1:]


def load_module(name: str, path: Path) -> Any:
    if not path.is_file():
        raise FileNotFoundError(f"Required verifier helper is missing: {path}")
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load verifier helper from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_helpers() -> tuple[Any, Any, Any]:
    sys.dont_write_bytecode = True
    directory = Path(__file__).resolve().parent
    phrase = load_module("jiang_sword_phrase_helpers", directory / "verify_sword_phrase.py")
    base, refined = phrase.load_helpers()
    return phrase, base, refined


def canonical_sha256(value: Any) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"),
                         ensure_ascii=False, allow_nan=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def finite(values: Any, np: Any) -> bool:
    return bool(np.isfinite(np.asarray(values, dtype=np.float64)).all())


def normalize_input_path(path: Path, label: str, suffix: str) -> Path:
    if not path.is_absolute():
        raise ValueError(f"--{label} must be an absolute path")
    raw = path.expanduser()
    if raw.is_symlink():
        raise ValueError(f"--{label} must not be a symlink: {raw}")
    resolved = raw.resolve(strict=True)
    if not resolved.is_file() or resolved.suffix.lower() != suffix:
        raise ValueError(f"--{label} must name an existing {suffix} file: {resolved}")
    return resolved


def json_plain(value: Any) -> Any:
    """Convert Blender RNA and math values to deterministic JSON primitives."""
    if value is None or isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("non-finite value in saved palette signature")
        return float(value)
    if hasattr(value, "name_full") or hasattr(value, "name"):
        name = getattr(value, "name_full", getattr(value, "name", None))
        if isinstance(name, str):
            return {"id_type": type(value).__name__, "name": name}
    if hasattr(value, "to_tuple"):
        return [json_plain(item) for item in value.to_tuple()]
    try:
        return [json_plain(item) for item in value]
    except (TypeError, AttributeError):
        return str(value)


def semantic_rna_properties(value: Any, excluded: set[str]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    rna = getattr(value, "bl_rna", None)
    if rna is None:
        return result
    for prop in rna.properties:
        identifier = str(prop.identifier)
        if identifier in excluded or prop.type not in {"BOOLEAN", "INT", "FLOAT", "STRING", "ENUM"}:
            continue
        try:
            current = getattr(value, identifier)
            result[identifier] = json_plain(current)
        except (AttributeError, TypeError, ValueError, RuntimeError):
            continue
    return result


NODE_UI_PROPERTIES = {
    "rna_type", "name", "label", "location", "width", "height", "select",
    "show_options", "show_preview", "show_texture", "use_custom_color", "color",
    "parent", "inputs", "outputs", "internal_links", "dimensions", "node_tree",
    "image", "bl_idname", "type",
}
MATERIAL_UI_PROPERTIES = {
    "rna_type", "name", "name_full", "users", "use_fake_user", "node_tree",
    "library", "library_weak_reference", "override_library", "preview", "session_uid",
}


def socket_record(socket: Any) -> dict[str, Any]:
    record: dict[str, Any] = {
        "name": str(socket.name),
        "identifier": str(getattr(socket, "identifier", socket.name)),
        "type": str(getattr(socket, "type", "")),
        "enabled": bool(getattr(socket, "enabled", True)),
        "hide_value": bool(getattr(socket, "hide_value", False)),
    }
    if hasattr(socket, "default_value"):
        record["default_value"] = json_plain(socket.default_value)
    if hasattr(socket, "default_input"):
        record["default_input"] = json_plain(socket.default_input)
    return record


def node_tree_record(tree: Any, visited: set[str] | None = None) -> dict[str, Any]:
    if visited is None:
        visited = set()
    tree_name = str(getattr(tree, "name", ""))
    if tree_name in visited:
        return {"name": tree_name, "recursive_reference": True}
    visited.add(tree_name)

    nodes: list[dict[str, Any]] = []
    for node in sorted(tree.nodes, key=lambda item: (str(item.name), str(item.bl_idname))):
        item: dict[str, Any] = {
            "name": str(node.name),
            "type": str(node.bl_idname),
            "label": str(node.label),
            "properties": semantic_rna_properties(node, NODE_UI_PROPERTIES),
            "inputs": [socket_record(socket) for socket in node.inputs],
            "outputs": [socket_record(socket) for socket in node.outputs],
        }
        if hasattr(node, "image"):
            image = node.image
            item["image"] = getattr(image, "name", None) if image is not None else None
        child_tree = getattr(node, "node_tree", None)
        if child_tree is not None:
            item["node_tree"] = node_tree_record(child_tree, visited)
        nodes.append(item)

    links = []
    for link in tree.links:
        links.append({
            "from_node": str(link.from_node.name),
            "from_socket": str(getattr(link.from_socket, "identifier", link.from_socket.name)),
            "from_socket_name": str(link.from_socket.name),
            "to_node": str(link.to_node.name),
            "to_socket": str(getattr(link.to_socket, "identifier", link.to_socket.name)),
            "to_socket_name": str(link.to_socket.name),
            "is_valid": bool(getattr(link, "is_valid", True)),
        })
    links.sort(key=lambda item: (item["from_node"], item["from_socket"],
                                 item["to_node"], item["to_socket"]))
    return {"name": tree_name, "type": str(getattr(tree, "bl_idname", "")),
            "nodes": nodes, "links": links}


def material_signature(bpy: Any) -> tuple[dict[str, Any], str]:
    materials: list[dict[str, Any]] = []
    for material in sorted(bpy.data.materials, key=lambda item: item.name):
        record: dict[str, Any] = {
            "name": str(material.name),
            "properties": semantic_rna_properties(material, MATERIAL_UI_PROPERTIES),
            "diffuse_color": json_plain(material.diffuse_color),
            "use_nodes": bool(material.use_nodes),
        }
        if material.node_tree is not None:
            record["node_tree"] = node_tree_record(material.node_tree)
        materials.append(record)
    payload = {"materials": materials}
    return payload, canonical_sha256(payload)


def uv_record(mesh: Any, np: Any) -> dict[str, Any]:
    layers: list[dict[str, Any]] = []
    finite_uvs = True
    for index, layer in enumerate(mesh.uv_layers):
        raw = np.empty(len(layer.data) * 2, dtype=np.float32)
        if len(layer.data):
            layer.data.foreach_get("uv", raw)
        values = raw.reshape((-1, 2))
        finite_uvs = finite_uvs and bool(np.isfinite(values).all())
        digest = hashlib.sha256()
        digest.update(np.asarray([len(values)], dtype="<u8").tobytes())
        digest.update(values.astype("<f4", copy=False).tobytes(order="C"))
        layers.append({"index": index, "name": str(layer.name), "loops": len(values),
                       "sha256": digest.hexdigest(), "finite": bool(np.isfinite(values).all())})
    payload = {"active_index": int(mesh.uv_layers.active_index), "layers": layers}
    return {**payload, "sha256": canonical_sha256(payload), "finite": finite_uvs}


def weights_record(obj: Any, np: Any, refined: Any) -> tuple[dict[str, Any], Any]:
    groups = sorted((str(group.name), int(group.index)) for group in obj.vertex_groups)
    names = [name for name, _ in groups]
    index_to_column = {index: column for column, (_, index) in enumerate(groups)}
    matrix = np.zeros((len(obj.data.vertices), len(groups)), dtype=np.float32)
    for vertex in obj.data.vertices:
        for assignment in vertex.groups:
            column = index_to_column.get(int(assignment.group))
            if column is not None:
                matrix[int(vertex.index), column] = float(assignment.weight)
    sums, _matrix, _indices = refined.weight_sum_record(obj, np, WEIGHT_TOLERANCE)
    payload = {"groups": names, "vertices": len(obj.data.vertices)}
    digest = hashlib.sha256()
    digest.update(json.dumps(payload, sort_keys=True, separators=(",", ":"),
                             ensure_ascii=False).encode("utf-8"))
    digest.update(matrix.astype("<f4", copy=False).tobytes(order="C"))
    return {
        "group_names": names,
        "vertices": len(obj.data.vertices),
        "sha256": digest.hexdigest(),
        "finite": bool(np.isfinite(matrix).all()),
        "normalized": sums,
    }, matrix


def color_attribute_record(obj: Any, np: Any) -> dict[str, Any]:
    attributes: list[dict[str, Any]] = []
    named: dict[str, dict[str, Any]] = {}
    for attribute in sorted(obj.data.color_attributes, key=lambda item: item.name):
        count = len(attribute.data)
        record: dict[str, Any] = {
            "name": str(attribute.name),
            "domain": str(attribute.domain),
            "data_type": str(attribute.data_type),
            "count": count,
        }
        if attribute.data_type == "FLOAT_COLOR":
            values = np.empty(count * 4, dtype=np.float32)
            if count:
                attribute.data.foreach_get("color", values)
            array = values.reshape((-1, 4))
            record["finite"] = bool(np.isfinite(array).all())
            digest = hashlib.sha256()
            digest.update(array.astype("<f4", copy=False).tobytes(order="C"))
            record["values_sha256"] = digest.hexdigest()
        else:
            # The approved warm source uses FLOAT_COLOR. Preserve a deterministic
            # signature for other color-attribute encodings if any are present.
            values = [json_plain(getattr(item, "color", getattr(item, "color_srgb", None)))
                      for item in attribute.data]
            record["values_sha256"] = canonical_sha256(values)
            record["finite"] = True
        attributes.append(record)
        if attribute.name == "JiangWarmGain":
            named[attribute.name] = record
    return {"attributes": attributes, "jiang_warm_gain": named.get("JiangWarmGain")}


def baseline_report_check(data: dict[str, Any], approved_sha: str) -> dict[str, Any]:
    summary = data.get("summary", {})
    source = data.get("source", {})
    recorded_sha = source.get("saved_blend_sha256") if isinstance(source, dict) else None
    passed = (
        data.get("status") == "PASS"
        and isinstance(summary, dict)
        and summary.get("checks_passed") == 27
        and summary.get("checks_failed") == 0
        and recorded_sha == approved_sha == EXPECTED_APPROVED_SHA256
    )
    return {
        "pass": passed,
        "status": data.get("status"),
        "checks_passed": summary.get("checks_passed") if isinstance(summary, dict) else None,
        "checks_failed": summary.get("checks_failed") if isinstance(summary, dict) else None,
        "report_saved_blend_sha256": recorded_sha,
        "approved_blend_sha256": approved_sha,
        "required_approved_sha256": EXPECTED_APPROVED_SHA256,
    }


def collect_static_snapshot(bpy: Any, np: Any, helpers: Any, phrase: Any,
                             refined: Any, path: Path, role: str,
                             expected_end: int) -> dict[str, Any]:
    """Inspect one loaded project at its saved frame 1 without changing it."""
    scene = bpy.context.scene
    if scene is None:
        raise RuntimeError(f"{role}: no active scene")
    scene_objects = list(scene.objects)
    scene_mesh_names = sorted(obj.name for obj in scene_objects if obj.type == "MESH")
    global_mesh_names = sorted(obj.name for obj in bpy.data.objects if obj.type == "MESH")
    meshes = {name: bpy.data.objects.get(name) for name in REQUIRED_MESHES}
    meshes = {name: obj for name, obj in meshes.items()
              if obj is not None and obj.type == "MESH" and obj in scene_objects}
    scene_meshes_ok = (
        scene_mesh_names == sorted(REQUIRED_MESHES)
        and global_mesh_names == sorted(REQUIRED_MESHES)
        and set(meshes) == set(REQUIRED_MESHES)
    )

    armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    rig = bpy.data.objects.get(REQUIRED_RIG)
    rig_ok = (
        len(armatures) == 1 and len(bpy.data.armatures) == 1
        and rig is not None and rig.type == "ARMATURE" and rig in scene_objects
        and len(rig.data.bones) == 22
    )
    bone_record: dict[str, Any] = {"bone_count": 0, "bones": [], "sha256": None, "finite": False}
    if rig is not None and rig.type == "ARMATURE":
        bone_record, _ = phrase.bone_rest_record(rig, np)

    camera = scene.camera
    camera_info, camera_hash, camera_frame, camera_bounds, resolution = phrase.camera_record(scene, camera, np)
    camera_ok = (
        camera is not None and camera.type == "CAMERA" and camera.data.type == "ORTHO"
        and camera_bounds is not None and camera_hash is not None
    )

    texture_records: list[dict[str, Any]] = []
    texture_errors: list[str] = []
    for image in bpy.data.images:
        if image.type == "RENDER_RESULT" or image.name == "Render Result":
            continue
        try:
            texture_records.append(helpers.texture_record(image))
        except Exception as exc:
            texture_errors.append(f"{image.name}: {type(exc).__name__}: {exc}")
    texture_records.sort(key=lambda item: item.get("name", ""))

    meshes_record: dict[str, Any] = {}
    rest_coords: dict[str, Any] = {}
    weight_arrays: dict[str, Any] = {}
    weights_ok = True
    geometry_ok = True
    uv_ok = True
    palette_attributes_ok = True
    for name, obj in meshes.items():
        geometry, coordinates = helpers.rest_geometry_record(obj.data, np)
        uv = uv_record(obj.data, np)
        weights, matrix = weights_record(obj, np, refined)
        attributes = color_attribute_record(obj, np)
        meshes_record[name] = {
            "data_name": str(obj.data.name),
            "rest_geometry": geometry,
            "uv": uv,
            "vertex_groups": [str(group.name) for group in obj.vertex_groups],
            "weights": weights,
            "color_attributes": attributes,
            "materials": [material.name if material else None for material in obj.data.materials],
        }
        rest_coords[name] = coordinates
        weight_arrays[name] = matrix
        geometry_ok = geometry_ok and bool(geometry.get("coordinates_finite"))
        uv_ok = uv_ok and uv["finite"]
        weights_ok = weights_ok and weights["finite"] and weights["normalized"]["pass"]

    # Warm v4 authors this POINT color attribute on the head and body.
    warm_gain_ok = True
    warm_gain_records: dict[str, Any] = {}
    for name in ("JiangApprovedHead", "JiangFullbody"):
        item = meshes_record.get(name, {}).get("color_attributes", {}).get("jiang_warm_gain")
        warm_gain_records[name] = item
        warm_gain_ok = warm_gain_ok and bool(
            item and item.get("domain") == "POINT" and item.get("data_type") == "FLOAT_COLOR"
            and item.get("count") == len(rest_coords.get(name, [])) and item.get("finite")
        )
    palette_attributes_ok = warm_gain_ok

    materials, material_hash = material_signature(bpy)
    blend_hash = helpers.sha256_file(path)
    scene_info = {
        "name": str(scene.name),
        "frame_start": int(scene.frame_start),
        "frame_end": int(scene.frame_end),
        "fps": int(scene.render.fps),
        "fps_base": float(scene.render.fps_base),
        "resolution": resolution,
        "saved_current_frame": int(scene.frame_current),
    }
    timing_ok = (
        scene.frame_start == 1 and scene.frame_end == expected_end
        and scene.render.fps == FPS and abs(float(scene.render.fps_base) - 1.0) <= 1.0e-8
    )
    text_objects = [obj.name for obj in bpy.data.objects if obj.type == "FONT"]
    text_curves = [curve.name for curve in bpy.data.curves if curve.type == "FONT"]
    drivers = helpers.find_drivers(bpy)

    return {
        "role": role,
        "path": str(path),
        "saved_blend_sha256": blend_hash,
        "scene": scene_info,
        "timing_pass": timing_ok,
        "mesh_names": {"scene": scene_mesh_names, "all_project": global_mesh_names,
                       "exact_four_expected": scene_meshes_ok},
        "rig": {"name": rig.name if rig else None,
                "object_count": len(armatures), "data_count": len(bpy.data.armatures),
                "bones": bone_record, "pass": rig_ok and bone_record["finite"]},
        "camera": {"record": camera_info, "sha256": camera_hash,
                   "frame_bounds": camera_bounds, "resolution": resolution, "pass": camera_ok},
        "textures": texture_records,
        "texture_errors": texture_errors,
        "texture_pass": (
            len(texture_records) == EXPECTED_TEXTURE_COUNT
            and not texture_errors
            and all(tuple(item["size"]) == EXPECTED_TEXTURE_SIZE and item["packed"]
                    and item["packed_sha256"] for item in texture_records)
        ),
        "meshes": meshes_record,
        "geometry_pass": len(rest_coords) == 4 and geometry_ok,
        "uv_pass": len(meshes_record) == 4 and uv_ok,
        "weights_pass": len(weight_arrays) == 4 and weights_ok,
        "warm_gain": warm_gain_records,
        "warm_gain_pass": palette_attributes_ok,
        "materials": materials,
        "material_signature_sha256": material_hash,
        "text_objects": text_objects,
        "text_curves": text_curves,
        "drivers": drivers,
        "no_text_or_drivers": not text_objects and not text_curves and not drivers,
        "private": {
            "meshes": meshes,
            "rest_coords": rest_coords,
            "weight_arrays": weight_arrays,
            "rig_object": rig,
            "camera_object": camera,
            "camera_frame": camera_frame,
            "camera_bounds": camera_bounds,
            "resolution": resolution,
        },
    }


def add_check(report: dict[str, Any], helpers: Any, name: str, passed: bool,
              evidence: Any, failure: str) -> None:
    helpers.record_check(report, name, bool(passed), evidence, failure)


def rest_comparison(candidate: dict[str, Any], approved: dict[str, Any]) -> dict[str, Any]:
    geometry: dict[str, Any] = {}
    uv: dict[str, Any] = {}
    weights: dict[str, Any] = {}
    for name in REQUIRED_MESHES:
        left = candidate["meshes"].get(name, {})
        right = approved["meshes"].get(name, {})
        candidate_geometry = left.get("rest_geometry", {}).get("rest_geometry_sha256")
        approved_geometry = right.get("rest_geometry", {}).get("rest_geometry_sha256")
        geometry[name] = {"candidate": candidate_geometry, "approved": approved_geometry,
                          "pass": candidate_geometry == approved_geometry}
        candidate_uv = left.get("uv", {}).get("sha256")
        approved_uv = right.get("uv", {}).get("sha256")
        uv[name] = {"candidate": candidate_uv, "approved": approved_uv,
                    "pass": candidate_uv == approved_uv}
        candidate_weights = left.get("weights", {}).get("sha256")
        approved_weights = right.get("weights", {}).get("sha256")
        weights[name] = {"candidate": candidate_weights, "approved": approved_weights,
                         "pass": candidate_weights == approved_weights}
    texture_candidate = {item["name"]: item.get("packed_sha256") for item in candidate["textures"]}
    texture_approved = {item["name"]: item.get("packed_sha256") for item in approved["textures"]}
    return {
        "geometry": geometry,
        "uv": uv,
        "weights": weights,
        "textures": {"candidate": texture_candidate, "approved": texture_approved,
                     "pass": texture_candidate == texture_approved},
        "bones": {"candidate": candidate["rig"]["bones"].get("sha256"),
                  "approved": approved["rig"]["bones"].get("sha256"),
                  "pass": candidate["rig"]["bones"].get("sha256") == approved["rig"]["bones"].get("sha256")},
        "camera": {"candidate": candidate["camera"].get("sha256"),
                   "approved": approved["camera"].get("sha256"),
                   "pass": candidate["camera"].get("sha256") == approved["camera"].get("sha256")},
        "materials": {"candidate": candidate.get("material_signature_sha256"),
                      "approved": approved.get("material_signature_sha256"),
                      "pass": candidate.get("material_signature_sha256") == approved.get("material_signature_sha256")},
        "JiangWarmGain": {
            "candidate": candidate.get("warm_gain"), "approved": approved.get("warm_gain"),
            "pass": candidate.get("warm_gain") == approved.get("warm_gain")
            and candidate.get("warm_gain_pass") and approved.get("warm_gain_pass"),
        },
    }


def compare_boundary_geometry(first: dict[str, Any], second: dict[str, Any], np: Any) -> dict[str, Any]:
    per_mesh: dict[str, Any] = {}
    all_pass = True
    for name in REQUIRED_MESHES:
        a = first.get(name)
        b = second.get(name)
        if a is None or b is None or a.shape != b.shape or not finite(a, np) or not finite(b, np):
            per_mesh[name] = {"pass": False, "reason": "missing, different topology, or non-finite geometry"}
            all_pass = False
            continue
        maximum = float(np.max(np.abs(a - b))) if a.size else 0.0
        digest_a = hashlib.sha256(np.asarray(a, dtype="<f8").tobytes(order="C")).hexdigest()
        digest_b = hashlib.sha256(np.asarray(b, dtype="<f8").tobytes(order="C")).hexdigest()
        passed = maximum <= BOUNDARY_GEOMETRY_TOLERANCE_M
        per_mesh[name] = {
            "vertices": int(len(a)), "first_sha256": digest_a, "second_sha256": digest_b,
            "maximum_absolute_coordinate_delta_m": maximum,
            "tolerance_m": BOUNDARY_GEOMETRY_TOLERANCE_M, "pass": passed,
        }
        all_pass = all_pass and passed
    return {"per_mesh": per_mesh, "pass": all_pass}


def matrix_delta(first: dict[str, Any], second: dict[str, Any], np: Any) -> dict[str, Any]:
    names_first = set(first)
    names_second = set(second)
    if names_first != names_second or not names_first:
        return {"bone_count_first": len(names_first), "bone_count_second": len(names_second), "pass": False}
    maximum = 0.0
    maximum_bone = None
    for name in sorted(names_first):
        a = np.asarray(first[name], dtype=np.float64)
        b = np.asarray(second[name], dtype=np.float64)
        if a.shape != (4, 4) or b.shape != (4, 4) or not finite(a, np) or not finite(b, np):
            return {"bone": name, "pass": False, "reason": "invalid pose matrix"}
        delta = float(np.max(np.abs(a - b)))
        if delta > maximum:
            maximum = delta
            maximum_bone = name
    return {"bone_count": len(names_first), "maximum_absolute_matrix_delta": maximum,
            "maximum_delta_bone": maximum_bone, "tolerance": RIGID_DISTANCE_TOLERANCE_M,
            "pass": maximum < RIGID_DISTANCE_TOLERANCE_M}


def invariant_record(values: list[float], meaning: str, tolerance: float) -> dict[str, Any]:
    valid = len(values) > 0 and all(math.isfinite(value) for value in values)
    maximum = None
    if valid:
        maximum = max(abs(value - values[0]) for value in values)
    return {"samples": len(values), "meaning": meaning,
            "maximum_absolute_drift_m": maximum, "tolerance_m": tolerance,
            "pass": bool(valid and maximum is not None and maximum < tolerance)}


def frame_camera_metrics(points_world: Any, camera: Any, depsgraph: Any,
                         bounds: Any, resolution: list[int], helpers: Any,
                         np: Any) -> dict[str, Any]:
    if camera is None or camera.type != "CAMERA" or camera.data.type != "ORTHO" or bounds is None:
        return {"finite": False, "minimum_margin_px": None, "pass": False}
    evaluated_camera = camera.evaluated_get(depsgraph)
    inverse = helpers.numpy_matrix(evaluated_camera.matrix_world.inverted(), np)
    camera_points = helpers.transform_points(points_world, inverse, np)
    if not finite(camera_points, np):
        return {"finite": False, "minimum_margin_px": None, "pass": False}
    left, right = bounds["min_x"], bounds["max_x"]
    bottom, top = bounds["min_y"], bounds["max_y"]
    width, height = right - left, top - bottom
    if width <= 0.0 or height <= 0.0:
        return {"finite": False, "minimum_margin_px": None, "pass": False}
    horizontal = (camera_points[:, 0] - left) / width * resolution[0]
    vertical = (camera_points[:, 1] - bottom) / height * resolution[1]
    margins = {
        "left": float(horizontal.min()),
        "right": float((resolution[0] - horizontal).min()),
        "bottom": float(vertical.min()),
        "top": float((resolution[1] - vertical).min()),
    }
    depth = -camera_points[:, 2]
    clipped = (depth < float(camera.data.clip_start)) | (depth > float(camera.data.clip_end))
    minimum = float(min(margins.values()))
    return {
        "finite": True,
        "side_margins_px": margins,
        "minimum_margin_px": minimum,
        "depth_range_m": [float(depth.min()), float(depth.max())],
        "clipped_or_behind_vertex_count": int(clipped.sum()),
        "world_vertex_count": int(len(points_world)),
        "pass": minimum > CAMERA_MARGIN_MIN_PX and int(clipped.sum()) == 0,
    }


def evaluate_clip(bpy: Any, np: Any, helpers: Any, refined: Any,
                  snapshot: dict[str, Any], role: str,
                  frame_end: int) -> dict[str, Any]:
    scene = bpy.context.scene
    rig = snapshot["private"]["rig_object"]
    camera = snapshot["private"]["camera_object"]
    rest_coords = snapshot["private"]["rest_coords"]
    weight_arrays = snapshot["private"]["weight_arrays"]
    meshes = snapshot["private"]["meshes"]
    camera_bounds = snapshot["private"]["camera_bounds"]
    resolution = snapshot["private"]["resolution"]
    if scene is None or rig is None or camera is None or len(meshes) != 4:
        raise RuntimeError(f"{role}: cannot evaluate without the four meshes, rig, and camera")

    head = rest_coords["JiangApprovedHead"]
    body = rest_coords["JiangFullbody"]
    head_weights = weight_arrays["JiangApprovedHead"]
    body_weights = weight_arrays["JiangFullbody"]
    face_ids = np.flatnonzero((head[:, 1] < FACE_Y_MAX) & (head[:, 2] > FACE_Z_MIN))
    face_pair = refined.farthest_face_pair(face_ids, head, np)
    rear_ids = np.flatnonzero((head[:, 1] > REAR_HAIR_Y_MIN) & (head[:, 2] > REAR_HAIR_Z_MIN))
    forward_axis = None

    body_group_names = [str(group.name) for group in meshes["JiangFullbody"].vertex_groups]
    group_index = {name: index for index, name in enumerate(sorted(body_group_names))}
    # weights_record stores sorted columns, so this index maps to its array column.
    support_boot_ids = np.asarray([], dtype=np.int64)
    left_boot_ids = np.asarray([], dtype=np.int64)
    for side, group_name, side_mask in (
        ("R", "foot.R", body[:, 0] < 0.0),
        ("L", "foot.L", body[:, 0] >= 0.0),
    ):
        column = group_index.get(group_name)
        if column is None:
            continue
        selected = np.flatnonzero((body[:, 2] < BOOT_REST_Z_MAX) & side_mask
                                  & (body_weights[:, column] >= 1.0 - WEIGHT_TOLERANCE))
        if side == "R":
            support_boot_ids = selected
        else:
            left_boot_ids = selected

    left_hand_vertex_pair = None
    wrist = np.asarray(LEFT_HAND_WRIST_REST, dtype=np.float64)
    axis_delta = np.asarray(LEFT_HAND_DIRECTION_POINT, dtype=np.float64) - wrist
    axis_length = float(np.linalg.norm(axis_delta))
    left_hand_ids = np.asarray([], dtype=np.int64)
    if axis_length > 1.0e-12 and math.isfinite(axis_length):
        axis = axis_delta / axis_length
        deltas = body - wrist
        along = np.einsum("ij,j->i", deltas, axis, optimize=False)
        radial = deltas - along[:, None] * axis
        radial_distance = np.linalg.norm(radial, axis=1)
        distance_from_wrist = np.linalg.norm(deltas, axis=1)
        left_hand_ids = np.flatnonzero(
            (body[:, 0] > 0.31)
            & (radial_distance < LEFT_HAND_RADIAL_MAX_M)
            & (distance_from_wrist < LEFT_HAND_LENGTH_MAX_M)
            & (along > LEFT_HAND_MIN_AXIAL_M)
        )
        left_hand_vertex_pair = refined.farthest_face_pair(left_hand_ids, body, np)

    sword_rest = rest_coords["JiangRightGrip_Jian"]
    sword_tip_index = int(np.argmax(sword_rest[:, 2]))
    if face_pair is None or not len(rear_ids) or not len(support_boot_ids) or not len(left_boot_ids):
        raise RuntimeError(f"{role}: source geometry cannot provide face, step, or boot references")

    original_frame = int(scene.frame_current)
    original_subframe = float(scene.frame_subframe)
    frames: list[dict[str, Any]] = []
    pose_at: dict[int, dict[str, Any]] = {}
    geometry_at: dict[int, dict[str, Any]] = {}
    supports: list[list[float]] = []
    right_boot_minima: list[float] = []
    left_boot_minima: list[float] = []
    right_boot_positions: list[Any] = []
    left_boot_positions: list[Any] = []
    left_head_positions: list[list[float]] = []
    left_tail_positions: list[list[float]] = []
    grip_distances: list[float] = []
    sword_length_distances: list[float] = []
    face_distances: list[float] = []
    left_hand_distances: list[float] = []
    camera_frames: list[dict[str, Any]] = []
    evaluated_counts: dict[str, int] = {}
    errors: list[str] = []
    from mathutils import Vector

    support_point = Vector(SUPPORT_BALL_REST)
    try:
        for frame in range(1, frame_end + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            depsgraph = bpy.context.evaluated_depsgraph_get()
            world_meshes: dict[str, Any] = {}
            world_points: list[Any] = []
            frame_finite = True
            for name, obj in meshes.items():
                evaluated_obj = obj.evaluated_get(depsgraph)
                evaluated_mesh = evaluated_obj.to_mesh()
                try:
                    coords = helpers.mesh_coordinates(evaluated_mesh, np)
                    evaluated_counts.setdefault(name, int(len(coords)))
                    if len(coords) != len(rest_coords[name]):
                        frame_finite = False
                        errors.append(f"{name} evaluated topology changed at frame {frame}.")
                    matrix = helpers.numpy_matrix(evaluated_obj.matrix_world, np)
                    points = helpers.transform_points(coords, matrix, np)
                    if not finite(points, np):
                        frame_finite = False
                        errors.append(f"{name} has non-finite evaluated vertices at frame {frame}.")
                        continue
                    world_meshes[name] = points
                    world_points.append(points)
                finally:
                    evaluated_obj.to_mesh_clear()

            if not set(world_meshes) == set(REQUIRED_MESHES):
                frame_finite = False
                errors.append(f"One or more required evaluated meshes are missing at frame {frame}.")

            all_points = np.concatenate(world_points, axis=0) if world_points else np.empty((0, 3))
            if not finite(all_points, np):
                frame_finite = False
                errors.append(f"Combined world geometry is non-finite at frame {frame}.")
            camera_metric = frame_camera_metrics(all_points, camera, depsgraph, camera_bounds,
                                                 resolution, helpers, np)
            camera_metric["frame"] = frame
            camera_frames.append(camera_metric)

            body_points = world_meshes.get("JiangFullbody")
            head_points = world_meshes.get("JiangApprovedHead")
            grip_points = world_meshes.get("JiangRightGrip_HandGrip")
            sword_points = world_meshes.get("JiangRightGrip_Jian")
            if body_points is not None and head_points is not None and grip_points is not None and sword_points is not None:
                if frame == 1 and face_pair is not None and len(face_ids) and len(rear_ids):
                    direction = head_points[face_ids].mean(axis=0) - head_points[rear_ids].mean(axis=0)
                    norm = float(np.linalg.norm(direction))
                    if norm > 1.0e-8 and math.isfinite(norm):
                        forward_axis = direction / norm
                    else:
                        frame_finite = False
                        errors.append("Could not derive a finite frame-1 world-space forward axis.")
                right_z = body_points[support_boot_ids, 2]
                left_z = body_points[left_boot_ids, 2]
                right_min = float(right_z.min()) if len(right_z) else math.nan
                left_min = float(left_z.min()) if len(left_z) else math.nan
                right_boot_minima.append(right_min)
                left_boot_minima.append(left_min)
                right_boot_positions.append(body_points[support_boot_ids].copy())
                left_boot_positions.append(body_points[left_boot_ids].copy())
                grip_distances.append(float(np.linalg.norm(grip_points[0] - sword_points[0])))
                sword_length_distances.append(float(np.linalg.norm(
                    sword_points[sword_tip_index] - sword_points[0])))
                face_distances.append(float(np.linalg.norm(
                    head_points[face_pair[0]] - head_points[face_pair[1]])))
                if left_hand_vertex_pair is not None:
                    pair = body_points[list(left_hand_vertex_pair)]
                    left_hand_distances.append(float(np.linalg.norm(pair[0] - pair[1])))
            else:
                frame_finite = False

            evaluated_rig = rig.evaluated_get(depsgraph)
            pose_bones = evaluated_rig.pose.bones
            current_pose: dict[str, Any] = {}
            for bone in sorted(rig.data.bones, key=lambda item: item.name):
                pose_bone = pose_bones.get(bone.name)
                if pose_bone is None:
                    frame_finite = False
                    errors.append(f"Pose bone {bone.name} is missing at frame {frame}.")
                    continue
                matrix = np.asarray([[float(pose_bone.matrix[row][column]) for column in range(4)]
                                     for row in range(4)], dtype=np.float64)
                if not finite(matrix, np):
                    frame_finite = False
                    errors.append(f"Pose bone {bone.name} is non-finite at frame {frame}.")
                current_pose[bone.name] = matrix
            pose_at[frame] = current_pose

            support_bone = pose_bones.get("foot.R")
            left_bone = pose_bones.get("foot.L")
            support_world = None
            left_head_world = None
            left_tail_world = None
            if support_bone is not None:
                armature_point = (support_bone.matrix
                                  @ rig.data.bones["foot.R"].matrix_local.inverted()
                                  @ support_point)
                point_world = evaluated_rig.matrix_world @ armature_point
                support_world = [float(value) for value in point_world]
                if finite(support_world, np):
                    supports.append(support_world)
                else:
                    frame_finite = False
            else:
                frame_finite = False
            if left_bone is not None:
                head_world = evaluated_rig.matrix_world @ left_bone.head
                tail_world = evaluated_rig.matrix_world @ left_bone.tail
                left_head_world = [float(value) for value in head_world]
                left_tail_world = [float(value) for value in tail_world]
                if finite(left_head_world, np) and finite(left_tail_world, np):
                    left_head_positions.append(left_head_world)
                    left_tail_positions.append(left_tail_world)
                else:
                    frame_finite = False
            else:
                frame_finite = False

            if frame in (1, frame_end):
                geometry_at[frame] = {name: points.copy() for name, points in world_meshes.items()}
            frames.append({
                "frame": frame,
                "finite": frame_finite,
                "mesh_finite": bool(all(name in world_meshes for name in REQUIRED_MESHES)),
                "pose_bone_count": len(current_pose),
                "camera": camera_metric,
                "support_ball_world": support_world,
                "left_foot_head_world": left_head_world,
                "left_foot_tail_world": left_tail_world,
                "right_boot_min_world_z_m": right_boot_minima[-1] if right_boot_minima else None,
                "left_boot_min_world_z_m": left_boot_minima[-1] if left_boot_minima else None,
            })
    except Exception as exc:
        errors.append(f"Frame evaluation failed: {type(exc).__name__}: {exc}")
    finally:
        scene.frame_set(original_frame, subframe=original_subframe)
        bpy.context.view_layer.update()

    all_finite = (
        len(frames) == frame_end
        and all(item["finite"] for item in frames)
        and all(len(pose_at.get(frame, {})) == 22 for frame in range(1, frame_end + 1))
        and all(len(geometry_at.get(frame, {})) == 4 for frame in (1, frame_end))
        and all(len(values) == frame_end for values in (
            supports, right_boot_minima, left_boot_minima, left_head_positions, left_tail_positions,
            grip_distances, sword_length_distances, face_distances,
        ))
    )

    support_positions = np.asarray(supports, dtype=np.float64) if supports else np.empty((0, 3))
    support_drifts = np.linalg.norm(support_positions - support_positions[0], axis=1) if len(support_positions) else np.asarray([])
    support_max = float(support_drifts.max()) if len(support_drifts) else None
    support_record = {
        "samples": len(supports), "rest_armature_point": list(SUPPORT_BALL_REST),
        "maximum_world_drift_m": support_max, "threshold_m": SUPPORT_BALL_TOLERANCE_M,
        "pass": bool(len(supports) == frame_end and support_max is not None
                      and support_max <= SUPPORT_BALL_TOLERANCE_M),
    }

    right_boot_record = {
        "samples": len(right_boot_minima), "minimum_world_z_m": min(right_boot_minima) if right_boot_minima else None,
        "threshold_m": BOOT_FLOOR_TOLERANCE_M,
        "pass": bool(len(right_boot_minima) == frame_end
                      and all(value >= BOOT_FLOOR_TOLERANCE_M for value in right_boot_minima)),
    }
    left_boot_record = {
        "samples": len(left_boot_minima), "minimum_world_z_m": min(left_boot_minima) if left_boot_minima else None,
        "threshold_m": BOOT_FLOOR_TOLERANCE_M,
        "pass": bool(len(left_boot_minima) == frame_end
                      and all(value >= BOOT_FLOOR_TOLERANCE_M for value in left_boot_minima)),
    }
    final_right = right_boot_minima[-1] if right_boot_minima else None
    final_left = left_boot_minima[-1] if left_boot_minima else None
    final_soles = {
        "right_final_min_world_z_m": final_right,
        "left_final_min_world_z_m": final_left,
        "threshold_abs_m": FINAL_SOLE_TOLERANCE_M,
        "pass": bool(final_right is not None and final_left is not None
                      and abs(final_right) <= FINAL_SOLE_TOLERANCE_M
                      and abs(final_left) <= FINAL_SOLE_TOLERANCE_M),
    }

    def maximum_vertex_drift(position_frames: list[Any]) -> float | None:
        if len(position_frames) != frame_end or not position_frames or not len(position_frames[0]):
            return None
        initial = position_frames[0]
        if any(item.shape != initial.shape or not finite(item, np) for item in position_frames):
            return None
        return max(float(np.linalg.norm(item - initial, axis=1).max()) for item in position_frames)

    right_boot_drift = maximum_vertex_drift(right_boot_positions)
    left_boot_drift = maximum_vertex_drift(left_boot_positions)
    boot_planted = {
        "applicable": role == "idle",
        "right_boot_maximum_world_vertex_drift_m": right_boot_drift,
        "left_boot_maximum_world_vertex_drift_m": left_boot_drift,
        "right_boot_maximum_floor_distance_m": max((abs(value) for value in right_boot_minima), default=None),
        "left_boot_maximum_floor_distance_m": max((abs(value) for value in left_boot_minima), default=None),
        "position_tolerance_m": RIGID_DISTANCE_TOLERANCE_M,
        "floor_tolerance_m": FINAL_SOLE_TOLERANCE_M,
        "pass": bool(role != "idle" or (
            right_boot_drift is not None and left_boot_drift is not None
            and right_boot_drift < RIGID_DISTANCE_TOLERANCE_M
            and left_boot_drift < RIGID_DISTANCE_TOLERANCE_M
            and len(right_boot_minima) == frame_end and len(left_boot_minima) == frame_end
            and all(abs(value) <= FINAL_SOLE_TOLERANCE_M for value in right_boot_minima)
            and all(abs(value) <= FINAL_SOLE_TOLERANCE_M for value in left_boot_minima))),
    }

    camera_valid = [item for item in camera_frames if item.get("minimum_margin_px") is not None]
    worst_camera = min(camera_valid, key=lambda item: item["minimum_margin_px"], default=None)
    camera_record = {
        "evaluated_frames": len(camera_frames),
        "minimum_margin_px": worst_camera.get("minimum_margin_px") if worst_camera else None,
        "minimum_margin_frame": worst_camera.get("frame") if worst_camera else None,
        "threshold_strictly_greater_than_px": CAMERA_MARGIN_MIN_PX,
        "clipped_or_behind_vertex_count": sum(item.get("clipped_or_behind_vertex_count", 1) for item in camera_frames),
        "pass": bool(len(camera_frames) == frame_end and len(camera_valid) == frame_end
                      and all(item.get("pass") for item in camera_frames)),
    }

    invariant_results = {
        "right_grip_to_blade": invariant_record(grip_distances,
            "distance between JiangRightGrip_HandGrip vertex 0 and JiangRightGrip_Jian vertex 0",
            RIGID_DISTANCE_TOLERANCE_M),
        "blade_length": invariant_record(sword_length_distances,
            "distance between sword root vertex 0 and its maximum-rest-Z tip vertex",
            RIGID_DISTANCE_TOLERANCE_M),
        "rigid_face_pair": invariant_record(face_distances,
            "distance between two head-weighted front-face vertices",
            RIGID_DISTANCE_TOLERANCE_M),
        "fully_rigid_left_hand_pair": invariant_record(left_hand_distances,
            "distance between farthest selected vertices of the hand.L-weighted left-hand region",
            RIGID_DISTANCE_TOLERANCE_M),
    }
    left_hand_column = group_index.get("hand.L")
    left_hand_weight_pass = bool(
        left_hand_vertex_pair is not None and len(left_hand_ids) > 0 and left_hand_column is not None
        and np.all(body_weights[left_hand_ids, left_hand_column] >= 1.0 - WEIGHT_TOLERANCE)
        and np.all(np.sum(body_weights[left_hand_ids], axis=1) - body_weights[left_hand_ids, left_hand_column]
                   <= WEIGHT_TOLERANCE)
    )

    cut_indices = [frame - 1 for frame in CUT_FRAMES if frame <= frame_end]
    first_head = np.asarray(left_head_positions[0], dtype=np.float64) if left_head_positions else None
    first_tail = np.asarray(left_tail_positions[0], dtype=np.float64) if left_tail_positions else None
    cut_lift = None
    cut_forward = None
    cut_peak_frame = None
    if cut_indices and len(left_head_positions) == frame_end and len(left_tail_positions) == frame_end:
        cut_lifts: list[tuple[float, int]] = []
        cut_forwards: list[tuple[float, int]] = []
        for index in cut_indices:
            head_pos = np.asarray(left_head_positions[index], dtype=np.float64)
            tail_pos = np.asarray(left_tail_positions[index], dtype=np.float64)
            lift = max(float(head_pos[2] - first_head[2]), float(tail_pos[2] - first_tail[2]))
            forward = (float(np.dot(tail_pos - first_tail, forward_axis))
                       if forward_axis is not None else float("nan"))
            cut_lifts.append((lift, index + 1))
            cut_forwards.append((forward, index + 1))
        cut_lift, cut_peak_frame = max(cut_lifts)
        cut_forward, _ = max(cut_forwards)
    step_record = {
        "applicable": role == "action",
        "cut_frames": [min(CUT_FRAMES), max(CUT_FRAMES)],
        "peak_lift_in_cut_m": cut_lift,
        "peak_lift_frame": cut_peak_frame,
        "minimum_lift_required_m": LEFT_LIFT_MIN_M,
        "maximum_forward_displacement_in_cut_m": cut_forward,
        "minimum_forward_required_m": LEFT_FORWARD_MIN_M,
        "forward_axis_world": [float(value) for value in forward_axis] if forward_axis is not None else None,
        "left_hand_weight_pair": list(left_hand_vertex_pair) if left_hand_vertex_pair else None,
        "left_hand_region_vertex_count": int(len(left_hand_ids)),
        "left_hand_fully_rigid_to_hand_L": left_hand_weight_pass,
        "pass": bool(role != "action" or (
            cut_lift is not None and cut_forward is not None
            and cut_lift > LEFT_LIFT_MIN_M and cut_forward > LEFT_FORWARD_MIN_M
            and left_hand_weight_pass)),
    }

    idle_bone_motion: dict[str, Any] = {}
    for bone_name in (("chest", "ponytail") if role == "idle" else ()):
        matrices = [pose_at.get(frame, {}).get(bone_name) for frame in range(1, frame_end + 1)]
        if role != "idle" or len(matrices) != frame_end or not matrices or any(item is None for item in matrices):
            idle_bone_motion[bone_name] = {"samples": len(matrices), "pass": False}
            continue
        base = np.asarray(matrices[0], dtype=np.float64)
        deltas = [float(np.max(np.abs(np.asarray(item, dtype=np.float64) - base))) for item in matrices]
        peak_index = int(np.argmax(deltas))
        idle_bone_motion[bone_name] = {
            "samples": len(matrices), "maximum_pose_matrix_delta": deltas[peak_index],
            "peak_frame": peak_index + 1, "minimum_nonzero_delta": 1.0e-6,
            "pass": deltas[peak_index] > 1.0e-6,
        }
    idle_motion_record = {
        "applicable": role == "idle",
        "bones": idle_bone_motion,
        "pass": bool(role != "idle" or all(item.get("pass") for item in idle_bone_motion.values())),
    }

    return {
        "role": role,
        "frame_count_evaluated": len(frames),
        "evaluated_vertex_counts": evaluated_counts,
        "frames": frames,
        "errors": errors,
        "all_frames_finite": all_finite,
        "support_ball": support_record,
        "right_boot_floor": right_boot_record,
        "left_boot_floor": left_boot_record,
        "final_soles": final_soles,
        "idle_boots_planted": boot_planted,
        "camera": camera_record,
        "rigid_distance_invariants": invariant_results,
        "left_hand_step": step_record,
        "idle_bone_motion": idle_motion_record,
        "pose_matrices_at_boundary": {key: pose_at.get(key) for key in (1, frame_end)},
        "geometry_at_boundary": geometry_at,
    }


def add_static_checks(report: dict[str, Any], helpers: Any,
                      snapshot: dict[str, Any], approved: dict[str, Any],
                      expected_end: int, role: str) -> dict[str, Any]:
    prefix = role.lower()
    add_check(report, helpers, f"{prefix}_saved_blend_readable", bool(snapshot.get("saved_blend_sha256")),
              {"path": snapshot.get("path"), "sha256": snapshot.get("saved_blend_sha256")},
              f"{role} must be an existing saved .blend file.")
    add_check(report, helpers, f"{prefix}_timing", snapshot["timing_pass"], snapshot["scene"],
              f"{role} must use frames 1–{expected_end} at 30 fps.")
    add_check(report, helpers, f"{prefix}_four_meshes", snapshot["mesh_names"]["exact_four_expected"],
              snapshot["mesh_names"], f"{role} must contain exactly the four expected Jiang meshes.")
    add_check(report, helpers, f"{prefix}_22_bone_rig", snapshot["rig"]["pass"], snapshot["rig"],
              f"{role} must contain one finite JiangRig with 22 bones.")
    add_check(report, helpers, f"{prefix}_orthographic_camera", snapshot["camera"]["pass"], snapshot["camera"],
              f"{role} must retain the approved orthographic camera.")
    add_check(report, helpers, f"{prefix}_six_packed_textures", snapshot["texture_pass"],
              {"textures": snapshot["textures"], "errors": snapshot["texture_errors"]},
              f"{role} must contain six readable packed 4096×4096 textures.")
    add_check(report, helpers, f"{prefix}_finite_rest_geometry", snapshot["geometry_pass"],
              {name: item["rest_geometry"] for name, item in snapshot["meshes"].items()},
              f"{role} rest geometry must be finite and hashed for all four meshes.")
    add_check(report, helpers, f"{prefix}_finite_uvs", snapshot["uv_pass"],
              {name: item["uv"] for name, item in snapshot["meshes"].items()},
              f"{role} UV coordinates must be finite.")
    add_check(report, helpers, f"{prefix}_normalized_weights", snapshot["weights_pass"],
              {name: item["weights"]["normalized"] for name, item in snapshot["meshes"].items()},
              f"{role} vertex weights must be finite, nonnegative, and sum to 1 within 0.001.")
    add_check(report, helpers, f"{prefix}_no_text_or_drivers", snapshot["no_text_or_drivers"],
              {"text_objects": snapshot["text_objects"], "text_curves": snapshot["text_curves"],
               "drivers": snapshot["drivers"]}, f"{role} must not contain Text objects or driver curves.")

    comparison = rest_comparison(snapshot, approved)
    add_check(report, helpers, f"{prefix}_rest_geometry_matches_approved",
              all(item["pass"] for item in comparison["geometry"].values()), comparison["geometry"],
              f"{role} must preserve all four approved rest meshes exactly.")
    add_check(report, helpers, f"{prefix}_uvs_match_approved",
              all(item["pass"] for item in comparison["uv"].values()), comparison["uv"],
              f"{role} must preserve all approved mesh UV data exactly.")
    add_check(report, helpers, f"{prefix}_weights_match_approved",
              all(item["pass"] for item in comparison["weights"].values()), comparison["weights"],
              f"{role} must preserve all approved source weights exactly.")
    add_check(report, helpers, f"{prefix}_textures_match_approved", comparison["textures"]["pass"],
              comparison["textures"], f"{role} packed texture payloads must match the approved source.")
    add_check(report, helpers, f"{prefix}_rest_bones_match_approved", comparison["bones"]["pass"],
              comparison["bones"], f"{role} must preserve the approved 22-bone rest skeleton.")
    add_check(report, helpers, f"{prefix}_camera_matches_approved", comparison["camera"]["pass"],
              comparison["camera"], f"{role} must preserve the approved camera and resolution.")
    add_check(report, helpers, f"{prefix}_material_signature_matches_approved", comparison["materials"]["pass"],
              comparison["materials"], f"{role} material, node, socket-default, and link signature must match approved.")
    add_check(report, helpers, f"{prefix}_jiang_warm_gain_matches_approved",
              comparison["JiangWarmGain"]["pass"], comparison["JiangWarmGain"],
              f"{role} must preserve the approved POINT JiangWarmGain color attributes.")
    return comparison


def verify_cycles(bpy: Any, np: Any, phrase: Any, helpers: Any,
                  refined: Any, paths: dict[str, Path], baseline: dict[str, Any],
                  baseline_path: Path, baseline_hash: str, report_path: Path) -> dict[str, Any]:
    report: dict[str, Any] = {
        "status": "FAIL", "report_path": str(report_path), "errors": [], "checks": {},
        "baseline": {"path": str(baseline_path), "sha256": baseline_hash},
        "sources": {}, "projects": {}, "comparisons": {}, "animation": {},
    }
    input_hashes = {name: helpers.sha256_file(path) for name, path in paths.items()}
    report["sources"] = {name: {"path": str(path), "sha256": input_hashes[name],
                               "bytes": path.stat().st_size} for name, path in paths.items()}
    baseline_record = baseline_report_check(baseline, input_hashes["approved"])
    report["baseline"].update(baseline_record)
    add_check(report, helpers, "approved_blend_sha256_is_expected",
              input_hashes["approved"] == EXPECTED_APPROVED_SHA256,
              report["sources"]["approved"],
              "Approved warm v4 blend must match its recorded SHA-256.")
    add_check(report, helpers, "baseline_report_is_passing_v4_source",
              baseline_record["pass"], baseline_record,
              "Baseline must be the PASS 27-check v4 report for the approved blend.")

    snapshots: dict[str, dict[str, Any]] = {}
    expectations = {"approved": APPROVED_FRAME_END, "action": ACTION_FRAME_END, "idle": IDLE_FRAME_END}
    for role in ("approved", "action", "idle"):
        path = paths[role]
        try:
            bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
            snapshot = collect_static_snapshot(bpy, np, helpers, phrase, refined,
                                               path, role, expectations[role])
            snapshots[role] = snapshot
            report["projects"][role] = {
                key: value for key, value in snapshot.items() if key != "private"
            }
            if role != "approved":
                report["comparisons"][role] = add_static_checks(
                    report, helpers, snapshot, snapshots["approved"], expectations[role], role.upper())
            else:
                add_check(report, helpers, "approved_reference_timing", snapshot["timing_pass"],
                          snapshot["scene"], "Approved v4 source must use frames 1–120 at 30 fps.")
                add_check(report, helpers, "approved_baseline_model_valid",
                          snapshot["mesh_names"]["exact_four_expected"] and snapshot["rig"]["pass"]
                          and snapshot["camera"]["pass"] and snapshot["texture_pass"]
                          and snapshot["geometry_pass"] and snapshot["uv_pass"]
                          and snapshot["weights_pass"] and snapshot["warm_gain_pass"]
                          and snapshot["no_text_or_drivers"],
                          {"meshes": snapshot["mesh_names"], "rig": snapshot["rig"],
                           "camera": snapshot["camera"], "texture_pass": snapshot["texture_pass"],
                           "warm_gain": snapshot["warm_gain"],
                           "no_text_or_drivers": snapshot["no_text_or_drivers"]},
                          "Approved source must provide the expected read-only model and palette baseline.")
                add_check(report, helpers, "baseline_geometry_hashes_match_approved",
                          all(baseline.get("source", {}).get("rest_geometry_sha256_by_mesh", {}).get(name)
                              == snapshot["meshes"].get(name, {}).get("rest_geometry", {}).get("rest_geometry_sha256")
                              for name in REQUIRED_MESHES),
                          {name: {"report": baseline.get("source", {}).get("rest_geometry_sha256_by_mesh", {}).get(name),
                                  "approved": snapshot["meshes"].get(name, {}).get("rest_geometry", {}).get("rest_geometry_sha256")}
                           for name in REQUIRED_MESHES},
                          "Baseline report rest-mesh hashes must match the opened approved blend.")
                baseline_textures = {item["name"]: item.get("packed_sha256")
                                     for item in baseline.get("textures", []) if isinstance(item, dict)}
                approved_textures = {item["name"]: item.get("packed_sha256")
                                     for item in snapshot["textures"]}
                add_check(report, helpers, "baseline_texture_hashes_match_approved",
                          baseline_textures == approved_textures,
                          {"baseline": baseline_textures, "approved": approved_textures},
                          "Baseline report packed texture hashes must match the approved source.")
        except Exception as exc:
            report["errors"].append(f"Could not inspect {role}: {type(exc).__name__}: {exc}")
            add_check(report, helpers, f"{role}_opened_and_inspected", False,
                      {"path": str(path), "error": f"{type(exc).__name__}: {exc}"},
                      f"Could not open and inspect the {role} project.")
            # The remaining candidates are still independently inspectable.
            continue

    if "approved" not in snapshots or "action" not in snapshots or "idle" not in snapshots:
        report["status"] = "FAIL"
        report["summary"] = {
            "checks_passed": sum(item["status"] == "PASS" for item in report["checks"].values()),
            "checks_failed": sum(item["status"] == "FAIL" for item in report["checks"].values()),
            "error_count": len(report["errors"]),
            "visual_review": "not performed by this automated verifier",
        }
        return report

    evaluated: dict[str, dict[str, Any]] = {}
    for role, frame_end in (("action", ACTION_FRAME_END), ("idle", IDLE_FRAME_END)):
        try:
            bpy.ops.wm.open_mainfile(filepath=str(paths[role]), load_ui=False)
            # Rebind Blender datablocks after each open_mainfile; RNA references
            # held by the earlier inspection become invalid when another file opens.
            eval_snapshot = collect_static_snapshot(
                bpy, np, helpers, phrase, refined, paths[role], role, frame_end)
            if eval_snapshot["saved_blend_sha256"] != report["sources"][role]["sha256"]:
                raise RuntimeError(f"{role} blend changed during verification")
            result = evaluate_clip(bpy, np, helpers, refined, eval_snapshot, role, frame_end)
            evaluated[role] = result
            report["animation"][role] = {key: value for key, value in result.items()
                                         if key not in ("pose_matrices_at_boundary", "geometry_at_boundary")}
            prefix = role
            add_check(report, helpers, f"{prefix}_all_saved_frames_finite", result["all_frames_finite"],
                      {"frames": result["frame_count_evaluated"],
                       "expected": frame_end, "vertex_counts": result["evaluated_vertex_counts"],
                       "errors": result["errors"]},
                      f"Every {role} frame must evaluate finite bones and all four meshes.")
            add_check(report, helpers, f"{prefix}_camera_margins_all_frames", result["camera"]["pass"],
                      result["camera"], f"Every {role} mesh vertex must stay over 16 px inside camera bounds.")
            add_check(report, helpers, f"{prefix}_right_support_ball_fixed", result["support_ball"]["pass"],
                      result["support_ball"], f"{role} right support point must drift no more than 0.004 m.")
            add_check(report, helpers, f"{prefix}_both_boots_above_floor", result["right_boot_floor"]["pass"]
                      and result["left_boot_floor"]["pass"],
                      {"right": result["right_boot_floor"], "left": result["left_boot_floor"]},
                      f"Both {role} boots must stay above -0.008 m in every frame.")
            add_check(report, helpers, f"{prefix}_rigid_face_grip_blade", all(
                item["pass"] for key, item in result["rigid_distance_invariants"].items()
                if key in ("right_grip_to_blade", "blade_length", "rigid_face_pair")),
                {key: result["rigid_distance_invariants"][key]
                 for key in ("right_grip_to_blade", "blade_length", "rigid_face_pair")},
                f"{role} protected face, right grip, and blade lengths must stay rigid at source tolerance.")
            add_check(report, helpers, f"{prefix}_fully_rigid_left_hand",
                      result["rigid_distance_invariants"]["fully_rigid_left_hand_pair"]["pass"]
                      and result["left_hand_step"]["left_hand_fully_rigid_to_hand_L"],
                      {"pair": result["rigid_distance_invariants"]["fully_rigid_left_hand_pair"],
                       "weights": result["left_hand_step"]},
                      f"{role} left-hand source region must remain fully rigid to hand.L.")
            if role == "action":
                add_check(report, helpers, "action_left_step_in_cut", result["left_hand_step"]["pass"],
                          result["left_hand_step"],
                          "Action frames 46–58 must lift the left foot over 0.04 m and move it over 0.10 m forward.")
                add_check(report, helpers, "action_both_soles_land_at_end", result["final_soles"]["pass"],
                          result["final_soles"], "Both action sole minima must finish within ±0.008 m of the floor.")
            else:
                add_check(report, helpers, "idle_boots_planted_all_frames",
                          result["idle_boots_planted"]["pass"], result["idle_boots_planted"],
                          "Idle left and right boot vertices must stay planted and within ±0.008 m of the floor.")
                add_check(report, helpers, "idle_chest_and_ponytail_move",
                          result["idle_bone_motion"]["pass"], result["idle_bone_motion"],
                          "Idle must contain nonzero chest and ponytail motion.")
        except Exception as exc:
            report["errors"].append(f"Could not evaluate {role}: {type(exc).__name__}: {exc}")
            add_check(report, helpers, f"{role}_frame_evaluation_completed", False,
                      {"error": f"{type(exc).__name__}: {exc}"}, f"Could not evaluate all {role} frames.")

    if "action" in evaluated and "idle" in evaluated:
        action = evaluated["action"]
        idle = evaluated["idle"]
        action_first = action["pose_matrices_at_boundary"].get(1)
        action_last = action["pose_matrices_at_boundary"].get(ACTION_FRAME_END)
        idle_first = idle["pose_matrices_at_boundary"].get(1)
        idle_last = idle["pose_matrices_at_boundary"].get(IDLE_FRAME_END)
        pose_checks = {
            "action_first_equals_last": matrix_delta(action_first or {}, action_last or {}, np),
            "idle_first_equals_last": matrix_delta(idle_first or {}, idle_last or {}, np),
            "idle_first_equals_action_first": matrix_delta(idle_first or {}, action_first or {}, np),
        }
        report["animation"]["boundary_pose_matrices"] = pose_checks
        add_check(report, helpers, "action_pose_first_equals_last", pose_checks["action_first_equals_last"]["pass"],
                  pose_checks["action_first_equals_last"], "All action pose bone matrices at frames 1 and 180 must match within 1e-5.")
        add_check(report, helpers, "idle_pose_first_equals_last", pose_checks["idle_first_equals_last"]["pass"],
                  pose_checks["idle_first_equals_last"], "All idle pose bone matrices at frames 1 and 60 must match within 1e-5.")
        add_check(report, helpers, "idle_pose_first_equals_action_first", pose_checks["idle_first_equals_action_first"]["pass"],
                  pose_checks["idle_first_equals_action_first"], "Idle frame 1 must share the neutral action frame 1 pose within 1e-5.")

        geometry_checks = {
            "action_first_equals_last": compare_boundary_geometry(
                action["geometry_at_boundary"].get(1, {}),
                action["geometry_at_boundary"].get(ACTION_FRAME_END, {}), np),
            "idle_first_equals_last": compare_boundary_geometry(
                idle["geometry_at_boundary"].get(1, {}),
                idle["geometry_at_boundary"].get(IDLE_FRAME_END, {}), np),
            "idle_first_equals_action_first": compare_boundary_geometry(
                idle["geometry_at_boundary"].get(1, {}),
                action["geometry_at_boundary"].get(1, {}), np),
        }
        report["animation"]["boundary_evaluated_geometry"] = geometry_checks
        for name, result in geometry_checks.items():
            add_check(report, helpers, f"boundary_geometry_{name}", result["pass"], result,
                      f"Evaluated four-mesh geometry {name.replace('_', ' ')} within 1e-6 m.")

    report["status"] = "PASS" if not report["errors"] and all(
        item["status"] == "PASS" for item in report["checks"].values()) else "FAIL"
    report["summary"] = {
        "checks_passed": sum(item["status"] == "PASS" for item in report["checks"].values()),
        "checks_failed": sum(item["status"] == "FAIL" for item in report["checks"].values()),
        "error_count": len(report["errors"]),
        "visual_review": "not performed by this automated verifier",
    }
    return report


def write_failure(path: Path, message: str, exc: BaseException | None = None) -> None:
    payload: dict[str, Any] = {"status": "FAIL", "report_path": str(path),
                               "errors": [message], "checks": {}}
    if exc is not None:
        payload["traceback"] = traceback.format_exc()
    with path.open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(payload, indent=2, ensure_ascii=False, allow_nan=False) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(script_args(sys.argv if argv is None else argv))
    try:
        phrase, helpers, refined = load_helpers()
        report_path = helpers.validate_report_destination(args.report)
        action_path = normalize_input_path(args.action, "action", ".blend")
        idle_path = normalize_input_path(args.idle, "idle", ".blend")
        approved_path = normalize_input_path(args.approved, "approved", ".blend")
        baseline, baseline_path, baseline_hash = phrase.read_baseline(args.baseline_report, helpers)
        if len({action_path, idle_path, approved_path}) != 3:
            raise ValueError("--action, --idle, and --approved must name distinct files")
    except Exception as exc:
        try:
            if not args.report.is_absolute():
                parser.error("--report must be an absolute path")
            report_path = locals().get("report_path", args.report.expanduser().resolve(strict=False))
            if report_path.suffix.lower() != ".json" or report_path.exists() or not report_path.parent.is_dir():
                parser.error(str(exc))
            write_failure(report_path, f"Could not prepare verifier inputs: {type(exc).__name__}: {exc}", exc)
        except Exception as write_exc:
            print(f"Could not write failure report: {type(write_exc).__name__}: {write_exc}", file=sys.stderr)
            return 2
        print(json.dumps({"status": "FAIL", "report": str(report_path),
                          "errors": [f"Could not prepare verifier inputs: {type(exc).__name__}: {exc}"]},
                         ensure_ascii=False))
        return 1

    try:
        import bpy
        import numpy as np
        report = verify_cycles(
            bpy, np, phrase, helpers, refined,
            {"approved": approved_path, "action": action_path, "idle": idle_path},
            baseline, baseline_path, baseline_hash, report_path,
        )
    except Exception as exc:
        report = {
            "status": "FAIL", "report_path": str(report_path),
            "baseline_report_path": str(baseline_path),
            "errors": [f"Verifier execution failed: {type(exc).__name__}: {exc}"],
            "traceback": traceback.format_exc(), "checks": {},
        }
    try:
        helpers.write_new_report(report_path, report)
    except Exception as exc:
        print(f"Could not write verification report: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({"status": report["status"], "report": str(report_path),
                      "errors": report.get("errors", [])}, ensure_ascii=False))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
