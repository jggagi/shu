#!/usr/bin/env python3
"""Build an original Tinglan candidate from Shu's existing technical character base.

Existing Jiang GLB is hash pinned and never saved over. Geometry/UV/rig is reused
as a technical base; palette, face proportions, ponytail, trims and left hands
are new candidate work. No network or dependency installation. Run Blender with
its existing process-local compatible OCIO configuration (see production card).
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, math, os, re, sys
from pathlib import Path
import bpy, bmesh, numpy as np
from mathutils import Matrix, Vector

BASE_SHA='e8d74b2e0be789f272597aa6f7fc268f57851bb669ed43d97e2efa91c3860e27'

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def ensure_ocio() -> dict:
    """Use the existing Blender LUTs with its installed OCIO library version.

    Fedora's installed Blender 5.2 config declares OCIO 2.5 while its runtime
    links 2.4. That otherwise silently falls back and gamma-encodes baked maps
    incorrectly. Only new 2.5 ICC/interchange *metadata* is omitted; every color
    transform and LUT is unchanged. This is a per-process workspace cache, never
    a system config/preferences modification.
    """
    source = Path(bpy.utils.resource_path("SYSTEM")) / "datafiles/colormanagement/config.ocio"
    if not source.is_file():
        raise RuntimeError("Cannot locate Blender's bundled color configuration")
    text = source.read_text()
    match = re.search(r"ocio_profile_version:\s*([0-9]+)\.([0-9]+)", text)
    supported = tuple(bpy.app.ocio.version[:2])
    declared = (int(match[1]), int(match[2])) if match else supported
    if declared <= supported:
        return {"bundled_config": str(source), "bundled_sha256": sha(source),
                "library_version": bpy.app.ocio.version_string, "compatibility_copy": False}
    cache = Path(__file__).resolve().parents[2] / ".local/qa/tinglan-character/ocio-compat"
    cache.mkdir(parents=True, exist_ok=True)
    destination = cache / "config.ocio"
    compatible = text.replace(match[0], "ocio_profile_version: %d.%d" % supported, 1)
    compatible = re.sub(r"(?m)^    interop_id:.*\n", "", compatible)
    compatible = re.sub(r"(?m)^    interchange:\n(?:      .*\n)+", "", compatible)
    compatible = compatible.replace('search_path: "icc:luts:filmic"',
        'search_path: "%s"' % ":".join(str(source.parent / name) for name in ("icc", "luts", "filmic")), 1)
    destination.write_text(compatible)
    if os.environ.get("OCIO") != str(destination):
        print("TINGLAN_BUILD restarting only this process with compatible bundled color transforms",flush=True)
        environment = os.environ.copy()
        environment["OCIO"] = str(destination)
        command = [bpy.app.binary_path, "--disable-autoexec", "--background", "--python-exit-code", "1", "--python",
                   str(Path(__file__).resolve()), "--"] + sys.argv[sys.argv.index("--") + 1:]
        os.execve(command[0], command, environment)
    return {"bundled_config": str(source), "bundled_sha256": sha(source),
            "library_version": bpy.app.ocio.version_string, "compatibility_copy": True,
            "workspace_config_sha256": sha(destination),
            "change": "version declaration and unsupported ICC metadata only; all transforms/LUTs retained"}



def smooth(t): t=max(0.,min(1.,t)); return t*t*(3-2*t)
def load_module(path,name):
 spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def material(name,hex_color,rough=.76):
 rgb=[int(hex_color[i:i+2],16)/255 for i in (1,3,5)]
 linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
 m=bpy.data.materials.new(name);m.use_nodes=True
 s=m.node_tree.nodes.get('Principled BSDF');s.inputs['Base Color'].default_value=(*linear,1);s.inputs['Roughness'].default_value=rough
 return m

def mesh(name,vertices,faces,mat,bone,rig):
 data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
 obj=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(obj);data.materials.append(mat)
 for p in data.polygons:p.use_smooth=True
 obj.vertex_groups.new(name=bone).add(list(range(len(vertices))),1.,'REPLACE')
 mod=obj.modifiers.new('Tinglan single skeleton','ARMATURE');mod.object=rig
 return obj

def tube(vertices,faces,points,radii,segments=12,flatten=1.):
 start=len(vertices);pts=[Vector(p) for p in points]
 for i,p in enumerate(pts):
  tangent=pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]
  axis=tangent.normalized();ref=Vector((0,0,1)) if abs(axis.z)<.9 else Vector((0,1,0))
  u=axis.cross(ref).normalized();v=axis.cross(u).normalized()
  for j in range(segments):
   a=j*math.tau/segments;vertices.append(tuple(p+radii[i]*(math.cos(a)*u+math.sin(a)*v*flatten)))
 for i in range(len(pts)-1):
  for j in range(segments):
   a=start+i*segments+j;b=start+i*segments+(j+1)%segments
   faces.append((a,b,b+segments,a+segments))
 faces.append(tuple(start+j for j in reversed(range(segments))))
 faces.append(tuple(start+(len(pts)-1)*segments+j for j in range(segments)))

def curve_points(points,radii):
 pts=[Vector(p) for p in points];out=[];rs=[]
 for i in range(len(pts)-1):
  a,b,c,d=pts[max(0,i-1)],pts[i],pts[i+1],pts[min(i+2,len(pts)-1)]
  for j in range(5):
   t=j/5;out.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t));rs.append(radii[i]*(1-t)+radii[i+1]*t)
 out.append(pts[-1]);rs.append(radii[-1]);return out,rs

def ellipsoid(verts,faces,center,radii,steps=16,rings=10):
 start=len(verts)
 for i in range(rings+1):
  a=-math.pi/2+math.pi*i/rings
  for j in range(steps):
   b=math.tau*j/steps
   verts.append((center[0]+radii[0]*math.cos(a)*math.cos(b),center[1]+radii[1]*math.cos(a)*math.sin(b),center[2]+radii[2]*math.sin(a)))
 for i in range(rings):
  for j in range(steps):
   a=start+i*steps+j;b=start+i*steps+(j+1)%steps;faces.append((a,b,b+steps,a+steps))

def ribbon(name,points,width,mat,bone,rig):
 verts=[];faces=[]
 for p in points:
  verts.extend([(p[0]-width/2,p[1],p[2]),(p[0]+width/2,p[1],p[2])])
 for i in range(len(points)-1): faces.append((i*2,i*2+1,i*2+3,i*2+2))
 obj=mesh(name,verts,faces,mat,bone,rig)
 solid=obj.modifiers.new('Cloth edge thickness','SOLIDIFY');solid.thickness=.003
 return obj

def base_color_sample(obj):
 n=len(obj.data.loops);image=None
 for node in obj.data.materials[0].node_tree.nodes:
  if node.type=='BSDF_PRINCIPLED' and node.inputs['Base Color'].links:
   stack=[node.inputs['Base Color'].links[0].from_node];seen=set()
   while stack:
    source=stack.pop()
    if source.name in seen:continue
    seen.add(source.name)
    if source.type=='TEX_IMAGE':image=source.image;break
    stack.extend(link.from_node for socket in source.inputs for link in socket.links)
 if image is None:return np.ones((n,3),dtype=np.float32)
 w,h=image.size;pixels=np.empty(w*h*4,dtype=np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape(h,w,4)
 uv=np.empty(n*2,dtype=np.float32);obj.data.uv_layers.active.data.foreach_get('uv',uv);uv=uv.reshape(n,2)
 return pixels[(uv[:,1]*h).astype(int).clip(0,h-1),(uv[:,0]*w).astype(int).clip(0,w-1),:3]

def tint_vertices(obj,head=False):
 layer=obj.data.color_attributes.get('Color');n=len(obj.data.loops)
 colors=np.ones((n,4),dtype=np.float32)
 if layer:layer.data.foreach_get('color',colors.ravel())
 else:layer=obj.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
 if layer.domain!='CORNER':raise RuntimeError('Expected GLB corner colors')
 ids=np.array([l.vertex_index for l in obj.data.loops]);coords=np.array([v.co[:] for v in obj.data.vertices])[ids]
 samples=base_color_sample(obj)
 if head:
  x,y,z=coords.T;face=(np.abs(x)<.152)&(y<-.09)&(z>1.57)&(z<1.91)
  fringe=face&(z>1.77)&(samples.max(axis=1)<.63)&(samples[:,0]>samples[:,2]*1.12)&(samples[:,0]>samples[:,1]*1.04)
  hair=~face|fringe
  # Retain the existing skin/eyes texture; the darker non-face material takes
  # an ink tint. This is per-vertex 3D material work, not painting over pixels.
  colors[hair,:3]*=np.array([.08,.25,1.40])
  colors[face&~fringe,:3]*=np.array([.96,1.,1.025])
  for polygon in obj.data.polygons:
   if polygon.material_index>0:colors[polygon.loop_start:polygon.loop_start+polygon.loop_total]=1.0
 else:
  x,y,z=coords.T;neck=(np.abs(x)<.09)&(z>1.48)
  blue=(samples[:,2]>samples[:,0]*1.12)
  colors[~neck&blue,:3]*=np.array([.42,.49,.24])
  colors[~neck&~blue,:3]*=np.array([.055,.19,.18])
 layer.data.foreach_set('color',colors.ravel());obj.data.color_attributes.active_color=layer
 obj.data.color_attributes.render_color_index=obj.data.color_attributes.find('Color')
 # glTF exporters only serialize colors used by an actual Base Color link.
 for mat in obj.data.materials:
  s=mat.node_tree.nodes.get('Principled BSDF')
  if not s or not s.inputs['Base Color'].links:continue
  if any(n.type in ['VERTEX_COLOR','ATTRIBUTE'] for n in mat.node_tree.nodes):continue
  t=mat.node_tree;old=s.inputs['Base Color'].links[0].from_socket
  c=t.nodes.new('ShaderNodeVertexColor');c.layer_name='Color'
  mix=t.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
  t.links.new(old,mix.inputs[1]);t.links.new(c.outputs['Color'],mix.inputs[2]);t.links.new(mix.outputs[0],s.inputs['Base Color'])

def trim_base(head,body,rig):
 g=head.vertex_groups.get('ponytail');remove=[]
 if g:
  remove=[v.index for v in head.data.vertices if any(a.group==g.index and a.weight>.65 for a in v.groups) and v.co.z<1.96]
 remove=sorted(set(remove)|{v.index for v in head.data.vertices if v.co.y>.23 and v.co.z<1.97})
 for obj,ids in [(head,remove)]:
  bm=bmesh.new();bm.from_mesh(obj.data);bm.verts.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.verts[i] for i in ids],context='VERTS');bm.to_mesh(obj.data);bm.free()
 # Mild lower-face narrowing creates a separate candidate while preserving UVs.
 for v in head.data.vertices:
  if v.co.y<.04 and 1.57<v.co.z<1.91:
   v.co.x*=.94+.06*smooth((v.co.z-1.82)/.09)
 hand=body.vertex_groups['hand.L'];basis=rig.data.bones['hand.L'].matrix_local.inverted();ids=[]
 for v in body.data.vertices:
  if any(a.group==hand.index and a.weight>.45 for a in v.groups) and (basis@v.co).y>.015:ids.append(v.index)
 bm=bmesh.new();bm.from_mesh(body.data);bm.verts.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.verts[i] for i in ids],context='VERTS');bm.to_mesh(body.data);bm.free()
 return {'old_ponytail_vertices_removed':len(remove),'left_hand_vertices_removed':len(ids),'lower_face_width_factor':.94}

def left_hand(rig,name,point,skin):
 verts=[];faces=[];basis=rig.data.bones['hand.L'].matrix_local
 ellipsoid(verts,faces,(0,.047,0),(.039,.047,.022))
 tube(verts,faces,[(0,-.018,0),(0,.018,0),(0,.048,0)],[.032,.034,.032],16,.70)
 for i,x in enumerate([-.026,-.008,.010,.028]):
  if point and i in [0,1]:
   points=[(x,.070,0),(x,.108,0),(x,.145,-.002),(x,.183,-.003)];r=[.010,.010,.009,.005]
  else:
   points=[(x,.070,0),(x,.095,.003),(x,.107,.021),(x,.084,.032)];r=[.010,.011,.009,.006]
  tube(verts,faces,points,r,10)
 tube(verts,faces,[(-.033,.026,.0),(-.049,.045,.009),(-.034,.068,.028),(-.017,.069,.030)],[.015,.013,.011,.006],12)
 return mesh(name,[basis@Vector(p) for p in verts],faces,skin,'hand.L',rig)

def author_details(rig):
 hair=material('Tinglan ink hair','#292e33',.66);jade=material('Tinglan teal silk','#4c8d87',.68)
 ivory=material('Tinglan warm inner edging','#d9d9c4');gold=material('Tinglan muted bronze piping','#b19c62',.65)
 robe=material('Tinglan deep teal panels','#31595b');skin=material('Tinglan warm skin','#dec2a9',.83)
 out=[]
 for i in range(7):
  dx=(i-3)*.020;verts=[];faces=[]
  points,radii=curve_points([(dx,.21,2.015),(dx*1.4,.30,1.92),(.035+dx*1.7,.39,1.73),(.02+dx*1.5,.43,1.52),(-.05+dx*.6,.40,1.28),(-.10+dx*.2,.34,1.19)],[.035,.042,.041,.033,.020,.0015])
  tube(verts,faces,points,radii,14,.62)
  out.append(mesh('TinglanLongHair_%02d'%i,verts,faces,hair,'ponytail',rig))
 for side in [-1,1]:
  verts=[];faces=[];points,radii=curve_points([(side*.14,-.04,1.96),(side*.18,-.11,1.87),(side*.17,-.15,1.71),(side*.16,-.12,1.61)],[.022,.025,.018,.001])
  tube(verts,faces,points,radii,12,.5);out.append(mesh('TinglanSideLock'+str(side),verts,faces,hair,'head',rig))
 # Teal knot and two finite, tapering cloth ribbons distinguish the high tie.
 verts=[];faces=[];ellipsoid(verts,faces,(0,.22,2.035),(.10,.055,.033));out.append(mesh('TinglanHairTie',verts,faces,jade,'head',rig))
 for side in [-1,1]:
  out.append(ribbon('TinglanHairRibbon'+str(side),[(side*.035,.27,2.04),(side*.14,.32,1.97),(side*.18,.34,1.79),(side*.16,.35,1.64)],.032,jade,'ponytail',rig))
  # Authored cloth panels preserve a long sword-disciple silhouette.
  xs=[.14,.22,.29,.30];zs=[1.02,.88,.66,.42];ys=[-.20,-.24,-.28,-.29]
  left=[(side*(x-.060),y,z) for x,y,z in zip(xs,ys,zs)];right=[(side*(x+.060),y,z+.012) for x,y,z in zip(xs,ys,zs)]
  verts=[];faces=[]
  for a,b in zip(left,right):verts.extend([a,b])
  for i in range(3):faces.append((i*2,i*2+1,i*2+3,i*2+2))
  out.append(mesh('TinglanFrontPanel'+str(side),verts,faces,robe,'skirt.front.L' if side>0 else 'skirt.front.R',rig))
  out.append(ribbon('TinglanPanelPiping'+str(side),[(p[0],p[1]-.004,p[2]) for p in right],.006,gold,'skirt.front.L' if side>0 else 'skirt.front.R',rig))
 # Small jade/bronze clasp, with the original belt texture below it.
 for name,c,r,mat in [('TinglanBronzeClasp',(0,-.257,1.045),(.050,.012,.035),gold),('TinglanJadeClasp',(0,-.271,1.045),(.029,.009,.023),jade)]:
  v=[];f=[];ellipsoid(v,f,c,r);out.append(mesh(name,v,f,mat,'pelvis',rig))
 # Narrow crossing lapels sit over the retained cloth, without a second torso.
 for side in [-1,1]:
  pts=[(side*.11,-.172,1.53),(side*.07,-.208,1.44),(-side*.06,-.233,1.30)]
  out.append(ribbon('TinglanIvoryLapel'+str(side),pts,.027,ivory,'chest',rig))
 # Cuff closes the original wrist cut; both hand variants share this exact anchor.
 basis=rig.data.bones['hand.L'].matrix_local;v=[];f=[]
 tube(v,f,[(0,-.022,0),(0,.010,0)],[.046,.043],20,.72)
 out.append(mesh('TinglanLeftCuff',[basis@Vector(p) for p in v],f,ivory,'hand.L',rig))
 out.append(left_hand(rig,'TinglanRelaxedHand',False,skin));out.append(left_hand(rig,'TinglanPointingHand',True,skin))
 return out

def interrupt_action(rig,base):
 scene=bpy.context.scene;scene.render.fps=30
 # glTF importer creates one track per original clip. Sample its real Idle.
 for t in rig.animation_data.nla_tracks:t.mute=True
 idle=next(a for a in bpy.data.actions if 'Idle' in a.name)
 rig.animation_data.action=idle;scene.frame_set(1);bpy.context.view_layer.update()
 neutral={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
 desired_idle={b.name:b.matrix.copy() for b in rig.pose.bones}
 action=bpy.data.actions.new('TinglanInterrupt');rig.animation_data.action=action
 for frame,power in [(0,0.),(2,.20),(4,1.),(6,.76),(8,.32),(10,0.),(12,0.)]:
  for b in rig.pose.bones:b.matrix_basis=neutral[b.name]
  bpy.context.view_layer.update()
  shoulder=rig.pose.bones['upper_arm.L'].head.copy();rest_wrist=desired_idle['hand.L'].translation
  wrist_goal=rest_wrist.lerp(Vector((.20,-.565,1.45)),power)
  lengths=[rig.data.bones[n].length for n in ['upper_arm.L','forearm.L']]
  elbow,wrist=base.two_bone(shoulder,Vector((.48,-.12,1.30)),wrist_goal,*lengths)
  for name,start,end in [('upper_arm.L',shoulder,elbow),('forearm.L',elbow,wrist)]:
   rest=rig.data.bones[name];q=(rest.tail_local-rest.head_local).rotation_difference(end-start)@rest.matrix_local.to_quaternion()
   rig.pose.bones[name].matrix=Matrix.LocRotScale(start,q,Vector((1,1,1)));bpy.context.view_layer.update()
  rest=rig.data.bones['hand.L'];aim=(wrist-elbow).normalized()
  point_q=(rest.tail_local-rest.head_local).rotation_difference(aim)@rest.matrix_local.to_quaternion()
  neutral_q=desired_idle['hand.L'].to_quaternion();q=neutral_q.slerp(point_q,power)
  rig.pose.bones['hand.L'].matrix=Matrix.LocRotScale(wrist,q,Vector((1,1,1)));bpy.context.view_layer.update()
  if power==0.:
   for b in rig.pose.bones:b.matrix_basis=neutral[b.name]
  for b in rig.pose.bones:
   b.rotation_mode='QUATERNION';b.keyframe_insert('location',frame=frame);b.keyframe_insert('rotation_quaternion',frame=frame);b.keyframe_insert('scale',frame=frame)
 track=rig.animation_data.nla_tracks.new();track.name='TinglanInterrupt';track.strips.new('TinglanInterrupt',0,action);track.mute=True
 rig.animation_data.action=None;scene.frame_set(1)
 return {'frames':[0,12],'fps':30,'hit_frame':4,'neutral_frame':10,'left_hand':'two fingers, separately authored mesh','right_hand':'retains one sword grip'}

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True);parser.add_argument('--out',type=Path,required=True);parser.add_argument('--blend',type=Path,required=True)
 args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);root=Path(__file__).resolve().parents[2]
 color_management=ensure_ocio()
 if sha(args.base)!=BASE_SHA:raise RuntimeError('Technical base hash mismatch')
 if len({args.base.resolve(),args.out.resolve(),args.blend.resolve()})!=3 or args.out.suffix!='.glb' or args.blend.suffix!='.blend':raise RuntimeError('Distinct base, candidate GLB and candidate Blend paths required')
 args.out.parent.mkdir(parents=True,exist_ok=True);args.blend.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=30;bpy.ops.import_scene.gltf(filepath=str(args.base))
 rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');head=bpy.data.objects['JiangApprovedHead'];body=bpy.data.objects['JiangFullbody']
 report={'status':'new candidate, not user-approved','technical_base_sha256':BASE_SHA,'identity_reference':'docs/concepts/03-character-roster.png, upper row second character','author':'Codex for Shu; local Blender derived model and original detail/hand meshes','new_cloud_calls':0,'new_paid_calls':0,'original_jiang_modified':False,'color_management':color_management,'builder_sha256':sha(__file__)}
 report['geometry_edits']=trim_base(head,body,rig);tint_vertices(head,True);tint_vertices(body)
 head.name='TinglanHead';body.name='TinglanBody';bpy.data.objects['JiangRightGrip_HandGrip'].name='TinglanRightGrip';bpy.data.objects['JiangRightGrip_Jian'].name='TinglanJian'
 extra=author_details(rig);base=load_module(root/'tools/hero_lookdev/build_fullbody_turn.py','tinglan_motion_base');report['interrupt']=interrupt_action(rig,base)
 rig.name='TinglanRig'
 # Keep the only visible relaxed hand in the saved source review. Export both.
 bpy.data.objects['TinglanPointingHand'].hide_render=True
 for image in bpy.data.images:
  if image.type!='RENDER_RESULT':image.pack()
 bpy.ops.wm.save_as_mainfile(filepath=str(args.blend.resolve()))
 bpy.data.objects['TinglanPointingHand'].hide_render=False
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith('Tinglan')]
 for o in meshes:o.select_set(True)
 bpy.context.view_layer.objects.active=rig
 bpy.ops.export_scene.gltf(filepath=str(args.out.resolve()),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_texcoords=True,export_vertex_color='NAME',export_vertex_color_name='Color',export_normals=True,export_materials='EXPORT',export_animations=True,export_animation_mode='NLA_TRACKS',export_frame_range=False,export_force_sampling=True,export_nla_strips=True,export_skins=True,export_def_bones=False,export_cameras=False,export_lights=False)
 helper=load_module(root/'tools/hero_lookdev/export_ambush_jiang.py','tinglan_gltf_report');gltf=helper.read_glb(args.out)
 report.update(helper.describe_glb(args.out,gltf));report['glb_sha256']=sha(args.out);report['bytes']=args.out.stat().st_size
 report['triangles']=sum(gltf['accessors'][p['indices']]['count']//3 for m in gltf.get('meshes',[]) for p in m['primitives']);report['mesh_count']=len(gltf.get('meshes',[]));report['bones']=[b.name for b in rig.data.bones]
 bounds=[o.matrix_world@Vector(p) for o in meshes for p in o.bound_box];floor=min(p.z for p in bounds);top=max(p.z for p in bounds)
 report['calibration']={'floor':floor,'height':top-floor,'display_height':1.90,'method':'standing source mesh bounds; runtime actual Idle feet midpoint on X/Z'}
 report['technical_base_record']='docs/P3_JIANG_MODEL_REUSE.md'
 report['author_and_usage']='Existing user-authorized Tencent Hunyuan mesh/texture outputs and original Shu grip/sword/rig as technical base; original source terms retained. New local Tinglan derivative, hand shapes, hair and clothing detail by Codex for Shu.'
 report['rebuild']={'script':'tools/hero_lookdev/build_ambush_tinglan.py','base':'assets/art/mountain_ambush/jiang-approved.glb','process_local_ocio':'Existing compatible bundled config; no system changes','editable_source':str(args.blend.relative_to(root))}
 report['limitations']=['Shared technical topology with Jiang; candidate face proportions and palette, no new independent scan or cloud sculpt.','Hand meshes are rigid to hand.L; no per-finger rig.','Conservative skirt and ponytail skinning; no cloth simulation.']
 args.out.with_suffix('.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('TINGLAN_BUILD '+json.dumps({k:report[k] for k in ['bytes','triangles','mesh_count','glb_sha256','animation_clips']}))
 if sha(args.base)!=BASE_SHA:raise RuntimeError('Original base changed')
if __name__=='__main__':main()
