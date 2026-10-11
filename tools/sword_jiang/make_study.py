"""Original Jiang candidate over the approved CMU clip; no gameplay code.
Run with pinned Blender. Uniform target scale, explicit grip IK and limited foot plants.
"""
import argparse, copy, importlib.util, json, math, struct, sys
from pathlib import Path
import bpy
from mathutils import Vector, Quaternion

def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec)
    sys.modules[name]=m;spec.loader.exec_module(m);return m

SWORD_AXIS=(.2168818116,.5327647328,.8180000186)

def vec(p):return Vector(p)
def put(b,head,tail,q=None):
    b['head']=list(head);b['tail']=list(tail)
    if q is not None:b['rotation']=list(q.normalized())

def two_bone(a,pole,end,l1,l2):
    delta=end-a;distance=delta.length
    if distance<1e-8:delta=Vector((0,0,-1));distance=1e-8
    axis=delta.normalized();d=max(abs(l1-l2)+1e-6,min(l1+l2-1e-6,distance))
    projected=pole-a-axis*(pole-a).dot(axis)
    if projected.length<1e-6:projected=axis.cross(Vector((0,1,0)))
    if projected.length<1e-6:projected=axis.cross(Vector((1,0,0)))
    projected.normalize();x=(l1*l1-l2*l2+d*d)/(2*d)
    y=math.sqrt(max(0,l1*l1-x*x));return a+axis*x+projected*y,a+axis*d

def aim(b,a,z):
    old=vec(b['tail'])-vec(b['head']);new=z-a
    q=old.rotation_difference(new)@Quaternion(b['rotation']);put(b,a,z,q)

def contact_windows(samples,side):
    points=[vec(s['bones'][side+'toes']['tail']) for s in samples]
    floor=min(p.z for p in points);vel=[]
    for i in range(len(points)):
        a=max(0,i-2);b=min(len(points)-1,i+2)
        vel.append(((points[b]-points[a])*60/max(1,b-a)).to_2d().length)
    flags=[p.z<floor+.030 and vel[i]<.12 for i,p in enumerate(points)]
    for i in range(1,len(flags)-2):
        if flags[i-1] and flags[i+1]:flags[i]=True
        if flags[i-1] and flags[i+2]:flags[i]=flags[i+1]=True
    windows=[];start=None
    for i,flag in enumerate(flags+[False]):
        if flag and start is None:start=i
        if not flag and start is not None:
            if i-start>=12:windows.append((start,i-1))
            start=None
    return windows

def clean(samples,rest,specs,scale=.70):
    raw=copy.deepcopy(samples)
    for sample in samples:
        for b in sample['bones'].values():
            b['head']=list(vec(b['head'])*scale);b['tail']=list(vec(b['tail'])*scale)
    contacts={side:contact_windows(raw,side) for side in ['l','r']}
    max_grip=0.;max_plant=0.;plant_measurements=[];grip_samples=0;full_grip_samples=0
    lengths={n:(vec(b['tail'])-vec(b['head'])).length for n,b in rest.items()}
    childmap={spec['name']:spec.get('parent') for spec in specs}
    for side,windows in contacts.items():
        for start,end in windows:
            anchor=sum((vec(samples[i]['bones'][side+'toes']['tail']) for i in range(start,min(start+4,end+1))),Vector())/min(4,end-start+1)
            for i in range(start,end+1):
                b=samples[i]['bones'];toe=vec(b[side+'toes']['tail'])
                t=min(1.,(i-start)/5.,(end-i)/5.);weight=t*t*(3-2*t)
                desired=toe.lerp(anchor,weight);ankle=vec(b[side+'tibia']['tail'])+(desired-toe)
                hip=vec(b[side+'femur']['head']);knee=vec(b[side+'femur']['tail'])
                k,z=two_bone(hip,knee,ankle,lengths[side+'femur'],lengths[side+'tibia'])
                aim(b[side+'femur'],hip,k);aim(b[side+'tibia'],k,z)
                offset=z-vec(b[side+'foot']['head'])
                for name in [side+'foot',side+'toes']:put(b[name],vec(b[name]['head'])+offset,vec(b[name]['tail'])+offset)
                if weight==1.:
                    error=(vec(b[side+'toes']['tail'])-anchor).length;max_plant=max(max_plant,error)
                    plant_measurements.append({'frame':i,'side':side,'error_m':error})
    for sample in samples:
        b=sample['bones'];old=copy.deepcopy(b)
        right=(vec(b['rhand']['head'])+vec(b['rhand']['tail']))*.5
        axis=Quaternion(b['rhand']['rotation'])@Vector(SWORD_AXIS).normalized();target=right-axis*.085
        left=(vec(b['lhand']['head'])+vec(b['lhand']['tail']))*.5
        gap=(left-target).length
        # The source includes one-handed movement. Only close, reachable captured grips are calibrated.
        weight=max(0.,min(1.,(.105-gap)/.065));weight=weight*weight*(3-2*weight)
        if weight<=0.:continue
        target=left.lerp(target,weight)
        q=Quaternion(b['lhand']['rotation']);hvec=vec(rest['lhand']['tail'])-vec(rest['lhand']['head'])
        h=target-q@hvec*.5;wvec=vec(rest['lwrist']['tail'])-vec(rest['lwrist']['head'])
        wrist=h-Quaternion(b['lwrist']['rotation'])@wvec
        shoulder=vec(b['lhumerus']['head']);elbow=vec(b['lhumerus']['tail'])
        if (wrist-shoulder).length>=.995*(lengths['lhumerus']+lengths['lradius']):continue
        grip_samples+=1
        if weight==1.:full_grip_samples+=1
        e,w=two_bone(shoulder,elbow,wrist,lengths['lhumerus'],lengths['lradius'])
        aim(b['lhumerus'],shoulder,e);aim(b['lradius'],e,w)
        put(b['lwrist'],w,w+Quaternion(b['lwrist']['rotation'])@wvec)
        h=vec(b['lwrist']['tail']);put(b['lhand'],h,h+q@hvec)
        for spec in specs:
            name=spec['name'];parent=childmap[name]
            if name not in ['lfingers','lthumb']:continue
            qnew=Quaternion(b[parent]['rotation'])@Quaternion(old[parent]['rotation']).inverted()@Quaternion(old[name]['rotation'])
            head=vec(b[parent]['tail']);v=vec(rest[name]['tail'])-vec(rest[name]['head']);put(b[name],head,head+qnew@v,qnew)
        max_grip=max(max_grip,((vec(b['lhand']['head'])+vec(b['lhand']['tail']))*.5-target).length)
    maximum_length=0.;maximum_direction=0.
    for sample in samples:
        for name,b in sample['bones'].items():
            if name=='root':continue
            expected=Quaternion(b['rotation'])@(vec(rest[name]['tail'])-vec(rest[name]['head']))
            actual=vec(b['tail'])-vec(b['head']);maximum_length=max(maximum_length,abs(actual.length-lengths[name]))
            maximum_direction=max(maximum_direction,(actual-expected).length)
    if maximum_length>1e-5 or maximum_direction>1e-5:raise RuntimeError('IK bone length/orientation mismatch')
    return {'uniform_scale':scale,'contact_windows':contacts,'fully_planted_samples':len(plant_measurements),
        'max_contact_anchor_error_m':max_plant,'max_left_target_error_m':max_grip,
        'close_hand_calibrated_samples':grip_samples,'fully_gripped_samples':full_grip_samples,
        'max_bone_length_error_m':maximum_length,'max_bone_vector_error_m':maximum_direction,
        'foot_method':'Low, slow toe-contact windows only; five-frame smooth entry/exit; captured foot rotation retained',
        'grip_method':'Right hand unchanged; left two-bone IK only for close reachable source gestures; one-handed gestures retained'}

def weapon(rest,arm,geometry,shared):
    colors={'steel':(.64,.69,.68),'edge':(.30,.37,.37),'wrap':(.16,.26,.31),'brass':(.53,.43,.25)}
    mats={n:shared.material('Sword_'+n,c) for n,c in colors.items()};b=geometry.MeshBuilder()
    palm=(vec(rest['rhand']['head'])+vec(rest['rhand']['tail']))*.5;axis=Vector(SWORD_AXIS).normalized();guard=palm+axis*.055;cross=axis.cross(Vector((0,0,1))).normalized()
    b.segment(palm-axis*.13,palm+axis*.05,.014,'wrap','rhand',sides=12)
    b.segment(guard-cross*.066,guard+cross*.066,.009,'brass','rhand',sides=12)
    b.ellipsoid(palm-axis*.137,(.020,.013,.020),'brass','rhand',segments=12,rings=8)
    b.segment(guard,guard+axis*.63,.017,'steel','rhand',radius_end=.001,sides=4,profile=((0,1),(.86,.85),(1,.01)))
    return b.mesh_object('JiangSword',arm,mats)

def ink_edges():
    """Thin matte silhouette shells; fixed geometry, same linear skinning as the source."""
    mat=bpy.data.materials.new('JiangInkEdge');mat.use_nodes=True;mat.use_backface_culling=True
    nodes=mat.node_tree.nodes;nodes.clear();out=nodes.new('ShaderNodeOutputMaterial');ink=nodes.new('ShaderNodeEmission')
    ink.inputs['Color'].default_value=(.075,.093,.085,1);ink.inputs['Strength'].default_value=1
    mat.node_tree.links.new(ink.outputs['Emission'],out.inputs['Surface'])
    for original in list(bpy.context.scene.objects):
        if original.type!='MESH':continue
        shell=original.copy();shell.data=original.data.copy();shell.name=original.name+'InkEdge'
        bpy.context.collection.objects.link(shell)
        for v in shell.data.vertices:v.co+=v.normal*(.0028 if original.name!='JiangSword' else .0010)
        for face in shell.data.polygons:face.flip()
        shell.data.materials.clear();shell.data.materials.append(mat)
        for face in shell.data.polygons:face.material_index=0
        shell.data.update()

def setup(shared):
    camera,cam=shared.scene_setup();scene=bpy.context.scene
    scene.render.resolution_x=384;scene.render.resolution_y=384
    target=Vector((0,0,.78));pos=Vector((-4,-6,3.2));cam.location=pos
    cam.rotation_euler=(target-pos).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.60
    scene.render.image_settings.compression=50
    return {'position':list(pos),'target':list(target),'ortho':2.60,'coordinate_system':'Blender Z up'},cam

def main():
    a=argparse.ArgumentParser();a.add_argument('--repo',type=Path,required=True);a.add_argument('--output',type=Path,required=True)
    a.add_argument('--style',choices=['original','legacy'],default='original');a.add_argument('--mode',choices=['build','preview','render'],default='build');args=a.parse_args(sys.argv[sys.argv.index('--')+1:])
    root=args.repo;out=args.output;out.mkdir(parents=True,exist_ok=True)
    if args.mode in ['preview','render']:
        bpy.ops.wm.open_mainfile(filepath=str(out/'study.blend'));scene=bpy.context.scene
        indices=[0,60,90,126,240,348,400,456,516] if args.mode=='preview' else range(scene.frame_end+1)
        dest=out/args.mode;dest.mkdir(exist_ok=True)
        for i in indices:
            path=dest/f'frame-{i:04d}.png'
            if path.exists():continue
            scene.frame_set(i);scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
        print('JIANG_RENDERED',len(indices),flush=True);return
    shared=load('shared_mocap',root/'tools/sword_mocap/make_study.py')
    converter=load('cmu_motion',root/'tools/sword_mocap/cmu_motion.py');geometry=load('lab_geometry',root/'tools/animation_lab/make_blender_demo.py')
    character_file='legacy_character.py' if args.style=='legacy' else 'character.py'
    character=load('jiang_character',root/'tools/sword_jiang'/character_file)
    asset_id='sword_jiang_legacy' if args.style=='legacy' else 'sword_jiang'
    sk=converter.parse_asf(root/'assets/data/sword_mocap/source/02.asf');zero={'root':(0,0,0,0,0,0)}
    zero.update({b.name:tuple(0 for _ in b.dofs) for b in sk.bones if b.dofs})
    rest=converter.solve_frame(sk,converter.MotionFrame(1,zero))
    for b in rest.values():b['head']=list(vec(b['head'])*.70);b['tail']=list(vec(b['tail'])*.70)
    specs=converter.sample_file(root/'assets/data/sword_mocap/source/02.asf',root/'assets/data/sword_mocap/source/02_09.amc',stride=2)['bones']
    samples=json.loads((root/'assets/data/sword_mocap/pose_reference.json').read_text())['samples'];cleanup=clean(samples,rest,specs)
    print('JIANG_CLEANUP',json.dumps(cleanup),flush=True)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    arm=shared.make_rig(specs,rest);result=character.build_character(arm,rest)
    weapon(rest,arm,geometry,shared);ink_edges();error=shared.bake(arm,specs,rest,samples);camera,cam=setup(shared)
    art=root/'assets/art'/asset_id;data=root/'assets/data'/asset_id;art.mkdir(parents=True,exist_ok=True);data.mkdir(parents=True,exist_ok=True)
    scene=bpy.context.scene;scene.frame_set(0);bpy.ops.wm.save_as_mainfile(filepath=str(out/'study.blend'))
    path=art/'study.glb'
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_cameras=True,export_lights=False,
        export_animations=True,export_frame_range=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,
        export_anim_single_armature=True,export_nla_strips=False,export_yup=True,export_rest_position_armature=True)
    raw=path.read_bytes();n,kind=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+n]);assert len(doc['animations'])==1
    doc['animations'][0]['name']='SwordStudy';packed=json.dumps(doc,separators=(',',':')).encode();packed+=b' '*((-len(packed))%4)
    binary=raw[20+n:];path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(packed)+len(binary))+struct.pack('<II',len(packed),kind)+packed+binary)
    meta={'source_label':('CMU 02_09 · 江砚秋原画服饰候选' if args.style=='legacy' else 'CMU 02_09 · 江砚秋造型候选'),'character_style':args.style,'asset_id':asset_id,'fps':60,'frame_count':len(samples),'duration':(len(samples)-1)/60,
        'original_fps':120,'camera':camera,'cleanup':cleanup,'max_bake_endpoint_error_m':error,'bone_count':31,
        'frame_size':384,'sword_rest_axis':list(Vector(SWORD_AXIS).normalized()),'ink_edge_m':.0028,'character':result,'source_sha256':shared.digest(root/'assets/data/sword_mocap/source/02_09.amc'),
        'reference_art_sha256':shared.digest(root/'assets/art/v2/jiang-yanqiu-v2.png'),'costume_reference_sha256':shared.digest(root/'assets/art/back_mountain_training/actor-sheet.png'),'model_sha256':shared.digest(path),
        'blender_version':bpy.app.version_string,'cost_rmb':0,
        'phases':[{'start':0,'label':'起势 / 迈步'},{'start':.9,'label':'转髋 / 背转'},{'start':2.1,'label':'斜劈 / 回剑'},
                  {'start':5.8,'label':'低势 / 再起'},{'start':7.6,'label':'收势'}],
        'limitations':['Original full-body interpretation of approved waist-up character reference',
          'Capture has no weapon markers; prop and left grip are authored','Limited contact cleanup, no full-body physics',
          'Skin-deformed robe; no cloth simulation','Human swordplay is not authenticated Chinese sword technique','Not a closed loop']}
    (data/'study.json').write_text(json.dumps(meta,indent=2,ensure_ascii=False)+'\n')
    (data/'pose_reference.json').write_text(json.dumps({'fps':60,'samples':samples},separators=(',',':')))
    if args.style=='legacy' and not (art/'study.glb.import').exists():
        (art/'study.glb.import').write_text('[params]\nanimation/fps=60\nanimation/trimming=false\n_subresources={\n"nodes": {"PATH:AnimationPlayer": {"compression/enabled": false, "optimizer/enabled": false}}\n}\n')
    (out/'model-receipt.json').write_text(json.dumps(meta,indent=2,ensure_ascii=False)+'\n')
    print('JIANG_MODEL',json.dumps(meta,ensure_ascii=False),flush=True)
if __name__=='__main__':main()
