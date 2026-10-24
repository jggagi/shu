"""Write a P1b QA save with the old stage, restore it in the HD2D stage.

Produces a retained, isolated fixture for the HD2D native-input test. Neither
process reads the player's save directory. Browser origins are outside scope.
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
CORE = ["pack_loader.gd", "session.gd", "save_store.gd", "walks_contract.gd", "town_navigation.gd"]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage_receipt(stage: Path) -> dict:
    receipt = json.loads((stage / "build-info.json").read_text())
    for relative, digest in receipt["source_hashes"].items():
        if sha(stage / relative) != digest:
            raise SystemExit("Frozen stage input differs from its receipt: " + str(stage / relative))
    return receipt


def run(godot: Path, stage: Path, mode: str, config_path: Path, report_dir: Path) -> dict:
    command = [str(godot), "--headless", "--path", str(stage), "--script", "res://" + HARNESS,
               "--", mode, str(config_path)]
    started = time.monotonic()
    try:
        result = subprocess.run(command, cwd=stage, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=120)
        code, stdout = result.returncode, result.stdout
    except subprocess.TimeoutExpired as exc:
        code, stdout = -1, exc.stdout or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode(errors="replace")
        stdout += "\nERROR: Compatibility process exceeded its deadline\n"
    log = report_dir / (mode + ".log")
    log.write_text(stdout)
    issues = [line for line in stdout.splitlines() if re.search(r"SCRIPT ERROR|\bERROR\b|\bWARNING\b|^FAIL:", line)]
    report_path = report_dir / (mode + "-report.json")
    report = json.loads(report_path.read_text()) if report_path.is_file() else {}
    row = {"stage": str(stage), "mode": mode, "command": command, "exit_code": code,
           "seconds": round(time.monotonic() - started, 3), "log": str(log),
           "issues": issues, "pid": report.get("pid"), "checks": report.get("checks"),
           "result": report.get("result", "NO_REPORT")}
    print(json.dumps(row), flush=True)
    return row


def validate(previous_stage: Path, stage: Path, output: Path, godot: Path) -> int:
    previous_stage, stage = previous_stage.resolve(strict=True), stage.resolve(strict=True)
    if not output.is_absolute() or output.exists():
        raise SystemExit("--output must be a new absolute QA directory")
    previous, current = stage_receipt(previous_stage), stage_receipt(stage)
    protected = sorted(rel for rel in previous["source_hashes"]
                       if rel.startswith("games/shu_town_walk/") and rel.endswith(".json"))
    protected += ["addons/cultivation_mode/" + name for name in CORE]
    for rel in protected:
        if previous["source_hashes"].get(rel) != current["source_hashes"].get(rel):
            raise SystemExit("HD2D must preserve the P1b data/state contract byte-for-byte: " + rel)
    if previous["user_dir"] != current["user_dir"]:
        raise SystemExit("The native HD2D preview must retain the P1b custom user directory")
    output.mkdir(parents=True)
    token = uuid.uuid4().hex
    writer_base, reader_base = output / ("fixture-" + token), output / ("reader-" + token)
    writer_base.mkdir()
    (writer_base / ".qa-owner").write_text(token)
    expected_path = output / "expected-snapshots.json"
    write_config = {"stage": str(previous_stage), "base_dir": str(writer_base), "token": token,
                    "report_dir": str(output), "expected_path": str(expected_path)}
    write_path = output / "writer-config.json"
    write_path.write_text(json.dumps(write_config, indent=2) + "\n")
    summary = {"previous_stage": str(previous_stage), "stage": str(stage), "protected_hashes":
               {rel: previous["source_hashes"][rel] for rel in protected},
               "custom_user_dir": current["user_dir"], "runs": [],
               "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "scope": "Old P1b process writes isolated QA checkpoints; new stage restores typed full snapshots. Retained fixture is for native HD2D UI continuation. No player-save or browser-origin migration."}
    writer = run(godot, previous_stage, "write", write_path, output)
    summary["runs"].append(writer)
    passed = writer["exit_code"] == 0 and not writer["issues"] and writer["result"] == "PASS"
    if passed:
        shutil.copytree(writer_base, reader_base)
        read_config = dict(write_config, stage=str(stage), base_dir=str(reader_base))
        read_path = output / "reader-config.json"
        read_path.write_text(json.dumps(read_config, indent=2) + "\n")
        reader = run(godot, stage, "read", read_path, output)
        summary["runs"].append(reader)
        passed = reader["exit_code"] == 0 and not reader["issues"] and reader["result"] == "PASS" and reader["pid"] != writer["pid"]
        fixture_files = {str(path.relative_to(writer_base)): sha(path)
                         for path in sorted(writer_base.rglob("checkpoint_*.json"))}
        native_config = {"base_dir": str(writer_base), "token": token,
                         "source_stage": str(previous_stage), "expected_path": str(expected_path),
                         "checkpoint_sha256": fixture_files, "scope": "QA fixture; copy into each native test's fresh Store before loading; never use the player directory"}
        (output / "native-fixture.json").write_text(json.dumps(native_config, indent=2) + "\n")
        summary["native_fixture"] = str(output / "native-fixture.json")
        summary["fixture_files"] = fixture_files
        if passed:
            if reader_base.parent != output or (reader_base / ".qa-owner").read_text() != token:
                raise SystemExit("Owned reader checkpoint cleanup guard failed")
            shutil.rmtree(reader_base)
    summary["result"] = "PASS" if passed else "FAIL_OR_INCOMPLETE"
    # Imports/reports may create cache and QA files, but no consumed source may
    # change while the writer and reader run.
    stage_receipt(previous_stage)
    stage_receipt(stage)
    summary["stage_source_integrity"] = True
    summary["checks"] = sum(row.get("checks") or 0 for row in summary["runs"])
    summary["retained_qa_fixture"] = str(writer_base)
    summary["different_process_ids"] = len(summary["runs"]) == 2 and summary["runs"][0]["pid"] != summary["runs"][1]["pid"]
    summary["completed_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (output / "compatibility-results.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: summary[key] for key in ["result", "checks", "retained_qa_fixture"]}), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--previous-stage", required=True, type=Path)
    parser.add_argument("--stage", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--godot", type=Path, default=Path("/opt/agent-creator/godot/bin/godot"))
    args = parser.parse_args()
    raise SystemExit(validate(args.previous_stage, args.stage, args.output, args.godot))
