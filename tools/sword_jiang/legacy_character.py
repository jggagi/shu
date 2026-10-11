"""Legacy-styled volumetric Jiang Yanqiu for the independent Blender study.

This keeps the source CMU 31-bone rig and unit object transforms. Geometry is
originally authored around its 0.70-scaled rest pose; the approved art is an
identity and costume reference, not a sampled texture or billboard.
"""
from __future__ import annotations

import importlib.util
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _load_shared_helpers():
    """Import only the existing local mesh/rig helpers, without editing them."""
    module_name = "jiang_legacy_shared_character_helpers"
    module = sys.modules.get(module_name)
    if module is not None:
        return module
    helper_path = Path(__file__).with_name("character.py")
    spec = importlib.util.spec_from_file_location(module_name, helper_path)
    if spec is None or spec.loader is None:
        raise ImportError("Could not load local Jiang character helpers: " + str(helper_path))
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


_shared = _load_shared_helpers()
# This privately imported helper instance belongs only to this candidate.
_shared.PALETTE["skin"] = (0.89, 0.70, 0.49, 1.0)
_shared.PALETTE["skin_light"] = (0.97, 0.79, 0.61, 1.0)
_WeightedMesh = _shared._WeightedMesh
_v = _shared._v
_unit = _shared._unit
_blend_weights = _shared._blend_weights
_normalize_weights = _shared._normalize_weights

MAX_BASE_VERTICES = 24000


def _clamp(value, low=0.0, high=1.0):
    return max(low, min(high, float(value)))


def _smoothstep(edge0, edge1, value):
    t = _clamp((float(value) - edge0) / max(1.0e-9, edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def _wash_patch(builder, first, rows, columns, amplitude=0.012, phase=0.0):
    """Add stable authored fold values over helper-generated fixed vertex colors."""
    for row in range(rows):
        t = row / max(1, rows - 1)
        for column in range(columns):
            u = column / max(1, columns - 1) * 2.0 - 1.0
            index = first + row * columns + column
            color = builder.colors[index]
            fold = amplitude * (
                0.68 * math.cos((u * 3.0 + phase) * math.pi)
                + 0.32 * math.cos((u * 6.0 - t * 0.7 + phase) * math.pi)
            ) * (0.28 + 0.72 * math.sin(math.pi * t))
            builder.colors[index] = tuple(
                _clamp(color[channel] * (1.0 + fold)) for channel in range(3)
            ) + (color[3],)


def _sample_ribbon(anchors, t):
    t = _clamp(t)
    span = min(len(anchors) - 2, int(t * (len(anchors) - 1)))
    local = t * (len(anchors) - 1) - span
    if t >= 1.0:
        span, local = len(anchors) - 2, 1.0
    left_point, left_weights = anchors[span]
    right_point, right_weights = anchors[span + 1]
    return _v(left_point).lerp(_v(right_point), local), _blend_weights(left_weights, right_weights, local)


def _ribbon_patch(builder, anchors, half_width, material, rows=13, columns=9,
                  bulge=0.0025, phase=0.0, fold_amplitude=0.010):
    """Create a fixed, softly folded fabric surface along a weighted path."""
    if len(anchors) < 2:
        raise ValueError("A ribbon needs at least two weighted anchors")

    def point_at(t, u):
        center, _weights = _sample_ribbon(anchors, t)
        before, _ = _sample_ribbon(anchors, max(0.0, t - 0.015))
        after, _ = _sample_ribbon(anchors, min(1.0, t + 0.015))
        tangent = _unit(after - before, (0.0, 0.0, 1.0))
        lateral = _unit(tangent.cross(Vector((0.0, -1.0, 0.0))), (1.0, 0.0, 0.0))
        if lateral.length < 1.0e-7:
            lateral = Vector((1.0, 0.0, 0.0))
        wrinkle = 0.0015 * math.sin((u * 2.0 + t * 0.8 + phase) * math.pi)
        front_bulge = -bulge * (1.0 - u * u)
        return center + lateral * (u * half_width) + Vector((0.0, front_bulge + wrinkle, 0.0))

    def weights_at(t, _u):
        return _sample_ribbon(anchors, t)[1]

    first = len(builder.vertices)
    builder.patch(rows, columns, point_at, weights_at, material)
    _wash_patch(builder, first, rows, columns, fold_amplitude, phase)
    return point_at, weights_at


def _spine_rings(rest):
    return _shared._spine_rings(rest)


def _frame_at_z(rings, z):
    return _shared._frame_at_z(rings, z)


def _spine_weights_at(rings, z):
    return _shared._spine_weights_at(rings, z)


def _front_y(rings, x, z, extra=0.0):
    return _shared._front_y(rings, x, z, extra)


def _make_torso_and_collar(garment, rest):
    rings = _spine_rings(rest)
    garment.shell(rings, "ivory", sides=40)

    # A narrow blue collar band sits below the neck and remains attached to the
    # same neck bones throughout the source animation.
    collar_z = _v(rest["lowerneck"]["tail"]).lerp(_v(rest["upperneck"]["tail"]), 0.78).z
    collar_center = Vector((0.0015, 0.004, collar_z))
    collar_points = [
        collar_center + Vector((0.057 * math.cos(2.0 * math.pi * i / 24),
                                0.050 * math.sin(2.0 * math.pi * i / 24), 0.0))
        for i in range(25)
    ]
    collar_weights = [{"lowerneck": 0.34, "upperneck": 0.66}] * len(collar_points)
    garment.tube(collar_points, [0.0045] * len(collar_points), collar_weights,
                 "blue_light", sides=8, steps_per_segment=1)

    # Two broad blue strips cross over the ivory body as a traditional wrap
    # collar. They taper toward the waist rather than forming a vest panel.
    top_z = min(0.263, _v(rest["thorax"]["tail"]).z + 0.016)
    low_z = _v(rest["root"]["head"]).z + 0.025
    for index, sign in enumerate((-1.0, 1.0)):
        positions = [
            (sign * 0.036, top_z),
            (sign * 0.050, top_z - 0.055),
            (-sign * 0.060, low_z + 0.075),
            (-sign * 0.108, low_z),
        ]
        anchors = []
        for x, z in positions:
            anchors.append((Vector((x, _front_y(rings, x, z, 0.010), z)),
                            _spine_weights_at(rings, z)))
        _ribbon_patch(garment, anchors, 0.040, "blue", rows=15, columns=9,
                      bulge=0.002, phase=index * 0.6, fold_amplitude=0.008)

    # A thin pale edge follows the outer diagonal of each wrap strip.
    for sign, phase in ((-1.0, 0.0), (1.0, 0.7)):
        seam = []
        for t, x, z in ((0.05, sign * 0.044, top_z - 0.004),
                        (0.38, sign * 0.046, top_z - 0.070),
                        (0.70, -sign * 0.048, low_z + 0.105),
                        (0.96, -sign * 0.091, low_z + 0.012)):
            seam.append(Vector((x, _front_y(rings, x, z, 0.014), z)))
        weights = [_spine_weights_at(rings, p.z) for p in seam]
        garment.tube(seam, [0.0023, 0.0020, 0.0018, 0.0012], weights,
                     "ivory_light", sides=6, steps_per_segment=3)

    return rings


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
    # Wide light sleeves follow the same arm chain as the source mesh.
    garment.tube(points,
                 [(0.087, 0.082), (0.102, 0.096), (0.094, 0.088),
                  (0.068, 0.065), (0.055, 0.052)],
                 weights, "ivory_light", sides=20, steps_per_segment=8)

    axis = _unit(wrist_end - forearm_end, (1.0, 0.0, 0.0))
    wrap_start = forearm_end - axis * 0.046
    wrap_points = [wrap_start, forearm_end, wrist_end]
    wrap_weights = [
        {side + "radius": 0.88, side + "wrist": 0.12},
        {side + "radius": 0.55, side + "wrist": 0.45},
        {side + "radius": 0.06, side + "wrist": 0.94},
    ]
    garment.tube(wrap_points, [(0.070, 0.067), (0.064, 0.061), (0.057, 0.054)],
                 wrap_weights, "blue_dark", sides=18, steps_per_segment=6)

    # Two quiet ochre bindings and one pale-blue edge make the wrapped cuff
    # legible without changing the source wrist or hand placement.
    hint = Vector((0.0, 0.0, 1.0))
    if abs(axis.dot(hint)) > 0.92:
        hint = Vector((0.0, 1.0, 0.0))
    axis_a = _unit(axis.cross(hint), (0.0, 1.0, 0.0))
    axis_b = _unit(axis.cross(axis_a), (0.0, 0.0, 1.0))
    for t, material in ((0.20, "gold"), (0.72, "gold"), (0.94, "blue_light")):
        center = wrap_start.lerp(wrist_end, t)
        radius_a = 0.067 - 0.010 * t
        radius_b = 0.064 - 0.010 * t
        loop = [center + axis_a * (radius_a * math.cos(2.0 * math.pi * i / 16))
                + axis_b * (radius_b * math.sin(2.0 * math.pi * i / 16))
                for i in range(17)]
        ring_weights = [_blend_weights(wrap_weights[0], wrap_weights[-1], t)] * len(loop)
        garment.tube(loop, [0.0018] * len(loop), ring_weights, material,
                     sides=6, steps_per_segment=1)


def _panel_weights(side, t):
    femur = side + "femur"
    thigh_blend = 0.12 + 0.86 * _smoothstep(0.0, 1.0, t)
    root_part = (1.0 - thigh_blend) * 0.76
    back_part = (1.0 - thigh_blend) * 0.24
    return {"root": root_part, "lowerback": back_part, femur: thigh_blend}


def _robe_panel(garment, rest, side, front, phase):
    root = _v(rest["root"]["head"])
    hip = _v(rest[side + "femur"]["head"])
    knee = _v(rest[side + "femur"]["tail"])
    sign = 1.0 if side == "l" else -1.0
    front_sign = -1.0 if front else 1.0
    hem_target = hip.lerp(knee, 0.97)
    top = root + Vector((sign * 0.018, 0.0, 0.030))
    material = "ivory_light" if front else "ivory"
    rows, columns = 21, 15

    def panel_point(t, u):
        center = top.lerp(hem_target, t)
        width = 0.132 + 0.036 * math.sin(math.pi * t) + 0.018 * t
        fold = math.cos((u * 3.0 + phase) * math.pi) * (0.0035 + 0.0025 * t)
        center_x = center.x + sign * 0.006 * math.sin(math.pi * t)
        x = center_x + u * width
        edge_flutter = 0.005 * math.sin((u * 2.0 + phase) * math.pi) * t
        z = center.z + edge_flutter
        y = hip.y + front_sign * (0.091 + 0.006 * t) + fold
        # A small overlap between the left and right panels forms a soft center
        # fold; fixed depth offsets prevent coplanar surfaces during playback.
        y += (-1.0 if side == "l" else 1.0) * (0.0025 if front else 0.0015)
        return Vector((x, y, z))

    def weights_at(t, _u):
        return _panel_weights(side, t)

    first = len(garment.vertices)
    garment.patch(rows, columns, panel_point, weights_at, material)
    _wash_patch(garment, first, rows, columns, amplitude=0.014, phase=phase)

    hem_points = [panel_point(1.0, u) + Vector((0.0, front_sign * 0.002, 0.0))
                  for u in (-1.0, -0.55, 0.0, 0.55, 1.0)]
    hem_weights = [weights_at(1.0, u) for u in (-1.0, -0.55, 0.0, 0.55, 1.0)]
    garment.tube(hem_points, [0.0026, 0.0024, 0.0022, 0.0024, 0.0020],
                 hem_weights, "blue_light", sides=6, steps_per_segment=3)

    # Fine outer seams suggest layered fabric and remain distributed over root
    # and thigh vertices, never adding or scaling a bone.
    for u in (-1.0, 1.0):
        seam = [panel_point(t, u) + Vector((0.0, front_sign * 0.0017, 0.0))
                for t in (0.03, 0.34, 0.68, 1.0)]
        seam_weights = [weights_at(t, u) for t in (0.03, 0.34, 0.68, 1.0)]
        garment.tube(seam, [0.0020, 0.0018, 0.0015, 0.0010], seam_weights,
                     "ivory_shadow", sides=5, steps_per_segment=3)


def _make_garments(garment, rest):
    _make_torso_and_collar(garment, rest)

    root = _v(rest["root"]["head"])
    # The blue sash is a cloth wrap around the waist, without a modern vest or
    # decorative rigid plate.
    garment.shell([
        {"center": root + Vector((0.0, 0.0, 0.018)), "rx": 0.144, "ry": 0.095,
         "weights": {"root": 0.76, "lowerback": 0.24}},
        {"center": root + Vector((0.0, 0.0, 0.034)), "rx": 0.148, "ry": 0.098,
         "weights": {"root": 0.70, "lowerback": 0.30}},
        {"center": root + Vector((0.0, 0.0, 0.056)), "rx": 0.143, "ry": 0.094,
         "weights": {"root": 0.42, "lowerback": 0.58}},
    ], "blue_dark", sides=36)
    garment.shell([
        {"center": root + Vector((0.0, 0.0, 0.057)), "rx": 0.144, "ry": 0.095,
         "weights": {"root": 0.40, "lowerback": 0.60}},
        {"center": root + Vector((0.0, 0.0, 0.064)), "rx": 0.142, "ry": 0.093,
         "weights": {"root": 0.35, "lowerback": 0.65}},
    ], "blue_light", sides=36)

    for side in ("l", "r"):
        _arm_sleeve(garment, rest, side)
    # Four broad, visibly separate front/back panels extend from the waist to
    # near the knees. Each panel follows the source root/thigh chain and keeps
    # subtle fixed folds rather than forming a rigid skirt.
    for front in (True, False):
        for side, phase in (("l", 0.15), ("r", 0.65)):
            _robe_panel(garment, rest, side, front, phase + (0.0 if front else 0.9))


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

        hand_start = _v(rest[side + "hand"]["head"])
        hand_end = _v(rest[side + "hand"]["tail"])
        fist = (hand_start + hand_end) * 0.5
        body.ellipsoid(fist, (0.040, 0.040, 0.040), "skin_light", {side + "hand": 1.0},
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


def _jaw_factor(nz):
    lower = max(0.0, (-float(nz) - 0.36) / 0.64)
    return 1.0 - 0.22 * (lower ** 0.88)


def _face_surface_y(center, radii, x, z):
    nz = _clamp((float(z) - center.z) / radii.z, -0.98, 0.98)
    x_radius = radii.x * _jaw_factor(nz)
    nx = _clamp((float(x) - center.x) / x_radius, -0.96, 0.96)
    depth = math.sqrt(max(0.05, 1.0 - nx * nx - nz * nz))
    return center.y - radii.y * depth


def _make_face(face, rest):
    head_center = _v(rest["head"]["head"]) + Vector((0.0, 0.0, 0.060))
    head_weights = {"head": 1.0}
    radii = Vector((0.20, 0.17, 0.23))
    segments, rings = 44, 30
    vertices = [head_center + Vector((0.0, 0.0, radii.z))]
    for row in range(1, rings):
        phi = math.pi * row / rings
        nz = math.cos(phi)
        jaw = _jaw_factor(nz)
        for column in range(segments):
            theta = 2.0 * math.pi * column / segments
            vertices.append(head_center + Vector((radii.x * jaw * math.sin(phi) * math.cos(theta),
                                                   radii.y * math.sin(phi) * math.sin(theta),
                                                   radii.z * nz)))
    bottom = len(vertices)
    vertices.append(head_center + Vector((0.0, 0.0, -radii.z)))
    faces = []
    for column in range(segments):
        faces.append((0, 1 + column, 1 + (column + 1) % segments))
    for row in range(rings - 2):
        upper = 1 + row * segments
        lower = upper + segments
        for column in range(segments):
            nxt = (column + 1) % segments
            faces.append((upper + column, lower + column, lower + nxt, upper + nxt))
    last = 1 + (rings - 2) * segments
    for column in range(segments):
        faces.append((last + column, bottom, last + (column + 1) % segments))

    first = len(face.vertices)
    face.add(vertices, faces, "skin", head_weights)
    base_skin = _shared.PALETTE["skin"]
    light_skin = _shared.PALETTE["skin_light"]
    for index, point in enumerate(vertices):
        local = point - head_center
        front = _clamp((-local.y - 0.018) / 0.115)
        cheek = 0.0
        for sign in (-1.0, 1.0):
            dx = (local.x - sign * 0.105) / 0.034
            dz = (local.z + 0.052) / 0.026
            cheek = max(cheek, math.exp(-0.5 * (dx * dx + dz * dz)) * front)
        color = face.colors[first + index]
        warmed = []
        for channel in range(3):
            value = color[channel] * (1.0 - 0.24 * front) + light_skin[channel] * (0.24 * front)
            if channel == 0:
                value += 0.022 * cheek
            elif channel == 1:
                value += 0.004 * cheek
            else:
                value -= 0.002 * cheek
            warmed.append(_clamp(value))
        face.colors[first + index] = tuple(warmed) + (color[3],)

    for sign in (-1.0, 1.0):
        ear = head_center + Vector((sign * 0.190, 0.006, -0.014))
        face.ellipsoid(ear, (0.034, 0.027, 0.048), "skin", head_weights,
                       segments=16, rings=10)
        face.ellipsoid(ear + Vector((0.0, -0.022, 0.0)), (0.014, 0.007, 0.026),
                       "skin_light", head_weights, segments=12, rings=8)

        eye_x = sign * 0.078
        eye_z = head_center.z + 0.038
        eye_y = _face_surface_y(head_center, radii, eye_x, eye_z) - 0.003
        face.ellipsoid((eye_x, eye_y, eye_z), (0.043, 0.014, 0.056),
                       "eye_white", head_weights, segments=22, rings=15)
        iris_x = eye_x + sign * 0.001
        iris_y = eye_y - 0.014
        iris_z = eye_z - 0.005
        face.ellipsoid((iris_x, iris_y, iris_z), (0.024, 0.010, 0.036),
                       "iris", head_weights, segments=18, rings=12)
        face.ellipsoid((iris_x, iris_y - 0.008, iris_z - 0.001), (0.012, 0.006, 0.026),
                       "pupil", head_weights, segments=16, rings=10)
        face.ellipsoid((iris_x - 0.004, iris_y - 0.015, iris_z + 0.014),
                       (0.0055, 0.004, 0.008), "glint", head_weights,
                       segments=10, rings=7)

        # Fine upper lashes sit against the white eye and remain much thinner
        # than the large iris/pupil shapes.
        lash = []
        for offset_x, offset_z in ((-0.043, 0.030), (-0.026, 0.040),
                                   (0.0, 0.043), (0.027, 0.039), (0.043, 0.028)):
            x = eye_x + offset_x
            z = eye_z + offset_z
            lash.append(Vector((x, eye_y - 0.012, z)))
        face.tube(lash, [0.0012, 0.0021, 0.0025, 0.0020, 0.0010],
                  [head_weights] * len(lash), "hair", sides=6, steps_per_segment=2)

        brow = []
        for offset_x, offset_z in ((-0.036, 0.087), (-0.006, 0.098), (0.028, 0.091)):
            x = eye_x + offset_x
            z = eye_z + offset_z
            brow.append(Vector((x, _face_surface_y(head_center, radii, x, z) - 0.006, z)))
        face.tube(brow, [0.0030, 0.0040, 0.0022], [head_weights] * 3,
                  "hair_mid", sides=7, steps_per_segment=3)

    nose_z = head_center.z - 0.008
    nose_y = _face_surface_y(head_center, radii, 0.0, nose_z) - 0.004
    face.ellipsoid((0.0, nose_y, nose_z), (0.008, 0.006, 0.008),
                   "skin_light", head_weights, segments=12, rings=8)

    # A tiny nearly level line gives a quiet, neutral expression.
    mouth = []
    for x, dz in ((-0.014, -0.087), (0.0, -0.088), (0.014, -0.087)):
        z = head_center.z + dz
        mouth.append(Vector((x, _face_surface_y(head_center, radii, x, z) - 0.003, z)))
    face.tube(mouth, [0.0015, 0.0017, 0.0013], [head_weights] * len(mouth),
              "hair_mid", sides=6, steps_per_segment=2)
    return head_center, radii


def _make_hair(hair, head_center):
    head_weights = {"head": 1.0}
    # Close-fitting crown and occipital volumes leave room for a distinct high
    # tail, avoiding the small-bun silhouette of the earlier simplified model.
    hair.ellipsoid(head_center + Vector((0.0, 0.018, 0.120)),
                   (0.202, 0.174, 0.137), "hair", head_weights,
                   segments=34, rings=22)
    hair.ellipsoid(head_center + Vector((0.0, 0.066, 0.018)),
                   (0.177, 0.112, 0.139), "hair_mid", head_weights,
                   segments=28, rings=18)

    # Swept forehead locks are separate, tapered volumes with light fixed
    # strand accents; they do not rely on a frame-dependent noise texture.
    fringe_paths = [
        [(-0.135, -0.060, 0.192), (-0.110, -0.115, 0.153), (-0.084, -0.158, 0.092), (-0.052, -0.161, 0.056)],
        [(-0.060, -0.078, 0.204), (-0.032, -0.131, 0.161), (-0.018, -0.166, 0.094), (0.006, -0.159, 0.061)],
        [(0.018, -0.074, 0.205), (0.050, -0.127, 0.165), (0.070, -0.161, 0.112), (0.048, -0.157, 0.070)],
        [(0.102, -0.054, 0.183), (0.131, -0.111, 0.140), (0.146, -0.145, 0.083), (0.126, -0.132, 0.045)],
    ]
    for index, path in enumerate(fringe_paths):
        points = [head_center + Vector(item) for item in path]
        radii = [0.030, 0.027, 0.022, 0.009]
        material = "hair_mid" if index in (1, 2) else "hair"
        hair.tube(points, radii, [head_weights] * len(points), material,
                  sides=12, steps_per_segment=4)
        if index in (0, 2):
            highlight = [point + Vector((0.0, -0.018, 0.006)) for point in points[1:]]
            hair.tube(highlight, [0.0055, 0.0040, 0.0012], [head_weights] * 3,
                      "hair_light", sides=7, steps_per_segment=3)

    for sign in (-1.0, 1.0):
        side_paths = [
            [(sign * 0.145, -0.082, 0.132), (sign * 0.178, -0.103, 0.065),
             (sign * 0.186, -0.068, -0.024), (sign * 0.164, 0.006, -0.108)],
            [(sign * 0.163, -0.024, 0.098), (sign * 0.193, -0.010, 0.016),
             (sign * 0.182, 0.028, -0.060), (sign * 0.144, 0.062, -0.126)],
        ]
        for index, path in enumerate(side_paths):
            points = [head_center + Vector(item) for item in path]
            hair.tube(points, [0.034, 0.029, 0.020, 0.007], [head_weights] * 4,
                      "hair" if index == 0 else "hair_mid", sides=11, steps_per_segment=4)

    tie = head_center + Vector((0.0, 0.122, 0.139))
    hair.ellipsoid(tie, (0.028, 0.025, 0.025), "hair_mid", head_weights,
                   segments=14, rings=9)

    # Four separated swept locks make one long high ponytail. The strand ends
    # reach shoulder height (about 0.15 m below the face centre in this rest pose).
    pony_paths = [
        [(0.000, 0.122, 0.139), (0.004, 0.190, 0.217), (0.020, 0.248, 0.198),
         (0.038, 0.282, 0.112), (0.047, 0.296, 0.018), (0.040, 0.278, -0.078), (0.025, 0.239, -0.151)],
        [(-0.016, 0.120, 0.136), (-0.052, 0.188, 0.207), (-0.080, 0.249, 0.174),
         (-0.103, 0.284, 0.086), (-0.115, 0.292, -0.013), (-0.105, 0.269, -0.105), (-0.080, 0.231, -0.157)],
        [(0.016, 0.119, 0.141), (0.049, 0.192, 0.219), (0.079, 0.257, 0.192),
         (0.105, 0.296, 0.106), (0.119, 0.307, 0.020), (0.110, 0.286, -0.070), (0.086, 0.247, -0.149)],
        [(-0.006, 0.125, 0.132), (-0.022, 0.202, 0.204), (-0.036, 0.270, 0.155),
         (-0.047, 0.310, 0.066), (-0.050, 0.319, -0.023), (-0.039, 0.296, -0.105), (-0.018, 0.255, -0.153)],
    ]
    pony_radii = [(0.047, 0.043), (0.052, 0.045), (0.047, 0.040),
                  (0.038, 0.033), (0.029, 0.025), (0.019, 0.016), (0.0035, 0.0030)]
    for index, path in enumerate(pony_paths):
        points = [head_center + Vector(item) for item in path]
        material = "hair" if index in (0, 3) else "hair_mid"
        hair.tube(points, pony_radii, [head_weights] * len(points), material,
                  sides=14, steps_per_segment=4)
        # Narrow warm-brown strands sit on the front-facing side of the locks.
        accent = [point + Vector((0.0, -0.024, 0.003)) for point in points[1:-1]]
        hair.tube(accent, [0.0060, 0.0050, 0.0040, 0.0030, 0.0010],
                  [head_weights] * len(accent), "hair_light" if index == 2 else "hair_mid",
                  sides=7, steps_per_segment=3)

    # Broad, flat pale-blue fabric loops sit at the high tie.
    bow_tie = tie + Vector((0.0, -0.012, 0.0))
    hair.ellipsoid(bow_tie, (0.027, 0.010, 0.022), "blue_light", head_weights,
                   segments=16, rings=10)
    for sign in (-1.0, 1.0):
        bow_anchors = []
        for t in (0.0, 0.33, 0.70, 1.0):
            x = sign * (0.018 + 0.090 * t)
            z = 0.002 * math.sin(math.pi * t)
            point = bow_tie + Vector((x, -0.003 * math.sin(math.pi * t), z))
            bow_anchors.append((point, head_weights))
        _ribbon_patch(hair, bow_anchors, 0.040, "blue_light", rows=11, columns=9,
                      bulge=0.0018, phase=sign * 0.2, fold_amplitude=0.009)

    ribbon_paths = [
        [(0.0, 0.120, 0.137), (-0.045, 0.186, 0.093), (-0.105, 0.229, 0.012),
         (-0.137, 0.254, -0.092), (-0.119, 0.239, -0.182)],
        [(0.010, 0.123, 0.132), (0.055, 0.192, 0.082), (0.091, 0.241, -0.016),
         (0.084, 0.264, -0.119), (0.050, 0.252, -0.222)],
    ]
    for index, path in enumerate(ribbon_paths):
        anchors = [(head_center + Vector(item), head_weights) for item in path]
        _ribbon_patch(hair, anchors, 0.023 if index == 0 else 0.020, "blue_light",
                      rows=16, columns=7, bulge=0.0014, phase=0.3 * index,
                      fold_amplitude=0.012)



def _apply_reference_textures(objects):
    """Map opaque cloth/hair regions of the unchanged approved art onto volumes.

    UVs and original pixels travel inside GLB; no image synthesis, camera-facing
    face card, per-frame replacement, or new raster texture is made here.
    """
    source = Path(__file__).resolve().parents[2] / "assets/art/v2/jiang-yanqiu-v2.png"
    image = bpy.data.images.load(str(source), check_existing=True)
    image.name = "JiangApprovedPaint"
    image.colorspace_settings.name = "sRGB"
    regions = {
        "ivory": (210, 1060, 315, 1125),
        "ivory_light": (210, 1060, 315, 1125),
        "blue": (540, 1000, 600, 1070),
        "blue_dark": (900, 1040, 960, 1100),
        "blue_light": (277, 475, 297, 510),
        "hair": (700, 375, 800, 465),
        "hair_mid": (700, 375, 800, 465),
        "hair_light": (700, 375, 800, 465),
    }
    used = {}
    for obj in objects:
        if obj.name not in ("JiangGarment", "JiangHair"):
            continue
        mesh = obj.data
        uv = mesh.uv_layers.new(name="OriginalPaintUV")
        wash = mesh.color_attributes.get("JiangWash")
        xs = [v.co.x for v in mesh.vertices]
        zs = [v.co.z for v in mesh.vertices]
        xmin, xmax, zmin, zmax = min(xs), max(xs), min(zs), max(zs)
        material_regions = {}
        for index, material in enumerate(mesh.materials):
            key = material.name.removeprefix("Jiang_" + obj.name.removeprefix("Jiang") + "_")
            if key not in regions:
                continue
            box = regions[key]
            material_regions[index] = box
            nodes = material.node_tree.nodes
            shader = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
            for link in list(shader.inputs["Base Color"].links):
                material.node_tree.links.remove(link)
            texture = nodes.new("ShaderNodeTexImage")
            texture.image = image
            texture.interpolation = "Linear"
            texture.extension = "EXTEND"
            material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
            used[material.name] = list(box)
        for polygon in mesh.polygons:
            box = material_regions.get(polygon.material_index)
            if box is None:
                continue
            x0, y0, x1, y1 = box
            for loop_index in polygon.loop_indices:
                point = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                u = _clamp((point.x - xmin) / max(1e-8, xmax - xmin))
                v = _clamp((point.z - zmin) / max(1e-8, zmax - zmin))
                uv.data[loop_index].uv = ((x0 + u * (x1 - x0)) / image.size[0],
                                          1.0 - (y1 - v * (y1 - y0)) / image.size[1])
                # COLOR_0 multiplies base color in glTF: keep it white where the
                # unchanged painting supplies the actual surface colors.
                wash.data[loop_index].color = (1.0, 1.0, 1.0, 1.0)
    return {"source": "assets/art/v2/jiang-yanqiu-v2.png", "regions_top_left_px": used,
            "method": "Original opaque artwork patches mapped by fixed rest-space UVs; original image unchanged"}


def build_character(armature, rest) -> dict:
    """Build the legacy-styled character over an existing CMU 31-bone rig.

    The interface and receipt shape match ``character.build_character``. This
    builder creates four weighted meshes and does not change bones, hand
    midpoints, proportions, animation timing, or object transforms.
    """
    _shared._require_rest(rest, armature)
    body = _WeightedMesh("Body")
    garment = _WeightedMesh("Garment")
    face = _WeightedMesh("Face")
    hair = _WeightedMesh("Hair")

    _make_body(body, rest)
    _make_garments(garment, rest)
    head_center, face_radii = _make_face(face, rest)
    _make_hair(hair, head_center)

    builders = [body, garment, face, hair]
    vertex_count = sum(len(builder.vertices) for builder in builders)
    if vertex_count > MAX_BASE_VERTICES:
        raise ValueError("Legacy Jiang character exceeds base vertex budget: {} > {}".format(
            vertex_count, MAX_BASE_VERTICES))
    objects = [builder.object("Jiang" + builder.part, armature) for builder in builders]
    paint = _apply_reference_textures(objects)
    all_weights = [item for builder in builders for item in builder.weights]
    max_influences = max((len(item) for item in all_weights), default=0)
    max_sum_error = max((abs(sum(item.values()) - 1.0) for item in all_weights), default=0.0)
    per_object = {}
    for builder in builders:
        per_object["Jiang" + builder.part] = {
            "vertex_count": len(builder.vertices),
            "max_influences": max(len(item) for item in builder.weights),
            "max_weight_sum_error": max(abs(sum(item.values()) - 1.0)
                                         for item in builder.weights),
        }

    left_fist = (_v(rest["lhand"]["head"]) + _v(rest["lhand"]["tail"])) * 0.5
    right_fist = (_v(rest["rhand"]["head"]) + _v(rest["rhand"]["tail"])) * 0.5
    return {
        "objects": [obj.name for obj in objects],
        "vertex_count": vertex_count,
        "reference_paint": paint,
        "identity": {
            "name": "江砚秋",
            "reference": "assets/art/v2/jiang-yanqiu-v2.png",
            "interpretation": "Original volumetric reading with warm light skin, larger brown eyes, layered swept hair, a long high ponytail, pale-blue fabric ribbons, and a knee-length ivory/blue wrap robe.",
            "coordinate_system": "Blender Z-up; face -Y; character left +X",
            "face_center_m": [float(value) for value in head_center],
            "face_radii_m": [float(value) for value in face_radii],
            "high_ponytail": True,
            "robe_panels_reach_near_knee": True,
        },
        "landmarks": {
            "closed_fist_centers_m": {
                "left": [float(value) for value in left_fist],
                "right": [float(value) for value in right_fist],
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
