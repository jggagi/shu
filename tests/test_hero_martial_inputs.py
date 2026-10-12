"""Input validation and fail-closed publication tests for the hero motion packager."""
import hashlib
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock
import zlib

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.hero_martial.prepare_input import (
    PackageError,
    _atomic_rename_no_replace,
    inspect_sources,
    prepare_package,
    validate_video,
)


def png_ihdr(width: int, height: int) -> bytes:
    chunk = b"IHDR" + struct.pack(">II", width, height) + bytes((8, 6, 0, 0, 0))
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + chunk + struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)


class HeroMartialInputTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.reference = self.root / "jiang-reference.png"
        self.reference_bytes = png_ihdr(640, 960)
        self.reference.write_bytes(self.reference_bytes)
        self.frames = self.root / "frames"
        self.frames.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def write_frames(self, count: int = 30, size: tuple[int, int] = (384, 384)):
        for index in range(count):
            (self.frames / f"frame-{index:04d}.png").write_bytes(png_ihdr(*size))

    def test_source_hashes_geometry_and_count_validate_without_ffmpeg(self):
        self.write_frames()
        sources = inspect_sources(self.reference, self.frames, 15)
        self.assertEqual(sources["reference"]["width"], 640)
        self.assertEqual(sources["reference"]["height"], 960)
        self.assertEqual(sources["reference"]["sha256"], hashlib.sha256(self.reference_bytes).hexdigest())
        motion = sources["source_motion"]
        self.assertEqual((motion["width"], motion["height"]), (384, 384))
        self.assertEqual(motion["frame_count"], 30)
        self.assertEqual(motion["duration_seconds"], 2.0)
        self.assertEqual(motion["frames"][0]["index"], 0)
        self.assertEqual(motion["frames"][-1]["index"], 29)

    def test_gap_in_numbered_sequence_is_rejected_before_parent_creation(self):
        self.write_frames()
        (self.frames / "frame-0001.png").unlink()
        output = self.root / "not-created" / "shot"
        with self.assertRaisesRegex(PackageError, "consecutive"):
            prepare_package("sword-thrust", self.reference, self.frames, 15, output)
        self.assertFalse(output.parent.exists())

    def test_invalid_id_and_out_of_range_duration_are_rejected(self):
        self.write_frames(count=29)
        with self.assertRaisesRegex(PackageError, "2 to 8 seconds"):
            inspect_sources(self.reference, self.frames, 15)
        with self.assertRaisesRegex(PackageError, "Invalid --shot-id"):
            prepare_package("Sword-Thrust", self.reference, self.frames, 15, self.root / "out")

    def test_changed_frame_geometry_is_rejected(self):
        self.write_frames()
        (self.frames / "frame-0017.png").write_bytes(png_ihdr(386, 384))
        with self.assertRaisesRegex(PackageError, "geometry changed"):
            inspect_sources(self.reference, self.frames, 15)

    def test_ffprobe_contract_and_output_hash_validation_need_no_ffmpeg(self):
        video = self.root / "motion-guide.mp4"
        video_bytes = b"synthetic encoded video receipt fixture"
        video.write_bytes(video_bytes)
        info = {
            "streams": [{
                "index": 0,
                "codec_type": "video",
                "codec_name": "h264",
                "width": 384,
                "height": 384,
                "pix_fmt": "yuv420p",
                "avg_frame_rate": "15/1",
                "r_frame_rate": "15/1",
                "nb_read_frames": "30",
            }],
            "format": {"duration": "2.000000"},
        }
        record = validate_video(info, video, 15, 30, 384, 384)
        self.assertEqual(record["sha256"], hashlib.sha256(video_bytes).hexdigest())
        self.assertEqual(record["bytes"], len(video_bytes))
        self.assertEqual(record["fps"], 15)
        self.assertNotIn("decode_verified", record)

        info["streams"][0]["pix_fmt"] = "yuv444p"
        with self.assertRaisesRegex(PackageError, "pixel_format=yuv444p"):
            validate_video(info, video, 15, 30, 384, 384)

    def test_successful_package_records_hashes_without_exposing_input_paths(self):
        self.write_frames()
        output = self.root / "new-parent" / "shot-package"
        fake_video_bytes = b"synthetic video bytes from mocked encoder"
        probe = {
            "streams": [{
                "index": 0,
                "codec_type": "video",
                "codec_name": "h264",
                "width": 384,
                "height": 384,
                "pix_fmt": "yuv420p",
                "avg_frame_rate": "15/1",
                "r_frame_rate": "15/1",
                "nb_read_frames": "30",
            }],
            "format": {"duration": "2.000000", "size": str(len(fake_video_bytes))},
        }

        def fake_encode(_ffmpeg, _frames_dir, video_path, _fps, _frame_count):
            video_path.write_bytes(fake_video_bytes)

        with (
            mock.patch("tools.hero_martial.prepare_input.resolve_tool", side_effect=lambda _p, n: self.root / n),
            mock.patch("tools.hero_martial.prepare_input.tool_version", side_effect=lambda path: f"{path.name} test-version"),
            mock.patch("tools.hero_martial.prepare_input.encode_video", side_effect=fake_encode),
            mock.patch("tools.hero_martial.prepare_input.probe_video", return_value=probe),
            mock.patch("tools.hero_martial.prepare_input.run_checked", return_value=mock.Mock(returncode=0)),
        ):
            result = prepare_package(
                "staff-sweep", self.reference, self.frames, 15, output,
                self.root / "ffmpeg", self.root / "ffprobe",
            )

        reference_copy = output / "reference.png"
        video_copy = output / "motion-guide.mp4"
        metadata_path = output / "metadata.json"
        self.assertEqual(reference_copy.read_bytes(), self.reference_bytes)
        self.assertEqual(video_copy.read_bytes(), fake_video_bytes)
        self.assertEqual(result["reference"]["sha256"], hashlib.sha256(self.reference_bytes).hexdigest())
        self.assertEqual(result["videos"][0]["sha256"], hashlib.sha256(fake_video_bytes).hexdigest())
        self.assertTrue(result["videos"][0]["decode_verified"])
        self.assertEqual(result["toolchain"]["ffmpeg"], "ffmpeg test-version")
        self.assertTrue(metadata_path.is_file())
        self.assertNotIn(str(self.root), metadata_path.read_text(encoding="utf-8"))

    def test_existing_output_is_preserved_without_tool_or_input_access(self):
        output = self.root / "existing"
        output.mkdir()
        sentinel = output / "keep.txt"
        sentinel.write_text("preserve me", encoding="utf-8")
        missing_reference = self.root / "missing.png"
        with self.assertRaisesRegex(PackageError, "Refusing existing output"):
            prepare_package("sword-thrust", missing_reference, self.frames, 15, output)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve me")
        self.assertEqual(sorted(path.name for path in output.iterdir()), ["keep.txt"])

    def test_decode_failure_does_not_publish_or_leave_staging_files(self):
        self.write_frames()
        output = self.root / "new-parent" / "shot-package"
        fake_video_bytes = b"synthetic video bytes from mocked encoder"
        probe = {
            "streams": [{
                "index": 0,
                "codec_type": "video",
                "codec_name": "h264",
                "width": 384,
                "height": 384,
                "pix_fmt": "yuv420p",
                "avg_frame_rate": "15/1",
                "r_frame_rate": "15/1",
                "nb_read_frames": "30",
            }],
            "format": {"duration": "2.000000"},
        }

        def fake_encode(_ffmpeg, _frames_dir, video_path, _fps, _frame_count):
            video_path.write_bytes(fake_video_bytes)

        with (
            mock.patch("tools.hero_martial.prepare_input.resolve_tool", side_effect=lambda _p, n: self.root / n),
            mock.patch("tools.hero_martial.prepare_input.tool_version", return_value="test-version"),
            mock.patch("tools.hero_martial.prepare_input.encode_video", side_effect=fake_encode),
            mock.patch("tools.hero_martial.prepare_input.probe_video", return_value=probe),
            mock.patch(
                "tools.hero_martial.prepare_input.run_checked",
                side_effect=PackageError("full decode failed"),
            ),
        ):
            with self.assertRaisesRegex(PackageError, "full decode failed"):
                prepare_package(
                    "staff-sweep", self.reference, self.frames, 15, output,
                    self.root / "ffmpeg", self.root / "ffprobe",
                )

        self.assertFalse(output.exists())
        self.assertEqual(list(output.parent.iterdir()), [])

    def test_atomic_publish_refuses_an_existing_output_directory(self):
        source = self.root / "temporary-package"
        source.mkdir()
        (source / "ours.txt").write_text("ours", encoding="utf-8")
        destination = self.root / "claimed-output"
        destination.mkdir()
        sentinel = destination / "owner.txt"
        sentinel.write_text("other invocation", encoding="utf-8")

        with self.assertRaisesRegex(PackageError, "Refusing existing output"):
            _atomic_rename_no_replace(source, destination)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "other invocation")
        self.assertEqual((source / "ours.txt").read_text(encoding="utf-8"), "ours")

    def test_preexisting_empty_output_directory_is_rejected(self):
        output = self.root / "already-created"
        output.mkdir()
        with self.assertRaisesRegex(PackageError, "Refusing existing output"):
            prepare_package("sword-thrust", self.reference, self.frames, 15, output)
        self.assertEqual(list(output.iterdir()), [])

    def test_atomic_publish_moves_a_complete_sibling_directory(self):
        source = self.root / "temporary-package"
        source.mkdir()
        (source / "metadata.json").write_text("complete", encoding="utf-8")
        destination = self.root / "published-package"

        _atomic_rename_no_replace(source, destination)
        self.assertFalse(source.exists())
        self.assertEqual(
            (destination / "metadata.json").read_text(encoding="utf-8"), "complete"
        )


if __name__ == "__main__":
    unittest.main()
