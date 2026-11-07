#!/usr/bin/env python3
"""Author an independent adult seated tea patron from the approved local Jiang rig.

Only the exact immutable approved runtime GLB is read. This script changes the
new NPC's face/body proportions, hair silhouette, cloth palette and seated skin
weights; it never edits the approved hero. Blender owns geometry/material edits
and all review renders. The 12 second action uses the host's existing tea window.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, math, sys
from pathlib import Path
import bpy, bmesh, numpy as np
from mathutils import Matrix, Quaternion, Vector

BASE_SHA='e8d74b2e0be789f272597aa6f7fc268f57851bb669ed43d97e2efa91c3860e27'
FPS=60
SEAT=0.33501386642456055
PELVIS=0.465
FLOOR=0.00033545034
KEEP={'JiangApprovedHead','JiangFullbody','JiangRightGrip_HandGrip'}

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def smooth(a,b,x):
 t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3-2*t)
def load_base():
 spec=importlib.util.spec_from_file_location('town_daily_base',str(Path(__file__).with_name('build_town_volume_character.py')))
 mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
base=load_base()

def vertex_colors(mesh):
 ca=mesh.color_attributes.get('Color'); out=np.zeros((len(mesh.vertices),4));ids=np.array([l.vertex_index for l in mesh.loops]);c=np.array([v.color[:] for v in ca.data]); np.add.at(out,ids,c);out/=np.maximum(np.bincount(ids,minlength=len(mesh.vertices)),1)[:,None];return out

def sampled_texture_colors(obj):
 image=next(n.image for n in obj.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image and 'SaturatedBaseColor' in n.image.name)
 pixels=np.array(image.pixels[:]).reshape((image.size[1],image.size[0],4));uv=np.array([u.uv[:] for u in obj.data.uv_layers.active.data]);ids=np.array([l.vertex_index for l in obj.data.loops]);samples=pixels[(uv[:,1]*image.size[1]).astype(int).clip(0,image.size[1]-1),(uv[:,0]*image.size[0]).astype(int).clip(0,image.size[0]-1)];out=np.zeros((len(obj.data.vertices),4));np.add.at(out,ids,samples);out/=np.maximum(np.bincount(ids,minlength=len(out)),1)[:,None];return out

def green_colors(a):
 a=a.copy();r,g,b=a[:,0],a[:,1],a[:,2];mask=(b>r*1.12)&(b>g*1.025)&(b>.1)
 lum=(r*.2126+g*.7152+b*.0722); target=np.array([.76,.80,.73]);a[mask,:3]=lum[mask,None]*target[None,:]/.85
 a[:,:3]=np.clip(a[:,:3],0,1);return a,mask

def edit_geometry(rig, objects):
 head=next(o for o in objects if o.name=='JiangApprovedHead');body=next(o for o in objects if o.name=='JiangFullbody')
 hco=np.array([v.co[:] for v in head.data.vertices]); colors=vertex_colors(head.data);texture_colors=sampled_texture_colors(head);hair_flags=(texture_colors[:,:3].mean(1)<.61)&(texture_colors[:,0]>texture_colors[:,1]*1.09)&(texture_colors[:,1]>texture_colors[:,2]*1.035)
 pony=head.vertex_groups['ponytail'].index
 remove=[]
 for v in head.data.vertices:
  x,y,z=v.co;ear=(.135<abs(x)<.205 and 1.67<z<1.81 and -.10<y<.025 and texture_colors[v.index,:3].mean()>.58 and texture_colors[v.index,2]>.34)
  if z>1.825 or (y>-.05 and not ear) or (y<-.22 and z>1.78) or (abs(x)>.145 and hair_flags[v.index]):remove.append(v.index)
 # Adult face: smaller cranium, longer mandibular third and narrower eye volume.
 for v in head.data.vertices:
  x,y,z=v.co
  if y<-.08:
   eye=max(math.exp(-(((x-.078)/.065)**2+((z-1.795)/.042)**2)),math.exp(-(((x+.078)/.065)**2+((z-1.795)/.042)**2)))
   z=1.795+(z-1.795)*(1-.32*eye)
   chin=(1-smooth(1.61,1.73,z))*smooth(.08,.22,-y)
   z-=.043*chin;x*=1+.085*chin; y-=.012*math.exp(-((x/.045)**2+((z-1.69)/.055)**2))
  v.co=(x*.83,y*.88,1.48+(z-1.48)*.85)
 # Broader shoulder/chest and a settled adult abdomen, without a toy cylinder.
 for o in objects:
  if o==head: continue
  for v in o.data.vertices:
   x,y,z=v.co; shoulder=smooth(1.03,1.32,z)*(1-smooth(1.50,1.64,z)); waist=math.exp(-((z-1.09)/.18)**2)
   v.co.x=x*(1+.10*shoulder+.07*waist)
   v.co.y=y*(1+.12*waist)
 # Independent muted grey/green outer cloth. Source sculpt, UV, maps remain.
 ca=body.data.color_attributes['Color']; arr=np.array([c.color[:] for c in ca.data]);arr,mask=green_colors(arr)
 for index,(c,value) in enumerate(zip(ca.data,arr)):
  vi=body.data.loops[index].vertex_index
  if body.data.vertices[vi].co.z<.255 and mask[index]:
   lum=float(value[:3]@np.array([.2126,.7152,.0722]));value[:3]=lum*np.array([1.0,.84,.68])
  c.color=value
 # Darken/desaturate surviving brown hair via its own vertex layer, preserve face.
 ca=head.data.color_attributes['Color']; ids=[l.vertex_index for l in head.data.loops]
 for item,vi in zip(ca.data,ids):
  v=head.data.vertices[vi]; c=np.array(item.color[:]); hair=bool(hair_flags[vi])
  if hair:
   lum=float(c[:3]@np.array([.2126,.7152,.0722]));c[:3]=lum*np.array([.68,.64,.58]);item.color=c
 # The face, eyes, nose, mouth and ears keep the source detailed surfaces.
 # Original hero hair is removed in the new NPC only; close combed hair is a
 # separately authored full-volume scalp below, avoiding compressed UV strips.
 bm=bmesh.new();bm.from_mesh(head.data);bm.verts.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.verts[i] for i in remove],context='VERTS');bm.to_mesh(head.data);bm.free()
 # Derived color map remaps source blue pixels only. Normal/roughness untouched.
 tex_edits=[]
 for mat in body.data.materials:
  for n in mat.node_tree.nodes:
   if n.type!='TEX_IMAGE' or not n.image or 'SaturatedBaseColor' not in n.image.name: continue
   image=n.image.copy(); image.name='TeaPatron_GreyGreen_DerivedBaseColor';pix=np.empty(len(image.pixels),dtype=np.float32);image.pixels.foreach_get(pix);a=pix.reshape((-1,4));a,pm=green_colors(a);image.pixels.foreach_set(a.ravel());image.pack();n.image=image;tex_edits.append({'pixels_blue_remapped':int(pm.sum()),'name':image.name})
 # Sitting needs genuine thigh weights: source white trousers mostly pelvis.
 co=np.array([v.co[:] for v in body.data.vertices]);reweighted=0
 for v in body.data.vertices:
  x,y,z=v.co
  arm_weight=sum(g.weight for g in v.groups if body.vertex_groups[g.group].name.startswith(('upper_arm.','forearm.','hand.')))
  if z<.12 or z>1.10 or (abs(x)>.30 and z>.80) or arm_weight>.10: continue
  for group in list(v.groups): body.vertex_groups[group.group].remove([v.index])
  # Continuous geometric lower-body skinning gives UV-separated vertices the
  # same weights and avoids cracks at a palette or connected-component border.
  pelvis=smooth(.82,1.10,z); thigh=(1-pelvis)*smooth(.42,.64,z); foot=1-smooth(.12,.30,z); shin=max(0,1-pelvis-thigh-foot)
  left=smooth(-.045,.045,x)
  if pelvis>0:body.vertex_groups['pelvis'].add([v.index],pelvis,'REPLACE')
  for side,share in [('R',1-left),('L',left)]:
   for name,w in [('thigh.'+side,thigh*share),('shin.'+side,shin*share),('foot.'+side,foot*share)]:
    if w>1e-6:body.vertex_groups[name].add([v.index],w,'REPLACE')
  reweighted+=1
 # Long front/back skirt is authored onto the seated thighs rather than hanging
 # through the bench. Front panels advance across knees; back panels drape.
 return {'removed_original_tail_vertices':len(remove),'original_tail_remodeled_to_low_bun':True,'adult_face_geometry':True,'body_width_changes':True,'seated_trouser_vertices_reweighted':reweighted,'cloth_palette_vertex_corners':int(mask.sum()),'derived_color_maps':tex_edits}

def skin_mesh(obj,rig,bone):
 group=obj.vertex_groups.new(name=bone);group.add(list(range(len(obj.data.vertices))),1,'REPLACE');mod=obj.modifiers.new('Skeletal attachment','ARMATURE');mod.object=rig;obj.parent=rig

def material(name,color,rough=.7):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;return m

def make_bun(rig):
 # Bespoke rolled hair surface, ellipsoidal with authored spiral ridges and an
 # asymmetrical lower knot. This is a detailed hair mesh, not a head stand-in.
 center=Vector((0,.17,1.77));verts=[];faces=[];nu=100;nv=48
 for j in range(nv+1):
  v=math.pi*j/nv
  for i in range(nu):
   u=math.tau*i/nu;r=1+.065*math.cos(12*u+7*v)+.025*math.cos(23*u-3*v)
   verts.append(tuple(center+Vector((.113*math.sin(v)*math.cos(u)*r,.085*math.sin(v)*math.sin(u)*r,.105*math.cos(v)))))
 for j in range(nv):
  for i in range(nu):a=j*nu+i;b=j*nu+(i+1)%nu;faces.append((a,a+nu,b+nu,b))
 mesh=bpy.data.meshes.new('Tea patron low rolled bun sculpt');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('TeaPatronLowBun',mesh);bpy.context.collection.objects.link(o);o.data.materials.append(material('Patron dark salt brown hair',(.105,.089,.073)))
 for p in mesh.polygons:p.use_smooth=True
 skin_mesh(o,rig,'head');return o

def make_combed_hair(rig):
 verts=[];faces=[];nu=160;nv=56;center=Vector((0,-.005,1.73))
 for j in range(nv+1):
  t=j/nv
  for i in range(nu):
   u=math.tau*i/nu;front=max(0,-math.sin(u));back=max(0,math.sin(u));bound=1.60-.28*front+.32*back;bound+=.027*math.sin(u*5+.6)*front;v=t*bound
   ridge=1+.016*math.cos(34*u+v*8)*math.sin(v)**.5+.005*math.cos(69*u-v*2)
   verts.append(tuple(center+Vector((.154*math.sin(v)*math.cos(u)*ridge,.188*math.sin(v)*math.sin(u)*ridge,.205*math.cos(v)))))
 for j in range(nv):
  for i in range(nu):a=j*nu+i;b=j*nu+(i+1)%nu;faces.append((a,a+nu,b+nu,b))
 mesh=bpy.data.meshes.new('Patron combed crown with directional sculpted hair ridges');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('TeaPatronCombedHair',mesh);bpy.context.collection.objects.link(o);mesh.materials.append(material('Patron combed salt brown hair',(.105,.088,.071),.72))
 for p in mesh.polygons:p.use_smooth=True
 skin_mesh(o,rig,'head');return o

def make_forehead(rig):
 # Local forehead surface completes the area formerly hidden by the hero's
 # large bangs. It joins the retained detailed eyes/face; it is not a new head.
 verts=[];faces=[];nu=64;nv=16
 for j in range(nv+1):
  t=j/nv;z=1.753+t*.073
  for i in range(nu+1):
   width=.128+.023*t;x=-width+2*width*i/nu;z=1.753+t*.073+.010*(x/.153)**2*(1-t);y=-.005-.177*math.sqrt(max(.04,1-(x/.159)**2-((z-1.73)/.205)**2))
   verts.append((x,y,z))
 for j in range(nv):
  for i in range(nu):a=j*(nu+1)+i;faces.append((a,a+1,a+nu+2,a+nu+1))
 mesh=bpy.data.meshes.new('Patron local forehead surface');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('TeaPatronForehead',mesh);bpy.context.collection.objects.link(o);mesh.materials.append(material('Patron forehead warm complexion',(.54,.325,.215),.57))
 for p in mesh.polygons:p.use_smooth=True
 skin_mesh(o,rig,'head');return o

def make_brows(rig):
 verts=[];faces=[]
 for sign in [-1,1]:
  start=len(verts)
  for i in range(25):
   t=i/24;x=sign*(.028+.062*t);z=1.770+.004*math.sin(t*math.pi)-.004*t;y=-.005-.178*math.sqrt(max(.04,1-(x/.159)**2))-.003
   for dz in [-.0025,.0025]:verts.append((x,y,z+dz*(1-.60*t)))
  for i in range(24):a=start+2*i;faces.append((a,a+1,a+3,a+2))
 mesh=bpy.data.meshes.new('Patron low calm eyebrows');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('TeaPatronEyebrows',mesh);bpy.context.collection.objects.link(o);mesh.materials.append(material('Patron eyebrow dark brown',(.075,.057,.042)));skin_mesh(o,rig,'head');return o

def make_headband(rig):
 # A woven everyday wrap, with a shaped double fold around the scalp.
 verts=[];faces=[];n=128
 for j in range(7):
  f=j/6;z=1.815+f*.045
  for i in range(n):
   a=math.tau*i/n;r=1+.017*math.cos(a*11+f*2)+.012*math.sin(f*math.tau)
   verts.append((.164*math.cos(a)*r,-.005+.196*math.sin(a)*r,z+.003*math.cos(a)))
 for j in range(6):
  for i in range(n):a=j*n+i;b=j*n+(i+1)%n;faces.append((a,b,b+n,a+n))
 mesh=bpy.data.meshes.new('Patron narrow folded forehead cloth');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('TeaPatronForeheadWrap',mesh);bpy.context.collection.objects.link(o);mesh.materials.append(material('Patron plain warm grey head cloth',(.28,.27,.235),.88))
 for p in mesh.polygons:p.use_smooth=True
 skin_mesh(o,rig,'head');return o

def make_cup(rig):
 # Revolved stoneware cup with an actual hollow inner wall and tea surface.
 profile=[(.021,-.035),(.037,-.030),(.047,.015),(.050,.030),(.045,.033),(.042,.025),(.034,-.021),(.019,-.023)]
 verts=[];faces=[];n=64;center=Vector((-.445,-.27,1.065))
 for r,z in profile:
  for i in range(n):a=math.tau*i/n;verts.append(tuple(center+Vector((r*math.cos(a),r*math.sin(a),z))))
 for j in range(len(profile)-1):
  for i in range(n):a=j*n+i;b=j*n+(i+1)%n;faces.append((a,b,b+n,a+n))
 mesh=bpy.data.meshes.new('Thrown stoneware cup with inner wall');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('TeaPatronCup',mesh);bpy.context.collection.objects.link(o);mesh.materials.append(material('Patron stoneware warm celadon',(.22,.31,.25),.35));skin_mesh(o,rig,'hand.R');return o

def pose(rig,t,standing=False):
 for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
 bpy.context.view_layer.update()
 if standing:
  base.pose(rig,'Idle',0);return
 breath=math.sin(math.tau*t/6)*.002
 rest=rig.data.bones['pelvis'].matrix_local;shift=Vector((0,0,PELVIS-rest.translation.z));rig.pose.bones['pelvis'].matrix=Matrix.Translation(shift)@rest;bpy.context.view_layer.update()
 # Keep upper body calm, slight natural inclination toward the tabletop.
 spine=rig.pose.bones['spine'];spine.matrix=Matrix.LocRotScale(spine.head,Quaternion((1,0,0),-.055+breath*.7)@spine.matrix.to_quaternion(),Vector((1,1,1)));bpy.context.view_layer.update()
 for side,sign in [('R',-1),('L',1)]:
  hip=rig.pose.bones['thigh.'+side].head.copy();ankle=rig.data.bones['foot.'+side].head_local.copy();ankle.x=sign*.17;ankle.y=-.78 if side=='R' else -.73;ankle.z=rig.data.bones['foot.'+side].head_local.z
  knee,actual,error=base.two_bone(hip,hip+Vector((0,-.6,.35)),ankle,rig.data.bones['thigh.'+side].length,rig.data.bones['shin.'+side].length)
  base.set_segment(rig,'thigh.'+side,hip,knee);base.set_segment(rig,'shin.'+side,knee,actual);foot=rig.data.bones['foot.'+side].matrix_local.copy();foot.translation=actual;rig.pose.bones['foot.'+side].matrix=foot;bpy.context.view_layer.update()
  # Thigh garment panels fold forward over the lap; back hem remains draped.
  for section,factor in [('front',1.0),('back',.46)]:
   bn=rig.pose.bones['skirt.'+section+'.'+side];bn.rotation_mode='QUATERNION';bn.rotation_quaternion=Quaternion((1,0,0),-1.29*factor)
 # Raise begins 7s, sip from 7.65 through 8.60, returns by9.20.
 lift=smooth(7,7.65,t)*(1-smooth(8.60,9.2,t))
 for side,sign in [('R',-1),('L',1)]:
  shoulder=rig.pose.bones['upper_arm.'+side].head.copy()
  low=Vector((sign*.24,-.38,.73));high=Vector((.0122 if side=='R' else .09,-.2103,1.0421));wrist=low.lerp(high,lift) if side=='R' else Vector((.245,-.44,.64))
  pole=shoulder+Vector((sign*.40,-.02,-.3));elbow,actual,error=base.two_bone(shoulder,pole,wrist,rig.data.bones['upper_arm.'+side].length,rig.data.bones['forearm.'+side].length)
  base.set_segment(rig,'upper_arm.'+side,shoulder,elbow);base.set_segment(rig,'forearm.'+side,elbow,actual)
  hand=rig.data.bones['hand.'+side].matrix_local.copy();hand.translation=actual
  if side=='R':hand=Matrix.Translation(actual)@Matrix.Rotation(-.48*lift,4,'X')@Matrix.Translation(-actual)@hand
  rig.pose.bones['hand.'+side].matrix=hand
 bpy.context.view_layer.update()
 return {'time':t,'lift':lift,'pelvis':list(rig.pose.bones['pelvis'].head),'feet':{s:list(rig.pose.bones['foot.'+s].head) for s in ['R','L']}}

def evaluated_coordinates(obj):
 evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh();coordinates=np.array([v.co[:] for v in mesh.vertices]);evaluated.to_mesh_clear();return coordinates

def author_and_verify(rig,objects,review):
 action=bpy.data.actions.new('PatronTea');rig.animation_data.action=action
 head=next(o for o in objects if o.name=='JiangApprovedHead');grip=next(o for o in objects if o.name=='JiangRightGrip_HandGrip');head_rest=np.array([v.co[:] for v in head.data.vertices]);texture=sampled_texture_colors(head);lip_ids=np.flatnonzero((abs(head_rest[:,0])<.025)&(head_rest[:,1]<-.15)&(head_rest[:,2]>1.645)&(head_rest[:,2]<1.685));lip_ids=lip_ids[np.argsort(texture[lip_ids,:3].mean(1))[:5]]
 body=next(o for o in objects if o.name=='JiangFullbody');cup=next(o for o in objects if o.name=='TeaPatronCup');rest=np.array([v.co[:] for v in body.data.vertices]);boots={side:np.flatnonzero((rest[:,2]<.20)&(rest[:,0]*sign>.04)) for side,sign in [('R',-1),('L',1)]};seat_index=880
 samples=[];boundary={};contact=[];sip=[];hand_contacts=[]
 for frame in range(721):
  bpy.context.scene.frame_set(frame);row=pose(rig,frame/FPS)
  for bone in rig.pose.bones:
   bone.rotation_mode='QUATERNION'
   for channel in ['location','rotation_quaternion','scale']:bone.keyframe_insert(channel,frame=frame)
  samples.append(row)
  if frame%6==0 or frame in [420,459,516,552,720]:
   a=evaluated_coordinates(body);c=evaluated_coordinates(cup);contact.append({'frame':frame,'seconds':frame/FPS,'seat_surface_vertex':a[seat_index].tolist(),'boot_min_z':{side:float(a[ids,2].min()) for side,ids in boots.items()},'cup_center':c.mean(0).tolist(),'right_hand_head':list(rig.pose.bones['hand.R'].head)})
   if 7.65<=frame/FPS<=8.60:
    face=evaluated_coordinates(head);lip=face[lip_ids].mean(0);rim=c[3*64:5*64];distances=np.linalg.norm(rim-lip,axis=1);nearest=rim[distances.argmin()];sip.append({'frame':frame,'back_rim_vertex_208':c[208].tolist(),'back_rim_lip_distance_m':float(np.linalg.norm(c[208]-lip)),'lip_mean':lip.tolist(),'nearest_actual_cup_rim_vertex':nearest.tolist(),'actual_rim_lip_distance_m':float(distances.min())})
   if frame in [0,420,459,486,516,552,720]:
    hand=evaluated_coordinates(grip);distance=np.linalg.norm(hand[:,None,:]-c[None,:,:],axis=2);hand_contacts.append({'frame':frame,'actual_cup_vertex_to_hand_vertex_distance_m':float(distance.min())})
  if frame in [0,720]:boundary[frame]={o.name:evaluated_coordinates(o) for o in objects}
 loop=max(float(np.linalg.norm(boundary[0][name]-boundary[720][name],axis=1).max()) for name in boundary[0]);seat_points=np.array([r['seat_surface_vertex'] for r in contact]);seat_error=float(np.linalg.norm(seat_points-seat_points[0],axis=1).max());foot_error=max(abs(r['boot_min_z'][side]-FLOOR) for r in contact for side in boots)
 foot_drift=max(abs(r['boot_min_z'][side]-contact[0]['boot_min_z'][side]) for r in contact for side in boots)
 if seat_error>.0001 or foot_error>.001 or foot_drift>.00001 or loop>.00001:raise RuntimeError('Seated source anchors/loop failed '+repr((seat_error,foot_error,loop)))
 anchor=[float(seat_points[0,0]),float(seat_points[0,2]),float(-seat_points[0,1])];floor=float(min(r['boot_min_z'][side] for r in contact for side in boots));scale=.3025/(anchor[1]-floor)
 report={'fps':FPS,'duration_seconds':12,'frames_including_endpoint':721,'actual_evaluated_contact_frames':len(contact),'source_seat_contact_gltf':anchor,'source_floor_y':floor,'display_scale_for_03025m_world_gap':scale,'source_seat_vertex_index':seat_index,'maximum_actual_seat_surface_vertex_drift_m':seat_error,'maximum_actual_boot_floor_error_m':foot_error,'maximum_actual_boot_floor_drift_m':foot_drift,'source_sole_height_asymmetry_m':{side:contact[0]['boot_min_z'][side]-FLOOR for side in boots},'whole_cast_loop_endpoint_vertex_error_m':loop,'lip_marker_post_trim_head_vertex_ids':[int(i) for i in lip_ids],'lip_marker_selection':'Five original red lip-line texture samples in the central 5cm-wide mouth, post-edit rest height1.645–1.685m; actual front/side closeups and markers in mouth-landmark-confirmation.json','sip_actual_rim_lip_samples':sip,'sip_minimum_actual_rim_lip_distance_m':min(r['actual_rim_lip_distance_m'] for r in sip),'sip_maximum_actual_rim_lip_distance_m':max(r['actual_rim_lip_distance_m'] for r in sip),'hand_contact_vertex_samples':hand_contacts,'maximum_actual_cup_hand_vertex_distance_m':max(r['actual_cup_vertex_to_hand_vertex_distance_m'] for r in hand_contacts),'samples':contact,'motion_samples':samples}
 (review/'actual-contact-and-motion.json').write_text(json.dumps(report,indent=2)+'\n')
 track=rig.animation_data.nla_tracks.new();track.name='PatronTea';track.strips.new('PatronTea',0,action);track.mute=True;rig.animation_data.action=None;pose(rig,0)
 return report

def export_asset(rig,objects,output,review,contract):
 output.parent.mkdir(parents=True,exist_ok=True);bpy.ops.object.select_all(action='DESELECT')
 for obj in [rig]+objects:obj.select_set(True)
 bpy.context.view_layer.objects.active=rig;bpy.context.scene.frame_start=0;bpy.context.scene.frame_end=720
 bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_texcoords=True,export_vertex_color='NAME',export_vertex_color_name='Color',export_all_vertex_colors=False,export_normals=True,export_tangents=False,export_materials='EXPORT',export_image_format='AUTO',export_animations=True,export_animation_mode='NLA_TRACKS',export_frame_range=False,export_force_sampling=True,export_nla_strips=True,export_skins=True,export_def_bones=False,export_all_influences=False,export_cameras=False,export_lights=False)
 _,gltf,_=base.read_glb(output);return {'path':str(output),'bytes':output.stat().st_size,'sha256':sha(output),'triangles':sum(gltf['accessors'][p['indices']]['count']//3 for m in gltf['meshes'] for p in m['primitives']),'animations':[a['name'] for a in gltf.get('animations',[])],'skin_joint_count':len(gltf['skins'][0]['joints']),'mesh_count':len(gltf['meshes']),'texture_payloads':base.texture_payloads(output)}

def review_scene(rig,objects,out):
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16;scene.render.threads_mode='FIXED';scene.render.threads=8;scene.render.resolution_x=640;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.world=bpy.data.worlds.new('Neutral daylight');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.73,.76,.71,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.55;scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
 bpy.ops.object.camera_add();cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=2.5;scene.camera=cam
 bpy.ops.object.light_add(type='AREA',location=(-3,-4,5));key=bpy.context.object;key.data.energy=330;key.data.size=4;key.rotation_euler=(Vector((0,0,1))-key.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.001));floor=bpy.context.object;floor.data.materials.append(material('QA matte floor',(.58,.60,.53)))
 bpy.ops.mesh.primitive_cube_add(size=1,location=(0,.005,SEAT-.03));bench=bpy.context.object;bench.name='QA seat contact reference only';bench.scale=(.60,.28,.06);bench.data.materials.append(material('QA wood',(.23,.16,.095)))
 renders=[]
 for view,standing,time in [('front',True,0),('side',True,0),('back',True,0),('seated-front',False,0),('seated-side',False,0),('seated-back',False,0),('sip-front',False,8.1),('sip-side',False,8.1)]:
  pose(rig,time,standing);bench.hide_render=standing
  cam.location={'front':(0,-5,2.35),'side':(5,0,2.1),'back':(0,5,2.35),'seated-front':(0,-5,2.15),'seated-side':(5,0,1.5),'seated-back':(0,5,2.15),'sip-front':(0,-5,2.15),'sip-side':(5,0,1.5)}[view];target=Vector((0,-.12,1.0 if standing else .73));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();path=out/(view+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True);renders.append(str(path))
 # Native geometry closeups and separate diagnostic markers confirm that the
 # authored landmark is on the lips rather than the previous dark chin sample.
 pose(rig,8.1);head=next(o for o in objects if o.name=='JiangApprovedHead');cup=next(o for o in objects if o.name=='TeaPatronCup');hr=np.array([v.co[:] for v in head.data.vertices]);tc=sampled_texture_colors(head);ids=np.flatnonzero((abs(hr[:,0])<.025)&(hr[:,1]<-.15)&(hr[:,2]>1.645)&(hr[:,2]<1.685));ids=ids[np.argsort(tc[ids,:3].mean(1))[:5]];hp=evaluated_coordinates(head);cp=evaluated_coordinates(cup);lip=hp[ids].mean(0);landmarks={'lip_source_head_vertex_ids':[int(i) for i in ids],'lip_vertices_blender':[hp[i].tolist() for i in ids],'lip_mean_blender':lip.tolist(),'back_cup_rim_vertex208_blender':cp[208].tolist(),'lip_mean_gltf_yup':[float(lip[0]),float(lip[2]),float(-lip[1])],'cup_back_rim_gltf_yup':[float(cp[208,0]),float(cp[208,2]),float(-cp[208,1])],'hand_right_head_gltf_yup':[float(rig.pose.bones['hand.R'].head.x),float(rig.pose.bones['hand.R'].head.z),float(-rig.pose.bones['hand.R'].head.y)]}
 (out/'mouth-landmark-confirmation.json').write_text(json.dumps(landmarks,indent=2)+'\n');cam.data.ortho_scale=.34
 for marked in [False,True]:
  if marked:
   mat=material('QA lip landmarks yellow',(.95,.65,.02));cmat=material('QA cup rim landmark blue',(.02,.20,.95))
   for index,point in enumerate([hp[i] for i in ids]+[cp[208]]):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,radius=.0016,location=point);marker=bpy.context.object;marker.name='QA contact marker';marker.data.materials.append(mat if index<len(ids) else cmat)
  for view in ['front','side']:
   cam.location=Vector(lip)+Vector((0,-2,.15) if view=='front' else (2,-.05,.12));target=Vector(lip)+Vector((0,0,.025));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();path=out/('mouth-contact-'+view+('-marked' if marked else '')+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True);renders.append(str(path))
 return renders

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--input',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--review',type=Path,required=True);parser.add_argument('--static-only',action='store_true');args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);source=args.input.resolve();out=args.output.resolve();review=args.review.resolve();review.mkdir(parents=True,exist_ok=True)
 if sha(source)!=BASE_SHA or out==source:raise RuntimeError('Immutable exact approved source required')
 bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene;scene.render.fps=FPS;bpy.ops.import_scene.gltf(filepath=str(source));rig=next(o for o in scene.objects if o.type=='ARMATURE');objects=[o for o in scene.objects if o.type=='MESH' and o.name in KEEP]
 for o in list(scene.objects):
  if o!=rig and o not in objects:bpy.data.objects.remove(o,do_unlink=True)
 rig.animation_data_clear()
 for a in list(bpy.data.actions):bpy.data.actions.remove(a)
 rig.animation_data_create();[setattr(b,'matrix_basis',Matrix.Identity(4)) for b in rig.pose.bones];bpy.context.view_layer.update();edits=edit_geometry(rig,objects);objects+=[make_bun(rig),make_cup(rig),make_combed_hair(rig),make_forehead(rig),make_brows(rig),make_headband(rig)]
 pose(rig,0);contract=None;asset=None
 if not args.static_only:
  contract=author_and_verify(rig,objects,review);asset=export_asset(rig,objects,out,review,contract)
 blend=review/('tea-patron-static.blend' if args.static_only else 'tea-patron-authored.blend');bpy.ops.wm.save_as_mainfile(filepath=str(blend));renders=review_scene(rig,objects,review)
 report={'status':'candidate-parent-visual-review','input':str(source),'source_sha256_before_and_after':sha(source),'tool_sha256':sha(__file__),'geometry_edits':edits,'asset':asset,'motion_and_contact_summary':({k:v for k,v in contract.items() if k not in ['samples','motion_samples']} if contract else None),'anchors':{'blender_up':'+Z','blender_front':'-Y','gltf_up':'+Y','gltf_front':'+Z','source_floor_m':FLOOR,'source_seat_contact_m':SEAT,'source_pelvis_m':PELVIS,'suggested_scale_for_world_seat_gap':.3025/(SEAT-FLOOR)},'renders':renders,'blend':str(blend)}
 (review/('static-review.json' if args.static_only else 'authoring-report.json')).write_text(json.dumps(report,indent=2)+'\n')
 print('PATRON_AUTHORING_READY',str(review/('static-review.json' if args.static_only else 'authoring-report.json')))
if __name__=='__main__':main()
