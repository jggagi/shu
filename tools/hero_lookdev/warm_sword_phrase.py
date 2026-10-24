#!/usr/bin/env python3
"""Local material revision and four-second authored sword phrase.

Original geometry/UV/packed textures are retained. Region gains are a vertex
attribute used by Blender materials, not rewritten source image pixels.
"""
from __future__ import annotations
import argparse, importlib.util, json, math, sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from bpy_extras.object_utils import world_to_camera_view


def helper(name):
    path = Path(__file__).with_name(name+'.py')
    spec = importlib.util.spec_from_file_location(name,path)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod


def smooth(value):
    value = np.clip(value,0,1)
    return value*value*(3-2*value)


def sample_vertex_colors(obj):
    material = obj.data.materials[0]
    shader = material.node_tree.nodes.get('Principled BSDF')
    image = shader.inputs['Base Color'].links[0].from_node.image
    width,height = image.size
    pixels = np.empty(width*height*4,dtype=np.float32); image.pixels.foreach_get(pixels)
    pixels = pixels.reshape((height,width,4))
    uv = np.empty(len(obj.data.loops)*2,dtype=np.float32)
    obj.data.uv_layers.active.data.foreach_get('uv',uv); uv = uv.reshape((-1,2))
    color = pixels[(uv[:,1]*height).astype(int).clip(0,height-1),(uv[:,0]*width).astype(int).clip(0,width-1),:3]
    ids = np.empty(len(obj.data.loops),dtype=np.int32); obj.data.loops.foreach_get('vertex_index',ids)
    count = np.bincount(ids,minlength=len(obj.data.vertices)).clip(1)
    result = np.stack([np.bincount(ids,weights=color[:,k],minlength=len(count))/count for k in range(3)],axis=1)
    return result


def set_gain_attribute(obj,gains):
    layer = obj.data.color_attributes.new(name='JiangWarmGain',type='FLOAT_COLOR',domain='POINT')
    values = np.ones((len(gains),4),dtype=np.float32); values[:,:3] = gains
    layer.data.foreach_set('color',values.ravel())
    material = obj.data.materials[0]
    nodes,links = material.node_tree.nodes,material.node_tree.links
    shader = nodes.get('Principled BSDF'); source = shader.inputs['Base Color'].links[0].from_socket
    attribute = nodes.new('ShaderNodeVertexColor'); attribute.layer_name = 'JiangWarmGain'
    attribute.label = 'Authored skin / hair / cloth color gains'
    saturate = nodes.new('ShaderNodeHueSaturation'); saturate.inputs['Saturation'].default_value=1.12
    saturate.label = 'Retain pigment rather than pale gray'
    multiply = nodes.new('ShaderNodeMixRGB'); multiply.blend_type='MULTIPLY'; multiply.inputs[0].default_value=1
    links.new(source,saturate.inputs['Color']); links.new(saturate.outputs['Color'],multiply.inputs[1])
    links.new(attribute.outputs['Color'],multiply.inputs[2]); links.new(multiply.outputs['Color'],shader.inputs['Base Color'])


def warm_materials():
    reports = {}
    for name in ['JiangApprovedHead','JiangFullbody']:
        obj = bpy.data.objects[name]; color = sample_vertex_colors(obj)
        points = np.array([v.co[:] for v in obj.data.vertices]); x,y,z=points.T
        r,g,b=color.T; maximum=color.max(axis=1); saturation=(maximum-color.min(axis=1))/np.maximum(maximum,1e-5)
        if name == 'JiangApprovedHead':
            hair_region = np.maximum.reduce([smooth((z-1.88)/.11),smooth((y+.01)/.12),smooth((np.abs(x)-.145)/.045)])
            hair = hair_region*smooth((saturation-.10)/.12)*smooth((r-b-.01)/.04)
            skin_gain = np.array([.72,.44,.31]); hair_gain=np.array([.50,.34,.23])
            gain = skin_gain[None,:]*(1-hair[:,None])+hair_gain[None,:]*hair[:,None]
            # Preserve the eye whites and iris contrast through a soft local mask.
            eye = np.exp(-((np.abs(x)-.071)/.042)**4-((z-1.825)/.035)**4)*smooth((-.14-y)/.06)
            gain = gain*(1-.85*eye[:,None])+np.ones_like(gain)*(.85*eye[:,None])
            cheek = np.exp(-((np.abs(x)-.088)/.050)**2-((z-1.755)/.045)**2)*smooth((-.15-y)/.06)*(1-hair)
            gain[:,1] *= 1-.035*cheek; gain[:,2] *= 1-.045*cheek
            region = (y<-.16)&(z>1.70)&(z<1.89)&(np.abs(x)<.14)
            reports[name]={'hair_weighted_vertices':int(np.count_nonzero(hair>.1)),
                           'skin_region_source_median':np.median(color[region],axis=0).tolist(),
                           'skin_gain':skin_gain.tolist(),'hair_gain':hair_gain.tolist()}
        else:
            blue = smooth((b-r-.012)/.060)
            ivory=np.array([.82,.74,.62]); indigo=np.array([.35,.57,.78])
            gain=ivory[None,:]*(1-blue[:,None])+indigo[None,:]*blue[:,None]
            # The original left hand belongs to this single source body mesh.
            skin = smooth((x-.27)/.045)*smooth((1.16-z)/.06)*smooth((z-.78)/.06)*smooth((r-b-.015)/.05)
            gain = gain*(1-skin[:,None])+np.array([.72,.44,.31])[None,:]*skin[:,None]
            reports[name]={'blue_weighted_vertices':int(np.count_nonzero(blue>.1)),
                           'left_skin_weighted_vertices':int(np.count_nonzero(skin>.1)),
                           'source_median':np.median(color,axis=0).tolist(),
                           'ivory_gain':ivory.tolist(),'blue_gain':indigo.tolist()}
        set_gain_attribute(obj,gain)
    for material in bpy.data.materials:
        if material.name.startswith(('Grip skin warm ivory','Neck warm ivory')):
            material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.55,.31,.21,1)
            reports[material.name]={'base_color_linear':[.55,.31,.21,1]}
    return reports


def stabilize_left_hand(config):
    """Keep the source open hand rigid; blend only the short wrist transition."""
    obj=bpy.data.objects['JiangFullbody'];points=np.array([v.co[:] for v in obj.data.vertices])
    wrist=np.array(config['joints']['wrist.L']); direction=np.array(config['joints']['hand_end.L'])-wrist
    direction/=np.linalg.norm(direction);delta=points-wrist
    along=np.einsum('ij,j->i',delta,direction,optimize=False)
    radial=np.linalg.norm(delta-along[:,None]*direction[None,:],axis=1)
    region=(points[:,0]>.31)&(radial<.105)&(np.linalg.norm(delta,axis=1)<.235)
    blend=smooth((along+.025)/.035)*region
    weights={g.name:np.zeros(len(points)) for g in obj.vertex_groups}
    for vertex in obj.data.vertices:
        for assignment in vertex.groups:weights[obj.vertex_groups[assignment.group].name][vertex.index]=assignment.weight
    for name in weights:weights[name]*=1-blend
    weights['hand.L']+=blend
    refine=helper('refine_fullbody_turn');refine.replace_weights(obj,weights)
    return {'affected_vertices':int(np.count_nonzero(blend>.01)),'rigid_hand_vertices':int(np.count_nonzero(blend>.999)),
            'geometry_unchanged':True,'transition_metres':.035}


def animate_phrase(arm,config,base,return_to_guard=False,motion_profile='balanced',routine_spec=None):
    """Guard, deliberate preparation, one diagonal cut, then recover and hold."""
    if motion_profile not in ['balanced','power-v1','jianshu-v1','routine-v1']:
        raise ValueError('Unknown sword motion profile')
    if motion_profile in ['power-v1','jianshu-v1','routine-v1'] and not return_to_guard:
        raise ValueError('Power profile requires the complete return-to-guard action')
    power=motion_profile in ['power-v1','jianshu-v1','routine-v1']
    jianshu=motion_profile in ['jianshu-v1','routine-v1']
    if motion_profile=='routine-v1' and not routine_spec:
        raise ValueError('A routine-v1 action requires its explicit authored specification')
    j,specs=base.rest_specs(config); bones=arm.data.bones
    arm.animation_data_clear()
    for pb in arm.pose.bones: pb.matrix_basis=Matrix.Identity(4)
    lengths={n:(j[b]-j[a]).length for n,a,b,_ in specs}
    support=Vector((-.19,-.22,.006))
    rest_hand=base.grip_basis(j['hand_end.R']-j['wrist.R'],config['rest_blade_axis'])
    # t, pelvis/torso/head yaw, forward lean, root Y/Z, right wrist, left wrist, blade direction.
    keys=[
        (0.,0,0,0,0,0,0,[-.24,-.38,1.17],[.34,-.16,1.04],[-.40,-.50,-.77]),
        (.60,0,0,0,0,0,0,[-.24,-.38,1.17],[.34,-.16,1.04],[-.40,-.50,-.77]),
        (1.45,-8,-23,-6,1,-.012,-.025,[-.35,-.20,1.52],[.25,-.14,1.27],[-.40,-.18,.90]),
        (1.92,20,42,20,4,-.085,-.047,[-.12,-.46,1.09],[.38,.02,1.14],[-.55,-.42,-.72]),
        (2.55,20,39,23,2,-.095,-.045,[-.05,-.39,1.06],[.36,-.02,1.10],[-.55,-.42,-.72]),
        (3.60,15,18,8,0,-.085,-.040,[-.20,-.36,1.19],[.33,-.18,1.05],[-.40,-.50,-.77]),
        (4.,15,18,8,0,-.085,-.040,[-.20,-.36,1.19],[.33,-.18,1.05],[-.40,-.50,-.77])]
    if return_to_guard:
        keys.extend([
            (4.60,10,12,5,0,-.060,-.025,[-.22,-.37,1.20],[.34,-.16,1.04],[-.40,-.50,-.77]),
            (5.60,0,0,0,0,0,0,[-.24,-.38,1.17],[.34,-.16,1.04],[-.40,-.50,-.77]),
            (6.,0,0,0,0,0,0,[-.24,-.38,1.17],[.34,-.16,1.04],[-.40,-.50,-.77])])
    phases=['guard','preparation','cut','follow','recovery','hold','return','return','guard']
    if power:
        # The waist starts the cut before the arm; the boot lands as the stroke completes.
        # The short follow-through and held extension let the movement read as a strike.
        keys=[
            keys[0],
            (.35,0,0,0,0,0,0,[-.24,-.38,1.17],[.34,-.16,1.04],[-.40,-.50,-.77]),
            (1.45,-10,-30,-8,-1,.008,-.040,[-.36,-.18,1.56],[.24,-.12,1.29],[-.40,-.18,.90]),
            (1.65,25,52,25,6,-.105,-.057,[-.10,-.49,1.08],[.40,.03,1.12],[-.60,-.44,-.67]),
            (1.92,28,55,27,7.5,-.115,-.058,[-.04,-.44,1.015],[.40,.03,1.10],[-.60,-.44,-.67]),
            (2.18,28,55,27,7.5,-.115,-.058,[-.04,-.44,1.015],[.40,.03,1.10],[-.60,-.44,-.67]),
            (3.15,15,18,8,0,-.085,-.040,[-.20,-.36,1.19],[.33,-.18,1.05],[-.40,-.50,-.77]),
            (3.40,15,18,8,0,-.085,-.040,[-.20,-.36,1.19],[.33,-.18,1.05],[-.40,-.50,-.77]),
            (4.10,10,12,5,0,-.060,-.025,[-.22,-.37,1.20],[.34,-.16,1.04],[-.40,-.50,-.77]),
            (5.55,0,0,0,0,0,0,[-.24,-.38,1.17],[.34,-.16,1.04],[-.40,-.50,-.77]),
            (6.,0,0,0,0,0,0,[-.24,-.38,1.17],[.34,-.16,1.04],[-.40,-.50,-.77])]
        phases=['guard','preparation','cut','follow','hold','recovery','hold','return','return','guard']
    if jianshu:
        # Authored from the IWUF elementary Pijian demonstration, not motion capture.
        # Lift into an open overhead preparation, then extend in front of the body.
        # The free arm leads upward; the torso stays three-quarter instead of twisting side-on.
        keys=[
            keys[0],keys[1],
            (1.18,-8,-16,-5,-1,.006,-.035,[-.40,-.05,1.88],[.24,-.12,1.40],[-.14,.98,.05]),
            (1.45,-8,-16,-5,-1,.006,-.035,[-.39,-.28,1.65],[.31,-.08,1.60],[-.10,-.50,.86]),
            (1.50,-3,-6,0,1,-.020,-.040,[-.37,-.38,1.55],[.36,-.12,1.62],[-.10,-.83,.55]),
            (1.56,6,10,6,3,-.065,-.050,[-.34,-.47,1.42],[.42,-.18,1.59],[-.10,-.985,.12]),
            (1.65,14,26,15,5,-.100,-.055,[-.30,-.54,1.27],[.45,-.22,1.56],[-.10,-.985,-.14]),
            (1.92,15,27,16,5,-.110,-.055,[-.30,-.55,1.25],[.45,-.22,1.56],[-.10,-.985,-.14]),
            (2.18,15,27,16,5,-.110,-.055,[-.30,-.55,1.25],[.45,-.22,1.56],[-.10,-.985,-.14]),
            (3.15,10,13,7,0,-.075,-.035,[-.28,-.43,1.28],[.38,-.18,1.28],[-.35,-.65,-.67]),
            (3.40,10,13,7,0,-.075,-.035,[-.28,-.43,1.28],[.38,-.18,1.28],[-.35,-.65,-.67]),
            (4.10,7,9,4,0,-.050,-.020,[-.25,-.40,1.22],[.34,-.16,1.10],[-.40,-.50,-.77]),
            keys[-2],keys[-1]]
        phases=['guard','preparation','preparation','cut','cut','cut','follow','hold','recovery','hold','return','return','guard']
    if routine_spec:
        keys=routine_spec['keys'];phases=routine_spec['phases']
        if len(phases)!=len(keys)-1 or keys[0][0]!=0 or keys[-1][0]!=6:
            raise ValueError('Routine keys must cover six seconds with outgoing phase labels')
    frame_count=180 if return_to_guard else 120
    scene=bpy.context.scene; scene.frame_start=1; scene.frame_end=frame_count; scene.render.fps=30
    records=[];previous_hand_q=None
    for frame in range(1,frame_count+1):
        seconds=(frame-1)/30
        segment=next((i for i in range(len(keys)-1) if keys[i][0]<=seconds<=keys[i+1][0]),len(keys)-2)
        a,b=keys[segment],keys[segment+1]
        raw=(seconds-a[0])/(b[0]-a[0])
        u=float(smooth(raw))
        values=[a[k]+(b[k]-a[k])*u for k in range(1,7)]
        if power and phases[segment]=='cut':
            for index,lead in [(0,.78),(1,.90),(4,.82),(5,.82)]:
                lead_u=float(smooth(raw/lead))
                values[index]=a[index+1]+(b[index+1]-a[index+1])*lead_u
        pyaw,tyaw,hyaw,lean,offset_y,offset_z=values
        qp=Quaternion((0,0,1),math.radians(pyaw))
        qt=Quaternion((0,0,1),math.radians(tyaw))@Quaternion((1,0,0),math.radians(lean))
        qh=Quaternion((0,0,1),math.radians(hyaw))@Quaternion((1,0,0),math.radians(lean*.45))
        step=float(smooth((seconds-(1.10 if power else 1.22))/(.55 if power else .72)))
        if return_to_guard:step*=1-float(smooth((seconds-(3.40 if power else 4.10))/(2.10 if power else 1.40)))
        sway_seconds=min(seconds,4.) if return_to_guard else seconds
        offset=Vector((.015*step-.01*math.sin(math.pi*sway_seconds/4)**2,offset_y,offset_z))
        tp=lambda point:support+qp@(Vector(point)-support)+offset
        torso_origin=tp(j['spine']); tt=lambda point:torso_origin+qt@(Vector(point)-j['spine'])
        head_origin=tt(j['head']); th=lambda point:head_origin+qh@(Vector(point)-j['head'])
        desired={}
        def setbone(name,start,end,q=None):
            rest=bones[name]
            if q is None:q=(rest.tail_local-rest.head_local).rotation_difference(end-start)@rest.matrix_local.to_quaternion()
            desired[name]=Matrix.LocRotScale(start,q,Vector((1,1,1)))
        for name,start,end,_ in specs[:5]:
            transform,q=(tp,qp) if name=='pelvis' else ((th,qh) if name=='head' else (tt,qt))
            setbone(name,transform(j[start]),transform(j[end]),q@bones[name].matrix_local.to_quaternion())
        lift=.075*math.sin(math.pi*step);leg_errors={}
        for side in ['R','L']:
            hip=tp(j['hip.'+side]); foot_yaw=math.radians((8 if side=='R' else 15)*step)
            fq=Quaternion((0,0,1),foot_yaw)
            if side=='R': ankle=support+fq@(j['ankle.R']-support)
            else:
                step_x=routine_spec.get('step_x',.020) if routine_spec else .020
                step_y=routine_spec.get('step_y',-.170) if routine_spec else -.170
                ankle=j['ankle.L']+Vector((step_x*step,step_y*step,lift))
            knee,actual=base.two_bone(hip,hip+qp@Vector((0,-.7,-.4)),ankle,lengths['thigh.'+side],lengths['shin.'+side])
            leg_errors[side]=(actual-ankle).length
            setbone('thigh.'+side,hip,knee);setbone('shin.'+side,knee,actual)
            setbone('foot.'+side,actual,actual+fq@(j['toe.'+side]-j['ankle.'+side]),fq@bones['foot.'+side].matrix_local.to_quaternion())
        source_axis=Vector(a[9]).normalized(); target_axis=Vector(b[9]).normalized()
        axis=Quaternion().slerp(source_axis.rotation_difference(target_axis),u)@source_axis
        wrist_bend=0.;right_wrist_error=0.;blade_aim_error=0.
        for side,k in [('R',7),('L',8)]:
            shoulder=tt(j['shoulder.'+side]); wrist_local=Vector(a[k]).lerp(Vector(b[k]),u)
            pole_local=Vector((-.48,-.10,1.23)) if side=='R' else Vector((.43,.04,1.22))
            if jianshu:
                new_pole=Vector((-.49,.02,1.90)) if side=='R' else Vector((.49,.04,1.56))
                if routine_spec and side=='R':new_pole=Vector(routine_spec.get('right_pole',new_pole))
                if side=='L':
                    low_elbow=float(smooth((seconds-1.45)/.20))*(1-float(smooth((seconds-3.40)/.70)))
                    new_pole=new_pole.lerp(Vector((.48,-.01,1.24)),low_elbow)
                pole_weight=float(smooth((seconds-.35)/.83))*(1-float(smooth((seconds-3.40)/2.15)))
                pole_local=pole_local.lerp(new_pole,pole_weight)
            elbow,wrist=base.two_bone(shoulder,tt(pole_local),tt(wrist_local),lengths['upper_arm.'+side],lengths['forearm.'+side])
            if side=='R':right_wrist_error=(wrist-tt(wrist_local)).length
            setbone('upper_arm.'+side,shoulder,elbow);setbone('forearm.'+side,elbow,wrist)
            forearm=(wrist-elbow).normalized(); direction=forearm
            if side=='R':
                blade=(qt@axis).normalized()
                direction=(forearm-blade*forearm.dot(blade)).normalized()
                requested_bend=math.degrees(math.acos(max(-1,min(1,forearm.dot(direction)))))
                if requested_bend>55:
                    direction=Quaternion().slerp(forearm.rotation_difference(direction),55/requested_bend)@forearm
                basis=base.grip_basis(direction,blade)
                q=basis.to_quaternion()@rest_hand.to_quaternion().inverted()@bones['hand.R'].matrix_local.to_quaternion()
                if previous_hand_q is not None:
                    angle=previous_hand_q.rotation_difference(q).angle
                    angle=min(angle,2*math.pi-angle)
                    cap=60 if jianshu else (35 if power else 18)
                    if angle>math.radians(cap):q=previous_hand_q.slerp(q,math.radians(cap)/angle)
                previous_hand_q=q.copy()
                direction=q@bones['hand.R'].matrix_local.to_quaternion().inverted()@(j['hand_end.R']-j['wrist.R']).normalized()
                wrist_bend=math.degrees(math.acos(max(-1,min(1,forearm.dot(direction)))))
                actual_blade=q@bones['hand.R'].matrix_local.to_quaternion().inverted()@(rest_hand@Vector((0,0,1)))
                blade_aim_error=math.degrees(math.acos(max(-1,min(1,actual_blade.normalized().dot(blade)))))
            else:q=(j['hand_end.L']-j['wrist.L']).rotation_difference(direction)@bones['hand.L'].matrix_local.to_quaternion()
            setbone('hand.'+side,wrist,wrist+direction*lengths['hand.'+side],q)
        follow=(-6*math.sin(math.pi*float(smooth((seconds-1.35)/.90)))
                +2*math.sin(math.pi*float(smooth((seconds-2.25)/1.25))))
        if return_to_guard:follow-=1.8*math.sin(math.pi*float(smooth((seconds-4.10)/1.50)))
        if power:
            follow=(-9*math.sin(math.pi*float(smooth((seconds-1.47)/.65)))
                    +3*math.sin(math.pi*float(smooth((seconds-2.08)/.90)))
                    -1.8*math.sin(math.pi*float(smooth((seconds-3.40)/2.10))))
        for name,start,end,_ in specs:
            if name.startswith('skirt.'):
                sign=1 if name.endswith('R') else -1
                q=qp@Quaternion((0,0,1),math.radians(follow*.45))@Quaternion((0,1,0),math.radians(follow*.15*sign))
                origin=tp(j[start])
            elif name=='ponytail':
                q=qh@Quaternion((0,0,1),math.radians(follow))@Quaternion((1,0,0),math.radians(follow*.4))
                origin=th(j[start])
            else:continue
            setbone(name,origin,origin+q@(j[end]-j[start]),q@bones[name].matrix_local.to_quaternion())
        for name,_,_,parent in specs:
            rest=bones[name].matrix_local
            basis=rest.inverted()@bones[parent].matrix_local@desired[parent].inverted()@desired[name] if parent else rest.inverted()@desired[name]
            pb=arm.pose.bones[name];pb.location,pb.rotation_quaternion,pb.scale=basis.decompose()
            for channel in ['location','rotation_quaternion','scale']:pb.keyframe_insert(channel,frame=frame)
        scene.frame_set(frame);bpy.context.view_layer.update()
        error=max((arm.pose.bones[n].head-desired[n].translation).length for n,*_ in specs)
        records.append({'frame':frame,'seconds':seconds,'pelvis_yaw':pyaw,'torso_yaw':tyaw,'head_yaw':hyaw,
                        'left_step_lift':lift,'leg_ik_target_errors':leg_errors,'wrist_bend_degrees':wrist_bend,'max_bone_head_error':error,
                        'right_wrist_target_error_m':right_wrist_error,'blade_aim_error_degrees':blade_aim_error,
                        'right_wrist_world':list(desired['hand.R'].translation),
                        'left_wrist_world':list(desired['hand.L'].translation),
                        'left_ankle_world':list(desired['foot.L'].translation),
                        'blade_axis_world':list(actual_blade.normalized()),
                        'phase': phases[segment]})
    scene.frame_set(1)
    projection=world_to_camera_view(scene,scene.camera,support)
    return {'frames':records,'frame_count':frame_count,'fps':30,'duration_seconds':frame_count/30,
            'single_shot_not_loop':True,'support_reference_rest':list(support),
            'returns_to_initial_guard':return_to_guard,
            'timing_profile':motion_profile,
            'phase_keys':[{'seconds':key[0],'phase':phases[min(i,len(phases)-1)]} for i,key in enumerate(keys)],
            'ground_anchor_source_pixels':[projection.x*1000,(1-projection.y)*1000],
            'max_bone_head_error':max(r['max_bone_head_error'] for r in records),
            'max_leg_ik_target_error':max(max(r['leg_ik_target_errors'].values()) for r in records),
            'max_wrist_bend_degrees':max(r['wrist_bend_degrees'] for r in records)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True); parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--config',type=Path); parser.add_argument('--mode',choices=['color','build','render'],default='color')
    parser.add_argument('--palette',choices=['original','warm'],default='warm')
    parser.add_argument('--start-frame',type=int);parser.add_argument('--end-frame',type=int)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not args.input.is_absolute() or not args.out.is_absolute() or args.out.exists(): raise ValueError('Absolute input and new output required')
    args.out.mkdir(parents=True); bpy.ops.wm.open_mainfile(filepath=str(args.input))
    scene=bpy.context.scene; scene.render.threads_mode='FIXED'; scene.render.threads=4
    if args.mode=='render':
        start=args.start_frame if args.start_frame is not None else scene.frame_start
        end=args.end_frame if args.end_frame is not None else scene.frame_end
        if not scene.frame_start<=start<=end<=scene.frame_end:raise ValueError('Render range must stay within the saved shot')
        for frame in range(start,end+1):
            scene.frame_set(frame); scene.render.filepath=str(args.out/f'frame-{frame:04d}.png'); bpy.ops.render.render(write_still=True)
        return
    report={'source_blend':str(args.input),'new_cloud_calls':0,'source_texture_pixels_modified':False,'geometry_modified':False,'palette':args.palette}
    if args.mode=='build':
        if not args.config:parser.error('Build requires source landmarks')
        config=json.loads(args.config.read_text());base=helper('build_fullbody_turn')
        report['left_hand_weights']=stabilize_left_hand(config)
        if args.palette=='warm':report['materials']=warm_materials()
        report['motion']=animate_phrase(bpy.data.objects['JiangRig'],config,base)
        bpy.ops.wm.save_as_mainfile(filepath=str(args.out/'jiang-sword-phrase.blend'))
        (args.out/'phrase-report.json').write_text(json.dumps(report,indent=2)+'\n')
        for frame in [1,35,44,51,58,78,106,120]:
            scene.frame_set(frame);scene.render.filepath=str(args.out/f'pose-{frame:04d}.png');bpy.ops.render.render(write_still=True)
        print('JIANG_PHRASE_DONE',args.out,flush=True);return
    if args.palette=='warm': report['materials']=warm_materials()
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.out/'jiang-warm-look.blend'))
    (args.out/'color-report.json').write_text(json.dumps(report,indent=2)+'\n')
    for frame in [1,30,60]:
        scene.frame_set(frame); scene.render.filepath=str(args.out/f'pose-{frame:04d}.png'); bpy.ops.render.render(write_still=True)
    scene.frame_set(1); camera=scene.camera
    base=helper('build_fullbody_turn')
    base.camera_at(camera,[-.65,-1,.12],[0,-.03,1.77]); camera.data.ortho_scale=.94
    scene.render.filepath=str(args.out/'face.png'); bpy.ops.render.render(write_still=True)
    print('JIANG_COLOR_DONE',args.out,flush=True)


if __name__=='__main__': main()
