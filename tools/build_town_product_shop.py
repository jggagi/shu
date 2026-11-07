#!/usr/bin/env python3
"""Original Song-inspired tea-shop structure; run with Blender 5.2.2 LTS.

  /usr/bin/blender --background --factory-startup --python tools/build_town_product_shop.py

The four merged meshes replace structure only. The game retains its front
panels, open doors, serving furniture, interior illustration and sign. No
external pictures, generated AI images, downloaded models or Python packages.
RGB PNGs are authored directly as sRGB bytes: this does not depend on the host
Blender OpenColorIO installation, baking, image conversion or render settings.
"""

from pathlib import Path
import hashlib
import json
import math
import struct
import zlib

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/art/town_product_shop"
BLEND = ROOT / "art/source/town-product-shop-20261029.blend"
WIDTH, DEPTH, HEIGHT = 6.75, 1.1875, 2.42
FRONT = DEPTH * 0.5 - 0.075
MATERIALS = {
    "Roof": ("roof-wash.png", 512, "#758680"),
    "Wall": ("plaster-wash.png", 512, "#d7d2c0"),
    "Wood": ("timber-wash.png", 256, "#9c805c"),
    "Foundation": ("stone-wash.png", 256, "#aaa995"),
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def rgb(hex_color):
    return tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))


def write_texture(kind, filename, size, base):
    """Broad, restrained original washes; no tile-line or crack overlays."""
    base = rgb(base)
    scanlines = []
    for y in range(size):
        row = bytearray([0])
        v = y / (size - 1)
        for x in range(size):
            u = x / (size - 1)
            broad = (math.sin(u * 7.1 + v * 2.4) * 0.43 +
                     math.sin(u * 13.2 - v * 8.1 + 1.7) * 0.25 +
                     math.cos(u * 3.1 + v * 11.9) * 0.32)
            soft = math.sin(u * 29.0 + math.sin(v * 9.0)) * math.cos(v * 23.0) * 0.004
            value, tint = 1.0, (0.0, 0.0, 0.0)
            if kind == "Roof":
                # Four broad tonal groups, not a dense tile grid.
                group = math.cos(u * math.tau * 4.0 + math.sin(v * 4.0) * 0.10)
                value = 1.0 + broad * 0.035 + group * 0.012 + soft
                tint = (-1.4 * broad, 0.2, 1.6 * broad)
            elif kind == "Wall":
                lower = max(0.0, (v - 0.65) / 0.35)
                value = 1.0 + broad * 0.026 + soft * 0.35 - lower * 0.038
                tint = (1.5 * broad, 0.7 * broad, -0.7 * broad)
            elif kind == "Wood":
                grain = math.sin(v * 93.0 + math.sin(u * 9.0) * 1.3) * 0.010
                value = 1.0 + broad * 0.045 + grain + soft * 0.35
                # The lower quarter of the atlas is the real eave dark mouth.
                if v > 0.76:
                    value *= 0.62
                tint = (1.5, 0.0, -1.0)
            else:
                value = 1.0 + broad * 0.027 + soft * 0.65
                tint = (-0.5 * broad, 0.3, 0.5 * broad)
            row.extend(max(0, min(255, round(base[i] * value + tint[i]))) for i in range(3))
        scanlines.append(row)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    data += chunk(b"sRGB", b"\x00") + chunk(b"IDAT", zlib.compress(b"".join(scanlines), 9)) + chunk(b"IEND", b"")
    (DEST / filename).write_bytes(data)


def godot_to_blender(point):
    # glTF +Y-up export maps Blender (x,y,z) to (x,z,-y).
    x, y, z = point
    return (x, -z, y)


class MergedMesh:
    def __init__(self, name):
        self.name = name
        self.vertices, self.faces, self.uvs, self.smooth = [], [], [], []

    def face(self, points, uv=None, smooth=False, dark=False):
        points = [tuple(p) for p in points]
        first = len(self.vertices)
        self.vertices.extend(points)
        self.faces.append(tuple(range(first, first + len(points))))
        self.smooth.append(smooth)
        if uv is None:
            n = (Vector(points[1]) - Vector(points[0])).cross(Vector(points[2]) - Vector(points[0]))
            axis = max(range(3), key=lambda i: abs(n[i]))
            indices = (0, 2) if axis == 1 else (0, 1) if axis == 2 else (2, 1)
            projected = [(p[indices[0]], p[indices[1]]) for p in points]
            lo = [min(p[i] for p in projected) for i in range(2)]
            span = [max(p[i] for p in projected) - lo[i] for i in range(2)]
            uv = [((p[0] - lo[0]) / max(span[0], 0.01), (p[1] - lo[1]) / max(span[1], 0.01)) for p in projected]
            if self.name == "Wood":
                low, high = (0.03, 0.20) if dark else (0.31, 0.94)
                uv = [(u, low + v * (high - low)) for u, v in uv]
        self.uvs.append(uv)

    def box(self, center, size, bevel=0.0, dark=False):
        """Offline bevelled solid, accumulated into one material mesh."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for vertex in bm.verts:
            vertex.co = Vector([center[i] + vertex.co[i] * size[i] for i in range(3)])
        if bevel:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect='EDGES')
        bm.normal_update()
        for face in bm.faces:
            self.face([v.co[:] for v in face.verts], dark=dark)
        bm.free()

    def beam(self, start, end, thickness, dark=False):
        start, end = Vector(start), Vector(end)
        direction = (end - start).normalized()
        side = direction.cross(Vector((0, 1, 0)))
        if side.length < 0.01:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(direction).normalized()
        s, u = side * thickness * 0.5, up * thickness * 0.5
        rings = [[p - s - u, p + s - u, p + s + u, p - s + u] for p in (start, end)]
        self.face(list(reversed(rings[0])), dark=dark)
        self.face(rings[1], dark=dark)
        for i in range(4):
            j = (i + 1) % 4
            self.face([rings[0][i], rings[1][i], rings[1][j], rings[0][j]], dark=dark)

    def finish(self, material):
        mesh = bpy.data.meshes.new(self.name + "Mesh")
        mesh.from_pydata([godot_to_blender(p) for p in self.vertices], [], self.faces)
        mesh.update()
        uv_layer = mesh.uv_layers.new(name="UVMap")
        for poly, uv, smooth in zip(mesh.polygons, self.uvs, self.smooth):
            poly.use_smooth = smooth
            for loop, coord in zip(poly.loop_indices, uv):
                uv_layer.data[loop].uv = coord
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.0000001)
        bm.to_mesh(mesh)
        bm.free()
        mesh.validate()
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        mesh.materials.append(material)
        obj["godot_role"] = self.name
        obj["original_author"] = "Codex for Shu, 2026-10-29"
        return obj


def roof_point(x, z, half_width, half_depth, base):
    t = abs(z) / half_depth
    corner = (abs(x) / half_width) ** 6
    y = base + 0.50 * (1.0 - t ** 0.94) + 0.105 * t ** 5 + 0.075 * corner * t ** 3
    # Wide, barely raised tile masses. There are no separate tile-strip nodes.
    roll = (0.5 + 0.5 * math.cos((x / half_width + 1.0) * math.pi * 4.0)) * 0.005
    return Vector((x, y + roll * math.sin(t * math.pi), z))


def build_tile_courses(mesh, center, half_width, half_depth, base, hole):
    """Shallow circular barrel sections, four stepped courses per slope.

    These are faces accumulated in Roof, never independently instanced tiles.
    The same quiet texture continues across them. Their normals, rounded ends
    and 18mm course steps carry the tile reading at the normal game camera.
    """
    cx, cz = center
    columns = 26 if half_width > 2.0 else 11
    pitch = half_width * 2.0 / columns
    half_tile = pitch * 0.488
    rise = 0.028 if half_width > 2.0 else 0.025
    radius = (half_tile * half_tile + rise * rise) / (2.0 * rise)

    def point(x, z, middle, row, side):
        p = roof_point(x, z, half_width, half_depth, base)
        dx = max(-half_tile, min(half_tile, x - middle))
        circular = math.sqrt(max(0.0, radius * radius - dx * dx)) - (radius - rise)
        progress = abs(z) / half_depth * 4.0 - row
        p.y += 0.006 + circular + max(0.0, min(1.0, progress)) * 0.018
        return p + Vector((cx, 0, cz))

    for column in range(columns):
        middle = -half_width + pitch * (column + 0.5)
        for side in (-1, 1):
            for row in range(4):
                xs = [middle - half_tile + half_tile * i / 3.0 for i in range(7)]
                za, zb = side * half_depth * row / 4.0, side * half_depth * (row + 1) / 4.0
                zs = [min(za, zb), (za + zb) * 0.5, max(za, zb)]
                if hole:
                    xs += [x - cx for x in hole[:2] if xs[0] < x - cx < xs[-1]]
                    zs += [z - cz for z in hole[2:] if zs[0] < z - cz < zs[-1]]
                xs, zs = sorted(set(xs)), sorted(set(zs))
                cells = {}
                for ix in range(len(xs) - 1):
                    for iz in range(len(zs) - 1):
                        mx, mz = (xs[ix] + xs[ix + 1]) * 0.5 + cx, (zs[iz] + zs[iz + 1]) * 0.5 + cz
                        if hole and hole[0] < mx < hole[1] and hole[2] < mz < hole[3]:
                            continue
                        points = [point(x, z, middle, row, side)
                                  for x, z in [(xs[ix], zs[iz]), (xs[ix], zs[iz + 1]),
                                               (xs[ix + 1], zs[iz + 1]), (xs[ix + 1], zs[iz])]]
                        uv = [((p.x - cx) / (2 * half_width) + 0.5,
                               (p.z - cz) / (2 * half_depth) + 0.5) for p in points]
                        mesh.face(points, uv, smooth=True)
                        cells[(ix, iz)] = points
                # Closed skirts meet the solid continuous roof. At the eave
                # these expose the actual round tile end; at internal course
                # boundaries the next layer hides the lower skirt naturally.
                for (ix, iz), points in cells.items():
                    for edge, neighbor in enumerate([(ix - 1, iz), (ix, iz + 1), (ix + 1, iz), (ix, iz - 1)]):
                        if neighbor not in cells:
                            a, b = points[edge], points[(edge + 1) % 4]
                            lower_a = roof_point(a.x - cx, a.z - cz, half_width, half_depth, base) + Vector((cx, 0, cz))
                            lower_b = roof_point(b.x - cx, b.z - cz, half_width, half_depth, base) + Vector((cx, 0, cz))
                            mesh.face([a, lower_a, lower_b, b])


def build_roof(mesh, wood, center, half_width, half_depth, base, hole=None):
    cx, cz = center
    xs = [(-1.0 + i / 24.0) * half_width for i in range(49)]
    zs = [(-1.0 + i / 10.0) * half_depth for i in range(21)]
    if hole:
        xs += [hole[0] - cx, hole[1] - cx]
        zs += [hole[2] - cz, hole[3] - cz]
    xs, zs = sorted(set(xs)), sorted(set(zs))
    thickness = 0.075
    cells = {}
    for ix in range(len(xs) - 1):
        for iz in range(len(zs) - 1):
            mx, mz = (xs[ix] + xs[ix + 1]) * 0.5 + cx, (zs[iz] + zs[iz + 1]) * 0.5 + cz
            if hole and hole[0] < mx < hole[1] and hole[2] < mz < hole[3]:
                continue
            points = [roof_point(x, z, half_width, half_depth, base) + Vector((cx, 0, cz))
                      for x, z in [(xs[ix], zs[iz]), (xs[ix], zs[iz + 1]),
                                   (xs[ix + 1], zs[iz + 1]), (xs[ix + 1], zs[iz])]]
            uv = [((p.x - cx) / (2 * half_width) + 0.5, (p.z - cz) / (2 * half_depth) + 0.5) for p in points]
            mesh.face(points, uv, smooth=True)
            mesh.face([p - Vector((0, thickness, 0)) for p in reversed(points)], list(reversed(uv)))
            cells[(ix, iz)] = points
    for (ix, iz), points in cells.items():
        for edge, neighbor in enumerate([(ix - 1, iz), (ix, iz + 1), (ix + 1, iz), (ix, iz - 1)]):
            if neighbor not in cells:
                a, b = points[edge], points[(edge + 1) % 4]
                mesh.face([a, a - Vector((0, thickness, 0)), b - Vector((0, thickness, 0)), b])
    # A single continuous rounded ridge, not a row of separate cap boxes.
    radius = 0.047
    for i in range(32):
        x0 = -half_width + 0.09 + (2 * half_width - 0.18) * i / 32
        x1 = -half_width + 0.09 + (2 * half_width - 0.18) * (i + 1) / 32
        for j in range(8):
            a, b = math.pi * j / 8, math.pi * (j + 1) / 8
            mesh.face([(cx + x0, base + 0.49 + math.sin(a) * radius, cz + math.cos(a) * radius),
                       (cx + x1, base + 0.49 + math.sin(a) * radius, cz + math.cos(a) * radius),
                       (cx + x1, base + 0.49 + math.sin(b) * radius, cz + math.cos(b) * radius),
                       (cx + x0, base + 0.49 + math.sin(b) * radius, cz + math.cos(b) * radius)], smooth=True)
        # The ridge has real sides and a bottom sunk into the roof body; its
        # rounded silhouette must not hover above the roof on two open edges.
        for side in (-1, 1):
            points = [(cx + x0, base + 0.49, cz + side * radius),
                      (cx + x0, base + 0.44, cz + side * radius),
                      (cx + x1, base + 0.44, cz + side * radius),
                      (cx + x1, base + 0.49, cz + side * radius)]
            if side < 0:
                points.reverse()
            mesh.face(points)
        mesh.face([(cx + x0, base + 0.44, cz - radius),
                   (cx + x0, base + 0.44, cz + radius),
                   (cx + x1, base + 0.44, cz + radius),
                   (cx + x1, base + 0.44, cz - radius)])
    for side in (-1, 1):
        x = cx + side * (half_width - 0.09)
        points = [(x, base + 0.44, cz - radius), (x, base + 0.44, cz + radius)]
        points.extend((x, base + 0.49 + math.sin(math.pi * j / 8) * radius,
                       cz + math.cos(math.pi * j / 8) * radius) for j in range(9))
        if side < 0:
            points.reverse()
        mesh.face(points)
    # Two continuous deep wood fascias establish the roof's real dark mouth.
    for side in (-1, 1):
        z = side * (half_depth - 0.045)
        for i in range(24):
            x0, x1 = -half_width + 2 * half_width * i / 24, -half_width + 2 * half_width * (i + 1) / 24
            a = roof_point(x0, z, half_width, half_depth, base) + Vector((cx, 0, cz))
            b = roof_point(x1, z, half_width, half_depth, base) + Vector((cx, 0, cz))
            low_a, low_b = a - Vector((0, 0.145, 0)), b - Vector((0, 0.145, 0))
            points = [a, low_a, low_b, b]
            if side < 0:
                points.reverse()
            wood.face(points, dark=True)
            inner_a, inner_b = low_a - Vector((0, 0, side * 0.085)), low_b - Vector((0, 0, side * 0.085))
            wood.face([low_a, inner_a, inner_b, low_b], dark=True)
    build_tile_courses(mesh, center, half_width, half_depth, base, hole)


def make_material(name, image):
    material = bpy.data.materials.new("ShuProduct" + name)
    material.use_nodes = True
    material.diffuse_color = (*[v / 255 for v in rgb(MATERIALS[name][2])], 1.0)
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 0.93 if name != "Wood" else 0.86
    # Keep the core glTF metallic/roughness path, without a specular extension.
    shader.inputs["Specular IOR Level"].default_value = 0.50
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = 'Linear'
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    material.use_backface_culling = True
    return material


def build_geometry():
    roof, wall, wood, foundation = [MergedMesh(name) for name in MATERIALS]
    wall.box((0, HEIGHT * 0.5, -DEPTH * 0.5 + 0.055), (WIDTH - 0.08, HEIGHT, 0.10), 0.014)
    for side in (-1, 1):
        wall.box((side * (WIDTH * 0.5 - 0.07), HEIGHT * 0.5, 0), (0.11, HEIGHT, DEPTH - 0.10), 0.014)
    # Raised left bay is an actual shell with an inset upper opening. The main
    # roof is cut underneath it, so it cannot slice through that opening.
    raised_x, raised_depth = -1.90, DEPTH - 0.19
    raised_front, raised_back = -0.04 + raised_depth * 0.5, -0.04 - raised_depth * 0.5
    wall.box((raised_x, 2.80, raised_back + 0.04), (2.45, 0.76, 0.08), 0.012)
    for side in (-1, 1):
        wall.box((raised_x + side * 1.185, 2.80, -0.04), (0.08, 0.76, raised_depth - 0.04), 0.012)
    for center, size in [((raised_x, 2.50, raised_front - 0.035), (2.29, 0.16, 0.07)),
                         ((raised_x, 3.10, raised_front - 0.035), (2.29, 0.16, 0.07))]:
        wall.box(center, size, 0.010)
    wood.box((raised_x, 2.80, raised_front - 0.105), (2.14, 0.45, 0.028), 0.006, dark=True)
    for side in (-1, 1):
        wood.box((raised_x + side * 1.13, 2.80, raised_front - 0.008), (0.09, 0.76, 0.075), 0.008)
    for i in range(7):
        wood.box((raised_x - 0.90 + i * 0.30, 2.80, raised_front - 0.020), (0.040, 0.40, 0.035), 0.005)
    for y in (2.565, 3.035):
        wood.box((raised_x, y, raised_front - 0.015), (2.19, 0.065, 0.065), 0.007)
    build_roof(roof, wood, (0, 0), 3.595, 0.85375, HEIGHT,
               hole=(-3.125, -0.675, raised_back, raised_front))
    build_roof(roof, wood, (-1.90, -0.03), 1.465, 0.76875, HEIGHT + 0.77)
    # Existing front columns stay in the native helper. These five real curved
    # braces start above them and support the new eave, rather than duplicating
    # door/window beams or posts.
    for x in (-3.20, -1.29, -0.33, 2.63, 3.20):
        wood.box((x, HEIGHT - 0.26, FRONT + 0.008), (0.14, 0.23, 0.15), 0.012)
        points = [(x, HEIGHT - 0.33, FRONT + 0.015),
                  (x, HEIGHT - 0.25, FRONT + 0.105),
                  (x, HEIGHT - 0.15, FRONT + 0.205),
                  (x, HEIGHT - 0.12, FRONT + 0.265)]
        for a, b in zip(points, points[1:]):
            wood.beam(a, b, 0.065)
    # Same 6.73 x 1.1675 x .17 stone envelope. Shallow joints have a solid,
    # same-material backing; all stone parts become one exported mesh.
    w, d = WIDTH - 0.02, DEPTH - 0.02
    foundation.box((0, 0.0725, -0.009), (w, 0.145, d - 0.018))
    foundation.box((0, 0.1575, 0), (w, 0.025, d), 0.003)
    weights = [0.92, 1.07, 0.86, 1.13, 0.98, 1.04, 1.08, 0.92]
    unit, left = (w - 0.01 * 7) / 8.0, -w * 0.5
    for weight in weights:
        span = unit * weight
        foundation.box((left + span * 0.5, 0.0725, (d - 0.018) * 0.5), (span, 0.145, 0.018), 0.006)
        left += span + 0.01
    return [roof, wall, wood, foundation]


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    root = bpy.data.objects.new("ProductTeaShop", None)
    bpy.context.collection.objects.link(root)
    objects = []
    for geometry in build_geometry():
        filename, size, base = MATERIALS[geometry.name]
        write_texture(geometry.name, filename, size, base)
        image = bpy.data.images.load(str(DEST / filename), check_existing=False)
        image.colorspace_settings.name = 'sRGB'
        material = make_material(geometry.name, image)
        obj = geometry.finish(material)
        obj.parent = root
        objects.append(obj)
    root["coordinate_contract"] = "Godot Y-up, +Z toward street, origin at original house ground center"
    root["wall_dimensions_m"] = [WIDTH, HEIGHT, DEPTH]
    root["body_height_m"] = HEIGHT
    root["native_front_panels_retained"] = True
    root["no_collision_or_game_state"] = True
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.context.scene.render.fps = 30
    text = bpy.data.texts.new("build_town_product_shop.py")
    text.write(Path(__file__).read_text())
    bpy.ops.file.pack_all()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), check_existing=False)
    output = DEST / "town-product-shop.glb"
    bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB', export_yup=True,
                             export_apply=False, export_extras=True, export_cameras=False,
                             export_lights=False, export_materials='EXPORT', export_texcoords=True,
                             export_normals=True, export_tangents=False, export_image_format='AUTO',
                             export_draco_mesh_compression_enable=False, export_use_gltfpack=False)
    meshes = {}
    for obj in objects:
        obj.data.calc_loop_triangles()
        godot_points = [(p[0], p[2], -p[1]) for p in [tuple(v.co) for v in obj.data.vertices]]
        meshes[obj.name] = {"vertices": len(obj.data.vertices), "triangles": len(obj.data.loop_triangles),
                            "material_slots": len(obj.data.materials), "uv_layers": [u.name for u in obj.data.uv_layers],
                            "aabb_min": [min(p[i] for p in godot_points) for i in range(3)],
                            "aabb_max": [max(p[i] for p in godot_points) for i in range(3)]}
    files = {p.name: {"sha256": sha(p), "bytes": p.stat().st_size} for p in sorted(DEST.iterdir())
             if p.is_file() and p.suffix in ('.png', '.glb')}
    source = {"title": "Shu original product tea-shop structure, direction A", "date": "2026-10-29",
              "author": "Codex, authored for Shu", "license": "Project-original; no external art or models",
              "method": "Original offline Blender geometry and deterministic code-authored sRGB RGB8 material washes; no imagegen, external pictures, downloaded models, add-ons or Python dependencies.",
              "blender_version": bpy.app.version_string, "blender_binary": "/usr/bin/blender",
              "blender_build_hash": bpy.app.build_hash.decode(), "blender_binary_sha256": sha('/usr/bin/blender'),
              "generator": "tools/build_town_product_shop.py", "generator_sha256": sha(__file__),
              "source_blend": str(BLEND.relative_to(ROOT)), "source_blend_sha256": sha(BLEND),
              "style_reference": "docs/concepts/town-product-art-20261029/a-song-celadon.png",
              "style_reference_sha256": sha(ROOT / "docs/concepts/town-product-art-20261029/a-song-celadon.png"),
              "style_reference_use": "Project-original composition/color direction only. No picture pixels are copied, projected or embedded into the model or textures.",
              "outputs": files, "meshes": meshes,
              "coordinates": {"up": "+Y", "front": "+Z", "unit": "meter", "origin": [0, 0, 0],
                              "placement": "Existing house logical bounds center, identity scale/rotation",
                              "wall_body_size": [WIDTH, HEIGHT, DEPTH], "foundation_size": [6.73, 0.17, 1.1675]},
              "recipe": {"roof": "Continuous closed 75mm curved body and micro eave lift; 26 shallow circular barrel columns on main roof,11 at the same physical pitch on raised roof; four stepped courses per slope with18mm relief,25-28mm circular rise and real closed round ends. Four broad low-contrast tonal washes continue across the geometry; no white/black grid or separate tile objects. Continuous rounded ridge and real cut under raised bay.",
                         "wall": "Bevelled rear/end shell and raised-bay shell only. Existing native front panels remain.",
                         "wood": "Merged fascia/dark mouth, upper screen and five short braces. No duplicated front posts or door/window frames.",
                         "materials": "Four opaque RGB base-color textures, sRGB, roughness .86/.93; no alpha, metallic, emission, displacement, normal-map shader or runtime generation.",
                         "color_management": "RGB8 PNG bytes written directly and used as source images; no dependency on Blender OCIO conversion or baking. Verify embedded GLB images against originals.",
                         "seed": "Analytical fixed sine washes; no random generator or time input"},
              "integration": {"replace": ["_build_foundation call", "rear-wall box and two end-wall boxes", "_build_eaves", "_build_upper_sign_bay structure before plaque"],
                              "retain": ["_build_front_panels", "_build_half_open_door", "_build_service_bay and illustration", "wood floor at z=-.02", "plaque/Label3D block", "small age marks", "footprint/contact pad/sun-occluder metadata"],
                              "packed_scene_root": "town-product-shop",
                              "mesh_nodes_relative_to_packed_scene_root": {name: "ProductTeaShop/" + name for name in MATERIALS},
                              "mesh_paths_in_house": {name: "town-product-shop/ProductTeaShop/" + name for name in MATERIALS},
                              "fade_nodes": ["ProductTeaShop/Roof", "ProductTeaShop/Wall"], "state_authority": "Existing stage and unique EngineSession; asset has no script, light, camera or collision"},
              "build_environment_notes": "Installed Blender reports 5.2.2 LTS, build hash unknown. Host OCIO profile2.5/library2.4.2 mismatch falls back; no color-management baking or rendering is used. Export disables Draco and gltfpack; optional MeshOptimizer is not used. Embedded PNG byte checks are required.",
              "status": "Original structural asset candidate. Offline geometry/export checks are recorded separately; actual Godot integration and user visual approval are separate."}
    (DEST / "source.json").write_text(json.dumps(source, ensure_ascii=False, indent=2) + '\n')
    print('SHU_PRODUCT_SHOP', json.dumps({"output": str(output), "meshes": meshes, "outputs": files}))


if __name__ == '__main__':
    main()
