"""Qwen Image 3.0 OpenAI-compatible synchronous client; Python 3.12 stdlib."""

import argparse
import base64
import json
import mimetypes
import os
from pathlib import Path
import re
import struct
import urllib.error
import urllib.request
import uuid
import zlib

from art_manifest import (DEFAULT_MODEL, PRO_MODEL, append_record, atomic_write,
                          https_url, load_config, make_record, reference_path,
                          relative_path, repo_path, repo_root)

MAX_REFERENCE_BYTES = 10 * 1024 * 1024
MAX_IMAGE_BYTES = 64 * 1024 * 1024
MAX_JSON_BYTES = 2 * 1024 * 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class ArtError(Exception):
    """Only application-authored, non-secret diagnostics belong here."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward Authorization or private prompts to a redirect target.
        return None


def image_mime(data):
    if data.startswith(PNG_SIGNATURE):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if data.startswith(b"BM"):
        return "image/bmp"
    if data.startswith((b"II*\x00", b"MM\x00*")):
        return "image/tiff"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    raise ValueError("Reference must contain a supported raster image")


def encode_reference(root, value):
    if str(value).startswith("https://"):
        return https_url(str(value))
    reference_path(root, value)
    path = repo_path(root, value)
    if not 0 < path.stat().st_size <= MAX_REFERENCE_BYTES:
        raise ValueError("Local reference must be nonempty and at most 10 MiB")
    data = path.read_bytes()
    if len(data) > MAX_REFERENCE_BYTES:
        raise ValueError("Local reference exceeds 10 MiB")
    mime = image_mime(data)
    guessed = mimetypes.guess_type(path.name)[0]
    if guessed and guessed not in {mime, "image/x-ms-bmp"}:
        raise ValueError("Reference extension does not match image content")
    return f"data:{mime};base64," + base64.b64encode(data).decode("ascii")


def valid_size(value):
    if value == "auto":
        return value
    match = re.fullmatch(r"([1-9][0-9]*)x([1-9][0-9]*)", value)
    if not match:
        raise ValueError("Size must be auto or WIDTHxHEIGHT (letter x)")
    width, height = map(int, match.groups())
    if not 512 * 512 <= width * height <= 2048 * 2048 or not 1 / 8 <= width / height <= 8:
        raise ValueError("Size area must be 512^2..2048^2 pixels, aspect ratio 1:8..8:1")
    return value


def build_request(root, *, prompt, model=DEFAULT_MODEL, size=None, references=(),
                  negative_prompt=None, seed=None, prompt_extend=True, watermark=False):
    if model not in {DEFAULT_MODEL, PRO_MODEL}:
        raise ValueError("Unsupported Qwen model")
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("Prompt must not be empty")
    if len(references) > 3:
        raise ValueError("At most 3 reference images are supported")
    if seed is not None and not 0 <= seed <= 2147483647:
        raise ValueError("Seed must be between 0 and 2147483647")
    payload = {"model": model, "prompt": prompt, "n": 1,
               "prompt_extend": prompt_extend, "watermark": watermark}
    if not prompt_extend:
        # Provider defaults thinking to true, but requires prompt rewriting for it.
        payload["enable_thinking"] = False
    if size is not None:
        payload["size"] = valid_size(size)
    if references:
        payload["image"] = [encode_reference(root, item) for item in references]
    if negative_prompt is not None:
        payload["negative_prompt"] = negative_prompt
    if seed is not None:
        payload["seed"] = seed
    return payload


def credentials():
    key = os.environ.get("DASHSCOPE_API_KEY", "").strip()
    endpoint = os.environ.get("QWEN_IMAGE_ENDPOINT", "").strip()
    missing = [name for name, value in (("DASHSCOPE_API_KEY", key), ("QWEN_IMAGE_ENDPOINT", endpoint)) if not value]
    if missing:
        raise ArtError("Missing required environment variables: " + ", ".join(missing))
    if "\r" in key or "\n" in key:
        raise ArtError("DASHSCOPE_API_KEY must be a single-line token")
    try:
        https_url(endpoint)
        from urllib.parse import urlsplit
        parts = urlsplit(endpoint)
        if not parts.path.endswith("/images/generations") or parts.query:
            raise ValueError()
    except ValueError:
        raise ArtError("QWEN_IMAGE_ENDPOINT must be the complete HTTPS /images/generations endpoint") from None
    return key, endpoint


def read_bounded(response, limit):
    data = response.read(limit + 1)
    if len(data) > limit:
        raise ArtError("Provider response exceeds the supported size limit")
    return data


def validate_png(data):
    """Reject empty, HTML, corrupt and truncated downloads before replacing output."""
    if not data.startswith(PNG_SIGNATURE):
        raise ArtError("Generated download is not PNG")
    offset, saw_header, saw_data = 8, False, False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            break
        kind = data[offset + 4:offset + 8]
        content = data[offset + 8:offset + 8 + length]
        crc = struct.unpack(">I", data[end - 4:end])[0]
        if zlib.crc32(kind + content) & 0xffffffff != crc:
            raise ArtError("Generated PNG checksum failed")
        if not saw_header:
            if kind != b"IHDR" or length != 13 or 0 in struct.unpack(">II", content[:8]):
                raise ArtError("Generated PNG header is invalid")
            saw_header = True
        if kind == b"IDAT":
            saw_data = True
        if kind == b"IEND":
            if saw_data and length == 0 and end == len(data):
                return
            break
        offset = end
    raise ArtError("Generated PNG is incomplete")


def generate(payload, key, endpoint, timeout=600):
    opener = urllib.request.build_opener(NoRedirect())
    request = urllib.request.Request(endpoint, data=json.dumps(payload).encode("utf-8"),
                                     headers={"Content-Type": "application/json", "Authorization": "Bearer " + key},
                                     method="POST")
    try:
        with opener.open(request, timeout=timeout) as response:
            raw = read_bounded(response, MAX_JSON_BYTES)
        try:
            result = json.loads(raw)
        except ValueError:
            raise ArtError("Provider returned malformed JSON") from None
        if not isinstance(result, dict) or result.get("error"):
            raise ArtError("Provider reported a failed generation; check model, region and account configuration")
        items = result.get("data")
        if not isinstance(items, list) or len(items) != 1 or not isinstance(items[0], dict):
            raise ArtError("Provider response must contain one image URL")
        try:
            url = https_url(items[0]["url"])
        except (KeyError, ValueError, TypeError):
            raise ArtError("Provider response has no valid HTTPS image URL") from None
        # Result download receives no API key, no prompt, and no reference data.
        with opener.open(urllib.request.Request(url, method="GET"), timeout=timeout) as response:
            data = read_bounded(response, MAX_IMAGE_BYTES)
        validate_png(data)
        return data
    except urllib.error.HTTPError as exc:
        raise ArtError(f"Provider HTTP {exc.code}; check endpoint, credentials, model and region. No automatic retry") from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ArtError("Provider connection/download failed; check connectivity. No automatic retry") from None


def sanitized(payload):
    result = dict(payload)
    result["prompt"] = f"<prompt text: {len(payload['prompt'])} characters>"
    if "negative_prompt" in result:
        result["negative_prompt"] = "<negative prompt text>"
    if "image" in result:
        result["image"] = ["<local image data URL>" if item.startswith("data:") else "<explicit HTTPS reference URL>" for item in result["image"]]
    return {"method": "POST", "endpoint": "<QWEN_IMAGE_ENDPOINT>",
            "headers": {"Content-Type": "application/json", "Authorization": "Bearer <redacted>"},
            "body": result}


def parser():
    cli = argparse.ArgumentParser(description="Generate one PNG with Qwen Image 3.0; record provenance")
    prompt = cli.add_mutually_exclusive_group(required=True)
    prompt.add_argument("--prompt")
    prompt.add_argument("--prompt-file", help="UTF-8 prompt inside this repository")
    cli.add_argument("--out", required=True, help="Repo-relative PNG path (native absolute repo paths also accepted)")
    cli.add_argument("--model", choices=[DEFAULT_MODEL, PRO_MODEL], default=DEFAULT_MODEL)
    cli.add_argument("--size", help="auto or WIDTHxHEIGHT; omitted uses provider auto-sizing")
    cli.add_argument("--reference", action="append", default=[], help="Repo file or explicit HTTPS URL; max 3, order preserved")
    cli.add_argument("--negative-prompt")
    cli.add_argument("--seed", type=int)
    cli.add_argument("--no-prompt-extend", action="store_true")
    cli.add_argument("--watermark", action="store_true")
    cli.add_argument("--dry-run", action="store_true", help="Validate and print redacted request; no network or writes")
    cli.add_argument("--purpose", default="game-art production")
    cli.add_argument("--overwrite", action="store_true", help="Replace existing image only after a complete successful download")
    return cli


def main(argv=None):
    args = parser().parse_args(argv)
    saved = False
    try:
        root = repo_root()
        config = load_config(root)
        output = repo_path(root, args.out)
        if output.suffix.lower() != ".png":
            raise ValueError("Output must use the .png extension")
        if output.exists() and not args.overwrite:
            raise ValueError("Output already exists; choose a new path or use --overwrite")
        if not args.purpose.strip():
            raise ValueError("Purpose must not be empty")
        prompt_path = repo_path(root, args.prompt_file) if args.prompt_file else None
        prompt = prompt_path.read_text(encoding="utf-8") if prompt_path else args.prompt
        payload = build_request(root, prompt=prompt, model=args.model, size=args.size,
                                references=args.reference, negative_prompt=args.negative_prompt,
                                seed=args.seed, prompt_extend=not args.no_prompt_extend, watermark=args.watermark)
        if args.dry_run:
            print(json.dumps(sanitized(payload), indent=2))
            return 0
        key, endpoint = credentials()
        # Check local destinations before making the billable request.
        for directory in {output.parent, repo_path(root, config["manifest"]).parent, repo_path(root, config["prompt_dir"])}:
            directory.mkdir(parents=True, exist_ok=True)
            import tempfile
            with tempfile.TemporaryFile(dir=directory):
                pass
        manifest = repo_path(root, config["manifest"])
        if manifest.exists():
            for line in manifest.read_text(encoding="utf-8").splitlines():
                if line.strip() and not isinstance(json.loads(line), dict):
                    raise ValueError("Existing manifest must contain JSON objects")
        data = generate(payload, key, endpoint)
        asset_id = uuid.uuid4().hex
        negative_path = None
        if prompt_path is None:
            prompt_path = repo_path(root, config["prompt_dir"]) / (asset_id + ".txt")
            atomic_write(prompt_path, prompt.encode("utf-8"))
        if args.negative_prompt is not None:
            negative_path = repo_path(root, config["prompt_dir"]) / (asset_id + "-negative.txt")
            atomic_write(negative_path, args.negative_prompt.encode("utf-8"))
        atomic_write(output, data)
        saved = True
        record = make_record(root, provider="qwen", model=args.model, purpose=args.purpose,
                             prompt_file=prompt_path, references=args.reference, output=output, asset_id=asset_id,
                             negative_prompt_file=negative_path,
                             request_parameters={name: payload[name] for name in ("size", "seed", "prompt_extend", "enable_thinking", "watermark", "n") if name in payload})
        append_record(root, record)
        print("[OK] image saved; provenance recorded")
        return 0
    except ArtError as exc:
        print("[ERROR] " + str(exc))
        return 1
    except ValueError as exc:
        # JSON/Unicode errors contain data; never echo these exception strings.
        if type(exc) is ValueError:
            print("[ERROR] " + str(exc))
        else:
            print("[ERROR] Invalid JSON or UTF-8 input")
    except OSError:
        print("[ERROR] Local file operation failed; check repo files and permissions")
    if saved:
        print("[WARN] Image was saved, but provenance failed; record it with art_manifest.py before use")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
