"""Check packaged skill examples/provenance; does not execute a Godot runtime."""

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_graph(data):
    nodes = data["nodes"]
    entry = data["entry"]
    require(entry in nodes, "event: missing entry node")
    edges = {}
    for node_id, node in nodes.items():
        kind = node["type"]
        require(kind in {"say", "choice", "cue", "end"}, f"{node_id}: unknown node type")
        targets = []
        if kind in {"say", "cue"}:
            targets.append(node["next"])
        if kind == "say":
            require(bool(node.get("speaker") and node.get("text")), f"{node_id}: empty dialogue")
        if kind == "cue":
            require(bool(node.get("cue_id")), f"{node_id}: missing cue ID")
        if kind == "choice":
            options = node["options"]
            require(bool(options), f"{node_id}: no choices")
            require(len({item["id"] for item in options}) == len(options), f"{node_id}: duplicate option ID")
            for option in options:
                require(bool(option["text"]), f"{node_id}: empty option text")
                targets.append(option["next"])
                if "action" in option:
                    require(option["action"]["id"] in data["allowed_action_ids"], f"{node_id}: action not allowed")
                    targets.append(option["failure_next"])
        if kind == "end":
            require(bool(node.get("reason")), f"{node_id}: missing end reason")
        require(all(target in nodes for target in targets), f"{node_id}: dangling next/failure reference")
        edges[node_id] = targets
    seen, active = set(), set()

    def visit(node_id):
        require(node_id not in active, f"{node_id}: cycle unsupported in schema 1")
        if node_id in seen:
            return
        active.add(node_id)
        for target in edges[node_id]:
            visit(target)
        active.remove(node_id)
        seen.add(node_id)

    visit(entry)
    require(seen == set(nodes), "event: unreachable nodes")
    # In this finite DAG, every terminal must be an explicit end.
    require(all(nodes[key]["type"] == "end" for key, targets in edges.items() if not targets), "event: path without end")
    return len(nodes)


def validate_package(skill_dir, repo=None):
    entry = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
    require(entry.startswith("---\n"), "skill: missing frontmatter")
    require("name: game-cultivation-build\n" in entry, "skill: unexpected name")
    ui = (skill_dir / "agents" / "openai.yaml").read_text(encoding="utf-8")
    short = re.search(r'short_description: "([^"]+)"', ui)
    require(short is not None and 25 <= len(short.group(1)) <= 64, "UI: description length")
    require("$game-cultivation-build" in ui, "UI: missing skill invocation")
    links = 0
    for path in skill_dir.rglob("*.md"):
        for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
            if "://" in target or target.startswith("#"):
                continue
            linked = (path.parent / target.split("#")[0]).resolve()
            require(linked.is_relative_to(skill_dir), f"{path.name}: reference escapes skill")
            require(linked.is_file(), f"{path.name}: missing reference {target}")
            links += 1
    assets = skill_dir / "assets"
    data = json.loads((assets / "episode.example.json").read_text(encoding="utf-8"))
    catalog = json.loads((assets / "mode.example.json").read_text(encoding="utf-8"))
    require(data["schema_version"] == catalog["schema_version"] == 1, "example: unsupported schema")
    require(data["mode"] == catalog["mode"] == "cultivation", "example: incorrect mode")
    require(data["return_to"] == "activity_panel", "event: incorrect return target")
    require(data["source"]["status"] == "illustrative" and catalog["source_status"] == "illustrative", "example: unlabelled proposal")
    require(data["scene_id"] == catalog["scene_id"], "example: scene mismatch")
    require(data["trigger"] == {"type": "activity_selected", "activity_id": data["activity_id"]}, "event: trigger mismatch")
    activity = catalog["activities"][data["activity_id"]]
    require(activity["event_id"] == data["id"], "catalog: event mismatch")
    require(activity["settlement"] == "deferred_to_event_action", "catalog: possible double charge")
    node_count = validate_graph(data)
    plan = json.loads((assets / "tea-chain.example.json").read_text(encoding="utf-8"))
    require(plan["kind"] == "cultivation_sidequest_adaptation_plan" and plan["status"] == "proposal_not_playable", "tea: unlabelled plan")
    require(plan["mode"] == "cultivation" and plan["return_to"] == "activity_panel", "tea: mode/return mismatch")
    stages = plan["stages"]
    require(len({stage["id"] for stage in stages}) == len(stages), "tea: duplicate stage")
    previous = None
    for stage in stages:
        require(stage["after"] == previous, f"tea/{stage['id']}: broken reveal order")
        previous = stage["id"]
    cups = plan["recurring_objects"]
    require(cups["first_visit"] == cups["ending_visit"] and len(set(cups["first_visit"])) == 2, "tea: changed recurring cups")
    source = plan["source"]
    require(re.fullmatch(r"[a-f0-9]{40}", source["revision"]) is not None, "tea: invalid source revision")
    require(re.fullmatch(r"[a-f0-9]{64}", source["sha256"]) is not None, "tea: invalid source hash")
    if repo is not None:
        # Process-local trust for this explicitly selected repository; no global config changes.
        raw = subprocess.check_output(["git", "-c", "safe.directory=" + repo.as_posix(), "-C", str(repo), "show", source["revision"] + ":" + source["path"]], stderr=subprocess.PIPE)
        require(hashlib.sha256(raw).hexdigest() == source["sha256"], "tea: pinned source hash mismatch")
        headings = set(re.findall(r"^#{1,6}\s+(.+)$", raw.decode("utf-8"), re.MULTILINE))
        require(all(stage["source_section"] in headings for stage in stages), "tea: source section missing")
    return f"PASS: {links} references, {node_count} event nodes, {len(stages)} tea stages; " + ("pinned source verified." if repo else "source check skipped (supply --repo).")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, help="Host checkout containing the pinned tea source commit")
    args = parser.parse_args()
    skill_dir = Path(__file__).resolve().parents[1]
    try:
        print(validate_package(skill_dir, args.repo.resolve() if args.repo else None))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}")
        return 1
    print("Scope: package consistency/provenance; Godot runtime and playable tea are not verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
