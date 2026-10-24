#!/usr/bin/env python3
"""Refine the saved v5 Jiang study locally; preserve its camera and textures.

Blender --background --disable-autoexec --python this.py -- --input V5.blend
  --config landmarks.json --out NEW_DIRECTORY [--skip-stills]
"""
from __future__ import annotations
import argparse, importlib.util, json, math, sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from bpy_extras.object_utils import world_to_camera_view


def load_base():
    spec = importlib.util.spec_from_file_location('jiang_turn_base', Path(__file__).with_name('build_fullbody_turn.py'))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod


def smooth(value):
    value = np.clip(value, 0., 1.)
    return value*value*(3.-2.*value)


def coordinates(obj):
    result = np.empty(len(obj.data.vertices)*3, dtype=np.float32)
    obj.data.vertices.foreach_get('co', result)
    return result.reshape((-1, 3))


def replace_weights(obj, weights):
    """Quantized continuous weights avoid hundreds of thousands of API calls."""
    obj.vertex_groups.clear()
    for name, values in weights.items():
        group = obj.vertex_groups.new(name=name)
        quantized = np.rint(np.clip(values, 0, 1)*4095).astype(np.int32)
        for value in np.unique(quantized):
            if value:
                group.add(np.flatnonzero(quantized == value).tolist(), float(value)/4095., 'REPLACE')


def soften_seams(body):
    """Relax only the exposed clipped collar rim; keep source UVs and face."""
    import bmesh
    bm = bmesh.new(); bm.from_mesh(body.data)
    boundary = [v for v in bm.verts if v.is_boundary and 1.48 < v.co.z < 1.64
                and abs(v.co.x) < .15 and -.25 < v.co.y < .05]
    for _ in range(3):
        bmesh.ops.smooth_vert(bm, verts=boundary, factor=.3, use_axis_x=True,
                             use_axis_y=True, use_axis_z=True)
    bm.to_mesh(body.data); bm.free(); body.data.update()
    return len(boundary)


def close_wrist(j):
    """A small skin cuff joins the authored closed grip to its sleeve."""
    hand = bpy.data.objects['JiangRightGrip_HandGrip']
    direction = (j['hand_end.R']-j['wrist.R']).normalized()
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,
        location=j['wrist.R']+direction*.003)
    cuff = bpy.context.object
    cuff.rotation_euler = direction.to_track_quat('Z','Y').to_euler()
    cuff.scale = (.030,.030,.055)
    cuff.data.materials.append(hand.data.materials[0])
    for polygon in cuff.data.polygons: polygon.use_smooth = True
    group = cuff.vertex_groups.new(name='hand.R')
    group.add(list(range(len(cuff.data.vertices))),1.,'REPLACE')
    count = len(cuff.data.vertices)
    bpy.ops.object.select_all(action='DESELECT')
    cuff.select_set(True); hand.select_set(True)
    bpy.context.view_layer.objects.active = hand
    bpy.ops.object.join()
    return count


def weights_for_secondary(body, head, base):
    c = coordinates(body); x, y, z = c.T
    weights = {g.name: np.zeros(len(c), dtype=np.float64) for g in body.vertex_groups}
    for vertex in body.data.vertices:
        for item in vertex.groups:
            weights[body.vertex_groups[item.group].name][vertex.index] = item.weight
    # The full hem, including ivory lining, follows continuously across panels.
    hem = .58*smooth((.94-z)/.42)*smooth((z-.29)/.12)
    # Keep trouser/leg geometry at the centre on its original leg weights.
    outer = np.maximum(smooth((np.abs(x)-.11)/.12), smooth((np.abs(y+.075)-.09)/.10))
    hem *= outer
    for name in weights:
        weights[name] *= 1.-hem
    right = smooth((.055-x)/.11); front = smooth((-.015-y)/.12)
    for side, lateral in [('R', right), ('L', 1-right)]:
        for depth, longitudinal in [('front', front), ('back', 1-front)]:
            weights['skirt.'+depth+'.'+side] += hem*lateral*longitudinal
    # Boots move as a single shape at the sole; transition above the ankle.
    boot = 1.-smooth((z-.20)/.12)
    for name in weights:
        weights[name] *= 1.-boot
    weights['foot.R'] += boot*(x < 0)
    weights['foot.L'] += boot*(x >= 0)
    total = sum(weights.values())
    replace_weights(body, {name: value/np.maximum(total, 1e-10) for name,value in weights.items()})
    hc = coordinates(head); hx, hy, hz = hc.T
    warm = base.brown_vertices(head)
    pony = smooth((hy-(.16+np.maximum(hz-1.8, 0)*.35))/.12)*smooth((2.035-hz)/.42)
    pony *= warm*(hz > 1.35)
    replace_weights(head, {'head': 1.-pony, 'ponytail': pony})
    return {'hem_vertices': int(np.count_nonzero(hem > .01)),
            'ponytail_vertices': int(np.count_nonzero(pony > .01)),
            'boot_rigid_vertices': int(np.count_nonzero(boot > .999)),
            'face_front_max_ponytail_weight': float(pony[hy < .05].max(initial=0)),
            'max_hem_weight': float(hem.max()), 'max_ponytail_weight': float(pony.max())}


def animate(arm, j, specs, config, base):
    scene = bpy.context.scene; bones = arm.data.bones
    length = {n:(j[b]-j[a]).length for n,a,b,_ in specs}
    support = Vector((-.19, -.22, .006))
    rest_hand = base.grip_basis(j['hand_end.R']-j['wrist.R'], config['rest_blade_axis'])
    records = []
    for frame in range(1, 61):
        t = (frame-1)/59
        p = math.radians(115)*float(smooth((t-.19)/.64))
        torso = math.radians(115)*float(smooth((t-.12)/.72))
        head = math.radians(115)*float(smooth((t-.07)/.77))
        drive = math.sin(math.pi*float(smooth((t-.10)/.78)))**2
        qp = Quaternion((0,0,1), p)
        qt = Quaternion((0,0,1), torso) @ Quaternion((1,0,0), math.radians(2)*drive)
        qh = Quaternion((0,0,1), head) @ Quaternion((1,0,0), math.radians(2)*drive)
        # A small anticipatory transfer toward the support foot, then settle.
        offset = Vector((-.018*drive, -.008*drive, -.026*drive))
        tp = lambda point: support+qp@(Vector(point)-support)+offset
        chest_origin = tp(j['spine'])
        tt = lambda point: chest_origin+qt@(Vector(point)-j['spine'])
        head_origin = tt(j['head'])
        th = lambda point: head_origin+qh@(Vector(point)-j['head'])
        desired = {}
        def setbone(name, start, end, q=None):
            rest = bones[name]
            if q is None:
                q = (rest.tail_local-rest.head_local).rotation_difference(end-start) @ rest.matrix_local.to_quaternion()
            desired[name] = Matrix.LocRotScale(start, q, Vector((1,1,1)))
        for name,a,b,_ in specs[:5]:
            transform, q = (tp, qp) if name == 'pelvis' else ((th,qh) if name == 'head' else (tt,qt))
            setbone(name, transform(j[a]), transform(j[b]), q@bones[name].matrix_local.to_quaternion())
        lift = .072*math.sin(math.pi*float(smooth((t-.20)/.60)))
        for side in ['R','L']:
            hip = tp(j['hip.'+side])
            if side == 'R':
                fq = Quaternion((0,0,1), p) @ Quaternion((1,0,0), math.radians(3.5)*drive)
                ankle = support+fq@(j['ankle.R']-support)
            else:
                step = math.radians(115)*float(smooth((t-.20)/.60))
                fq = Quaternion((0,0,1), step) @ Quaternion((1,0,0), math.radians(-5)*math.sin(math.pi*t)**2)
                ankle = support+Quaternion((0,0,1),step)@(j['ankle.L']-support)
                ankle.z += lift
            pole = hip+qp@Vector((0,-.7,-.4))
            knee, actual = base.two_bone(hip,pole,ankle,length['thigh.'+side],length['shin.'+side])
            setbone('thigh.'+side, hip, knee); setbone('shin.'+side, knee, actual)
            setbone('foot.'+side, actual, actual+fq@(j['toe.'+side]-j['ankle.'+side]), fq@bones['foot.'+side].matrix_local.to_quaternion())
        for side in ['R','L']:
            shoulder = tt(j['shoulder.'+side]); target = tt(config['posed_wrist.'+side])
            target.z += (.012 if side == 'R' else .018)*drive
            elbow,wrist = base.two_bone(shoulder,tt(config['posed_elbow_pole.'+side]),target,length['upper_arm.'+side],length['forearm.'+side])
            setbone('upper_arm.'+side, shoulder, elbow); setbone('forearm.'+side, elbow, wrist)
            direction = (wrist-elbow).normalized()
            if side == 'R':
                basis = base.grip_basis(direction,qt@Vector(config['posed_blade_axis']))
                q = basis.to_quaternion()@rest_hand.to_quaternion().inverted()@bones['hand.R'].matrix_local.to_quaternion()
            else:
                q = (j['hand_end.L']-j['wrist.L']).rotation_difference(direction)@bones['hand.L'].matrix_local.to_quaternion()
            setbone('hand.'+side, wrist,wrist+direction*length['hand.'+side],q)
        # Authored follow-through, not a cloth or hair simulation.
        lag = -math.radians(7)*drive + math.radians(2)*math.sin(math.pi*float(smooth((t-.73)/.27)))
        for name,a,b,_ in specs:
            if name.startswith('skirt.'):
                side_sign = 1 if name.endswith('R') else -1
                local = Quaternion((0,0,1), lag*.42) @ Quaternion((0,1,0), math.radians(1.8)*drive*side_sign)
                q = qp@local; start = tp(j[a])
            elif name == 'ponytail':
                local = Quaternion((0,0,1),lag) @ Quaternion((1,0,0),math.radians(3.5)*drive)
                q = qh@local; start = th(j[a])
            else:
                continue
            setbone(name,start,start+q@(j[b]-j[a]),q@bones[name].matrix_local.to_quaternion())
        for name,_,_,parent in specs:
            rest = bones[name].matrix_local
            basis = rest.inverted()@bones[parent].matrix_local@desired[parent].inverted()@desired[name] if parent else rest.inverted()@desired[name]
            pb = arm.pose.bones[name]; pb.location,pb.rotation_quaternion,pb.scale = basis.decompose()
            for channel in ['location','rotation_quaternion','scale']:
                pb.keyframe_insert(channel,frame=frame)
        scene.frame_set(frame); bpy.context.view_layer.update()
        error = max((arm.pose.bones[n].head-desired[n].translation).length for n,*_ in specs)
        # Track a true rigid sole reference, rather than a fixed ankle.
        support_actual = arm.pose.bones['foot.R'].matrix @ bones['foot.R'].matrix_local.inverted() @ support
        records.append({'frame':frame,'pelvis_yaw_degrees':math.degrees(p),'torso_yaw_degrees':math.degrees(torso),
                        'head_yaw_degrees':math.degrees(head),'left_step_lift':lift,'hair_lag_degrees':math.degrees(lag),
                        'support_reference':list(support_actual),'max_bone_head_error':error})
    scene.frame_set(1)
    return support,records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True); parser.add_argument('--config',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True); parser.add_argument('--skip-stills',action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not all(p.is_absolute() for p in [args.input,args.config,args.out]) or args.out.exists():
        raise ValueError('Absolute inputs and a new output directory required')
    args.out.mkdir(); base = load_base()
    bpy.ops.wm.open_mainfile(filepath=str(args.input)); scene = bpy.context.scene
    arm = bpy.data.objects['JiangRig']; arm.animation_data_clear()
    for pb in arm.pose.bones: pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    arm.data.edit_bones['ponytail'].head = (0,.26,2.02)
    arm.data.edit_bones['ponytail'].tail = (0,.29,1.42)
    bpy.ops.object.mode_set(mode='OBJECT')
    config = json.loads(args.config.read_text()); config['joints']['hair_top'] = [0,.26,2.02]; config['joints']['hair_end'] = [0,.29,1.42]
    j,specs = base.rest_specs(config)
    seam_count = soften_seams(bpy.data.objects['JiangFullbody'])
    wrist_count = close_wrist(j)
    weight_report = weights_for_secondary(bpy.data.objects['JiangFullbody'],bpy.data.objects['JiangApprovedHead'],base)
    support,records = animate(arm,j,specs,config,base)
    scene.frame_set(1); scene.render.threads_mode='FIXED'; scene.render.threads=4
    bpy.ops.wm.save_as_mainfile(filepath=str(args.out/'jiang-turn-refined.blend'))
    projection = world_to_camera_view(scene,scene.camera,support)
    report = {'status':'BUILT_AWAITING_VISUAL_REVIEW','source_blend':str(args.input),'source_sha256':base.sha(args.input),
              'cloud_calls':0,'camera_unchanged':True,'source_texture_pixels_modified':False,
              'collar_boundary_vertices_relaxed':seam_count,'wrist_bridge_vertices':wrist_count,'weights':weight_report,
              'support_reference_rest':list(support),'ground_anchor_source_pixels':[projection.x*1000,(1-projection.y)*1000],
              'frames':records,'max_bone_head_error':max(r['max_bone_head_error'] for r in records)}
    (args.out/'refinement-report.json').write_text(json.dumps(report,indent=2)+'\n')
    (args.out/'landmarks.json').write_text(json.dumps(config,indent=2)+'\n')
    if not args.skip_stills:
        for frame in [1,15,30,45,60]:
            scene.frame_set(frame); scene.render.filepath=str(args.out/f'pose-{frame:04d}.png'); bpy.ops.render.render(write_still=True)
    print('JIANG_REFINEMENT_DONE',args.out,flush=True)


if __name__ == '__main__': main()
