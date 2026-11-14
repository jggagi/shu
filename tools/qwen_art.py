"""Run project Qwen art tools with process-only credentials.

Ignored .local/qwen-art.json contains only endpoint and vault metadata.
Secrets remain in Linux Secret Service or macOS Keychain. A complete explicit
environment takes precedence on every host.
"""
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / ".agents/skills/game-art/scripts"
SETTINGS = ROOT / ".local/qwen-art.json"
SECRET_TOOL = "/usr/bin/secret-tool"


def validate_endpoint(endpoint):
    if not isinstance(endpoint, str) or any(char.isspace() or ord(char) < 32 or ord(char) == 127 for char in endpoint):
        raise ValueError("Invalid image endpoint")
    url = urlsplit(endpoint)
    if (url.scheme != "https" or not url.hostname
            or not url.hostname.endswith(".maas.aliyuncs.com")
            or url.username or url.password or url.port or url.query or url.fragment
            or url.path != "/compatible-mode/v1/images/generations"):
        raise ValueError("Use the complete official Alibaba workspace image endpoint")
    return endpoint


def private_settings():
    fd = os.open(SETTINGS, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "r", encoding="utf-8") as handle:
        meta = os.fstat(handle.fileno())
        if not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or meta.st_mode & 0o077:
            raise ValueError("Local art settings must be private and owned by the current user")
        text = handle.read(16385)
        if len(text) > 16384:
            raise ValueError("Local art settings are too large")
        config = json.loads(text)
    if not isinstance(config, dict):
        raise ValueError("Invalid local art settings")
    return config


def single_line_key(value):
    if not re.fullmatch(r"[A-Za-z0-9._-]{8,4096}", value):
        raise ValueError("Invalid credential format")
    return value


def environment():
    env = os.environ.copy()
    names = ("DASHSCOPE_API_KEY", "QWEN_IMAGE_ENDPOINT")
    present = [bool(env.get(name, "").strip()) for name in names]
    if all(present):
        return env
    if any(present):
        raise ValueError("Set both Qwen environment variables together; partial overrides are refused")
    if sys.platform.startswith("linux"):
        config = private_settings()
        endpoint = validate_endpoint(config["endpoint"])
        secret_id = config["secret_id"]
        if not isinstance(secret_id, str) or not re.fullmatch(r"[a-f0-9]{32}", secret_id):
            raise ValueError("Invalid local credential identifier")
        result = subprocess.run([SECRET_TOOL, "lookup", "application", "shu-art", "profile", secret_id],
                                stdin=subprocess.DEVNULL, capture_output=True, timeout=20)
        if result.returncode != 0:
            raise ValueError("Unlock the system wallet or configure the art credential again")
        key = single_line_key(result.stdout.decode("ascii").strip())
        env["DASHSCOPE_API_KEY"] = key
        env["QWEN_IMAGE_ENDPOINT"] = endpoint
        return env
    if sys.platform != "darwin":
        raise ValueError("Configure both Qwen environment variables on this host")
    config = json.loads(SETTINGS.read_text(encoding="utf-8"))
    endpoint = validate_endpoint(config["endpoint"])
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
        print("[ERROR] Qwen configuration or system wallet is unavailable; no provider request was made")
        return 1
    script = "doctor.py" if sys.argv[1] == "doctor" else "qwen_image.py"
    return subprocess.run([sys.executable, str(SCRIPTS / script), *sys.argv[2:]],
                          cwd=ROOT, env=env).returncode


if __name__ == "__main__":
    raise SystemExit(main())
