#!/usr/bin/env python3
"""Author a neutral idle and a complete sword action from the approved warm model.

Only bone animation changes. Rendering is deliberately bounded to short ranges
so each chunk can use a fresh Blender process on the local workstation.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Quaternion


def helper(name):
    path=Path(__file__).with_name(name+'.py')
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1048576),b''):digest.update(block)
    return digest.hexdigest()


def idle_animation(arm):
    scene=bpy.context.scene;scene.frame_set(1)
    base={pb.name:(pb.location.copy(),pb.rotation_quaternion.copy(),pb.scale.copy()) for pb in arm.pose.bones}
    arm.animation_data_clear()
    scene.frame_start=1;scene.frame_end=60;scene.render.fps=30
    for frame in range(1,61):
        phase=2*math.pi*(frame-1)/59
        breath=1-math.cos(phase);sway=math.sin(phase)
        for pb in arm.pose.bones:
            location,rotation,scale=base[pb.name]
            pb.location=location;pb.rotation_mode='QUATERNION';pb.rotation_quaternion=rotation;pb.scale=scale
            degrees=0.
            if pb.name=='chest':degrees=.30*breath
            elif pb.name=='head':degrees=-.15*breath
            elif pb.name=='ponytail':degrees=.45*sway
            elif pb.name.startswith('skirt.'):degrees=.10*sway*(1 if pb.name.endswith('R') else -1)
            if degrees:pb.rotation_quaternion=rotation@Quaternion((1,0,0),math.radians(degrees))
            for channel in ['location','rotation_quaternion','scale']:pb.keyframe_insert(channel,frame=frame)
    scene.frame_set(1)
    return {'frame_count':60,'fps':30,'duration_seconds':2,'endpoints_equal':True,
            'maximum_torso_pitch_degrees':.60,'maximum_ponytail_sway_degrees':.45,
            'feet_and_root_stationary':True}


def render_frames(out,frames,prefix='pose'):
    scene=bpy.context.scene
    for frame in frames:
        scene.frame_set(frame);scene.render.filepath=str(out/f'{prefix}-{frame:04d}.png')
        bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--config',type=Path)
    parser.add_argument('--mode',choices=['build','render'],default='build')
    parser.add_argument('--start-frame',type=int)
    parser.add_argument('--end-frame',type=int)
    parser.add_argument('--motion-profile',choices=['balanced','power-v1','jianshu-v1','routine-v1'],default='balanced')
    parser.add_argument('--routine-id',help='Authored short routine from sword_routine_profiles.py')
    parser.add_argument('--skip-key-renders',action='store_true',help='Save animation/report without opening the renderer')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not args.input.is_absolute() or not args.out.is_absolute() or args.out.exists():
        raise ValueError('Absolute existing input and new output required')
    if not args.input.is_file():raise ValueError('Source does not exist')
    if args.mode=='build' and (not args.config or not args.config.is_file()):raise ValueError('Source landmarks required')
    args.out.mkdir(parents=True)
    bpy.ops.wm.open_mainfile(filepath=str(args.input))
    scene=bpy.context.scene;scene.render.threads_mode='FIXED';scene.render.threads=4
    if args.mode=='render':
        start=args.start_frame if args.start_frame is not None else scene.frame_start
        end=args.end_frame if args.end_frame is not None else scene.frame_end
        if not scene.frame_start<=start<=end<=scene.frame_end:raise ValueError('Range outside saved animation')
        render_frames(args.out,range(start,end+1),'frame');return
    config=json.loads(args.config.read_text());warm=helper('warm_sword_phrase');base=helper('build_fullbody_turn')
    report={'source_blend':str(args.input),'source_sha256':sha(args.input),'config_sha256':sha(args.config),
            'new_cloud_calls':0,'material_changes':False,'geometry_changes':False,'weight_changes':False,
            'approved_color_preserved':True}
    action=args.out/'action';action.mkdir()
    routine=helper('sword_routine_profiles').routine(args.routine_id) if args.routine_id else None
    report['action']=warm.animate_phrase(bpy.data.objects['JiangRig'],config,base,return_to_guard=True,
                                         motion_profile=args.motion_profile,routine_spec=routine)
    if routine:report['routine']={key:routine[key] for key in ['id','label','description']}
    action_blend=action/'cycle-action.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(action_blend))
    if not args.skip_key_renders:
        render_frames(action,([1,36,44,47,50,54,58,66,95,103,124,166,180]
                             if args.motion_profile!='balanced' else [1,35,44,58,78,120,138,150,168,180]))
    # Start idle from the newly authored action's exact neutral pose.
    bpy.ops.wm.open_mainfile(filepath=str(action_blend))
    idle=args.out/'idle';idle.mkdir()
    report['idle']=idle_animation(bpy.data.objects['JiangRig'])
    bpy.ops.wm.save_as_mainfile(filepath=str(idle/'cycle-idle.blend'))
    if not args.skip_key_renders:render_frames(idle,[1,16,31,45,60])
    (args.out/'cycle-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('JIANG_CYCLE_BUILT',args.out,flush=True)


if __name__=='__main__':main()
