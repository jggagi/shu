"""Validate P1b checkpoints in separate Godot processes against a frozen stage.

Uses standard-library Python only. This verifies EngineSession/SaveStore state;
rendered movement/input must be verified by the separate native window check.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import time
import uuid
from pathlib import Path

HARNESS = "tests/cultivation_engine_town_walk_restart.gd"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(stage: Path, output: Path, godot: Path) -> int:
    stage = stage.resolve(strict=True)
    if not output.is_absolute() or output.exists():
        raise SystemExit("--output must be a new absolute QA directory")
    build_info = json.loads((stage / "build-info.json").read_text())
    source_hashes = build_info["source_hashes"]
    if HARNESS not in source_hashes:
        raise SystemExit("The selected stage must include the bound P1b restart harness")
    for relative, digest in source_hashes.items():
        if sha(stage / relative) != digest:
            raise SystemExit("Stage input differs from build receipt: " + relative)
    output.mkdir(parents=True)
    token = uuid.uuid4().hex
    save_base = output / ("test-checkpoints-" + token)
    save_base.mkdir()
    (save_base / ".qa-owner").write_text(token)
    config = {"stage": str(stage), "base_dir": str(save_base), "token": token,
              "report_dir": str(output), "expected_path": str(output / "expected-snapshots.json")}
    config_path = output / "restart-config.json"
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    summary = {"stage": str(stage), "source_head": build_info["head"],
               "runtime_digest": build_info["shared_runtime_digest"],
               "harness": HARNESS, "harness_sha256": source_hashes[HARNESS],
               "scope": "P1b EngineSession/SaveStore in distinct operating-system processes; position commits and presenter completion simulated; no UI/browser/physical input evidence",
               "expected_comparison": "strict full typed Variant snapshot; JSON copies also retained",
               "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "save_base": str(save_base), "runs": [], "cleanup": False}
    for mode in ["write", "read"]:
        command = [str(godot), "--headless", "--path", str(stage), "--script",
                   "res://" + HARNESS, "--", mode, str(config_path)]
        start = time.monotonic()
        try:
            process = subprocess.run(command, cwd=stage, text=True, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, timeout=120)
            stdout, code = process.stdout, process.returncode
        except subprocess.TimeoutExpired as exc:
            stdout = exc.stdout or ""
            if isinstance(stdout, bytes):
                stdout = stdout.decode(errors="replace")
            code = -1
            stdout += "\nERROR: P1b validation exceeded its process deadline\n"
        log = output / (mode + ".log")
        log.write_text(stdout)
        issues = [line for line in stdout.splitlines()
                  if re.search(r"SCRIPT ERROR|\bERROR\b|\bWARNING\b|^FAIL:", line)]
        report_path = output / (mode + "-report.json")
        report = json.loads(report_path.read_text()) if report_path.is_file() else {}
        row = {"mode": mode, "command": command, "exit_code": code,
               "seconds": round(time.monotonic() - start, 3), "log": str(log),
               "report": str(report_path), "issues": issues, "pid": report.get("pid"),
               "checks": report.get("checks"), "result": report.get("result", "NO_REPORT")}
        summary["runs"].append(row)
        print(json.dumps(row), flush=True)
        if code or issues or row["result"] != "PASS":
            break
    passed = len(summary["runs"]) == 2 and all(
        row["exit_code"] == 0 and not row["issues"] and row["result"] == "PASS"
        for row in summary["runs"])
    summary["different_process_ids"] = passed and summary["runs"][0]["pid"] != summary["runs"][1]["pid"]
    integrity = all(sha(stage / rel) == digest for rel, digest in source_hashes.items())
    summary["stage_source_integrity"] = integrity
    passed = passed and summary["different_process_ids"] and integrity
    summary["checkpoint_files"] = [{"path": str(path.relative_to(save_base)),
                                     "sha256": sha(path), "bytes": path.stat().st_size}
                                    for path in sorted(save_base.rglob("checkpoint_*.json"))]
    if passed:
        if save_base.parent != output or not save_base.name.startswith("test-checkpoints-") or (save_base / ".qa-owner").read_text() != token:
            raise SystemExit("Owned QA checkpoint cleanup guard failed")
        shutil.rmtree(save_base)
        summary["cleanup"] = not save_base.exists()
    summary["checks"] = sum(row.get("checks") or 0 for row in summary["runs"])
    summary["result"] = "PASS" if passed else "FAIL_OR_INCOMPLETE"
    summary["completed_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (output / "process-restart-results.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: summary[key] for key in ["result", "checks", "cleanup", "stage_source_integrity"]}), flush=True)
    if not passed:
        print("\n".join(stdout.splitlines()[-35:]))
    return 0 if passed else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--godot", type=Path, default=Path("/opt/agent-creator/godot/bin/godot"))
    args = parser.parse_args()
    raise SystemExit(validate(args.stage, args.output, args.godot))
