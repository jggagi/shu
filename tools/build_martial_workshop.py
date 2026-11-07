#!/usr/bin/env python3
"""Validate, compile and cache offline martial-move recipes (stdlib only).

Default output is the project catalog. Custom --output writes its own catalog,
so experiments (including new IDs) never replace the six-move application batch.
No game rules, runtime scripts, original models or credentials are modified.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RECIPES = ROOT / "assets/data/martial_workshop/recipes"
DEFAULT_OUTPUT = ROOT / "assets/art/martial_workshop/generated"
DEFAULT_PROFILES = ROOT / "assets/data/martial_workshop/profiles.json"
COMPILER = ROOT / "tools/hero_lookdev/build_workshop_motions.py"
TEMPLATES = {"sword_path": ("sword", "blade", "default"), "palm_sweep": ("palm", "palm", "palm"), "palm_guard": ("palm", "palm", "palm")}
BONES = ["pelvis", "skirt.back.L", "skirt.back.R", "skirt.front.L", "skirt.front.R", "spine", "chest", "neck", "head", "ponytail", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R"]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def content_hash(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n")


def res_file(value):
    if not isinstance(value, str) or not value.startswith("res://"):
        raise ValueError("Expected res:// asset path: " + repr(value))
    path = (ROOT / value[6:]).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError("Resource escapes project root")
    if not path.is_file():
        raise ValueError("Missing resource: " + value)
    return path


def resource_refs(value):
    if isinstance(value, str) and value.startswith("res://"):
        yield value
    elif isinstance(value, dict):
        for v in value.values():
            yield from resource_refs(v)
    elif isinstance(value, list):
        for v in value:
            yield from resource_refs(v)


def glb_json(path):
    data = Path(path).read_bytes()
    if data[:4] != b"glTF" or struct.unpack_from("<I", data, 4)[0] != 2:
        raise ValueError("Not a glTF2 GLB: " + str(path))
    return json.loads(data[20:20 + struct.unpack_from("<I", data, 12)[0]])


def number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(label + " must be finite numeric")
    return float(value)


def vector(value, label):
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError(label + " must be a three-number array")
    return [number(v, label) for v in value]


def validate_profile(name, profile):
    if profile["bone_names"] != BONES:
        raise ValueError("Invalid 22-bone profile contract: " + name)
    source = res_file(profile["source_asset"])
    if digest(source) != profile["source_sha256"]:
        raise ValueError("Profile source SHA differs: " + name)
    gltf = glb_json(source)
    if len(gltf.get("skins", [])) != 1:
        raise ValueError("Profile requires one original Skin")
    joints = [gltf["nodes"][i]["name"] for i in gltf["skins"][0]["joints"]]
    if set(joints) != set(BONES):
        raise ValueError("Source GLB does not have the profile 22 bones")
    if profile["import"] != {"fps": 100, "remove_immutable_tracks": False, "optimizer": False}:
        raise ValueError("Motion import contract must preserve dense 100fps tracks")
    for anchor in profile["anchors"].values():
        if anchor["bone"] not in BONES:
            raise ValueError("Invalid anchor bone")
        vector(anchor["point"], "anchor point")
    for variant in profile.get("hand_variants", {}).values():
        res_file(variant["asset"])


def validate_recipe(path, recipe, profiles):
    if recipe.get("schema_version") != 1 or recipe.get("mode") not in {"reuse", "generate"}:
        raise ValueError("Invalid recipe version/mode: " + str(path))
    move = recipe["move"]
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,47}", move["id"]):
        raise ValueError("Invalid recipe ID")
    if move["profile"] not in profiles:
        raise ValueError("Unknown rig profile: " + move["profile"])
    profile = profiles[move["profile"]]
    if profile["actor"] != move["actor"]:
        raise ValueError("Actor/profile mismatch")
    if recipe["template"] not in TEMPLATES:
        raise ValueError("Unknown motion template")
    category, visual, hand = TEMPLATES[recipe["template"]]
    if (move["category"], move["visual"]["type"], move["animation"]["hand"]) != (category, visual, hand):
        raise ValueError("Template/category/hand mismatch")
    if category == "palm" and hand not in profile.get("hand_variants", {}):
        raise ValueError("Missing open-palm variant in profile")
    if move["style"] not in {"light", "strong"} or not isinstance(move["preview_only"], bool):
        raise ValueError("Invalid style/preview_only")
    if not move["preview_only"] and not move["combat_skill"]:
        raise ValueError("Battle move requires existing combat skill")
    if move["preview_only"] and move["combat_skill"]:
        raise ValueError("Preview-only move cannot claim a combat skill")
    timing = move["timing"]
    duration = number(timing["duration"], "duration")
    total = number(timing["total"], "total")
    release = number(timing["release"], "release")
    impact = number(timing["impact"], "impact")
    source_seconds = number(move["animation"]["source_seconds"], "source_seconds")
    if not 0 < release < impact <= duration <= total or source_seconds <= 0:
        raise ValueError("Invalid release/impact/duration timeline")
    mapping = timing["source_map"]
    if len(mapping) < 2 or mapping[0] != [0, 0] or mapping[-1] != [duration, source_seconds]:
        raise ValueError("source_map must span complete playback and source duration")
    previous = [-1., -1.]
    for pair in mapping:
        if len(pair) != 2:
            raise ValueError("source_map requires pairs")
        x, y = [number(v, "source_map") for v in pair]
        if x <= previous[0] or y < previous[1] or not 0 <= x <= duration or not 0 <= y <= source_seconds:
            raise ValueError("source_map must have strictly increasing play time and monotonic source time")
        previous = [x, y]
    if not isinstance(move["animation"]["clip"], str) or not move["animation"]["clip"].strip():
        raise ValueError("Clip name is required")
    refs = set(resource_refs(move))
    if recipe["mode"] == "generate":
        refs.discard(move["animation"]["asset"])
        motion = recipe["motion"]
        if motion["fps"] != 100 or not 1.2 <= source_seconds <= 1.6 or abs(round(source_seconds * 100) - source_seconds * 100) > 1e-8:
            raise ValueError("New motion requires 100fps duration1.2–1.6 seconds on exact frames")
        if not 0 < number(motion["contact"], "contact") < source_seconds:
            raise ValueError("Invalid source contact time")
        keys = motion["keys"]
        if len(keys) < 3 or keys[0]["t"] != 0 or keys[-1]["t"] != source_seconds:
            raise ValueError("Pose keys must span complete source clip")
        previous = -1.
        for key in keys:
            time = number(key["t"], "pose key time")
            if not previous < time <= source_seconds:
                raise ValueError("Pose key times must increase")
            previous = time
            for field in ["hip_yaw", "chest_yaw", "lean", "palm_yaw"]:
                if abs(number(key[field], field)) > 90:
                    raise ValueError("Pose rotation outside workshop range")
            vector(key["shift"], "shift")
            for field in ["left", "right", "right_direction"]:
                if key[field] != "neutral":
                    v = vector(key[field], field)
                    if field == "right_direction" and sum(n * n for n in v) < 1e-8:
                        raise ValueError("Sword direction cannot be zero")
            if not 0 <= number(key["palm_open"], "palm_open") <= 1:
                raise ValueError("palm_open outside0–1")
        for key in [keys[0], keys[-1]]:
            if any(key[x] != "neutral" for x in ["left", "right", "right_direction"]) or any(key[x] != 0 for x in ["hip_yaw", "chest_yaw", "lean", "palm_yaw", "palm_open"]) or key["shift"] != [0, 0, 0]:
                raise ValueError("Motion must start and end in source neutral pose")
    else:
        gltf = glb_json(res_file(move["animation"]["asset"]))
        clips = {a["name"]: a for a in gltf.get("animations", [])}
        if move["animation"]["clip"] not in clips:
            raise ValueError("Reused animation clip missing")
        actual = max(gltf["accessors"][s["input"]]["max"][0] for s in clips[move["animation"]["clip"]]["samplers"])
        if abs(actual - source_seconds) > 1e-5:
            raise ValueError("Reused clip source duration mismatch")
    refs.update(resource_refs(profile))
    refs.update(recipe.get("source_manifests", []))
    inputs = {ref: digest(res_file(ref)) for ref in sorted(refs)}
    return inputs


def resource_path(path):
    path = Path(path).resolve()
    if path.is_relative_to(ROOT) and not any(part.startswith(".") for part in path.relative_to(ROOT).parts):
        return "res://" + path.relative_to(ROOT).as_posix()
    # A standalone output is a portable resource-root package; copy generated/
    # and catalog.json into the consumer's resource root before loading it.
    return "res://generated/" + "/".join(path.parts[-3:])


def import_profile(asset, resource, godot, log_path):
    """Bake complete matching Godot sidecar in an isolated CPU-only project."""
    with tempfile.TemporaryDirectory(prefix="shu-workshop-import-") as tmp:
        project = Path(tmp)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Offline workshop import"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        dest = project / resource[6:]
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(asset, dest)
        # Let Godot author its own UID/remap fields, while pinning animation
        # sampling before import. No original source or source cache is touched.
        dest.with_suffix(".glb.import").write_text('[remap]\nimporter="scene"\ntype="PackedScene"\n\n[params]\nanimation/fps=100\nanimation/remove_immutable_tracks=false\n_subresources={"nodes":{"PATH:AnimationPlayer":{"optimizer/enabled":false}}}\n')
        result = subprocess.run([godot, "--headless", "--path", str(project), "--editor", "--import"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(result.stdout)
        if result.returncode or "ERROR:" in result.stdout:
            raise RuntimeError("Isolated CPU asset import failed: " + result.stdout[-2000:])
        shutil.copy2(dest.with_suffix(".glb.import"), asset.with_suffix(".glb.import"))


def cache_valid(manifest, inputs, generated):
    if not manifest.is_file():
        return False
    try:
        data = json.loads(manifest.read_text())
        if data["inputs"] != inputs:
            return False
        for path, expected in data["output_files"].items():
            if not Path(path).is_file() or digest(path) != expected:
                return False
        return data["mode"] != "generate" or generated.is_file()
    except (KeyError, ValueError, OSError):
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipes-dir", type=Path, default=DEFAULT_RECIPES)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--profiles", type=Path, default=DEFAULT_PROFILES)
    parser.add_argument("--catalog-output", type=Path)
    parser.add_argument("--blender", default="/usr/bin/blender")
    parser.add_argument("--godot", default="/opt/agent-creator/godot/bin/godot")
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        profiles = json.loads(args.profiles.read_text())["profiles"]
        for name, profile in profiles.items():
            validate_profile(name, profile)
        paths = sorted(args.recipes_dir.glob("*.json"))
        if not paths:
            raise ValueError("No recipe JSON files")
        recipes, seen = [], set()
        # Validation of the entire batch precedes any directory, Blender or
        # output mutation. A late bad recipe cannot leave a half-built batch.
        for path in paths:
            recipe = json.loads(path.read_text())
            inputs = validate_recipe(path, recipe, profiles)
            move_id = recipe["move"]["id"]
            if move_id in seen:
                raise ValueError("Duplicate recipe ID: " + move_id)
            seen.add(move_id)
            recipes.append((path, recipe, inputs))
        report = {"schema_version": 1, "ok": True, "check_only": args.check_only, "validated": len(recipes), "jobs": [], "source_originals_unchanged": True}
        if args.check_only:
            report["ids"] = sorted(seen)
            if args.report:
                write_json(args.report, report)
            print(json.dumps(report, ensure_ascii=False))
            return
        for binary in [args.blender, args.godot]:
            if not Path(binary).is_file():
                raise ValueError("Required pinned executable missing: " + binary)
        tool_inputs = {str(path.relative_to(ROOT)): digest(path) for path in [Path(__file__), COMPILER,
            COMPILER.with_name("build_ambush_palm_clips.py"), COMPILER.with_name("build_ambush_martial_clips.py")]}
        tool_inputs["blender_binary_sha256"] = digest(args.blender)
        tool_inputs["godot_binary_sha256"] = digest(args.godot)
        moves = []
        manifests = {}
        for path, recipe, inputs in recipes:
            move = copy.deepcopy(recipe["move"])
            profile = profiles[move["profile"]]
            fingerprint = content_hash({"recipe": recipe, "profile": profile, "inputs": inputs, "tools": tool_inputs})
            job = args.output.resolve() / move["id"] / fingerprint[:16]
            generated = job / "motion.glb"
            manifest = job / "manifest.json"
            cached = cache_valid(manifest, inputs, generated)
            if cached:
                previous = json.loads(manifest.read_text())
                move = previous["resolved_move"]
                status = "cache_hit"
            else:
                job.mkdir(parents=True, exist_ok=True)
                output_files = {}
                if recipe["mode"] == "generate":
                    blend = ROOT / ".local/sources/martial-workshop" / move["id"] / fingerprint[:16] / "motion.blend"
                    source_report = job / "source-motion.json"
                    command = [args.blender, "--disable-autoexec", "--background", "--python-exit-code", "1", "--python", str(COMPILER), "--",
                        "--recipe", str(path.resolve()), "--profiles", str(args.profiles.resolve()), "--root", str(ROOT),
                        "--out", str(generated), "--blend", str(blend), "--report", str(source_report)]
                    env = dict(os.environ)
                    ocio = ROOT / ".local/qa/tinglan-character/ocio-compat/config.ocio"
                    if ocio.is_file() and not env.get("OCIO"):
                        env["OCIO"] = str(ocio)
                    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, timeout=300)
                    log_dir = ROOT / ".local/qa/martial-workshop/jobs" / move["id"] / fingerprint[:16]
                    log_dir.mkdir(parents=True, exist_ok=True)
                    (log_dir / "blender.log").write_text(result.stdout)
                    if result.returncode:
                        raise RuntimeError("Blender failed for " + move["id"] + ": " + result.stdout[-3500:])
                    source_data = json.loads(source_report.read_text())
                    if not source_data["all_pass"]:
                        raise RuntimeError("Source invariants failed")
                    move["animation"]["asset"] = resource_path(generated)
                    import_profile(generated, move["animation"]["asset"], args.godot, log_dir / "godot-import.log")
                    move["animation"]["sha256"] = digest(generated)
                    for item in [generated, generated.with_suffix(".glb.import"), source_report, blend]:
                        output_files[str(item)] = digest(item)
                    status = "generated"
                else:
                    move["animation"]["sha256"] = digest(res_file(move["animation"]["asset"]))
                    status = "reused"
                resource_sha256 = {ref: value for ref, value in inputs.items() if ref not in recipe.get("source_manifests", [])}
                resource_sha256[move["animation"]["asset"]] = move["animation"]["sha256"]
                move["resource_sha256"] = resource_sha256
                move["resource_hash"] = content_hash(move)
                write_json(manifest, {"schema_version": 1, "id": move["id"], "mode": recipe["mode"], "template": recipe["template"],
                    "fingerprint": fingerprint, "canonical_recipe_sha256": content_hash(recipe), "inputs": inputs, "tools": tool_inputs,
                    "output_files": output_files, "resolved_move": move, "source_manifest_hashes": {x: inputs[x] for x in recipe.get("source_manifests", [])},
                    "provenance": {"author": "Codex for Shu; original choreography", "source_license": profile["source_license"], "source_originals_modified": False,
                        "cloud_calls": 0, "paid_calls": 0, "installs": 0}})
            moves.append(move)
            manifests[move["id"]] = {"path": str(manifest), "sha256": digest(manifest), "fingerprint": fingerprint}
            report["jobs"].append({"id": move["id"], "status": status, "fingerprint": fingerprint, "asset": move["animation"]["asset"], "sha256": move["animation"]["sha256"], "manifest": str(manifest)})
            print("WORKSHOP_JOB " + json.dumps(report["jobs"][-1], ensure_ascii=False), flush=True)
        for name, profile in profiles.items():
            if digest(res_file(profile["source_asset"])) != profile["source_sha256"]:
                raise RuntimeError("Original changed during batch: " + name)
        # Recipe order in filenames is intentionally independent of move IDs;
        # optional numeric authoring order provides a stable UI layout.
        order = {r["move"]["id"]: r.get("order", 1000) for _, r, _ in recipes}
        moves.sort(key=lambda x: (order[x["id"]], x["id"]))
        catalog = {"schema_version": 1, "profiles": profiles, "moves": moves}
        catalog_path = args.catalog_output or (ROOT / "assets/data/martial_workshop/catalog.json" if args.output.resolve() == DEFAULT_OUTPUT else args.output / "catalog.json")
        write_json(catalog_path, catalog)
        write_json(args.output / "batch-manifest.json", {"schema_version": 1, "catalog_sha256": digest(catalog_path), "jobs": manifests})
        report.update(catalog=str(catalog_path), catalog_sha256=digest(catalog_path),
            cache_hits=sum(x["status"] == "cache_hit" for x in report["jobs"]), generated=sum(x["status"] == "generated" for x in report["jobs"]), reused=sum(x["status"] == "reused" for x in report["jobs"]))
        if args.report:
            write_json(args.report, report)
        print("WORKSHOP_BATCH " + json.dumps(report, ensure_ascii=False), flush=True)
    except (ValueError, KeyError, TypeError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        report = {"schema_version": 1, "ok": False, "error": str(error), "check_only": args.check_only}
        if args.report:
            write_json(args.report, report)
        print(json.dumps(report, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
