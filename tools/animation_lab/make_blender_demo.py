"""Build an original Blender motion-study rig from animation_lab/motion.json.

Coordinates are metres: X forward, Y lateral, Z up. The source motion JSON is
read-only. Run inside Blender 4.5.9 with:
  Blender -b --python tools/animation_lab/make_blender_demo.py -- --repo PATH --mode build
Modes: build (blend + GLB), sample (four review PNGs), render (3 x 120 PNGs).
"""
from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import math
import struct
import sys
import time
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

CLIPS = ("thrust", "cut", "staff")
PREVIEW_SIZE = 384
FRAME_COUNT = 120

# Original palette approximation sampled from the existing Jiang Yanqiu art;
# the image itself is not used as model texture or geometry.
PALETTE = {
    "robe": (0.89, 0.92, 0.91, 1.0),
    "robe_light": (0.96, 0.97, 0.93, 1.0),
    "robe_shadow": (0.60, 0.71, 0.77, 1.0),
    "blue": (0.20, 0.34, 0.48, 1.0),
    "blue_light": (0.44, 0.60, 0.70, 1.0),
    "blue_dark": (0.12, 0.20, 0.29, 1.0),
    "skin": (0.91, 0.66, 0.50, 1.0),
    "skin_light": (0.98, 0.77, 0.61, 1.0),
    "blush": (0.87, 0.39, 0.34, 1.0),
    "hair": (0.12, 0.095, 0.075, 1.0),
    "hair_light": (0.27, 0.20, 0.15, 1.0),
    "eye": (0.095, 0.075, 0.065, 1.0),
    "eye_light": (1.0, 0.94, 0.80, 1.0),
    "gold": (0.72, 0.51, 0.25, 1.0),
    "steel": (0.66, 0.76, 0.82, 1.0),
    "steel_light": (0.89, 0.94, 0.94, 1.0),
    "wood": (0.44, 0.25, 0.12, 1.0),
    "sole": (0.10, 0.12, 0.14, 1.0),
}


def v3(value):
    return Vector((float(value[0]), float(value[1]), float(value[2])))


def unit(vector):
    return vector.normalized() if vector.length > 1.0e-8 else Vector((0.0, 0.0, 1.0))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


class MeshBuilder:
    """Accumulate disconnected stylized pieces into one weighted mesh."""

    def __init__(self):
        self.vertices = []
        self.faces = []
        self.face_materials = []
        self.group_vertices = {}

    def add(self, vertices, faces, material, bone):
        first = len(self.vertices)
        self.vertices.extend(tuple(float(c) for c in point) for point in vertices)
        self.faces.extend(tuple(first + i for i in face) for face in faces)
        self.face_materials.extend([material] * len(faces))
        self.group_vertices.setdefault(bone, []).extend(range(first, len(self.vertices)))

    def ellipsoid(self, center, radii, material, bone, rotation=None, segments=20, rings=12):
        center = Vector(center)
        radii = Vector(radii)
        rotation = rotation or Quaternion()
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
        first_ring = 1
        for col in range(segments):
            faces.append((0, first_ring + col, first_ring + (col + 1) % segments))
        for row in range(rings - 2):
            upper = 1 + row * segments
            lower = upper + segments
            for col in range(segments):
                nxt = (col + 1) % segments
                faces.append((upper + col, lower + col, lower + nxt, upper + nxt))
        last_ring = 1 + (rings - 2) * segments
        for col in range(segments):
            faces.append((last_ring + col, bottom, last_ring + (col + 1) % segments))
        self.add(vertices, faces, material, bone)

    def segment(self, start, end, radius, material, bone, radius_end=None, sides=14, profile=None):
        start = Vector(start)
        end = Vector(end)
        axis = unit(end - start)
        if profile is None:
            profile = ((0.0, 0.42), (0.10, 0.84), (0.28, 1.0),
                       (0.72, 1.0), (0.90, 0.84), (1.0, 0.42))
        radius_end = radius if radius_end is None else radius_end
        basis_hint = Vector((0.0, 1.0, 0.0)) if abs(axis.dot(Vector((0.0, 0.0, 1.0))) or 0.0) > 0.93 else Vector((0.0, 0.0, 1.0))
        side = unit(axis.cross(basis_hint))
        depth = unit(axis.cross(side))
        vertices = []
        for t, scale in profile:
            center = start.lerp(end, t)
            ring_radius = radius * (1.0 - t) + radius_end * t
            for col in range(sides):
                angle = 2.0 * math.pi * col / sides
                offset = side * (math.cos(angle) * ring_radius) + depth * (math.sin(angle) * ring_radius)
                vertices.append(center + offset * scale)
        faces = []
        rows = len(profile)
        for row in range(rows - 1):
            for col in range(sides):
                nxt = (col + 1) % sides
                a = row * sides + col
                b = row * sides + nxt
                faces.append((a, b, b + sides, a + sides))
        start_center = len(vertices)
        vertices.append(start)
        end_center = len(vertices)
        vertices.append(end)
        for col in range(sides):
            nxt = (col + 1) % sides
            faces.append((start_center, nxt, col))
            last = (rows - 1) * sides
            faces.append((end_center, last + col, last + nxt))
        self.add(vertices, faces, material, bone)

    def vertical_tube(self, rings, material, bone, sides=32):
        """rings are (z, center_x, center_y, radius_x, radius_y)."""
        vertices = []
        for z, cx, cy, rx, ry in rings:
            for col in range(sides):
                angle = 2.0 * math.pi * col / sides
                vertices.append((cx + rx * math.cos(angle), cy + ry * math.sin(angle), z))
        faces = []
        for row in range(len(rings) - 1):
            for col in range(sides):
                nxt = (col + 1) % sides
                a = row * sides + col
                b = row * sides + nxt
                faces.append((a, b, b + sides, a + sides))
        faces.append(tuple(reversed(tuple(range(sides)))))
        last = (len(rings) - 1) * sides
        faces.append(tuple(last + col for col in range(sides)))
        self.add(vertices, faces, material, bone)

    def mesh_object(self, name, armature, materials):
        mesh = bpy.data.meshes.new(name + "Mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        for key in materials:
            mesh.materials.append(materials[key])
        material_slots = {key: index for index, key in enumerate(materials)}
        for polygon, key in zip(mesh.polygons, self.face_materials):
            polygon.material_index = material_slots[key]
            polygon.use_smooth = True
        for group_name, indices in self.group_vertices.items():
            group = obj.vertex_groups.new(name=group_name)
            group.add(indices, 1.0, "REPLACE")
        modifier = obj.modifiers.new("MotionStudySkin", "ARMATURE")
        modifier.object = armature
        modifier.use_vertex_groups = True
        modifier.use_bone_envelopes = False
        obj.parent = armature
        return obj


def make_materials():
    materials = {}
    for name, color in PALETTE.items():
        material = bpy.data.materials.new("Jiang_" + name)
        material.diffuse_color = color
        material.use_nodes = True
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.72 if name not in {"steel", "steel_light", "gold"} else 0.36
        materials[name] = material
    return materials


def rest_joint_frame(motion):
    return motion["clips"]["thrust"][0]["joints"]


def make_armature(motion):
    rest = rest_joint_frame(motion)
    data = bpy.data.armatures.new("JiangMotionRig")
    armature = bpy.data.objects.new("Jiang_Rig", data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = {}
    for spec in motion["bones"]:
        bone = data.edit_bones.new(spec["name"])
        bone.head = v3(rest[spec["head"]])
        bone.tail = v3(rest[spec["tail"]])
        if (bone.tail - bone.head).length < 1.0e-5:
            raise RuntimeError("zero-length source bone: " + spec["name"])
        bone.align_roll(Vector((0.0, 1.0, 0.0)))
        edit_bones[spec["name"]] = bone
    for spec in motion["bones"]:
        if spec["parent"]:
            edit_bones[spec["name"]].parent = edit_bones[spec["parent"]]
            edit_bones[spec["name"]].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    data.display_type = "STICK"
    data.pose_position = "POSE"
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
    return armature


def add_character(mesh, rest):
    # Flared white outer robe, with a cool blue hem and a separate blue inner vest.
    mesh.vertical_tube([
        (0.57, 0.00, 0.0, 0.43, 0.34),
        (0.64, 0.00, 0.0, 0.48, 0.38),
        (0.82, 0.00, 0.0, 0.44, 0.35),
        (1.06, 0.01, 0.0, 0.37, 0.31),
        (1.28, 0.02, 0.0, 0.33, 0.29),
        (1.47, 0.025, 0.0, 0.31, 0.28),
        (1.54, 0.025, 0.0, 0.28, 0.25),
    ], "robe", "hips")
    mesh.vertical_tube([
        (0.58, 0.0, 0.0, 0.482, 0.382),
        (0.65, 0.0, 0.0, 0.485, 0.385),
    ], "blue", "hips")
    # Indigo-blue waist sash, shaped as a low ring around the robe.
    mesh.vertical_tube([
        (1.015, 0.0, 0.0, 0.385, 0.315),
        (1.035, 0.0, 0.0, 0.397, 0.325),
        (1.105, 0.0, 0.0, 0.382, 0.313),
        (1.125, 0.0, 0.0, 0.374, 0.307),
    ], "blue", "hips")
    mesh.ellipsoid((0.402, 0.0, 1.067), (0.040, 0.085, 0.061), "gold", "hips", segments=16, rings=10)
    mesh.ellipsoid((0.426, 0.0, 1.067), (0.026, 0.047, 0.032), "blue_light", "hips", segments=16, rings=10)
    # A fitted blue vest over the chest; the pale lapels remain distinct in profile.
    mesh.ellipsoid((0.265, 0.0, 1.395), (0.145, 0.282, 0.325), "blue", "chest", segments=24, rings=14)
    mesh.segment((0.392, -0.17, 1.59), (0.435, -0.035, 1.34), 0.025, "robe_light", "chest")
    mesh.segment((0.435, -0.035, 1.34), (0.392, 0.17, 1.59), 0.025, "robe_light", "chest")
    mesh.segment((0.391, 0.0, 1.58), (0.405, 0.0, 1.38), 0.018, "blue_light", "chest")
    for z in (1.43, 1.34, 1.25):
        mesh.ellipsoid((0.414, 0.0, z), (0.022, 0.027, 0.027), "gold", "chest", segments=12, rings=8)

    # Short dark trousers and articulated boots remain visible below the robe.
    for side in ("R", "L"):
        hip = v3(rest["hip_" + side])
        knee = v3(rest["knee_" + side])
        ankle = v3(rest["ankle_" + side])
        toe = v3(rest["toe_" + side])
        mesh.segment(hip, knee, 0.145, "blue_dark", "thigh_" + side)
        mesh.segment(knee, ankle, 0.118, "blue", "shin_" + side)
        mesh.segment(ankle.lerp(toe, 0.20), ankle.lerp(toe, 0.80), 0.105, "sole", "foot_" + side)
        mesh.ellipsoid((ankle.lerp(toe, 0.52).x, ankle.lerp(toe, 0.52).y, 0.135),
                       (0.17, 0.115, 0.105), "blue_dark", "foot_" + side, segments=18, rings=10)
        mesh.segment(knee.lerp(ankle, 0.17), knee.lerp(ankle, 0.31), 0.124, "gold", "shin_" + side)
        # White sleeves over both arm chains; blue cuffs and warm hands mark grips.
        for bone_name, start_name, end_name, radius in (
            ("upper_" + side, "shoulder_" + side, "elbow_" + side, 0.142),
            ("fore_" + side, "elbow_" + side, "hand_" + side, 0.118),
        ):
            a = v3(rest[start_name])
            b = v3(rest[end_name])
            mesh.segment(a, b, radius, "robe_light", bone_name)
            direction = unit(b - a)
            cuff_a = b - direction * 0.10
            cuff_b = b - direction * 0.025
            mesh.segment(cuff_a, cuff_b, radius * 0.98, "blue_light", bone_name)
            mesh.ellipsoid(b, (0.080, 0.082, 0.086), "skin", bone_name, segments=16, rings=10)
            mesh.ellipsoid(b + Vector((0.035, 0.0, 0.012)), (0.050, 0.050, 0.055), "skin_light", bone_name, segments=14, rings=8)
        shoulder = v3(rest["shoulder_" + side])
        mesh.ellipsoid(shoulder, (0.15, 0.17, 0.16), "blue", "upper_" + side, segments=18, rings=10)
        mesh.segment(shoulder, v3(rest["elbow_" + side]), 0.145, "robe", "upper_" + side)

    # Neck, oversized friendly face, tied dark-brown hair and pale-blue ribbon.
    mesh.segment((0.025, 0.0, 1.64), (0.025, 0.0, 1.84), 0.16, "skin", "head")
    mesh.ellipsoid((0.035, 0.0, 2.025), (0.385, 0.345, 0.405), "skin", "head", segments=28, rings=18)
    mesh.ellipsoid((-0.005, 0.0, 2.285), (0.352, 0.333, 0.205), "hair", "head", segments=24, rings=14)
    mesh.ellipsoid((-0.185, 0.0, 2.335), (0.235, 0.235, 0.225), "hair", "head", segments=22, rings=14)
    mesh.ellipsoid((-0.18, -0.015, 2.42), (0.172, 0.18, 0.115), "hair_light", "head", segments=18, rings=10)
    for y in (-0.28, 0.28):
        mesh.ellipsoid((0.00, y, 1.99), (0.17, 0.082, 0.17), "skin_light", "head", segments=16, rings=10)
        mesh.ellipsoid((-0.17, y * 0.63, 2.44), (0.17, 0.075, 0.045), "blue_light", "head", segments=16, rings=8, rotation=Quaternion((0.0, 0.0, 1.0), 0.18 if y < 0 else -0.18))
    # Side locks frame rather than hide the face.
    for y in (-0.265, 0.265):
        mesh.segment((0.21, y, 2.27), (0.315, y * 0.90, 1.94), 0.092, "hair", "head", radius_end=0.032)
        mesh.segment((0.10, y * 1.05, 2.30), (0.24, y * 1.06, 2.12), 0.075, "hair_light", "head", radius_end=0.040)
    # Large readable eyes on the +X face plane, with small glints and brows.
    for y in (-0.132, 0.132):
        mesh.ellipsoid((0.370, y, 2.045), (0.040, 0.052, 0.074), "eye", "head", segments=18, rings=12)
        mesh.ellipsoid((0.402, y - 0.008, 2.050), (0.020, 0.030, 0.048), "hair_light", "head", segments=14, rings=9)
        mesh.ellipsoid((0.419, y - 0.012, 2.071), (0.010, 0.014, 0.020), "eye_light", "head", segments=12, rings=8)
        mesh.segment((0.354, y - 0.052, 2.148), (0.368, y + 0.046, 2.158), 0.021, "hair", "head", radius_end=0.018)
        mesh.ellipsoid((0.367, y * 1.64, 1.980), (0.018, 0.052, 0.026), "blush", "head", segments=14, rings=8)
    mesh.ellipsoid((0.409, 0.0, 1.997), (0.033, 0.033, 0.040), "skin_light", "head", segments=14, rings=9)
    mesh.segment((0.409, -0.046, 1.908), (0.412, 0.046, 1.908), 0.012, "eye", "head", radius_end=0.010)
    mesh.ellipsoid((0.0, -0.34, 2.025), (0.105, 0.052, 0.12), "skin", "head", segments=14, rings=9)
    mesh.ellipsoid((0.0, 0.34, 2.025), (0.105, 0.052, 0.12), "skin", "head", segments=14, rings=9)
    # Small round hair tie and two pale ribbon tails echo the established art palette.
    mesh.ellipsoid((-0.24, -0.12, 2.34), (0.06, 0.10, 0.07), "blue_light", "head", segments=14, rings=8)
    mesh.segment((-0.30, -0.15, 2.35), (-0.43, -0.26, 2.12), 0.048, "blue_light", "head", radius_end=0.012)
    mesh.segment((-0.29, -0.13, 2.34), (-0.16, -0.29, 2.16), 0.043, "robe_light", "head", radius_end=0.010)

    # A compact sleeve at each hand clarifies the two-source grip without changing joints.
    for side in ("R", "L"):
        hand = v3(rest["hand_" + side])
        mesh.ellipsoid(hand, (0.082, 0.078, 0.082), "skin_light", "fore_" + side, segments=16, rings=10)


def add_weapon_geometry(builder, rest, kind):
    hand = v3(rest["hand_R"])
    tip = v3(rest["tip"])
    axis = unit(tip - hand)
    side = unit(axis.cross(Vector((0.0, 1.0, 0.0))))
    if side.length < 1.0e-6:
        side = unit(axis.cross(Vector((0.0, 0.0, 1.0))))
    depth = unit(axis.cross(side))
    if kind == "sword":
        # Wrapped hilt, curved guard, and a broad tapered blade, all on weapon bone.
        builder.segment(hand - axis * 0.17, hand + axis * 0.11, 0.032, "blue_dark", "weapon")
        builder.segment(hand - axis * 0.17, hand - axis * 0.13, 0.040, "gold", "weapon")
        builder.segment(hand - axis * 0.08, hand - axis * 0.01, 0.037, "blue_light", "weapon")
        builder.segment(hand + axis * 0.105 - side * 0.13, hand + axis * 0.105 + side * 0.13, 0.022, "gold", "weapon")
        base = hand + axis * 0.125
        length = 0.775
        rings = ((0.0, 0.047, 0.020), (0.09, 0.067, 0.024),
                 (0.72, 0.054, 0.018), (0.94, 0.030, 0.012), (1.0, 0.006, 0.004))
        vertices = []
        for t, width, thick in rings:
            center = base + axis * (length * t)
            for sx, sy in ((-1, -1), (-1, 1), (1, 1), (1, -1)):
                vertices.append(center + side * (sx * width) + depth * (sy * thick))
        faces = []
        for row in range(len(rings) - 1):
            for col in range(4):
                faces.append((row * 4 + col, row * 4 + (col + 1) % 4,
                              (row + 1) * 4 + (col + 1) % 4, (row + 1) * 4 + col))
        faces.append((0, 1, 2, 3))
        last = (len(rings) - 1) * 4
        faces.append((last, last + 1, last + 2, last + 3))
        builder.add(vertices, faces, "steel", "weapon")
        builder.segment(base + depth * 0.018, base + axis * (length * 0.74) + depth * 0.018,
                        0.006, "steel_light", "weapon", radius_end=0.002, sides=8)
    else:
        start = hand - axis * 0.68
        end = hand + axis * 1.12
        builder.segment(start, end, 0.036, "wood", "weapon", radius_end=0.032, sides=16)
        builder.segment(start + axis * 0.02, start + axis * 0.08, 0.042, "gold", "weapon", sides=14)
        builder.segment(end - axis * 0.08, end - axis * 0.02, 0.041, "gold", "weapon", sides=14)
        # Exact source grip spacing is 0.34 along the staff direction.
        for center in (hand, hand + axis * 0.34):
            builder.segment(center - axis * 0.045, center + axis * 0.045, 0.044,
                            "blue_light", "weapon", sides=14)


def look_at(obj, point):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_camera_and_lights(motion):
    camera_spec = motion["camera"]
    camera_data = bpy.data.cameras.new("LabCamera")
    camera = bpy.data.objects.new("LabCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.name = "LabCamera"
    camera.location = v3(camera_spec["position"])
    look_at(camera, camera_spec["target"])
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = float(camera_spec["ortho"])
    camera_data.lens = 50.0
    camera_data.clip_start = 0.01
    camera_data.clip_end = 100.0
    bpy.context.scene.camera = camera

    key_data = bpy.data.lights.new("StudyKey", type="AREA")
    key = bpy.data.objects.new("StudyKey", key_data)
    bpy.context.collection.objects.link(key)
    key.location = (1.5, -4.0, 5.0)
    key_data.energy = 420.0
    key_data.shape = "DISK"
    key_data.size = 4.2
    look_at(key, (0.0, 0.0, 1.25))

    fill_data = bpy.data.lights.new("StudyFill", type="AREA")
    fill = bpy.data.objects.new("StudyFill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (4.0, 2.0, 2.8)
    fill_data.energy = 220.0
    fill_data.shape = "DISK"
    fill_data.size = 3.5
    look_at(fill, (0.0, 0.0, 1.4))
    return camera, (key, fill)


def desired_bone_matrix(spec, joints, rest_matrices, rest_lengths):
    head = v3(joints[spec["head"]])
    tail = v3(joints[spec["tail"]])
    direction = unit(tail - head)
    rest = rest_matrices[spec["name"]]
    rest_direction = unit(Vector(rest.to_3x3() @ Vector((0.0, 1.0, 0.0))))
    rest_rotation = rest.to_3x3().to_quaternion()
    yaw_rotation = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(float(joints.get("yaw", 0.0))))
    authored_rotation = yaw_rotation @ rest_rotation
    yawed_rest_direction = unit(authored_rotation @ Vector((0.0, 1.0, 0.0)))
    swing = yawed_rest_direction.rotation_difference(direction)
    rotation = swing @ authored_rotation
    # Bone matrix columns are unit axes; the source endpoint distance carries
    # the authored rest length. Only the weapon grows for the longer staff.
    scale_y = (tail - head).length / max(rest_lengths[spec["name"]], 1.0e-8)
    return Matrix.LocRotScale(head, rotation, Vector((1.0, scale_y, 1.0)))


def local_basis_from_desired(spec, desired, rest_matrices, desired_by_name, specs_by_name):
    rest = rest_matrices[spec["name"]]
    if spec["parent"] is None:
        return rest.inverted() @ desired
    parent_name = spec["parent"]
    parent_rest = rest_matrices[parent_name]
    parent_pose = desired_by_name[parent_name]
    return rest.inverted() @ parent_rest @ parent_pose.inverted() @ desired


def iter_action_fcurves(action, slot):
    if hasattr(action, "layers") and len(action.layers):
        for layer in action.layers:
            for strip in layer.strips:
                try:
                    bag = strip.channelbag(slot)
                except Exception:
                    bag = None
                if bag:
                    for curve in bag.fcurves:
                        yield curve
    else:
        for curve in action.fcurves:
            yield curve


def bake_actions(motion, armature):
    scene = bpy.context.scene
    scene.render.fps = int(motion["fps"])
    specs = motion["bones"]
    specs_by_name = {spec["name"]: spec for spec in specs}
    rest_matrices = {name: armature.data.bones[name].matrix_local.copy() for name in specs_by_name}
    rest_joints = rest_joint_frame(motion)
    rest_lengths = {spec["name"]: (v3(rest_joints[spec["tail"]]) - v3(rest_joints[spec["head"]])).length
                    for spec in specs}
    animation_data = armature.animation_data_create()
    actions = {}
    all_frame_endpoint_errors = {clip: 0.0 for clip in CLIPS}
    for clip in CLIPS:
        action = bpy.data.actions.new(clip)
        action.use_fake_user = True
        slot = action.slots.new("OBJECT", armature.name) if hasattr(action, "slots") else None
        animation_data.action = action
        if slot is not None:
            animation_data.action_slot = slot
        actions[clip] = (action, slot)
        for index, sample in enumerate(motion["clips"][clip]):
            frame = index + 1
            scene.frame_set(frame)
            desired_by_name = {}
            for spec in specs:
                desired_by_name[spec["name"]] = desired_bone_matrix(
                    spec, sample["joints"], rest_matrices, rest_lengths)
            for spec in specs:
                pose_bone = armature.pose.bones[spec["name"]]
                # Assign in armature space and let Blender solve each local basis
                # after its parent has evaluated. This avoids accumulated matrix
                # decomposition drift in nested limb chains.
                pose_bone.matrix = desired_by_name[spec["name"]]
                bpy.context.view_layer.update()
                joint_data = sample["joints"]
                error = max((pose_bone.head - v3(joint_data[spec["head"]])).length,
                            (pose_bone.tail - v3(joint_data[spec["tail"]])).length)
                all_frame_endpoint_errors[clip] = max(all_frame_endpoint_errors[clip], error)
                pose_bone.keyframe_insert(data_path="location", frame=frame, group=spec["name"])
                pose_bone.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=spec["name"])
                pose_bone.keyframe_insert(data_path="scale", frame=frame, group=spec["name"])
        for curve in iter_action_fcurves(action, slot):
            for point in curve.keyframe_points:
                point.interpolation = "LINEAR"
        print("BAKED", clip, "frames", len(motion["clips"][clip]),
              "curves", sum(1 for _ in iter_action_fcurves(action, slot)),
              "max_endpoint_error", all_frame_endpoint_errors[clip], flush=True)
        if all_frame_endpoint_errors[clip] > 2.0e-5:
            raise RuntimeError(f"Frame bake diverged from source ({clip}: {all_frame_endpoint_errors[clip]:.8f} m)")

    # Re-evaluate representative non-neutral frames from the keyed actions.
    for clip, sample_index in (("thrust", 42), ("cut", 45), ("staff", 42)):
        action, slot = actions[clip]
        animation_data.action = action
        if slot is not None:
            animation_data.action_slot = slot
        frame = sample_index + 1
        scene.frame_set(frame)
        source = motion["clips"][clip][sample_index]["joints"]
        bpy.context.view_layer.update()
        errors = []
        per_bone = []
        for spec in specs:
            pose_bone = armature.pose.bones[spec["name"]]
            head_error = (pose_bone.head - v3(source[spec["head"]])).length
            tail_error = (pose_bone.tail - v3(source[spec["tail"]])).length
            errors.extend((head_error, tail_error))
            per_bone.append((spec["name"], round(head_error, 6), round(tail_error, 6),
                             tuple(round(float(c), 4) for c in pose_bone.head),
                             tuple(round(float(c), 4) for c in v3(source[spec["head"]]))))
        maximum = max(errors)
        print("POSE_ERRORS", clip, per_bone, flush=True)
        print("POSE_CHECK", clip, "frame", frame, "max_endpoint_error", maximum, flush=True)
        if maximum > 0.003:
            raise RuntimeError(f"Baked endpoints differ from source ({clip}: {maximum:.6f} m)")
    animation_data.action = actions["thrust"][0]
    if actions["thrust"][1] is not None:
        animation_data.action_slot = actions["thrust"][1]
    scene.frame_set(1)
    return actions


def create_scene(repo, motion):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures,
                       bpy.data.cameras, bpy.data.lights, bpy.data.actions, bpy.data.materials):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = PREVIEW_SIZE
    scene.render.resolution_y = PREVIEW_SIZE
    scene.render.resolution_percentage = 100
    scene.render.fps = int(motion["fps"])
    scene.frame_start = 1
    scene.frame_end = FRAME_COUNT + 1
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.render.filepath = "//"
    scene.world.color = (0.08, 0.08, 0.08)
    materials = make_materials()
    armature = make_armature(motion)
    rest = rest_joint_frame(motion)
    body = MeshBuilder()
    add_character(body, rest)
    character = body.mesh_object("Jiang_Training_Dummy", armature, materials)
    character["study_role"] = "rigged full-body stylized Jiang color study"
    sword_builder = MeshBuilder()
    add_weapon_geometry(sword_builder, rest, "sword")
    sword = sword_builder.mesh_object("Weapon_Sword_Variant", armature, materials)
    staff_builder = MeshBuilder()
    add_weapon_geometry(staff_builder, rest, "staff")
    staff = staff_builder.mesh_object("Weapon_Staff_Variant", armature, materials)
    sword["study_role"] = "toggle this variant for thrust/cut"
    staff["study_role"] = "toggle this variant for staff"
    camera, lights = setup_camera_and_lights(motion)
    scene.camera = camera
    scene.frame_set(1)
    bpy.context.view_layer.update()
    return armature, (character, sword, staff), camera, lights


def select_export_set(armature, objects, camera):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (armature, *objects, camera):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature


def parse_glb(path):
    data = path.read_bytes()
    if len(data) < 20:
        raise RuntimeError("GLB is unexpectedly small")
    magic, version, total = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or total != len(data):
        raise RuntimeError("GLB header is invalid")
    json_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise RuntimeError("GLB first chunk is not JSON")
    return json.loads(data[20:20 + json_length].decode("utf-8").rstrip(" \t\r\n\x00"))


def export_glb(repo, armature, objects, camera, motion):
    destination = repo / "assets/art/animation_lab/model.glb"
    destination.parent.mkdir(parents=True, exist_ok=True)
    select_export_set(armature, objects, camera)
    result = bpy.ops.export_scene.gltf(
        filepath=str(destination),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_nla_strips=False,
        export_frame_range=True,
        export_frame_step=1,
        export_force_sampling=True,
        export_sampling_interpolation_fallback="LINEAR",
        export_anim_single_armature=True,
        export_skins=True,
        export_def_bones=True,
        export_leaf_bone=False,
        export_cameras=True,
        export_lights=False,
        export_materials="EXPORT",
        export_yup=True,
        export_apply=False,
        export_optimize_animation_size=False,
    )
    if "FINISHED" not in result:
        raise RuntimeError("Blender glTF export did not finish")
    gltf = parse_glb(destination)
    animations = [animation.get("name", "") for animation in gltf.get("animations", [])]
    if sorted(animations) != sorted(CLIPS):
        raise RuntimeError(f"Expected GLB actions {CLIPS}, got {animations}")
    if not gltf.get("skins"):
        raise RuntimeError("Exported GLB contains no skin")
    if not gltf.get("cameras"):
        raise RuntimeError("Exported GLB omitted LabCamera")
    node_names = {node.get("name") for node in gltf.get("nodes", [])}
    for required in ("Jiang_Rig", "Jiang_Training_Dummy", "Weapon_Sword_Variant", "Weapon_Staff_Variant", "LabCamera"):
        if required not in node_names:
            raise RuntimeError("Exported GLB omitted node " + required)
    print("GLB_CHECK", json.dumps({"size_bytes": destination.stat().st_size,
          "animations": animations, "skins": len(gltf.get("skins", [])),
          "cameras": len(gltf.get("cameras", [])), "nodes": len(node_names)}), flush=True)
    return destination, animations


def write_provenance(repo, motion_path, script_path, glb_path, motion, animations, render_info=None):
    info = {
        "version": 1,
        "purpose": "Original Blender full-body motion study; exploratory and not final Jiang artwork or verified martial technique.",
        "tool": "Blender " + bpy.app.version_string,
        "source_motion": "assets/data/animation_lab/motion.json",
        "source_motion_sha256": sha256(motion_path),
        "builder_script": "tools/animation_lab/make_blender_demo.py",
        "builder_script_sha256": sha256(script_path),
        "palette_reference": "assets/art/v2/jiang-yanqiu-v2.png (color inspiration only; no image pixels imported)",
        "model": "Original stylized Q版 blue-white robe, dark tied hair, warm face, boots and separate sword/staff toggle meshes.",
        "coordinate_system": "X forward, Y lateral, Z up; metres; source motion JSON read-only.",
        "rig": {"armature": "Jiang_Rig", "character_mesh": "Jiang_Training_Dummy",
                "weapon_variants": ["Weapon_Sword_Variant", "Weapon_Staff_Variant"],
                "weighted_armature_meshes": 3},
        "animations": {"fps": motion["fps"], "duration_seconds": motion["duration"],
                       "source_samples_per_clip": {name: len(motion["clips"][name]) for name in CLIPS},
                       "glb_actions": animations},
        "camera": {"name": "LabCamera", "position": motion["camera"]["position"],
                   "target": motion["camera"]["target"], "ortho_scale": motion["camera"]["ortho"],
                   "render_resolution": [PREVIEW_SIZE, PREVIEW_SIZE],
                   "camera_frame_bounds_camera_space": {"left": -motion["camera"]["ortho"] / 2.0,
                       "right": motion["camera"]["ortho"] / 2.0,
                       "bottom": -motion["camera"]["ortho"] / 2.0,
                       "top": motion["camera"]["ortho"] / 2.0}},
        "glb": {"path": "assets/art/animation_lab/model.glb",
                "sha256": sha256(glb_path), "size_bytes": glb_path.stat().st_size},
        "renders": render_info or {"status": "not rendered yet"},
    }
    target = repo / "assets/art/animation_lab/blender-source.json"
    target.write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("PROVENANCE", str(target), flush=True)
    return info


def alpha_bounds(path):
    image = bpy.data.images.load(str(path), check_existing=False)
    width, height = image.size
    pixels = array("f", [0.0]) * (width * height * 4)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    left, bottom, right, top = width, height, -1, -1
    for y in range(height):
        row = y * width * 4
        for x in range(width):
            if pixels[row + x * 4 + 3] > 0.02:
                left = min(left, x)
                right = max(right, x)
                bottom = min(bottom, y)
                top = max(top, y)
    if right < left:
        return None
    return {"left": left, "top": height - 1 - top,
            "right": right, "bottom": height - 1 - bottom,
            "width": right - left + 1, "height": top - bottom + 1}


def render_one(repo, armature, objects_by_name, clip, frame, destination, include_bounds=True):
    scene = bpy.context.scene
    action = bpy.data.actions.get(clip)
    if action is None:
        raise RuntimeError("Missing baked action " + clip)
    armature.animation_data.action = action
    if hasattr(action, "slots") and len(action.slots):
        armature.animation_data.action_slot = action.slots[0]
    scene.frame_set(frame)
    objects_by_name["Weapon_Sword_Variant"].hide_render = (clip == "staff")
    objects_by_name["Weapon_Staff_Variant"].hide_render = (clip != "staff")
    scene.render.filepath = str(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    bounds = alpha_bounds(destination) if include_bounds else None
    return {"path": str(destination.relative_to(repo)), "frame": frame - 1,
            "time_seconds": (frame - 1) / scene.render.fps,
            "resolution": [scene.render.resolution_x, scene.render.resolution_y],
            "alpha_bbox_px": bounds, "size_bytes": destination.stat().st_size,
            "sha256": sha256(destination)}


def open_saved_scene(repo):
    path = repo / ".local/qa/animation-options-lab/blender/original-motion-study.blend"
    if not path.exists():
        raise RuntimeError("Build the reusable .blend first: " + str(path))
    bpy.ops.wm.open_mainfile(filepath=str(path))
    return path


def object_map():
    return {obj.name: obj for obj in bpy.context.scene.objects}


def render_sample(repo):
    open_saved_scene(repo)
    objects = object_map()
    armature = objects["Jiang_Rig"]
    samples = (("thrust", 1, "thrust-initial.png"),
               ("thrust", 43, "thrust-contact.png"),
               ("cut", 46, "cut-contact.png"),
               ("staff", 43, "staff-contact.png"))
    output = repo / ".local/qa/animation-options-lab/blender/sample"
    rows = []
    start = time.monotonic()
    for clip, frame, filename in samples:
        result = render_one(repo, armature, objects, clip, frame, output / filename)
        rows.append(result)
        print("SAMPLE_RENDER", json.dumps(result), flush=True)
    total = time.monotonic() - start
    report = {"status": "sampled", "resolution": [PREVIEW_SIZE, PREVIEW_SIZE],
              "transparent": True, "sample_count": len(rows), "total_seconds": round(total, 3),
              "frames": rows, "full_sequence_rendered": False}
    print("SAMPLE_RENDER_REPORT", json.dumps(report), flush=True)
    return report


def render_full(repo, clip_filter=None):
    open_saved_scene(repo)
    objects = object_map()
    armature = objects["Jiang_Rig"]
    clips = [clip_filter] if clip_filter else list(CLIPS)
    rows = []
    start = time.monotonic()
    for clip in clips:
        target = repo / "assets/art/animation_lab/blender_frames" / clip
        target.mkdir(parents=True, exist_ok=True)
        for index in range(FRAME_COUNT):
            result = render_one(repo, armature, objects, clip, index + 1,
                                target / f"{index:04d}.png", include_bounds=True)
            rows.append(result)
            if index % 10 == 0 or index == FRAME_COUNT - 1:
                print("FRAME_RENDER", clip, index, "elapsed_seconds", round(time.monotonic() - start, 3), flush=True)
        print("CLIP_RENDER_DONE", clip, "frames", FRAME_COUNT, flush=True)
    total = time.monotonic() - start
    clip_bounds = {}
    cropped_frames = []
    for clip in clips:
        clip_rows = [row for row in rows if f"/{clip}/" in row["path"]]
        boxes = [row["alpha_bbox_px"] for row in clip_rows if row["alpha_bbox_px"]]
        if len(boxes) != FRAME_COUNT:
            cropped_frames.extend(row["path"] for row in clip_rows if not row["alpha_bbox_px"])
        for row in clip_rows:
            box = row["alpha_bbox_px"]
            if not box or box["left"] <= 0 or box["top"] <= 0 or box["right"] >= PREVIEW_SIZE - 1 or box["bottom"] >= PREVIEW_SIZE - 1:
                cropped_frames.append(row["path"])
        margins = [min(box["left"], box["top"], PREVIEW_SIZE - 1 - box["right"],
                       PREVIEW_SIZE - 1 - box["bottom"]) for box in boxes]
        clip_bounds[clip] = {
            "frames_with_alpha_bounds": len(boxes),
            "min_left": min(box["left"] for box in boxes) if boxes else None,
            "max_right": max(box["right"] for box in boxes) if boxes else None,
            "min_top": min(box["top"] for box in boxes) if boxes else None,
            "max_bottom": max(box["bottom"] for box in boxes) if boxes else None,
            "minimum_edge_margin_px": min(margins) if margins else None,
            "cropped_frames": [row["frame"] for row in clip_rows
                               if not row["alpha_bbox_px"] or row["alpha_bbox_px"]["left"] <= 0
                               or row["alpha_bbox_px"]["top"] <= 0
                               or row["alpha_bbox_px"]["right"] >= PREVIEW_SIZE - 1
                               or row["alpha_bbox_px"]["bottom"] >= PREVIEW_SIZE - 1],
        }
    if len(set(cropped_frames)) != len(cropped_frames):
        cropped_frames = sorted(set(cropped_frames))
    report = {"status": "rendered", "fps": 30, "resolution": [PREVIEW_SIZE, PREVIEW_SIZE],
              "frames_per_clip": FRAME_COUNT, "clips": clips, "total_frames": len(rows),
              "total_seconds": round(total, 3),
              "seconds_per_frame": round(total / max(1, len(rows)), 3),
              "bytes_total": sum(row["size_bytes"] for row in rows),
              "transparent": True, "frame_time_range_seconds": [0.0, (FRAME_COUNT - 1) / 30.0],
              "frame_bounds_and_sha256": rows, "alpha_bounds_by_clip": clip_bounds,
              "cropped_frames": cropped_frames, "all_frames_inside_camera": not cropped_frames}
    print("FULL_RENDER_REPORT", json.dumps(report), flush=True)
    return report


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--mode", choices=("build", "sample", "render"), default="build")
    parser.add_argument("--clip", choices=CLIPS, help="Render only this clip in render mode")
    args = parser.parse_args(argv)
    args.repo = args.repo.resolve()
    return args


def main():
    args = parse_args()
    repo = args.repo
    if args.mode == "build":
        motion_path = repo / "assets/data/animation_lab/motion.json"
        script_path = repo / "tools/animation_lab/make_blender_demo.py"
        motion = json.loads(motion_path.read_text(encoding="utf-8"))
        if int(motion["fps"]) != 30 or set(motion["clips"]) != set(CLIPS):
            raise RuntimeError("Unexpected source motion contract; expected 30fps thrust/cut/staff")
        armature, objects, camera, lights = create_scene(repo, motion)
        actions = bake_actions(motion, armature)
        blend_path = repo / ".local/qa/animation-options-lab/blender/original-motion-study.blend"
        blend_path.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), compress=True)
        print("BLEND_SAVED", str(blend_path), blend_path.stat().st_size, flush=True)
        glb_path, animations = export_glb(repo, armature, objects, camera, motion)
        write_provenance(repo, motion_path, script_path, glb_path, motion, animations)
    elif args.mode == "sample":
        render_report = render_sample(repo)
        motion_path = repo / "assets/data/animation_lab/motion.json"
        script_path = repo / "tools/animation_lab/make_blender_demo.py"
        motion = json.loads(motion_path.read_text(encoding="utf-8"))
        glb_path = repo / "assets/art/animation_lab/model.glb"
        gltf = parse_glb(glb_path)
        write_provenance(repo, motion_path, script_path, glb_path, motion,
                         [item.get("name", "") for item in gltf.get("animations", [])], render_report)
    else:
        if args.clip and args.clip not in CLIPS:
            raise RuntimeError("Unknown clip " + args.clip)
        report = render_full(repo, args.clip)
        motion_path = repo / "assets/data/animation_lab/motion.json"
        script_path = repo / "tools/animation_lab/make_blender_demo.py"
        motion = json.loads(motion_path.read_text(encoding="utf-8"))
        glb_path = repo / "assets/art/animation_lab/model.glb"
        gltf = parse_glb(glb_path)
        write_provenance(repo, motion_path, script_path, glb_path, motion,
                         [item.get("name", "") for item in gltf.get("animations", [])], report)


if __name__ == "__main__":
    main()
