"""Build a local-coordinate five-digit Jiang Yanqiu sword grip in Blender."""
from __future__ import annotations

import math
from typing import Any


def build_grip(name: str, skin_material: Any, scale: float = 1.0) -> tuple[Any, Any, dict[str, Any]]:
    """Create and link a closed hand and one straight jian, both at identity.

    The returned objects contain vertices in the supplied local grip frame;
    root may place, parent, or weight them later. The sword axis is local +Z,
    the palm sits behind its handle at +Y, and the wrist attachment point is
    ``(0, .067 * scale, 0)``. ``skin_material`` is assigned to the whole hand.

    This function creates only its two mesh objects and four sword materials in
    the active collection. It does not clear, save, render, or otherwise reset
    the current Blender scene.
    """
    import bmesh
    import bpy
    from mathutils import Vector

    if not isinstance(name, str) or not name.strip():
        raise ValueError("name must be a non-empty string")
    if skin_material is None:
        raise ValueError("skin_material is required")
    uniform_scale = float(scale)
    if not math.isfinite(uniform_scale) or uniform_scale <= 0.0:
        raise ValueError("scale must be finite and positive")

    class MeshBuilder:
        def __init__(self) -> None:
            self.vertices: list[tuple[float, float, float]] = []
            self.faces: list[tuple[int, ...]] = []
            self.material_indices: list[int] = []
            self.smooth_flags: list[bool] = []

        def add(
            self,
            vertices: list[Vector],
            faces: list[tuple[int, ...]],
            material_index: int,
            smooth: bool = True,
            material_indices: list[int] | None = None,
            smooth_flags: list[bool] | None = None,
        ) -> None:
            offset = len(self.vertices)
            for point in vertices:
                self.vertices.append(tuple(float(component) * uniform_scale for component in point))
            self.faces.extend(tuple(offset + int(index) for index in face) for face in faces)
            if material_indices is None:
                self.material_indices.extend([material_index] * len(faces))
            else:
                if len(material_indices) != len(faces):
                    raise ValueError("material_indices must match the number of faces")
                self.material_indices.extend(material_indices)
            if smooth_flags is None:
                self.smooth_flags.extend([smooth] * len(faces))
            else:
                if len(smooth_flags) != len(faces):
                    raise ValueError("smooth_flags must match the number of faces")
                self.smooth_flags.extend(smooth_flags)

    def signed_power(value: float, exponent: float) -> float:
        return math.copysign(abs(value) ** exponent, value)

    def add_superellipsoid(
        builder: MeshBuilder,
        center: tuple[float, float, float],
        extents: tuple[float, float, float],
        material_index: int,
        exponent: float = 0.76,
        latitude_steps: int = 20,
        longitude_steps: int = 32,
    ) -> None:
        cx, cy, cz = center
        rx, ry, rz = extents
        vertices = [Vector((cx, cy, cz - rz))]
        ring_indices: list[list[int]] = []
        for latitude in range(1, latitude_steps):
            angle = -math.pi / 2.0 + math.pi * latitude / latitude_steps
            vertical = signed_power(math.sin(angle), exponent)
            horizontal = abs(math.cos(angle)) ** exponent
            row = []
            for longitude in range(longitude_steps):
                around = math.tau * longitude / longitude_steps
                x = signed_power(math.cos(around), exponent)
                y = signed_power(math.sin(around), exponent)
                row.append(len(vertices))
                vertices.append(Vector((cx + rx * horizontal * x,
                                        cy + ry * horizontal * y,
                                        cz + rz * vertical)))
            ring_indices.append(row)
        top_index = len(vertices)
        vertices.append(Vector((cx, cy, cz + rz)))

        faces: list[tuple[int, ...]] = []
        first = ring_indices[0]
        for column in range(longitude_steps):
            nxt = (column + 1) % longitude_steps
            faces.append((0, first[nxt], first[column]))
        for lower, upper in zip(ring_indices, ring_indices[1:]):
            for column in range(longitude_steps):
                nxt = (column + 1) % longitude_steps
                faces.append((lower[column], lower[nxt], upper[nxt], upper[column]))
        last = ring_indices[-1]
        for column in range(longitude_steps):
            nxt = (column + 1) % longitude_steps
            faces.append((last[column], last[nxt], top_index))
        builder.add(vertices, faces, material_index, smooth=True)

    def add_wrist(builder: MeshBuilder, material_index: int) -> None:
        # Elliptical rings taper to the specified forearm attachment plane.
        profile = (
            (0.032, 0.030, 0.036),
            (0.042, 0.027, 0.032),
            (0.052, 0.022, 0.026),
            (0.061, 0.018, 0.020),
            (0.067, 0.014, 0.015),
        )
        sides = 24
        vertices: list[Vector] = []
        rings: list[list[int]] = []
        for y, radius_x, radius_z in profile:
            ring = []
            for side in range(sides):
                angle = math.tau * side / sides
                ring.append(len(vertices))
                vertices.append(Vector((radius_x * math.cos(angle), y,
                                        radius_z * math.sin(angle))))
            rings.append(ring)
        faces: list[tuple[int, ...]] = []
        for lower, upper in zip(rings, rings[1:]):
            for side in range(sides):
                nxt = (side + 1) % sides
                faces.append((lower[side], lower[nxt], upper[nxt], upper[side]))
        bottom_center = len(vertices)
        vertices.append(Vector((0.0, profile[0][0], 0.0)))
        top_center = len(vertices)
        vertices.append(Vector((0.0, profile[-1][0], 0.0)))
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((bottom_center, rings[0][nxt], rings[0][side]))
            faces.append((top_center, rings[-1][side], rings[-1][nxt]))
        builder.add(vertices, faces, material_index, smooth=True)

    def catmull_rom(a: Vector, b: Vector, c: Vector, d: Vector, t: float) -> Vector:
        return 0.5 * (
            (2.0 * b)
            + (-a + c) * t
            + (2.0 * a - 5.0 * b + 4.0 * c - d) * (t * t)
            + (-a + 3.0 * b - 3.0 * c + d) * (t * t * t)
        )

    def sample_path(
        control_points: list[tuple[float, float, float]],
        radii: list[float],
        steps_per_span: int = 8,
    ) -> list[tuple[Vector, float]]:
        if len(control_points) != len(radii) or len(control_points) < 2:
            raise ValueError("A swept path needs matching point and radius lists")
        points = [Vector(point) for point in control_points]
        samples: list[tuple[Vector, float]] = []
        for span in range(len(points) - 1):
            a = points[max(0, span - 1)]
            b = points[span]
            c = points[span + 1]
            d = points[min(len(points) - 1, span + 2)]
            for step in range(steps_per_span):
                t = step / steps_per_span
                position = catmull_rom(a, b, c, d, t)
                radius = radii[span] * (1.0 - t) + radii[span + 1] * t
                samples.append((position, radius))
        samples.append((points[-1], radii[-1]))
        return samples

    def add_swept_tube(
        builder: MeshBuilder,
        control_points: list[tuple[float, float, float]],
        radii: list[float],
        material_index: int,
        reference_axis: tuple[float, float, float] = (0.0, 0.0, 1.0),
        depth_scale: float = 0.88,
        sides: int = 16,
    ) -> None:
        samples = sample_path(control_points, radii)
        tangents: list[Vector] = []
        for index, (point, _) in enumerate(samples):
            previous = samples[max(0, index - 1)][0]
            following = samples[min(len(samples) - 1, index + 1)][0]
            tangent = following - previous
            if tangent.length < 1.0e-8:
                raise ValueError("Swept path contains a degenerate tangent")
            tangents.append(tangent.normalized())

        reference = Vector(reference_axis).normalized()
        first_point, first_radius = samples[0]
        last_point, last_radius = samples[-1]
        first_tangent = tangents[0]
        last_tangent = tangents[-1]
        # Two hemisphere rings at each end make the curved digits rounded rather
        # than ending as flat-cut tubes.
        rows: list[tuple[Vector, float, Vector]] = [
            (first_point - first_tangent * first_radius * 0.8660254038,
             first_radius * 0.5, first_tangent),
            (first_point - first_tangent * first_radius * 0.5,
             first_radius * 0.8660254038, first_tangent),
        ]
        rows.extend((point, radius, tangents[index]) for index, (point, radius) in enumerate(samples))
        rows.extend((
            (last_point + last_tangent * last_radius * 0.5,
             last_radius * 0.8660254038, last_tangent),
            (last_point + last_tangent * last_radius * 0.8660254038,
             last_radius * 0.5, last_tangent),
        ))

        vertices: list[Vector] = []
        rings: list[list[int]] = []
        for center, radius, tangent in rows:
            normal = tangent.cross(reference)
            if normal.length < 1.0e-7:
                normal = tangent.cross(Vector((1.0, 0.0, 0.0)))
            if normal.length < 1.0e-7:
                normal = tangent.cross(Vector((0.0, 1.0, 0.0)))
            normal.normalize()
            binormal = tangent.cross(normal).normalized()
            ring = []
            for side in range(sides):
                angle = math.tau * side / sides
                ring.append(len(vertices))
                vertices.append(center
                                + normal * (radius * math.cos(angle))
                                + binormal * (radius * depth_scale * math.sin(angle)))
            rings.append(ring)

        start_pole = len(vertices)
        vertices.append(first_point - first_tangent * first_radius)
        end_pole = len(vertices)
        vertices.append(last_point + last_tangent * last_radius)
        faces: list[tuple[int, ...]] = []
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((start_pole, rings[0][nxt], rings[0][side]))
        for lower, upper in zip(rings, rings[1:]):
            for side in range(sides):
                nxt = (side + 1) % sides
                faces.append((lower[side], lower[nxt], upper[nxt], upper[side]))
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((rings[-1][side], rings[-1][nxt], end_pole))
        builder.add(vertices, faces, material_index, smooth=True)

    def add_cylinder_z(
        builder: MeshBuilder,
        radius: float,
        z_min: float,
        z_max: float,
        material_index: int,
        sides: int = 24,
    ) -> None:
        vertices: list[Vector] = []
        for z in (z_min, z_max):
            for side in range(sides):
                angle = math.tau * side / sides
                vertices.append(Vector((radius * math.cos(angle), radius * math.sin(angle), z)))
        bottom_center = len(vertices)
        vertices.append(Vector((0.0, 0.0, z_min)))
        top_center = len(vertices)
        vertices.append(Vector((0.0, 0.0, z_max)))
        faces: list[tuple[int, ...]] = []
        smooth_flags: list[bool] = []
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((side, nxt, sides + nxt, sides + side))
            smooth_flags.append(True)
        for side in range(sides):
            nxt = (side + 1) % sides
            faces.append((bottom_center, nxt, side))
            smooth_flags.append(False)
            faces.append((top_center, sides + side, sides + nxt))
            smooth_flags.append(False)
        builder.add(vertices, faces, material_index, smooth_flags=smooth_flags)

    def make_material(
        material_name: str,
        rgba: tuple[float, float, float, float],
        roughness: float,
        metallic: float = 0.0,
    ) -> Any:
        material = bpy.data.materials.new(material_name)
        material.diffuse_color = rgba
        material.use_nodes = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        if shader is None:
            shader = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        shader.inputs["Base Color"].default_value = rgba
        shader.inputs["Roughness"].default_value = roughness
        shader.inputs["Metallic"].default_value = metallic
        return material

    def make_handle_material(material_name: str) -> Any:
        material = make_material(material_name, (0.025, 0.065, 0.13, 1.0), 0.62)
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        shader = nodes.get("Principled BSDF")
        coordinates = nodes.new("ShaderNodeTexCoord")
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 110.0
        noise.inputs["Detail"].default_value = 2.0
        noise.inputs["Roughness"].default_value = 0.7
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (0.014, 0.036, 0.078, 1.0)
        ramp.color_ramp.elements[1].color = (0.045, 0.105, 0.19, 1.0)
        links.new(coordinates.outputs["Generated"], noise.inputs["Vector"])
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.12
        bump.inputs["Distance"].default_value = 0.00025
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], shader.inputs["Normal"])
        return material

    def make_object(object_name: str, builder: MeshBuilder, materials: list[Any]) -> Any:
        if not builder.vertices or not builder.faces:
            raise ValueError(f"Refusing to create empty mesh {object_name}")
        data = bpy.data.meshes.new(object_name + "Mesh")
        data.from_pydata(builder.vertices, [], builder.faces)
        for material in materials:
            data.materials.append(material)
        data.update()
        if len(data.polygons) != len(builder.faces):
            raise RuntimeError(f"Unexpected polygon count while building {object_name}")
        for polygon, material_index in zip(data.polygons, builder.material_indices):
            polygon.material_index = material_index

        bm = bmesh.new()
        try:
            bm.from_mesh(data)
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            bm.to_mesh(data)
        finally:
            bm.free()
        data.update()
        if len(data.polygons) != len(builder.smooth_flags):
            raise RuntimeError(f"Normal recalculation changed polygon count for {object_name}")
        for polygon, smooth in zip(data.polygons, builder.smooth_flags):
            polygon.use_smooth = smooth

        obj = bpy.data.objects.new(object_name, data)
        bpy.context.collection.objects.link(obj)
        obj.location = (0.0, 0.0, 0.0)
        obj.rotation_euler = (0.0, 0.0, 0.0)
        obj.scale = (1.0, 1.0, 1.0)
        return obj

    def bounds(obj: Any) -> dict[str, list[float]]:
        coordinates = [[float(component) for component in vertex.co] for vertex in obj.data.vertices]
        return {
            "min": [min(point[axis] for point in coordinates) for axis in range(3)],
            "max": [max(point[axis] for point in coordinates) for axis in range(3)],
        }

    # The palm and wrist overlap to form a soft transition; digits are swept
    # tapered tubes whose centerlines curl around, rather than stop at, the hilt.
    hand_builder = MeshBuilder()
    add_superellipsoid(
        hand_builder,
        center=(0.0, 0.028, 0.0),
        extents=(0.038, 0.020, 0.047),
        material_index=0,
        exponent=0.76,
        latitude_steps=24,
        longitude_steps=40,
    )
    add_wrist(hand_builder, material_index=0)
    finger_rows = (-0.028, -0.009, 0.010, 0.029)
    finger_path = ((0.034, 0.015), (0.035, -0.012), (0.010, -0.028), (-0.016, -0.017))
    for row in finger_rows:
        add_swept_tube(
            hand_builder,
            [(x, y, row) for x, y in finger_path],
            [0.010, 0.011, 0.010, 0.008],
            material_index=0,
            reference_axis=(0.0, 0.0, 1.0),
            depth_scale=0.88,
            sides=18,
        )
    add_swept_tube(
        hand_builder,
        [(-0.033, 0.035, 0.030), (-0.040, 0.006, 0.028),
         (-0.018, -0.029, 0.019), (0.004, -0.031, 0.007)],
        [0.012, 0.011, 0.010, 0.009],
        material_index=0,
        reference_axis=(0.0, 0.0, 1.0),
        depth_scale=0.88,
        sides=18,
    )
    hand = make_object(f"{name}_HandGrip", hand_builder, [skin_material])

    handle_material = make_handle_material(f"{name}_DarkBlueHandleWrap")
    steel_material = make_material(f"{name}_JianSteel", (0.58, 0.66, 0.69, 1.0), 0.28, 0.72)
    edge_material = make_material(f"{name}_JianEdge", (0.35, 0.43, 0.46, 1.0), 0.33, 0.68)
    brass_material = make_material(f"{name}_RestrainedBrass", (0.48, 0.34, 0.14, 1.0), 0.34, 0.62)
    sword_builder = MeshBuilder()
    HANDLE_SLOT, STEEL_SLOT, EDGE_SLOT, BRASS_SLOT = range(4)

    add_cylinder_z(sword_builder, 0.011, -0.070, 0.070, HANDLE_SLOT, sides=28)
    add_superellipsoid(
        sword_builder,
        center=(0.0, 0.0, -0.085),
        extents=(0.013, 0.013, 0.012),
        material_index=BRASS_SLOT,
        exponent=1.0,
        latitude_steps=12,
        longitude_steps=20,
    )
    add_swept_tube(
        sword_builder,
        [(-0.075, 0.0, 0.081), (0.0, 0.0, 0.081), (0.075, 0.0, 0.081)],
        [0.0045, 0.0045, 0.0045],
        STEEL_SLOT,
        reference_axis=(0.0, 1.0, 0.0),
        depth_scale=1.0,
        sides=16,
    )
    add_superellipsoid(
        sword_builder,
        center=(-0.075, 0.0, 0.081),
        extents=(0.005, 0.0055, 0.0055),
        material_index=BRASS_SLOT,
        exponent=1.0,
        latitude_steps=8,
        longitude_steps=16,
    )
    add_superellipsoid(
        sword_builder,
        center=(0.075, 0.0, 0.081),
        extents=(0.005, 0.0055, 0.0055),
        material_index=BRASS_SLOT,
        exponent=1.0,
        latitude_steps=8,
        longitude_steps=16,
    )

    # A four-face diamond section keeps a straight center ridge and gives the
    # two narrow edge facets their own restrained steel material.
    blade_stations = (
        (0.092, 0.042, 0.0050),
        (0.250, 0.039, 0.0048),
        (0.520, 0.032, 0.0042),
        (0.730, 0.025, 0.0036),
    )
    blade_vertices: list[Vector] = []
    blade_rings: list[list[int]] = []
    for z, width, thickness in blade_stations:
        half_width = width * 0.5
        half_thickness = thickness * 0.5
        ring = []
        for point in ((-half_width, 0.0, z), (0.0, -half_thickness, z),
                      (half_width, 0.0, z), (0.0, half_thickness, z)):
            ring.append(len(blade_vertices))
            blade_vertices.append(Vector(point))
        blade_rings.append(ring)
    blade_faces: list[tuple[int, ...]] = [tuple(blade_rings[0])]
    blade_materials: list[int] = [STEEL_SLOT]
    blade_smooth: list[bool] = [False]
    for lower, upper in zip(blade_rings, blade_rings[1:]):
        for side in range(4):
            nxt = (side + 1) % 4
            blade_faces.append((lower[side], lower[nxt], upper[nxt], upper[side]))
            blade_materials.append(EDGE_SLOT if side in (0, 2) else STEEL_SLOT)
            blade_smooth.append(False)
    tip_index = len(blade_vertices)
    blade_vertices.append(Vector((0.0, 0.0, 0.830)))
    for side in range(4):
        nxt = (side + 1) % 4
        blade_faces.append((blade_rings[-1][side], blade_rings[-1][nxt], tip_index))
        blade_materials.append(EDGE_SLOT if side in (0, 2) else STEEL_SLOT)
        blade_smooth.append(False)
    sword_builder.add(
        blade_vertices,
        blade_faces,
        STEEL_SLOT,
        material_indices=blade_materials,
        smooth_flags=blade_smooth,
    )

    sword = make_object(
        f"{name}_Jian",
        sword_builder,
        [handle_material, steel_material, edge_material, brass_material],
    )

    metadata = {
        "grip_center": [0.0, 0.0, 0.0],
        "wrist_anchor": [0.0, 0.067 * uniform_scale, 0.0],
        "sword_axis": [0.0, 0.0, 1.0],
        "blade_tip": [0.0, 0.0, 0.830 * uniform_scale],
        "finger_count": 5,
        "finger_rows_z": [row * uniform_scale for row in finger_rows],
        "scale": uniform_scale,
        "objects": {"hand": hand.name, "sword": sword.name},
        "bounds": {"hand": bounds(hand), "sword": bounds(sword)},
        "mesh_stats": {
            "hand_vertices": len(hand.data.vertices),
            "hand_faces": len(hand.data.polygons),
            "sword_vertices": len(sword.data.vertices),
            "sword_faces": len(sword.data.polygons),
        },
        "normals_recalculated": True,
        "smooth_shading": {
            "hand": "smooth shaded rounded palm, wrist, fingers, and thumb",
            "sword": "smooth shaded handle and fittings; crisp flat blade facets",
        },
        "sword_materials": {
            "handle": handle_material.name,
            "steel": steel_material.name,
            "edge": edge_material.name,
            "brass": brass_material.name,
        },
    }
    return hand, sword, metadata
