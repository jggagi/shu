#!/usr/bin/env python3
"""Author a Material Maker graph and optionally run its genuine GPU exporter.

Python only writes .ptex JSON and provenance; it never renders texture pixels.
Use --prepare to refresh the editable graph; use --export with the isolated
official Material Maker 1.8 binary to generate the two original RGBA PNGs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / "assets/art/mountain_ambush/palm_lab/material_maker"
LOCAL = ROOT / ".local/tools/martial-vfx-authoring/MaterialMaker"
QA = ROOT / ".local/qa/palm-vfx-material-maker"
DEFAULT_BINARY = LOCAL / "binary-1.8/material_maker_1_8_linux/material_maker.x86_64"
TOOL_COMMIT = "7d6daae3c74c09720afe4138ce09699ab3591ce1"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def noise(name: str, seed: int, sx: int, sy: int, x: int, y: int) -> dict:
    return {"name": name, "type": "perlin", "seed_int": seed,
            "node_position": {"x": x, "y": y},
            "parameters": {"iterations": 5, "persistence": 0.55,
                           "scale_x": sx, "scale_y": sy}}


def graph() -> dict:
    # Both outputs deliberately share two stock MM noise generators. Our own
    # editable shader shapes the silhouette, alpha, and wind contours.
    code = [
        "vec2 $(name_uv)_p = ($uv - vec2(0.5)) * 2.0;",
        "float $(name_uv)_r = length($(name_uv)_p);",
        "float $(name_uv)_a = atan($(name_uv)_p.y, $(name_uv)_p.x);",
        "float $(name_uv)_c = $coarse($uv);",
        "float $(name_uv)_f = $fine($uv);",
        "float $(name_uv)_edge = 1.0-smoothstep(0.44, 0.91, $(name_uv)_r + 0.20*($(name_uv)_c-0.5));",
        "float $(name_uv)_dust = $(name_uv)_edge * smoothstep(0.18, 0.78, 0.74*$(name_uv)_c + 0.26*$(name_uv)_f) * $opacity;",
        "float $(name_uv)_wr = 0.61 + 0.045*sin(5.0*$(name_uv)_a + 4.0*$(name_uv)_c);",
        "float $(name_uv)_band = exp(-pow(($(name_uv)_r-$(name_uv)_wr)/$width, 2.0));",
        "float $(name_uv)_wisps = 0.55 + 0.45*pow(0.5+0.5*sin(9.0*$(name_uv)_a + 8.0*$(name_uv)_f), 2.0);",
        "float $(name_uv)_wind = $(name_uv)_band * $(name_uv)_wisps * $opacity * (1.0-smoothstep(0.82, 0.95, $(name_uv)_r));",
    ]
    compositor = {
        "name": "ShuPalmTextureOutput", "type": "shader", "seed_int": 26025,
        "node_position": {"x": 360, "y": 80},
        "parameters": {"opacity": 0.9, "width": 0.065, "size": 9},
        "shader_model": {
            "name": "Shu Palm Dust and Wind", "shortdesc": "Original palm impact textures",
            "longdesc": "Two seeded MM noise nodes drive soft dust alpha and an irregular wind ring. Output RGB is neutral white; tint at runtime.",
            "code": code, "global": "", "instance": "",
            "preview_shader": [
                "shader_type spatial;", "render_mode unshaded, blend_mix, cull_disabled;",
                "uniform sampler2D texture_dust; // $output(0)",
                "void fragment() { vec4 c = texture(texture_dust, UV); ALBEDO=c.rgb; ALPHA=c.a; }",
            ],
            "inputs": [{"name": n, "type": "f", "default": "0.5", "shortdesc": n.title(), "label": n.title()} for n in ["coarse", "fine"]],
            "outputs": [{"type": "rgba", "rgba": f"vec4(vec3(1.0), $(name_uv)_{n})", "shortdesc": n.title()} for n in ["dust", "wind"]],
            "parameters": [
                {"name": "opacity", "type": "float", "label": "Opacity", "default": 0.9, "min": 0.0, "max": 1.0, "step": 0.01},
                {"name": "width", "type": "float", "label": "Wind width", "default": 0.065, "min": 0.02, "max": 0.2, "step": 0.005},
                {"name": "size", "type": "size", "label": "Size", "default": 9, "first": 4, "last": 13},
            ],
            "exports": {"Shu/Palm PNG": {"export_extension": "png", "files": [
                {"file_name": "$(path_prefix)-dust.png", "output": 0, "type": "texture"},
                {"file_name": "$(path_prefix)-wind.png", "output": 1, "type": "texture"},
            ]}},
        },
    }
    return {
        "name": "ShuPalmOriginalMaterials", "type": "graph", "label": "Shu Palm Materials",
        "node_position": {"x": 0, "y": 0}, "parameters": {}, "seed_int": 26025,
        "nodes": [noise("DustCoarse", 260251, 5, 5, -220, -40),
                  noise("DustFine", 260252, 19, 16, -220, 220), compositor],
        "connections": [{"from": n, "from_port": 0, "to": "ShuPalmTextureOutput", "to_port": i}
                        for i, n in enumerate(["DustCoarse", "DustFine"])],
    }


def inspect_outputs(output: Path, source: Path, binary: Path) -> dict:
    # Existing Pillow is used only to read and inspect MM's PNG files.
    from PIL import Image
    textures = []
    checks = []
    for name in ["dust", "wind"]:
        path = output / f"palm-{name}.png"
        with Image.open(path) as image:
            image.load()
            alpha = image.getchannel("A")
            extrema = alpha.getextrema()
            edge = list(alpha.crop((0, 0, image.width, 1)).tobytes())
            edge += list(alpha.crop((0, image.height-1, image.width, image.height)).tobytes())
            edge += list(alpha.crop((0, 0, 1, image.height)).tobytes())
            edge += list(alpha.crop((image.width-1, 0, image.width, image.height)).tobytes())
            rgba_extrema = image.getextrema()
            conditions = {
                "RGBA_512_square": image.mode == "RGBA" and image.size == (512, 512),
                "neutral_white_rgb": all(v == (255, 255) for v in rgba_extrema[:3]),
                "real_nonempty_alpha": extrema[0] == 0 and 40 <= extrema[1] <= 250,
                "soft_alpha": len(alpha.getcolors(65536) or []) > 32,
                "transparent_edges": max(edge) <= 2,
            }
            checks.extend({"name": f"{name}:{key}", "pass": bool(value)} for key, value in conditions.items())
            textures.append({"path": "res://"+str((ASSET/path.name).relative_to(ROOT)),
                             "bytes": path.stat().st_size, "sha256": sha(path),
                             "width": image.width, "height": image.height, "mode": image.mode,
                             "alpha_min_max": list(extrema), "edge_alpha_max": max(edge),
                             "alpha_unique_values": len(alpha.getcolors(65536) or []),
                             "semantics": "Straight RGBA, neutral white RGB, tint in Godot; no black matte."})
    result = {"checks": checks, "count": len(checks), "failures": sum(not check["pass"] for check in checks), "textures": textures}
    (QA/"texture-check.json").write_text(json.dumps(result, indent=2)+"\n")
    if result["failures"]:
        raise SystemExit("Material Maker PNG validation failed; see texture-check.json")
    provenance = {
        "schema": 1, "status": "Actual Material Maker GPU export; inspected original PNG bytes",
        "author": "Original Shu procedural graph and compositor authored by Codex",
        "asset_license": "Original Shu project production assets; no third-party texture inputs",
        "tool": {"name": "Material Maker", "version": "1.8", "source_commit": TOOL_COMMIT,
                 "release": "https://github.com/RodZill4/material-maker/releases/tag/1.8",
                 "source": "https://github.com/RodZill4/material-maker/tree/"+TOOL_COMMIT,
                 "license": "MIT, Rodolphe Suescun and contributors", "license_copy": "MaterialMaker-LICENSE.md",
                 "linux_archive": "https://github.com/RodZill4/material-maker/releases/download/1.8/material_maker_1_8_linux.tar.gz",
                 "linux_archive_sha256": "8e8eb7050e75086cfafeb4ddc0b09c4fe117f529693e611d6fccca1651e913b3",
                 "source_archive": "https://api.github.com/repos/RodZill4/material-maker/tarball/"+TOOL_COMMIT,
                 "source_archive_sha256": "40a89ef34874cc1da738769958bf4a7e3fcd90367d00203871d51d875fc9c1a0",
                 "binary_sha256": sha(binary), "embedded_Godot": "4.7.2.stable.official.ed1daf0bf"},
        "editable_graph": {"path": str(source.relative_to(ROOT)), "sha256": sha(source),
                           "nodes": ["DustCoarse: stock MM Value Noise, seed 260251", "DustFine: stock MM Value Noise, seed 260252", "ShuPalmTextureOutput: original editable alpha compositor and two PNG exports"]},
        "generator": {"path": str(Path(__file__).resolve().relative_to(ROOT)), "sha256": sha(Path(__file__)),
                      "rebuild": "python3 tools/hero_lookdev/build_palm_material_textures.py --export --source-runner",
                      "command_template": ["godot-4.7.2", "--export-material", "--target", "Shu/Palm PNG", "--size", "512", "--output-file", "palm", "-o", "<output-directory>", "<palm-materials.ptex>"],
                      "command_working_directory": "Isolated fixed Material Maker source-runner-1.8, prepared using adjacent README and versioned patch/manifest",
                      "python_raster_generation": False},
        "inputs": {"external_images": [], "community_assets": [], "cloud_AI_calls": 0},
        "outputs": textures, "checks": {"pixel_checks": len(checks), "failures": 0},
        "verification_boundary": "Original PNG encoding/alpha/bounds verified separately from gameplay composition, browser performance and user visual approval.",
    }
    plan_path, run_path = QA/"export-plan.json", QA/"export-run.json"
    if plan_path.exists() and run_path.exists():
        execution_plan = json.loads(plan_path.read_text())
        execution_run = json.loads(run_path.read_text())
        run_hashes = {Path(item["path"]).name: item["sha256"] for item in execution_run["outputs"]}
        if (execution_run["plan_sha256"] == sha(plan_path)
                and all(run_hashes.get(Path(item["path"]).name) == item["sha256"] for item in textures)):
            provenance["authoring_execution"] = {
                "recipe": execution_plan["recipe"], "exit_code": execution_run["exit_code"],
                "timed_out": execution_run["timed_out"], "engine_sha256": execution_plan["binary_sha256"],
                "source_runner_patch_sha256": execution_plan.get("source_runner_patch_sha256"),
                "source_runner_manifest_sha256": execution_plan.get("source_runner_manifest_sha256"),
                "source_runner_modifications": execution_plan.get("source_runner_modifications", []),
                "export_plan_sha256": sha(plan_path), "export_run_sha256": sha(run_path),
            }
            execution_log = Path(execution_run["log"])
            if execution_log.exists():
                messages = execution_log.read_text()
                provenance["authoring_execution"]["log_sha256"] = sha(execution_log)
                provenance["authoring_execution"]["reported_warning_error_lines"] = [
                    line for line in messages.splitlines() if line.startswith(("WARNING:", "ERROR:", "SCRIPT ERROR:"))]
                provenance["authoring_execution"]["script_errors"] = messages.count("SCRIPT ERROR:")
                provenance["authoring_execution"]["boundary"] = "Exit 0 and valid byte-identical PNGs do not imply a warning-free authoring tool; upstream teardown leaks remain separate from the game runtime."
    patch = ASSET/"material-maker-1.8-cli-shutdown.patch"
    if patch.exists():
        provenance["cli_shutdown_patch"] = {"path": str(patch.relative_to(ROOT)), "sha256": sha(patch),
                                             "scope": "Offline Material Maker source CLI only: skip Steam autoload initialization for export, wait for RenderingDevice before graph/preview creation, then drain frames and stop the stock rendering worker before quit. Shader, noise and PNG exporter unchanged."}
    provenance["authoring_history"] = [
        {"recipe": "official Linux 1.8 portable, first graph without export preview marker", "exit": "120s timeout; no PNG; partial output was not retained by first wrapper"},
        {"recipe": "official Linux 1.8 portable, corrected graph", "exit": "120s timeout after two valid PNGs were written; automatic process termination not verified"},
        {"recipe": "fixed 1.8 source with localized CLI thread shutdown patch, first run", "exit": "0 with two byte-identical PNGs and 10 pixel checks; tool log contained Steam initialization failures, size UI metadata error, preview-before-RenderingDevice error, and teardown leaks. Preserved as dirty authoring evidence."},
        {"recipe": "fixed 1.8 source with offline startup/readiness/shutdown patch and completed size UI metadata", "exit": "Actual return code, source modifications and output binding recorded in authoring_execution; no shader/noise/export math changes."},
    ]
    if output == ASSET:
        (ASSET/"source.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2)+"\n")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--export", action="store_true", dest="do_export")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--source-runner", action="store_true",
                        help="Use isolated official 1.8 source plus recorded CLI thread shutdown patch.")
    parser.add_argument("--godot", type=Path, default=Path("/opt/agent-creator/godot/bin/godot"))
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY)
    parser.add_argument("--output", type=Path, default=ASSET)
    args = parser.parse_args()
    ASSET.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    source = ASSET / "palm-materials.ptex"
    source.write_text(json.dumps(graph(), ensure_ascii=False, indent=2)+"\n")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    executable = args.godot.resolve() if args.source_runner else args.binary.resolve()
    process_cwd = LOCAL/"source-runner-1.8" if args.source_runner else ROOT
    command = [str(executable), "--export-material", "--target", "Shu/Palm PNG",
               "--size", "512", "--output-file", "palm", "-o", str(output), str(source)]
    env = os.environ.copy()
    for key, subdir in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        path = LOCAL / ("isolated-source-user" if args.source_runner else "isolated-user") / subdir
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    plan = {"schema": 1, "tool": "Material Maker", "version": "1.8", "tool_commit": TOOL_COMMIT,
            "binary": str(executable), "binary_sha256": sha(executable) if executable.exists() else None,
            "recipe": "fixed 1.8 source with CLI shutdown patch" if args.source_runner else "official 1.8 portable binary",
            "graph": str(source.relative_to(ROOT)), "graph_sha256": sha(source),
            "command": command, "cwd": str(process_cwd), "environment_overrides": {k: env[k] for k in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]},
            "gpu_required": True, "outputs": [str(output / f"palm-{name}.png") for name in ["dust", "wind"]],
            "renderer": "Material Maker official export_material -> stock multi_renderer GPU pipeline",
            "python_raster_generation": False}
    if args.source_runner:
        manifest_path = ASSET/"material-maker-1.8-source-runner.json"
        manifest = json.loads(manifest_path.read_text())
        for item in manifest["modifications"]:
            if sha(process_cwd/item["path"]) != item["patched_sha256"]:
                raise SystemExit("Isolated Material Maker source runner does not match its recorded patch.")
        plan["source_runner_manifest_sha256"] = sha(manifest_path)
        plan["source_runner_patch_sha256"] = manifest["patch_sha256"]
        plan["source_runner_modifications"] = manifest["modifications"]
    if not args.verify:
        (QA / "export-plan.json").write_text(json.dumps(plan, indent=2)+"\n")
    print(json.dumps(plan, indent=2), flush=True)
    if args.do_export:
        log = QA / "export.log"
        try:
            result = subprocess.run(command, cwd=process_cwd, env=env, text=True, capture_output=True, timeout=120)
            return_code = result.returncode
            timed_out = False
            stdout, stderr = result.stdout, result.stderr
        except subprocess.TimeoutExpired as error:
            return_code, timed_out = 124, True
            stdout, stderr = error.stdout or "", error.stderr or ""
            if isinstance(stdout, bytes):
                stdout = stdout.decode("utf-8", errors="replace")
            if isinstance(stderr, bytes):
                stderr = stderr.decode("utf-8", errors="replace")
        log.write_text(stdout+stderr+("\nTIMEOUT: Material Maker exceeded 120 seconds.\n" if timed_out else ""))
        record = {"exit_code": return_code, "timed_out": timed_out, "log": str(log), "plan_sha256": sha(QA/"export-plan.json"),
                  "outputs": [{"path": p, "bytes": Path(p).stat().st_size, "sha256": sha(Path(p))}
                              for p in plan["outputs"] if Path(p).exists()]}
        (QA / "export-run.json").write_text(json.dumps(record, indent=2)+"\n")
        print(json.dumps(record, indent=2), flush=True)
        if return_code or len(record["outputs"]) != 2:
            raise SystemExit("Material Maker export failed; inspect the preserved log.")
        print(json.dumps(inspect_outputs(output, source, args.binary), indent=2), flush=True)
    elif args.verify:
        print(json.dumps(inspect_outputs(output, source, args.binary), indent=2), flush=True)


if __name__ == "__main__":
    main()
