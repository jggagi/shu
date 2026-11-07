extends RefCounted
## Original mesh construction for the combat character candidate. No game rules.
## All geometry is authored locally; no generated or external character asset.
var meshes: Array[MeshInstance3D] = []
var materials: Dictionary = {}

func material(hex: String) -> StandardMaterial3D:
	if materials.has(hex):
		return materials[hex]
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.98
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	materials[hex] = mat
	return mat

func make_mesh(parent: Node3D, name: String, vertices: Array, color: String, colors: Array = []) -> MeshInstance3D:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base: Color = Color(color)
	for i: int in range(vertices.size()):
		surface.set_color(colors[i] if i < colors.size() else base)
		surface.add_vertex(vertices[i])
	surface.index()
	surface.generate_normals()
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = name
	node.mesh = surface.commit()
	node.material_override = material(color)
	parent.add_child(node)
	meshes.append(node)
	return node

func polygon(parent: Node3D, name: String, points: Array, color: String) -> MeshInstance3D:
	var vertices: Array = []
	for i: int in range(1, points.size() - 1):
		vertices.append_array([points[0], points[i], points[i + 1]])
	return make_mesh(parent, name, vertices, color)

func loft(parent: Node3D, name: String, rings: Array, color: String, segments: int = 20) -> MeshInstance3D:
	# Each ring is [height, half_width, half_depth, centre_x, centre_z].
	# Ring radii describe the authored silhouette, rather than stacked spheres.
	var vertices: Array = []
	var colors: Array = []
	for row: int in range(rings.size() - 1):
		var low: Array = rings[row]
		var high: Array = rings[row + 1]
		for i: int in range(segments):
			var a: float = TAU * float(i) / float(segments)
			var b: float = TAU * float(i + 1) / float(segments)
			var points: Array = [_ring_point(low, a), _ring_point(low, b), _ring_point(high, b), _ring_point(high, a)]
			for index: int in [0, 1, 2, 0, 2, 3]:
				vertices.append(points[index])
				colors.append(Color(color))
	for index: int in [0, rings.size() - 1]:
		var ring: Array = rings[index]
		var centre: Vector3 = Vector3(float(ring[3]), float(ring[0]), float(ring[4]))
		for i: int in range(segments):
			vertices.append_array([centre, _ring_point(ring, TAU * float(i + 1) / float(segments)), _ring_point(ring, TAU * float(i) / float(segments))])
			colors.append_array([Color(color), Color(color), Color(color)])
	return make_mesh(parent, name, vertices, color, colors)

func _ring_point(ring: Array, angle: float) -> Vector3:
	return Vector3(float(ring[3]) + sin(angle) * float(ring[1]), float(ring[0]), float(ring[4]) + cos(angle) * float(ring[2]))

func strand(parent: Node3D, name: String, points: Array, widths: Array, depth: float, color: String, segments: int = 8) -> MeshInstance3D:
	var vertices: Array = []
	var rings: Array = []
	var smooth_points: Array = []
	var smooth_widths: Array = []
	for i: int in range(points.size() - 1):
		for n: int in range(4):
			var t: float = float(n) / 4.0
			var point: Vector3 = points[i]
			smooth_points.append(point.cubic_interpolate(points[i + 1], points[maxi(i - 1, 0)], points[mini(i + 2, points.size() - 1)], t))
			smooth_widths.append(lerpf(float(widths[i]), float(widths[i + 1]), t))
	smooth_points.append(points[-1])
	smooth_widths.append(widths[-1])
	points = smooth_points
	widths = smooth_widths
	for i: int in range(points.size()):
		var tangent: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var normal: Vector3 = Vector3.FORWARD - tangent * Vector3.FORWARD.dot(tangent)
		if normal.length_squared() < 0.01:
			normal = Vector3.UP - tangent * Vector3.UP.dot(tangent)
		normal = normal.normalized()
		var side: Vector3 = tangent.cross(normal).normalized()
		var ring: Array = []
		for j: int in range(segments):
			var angle: float = TAU * float(j) / float(segments)
			ring.append(points[i] + side * cos(angle) * float(widths[i]) + normal * sin(angle) * depth * minf(1.0, float(widths[i]) * 20.0))
		rings.append(ring)
	for i: int in range(rings.size() - 1):
		for j: int in range(segments):
			var k: int = (j + 1) % segments
			vertices.append_array([rings[i][j], rings[i][k], rings[i + 1][k], rings[i][j], rings[i + 1][k], rings[i + 1][j]])
	# Close both ends. The sleeve roots must never expose the dark interior
	# when seen from the normal elevated combat camera.
	for end: int in [0, rings.size() - 1]:
		for j: int in range(segments):
			var k: int = (j + 1) % segments
			vertices.append_array([points[end], rings[end][j], rings[end][k]] if end == 0 else [points[end], rings[end][k], rings[end][j]])
	return make_mesh(parent, name, vertices, color)

func curved_strip(parent: Node3D, name: String, points: Array, widths: Array, color: String, depth: float = 0.004) -> MeshInstance3D:
	return strand(parent, name, points, widths, depth, color, 4)

func panel(parent: Node3D, name: String, left: Array, right: Array, color: String) -> MeshInstance3D:
	var vertices: Array = []
	for i: int in range(mini(left.size(), right.size()) - 1):
		vertices.append_array([left[i], right[i], right[i + 1], left[i], right[i + 1], left[i + 1]])
	return make_mesh(parent, name, vertices, color)

func beam(parent: Node3D, name: String, a: Vector3, b: Vector3, radius: float, color: String, top_radius: float = -1.0, segments: int = 10) -> MeshInstance3D:
	var length: float = a.distance_to(b)
	var top: float = top_radius if top_radius >= 0 else radius
	var node: MeshInstance3D = loft(parent, name, [[-length * 0.5, radius, radius, 0, 0], [length * 0.5, top, top, 0, 0]], color, segments)
	node.position = (a + b) * 0.5
	node.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return node

func bevel_box(parent: Node3D, name: String, centre: Vector3, dimensions: Vector3, color: String) -> MeshInstance3D:
	var vertices: Array = []
	var rx: float = dimensions.x * 0.5
	var rz: float = dimensions.z * 0.5
	var bevel: float = minf(rx, rz) * 0.28
	var contour: Array = [Vector2(-rx + bevel, -rz), Vector2(rx - bevel, -rz), Vector2(rx, -rz + bevel), Vector2(rx, rz - bevel), Vector2(rx - bevel, rz), Vector2(-rx + bevel, rz), Vector2(-rx, rz - bevel), Vector2(-rx, -rz + bevel)]
	for i: int in range(8):
		var j: int = (i + 1) % 8
		var a: Vector3 = centre + Vector3(contour[i].x, -dimensions.y * 0.5, contour[i].y)
		var b: Vector3 = centre + Vector3(contour[j].x, -dimensions.y * 0.5, contour[j].y)
		var c: Vector3 = centre + Vector3(contour[j].x, dimensions.y * 0.5, contour[j].y)
		var d: Vector3 = centre + Vector3(contour[i].x, dimensions.y * 0.5, contour[i].y)
		vertices.append_array([a, b, c, a, c, d])
		vertices.append_array([centre + Vector3(0, dimensions.y * 0.5, 0), d, c])
		vertices.append_array([centre - Vector3(0, dimensions.y * 0.5, 0), b, a])
	return make_mesh(parent, name, vertices, color)

func face_z(x: float, y: float) -> float:
	var rings: Array = face_rings()
	for i: int in range(rings.size() - 1):
		if y >= float(rings[i][0]) and y <= float(rings[i + 1][0]):
			var t: float = inverse_lerp(float(rings[i][0]), float(rings[i + 1][0]), y)
			var rx: float = lerpf(float(rings[i][1]), float(rings[i + 1][1]), t)
			var rz: float = lerpf(float(rings[i][2]), float(rings[i + 1][2]), t)
			var cz: float = lerpf(float(rings[i][4]), float(rings[i + 1][4]), t)
			return cz + rz * sqrt(maxf(0.0, 1.0 - x * x / maxf(0.0001, rx * rx)))
	return 0.20

func face_rings() -> Array:
	return [[-0.28, 0.065, 0.070, 0, 0.040], [-0.25, 0.15, 0.14, 0, 0.025], [-0.18, 0.23, 0.195, 0, 0.005], [-0.07, 0.277, 0.230, 0, 0], [0.05, 0.282, 0.240, 0, 0], [0.16, 0.26, 0.225, 0, -0.006], [0.25, 0.20, 0.17, 0, -0.012], [0.30, 0.11, 0.09, 0, -0.012], [0.32, 0.005, 0.005, 0, -0.012]]

func face_patch(parent: Node3D, name: String, xy: Array, color: String, offset: float = 0.003) -> MeshInstance3D:
	var points: Array = []
	var signed_area: float = 0.0
	for i: int in range(xy.size()):
		signed_area += xy[i].cross(xy[(i + 1) % xy.size()])
	if signed_area < 0:
		xy = xy.duplicate()
		xy.reverse()
	for point: Vector2 in xy:
		points.append(Vector3(point.x, point.y, face_z(point.x, point.y) + offset))
	return polygon(parent, name, points, color)

func face_oval(parent: Node3D, name: String, centre: Vector2, radii: Vector2, color: String, offset: float = 0.006, segments: int = 16) -> MeshInstance3D:
	var points: Array = []
	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return face_patch(parent, name, points, color, offset)
