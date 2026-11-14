#!/usr/bin/env python3
"""Author and export the small Chengdu Blender kit (run with Blender Python).

Reproduce: blender --background --factory-startup --python tools/art/build_chengdu_blender_kit.py
Only source .blend, two selected-mesh GLBs and their audit/provenance are written.
All authored coordinates below use Godot's metre / Y-up / front +Z convention.
Blender stores (x,-z,y), and its standard Y-up glTF exporter restores (x,y,z).
The six semantic material groups share an atlas contract, without an external
image dependency inside GLB.  Godot attaches Krita's painted atlas at runtime.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import random
import struct
import sys

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/source/chengdu-blender-kit-20261110"
OUTPUT = ROOT / "assets/art/chengdu_blender_kit_20261110"
SEED = 1102026
ROLES = ("plaster", "wood", "roof", "stone", "leaf", "ceramic")
COLORS = {
    "plaster": (0.61, 0.55, 0.40, 1),
    "wood": (0.20, 0.105, 0.045, 1),
    "roof": (0.21, 0.27, 0.26, 1),
    "stone": (0.43, 0.43, 0.33, 1),
    "leaf": (0.31, 0.41, 0.12, 1),
    "ceramic": (0.56, 0.62, 0.47, 1),
}
PIXEL_X = (0, 341, 682, 1024)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bvec(p):
    return (p[0], -p[2], p[1])


def gv(p):
    return (p[0], p[2], -p[1])


def atlas_uv(role, uv):
    """Exact 16px inset texel centres, PNG top row = plaster/wood/roof."""
    index = ROLES.index(role)
    column, row = index % 3, index // 3
    px = PIXEL_X[column] + 16.5 + uv[0] * (PIXEL_X[column + 1] - PIXEL_X[column] - 33)
    py = row * 512 + 16.5 + uv[1] * 479
    return (px / 1024, 1 - py / 1024)


class Geometry:
    def __init__(self, role):
        self.role = role
        self.vertices = []
        self.faces = []
        self.uvs = []
        self.smooth = []

    def add(self, vertices, faces, uvs=None, smooth=False):
        base = len(self.vertices)
        self.vertices.extend(vertices)
        for index, face in enumerate(faces):
            self.faces.append(tuple(base + i for i in face))
            if uvs is not None:
                self.uvs.append([atlas_uv(self.role, uv) for uv in uvs[index]])
            elif len(face) == 4:
                self.uvs.append([atlas_uv(self.role, p) for p in [(0, 1), (1, 1), (1, 0), (0, 0)]])
            else:
                self.uvs.append([atlas_uv(self.role, p) for p in [(0, 1), (1, 1), (.5, 0)]])
            self.smooth.append(smooth)

    def box(self, center, size):
        x, y, z = center
        a, b, c = (n * .5 for n in size)
        verts = [(x-a, y-b, z-c), (x+a, y-b, z-c), (x+a, y+b, z-c), (x-a, y+b, z-c),
                 (x-a, y-b, z+c), (x+a, y-b, z+c), (x+a, y+b, z+c), (x-a, y+b, z+c)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                 (3, 7, 6, 2), (0, 4, 7, 3), (1, 2, 6, 5)]
        if self.role == "plaster":
            # AO on only four buried wall corners would darken the full face.
            # Author real interior face samples every <=.20m before baking.
            for face in faces:
                a0, a1, a2, a3 = [Vector(verts[i]) for i in face]
                nu = max(1, math.ceil((a1-a0).length/.20))
                nv = max(1, math.ceil((a3-a0).length/.20))
                points, quads, uv = [], [], []
                for j in range(nv+1):
                    for i in range(nu+1):
                        points.append(tuple(a0+(a1-a0)*(i/nu)+(a3-a0)*(j/nv)))
                for j in range(nv):
                    for i in range(nu):
                        quads.append((j*(nu+1)+i,j*(nu+1)+i+1,(j+1)*(nu+1)+i+1,(j+1)*(nu+1)+i))
                        uv.append([(i/nu,1-j/nv),((i+1)/nu,1-j/nv),
                                   ((i+1)/nu,1-(j+1)/nv),(i/nu,1-(j+1)/nv)])
                self.add(points,quads,uv)
            return
        self.add(verts, faces)

    def tube(self, points, radii, sides=8):
        """Tapered bent branch / cylindrical timber with shared smooth sides."""
        points = [Vector(p) for p in points]
        vertices = []
        for i, (point, radius) in enumerate(zip(points, radii)):
            tangent = (points[min(i+1, len(points)-1)] - points[max(0, i-1)]).normalized()
            reference = Vector((0, 1, 0)) if abs(tangent.y) < .9 else Vector((1, 0, 0))
            across = tangent.cross(reference).normalized()
            along = tangent.cross(across).normalized()
            for k in range(sides):
                theta = k * math.tau / sides
                vertices.append(tuple(point + radius * (math.cos(theta)*across + math.sin(theta)*along)))
        faces, uvs = [], []
        for ring in range(len(points)-1):
            for k in range(sides):
                nxt = (k+1) % sides
                faces.append((ring*sides+k, ring*sides+nxt, (ring+1)*sides+nxt, (ring+1)*sides+k))
                uvs.append([(k/sides, ring/(len(points)-1)), ((k+1)/sides, ring/(len(points)-1)),
                            ((k+1)/sides, (ring+1)/(len(points)-1)), (k/sides, (ring+1)/(len(points)-1))])
        # Fan caps avoid n-gons and provide a solid branch, including its foot.
        for ring, reverse in [(0, True), (len(points)-1, False)]:
            center = len(vertices)
            vertices.append(tuple(points[ring]))
            for k in range(sides):
                face = (center, ring*sides+k, ring*sides+(k+1) % sides)
                faces.append(face[::-1] if reverse else face)
                uvs.append([(.5, .5), (0, 1), (1, 1)])
        self.add(vertices, faces, uvs, smooth=True)

    def pot(self, x, z, base, height, radius, shape="jar"):
        if shape == "cup":
            profile = [(0, .62), (.12, .78), (.87, 1), (1, 1), (1, .81), (.30, .57)]
        elif shape == "basket":
            profile = [(0, .67), (.13, .88), (.80, 1), (1, .94), (1, .77), (.30, .64)]
        else:
            profile = [(0, .62), (.12, .87), (.48, 1), (.82, .85), (.91, .58), (1, .62), (1, .45), (.91, .43)]
        vertices = []
        n = 12
        for y, r in profile:
            for k in range(n):
                theta = k * math.tau / n
                vertices.append((x+radius*r*math.cos(theta), base+height*y, z+radius*r*math.sin(theta)))
        faces, uvs = [], []
        for ring in range(len(profile)-1):
            for k in range(n):
                nxt = (k+1) % n
                faces.append((ring*n+k, ring*n+nxt, (ring+1)*n+nxt, (ring+1)*n+k))
                uvs.append([(k/n, ring/(len(profile)-1)), ((k+1)/n, ring/(len(profile)-1)),
                            ((k+1)/n, (ring+1)/(len(profile)-1)), (k/n, (ring+1)/(len(profile)-1))])
        self.add(vertices, faces, uvs, smooth=True)

    def folded_leaf(self, vertices):
        """A hexagonal, shallow-fold leaf: four genuine 3D triangles."""
        faces = [(0,1,2),(0,2,3),(0,3,4),(0,4,5)]
        uv = [(.5,1),(.05,.75),(0,.32),(.5,0),(1,.32),(.95,.75)]
        self.add(vertices,faces,[[uv[i] for i in face] for face in faces])


def tea_shop():
    geo = {role: Geometry(role) for role in ROLES}
    p, w, r, s = (geo[k] for k in ["plaster", "wood", "roof", "stone"])
    # A compact solid plinth stays below the inherited collision footprint.
    s.box((0, .08, -.055), (1.88, .16, 1.57))
    # Actual 11cm plaster walls, with a door opening and deep east window.
    p.box((0, 1.02, -.71), (1.86, 1.72, .11))
    p.box((-.875, 1.02, -.075), (.11, 1.72, 1.27))
    p.box((.875, .555, -.075), (.11, .79, 1.27))
    p.box((.875, 1.715, -.075), (.11, .33, 1.27))
    p.box((.875, 1.25, -.65), (.11, .60, .12))
    p.box((.875, 1.25, .3825), (.11, .60, .345))
    for x in [-.73, .73]:
        p.box((x, .93, .555), (.40, 1.54, .11))
    p.box((0, 1.76, .555), (1.86, .24, .11))
    # Door posts, corner posts, sill and load-bearing front/back beams.
    for x in [-.88, .88]:
        for z in [-.69, .565]:
            w.box((x, 1.06, z), (.09, 1.80, .09))
            s.box((x, .205, z), (.14, .09, .14))
    for x in [-.50, .50]:
        w.box((x, .96, .60), (.075, 1.60, .10))
    for z in [-.72, .58]:
        for y in [.32, 1.63, 1.91]:
            w.box((0, y, z), (1.87, .075, .095))
    for x in [-.9, .9]:
        w.box((x, 1.91, -.075), (.075, .075, 1.48))
        w.box((x, .31, -.075), (.070, .060, 1.27))
    # East window is empty space; the inner jamb and opened shutters have depth.
    for z in [-.59, .21]:
        w.box((.875, 1.25, z), (.15, .66, .045))
    for y in [.95, 1.55]:
        w.box((.875, y, -.1905), (.15, .055, .84))
    # A recessed inner lattice is behind the physical outer frame.
    for z in [-.44, -.28, -.12, .04]:
        w.box((.823, 1.25, z), (.027, .54, .025))
    for y in [1.15, 1.39]:
        w.box((.824, y, -.1905), (.028, .025, .73))
    for z in [-.695, .405]:
        w.box((.925, 1.25, z), (.045, .55, .14))
        for yy in [1.05, 1.25, 1.45]:
            w.box((.955, yy, z), (.022, .027, .135))
    # Preserve the existing TeaPolish cloth, counter, tea vessels and bamboo
    # screen.  This exported shell adds no duplicate shopfront props.
    for xx in [-.87, -.35, .36, .87]:
        w.box((xx, 1.91, .685), (.10, .10, .30))
        w.box((xx, 1.85, .625), (.055, .18, .10))
        w.box((xx, 1.97, .78), (.15, .05, .16))
    # True curved, hipped main roof: a thick closed shell, not intersecting cards.
    def roof_y(x, z):
        front_back = abs((z + .045) / 1.06)
        hip = max(0, (abs(x)-.56)/.42) * .82
        t = min(1, max(front_back, hip))
        return 2.59 - .64 * (t**.72) + .105 * (t**6)
    nx, nz = 18, 18
    vertices = []
    for offset in [0, -.048]:
        for j in range(nz+1):
            zz = -1.035 + j * 2.07/nz
            for i in range(nx+1):
                xx = -.975 + i * 1.95/nx
                vertices.append((xx, roof_y(xx, zz)+offset, zz))
    faces, uvs = [], []
    stride, layer = nx+1, (nx+1)*(nz+1)
    for side in [0, 1]:
        for j in range(nz):
            for i in range(nx):
                face = (side*layer+j*stride+i, side*layer+j*stride+i+1,
                        side*layer+(j+1)*stride+i+1, side*layer+(j+1)*stride+i)
                face_uv = [(i/nx,j/nz), ((i+1)/nx,j/nz), ((i+1)/nx,(j+1)/nz), (i/nx,(j+1)/nz)]
                faces.append(face[::-1] if not side else face)
                uvs.append(face_uv[::-1] if not side else face_uv)
    edges = [(j*stride, (j+1)*stride) for j in range(nz)]
    edges += [(j*stride+nx, (j+1)*stride+nx) for j in range(nz)]
    edges += [(i, i+1) for i in range(nx)]
    edges += [(nz*stride+i, nz*stride+i+1) for i in range(nx)]
    for a, b in edges:
        faces.append((a, a+layer, b+layer, b))
        uvs.append([(0,0), (0,1), (1,1), (1,0)])
    r.add(vertices, faces, uvs)
    # Low-relief tile channels, with lips following the roof curve.
    for xx in [i*.122 for i in range(-7,8)]:
        for sign in [-1, 1]:
            path = []
            for j in range(9):
                zz = -.045 + sign*(.06 + .925*j/8)
                path.append((xx, roof_y(xx,zz)+.009, zz))
            r.tube(path, [.012]*len(path), 4)
    # Double-cap ridge and gently lifted terminal detail stay below 2.63m.
    r.tube([(-.72,2.602,-.045),(.72,2.602,-.045)], [.025,.025], 8)
    for sign in [-1,1]:
        r.tube([(sign*.68,2.60,-.045),(sign*.77,2.608,-.045),(sign*.80,2.615,-.045)], [.021,.017,.010], 6)
    return geo, {"front":"+z", "primary_visible_side":"+x", "opening":"real front door and 11cm-deep side window", "roof":"closed curved hip shell with raised tile channels", "room_gameplay":False}


def courtyard_tree():
    geo = {role: Geometry(role) for role in ROLES}
    w, leaf = geo["wood"], geo["leaf"]
    # Root flare and a single tapered, non-vertical trunk with no ground plane.
    trunk = [(0,0,0),(.015,.22,.01),(-.025,.85,.005),(-.06,1.43,.025),(.045,2.10,.04),(.09,2.62,.095),(.03,3.30,.075)]
    w.tube(trunk, [.15,.125,.105,.088,.071,.050,.020], 10)
    for i in range(6):
        theta = i*math.tau/6+.21
        w.tube([(0,.12,0),(.19*math.cos(theta),.045,.19*math.sin(theta)),(.31*math.cos(theta),.012,.31*math.sin(theta))], [.065,.035,.008], 7)
    branches = [
        ((-.045,1.52,.02),(-.25,2.20,.08),(-.51,2.91,.13)),
        ((-.02,1.85,.035),(.25,2.35,.29),(.49,3.17,.40)),
        ((.045,2.13,.045),(.12,2.68,-.30),(.29,3.30,-.53)),
        ((.055,2.36,.07),(-.24,2.78,-.28),(-.40,3.35,-.45)),
        ((.07,2.57,.08),(.38,2.91,-.05),(.59,3.37,-.01)),
        ((.05,2.81,.08),(-.26,3.10,.35),(-.38,3.53,.48)),
        ((.04,2.94,.08),(.01,3.28,.17),(.13,3.73,.20)),
    ]
    for i, path in enumerate(branches):
        w.tube(path, [.055 if i<3 else .041,.030,.011], 7)
        end = Vector(path[-1]); mid = Vector(path[1])
        twig_end = end + Vector((-.12 if i%2 else .12, .12, .12 if i%2 else -.10))
        w.tube([tuple(mid), tuple(end), tuple(twig_end)], [.021,.011,.004], 5)
    # Preserve the authored, asymmetric three-band envelope of the first draft,
    # but replace its rejected closed cabbage-like masses with attached leaves.
    clusters = [
        ((-.48,3.02,.12),(.36,.24,.38)),
        ((.43,3.18,.40),(.35,.25,.34)),
        ((.26,3.35,-.49),(.37,.27,.35)),
        ((-.39,3.40,-.40),(.34,.28,.39)),
        ((.56,3.43,-.04),(.29,.27,.39)),
        ((-.36,3.57,.45),(.38,.26,.32)),
        ((.10,3.70,.21),(.40,.28,.37)),
        ((-.03,3.49,-.12),(.37,.30,.36)),
        ((.35,3.61,-.25),(.35,.24,.34)),
        ((-.62,3.28,-.12),(.22,.22,.32)),
        ((-.10,3.22,.51),(.35,.24,.33)),
    ]
    rng = random.Random(SEED)
    leaf_count = 0
    leaf_lengths, leaf_widths = [], []
    for center0, size in clusters:
        center = Vector(center0)
        branch_anchor = min((Vector(path[-1]) for path in branches),key=lambda p:(p-center).length)
        w.tube([tuple(branch_anchor),tuple(center)], [.013,.007], 5)
        for twig in range(11):
            # Branchlets grow in 3D with irregular inclination. They are not
            # camera-facing cards, radial planar fans, or an opaque inner ball.
            direction = Vector((rng.uniform(-1,1),rng.uniform(-.85,1),rng.uniform(-1,1))).normalized()
            spread = Vector((direction.x*size[0],direction.y*size[1],direction.z*size[2]))
            midpoint = center + spread*.31
            tip = center + spread*rng.uniform(.60,.84)
            w.tube([tuple(center),tuple(midpoint),tuple(tip)],[.005,.003,.0012],4)
            stem_axis = (tip-midpoint).normalized()
            for number in range(10):
                base = midpoint.lerp(tip,(number+rng.uniform(.1,.9))/10)
                for attempt in range(50):
                    axis = (stem_axis*.28+Vector((rng.uniform(-1,1),rng.uniform(-.8,1),rng.uniform(-1,1)))).normalized()
                    across = axis.cross(Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-1,1)))).normalized()
                    if across.length < .5:
                        continue
                    normal = axis.cross(across).normalized()
                    length, width = rng.uniform(.08,.16),rng.uniform(.04,.08)
                    # Base and tip form a raised midrib; margins fold down.
                    profile = [(0,0,0),(.25,-.45,-.065),(.68,-.5,-.085),
                               (1,0,.025),(.68,.5,-.085),(.25,.45,-.065)]
                    points = [tuple(base+axis*(u*length)+across*(v*width)+normal*(h*length)) for u,v,h in profile]
                    # Validate the inherited final metre envelope before adding
                    # a whole leaf; never flatten or crop its natural outline.
                    if all(abs(p[0]*.96)<=.89 and abs(p[2]*.86+.15)<=.94 and 2.7<=p[1]<=4.08 for p in points):
                        leaf.folded_leaf(points)
                        leaf_count += 1
                        leaf_lengths.append(length)
                        leaf_widths.append(width)
                        break
                else:
                    raise RuntimeError("Cannot fit one complete leaf in inherited courtyard envelope")
    # Preserve the inherited courtyard tree centre at local z=.15.  A small
    # anisotropic fit keeps all solid foliage inside its unchanged lot.
    for group in geo.values():
        group.vertices = [(p[0]*.96, max(0,p[1]), p[2]*.86+.15) for p in group.vertices]
    return geo, {"crown_layers":3,"branchlet_groups":len(clusters),"closed_canopy_volumes":0,
                 "individual_folded_leaves":leaf_count,"leaf_triangles":leaf_count*4,
                 "leaf_length_m":[min(leaf_lengths),max(leaf_lengths)],
                 "leaf_width_m":[min(leaf_widths),max(leaf_widths)],
                 "leaf_shape":"six-vertex shallow fold; four triangles, attached to 3D branchlets; runtime double-sided",
                 "crown_minimum_expected_y":2.7,"root_center":[0,0,.15],"billboards":0,
                 "rejected_previous_canopy":"Eleven closed wrinkled masses read as cabbage in actual follow-camera view; archived in source/rejected-closed-crown-first-candidate",
                 "existing_tree_replacement":"one complete tree, trunk and crown together"}


def make_material(role):
    material = bpy.data.materials.new("Chengdu_"+role)
    material.use_nodes = True
    material.diffuse_color = COLORS[role]
    material["semantic_role"] = role
    material["runtime_atlas"] = "painted-atlas.png"
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = COLORS[role]
    principled.inputs["Roughness"].default_value = 1.0
    principled.inputs["Metallic"].default_value = 0.0
    principled.inputs["Specular IOR Level"].default_value = .0
    return material


def mesh_objects(geometry):
    objects = []
    for role, geo in geometry.items():
        if not geo.faces:
            continue
        mesh = bpy.data.meshes.new(role+"_mesh")
        mesh.from_pydata([bvec(p) for p in geo.vertices], [], geo.faces)
        mesh.update()
        uv = mesh.uv_layers.new(name="AtlasUV")
        for polygon, corners, smooth in zip(mesh.polygons, geo.uvs, geo.smooth):
            polygon.use_smooth = smooth
            for li, coord in zip(polygon.loop_indices, corners):
                uv.data[li].uv = coord
        # Correct all mesh normals from closed topology before a real AO bake.
        obj = bpy.data.objects.new("Kit_"+role, mesh)
        bpy.context.collection.objects.link(obj)
        mesh.materials.append(make_material(role))
        colors = mesh.color_attributes.new(name="Color", type='FLOAT_COLOR', domain='CORNER')
        mesh.color_attributes.active_color = colors
        for sample in colors.data:
            sample.color = (1,1,1,1)
        objects.append(obj)
    return objects


def bake_ao(objects):
    """Cycles AO node -> EMIT -> corner colors: real offline ray visibility."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 16
    scene.render.bake.target = 'VERTEX_COLORS'
    scene.render.bake.use_clear = True
    scene.render.bake.use_selected_to_active = False
    for obj in objects:
        material = obj.data.materials[0]
        nodes = material.node_tree.nodes
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        emission = nodes.new("ShaderNodeEmission")
        ambient = nodes.new("ShaderNodeAmbientOcclusion")
        ambient.samples = 16
        ambient.inputs["Distance"].default_value = .38
        material.node_tree.links.new(ambient.outputs["AO"], emission.inputs["Color"])
        material.node_tree.links.new(emission.outputs[0], output.inputs["Surface"])
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.bake(type='EMIT', target='VERTEX_COLORS')
    audit = {}
    for obj in objects:
        attribute = obj.data.color_attributes["Color"]
        raw = [float(v.color[0]) for v in attribute.data]
        for sample in attribute.data:
            value = .66 + .34 * max(0, min(1, sample.color[0]))
            sample.color = (value, value, value, 1)
        role = obj.name.removeprefix("Kit_")
        audit[role] = {"raw_min":min(raw),"raw_max":max(raw),"raw_mean":sum(raw)/len(raw),
                       "color0_min":min(v.color[0] for v in attribute.data),
                       "color0_max":max(v.color[0] for v in attribute.data),
                       "corner_samples":len(raw)}
        # Rebuild the source preview material.  The GLB exports the white/grey
        # vertex AO separately; Godot combines it with the authored color atlas.
        old = obj.data.materials[0]
        obj.data.materials[0] = make_material(role)
        bpy.data.materials.remove(old)
        obj.data.materials[0].name = "Chengdu_"+role
    return audit


def audit_objects(objects, asset, details, ao):
    vertices = [gv(o.matrix_world @ v.co) for o in objects for v in o.data.vertices]
    bounds = [[min(v[i] for v in vertices) for i in range(3)],
              [max(v[i] for v in vertices) for i in range(3)]]
    triangles = sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects)
    assert triangles < 12000, (asset, triangles)
    max_x, max_z = (.98,1.04) if asset == "tea_shop" else (.90,.95)
    assert min(v[0] for v in vertices) >= -max_x-1e-5
    assert max(v[0] for v in vertices) <= max_x+1e-5
    assert min(v[2] for v in vertices) >= -max_z-1e-5
    assert max(v[2] for v in vertices) <= max_z+1e-5
    assert bounds[0][1] >= -1e-5
    if asset == "courtyard_tree":
        leaf_verts = [gv(v.co) for o in objects if o.name == "Kit_leaf" for v in o.data.vertices]
        assert min(v[1] for v in leaf_verts) >= 2.7
        details["actual_crown_minimum_y"] = min(v[1] for v in leaf_verts)
    return {"asset":asset,"godot_bounds_m":bounds,"triangles":triangles,"mesh_objects":len(objects),
            "materials":len(objects),"semantic_roles":[o.name.removeprefix("Kit_") for o in objects],
            "details":details,"ao":ao,"external_images":[],"lights_cameras_collision_in_glb":False}


def glb_audit(path):
    data = path.read_bytes()
    magic, version, size = struct.unpack_from('<4sII', data)
    assert magic == b'glTF' and version == 2 and size == len(data)
    json_size, chunk_type = struct.unpack_from('<II', data, 12)
    assert chunk_type == 0x4e4f534a
    doc = json.loads(data[20:20+json_size])
    attrs = [p['attributes'] for m in doc['meshes'] for p in m['primitives']]
    assert all('COLOR_0' in a and 'TEXCOORD_0' in a for a in attrs)
    assert not doc.get('images') and not doc.get('cameras')
    return {"bytes":len(data),"sha256":sha(path),"mesh_primitives":len(attrs),
            "all_primitives_have_uv_and_color0":True,"image_count":len(doc.get('images',[])),
            "export_y_up":True}


def produce(asset, build):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for collection in [bpy.data.meshes,bpy.data.materials]:
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)
    geometry, details = build()
    objects = mesh_objects(geometry)
    ao = bake_ao(objects)
    audit = audit_objects(objects, asset, details, ao)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    scene["asset_convention"] = "Godot Y-up in metres; Blender stored x,-z,y; front +Z after glTF export"
    scene["atlas_convention"] = "PNG top-left: top plaster/wood/roof, bottom stone/leaf/ceramic. 16px gutter."
    scene["ao_recipe"] = "Cycles CPU AO shader node distance .38m samples16 -> EMIT VERTEX_COLORS; Color=.66+.34*AO"
    # Only authored meshes are selected; no source helper can leak into GLB.
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    glb = OUTPUT / (asset+".glb")
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB', use_selection=True,
                             export_yup=True, export_apply=True,
                             export_texcoords=True, export_normals=True,
                             export_vertex_color='NAME', export_vertex_color_name='Color',
                             export_all_vertex_colors=False, export_materials='EXPORT',
                             export_cameras=False, export_lights=False, export_extras=True,
                             export_animations=False)
    audit["glb"] = glb_audit(glb)
    blend = SOURCE / (asset+".blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    audit["source_blend"] = {"path":str(blend.relative_to(ROOT)),"sha256":sha(blend),"bytes":blend.stat().st_size}
    (SOURCE / (asset+"-audit.json")).write_text(json.dumps(audit, ensure_ascii=False, indent=2)+"\n")
    return audit


def main():
    SOURCE.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    if "--tree-only" in sys.argv:
        previous = json.loads((OUTPUT / "model-source.json").read_text())
        preserved_tea = next(a for a in previous["assets"] if a["asset"]=="tea_shop")
        assert sha(OUTPUT / "tea_shop.glb") == preserved_tea["glb"]["sha256"]
        audits = [preserved_tea,produce("courtyard_tree",courtyard_tree)]
    else:
        audits = [produce("tea_shop",tea_shop), produce("courtyard_tree",courtyard_tree)]
    manifest = {
        "schema_version":1,"purpose":"One editable, original Blender tea-shop and volumetric courtyard-tree sample for the existing Chengdu continuous scene",
        "author":"OpenAI Codex, original procedural modelling authored for shu; no third-party model or texture imported",
        "license":"Project-original source assets; no external asset licence dependency",
        "date":"2026-11-10","tool":"Blender","tool_version":bpy.app.version_string,
        "script":str(Path(__file__).resolve().relative_to(ROOT)),"script_sha256":sha(Path(__file__)),
        "reproduce":"blender --background --factory-startup --python tools/art/build_chengdu_blender_kit.py",
        "coordinates":{"units":"metres","runtime":"Godot Y-up / front +Z","blender":"stored (x,-z,y); standard glTF Y-up export restores (x,y,z)"},
        "atlas":{"runtime_image":"painted-atlas.png","size":[1024,1024],"png_origin":"top-left",
                 "png_top_row":["plaster","wood","roof"],"png_bottom_row":["stone","leaf","ceramic"],
                 "column_boundaries_px":[0,341,682,1024],"padding_px":16,
                 "uv_contract":"Blender UV V is flipped from PNG top-left; glTF exporter flips back. Every UV lies within inner texel centres of its semantic tile.",
                 "vertex_color":"COLOR_0 is a grayscale ambient-occlusion multiplier, never the semantic base color. Runtime shader: painted atlas RGB * COLOR.rgb; roughness1, metallic0."},
        "bake":{"engine":"Cycles","device":"CPU","type":"EMIT from ShaderNodeAmbientOcclusion AO output",
                "samples":16,"ray_distance_m":.38,"target":"VERTEX_COLORS Color, CORNER FLOAT_COLOR",
                "postprocess":"Color.rgb = .66 + .34 * clamp(rawAO,0,1)","baked":True},
        "environment_limit":"System Blender OCIO profile version2.5 exceeds linked OCIO2.4.2; Blender logs display-transform fallback. Geometry and scalar AO baking do not use the display transform. Godot scene is final colour review.",
        "assets":audits,
        "limits":["Local exterior sample only; no change to navigation, actors, saved state or other city lots",
                  "AO is static offline vertex visibility, not full light baking or dynamic GI",
                  "Blender source materials provide preview colors; runtime uses the separately authored Krita atlas"]}
    (OUTPUT / "model-source.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
    (SOURCE / "README.md").write_text("# 成都 Blender 茶铺与庭树源工程\n\n运行仓库 `tools/art/build_chengdu_blender_kit.py` 重建两份 .blend / GLB。单位米；脚本用 Godot Y-up，存入 Blender 时转成 (x,-z,y)，标准 glTF Y-up 导出还原。PNG 图集左上原点，上排灰泥／木／瓦，下排石／叶／瓷；每格16像素留边。GLB 不携带外部图像，运行接 Krita 同合同图集。\n\n两资产均真实通过 Cycles CPU AO 节点离线烘焙到 CORNER Color，灰度乘数 .66+.34*AO；不可把材质底色重复乘入。独立 audit 保存各组原AO与导出范围、几何bounds、三角数和GLB hash。系统 Blender 的 OCIO版本不匹配触发显示fallback，未修改系统；最终色彩以 Godot 实景确认。\n",encoding='utf-8')
    print("CHENGDU_BLENDER_KIT_DONE "+json.dumps({a['asset']:{'triangles':a['triangles'],'bounds':a['godot_bounds_m'],'glb':a['glb']} for a in audits}))


if __name__ == "__main__":
    main()
