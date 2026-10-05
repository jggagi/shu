"""Offline behavioral tests; all HTTP is mocked, no paid generation."""

import ast
import base64
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.error
import urllib.request
import zlib

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import art_manifest as manifest
import doctor
import qwen_image as qwen


def png():
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (qwen.PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00\x10\x20\x30\xff")) + chunk(b"IEND", b""))


class GameArtTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.config = {"qwen_model": manifest.DEFAULT_MODEL, "qwen_pro_model": manifest.PRO_MODEL,
                       "work_dir": "art/work", "approved_dir": "assets/art",
                       "reference_dir": "docs/concepts", "prompt_dir": "art/prompts",
                       "manifest": "art/manifest.jsonl"}
        (self.root / "art").mkdir()
        (self.root / "art/config.json").write_text(json.dumps(self.config), encoding="utf-8")
        self.reference = self.root / "docs/concepts/ref space.png"
        self.reference.parent.mkdir(parents=True)
        self.reference.write_bytes(png())
        self.prompt = self.root / "art/prompts/scene.txt"
        self.prompt.parent.mkdir()
        self.prompt.write_text("Chinese watercolor courtyard", encoding="utf-8")
        self.env = {"DASHSCOPE_API_KEY": "PRIVATE-API-KEY-DO-NOT-PRINT",
                    "QWEN_IMAGE_ENDPOINT": "https://selected-provider.example/compatible-mode/v1/images/generations"}

    def run_cli(self, args, env=None):
        stream = io.StringIO()
        with patch.object(qwen, "repo_root", return_value=self.root), patch.dict(os.environ, env or {}, clear=True), redirect_stdout(stream):
            code = qwen.main(args)
        return code, stream.getvalue()

    def test_t2i_top_level_request_and_defaults(self):
        body = qwen.build_request(self.root, prompt="courtyard")
        self.assertEqual(body, {"model": "qwen-image-3.0", "prompt": "courtyard", "n": 1,
                                "prompt_extend": True, "watermark": False})
        self.assertNotIn("image", body)
        self.assertNotIn("parameters", body)

    def test_default_model_and_pro_explicit_only(self):
        self.assertEqual(qwen.parser().parse_args(["--prompt", "x", "--out", "art/work/x.png"]).model, manifest.DEFAULT_MODEL)
        with self.assertRaises(ValueError):
            qwen.build_request(self.root, prompt="x", model="auto-pro")
        self.assertEqual(qwen.build_request(self.root, prompt="x", model=manifest.PRO_MODEL)["model"], manifest.PRO_MODEL)

    def test_reference_is_valid_data_url(self):
        body = qwen.build_request(self.root, prompt="edit", references=[self.reference])
        prefix, data = body["image"][0].split(",", 1)
        self.assertEqual(prefix, "data:image/png;base64")
        self.assertEqual(base64.b64decode(data, validate=True), png())

    def test_three_references_preserve_order(self):
        refs = [self.reference, "https://reference.example/second.png?signature=private", self.reference]
        body = qwen.build_request(self.root, prompt="edit", references=refs)
        self.assertEqual(len(body["image"]), 3)
        self.assertEqual(body["image"][1], refs[1])
        with self.assertRaisesRegex(ValueError, "At most 3"):
            qwen.build_request(self.root, prompt="edit", references=refs + [self.reference])

    def test_reference_validation(self):
        for value in ("http://reference.example/a.png", "file:///private.png", "data:image/png;base64,xxx", "missing.png"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                qwen.encode_reference(self.root, value)
        self.reference.write_bytes(b"not-an-image")
        with self.assertRaisesRegex(ValueError, "supported raster"):
            qwen.encode_reference(self.root, self.reference)
        self.reference.write_bytes(b"x" * (qwen.MAX_REFERENCE_BYTES + 1))
        with self.assertRaisesRegex(ValueError, "10 MiB"):
            qwen.encode_reference(self.root, self.reference)

    def test_size_seed_and_optional_fields(self):
        body = qwen.build_request(self.root, prompt="x", size="1024x1024", seed=3,
                                  negative_prompt="text", prompt_extend=False, watermark=True)
        self.assertEqual(body["size"], "1024x1024")
        self.assertEqual(body["seed"], 3)
        self.assertEqual(body["negative_prompt"], "text")
        self.assertFalse(body["prompt_extend"])
        self.assertFalse(body["enable_thinking"])
        self.assertTrue(body["watermark"])
        for size in ("1024*1024", "0x1024", "10x10", "5000x5000", "32x16384"):
            with self.subTest(size=size), self.assertRaises(ValueError):
                qwen.build_request(self.root, prompt="x", size=size)
        for seed in (-1, 2147483648):
            with self.assertRaises(ValueError):
                qwen.build_request(self.root, prompt="x", seed=seed)
        self.assertEqual(qwen.valid_size("auto"), "auto")

    def test_dry_run_has_no_network_writes_or_secrets(self):
        files_before = sorted(path.relative_to(self.root).as_posix() for path in self.root.rglob("*"))
        with patch.object(urllib.request, "build_opener", side_effect=AssertionError("network")), patch.object(socket, "create_connection", side_effect=AssertionError("network")), patch.object(qwen, "credentials", side_effect=AssertionError("credential access")):
            code, output = self.run_cli(["--prompt", self.env["DASHSCOPE_API_KEY"], "--negative-prompt", "private brief",
                                         "--reference", str(self.reference), "--reference", "https://ref.example/a.png?token=PRIVATE",
                                         "--out", "art/work/test.png", "--dry-run"], self.env)
        self.assertEqual(code, 0)
        for secret in (self.env["DASHSCOPE_API_KEY"], self.env["QWEN_IMAGE_ENDPOINT"], "private brief", "token=PRIVATE", str(self.root)):
            self.assertNotIn(secret, output)
        self.assertNotIn(base64.b64encode(png()).decode(), output)
        self.assertEqual(json.loads(output)["body"]["model"], manifest.DEFAULT_MODEL)
        self.assertEqual(files_before, sorted(path.relative_to(self.root).as_posix() for path in self.root.rglob("*")))

    def test_dry_run_validates_arguments(self):
        code, output = self.run_cli(["--prompt", " ", "--out", "art/work/test.png", "--dry-run"])
        self.assertEqual(code, 1)
        self.assertIn("Prompt must not be empty", output)
        code, output = self.run_cli(["--prompt", "x", "--out", "../escape.png", "--dry-run"])
        self.assertEqual(code, 1)

    def test_missing_environment_fails_before_network(self):
        with patch.object(qwen, "generate", side_effect=AssertionError("network")):
            for env, missing in (({}, ["DASHSCOPE_API_KEY", "QWEN_IMAGE_ENDPOINT"]),
                                 ({"DASHSCOPE_API_KEY": "secret"}, ["QWEN_IMAGE_ENDPOINT"]),
                                 ({"QWEN_IMAGE_ENDPOINT": self.env["QWEN_IMAGE_ENDPOINT"]}, ["DASHSCOPE_API_KEY"])):
                code, output = self.run_cli(["--prompt", "x", "--out", "art/work/test.png"], env)
                self.assertEqual(code, 1)
                for name in missing:
                    self.assertIn(name, output)

    def test_endpoint_validation_and_redaction(self):
        for endpoint in ("http://provider.example/images/generations", "https://provider.example/v1",
                         "https://secret@provider.example/images/generations", "https://provider.example/images/generations?key=secret"):
            env = dict(self.env, QWEN_IMAGE_ENDPOINT=endpoint)
            code, output = self.run_cli(["--prompt", "x", "--out", "art/work/x.png"], env)
            self.assertEqual(code, 1)
            self.assertNotIn(endpoint, output)
            self.assertNotIn(self.env["DASHSCOPE_API_KEY"], output)

    def test_script_anchor_and_git_fallback_ignore_cwd(self):
        expected = SCRIPTS.parents[3]
        with patch.object(manifest.subprocess, "run", side_effect=FileNotFoundError):
            self.assertEqual(manifest.repo_root(), expected)
        result = subprocess.CompletedProcess([], 0, str(expected) + "\n", "")
        with patch.object(manifest.subprocess, "run", return_value=result) as run:
            self.assertEqual(manifest.repo_root(), expected)
            self.assertEqual(run.call_args.kwargs["cwd"], expected)
            self.assertFalse(run.call_args.kwargs.get("shell", False))

    def test_real_subprocess_invocation_from_other_cwd(self):
        environment = dict(os.environ)
        environment.pop("DASHSCOPE_API_KEY", None)
        environment.pop("QWEN_IMAGE_ENDPOINT", None)
        other_cwd = self.root / "other-cwd"
        other_cwd.mkdir()
        for layout in (".agents", ".codex"):
            with self.subTest(layout=layout):
                installed_scripts = self.root / layout / "skills/game-art/scripts"
                installed_scripts.mkdir(parents=True)
                for name in ("art_manifest.py", "doctor.py", "qwen_image.py"):
                    shutil.copy2(SCRIPTS / name, installed_scripts / name)
                result = subprocess.run([sys.executable, str(installed_scripts / "qwen_image.py"), "--prompt", "scene",
                                         "--out", "art/work/cwd-test.png", "--dry-run"],
                                        cwd=other_cwd, env=environment, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(json.loads(result.stdout)["body"]["model"], manifest.DEFAULT_MODEL)
                self.assertFalse((self.root / "art/work/cwd-test.png").exists())

    def test_windows_relative_paths_and_native_absolute_paths(self):
        self.assertEqual(manifest.relative_path(self.root, r"art\work\scene.png"), "art/work/scene.png")
        self.assertEqual(manifest.relative_path(self.root, self.reference), "docs/concepts/ref space.png")
        with self.assertRaises(ValueError):
            manifest.repo_path(self.root, r"..\outside.png")
        if os.name == "nt":
            self.assertEqual(manifest.repo_path(self.root, str(self.reference)), self.reference)
        else:
            with self.assertRaises(ValueError):
                manifest.repo_path(self.root, r"C:\private\ref.png")

    def test_outside_repo_paths_rejected(self):
        with self.assertRaises(ValueError):
            manifest.repo_path(self.root, self.root.parent / "outside.png")

    def record(self, provider="qwen"):
        output = self.root / "art/work/output.png"
        output.parent.mkdir(exist_ok=True)
        output.write_bytes(png())
        return manifest.make_record(self.root, provider=provider, model=manifest.DEFAULT_MODEL if provider == "qwen" else None,
                                    purpose="scene reference", prompt_file=self.prompt, references=[self.reference], output=output)

    def test_manifest_relative_paths_sha256_and_append(self):
        record = self.record()
        self.assertEqual(record["output"], "art/work/output.png")
        self.assertEqual(record["prompt_file"], "art/prompts/scene.txt")
        self.assertEqual(record["references"], ["docs/concepts/ref space.png"])
        self.assertEqual(len(record["sha256"]), 64)
        manifest.append_record(self.root, record)
        manifest.append_record(self.root, record)
        lines = (self.root / "art/manifest.jsonl").read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(lines), 2)
        self.assertEqual(json.loads(lines[0]), record)
        self.assertNotIn(str(self.root), "\n".join(lines))

    def test_codex_model_unknown_and_signed_url_not_persisted(self):
        record = self.record("codex-imagegen")
        self.assertIsNone(record["model"])
        self.assertEqual(manifest.reference_path(self.root, "https://ref.example/a.png?token=secret"), "https://ref.example/a.png")
        with self.assertRaises(ValueError):
            manifest.make_record(self.root, provider="codex-imagegen", model="guessed", purpose="x", prompt_file=self.prompt, references=[], output=record["output"])

    def test_corrupt_manifest_preserved(self):
        path = self.root / "art/manifest.jsonl"
        path.write_bytes(b"not json\n")
        with self.assertRaises(ValueError):
            manifest.append_record(self.root, self.record())
        self.assertEqual(path.read_bytes(), b"not json\n")

    def test_successful_cli_records_provenance_and_prompt(self):
        with patch.object(qwen, "generate", return_value=png()) as generate:
            code, output = self.run_cli(["--prompt", "courtyard", "--out", r"art\work\scene.png", "--reference", str(self.reference), "--purpose", "background"], self.env)
        self.assertEqual(code, 0, output)
        self.assertEqual((self.root / "art/work/scene.png").read_bytes(), png())
        record = json.loads((self.root / "art/manifest.jsonl").read_text(encoding="utf-8"))
        self.assertEqual(record["output"], "art/work/scene.png")
        self.assertEqual(record["purpose"], "background")
        self.assertEqual(record["status"], "candidate")
        self.assertEqual(record["model"], manifest.DEFAULT_MODEL)
        self.assertEqual((self.root / record["prompt_file"]).read_text(encoding="utf-8"), "courtyard")
        self.assertNotIn(self.env["DASHSCOPE_API_KEY"], output)
        self.assertNotIn(self.env["DASHSCOPE_API_KEY"], json.dumps(record))
        self.assertEqual(generate.call_count, 1)

    def test_explicit_pro_prompt_file_and_overwrite(self):
        output_path = self.root / "art/work/scene.png"
        output_path.parent.mkdir()
        output_path.write_bytes(b"existing")
        with patch.object(qwen, "generate", return_value=png()):
            code, output = self.run_cli(["--prompt-file", str(self.prompt), "--out", str(output_path), "--model", manifest.PRO_MODEL, "--overwrite"], self.env)
        self.assertEqual(code, 0, output)
        record = json.loads((self.root / "art/manifest.jsonl").read_text(encoding="utf-8"))
        self.assertEqual(record["model"], manifest.PRO_MODEL)
        self.assertEqual(record["prompt_file"], "art/prompts/scene.txt")
        self.assertEqual(output_path.read_bytes(), png())

    def test_negative_prompt_and_disabled_thinking_provenance(self):
        with patch.object(qwen, "generate", return_value=png()) as generate:
            code, output = self.run_cli(["--prompt", "scene", "--negative-prompt", "text and borders", "--no-prompt-extend", "--out", "art/work/scene.png"], self.env)
        self.assertEqual(code, 0, output)
        self.assertFalse(generate.call_args.args[0]["enable_thinking"])
        record = json.loads((self.root / "art/manifest.jsonl").read_text(encoding="utf-8"))
        self.assertFalse(record["request_parameters"]["enable_thinking"])
        self.assertEqual((self.root / record["negative_prompt_file"]).read_text(encoding="utf-8"), "text and borders")

    def test_existing_output_requires_explicit_overwrite(self):
        output_path = self.root / "art/work/scene.png"
        output_path.parent.mkdir()
        output_path.write_bytes(b"existing")
        with patch.object(qwen, "generate", side_effect=AssertionError("network")):
            code, _ = self.run_cli(["--prompt", "x", "--out", str(output_path)], self.env)
        self.assertEqual(code, 1)
        self.assertEqual(output_path.read_bytes(), b"existing")

    def test_failed_generation_preserves_final_and_no_provenance(self):
        path = self.root / "art/work/scene.png"
        path.parent.mkdir()
        path.write_bytes(b"original")
        with patch.object(qwen, "generate", side_effect=qwen.ArtError("Provider connection/download failed")):
            code, _ = self.run_cli(["--prompt", "x", "--out", str(path), "--overwrite"], self.env)
        self.assertEqual(code, 1)
        self.assertEqual(path.read_bytes(), b"original")
        self.assertFalse((self.root / "art/manifest.jsonl").exists())

    def test_png_validation_rejects_empty_partial_html_corrupt(self):
        qwen.validate_png(png())
        for data in (b"", png()[:-3], b"<html>not an image</html>", png()[:30] + b"CORRUPT" + png()[37:]):
            with self.subTest(data=data[:12]), self.assertRaises(qwen.ArtError):
                qwen.validate_png(data)

    def test_atomic_replace_failure_preserves_old_file_and_cleans_temp(self):
        path = self.root / "art/existing.png"
        path.write_bytes(b"original")
        with patch.object(Path, "replace", side_effect=OSError("locked")), self.assertRaises(OSError):
            manifest.atomic_write(path, b"new complete data")
        self.assertEqual(path.read_bytes(), b"original")
        self.assertEqual(list(path.parent.glob(".game-art-*.tmp")), [])

    def test_atomic_replace_success(self):
        path = self.root / "art/new-dir/scene.png"
        manifest.atomic_write(path, png())
        self.assertEqual(path.read_bytes(), png())
        self.assertEqual(list(path.parent.glob(".game-art-*.tmp")), [])

    def mock_opener(self, api_body, image=None):
        def response(data):
            stream = io.BytesIO(data)
            return stream
        opener = Mock()
        opener.open.side_effect = [response(api_body), response(png() if image is None else image)]
        return opener

    def test_mock_http_request_and_download_auth_isolation(self):
        opener = self.mock_opener(json.dumps({"data": [{"url": "https://generated.example/scene.png?signature=private"}]}).encode())
        payload = qwen.build_request(self.root, prompt="private prompt")
        with patch.object(urllib.request, "build_opener", return_value=opener):
            data = qwen.generate(payload, self.env["DASHSCOPE_API_KEY"], self.env["QWEN_IMAGE_ENDPOINT"])
        self.assertEqual(data, png())
        request = opener.open.call_args_list[0].args[0]
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(request.get_header("Authorization"), "Bearer " + self.env["DASHSCOPE_API_KEY"])
        self.assertEqual(json.loads(request.data), payload)
        download = opener.open.call_args_list[1].args[0]
        self.assertEqual(download.get_method(), "GET")
        self.assertIsNone(download.get_header("Authorization"))
        self.assertIsNone(download.data)

    def test_malformed_failed_or_unsafe_http_response(self):
        for body in (b"not-json", b"[]", b"{}", b'{"error":{"message":"PRIVATE-API-KEY-DO-NOT-PRINT"}}',
                     b'{"data":[]}', b'{"data":[{"url":"http://unsafe.example/a.png"}]}'):
            opener = self.mock_opener(body)
            with patch.object(urllib.request, "build_opener", return_value=opener), self.assertRaises(qwen.ArtError) as error:
                qwen.generate({}, self.env["DASHSCOPE_API_KEY"], self.env["QWEN_IMAGE_ENDPOINT"])
            self.assertNotIn(self.env["DASHSCOPE_API_KEY"], str(error.exception))

    def test_http_failure_does_not_print_raw_provider_error_or_key(self):
        secret = self.env["DASHSCOPE_API_KEY"]
        opener = Mock()
        opener.open.side_effect = urllib.error.HTTPError(self.env["QWEN_IMAGE_ENDPOINT"], 401, secret, {}, io.BytesIO(secret.encode()))
        with patch.object(urllib.request, "build_opener", return_value=opener):
            code, output = self.run_cli(["--prompt", "private prompt", "--out", "art/work/x.png"], self.env)
        self.assertEqual(code, 1)
        self.assertIn("HTTP 401", output)
        self.assertNotIn(secret, output)
        self.assertNotIn("private prompt", output)
        self.assertEqual(opener.open.call_count, 1)

    def test_redirects_disabled(self):
        handler = qwen.NoRedirect()
        request = urllib.request.Request(self.env["QWEN_IMAGE_ENDPOINT"], data=b"private", headers={"Authorization": "secret"})
        self.assertIsNone(handler.redirect_request(request, None, 307, "move", {}, "https://other.example"))

    def test_truncated_download_never_creates_final_file(self):
        opener = self.mock_opener(b'{"data":[{"url":"https://generated.example/x.png"}]}', png()[:-1])
        with patch.object(urllib.request, "build_opener", return_value=opener):
            code, _ = self.run_cli(["--prompt", "x", "--out", "art/work/x.png"], self.env)
        self.assertEqual(code, 1)
        self.assertFalse((self.root / "art/work/x.png").exists())
        self.assertFalse((self.root / "art/manifest.jsonl").exists())

    def test_response_limit(self):
        with self.assertRaises(qwen.ArtError):
            qwen.read_bounded(io.BytesIO(b"too large"), 2)

    def test_doctor_no_network_supports_both_install_locations(self):
        skill_paths = (".agents/skills/game-art/SKILL.md", ".codex/skills/game-art/SKILL.md")
        for install_path in skill_paths:
            with self.subTest(install_path=install_path):
                for path in skill_paths:
                    (self.root / path).unlink(missing_ok=True)
                skill = self.root / install_path
                skill.parent.mkdir(parents=True, exist_ok=True)
                skill.write_text("skill", encoding="utf-8")
                for env, readiness in (({}, "NOT CONFIGURED"), (self.env, "READY (configuration only")):
                    stream = io.StringIO()
                    with patch.object(doctor, "repo_root", return_value=self.root), patch.dict(os.environ, env, clear=True), patch.object(urllib.request, "build_opener", side_effect=AssertionError("network")), patch.object(socket, "create_connection", side_effect=AssertionError("network")), redirect_stdout(stream):
                        code = doctor.main(["--no-network"])
                    self.assertEqual(code, 0)
                    self.assertIn(readiness, stream.getvalue())
                    for value in self.env.values():
                        self.assertNotIn(value, stream.getvalue())

    def test_doctor_missing_skill_fails_without_network(self):
        stream = io.StringIO()
        with patch.object(doctor, "repo_root", return_value=self.root), patch.dict(os.environ, {}, clear=True), patch.object(urllib.request, "build_opener", side_effect=AssertionError("network")), patch.object(socket, "create_connection", side_effect=AssertionError("network")), redirect_stdout(stream):
            code = doctor.main(["--no-network"])
        self.assertEqual(code, 1)
        self.assertIn("[FAIL] repository root", stream.getvalue())
        self.assertIn("[WARN] DASHSCOPE_API_KEY missing", stream.getvalue())
        self.assertIn("[WARN] QWEN_IMAGE_ENDPOINT missing", stream.getvalue())

    def test_config_rejects_secret_fields_and_absolute_paths(self):
        for change in ({"endpoint": "secret"}, {"work_dir": str(self.root / "art/work")}, {"qwen_model": manifest.PRO_MODEL}):
            (self.root / "art/config.json").write_text(json.dumps(dict(self.config, **change)), encoding="utf-8")
            with self.assertRaises(ValueError):
                manifest.load_config(self.root)

    def test_core_imports_and_subprocess_are_portable(self):
        allowed = set(sys.stdlib_module_names) | {"art_manifest", "qwen_image"}
        for script in SCRIPTS.glob("*.py"):
            tree = ast.parse(script.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    modules = [entry.name.split(".")[0] for entry in node.names]
                elif isinstance(node, ast.ImportFrom):
                    modules = [node.module.split(".")[0]]
                else:
                    modules = []
                self.assertTrue(set(modules) <= allowed, (script.name, modules))
                self.assertFalse(set(modules) & {"fcntl", "msvcrt", "winreg", "pwd", "grp"})
                if isinstance(node, ast.Call):
                    self.assertFalse(any(keyword.arg == "shell" and isinstance(keyword.value, ast.Constant) and keyword.value.value is True for keyword in node.keywords))


if __name__ == "__main__":
    unittest.main()
