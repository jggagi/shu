#!/usr/bin/env python3
"""Editable Jiang bust: authored face/hair/robe and reshaped CC-BY ears.

Snow Rig © Blender Foundation | studio.blender.org (CC BY 4.0).
Only neutral mesh coordinates/topology are read. No source scripts, drivers,
rig, actions, textures, or modifiers are evaluated or copied to the result.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, math, shutil, sys
from pathlib import Path
import bpy, bmesh
from mathutils import Vector

spec=importlib.util.spec_from_file_location('bust_helpers',Path(__file__).with_name('build_bust.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
M=h.MATERIALS
TAU=math.tau


def hair_leaf(name,points,widths,depths,mat=None,flow=True):
    """Flattened curved lock with a pointed silhouette and fixed pigment."""
    obj=h.strand(name,points,widths,depths,mat or M['hair'],sides=20)
    centers=h.spline(points)
    attr=obj.data.color_attributes.new(name='Hair pigment',type='FLOAT_COLOR',domain='POINT')
    for i,(v,c) in enumerate(zip(obj.data.vertices,attr.data)):
        row,col=divmod(i,20)
        t=row/max(1,len(centers)-1);theta=TAU*col/20
        streak=.93+.055*math.cos(theta*7+.3*math.sin(t*5))+.015*math.cos(theta*17)
        highlight=.075*max(0,math.sin(theta))*(.4+.6*math.sin(math.pi*t))
        shade=.92+.08*math.sin(t*math.pi)
        rgb=tuple(min(1,(a+highlight)*streak*shade) for a in (.27,.163,.092))
        c.color=h.color(rgb)
    if flow:
        # One quiet line per lock. Fine lines are nested inside broad masses.
        for shift in (-.33,.35):
            line=[]
            for row in range(3,len(centers)-4,2):
                tangent=(centers[min(row+1,len(centers)-1)]-centers[row-1]).normalized()
                axis=Vector((1,0,0));axis-=tangent*axis.dot(tangent)
                if axis.length<.1:axis=Vector((0,0,1));axis-=tangent*axis.dot(tangent)
                axis.normalize();normal=tangent.cross(axis).normalized()
                if normal.y>0:normal.negate()
                t=row/(len(centers)-1)
                line.append(tuple(centers[row]+axis*(shift*h.sample(widths,t))+normal*(h.sample(depths,t)*math.sqrt(1-shift**2)+.0008)))
            h.curve(name+' flowing division '+str(shift),line,.0010,M['hair line'])
    return obj


def eye_point(sign,x,z,push=0):
    cx=sign*.205;cy=-.205;cz=1.535
    q=((x-cx)/.183)**2+((z-cz)/.174)**2
    return (x,cy-.156*math.sqrt(max(.001,1-q))-push,z)


def eye_contour(sign,theta):
    u=math.cos(theta);v=math.sin(theta)
    x=sign*.205+.160*u
    z=1.535+(.104 if v>=0 else .095)*v+sign*.008*u
    return eye_point(sign,x,z,.003)


def authored_face(base):
    """Continuous rounded head with real eye openings and fitted spheres.

    The Snow face experiment is preserved separately. This mesh is authored
    locally; only the small ear topology is reused from the licensed baseline.
    """
    obj=h.head()
    obj.name='Authored youthful face with open orbital sockets'
    bm=bmesh.new();bm.from_mesh(obj.data)
    def ellipse(x,z,sign):
        u=(x-sign*.205)/.160
        dz=z-1.535-sign*.008*u
        v=dz/(.104 if dz>=0 else .095)
        return u,v,math.hypot(u,v)
    removed=[]
    for f in bm.faces:
        p=f.calc_center_median()
        if p.y<-.09 and 1.39<p.z<1.68 and min(ellipse(p.x,p.z,s)[2] for s in (-1,1))<1:
            removed.append(f)
    bmesh.ops.delete(bm,geom=removed,context='FACES')
    for v in bm.verts:
        x,y,z=v.co
        if y>-.09 or not 1.32<z<1.76:continue
        sign=1 if x>=0 else -1
        u,vv,q=ellipse(x,z,sign)
        if q>1.7:continue
        theta=math.atan2(vv,u)
        rim=Vector(eye_contour(sign,theta))
        if any(e.is_boundary for e in v.link_edges):
            v.co=rim
        else:
            weight=math.exp(-((q-1)/.27)**2)
            v.co.y=y*(1-weight)+rim.y*weight
            # Skin must cover the entire sphere outside the opening. A
            # fitted contour alone leaves white crescents beneath the lid.
            sphere_q=((x-sign*.205)/.183)**2+((z-1.535)/.174)**2
            if sphere_q<1:
                v.co.y=min(v.co.y,eye_point(sign,x,z,.006)[1])
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(obj.data);bm.free()
    sub=obj.modifiers.new('Smooth socket contour','SUBSURF');sub.levels=1;sub.render_levels=1
    # Independent full eyeballs remain occluded by the actual eye openings.
    for sign in (-1,1):
        h.ellipsoid('Full fitted eyeball '+str(sign),(sign*.205,-.205,1.535),(.183,.156,.174),M['eye white'],64,48)
        for pupil in (False,True):
            verts,faces,pigment=[],[],[];rows,cols=24,96
            rx,rz=(.041,.059) if pupil else (.094,.117)
            for i in range(rows+1):
                r=i/rows
                for j in range(cols):
                    theta=TAU*j/cols
                    x=sign*.205+rx*r*math.cos(theta);z=1.543+rz*r*math.sin(theta)
                    verts.append(eye_point(sign,x,z,.002 if pupil else .001))
                    streak=.93+.06*math.sin(theta*43)+.025*math.sin(theta*83)
                    radial=.64+.36*math.sin(math.pi*r)**.65
                    bright=.82-.18*math.sin(theta)
                    pigment.append(h.color(tuple(c*streak*radial*bright for c in (.65,.40,.18))))
            for i in range(rows):
                for j in range(cols):
                    a=i*cols+j;b=i*cols+(j+1)%cols;faces.append((a,a+cols,b+cols,b))
            eye=h.mesh(('Pupil' if pupil else 'Curved amber iris')+' '+str(sign),verts,faces,M['pupil'] if pupil else M['iris'])
            if not pupil:
                a=eye.data.color_attributes.new(name='Fixed iris pigment',type='FLOAT_COLOR',domain='POINT')
                for dst,value in zip(a.data,pigment):dst.color=value
        for upper in (True,False):
            pts=[eye_contour(sign,(math.pi if upper else -math.pi)*i/48) for i in range(49)]
            h.strand(('Upper lid volume ' if upper else 'Lower lid volume ')+str(sign),pts,
                     [.001,.006,.007,.001] if upper else [.001,.004,.004,.001],
                     [.001,.004,.004,.001],M['skin plain'],sides=12)
            if upper:
                h.strand('Fine upper lash '+str(sign),[(x,y-.003,z+.001) for x,y,z in pts],
                         [.001,.0038,.0045,.001],[.001,.002,.002,.001],M['hair dark'],sides=10)
        pts=[]
        for x,z in ((.075,1.724),(.15,1.746),(.245,1.746),(.325,1.718)):
            x*=sign;pts.append((x,h.face_y(x,z)-.009,z))
        h.strand('Fine tapered brow '+str(sign),pts,[.001,.009,.009,.001],[.001,.003,.003,.001],M['hair dark'])
        for dx,dz,r in ((-.024,.043,.013),(.023,-.033,.005)):
            center=eye_point(sign,sign*.205+dx,1.543+dz,.004)
            h.ellipsoid('Fixed eye glint '+str((sign,dx)),center,(r,.003,r*1.2),M['eye white'],24,16)
    # Reuse only the ear shell and antihelix topology from the CC-BY base.
    with bpy.data.libraries.load(str(base),link=False) as (src,dst):dst.objects=['GEO-snow_head']
    raw=dst.objects[0]
    for sign in (-1,1):
        selected=[p for p in raw.data.polygons if all(sign*raw.data.vertices[i].co.x>.103 and 1.55<raw.data.vertices[i].co.z<1.67 for i in p.vertices)]
        used=sorted({i for p in selected for i in p.vertices});lookup={v:i for i,v in enumerate(used)}
        verts=[]
        for i in used:
            x,y,z=raw.data.vertices[i].co
            verts.append((sign*(.433+(abs(x)-.103)*1.65),(y+.015)*2.4,(z-1.60)*2.4+1.48))
        ear=h.mesh('CC-BY reshaped ear shell '+str(sign),verts,[tuple(lookup[i] for i in p.vertices) for p in selected],M['skin plain'])
        ear['Attribution']='Snow Rig © Blender Foundation | studio.blender.org — CC BY 4.0; cropped, scaled and recolored ear topology'
        sub=ear.modifiers.new('Ear subdivision','SUBSURF');sub.levels=2
    for o in list(bpy.data.objects):
        if o not in h.CHARACTER:bpy.data.objects.remove(o,do_unlink=True)
    for text in list(bpy.data.texts):bpy.data.texts.remove(text)
    for action in list(bpy.data.actions):bpy.data.actions.remove(action)
    h.ellipsoid('Neck beneath folded collar',(0,0,.99),(.125,.12,.17),M['skin plain'])
    points=[(x,h.face_y(x,z)-.002,z) for x,z in ((-.052,1.214),(-.024,1.218),(0,1.218),(.03,1.216),(.055,1.212))]
    h.strand('Quiet lip crease',points,[.0007,.002,.002,.002,.0007],[.0005,.001,.001,.001,.0005],M['mouth crease'],sides=10)


def hair():
    # A sculpted cap with a low rear nape, high central part and swept sides.
    verts,faces=[],[];rows,cols=48,128
    for row in range(rows+1):
        for col in range(cols):
            phi=-math.pi+TAU*col/cols
            rear=((1-math.cos(phi))/2)**.60
            limit=.99+1.55*rear+rear*(.025*math.sin(phi*13)+.015*math.sin(phi*23))
            theta=limit*row/rows
            relief=1+.006*math.cos(phi*35+theta*2.4)
            verts.append((.493*math.sin(theta)*math.sin(phi)*relief,
                          .025-.478*math.sin(theta)*math.cos(phi)*relief,
                          1.63+.635*math.cos(theta)))
    for row in range(rows):
        for col in range(cols):
            a=row*cols+col;b=row*cols+(col+1)%cols
            faces.append((a,b,b+cols,a+cols))
    h.mesh('Continuous swept scalp',verts,faces,M['hair base'])
    # Large overlapping flow masses, with an open off-center forehead.
    specs=[
      ('Main left sweep',[(.055,-.13,2.25),(-.14,-.36,2.15),(-.28,-.435,1.95),(-.38,-.36,1.71)], [.016,.13,.115,.002],[.012,.041,.035,.001]),
      ('Left layered sweep',[(.00,-.10,2.25),(-.27,-.28,2.13),(-.39,-.365,1.89),(-.43,-.23,1.59)],[.012,.11,.085,.002],[.01,.038,.029,.001]),
      ('Left inner fringe',[(.06,-.16,2.23),(-.08,-.38,2.07),(-.17,-.45,1.87),(-.22,-.43,1.76)],[.01,.083,.067,.001],[.009,.027,.019,.001]),
      ('Main right sweep',[(.07,-.12,2.25),(.27,-.33,2.14),(.365,-.39,1.91),(.39,-.31,1.68)],[.012,.12,.102,.002],[.01,.04,.03,.001]),
      ('Right inner fringe',[(.08,-.16,2.22),(.20,-.385,2.07),(.28,-.44,1.91),(.29,-.43,1.80)],[.01,.073,.060,.001],[.009,.025,.018,.001]),
      ('Right outer sweep',[(.12,-.07,2.24),(.36,-.20,2.11),(.455,-.25,1.85),(.44,-.13,1.55)],[.01,.10,.078,.001],[.009,.033,.026,.001]),
    ]
    for spec in specs:hair_leaf(*spec)
    for sign in (-1,1):
        hair_leaf('Fine temple curl '+str(sign),[(sign*.38,-.21,1.92),(sign*.455,-.24,1.66),
                  (sign*.447,-.22,1.40),(sign*.38,-.26,1.28),(sign*.34,-.29,1.33)],
                  [.028,.046,.035,.016,.001],[.012,.019,.015,.008,.001])
        hair_leaf('Loose ear-side curl '+str(sign),[(sign*.42,-.01,1.89),(sign*.49,.015,1.65),
                  (sign*.51,.09,1.42),(sign*.455,.11,1.23),(sign*.49,.03,1.18)],
                  [.024,.049,.045,.025,.001],[.012,.025,.020,.011,.001])
        # Back hair collects upward into a high knot rather than hanging helmet panels.
        for j in range(4):
            points=[]
            for k in range(6):
                t=k/5;theta=2.37-1.56*t;phi=sign*(1.52+j*.31+(.85-.12*j)*t)
                points.append((.507*math.sin(theta)*math.sin(phi),
                              .025-.490*math.sin(theta)*math.cos(phi),1.63+.655*math.cos(theta)))
            hair_leaf('Gathered side flow '+str((sign,j)),points,
                      [.001,.05,.065,.07,.035,.004],[.001,.019,.024,.025,.014,.002])
    # An ample high ponytail, with broad overlapping curls and loose ends.
    hair_leaf('Swept gathered ponytail root',[(0,.25,2.15),(0,.40,2.25),(0,.57,2.30)],
              [.14,.12,.105],[.09,.075,.065])
    hair_leaf('Ponytail core',[(0,.39,2.20),(-.04,.62,2.38),(-.05,.84,2.22),
              (0,.89,1.85),(.04,.81,1.47),(.16,.65,1.15)],
              [.11,.17,.185,.15,.10,.002],[.07,.11,.13,.11,.065,.001])
    for i in range(7):
        t=(i-3)/3;side=t*.18
        hair_leaf('Long ponytail flowing layer '+str(i),[(side*.15,.46,2.27),(side*.8,.66,2.40-abs(t)*.07),
                  (side,.87,2.16),(side*1.05,.93,1.83),(side*.8+.035,.84,1.49),
                  (side*.6+.10,.71,1.16+abs(t)*.17),
                  (side*.55+.16+.035*math.sin(i*2),.58,1.14+abs(t)*.20)],
                  [.015,.062,.077,.076,.054,.024,.001],
                  [.01,.03,.034,.031,.026,.012,.001])
    for sign in (-1,1):
        hair_leaf('Ponytail flying curl '+str(sign),[(sign*.04,.62,2.31),(sign*.13,.72,2.43),
                  (sign*.23,.78,2.37),(sign*.25,.84,2.24)],
                  [.015,.043,.025,.001],[.01,.018,.012,.001])
        hair_leaf('Nape wispy curl '+str(sign),[(sign*.30,.30,1.61),(sign*.35,.39,1.34),
                  (sign*.39,.29,1.12),(sign*.46,.17,1.10)],
                  [.025,.045,.030,.001],[.012,.021,.014,.001])
    # Cloth tied around the actual gathered root; ribbon tails have folded volume.
    h.ellipsoid('Silk knot',(0,.48,2.28),(.091,.061,.055),M['ribbon'])
    for sign in (-1,1):
        h.ribbon('Folded knot loop '+str(sign),[(sign*.025,.48,2.29),(sign*.14,.48,2.34),
                 (sign*.17,.48,2.28),(sign*.055,.49,2.26)],[.022,.029,.028,.013],M['ribbon'])
        h.ribbon('Trailing silk ribbon '+str(sign),[(sign*.05,.52,2.28),(sign*.20,.69,2.06),
                 (sign*.28,.79,1.77),(sign*.30,.69,1.46),(sign*.37,.53,1.30)],
                 [.039,.048,.046,.040,.033],M['ribbon'])


TORSO=[(.02,.47,.25),(.25,.48,.26),(.48,.49,.25),(.68,.47,.23),(.79,.37,.20),(.90,.16,.135),(.98,.115,.11)]


def torso_y(x,z):
    rx,ry=h.profile_at(TORSO,z)
    return -ry*math.sqrt(max(.03,1-(x/rx)**2))


def cloth_strip(name,points,width,mat,offset=.015,edge=False):
    path=h.spline([(x,0,z) for x,z in points]);verts,faces=[],[];cols=11
    edges=[[],[]]
    for i,p in enumerate(path):
        tangent=path[min(i+1,len(path)-1)]-path[max(0,i-1)]
        across=Vector((tangent.z,0,-tangent.x)).normalized()
        for j in range(cols):
            u=j/(cols-1)*2-1;q=p+across*(width*u)
            q.y=torso_y(q.x,q.z)-offset-.003*(1-u*u)
            verts.append(tuple(q))
            if j==0:edges[0].append(tuple(q+Vector((0,-.001,0))))
            if j==cols-1:edges[1].append(tuple(q+Vector((0,-.001,0))))
    for i in range(len(path)-1):
        for j in range(cols-1):a=i*cols+j;faces.append((a,a+cols,a+cols+1,a+1))
    obj=h.mesh(name,verts,faces,mat)
    mod=obj.modifiers.new('Folded fabric thickness','SOLIDIFY');mod.thickness=.004
    if edge:
        for i,line in enumerate(edges):h.curve(name+' sewn edge '+str(i),line,.0011,M['seam'])
    return obj


def garment():
    verts,faces=[],[];rows,cols=72,112
    for i in range(rows+1):
        z=.02+.96*i/rows;rx,ry=h.profile_at(TORSO,z)
        for j in range(cols):
            phi=-math.pi+TAU*j/cols
            wrinkle=.0035*math.sin(phi*13+z*3)*math.exp(-((z-.56)/.3)**2)
            verts.append(((rx+wrinkle)*math.sin(phi),-(ry+wrinkle*.5)*math.cos(phi),z))
    for i in range(rows):
        for j in range(cols):a=i*cols+j;b=i*cols+(j+1)%cols;faces.append((a,a+cols,b+cols,b))
    faces.append(tuple(reversed(range(cols))))
    h.mesh('Ivory wrap robe shoulder and chest',verts,faces,M['ivory'])
    # Separate sloping sleeve volumes retain the vest's sleeveless construction.
    for sign in (-1,1):
        obj=h.strand('Loose ivory sleeve '+str(sign),[(sign*.21,.02,.65),(sign*.43,.015,.57),(sign*.60,.0,.30),(sign*.63,.0,.03)],
                     [.14,.20,.18,.18],[.20,.22,.21,.20],M['ivory'],sides=40)
        # Blue panel follows the shoulder surface and wraps to the back.
        vs,fs=[],[];r,c=56,56
        for i in range(r):
            t=i/(r-1);z=.025+.87*t;rx,ry=h.profile_at(TORSO,z)
            edge_x=.265-.10*t
            start=math.asin(min(.96,edge_x/rx))
            for j in range(c):
                u=j/(c-1);phi=sign*(start+(math.pi-start)*u)
                fold=.004*math.sin(u*16+z*3)*math.sin(math.pi*t)
                vs.append(((rx+.010+fold)*math.sin(phi),-(ry+.010+fold*.5)*math.cos(phi),z))
        for i in range(r-1):
            for j in range(c-1):
                a=i*c+j;face=(a,a+c,a+c+1,a+1);fs.append(tuple(reversed(face)) if sign<0 else face)
        panel=h.mesh('Indigo sleeveless outer robe '+str(sign),vs,fs,M['blue'])
        thick=panel.modifiers.new('Woven cloth thickness','SOLIDIFY');thick.thickness=.006
        cloth_strip('Indigo vest facing '+str(sign),[(sign*.17,.89),(sign*.21,.78),
                   (sign*.23,.56),(sign*.26,.29),(sign*.28,.04)],.019,M['blue edge'],.027,True)
        for j in range(3):
            pts=[(sign*(.45+.025*j),-.135,.65-.04*j),(sign*(.50+.024*j),-.19,.48-.04*j),
                 (sign*(.55+.025*j),-.18,.25-.04*j)]
            h.strand('Sleeve fold '+str((sign,j)),pts,[.001,.007,.001],[.001,.003,.001],M['ivory shade'],sides=10)
    # Wide crossed collars with a narrow indigo inner binding at the neck.
    cloth_strip('Under collar indigo binding',[(.105,.975),(.15,.87),(.08,.72),(-.07,.54)],.049,M['blue edge'],.011)
    cloth_strip('Under collar ivory',[(.105,.96),(.137,.86),(.065,.72),(-.075,.53)],.036,M['ivory light'],.024,True)
    cloth_strip('Outer collar indigo binding',[(-.105,.975),(-.15,.86),(-.06,.69),(.07,.51),(.21,.32)],.057,M['blue edge'],.027)
    cloth_strip('Outer crossed ivory lapel',[(-.105,.965),(-.14,.86),(-.05,.69),(.08,.51),(.215,.32)],.044,M['ivory light'],.037,True)
    cloth_strip('Lower wrap fold',[(-.24,.08),(-.14,.19),(.02,.33),(.16,.45)],.034,M['ivory light'],.010)


def setup_materials():
    h.material('skin',(.975,.819,.696),.83)
    h.material('skin plain',(.975,.819,.696),.83)
    h.material('ear inset',(.89,.62,.52),.9)
    h.material('lip',(.95,.75,.64),.85)
    h.material('lower lip',(.975,.81,.69),.86)
    h.material('mouth crease',(.51,.31,.25),.9)
    skin=M['skin'];nodes=skin.node_tree.nodes
    v=nodes.new('ShaderNodeVertexColor');v.layer_name='Fixed pigment'
    skin.node_tree.links.new(v.outputs['Color'],nodes.get('Principled BSDF').inputs['Base Color'])
    shader=nodes.get('Principled BSDF');shader.inputs['Subsurface Weight'].default_value=.05
    h.material('eye white',(.97,.93,.86),.31)
    iris=h.material('iris',(.57,.32,.12),.40)
    v=iris.node_tree.nodes.new('ShaderNodeVertexColor');v.layer_name='Fixed iris pigment'
    iris.node_tree.links.new(v.outputs['Color'],iris.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    h.material('pupil',(.045,.022,.012),.35)
    hair=h.material('hair',(.27,.163,.092),.78)
    v=hair.node_tree.nodes.new('ShaderNodeVertexColor');v.layer_name='Hair pigment'
    hair.node_tree.links.new(v.outputs['Color'],hair.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    h.material('hair base',(.22,.125,.067),.84)
    h.material('hair dark',(.14,.075,.040),.88)
    h.material('hair line',(.19,.104,.054),.88)
    h.material('ivory',(.91,.90,.84),.94,True)
    h.material('ivory light',(.96,.94,.87),.94,True)
    h.material('ivory shade',(.82,.82,.76),.95)
    h.material('blue',(.37,.52,.62),.95,True)
    h.material('blue edge',(.25,.38,.47),.94,True)
    h.material('seam',(.68,.70,.65),.95)
    h.material('ribbon',(.63,.75,.81),.92,True)
    h.material('Structural gray clay',(.55,.55,.55),.85)
    # Fixed pigment variation; every view uses the same spatial field.
    for name,base in [('blue',(.37,.52,.62)),('ivory',(.91,.90,.84)),('ivory light',(.96,.94,.87)),('ribbon',(.63,.75,.81))]:
        mat=M[name];nodes=mat.node_tree.nodes;links=mat.node_tree.links
        tex=nodes.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=12;tex.inputs['Detail'].default_value=3
        coords=nodes.new('ShaderNodeTexCoord');links.new(coords.outputs['Generated'],tex.inputs['Vector'])
        ramp=nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position=.15;ramp.color_ramp.elements[0].color=h.color(tuple(c*.92 for c in base))
        ramp.color_ramp.elements[1].position=.85;ramp.color_ramp.elements[1].color=h.color(tuple(min(1,c*1.045) for c in base))
        links.new(tex.outputs['Fac'],ramp.inputs[0]);links.new(ramp.outputs['Color'],nodes.get('Principled BSDF').inputs['Base Color'])


def build(args):
    if args.output.exists():raise SystemExit('Refusing to overwrite output')
    args.output.mkdir(parents=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_materials();authored_face(args.base);hair();garment()
    scene,cameras=h.studio(args.size)
    # Increase space around the tall ponytail while retaining equal camera scale.
    for cam in cameras.values():cam.data.ortho_scale=2.80
    data=bpy.data.cameras.new('back');data.type='ORTHO';data.ortho_scale=2.80
    back=bpy.data.objects.new('Camera back',data);scene.collection.objects.link(back)
    target=Vector((0,.10,1.18));back.location=target+Vector((0,6,.12))
    back.rotation_euler=(target-back.location).to_track_quat('-Z','Y').to_euler();cameras['back']=back
    baseline=h.identity()
    # Purge unreferenced foreign materials and script-bearing blocks from the deliverable.
    for mat in list(bpy.data.materials):
        if mat.name not in M and mat.users==0:bpy.data.materials.remove(mat)
    for img in list(bpy.data.images):
        if img.users==0:bpy.data.images.remove(img)
    M['Structural gray clay'].use_fake_user=True
    bpy.data.orphans_purge(do_recursive=True)
    assert not bpy.data.texts and not bpy.data.actions and not bpy.data.armatures
    scene['Attribution']='Snow Rig © Blender Foundation | studio.blender.org — CC BY 4.0'
    scene['Modification notice']='Only ear shells cropped and reshaped from Snow; face with real eye openings, hair, ponytail, robe, materials and studio authored by Codex, 2026-10-22.'
    scene['Status']='Static bust candidate; no approved likeness, finished rig or animation.'
    source=args.output/'source';source.mkdir()
    for file in [Path(__file__),Path(__file__).with_name('build_bust.py')]:shutil.copy2(file,source/file.name)
    shutil.copy2(args.reference,source/'identity-reference.png')
    shutil.copy2(args.concept,source/'concept-target.png')
    shutil.copy2(args.base,source/'snow_v03.blend')
    shutil.copy2(Path(__file__).parents[2]/'docs/image-motion/jiang-bust-basemesh-source-20261022.md',source/'BASEMESH-LICENSE.md')
    scene.camera=cameras['three-quarter']
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output/'jiang-bust.blend'))
    slots={o.name:list(o.data.materials) for o in h.CHARACTER}
    indices={o.name:[p.material_index for p in o.data.polygons] for o in h.CHARACTER}
    renders={}
    for mode in ['painted','clay']:
        for obj in h.CHARACTER:
            obj.data.materials.clear()
            for mat in ([M['Structural gray clay']] if mode=='clay' else slots[obj.name]):obj.data.materials.append(mat)
            for p,i in zip(obj.data.polygons,indices[obj.name]):p.material_index=0 if mode=='clay' else i
        for name,cam in cameras.items():
            scene.camera=cam;filename=name+'-'+mode+'.png';scene.render.filepath=str(args.output/filename)
            bpy.ops.render.render(write_still=True)
            assert h.identity()==baseline
            renders[filename]={'sha256':hashlib.sha256((args.output/filename).read_bytes()).hexdigest(),
                               'geometry_sha256':baseline,'material_override':mode=='clay'}
    receipt={'status':'STATIC_BUST_CANDIDATE_AWAITING_USER_REVIEW','runtime':bpy.app.version_string,
      'geometry_sha256':baseline,'size':[args.size,args.size],'renders':renders,
      'mesh_objects':len(h.CHARACTER),'vertices':sum(len(o.data.vertices) for o in h.CHARACTER),
      'image_textures':0,'no_face_billboard':True,'animation_actions':len(bpy.data.actions),
      'clay_is_uniform_material_replacement':True,'external_generations':0,
      'base':{'name':'Blender Studio Snow v3','license':'CC BY 4.0',
              'credit':'Snow Rig © Blender Foundation | studio.blender.org',
              'sha256':hashlib.sha256(args.base.read_bytes()).hexdigest(),
              'reused_parts':['ear shells only'],
              'modification_notice':'Ear shells cropped, scaled and recolored; face, eyes, hair and robe authored locally'},
      'limitations':['Authored static face with reused CC BY ear shells; no transferred rig or animation readiness',
                     'Appearance still requires user review; not equivalent to the painted concept target'],
      'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (args.output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'status':'DONE','output':str(args.output),'geometry_sha256':baseline}))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--base',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--reference',type=Path,required=True);p.add_argument('--concept',type=Path,required=True)
    p.add_argument('--size',type=int,default=1400)
    build(p.parse_args(sys.argv[sys.argv.index('--')+1:]))
