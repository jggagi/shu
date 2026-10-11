"""Blender math check against approved capture, independent of model/rendering."""
import copy,json,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools/sword_jiang'))
import make_study as m
class MotionCheck(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  c=m.load('cmu_motion',ROOT/'tools/sword_mocap/cmu_motion.py');sk=c.parse_asf(ROOT/'assets/data/sword_mocap/source/02.asf')
  zero={'root':(0,0,0,0,0,0)};zero.update({b.name:tuple(0 for _ in b.dofs) for b in sk.bones if b.dofs})
  cls.rest=c.solve_frame(sk,c.MotionFrame(1,zero))
  for b in cls.rest.values():b['head']=list(m.vec(b['head'])*.70);b['tail']=list(m.vec(b['tail'])*.70)
  cls.specs=c.sample_file(ROOT/'assets/data/sword_mocap/source/02.asf',ROOT/'assets/data/sword_mocap/source/02_09.amc',stride=2)['bones']
  cls.raw=json.loads((ROOT/'assets/data/sword_mocap/pose_reference.json').read_text())['samples']
  cls.actual=copy.deepcopy(cls.raw);cls.report=m.clean(cls.actual,cls.rest,cls.specs)
 def test_human_clock_and_source_indices(self):
  self.assertEqual(len(self.actual),517)
  self.assertEqual([s['source_frame'] for s in self.actual],[s['source_frame'] for s in self.raw])
 def test_right_hand_and_spine_keep_capture(self):
  for raw,actual in zip(self.raw,self.actual):
   for name in ['root','lowerback','upperback','thorax','head','rhumerus','rradius','rwrist','rhand']:
    self.assertEqual(raw['bones'][name]['rotation'],actual['bones'][name]['rotation'])
    self.assertLess((m.vec(actual['bones'][name]['head'])-m.vec(raw['bones'][name]['head'])*.70).length,1e-6)
 def test_unit_rotations_and_rigid_lengths(self):
  for sample in self.actual:
   for name,b in sample['bones'].items():
    self.assertAlmostEqual(sum(q*q for q in b['rotation']),1.,places=5)
    length=(m.vec(self.rest[name]['tail'])-m.vec(self.rest[name]['head'])).length
    self.assertLess(abs((m.vec(b['tail'])-m.vec(b['head'])).length-length),1e-5)
 def test_contact_anchors_and_reachable_left_targets(self):
  self.assertGreater(self.report['fully_planted_samples'],0)
  self.assertLess(self.report['max_contact_anchor_error_m'],1e-5)
  self.assertLess(self.report['max_left_target_error_m'],1e-5)
  self.assertGreater(self.report['close_hand_calibrated_samples'],0)
  self.assertLess(self.report['close_hand_calibrated_samples'],len(self.actual))
 def test_irreachable_ik_preserves_limb_lengths(self):
  a=m.Vector((0,0,0));pole=m.Vector((0,1,0));k,end=m.two_bone(a,pole,m.Vector((4,0,0)),.2,.3)
  self.assertAlmostEqual((k-a).length,.2,places=5);self.assertAlmostEqual((end-k).length,.3,places=5)
  self.assertLess((end-a).length,.5)
if __name__=='__main__':
 result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(MotionCheck))
 if not result.wasSuccessful():raise RuntimeError('Jiang motion checks failed')
