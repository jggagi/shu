extends Node3D
## Songfeng's fixed-camera scenery. Authored layout and editor-baked scattering;
## no physics, game clock, gameplay state, runtime scattering or own processing.

const LAYOUT_PATH := "res://assets/art/mountain_ambush/environment/layout.json"
const ROCK_PATHS := ["res://assets/art/mountain_ambush/environment/rock-a.glb", "res://assets/art/mountain_ambush/environment/rock-b.glb"]
const GRASS_PATH := "res://assets/art/mountain_ambush/environment/grass-a.glb"
const WISPY_GRASS_PATH := "res://assets/art/mountain_ambush/environment/grass-b.glb"
const PINE_PATH := "res://assets/art/mountain_ambush/environment/detailed-pine.glb"
const RockShader = preload("res://addons/cultivation_mode/ambush_rock_detail.gdshader")
const RoadShader = preload("res://addons/cultivation_mode/ambush_road_detail.gdshader")
const EnvironmentFinish = preload("res://addons/cultivation_mode/ambush_environment_finish.gd")
var _layout: Dictionary = {}
var _elapsed: float = 0.0
var _static: bool = false
var _ready_ok: bool = false
var _motion: Array[Dictionary] = []
var _mist_materials: Array[ShaderMaterial] = []
var _decorations: Array[Dictionary] = []
var _materials: Dictionary = {}
var _asset_scenes: Dictionary = {}
var _nature_materials: Dictionary = {}
var _width: float
var _depth: float
var _road_surface: MeshInstance3D
var _flagstone_surface: MeshInstance3D
var _finish: Node3D
var _refined_details := true

func setup(width: int, depth: int, cell: float) -> Dictionary:
	set_process(false)
	name = "SongfengEnvironment"
	_width = float(width) * cell
	_depth = float(depth) * cell
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if not parsed is Dictionary or int(parsed.get("schema", 0)) != 1:
		push_error("Songfeng environment layout missing or invalid")
		return {"ok": false}
	_layout = parsed
	for path: String in ROCK_PATHS + [GRASS_PATH, WISPY_GRASS_PATH, PINE_PATH]:
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			push_error("Songfeng environment asset missing: " + path)
			return {"ok": false}
		_asset_scenes[path] = scene
	_build_ground()
	for row: Dictionary in _layout.ridges:
		_ridge(row, "backdrop")
	for row: Dictionary in _layout.cliffs:
		_ridge(row, "cliff")
	for row: Dictionary in _layout.pines:
		if not _pine(row):
			return {"ok": false}
	for row: Dictionary in _layout.rocks:
		_asset(ROCK_PATHS[int(row.variant)], _v3(row.at), Vector3.ONE * float(row.size), float(row.yaw), "rock")
	_build_ground_details()
	if not _build_scatter():
		return {"ok": false}
	_build_rail()
	for row: Dictionary in _layout.mist:
		_mist(row)
	_finish = EnvironmentFinish.new()
	add_child(_finish)
	_finish.call("setup", _layout, _width, _depth, _road_surface, _flagstone_surface, _decorations)
	_finish.call("set_refined_details", _refined_details)
	_ready_ok = true
	reset()
	return {"ok": true}

func _v3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _material(hex: String) -> StandardMaterial3D:
	if _materials.has(hex):
		return _materials[hex]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(hex)
	mat.roughness = 0.98
	_materials[hex] = mat
	return mat

func _rock_material(hex: String, scale_value: float = 1.0, moss_amount: float = 0.38) -> ShaderMaterial:
	var key: String = "rock:" + hex + str(scale_value) + str(moss_amount)
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = RockShader
	mat.set_shader_parameter("stone_tint", Color(hex).srgb_to_linear())
	mat.set_shader_parameter("strata_scale", scale_value)
	mat.set_shader_parameter("moss_amount", moss_amount)
	_materials[key] = mat
	return mat

func _mesh(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, kind: String, shadow: bool = true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.name = kind.capitalize() + str(_decorations.size())
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.set_meta("environment_kind", kind)
	if kind != "ground":
		_decorations.append({"node": node, "kind": kind})
	return node

func _build_ground() -> void:
	# A mountain ledge opens onto the valley. An infinite green ground plane
	# would hide every distant ridge from this downward orthographic camera.
	var rim: Array[Vector3] = [Vector3(-9.0, -0.02, -7.8), Vector3(-5.5, -0.02, -7.7), Vector3(-5.4, -0.02, -5.8), Vector3(5.4, -0.02, -5.8), Vector3(5.6, -0.02, -7.7), Vector3(9.2, -0.02, -7.9), Vector3(9.0, -0.02, 1.8), Vector3(8.5, -0.02, 6.4), Vector3(2.4, -0.02, 7.0), Vector3(-3.3, -0.02, 6.8), Vector3(-8.9, -0.02, 5.8), Vector3(-9.1, -0.02, -0.7)]
	var plateau := SurfaceTool.new()
	plateau.begin(Mesh.PRIMITIVE_TRIANGLES)
	var polygon := PackedVector2Array()
	for point: Vector3 in rim:
		polygon.append(Vector2(point.x, point.z))
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	for index: int in indices:
		plateau.set_color(Color("#93a184"))
		plateau.add_vertex(rim[index])
	var edge_points: Array[Vector3] = []
	for i: int in range(rim.size()):
		var next: int = (i + 1) % rim.size()
		var divisions: int = maxi(1, ceili(rim[i].distance_to(rim[next]) / 0.7))
		for step_index: int in range(divisions):
			edge_points.append(rim[i].lerp(rim[next], float(step_index) / float(divisions)))
	var bands: Array = []
	for level: int in range(9):
		var row: Array[Vector3] = []
		for i: int in range(edge_points.size()):
			var point: Vector3 = edge_points[i]
			var depth: float = float(level) * 0.76
			var displacement: float = (sin(float(i) * 1.7 + float(level) * 2.4) * 0.11 + float(level % 2) * 0.09) * minf(float(level), 1.0)
			var outward: Vector3 = Vector3(point.x, 0, point.z).normalized()
			row.append(point + outward * displacement + Vector3(0, -depth, 0))
		bands.append(row)
	for level: int in range(bands.size() - 1):
		for i: int in range(edge_points.size()):
			var next: int = (i + 1) % edge_points.size()
			for point: Vector3 in [bands[level][i], bands[level][next], bands[level + 1][next], bands[level][i], bands[level + 1][next], bands[level + 1][i]]:
				plateau.add_vertex(point)
	plateau.generate_normals()
	_mesh(self, plateau.commit(), _rock_material("#8a8d78", 0.8), Vector3.ZERO, "ground", false)
	var path := SurfaceTool.new()
	path.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in indices:
		path.set_normal(Vector3.UP)
		path.add_vertex(Vector3(rim[index].x, 0.002, rim[index].z))
	var mat := ShaderMaterial.new()
	mat.shader = RoadShader
	_road_surface = _mesh(self, path.commit(), mat, Vector3.ZERO, "ground", false)

func _ridge(row: Dictionary, kind: String) -> void:
	if kind == "cliff":
		_cliff(row)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(row.seed)
	var dim := _v3(row.size)
	var at := _v3(row.at)
	var rings: Array = []
	var levels: Array = [0.0, 0.24, 0.52, 0.78, 0.94, 1.0]
	for level: int in range(levels.size()):
		var points: Array[Vector3] = []
		var taper: float = [1.0, 0.90, 0.69, 0.46, 0.20, 0.035][level]
		for n: int in range(9):
			var angle: float = TAU * float(n) / 9.0
			var radius: float = taper * rng.randf_range(0.83, 1.15)
			points.append(Vector3(cos(angle) * dim.x * radius + float(level) * 0.10, float(levels[level]) * dim.y + rng.randf_range(-0.07, 0.07) * dim.y, sin(angle) * dim.z * radius))
		rings.append(points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(str(row.color))
	for level: int in range(rings.size() - 1):
		for n: int in range(9):
			var next: int = (n + 1) % 9
			var shade: Color = base.lerp(Color("#d0d2b9"), rng.randf_range(0.0, 0.17))
			shade = shade.darkened(rng.randf_range(0.0, 0.09))
			for point: Vector3 in [rings[level][n], rings[level + 1][n], rings[level + 1][next], rings[level][n], rings[level + 1][next], rings[level][next]]:
				surface.set_color(shade)
				surface.add_vertex(point)
	surface.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	if kind == "backdrop":
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh(self, surface.commit(), mat, at, kind, kind != "backdrop")

func _cliff(row: Dictionary) -> void:
	var dim := _v3(row.size)
	var rings: Array = []
	var phase: float = float(row.seed) * 0.61
	for level: int in range(13):
		var t: float = float(level) / 12.0
		var ring: Array[Vector3] = []
		var taper: float = maxf(0.015, pow(1.0 - t, 0.57))
		for i: int in range(32):
			var angle: float = TAU * float(i) / 32.0
			var eroded: float = 1.0 + sin(angle * 5.0 + phase) * 0.07 + sin(angle * 11.0 + float(level)) * 0.025
			var ledge: float = 0.045 if level % 3 == 1 else -0.02
			var radius: float = taper * eroded + ledge * minf(t * 8.0, 1.0)
			ring.append(Vector3(cos(angle) * dim.x * radius + t * 0.45, t * dim.y + sin(angle * 3.0 + phase) * 0.045, sin(angle) * dim.z * radius))
		rings.append(ring)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for level: int in range(rings.size() - 1):
		for i: int in range(32):
			var next: int = (i + 1) % 32
			for point: Vector3 in [rings[level][i], rings[level + 1][i], rings[level + 1][next], rings[level][i], rings[level + 1][next], rings[level][next]]:
				surface.add_vertex(point)
	surface.generate_normals()
	_mesh(self, surface.commit(), _rock_material(str(row.color)), _v3(row.at), "cliff")

func _build_ground_details() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: Dictionary in _layout.get("flagstones", []):
		var center := Vector3(float(row.at[0]), 0.004, float(row.at[1]))
		var ring: Array[Vector3] = []
		for i: int in range(7):
			var angle: float = TAU * float(i) / 7.0 + float(row.yaw)
			var radius: float = 1.0 + sin(float(i) * 3.0 + float(row.yaw)) * 0.12
			ring.append(center + Vector3(cos(angle) * float(row.size[0]) * radius, 0.002 + sin(float(i) * 1.3) * 0.001, sin(angle) * float(row.size[1]) * radius))
		for i: int in range(7):
			var color: Color = Color("#929980").lightened(float((i + int(row.seed)) % 4) * 0.035)
			for point: Vector3 in [center + Vector3.UP * 0.013, ring[(i + 1) % 7], ring[i]]:
				surface.set_color(color)
				surface.add_vertex(point)
	surface.generate_normals()
	_flagstone_surface = _mesh(self, surface.commit(), _rock_material("#979a92", 1.4, 0.05), Vector3.ZERO, "ground", false)
	surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tiny embedded gravel is batched in the same mesh and stays below overlays.
	for row: Dictionary in _layout.get("gravel", []):
		var at := _v3(row.at)
		var radius: float = float(row.radius)
		var color: Color = Color(str(row.color)).srgb_to_linear()
		for n: int in range(5):
			var a: float = TAU * float(n) / 5.0
			var b: float = TAU * float(n + 1) / 5.0
			for point: Vector3 in [at + Vector3.UP * 0.006, at + Vector3(cos(b) * radius, 0, sin(b) * radius * 0.65), at + Vector3(cos(a) * radius, 0, sin(a) * radius * 0.65)]:
				surface.set_color(color)
				surface.add_vertex(point)
	surface.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.97
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(self, surface.commit(), mat, Vector3.ZERO, "ground", false)
	for row: Dictionary in _layout.get("wispy_grass", []):
		_asset(WISPY_GRASS_PATH, _v3(row.at), Vector3.ONE * float(row.size), float(row.yaw), "grass")

func _beam(parent: Node3D, a: Vector3, b: Vector3, bottom: float, top: float, mat: Material, kind: String = "pine") -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 7
	var node := _mesh(parent, mesh, mat, (a + b) * 0.5, kind)
	node.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))

func _pine(row: Dictionary) -> bool:
	var tree: Node3D = _asset(PINE_PATH, _v3(row.at), Vector3.ONE * float(row.height), float(row.yaw), "pine")
	tree.name = "DetailedPine" + str(row.seed)
	var crown: Node3D = tree.find_child("WindCrown", true, false) as Node3D
	if crown == null:
		push_error("Detailed pine is missing its authored WindCrown node")
		return false
	_motion.append({"node": crown, "basis": crown.transform, "phase": float(row.seed), "amplitude": 0.10})
	return true

func _asset(path: String, at: Vector3, dimensions: Vector3, yaw: float, kind: String) -> Node3D:
	var node: Node3D = (_asset_scenes[path] as PackedScene).instantiate() as Node3D
	node.position = at
	node.scale = dimensions
	node.rotation.y = yaw
	add_child(node)
	for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
		mesh.set_meta("environment_kind", kind)
		if kind == "grass":
			var instance := mesh as MeshInstance3D
			for surface: int in range(instance.mesh.get_surface_count()):
				var original: Material = instance.get_active_material(surface)
				if original is StandardMaterial3D:
					var key: int = original.get_instance_id()
					if not _nature_materials.has(key):
						var graded := original.duplicate() as StandardMaterial3D
						graded.albedo_color *= Color(0.79, 0.84, 0.78, 1.0)
						_nature_materials[key] = graded
					instance.set_surface_override_material(surface, _nature_materials[key])
		if kind == "ground":
			(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			_decorations.append({"node": mesh, "kind": kind})
	if kind == "grass":
		_motion.append({"node": node, "basis": node.transform, "phase": at.x * 2.0 + at.z})
	return node

func _build_scatter() -> bool:
	var path: String = str(_layout.scatter)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema", 0)) != 1 or not parsed.get("instances", []) is Array:
		push_error("Songfeng scatter cache missing or invalid")
		return false
	for row: Dictionary in parsed.instances:
		var at := _v3(row.at)
		# A cache is presentation data; it may never silently populate combat cells.
		if absf(at.x) < _width * 0.5 + 0.35 and absf(at.z) < _depth * 0.5 + 0.4:
			push_error("Songfeng scatter cache crosses the playable road")
			return false
		var is_rock: bool = str(row.get("kind", "grass")) == "rock"
		var scale_value: float = float(row.get("scale", 0.35))
		_asset(ROCK_PATHS[0] if is_rock else GRASS_PATH, at, Vector3.ONE * scale_value, float(row.get("yaw", 0)), "rock" if is_rock else "grass")
	return true

func _build_rail() -> void:
	var wood := _material("#827858")
	for i: int in range(8):
		var at := Vector3(_width * 0.5 + 0.85, 0, -_depth * 0.5 + float(i) * 1.15)
		_beam(self, at, at + Vector3(0.04, 0.58, 0), 0.038, 0.030, wood, "rail")
		if i < 7:
			_beam(self, at + Vector3(0, 0.43, 0), at + Vector3(0.03, 0.46, 1.15), 0.029, 0.024, wood, "rail")

func _mist(row: Dictionary) -> void:
	var plane := QuadMesh.new()
	plane.size = Vector2(float(row.size[0]), float(row.size[1]))
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform float elapsed=0.0;
uniform float drift=0.01;
uniform float strength=0.25;
void fragment(){
 vec2 p=UV; float t=elapsed*drift;
 float w=sin((p.x+t)*17.0+sin(p.y*7.0))*0.5+0.5;
 float soft=sin(p.y*3.14159265); soft=soft*soft;
 float edge=smoothstep(0.0,0.15,p.x)*(1.0-smoothstep(0.85,1.0,p.x));
 ALBEDO=vec3(0.79,0.85,0.78); ALPHA=soft*edge*(0.55+w*0.45)*strength;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("drift", float(row.speed))
	mat.set_shader_parameter("strength", float(row.strength))
	_mist_materials.append(mat)
	_mesh(self, plane, mat, _v3(row.at), "mist", false)

func set_refined_details(enabled: bool) -> void:
	_refined_details = enabled
	if is_instance_valid(_finish):
		_finish.call("set_refined_details", enabled)

func bind_scene_details(scene_root: Node3D) -> void:
	if is_instance_valid(_finish):
		_finish.call("bind_scene_details", scene_root)

func detail_audit() -> Dictionary:
	return _finish.call("detail_audit") if is_instance_valid(_finish) else {"ready": false, "enabled": _refined_details}

func set_static(enabled: bool) -> void:
	_static = enabled

func reset() -> void:
	_elapsed = 0.0
	_apply_motion()

func step(delta: float) -> void:
	if not _ready_ok or _static:
		return
	_elapsed += maxf(delta, 0.0)
	_apply_motion()

func _apply_motion() -> void:
	for item: Dictionary in _motion:
		var node: Node3D = item.node
		node.transform = item.basis
		var wave: float = sin(_elapsed * 0.83 + float(item.phase)) - sin(float(item.phase))
		node.rotate_z(wave * float(_layout.get("wind_amplitude", 0.035)) * float(item.get("amplitude", 1.0)))
	for mat: ShaderMaterial in _mist_materials:
		mat.set_shader_parameter("elapsed", _elapsed)

func audit() -> Dictionary:
	var rows: Array[Dictionary] = []
	for item: Dictionary in _decorations:
		var node: MeshInstance3D = item.node
		rows.append({"node_path": str(get_path_to(node)), "world_aabb": node.global_transform * node.get_aabb(), "kind": item.kind})
	var motion_state: Array = []
	for item: Dictionary in _motion:
		motion_state.append((item.node as Node3D).transform)
	for mat: ShaderMaterial in _mist_materials:
		motion_state.append(mat.get_shader_parameter("elapsed"))
	return {"ready": _ready_ok, "static": _static, "elapsed": _elapsed, "node_count": find_children("*", "", true, false).size(), "mesh_count": find_children("*", "MeshInstance3D", true, false).size(), "motion_state": motion_state, "decorations": rows, "layout_path": LAYOUT_PATH}
