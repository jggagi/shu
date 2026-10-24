#!/usr/bin/env python3
"""Compare measured timing and motion values in two sword cycle reports.

This is a report-only check. It does not inspect blend files or render frames,
and its PASS result does not establish visual or player acceptance.
"""
from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from pathlib import Path
from typing import Any


YAW_FIELDS = ("pelvis_yaw", "torso_yaw", "head_yaw")
YAW_MATCH_TOLERANCE_DEGREES = 1e-4
CUT_TARGET_SECONDS = 0.20
CUT_TARGET_TOLERANCE_SECONDS = 1e-6
LANDING_THRESHOLD = 1e-5
IK_MAXIMUM = 1e-4
WRIST_MAXIMUM_DEGREES = 55.01


def finite_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) else None


def all_numbers_finite(value: Any) -> bool:
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return True
    if isinstance(value, (int, float)):
        return math.isfinite(float(value))
    if isinstance(value, list):
        return all(all_numbers_finite(item) for item in value)
    if isinstance(value, dict):
        return all(all_numbers_finite(item) for item in value.values())
    return True


def read_report(path: Path) -> dict[str, Any]:
    if not path.is_absolute():
        raise ValueError(f"input path must be absolute: {path}")
    if not path.is_file():
        raise ValueError(f"input report does not exist or is not a file: {path}")
    try:
        with path.open("r", encoding="utf-8") as stream:
            value = json.load(stream)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read JSON report {path}: {exc}") from exc
    if not isinstance(value, dict) or not isinstance(value.get("action"), dict):
        raise ValueError(f"report must contain an action object: {path}")
    frames = value["action"].get("frames")
    if not isinstance(frames, list) or not frames or not all(isinstance(row, dict) for row in frames):
        raise ValueError(f"action.frames must be a non-empty array of objects: {path}")
    return value


def safe_series(action: dict[str, Any], field: str) -> list[tuple[float, float]] | None:
    frames = action.get("frames")
    if not isinstance(frames, list) or not frames:
        return None
    pairs: list[tuple[float, float]] = []
    for row in frames:
        if not isinstance(row, dict):
            return None
        seconds = finite_number(row.get("seconds"))
        value = finite_number(row.get(field))
        if seconds is None or value is None:
            return None
        pairs.append((seconds, value))
    if any(pairs[i][0] <= pairs[i - 1][0] for i in range(1, len(pairs))):
        return None
    return pairs


def angular_velocity(action: dict[str, Any], field: str) -> dict[str, Any] | None:
    series = safe_series(action, field)
    if not series or len(series) < 2:
        return None
    maximum = -1.0
    peak_start: float | None = None
    peak_end: float | None = None
    for (start, first), (end, second) in zip(series, series[1:]):
        delta = abs((second - first + 180.0) % 360.0 - 180.0)
        speed = delta / (end - start)
        if speed > maximum:
            maximum, peak_start, peak_end = speed, start, end
    return {
        "maximum_degrees_per_second": maximum,
        "peak_interval_seconds": [peak_start, peak_end],
        "nonzero_peak_time_seconds": (peak_start + peak_end) / 2.0 if maximum > 0 else None,
    }


def max_frame_value(action: dict[str, Any], field: str) -> dict[str, Any] | None:
    series = safe_series(action, field)
    if not series:
        return None
    value, seconds = max(((value, seconds) for seconds, value in series), key=lambda pair: pair[0])
    return {"maximum": value, "seconds": seconds}


def maximum_nested_values(action: dict[str, Any], field: str) -> dict[str, Any] | None:
    frames = action.get("frames")
    if not isinstance(frames, list):
        return None
    maximum = -1.0
    maximum_at: float | None = None
    for row in frames:
        if not isinstance(row, dict) or not isinstance(row.get(field), dict):
            return None
        seconds = finite_number(row.get("seconds"))
        if seconds is None or not row[field]:
            return None
        for value in row[field].values():
            number = finite_number(value)
            if number is None:
                return None
            if number > maximum:
                maximum, maximum_at = number, seconds
    if maximum < 0:
        return None
    return {"maximum": maximum, "seconds": maximum_at}


def yaw_endpoints(action: dict[str, Any]) -> dict[str, Any]:
    frames = action.get("frames", [])
    endpoints: dict[str, Any] = {}
    for field in YAW_FIELDS:
        first = finite_number(frames[0].get(field)) if frames and isinstance(frames[0], dict) else None
        last = finite_number(frames[-1].get(field)) if frames and isinstance(frames[-1], dict) else None
        if first is None or last is None:
            endpoints[field] = {"start_degrees": first, "end_degrees": last, "matches": None}
        else:
            delta = abs((last - first + 180.0) % 360.0 - 180.0)
            start_from_zero = abs((first + 180.0) % 360.0 - 180.0)
            end_from_zero = abs((last + 180.0) % 360.0 - 180.0)
            endpoints[field] = {
                "start_degrees": first,
                "end_degrees": last,
                "absolute_difference_degrees": delta,
                "matches": delta <= YAW_MATCH_TOLERANCE_DEGREES,
                "start_from_zero_degrees": start_from_zero,
                "end_from_zero_degrees": end_from_zero,
                "both_zero": (start_from_zero <= YAW_MATCH_TOLERANCE_DEGREES
                              and end_from_zero <= YAW_MATCH_TOLERANCE_DEGREES
                              and delta <= YAW_MATCH_TOLERANCE_DEGREES),
            }
    return endpoints


def sample_step_seconds(action: dict[str, Any]) -> float | None:
    series = safe_series(action, "seconds")
    if series is None or len(series) < 2:
        # safe_series expects a value as well as a time, so read timestamps directly.
        frames = action.get("frames", [])
        timestamps = [finite_number(row.get("seconds")) for row in frames if isinstance(row, dict)]
        if len(timestamps) != len(frames) or len(timestamps) < 2 or any(t is None for t in timestamps):
            return None
    else:
        timestamps = [pair[0] for pair in series]
    deltas = [timestamps[i] - timestamps[i - 1] for i in range(1, len(timestamps))]
    if any(delta <= 0 for delta in deltas):
        return None
    return statistics.median(deltas)


def cut_spans(action: dict[str, Any]) -> list[dict[str, float]]:
    keys = action.get("phase_keys")
    spans: list[dict[str, float]] = []
    if isinstance(keys, list) and keys:
        normalized: list[tuple[float, str]] = []
        for key in keys:
            if not isinstance(key, dict):
                continue
            seconds = finite_number(key.get("seconds"))
            phase = key.get("phase")
            if seconds is not None and isinstance(phase, str):
                normalized.append((seconds, phase))
        normalized.sort(key=lambda item: item[0])
        for index, (start, phase) in enumerate(normalized):
            if phase != "cut":
                continue
            end = next((time for time, next_phase in normalized[index + 1:] if next_phase != "cut"), None)
            if end is None:
                duration = finite_number(action.get("duration_seconds"))
                if duration is None:
                    frames = action.get("frames", [])
                    duration = finite_number(frames[-1].get("seconds")) if frames and isinstance(frames[-1], dict) else None
                end = duration
            if end is not None and end >= start:
                spans.append({"start_seconds": start, "end_seconds": end, "duration_seconds": end - start})
        if spans:
            return spans

    frames = action.get("frames", [])
    rows: list[tuple[float, str]] = []
    for row in frames:
        if not isinstance(row, dict):
            return []
        seconds = finite_number(row.get("seconds"))
        phase = row.get("phase")
        if seconds is None or not isinstance(phase, str):
            return []
        rows.append((seconds, phase))
    if not rows:
        return []
    step = sample_step_seconds(action)
    if step is None:
        return []
    start_index: int | None = None
    for index, (_, phase) in enumerate(rows):
        if phase == "cut" and start_index is None:
            start_index = index
        if start_index is not None and (phase != "cut" or index == len(rows) - 1):
            end_index = index if phase != "cut" else index + 1
            start = rows[start_index][0]
            end = rows[end_index][0] if end_index < len(rows) else rows[-1][0] + step
            spans.append({"start_seconds": start, "end_seconds": end, "duration_seconds": end - start})
            start_index = None
    return spans


def endpoint_pose_hold(action: dict[str, Any]) -> dict[str, Any] | None:
    keys = action.get("phase_keys")
    if not isinstance(keys, list) or not keys:
        return None
    normalized = []
    for key in keys:
        if not isinstance(key, dict):
            continue
        seconds = finite_number(key.get("seconds"))
        phase = key.get("phase")
        if seconds is not None and isinstance(phase, str):
            normalized.append((seconds, phase))
    if not normalized:
        return None
    normalized.sort(key=lambda item: item[0])
    if normalized[-1][1] != "guard":
        return None
    first_guard_index = len(normalized) - 1
    while first_guard_index > 0 and normalized[first_guard_index - 1][1] == "guard":
        first_guard_index -= 1
    start = normalized[first_guard_index][0]
    end = finite_number(action.get("duration_seconds"))
    frames = action.get("frames", [])
    last_sample = (finite_number(frames[-1].get("seconds"))
                   if frames and isinstance(frames[-1], dict) else None)
    if end is None:
        return None
    return {
        "phase": "guard",
        "declared_start_seconds": start,
        "declared_end_seconds": end,
        "declared_duration_seconds": end - start,
        "discrete_last_sample_seconds": last_sample,
    }


def clean_phase_keys(action: dict[str, Any]) -> list[dict[str, Any]] | None:
    keys = action.get("phase_keys")
    if not isinstance(keys, list):
        return None
    cleaned = []
    for key in keys:
        if not isinstance(key, dict):
            continue
        phase = key.get("phase")
        cleaned.append({
            "seconds": finite_number(key.get("seconds")),
            "phase": phase if isinstance(phase, str) else None,
        })
    return cleaned


def first_step_landing(action: dict[str, Any]) -> dict[str, Any] | None:
    series = safe_series(action, "left_step_lift")
    if not series:
        return None
    start_index = next((index for index, (_, lift) in enumerate(series) if lift > LANDING_THRESHOLD), None)
    if start_index is None:
        return {
            "selection_rule": "first lift > 1e-5 through the next landing < 1e-5",
            "episode_start_seconds": None,
            "peak_lift": None,
            "peak_seconds": None,
            "peak_frame": None,
            "landing_seconds": None,
            "landing_frame": None,
        }
    landing = next(((seconds, index) for index, (seconds, lift) in enumerate(series)
                    if index > start_index and lift < LANDING_THRESHOLD), None)
    peak_end_index = landing[1] if landing else len(series)
    peak_index, (peak_seconds, peak_lift) = max(
        enumerate(series[start_index:peak_end_index], start=start_index),
        key=lambda item: item[1][1],
    )
    frames = action.get("frames", [])

    def frame_at(index: int | None) -> Any:
        if index is None or index >= len(frames) or not isinstance(frames[index], dict):
            return None
        return frames[index].get("frame")

    return {
        "selection_rule": "first lift > 1e-5 through the next landing < 1e-5",
        "episode_start_seconds": series[start_index][0],
        "peak_lift": peak_lift,
        "peak_seconds": peak_seconds,
        "peak_frame": frame_at(peak_index),
        "landing_threshold": LANDING_THRESHOLD,
        "landing_seconds": landing[0] if landing else None,
        "landing_frame": frame_at(landing[1]) if landing else None,
    }


def action_metrics(action: dict[str, Any]) -> dict[str, Any]:
    velocities = {field: angular_velocity(action, field) for field in YAW_FIELDS}
    endpoints = yaw_endpoints(action)
    cut = cut_spans(action)
    left_foot = max_frame_value(action, "left_step_lift")
    return {
        "timing_profile": action.get("timing_profile"),
        "phase_keys": clean_phase_keys(action),
        "frame_count": action.get("frame_count", len(action.get("frames", []))),
        "fps": action.get("fps"),
        "duration_seconds": action.get("duration_seconds"),
        "all_numeric_values_finite": all_numbers_finite(action),
        "maximum_angular_velocity": velocities,
        "cut_phase_spans": cut,
        "maximum_left_step_lift": ({**left_foot, "unit": "Blender scene units (source report)"}
                                    if left_foot else None),
        "first_step_landing": first_step_landing(action),
        "yaw_endpoints": endpoints,
        "maximum_wrist_bend_degrees": max_frame_value(action, "wrist_bend_degrees"),
        "maximum_leg_ik_target_error": maximum_nested_values(action, "leg_ik_target_errors"),
        "maximum_bone_head_error": max_frame_value(action, "max_bone_head_error"),
        "returns_to_initial_guard": action.get("returns_to_initial_guard"),
        "endpoint_pose_hold": endpoint_pose_hold(action),
    }


def first_cut_duration(metrics: dict[str, Any]) -> float | None:
    spans = metrics.get("cut_phase_spans")
    if not isinstance(spans, list) or not spans:
        return None
    return finite_number(spans[0].get("duration_seconds"))


def add_check(checks: list[dict[str, Any]], name: str, passed: bool | None,
              observed: Any, requirement: str) -> None:
    checks.append({
        "name": name,
        "status": "PASS" if passed is True else "FAIL" if passed is False else "UNAVAILABLE",
        "observed": observed,
        "requirement": requirement,
    })


def build_result(before_path: Path, after_path: Path,
                 before_report: dict[str, Any], after_report: dict[str, Any]) -> dict[str, Any]:
    before = action_metrics(before_report["action"])
    after = action_metrics(after_report["action"])
    checks: list[dict[str, Any]] = []
    frames = after_report["action"]["frames"]
    frame_count = finite_number(after.get("frame_count"))
    fps = finite_number(after.get("fps"))
    duration = finite_number(after.get("duration_seconds"))
    add_check(checks, "new_action_180_frames", frame_count == 180 and len(frames) == 180,
              {"frame_count_field": after.get("frame_count"), "frames_array_length": len(frames)}, "180 frames")
    add_check(checks, "new_action_30_fps", fps == 30, fps, "30 fps")
    add_check(checks, "new_action_6_seconds", duration == 6.0, duration, "6.0 seconds")
    add_check(checks, "new_action_all_numeric_values_finite",
              after["all_numeric_values_finite"], after["all_numeric_values_finite"], "all numeric values finite")
    add_check(checks, "new_timing_profile_power_v1", after.get("timing_profile") == "power-v1",
              after.get("timing_profile"), "timing_profile equals power-v1")
    add_check(checks, "new_phase_keys_present",
              isinstance(after.get("phase_keys"), list) and bool(after["phase_keys"]),
              after.get("phase_keys"), "non-empty phase_keys array")

    endpoints = after["yaw_endpoints"]
    for field, value in endpoints.items():
        add_check(checks, f"new_{field}_start_end_yaw_match_and_zero", value.get("both_zero"), value,
                  "both endpoints within "
                  f"{YAW_MATCH_TOLERANCE_DEGREES} degrees of yaw zero and match")

    after_cut = first_cut_duration(after)
    before_cut = first_cut_duration(before)
    add_check(checks, "new_cut_duration_0_20_seconds",
              after_cut is not None and abs(after_cut - CUT_TARGET_SECONDS) <= CUT_TARGET_TOLERANCE_SECONDS,
              after_cut, f"{CUT_TARGET_SECONDS} seconds +/- {CUT_TARGET_TOLERANCE_SECONDS}")
    add_check(checks, "new_cut_shorter_than_before",
              after_cut < before_cut if after_cut is not None and before_cut is not None else None,
              {"before_seconds": before_cut, "after_seconds": after_cut}, "new cut phase is shorter")

    new_torso = after["maximum_angular_velocity"].get("torso_yaw")
    old_torso = before["maximum_angular_velocity"].get("torso_yaw")
    ratio = None
    if new_torso is not None and old_torso is not None and old_torso["maximum_degrees_per_second"] > 0:
        ratio = new_torso["maximum_degrees_per_second"] / old_torso["maximum_degrees_per_second"]
    add_check(checks, "new_torso_peak_velocity_at_least_2x_before",
              ratio >= 2.0 if ratio is not None else None,
              {"before_degrees_per_second": old_torso["maximum_degrees_per_second"] if old_torso else None,
               "after_degrees_per_second": new_torso["maximum_degrees_per_second"] if new_torso else None,
               "ratio": ratio}, "new peak >= 2.0x old peak")

    landing = after["first_step_landing"]
    landing_time = landing.get("landing_seconds") if landing else None
    add_check(checks, "new_left_foot_lands_by_1_67_seconds",
              landing_time is not None and landing_time <= 1.67,
              landing, "first lift > 1e-5 through its next lift < 1e-5 landing by 1.67 seconds")

    wrist = after["maximum_wrist_bend_degrees"]
    wrist_value = wrist.get("maximum") if wrist else None
    add_check(checks, "new_wrist_bend_at_most_55_01_degrees",
              wrist_value is not None and wrist_value <= WRIST_MAXIMUM_DEGREES,
              wrist, f"<= {WRIST_MAXIMUM_DEGREES} degrees")
    ik = after["maximum_leg_ik_target_error"]
    ik_value = ik.get("maximum") if ik else None
    add_check(checks, "new_leg_ik_target_error_at_most_1e_4",
              ik_value is not None and ik_value <= IK_MAXIMUM,
              ik, f"<= {IK_MAXIMUM} (report units)")

    add_check(checks, "new_action_returns_to_initial_guard",
              after.get("returns_to_initial_guard") is True,
              after.get("returns_to_initial_guard"), "returns_to_initial_guard is true")
    endpoint_hold = after.get("endpoint_pose_hold")
    endpoint_hold_duration = (endpoint_hold.get("declared_duration_seconds")
                              if endpoint_hold else None)
    add_check(checks, "new_declared_endpoint_guard_hold_0_45_seconds",
              endpoint_hold_duration is not None and abs(endpoint_hold_duration - 0.45) <= 1e-6,
              endpoint_hold, "final phase_keys guard interval declares 0.45 seconds")

    overall = "PASS" if all(check["status"] == "PASS" for check in checks) else "FAIL"
    return {
        "schema_version": 1,
        "status": overall,
        "inputs": {"before": str(before_path), "after": str(after_path)},
        "metrics": {"before": before, "after": after,
                    "torso_peak_velocity_ratio": ratio,
                    "cut_duration_comparison_seconds": {"before": before_cut, "after": after_cut}},
        "checks": checks,
        "limitations": "not visual acceptance",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", required=True, type=Path, help="absolute path to the previous cycle-report.json")
    parser.add_argument("--after", required=True, type=Path, help="absolute path to the revised cycle-report.json")
    parser.add_argument("--out", required=True, type=Path, help="absolute path for a new comparison report")
    args = parser.parse_args(argv)
    if not args.out.is_absolute():
        parser.error("--out must be an absolute path")
    if args.out.exists():
        parser.error(f"refusing to overwrite existing output: {args.out}")
    try:
        before_report = read_report(args.before)
        after_report = read_report(args.after)
        result = build_result(args.before, args.after, before_report, after_report)
        serialized = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
        # Exclusive creation also closes the race between the preflight check and write.
        with args.out.open("x", encoding="utf-8") as stream:
            stream.write(serialized)
    except (OSError, ValueError, TypeError) as exc:
        print(f"compare_sword_power: {exc}", file=sys.stderr)
        return 2
    print(f"{result['status']}: wrote {args.out}")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
