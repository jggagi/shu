"""Interactive process-only setup; real requests require an explicit user choice."""

import argparse
import getpass
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
for layout in (".agents", ".codex"):
    script_directory = ROOT / layout / "skills" / "game-art" / "scripts"
    if (script_directory / "qwen_image.py").is_file():
        sys.path.insert(0, str(script_directory))
        break
else:
    raise SystemExit("[ERROR] Install game-art under .agents/skills or .codex/skills in this project first")

import doctor
import qwen_image


def configure():
    """Keep secrets solely in this process environment and conceal key entry."""
    print("\nGame Art / Qwen setup")
    print("Settings apply to this helper session only; no credentials are saved to files.")
    existing = bool(os.environ.get("DASHSCOPE_API_KEY", "").strip())
    label = "API key (hidden; Enter keeps current value): " if existing else "API key (hidden): "
    # getpass may fall back to echoed stdin when no terminal exists: refuse that.
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        key = getpass.getpass(label).strip()
    if key:
        os.environ["DASHSCOPE_API_KEY"] = key
    existing = bool(os.environ.get("QWEN_IMAGE_ENDPOINT", "").strip())
    label = "Complete HTTPS endpoint (Enter keeps current value): " if existing else "Complete HTTPS /images/generations endpoint: "
    endpoint = input(label).strip()
    if endpoint:
        os.environ["QWEN_IMAGE_ENDPOINT"] = endpoint


def main(argv=None):
    parser = argparse.ArgumentParser(description="Configure Qwen for this window, check it, and preview a request offline")
    parser.add_argument("--no-input", action="store_true", help="Run doctor using existing environment; no prompts or network")
    args = parser.parse_args(argv)
    if sys.version_info < (3, 12):
        print("[ERROR] Python 3.12+ is required")
        return 1
    try:
        if not args.no_input:
            configure()
        result = doctor.main(["--no-network"])
        if result or args.no_input:
            return result
        while True:
            print("\n1 = Offline preview (default, no network)\n2 = Generate one image (billable)\n0 = Exit")
            choice = input("Choose: ").strip() or "1"
            if choice == "0":
                return 0
            if choice not in {"1", "2"}:
                print("Choose 1, 2 or 0.")
                continue
            prompt = input("Prompt (Enter uses 'watercolor courtyard scene reference'): ").strip() or "watercolor courtyard scene reference"
            output = input("Output PNG (Enter uses art/work/setup-preview.png): ").strip() or "art/work/setup-preview.png"
            command = ["--prompt", prompt, "--out", output]
            if choice == "1":
                command.append("--dry-run")
            else:
                if input("One Qwen request may incur charges. Type GENERATE to submit: ").strip() != "GENERATE":
                    print("Generation cancelled.")
                    continue
            qwen_image.main(command)
    except getpass.GetPassWarning:
        print("[ERROR] Hidden key input requires an interactive terminal. Double-click Setup-Game-Art.cmd.")
        return 1
    except (EOFError, KeyboardInterrupt):
        print("\nSetup cancelled; no paid requests were made.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
