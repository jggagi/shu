"""Regression coverage for the isolated Stream Teahouse package builder.

Godot is mocked throughout; this test verifies staging and export destinations,
not actual engine import or export behavior.
"""
import importlib.util
import json
import re
import runpy
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
BUILDER_PATH = ROOT / "tools/build_stream_teahouse.py"


def load_builder_module():
    spec = importlib.util.spec_from_file_location("stream_teahouse_builder", BUILDER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def relative_files(directory):
    return {
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.is_file()
    }


class StreamTeahouseBuildTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load_builder_module()

    def test_manifest_covers_current_stream_scene_dependencies(self):
        files = set(self.builder.FILES)
        self.assertEqual(len(self.builder.FILES), 25)
        self.assertEqual(len(files), len(self.builder.FILES))
        for relative in self.builder.FILES:
            self.assertTrue((ROOT / relative).is_file(), relative)

        references = set()
        for relative in self.builder.FILES:
            source = ROOT / relative
            if source.suffix not in {".gd", ".tscn", ".gdshader", ".json"}:
                continue
            content = source.read_text(encoding="utf-8", errors="ignore")
            references.update(re.findall(r"res://([A-Za-z0-9_./-]+)", content))
            directories = dict(re.findall(
                r'const\s+(\w+)\s*:?=\s*"(res://[^" ]*/)"', content
            ))
            for name, directory in directories.items():
                references.update(
                    directory.removeprefix("res://") + child
                    for child in re.findall(rf"\b{name}\s*\+\s*\"([^\"]+)\"", content)
                )

        for relative in references:
            if (ROOT / relative).is_file():
                self.assertIn(relative, files, f"unbundled res:// dependency: {relative}")

    def _prepare_fixture(self, fixture_root):
        tools_dir = fixture_root / "tools"
        tools_dir.mkdir(parents=True)
        fixture_builder = tools_dir / BUILDER_PATH.name
        fixture_builder.write_bytes(BUILDER_PATH.read_bytes())
        (fixture_root / ".engine-version").write_text("4.7.2\n", encoding="utf-8")
        (fixture_root / "project.godot").write_text(
            'config/name="蜀山行记 · 听雨廊环境 v1"\n'
            'config/version="0.1.10-tingyu-environment-local"\n'
            'run/main_scene="res://scenes/main.tscn"\n',
            encoding="utf-8",
        )
        (fixture_root / "export_presets.cfg").write_text(
            'name="Shu - Cultivation Demo"\n'
            'name="Shu - Return Sword Demo"\n',
            encoding="utf-8",
        )
        for relative in self.builder.FILES:
            target = fixture_root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(f"fixture dependency: {relative}\n".encode())
        return fixture_builder

    def _run_mocked_build(self, fixture_builder):
        export_observations = []

        def simulated_godot_run(command, check=False):
            self.assertTrue(check)
            if "--export-release" in command:
                stage = Path(command[command.index("--path") + 1])
                preset = command[command.index("--export-release") + 1]
                export_observations.append((preset, command[-1], relative_files(stage)))
            return mock.Mock(returncode=0)

        with (
            mock.patch.object(sys, "argv", [str(fixture_builder), "--godot", "mock-godot"]),
            mock.patch("subprocess.check_output", return_value="4.7.2.stable.mock"),
            mock.patch("subprocess.run", side_effect=simulated_godot_run),
        ):
            runpy.run_path(str(fixture_builder), run_name="__main__")
        return export_observations

    def test_each_build_gets_a_fresh_preserved_stage_and_stable_exports(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture_root = Path(temporary_directory) / "fixture"
            fixture_root.mkdir()
            fixture_builder = self._prepare_fixture(fixture_root)
            output = fixture_root / ".local/build/stream-teahouse"

            old_stage = output / "project"
            old_stage.mkdir(parents=True)
            old_stage_sentinel = old_stage / "keep-existing-stage.txt"
            old_stage_sentinel.write_text("preserve", encoding="utf-8")

            expected_stage_files = set(self.builder.FILES) | {
                "project.godot",
                "export_presets.cfg",
            }
            first_exports = self._run_mocked_build(fixture_builder)
            first_receipt = json.loads((output / "build-info.json").read_text(encoding="utf-8"))
            first_stage = output / first_receipt["stage_relative_path"]

            stale_canary = first_stage / "assets/data/stale-canary.json"
            stale_canary.write_text("must stay in old stage", encoding="utf-8")
            removed_dependency = first_stage / "assets/shaders/stream_water_old.gdshader"
            removed_dependency.write_text("old allowlist entry", encoding="utf-8")

            second_exports = self._run_mocked_build(fixture_builder)
            second_receipt = json.loads((output / "build-info.json").read_text(encoding="utf-8"))
            second_stage = output / second_receipt["stage_relative_path"]

            self.assertNotEqual(first_stage, second_stage)
            self.assertTrue(first_stage.is_dir())
            self.assertTrue(stale_canary.is_file())
            self.assertTrue(removed_dependency.is_file())
            self.assertEqual(old_stage_sentinel.read_text(encoding="utf-8"), "preserve")
            self.assertFalse((second_stage / "assets/data/stale-canary.json").exists())
            self.assertFalse((second_stage / "assets/shaders/stream_water_old.gdshader").exists())
            self.assertEqual(relative_files(second_stage), expected_stage_files)
            self.assertEqual(second_receipt["stage_relative_path"], second_stage.name)

            web_path = (output.resolve() / "web/index.html").as_posix()
            windows_path = (output.resolve() / "windows/StreamTeahouse.exe").as_posix()
            for exports in (first_exports, second_exports):
                self.assertEqual([preset for preset, _, _ in exports], ["Web", "Windows Desktop"])
                self.assertEqual([path for _, path, _ in exports], [web_path, windows_path])
                self.assertTrue(all(stage_files == expected_stage_files for _, _, stage_files in exports))

            for folder in ("web", "windows"):
                licenses = output / folder / "licenses"
                self.assertTrue((licenses / "OFL-Serif.txt").is_file())
                self.assertTrue((licenses / "GODOT-LICENSE.txt").is_file())
                self.assertTrue((licenses / "GODOT-NOTICES.txt").is_file())


if __name__ == "__main__":
    unittest.main()
