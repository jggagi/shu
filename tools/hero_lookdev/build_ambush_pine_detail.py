#!/usr/bin/env python3
"""Author one spreading pine with real branching, needle geometry and CC0 fronds.

Uses only the already acquired Quaternius Standard bark/normal/alpha images.
No image generation or painting. Python builds a deterministic GLB; the existing
Blender imports that same GLB and packs an editable source project for review.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, io, json, math, os, struct, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / ".local/sources/songfeng-environment/standard-original/glTF"
WORK = ROOT / ".local/sources/songfeng-detail"
OUTPUT = ROOT / "assets/art/mountain_ambush/environment/detailed-pine.glb"
SEED = 4217
HORIZONTAL_FACTOR = .80  # Keep the spreading crown inside one normalized tree-height.

def sha(data): return hashlib.sha256(data).hexdigest()
def unit(v):
    v = np.asarray(v, dtype=float)
    return v / max(1e-10, np.linalg.norm(v))
def vector(v): return np.asarray(v, dtype=float)
def smooth(t): return t*t*(3-2*t)

class Geometry:
    def __init__(self): self.groups = {}
    def group(self, material): return self.groups.setdefault(material, {"p": [], "n": [], "uv": [], "i": []})
    def add(self, material, positions, normals, uvs, faces):
        g = self.group(material); base = len(g["p"])
        g["p"].extend(positions); g["n"].extend(normals); g["uv"].extend(uvs)
        for face in faces:
            for i in range(1, len(face)-1): g["i"].extend([base+face[0],base+face[i],base+face[i+1]])
    def points(self):
        for g in self.groups.values():
            for p in g["p"]: yield p

def sample_curve(points, subdivisions=4):
    p = [vector(x) for x in points]; out = []
    for i in range(len(p)-1):
        a=p[max(0,i-1)]; b=p[i]; c=p[i+1]; d=p[min(len(p)-1,i+2)]
        for k in range(subdivisions):
            t=k/subdivisions
            out.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
    return out+[p[-1]]

def tube(mesh, points, radii, sides=9, material=0, flute=0.0):
    points=[vector(p) for p in points]; vertices=[]; normals=[]; uvs=[]; faces=[]; length=0.
    previous_u=None
    for i,p in enumerate(points):
        tangent=unit(points[min(i+1,len(points)-1)]-points[max(0,i-1)])
        reference=vector((0,0,1)) if abs(tangent[2])<.92 else vector((0,1,0))
        u=unit(np.cross(tangent,reference))
        if previous_u is not None and np.dot(previous_u,u)<0: u=-u
        v=unit(np.cross(tangent,u));previous_u=u
        if i: length+=np.linalg.norm(p-points[i-1])
        radius=radii[0]+(radii[-1]-radii[0])*i/max(1,len(points)-1) if len(radii)==2 else radii[i]
        for j in range(sides+1):
            angle=j*math.tau/sides
            normal=math.cos(angle)*u+math.sin(angle)*v
            radius_j=radius*(1+flute*math.sin(angle*5+.7*i)+flute*.45*math.sin(angle*9-i*.4))
            vertices.append(p+normal*radius_j);normals.append(normal);uvs.append((j/sides,length*6))
    for i in range(len(points)-1):
        for j in range(sides):
            a=i*(sides+1)+j;faces.append((a,a+1,a+sides+2,a+sides+1))
    faces.append(tuple(reversed(range(sides))));faces.append(tuple((len(points)-1)*(sides+1)+j for j in range(sides)))
    mesh.add(material,vertices,normals,uvs,faces)

def frond(mesh, base, forward, width, length, material, rng):
    # A gently curved narrow frond, never an opaque circular canopy sheet.
    forward=unit(forward);side=unit(np.cross(forward,vector((0,0,1))))
    normal=unit(np.cross(side,forward));vertices=[];normals=[];uvs=[];faces=[]
    for row in range(4):
        t=row/3
        center=base+forward*length*t+normal*(math.sin(math.pi*t)*length*.12)
        for sign in [-1,1]:
            vertices.append(center+side*width*.5*sign)
            normals.append(normal);uvs.append(((sign+1)*.5,t))
    for i in range(3):faces.append((2*i,2*i+1,2*i+3,2*i+2))
    mesh.add(material,vertices,normals,uvs,faces)

def needle(mesh, base, direction, length, width, material):
    direction=unit(direction)
    u=unit(np.cross(direction,vector((0,0,1))))
    if np.linalg.norm(u)<.01:u=vector((1,0,0))
    v=unit(np.cross(direction,u))
    # Crossed tapered strips remain real thin geometry from every direction.
    for axis,normal in [(u,v),(v,u)]:
        tip=base+direction*length
        positions=[base-axis*width,base+axis*width,tip+axis*width*.07,tip-axis*width*.07]
        mesh.add(material,positions,[normal]*4,[(.44,.22),(.56,.22),(.52,.88),(.48,.88)],[(0,1,2,3)])

def author():
    rng=np.random.default_rng(SEED)
    trunk=Geometry();branches=Geometry();crown=Geometry()
    main=sample_curve([(0,0,.012),(-.025,.006,.12),(.012,-.012,.25),(.070,-.018,.39),(.045,.010,.56),(.105,.005,.73),(.115,.015,.91),(.145,.010,.985)],5)
    radii=[.048*(1-i/(len(main)-1))**1.10+.003 for i in range(len(main))]
    tube(trunk,main,radii,18,flute=.12)
    # Asymmetrical visible roots, with broad shoulders tapering into the ground.
    for i in range(9):
        a=i*math.tau/9+float(rng.uniform(-.16,.16)); reach=float(rng.uniform(.11,.19));d=vector((math.cos(a),math.sin(a),0))
        path=sample_curve([vector((0,0,.075)),d*.055+vector((0,0,.032)),d*reach*.75+vector((0,0,.011)),d*reach+vector((0,0,.004))],3)
        tube(trunk,path,[.024,.0013],10,flute=.13)
    specs=[(.37,3.35,.43),(.45,.10,.47),(.53,1.70,.35),(.61,4.85,.39),(.68,2.85,.36),(.77,.42,.30),(.85,2.1,.24),(.92,4.75,.18)]
    tuft_sites=[];secondary_count=0;twig_count=0
    for k,(height,angle,reach) in enumerate(specs):
        start=min(main,key=lambda p:abs(p[2]-height)).copy();d=vector((math.cos(angle),math.sin(angle),0));side=vector((-d[1],d[0],0))
        controls=[start,start+d*reach*.22+vector((0,0,-.004)),start+d*reach*.55+vector((0,0,-.035)),start+d*reach*.90+vector((0,0,.018)),start+d*reach+vector((0,0,.055))]
        path=sample_curve(controls,4)
        tube(branches,path,[.020*(1-k*.055),.0032],11,flute=.10)
        for j,t in enumerate([.38,.58,.78,.96]):
            stem=path[round(t*(len(path)-1))];sgn=-1 if j%2 else 1
            direction=unit(d*.66+side*sgn*.70+vector((0,0,.12)))
            length=reach*(.30 if j<3 else .22)
            secondary=sample_curve([stem,stem+direction*length*.55+vector((0,0,-.007)),stem+direction*length+vector((0,0,.025))],4)
            tube(branches,secondary,[.006,.0013],8,flute=.08);secondary_count+=1
            for n in range(3):
                place=secondary[round((.45+n*.24)*(len(secondary)-1))]
                twig_direction=unit(direction*.65+side*(n-1)*.45+vector((0,0,.25)))
                tip=place+twig_direction*float(rng.uniform(.045,.075))
                tube(branches,sample_curve([place,(place+tip)*.5-vector((0,0,.003)),tip],2),[.0022,.00055],6);twig_count+=1
                tuft_sites.append((tip,twig_direction,k))
        # A few dry tips expose real branching and retain negative spaces.
        if k%2==0:
            tip=path[-1]+d*.045+vector((0,0,.018))
            tube(branches,[path[-2],path[-1],tip],[.0028,.0004],6)
    for base,direction,k in tuft_sites:
        material=1+(k%3)
        # Small twiglets sit inside the independently moving needle crown.
        end=base+direction*.047+vector((0,0,.012))
        tube(crown,[base,(base+end)*.5,end],[.0012,.00035],5,material=0)
        side=unit(np.cross(direction,vector((0,0,1))));up=unit(np.cross(side,direction))
        for whorl in range(3):
            position=base+direction*(.006+whorl*.014)
            for n in range(7):
                a=n*math.tau/7+whorl*.8+float(rng.uniform(-.15,.15))
                outward=unit(direction*.35+side*math.cos(a)+up*math.sin(a)*.68+vector((0,0,.15)))
                needle(crown,position,outward,float(rng.uniform(.040,.073)),float(rng.uniform(.0010,.0016)),material)
        for n in range(10):
            a=math.atan2(direction[1],direction[0])+(n-4.5)*.23+float(rng.uniform(-.14,.14))
            forward=unit(vector((math.cos(a),math.sin(a),float(rng.uniform(.10,.45)))))
            place=base+direction*float(rng.uniform(-.015,.035))+side*float(rng.uniform(-.018,.018))
            frond(crown,place,forward,float(rng.uniform(.028,.049)),float(rng.uniform(.080,.135)),material,rng)
    return [trunk,branches,crown],{"primary_boughs":len(specs),"secondary_boughs":secondary_count,"terminal_twigs":twig_count,"needle_tufts":len(tuft_sites),"individual_needles":len(tuft_sites)*21,"alpha_fronds":len(tuft_sites)*10}

def embed_texture(path,cap,binary,document):
    raw=path.read_bytes()
    with Image.open(io.BytesIO(raw)) as image:
        before=list(image.size);image.thumbnail((cap,cap),Image.Resampling.LANCZOS)
        output=io.BytesIO();image.save(output,format="PNG",optimize=True);encoded=output.getvalue();after=list(image.size)
    binary.extend(b"\0"*(-len(binary)%4));offset=len(binary);binary.extend(encoded)
    index=len(document["bufferViews"]);document["bufferViews"].append({"buffer":0,"byteOffset":offset,"byteLength":len(encoded)})
    document["images"].append({"name":path.stem,"mimeType":"image/png","bufferView":index})
    document["textures"].append({"source":len(document["images"])-1,"sampler":0})
    return {"source":str(path.relative_to(ROOT)),"source_sha256":sha(raw),"source_dimensions":before,"embedded_dimensions":after,"embedded_sha256":sha(encoded),"bytes":len(encoded),"processing":"Existing original image resized only; no generated/repainted pixels"}

def pack(meshes,structure):
    vertices=np.array([p for m in meshes for p in m.points()]);floor=float(vertices[:,2].min());top=float(vertices[:,2].max());factor=1/(top-floor)
    pivot=(vector((0,0,.60))-vector((0,0,floor)))*factor
    document={"asset":{"version":"2.0","generator":"Shu authored detailed pine geometry","copyright":"Original Shu geometry; Quaternius CC0 bark and alpha-frond images"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"SongfengDetailedPine","children":[1,2,3]}],"meshes":[],"accessors":[],"bufferViews":[],"images":[],"textures":[],"samplers":[{"magFilter":9729,"minFilter":9987,"wrapS":10497,"wrapT":10497}],"materials":[]}
    binary=bytearray()
    texture_rows=[embed_texture(SOURCE/name,512,binary,document) for name in ["Bark_NormalTree.png","Bark_NormalTree_Normal.png","Leaf_Pine_C.png"]]
    document["materials"].append({"name":"DetailedPine_TexturedBark","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"baseColorFactor":[.65,.61,.52,1],"roughnessFactor":.95,"metallicFactor":0},"normalTexture":{"index":1,"scale":.65},"doubleSided":False})
    for label,tint in [("Deep",[.48,.63,.68,1]),("Middle",[.60,.73,.74,1]),("Lit",[.75,.83,.78,1])]:
        document["materials"].append({"name":"DetailedPine_AlphaNeedles_"+label,"alphaMode":"MASK","alphaCutoff":.32,"doubleSided":True,"pbrMetallicRoughness":{"baseColorTexture":{"index":2},"baseColorFactor":tint,"roughnessFactor":.96,"metallicFactor":0}})
    def accessor(values,kind,component,bound=False):
        a=np.asarray(values,dtype={5126:"<f4",5123:"<u2",5125:"<u4"}[component]);data=a.tobytes();binary.extend(b"\0"*(-len(binary)%4));offset=len(binary);binary.extend(data)
        view=len(document["bufferViews"]);document["bufferViews"].append({"buffer":0,"byteOffset":offset,"byteLength":len(data)})
        row={"bufferView":view,"componentType":component,"count":len(values),"type":kind}
        if bound:row.update({"min":a.min(axis=0).astype(float).tolist(),"max":a.max(axis=0).astype(float).tolist()})
        i=len(document["accessors"]);document["accessors"].append(row);return i
    names=["PineRootAndTrunk","PineBoughs","WindCrown"];triangles=[]
    def gltf(p):return [p[0],p[2],-p[1]]
    for number,mesh in enumerate(meshes):
        primitives=[];tri=0
        for material,g in mesh.groups.items():
            pos=[(vector(p)-vector((0,0,floor)))*factor*vector((HORIZONTAL_FACTOR,HORIZONTAL_FACTOR,1))-(pivot if number==2 else 0) for p in g["p"]]
            normals=[unit(vector(n)/vector((HORIZONTAL_FACTOR,HORIZONTAL_FACTOR,1))) for n in g["n"]]
            attrs={"POSITION":accessor([gltf(p) for p in pos],"VEC3",5126,True),"NORMAL":accessor([gltf(n) for n in normals],"VEC3",5126),"TEXCOORD_0":accessor(g["uv"],"VEC2",5126)}
            index=accessor(g["i"],"SCALAR",5123 if len(g["p"])<65536 else 5125)
            primitives.append({"attributes":attrs,"indices":index,"material":material});tri+=len(g["i"])//3
        triangles.append(tri);document["meshes"].append({"name":names[number],"primitives":primitives})
        node={"name":names[number],"mesh":number}
        if number==2:node.update({"translation":gltf(pivot),"extras":{"wind_part":"needles_only","suggested_max_angle_radians":.008}})
        document["nodes"].append(node)
    document["buffers"]=[{"byteLength":len(binary)}];encoded=json.dumps(document,separators=(",",":")).encode();encoded+=b" "*(-len(encoded)%4);binary.extend(b"\0"*(-len(binary)%4))
    data=struct.pack("<III",0x46546c67,2,12+8+len(encoded)+8+len(binary))+struct.pack("<II",len(encoded),0x4e4f534a)+encoded+struct.pack("<II",len(binary),0x004e4942)+binary
    if not 15000<=sum(triangles)<=35000 or len(data)>3_000_000:raise RuntimeError("Detailed tree exceeds the agreed geometry or byte budget")
    OUTPUT.parent.mkdir(parents=True,exist_ok=True);temporary=OUTPUT.with_suffix('.working.glb');temporary.write_bytes(data);os.replace(temporary,OUTPUT)
    return {"triangles":sum(triangles),"mesh_triangles":dict(zip(names,triangles)),"mesh_count":3,"bytes":len(data),"sha256":sha(data),"textures":texture_rows,"structure":structure,"bounds":{"min":[float(vertices[:,0].min()*factor*HORIZONTAL_FACTOR),0,float(-vertices[:,1].max()*factor*HORIZONTAL_FACTOR)],"max":[float(vertices[:,0].max()*factor*HORIZONTAL_FACTOR),1,float(-vertices[:,1].min()*factor*HORIZONTAL_FACTOR)]},"normalization":{"up":"+Y","height":1,"floor":0,"root_origin":"original root center, no XZ recentering","uniform_factor":factor,"horizontal_factor":HORIZONTAL_FACTOR,"source_floor":floor},"wind":{"node_name":"WindCrown","fixed_nodes":["PineRootAndTrunk","PineBoughs"],"pivot_gltf":gltf(pivot),"suggested_max_angle_radians":.008,"clock":"Host shared presentation step; no per-instance runtime clock embedded"}}

def save_blender_source(path):
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(OUTPUT))
    for image in bpy.data.images:
        if image.type!='RENDER_RESULT':image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(path))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--blender-source',action='store_true');args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else None)
    WORK.mkdir(parents=True,exist_ok=True);blend=WORK/'detailed-pine.blend'
    if args.blender_source:save_blender_source(blend);return
    meshes,structure=author();record=pack(meshes,structure)
    subprocess.run(['blender','--background','--factory-startup','--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--blender-source'],check=True)
    record.update({"status":"new detailed environment candidate, not user-approved","geometry_author":"Codex for Shu, original procedural roots/branching/needles/fronds","texture_author":"Quaternius","source_pack":"Stylized Nature MegaKit Standard, official free upload 11055123","source_url":"https://quaternius.itch.io/stylized-nature-megakit","source_archive_sha256":"298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9","license":"CC0-1.0 for source textures","license_file":"License_Quaternius_CC0.txt","source_project":str(blend.relative_to(ROOT)),"source_project_sha256":sha(blend.read_bytes()),"builder":"tools/hero_lookdev/build_ambush_pine_detail.py","builder_sha256":sha(Path(__file__).read_bytes()),"seed":SEED,"new_generated_images":0,"new_installs":0,"cost_usd":0,"limits":["Original source alpha frond is a broad silhouette; fine needles are real new geometry, not claimed texture detail.","No shader dependency, skeletal rig or automatic runtime wind.","Alpha-tested foliage may alias at distance; target scene review remains required."]})
    (OUTPUT.parent/'source-detail-pine.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    print('DETAILED_PINE_BUILT',json.dumps({k:record[k] for k in ['triangles','mesh_triangles','bytes','sha256','bounds','structure']}),flush=True)

if __name__=='__main__':main()
