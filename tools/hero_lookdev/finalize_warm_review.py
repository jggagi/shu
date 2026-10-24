#!/usr/bin/env python3
"""Assemble and hash-verify the local Jiang warm sword review deliverable.

This helper copies existing artifacts only. It does not render, encode, invoke
Blender/Godot, or modify its inputs. The output directory must be new.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import struct
import sys
from pathlib import Path, PurePosixPath
from typing import Any


WARM_BLEND_NAME = "jiang-sword-phrase.blend"
REVIEW_BLEND_NAME = "jiang-fullbody-turn.blend"
DELIVERED_BLEND_NAME = "jiang-sword-phrase.blend"
MANIFEST_NAME = "sha256-manifest.json"
FRAME_COUNT = 120
FPS = 30
VERIFICATION_CHECKS = 27

REPRODUCTION_SCRIPTS = (
    "tools/hero_lookdev/warm_sword_phrase.py",
    "tools/hero_lookdev/build_fullbody_turn.py",
    "tools/hero_lookdev/refine_fullbody_turn.py",
    "tools/hero_lookdev/grip_geometry.py",
    "tools/hero_lookdev/package_turn_review.py",
    "tools/hero_lookdev/build_turn_scene_review.py",
    "tools/hero_lookdev/verify_sword_phrase.py",
    "tools/hero_lookdev/verify_fullbody_turn.py",
    "tools/hero_lookdev/verify_refined_turn.py",
    "tools/hero_lookdev/finalize_warm_review.py",
)
STUDY_SOURCE_FILES = (
    "docs/image-motion/jiang-warm-sword-20261022.md",
    "docs/image-motion/jiang-fullbody-turn-20261022.md",
    "docs/image-motion/jiang-turn-refined-20261022.md",
    "docs/image-motion/jiang-cute-handsome-20261022.md",
    "docs/image-motion/jiang-hunyuan-bust-20261022.md",
    "docs/image-motion/jiang-meshy-bust-20261022.md",
    "art/prompts/jiang-fullbody-turn-20261022.txt",
    "art/prompts/jiang-cute-handsome-look-20261022.txt",
    "art/prompts/jiang-meshy-bust-input-20261022.txt",
)


class FinalizeError(RuntimeError):
    """Invalid input, incomplete copy, or manifest verification failure."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def file_record(path: Path, root: Path) -> dict[str, Any]:
    return {
        "path": path.relative_to(root).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def absolute_existing(value: Path, label: str, kind: str) -> Path:
    raw = value.expanduser()
    if not raw.is_absolute():
        raise FinalizeError(f"{label} must be an absolute path: {value}")
    if raw.is_symlink():
        raise FinalizeError(f"{label} must not be a symlink: {raw}")
    try:
        resolved = raw.resolve(strict=True)
    except FileNotFoundError as exc:
        raise FinalizeError(f"{label} does not exist: {raw}") from exc
    if kind == "directory" and not resolved.is_dir():
        raise FinalizeError(f"{label} must be a directory: {resolved}")
    if kind == "file" and not resolved.is_file():
        raise FinalizeError(f"{label} must be a regular file: {resolved}")
    return resolved


def json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise FinalizeError(f"Could not read {label} JSON at {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise FinalizeError(f"{label} must contain a JSON object: {path}")
    return value


def safe_manifest_path(value: Any) -> PurePosixPath:
    if not isinstance(value, str) or not value:
        raise FinalizeError("Manifest entry has an empty or invalid path")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or "\\" in value:
        raise FinalizeError(f"Manifest path must stay inside its package: {value!r}")
    return path


def tree_files(root: Path, excluded_top_level: tuple[str, ...] = ()) -> list[Path]:
    files: list[Path] = []
    for directory, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(directory)
        kept_directories: list[str] = []
        for name in sorted(directory_names):
            child = current / name
            if current == root and name in excluded_top_level:
                continue
            if child.is_symlink():
                raise FinalizeError(f"Symlinks are not allowed in packaged inputs: {child}")
            kept_directories.append(name)
        directory_names[:] = kept_directories
        for name in sorted(file_names):
            path = current / name
            if path.is_symlink():
                raise FinalizeError(f"Symlinks are not allowed in packaged inputs: {path}")
            if not path.is_file():
                raise FinalizeError(f"Unsupported filesystem entry: {path}")
            files.append(path)
    return files


def verify_manifest(root: Path, manifest_path: Path, label: str) -> dict[str, Any]:
    manifest = json_object(manifest_path, f"{label} SHA-256 manifest")
    if manifest.get("algorithm") != "SHA-256" or not isinstance(manifest.get("files"), list):
        raise FinalizeError(f"{label} manifest has an unsupported shape")
    listed: dict[str, tuple[int, str]] = {}
    for item in manifest["files"]:
        if not isinstance(item, dict):
            raise FinalizeError(f"{label} manifest contains a non-object file record")
        relative = safe_manifest_path(item.get("path")).as_posix()
        try:
            expected_bytes = int(item["bytes"])
        except (KeyError, TypeError, ValueError) as exc:
            raise FinalizeError(f"{label} manifest has invalid byte count for {relative}") from exc
        expected_hash = item.get("sha256")
        if not isinstance(expected_hash, str) or len(expected_hash) != 64:
            raise FinalizeError(f"{label} manifest has invalid SHA-256 for {relative}")
        if relative in listed:
            raise FinalizeError(f"{label} manifest repeats a path: {relative}")
        listed[relative] = (expected_bytes, expected_hash)

    actual_paths = {
        path.relative_to(root).as_posix()
        for path in tree_files(root)
        if path != manifest_path
    }
    if actual_paths != set(listed):
        missing = sorted(actual_paths - set(listed))[:5]
        absent = sorted(set(listed) - actual_paths)[:5]
        raise FinalizeError(
            f"{label} manifest file set differs from package contents; "
            f"unlisted={missing}, missing={absent}"
        )
    for relative, (expected_bytes, expected_hash) in listed.items():
        path = root.joinpath(*PurePosixPath(relative).parts)
        if path.stat().st_size != expected_bytes or sha256_file(path) != expected_hash:
            raise FinalizeError(f"{label} manifest verification failed for {relative}")
    return manifest


def read_image_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(29)
        if (len(header) >= 29
                and header[:8] == b"\x89PNG\r\n\x1a\n"
                and header[12:16] == b"IHDR"):
            width, height = struct.unpack(">II", header[16:24])
            if width > 0 and height > 0:
                return width, height
            raise FinalizeError(f"PNG has invalid dimensions: {path}")

        if header[:2] != b"\xff\xd8":
            raise FinalizeError(f"Expected a readable PNG or JPEG image: {path}")

        stream.seek(2)
        while True:
            byte = stream.read(1)
            if not byte:
                break
            if byte != b"\xff":
                continue
            marker_byte = stream.read(1)
            while marker_byte == b"\xff":
                marker_byte = stream.read(1)
            if not marker_byte:
                break
            marker = marker_byte[0]
            if marker in (0x00, 0xD8, 0xD9, 0x01) or 0xD0 <= marker <= 0xD7:
                continue
            segment_length_bytes = stream.read(2)
            if len(segment_length_bytes) != 2:
                break
            segment_length = struct.unpack(">H", segment_length_bytes)[0]
            if segment_length < 2:
                break
            segment = stream.read(segment_length - 2)
            if len(segment) != segment_length - 2:
                break
            is_start_of_frame = (
                marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                           0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF)
            )
            if is_start_of_frame:
                if len(segment) < 5:
                    break
                height, width = struct.unpack(">HH", segment[1:5])
                if width > 0 and height > 0:
                    return width, height
                break
            if marker == 0xDA:
                break

    raise FinalizeError(f"Could not read image dimensions from PNG or JPEG header: {path}")


def path_inside(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


def copy_file_verified(source: Path, destination: Path) -> dict[str, Any]:
    if source.is_symlink() or not source.is_file():
        raise FinalizeError(f"Expected a regular source file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    before = sha256_file(source)
    with source.open("rb") as source_stream, destination.open("xb") as destination_stream:
        shutil.copyfileobj(source_stream, destination_stream)
    copied = sha256_file(destination)
    after = sha256_file(source)
    if copied != before or after != before:
        raise FinalizeError(f"Source changed during copy or copied hash differs: {source}")
    return {"path": destination.name, "bytes": destination.stat().st_size, "sha256": copied}


def copy_tree_verified(
    source: Path, destination: Path, excluded_top_level: tuple[str, ...] = ()
) -> list[dict[str, Any]]:
    copied: list[dict[str, Any]] = []
    for path in tree_files(source, excluded_top_level):
        relative = path.relative_to(source)
        copied.append(copy_file_verified(path, destination / relative))
    return copied


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")


def package_manifest(root: Path) -> list[dict[str, Any]]:
    manifest_path = root / MANIFEST_NAME
    return [file_record(path, root) for path in tree_files(root) if path != manifest_path]


def write_and_verify_manifest(root: Path) -> dict[str, Any]:
    manifest_path = root / MANIFEST_NAME
    write_json(manifest_path, {"algorithm": "SHA-256", "files": package_manifest(root)})
    manifest = verify_manifest(root, manifest_path, "final package")
    return manifest


def copy_review_package(source: Path, destination: Path) -> dict[str, Any]:
    source_manifest = source / MANIFEST_NAME
    verify_manifest(source, source_manifest, "review source")
    metadata = json_object(source / "metadata.json", "review metadata")
    model_record = metadata.get("package", {}).get("model_copy")
    if not isinstance(model_record, dict) or model_record.get("path") != REVIEW_BLEND_NAME:
        raise FinalizeError(f"Review metadata must identify {REVIEW_BLEND_NAME!r} as its model copy")

    source_model = source / REVIEW_BLEND_NAME
    if not source_model.is_file() or source_model.is_symlink():
        raise FinalizeError(f"Review package is missing its saved Blender project: {source_model}")
    destination.mkdir(parents=True, exist_ok=False)
    for path in tree_files(source):
        if path in (source_manifest, source_model):
            continue
        relative = path.relative_to(source)
        copy_file_verified(path, destination / relative)
    copied_model = destination / DELIVERED_BLEND_NAME
    copy_file_verified(source_model, copied_model)

    copied_metadata_path = destination / "metadata.json"
    copied_metadata = json_object(copied_metadata_path, "copied review metadata")
    copied_metadata["package"]["model_copy"] = file_record(copied_model, destination)
    copied_metadata["package"]["model_copy"]["renamed_from"] = REVIEW_BLEND_NAME
    temporary = copied_metadata_path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(copied_metadata, indent=2, ensure_ascii=False, allow_nan=False) + "\n",
                          encoding="utf-8")
    temporary.replace(copied_metadata_path)
    write_and_verify_manifest(destination)
    return copied_metadata


def read_source_inputs(args: argparse.Namespace) -> dict[str, Any]:
    base = absolute_existing(args.base, "--base", "directory")
    stage = absolute_existing(args.stage, "--stage", "directory")
    scene_qa = absolute_existing(args.scene_qa, "--scene-qa", "directory")
    review = absolute_existing(args.review, "--review", "directory")
    browser_proof = absolute_existing(args.browser_proof, "--browser-proof", "file")
    browser_observation = absolute_existing(args.browser_observation, "--browser-observation", "file")
    config = absolute_existing(args.config, "--config", "file")

    if not path_inside(review, base):
        raise FinalizeError("--review must be inside --base (expected base/review-warm-v4)")
    for label, path, excluded in (
        ("--stage", stage, (".godot",)),
        ("--scene-qa", scene_qa, ()),
        ("--review", review, ()),
    ):
        tree_files(path, excluded)

    warm_dir = base / "phrase-warm-v4"
    original_dir = base / "phrase-original-v4"
    warm_blend = warm_dir / WARM_BLEND_NAME
    warm_report_path = warm_dir / "phrase-report.json"
    warm_verification_path = warm_dir / "verification-v1.json"
    original_report_path = original_dir / "phrase-report.json"
    original_blend = original_dir / WARM_BLEND_NAME
    alpha_pair_path = base / "alpha-pair-v4.json"
    required_files = {
        "final warm blend": warm_blend,
        "warm action report": warm_report_path,
        "warm verification report": warm_verification_path,
        "original-color action report": original_report_path,
        "original-color reference blend": original_blend,
        "alpha pair report": alpha_pair_path,
        "review preview": review / "turn-preview.mp4",
        "review contact sheet": review / "contact-sheet.png",
        "review viewer": review / "index.html",
        "review metadata": review / "metadata.json",
        "review manifest": review / MANIFEST_NAME,
        "stage project": stage / "project.godot",
        "stage build receipt": stage / "build-info.json",
        "scene QA report": scene_qa / "scene-verification.json",
    }
    for label, path in required_files.items():
        if path.is_symlink() or not path.is_file():
            raise FinalizeError(f"Missing required {label}: {path}")
    if not tree_files(scene_qa):
        raise FinalizeError(f"--scene-qa contains no files: {scene_qa}")

    warm_report = json_object(warm_report_path, "warm action report")
    original_report = json_object(original_report_path, "original-color action report")
    verification = json_object(warm_verification_path, "warm verification report")
    stage_receipt = json_object(stage / "build-info.json", "stage build receipt")
    scene_qa_report = json_object(scene_qa / "scene-verification.json", "scene QA report")
    review_metadata = json_object(review / "metadata.json", "review metadata")
    browser_record = json_object(browser_observation, "browser observation")
    config_data = json_object(config, "landmark configuration")
    alpha_pair = json.loads(alpha_pair_path.read_text(encoding="utf-8"))

    if warm_report.get("palette") != "warm":
        raise FinalizeError("Warm action report does not identify the warm palette")
    if original_report.get("palette") != "original":
        raise FinalizeError("Original-color action report does not identify the original palette")
    summary = verification.get("summary", {})
    if (verification.get("status") != "PASS"
            or summary.get("checks_passed") != VERIFICATION_CHECKS
            or summary.get("checks_failed") != 0):
        raise FinalizeError("Warm v4 verification must be PASS with exactly 27 passed checks and no failures")
    verification_source = verification.get("source")
    saved_blend_hash = (verification_source.get("saved_blend_sha256")
                        if isinstance(verification_source, dict) else None)
    if saved_blend_hash != sha256_file(warm_blend):
        raise FinalizeError("Warm verification source.saved_blend_sha256 must match the current warm final blend")
    if stage_receipt.get("status") != "STAGE_PREPARED":
        raise FinalizeError("Stage build receipt is not STAGE_PREPARED")
    scene_failures = scene_qa_report.get("failures")
    if scene_qa_report.get("status") != "PASS" or type(scene_failures) is not int or scene_failures != 0:
        raise FinalizeError("Scene QA report must have PASS status and failures == 0")
    if not isinstance(browser_record, dict) or not isinstance(config_data, dict):
        raise FinalizeError("Browser observation and landmark configuration must be JSON objects")
    if (not isinstance(alpha_pair, dict)
            or alpha_pair.get("status") != "PASS"
            or alpha_pair.get("all_alpha_exactly_equal") is not True
            or alpha_pair.get("all_motion_reports_identical") is not True
            or alpha_pair.get("frame_count") != FRAME_COUNT):
        raise FinalizeError(
            "alpha-pair-v4.json must PASS with exact alpha and motion-report parity across 120 frames"
        )
    if browser_proof.suffix.lower() not in (".png", ".jpg", ".jpeg"):
        raise FinalizeError("--browser-proof must have a .png, .jpg, or .jpeg extension")
    proof_dimensions = read_image_dimensions(browser_proof)

    review_metadata = json_object(review / "metadata.json", "review metadata")
    if (review_metadata.get("fps") != FPS
            or review_metadata.get("frame_count") != FRAME_COUNT
            or review_metadata.get("duration_seconds") != FRAME_COUNT / FPS
            or review_metadata.get("clip_semantics") != "single action, not seamless loop"):
        raise FinalizeError("Review metadata must describe the 120-frame, 30 fps, four-second single action")
    frames_dir = review / "frames"
    expected_frames = {f"frame-{index:04d}.png" for index in range(1, FRAME_COUNT + 1)}
    actual_frames = {path.name for path in frames_dir.iterdir()
                     if path.name.startswith("frame-") and path.suffix.lower() == ".png"} if frames_dir.is_dir() else set()
    if actual_frames != expected_frames:
        raise FinalizeError("Review package must contain exactly 120 sequential transparent frame PNGs")
    viewer_text = (review / "index.html").read_text(encoding="utf-8")
    if "play-normal" not in viewer_text or "play-slow" not in viewer_text:
        raise FinalizeError("Review HTML must provide both normal-speed and half-speed playback controls")

    package_source_model = review / REVIEW_BLEND_NAME
    package_meta_model = review_metadata.get("package", {}).get("model_copy", {})
    if (not package_source_model.is_file()
            or package_meta_model.get("sha256") != sha256_file(warm_blend)
            or sha256_file(package_source_model) != sha256_file(warm_blend)):
        raise FinalizeError("Review package model must match phrase-warm-v4/jiang-sword-phrase.blend")
    verify_manifest(review, review / MANIFEST_NAME, "review source")

    repository_root = Path(__file__).resolve().parents[2]
    reproduction_sources: list[Path] = []
    for relative in REPRODUCTION_SCRIPTS:
        path = repository_root / relative
        if not path.is_file() or path.is_symlink():
            raise FinalizeError(f"Required reproduction script is missing: {path}")
        reproduction_sources.append(path)
    study_sources: list[Path] = []
    for relative in STUDY_SOURCE_FILES:
        path = repository_root / relative
        if not path.is_file() or path.is_symlink():
            raise FinalizeError(f"Required linked study source is missing: {path}")
        study_sources.append(path)

    return {
        "base": base,
        "stage": stage,
        "scene_qa": scene_qa,
        "review": review,
        "browser_proof": browser_proof,
        "browser_observation": browser_observation,
        "config": config,
        "warm_dir": warm_dir,
        "warm_blend": warm_blend,
        "warm_report": warm_report_path,
        "warm_verification": warm_verification_path,
        "original_dir": original_dir,
        "original_blend": original_blend,
        "original_report": original_report_path,
        "alpha_pair": alpha_pair_path,
        "reproduction_sources": reproduction_sources,
        "study_sources": study_sources,
        "warm_report_data": warm_report,
        "original_report_data": original_report,
        "verification_data": verification,
        "stage_receipt": stage_receipt,
        "scene_qa_report": scene_qa_report,
        "review_metadata": review_metadata,
        "browser_proof_dimensions": proof_dimensions,
    }


def write_readme(root: Path, sources: dict[str, Any]) -> None:
    baseline = sources["verification_data"].get("baseline", {})
    baseline_path = baseline.get("path") if isinstance(baseline, dict) else None
    baseline_note = ("复核基线报告已放入 `reproduction/baseline-report.json`。"
                     if (root / "reproduction" / "baseline-report.json").is_file()
                     else f"复核报告记录的基线来源：`{baseline_path or '未记录'}`；本包不依赖固定的旧版报告路径。")
    content = f"""# 江砚秋暖色持剑单招审阅包

本地交付快照：暖色四秒、30 fps、120 帧的单次动作（不是无缝循环）。暖色和单招仍待用户审阅；本轮无新增云端调用或费用。Windows 生产性能尚未验收。

## 观看与打开

- 打开 [`review/index.html`](review/index.html)：可正常播放、半速播放、逐帧查看透明帧。
- 打开 [`review/jiang-sword-phrase.blend`](review/jiang-sword-phrase.blend)：最终暖色 Blender 工程。它由审阅包内的模型文件重命名而来，只保存一份。
- 用 Godot 4.7.2 打开 [`godot-stage/project.godot`](godot-stage/project.godot)。审阅目录与浏览器观测证据在 `scene-qa/` 和 `browser-evidence/`。

## 报告与来源

- 暖色动作报告、27 项通过的结构／动画验证和原色动作报告见 `reports/`。
- `reports/alpha-pair-v4.json` 保存原色／暖色逐帧对照证据。
- 原色参考 Blender 文件不重复复制；源路径和 SHA-256 记在 `provenance.json`。
- {baseline_note}

## 复现材料

本包将制作、打包、场景准备与验证脚本放在 `reproduction/tools/hero_lookdev/`，地标配置在 `reproduction/config/landmarks.json`。`reproduction/commands.json` 记录了可复用的命令模板。暖色最终工程和透明帧可直接从 `review/` 取用；脚本依赖 Blender、NumPy、Pillow 或 FFmpeg 的环境要求见各脚本说明。

所有文件的字节数和 SHA-256 见根目录 `{MANIFEST_NAME}`；打包器已在写入后逐项读回核验。
"""
    (root / "README.md").write_text(content, encoding="utf-8", newline="\n")


def finalize(args: argparse.Namespace) -> dict[str, Any]:
    sources = read_source_inputs(args)
    output_raw = args.out.expanduser()
    if not output_raw.is_absolute():
        raise FinalizeError("--out must be an absolute path")
    if output_raw.exists() or output_raw.is_symlink():
        raise FinalizeError(f"Refusing to overwrite existing output: {output_raw}")
    if not output_raw.parent.is_dir():
        raise FinalizeError(f"Output parent directory must already exist: {output_raw.parent}")
    output = output_raw.parent.resolve() / output_raw.name
    if output == sources["base"]:
        raise FinalizeError("--out must be a new sibling inside or outside --base, not --base itself")
    for key in ("stage", "scene_qa", "review"):
        if path_inside(output, sources[key]):
            raise FinalizeError(f"--out must be outside input {key}: {sources[key]}")

    output.mkdir(exist_ok=False)
    try:
        copied_review = copy_review_package(sources["review"], output / "review")

        copy_tree_verified(sources["stage"], output / "godot-stage", excluded_top_level=(".godot",))
        copy_tree_verified(sources["scene_qa"], output / "scene-qa")
        browser_proof_name = f"browser-proof{sources['browser_proof'].suffix.lower()}"
        browser_proof_path = output / "browser-evidence" / browser_proof_name
        copy_file_verified(sources["browser_proof"], browser_proof_path)
        copy_file_verified(sources["browser_observation"],
                           output / "browser-evidence" / "browser-observation.json")

        copy_file_verified(sources["warm_report"], output / "reports" / "phrase-warm-v4" / "phrase-report.json")
        copy_file_verified(sources["warm_verification"],
                           output / "reports" / "phrase-warm-v4" / "verification-v1.json")
        copy_file_verified(sources["original_report"],
                           output / "reports" / "phrase-original-v4" / "phrase-report.json")
        copy_file_verified(sources["alpha_pair"], output / "reports" / "alpha-pair-v4.json")

        script_dest_root = output / "reproduction" / "tools" / "hero_lookdev"
        for script in sources["reproduction_sources"]:
            relative = Path(script.name)
            copy_file_verified(script, script_dest_root / relative)
        copy_file_verified(sources["config"], output / "reproduction" / "config" / "landmarks.json")
        repository_root = Path(__file__).resolve().parents[2]
        for source in sources["study_sources"]:
            copy_file_verified(source, output / source.relative_to(repository_root))

        source_original = sources["original_blend"]
        source_warm = sources["warm_blend"]
        baseline_info: dict[str, Any] = {}
        recorded_baseline = sources["verification_data"].get("baseline", {})
        baseline_source = recorded_baseline.get("path") if isinstance(recorded_baseline, dict) else None
        if isinstance(baseline_source, str):
            baseline_path = Path(baseline_source).expanduser()
            if baseline_path.is_absolute() and baseline_path.is_file() and not baseline_path.is_symlink():
                copy_file_verified(baseline_path, output / "reproduction" / "baseline-report.json")
                baseline_info = {
                    "source_path": str(baseline_path),
                    "source_sha256": sha256_file(baseline_path),
                    "delivered_path": "reproduction/baseline-report.json",
                    "delivered": True,
                }
            else:
                baseline_info = {"source_path": baseline_source, "delivered": False}

        warm_source_blend = sources["warm_report_data"].get("source_blend")
        warm_source_record: dict[str, Any] = {"path": warm_source_blend, "included": False}
        if isinstance(warm_source_blend, str):
            warm_source_path = Path(warm_source_blend).expanduser()
            if warm_source_path.is_absolute() and warm_source_path.is_file() and not warm_source_path.is_symlink():
                warm_source_record.update({"bytes": warm_source_path.stat().st_size,
                                           "sha256": sha256_file(warm_source_path)})

        provenance = {
            "warm_final_blend": {
                "source_path": str(source_warm),
                "source_bytes": source_warm.stat().st_size,
                "source_sha256": sha256_file(source_warm),
                "delivered_path": "review/jiang-sword-phrase.blend",
                "review_copy_sha256": copied_review["package"]["model_copy"]["sha256"],
            },
            "original_palette_reference_blend": {
                "source_path": str(source_original),
                "bytes": source_original.stat().st_size,
                "sha256": sha256_file(source_original),
                "copied": False,
            },
            "warm_build_input_blend": warm_source_record,
            "verification_baseline": baseline_info,
            "input_roots": {
                "stage": str(sources["stage"]),
                "scene_qa": str(sources["scene_qa"]),
                "review": str(sources["review"]),
                "landmarks_config": str(sources["config"]),
            },
            "scene_qa": {
                "report_path": "scene-qa/scene-verification.json",
                "status": sources["scene_qa_report"].get("status"),
            },
            "browser_proof": {
                "path": browser_proof_path.relative_to(output).as_posix(),
                "dimensions_px": list(sources["browser_proof_dimensions"]),
            },
            "verification": {
                "status": sources["verification_data"].get("status"),
                "checks_passed": sources["verification_data"].get("summary", {}).get("checks_passed"),
                "checks_failed": sources["verification_data"].get("summary", {}).get("checks_failed"),
            },
        }
        write_json(output / "provenance.json", provenance)

        commands = {
            "view": "Open /ABSOLUTE/PACKAGE/review/index.html in a browser or copy the package to a local web server.",
            "repackage_review": (
                "python3 /ABSOLUTE/PACKAGE/reproduction/tools/hero_lookdev/package_turn_review.py "
                "--frames-dir /ABSOLUTE/PACKAGE/review/frames --frame-count 120 "
                "--blend /ABSOLUTE/PACKAGE/review/jiang-sword-phrase.blend "
                "--output /ABSOLUTE/NEW_OUTPUT"
            ),
            "rebuild_warm_action": (
                "blender --disable-autoexec --background /ABSOLUTE/SOURCE_BLEND "
                "--python /ABSOLUTE/PACKAGE/reproduction/tools/hero_lookdev/warm_sword_phrase.py -- "
                "--input /ABSOLUTE/SOURCE_BLEND --config /ABSOLUTE/PACKAGE/reproduction/config/landmarks.json "
                "--out /ABSOLUTE/NEW_OUTPUT --mode build --palette warm"
            ),
            "verify_warm_action": (
                "blender --disable-autoexec --background /ABSOLUTE/PACKAGE/review/jiang-sword-phrase.blend "
                "--python /ABSOLUTE/PACKAGE/reproduction/tools/hero_lookdev/verify_sword_phrase.py -- "
                "--report /ABSOLUTE/NEW_REPORT.json --baseline-report "
                + ("/ABSOLUTE/PACKAGE/reproduction/baseline-report.json" if baseline_info.get("delivered")
                   else "/BASELINE_PATH_FROM_PROVENANCE")
            ),
            "note": "All commands create new outputs; adapt absolute paths for the local machine.",
        }
        write_json(output / "reproduction" / "commands.json", commands)
        write_readme(output, sources)

        final_manifest = write_and_verify_manifest(output)
        return {
            "status": "DONE",
            "output": str(output),
            "file_count": len(final_manifest["files"]),
            "warm_verification": provenance["verification"],
            "review_blend": "review/jiang-sword-phrase.blend",
            "manifest": MANIFEST_NAME,
            "readback_verified": True,
        }
    except Exception:
        if output.is_dir() and not output.is_symlink():
            shutil.rmtree(output)
        raise


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True,
                        help="absolute external artifact root containing phrase-warm-v4/ and phrase-original-v4/")
    parser.add_argument("--stage", type=Path, required=True,
                        help="absolute path to the prepared Godot project stage")
    parser.add_argument("--scene-qa", type=Path, required=True,
                        help="absolute path to the completed scene QA evidence directory")
    parser.add_argument("--review", type=Path, required=True,
                        help="absolute path to base/review-warm-v4")
    parser.add_argument("--browser-proof", type=Path, required=True,
                        help="absolute path to the observed browser proof PNG or JPEG")
    parser.add_argument("--browser-observation", type=Path, required=True,
                        help="absolute path to the browser observation JSON")
    parser.add_argument("--config", type=Path, required=True,
                        help="absolute path to the warm phrase landmarks.json")
    parser.add_argument("--out", type=Path, required=True,
                        help="absolute path for a new final review package directory")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = finalize(args)
    except (FinalizeError, OSError, json.JSONDecodeError, shutil.Error) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
