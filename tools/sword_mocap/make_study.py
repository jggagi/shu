"""CMU subject 02 swordplay -> connected gray rig, GLB and fixed-camera RGBA frames.
Run in Blender 4.5.9. Input preserves human timing; no independent limb curves.
"""
import argparse, hashlib, importlib.util, json, math, sys, time
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector

def digest(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def load_module(name, path):
    spec=importlib.util.spec_from_file_location(name,path); module=importlib.util.module_from_spec(spec)
    sys.modules[name]=module; spec.loader.exec_module(module); return module

def material(name, color):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    b=m.node_tree.nodes.get('Principled BSDF'); b.inputs['Base Color'].default_value=(*color,1)
    b.inputs['Roughness'].default_value=.82; return m

def make_rig(specs, rest):
    arm=bpy.data.armatures.new('HumanMotionSkeleton'); obj=bpy.data.objects.new('HumanMotionRig',arm)
    bpy.context.collection.objects.link(obj); bpy.context.view_layer.objects.active=obj; obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT'); edits={}
    for spec in specs:
        name=spec['name']; b=arm.edit_bones.new(name)
        b.head=Vector(rest[name]['head']); b.tail=Vector(rest[name]['tail'])
        if name=='root': b.tail=b.head+Vector((0,0,.01))
        if (b.tail-b.head).length < 1e-7: raise RuntimeError('Zero bone '+name)
        b.align_roll(Vector((0,-1,0))); edits[name]=b
    for spec in specs:
        if spec.get('parent'): edits[spec['name']].parent=edits[spec['parent']]
    bpy.ops.object.mode_set(mode='OBJECT')
    for bone in obj.pose.bones: bone.rotation_mode='QUATERNION'
    return obj

def build_mesh(builder, rest, mats):
    # Connected research mannequin at the subject's proportions; clear joint anatomy.
    radius={'lfemur':.070,'rfemur':.070,'ltibia':.052,'rtibia':.052,
            'lhumerus':.048,'rhumerus':.048,'lradius':.038,'rradius':.038,
            'lfoot':.039,'rfoot':.039,'ltoes':.030,'rtoes':.030,
            'lhand':.041,'rhand':.041,'lwrist':.032,'rwrist':.032}
    for name,r in radius.items():
        a,b=Vector(rest[name]['head']),Vector(rest[name]['tail'])
        builder.segment(a,b,r,'body',name,radius_end=r*.85,sides=16,
                        profile=((0,1),(.2,1),(1,.85)))
        builder.ellipsoid(a,(r*1.02,)*3,'joint',name,segments=16,rings=10)
        builder.ellipsoid(b,(r*.88,)*3,'body',name,segments=16,rings=10)
    for name,r in [('lclavicle',.058),('rclavicle',.058),('lowerneck',.04),('upperneck',.035)]:
        builder.segment(Vector(rest[name]['head']),Vector(rest[name]['tail']),r,'body',name,sides=16)
    # Torso mass follows the same spine chain, with overlapping sections at actual joints.
    for name,rx,ry in [('lowerback',.132,.095),('upperback',.152,.102),('thorax',.166,.106)]:
        a,b=Vector(rest[name]['head']),Vector(rest[name]['tail']); q=(b-a).to_track_quat('Z','Y')
        builder.ellipsoid((a+b)*.5,(rx,ry,(b-a).length*.62+.025),'body',name,rotation=q,segments=24,rings=14)
    hips=Vector(rest['root']['head']);builder.ellipsoid(hips,(.135,.095,.100),'body','root',segments=24,rings=14)
    neck=Vector(rest['head']['head']); skull=neck+Vector((0,0,.025))
    builder.ellipsoid(skull,(.081,.074,.110),'body','head',segments=24,rings=16)
    # A nose identifies front/back without styling a final game character.
    builder.ellipsoid(skull+Vector((0,-.072,.005)),(.019,.020,.018),'joint','head',segments=12,rings=8)
    for x in [-.028,.028]:builder.ellipsoid(skull+Vector((x,-.067,.03)),(.006,.008,.005),'dark','head',segments=10,rings=6)
    # Compact closed fists: original finger DOFs remain in the rig; fingers are not reanimated.
    for side in ['l','r']:
        a,b=Vector(rest[side+'hand']['head']),Vector(rest[side+'hand']['tail'])
        builder.ellipsoid((a+b)*.5,(.041,.04,.035),'body',side+'hand',segments=16,rings=10)
    # Prop is rigidly parented to the captured right hand; sword markers were not captured.
    hand=(Vector(rest['rhand']['head'])+Vector(rest['rhand']['tail']))*.5
    axis=Vector((0,-1,0)); base=hand+axis*.08; tip=hand+axis*.93
    builder.segment(hand-axis*.075,base,.014,'dark','rhand',sides=12)
    builder.segment(base+Vector((-.066,0,0)),base+Vector((.066,0,0)),.012,'guard','rhand',sides=12)
    builder.segment(base,tip,.019,'steel','rhand',radius_end=.002,sides=4,
                    profile=((0,1),(.7,.9),(1,.1)))
    return hand,tip

def bake(arm, specs, rest, samples):
    scene=bpy.context.scene; scene.render.fps=60; scene.frame_start=0; scene.frame_end=len(samples)-1
    ad=arm.animation_data_create(); action=bpy.data.actions.new('SwordStudy');ad.action=action
    slot=action.slots.new('OBJECT',arm.name);ad.action_slot=slot
    restmat={b.name:b.matrix_local.copy() for b in arm.data.bones}; prev={};maximum=0
    for index,sample in enumerate(samples):
        scene.frame_set(index); desired={}
        for spec in specs:
            name=spec['name']; transform=sample['bones'][name]
            q=Quaternion(transform['rotation']) @ restmat[name].to_quaternion()
            desired[name]=Matrix.LocRotScale(Vector(transform['head']),q,Vector((1,1,1)))
        for spec in specs:
            name=spec['name']; p=arm.pose.bones[name];parent=spec.get('parent')
            basis=restmat[name].inverted() @ desired[name] if not parent else restmat[name].inverted() @ restmat[parent] @ desired[parent].inverted() @ desired[name]
            loc,q,scale=basis.decompose()
            if name in prev and prev[name].dot(q)<0:q.negate()
            prev[name]=q.copy();p.location=loc;p.rotation_quaternion=q;p.scale=Vector((1,1,1))
            p.keyframe_insert(data_path='location',frame=index,group=name)
            p.keyframe_insert(data_path='rotation_quaternion',frame=index,group=name)
        bpy.context.view_layer.update()
        for spec in specs:
            name=spec['name'];p=arm.pose.bones[name]; source=sample['bones'][name]
            maximum=max(maximum,(p.head-Vector(source['head'])).length)
            if name!='root':maximum=max(maximum,(p.tail-Vector(source['tail'])).length)
        if index%120==0:print('BAKE',index,'/',len(samples),'endpoint_error',maximum,flush=True)
    for layer in action.layers:
        for strip in layer.strips:
            bag=strip.channelbag(slot)
            if bag:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
    if maximum>.00005:raise RuntimeError('Rig bake differs from capture: '+str(maximum))
    scene.frame_set(0);bpy.context.view_layer.update();return maximum

def scene_setup():
    scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE_NEXT'
    scene.render.resolution_x=320;scene.render.resolution_y=320;scene.render.resolution_percentage=100
    scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG'
    scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.color_depth='8'
    scene.render.image_settings.compression=50;scene.view_settings.view_transform='Standard'
    scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.8,.8,.8,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
    target=Vector((0,0,.94));pos=Vector((-4,-6,3.2))
    camdata=bpy.data.cameras.new('StudyCamera');cam=bpy.data.objects.new('StudyCamera',camdata)
    bpy.context.collection.objects.link(cam);cam.location=pos;cam.rotation_euler=(target-pos).to_track_quat('-Z','Y').to_euler()
    camdata.type='ORTHO';camdata.ortho_scale=3.35;camdata.clip_start=.01;scene.camera=cam
    for name,pos,energy,size in [('Key',(-3,-4,6),420,5),('Fill',(4,2,4),180,5)]:
        data=bpy.data.lights.new(name,'AREA');light=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(light)
        light.location=pos;data.energy=energy;data.size=size;light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
    return {'position':list(cam.location),'target':list(target),'ortho':camdata.ortho_scale,'coordinate_system':'Blender Z up'},cam

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True);parser.add_argument('--mode',choices=['build','preview','render'],default='build')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);repo=args.repo;args.output.mkdir(parents=True,exist_ok=True)
    if args.mode in {'preview','render'} and (args.output/'study.blend').is_file():
        bpy.ops.wm.open_mainfile(filepath=str(args.output/'study.blend'))
        count=bpy.context.scene.frame_end+1
        indices=list(range(0,count,12)) if args.mode=='preview' else list(range(count))
        out=args.output/('preview' if args.mode=='preview' else 'frames');out.mkdir(exist_ok=True)
        rendered=0
        for i in indices:
            frame_path=out/f'frame-{i:04d}.png'
            if frame_path.is_file():
                import struct
                header=frame_path.read_bytes()[:24]
                if header[:8]!=b'\x89PNG\r\n\x1a\n' or struct.unpack('>II',header[16:24])!=(320,320):
                    raise RuntimeError('Invalid existing frame: '+str(frame_path))
                continue
            bpy.context.scene.frame_set(i);bpy.context.scene.render.filepath=str(frame_path)
            bpy.ops.render.render(write_still=True);rendered+=1
        print('NEW_RENDERED',rendered,flush=True)
        print('RENDERED',len(indices),'frames',flush=True);return
    converter=load_module('cmu_motion',repo/'tools/sword_mocap/cmu_motion.py')
    geometry=load_module('lab_geometry',repo/'tools/animation_lab/make_blender_demo.py')
    skeleton=converter.parse_asf(repo/'assets/data/sword_mocap/source/02.asf')
    # Converter metadata is read as its stable exported schema.
    data=converter.sample_file(repo/'assets/data/sword_mocap/source/02.asf',repo/'assets/data/sword_mocap/source/02_09.amc',stride=2)
    specs=data['bones'];samples=data['samples'];zero_channels={'root':(0,0,0,0,0,0)}
    zero_channels.update({b.name:tuple(0 for _ in b.dofs) for b in skeleton.bones if b.dofs})
    rest=converter.solve_frame(skeleton,converter.MotionFrame(1,zero_channels))
    # One rigid translation sets the stage origin; no per-frame root/feet correction.
    origin=Vector(samples[0]['bones']['root']['head']);origin.z=0
    ground=min(Vector(s['bones'][b]['tail']).z for s in samples for b in ['ltoes','rtoes'])-.034
    shift=origin+Vector((0,0,ground))
    for sample in samples:
        for pose in sample['bones'].values():
            pose['head']=list(Vector(pose['head'])-shift);pose['tail']=list(Vector(pose['tail'])-shift)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    mats={name:material(name,c) for name,c in {'body':(.56,.60,.59),'joint':(.43,.48,.47),'dark':(.14,.20,.19),'steel':(.64,.73,.74),'guard':(.35,.40,.39)}.items()}
    arm=make_rig(specs,rest);builder=geometry.MeshBuilder();grip,tip=build_mesh(builder,rest,mats)
    model=builder.mesh_object('GrayHuman',arm,mats)
    max_error=bake(arm,specs,rest,samples);camera,cam=scene_setup()
    art=repo/'assets/art/sword_mocap';art.mkdir(parents=True,exist_ok=True)
    scene=bpy.context.scene;scene.frame_set(0)
    if args.mode=='build':
        bpy.ops.wm.save_as_mainfile(filepath=str(args.output/'study.blend'))
        bpy.ops.export_scene.gltf(filepath=str(art/'study.glb'),export_format='GLB',export_cameras=True,
            export_lights=False,export_animations=True,export_frame_range=True,export_animation_mode='ACTIVE_ACTIONS',
            export_force_sampling=True,export_anim_single_armature=True,export_nla_strips=False,export_yup=True,
            export_rest_position_armature=True)
        # Active-action export has a generic animation name in Blender 4.5.
        # Normalize only that label; preserve binary geometry/animation bytes.
        import struct
        glb_path=art/'study.glb';raw=glb_path.read_bytes();n,kind=struct.unpack_from('<II',raw,12)
        doc=json.loads(raw[20:20+n]);assert len(doc['animations'])==1
        doc['animations'][0]['name']='SwordStudy';packed=json.dumps(doc,separators=(',',':')).encode()
        packed+=b' '*((-len(packed))%4);binary=raw[20+n:]
        glb_path.write_bytes(struct.pack('<4sII',b'glTF',2,12+8+len(packed)+len(binary))+struct.pack('<II',len(packed),kind)+packed+binary)
        metadata={'source_label':'CMU 02_09 · human swordplay capture','fps':60,'frame_count':len(samples),
            'duration':(len(samples)-1)/60,'clip_start_frame':1,'clip_end_frame':samples[-1]['source_frame'],
            'original_fps':120,'camera':camera,'stage_translation':list(-shift),'max_bake_endpoint_error_m':max_error,
            'phases':[{'start':0,'label':'起势 / 迈步'},{'start':.9,'label':'转髋 / 背转'},
                {'start':2.1,'label':'斜劈 / 回剑'},{'start':5.8,'label':'低势 / 再起'},{'start':7.6,'label':'收势'}],
            'limitations':['Research mannequin, not Jiang final art','Sword prop rigidly attached to right hand; no captured weapon markers',
                'Human swordplay is not authenticated Chinese sword technique','No Q proportions or foot cleanup applied','Not a closed loop'],
            'bone_count':len(specs),'mesh_vertices':len(builder.vertices),'source_sha256':digest(repo/'assets/data/sword_mocap/source/02_09.amc'),
            'model_sha256':digest(art/'study.glb'),'blender_version':bpy.app.version_string,'cost_rmb':0}
        (repo/'assets/data/sword_mocap/study.json').write_text(json.dumps(metadata,indent=2,ensure_ascii=False)+'\n')
        # Store transformed source endpoints for independent Godot import verification.
        (repo/'assets/data/sword_mocap/pose_reference.json').write_text(json.dumps({'fps':60,'samples':samples},separators=(',',':')))
        (args.output/'model-receipt.json').write_text(json.dumps(metadata,indent=2,ensure_ascii=False))
        print('MODEL',json.dumps(metadata,ensure_ascii=False),flush=True)
    else:
        indices=list(range(0,len(samples),12)) if args.mode=='preview' else list(range(len(samples)))
        out=args.output/('preview' if args.mode=='preview' else 'frames');out.mkdir(exist_ok=True)
        for i in indices:
            scene.frame_set(i);scene.render.filepath=str(out/f'frame-{i:04d}.png');bpy.ops.render.render(write_still=True)
        print('RENDERED',len(indices),'frames',flush=True)
if __name__=='__main__':main()
