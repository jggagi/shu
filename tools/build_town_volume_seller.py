#!/usr/bin/env python3
"""Author a separate, adult tea-seller derivative of the approved warm Jiang.

No source payload restoration: face/body vertices, linear vertex tint and rest
joint positions below are intentional NPC edits. Retain original six textures,
complete hand and detailed source garments. Blender --disable-autoexec only.
"""
from __future__ import annotations
import bpy,bmesh,numpy as np
import math,json,hashlib,argparse,sys,runpy
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
BASE=Path('/home/x1-lite/games/shu/.local/worktrees/mountain-ambush/assets/art/mountain_ambush/jiang-approved.glb')
BASE_SHA='e8d74b2e0be789f272597aa6f7fc268f57851bb669ed43d97e2efa91c3860e27'
FLOOR=.000216
lib=runpy.run_path(str(ROOT/'tools/build_town_volume_character.py'),run_name='town_volume_lib')
two_bone,set_segment=lib['two_bone'],lib['set_segment']

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def smooth(v):v=max(0,min(1,v));return v*v*(3-2*v)
def srgb(v):return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4

def mat(name,hex,rough=.85):
 m=bpy.data.materials.new(name);m.use_nodes=True;c=tuple(srgb(int(hex[i:i+2],16)/255)for i in (1,3,5))+(1,)
 m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=c;m.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=rough;m.diffuse_color=c;return m

def bind_mesh(name,verts,faces,material,rig,weights):
 data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update();o=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(o);data.materials.append(material)
 for p in data.polygons:p.use_smooth=True
 for group in sorted({g for row in weights for g in row}):
  vg=o.vertex_groups.new(name=group)
  for i,row in enumerate(weights):
   if row.get(group,0)>0:vg.add([i],row[group],'REPLACE')
 mod=o.modifiers.new('Original source22bone skin','ARMATURE');mod.object=rig;return o

def pipe(verts,faces,points,radii,steps=12):
 pts=[];rs=[]
 for i in range(len(points)-1):
  a,b,c,d=[Vector(points[j])for j in [max(0,i-1),i,i+1,min(len(points)-1,i+2)]]
  for j in range(5):
   t=j/5;pts.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t));rs.append(radii[i]*(1-t)+radii[i+1]*t)
 pts.append(Vector(points[-1]));rs.append(radii[-1]);start=len(verts)
 for i,p in enumerate(pts):
  axis=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized();ref=Vector((0,0,1))if abs(axis.z)<.9 else Vector((0,1,0));u=axis.cross(ref).normalized();v=axis.cross(u).normalized()
  for j in range(steps):a=math.tau*j/steps;verts.append(tuple(p+rs[i]*(math.cos(a)*u+math.sin(a)*v)))
 for i in range(len(pts)-1):
  for j in range(steps):a=start+i*steps+j;b=start+i*steps+(j+1)%steps;faces.append((a,b,b+steps,a+steps))
 faces.append(tuple(start+j for j in reversed(range(steps))));faces.append(tuple(start+(len(pts)-1)*steps+j for j in range(steps)))

def cloth_shell(name,rows,cols,point,material,rig,weightfn,thick=.004):
 verts=[];faces=[];ws=[]
 for layer in [0,1]:
  for r in range(rows):
   for c in range(cols):
    p=Vector(point(r/(rows-1),c/(cols-1)));p.y+=layer*thick;verts.append(tuple(p));ws.append(weightfn(p))
 count=rows*cols
 for r in range(rows-1):
  for c in range(cols-1):
   a=r*cols+c;faces.extend([(a,a+1,a+cols+1,a+cols),(a+count,a+cols+count,a+cols+1+count,a+1+count)])
 edge=list(range(cols))+[r*cols+cols-1 for r in range(1,rows)]+list(range(count-2,count-cols-1,-1))+[r*cols for r in range(rows-2,0,-1)]
 for a,b in zip(edge,edge[1:]+edge[:1]):faces.append((a,b,b+count,a+count))
 return bind_mesh(name,verts,faces,material,rig,ws)

def body_map(v):
 x,y,z=v;shoulder=smooth((z-.95)/.35)*(1-smooth((z-1.48)/.15));waist=math.exp(-((z-1.02)/.3)**2)
 return Vector((x*(1.045+.20*shoulder+.07*waist),-.10+(y+.10)*(1+.12*waist),z))

def head_map(v):
 x,y,z=v;front=smooth((.04-y)/.18);jaw=math.exp(-((z-1.665)/.075)**2)*front
 x*=1+.22*jaw;z-=.038*jaw
 nose=math.exp(-(x/.035)**2-((z-1.75)/.055)**2)*smooth((-.10-y)/.09);y-=.024*nose
 for ex in [-.065,.065]:
  eye=math.exp(-((x-ex)/.046)**2-((z-1.795)/.032)**2)*front
  z+=(1.795-z)*eye*.65
  x+=(ex-x)*eye*.20
 blend=smooth((z-1.52)/.11)
 return Vector((x*(1-.13*blend),-.1+(y+.1)*(1-.045*blend),1.57+(z-1.57)*(1-.075*blend)))

def image_samples(obj):
 m=obj.data.materials[0];images=[n.image for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and ('SaturatedBaseColor'in n.image.name)]
 if not images:raise RuntimeError('Original albedo missing')
 image=images[0];w,h=image.size;pixels=np.empty(w*h*4,dtype=np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape(h,w,4)
 uv=np.empty(len(obj.data.loops)*2,dtype=np.float32);obj.data.uv_layers.active.data.foreach_get('uv',uv);uv=uv.reshape(-1,2)
 return pixels[(uv[:,1]*h).astype(int).clip(0,h-1),(uv[:,0]*w).astype(int).clip(0,w-1),:3]

def colors(obj,kind):
 m=obj.data;n=len(m.loops);layer=m.color_attributes.get('Color');data=np.ones((n,4),dtype=np.float32)
 if layer:layer.data.foreach_get('color',data.ravel());m.color_attributes.remove(layer)
 layer=m.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
 ids=np.array([l.vertex_index for l in m.loops]);co=np.array([v.co[:]for v in m.vertices])[ids]
 if kind=='body':
  sample=image_samples(obj);blue=(sample[:,2]>sample[:,0]*1.04)&(sample[:,2]>sample[:,1]*.95);neck=(np.abs(co[:,0])<.10)&(co[:,2]>1.47)
  data[blue,:3]*=np.array([1.,.12,.025]);data[~blue&~neck,:3]*=np.array([.88,.79,.65]);data[(co[:,2]<.36)&blue,:3]*=np.array([.60,.65,.65])
 elif kind=='head':
  sample=image_samples(obj);skin=(sample[:,0]>.38)&(sample[:,1]>.20)&(sample[:,0]>sample[:,2]*1.12)&(sample[:,0]>sample[:,1]*1.02)&(co[:,1]<.04)&(co[:,2]<1.88)
  data[skin,:3]*=np.array([.92,.86,.79]);hair=~skin&(sample.max(1)<.68);data[hair,:3]*=np.array([.42,.36,.30]);blue=(sample[:,2]>sample[:,0]*1.05)&(sample[:,2]>sample[:,1]*.95)&(co[:,2]<1.68);data[blue,:3]*=np.array([1.,.12,.025])
 else:data[:,:3]*=np.array([.92,.86,.79])
 layer.data.foreach_set('color',data.ravel());m.color_attributes.active_color=layer;m.color_attributes.render_color_index=m.color_attributes.find('Color')
 for material in m.materials:
  t=material.node_tree;p=t.nodes.get('Principled BSDF')
  if not p or any(n.type in ['VERTEX_COLOR','ATTRIBUTE']for n in t.nodes):continue
  old=p.inputs['Base Color'].links[0].from_socket if p.inputs['Base Color'].links else None;value=tuple(p.inputs['Base Color'].default_value)
  vc=t.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';mix=t.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
  if old:t.links.new(old,mix.inputs[1])
  else:mix.inputs[1].default_value=value
  t.links.new(vc.outputs['Color'],mix.inputs[2]);t.links.new(mix.outputs[0],p.inputs['Base Color'])

def make_seller(out):
 assert sha(BASE)==BASE_SHA
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=60;bpy.ops.import_scene.gltf(filepath=str(BASE))
 rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');head=bpy.data.objects['JiangApprovedHead'];body=bpy.data.objects['JiangFullbody'];grip=bpy.data.objects['JiangRightGrip_HandGrip']
 for o in list(bpy.context.scene.objects):
  if o not in [rig,head,body,grip]:bpy.data.objects.remove(o,do_unlink=True)
 rig.animation_data_clear()
 for a in list(bpy.data.actions):bpy.data.actions.remove(a)
 for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
 # Remove the original long ponytail only in this new merchant derivative.
 pony=head.vertex_groups.get('ponytail');remove=[]
 samples=image_samples(head);ids=np.array([l.vertex_index for l in head.data.loops]);rgb=np.zeros((len(head.data.vertices),3));counts=np.zeros(len(head.data.vertices));np.add.at(rgb,ids,samples);np.add.at(counts,ids,1);rgb/=np.maximum(counts,1)[:,None]
 for v in head.data.vertices:
  g=any(w.group==pony.index and w.weight>.55 for w in v.groups)if pony else False
  color=rgb[v.index];skin=color[0]>.38 and color[1]>.20 and color[0]>color[2]*1.12 and color[0]>color[1]*1.02
  # The head source is a bust with fragments of its former garment. Retain
  # central front skin under the jaw, while omitting overlapping old collar
  # triangles around the shoulders; mouth/nose/eyes lie above this crop.
  central_neck_skin=skin and abs(v.co.x)<.105 and -.19<v.co.y<.015
  old_collar=v.co.z<1.64 and not central_neck_skin
  if g or old_collar or (v.co.y>.12 and v.co.z>1.56) or (v.co.y>.06 and v.co.z<1.86) or (v.co.z>1.84):remove.append(v.index)
  elif v.co.y<.055 and v.co.z>1.79 and rgb[v.index].max()<.84 and not(abs(v.co.x)<.115 and v.co.y<-.17 and v.co.z<1.82):
   v.co.z=1.89+(v.co.z-1.89)*.16;v.co.y=.015+(v.co.y-.015)*.67
 bm=bmesh.new();bm.from_mesh(head.data);bm.verts.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.verts[i]for i in remove],context='VERTS');bm.to_mesh(head.data);bm.free()
 for v in head.data.vertices:v.co=head_map(v.co)
 for obj in [body,grip]:
  for v in obj.data.vertices:v.co=body_map(v.co)
 bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 for b in rig.data.edit_bones:
  b.head=body_map(b.head);b.tail=body_map(b.tail)
 bpy.ops.object.mode_set(mode='OBJECT');bpy.context.view_layer.update()
 colors(head,'head');colors(body,'body');colors(grip,'grip')
 # Keep original normals/roughness maps and detailed albedo payloads. Newly
 # sculpted vertices recompute their geometric normals, without new raster art.
 for obj in [head,body,grip]:
  try:obj.data.normals_split_custom_set([(0,0,0)]*len(obj.data.loops))
  except RuntimeError:pass
 head.name='TeaSellerAdultHead';body.name='TeaSellerBrownClothing';grip.name='TeaSellerRightHand'
 hair=mat('Seller dark chestnut hair','#302a24',.82);linen=mat('Seller unbleached linen','#c5b394',.95);stitch=mat('Seller apron seam','#a18b67',.96)
 props=[]
 # A small, solid tailored collar covers the retained source body's broken
 # collar rim. This is a garment layer, not an attempt to paint holes black.
 collar_mat=mat('Seller brown folded collar','#765446',.94)
 def collar_point(r,c):
  a=math.tau*c;rx=.108+.130*r;ry=.106+.126*r
  z=1.635-.205*r+.006*math.cos(a*2)*math.sin(math.pi*r)
  fold=.003*math.sin(a*8)*math.sin(math.pi*r)
  return ((rx+fold)*math.sin(a),-.035-(ry+fold)*math.cos(a),z)
 props.append(cloth_shell('SellerTailoredCollar',11,65,collar_point,collar_mat,rig,lambda p:{'spine':1},.005))
 # An authored short compact knot of tapered, curved hair locks, not a sphere.
 for i in range(12):
  a=math.tau*i/12;dx=.050*math.cos(a);dz=.035*math.sin(a);v=[];f=[]
  pipe(v,f,[(dx*.6,.155,1.82+dz*.4),(dx,.205,1.85+dz),(dx*.8,.225,1.86+dz*.5),(dx*.2,.218,1.825)],[.014,.022,.018,.003],10)
  props.append(bind_mesh('SellerShortHairLock%02d'%i,v,f,hair,rig,[{'head':1}for _ in v]))
 # A pleated working headwrap covers the combed-up former fringe. This is
 # a finite cloth shell with an authored profile and raised seams.
 capmat=mat('Seller weathered brown headwrap','#7b6950',.96)
 profiles=[(1.800,.180,.209),(1.855,.185,.204),(1.920,.160,.178),(1.970,.110,.124),(1.995,.051,.063),(2.003,.003,.004)]
 def cap_point(r,c):
  f=r*(len(profiles)-1);i=min(len(profiles)-2,int(f));t=f-i;z,rx,ry=[profiles[i][k]*(1-t)+profiles[i+1][k]*t for k in range(3)];a=math.tau*c;fold=.006*math.sin(a*13+r*2)*math.sin(math.pi*r)+.0018*math.sin(a*23-r*4)*math.sin(math.pi*r)
  return ((rx+fold)*math.sin(a),.006-(ry+fold)*math.cos(a),z-.105*(1-math.cos(a))*.5*(1-r)**2)
 props.append(cloth_shell('SellerPleatedWorkingHeadwrap',23,65,cap_point,capmat,rig,lambda p:{'head':1},.003))
 for strand in range(7):
  v=[];f=[];points=[cap_point(.1+i*.085,strand/7) for i in range(10)];pipe(v,f,points,[.0013]*10,6);props.append(bind_mesh('SellerHeadwrapSeam%02d'%strand,v,f,capmat,rig,[{'head':1}for _ in v]))
 for sign in [-1,1]:
  props.append(cloth_shell('SellerHeadwrapBackTail'+str(sign),8,3,lambda r,c:(sign*(.026+.012*r)+(c-.5)*.019,.185+.012*r,1.84-.105*r),capmat,rig,lambda p:{'head':1},.003))
 # Fine adult moustache/goatee, projected on the actual sculpted face surface.
 tree=BVHTree.FromPolygons([v.co[:]for v in head.data.vertices],[p.vertices[:]for p in head.data.polygons],all_triangles=False)
 def front_y(x,z):
  hit=tree.ray_cast(Vector((x,-2,z)),Vector((0,1,0)),4)
  return hit[0].y-.002 if hit[0] else -.20
 for sign in [-1,1]:
  for row in range(3):
   points=[]
   for i in range(5):
    x=sign*(.008+i*.011);z=1.685-row*.004-i*.001
    points.append((x,front_y(x,z),z))
   v=[];f=[];pipe(v,f,points,[.001,.0025,.0026,.002,.0005],7);props.append(bind_mesh('SellerMoustache%d-%d'%(sign,row),v,f,hair,rig,[{'head':1}for _ in v]))
 for i in range(5):
  x=(i-2)*.006;points=[]
  for j in range(4):z=1.636-j*.008;points.append((x,front_y(x,z),z))
  v=[];f=[];pipe(v,f,points,[.0015,.002,.002,.0004],7);props.append(bind_mesh('SellerChinStubble%d'%i,v,f,hair,rig,[{'head':1}for _ in v]))
 # Apron follows the actual brown garment surface, with a closed cloth edge.
 treebody=BVHTree.FromPolygons([v.co[:]for v in body.data.vertices],[p.vertices[:]for p in body.data.polygons],all_triangles=False)
 def garment_y(x,z):
  hit=treebody.ray_cast(Vector((x,-2,z)),Vector((0,1,0)),4)
  return (hit[0].y if hit[0] else -.23)-.012
 def apronpoint(r,c):
  z=1.34-r*.82;width=.17+.14*smooth(r/.42);x=(c-.5)*2*width;y=(-.275-.092*smooth(r/.42))+.032*((c-.5)*2)**2-.007*math.sin(c*math.pi*5)*smooth(r/.30)
  return x,y,z
 def apronweights(p):
  v=smooth((p.z-1.02)/.25);return {'pelvis':1-v,'spine':v}
 props.append(cloth_shell('SellerLinenApron',29,23,apronpoint,linen,rig,apronweights,.005))
 def pocket_point(r,c):
  z=.90-r*.13;x=(c-.5)*.23;ar=(1.34-z)/.82;width=.17+.14*smooth(ar/.42);ac=(x/width+1)/2;p=Vector(apronpoint(ar,ac));p.y-=.012;return p
 props.append(cloth_shell('SellerApronPocket',8,11,pocket_point,linen,rig,lambda p:{'pelvis':1},.006))
 for side in [-1,1]:
  props.append(cloth_shell('SellerApronNeckStrap'+str(side),10,3,lambda r,c:(side*(.145-.065*r)+(c-.5)*.024,garment_y(side*(.145-.065*r),1.33+.15*r)-.008,1.33+.15*r),linen,rig,lambda p:{'spine':1},.004))
 def waistband(r,c):
  a=math.tau*c;z=1.025+(r-.5)*.026
  # Cast outward from within the torso: an inward cast from outside could
  # accidentally hit a sleeve instead of the body of the garment.
  center=Vector((0,-.08,z));direction=Vector((math.sin(a),-math.cos(a),0));hit=treebody.ray_cast(center,direction,.45)
  p=hit[0]+direction*.007 if hit[0] else center+Vector((.23*math.sin(a),-.14*math.cos(a),0))
  return p
 props.append(cloth_shell('SellerApronWaistTie',3,65,waistband,linen,rig,lambda p:{'pelvis':1},.004))
 for sign in [-1,1]:
  props.append(cloth_shell('SellerApronDownwardTie'+str(sign),10,3,lambda r,c:(sign*(.070+.012*r)+(c-.5)*.030,.060+.010*math.sin(math.pi*r),1.028-.185*r),linen,rig,lambda p:{'pelvis':1},.004))
 hand_quats={}
 cloth_offset=None
 cupcentre=None
 pose_diagnostics=[]
 def pose(frame,diagnose=False):
  t=frame/60
  for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
  pelvis=rig.pose.bones['pelvis'];p=pelvis.bone.matrix_local.copy();p.translation.z-=.025;pelvis.matrix=p;bpy.context.view_layer.update()
  # The waist and supported boots stay fixed. Breathing and attention live in
  # the upper trunk; global hand goals keep the held ceramic cup steady.
  breath=math.sin(math.tau*t/7)
  work=smooth((t-1.55)/.45)*(1-smooth((t-5)/.45))
  rig.pose.bones['spine'].rotation_mode='QUATERNION';rig.pose.bones['spine'].rotation_quaternion=Quaternion((1,0,0),.0045*breath)
  rig.pose.bones['chest'].rotation_mode='QUATERNION';rig.pose.bones['chest'].rotation_quaternion=Quaternion((1,0,0),.003*breath)
  rig.pose.bones['head'].rotation_mode='QUATERNION';rig.pose.bones['head'].rotation_quaternion=Quaternion((1,0,0),.045*work+.004*math.sin(math.tau*t/14))
  bpy.context.view_layer.update()
  for side in ['R','L']:
   hip=rig.pose.bones['thigh.'+side].head.copy();ankle=rig.data.bones['foot.'+side].head_local.copy();k,e,err=two_bone(hip,hip+Vector((0,-.7,-.3)),ankle,rig.data.bones['thigh.'+side].length,rig.data.bones['shin.'+side].length)
   set_segment(rig,'thigh.'+side,hip,k);set_segment(rig,'shin.'+side,k,e);p=rig.data.bones['foot.'+side].matrix_local.copy();p.translation=e;rig.pose.bones['foot.'+side].matrix=p;bpy.context.view_layer.update()
  wrists={'R':Vector((-.10,-.35,1.145)),'L':Vector((.37,-.14,.99))}
  if cloth_offset is not None and cupcentre is not None:
   # A short lift, five small rubbing strokes, then a controlled return. The
   # cloth's actual authored face is brought to the front of the cup wall.
   stroke=math.tau*(t-2)/.6
   target=cupcentre+Vector((.011*math.sin(stroke),-.058,.047+.019*math.cos(stroke)))
   wrists['L']=wrists['L'].lerp(target-cloth_offset,work)
  frame_err={}
  for side,wrist in wrists.items():
   shoulder=rig.pose.bones['upper_arm.'+side].head.copy();pole=shoulder+Vector((-.28 if side=='R'else .28,.14,-.20));elbow,end,err=two_bone(shoulder,pole,wrist,rig.data.bones['upper_arm.'+side].length,rig.data.bones['forearm.'+side].length)
   frame_err[side]=err
   if err>.0001:raise RuntimeError('Seller arm target outside actual limb length: '+str((frame,side,err)))
   set_segment(rig,'upper_arm.'+side,shoulder,elbow);set_segment(rig,'forearm.'+side,elbow,end);direction=(end-elbow).normalized()
   if side in hand_quats:rig.pose.bones['hand.'+side].matrix=Matrix.LocRotScale(end,hand_quats[side],Vector((1,1,1)))
   else:set_segment(rig,'hand.'+side,end,end+direction*rig.data.bones['hand.'+side].length)
  bpy.context.view_layer.update()
  if diagnose:pose_diagnostics.append({'frame':frame,'arm_ik_errors':frame_err})
 pose(0)
 # Calibrate actual original hand geometry and bind cup/cloth through its Skin.
 handR=rig.pose.bones['hand.R'].matrix.copy();restR=rig.data.bones['hand.R'].matrix_local.copy();transform=handR@restR.inverted();gcentre=sum((transform@v.co for v in grip.data.vertices),Vector())/len(grip.data.vertices)
 cupcentre=gcentre+Vector((.073,-.015,-.025));cupmat=mat('Seller pale celadon cup','#acb7aa',.38);v=[];f=[]
 profile=[(.029,0),(.034,.005),(.044,.013),(.061,.071),(.062,.078),(.058,.082),(.054,.077),(.040,.022),(.027,.017)]
 for radius,z in profile:
  for i in range(40):a=math.tau*i/40;v.append(tuple(cupcentre+Vector((radius*math.cos(a),radius*math.sin(a),z))))
 for r in range(len(profile)-1):
  for i in range(40):a=r*40+i;b=r*40+(i+1)%40;f.append((a,b,b+40,a+40))
 h=[]
 for i in range(8):a=-math.pi/2+math.pi*i/7;h.append(tuple(cupcentre+Vector((-.062-.035*math.cos(a),0,.043+.030*math.sin(a)))))
 pipe(v,f,h,[.006]*len(h),10)
 bind=restR@handR.inverted();cup=bind_mesh('SellerCeladonCup',[bind@Vector(p)for p in v],f,cupmat,rig,[{'hand.R':1}for _ in v]);props.append(cup)
 handL=rig.pose.bones['hand.L'].matrix.copy();restL=rig.data.bones['hand.L'].matrix_local.copy();clothcentre=handL.translation+(handL.to_quaternion()@Vector((0,.09,0)));bindL=restL@handL.inverted();cloth=cloth_shell('SellerWipingCloth',9,9,lambda r,c:bindL@(clothcentre+Vector(((c-.5)*.13,-.012+.006*math.sin(c*math.pi*3),(.5-r)*.095+.004*math.sin(r*math.pi*2)))),linen,rig,lambda p:{'hand.L':1},.008);props.append(cloth)
 hand_quats.update({'R':handR.to_quaternion(),'L':handL.to_quaternion()})
 cloth_offset=clothcentre-handL.translation
 rig.animation_data_create();action=bpy.data.actions.new('SellerCupWork');rig.animation_data.action=action
 for frame in range(841):
  bpy.context.scene.frame_set(frame);pose(frame)
  for b in rig.pose.bones:
   b.rotation_mode='QUATERNION'
   for ch in ['location','rotation_quaternion','scale']:b.keyframe_insert(ch,frame=frame)
 bpy.context.scene.frame_start=0;bpy.context.scene.frame_end=840;bpy.context.scene.frame_set(0);pose(0)
 # Merge decorative parts sharing a material/rig, retaining bone weights.
 # Cup and wiping cloth stay separately inspectable despite sharing a rig.
 merged=[]
 untouched=[o for o in props if o!=cloth and (len(o.data.materials)!=1 or o.data.materials[0] not in [hair,linen,capmat])]
 merge_groups={material:[o for o in props if o!=cloth and len(o.data.materials)==1 and o.data.materials[0]==material]for material in [hair,linen,capmat]}
 for material,objects in merge_groups.items():
  if not objects:continue
  bpy.ops.object.select_all(action='DESELECT')
  for obj in objects:obj.select_set(True)
  bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();joined=bpy.context.object
  joined.name={hair:'SellerHairAndFineFacialHair',linen:'SellerApronAndTies',capmat:'SellerWorkingHeadwrap'}[material];merged.append(joined)
 props=merged+untouched+[cloth]
 allmeshes=[head,body,grip]+props
 # Read actual deformed surfaces, including the source's split garment skin.
 # Boot contact is not inferred merely from an ankle target.
 foot_ids={side:[v.index for v in body.data.vertices if any(g.group==body.vertex_groups['foot.'+side].index and g.weight>.65 for g in v.groups) and v.co.z<.24]for side in ['R','L']}
 support=[];cloth_contacts=[];loop_positions=[]
 for frame in range(0,841,6):
  bpy.context.scene.frame_set(frame);pose(frame,True);deps=bpy.context.evaluated_depsgraph_get();bm=body.evaluated_get(deps).to_mesh()
  row={'frame':frame,'time':frame/60,'boots':{side:{'min_z':min(bm.vertices[i].co.z for i in ids),'centroid':list(sum((bm.vertices[i].co for i in ids),Vector())/len(ids))}for side,ids in foot_ids.items()}}
  support.append(row);body.evaluated_get(deps).to_mesh_clear()
  if frame in [0,840]:
   positions=[]
   for o in allmeshes:
    eo=o.evaluated_get(deps);mesh=eo.to_mesh();positions.extend(tuple(v.co)for v in mesh.vertices);eo.to_mesh_clear()
   loop_positions.append(np.array(positions))
  if 120<=frame<=300:
   ec=cup.evaluated_get(deps);cm=ec.to_mesh();cv=[v.co.copy()for v in cm.vertices];cp=[list(p.vertices)for p in cm.polygons];tree=BVHTree.FromPolygons(cv,cp,all_triangles=False)
   ew=cloth.evaluated_get(deps);wm=ew.to_mesh();dist=[tree.find_nearest(v.co)[3]for v in wm.vertices]
   cloth_contacts.append({'frame':frame,'min_surface_distance':min(dist),'mean_surface_distance':sum(dist)/len(dist)})
   ec.to_mesh_clear();ew.to_mesh_clear()
 loop_error=float(np.max(np.linalg.norm(loop_positions[1]-loop_positions[0],axis=1)))
 if loop_error>.0001:raise RuntimeError('Seller loop surface mismatch: '+str(loop_error))
 if max(abs(row['boots'][s]['min_z']-support[0]['boots'][s]['min_z'])for row in support for s in ['R','L'])>.0002:raise RuntimeError('Seller supported boot surface drift')
 bpy.context.scene.frame_set(0);pose(0)
 out.mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(out/'seller-authoring.blend'))
 bpy.ops.object.select_all(action='DESELECT')
 for obj in [rig]+allmeshes:obj.select_set(True)
 bpy.context.view_layer.objects.active=rig
 bpy.ops.export_scene.gltf(filepath=str(out/'tea-seller.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_texcoords=True,export_vertex_color='NAME',export_vertex_color_name='Color',export_all_vertex_colors=False,export_normals=True,export_tangents=False,export_materials='EXPORT',export_image_format='AUTO',export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,export_skins=True,export_cameras=False,export_lights=False)
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.render.threads_mode='FIXED';scene.render.threads=8;scene.render.resolution_x=640;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
 scene.world=bpy.data.worlds.new('Seller review world');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.78,.79,.75,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.55
 bpy.ops.object.camera_add();camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=2.48;scene.camera=camera
 bpy.ops.object.light_add(type='AREA',location=(-3,-4,5));key=bpy.context.object;key.data.energy=330;key.data.shape='DISK';key.data.size=4;key.rotation_euler=(Vector((0,0,1))-key.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,FLOOR-.002));bpy.context.object.data.materials.append(mat('Review matte floor','#b1b09b',1))
 renders=[]
 for frame,view,loc in [(0,'front',(0,-5,2.45)),(0,'side',(5,0,2.2)),(0,'back',(0,5,2.45)),(150,'wipe-front',(0,-5,2.45)),(150,'wipe-side',(5,0,2.2))]:
  scene.frame_set(frame);camera.location=loc;camera.rotation_euler=(Vector((0,-.05,1.03))-camera.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(out/('seller-'+view+'.png'));bpy.ops.render.render(write_still=True);renders.append(scene.render.filepath)
 report={'status':'authored-complete-skeletal-clip-pending-native-scene-review','input':str(BASE),'input_sha256':BASE_SHA,'source_original_after':sha(BASE),'rig_bones':len(rig.data.bones),'head':{'ponytail_vertices_removed':len(remove),'geometry_changes':'Wider lower jaw/longer chin/nose bridge and reduced eye aperture, smaller head proportions; distinct short knot, linen headband and fine facial hair'},'body':'Broader original shoulders and torso with original skin hierarchy adapted; original detailed cloth/normal/roughness retained, brown albedo tint via linear FLOAT_COLOR, original new linen apron/bib/pocket/strap/waistband','actors':{'tea_seller':{'model':'res://assets/art/town_volume_cast/tea-seller.glb','clip':'SellerCupWork','period':14,'display_scale':.90,'source_anchor':[0,FLOOR,.09],'anchor_kind':'feet','source_floor_y':FLOOR}},'animation':{'fps':60,'first_frame':0,'last_frame':840,'samples_including_last':841,'action_window_seconds':[2,5],'loop_max_actual_surface_error':loop_error,'foot_surface_samples':support,'cloth_cup_samples':cloth_contacts,'arm_ik_samples':pose_diagnostics},'props':{'cup_grip_centre_blender':list(gcentre),'cup_centre_blender':list(cupcentre),'cup_bound_to':'hand.R','cloth_bound_to':'hand.L','right_hand_complete':True},'result':{'bytes':(out/'tea-seller.glb').stat().st_size,'sha256':sha(out/'tea-seller.glb'),'mesh_count':len(allmeshes),'renders':renders},'new_cloud_calls':0,'downloads':0,'installs':0}
 (out/'seller-source.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('SELLER_COMPLETE',json.dumps(report['result']))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--source',type=Path,default=BASE,help='Immutable approved GLB; exact BASE_SHA required');a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);BASE=a.source.resolve();make_seller(a.out.resolve())
