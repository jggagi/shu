#!/usr/bin/env python3
"""Build an actual static Jiang Yanqiu head-and-shoulders study.

The six renders use one unchanged volumetric scene. Eyes, eyelids, nose,
mouth, ears and hair are geometry; no face painting or camera-facing card
stands in for their structure. This is an art candidate, not an animation rig.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import shutil
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Vector

TAU = math.tau
CHARACTER = []
MATERIALS = {}


def linear(v):
    return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4


def color(rgb):
    return tuple(linear(v) for v in rgb) + (1,)


def material(name, rgb, roughness=.85, painted=False):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color(rgb)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color(rgb)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Specular IOR Level"].default_value = .16
    if painted:
        # Spatially fixed, quiet fiber. It never changes with camera/frame.
        coords = nodes.new("ShaderNodeTexCoord")
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 170
        noise.inputs["Detail"].default_value = 2
        links.new(coords.outputs["Generated"], noise.inputs["Vector"])
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = .10
        bump.inputs["Distance"].default_value = .006
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    MATERIALS[name] = mat
    return mat


def mesh(name, vertices, faces, mat, colors=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.materials.append(mat)
    for polygon in data.polygons:
        polygon.use_smooth = True
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj["jiang_bust_geometry"] = True
    CHARACTER.append(obj)
    if colors is not None:
        attribute = data.color_attributes.new(name="Fixed pigment", type="FLOAT_COLOR", domain="POINT")
        for dst, value in zip(attribute.data, colors):
            dst.color = value
    return obj


def spline(points, steps=8):
    points = [Vector(p) for p in points]
    result = []
    for i in range(len(points) - 1):
        a, b = points[max(0, i - 1)], points[i]
        c, d = points[i + 1], points[min(len(points) - 1, i + 2)]
        for j in range(steps):
            t = j / steps
            result.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
    result.append(points[-1])
    return result


def sample(values, t):
    f = max(0, min(len(values)-1.000001, t*(len(values)-1)))
    i = int(f)
    return values[i]*(1-(f-i)) + values[i+1]*(f-i)


def strand(name, points, widths, depths, mat, sides=16, grooves=0):
    centers = spline(points)
    vertices, faces = [], []
    axes = []
    for row, center in enumerate(centers):
        t = row/(len(centers)-1)
        tangent = centers[min(row+1,len(centers)-1)]-centers[max(row-1,0)]
        tangent.normalize()
        axis = Vector((1,0,0))
        axis -= tangent*axis.dot(tangent)
        if axis.length < .1:
            axis = Vector((0,0,1)); axis -= tangent*axis.dot(tangent)
        axis.normalize()
        depth_axis = tangent.cross(axis).normalized()
        if depth_axis.y > 0:
            depth_axis.negate()
        axes.append((axis,depth_axis))
        w, depth = sample(widths,t), sample(depths,t)
        for col in range(sides):
            theta = TAU*col/sides
            # A subtle sculpted ridge gives a broad lock hierarchy without
            # repeated high-contrast bark textures or hair-card edges.
            ridge = 1 + (.035*math.cos(theta*6) if grooves else 0)
            vertices.append(tuple(center + axis*(w*math.cos(theta)) +
                                  depth_axis*(depth*math.sin(theta)*ridge)))
    for row in range(len(centers)-1):
        for col in range(sides):
            a=row*sides+col; b=row*sides+(col+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces += [tuple(reversed(range(sides))),tuple((len(centers)-1)*sides+i for i in range(sides))]
    obj=mesh(name,vertices,faces,mat)
    # Thin raised strand divisions follow the SAME authored flow and remain
    # sparse. No extra sharp ridges around the silhouette.
    if grooves:
        for offset in (-.42,.18,.54):
            line=[]
            for row in range(2,len(centers)-3,3):
                t=row/(len(centers)-1)
                w,d=sample(widths,t),sample(depths,t)
                axis,depth_axis=axes[row]
                line.append(tuple(centers[row]+axis*(w*offset)+depth_axis*(d*math.sqrt(1-offset*offset)+.0015)))
            if len(line)>2:
                curve(name+" fine flow "+str(offset),line,.0015,MATERIALS["hair highlight"])
    return obj


def curve(name, points, radius, mat):
    # Fine relief lines are true tubes, including in the gray-material view.
    return strand(name,points,[radius]*len(points),[radius]*len(points),mat,sides=8)


HEAD_PROFILE = [
    (1.01,.005,.010,.010), (1.035,.125,.155,.125),
    (1.095,.255,.255,.245), (1.20,.355,.325,.330),
    (1.37,.430,.365,.385), (1.55,.455,.370,.405),
    (1.73,.450,.355,.410), (1.90,.395,.315,.365),
    (2.06,.275,.225,.250), (2.15,.090,.080,.085), (2.17,.002,.003,.003),
]


def profile_at(profile,z):
    if z <= profile[0][0]: return profile[0][1:]
    if z >= profile[-1][0]: return profile[-1][1:]
    for index,(a,b) in enumerate(zip(profile,profile[1:])):
        if a[0] <= z <= b[0]:
            t=(z-a[0])/(b[0]-a[0])
            before=profile[max(0,index-1)]
            after=profile[min(len(profile)-1,index+2)]
            span=b[0]-a[0]
            # Continuous profile tangents avoid a horizontal ridge at every
            # authored control ring, particularly around the jaw and cheeks.
            return tuple((2*t**3-3*t*t+1)*x + (t**3-2*t*t+t)*span*(y-prev)/(b[0]-before[0]) +
                         (-2*t**3+3*t*t)*y + (t**3-t*t)*span*(following-x)/(after[0]-a[0])
                         for x,y,prev,following in zip(a[1:],b[1:],before[1:],after[1:]))


def gaussian(x,z,cx,cz,sx,sz):
    return math.exp(-((x-cx)/sx)**2-((z-cz)/sz)**2)


def facial_relief(x,z):
    bridge=.022*gaussian(x,z,0,1.46,.055,.17)
    tip=.061*gaussian(x,z,0,1.355,.065,.065)
    wings=.012*(gaussian(x,z,-.065,1.34,.035,.032)+gaussian(x,z,.065,1.34,.035,.032))
    cheeks=.018*(gaussian(x,z,-.25,1.32,.15,.13)+gaussian(x,z,.25,1.32,.15,.13))
    lips=.012*gaussian(x,z,0,1.205,.10,.034)
    chin=.008*gaussian(x,z,0,1.105,.16,.06)
    return bridge+tip+wings+cheeks+lips+chin


def face_y(x,z):
    rx,depth,_=profile_at(HEAD_PROFILE,z)
    phi=math.asin(max(-.999,min(.999,x/rx)))
    return -depth*math.cos(phi)-facial_relief(x,z)*max(0,math.cos(phi))**3


def head():
    vertices,faces,colors=[],[],[]
    rows,cols=110,144
    for row in range(rows+1):
        z=1.01+(2.17-1.01)*row/rows
        rx,front,back=profile_at(HEAD_PROFILE,z)
        for col in range(cols):
            phi=-math.pi+TAU*col/cols
            x=rx*math.sin(phi)
            forward=max(0,math.cos(phi))
            depth=front if math.cos(phi)>=0 else back
            y=-depth*math.cos(phi)-facial_relief(x,z)*forward**3
            vertices.append((x,y,z))
            blush=.24*(gaussian(x,z,-.28,1.33,.12,.10)+gaussian(x,z,.28,1.33,.12,.10))*forward**4
            base=(.965,.803,.677); pink=(.91,.565,.485)
            colors.append(color(tuple(a*(1-blush)+b*blush for a,b in zip(base,pink))))
    for row in range(rows):
        for col in range(cols):
            a=row*cols+col; b=row*cols+(col+1)%cols
            faces.append((a,a+cols,b+cols,b))
    faces += [tuple(reversed(range(cols))), tuple(rows*cols+i for i in range(cols))]
    obj=mesh("Continuous sculpted face, jaw and skull",vertices,faces,MATERIALS["skin"],colors)
    nodes,links=MATERIALS["skin"].node_tree.nodes,MATERIALS["skin"].node_tree.links
    attr=nodes.new("ShaderNodeVertexColor");attr.layer_name="Fixed pigment"
    links.new(attr.outputs["Color"],nodes.get("Principled BSDF").inputs["Base Color"])
    return obj


def ellipsoid(name,center,radii,mat,segments=48,rings=32):
    vertices,faces=[],[]
    for row in range(rings+1):
        theta=math.pi*row/rings
        for col in range(segments):
            phi=TAU*col/segments
            vertices.append((center[0]+radii[0]*math.sin(theta)*math.cos(phi),
                             center[1]+radii[1]*math.sin(theta)*math.sin(phi),
                             center[2]+radii[2]*math.cos(theta)))
    for row in range(rings):
        for col in range(segments):
            a=row*segments+col;b=row*segments+(col+1)%segments
            faces.append((a,b,b+segments,a+segments))
    return mesh(name,vertices,faces,mat)


def facial_details():
    for sign in (-1,1):
        # A small helix around a recessed concha, not an undifferentiated oval.
        ellipsoid("Ear shell "+str(sign),(sign*.435,.012,1.43),(.071,.047,.108),MATERIALS["ear skin"])
        pts=[]
        for i in range(30):
            t=TAU*i/29
            pts.append((sign*(.476+.011*math.cos(t)),.003+.031*math.sin(t),1.44+.075*math.cos(t)))
        curve("Ear helix "+str(sign),pts,.009,MATERIALS["ear skin"])
        ellipsoid("Ear concha "+str(sign),(sign*.494,-.001,1.43),(.005,.025,.051),MATERIALS["ear inset"],32,24)
        # Eyebrows have a drawn contour but a real tapered volume.
        xs=[sign*v for v in (.085,.15,.23,.31)]
        zs=[1.755,1.775,1.775,1.742]
        pts=[(x,face_y(x,z)-.008,z) for x,z in zip(xs,zs)]
        strand("Tapered brow "+str(sign),pts,[.004,.014,.013,.002],[.003,.005,.005,.001],MATERIALS["hair dark"])
    # Lip crease, raised lower lip, nostrils: small forms on the continuous face.
    points=[]
    for x,z in ((-.067,1.218),(-.035,1.211),(0,1.210),(.036,1.214),(.062,1.224)):
        points.append((x,face_y(x,z)-.001,z))
    strand("Quiet mouth crease",points,[.001,.003,.003,.0025,.0008],[.001,.0015,.0015,.001,.0005],MATERIALS["lip shadow"])
    pts=[(x,face_y(x,z)-.001,z) for x,z in ((-.035,1.195),(0,1.190),(.031,1.198))]
    strand("Lower lip sculpt",pts,[.001,.004,.001],[.001,.002,.001],MATERIALS["lip"])
    for sign in (-1,1):
        pts=[(sign*x,face_y(sign*x,z)-.0005,z) for x,z in ((.033,1.331),(.043,1.328),(.053,1.333))]
        curve("Nostril crease "+str(sign),pts,.0018,MATERIALS["lip shadow"])


def eye(sign):
    origin=Vector((sign*.205,-.330,1.535))
    normal=Vector((sign*.38,-.925,0)).normalized()
    across=Vector((.925,sign*.38,0)).normalized()
    up=Vector((0,0,1))
    def surface(u,v,push=0):
        height=.141 if v>=0 else .106
        point=origin+across*(u*.158)+up*(v*height)
        # The eye opening is fitted into the facial surface. Its shallow
        # corneal arc keeps the profile from becoming an attached eyeball disc.
        point.y=face_y(point.x,point.z)-.003-.006*max(0,1-u*u-v*v)-push
        return point
    def disk(name,mat,umax=1,vmax=1,push=0,iris=False):
        vertices,faces,colors=[],[],[]
        rings,cols=22,96
        rng=random.Random(487+sign)
        pigment=[rng.uniform(.83,1.12) for _ in range(cols)]
        for row in range(rings+1):
            radius=row/rings
            for col in range(cols):
                theta=TAU*col/cols
                u=umax*radius*math.cos(theta);v=vmax*radius*math.sin(theta)
                vertices.append(tuple(surface(u,v,push)))
                if iris:
                    light=.70+.30*math.sin(theta)*(-1)
                    edge=.60+.40*math.sin(math.pi*radius)**.4
                    base=(.56,.33,.12)
                    mul=pigment[col]*edge*light
                    colors.append(color(tuple(min(1,c*mul) for c in base)))
        for row in range(rings):
            for col in range(cols):
                a=row*cols+col;b=row*cols+(col+1)%cols
                faces.append((a,a+cols,b+cols,b))
        return mesh(name,vertices,faces,mat,colors if iris else None)
    disk("Sculpted eye white "+str(sign),MATERIALS["eye white"])
    disk("Radial amber iris "+str(sign),MATERIALS["iris"],.60,.86,.0015,True)
    disk("Pupil "+str(sign),MATERIALS["pupil"],.265,.58,.0025)
    # Skin rims surround the almond opening; dark upper lash is a thin edge,
    # not a second painted face. The forms remain visible in clay renders.
    for upper in (True,False):
        pts=[]
        for i in range(42):
            theta=(math.pi if upper else -math.pi)*i/41
            pts.append(tuple(surface(math.cos(theta),math.sin(theta),.001)))
        strand(("Upper" if upper else "Lower")+" eyelid "+str(sign),pts,
               [.004,.012,.013,.004] if upper else [.003,.007,.007,.002],
               [.004,.008,.008,.003] if upper else [.002,.004,.004,.002],
               MATERIALS["ear skin"],sides=12)
        if upper:
            lash=[tuple(Vector(p)+normal*.006) for p in pts]
            strand("Fine upper lash "+str(sign),lash,[.001,.006,.007,.001],
                   [.001,.003,.003,.001],MATERIALS["hair dark"],sides=12)
    for u,v,r in ((-.23,.38,.018),(.21,-.35,.006)):
        pos=surface(u,v,.005)
        ellipsoid("Eye catchlight "+str((sign,u)),tuple(pos),(r,.004,r),MATERIALS["catchlight"],24,16)


def hair():
    # Continuous cap with a shaped hairline, then a deliberately small number
    # of major locks. Fine sculpted divisions follow each lock's growth flow.
    vertices,faces=[],[]
    rows,cols=64,144
    for row in range(rows+1):
        for col in range(cols):
            phi=-math.pi+TAU*col/cols
            limit=1.15+.90*((1-math.cos(phi))/2)**.65
            theta=limit*row/rows
            # Gentle grooves are geometry, not contrasty image stripes.
            contour=1+.004*math.cos(phi*32+theta*1.5)
            vertices.append((.490*math.sin(theta)*math.sin(phi)*contour,
                             -.460*math.sin(theta)*math.cos(phi)*contour,
                             1.60+.620*math.cos(theta)))
    for row in range(rows):
        for col in range(cols):
            a=row*cols+col;b=row*cols+(col+1)%cols
            faces.append((a,b,b+cols,a+cols))
    mesh("Continuous scalp and nape",vertices,faces,MATERIALS["hair"])
    specs=[
        ("Central swept forelock",[(-.16,-.04,2.16),(-.13,-.30,2.04),(-.025,-.418,1.86),(.10,-.415,1.77)], [.008,.13,.11,.002],[.008,.055,.042,.001]),
        ("Right swept forelock",[(-.28,-.015,2.08),(-.31,-.25,1.98),(-.35,-.35,1.81),(-.39,-.275,1.64)], [.01,.10,.085,.002],[.008,.05,.035,.001]),
        ("Left swept forelock",[(.015,-.04,2.17),(.16,-.29,2.04),(.24,-.405,1.86),(.23,-.415,1.74)], [.008,.105,.08,.002],[.008,.05,.035,.001]),
        ("Outer swept forelock",[(.22,-.01,2.12),(.32,-.20,1.98),(.38,-.31,1.78),(.395,-.23,1.59)], [.008,.09,.07,.002],[.008,.042,.032,.001]),
    ]
    for i,(name,pts,ws,ds) in enumerate(specs):
        strand(name,pts,ws,ds,MATERIALS["hair" if i%2 else "hair middle"],sides=24,grooves=1)
    for sign in (-1,1):
        strand("Curved temple lock "+str(sign),[(sign*.32,-.01,1.99),(sign*.442,-.14,1.78),
               (sign*.451,-.15,1.47),(sign*.39,-.12,1.20)],
               [.012,.065,.050,.0015],[.008,.032,.025,.001],MATERIALS["hair"],sides=24,grooves=1)
        strand("Rear side lock "+str(sign),[(sign*.29,.15,2.08),(sign*.43,.25,1.82),
               (sign*.40,.28,1.49),(sign*.31,.20,1.24)],
               [.01,.085,.070,.002],[.008,.035,.030,.001],MATERIALS["hair middle"],sides=24,grooves=1)
    strand("Gathered high ponytail",[(0,.22,2.08),(0,.43,2.18),(0,.58,2.19)],
           [.16,.11,.10],[.10,.075,.065],MATERIALS["hair"],sides=28,grooves=1)
    for i in range(5):
        offset=(i-2)*.055
        pts=[(offset*.2,.55,2.18),(offset,.72,2.10),(offset*1.3,.83,1.83),
             (offset*1.2+.025,.81,1.49),(offset*.6+.08,.70,1.21),(.11+offset*.4,.59,1.11+abs(i-2)*.055)]
        strand("Layered ponytail lock "+str(i),pts,[.045,.070,.075,.062,.040,.0015],
               [.03,.035,.035,.03,.02,.001],MATERIALS["hair" if i%2 else "hair middle"],sides=24,grooves=1)
    # A small cloth tie, with two folded ribbons. No giant decorative bow.
    ellipsoid("Pale-blue ponytail knot",(0,.54,2.20),(.075,.047,.048),MATERIALS["blue light"])
    for sign in (-1,1):
        strand("Folded hair tie "+str(sign),[(sign*.025,.55,2.20),(sign*.13,.56,2.25),
                (sign*.17,.55,2.19),(sign*.09,.54,2.17)],
                [.019,.031,.030,.012],[.006,.012,.010,.005],MATERIALS["blue light"],sides=20)
        ribbon("Long silk tie "+str(sign),[(sign*.04,.58,2.19),(sign*.20,.76,1.92),
                (sign*.24,.83,1.60),(sign*.26,.74,1.32)],[.034,.044,.038,.028],MATERIALS["blue light"])


def ribbon(name,points,widths,mat):
    centers=spline(points)
    verts,faces=[],[]
    columns=9
    for row,p in enumerate(centers):
        t=row/(len(centers)-1)
        for col in range(columns):
            u=2*col/(columns-1)-1
            verts.append(tuple(p+Vector((u*sample(widths,t),-.005*(1-u*u),.006*math.sin(t*TAU)*u))))
    for row in range(len(centers)-1):
        for col in range(columns-1):
            a=row*columns+col;faces.append((a,a+columns,a+columns+1,a+1))
    obj=mesh(name,verts,faces,mat)
    thick=obj.modifiers.new("Fabric thickness","SOLIDIFY");thick.thickness=.004
    return obj


TORSO=[(.0,.54,.29),(.22,.59,.32),(.48,.62,.32),(.70,.58,.285),
       (.82,.43,.24),(.89,.20,.17)]


def torso_y(x,z):
    if z>.89:
        width=.125*math.sqrt(max(.10,1-((z-.98)/.17)**2))
        return -.115*math.sqrt(max(.02,1-(x/width)**2))
    rx,ry=profile_at(TORSO,max(0,min(.89,z)))
    return -ry*math.sqrt(max(.04,1-(x/rx)**2))


def garment():
    # The cut bust has real shoulder/neck volume and close-fitting cloth layers.
    vertices,faces=[],[]
    rows,cols=72,128
    for row in range(rows+1):
        z=.89*row/rows;rx,ry=profile_at(TORSO,z)
        for col in range(cols):
            phi=-math.pi+TAU*col/cols
            fold=.007*math.sin(phi*10)*math.exp(-((z-.60)/.24)**2)
            vertices.append(((rx+fold)*math.sin(phi),-(ry+fold*.7)*math.cos(phi),z))
    for row in range(rows):
        for col in range(cols):
            a=row*cols+col;b=row*cols+(col+1)%cols
            faces.append((a,a+cols,b+cols,b))
    faces.append(tuple(reversed(range(cols))))
    mesh("Ivory shoulder garment with cloth volume",vertices,faces,MATERIALS["ivory"])
    # Neck sits inside the collar, visible immediately beneath the jaw.
    ellipsoid("Neck",(0,.0,.98),(.125,.115,.17),MATERIALS["ear skin"])
    # Sleeveless vest panels wrap around both sides of the shoulder.
    for sign in (-1,1):
        verts,fs=[],[];r,c=48,40
        for row in range(r):
            t=row/(r-1);z=.025+.86*t
            rx,ry=profile_at(TORSO,z)
            for col in range(c):
                u=col/(c-1)
                # Front opening is narrow at the waist, opens towards neck.
                start=.07+.22*t*t
                phi=sign*(start+(math.pi-start-.12)*u)
                fold=.005*math.sin(u*math.pi*5+t*2)*math.sin(math.pi*t)
                verts.append(((rx+.014+fold)*math.sin(phi),-(ry+.014+fold)*math.cos(phi),z))
        for row in range(r-1):
            for col in range(c-1):
                a=row*c+col;face=(a,a+c,a+c+1,a+1)
                fs.append(tuple(reversed(face)) if sign<0 else face)
        obj=mesh("Wrapped blue vest "+str(sign),verts,fs,MATERIALS["blue"])
        thick=obj.modifiers.new("Cloth edge thickness","SOLIDIFY");thick.thickness=.007
    # Lapels are flat cloth strips conforming to torso, with a rolled edge.
    def lapel(name,xzs,width,mat):
        path=spline([(x,0,z) for x,z in xzs])
        verts,fs=[],[];columns=13
        for i,p in enumerate(path):
            tangent=path[min(len(path)-1,i+1)]-path[max(0,i-1)]
            side=Vector((tangent.z,0,-tangent.x)).normalized()
            for col in range(columns):
                u=2*col/(columns-1)-1
                q=p+side*(width*u)
                q.y=torso_y(q.x,q.z)-.026-.005*(1-u*u)
                verts.append(tuple(q))
        for row in range(len(path)-1):
            for col in range(columns-1):
                a=row*columns+col;fs.append((a,a+columns,a+columns+1,a+1))
        obj=mesh(name,verts,fs,mat)
        thick=obj.modifiers.new("Lapel fabric thickness","SOLIDIFY");thick.thickness=.006
    lapel("Ivory wrapped outer collar",[(-.09,.95),(-.115,.87),(-.035,.72),(.10,.55),(.25,.40)],.036,MATERIALS["ivory light"])
    lapel("Ivory under collar",[(.09,.95),(.115,.88),(.03,.72)],.032,MATERIALS["ivory light"])


def studio(size):
    scene=bpy.context.scene
    scene.render.engine="BLENDER_EEVEE_NEXT"
    scene.render.resolution_x=scene.render.resolution_y=size
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG"
    scene.render.image_settings.color_mode="RGBA"
    scene.render.film_transparent=True
    scene.render.image_settings.compression=25
    scene.render.threads_mode="FIXED";scene.render.threads=4
    scene.view_settings.view_transform="AgX"
    scene.view_settings.look="AgX - Medium High Contrast"
    world=bpy.data.worlds.new("Neutral studio")
    world.use_nodes=True
    world.node_tree.nodes["Background"].inputs["Color"].default_value=(.65,.65,.65,1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value=.65
    scene.world=world
    for name,location,power,span in (("Soft key",(-3,-4,5),430,4),
                                     ("Large fill",(4,-2,3),230,4),
                                     ("Hair edge",(0,3,4),320,3)):
        data=bpy.data.lights.new(name,"AREA");data.energy=power;data.shape="DISK";data.size=span
        obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);obj.location=location
        obj.rotation_euler=(Vector((0,0,1.2))-obj.location).to_track_quat("-Z","Y").to_euler()
    cameras={}
    for name,angle in (("front",0),("three-quarter",38),("side",90)):
        theta=math.radians(angle)
        data=bpy.data.cameras.new(name);data.type="ORTHO";data.ortho_scale=2.65
        obj=bpy.data.objects.new("Camera "+name,data);scene.collection.objects.link(obj)
        target=Vector((0,.10,1.18));obj.location=target+Vector((6*math.sin(theta),-6*math.cos(theta),.12))
        obj.rotation_euler=(target-obj.location).to_track_quat("-Z","Y").to_euler();cameras[name]=obj
    return scene,cameras


def identity():
    digest=hashlib.sha256()
    for obj in sorted(CHARACTER,key=lambda x:x.name):
        digest.update(obj.name.encode())
        for v in obj.data.vertices:digest.update(struct.pack("<3f",*v.co))
        for p in obj.data.polygons:digest.update(struct.pack("<"+"I"*len(p.vertices),*p.vertices))
    return digest.hexdigest()


def build(args):
    if args.output.exists():raise SystemExit("Refusing to overwrite output")
    args.output.mkdir(parents=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    material("skin",(.965,.803,.677),.83)
    material("ear skin",(.955,.785,.665),.86)
    material("ear inset",(.79,.53,.435),.94)
    material("lip",(.85,.59,.52),.89)
    material("lip shadow",(.51,.30,.245),.91)
    material("hair",(.205,.124,.079),.78)
    material("hair middle",(.25,.153,.094),.81)
    material("hair highlight",(.29,.185,.117),.88)
    material("hair dark",(.09,.053,.038),.88)
    material("eye white",(.97,.925,.85),.40)
    iris=material("iris",(.55,.32,.12),.45)
    attr=iris.node_tree.nodes.new("ShaderNodeVertexColor");attr.layer_name="Fixed pigment"
    iris.node_tree.links.new(attr.outputs["Color"],iris.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    material("pupil",(.07,.035,.018),.38)
    material("catchlight",(1,.98,.91),.30)
    material("ivory",(.86,.858,.80),.95,True)
    material("ivory light",(.94,.925,.86),.94,True)
    material("blue",(.31,.48,.585),.96,True)
    material("blue shadow",(.20,.34,.42),.94)
    material("blue light",(.52,.68,.75),.90,True)
    clay=material("Structural gray clay",(.55,.55,.55),.83)
    head();facial_details();eye(-1);eye(1);hair();garment()
    scene,cameras=studio(args.size)
    baseline=identity()
    source=args.output/"source";source.mkdir()
    shutil.copy2(__file__,source/"build_bust.py")
    if args.reference:
        shutil.copy2(args.reference,source/"identity-reference.png")
    scene.camera=cameras["three-quarter"]
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output/"jiang-bust.blend"))
    renders={}
    original_slots={obj.name:list(obj.data.materials) for obj in CHARACTER}
    for mode in ("painted","clay"):
        # Explicitly replace mesh slots: Eevee does not apply the view-layer
        # override consistently in this runtime. Verify actual pixels below.
        for obj in CHARACTER:
            obj.data.materials.clear()
            for mat in ([clay] if mode=="clay" else original_slots[obj.name]):
                obj.data.materials.append(mat)
        for view,camera in cameras.items():
            scene.camera=camera
            filename=view+"-"+mode+".png"
            scene.render.filepath=str(args.output/filename)
            bpy.ops.render.render(write_still=True)
            assert identity()==baseline,"Geometry changed during camera/material review"
            renders[filename]={"sha256":hashlib.sha256((args.output/filename).read_bytes()).hexdigest(),
                               "geometry_sha256":baseline,"material_override":mode=="clay"}
    receipt={"status":"STATIC_BUST_CANDIDATE_AWAITING_USER_REVIEW","runtime":bpy.app.version_string,
             "size":[args.size,args.size],"geometry_sha256":baseline,"renders":renders,
             "mesh_objects":len(CHARACTER),"vertices":sum(len(o.data.vertices) for o in CHARACTER),
             "image_textures":sum(1 for mat in bpy.data.materials if mat.use_nodes
                                  for node in mat.node_tree.nodes if node.type=="TEX_IMAGE"),
             "no_face_billboard":True,"animation_actions":len(bpy.data.actions),
             "external_generations":0,"clay_is_uniform_material_replacement":True,
             "limitations":["Procedurally authored static geometry; not a hand-sculpted commissioned asset",
                            "No animation-ready retopology, facial rig or final character approval"],
             "source_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (args.output/"receipt.json").write_text(json.dumps(receipt,indent=2)+"\n")
    print(json.dumps({"status":"DONE","output":str(args.output),"geometry_sha256":baseline}))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--reference",type=Path)
    parser.add_argument("--size",type=int,default=1200)
    build(parser.parse_args(sys.argv[sys.argv.index("--")+1:]))
