#!/usr/bin/env python3
"""Verify the JSON motion contract for five six-second sword routines.

This report-only tool reads cycle-report JSON. It does not inspect source
geometry, palette, rigging, grips, Blender files, or rendered images. A PASS
establishes numeric report conditions and trajectory differences only; it is
not artistic or visual acceptance.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


EXPECTED_IDS = ("songfeng", "chuanyun", "huilan", "tiaoyue", "xieying")
FRAME_COUNT = 180
FPS = 30
DURATION_SECONDS = 6.0
TIMING_PROFILE = "routine-v1"
TIME_TOLERANCE_SECONDS = 1.0e-9
ENDPOINT_TOLERANCE = 1.0e-5
RIGHT_WRIST_TARGET_MAX_M = 1.0e-5
BONE_HEAD_MAX_M = 1.0e-5
LEG_IK_TARGET_MAX_M = 0.03
WRIST_BEND_MAX_DEGREES = 60.0
BLADE_AIM_MAX_DEGREES = 15.0
MIN_WRIST_RMS_M = 0.015
MIN_BLADE_ANGLE_RMS_DEGREES = 8.0
TIP_PROXY_SCALE_M = 1.0
YAW_FIELDS = ("pelvis_yaw", "torso_yaw", "head_yaw")
WORLD_VECTOR_FIELDS = (
    "right_wrist_world", "left_wrist_world", "left_ankle_world", "blade_axis_world",
)
POSITION_VECTOR_FIELDS = ("right_wrist_world", "left_wrist_world", "left_ankle_world")
REQUIRED_NUMERIC_FIELDS = (
    "frame", "seconds", "pelvis_yaw", "torso_yaw", "head_yaw", "left_step_lift",
    "wrist_bend_degrees", "max_bone_head_error", "right_wrist_target_error_m",
    "blade_aim_error_degrees",
)


def finite_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    try:
        number = float(value)
    except OverflowError:
        return None
    return number if math.isfinite(number) else None


def nonfinite_paths(value: Any, path: str = "action") -> list[str]:
    found: list[str] = []
    if value is None or isinstance(value, (bool, str)):
        return found
    if isinstance(value, int):
        return found
    if isinstance(value, float):
        if not math.isfinite(value):
            found.append(path)
        return found
    if isinstance(value, list):
        for index, item in enumerate(value):
            found.extend(nonfinite_paths(item, f"{path}[{index}]"))
    elif isinstance(value, dict):
        for key, item in value.items():
            found.extend(nonfinite_paths(item, f"{path}.{key}"))
    return found


def vector3(value: Any) -> tuple[float, float, float] | None:
    if not isinstance(value, (list, tuple)) or len(value) != 3:
        return None
    components = [finite_number(component) for component in value]
    if any(component is None for component in components):
        return None
    return (components[0], components[1], components[2])  # type: ignore[return-value]


def frame_id(row: Any, index: int) -> int:
    if isinstance(row, dict):
        number = finite_number(row.get("frame"))
        if number is not None and number.is_integer():
            return int(number)
    return index + 1


def add_check(
    checks: list[dict[str, Any]],
    name: str,
    passed: bool,
    observed: Any,
    unit: str,
    failure_frames: list[int] | None = None,
    details: Any = None,
) -> None:
    item = {
        "name": name,
        "status": "PASS" if passed else "FAIL",
        "observed": observed,
        "unit": unit,
        "failure_frames": sorted(set(failure_frames or [])),
    }
    if details is not None:
        item["failure_details"] = details
    checks.append(item)


def grouped_phase_keys(phase_keys: Any) -> tuple[list[dict[str, Any]], bool, list[int]]:
    if not isinstance(phase_keys, list) or not phase_keys:
        return [], False, []

    groups: list[dict[str, Any]] = []
    valid = True
    invalid_indexes: list[int] = []
    previous_seconds: float | None = None
    previous_valid_index = -2
    for index, item in enumerate(phase_keys):
        if not isinstance(item, dict):
            valid = False
            invalid_indexes.append(index)
            previous_valid_index = -2
            continue
        seconds = finite_number(item.get("seconds"))
        phase = item.get("phase")
        if seconds is None or not isinstance(phase, str) or not phase:
            valid = False
            invalid_indexes.append(index)
            previous_valid_index = -2
            continue
        if seconds < 0 or seconds > DURATION_SECONDS:
            valid = False
            invalid_indexes.append(index)
        if previous_seconds is not None and seconds <= previous_seconds:
            valid = False
            invalid_indexes.append(index)
        previous_seconds = seconds

        if (groups and groups[-1]["phase"] == phase
                and previous_valid_index == index - 1):
            groups[-1]["key_count"] += 1
        else:
            groups.append({"phase": phase, "start_seconds": seconds, "key_count": 1})
        previous_valid_index = index

    for index, group in enumerate(groups):
        group["end_seconds"] = (
            groups[index + 1]["start_seconds"] if index + 1 < len(groups) else DURATION_SECONDS
        )
        group["duration_seconds"] = finite_number(
            group["end_seconds"] - group["start_seconds"]
        )
    return groups, valid, invalid_indexes


def frame_phase_counts(frames: Any) -> dict[str, int]:
    counts: dict[str, int] = {}
    if isinstance(frames, list):
        for row in frames:
            if isinstance(row, dict) and isinstance(row.get("phase"), str):
                phase = row["phase"]
                counts[phase] = counts.get(phase, 0) + 1
    return dict(sorted(counts.items()))


def normalized_axis(value: Any) -> tuple[float, float, float] | None:
    axis = vector3(value)
    if axis is None:
        return None
    scale = max(abs(component) for component in axis)
    if scale <= 0.0:
        return None
    scaled = tuple(component / scale for component in axis)
    length = math.hypot(*scaled)
    return tuple(component / length for component in scaled)  # type: ignore[return-value]


def inspect_set(set_entry: dict[str, Any], source: Any) -> dict[str, Any]:
    action_value = source.get("action") if isinstance(source, dict) else None
    action = action_value if isinstance(action_value, dict) else {}
    frames_value = action.get("frames")
    frames = frames_value if isinstance(frames_value, list) else []
    checks: list[dict[str, Any]] = []

    add_check(checks, "action_object_present", isinstance(action_value, dict),
              isinstance(action_value, dict), "boolean")
    profile = action.get("timing_profile")
    add_check(checks, "timing_profile", profile == TIMING_PROFILE,
              profile if isinstance(profile, str) else None, "profile")

    declared_count = finite_number(action.get("frame_count"))
    add_check(checks, "frame_count", len(frames) == FRAME_COUNT and declared_count == FRAME_COUNT,
              {"declared_frame_count": declared_count, "frames_length": len(frames),
               "expected": FRAME_COUNT}, "frames")
    fps = finite_number(action.get("fps"))
    add_check(checks, "fps", fps == FPS, fps, "frames/second")
    duration = finite_number(action.get("duration_seconds"))
    add_check(checks, "duration", duration is not None
              and abs(duration - DURATION_SECONDS) <= TIME_TOLERANCE_SECONDS,
              duration, "seconds")

    bad_numeric_paths = nonfinite_paths(action)
    add_check(checks, "all_action_numbers_finite", not bad_numeric_paths,
              {"nonfinite_count": len(bad_numeric_paths), "nonfinite_paths": bad_numeric_paths[:100]},
              "numeric values")

    schema_failures: list[int] = []
    sample_failures: list[int] = []
    wrist_residual_failures: list[int] = []
    bone_head_failures: list[int] = []
    wrist_bend_failures: list[int] = []
    leg_ik_failures: list[int] = []
    leg_ik_failure_details: list[dict[str, Any]] = []
    leg_ik_schema_failures: list[int] = []
    vector_failures: dict[str, list[int]] = {field: [] for field in WORLD_VECTOR_FIELDS}
    zero_axis_failures: list[int] = []

    wrist_residuals: list[float] = []
    bone_head_errors: list[float] = []
    wrist_bends: list[float] = []
    leg_ik_errors: list[float] = []
    parsed_vectors: dict[str, list[tuple[float, float, float] | None]] = {
        field: [] for field in WORLD_VECTOR_FIELDS
    }

    for index, row in enumerate(frames):
        label = frame_id(row, index)
        if not isinstance(row, dict):
            schema_failures.append(label)
            sample_failures.append(label)
            wrist_residual_failures.append(label)
            bone_head_failures.append(label)
            wrist_bend_failures.append(label)
            leg_ik_failures.append(label)
            leg_ik_schema_failures.append(label)
            leg_ik_failure_details.append({"frame": label,
                                           "reason": "frame row is not an object"})
            for failures in vector_failures.values():
                failures.append(label)
            parsed_vectors["right_wrist_world"].append(None)
            parsed_vectors["left_wrist_world"].append(None)
            parsed_vectors["left_ankle_world"].append(None)
            parsed_vectors["blade_axis_world"].append(None)
            continue

        for field in REQUIRED_NUMERIC_FIELDS:
            if finite_number(row.get(field)) is None:
                schema_failures.append(label)
                break
        phase = row.get("phase")
        if not isinstance(phase, str) or not phase:
            schema_failures.append(label)

        ik = row.get("leg_ik_target_errors")
        if not isinstance(ik, dict) or any(finite_number(ik.get(side)) is None for side in ("R", "L")):
            schema_failures.append(label)
            leg_ik_schema_failures.append(label)
            leg_ik_failure_details.append({"frame": label,
                                           "reason": "missing or non-finite R/L target error"})
        else:
            for side in ("R", "L"):
                value = finite_number(ik.get(side))
                if value is not None:
                    magnitude = abs(value)
                    leg_ik_errors.append(magnitude)
                    if magnitude > LEG_IK_TARGET_MAX_M:
                        leg_ik_failures.append(label)
                        leg_ik_failure_details.append({"frame": label, "side": side,
                                                       "observed_m": magnitude})

        frame_value = finite_number(row.get("frame"))
        seconds_value = finite_number(row.get("seconds"))
        expected_seconds = index / FPS
        if (frame_value is None or frame_value != index + 1 or seconds_value is None
                or abs(seconds_value - expected_seconds) > TIME_TOLERANCE_SECONDS):
            sample_failures.append(label)

        wrist_error = finite_number(row.get("right_wrist_target_error_m"))
        if wrist_error is None:
            wrist_residual_failures.append(label)
        else:
            wrist_error = abs(wrist_error)
            wrist_residuals.append(wrist_error)
            if wrist_error > RIGHT_WRIST_TARGET_MAX_M:
                wrist_residual_failures.append(label)

        bone_error = finite_number(row.get("max_bone_head_error"))
        if bone_error is None:
            bone_head_failures.append(label)
        else:
            bone_error = abs(bone_error)
            bone_head_errors.append(bone_error)
            if bone_error > BONE_HEAD_MAX_M:
                bone_head_failures.append(label)

        wrist_bend = finite_number(row.get("wrist_bend_degrees"))
        if wrist_bend is None:
            wrist_bend_failures.append(label)
        else:
            wrist_bend = abs(wrist_bend)
            wrist_bends.append(wrist_bend)
            if wrist_bend > WRIST_BEND_MAX_DEGREES:
                wrist_bend_failures.append(label)

        for field in WORLD_VECTOR_FIELDS:
            vector = vector3(row.get(field))
            parsed_vectors[field].append(vector)
            if vector is None:
                vector_failures[field].append(label)
        axis = parsed_vectors["blade_axis_world"][-1]
        if axis is not None and not any(component != 0.0 for component in axis):
            zero_axis_failures.append(label)

    add_check(checks, "required_frame_fields", len(frames) == FRAME_COUNT and not schema_failures,
              {"rows": len(frames), "required_numeric_fields": list(REQUIRED_NUMERIC_FIELDS),
               "required_other_fields": ["phase", "leg_ik_target_errors.R", "leg_ik_target_errors.L"]},
              "fields and numeric values", schema_failures)
    add_check(checks, "frame_sampling", len(frames) == FRAME_COUNT and not sample_failures,
              {"expected": "frame n has seconds (n-1)/30", "sample_count": len(frames)},
              "seconds at 30 frames/second", sample_failures)
    add_check(checks, "right_wrist_target_error",
              len(frames) == FRAME_COUNT and not wrist_residual_failures,
              {"maximum_m": max(wrist_residuals) if wrist_residuals else None,
               "threshold_m": RIGHT_WRIST_TARGET_MAX_M,
               "finite_samples": len(wrist_residuals)}, "metres", wrist_residual_failures)
    add_check(checks, "max_bone_head_error",
              len(frames) == FRAME_COUNT and not bone_head_failures,
              {"maximum_m": max(bone_head_errors) if bone_head_errors else None,
               "threshold_m": BONE_HEAD_MAX_M,
               "finite_samples": len(bone_head_errors)}, "metres", bone_head_failures)
    add_check(checks, "leg_ik_target_errors",
              len(frames) == FRAME_COUNT and not leg_ik_failures
              and not leg_ik_schema_failures,
              {"maximum_m": max(leg_ik_errors) if leg_ik_errors else None,
               "threshold_m": LEG_IK_TARGET_MAX_M,
               "finite_samples": len(leg_ik_errors)}, "metres",
              leg_ik_failures + leg_ik_schema_failures,
              leg_ik_failure_details)
    add_check(checks, "wrist_bend_degrees",
              len(frames) == FRAME_COUNT and not wrist_bend_failures,
              {"maximum_degrees": max(wrist_bends) if wrist_bends else None,
               "threshold_degrees": WRIST_BEND_MAX_DEGREES,
               "finite_samples": len(wrist_bends)}, "degrees", wrist_bend_failures)

    for field in WORLD_VECTOR_FIELDS:
        add_check(checks, f"{field}_finite_3d",
                  len(frames) == FRAME_COUNT and not vector_failures[field],
                  {"sample_count": len(parsed_vectors[field]), "dimensions": 3},
                  "world vector components", vector_failures[field])
    add_check(checks, "blade_axis_nonzero",
              len(frames) == FRAME_COUNT and not zero_axis_failures
              and not vector_failures["blade_axis_world"],
              {"nonzero_direction_samples": sum(
                   axis is not None and any(component != 0.0 for component in axis)
                   for axis in parsed_vectors["blade_axis_world"]),
               "sample_count": len(frames)}, "unitless direction vectors", zero_axis_failures)

    phase_groups, phase_keys_valid, phase_key_errors = grouped_phase_keys(action.get("phase_keys"))
    cut_groups = [group for group in phase_groups if group["phase"] == "cut"]
    frame_cut_indexes = [index for index, row in enumerate(frames)
                         if isinstance(row, dict) and row.get("phase") == "cut"]
    cut_aim_failures: list[int] = []
    cut_aim_values: list[float] = []
    for index in frame_cut_indexes:
        row = frames[index]
        value = finite_number(row.get("blade_aim_error_degrees"))
        if value is None:
            cut_aim_failures.append(frame_id(row, index))
            continue
        magnitude = abs(value)
        cut_aim_values.append(magnitude)
        if magnitude > BLADE_AIM_MAX_DEGREES:
            cut_aim_failures.append(frame_id(row, index))
    add_check(checks, "phase_keys_and_distinct_cut_intervals",
              phase_keys_valid and len(cut_groups) >= 2,
              {"phase_summary": phase_groups, "cut_interval_count": len(cut_groups),
               "minimum_cut_intervals": 2}, "outgoing phase intervals", [],
              [{"phase_key_index": index} for index in phase_key_errors])
    add_check(checks, "cut_blade_aim_error",
              bool(frame_cut_indexes) and len(frame_cut_indexes) == len(cut_aim_values)
              and not cut_aim_failures,
              {"cut_frame_count": len(frame_cut_indexes),
               "maximum_degrees": max(cut_aim_values) if cut_aim_values else None,
               "threshold_degrees": BLADE_AIM_MAX_DEGREES},
              "degrees", cut_aim_failures)

    yaw_failures: list[int] = []
    yaw_endpoints: dict[str, Any] = {}
    if frames and isinstance(frames[0], dict) and isinstance(frames[-1], dict):
        first, last = frames[0], frames[-1]
        for field in YAW_FIELDS:
            start = finite_number(first.get(field))
            end = finite_number(last.get(field))
            difference = finite_number(abs(end - start)) if start is not None and end is not None else None
            yaw_endpoints[field] = {"first_degrees": start, "last_degrees": end,
                                    "difference_degrees": difference}
            if difference is None or difference > ENDPOINT_TOLERANCE:
                yaw_failures.extend((frame_id(first, 0), frame_id(last, len(frames) - 1)))
    else:
        yaw_failures.extend((1, len(frames)) if frames else [1, FRAME_COUNT])
    add_check(checks, "yaw_endpoint_match", bool(frames) and not yaw_failures,
              yaw_endpoints, "degrees", yaw_failures)

    for field in WORLD_VECTOR_FIELDS:
        differences: dict[str, Any] = {"first": None, "last": None, "distance": None}
        failures: list[int] = []
        if frames and isinstance(frames[0], dict) and isinstance(frames[-1], dict):
            first_vector = vector3(frames[0].get(field))
            last_vector = vector3(frames[-1].get(field))
            if first_vector is not None and last_vector is not None:
                difference = finite_number(math.dist(first_vector, last_vector))
                differences = {"first": list(first_vector), "last": list(last_vector),
                               "distance": difference}
                if difference is None or difference > ENDPOINT_TOLERANCE:
                    failures.extend((frame_id(frames[0], 0), frame_id(frames[-1], len(frames) - 1)))
            else:
                failures.extend((frame_id(frames[0], 0), frame_id(frames[-1], len(frames) - 1)))
        else:
            failures.extend((1, len(frames)) if frames else [1, FRAME_COUNT])
        add_check(checks, f"{field}_endpoint_match", bool(frames) and not failures,
                  differences, "metres" if field in POSITION_VECTOR_FIELDS else "unitless axis-vector magnitude",
                  failures)

    returns_to_guard = action.get("returns_to_initial_guard")
    last_phase_key = phase_groups[-1]["phase"] if phase_groups else None
    last_frame_phase = frames[-1].get("phase") if frames and isinstance(frames[-1], dict) else None
    add_check(checks, "final_guard_and_return", returns_to_guard is True
              and last_phase_key == "guard" and last_frame_phase == "guard",
              {"returns_to_initial_guard": returns_to_guard is True,
               "last_phase_key": last_phase_key, "last_frame_phase": last_frame_phase}, "boolean/phase")

    check_failures = sum(check["status"] == "FAIL" for check in checks)
    return {
        "id": set_entry["id"],
        "label": set_entry["label"],
        "cycle_report": str(set_entry["cycle_report"]),
        "status": "PASS" if check_failures == 0 else "FAIL",
        "summary": {"checks": len(checks), "passed": len(checks) - check_failures,
                    "failed": check_failures},
        "phase_summary": phase_groups,
        "frame_phase_counts": frame_phase_counts(frames),
        "trajectory_samples": {
            "right_wrist_world": parsed_vectors["right_wrist_world"],
            "blade_axis_world": parsed_vectors["blade_axis_world"],
        },
        "checks": checks,
    }


def rms_trajectory_difference(first: list[tuple[float, float, float]],
                               second: list[tuple[float, float, float]]) -> float | None:
    distances = [math.dist(left, right) for left, right in zip(first, second)]
    if not distances:
        return None
    rms = math.hypot(*distances) / math.sqrt(len(distances))
    return finite_number(rms)


def pairwise_diversity(first: dict[str, Any], second: dict[str, Any]) -> dict[str, Any]:
    wrist_first = first["trajectory_samples"]["right_wrist_world"]
    wrist_second = second["trajectory_samples"]["right_wrist_world"]
    axis_first = first["trajectory_samples"]["blade_axis_world"]
    axis_second = second["trajectory_samples"]["blade_axis_world"]

    wrist_ready = (
        len(wrist_first) == FRAME_COUNT and len(wrist_second) == FRAME_COUNT
        and all(value is not None for value in wrist_first + wrist_second)
    )
    axes_ready = (len(axis_first) == FRAME_COUNT and len(axis_second) == FRAME_COUNT
                  and all(value is not None for value in axis_first + axis_second))
    wrist_rms: float | None = None
    blade_angle_rms: float | None = None
    tip_proxy_rms: float | None = None
    if wrist_ready:
        wrist_rms = rms_trajectory_difference(wrist_first, wrist_second)
    if wrist_ready and axes_ready:
        angles: list[float] = []
        first_proxy: list[tuple[float, float, float]] = []
        second_proxy: list[tuple[float, float, float]] = []
        for wrist_a, wrist_b, axis_a_raw, axis_b_raw in zip(
                wrist_first, wrist_second, axis_first, axis_second):
            axis_a = normalized_axis(axis_a_raw)
            axis_b = normalized_axis(axis_b_raw)
            if axis_a is None or axis_b is None:
                axes_ready = False
                break
            dot = max(-1.0, min(1.0, sum(axis_a[i] * axis_b[i] for i in range(3))))
            angles.append(math.degrees(math.acos(dot)))
            first_proxy.append(tuple(wrist_a[i] + axis_a[i] * TIP_PROXY_SCALE_M for i in range(3)))
            second_proxy.append(tuple(wrist_b[i] + axis_b[i] * TIP_PROXY_SCALE_M for i in range(3)))
        if axes_ready and len(angles) == FRAME_COUNT:
            blade_angle_rms = math.sqrt(sum(angle * angle for angle in angles) / len(angles))
            tip_proxy_rms = rms_trajectory_difference(first_proxy, second_proxy)

    passed_by_wrist = wrist_rms is not None and wrist_rms > MIN_WRIST_RMS_M
    passed_by_blade = (blade_angle_rms is not None
                       and blade_angle_rms > MIN_BLADE_ANGLE_RMS_DEGREES)
    return {
        "first_id": first["id"],
        "second_id": second["id"],
        "status": "PASS" if passed_by_wrist or passed_by_blade else "FAIL",
        "sample_count": FRAME_COUNT if wrist_ready and axes_ready else 0,
        "right_wrist_sample_count": FRAME_COUNT if wrist_ready else 0,
        "blade_angle_sample_count": FRAME_COUNT if axes_ready and blade_angle_rms is not None else 0,
        "right_wrist_rms_m": wrist_rms,
        "right_wrist_threshold_m": MIN_WRIST_RMS_M,
        "blade_angle_rms_degrees": blade_angle_rms,
        "blade_angle_threshold_degrees": MIN_BLADE_ANGLE_RMS_DEGREES,
        "tip_proxy_rms_m": tip_proxy_rms,
        "tip_proxy_definition": {
            "formula": "right_wrist_world + normalized(blade_axis_world) * proxy_scale_m",
            "proxy_scale_m": TIP_PROXY_SCALE_M,
            "blade_length_claimed": False,
        },
        "distinct_trajectory_by": ("right_wrist_world" if passed_by_wrist
                                    else "blade_axis_world" if passed_by_blade else None),
    }


def inspect_catalog(entries: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    by_id = {entry["id"]: entry for entry in entries}
    ordered = [by_id[set_id] for set_id in EXPECTED_IDS]
    catalog_checks = [
        {"name": "catalog_version", "status": "PASS", "observed": 1, "expected": 1,
         "unit": "version"},
        {"name": "exact_five_unique_set_ids", "status": "PASS",
         "observed": [entry["id"] for entry in ordered],
         "expected": list(EXPECTED_IDS), "unit": "set IDs"},
    ]
    inspected: list[dict[str, Any]] = []
    for entry in ordered:
        report_path: Path = entry["cycle_report"]
        try:
            with report_path.open("r", encoding="utf-8") as stream:
                source = json.load(stream)
            result = inspect_set(entry, source)
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            result = {
                "id": entry["id"],
                "label": entry["label"],
                "cycle_report": str(report_path),
                "status": "FAIL",
                "summary": {"checks": 1, "passed": 0, "failed": 1},
                "phase_summary": [],
                "frame_phase_counts": {},
                "trajectory_samples": {"right_wrist_world": [], "blade_axis_world": []},
                "checks": [{"name": "cycle_report_readable_json", "status": "FAIL",
                            "observed": str(exc), "unit": "JSON report",
                            "failure_frames": []}],
            }
        inspected.append(result)
    return catalog_checks, inspected


def validate_catalog_shape(catalog: Any) -> list[dict[str, Any]]:
    if not isinstance(catalog, dict):
        raise ValueError("catalog JSON must be an object")
    version = catalog.get("version")
    if isinstance(version, bool) or not isinstance(version, int) or version != 1:
        raise ValueError("catalog version must be 1")
    entries = catalog.get("sets")
    if not isinstance(entries, list) or len(entries) != len(EXPECTED_IDS):
        raise ValueError(f"catalog sets must contain exactly {len(EXPECTED_IDS)} entries")
    seen: set[str] = set()
    normalized: list[dict[str, Any]] = []
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ValueError(f"catalog sets[{index}] must be an object")
        set_id = entry.get("id")
        label = entry.get("label")
        raw_report = entry.get("cycle_report")
        if not isinstance(set_id, str) or set_id not in EXPECTED_IDS:
            raise ValueError(f"catalog sets[{index}].id must be one of {', '.join(EXPECTED_IDS)}")
        if set_id in seen:
            raise ValueError(f"duplicate set id in catalog: {set_id}")
        seen.add(set_id)
        if not isinstance(label, str) or not label.strip():
            raise ValueError(f"catalog sets[{index}].label must be a non-empty string")
        if not isinstance(raw_report, str):
            raise ValueError(f"catalog sets[{index}].cycle_report must be an absolute JSON path")
        report_path = Path(raw_report)
        if not report_path.is_absolute():
            raise ValueError(f"catalog sets[{index}].cycle_report must be absolute: {raw_report}")
        normalized.append({"id": set_id, "label": label, "cycle_report": report_path})
    if seen != set(EXPECTED_IDS):
        raise ValueError("catalog must contain exactly these IDs: " + ", ".join(EXPECTED_IDS))
    return normalized


def symlink_components(path: Path) -> list[Path]:
    components: list[Path] = []
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current = current / part
        if current.is_symlink():
            components.append(current)
    return components


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", required=True, type=Path,
                        help="absolute path to the five-set catalog JSON")
    parser.add_argument("--out", required=True, type=Path,
                        help="new absolute path for the JSON verification report")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    catalog_path: Path = args.catalog
    output_path: Path = args.out
    if not catalog_path.is_absolute():
        parser.error("--catalog must be an absolute path")
    if not output_path.is_absolute():
        parser.error("--out must be an absolute path")
    if not catalog_path.is_file():
        parser.error(f"--catalog must name an existing file: {catalog_path}")
    if output_path.exists() or output_path.is_symlink():
        parser.error(f"--out must be a new path; refusing to overwrite: {output_path}")
    if not output_path.parent.is_dir():
        parser.error(f"--out parent directory must already exist: {output_path.parent}")

    for path_name, path in (("--catalog", catalog_path), ("--out", output_path)):
        found = symlink_components(path)
        if found:
            parser.error(f"{path_name} path contains a symlink: {found[0]}")

    try:
        with catalog_path.open("r", encoding="utf-8") as stream:
            catalog_source = json.load(stream)
        entries = validate_catalog_shape(catalog_source)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        parser.error(f"cannot use catalog: {exc}")

    for entry in entries:
        path = entry["cycle_report"]
        if symlink_components(path):
            parser.error(f"cycle_report path contains a symlink: {path}")

    source_paths = [catalog_path.resolve(strict=True)]
    source_paths.extend(entry["cycle_report"].resolve(strict=False) for entry in entries)
    if output_path.resolve(strict=False) in source_paths:
        parser.error("--out must not refer to the catalog or any cycle report")

    catalog_checks, sets = inspect_catalog(entries)
    pairwise = [pairwise_diversity(sets[left], sets[right])
                for left in range(len(sets)) for right in range(left + 1, len(sets))]
    failed_set_checks = sum(check["status"] == "FAIL"
                            for entry in sets for check in entry["checks"])
    failed_catalog_checks = sum(check["status"] == "FAIL" for check in catalog_checks)
    failed_pairs = sum(item["status"] == "FAIL" for item in pairwise)
    failed_sets = sum(entry["status"] == "FAIL" for entry in sets)
    status = "PASS" if not (failed_set_checks or failed_catalog_checks or failed_pairs) else "FAIL"
    result = {
        "schema_version": 1,
        "status": status,
        "catalog": str(catalog_path),
        "summary": {
            "sets": len(sets),
            "sets_passed": len(sets) - failed_sets,
            "sets_failed": failed_sets,
            "set_checks_failed": failed_set_checks,
            "pairwise_checks": len(pairwise),
            "pairwise_checks_failed": failed_pairs,
            "catalog_checks_failed": failed_catalog_checks,
        },
        "catalog_checks": catalog_checks,
        "sets": sets,
        "pairwise_diversity": pairwise,
        "limitations": {
            "source_geometry_checked": False,
            "palette_checked": False,
            "rigid_grip_checked": False,
            "render_checked": False,
            "artistic_or_visual_acceptance": False,
            "tip_proxy_uses_actual_blade_length": False,
            "statement": (
                "JSON numeric checks only. Trajectory comparison demonstrates measured differences; "
                "it does not establish artistic variety, source-geometry correctness, palette, "
                "rigid grip, render quality, or visual acceptance. The tip proxy uses a synthetic "
                "unit-axis scale and does not claim actual blade length."
            ),
        },
    }

    try:
        payload = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
        with output_path.open("x", encoding="utf-8") as stream:
            stream.write(payload)
    except FileExistsError:
        parser.error(f"--out appeared during verification; refusing to overwrite: {output_path}")
    except (OSError, ValueError) as exc:
        parser.error(f"cannot write verification report: {exc}")
    print(f"{status} {output_path}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
