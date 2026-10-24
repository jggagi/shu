#!/usr/bin/env python3
"""Local Blender full-body rig/turn study; no cloud calls or game asset writes.

Blender --background --disable-autoexec --python this.py -- --input MODEL.glb
  --out NEW_DIRECTORY --config LANDMARKS.json [--mode inspect|build|render]

The hand replacement and approximate analytic weights are study-specific. They
are not an automatic production retopology or general-purpose rigging system.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, math, shutil, sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def smooth(t):
    t = min(1., max(0., t))
    return t*t*(3.-2.*t)


def unit(value):
    return Vector(value).normalized()


def rz(angle):
    return Matrix.Rotation(angle, 3, 'Z')


def two_bone(a, pole, end, l1, l2):
    delta = end-a
    d = max(abs(l1-l2)+1e-6, min(l1+l2-1e-6, delta.length))
    axis = delta.normalized()
    projection = pole-a-axis*(pole-a).dot(axis)
    if projection.length < 1e-7:
        projection = axis.cross(Vector((1, 0, 0)))
    projection.normalize()
    x = (l1*l1-l2*l2+d*d)/(2*d)
    return a+axis*x+projection*math.sqrt(max(0., l1*l1-x*x)), a+axis*d


def studio(scene, target, scale, resolution=1000):
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.eevee.taa_render_samples = 32
    scene.render.resolution_x = scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.film_transparent = True
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 4
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    world = bpy.data.worlds.new('Jiang turn neutral world')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.65, .65, .65, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = .35
    scene.world = world
    target = Vector(target)
    for label, pos, power, size in [
        ('Key', (-3, -4, 5), 420, 4),
        ('Fill', (4, -2, 3), 220, 4),
        ('Rim', (1, 3, 4), 340, 3)]:
        data = bpy.data.lights.new(label, 'AREA')
        data.energy = power
        data.shape = 'DISK'
        data.size = size
        light = bpy.data.objects.new(label, data)
        scene.collection.objects.link(light)
        light.location = Vector(pos)
        light.rotation_euler = (target-light.location).to_track_quat('-Z', 'Y').to_euler()
    data = bpy.data.cameras.new('ReviewCamera')
    data.type = 'ORTHO'
    data.ortho_scale = scale
    camera = bpy.data.objects.new('ReviewCamera', data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def camera_at(camera, direction, target):
    target = Vector(target)
    camera.location = target+Vector(direction).normalized()*7
    camera.rotation_euler = (target-camera.location).to_track_quat('-Z', 'Y').to_euler()


def import_model(path, yaw):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.use_scripts_auto_execute = False
    bpy.ops.import_scene.gltf(filepath=str(path))
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if not objects:
        raise ValueError('No imported mesh')
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = 'JiangFullbody'
    # Bake imported placement and one documented front-axis calibration.
    matrix = Matrix.Rotation(math.radians(yaw), 4, 'Z') @ obj.matrix_world
    obj.data.transform(matrix)
    obj.matrix_world = Matrix.Identity(4)
    coords = np.array([v.co[:] for v in obj.data.vertices], dtype=np.float64)
    low, high = coords.min(0), coords.max(0)
    factor = 2.1/(high[2]-low[2])
    center = np.array([(low[0]+high[0])/2, (low[1]+high[1])/2, low[2]])
    coords = (coords-center)*factor
    obj.data.vertices.foreach_set('co', coords.astype(np.float32).ravel())
    obj.data.update()
    return obj, {'rotation_z_degrees': yaw, 'uniform_scale': float(factor),
                 'translation_before_scale': (-center).tolist(),
                 'vertices': len(obj.data.vertices), 'polygons': len(obj.data.polygons)}


def inspect(obj, out):
    scene = bpy.context.scene
    camera = studio(scene, (0, 0, 1.05), 2.55)
    for name, direction in [('front', (0, -1, .02)), ('quarter', (-.7, -1, .08)),
                            ('side', (-1, 0, .02)), ('back', (0, 1, .02))]:
        camera_at(camera, direction, (0, 0, 1.05))
        scene.render.filepath = str(out/(name+'.png'))
        bpy.ops.render.render(write_still=True)
    coords = np.array([v.co[:] for v in obj.data.vertices])
    rows = []
    for z in np.arange(.05, 2.11, .1):
        band = coords[abs(coords[:, 2]-z) < .025]
        if len(band):
            rows.append({'z': round(float(z), 3), 'count': len(band),
                         'min': band.min(0).tolist(), 'max': band.max(0).tolist()})
    (out/'bands.json').write_text(json.dumps(rows, indent=2)+'\n')
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'inspection.blend'))


def rest_specs(config):
    j = {k: Vector(v) for k, v in config['joints'].items()}
    specs = [
        ('pelvis', 'pelvis', 'spine', None),
        ('spine', 'spine', 'chest', 'pelvis'),
        ('chest', 'chest', 'neck', 'spine'),
        ('neck', 'neck', 'head', 'chest'),
        ('head', 'head', 'head_top', 'neck')]
    for side in ['R', 'L']:
        specs += [(f'upper_arm.{side}', f'shoulder.{side}', f'elbow.{side}', 'chest'),
                  (f'forearm.{side}', f'elbow.{side}', f'wrist.{side}', f'upper_arm.{side}'),
                  (f'hand.{side}', f'wrist.{side}', f'hand_end.{side}', f'forearm.{side}'),
                  (f'thigh.{side}', f'hip.{side}', f'knee.{side}', 'pelvis'),
                  (f'shin.{side}', f'knee.{side}', f'ankle.{side}', f'thigh.{side}'),
                  (f'foot.{side}', f'ankle.{side}', f'toe.{side}', f'shin.{side}')]
    for name in ['front.R', 'front.L', 'back.R', 'back.L']:
        specs.append(('skirt.'+name, 'skirt_top.'+name, 'skirt_end.'+name, 'pelvis'))
    specs.append(('ponytail', 'hair_top', 'hair_end', 'head'))
    return j, specs


def make_rig(j, specs):
    data = bpy.data.armatures.new('Jiang study skeleton')
    arm = bpy.data.objects.new('JiangRig', data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name, a, b, parent in specs:
        bone = data.edit_bones.new(name)
        bone.head, bone.tail = j[a], j[b]
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.show_in_front = True
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return arm


def bind_single(obj, arm, bone):
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1., 'REPLACE')
    modifier = obj.modifiers.new('Fixed grip skinning', 'ARMATURE')
    modifier.object = arm
    obj.parent = arm


def remove_right_hand(obj, wrist, end, radius):
    import bmesh
    direction = (end-wrist).normalized()
    skin = brown_vertices(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    removed = [v for v in bm.verts if skin[v.index] and (v.co-wrist).dot(direction) > -.010
               and ((v.co-wrist)-direction*(v.co-wrist).dot(direction)).length < radius
               and (v.co-wrist).length < .23]
    count = len(removed)
    bmesh.ops.delete(bm, geom=removed, context='VERTS')
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return count


def assign_weights(obj, arm, j, specs, config):
    coords = np.array([v.co[:] for v in obj.data.vertices], dtype=np.float64)
    names = [s[0] for s in specs]
    index = {n:i for i,n in enumerate(names)}
    base = np.zeros((len(coords), len(names)), dtype=np.float64)
    for name,a,b,_ in specs:
        start,end = np.array(j[a]),np.array(j[b])
        vector = end-start
        t = np.clip(np.sum((coords-start)*vector,axis=1)/np.sum(vector*vector),0,1)
        d = np.linalg.norm(coords-start-t[:,None]*vector,axis=1)
        base[:,index[name]] = 1./(d+.065)**4
    x,z = coords[:,0],coords[:,2]
    ramp = lambda v: np.clip(v,0,1)**2*(3-2*np.clip(v,0,1))
    arm_mix = ramp((abs(x)-.175)/.19)*ramp((z-.80)/.23)
    weights = np.zeros_like(base)
    torso_names = ['pelvis','spine','chest','neck']
    torso = base[:,[index[n] for n in torso_names]]
    torso /= torso.sum(1)[:,None]
    for k,n in enumerate(torso_names):weights[:,index[n]] = torso[:,k]*(1-arm_mix)
    # Continuous shoulder/elbow transition; no binary seams through sleeves.
    for side in ['R','L']:
        mask = x<0 if side=='R' else x>=0
        ids = [index[n+'.'+side] for n in ['upper_arm','forearm','hand']]
        values=base[:,ids]; values/=values.sum(1)[:,None]
        weights[:,ids]=values*(arm_mix*mask)[:,None]
    lower = z<j['pelvis'].z
    leg_mix = ramp((.46-z)/.22)
    leg_mix *= 1-ramp((abs(x)-.22)/.12)
    leg_mix[z<.24]=1
    body_mix=1-arm_mix
    weights[lower]=0
    weights[lower,index['pelvis']] = body_mix[lower]*(1-leg_mix[lower])
    for side in ['R','L']:
        mask = lower & (x<0 if side=='R' else x>=0)
        ids=[index[n+'.'+side] for n in ['thigh','shin','foot']]
        values=base[:,ids];values/=values.sum(1)[:,None]
        weights[:,ids]+=values*(body_mix*leg_mix*mask)[:,None]
        ids=[index[n+'.'+side] for n in ['upper_arm','forearm','hand']]
        values=base[:,ids];values/=values.sum(1)[:,None]
        weights[:,ids]+=values*(arm_mix*mask)[:,None]
    missing=weights.sum(1)<1e-12
    weights[missing,index['pelvis']]=1
    weights/=weights.sum(1)[:,None]
    if not np.isfinite(weights).all():raise ValueError('Nonfinite skin weights')
    for name in names:
        group=obj.vertex_groups.new(name=name)
        values=np.round(weights[:,index[name]]*4095).astype(np.int32)
        for value in np.unique(values):
            if value:group.add(np.flatnonzero(values==value).tolist(),float(value)/4095,'REPLACE')
    modifier=obj.modifiers.new('Jiang continuous study weights','ARMATURE')
    modifier.object=arm
    modifier.use_deform_preserve_volume=True
    obj.parent=arm
    return {'method':'Continuous shoulder and elbow masks; conservative pelvis-bound robe with smooth visible lower-leg blend',
            'unassigned_fallback_vertices':int(missing.sum()),'weight_quantization':4095,
            'cloth_simulation':False,'ponytail':'Rigid approved head/hair mesh'}


def grip_basis(direction, blade):
    y = -direction.normalized()
    z = Vector(blade)-y*Vector(blade).dot(y)
    z.normalize()
    x = y.cross(z).normalized()
    return Matrix((x, y, z)).transposed()


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = .48
    return mat


def brown_vertices(obj):
    """Identify warm hair pixels for a reviewed crop, preserving source texture."""
    material = obj.data.materials[0]
    shader = material.node_tree.nodes.get('Principled BSDF')
    link = shader.inputs['Base Color'].links[0]
    image = link.from_node.image
    width,height = image.size
    pixels = np.empty(width*height*4,dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape((height,width,4))
    uv = np.empty(len(obj.data.loops)*2,dtype=np.float32)
    obj.data.uv_layers.active.data.foreach_get('uv',uv)
    uv = uv.reshape((-1,2))
    color = pixels[(uv[:,1]*height).astype(int).clip(0,height-1),
                   (uv[:,0]*width).astype(int).clip(0,width-1),:3]
    brown = (color[:,0]>color[:,2]*1.10) & (color[:,0]>color[:,1]*1.025)
    ids = np.empty(len(obj.data.loops),dtype=np.int32)
    obj.data.loops.foreach_get('vertex_index',ids)
    result = np.zeros(len(obj.data.vertices),dtype=bool)
    result[ids[brown]] = True
    return result


def reuse_approved_head(body, config):
    """Keep the exact approved head/hair surface; crop only bust clothing."""
    import bmesh
    old_brown=brown_vertices(body)
    bm=bmesh.new();bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    remove=[v for v in bm.verts if v.co.z>config['body_head_cut_z'] or
            (v.co.z>config['body_hair_cut_z'] and old_brown[v.index])]
    removed=len(remove)
    bmesh.ops.delete(bm,geom=remove,context='VERTS')
    bm.to_mesh(body.data);bm.free()
    previous=set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=config['approved_head_glb'])
    head=[o for o in bpy.context.scene.objects if o not in previous and o.type=='MESH'][0]
    head.name='JiangApprovedHead'
    # glTF imports may retain a Y-up-to-Z-up object matrix. Crop in world Z.
    head.data.transform(Matrix.Rotation(math.radians(45),4,'Z') @ head.matrix_world)
    head.matrix_world=Matrix.Identity(4)
    hair=brown_vertices(head)
    # Crop in original bust-local coordinates before applying rigid placement.
    bm=bmesh.new();bm.from_mesh(head.data);bm.verts.ensure_lookup_table()
    remove=[v for v in bm.verts if v.co.z<config['head_source_cut_z'] and
            not (hair[v.index] and v.co.z>config['hair_source_min_z'] and v.co.y>.035)]
    bmesh.ops.delete(bm,geom=remove,context='VERTS')
    bm.to_mesh(head.data);bm.free()
    transform=(Matrix.Translation(config['head_translation']) @
               Matrix.Scale(config['head_uniform_scale'],4) @ head.matrix_world)
    head.data.transform(transform);head.matrix_world=Matrix.Identity(4)
    reused_count=len(head.data.vertices)
    # Close the small neck seam under the retained head with a smooth bridge.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=16,
        location=config.get('neck_bridge_center',[0,-.10,1.60]))
    bridge=bpy.context.object
    bridge.name='Neck seam bridge'
    bridge.scale=(.058,.050,.105)
    bridge.data.materials.append(material('Neck warm ivory',config.get('skin_color',[.76,.64,.56])))
    for p in bridge.data.polygons:p.use_smooth=True
    bpy.ops.object.select_all(action='DESELECT')
    bridge.select_set(True);head.select_set(True)
    bpy.context.view_layer.objects.active=head
    bpy.ops.object.join()
    return head,{'source':config['approved_head_glb'],'scale':config['head_uniform_scale'],
                 'rotation_z_degrees':45,'translation':config['head_translation'],
                 'body_head_vertices_removed':removed,'reused_vertices':reused_count,
                 'neck_seam_bridge_vertices':len(head.data.vertices)-reused_count,
                 'source_texture_pixels_unchanged':True,
                 'surface_change':'Only bust lower crop; surviving face/hair vertices transformed uniformly'}


def pose_animation(arm, j, specs, rest_hand_basis, config):
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 1, 60
    bones = arm.data.bones
    length = {n:(j[b]-j[a]).length for n,a,b,_ in specs}
    pivot = j['ankle.R'].copy()
    pivot.z = 0
    metrics = []
    for frame in range(1, 61):
        t = (frame-1)/59
        theta = math.radians(config.get('turn_degrees',115))*smooth((t-.14)/.70)
        rotation = rz(theta)
        center = pivot+rotation@(-pivot)
        center.z = -.035*math.sin(math.pi*smooth((t-.1)/.8))**2
        transform = lambda p: center+rotation@Vector(p)
        desired = {}
        def setbone(name, head, tail, orientation=None):
            rest = bones[name]
            if orientation is None:
                old = rest.tail_local-rest.head_local
                orientation = old.rotation_difference(tail-head)@rest.matrix_local.to_quaternion()
            desired[name] = Matrix.LocRotScale(head, orientation, Vector((1,1,1)))
        for name,a,b,parent in specs[:5]:
            setbone(name, transform(j[a]), transform(j[b]), Quaternion((0,0,1),theta)@bones[name].matrix_local.to_quaternion())
        # Fixed support ankle and an explicitly lifted, arcing left step.
        foot_lift = .075*math.sin(math.pi*smooth((t-.18)/.60))
        for side in ['R','L']:
            hip = transform(j['hip.'+side])
            if side == 'R':
                ankle = j['ankle.R'].copy()
            else:
                step_angle = math.radians(config.get('turn_degrees',115))*smooth((t-.18)/.60)
                ankle = pivot+rz(step_angle)@(j['ankle.L']-pivot)
                ankle.z += foot_lift
            pole = hip+rotation@Vector((0,-.7,-.4))
            knee, actual_ankle = two_bone(hip,pole,ankle,length['thigh.'+side],length['shin.'+side])
            setbone('thigh.'+side,hip,knee)
            setbone('shin.'+side,knee,actual_ankle)
            footq = Quaternion((0,0,1),theta)@bones['foot.'+side].matrix_local.to_quaternion()
            toe = actual_ankle+rotation@(j['toe.'+side]-j['ankle.'+side])
            setbone('foot.'+side,actual_ankle,toe,footq)
        # Right hand maintains a single grip throughout; left arm balances.
        for side in ['R','L']:
            shoulder = transform(j['shoulder.'+side])
            target = transform(config['posed_wrist.'+side])
            pole = transform(config['posed_elbow_pole.'+side])
            elbow,wrist = two_bone(shoulder,pole,target,length['upper_arm.'+side],length['forearm.'+side])
            setbone('upper_arm.'+side,shoulder,elbow)
            setbone('forearm.'+side,elbow,wrist)
            direction = (wrist-elbow).normalized()
            if side == 'R':
                basis = grip_basis(direction,rotation@Vector(config['posed_blade_axis']))
                q = basis.to_quaternion()@rest_hand_basis.to_quaternion().inverted()@bones['hand.R'].matrix_local.to_quaternion()
            else:
                q = (j['hand_end.L']-j['wrist.L']).rotation_difference(direction)@bones['hand.L'].matrix_local.to_quaternion()
            setbone('hand.'+side,wrist,wrist+direction*length['hand.'+side],q)
        for name,a,b,parent in specs:
            if name.startswith('skirt.'):
                lag = math.radians(-5)*math.sin(math.pi*t)
                q = Quaternion((0,0,1),theta+lag)@bones[name].matrix_local.to_quaternion()
                h = transform(j[a]); v=q@bones[name].matrix_local.to_quaternion().inverted()@(j[b]-j[a])
                setbone(name,h,h+v,q)
            elif name == 'ponytail':
                lag = math.radians(-7)*math.sin(math.pi*t)**2
                q=Quaternion((0,0,1),theta+lag)@bones[name].matrix_local.to_quaternion()
                h=transform(j[a]);v=q@bones[name].matrix_local.to_quaternion().inverted()@(j[b]-j[a])
                setbone(name,h,h+v,q)
        for name,a,b,parent in specs:
            rest=bones[name].matrix_local
            if parent:
                basis=rest.inverted()@bones[parent].matrix_local@desired[parent].inverted()@desired[name]
            else:
                basis=rest.inverted()@desired[name]
            loc,rot,scale=basis.decompose()
            pb=arm.pose.bones[name]
            pb.location, pb.rotation_quaternion, pb.scale=loc,rot,scale
            pb.keyframe_insert('location',frame=frame)
            pb.keyframe_insert('rotation_quaternion',frame=frame)
            pb.keyframe_insert('scale',frame=frame)
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        error=max((arm.pose.bones[n].head-desired[n].translation).length for n,*_ in specs)
        metrics.append({'frame':frame,'body_yaw_degrees':math.degrees(theta),
                        'left_step_lift':foot_lift,'max_bone_head_error':error,
                        'support_ankle':list(arm.pose.bones['foot.R'].head)})
    scene.frame_set(1)
    return metrics


def build(obj, out, config):
    j,specs = rest_specs(config)
    head,head_report = reuse_approved_head(obj,config)
    removed = remove_right_hand(obj,j['wrist.R'],j['hand_end.R'],config['hand_cut_radius'])
    arm = make_rig(j,specs)
    weights=assign_weights(obj,arm,j,specs,config)
    bind_single(head,arm,'head')
    grip=module(Path(__file__).with_name('grip_geometry.py'),'jiang_grip')
    skin=material('Grip skin warm ivory',config.get('skin_color',[.74,.59,.48]))
    hand,sword,grip_meta=grip.build_grip('JiangRightGrip',skin,scale=config.get('grip_scale',1.0))
    rest_direction=(j['hand_end.R']-j['wrist.R']).normalized()
    basis=grip_basis(rest_direction,config['rest_blade_axis'])
    center=j['wrist.R']-basis@Vector(grip_meta['wrist_anchor'])
    for part in [hand,sword]:
        for v in part.data.vertices:
            v.co=center+basis@v.co
        bind_single(part,arm,'hand.R')
    # Both meshes use the same rest-space grip center and one rigid hand bone.
    metrics=pose_animation(arm,j,specs,basis,config)
    scene=bpy.context.scene
    camera=studio(scene,config.get('camera_target',[0,0,1.05]),config.get('camera_scale',2.65))
    camera_at(camera,config.get('camera_direction',[-.65,-1,.16]),config.get('camera_target',[0,0,1.05]))
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'jiang-fullbody-turn.blend'))
    images=[{'name':i.name,'size':list(i.size),'packed':bool(i.packed_file)} for i in bpy.data.images if i.type!='RENDER_RESULT']
    report={'status':'BUILT_AWAITING_VISUAL_REVIEW','approved_head_reuse':head_report,'mesh_source_hand_vertices_removed':removed,
            'weights':weights,'bones':len(specs),'grip':grip_meta,'images':images,'frames':metrics,
            'frame_count':60,'fps':30,'duration_seconds':2,'single_action_not_loop':True,
            'source_geometry_modified_for_rig':True,'source_textures_pixels_modified':False,
            'max_bone_head_error':max(x['max_bone_head_error'] for x in metrics)}
    (out/'rig-report.json').write_text(json.dumps(report,indent=2)+'\n')
    for frame in [1,15,30,45,60]:
        scene.frame_set(frame)
        scene.render.filepath=str(out/f'pose-{frame:04d}.png')
        bpy.ops.render.render(write_still=True)
    scene.frame_set(1)
    for name,direction in [('front',(0,-1,.02)),('side',(-1,0,.02)),('back',(0,1,.02))]:
        camera_at(camera,direction,config.get('camera_target',[0,-.03,1.07]))
        scene.render.filepath=str(out/f'static-{name}.png')
        bpy.ops.render.render(write_still=True)
    camera_at(camera,config.get('camera_direction',[-.65,-1,.16]),config.get('camera_target',[0,-.03,1.07]))


def render(args):
    if args.out.exists():
        raise ValueError('Refusing existing frames directory')
    args.out.mkdir()
    bpy.ops.wm.open_mainfile(filepath=str(args.input))
    scene=bpy.context.scene
    for frame in range(1,61):
        scene.frame_set(frame)
        scene.render.filepath=str(args.out/f'frame-{frame:04d}.png')
        bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--config',type=Path)
    parser.add_argument('--yaw',type=float,default=0)
    parser.add_argument('--mode',choices=['inspect','build','render'],default='inspect')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not args.input.is_absolute() or not args.out.is_absolute():
        parser.error('Absolute input/output paths required')
    if args.mode=='render':
        render(args);return
    if args.out.exists():
        raise ValueError('Refusing to overwrite output')
    args.out.mkdir()
    obj,normalization=import_model(args.input,args.yaw)
    (args.out/'normalization.json').write_text(json.dumps(normalization,indent=2)+'\n')
    shutil.copy2(args.input,args.out/args.input.name)
    if args.mode=='inspect':inspect(obj,args.out)
    else:
        if not args.config:parser.error('Build requires calibrated config')
        shutil.copy2(args.config,args.out/'landmarks.json')
        build(obj,args.out,json.loads(args.config.read_text()))
    print('JIANG_FULLBODY_DONE',args.mode,str(args.out),flush=True)


if __name__=='__main__':main()
