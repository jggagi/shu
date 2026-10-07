"""Run project Qwen art tools with process-only credentials.

macOS local settings live in ignored .local/qwen-art.json; secrets remain in
Keychain. A complete explicit environment takes precedence on every host.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / ".agents/skills/game-art/scripts"


def environment():
    env = os.environ.copy()
    names = ("DASHSCOPE_API_KEY", "QWEN_IMAGE_ENDPOINT")
    present = [bool(env.get(name, "").strip()) for name in names]
    if all(present):
        return env
    if any(present):
        raise ValueError("Set both Qwen environment variables together; partial overrides are refused")
    if sys.platform != "darwin":
        raise ValueError("Configure both Qwen environment variables on this host")
    config = json.loads((ROOT / ".local/qwen-art.json").read_text(encoding="utf-8"))
    endpoint = config["endpoint"]
    url = urlsplit(endpoint)
    if (url.scheme != "https" or not url.hostname
            or not url.hostname.endswith(".maas.aliyuncs.com")
            or url.username or url.password or url.port or url.query or url.fragment
            or url.path != "/compatible-mode/v1/images/generations"):
        raise ValueError("Local endpoint must be an Alibaba workspace HTTPS image endpoint")
    result = subprocess.run([
        "/usr/bin/security", "find-generic-password", "-s", config["keychain_service"],
        "-a", config["keychain_account"], "-w",
    ], capture_output=True, timeout=15)
    if result.returncode != 0:
        raise ValueError("Qwen Keychain credential is unavailable; no network request was made")
    key = result.stdout.decode("utf-8").strip()
    if not key or "\r" in key or "\n" in key:
        raise ValueError("Qwen Keychain credential format is invalid")
    env["DASHSCOPE_API_KEY"] = key
    env["QWEN_IMAGE_ENDPOINT"] = endpoint
    return env


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in {"doctor", "generate"}:
        print("Usage: python tools/qwen_art.py {doctor|generate} [art tool arguments]")
        return 2
    try:
        env = environment()
    except (OSError, KeyError, ValueError, subprocess.TimeoutExpired):
        print("[ERROR] Qwen local configuration or Keychain access failed; inspect local settings without printing secrets")
        return 1
    script = "doctor.py" if sys.argv[1] == "doctor" else "qwen_image.py"
    return subprocess.run([sys.executable, str(SCRIPTS / script), *sys.argv[2:]],
                          cwd=ROOT, env=env).returncode


if __name__ == "__main__":
    raise SystemExit(main())
