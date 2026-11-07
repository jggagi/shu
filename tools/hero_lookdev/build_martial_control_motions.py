#!/usr/bin/env python3
"""CPU Blender custom-control authoring; bake constraints into the original 22 bones.

The editable Blend retains named COG/torso/hand/foot/pole controls and actual
Blender IK constraints. The runtime GLB retains only the immutable deform rig
and a three-vertex skin carrier. No Rigify dependency or new bone is implied.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, math, struct, sys
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def module(name):
    path=Path(__file__).with_name(name)
    spec=importlib.util.spec_from_file_location(path.stem,path)
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
sword_math=module('build_ambush_martial_clips.py')
palm_math=module('build_ambush_palm_clips.py')

def yup(v): return [float(v.x),float(v.z),float(-v.y)]
def matrix_error(a,b): return max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4))
def rotation_z(value): return Quaternion((0,0,1),math.radians(value))
def smooth(x):
    x=min(1.,max(0.,x));return x*x*(3-2*x)
def interpolate(keys,t):
    for a,b in zip(keys,keys[1:]):
        if t<=b['t']+1e-8:
            x=smooth((t-a['t'])/(b['t']-a['t']))
            return {k:(Vector(a[k]).lerp(Vector(b[k]),x) if isinstance(a[k],list) else a[k]*(1-x)+b[k]*x) for k in a if k!='t'}
    return keys[-1]

def footwork_contract(recipe,recipe_path,seconds,expected_sha256=None):
    """One small optional two-use contract; absent means the original static feet."""
    parameters=recipe.get('footwork')
    if parameters is None:
        if expected_sha256 is not None:raise RuntimeError('Expected template SHA supplied for a static recipe')
        return None
    def number(value):return type(value) in {int,float} and math.isfinite(value)
    if not isinstance(parameters,dict) or set(parameters)!={'template','active_side','distance_m','lift_m'} or parameters['active_side'] not in {'L','R'}:raise RuntimeError('Invalid footwork parameters')
    if not isinstance(parameters['template'],str):raise RuntimeError('Template name must be a string')
    for name,bounds in [('distance_m',(.05,.28)),('lift_m',(.02,.08))]:
        if not number(parameters[name]) or not bounds[0]<=parameters[name]<=bounds[1]:raise RuntimeError('Unsupported short-step '+name)
    if not number(seconds) or seconds<=0:raise RuntimeError('Invalid footwork clip duration')
    path=(recipe_path.parent/parameters['template']).resolve()
    if path.parent!=recipe_path.parent.resolve() or path.name!='step_plant_return.template.json':raise RuntimeError('Footwork must use the local step/plant/return template')
    # Parse and hash the very same captured bytes. A batch invocation pins its
    # preflight digest so an intervening edit fails before any Blender work.
    template_bytes=path.read_bytes();template_sha=hashlib.sha256(template_bytes).hexdigest()
    if expected_sha256 is not None and template_sha!=expected_sha256:raise RuntimeError('Footwork template SHA changed since batch preflight')
    template=json.loads(template_bytes)
    if template.get('schema_version')!=1 or template.get('kind')!='footwork_template' or template.get('id')!='step_plant_return':raise RuntimeError('Unsupported footwork contract')
    keys=template['keys'];last=-1.
    if not isinstance(keys,list) or len(keys)<4:raise RuntimeError('Footwork needs ordered normalized keys')
    for key in keys:
        if not isinstance(key,dict) or set(key)!={'t','advance','lift'} or not all(number(v) for v in key.values()) or not last<key['t']<=1 or not 0<=key['advance']<=1 or not 0<=key['lift']<=1:raise RuntimeError('Invalid normalized footwork key')
        last=key['t']
    if keys[0]!={'t':0,'advance':0,'lift':0} or keys[-1]!={'t':1,'advance':0,'lift':0} or keys[1]['advance'] or keys[1]['lift'] or keys[-2]['advance'] or keys[-2]['lift']:raise RuntimeError('Footwork needs stationary neutral boundary intervals')
    phases=template['phases'];last=0.
    if not isinstance(phases,list) or not phases:raise RuntimeError('Footwork needs ordered phases')
    for phase in phases:
        if not isinstance(phase,dict) or set(phase)!={'from','to','label'} or not all(number(phase[k]) for k in ['from','to']) or phase['from']!=last or not last<phase['to']<=1 or not isinstance(phase['label'],str) or not phase['label']:raise RuntimeError('Invalid normalized footwork phase')
        last=phase['to']
    if last!=1:raise RuntimeError('Footwork phases must cover0..1')
    planted=template['planted_interval']
    if not isinstance(planted,list) or len(planted)!=2 or not all(number(v) for v in planted):raise RuntimeError('Invalid planted interval')
    plant,release=planted
    if not 0<plant<release<1 or not any(k['t']==plant and k['advance']==1 and k['lift']==0 for k in keys) or not any(k['t']==release and k['advance']==1 and k['lift']==0 for k in keys) or any(k['advance']!=1 or k['lift'] for k in keys if plant<=k['t']<=release):raise RuntimeError('Footwork needs an exact planted plateau')
    return {'template':{'path':str(path),'sha256':template_sha,'id':template['id']},'parameters':parameters,'keys':keys,'phases':[{'from':p['from']*seconds,'to':p['to']*seconds,'label':p['label']} for p in phases],'planted_interval':[v*seconds for v in planted]}

def foot_offset(contract,time,seconds):
    if contract is None:return Vector((0,0,0))
    sample=interpolate(contract['keys'],time/seconds);p=contract['parameters']
    return Vector((0,-p['distance_m']*sample['advance'],p['lift_m']*sample['lift']))

def main():
    p=argparse.ArgumentParser();p.add_argument('--recipe',type=Path,required=True);p.add_argument('--profiles',type=Path,required=True);p.add_argument('--root',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--blend',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--edited-blend',type=Path);p.add_argument('--expected-template-sha256')
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);recipe=json.loads(a.recipe.read_text());profile=json.loads(a.profiles.read_text())['profiles'][recipe['profile']]
    footwork=footwork_contract(recipe,a.recipe,recipe['seconds'],a.expected_template_sha256)
    source=a.root/profile['source_asset'][6:]
    if sha(source)!=profile['source_sha256']:raise RuntimeError('Immutable source SHA mismatch')
    for out in [a.out,a.blend,a.report]:out.parent.mkdir(parents=True,exist_ok=True)
    if not a.edited_blend:
        bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        if [b.name for b in rig.data.bones]!=profile['bone_names']:raise RuntimeError('22 bone contract differs')
        for tr in rig.animation_data.nla_tracks:tr.mute=True
        rig.animation_data.action=bpy.data.actions['Idle'];scene=bpy.context.scene;scene.frame_set(0);bpy.context.view_layer.update()
        neutral={b.name:b.matrix_basis.copy() for b in rig.pose.bones};world={b.name:b.matrix.copy() for b in rig.pose.bones}
        rest={b.name:[list(row) for row in b.matrix_local] for b in rig.data.bones};parents={b.name:b.parent.name if b.parent else None for b in rig.data.bones}
        if recipe['category']=='palm':
            palm_math.open_hand(rig)
            for hand_name in ['TinglanPointingHand','TinglanRelaxedHand']:
                bpy.data.objects[hand_name].hide_render=True;bpy.data.objects[hand_name].hide_viewport=True
        for tr in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(tr)
        rig.animation_data.action=None
        landmarks=sword_math.sword_landmarks(rig,bpy.data.objects['JiangRightGrip_Jian']) if recipe['category']=='sword' else None
        blade_axis=(world['hand.R']@landmarks['hand_tip']-world['hand.R']@landmarks['hand_base']).normalized() if landmarks else Vector((0,-1,0))
        keys=[]
        for raw in recipe['keys']:
            key=dict(raw)
            for field,bone in [('left','hand.L'),('right','hand.R')]:
                if key[field]=='neutral':key[field]=list(world[bone].translation)
            if key['right_direction']=='neutral':key['right_direction']=list(blade_axis)
            keys.append(key)
        fps=100;seconds=recipe['seconds'];scene.render.fps=fps;scene.frame_start=0;scene.frame_end=round(seconds*fps)
        collection=bpy.data.collections.new('SHU Editable Martial Controls');scene.collection.children.link(collection)
        controls={}
        def empty(name,style='CUBE',size=.11):
            ob=bpy.data.objects.new('CTRL_'+name,None);collection.objects.link(ob);ob.empty_display_type=style;ob.empty_display_size=size;ob.show_in_front=True;ob.rotation_mode='QUATERNION';controls[name]=ob;return ob
        for n in ['COG','Spine','Chest','Gaze','Hand.L','Hand.R','Foot.L','Foot.R','Elbow.L','Elbow.R','Knee.L','Knee.R']:empty(n,'SPHERE' if n.startswith(('Elbow','Knee')) else 'ARROWS')
        controls['COG']['purpose']='Lower and transfer the body center; leg IK follows authored contact targets.'
        controls['Chest']['purpose']='Late torso follow-through, after hips have begun to turn.'
        for side in ['L','R']:
            controls['Foot.'+side]['purpose']='World-space ankle target; stance foot locked, optional swing foot follows step/plant/return. Rotation locked.'
            controls['Hand.'+side]['purpose']='World-space wrist target and hand/weapon orientation.'
        constraints=[]
        def constrain(bone,kind,target):
            c=rig.pose.bones[bone].constraints.new(kind);c.name='SHU '+kind+' '+target;c.target=controls[target]
            if kind in {'COPY_TRANSFORMS','COPY_ROTATION'}:c.target_space='WORLD';c.owner_space='WORLD'
            constraints.append(c);return c
        constrain('pelvis','COPY_TRANSFORMS','COG')
        constrain('spine','COPY_ROTATION','Spine');constrain('chest','COPY_ROTATION','Chest');constrain('head','COPY_ROTATION','Gaze')
        for side in ['L','R']:
            for bone,target,pole in [('forearm.'+side,'Hand.'+side,'Elbow.'+side),('shin.'+side,'Foot.'+side,'Knee.'+side)]:
                c=constrain(bone,'IK',target);c.chain_count=2;c.use_stretch=False;c.iterations=500;c.pole_target=controls[pole]
                # The pole offset is calibrated once against the original neutral
                # pose. Pole objects remain editable in the saved Blend.
                base=rig.pose.bones['upper_arm.'+side if bone.startswith('forearm') else 'thigh.'+side]
                c.pole_angle=0
            constrain('hand.'+side,'COPY_ROTATION','Hand.'+side);constrain('foot.'+side,'COPY_TRANSFORMS','Foot.'+side)
        upright=Matrix(((1,0,0),(0,0,-1),(0,1,0))).to_quaternion()
        bend_history={}
        min_pole_perpendicular_distance=[float('inf')]
        def set_controls(control,time=0.):
            hip_yaw=control['hip_yaw'];hip_rot=rotation_z(hip_yaw)
            controls['COG'].matrix_world=Matrix.LocRotScale(world['pelvis'].translation+Vector(control['shift']),hip_rot@world['pelvis'].to_quaternion(),Vector((1,1,1)))
            controls['Spine'].rotation_quaternion=rotation_z(hip_yaw+control['spine_yaw'])@Quaternion((1,0,0),math.radians(control['lean']*.4))@world['spine'].to_quaternion()
            controls['Chest'].rotation_quaternion=rotation_z(hip_yaw+control['spine_yaw']+control['chest_yaw'])@Quaternion((1,0,0),math.radians(control['lean']))@world['chest'].to_quaternion()
            controls['Gaze'].rotation_quaternion=rotation_z(control['gaze_yaw'])@world['head'].to_quaternion()
            for side in ['L','R']:
                hand=controls['Hand.'+side];hand.location=control['left' if side=='L' else 'right']
                rot=world['hand.'+side].to_quaternion()
                if side=='L':rot=rot.slerp(rotation_z(control['palm_yaw'])@upright,control['palm_open'])
                elif landmarks:rot=blade_axis.rotation_difference(Vector(control['right_direction']).normalized())@rot
                hand.rotation_quaternion=rot
                foot_matrix=world['foot.'+side].copy()
                if footwork and side==footwork['parameters']['active_side']:
                    foot_matrix.translation+=foot_offset(footwork,time,seconds)
                controls['Foot.'+side].matrix_world=foot_matrix
                # Match original bend planes at neutral; artist-authored pole
                # offsets add a measured elbow opening during the effort phase.
                # Keep the elbow bend plane relative to the moving torso,
                # rather than leaving a world-space pole behind as the hips
                # rotate through it. A fixed old pole caused arm-axis twists.
                bpy.context.view_layer.update()
                shoulder=rig.pose.bones['upper_arm.'+side].head.copy()
                axis=(Vector(control['left' if side=='L' else 'right'])-shoulder).normalized()
                if side not in bend_history:
                    neutral_axis=(world['hand.'+side].translation-world['upper_arm.'+side].translation).normalized()
                    bend=world['forearm.'+side].translation-world['upper_arm.'+side].translation
                    bend_history[side]=(bend-neutral_axis*bend.dot(neutral_axis)).normalized()
                # Parallel transport the previous bend plane to the new wrist
                # axis. Unlike a fixed world/body pole this cannot cross the
                # wrist axis and flip when a close-in palm passes the chest.
                transported=bend_history[side]-axis*bend_history[side].dot(axis)
                transported.normalize()
                torso_turn=rotation_z(hip_yaw+control['spine_yaw']+control['chest_yaw'])
                preferred=torso_turn@Vector((.55 if side=='L' else -.55,0,-.45))+Vector(control['elbow_'+side])
                preferred-=axis*preferred.dot(axis)
                if preferred.length>1e-5:
                    preferred.normalize()
                    if preferred.dot(transported)<0:preferred=-preferred
                    transported=transported.lerp(preferred,.04).normalized()
                # Recovery returns the entire bend plane to source neutral
                # over .45s, not on the final IK-off frame. This removes the
                # otherwise hidden elbow/wrist snap at the neutral endpoint.
                neutral_axis=(world['hand.'+side].translation-world['upper_arm.'+side].translation).normalized()
                neutral_bend=world['forearm.'+side].translation-world['upper_arm.'+side].translation
                neutral_bend-=neutral_axis*neutral_bend.dot(neutral_axis)
                neutral_bend-=axis*neutral_bend.dot(axis)
                if neutral_bend.length>1e-5:
                    neutral_bend.normalize()
                    return_amount=smooth((time-(seconds-.45))/.40)
                    delta=transported.rotation_difference(neutral_bend)
                    transported=(Quaternion().slerp(delta,return_amount)@transported).normalized()
                bend_history[side]=transported
                controls['Elbow.'+side].location=shoulder+transported*.45
                min_pole_perpendicular_distance[0]=min(min_pole_perpendicular_distance[0],((controls['Elbow.'+side].location-shoulder).cross(axis)).length)
                controls['Knee.'+side].location=world['shin.'+side].translation+Vector((0,-.35,0))
            bpy.context.view_layer.update()
        set_controls(interpolate(keys,0))
        # Find stable neutral pole angles independently for each 2-bone chain.
        # This calibration changes constraints only, never source rest or lengths.
        for c in [x for x in constraints if x.type=='IK']:
            bone=next(b for b in rig.pose.bones if c in b.constraints.values())
            expected=world[bone.name].translation
            best=(float('inf'),0.)
            for step,span in [(2.,180.),(.1,2.),(.005,.1),(.00025,.005)]:
                center=math.degrees(best[1]);first=center-span
                for index in range(round(2*span/step)+1):
                    degree=first+index*step;c.pole_angle=math.radians(degree);bpy.context.view_layer.update()
                    error=(bone.head-expected).length
                    if error<best[0]:best=(error,c.pole_angle)
            c.pole_angle=best[1]
        # Key the actual controls densely using eased sparse pose intent. These are
        # editable ordinary object F-curves, not hidden handlers or Python drivers.
        bend_history.clear()
        for frame in range(scene.frame_end+1):
            scene.frame_set(frame);control=interpolate(keys,frame/fps);set_controls(control,frame/fps)
            for ob in controls.values():
                for channel in ['location','rotation_quaternion']:ob.keyframe_insert(channel,frame=frame)
            # At the two exact neutral endpoints retain the imported neutral bone
            # basis rather than solving its almost-straight legs again. Interior
            # frames keep full IK influence; no foot-lock crossfade is introduced.
            for c in [x for x in constraints if x.type=='IK']:
                c.influence=0. if frame in [0,scene.frame_end] else 1.
                c.keyframe_insert('influence',frame=frame)
        scene.frame_set(0);bpy.context.view_layer.update()
        rig['authoring']='Custom named Blender control objects + actual two-bone IK. Not Rigify.'
        rig['source_sha256']=profile['source_sha256'];rig['phase_plan']=json.dumps(recipe['phases'],ensure_ascii=False)
        rig['source_neutral_basis']=json.dumps({n:[list(r) for r in m] for n,m in neutral.items()})
        rig['source_neutral_world']=json.dumps({n:[list(r) for r in m] for n,m in world.items()})
        rig['source_rest']=json.dumps(rest)
        rig['source_footwork_contract']=json.dumps(footwork,sort_keys=True)
    else:
        if a.edited_blend.resolve()==a.blend.resolve():raise RuntimeError('Edited source must be a separate retained input copy')
        bpy.ops.wm.open_mainfile(filepath=str(a.edited_blend.resolve()))
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        if rig.get('source_sha256')!=profile['source_sha256']:raise RuntimeError('Edited source identity differs')
        if [b.name for b in rig.data.bones]!=profile['bone_names']:raise RuntimeError('Edited source 22 bones differ')
        neutral={n:Matrix(m) for n,m in json.loads(rig['source_neutral_basis']).items()}
        world={n:Matrix(m) for n,m in json.loads(rig['source_neutral_world']).items()}
        rest=json.loads(rig['source_rest']);parents={b.name:b.parent.name if b.parent else None for b in rig.data.bones}
        if rest!={b.name:[list(row) for row in b.matrix_local] for b in rig.data.bones}:raise RuntimeError('Edited source changed immutable rest')
        scene=bpy.context.scene;fps=100;seconds=recipe['seconds'];scene.frame_start=0;scene.frame_end=round(seconds*fps);scene.render.fps=fps;scene.frame_set(0);bpy.context.view_layer.update()
        controls={ob.name.removeprefix('CTRL_'):ob for ob in bpy.context.scene.objects if ob.name.startswith('CTRL_')}
        if len(controls)!=12:raise RuntimeError('Edited source requires all 12 named controls')
        if json.loads(rig.get('source_footwork_contract','null'))!=footwork:raise RuntimeError('Edited source footwork contract differs; retain its matching recipe/template')
        landmarks=sword_math.sword_landmarks(rig,bpy.data.objects['JiangRightGrip_Jian']) if recipe['category']=='sword' else None
        blade_axis=(world['hand.R']@landmarks['hand_tip']-world['hand.R']@landmarks['hand_base']).normalized() if landmarks else Vector((0,-1,0))
    constraint_info=[{'bone':b.name,'name':c.name,'type':c.type,'target':c.target.name,'chain_count':c.chain_count if c.type=='IK' else 0,'pole_target':c.pole_target.name if c.type=='IK' else '', 'pole_angle':c.pole_angle if c.type=='IK' else 0} for b in rig.pose.bones for c in b.constraints]
    # Full original model + controls are local authoring sources only.
    bpy.ops.wm.save_as_mainfile(filepath=str(a.blend.resolve()))
    baked=[];samples=[];max_foot=0;max_foot_rotation=0;max_wrist=0;max_blade=0;boundary=0
    max_support=0.;max_active_target=0.;max_planted=0.;max_control_template_deviation=0.;plant_samples=0;max_arm_length_error=0.;max_leg_length_error=0.;max_rotation_step=0.;rotation_worst=None;previous_local={}
    active_side=footwork['parameters']['active_side'] if footwork else None
    support_side=('L' if active_side=='R' else 'R') if footwork else None
    for frame in range(scene.frame_end+1):
        scene.frame_set(frame);bpy.context.view_layer.update();evaluated=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        poses={b.name:b.matrix.copy() for b in evaluated.pose.bones}
        if frame in [0,scene.frame_end]:
            # Preserve the original complete neutral pose exactly at both ends;
            # constraints already evaluate there within micrometre rounding.
            boundary=max(boundary,max(matrix_error(poses[n],world[n]) for n in world));poses={n:m.copy() for n,m in world.items()}
        baked.append(poses)
        foot=max((poses['foot.'+s].translation-world['foot.'+s].translation).length for s in ['L','R'])
        foot_rot=max(poses['foot.'+s].to_quaternion().rotation_difference(world['foot.'+s].to_quaternion()).angle for s in ['L','R'])
        max_foot=max(max_foot,foot);max_foot_rotation=max(max_foot_rotation,foot_rot)
        active_target_error=0.;support_error=foot;planted_error=0.
        if footwork:
            support_error=(poses['foot.'+support_side].translation-world['foot.'+support_side].translation).length
            active_target_error=(poses['foot.'+active_side].translation-controls['Foot.'+active_side].matrix_world.translation).length
            authored_target=world['foot.'+active_side].translation+foot_offset(footwork,frame/fps,seconds)
            control_template_deviation=(controls['Foot.'+active_side].matrix_world.translation-authored_target).length
            max_control_template_deviation=max(max_control_template_deviation,control_template_deviation)
            if footwork['planted_interval'][0]-1e-8<=frame/fps<=footwork['planted_interval'][1]+1e-8:
                plant_samples+=1
                planted=world['foot.'+active_side].translation+Vector((0,-footwork['parameters']['distance_m'],0))
                planted_error=(poses['foot.'+active_side].translation-planted).length
            max_support=max(max_support,support_error);max_active_target=max(max_active_target,active_target_error);max_planted=max(max_planted,planted_error)
        for side in ['L','R']:
            for chain,label in [(['upper_arm.'+side,'forearm.'+side,'hand.'+side],'arm'),(['thigh.'+side,'shin.'+side,'foot.'+side],'leg')]:
                error=max(abs((poses[b].translation-poses[c].translation).length-(world[b].translation-world[c].translation).length) for b,c in zip(chain,chain[1:]))
                if label=='arm':max_arm_length_error=max(max_arm_length_error,error)
                else:max_leg_length_error=max(max_leg_length_error,error)
        for name,pose in poses.items():
            local=(poses[parents[name]].inverted()@pose if parents[name] else pose).to_quaternion()
            if name in previous_local:
                delta=math.degrees(2*math.acos(min(1.,abs(local.dot(previous_local[name])))))
                if delta>max_rotation_step:max_rotation_step=delta;rotation_worst={'bone':name,'seconds':frame/fps}
            previous_local[name]=local
        wrist=max((poses['hand.'+s].translation-controls['Hand.'+s].location).length for s in ['L','R'])
        max_wrist=max(max_wrist,wrist)
        sample={'seconds':frame/fps,'hip':yup(poses['pelvis'].translation),'chest':yup(poses['chest'].translation),'shoulder_L':yup(poses['upper_arm.L'].translation),'shoulder_R':yup(poses['upper_arm.R'].translation),'left_wrist':yup(poses['hand.L'].translation),'right_wrist':yup(poses['hand.R'].translation),'foot_L':yup(poses['foot.L'].translation),'foot_R':yup(poses['foot.R'].translation),'foot_L_rotation':list(poses['foot.L'].to_quaternion()),'foot_R_rotation':list(poses['foot.R'].to_quaternion()),'foot_drift_m':foot,'wrist_target_error_m':wrist,'palm_center':yup(poses['hand.L']@Vector((0,.055,.018))),'palm_normal':yup((poses['hand.L'].to_3x3()@Vector((0,0,1))).normalized())}
        if footwork:sample.update(active_foot_target=yup(controls['Foot.'+active_side].matrix_world.translation),authored_foot_target=yup(authored_target),active_control_template_deviation_m=control_template_deviation,support_foot_drift_m=support_error,active_foot_target_error_m=active_target_error,planted_contact_error_m=planted_error,planted=footwork['planted_interval'][0]-1e-8<=frame/fps<=footwork['planted_interval'][1]+1e-8)
        if landmarks:
            base=poses['hand.R']@landmarks['hand_base'];tip=poses['hand.R']@landmarks['hand_tip'];local_axis=world['hand.R'].to_quaternion().inverted()@blade_axis;want=(controls['Hand.R'].rotation_quaternion@local_axis).normalized()
            error=math.degrees((tip-base).normalized().angle(want));max_blade=max(max_blade,error)
            sample.update(blade_base=yup(base),blade_tip=yup(tip),blade_axis_error_degrees=error)
        samples.append(sample)
    rig.animation_data_clear()
    for bone in rig.pose.bones:
        for c in list(bone.constraints):bone.constraints.remove(c)
    if not a.edited_blend:constraints.clear()
    action=bpy.data.actions.new(recipe['clip']);rig.animation_data_create();rig.animation_data.action=action
    for frame,poses in enumerate(baked):
        scene.frame_set(frame)
        for bone in rig.pose.bones:
            bone.matrix=poses[bone.name];bpy.context.view_layer.update()
            bone.rotation_mode='QUATERNION'
            for channel in ['location','rotation_quaternion','scale']:bone.keyframe_insert(channel,frame=frame)
    tr=rig.animation_data.nla_tracks.new();tr.name=recipe['clip'];tr.strips.new(recipe['clip'],0,action);tr.mute=True;rig.animation_data.action=None
    scene.frame_set(0)
    for bone in rig.pose.bones:bone.matrix_basis=neutral[bone.name]
    bpy.context.view_layer.update()
    mesh=bpy.data.meshes.new('ControlMotionCarrier');mesh.from_pydata([(0,0,0),(.00001,0,0),(0,.00001,0)],[],[(0,1,2)]);carrier=bpy.data.objects.new('ControlMotionCarrier',mesh);scene.collection.objects.link(carrier);carrier.parent=rig;carrier.vertex_groups.new(name='pelvis').add([0,1,2],1.,'REPLACE');carrier.modifiers.new('Skeleton import carrier','ARMATURE').object=rig
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [rig,carrier]:ob.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(a.out.resolve()),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_materials='NONE',export_texcoords=False,export_normals=False,export_animations=True,export_animation_mode='NLA_TRACKS',export_frame_range=False,export_force_sampling=True,export_nla_strips=True,export_skins=True,export_def_bones=False,export_cameras=False,export_lights=False)
    data=a.out.read_bytes();gltf=json.loads(data[20:20+struct.unpack_from('<I',data,12)[0]])
    checks={'source_sha_unchanged':sha(source)==profile['source_sha256'],'same_22_bones_and_parents':len(rig.data.bones)==22 and parents=={b.name:b.parent.name if b.parent else None for b in rig.data.bones},'source_bind_rest_unchanged':rest=={b.name:[list(row) for row in b.matrix_local] for b in rig.data.bones},'foot_lock_under_50um':max_foot<.00005,'foot_rotation_lock_under_0_1deg':max_foot_rotation<math.radians(.1),'wrist_target_under_2mm':max_wrist<.002,'neutral_constraint_boundary_under_50um':boundary<.00005,'blade_axis_under_0_1deg':max_blade<.1,'one_expected_clip':len(gltf.get('animations',[]))==1 and gltf['animations'][0]['name']==recipe['clip'],'carrier_only':len(gltf.get('meshes',[]))==1 and not gltf.get('materials') and not gltf.get('images'),'skin_original_22':len(gltf['skins'][0]['joints'])==22,'no_actor_node_animation':all(gltf['nodes'][c['target']['node']]['name'] in profile['bone_names'] for c in gltf['animations'][0]['channels'])}
    # A stepping foot is deliberate travel, not a failed lock or an asserted
    # all-feet lock. Static legacy recipes retain their exact old lock checks.
    if footwork:
        checks.pop('foot_lock_under_50um')
        checks.update(support_foot_lock_under_50um=max_support<.00005,active_foot_target_under_50um=max_active_target<.00005,active_control_matches_template_under_50um=max_control_template_deviation<.00005,planted_contact_under_50um=max_planted<.00005,planted_samples_present=plant_samples>0)
    checks.update(arm_link_lengths_under_50um=max_arm_length_error<.00005,leg_link_lengths_under_50um=max_leg_length_error<.00005,local_rotation_continuity_under_30deg=max_rotation_step<30.)
    measurements={'max_foot_drift_m':max_foot,'max_foot_rotation_radians':max_foot_rotation,'max_wrist_residual_m':max_wrist,'max_blade_axis_error_degrees':max_blade,'boundary_pose_max_error':boundary,'max_arm_link_length_error_m':max_arm_length_error,'max_leg_link_length_error_m':max_leg_length_error,'max_local_rotation_step_degrees':max_rotation_step,'worst_rotation_step':rotation_worst}
    if footwork:
        origin=samples[0]['foot_'+active_side]
        measurements.update(max_support_foot_drift_m=max_support,max_active_foot_target_residual_m=max_active_target,max_active_control_template_deviation_m=max_control_template_deviation,max_planted_contact_drift_m=max_planted,planted_sample_count=plant_samples,active_foot_forward_travel_m=max(s['foot_'+active_side][2]-origin[2] for s in samples),active_foot_lift_m=max(s['foot_'+active_side][1]-origin[1] for s in samples),boundary_foot_target_delta_m=max((Vector(samples[i]['active_foot_target'])-Vector(samples[j]['active_foot_target'])).length for i,j in [(0,1),(-1,-2)]))
        checks['foot_target_boundary_travel_under_50um']=measurements['boundary_foot_target_delta_m']<.00005
    report={'schema_version':1,'author':'Codex for Shu; original custom-control choreography','license':profile['source_license'],'source':{'asset':profile['source_asset'],'sha256':sha(source)},'builder':{'path':'tools/hero_lookdev/build_martial_control_motions.py','sha256':sha(__file__),'blender':bpy.app.version_string},'recipe_sha256':sha(a.recipe),'edited_source':({'path':str(a.edited_blend),'sha256':sha(a.edited_blend)} if a.edited_blend else None),'controller_rig':{'type':'Custom Blender control objects and actual two-bone IK; not Rigify','controls':[{'name':ob.name,'purpose':ob.get('purpose','torso phase or limb pole control')} for ob in controls.values()],'constraints':constraint_info,'editable_blend_path':str(a.blend),'editable_blend_sha256':sha(a.blend)},'clip':{'name':recipe['clip'],'seconds':seconds,'fps':fps,'frames':scene.frame_end+1,'tracks':len(gltf['animations'][0]['channels']),'phases':recipe['phases']},'rig':{'names':profile['bone_names'],'parents':parents,'rest_matrices_blender':rest},'footwork':footwork,'measurements':measurements,'checks':checks,'all_pass':all(checks.values()),'samples':samples,'output':{'path':str(a.out),'bytes':len(data),'sha256':sha(a.out)},'import':{'fps':100,'remove_immutable_tracks':False,'optimizer':False},'limitations':['Custom authoring controls, not Rigify','No finger bones or cloth simulation','Numeric constraints do not establish artistic acceptance','Native/Web visual review performed separately by integrator'],'cloud_calls':0,'paid_calls':0,'new_installs':0}
    a.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('CONTROL_MOTION '+json.dumps({'all_pass':report['all_pass'],'checks':checks,'measurements':report['measurements']},ensure_ascii=False),flush=True)
    if not report['all_pass']:raise RuntimeError('Control motion invariant failure')
if __name__=='__main__':main()
