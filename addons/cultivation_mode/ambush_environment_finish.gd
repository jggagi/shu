extends Node3D
## A reversible, deterministic finishing pass. No physics, processing or gameplay.
## Existing imported meshes and their materials are never edited in place.

const StoneShader = preload("res://addons/cultivation_mode/ambush_finish_stone.gdshader")
const RoadShader = preload("res://addons/cultivation_mode/ambush_finish_road.gdshader")
const WoodShader = preload("res://addons/cultivation_mode/ambush_finish_wood.gdshader")
const GROUND_MAX_HEIGHT := 0.020
const OUTSIDE_MARGIN := 0.36
var _enabled := true
var _ready_ok := false
var _surfaces: Dictionary = {}
var _materials: Dictionary = {}
var _bindings: Array[Dictionary] = []
var _visibility_bindings: Array[Dictionary] = []
var _batches: Array[Dictionary] = []
var _width: float
var _depth: float
var _rng := RandomNumberGenerator.new()
var _ground_triangles := 0
var _outside_triangles := 0
var _measured_ground_max_height := 0.0
var _measured_outside_margin := INF
var _clearance_met := true

func setup(layout: Dictionary, width: float, depth: float, road: MeshInstance3D, flagstones: MeshInstance3D, decorations: Array[Dictionary]) -> void:
	set_process(false)
	name = "RefinedEnvironmentFinish"
	set_meta("presentation_only", true)
	_width = width
	_depth = depth
	_rng.seed = 2026102601
	_bind(road, "road")
	_visibility_bindings.append({"node": flagstones, "visible": flagstones.visible})
	for item: Dictionary in decorations:
		var kind: String = str(item.kind)
		if kind in ["rock", "cliff", "rail"]:
			_bind(item.node as MeshInstance3D, kind)
	_build_stone_paving(layout.get("flagstones", []))
	_build_road_shoulder()
	_build_rail_lashings()
	_build_old_waymark()
	_build_fallen_wood()
	_commit_batches()
	_ready_ok = true
	set_refined_details(_enabled)

func bind_scene_details(scene_root: Node3D) -> void:
	# Declared obstacle rocks are built by Stage after this environment. Only their
	# surface overrides are recorded; no geometry, position or visibility changes.
	for child: Node in scene_root.get_children():
		if not str(child.name).begins_with("DeclaredObstacle"):
			continue
		for mesh: Node in child.find_children("*", "MeshInstance3D", true, false):
			_bind(mesh as MeshInstance3D, "rock")
	set_refined_details(_enabled)

func _bind(node: MeshInstance3D, kind: String) -> void:
	if node == null:
		return
	for row: Dictionary in _bindings:
		if row.node == node:
			return
	var surfaces: Array[Material] = []
	for index: int in range(node.mesh.get_surface_count()):
		surfaces.append(node.get_surface_override_material(index))
	var mat: Material
	if kind == "road":
		if not _materials.has("road"):
			var road_mat := ShaderMaterial.new()
			road_mat.shader = RoadShader
			_materials.road = road_mat
		mat = _materials.road
	elif kind == "rail":
		if not _materials.has("wood"):
			var wood_mat := ShaderMaterial.new()
			wood_mat.shader = WoodShader
			wood_mat.set_shader_parameter("wood_tint", Color("#827858").srgb_to_linear())
			_materials.wood = wood_mat
		mat = _materials.wood
	else:
		var tint := Color("#858d7b")
		var source_texture: Texture2D
		var source: Material = node.material_override if node.material_override != null else node.get_active_material(0)
		if source is StandardMaterial3D:
			tint = (source as StandardMaterial3D).albedo_color
			source_texture = (source as StandardMaterial3D).albedo_texture
		elif source is ShaderMaterial and (source as ShaderMaterial).shader != null:
			var source_tint: Variant = (source as ShaderMaterial).get_shader_parameter("stone_tint")
			if source_tint is Color:
				tint = (source_tint as Color).linear_to_srgb()
		var key: String = "stone:" + tint.to_html() + ":" + kind + ":" + str(source_texture.get_instance_id() if source_texture != null else 0)
		if not _materials.has(key):
			var stone_mat := ShaderMaterial.new()
			stone_mat.shader = StoneShader
			stone_mat.set_shader_parameter("stone_tint", tint.srgb_to_linear())
			stone_mat.set_shader_parameter("weather_scale", 0.65 if kind == "cliff" else 1.7)
			stone_mat.set_shader_parameter("moss_amount", 0.27 if kind == "cliff" else 0.22)
			stone_mat.set_shader_parameter("use_source_albedo", source_texture != null)
			if source_texture != null:
				stone_mat.set_shader_parameter("source_albedo", source_texture)
			_materials[key] = stone_mat
		mat = _materials[key]
	_bindings.append({"node": node, "override": node.material_override, "surfaces": surfaces, "refined": mat, "kind": kind})

func set_refined_details(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	for row: Dictionary in _bindings:
		var node: MeshInstance3D = row.node
		if not is_instance_valid(node):
			continue
		node.material_override = row.refined if enabled else row.override
		# Surface overrides remain the exact original references in both modes.
	for row: Dictionary in _visibility_bindings:
		(row.node as Node3D).visible = false if enabled else bool(row.visible)

func _flat_material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.98
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = mat
	return mat

func _surface(key: String) -> SurfaceTool:
	if not _surfaces.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[key] = {"tool": surface, "triangles": 0}
	return _surfaces[key].tool

func _triangle(key: String, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var surface := _surface(key)
	for point: Vector3 in [a, b, c]:
		surface.set_color(color)
		surface.add_vertex(point)
	_surfaces[key].triangles += 1

func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_triangle(key, a, b, c, color)
	_triangle(key, a, c, d, color)

func _polygon_stone(at: Vector3, radii: Vector2, yaw: float, height: float, color: Color, key: String, seed_value: int) -> void:
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	var base: Array[Vector3] = []
	var count := 7
	for i: int in range(count):
		var angle: float = TAU * float(i) / float(count) + yaw
		var irregular: float = 1.0 + sin(float(i * 7 + seed_value) * 1.37) * 0.12
		var point := Vector3(cos(angle) * radii.x * irregular, 0, sin(angle) * radii.y * irregular)
		outer.append(at + point + Vector3.UP * height * 0.68)
		inner.append(at + point * 0.89 + Vector3.UP * height)
		base.append(at + point * 1.015)
	var center: Vector3 = at + Vector3.UP * height
	for i: int in range(count):
		var next: int = (i + 1) % count
		_triangle(key, center, inner[next], inner[i], color.lightened(float(i % 3) * 0.017))
		_quad(key, inner[i], inner[next], outer[next], outer[i], color.lightened(0.075))
		_quad(key, outer[i], outer[next], base[next], base[i], color.darkened(0.23))

func _line(key: String, a: Vector3, b: Vector3, radius: float, color: Color, sides: int = 6, end_radius: float = -1.0) -> void:
	var direction: Vector3 = (b - a).normalized()
	var reference: Vector3 = Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.94 else Vector3.UP
	var x_axis: Vector3 = direction.cross(reference).normalized()
	var y_axis: Vector3 = direction.cross(x_axis).normalized()
	var top_radius: float = radius if end_radius < 0 else end_radius
	for i: int in range(sides):
		var angle: float = TAU * float(i) / float(sides)
		var next_angle: float = TAU * float(i + 1) / float(sides)
		var p: Vector3 = x_axis * cos(angle) + y_axis * sin(angle)
		var q: Vector3 = x_axis * cos(next_angle) + y_axis * sin(next_angle)
		var shade: Color = color.lightened(0.025 * float(i % 3))
		_quad(key, a + p * radius, a + q * radius, b + q * top_radius, b + p * top_radius, shade)
		_triangle(key, b, b + p * top_radius, b + q * top_radius, color.lightened(0.10))

func _build_stone_paving(rows: Array) -> void:
	for row: Dictionary in rows:
		var at := Vector3(float(row.at[0]), 0.003, float(row.at[1]))
		var radii := Vector2(float(row.size[0]), float(row.size[1]))
		var index: int = int(row.seed)
		var color: Color = Color("#7f877b").lightened(float(index % 4) * 0.022)
		_polygon_stone(at, radii, float(row.yaw), 0.016, color, "paving", index)
		# Sparse short cracks change direction across each slab. These lie in its
		# shallow top and stay below every board overlay (0.023 m).
		if index % 3 == 0:
			var a: Vector3 = at + Vector3(-radii.x * 0.65, 0.0162, radii.y * 0.28)
			var b: Vector3 = at + Vector3(radii.x * 0.03, 0.0162, -radii.y * 0.10)
			var c: Vector3 = at + Vector3(radii.x * 0.39, 0.0162, -radii.y * 0.65)
			_ribbon("paving_seams", a, b, 0.0055, Color("#626b61"))
			_ribbon("paving_seams", b, c, 0.0035, Color("#626b61"))
		for n: int in range(3):
			var angle: float = float(index * 3 + n) * 2.19
			var point: Vector3 = at + Vector3(cos(angle) * (radii.x + 0.08), 0, sin(angle) * (radii.y + 0.08))
			_polygon_stone(point, Vector2(0.026, 0.018) * _rng.randf_range(0.7, 1.5), angle, 0.009, color.darkened(0.12), "embedded_gravel", index + n)
	# The two road entrances show fragmented older paving, not a new obstacle.
	for side: float in [-1.0, 1.0]:
		for i: int in range(6):
			var at := Vector3(-1.8 + float(i) * 0.64, 0.003, side * (_depth * 0.5 + 0.33) + sin(float(i) * 1.7) * 0.12)
			_polygon_stone(at, Vector2(0.28, 0.15), float(i) * 0.7, 0.017, Color("#85897b"), "paving", i + 41)

func _ribbon(key: String, a: Vector3, b: Vector3, half_width: float, color: Color) -> void:
	var perpendicular: Vector3 = (b - a).cross(Vector3.UP).normalized() * half_width
	_quad(key, a - perpendicular, a + perpendicular, b + perpendicular, b - perpendicular, color)

func _build_road_shoulder() -> void:
	# The shoulder follows the authored ledge instead of scattering into cells.
	for side: float in [-1.0, 1.0]:
		for index: int in range(34):
			var z: float = -_depth * 0.5 + float(index) * _depth / 33.0
			var x: float = side * (_width * 0.5 + 0.46 + sin(z * 1.7) * 0.07)
			var at := Vector3(x, 0.004, z)
			var radius: float = _rng.randf_range(0.045, 0.11)
			_polygon_stone(at, Vector2(radius, radius * 0.64), _rng.randf() * TAU, 0.012, Color("#92917a"), "embedded_gravel", index)
			if index % 3 == 0:
				# Ground-hugging leaves, never tall blades in a selectable tile.
				for leaf: int in range(4):
					var direction: float = float(leaf) * 2.33 + z
					var start: Vector3 = at + Vector3(side * 0.10, 0, 0)
					var tip: Vector3 = start + Vector3(cos(direction) * 0.13, 0.009, sin(direction) * 0.13)
					var cross_axis: Vector3 = (tip - start).cross(Vector3.UP).normalized() * 0.029
					_triangle("shoulder_leaves", start, tip + cross_axis * 0.20, start.lerp(tip, 0.45) + cross_axis, Color("#667055"))
					_triangle("shoulder_leaves", start, start.lerp(tip, 0.45) - cross_axis, tip - cross_axis * 0.20, Color("#758062"))
		# Dark irregular exposed seams at the ledge lip are outside the board.
		for index: int in range(8):
			var z: float = -_depth * 0.5 + 0.28 + float(index) * 0.95
			var a := Vector3(side * (_width * 0.5 + 0.62), 0.005, z)
			var b: Vector3 = a + Vector3(side * 0.22, 0, 0.14)
			var c: Vector3 = b + Vector3(side * 0.13, 0, 0.41)
			_ribbon("shoulder_seams", a, b, 0.008, Color("#626957"))
			_ribbon("shoulder_seams", b, c, 0.005, Color("#626957"))

func _build_rail_lashings() -> void:
	var x: float = _width * 0.5 + 0.85
	for index: int in range(8):
		var at := Vector3(x, 0.44, -_depth * 0.5 + float(index) * 1.15)
		# Three turns of rope visibly bind rail and upright. Both are outside the
		# grid; ropes do not imply a usable path or a new barricade.
		for turn: int in range(3):
			var ring: Array[Vector3] = []
			for segment: int in range(12):
				var angle: float = TAU * float(segment) / 12.0
				ring.append(at + Vector3(cos(angle) * 0.052, float(turn - 1) * 0.021 + sin(angle) * 0.012, sin(angle) * 0.052))
			for segment: int in range(12):
				_line("rail_rope", ring[segment], ring[(segment + 1) % 12], 0.009, Color("#a0926e"), 5)
		_line("rail_rope", at + Vector3(-0.055, -0.02, 0.018), at + Vector3(-0.072, -0.14, 0.03), 0.009, Color("#958662"), 5)
		# Freshly worn cut cap and a small split in the upright.
		_polygon_stone(Vector3(x + 0.04, 0.577, at.z), Vector2(0.026, 0.025), 0.0, 0.003, Color("#a99c79"), "rail_endgrain", index)

func _build_old_waymark() -> void:
	# An unlettered, partly buried wayside stone and its two weathered steps.
	# The local silhouette is beyond the left edge, never an undeclared blocker.
	var at := Vector3(-_width * 0.5 - 0.95, 0.0, 1.35)
	_polygon_stone(at, Vector2(0.34, 0.24), 0.27, 0.07, Color("#79816e"), "outside_stone", 65)
	_polygon_stone(at + Vector3(-0.06, 0.065, -0.035), Vector2(0.23, 0.16), 0.19, 0.09, Color("#858b78"), "outside_stone", 69)
	var base: Vector3 = at + Vector3(-0.04, 0.12, -0.03)
	var left := Vector3(-0.145, 0, 0.065)
	var right := Vector3(0.145, 0, 0.065)
	var upper_left := Vector3(-0.12, 0.62, 0.035)
	var upper_right := Vector3(0.11, 0.67, 0.025)
	_quad("outside_stone", base + left, base + right, base + upper_right, base + upper_left, Color("#8f9683"))
	_quad("outside_stone", base + right, base + right - Vector3(0, 0, 0.13), base + upper_right - Vector3(0, 0, 0.13), base + upper_right, Color("#7f8876"))
	_quad("outside_stone", base + left - Vector3(0, 0, 0.13), base + upper_left - Vector3(0, 0, 0.13), base + upper_right - Vector3(0, 0, 0.13), base + right - Vector3(0, 0, 0.13), Color("#7b8473"))
	_quad("outside_stone", base + left, base + upper_left, base + upper_left - Vector3(0, 0, 0.13), base + left - Vector3(0, 0, 0.13), Color("#747c6c"))
	_quad("outside_stone", base + upper_left, base + upper_right, base + upper_right - Vector3(0, 0, 0.13), base + upper_left - Vector3(0, 0, 0.13), Color("#a0a58f"))
	# A shallow weathered rectangular recess; no invented inscriptions.
	var front := base + Vector3(-0.002, 0.37, 0.066)
	_quad("waymark_recess", front + Vector3(-0.065, -0.115, 0), front + Vector3(0.065, -0.115, 0), front + Vector3(0.065, 0.115, 0), front + Vector3(-0.065, 0.115, 0), Color("#747f6d"))

func _build_fallen_wood() -> void:
	var left_x: float = -_width * 0.5 - 0.91
	var at := Vector3(left_x, 0.04, 2.70)
	_line("fallen_wood_left", at, at + Vector3(-0.56, 0.08, 0.57), 0.070, Color("#796e52"), 9, 0.052)
	_line("fallen_wood_left", at + Vector3(-0.30, 0.04, 0.31), at + Vector3(-0.70, 0.28, 0.20), 0.026, Color("#796e52"), 7, 0.012)
	_line("fallen_wood_left", at + Vector3(-0.18, 0.03, 0.18), at + Vector3(0.02, 0.16, 0.43), 0.019, Color("#8b7b5a"), 6, 0.008)
	var stump := Vector3(_width * 0.5 + 1.16, 0.0, -1.75)
	_line("fallen_wood_right", stump, stump + Vector3(-0.045, 0.39, 0.03), 0.100, Color("#786f52"), 9, 0.070)
	_line("fallen_wood_right", stump + Vector3(-0.02, 0.20, 0.01), stump + Vector3(-0.23, 0.31, -0.07), 0.030, Color("#887759"), 7, 0.010)

func _commit_batches() -> void:
	for key: String in _surfaces:
		var row: Dictionary = _surfaces[key]
		var surface: SurfaceTool = row.tool
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "Finish_" + key
		mesh.mesh = surface.commit()
		mesh.material_override = _flat_material(key)
		mesh.set_meta("environment_finish_kind", key)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key in ["paving", "paving_seams", "embedded_gravel", "shoulder_seams", "shoulder_leaves", "waymark_recess"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mesh)
		var ground: bool = key in ["paving", "paving_seams", "embedded_gravel", "shoulder_seams", "shoulder_leaves"]
		var bounds: AABB = mesh.get_aabb()
		if ground:
			_ground_triangles += int(row.triangles)
			_measured_ground_max_height = maxf(_measured_ground_max_height, bounds.end.y)
			_clearance_met = _clearance_met and bounds.end.y < 0.023
		else:
			_outside_triangles += int(row.triangles)
			var margin: float = minf(absf(bounds.position.x), absf(bounds.end.x)) - _width * 0.5
			_measured_outside_margin = minf(_measured_outside_margin, margin)
			_clearance_met = _clearance_met and bounds.position.x * bounds.end.x > 0.0 and margin >= OUTSIDE_MARGIN
		_batches.append({"node": mesh, "kind": key, "triangles": int(row.triangles), "ground": ground})

func _material_id(value: Material) -> int:
	return value.get_instance_id() if value != null else 0

func detail_audit() -> Dictionary:
	var rows: Array[Dictionary] = []
	var triangles := 0
	var restored := true
	var original_slots: Array[Dictionary] = []
	for item: Dictionary in _batches:
		var mesh: MeshInstance3D = item.node
		triangles += int(item.triangles)
		rows.append({"node_path": str(get_path_to(mesh)), "kind": item.kind, "triangles": item.triangles, "ground": item.ground, "world_aabb": mesh.global_transform * mesh.get_aabb(), "visible": mesh.is_visible_in_tree()})
	for row: Dictionary in _bindings:
		var mesh: MeshInstance3D = row.node
		if not is_instance_valid(mesh):
			continue
		var current_surfaces: Array[int] = []
		var expected_surfaces: Array[int] = []
		for index: int in range(mesh.mesh.get_surface_count()):
			current_surfaces.append(_material_id(mesh.get_surface_override_material(index)))
			expected_surfaces.append(_material_id(row.surfaces[index]))
		var exact: bool = mesh.material_override == row.override and current_surfaces == expected_surfaces
		restored = restored and exact
		original_slots.append({"node_path": str(mesh.get_path()), "kind": row.kind, "original_override": _material_id(row.override), "current_override": _material_id(mesh.material_override), "original_surfaces": expected_surfaces, "current_surfaces": current_surfaces, "restored": exact})
	for row: Dictionary in _visibility_bindings:
		restored = restored and (row.node as Node3D).visible == bool(row.visible)
	return {"ready": _ready_ok, "enabled": _enabled, "root_visible": visible, "mesh_batches": _batches.size(), "draw_calls_estimate": _batches.size(), "draw_calls_estimate_excludes_shadows": true, "triangles": triangles, "ground_triangles": _ground_triangles, "outside_triangles": _outside_triangles, "ground_max_height": _measured_ground_max_height, "ground_height_limit": GROUND_MAX_HEIGHT, "outside_props_min_grid_margin": _measured_outside_margin, "outside_props_margin_limit": OUTSIDE_MARGIN, "gameplay_clearance_met": _clearance_met, "decorative_blockers": 0, "changed_material_slots": _bindings.size() if _enabled else 0, "original_materials_restored": restored, "source_layout_unchanged": true, "batches": rows, "material_slots": original_slots, "owns_processing": is_processing()}
