#!/usr/bin/env python3
"""Check the numeric motion contract in a Jiang sword cycle report.

This report-only verifier reads JSON; it does not inspect Blender files or
render images. PASS is not motion-capture evidence, visual acceptance, or a
claim about standard swordsmanship.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


FRAME_COUNT = 180
FPS = 30
DURATION_SECONDS = 6.0
YAW_FIELDS = ("pelvis_yaw", "torso_yaw", "head_yaw")
YAW_TOLERANCE_DEGREES = 1.0e-6
TIME_TOLERANCE_SECONDS = 1.0e-9
CUT_START_SECONDS = 1.45
CUT_END_SECONDS = 1.65
CUT_TOLERANCE_SECONDS = 1.0e-6
RIGHT_WRIST_TARGET_MAX_M = 1.0e-5
WRIST_BEND_MAX_DEGREES = 55.01
BLADE_AIM_MAX_DEGREES = 10.0


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
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return found
    if isinstance(value, int):
        return found
    if isinstance(value, (int, float)):
        try:
            finite = math.isfinite(value)
        except OverflowError:
            finite = True
        if not finite:
            found.append(path)
        return found
    if isinstance(value, list):
        for index, item in enumerate(value):
            found.extend(nonfinite_paths(item, f"{path}[{index}]"))
    elif isinstance(value, dict):
        for key, item in value.items():
            found.extend(nonfinite_paths(item, f"{path}.{key}"))
    return found


def frame_id(row: Any, index: int) -> int:
    if isinstance(row, dict):
        number = finite_number(row.get("frame"))
        if number is not None and number.is_integer():
            return int(number)
    return index + 1


def frame_ids_with_nonfinite(frames: Any) -> list[int]:
    if not isinstance(frames, list):
        return []
    result = []
    for index, row in enumerate(frames):
        if nonfinite_paths(row, f"frames[{index}]"):
            result.append(frame_id(row, index))
    return result


def phase_key_summary(phase_keys: Any) -> tuple[list[dict[str, Any]], bool]:
    if not isinstance(phase_keys, list) or not phase_keys:
        return [], False

    merged: list[dict[str, Any]] = []
    previous_seconds: float | None = None
    valid = True
    previous_index = -2
    for index, item in enumerate(phase_keys):
        if not isinstance(item, dict):
            valid = False
            previous_index = index
            continue
        seconds = finite_number(item.get("seconds"))
        phase = item.get("phase")
        if seconds is None or not isinstance(phase, str) or not phase:
            valid = False
            previous_index = index
            continue
        if previous_seconds is not None and seconds <= previous_seconds:
            valid = False
        previous_seconds = seconds

        if merged and merged[-1]["phase"] == phase and previous_index == index - 1:
            merged[-1]["end_seconds"] = seconds
            merged[-1]["key_count"] += 1
        else:
            merged.append({
                "phase": phase,
                "start_seconds": seconds,
                "end_seconds": seconds,
                "key_count": 1,
            })
        previous_index = index
    # Each key labels the outgoing interval, so a phase ends at the next phase's start.
    for index in range(len(merged)-1):
        merged[index]["end_seconds"] = merged[index+1]["start_seconds"]
    return merged, valid


def add_check(
    checks: list[dict[str, Any]],
    name: str,
    passed: bool,
    observed: Any,
    unit: str,
    failure_frames: list[int] | None = None,
) -> None:
    checks.append({
        "name": name,
        "status": "PASS" if passed else "FAIL",
        "observed": observed,
        "unit": unit,
        "failure_frames": sorted(set(failure_frames or [])),
    })


def inspect_report(source: Any, input_path: Path) -> dict[str, Any]:
    action = source.get("action") if isinstance(source, dict) else None
    action_obj = action if isinstance(action, dict) else {}
    frames = action_obj.get("frames")
    frame_rows = frames if isinstance(frames, list) else []
    checks: list[dict[str, Any]] = []

    add_check(
        checks,
        "action_object_present",
        isinstance(action, dict),
        isinstance(action, dict),
        "boolean",
    )
    profile = action_obj.get("timing_profile")
    add_check(checks, "timing_profile", profile == "jianshu-v1", profile, "profile")

    declared_count = finite_number(action_obj.get("frame_count"))
    add_check(
        checks,
        "frame_count",
        isinstance(frames, list) and len(frame_rows) == FRAME_COUNT and declared_count == FRAME_COUNT,
        {"frame_count": action_obj.get("frame_count"), "frames_length": len(frame_rows)},
        "frames",
    )
    fps = finite_number(action_obj.get("fps"))
    add_check(checks, "fps", fps == FPS, action_obj.get("fps"), "frames/second")
    duration = finite_number(action_obj.get("duration_seconds"))
    add_check(
        checks,
        "duration",
        duration is not None and abs(duration - DURATION_SECONDS) <= TIME_TOLERANCE_SECONDS,
        action_obj.get("duration_seconds"),
        "seconds",
    )

    bad_numeric_paths = nonfinite_paths(action_obj)
    add_check(
        checks,
        "all_action_numbers_finite",
        not bad_numeric_paths,
        {"nonfinite_count": len(bad_numeric_paths), "nonfinite_paths": bad_numeric_paths[:50]},
        "numeric values",
        frame_ids_with_nonfinite(frames),
    )

    required_numeric = (
        "frame", "seconds", "pelvis_yaw", "torso_yaw", "head_yaw", "left_step_lift",
        "wrist_bend_degrees", "max_bone_head_error", "right_wrist_target_error_m",
        "blade_aim_error_degrees",
    )
    schema_failures: list[int] = []
    sample_failures: list[int] = []
    right_error_failures: list[int] = []
    wrist_bend_failures: list[int] = []
    frame_labels = [frame_id(row, index) for index, row in enumerate(frame_rows)]

    for index, row in enumerate(frame_rows):
        label = frame_id(row, index)
        if not isinstance(row, dict):
            schema_failures.append(label)
            sample_failures.append(label)
            right_error_failures.append(label)
            wrist_bend_failures.append(label)
            continue

        for field in required_numeric:
            if finite_number(row.get(field)) is None:
                schema_failures.append(label)
                break
        if not isinstance(row.get("phase"), str) or not row.get("phase"):
            schema_failures.append(label)
        ik = row.get("leg_ik_target_errors")
        if not isinstance(ik, dict) or any(finite_number(ik.get(side)) is None for side in ("R", "L")):
            schema_failures.append(label)

        frame_value = finite_number(row.get("frame"))
        seconds_value = finite_number(row.get("seconds"))
        expected_seconds = index / FPS
        if (frame_value is None or frame_value != index + 1 or seconds_value is None
                or abs(seconds_value - expected_seconds) > TIME_TOLERANCE_SECONDS):
            sample_failures.append(label)

        wrist_error = finite_number(row.get("right_wrist_target_error_m"))
        if wrist_error is None or wrist_error > RIGHT_WRIST_TARGET_MAX_M:
            right_error_failures.append(label)
        bend = finite_number(row.get("wrist_bend_degrees"))
        if bend is None or bend > WRIST_BEND_MAX_DEGREES:
            wrist_bend_failures.append(label)

    add_check(
        checks,
        "frame_fields_and_ik_values",
        isinstance(frames, list) and len(frame_rows) == FRAME_COUNT and not schema_failures,
        {"required_fields": list(required_numeric) + ["phase", "leg_ik_target_errors.R", "leg_ik_target_errors.L"],
         "rows": len(frame_rows)},
        "fields and numeric values",
        schema_failures,
    )
    add_check(
        checks,
        "frame_sampling",
        isinstance(frames, list) and len(frame_rows) == FRAME_COUNT and not sample_failures,
        {"expected": "frame n has seconds (n-1)/30", "sample_count": len(frame_rows)},
        "seconds at 30 fps",
        sample_failures,
    )

    merged_keys, valid_keys = phase_key_summary(action_obj.get("phase_keys"))
    cut_runs = [item for item in merged_keys if item["phase"] == "cut"]
    cut_span_ok = (
        valid_keys and len(cut_runs) == 1 and cut_runs[0]["key_count"] >= 2
        and abs(cut_runs[0]["start_seconds"] - CUT_START_SECONDS) <= CUT_TOLERANCE_SECONDS
        and abs(cut_runs[0]["end_seconds"] - CUT_END_SECONDS) <= CUT_TOLERANCE_SECONDS
    )
    add_check(
        checks,
        "merged_cut_key_interval",
        cut_span_ok,
        {"merged_phase_keys": merged_keys, "cut_runs": cut_runs,
         "duration_seconds": (cut_runs[0]["end_seconds"] - cut_runs[0]["start_seconds"]
                              if len(cut_runs) == 1 else None)},
        "seconds; cut key interval 1.45 to 1.65",
    )

    valid_right_errors = [finite_number(row.get("right_wrist_target_error_m"))
                          for row in frame_rows if isinstance(row, dict)]
    valid_right_errors = [value for value in valid_right_errors if value is not None]
    add_check(
        checks,
        "right_wrist_target_error",
        len(frame_rows) == FRAME_COUNT and not right_error_failures,
        {"maximum_m": max(valid_right_errors) if valid_right_errors else None,
         "threshold_m": RIGHT_WRIST_TARGET_MAX_M,
         "finite_samples": len(valid_right_errors)},
        "metres",
        right_error_failures,
    )

    valid_bends = [finite_number(row.get("wrist_bend_degrees"))
                   for row in frame_rows if isinstance(row, dict)]
    valid_bends = [value for value in valid_bends if value is not None]
    add_check(
        checks,
        "wrist_bend_maximum",
        len(frame_rows) == FRAME_COUNT and not wrist_bend_failures,
        {"maximum_degrees": max(valid_bends) if valid_bends else None,
         "threshold_degrees": WRIST_BEND_MAX_DEGREES,
         "finite_samples": len(valid_bends)},
        "degrees",
        wrist_bend_failures,
    )

    cut_rows: list[tuple[int, dict[str, Any]]] = []
    invalid_time_frames: list[int] = []
    for index, row in enumerate(frame_rows):
        if not isinstance(row, dict):
            continue
        seconds = finite_number(row.get("seconds"))
        if seconds is None:
            invalid_time_frames.append(frame_id(row, index))
        elif CUT_START_SECONDS <= seconds <= CUT_END_SECONDS:
            cut_rows.append((index, row))
    cut_aim_values = [finite_number(row.get("blade_aim_error_degrees")) for _, row in cut_rows]
    finite_cut_aims = [value for value in cut_aim_values if value is not None]
    blade_failures = [
        frame_id(row, index)
        for index, row in cut_rows
        if (finite_number(row.get("blade_aim_error_degrees")) is None
            or finite_number(row.get("blade_aim_error_degrees")) > BLADE_AIM_MAX_DEGREES)
    ] + invalid_time_frames
    add_check(
        checks,
        "cut_blade_aim_error",
        bool(cut_rows) and not blade_failures and len(finite_cut_aims) == len(cut_rows),
        {"cut_interval_seconds": [CUT_START_SECONDS, CUT_END_SECONDS],
         "sample_count": len(cut_rows),
         "maximum_degrees": max(finite_cut_aims) if finite_cut_aims else None,
         "threshold_degrees": BLADE_AIM_MAX_DEGREES},
        "degrees",
        blade_failures,
    )

    endpoint_failures: list[int] = []
    yaw_observed: dict[str, Any] = {}
    if frame_rows and isinstance(frame_rows[0], dict) and isinstance(frame_rows[-1], dict):
        first, last = frame_rows[0], frame_rows[-1]
        for field in YAW_FIELDS:
            start = finite_number(first.get(field))
            end = finite_number(last.get(field))
            yaw_observed[field] = {"first_degrees": start, "last_degrees": end,
                                   "difference_degrees": abs(end - start) if start is not None and end is not None else None}
            if (start is None or end is None or abs(start) > YAW_TOLERANCE_DEGREES
                    or abs(end) > YAW_TOLERANCE_DEGREES or abs(end - start) > YAW_TOLERANCE_DEGREES):
                endpoint_failures.extend((frame_id(first, 0), frame_id(last, len(frame_rows) - 1)))
    else:
        endpoint_failures.extend((frame_labels[0], frame_labels[-1]) if frame_labels else [])
    add_check(
        checks,
        "yaw_endpoints_zero_and_matching",
        bool(frame_rows) and not endpoint_failures and len(yaw_observed) == len(YAW_FIELDS),
        yaw_observed,
        "degrees",
        endpoint_failures,
    )

    returns_to_guard = action_obj.get("returns_to_initial_guard")
    add_check(
        checks,
        "returns_to_initial_guard",
        returns_to_guard is True,
        returns_to_guard,
        "boolean",
    )

    failures = sum(item["status"] == "FAIL" for item in checks)
    return {
        "schema_version": 1,
        "status": "PASS" if failures == 0 else "FAIL",
        "input_cycle_report": str(input_path),
        "summary": {"checks": len(checks), "passed": len(checks) - failures, "failed": failures},
        "checks": checks,
        "limitations": {
            "motion_capture": False,
            "visual_acceptance": False,
            "standard_swordsmanship_claim": False,
            "statement": "Numeric report checks only; this is not motion-capture evidence, visual acceptance, or a claim about standard swordsmanship.",
        },
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cycle-report", required=True, type=Path,
                        help="absolute path to a cycle-report JSON file")
    parser.add_argument("--out", required=True, type=Path,
                        help="new absolute path for the JSON verification report")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    input_path: Path = args.cycle_report
    output_path: Path = args.out
    if not input_path.is_absolute():
        parser.error("--cycle-report must be an absolute path")
    if not input_path.is_file():
        parser.error(f"--cycle-report must name an existing file: {input_path}")
    if not output_path.is_absolute():
        parser.error("--out must be an absolute path")
    if output_path.exists() or output_path.is_symlink():
        parser.error(f"--out must be a new path; refusing to overwrite: {output_path}")
    if not output_path.parent.is_dir():
        parser.error(f"--out parent directory must already exist: {output_path.parent}")
    if output_path.resolve(strict=False) == input_path.resolve(strict=True):
        parser.error("--out must not refer to the input report")

    try:
        with input_path.open("r", encoding="utf-8") as stream:
            source = json.load(stream)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        parser.error(f"cannot read cycle-report JSON: {exc}")

    result = inspect_report(source, input_path)
    try:
        with output_path.open("x", encoding="utf-8") as stream:
            json.dump(result, stream, ensure_ascii=False, indent=2, allow_nan=False)
            stream.write("\n")
    except FileExistsError:
        parser.error(f"--out appeared during verification; refusing to overwrite: {output_path}")
    except OSError as exc:
        parser.error(f"cannot write verification report: {exc}")
    print(f"{result['status']} {output_path}")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
