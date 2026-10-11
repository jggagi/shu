import math
import tempfile
import unittest
from pathlib import Path

from tools.sword_mocap.cmu_motion import (
    MotionFrame,
    parse_amc,
    parse_asf,
    sample_file,
    solve_frame,
)

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/data/sword_mocap/source"


def synthetic_asf() -> str:
    return """:version 1.10
:units
 length 0.45
:root
 order TX TY TZ RX RY RZ
 axis XYZ
 position 0 0 0
 orientation 0 0 0
:bonedata
 begin
  id 1
  name axisbone
  direction 1 0 0
  length 1
  axis 0 0 90 XYZ
  dof rx
 end
:hierarchy
 begin
  root axisbone
 end
"""


class CMUMotionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.asf = Path(self.temp.name) / "synthetic.asf"
        self.asf.write_text(synthetic_asf(), encoding="utf-8")
        self.scale = 0.0254 / 0.45

    def test_90_degree_root_z_rotation_and_translation_have_analytical_result(self) -> None:
        skeleton = parse_asf(self.asf)
        frame = MotionFrame(7, {"root": (1, 2, 3, 0, 0, 90), "axisbone": (0,)})
        result = solve_frame(skeleton, frame)
        root = result["root"]
        self.assertVectorAlmostEqual(root["head"], (self.scale, -3 * self.scale, 2 * self.scale))
        self.assertVectorAlmostEqual(root["tail"], root["head"])
        # ASF +Z 90-degree rotation becomes a Blender -Y 90-degree rotation.
        half = math.sqrt(0.5)
        self.assertVectorAlmostEqual(root["rotation"], (half, 0, -half, 0))
        # +X rotated around ASF +Z becomes +Y, which maps to Blender +Z.
        self.assertVectorAlmostEqual(
            result["axisbone"]["tail"],
            (self.scale, -3 * self.scale, 3 * self.scale),
        )

    def test_zero_dof_cancels_nonzero_bone_axis(self) -> None:
        skeleton = parse_asf(self.asf)
        result = solve_frame(skeleton, MotionFrame(1, {"root": (0, 0, 0, 0, 0, 0), "axisbone": (0,)}))
        self.assertVectorAlmostEqual(result["axisbone"]["tail"], (self.scale, 0, 0))
        self.assertVectorAlmostEqual(result["axisbone"]["rotation"], (1, 0, 0, 0))

    def test_90_degree_bone_axis_rotation_is_conjugated_analytically(self) -> None:
        skeleton = parse_asf(self.asf)
        result = solve_frame(skeleton, MotionFrame(3, {"root": (0, 0, 0, 0, 0, 0), "axisbone": (90,)}))
        # C=Rz(90), R=Rx(90), hence C*R*C^-1=Ry(90).
        # +X maps to -ASF-Z, which is +Blender-Y; Ry maps to Blender Rz.
        self.assertVectorAlmostEqual(result["axisbone"]["tail"], (0, self.scale, 0))
        half = math.sqrt(0.5)
        self.assertVectorAlmostEqual(result["axisbone"]["rotation"], (half, 0, 0, half))

    def test_real_skeleton_is_complete_and_connected(self) -> None:
        skeleton = parse_asf(SOURCE / "02.asf")
        self.assertEqual(len(skeleton.bones), 30)
        self.assertEqual(len({b.identifier for b in skeleton.bones}), 30)
        self.assertEqual(len({b.name for b in skeleton.bones}), 30)
        self.assertEqual(skeleton.length_unit_metres, self.scale)
        self.assertTrue(all(b.parent == "root" or b.parent in {x.name for x in skeleton.bones} for b in skeleton.bones))
        self.assertEqual(sum(b.parent == "root" for b in skeleton.bones), 3)

    def test_real_zero_pose_keeps_asf_direction_and_basis(self) -> None:
        skeleton = parse_asf(SOURCE / "02.asf")
        channels = {"root": (0, 0, 0, 0, 0, 0)}
        channels.update({b.name: tuple(0.0 for _ in b.dofs) for b in skeleton.bones if b.dofs})
        result = solve_frame(skeleton, MotionFrame(1, channels))
        bone = next(b for b in skeleton.bones if b.name == "lhumerus")
        # Blender basis is (x, -z, y); compare the segment vector from its connected head.
        actual_offset = tuple(result["lhumerus"]["tail"][i] - result["lhumerus"]["head"][i] for i in range(3))
        self.assertVectorAlmostEqual(
            actual_offset,
            (bone.direction[0] * bone.length * self.scale,
             -bone.direction[2] * bone.length * self.scale,
             bone.direction[1] * bone.length * self.scale),
        )

    def test_real_clip_subsets_preserve_frames_lengths_and_normalized_quaternions(self) -> None:
        skeleton_path = SOURCE / "02.asf"
        skeleton = parse_asf(skeleton_path)
        for clip_name in ("02_07.amc", "02_08.amc", "02_09.amc"):
            with self.subTest(clip=clip_name):
                frames = parse_amc(SOURCE / clip_name)
                self.assertGreaterEqual(len(frames), 3)
                chosen = frames[10:13]
                self.assertEqual([f.source_frame for f in chosen],
                                 list(range(chosen[0].source_frame, chosen[0].source_frame + 3)))
                for frame in chosen:
                    pose = solve_frame(skeleton, frame)
                    self.assertEqual(len(pose), 31)
                    for record in pose.values():
                        self.assertTrue(all(math.isfinite(v) for v in (*record["head"], *record["tail"], *record["rotation"])))
                        self.assertAlmostEqual(math.sqrt(sum(x*x for x in record["rotation"])), 1.0, places=12)
                    for bone in skeleton.bones:
                        head, tail = pose[bone.name]["head"], pose[bone.name]["tail"]
                        self.assertVectorAlmostEqual(head, pose[bone.parent]["tail"])
                        actual = math.sqrt(sum((tail[i] - head[i]) ** 2 for i in range(3)))
                        expected = bone.length * skeleton.length_unit_metres * math.sqrt(sum(v*v for v in bone.direction))
                        self.assertAlmostEqual(actual, expected, places=10)

    def test_sample_schema_has_root_and_source_frame_index(self) -> None:
        result = sample_file(SOURCE / "02.asf", SOURCE / "02_07.amc", stride=240)
        self.assertEqual(result["schema_version"], 1)
        self.assertEqual(result["fps"], 120)
        self.assertEqual(result["length_unit_metres"], self.scale)
        self.assertEqual(result["source_frame"], [s["source_frame"] for s in result["samples"]])
        self.assertEqual(len(result["bones"]), 31)
        self.assertEqual(len(result["samples"][0]["bones"]), 31)
        self.assertEqual(result["bones"][0]["name"], "root")

    def assertVectorAlmostEqual(self, actual, expected, places=10) -> None:
        self.assertEqual(len(actual), len(expected))
        for a, e in zip(actual, expected):
            self.assertAlmostEqual(a, e, places=places)


if __name__ == "__main__":
    unittest.main()
