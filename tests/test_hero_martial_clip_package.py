"""Stdlib-only preflight and media-contract tests for the clip packager."""
import hashlib
import sys
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.hero_martial.package_clip import (
    PackageError,
    _valid_sha256,
    sha256_file,
    validate_destinations,
    validate_frame_timestamps,
    validate_job_record,
    validate_source_probe,
)


SHOT_ID = "jiang-sword-horizontal-return-v1"
SOURCE_SHA256 = "e6a5e438f4e3c61ceac1a357d2d06b6514c129047f1863c904fa9fa4890a8f68"


def valid_probe(frame_count=50, width=960, height=960, fps="25/1", duration="2.000000"):
    return {
        "streams": [{
            "codec_name": "h264",
            "width": width,
            "height": height,
            "avg_frame_rate": fps,
            "r_frame_rate": fps,
            "nb_read_frames": str(frame_count),
        }],
        "format": {"duration": duration},
    }


def timestamps(frame_count=50, fps=25):
    return {"frames": [
        {"best_effort_timestamp_time": f"{index / fps:.6f}"}
        for index in range(frame_count)
    ]}


class HeroMartialClipPackageTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def test_sha256_helper_and_expected_model_hash_validation(self):
        source = self.root / "source.mp4"
        source.write_bytes(b"synthetic source fixture")
        expected = hashlib.sha256(source.read_bytes()).hexdigest()
        self.assertEqual(sha256_file(source), expected)
        self.assertEqual(_valid_sha256(expected.upper(), "model"), expected)
        with self.assertRaisesRegex(PackageError, "64-character"):
            _valid_sha256("not-a-hash", "model")

    def test_successful_job_receipt_is_bound_to_shot_and_source_hash(self):
        record_path = self.root / "job.json"
        record_path.write_text("job receipt fixture", encoding="utf-8")
        record = {
            "status": "SUCCEEDED",
            "shot_id": SHOT_ID,
            "task_id": "task-123",
            "source_sha256": SOURCE_SHA256,
            "mode": "wan2.2-animate-move",
            "quality": "wan-pro",
        }
        validated = validate_job_record(
            record, shot_id=SHOT_ID, source_sha256=SOURCE_SHA256,
            record_path=record_path,
        )
        self.assertEqual(validated["task_id"], "task-123")
        self.assertEqual(validated["provider"], "unknown")
        self.assertEqual(validated["mode"], "wan2.2-animate-move")
        self.assertEqual(validated["quality"], "wan-pro")
        self.assertEqual(validated["record_sha256"], sha256_file(record_path))

    def test_job_receipt_rejects_unfinished_wrong_shot_or_mismatched_source(self):
        record_path = self.root / "job.json"
        record_path.write_text("fixture", encoding="utf-8")
        base = {
            "status": "SUCCEEDED",
            "shot_id": SHOT_ID,
            "task_id": "task-123",
            "source_sha256": SOURCE_SHA256,
        }
        for changes, message in (
            ({"status": "RUNNING"}, "SUCCEEDED"),
            ({"shot_id": "jiang-fist-straight-punch-v1"}, "shot_id"),
            ({"source_sha256": "0" * 64}, "does not match"),
            ({"task_id": ""}, "task_id"),
        ):
            with self.subTest(changes=changes), self.assertRaisesRegex(PackageError, message):
                validate_job_record(
                    {**base, **changes}, shot_id=SHOT_ID,
                    source_sha256=SOURCE_SHA256, record_path=record_path,
                )

    def test_cfr_source_contract_measures_geometry_fps_count_and_duration(self):
        media = validate_source_probe(valid_probe(), timestamps())
        self.assertEqual((media["width"], media["height"]), (960, 960))
        self.assertEqual((media["cell_width"], media["cell_height"]), (480, 480))
        self.assertEqual(media["fps"], 25.0)
        self.assertEqual(media["fps_rational"], "25/1")
        self.assertEqual(media["frame_count"], 50)
        self.assertEqual(media["duration_seconds"], 2.0)
        self.assertEqual(len(media["timestamps"]), 50)

    def test_frame_timestamps_must_match_cfr_within_point_one_millisecond(self):
        records = timestamps(frame_count=8)["frames"]
        validate_frame_timestamps(records, frame_count=8, fps=Fraction(25, 1))
        records[4]["best_effort_timestamp_time"] = "0.120200"
        with self.assertRaisesRegex(PackageError, "not CFR within 0.1 ms"):
            validate_frame_timestamps(records, frame_count=8, fps=Fraction(25, 1))
        with self.assertRaisesRegex(PackageError, "Expected 8 decoded frame timestamps"):
            validate_frame_timestamps(records[:-1], frame_count=8, fps=Fraction(25, 1))

    def test_source_media_temporal_and_geometry_guards_fail_closed(self):
        bad_probes = [
            (valid_probe(width=959), timestamps(), "even values"),
            (valid_probe(width=2300), timestamps(), "256 to 2048"),
            (valid_probe(fps="25/1"), timestamps(), "Average and nominal"),
            (valid_probe(duration="2.010000"), timestamps(), "within 1 ms"),
            (valid_probe(frame_count=1001, duration="40.040000"), timestamps(1001), "frame count"),
            ({**valid_probe(), "streams": [{**valid_probe()["streams"][0], "codec_name": "hevc"}]}, timestamps(), "H.264"),
        ]
        bad_probes[2][0]["streams"][0]["r_frame_rate"] = "30/1"
        for probe, frame_data, message in bad_probes:
            with self.subTest(message=message), self.assertRaisesRegex(PackageError, message):
                validate_source_probe(probe, frame_data)

    def test_namespace_is_exact_external_and_rejects_existing_or_original_paths(self):
        repo = self.root / "repo"
        repo.mkdir()
        source = self.root / "source.mp4"
        source.write_bytes(b"source")
        assets = repo / "assets/art/hero_martial_v1" / SHOT_ID
        output = self.root / "external-work" / SHOT_ID
        resolved_output, resolved_assets = validate_destinations(
            repo_root=repo, shot_id=SHOT_ID, output=output, assets=assets,
            input_paths=[source],
        )
        self.assertEqual(resolved_output, output.resolve())
        self.assertEqual(resolved_assets, assets.resolve())
        self.assertFalse(output.exists())
        self.assertFalse(assets.exists())

        invalid_cases = [
            (output, repo / "assets/art/sword_image_driven_v1", "per-shot path"),
            (repo / "inside-work", assets, "outside and disjoint"),
            (output, repo / "assets/art/hero_martial_v1/jiang-staff-forward-thrust-v1", "per-shot path"),
        ]
        for bad_output, bad_assets, message in invalid_cases:
            with self.subTest(path=bad_assets), self.assertRaisesRegex(PackageError, message):
                validate_destinations(
                    repo_root=repo, shot_id=SHOT_ID, output=bad_output,
                    assets=bad_assets, input_paths=[source],
                )

        output.mkdir(parents=True)
        with self.assertRaisesRegex(PackageError, "Refusing existing external output"):
            validate_destinations(
                repo_root=repo, shot_id=SHOT_ID, output=output, assets=assets,
                input_paths=[source],
            )

    def test_existing_empty_shot_asset_directory_is_rejected(self):
        repo = self.root / "repo"
        repo.mkdir()
        source = self.root / "source.mp4"
        source.write_bytes(b"source")
        assets = repo / "assets/art/hero_martial_v1" / SHOT_ID
        assets.mkdir(parents=True)
        output = self.root / "external-work" / SHOT_ID
        with self.assertRaisesRegex(PackageError, "Refusing existing shot assets"):
            validate_destinations(
                repo_root=repo, shot_id=SHOT_ID, output=output, assets=assets,
                input_paths=[source],
            )
        self.assertFalse(output.exists())
        self.assertEqual(list(assets.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
