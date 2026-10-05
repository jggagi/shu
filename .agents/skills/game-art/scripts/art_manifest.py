"""Repo paths, non-secret configuration and atomic JSONL provenance (stdlib only)."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PureWindowsPath
import subprocess
import tempfile
from urllib.parse import urlsplit, urlunsplit
import uuid

DEFAULT_MODEL = "qwen-image-3.0"
PRO_MODEL = "qwen-image-3.0-pro"


def repo_root():
    """Anchor Git discovery to this script, never to the caller's cwd."""
    anchor = Path(__file__).resolve()
    fallback = anchor.parents[4]
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=fallback,
            capture_output=True, text=True, timeout=5, check=False,
        )
        if result.returncode == 0:
            root = Path(result.stdout.strip()).resolve()
            if anchor.is_relative_to(root):
                return root
    except (OSError, subprocess.TimeoutExpired):
        pass
    return fallback


def repo_path(root, value):
    """Accept native absolute paths and portable relative paths; reject escapes."""
    root = Path(root).resolve()
    raw = str(value)
    # A Windows absolute path must not become a relative filename on POSIX.
    if os.name != "nt" and PureWindowsPath(raw).drive:
        raise ValueError("Windows absolute paths require a Windows runtime; use repo-relative paths")
    path = Path(raw.replace("\\", "/"))
    if not path.is_absolute():
        path = root / path
    path = path.resolve()
    if not path.is_relative_to(root) or path == root:
        raise ValueError("Path must name a file or directory inside the repository")
    return path


def relative_path(root, value):
    return repo_path(root, value).relative_to(Path(root).resolve()).as_posix()


def https_url(value):
    try:
        parts = urlsplit(value)
        port = parts.port
    except ValueError:
        raise ValueError("Expected a valid HTTPS URL") from None
    if (parts.scheme != "https" or not parts.hostname or parts.username
            or parts.password or parts.fragment or port == 0):
        raise ValueError("Expected an HTTPS URL without embedded credentials or fragment")
    return value


def reference_path(root, value):
    if str(value).startswith("https://"):
        parts = urlsplit(https_url(str(value)))
        # Signed URL queries are transport credentials, never provenance.
        return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))
    if "://" in str(value) or str(value).startswith("data:"):
        raise ValueError("References must be repo files or explicit HTTPS URLs")
    path = repo_path(root, value)
    if not path.is_file():
        raise ValueError("Reference file does not exist in the repository")
    return relative_path(root, path)


def load_config(root):
    path = repo_path(root, "art/config.json")
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise ValueError("Cannot read valid art/config.json") from None
    keys = {"qwen_model", "qwen_pro_model", "work_dir", "approved_dir", "manifest", "reference_dir", "prompt_dir"}
    if not isinstance(config, dict) or set(config) != keys:
        raise ValueError("art/config.json has missing or unsupported fields")
    if config["qwen_model"] != DEFAULT_MODEL or config["qwen_pro_model"] != PRO_MODEL:
        raise ValueError("Config models must be qwen-image-3.0 and qwen-image-3.0-pro")
    for key in keys - {"qwen_model", "qwen_pro_model"}:
        if not isinstance(config[key], str) or Path(config[key]).is_absolute() or PureWindowsPath(config[key]).drive:
            raise ValueError("Config paths must be repo-relative")
        repo_path(root, config[key])
    if not config["manifest"].endswith(".jsonl"):
        raise ValueError("Manifest must be a .jsonl file")
    return config


def atomic_write(path, data):
    """Use a sibling temporary file; close before replace (also works on Windows)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".game-art-", suffix=".tmp", delete=False) as stream:
            temp_path = Path(stream.name)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        temp_path.replace(path)
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


def make_record(root, *, provider, model, purpose, prompt_file, references, output,
                asset_id=None, status="candidate", request_parameters=None, negative_prompt_file=None):
    if provider not in {"qwen", "codex-imagegen"}:
        raise ValueError("Provider must be qwen or codex-imagegen")
    if provider == "qwen" and model not in {DEFAULT_MODEL, PRO_MODEL}:
        raise ValueError("Unsupported Qwen model")
    if provider == "codex-imagegen" and model is not None:
        raise ValueError("Leave Codex's hidden model unset")
    if status not in {"candidate", "approved"} or not purpose.strip():
        raise ValueError("A purpose and candidate/approved status are required")
    output_path = repo_path(root, output)
    prompt_path = repo_path(root, prompt_file)
    if not output_path.is_file() or output_path.stat().st_size == 0 or not prompt_path.is_file():
        raise ValueError("Output must be a nonempty file and prompt_file must exist")
    if len(references) > 3:
        raise ValueError("At most 3 reference images are supported")
    record = {
        "asset_id": asset_id or uuid.uuid4().hex,
        "provider": provider, "model": model, "purpose": purpose,
        "prompt_file": relative_path(root, prompt_path),
        "references": [reference_path(root, item) for item in references],
        "output": relative_path(root, output_path),
        "created_at": datetime.now(timezone.utc).isoformat(), "status": status,
        "sha256": hashlib.sha256(output_path.read_bytes()).hexdigest(),
    }
    if request_parameters is not None:
        allowed = {"size", "seed", "prompt_extend", "enable_thinking", "watermark", "n"}
        if set(request_parameters) - allowed:
            raise ValueError("Unsupported provenance parameters")
        record["request_parameters"] = request_parameters
    if negative_prompt_file is not None:
        path = repo_path(root, negative_prompt_file)
        if not path.is_file():
            raise ValueError("Negative prompt file must exist")
        record["negative_prompt_file"] = relative_path(root, path)
    return record


def append_record(root, record):
    """Serial calls only: preserve existing records and replace the complete JSONL."""
    config = load_config(root)
    path = repo_path(root, config["manifest"])
    existing = path.read_bytes() if path.exists() else b""
    if existing and not existing.endswith(b"\n"):
        existing += b"\n"
    for line in existing.splitlines():
        if line.strip():
            try:
                parsed = json.loads(line)
            except ValueError:
                raise ValueError("Existing manifest is malformed; repair it before appending") from None
            if not isinstance(parsed, dict):
                raise ValueError("Existing manifest must contain JSON objects")
    line = json.dumps(record, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
    atomic_write(path, existing + line)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Record a selected project image's provenance; no network")
    parser.add_argument("--provider", required=True, choices=["qwen", "codex-imagegen"])
    parser.add_argument("--model", choices=[DEFAULT_MODEL, PRO_MODEL])
    parser.add_argument("--purpose", required=True)
    parser.add_argument("--prompt-file", required=True)
    parser.add_argument("--reference", action="append", default=[])
    parser.add_argument("--output", required=True)
    parser.add_argument("--asset-id")
    parser.add_argument("--status", choices=["candidate", "approved"], default="candidate")
    args = parser.parse_args(argv)
    try:
        root = repo_root()
        model = args.model or (DEFAULT_MODEL if args.provider == "qwen" else None)
        record = make_record(root, provider=args.provider, model=model, purpose=args.purpose,
                             prompt_file=args.prompt_file, references=args.reference,
                             output=args.output, asset_id=args.asset_id, status=args.status)
        append_record(root, record)
        print("[OK] provenance recorded")
        return 0
    except (ValueError, OSError):
        # No raw exception data: OS/provider errors can contain personal paths or secrets.
        print("[ERROR] Cannot record provenance; check arguments, files, config and manifest")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
