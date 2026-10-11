"""Procedural, rig-bound Jiang Yanqiu character for the local Blender study.

The approved 2D art is used only as an identity/style reference; no image texture
or billboard geometry is sampled. Coordinates are Blender Z-up, front is -Y,
and the CMU left side is +X. All proportions are authored around the supplied
0.70-scaled rest pose without changing the skeleton.
"""
from __future__ import annotations

import math
import random

import bpy
from mathutils import Quaternion, Vector

COLOR_ATTRIBUTE = "JiangWash"

# Linear-looking, restrained watercolor colors. Roughness keeps cloth, skin and
# hair matte; tiny fixed vertex-color changes provide a stable painted surface.
PALETTE = {
    "ivory": (0.82, 0.83, 0.78, 1.0),
    "ivory_light": (0.91, 0.90, 0.83, 1.0),
    "ivory_shadow": (0.66, 0.70, 0.69, 1.0),
    "blue": (0.20, 0.34, 0.45, 1.0),
    "blue_light": (0.43, 0.60, 0.68, 1.0),
    "blue_dark": (0.11, 0.21, 0.30, 1.0),
    "skin": (0.86, 0.56, 0.40, 1.0),
    "skin_light": (0.95, 0.69, 0.51, 1.0),
    "blush": (0.72, 0.31, 0.27, 1.0),
    "eye_white": (0.94, 0.88, 0.77, 1.0),
    "iris": (0.27, 0.13, 0.055, 1.0),
    "pupil": (0.042, 0.028, 0.022, 1.0),
    "glint": (1.0, 0.95, 0.82, 1.0),
    "hair": (0.105, 0.063, 0.041, 1.0),
    "hair_mid": (0.19, 0.112, 0.071, 1.0),
    "hair_light": (0.29, 0.18, 0.112, 1.0),
    "trousers": (0.105, 0.16, 0.205, 1.0),
    "boot": (0.075, 0.105, 0.125, 1.0),
    "gold": (0.49, 0.34, 0.17, 1.0),
}

ROUGHNESS = {
    "skin": 0.82,
    "skin_light": 0.84,
    "eye_white": 0.76,
    "iris": 0.73,
    "pupil": 0.72,
    "glint": 0.7,
    "hair": 0.86,
    "hair_mid": 0.86,
    "hair_light": 0.85,
    "gold": 0.73,
    "default": 0.91,
}


def _v(value) -> Vector:
    return value.copy() if isinstance(value, Vector) else Vector(value)


def _unit(value, fallback=(0.0, 0.0, 1.0)) -> Vector:
    result = _v(value)
    return result.normalized() if result.length > 1.0e-9 else Vector(fallback)


def _blend_weights(left, right, t):
    t = max(0.0, min(1.0, float(t)))
    result = {}
    for name, weight in left.items():
        result[name] = result.get(name, 0.0) + float(weight) * (1.0 - t)
    for name, weight in right.items():
        result[name] = result.get(name, 0.0) + float(weight) * t
    return result


def _normalize_weights(weights):
    combined = {}
    for name, weight in weights.items():
        weight = float(weight)
        if math.isfinite(weight) and weight > 1.0e-8:
            combined[name] = combined.get(name, 0.0) + weight
    strongest = sorted(combined.items(), key=lambda item: (-item[1], item[0]))[:4]
    total = sum(weight for _, weight in strongest)
    if total <= 1.0e-10:
        raise ValueError("Every character vertex needs at least one positive bone weight")
    return {name: weight / total for name, weight in strongest}


def _lerp_radius(a, b, t):
    av = (float(a), float(a)) if isinstance(a, (int, float)) else tuple(map(float, a))
    bv = (float(b), float(b)) if isinstance(b, (int, float)) else tuple(map(float, b))
    return (av[0] + (bv[0] - av[0]) * t, av[1] + (bv[1] - av[1]) * t)


def _make_material(part, key):
    name = "Jiang_{}_{}".format(part, key)
    old = bpy.data.materials.get(name)
    if old is not None:
        bpy.data.materials.remove(old, do_unlink=True)
    material = bpy.data.materials.new(name)
    material.diffuse_color = PALETTE[key]
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Roughness"].default_value = ROUGHNESS.get(key, ROUGHNESS["default"])
    shader.inputs["Metallic"].default_value = 0.0
    color = nodes.new("ShaderNodeVertexColor")
    color.layer_name = COLOR_ATTRIBUTE
    material.node_tree.links.new(color.outputs["Color"], shader.inputs["Base Color"])
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


class _WeightedMesh:
    """Small per-part geometry accumulator with normalized multi-bone weights."""

    def __init__(self, part):
        self.part = part
        self.vertices = []
        self.faces = []
        self.face_materials = []
        self.weights = []
        self.colors = []
        self._rng = random.Random(0x4A49414E + sum(ord(c) for c in part))

    def add(self, vertices, faces, material, weights, face_materials=None):
        if material not in PALETTE:
            raise KeyError("Unknown Jiang palette key: " + str(material))
        first = len(self.vertices)
        verts = [_v(point) for point in vertices]
        if isinstance(weights, dict):
            per_vertex_weights = [weights] * len(verts)
        else:
            per_vertex_weights = list(weights)
        if len(per_vertex_weights) != len(verts):
            raise ValueError("Per-vertex weight count must match vertex count")
        base = PALETTE[material]
        for point, raw_weights in zip(verts, per_vertex_weights):
            normalized = _normalize_weights(raw_weights)
            self.vertices.append(tuple(float(c) for c in point))
            self.weights.append(normalized)
            # One fixed random stream per object: variation is authored once and
            # never changes with the animation frame or render time.
            tone = self._rng.uniform(0.986, 1.014)
            warm = self._rng.uniform(-0.004, 0.004)
            self.colors.append((
                max(0.0, min(1.0, base[0] * tone + warm * 0.35)),
                max(0.0, min(1.0, base[1] * tone)),
                max(0.0, min(1.0, base[2] * tone - warm * 0.30)),
                1.0,
            ))
        for face in faces:
            self.faces.append(tuple(first + int(index) for index in face))
        if face_materials is None:
            self.face_materials.extend([material] * len(faces))
        else:
            if len(face_materials) != len(faces):
                raise ValueError("Per-face material count must match face count")
            self.face_materials.extend(face_materials)

    def ellipsoid(self, center, radii, material, weights, rotation=None, segments=20, rings=12):
        center = _v(center)
        radii = _v(radii)
        rotation = rotation if rotation is not None else Quaternion()
        vertices = [center + rotation @ Vector((0.0, 0.0, radii.z))]
        for row in range(1, rings):
            phi = math.pi * row / rings
            for col in range(segments):
                theta = 2.0 * math.pi * col / segments
                local = Vector((radii.x * math.sin(phi) * math.cos(theta),
                                radii.y * math.sin(phi) * math.sin(theta),
                                radii.z * math.cos(phi)))
                vertices.append(center + rotation @ local)
        bottom = len(vertices)
        vertices.append(center + rotation @ Vector((0.0, 0.0, -radii.z)))
        faces = []
        for col in range(segments):
            faces.append((0, 1 + col, 1 + (col + 1) % segments))
        for row in range(rings - 2):
            upper = 1 + row * segments
            lower = upper + segments
            for col in range(segments):
                nxt = (col + 1) % segments
                faces.append((upper + col, lower + col, lower + nxt, upper + nxt))
        last = 1 + (rings - 2) * segments
        for col in range(segments):
            faces.append((last + col, bottom, last + (col + 1) % segments))
        self.add(vertices, faces, material, weights)

    def tube(self, points, radii, weights, material, segment_materials=None, sides=12, steps_per_segment=5):
        """Build a closed, smooth elliptical tube along a weighted centerline."""
        points = [_v(point) for point in points]
        radii = list(radii)
        weights = [_normalize_weights(item) for item in weights]
        if len(points) < 2 or len(points) != len(radii) or len(points) != len(weights):
            raise ValueError("Tube anchors, radii and weight maps must have equal length >= 2")
        if segment_materials is None:
            segment_materials = [material] * (len(points) - 1)
        if len(segment_materials) != len(points) - 1:
            raise ValueError("Tube segment materials must describe each centerline span")
        centers, ring_radii, ring_weights, row_materials = [], [], [], []
        for span in range(len(points) - 1):
            for step in range(steps_per_segment):
                t = step / steps_per_segment
                centers.append(points[span].lerp(points[span + 1], t))
                ring_radii.append(_lerp_radius(radii[span], radii[span + 1], t))
                ring_weights.append(_blend_weights(weights[span], weights[span + 1], t))
                row_materials.append(segment_materials[span])
        centers.append(points[-1])
        ring_radii.append(_lerp_radius(radii[-1], radii[-1], 0.0))
        ring_weights.append(weights[-1])
        row_materials.append(segment_materials[-1])

        vertices = []
        for index, center in enumerate(centers):
            before = centers[max(0, index - 1)]
            after = centers[min(len(centers) - 1, index + 1)]
            tangent = _unit(after - before)
            hint = Vector((0.0, 0.0, 1.0))
            if abs(tangent.dot(hint)) > 0.92:
                hint = Vector((0.0, 1.0, 0.0))
            side = _unit(tangent.cross(hint), (0.0, 1.0, 0.0))
            depth = _unit(tangent.cross(side), (0.0, 0.0, 1.0))
            radius_side, radius_depth = ring_radii[index]
            for col in range(sides):
                angle = 2.0 * math.pi * col / sides
                vertices.append(center + side * (math.cos(angle) * radius_side)
                                + depth * (math.sin(angle) * radius_depth))
        faces, face_materials = [], []
        for row in range(len(centers) - 1):
            for col in range(sides):
                nxt = (col + 1) % sides
                a = row * sides + col
                b = row * sides + nxt
                faces.append((a, b, b + sides, a + sides))
                face_materials.append(row_materials[row])
        start_center = len(vertices)
        vertices.append(centers[0])
        end_center = len(vertices)
        vertices.append(centers[-1])
        for col in range(sides):
            nxt = (col + 1) % sides
            faces.append((start_center, nxt, col))
            face_materials.append(material)
            last = (len(centers) - 1) * sides
            faces.append((end_center, last + col, last + nxt))
            face_materials.append(segment_materials[-1])
        vertex_weights = []
        for item in ring_weights:
            vertex_weights.extend([item] * sides)
        vertex_weights.extend([ring_weights[0], ring_weights[-1]])
        self.add(vertices, faces, material, vertex_weights, face_materials)

    def shell(self, rings, material, segment_materials=None, sides=32):
        """Continuous capped ring surface; rings carry center, radii and weights."""
        if len(rings) < 2:
            raise ValueError("A ring shell needs at least two rings")
        if segment_materials is None:
            segment_materials = [material] * (len(rings) - 1)
        vertices = []
        for ring in rings:
            center = _v(ring["center"])
            rx, ry = float(ring["rx"]), float(ring["ry"])
            for col in range(sides):
                theta = 2.0 * math.pi * col / sides
                vertices.append(center + Vector((rx * math.cos(theta), ry * math.sin(theta), 0.0)))
        faces, face_materials = [], []
        for row in range(len(rings) - 1):
            for col in range(sides):
                nxt = (col + 1) % sides
                a, b = row * sides + col, row * sides + nxt
                faces.append((a, b, b + sides, a + sides))
                face_materials.append(segment_materials[row])
        faces.append(tuple(reversed(tuple(range(sides)))))
        face_materials.append(segment_materials[0])
        last = (len(rings) - 1) * sides
        faces.append(tuple(last + col for col in range(sides)))
        face_materials.append(segment_materials[-1])
        vertex_weights = []
        for ring in rings:
            vertex_weights.extend([ring["weights"]] * sides)
        self.add(vertices, faces, material, vertex_weights, face_materials)

    def patch(self, rows, columns, point_at, weights_at, material):
        vertices, weights = [], []
        for row in range(rows):
            t = row / max(1, rows - 1)
            for col in range(columns):
                u = col / max(1, columns - 1) * 2.0 - 1.0
                vertices.append(point_at(t, u))
                weights.append(weights_at(t, u))
        faces = []
        for row in range(rows - 1):
            for col in range(columns - 1):
                a = row * columns + col
                faces.append((a, a + 1, a + 1 + columns, a + columns))
        self.add(vertices, faces, material, weights)

    def object(self, name, armature):
        if not self.vertices:
            raise ValueError("Cannot create an empty character mesh: " + name)
        mesh = bpy.data.meshes.new(name + "Mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.validate(verbose=False)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        used_keys = sorted(set(self.face_materials))
        material_slots = {}
        for key in used_keys:
            material_slots[key] = len(mesh.materials)
            mesh.materials.append(_make_material(self.part, key))
        for polygon, key in zip(mesh.polygons, self.face_materials):
            polygon.material_index = material_slots[key]
            polygon.use_smooth = True
        # GLB exports this corner-domain attribute as standard COLOR_0.
        color_attr = mesh.color_attributes.new(name=COLOR_ATTRIBUTE, type="BYTE_COLOR", domain="CORNER")
        for index, loop in enumerate(mesh.loops):
            color_attr.data[index].color = self.colors[loop.vertex_index]
        group_weights = {}
        for index, item in enumerate(self.weights):
            for bone, weight in item.items():
                group_weights.setdefault(bone, []).append((index, weight))
        for bone in sorted(group_weights):
            group = obj.vertex_groups.new(name=bone)
            # Blender VertexGroup.add accepts one scalar for each batch. Bucket
            # nearly equal values so smoothly weighted rings stay efficient;
            # six decimal places keeps accumulated per-vertex error < 2e-6.
            weight_buckets = {}
            for index, weight in group_weights[bone]:
                scalar = round(weight, 6)
                weight_buckets.setdefault(scalar, []).append(index)
            for scalar, indices in weight_buckets.items():
                group.add(indices, float(scalar), "REPLACE")
        modifier = obj.modifiers.new("JiangLinearBlendSkin", "ARMATURE")
        modifier.object = armature
        modifier.use_vertex_groups = True
        modifier.use_bone_envelopes = False
        modifier.use_deform_preserve_volume = False
        obj.parent = armature
        obj.matrix_parent_inverse = armature.matrix_world.inverted()
        obj.location = (0.0, 0.0, 0.0)
        obj.rotation_euler = (0.0, 0.0, 0.0)
        obj.scale = (1.0, 1.0, 1.0)
        return obj


def _require_rest(rest, armature):
    required = {
        "root", "lowerback", "upperback", "thorax", "lowerneck", "upperneck", "head",
        "lclavicle", "lhumerus", "lradius", "lwrist", "lhand",
        "rclavicle", "rhumerus", "rradius", "rwrist", "rhand",
        "lfemur", "ltibia", "lfoot", "ltoes", "rfemur", "rtibia", "rfoot", "rtoes",
    }
    missing = sorted(required - set(rest))
    if missing:
        raise ValueError("CMU rest mapping is missing required bones: " + ", ".join(missing))
    if len(armature.data.bones) != 31:
        raise ValueError("Expected the original CMU 31-bone armature; found {}".format(len(armature.data.bones)))
    for name in required:
        if name not in armature.data.bones:
            raise ValueError("CMU rest bone is absent from armature: " + name)
        for key in ("head", "tail", "rotation"):
            if key not in rest[name] or len(rest[name][key]) != (4 if key == "rotation" else 3):
                raise ValueError("Invalid {} field for rest bone {}".format(key, name))
            if not all(math.isfinite(float(value)) for value in rest[name][key]):
                raise ValueError("Non-finite {} field for rest bone {}".format(key, name))


def _spine_rings(rest):
    root = _v(rest["root"]["head"])
    lower = _v(rest["lowerback"]["tail"])
    upper = _v(rest["upperback"]["tail"])
    thorax = _v(rest["thorax"]["tail"])
    return [
        {"center": root + Vector((0.0, 0.0, 0.018)), "rx": 0.140, "ry": 0.092,
         "weights": {"root": 0.82, "lowerback": 0.18}},
        {"center": root.lerp(lower, 0.64), "rx": 0.132, "ry": 0.090,
         "weights": {"root": 0.24, "lowerback": 0.66, "upperback": 0.10}},
        {"center": lower, "rx": 0.139, "ry": 0.094,
         "weights": {"lowerback": 0.76, "upperback": 0.24}},
        {"center": lower.lerp(upper, 0.52), "rx": 0.150, "ry": 0.100,
         "weights": {"lowerback": 0.12, "upperback": 0.68, "thorax": 0.20}},
        {"center": upper, "rx": 0.160, "ry": 0.102,
         "weights": {"upperback": 0.68, "thorax": 0.32}},
        {"center": upper.lerp(thorax, 0.66), "rx": 0.171, "ry": 0.105,
         "weights": {"upperback": 0.18, "thorax": 0.82}},
        {"center": thorax + Vector((0.0, 0.0, 0.020)), "rx": 0.146, "ry": 0.091,
         "weights": {"upperback": 0.10, "thorax": 0.90}},
    ]


def _frame_at_z(rings, z):
    if z <= rings[0]["center"].z:
        return rings[0]
    for left, right in zip(rings, rings[1:]):
        zl, zr = left["center"].z, right["center"].z
        if z <= zr:
            t = 0.0 if zr - zl < 1.0e-9 else (z - zl) / (zr - zl)
            return {
                "center": _v(left["center"]).lerp(_v(right["center"]), t),
                "rx": left["rx"] + (right["rx"] - left["rx"]) * t,
                "ry": left["ry"] + (right["ry"] - left["ry"]) * t,
                "weights": _blend_weights(left["weights"], right["weights"], t),
            }
    return rings[-1]


def _spine_weights_at(rings, z):
    return _frame_at_z(rings, z)["weights"]


def _front_y(rings, x, z, extra=0.0):
    frame = _frame_at_z(rings, z)
    center = _v(frame["center"])
    nx = max(-0.96, min(0.96, (float(x) - center.x) / frame["rx"]))
    return center.y - frame["ry"] * math.sqrt(max(0.05, 1.0 - nx * nx)) - extra


def _make_torso_and_vest(garment, rest, rings):
    garment.shell(rings, "ivory", sides=36)
    low_z = rings[1]["center"].z + 0.006
    high_z = rings[-1]["center"].z - 0.004

    def vest_point(t, u):
        z = low_z + (high_z - low_z) * t
        frame = _frame_at_z(rings, z)
        widths = 0.088 + 0.020 * math.sin(math.pi * t) - 0.012 * t
        x = frame["center"].x + u * widths
        return Vector((x, _front_y(rings, x, z, 0.004), z))

    def vest_weights(t, _u):
        z = low_z + (high_z - low_z) * t
        return _spine_weights_at(rings, z)

    garment.patch(9, 13, vest_point, vest_weights, "blue")

    # Narrow, volumetric lapel strokes trace a cross collar over the blue vest.
    for sign in (-1.0, 1.0):
        z0, z1 = high_z - 0.002, low_z + 0.020
        p0 = Vector((sign * 0.052, _front_y(rings, sign * 0.052, z0, 0.010), z0))
        p1 = Vector((sign * 0.028, _front_y(rings, sign * 0.028, z0 - 0.055, 0.012), z0 - 0.055))
        p2 = Vector((-sign * 0.060, _front_y(rings, -sign * 0.060, z1 + 0.025, 0.012), z1 + 0.025))
        p3 = Vector((-sign * 0.050, _front_y(rings, -sign * 0.050, z1, 0.010), z1))
        garment.tube([p0, p1, p2, p3], [0.010, 0.010, 0.009, 0.006],
                     [vest_weights(1.0, 0.0), vest_weights(0.78, 0.0),
                      vest_weights(0.22, 0.0), vest_weights(0.0, 0.0)],
                     "ivory_light", sides=8, steps_per_segment=3)

    # Soft, fine front seams remain legible as ink accents without hull outlines.
    for sign in (-1.0, 1.0):
        path = []
        for t in (0.25, 0.48, 0.72, 0.93):
            z = low_z + (high_z - low_z) * t
            frame = _frame_at_z(rings, z)
            x = frame["center"].x + sign * (0.122 - 0.022 * t)
            path.append(Vector((x, _front_y(rings, x, z, 0.002), z)))
        garment.tube(path, [0.0024] * len(path),
                     [_spine_weights_at(rings, point.z) for point in path],
                     "ivory_shadow", sides=6, steps_per_segment=2)


def _arm_sleeve(garment, rest, side):
    clavicle = rest[side + "clavicle"]
    humerus = rest[side + "humerus"]
    radius = rest[side + "radius"]
    wrist = rest[side + "wrist"]
    start = _v(clavicle["head"]).lerp(_v(clavicle["tail"]), 0.30)
    shoulder = _v(clavicle["tail"])
    elbow = _v(humerus["tail"])
    forearm_end = _v(radius["tail"])
    wrist_end = _v(wrist["tail"])
    points = [start, shoulder, elbow, forearm_end, wrist_end]
    weights = [
        {"thorax": 0.16, side + "clavicle": 0.84},
        {side + "clavicle": 0.48, side + "humerus": 0.52},
        {side + "humerus": 0.54, side + "radius": 0.46},
        {side + "radius": 0.64, side + "wrist": 0.36},
        {side + "radius": 0.06, side + "wrist": 0.94},
    ]
    radii = [(0.074, 0.071), (0.082, 0.078), (0.077, 0.072),
             (0.061, 0.058), (0.052, 0.050)]
    garment.tube(points, radii, weights, "ivory", ["ivory", "ivory", "ivory", "blue_light"],
                 sides=18, steps_per_segment=7)
    # A single narrow cuff seam, attached to the wrist deformation.
    cuff_direction = _unit(wrist_end - forearm_end)
    cuff_center = forearm_end.lerp(wrist_end, 0.20)
    tangent = cuff_direction
    hint = Vector((0.0, 0.0, 1.0))
    if abs(tangent.dot(hint)) > 0.92:
        hint = Vector((0.0, 1.0, 0.0))
    axis_a = _unit(tangent.cross(hint))
    axis_b = _unit(tangent.cross(axis_a))
    loop = [cuff_center + axis_a * (0.054 * math.cos(2 * math.pi * i / 16))
            + axis_b * (0.052 * math.sin(2 * math.pi * i / 16)) for i in range(17)]
    loop_weights = [{side + "radius": 0.20, side + "wrist": 0.80}] * len(loop)
    garment.tube(loop, [0.0022] * len(loop), loop_weights, "gold", sides=6, steps_per_segment=1)


def _robe_panel(garment, rest, side):
    femur_name = side + "femur"
    hip = _v(rest[femur_name]["head"])
    knee = _v(rest[femur_name]["tail"])
    sign = 1.0 if side == "l" else -1.0

    def panel_point(t, u):
        along = min(0.78, 0.02 + 0.76 * t)
        center = hip.lerp(knee, along)
        center += Vector((0.0, -0.076 + 0.018 * t, 0.0))
        width = 0.085 - 0.018 * t
        # The slightly curved cross-section gives the panel a real volume and
        # keeps its ink seam visible in the back and side views.
        return center + Vector((u * width, -0.012 * (1.0 - u * u), 0.0))

    def panel_weights(t, _u):
        blend = min(1.0, 0.25 + t * 2.0)
        return _blend_weights({"root": 0.62, femur_name: 0.38}, {femur_name: 1.0}, blend)

    garment.patch(10, 7, panel_point, panel_weights, "ivory_light")
    # Blue underside/hem accent follows the same thigh instead of a rigid skirt.
    hem_points = []
    for u in (-1.0, -0.5, 0.0, 0.5, 1.0):
        hem_points.append(panel_point(1.0, u) + Vector((0.0, -0.002, 0.0)))
    hem_w = [panel_weights(1.0, 0.0)] * len(hem_points)
    garment.tube(hem_points, [0.0030] * len(hem_points), hem_w, "blue_light",
                 sides=6, steps_per_segment=2)
    # Fine outer edge stitches, each a single tapered line.
    for u in (-1.0, 1.0):
        seam = [panel_point(t, u) + Vector((0.0, -0.0025, 0.0)) for t in (0.0, 0.35, 0.72, 1.0)]
        garment.tube(seam, [0.0020, 0.0018, 0.0015, 0.0010],
                     [panel_weights(t, u) for t in (0.0, 0.35, 0.72, 1.0)],
                     "ivory_shadow", sides=5, steps_per_segment=2)


def _make_garments(garment, rest):
    rings = _spine_rings(rest)
    _make_torso_and_vest(garment, rest, rings)

    # The waist band follows the root and lower back, while staying narrow.
    root = _v(rest["root"]["head"])
    garment.shell([
        {"center": root + Vector((0.0, 0.0, 0.025)), "rx": 0.142, "ry": 0.094,
         "weights": {"root": 0.75, "lowerback": 0.25}},
        {"center": root + Vector((0.0, 0.0, 0.038)), "rx": 0.146, "ry": 0.096,
         "weights": {"root": 0.72, "lowerback": 0.28}},
        {"center": root + Vector((0.0, 0.0, 0.060)), "rx": 0.140, "ry": 0.092,
         "weights": {"root": 0.42, "lowerback": 0.58}},
    ], "blue_dark", sides=32)
    knot = root + Vector((0.0, -0.098, 0.044))
    garment.ellipsoid(knot, (0.028, 0.014, 0.025), "gold", {"root": 0.68, "lowerback": 0.32},
                      segments=14, rings=8)

    for side in ("l", "r"):
        _arm_sleeve(garment, rest, side)
        _robe_panel(garment, rest, side)


def _make_body(body, rest):
    for side in ("l", "r"):
        femur = rest[side + "femur"]
        tibia = rest[side + "tibia"]
        hip, knee, ankle = _v(femur["head"]), _v(femur["tail"]), _v(tibia["tail"])
        body.tube([hip, knee, ankle], [(0.076, 0.073), (0.064, 0.062), (0.043, 0.042)],
                  [{"root": 0.24, side + "femur": 0.76},
                   {side + "femur": 0.52, side + "tibia": 0.48},
                   {side + "tibia": 0.92, side + "foot": 0.08}],
                  "trousers", sides=16, steps_per_segment=7)
        toes = _v(rest[side + "toes"]["tail"])
        foot_head = _v(rest[side + "foot"]["head"])
        boot_center = foot_head.lerp(toes, 0.57) + Vector((0.0, 0.0, 0.010))
        foot_weights = {side + "foot": 0.62, side + "toes": 0.38}
        body.ellipsoid(boot_center, (0.057, 0.088, 0.044), "boot", foot_weights,
                       segments=20, rings=12)
        sole_center = boot_center + Vector((0.0, 0.0, -0.031))
        body.ellipsoid(sole_center, (0.058, 0.085, 0.014), "blue_dark", foot_weights,
                       segments=18, rings=10)

        # Closed palms only; the source finger joints receive no decorative DOFs.
        hand_start = _v(rest[side + "hand"]["head"])
        hand_end = _v(rest[side + "hand"]["tail"])
        fist = (hand_start + hand_end) * 0.5
        body.ellipsoid(fist, (0.040, 0.040, 0.040), "skin", {side + "hand": 1.0},
                       segments=20, rings=12)

    thorax = _v(rest["thorax"]["tail"])
    low_neck = _v(rest["lowerneck"]["tail"])
    upper_neck = _v(rest["upperneck"]["tail"])
    head_base = _v(rest["head"]["head"])
    body.tube([thorax, low_neck, upper_neck, head_base],
              [0.060, 0.055, 0.053, 0.056],
              [{"thorax": 0.62, "lowerneck": 0.38},
               {"lowerneck": 0.62, "upperneck": 0.38},
               {"upperneck": 0.74, "head": 0.26},
               {"upperneck": 0.28, "head": 0.72}],
              "skin", sides=16, steps_per_segment=4)


def _face_surface_y(center, radii, x, z):
    nx = max(-0.94, min(0.94, (x - center.x) / radii.x))
    nz = max(-0.94, min(0.94, (z - center.z) / radii.z))
    return center.y - radii.y * math.sqrt(max(0.04, 1.0 - nx * nx - nz * nz))


def _make_face(face, rest):
    head_center = _v(rest["head"]["head"]) + Vector((0.0, 0.0, 0.060))
    head_weights = {"head": 1.0}
    radii = Vector((0.20, 0.17, 0.23))
    face.ellipsoid(head_center, radii, "skin", head_weights, segments=36, rings=24)

    for sign in (-1.0, 1.0):
        ear = head_center + Vector((sign * 0.190, 0.006, -0.012))
        face.ellipsoid(ear, (0.037, 0.030, 0.052), "skin", head_weights, segments=16, rings=10)
        face.ellipsoid(ear + Vector((0.0, -0.024, 0.0)), (0.016, 0.009, 0.029),
                       "skin_light", head_weights, segments=12, rings=8)

        eye_x = sign * 0.077
        eye_z = head_center.z + 0.040
        eye_y = _face_surface_y(head_center, radii, eye_x, eye_z) - 0.003
        face.ellipsoid((eye_x, eye_y, eye_z), (0.034, 0.014, 0.047),
                       "eye_white", head_weights, segments=20, rings=14)
        iris_x = eye_x + sign * 0.002
        iris_y = eye_y - 0.012
        face.ellipsoid((iris_x, iris_y, eye_z - 0.004), (0.019, 0.009, 0.030),
                       "iris", head_weights, segments=16, rings=11)
        face.ellipsoid((iris_x, iris_y - 0.007, eye_z - 0.004), (0.009, 0.006, 0.021),
                       "pupil", head_weights, segments=14, rings=9)
        face.ellipsoid((iris_x - 0.003, iris_y - 0.013, eye_z + 0.010), (0.0055, 0.004, 0.007),
                       "glint", head_weights, segments=10, rings=7)
        face.ellipsoid((sign * 0.115, _face_surface_y(head_center, radii, sign * 0.115, head_center.z - 0.047) - 0.004,
                        head_center.z - 0.047), (0.025, 0.006, 0.012),
                       "blush", head_weights, segments=14, rings=9)
        brow_points = []
        for offset_x, offset_z in ((-0.032, 0.105), (0.0, 0.118), (0.032, 0.105)):
            x = eye_x + offset_x
            z = head_center.z + offset_z
            brow_points.append(Vector((x, _face_surface_y(head_center, radii, x, z) - 0.006, z)))
        face.tube(brow_points, [0.0045, 0.0060, 0.0032], [head_weights] * 3,
                  "hair_mid", sides=7, steps_per_segment=3)

    nose_z = head_center.z - 0.008
    nose_y = _face_surface_y(head_center, radii, 0.0, nose_z) - 0.006
    face.ellipsoid((0.0, nose_y, nose_z), (0.012, 0.010, 0.010),
                   "skin_light", head_weights, segments=12, rings=8)
    smile = []
    for x, dz in ((-0.024, -0.090), (-0.010, -0.096), (0.010, -0.096), (0.024, -0.090)):
        z = head_center.z + dz
        smile.append(Vector((x, _face_surface_y(head_center, radii, x, z) - 0.003, z)))
    face.tube(smile, [0.0032, 0.0035, 0.0035, 0.0028], [head_weights] * len(smile),
              "hair_mid", sides=6, steps_per_segment=2)
    return head_center, radii


def _hair_bow(hair, tie, weight):
    hair.ellipsoid(tie, (0.026, 0.022, 0.022), "blue_light", weight, segments=14, rings=9)
    # Two plump but flat-looking bow loops sit on either side of the knot.
    for sign in (-1.0, 1.0):
        p0 = tie + Vector((0.0, 0.0, 0.0))
        p1 = tie + Vector((sign * 0.050, 0.020, 0.030))
        p2 = tie + Vector((sign * 0.105, 0.026, 0.010))
        p3 = tie + Vector((sign * 0.060, 0.018, -0.030))
        p4 = tie + Vector((0.0, 0.0, 0.0))
        hair.tube([p0, p1, p2, p3, p4], [0.010, 0.013, 0.011, 0.013, 0.008],
                  [weight] * 5, "blue_light", sides=10, steps_per_segment=3)
    # Pale tails flow behind the crown; they do not replace the ponytail mass.
    for sign in (-1.0, 1.0):
        p0 = tie + Vector((sign * 0.012, 0.010, -0.006))
        p1 = tie + Vector((sign * 0.030, 0.065, -0.045))
        p2 = tie + Vector((sign * 0.045, 0.105, -0.090))
        p3 = tie + Vector((sign * 0.068, 0.126, -0.128))
        hair.tube([p0, p1, p2, p3], [(0.014, 0.005), (0.013, 0.0045),
                                     (0.009, 0.0035), (0.002, 0.0015)],
                  [weight] * 4, "blue_light", sides=10, steps_per_segment=3)


def _make_hair(hair, head_center):
    w = {"head": 1.0}
    # Volumetric cap and occipital mass leave the face and its profile visible.
    hair.ellipsoid(head_center + Vector((0.0, 0.027, 0.118)), (0.203, 0.179, 0.139),
                   "hair", w, segments=32, rings=20)
    hair.ellipsoid(head_center + Vector((0.0, 0.080, 0.016)), (0.192, 0.137, 0.175),
                   "hair_mid", w, segments=28, rings=18)
    # Three separated fringe locks sweep from the crown onto the upper forehead.
    for sign, xoff in ((-1.0, -0.060), (1.0, 0.012), (1.0, 0.073)):
        p0 = head_center + Vector((xoff * 0.50, -0.078, 0.198))
        p1 = head_center + Vector((xoff * 0.85, -0.132, 0.164))
        p2 = head_center + Vector((xoff, -0.156, 0.106))
        p3 = head_center + Vector((xoff + sign * 0.016, -0.151, 0.074))
        hair.tube([p0, p1, p2, p3], [0.032, 0.030, 0.026, 0.012], [w] * 4,
                  "hair_mid" if xoff > 0 else "hair", sides=12, steps_per_segment=4)
    # Two layered locks frame the face and continue around the ears to the sides.
    for sign in (-1.0, 1.0):
        points = [head_center + Vector((sign * 0.145, -0.090, 0.138)),
                  head_center + Vector((sign * 0.178, -0.108, 0.062)),
                  head_center + Vector((sign * 0.184, -0.070, -0.036)),
                  head_center + Vector((sign * 0.166, 0.012, -0.108))]
        hair.tube(points, [0.041, 0.035, 0.025, 0.010], [w] * 4,
                  "hair", sides=12, steps_per_segment=4)
    # High ponytail is an arcing, tapered volume rooted above the rear crown.
    tie = head_center + Vector((0.0, 0.130, 0.158))
    pony_points = [tie,
                   head_center + Vector((0.008, 0.194, 0.239)),
                   head_center + Vector((0.025, 0.272, 0.238)),
                   head_center + Vector((0.054, 0.316, 0.176)),
                   head_center + Vector((0.074, 0.326, 0.100)),
                   head_center + Vector((0.070, 0.304, 0.035)),
                   head_center + Vector((0.045, 0.272, -0.012))]
    pony_radii = [(0.072, 0.065), (0.071, 0.060), (0.062, 0.052),
                  (0.050, 0.043), (0.037, 0.032), (0.023, 0.020), (0.004, 0.004)]
    hair.tube(pony_points, pony_radii, [w] * len(pony_points), "hair",
              sides=16, steps_per_segment=5)
    # Fine raised strands catch the key light while remaining part of the same hair object.
    for sign, offset in ((-1.0, -0.030), (1.0, 0.026)):
        points = [p + Vector((offset, -0.020, 0.005)) for p in pony_points[1:-1]]
        hair.tube(points, [0.010, 0.009, 0.007, 0.004, 0.001], [w] * len(points),
                  "hair_light" if sign > 0 else "hair_mid", sides=7, steps_per_segment=3)
    _hair_bow(hair, tie, w)


def build_character(armature, rest) -> dict:
    """Build Jiang Yanqiu over the caller's original 31-bone CMU armature.

    Args:
        armature: Existing Blender armature with the original CMU bone names.
        rest: Mapping of all CMU bone names to head/tail/rotation lists in metres.

    Returns a JSON-serializable build receipt; no bones, props or object-scale
    animation are created here.
    """
    _require_rest(rest, armature)
    body = _WeightedMesh("Body")
    garment = _WeightedMesh("Garment")
    face = _WeightedMesh("Face")
    hair = _WeightedMesh("Hair")

    _make_body(body, rest)
    _make_garments(garment, rest)
    head_center, face_radii = _make_face(face, rest)
    _make_hair(hair, head_center)

    builders = [body, garment, face, hair]
    objects = [builder.object("Jiang" + builder.part, armature) for builder in builders]
    all_weights = [weight for builder in builders for weight in builder.weights]
    max_influences = max((len(weight) for weight in all_weights), default=0)
    max_sum_error = max((abs(sum(weight.values()) - 1.0) for weight in all_weights), default=0.0)
    per_object = {}
    for builder in builders:
        per_object["Jiang" + builder.part] = {
            "vertex_count": len(builder.vertices),
            "max_influences": max(len(item) for item in builder.weights),
            "max_weight_sum_error": max(abs(sum(item.values()) - 1.0) for item in builder.weights),
        }

    left_fist = (_v(rest["lhand"]["head"]) + _v(rest["lhand"]["tail"])) * 0.5
    right_fist = (_v(rest["rhand"]["head"]) + _v(rest["rhand"]["tail"])) * 0.5
    return {
        "objects": [obj.name for obj in objects],
        "vertex_count": sum(len(builder.vertices) for builder in builders),
        "identity": {
            "name": "江砚秋",
            "reference": "assets/art/v2/jiang-yanqiu-v2.png",
            "interpretation": "Original volumetric 3D reading of the approved Q-style face, high dark-brown ponytail, pale-blue ribbon and ivory/blue robe.",
            "coordinate_system": "Blender Z-up; face -Y; character left +X",
            "face_center_m": [float(x) for x in head_center],
            "face_radii_m": [float(x) for x in face_radii],
            "high_ponytail": True,
        },
        "landmarks": {
            "closed_fist_centers_m": {
                "left": [float(x) for x in left_fist],
                "right": [float(x) for x in right_fist],
            },
        },
        "cloth_weights": {
            "max_influences_allowed": 4,
            "max_observed_influences": max_influences,
            "all_normalized": max_sum_error < 1.0e-6,
            "max_weight_sum_error": max_sum_error,
            "per_object": per_object,
            "torso_bones": ["root", "lowerback", "upperback", "thorax"],
            "left_sleeve_bones": ["lclavicle", "lhumerus", "lradius", "lwrist"],
            "right_sleeve_bones": ["rclavicle", "rhumerus", "rradius", "rwrist"],
            "lower_panels_follow": {"left": "lfemur", "right": "rfemur"},
            "deformation": "normalized linear blend skinning; preserve volume disabled",
        },
    }
