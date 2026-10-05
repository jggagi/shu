"""Check local Game Art configuration. Never performs network requests."""

import argparse
import os
from pathlib import Path
import sys
import tempfile

from art_manifest import load_config, repo_path, repo_root
from qwen_image import ArtError, credentials


def check_writable(directory):
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryFile(dir=directory):
        pass


def main(argv=None):
    parser = argparse.ArgumentParser(description="Configuration readiness only; never generates an image")
    parser.add_argument("--no-network", action="store_true", help="Explicit offline check (also the default)")
    parser.parse_args(argv)
    print("Game Art Skill\n")
    local_ok = True
    root = repo_root()
    skill_installed = any(
        (root / skill_path).is_file()
        for skill_path in (".agents/skills/game-art/SKILL.md", ".codex/skills/game-art/SKILL.md")
    )
    print("[OK] repository root" if skill_installed else "[FAIL] repository root")
    python_ok = sys.version_info >= (3, 12)
    print("[OK] Python version" if python_ok else "[FAIL] Python 3.12+ required")
    local_ok = local_ok and python_ok and skill_installed
    try:
        config = load_config(root)
        print("[OK] art/config.json")
        check_writable(repo_path(root, config["work_dir"]))
        print("[OK] work directory writable")
        manifest = repo_path(root, config["manifest"])
        check_writable(manifest.parent)
        if manifest.exists():
            import json
            for line in manifest.read_text(encoding="utf-8").splitlines():
                if line.strip() and not isinstance(json.loads(line), dict):
                    raise ValueError()
            with manifest.open("ab"):
                pass
        print("[OK] manifest location")
        for key in ("approved_dir", "reference_dir", "prompt_dir"):
            path = repo_path(root, config[key])
            path.mkdir(parents=True, exist_ok=True)
    except (ValueError, OSError):
        print("[FAIL] config, work directory or manifest; inspect repo files and permissions")
        local_ok = False
    for name in ("DASHSCOPE_API_KEY", "QWEN_IMAGE_ENDPOINT"):
        present = bool(os.environ.get(name, "").strip())
        print(f"[{'OK' if present else 'WARN'}] {name} {'present' if present else 'missing'}")
    ready = False
    try:
        credentials()
        ready = local_ok
    except ArtError:
        if all(os.environ.get(name, "").strip() for name in ("DASHSCOPE_API_KEY", "QWEN_IMAGE_ENDPOINT")):
            print("[WARN] Qwen environment format invalid; check the complete HTTPS endpoint and token")
    print("\nCodex imagegen:\n  agent-managed / optional")
    print("\nQwen:\n  " + ("READY (configuration only; network and account access untested)" if ready else "NOT CONFIGURED / NOT READY"))
    print("\nNo network calls or paid generations performed.")
    # Missing optional backend credentials are a WARN; broken local installation fails.
    return 0 if local_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
