extends "res://addons/cultivation_mode/chengdu_large_stage.gd"
## Original geometry arranged from the user's Chengdu reference map. The
## supplied image remains documentation; no reference pixels enter runtime art.

const REFERENCE_LAYOUT := "res://assets/data/chengdu-reference-layout.json"
var _reference_kinds: Dictionary = {}
var _bridge_decks: Array = []
var _reference_water: Array = []
var _reference_lots: Array = []
const LOOK_AHEAD := Vector2(0, 175)
const SOUTH_TARGET_FRAMING_DISTANCE := 360.0
var _active_lookahead := LOOK_AHEAD


func _init() -> void:
	layout_path = REFERENCE_LAYOUT


func _update_follow_camera(point: Vector2, delta: float, snap: bool) -> void:
	# Tall roofs receive extra northern space until a nearby southern target
	# needs that space. Start recentering before the walker reaches interaction
	# distance; keep the same bounded, smoothed camera and picking projection.
	_active_lookahead = LOOK_AHEAD
	for item: Dictionary in _definition.get("interactions", {}).values():
		var coordinates: Array = item.position
		var difference := Vector2(float(coordinates[0]), float(coordinates[1])) - point
		if difference.y > 0 and difference.length_squared() <= SOUTH_TARGET_FRAMING_DISTANCE * SOUTH_TARGET_FRAMING_DISTANCE:
			_active_lookahead = Vector2.ZERO
			break
	super._update_follow_camera(point - _active_lookahead, delta, snap)


func _visibility_padding() -> float:
	# The reference contains tall pavilions and temple roofs above the old low
	# street lots. Keep their bases eligible until the high silhouette leaves.
	return 600.0


func _build_ground() -> void:
	var earth := _material("#b8c3a9", "flat")
	earth.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plane(logical_to_world(_world_size * 0.5) - Vector3.UP * 0.18, _world_size / WORLD_SCALE + Vector2(22, 22), earth)
	var ground_patches: Array[Rect2] = [_world_floor]
	for water: Rect2 in _water_bounds:
		var next: Array[Rect2] = []
		for patch: Rect2 in ground_patches:
			next.append_array(_subtract_rect(patch, water))
		ground_patches = next
	for patch: Rect2 in ground_patches:
		_plane(logical_to_world(patch.get_center()), patch.size / WORLD_SCALE, earth)
	# The city is stone; the western and southern outskirts remain cultivated
	# ground. Rivers and the lake are subtracted from every paving patch.
	_paving_without_water(Rect2(1100, 500, 3300, 2340), 0.78, 0.001)
	for row: Array in _city_layout.get("street_bands", []):
		_paving_without_water(_rect(row), 0.99, 0.006)


func _paving_without_water(area: Rect2, tone: float, height: float) -> void:
	var patches: Array[Rect2] = [area]
	for water: Rect2 in _water_bounds:
		var next: Array[Rect2] = []
		for patch: Rect2 in patches:
			next.append_array(_subtract_rect(patch, water))
		patches = next
	for patch: Rect2 in patches:
		_large_paved_patch(patch, tone, height)


func _build_lot_geometry(bounds: Rect2, profile: Dictionary) -> void:
	var kind := str(profile.get("kind", "house"))
	var label := str(profile.get("label", "成都铺面"))
	_reference_kinds[kind] = int(_reference_kinds.get(kind, 0)) + 1
	_reference_lots.append({"id": str(profile.get("id", "")), "kind": kind, "bounds": bounds, "label": label})
	match kind:
		"wall", "city_wall":
			_build_city_wall(bounds, profile)
		"palace", "inner_palace":
			_build_palace(bounds, label)
		"temple":
			_build_temple(bounds, label)
		"academy":
			_build_academy(bounds, label)
		"pavilion":
			_build_reference_pavilion(bounds, label, 3 if label.contains("散花") else 1)
		"cottage":
			_build_cottage(bounds, label)
		"shrine":
			_build_shrine(bounds, label)
		"house":
			_build_dense_ward(bounds, label)
		"stall":
			_build_work_stall(bounds)
		_:
			var before := world_root.get_child_count()
			super._build_lot_geometry(bounds, profile)
			for index: int in range(before, world_root.get_child_count()):
				for text_node: Node in world_root.get_child(index).find_children("*", "Label3D", true, false):
					(text_node as Label3D).text = label
				if kind == "courtyard":
					var court := world_root.get_child(index) as Node3D
					var size := bounds.size / WORLD_SCALE
					_garden_tree(court, Vector3(size.x * 0.27, 0, size.y * 0.20), 2.4, true)


func _build_dense_ward(bounds: Rect2, label: String) -> void:
	var root := _lot_root(bounds, "ContinuousSmallRoofWard")
	var size := bounds.size / WORLD_SCALE
	var columns := maxi(1, ceili(bounds.size.x / 225.0))
	var rows := maxi(1, ceili(bounds.size.y / 245.0))
	var materials: Array[ShaderMaterial] = []
	for row: int in range(rows):
		for column: int in range(columns):
			var width := size.x / columns
			var depth := size.y / rows
			var house := Node3D.new()
			house.position = Vector3(-size.x * 0.5 + width * (column + 0.5), 0, -size.y * 0.5 + depth * (row + 0.5))
			root.add_child(house)
			var wall := _fade_material("#d1cbb6", "plaster")
			var tiles := _fade_material("#75887c", "roof", Vector2(maxf(width * 1.6, 1), 1.4))
			materials.append(wall)
			materials.append(tiles)
			var timber := _material("#81684f", "wood")
			_box(house, Vector3(0, 0.07, 0), Vector3(width, 0.14, depth), _material("#b1bca9", "stone"))
			_box(house, Vector3(0, 0.87, 0), Vector3(width - 0.06, 1.65, depth - 0.05), wall)
			for side: float in [-1, 1]:
				_box(house, Vector3(side * (width * 0.5 - 0.07), 0.86, depth * 0.5 - 0.015), Vector3(0.075, 1.65, 0.075), timber)
			_box(house, Vector3(width * 0.22, 0.78, depth * 0.5 + 0.01), Vector3(width * 0.32, 1.40, 0.05), timber)
			_box(house, Vector3(-width * 0.22, 1.03, depth * 0.5 + 0.015), Vector3(width * 0.30, 0.54, 0.035), _material("#667c6c", "flat"))
			for line: int in range(3):
				_box(house, Vector3(-width * 0.32 + line * width * 0.10, 1.03, depth * 0.5 + 0.04), Vector3(0.028, 0.56, 0.028), timber)
			_small_roof(house, Vector3(0, 1.76, 0), width - 0.40, depth - 0.36, tiles)
			if row == rows - 1 and column == 0:
				_sign(house, Vector3(0, 1.58, depth * 0.5 + 0.04), label, Vector2(minf(width * 0.8, 1.3), 0.22), 28)
	_register_lot_roof(root, materials)


func _small_roof(parent: Node3D, at: Vector3, width: float, depth: float, material: ShaderMaterial) -> void:
	var roof := Node3D.new()
	roof.position = at
	parent.add_child(roof)
	for side: int in [-1, 1]:
		var panel := MeshInstance3D.new()
		panel.mesh = _roof_surface(width, depth, side)
		panel.material_override = material
		roof.add_child(panel)
	var ridge := _cylinder(roof, Vector3(0, 0.49, 0), 0.048, width + 0.18, _material("#798a7d", "roof"))
	ridge.rotation.z = PI * 0.5


func _lot_root(bounds: Rect2, name_text: String) -> Node3D:
	var root := Node3D.new()
	root.name = name_text
	root.position = logical_to_world(bounds.get_center())
	world_root.add_child(root)
	solid_footprints.append(bounds)
	return root


func _register_lot_roof(body: Node3D, materials: Array[ShaderMaterial]) -> void:
	roof_rows.append({"node": body, "body": body, "materials": materials, "fade": 0.0})


func _compound_wall(root: Node3D, size: Vector2, height: float, material: ShaderMaterial) -> void:
	var cap := _material("#7d8d80", "roof")
	for side: float in [-1, 1]:
		_box(root, Vector3(side * (size.x * 0.5 - 0.07), height * 0.5, 0), Vector3(0.14, height, size.y), material)
		_box(root, Vector3(0, height * 0.5, side * (size.y * 0.5 - 0.07)), Vector3(size.x - 0.14, height, 0.14), material)
		_box(root, Vector3(side * (size.x * 0.5 - 0.07), height + 0.04, 0), Vector3(0.18, 0.10, size.y), cap)
		_box(root, Vector3(0, height + 0.04, side * (size.y * 0.5 - 0.07)), Vector3(size.x, 0.10, 0.18), cap)


func _hall(parent: Node3D, at: Vector3, width: float, depth: float, height: float, tiers: int, materials: Array[ShaderMaterial], straw: bool = false) -> Node3D:
	var hall := Node3D.new()
	hall.position = at
	parent.add_child(hall)
	var timber := _material("#805f43", "wood")
	var wall := _fade_material("#d9d0b7", "plaster")
	var roof_mat := _fade_material("#7a8a7e", "roof", Vector2(width * 1.6, 2))
	if straw:
		roof_mat.set_shader_parameter("surface_texture", _surface_texture("wood"))
		roof_mat.set_shader_parameter("surface_color", Color("#d7c18d"))
	materials.append(wall)
	materials.append(roof_mat)
	_box(hall, Vector3(0, 0.12, 0), Vector3(width, 0.24, depth), _material("#b9bca9", "stone"))
	_box(hall, Vector3(0, height * 0.5 + 0.14, -depth * 0.05), Vector3(width * 0.86, height, depth * 0.78), wall)
	for index: int in range(5):
		var x := lerpf(-width * 0.40, width * 0.40, index / 4.0)
		_box(hall, Vector3(x, height * 0.5 + 0.12, depth * 0.42), Vector3(0.10, height, 0.10), timber)
	_box(hall, Vector3(0, height * 0.48, depth * 0.35), Vector3(minf(width * 0.26, 0.82), height * 0.80, 0.06), timber)
	for side: float in [-1, 1]:
		_box(hall, Vector3(side * width * 0.28, height * 0.60, depth * 0.35), Vector3(width * 0.19, height * 0.35, 0.055), _material("#647a6d", "flat"))
	for tier: int in range(tiers):
		var factor := pow(0.77, tier)
		var roof_y := height + 0.18 + tier * 0.74
		if tier > 0:
			_box(hall, Vector3(0, roof_y - 0.20, 0), Vector3(width * factor * 0.8, 0.55, depth * factor * 0.75), wall)
		_roof(hall, Vector3(0, roof_y, 0), width * factor, depth * factor, roof_mat)
	return hall


func _closed_gate(parent: Node3D, at: Vector3, width: float, label: String, materials: Array[ShaderMaterial], height: float = 1.5) -> void:
	var wood := _material("#8e6c4b", "wood")
	_box(parent, at + Vector3.UP * height * 0.5, Vector3(width, height, 0.08), wood)
	for side: float in [-1, 1]:
		_box(parent, at + Vector3(side * width * 0.53, height * 0.52, 0.03), Vector3(0.12, height * 1.08, 0.15), wood)
		_cylinder(parent, at + Vector3(side * width * 0.17, height * 0.48, 0.065), 0.042, 0.035, _material("#d0b578", "flat")).rotation_degrees.x = 90
	_sign(parent, at + Vector3(0, height + 0.20, 0.08), label, Vector2(maxf(width * 1.3, 1.0), 0.30), 40)
	var tiles := _fade_material("#74877a", "roof")
	materials.append(tiles)
	_roof(parent, at + Vector3.UP * (height + 0.42), width * 1.60, 0.80, tiles)


func _build_city_wall(bounds: Rect2, profile: Dictionary) -> void:
	var root := _lot_root(bounds, "ReferenceCityWall")
	var size := bounds.size / WORLD_SCALE
	var height := float(profile.get("height", 2.2))
	var wall := _fade_material("#a7b3a2", "stone", Vector2(maxf(maxf(size.x, size.y) / 2.0, 1.0), maxf(height / 2.0, 1.0)))
	_box(root, Vector3(0, height * 0.5, 0), Vector3(size.x, height, size.y), wall)
	var cap := _material("#909f8d", "stone")
	_box(root, Vector3(0, height + 0.05, 0), Vector3(size.x, 0.10, size.y), cap)
	var along_x := size.x >= size.y
	var length := maxf(size.x, size.y)
	var count := maxi(1, floori(length / 0.72))
	for index: int in range(count):
		var value := -length * 0.5 + (index + 0.5) * length / count
		var at := Vector3(value, height + 0.23, 0) if along_x else Vector3(0, height + 0.23, value)
		_box(root, at, Vector3(0.35, 0.38, minf(size.y, 0.72)) if along_x else Vector3(minf(size.x, 0.72), 0.38, 0.35), cap)
	_register_lot_roof(root, [wall])


func _build_palace(bounds: Rect2, label: String) -> void:
	var root := _lot_root(bounds, "DoubleTerracedInnerCity")
	var size := bounds.size / WORLD_SCALE
	var wall := _fade_material("#c7c9b5", "plaster")
	var materials: Array[ShaderMaterial] = [wall]
	_compound_wall(root, size, 1.65, wall)
	var terrace := _material("#b5bbaa", "stone")
	_box(root, Vector3(0, 0.30, -size.y * 0.10), Vector3(size.x * 0.77, 0.60, size.y * 0.65), terrace)
	var inner_size := size * Vector2(0.78, 0.67)
	var inner := Node3D.new()
	inner.position = Vector3(0, 0.45, -size.y * 0.12)
	root.add_child(inner)
	_compound_wall(inner, inner_size, 0.75, wall)
	_hall(root, Vector3(0, 0.55, -size.y * 0.15), size.x * 0.63, size.y * 0.40, 2.05, 2, materials)
	_closed_gate(root, Vector3(0, 0, size.y * 0.5 - 0.02), minf(size.x * 0.24, 1.65), label, materials, 1.8)
	for index: int in range(5):
		_box(root, Vector3(0, 0.055 * (index + 1), size.y * 0.22 - index * 0.11), Vector3(1.50, 0.11 * (index + 1), 0.24), terrace)
	_register_lot_roof(root, materials)


func _build_temple(bounds: Rect2, label: String) -> void:
	var root := _lot_root(bounds, "ReferenceTempleCompound")
	var size := bounds.size / WORLD_SCALE
	var wall := _fade_material("#d6ccb2", "plaster")
	var materials: Array[ShaderMaterial] = [wall]
	_compound_wall(root, size, 0.95, wall)
	_hall(root, Vector3(0, 0, -size.y * 0.23), size.x * 0.70, size.y * 0.34, 1.85, 2, materials)
	if size.y > 4.0:
		for side: float in [-1, 1]:
			var wing := _hall(root, Vector3(side * size.x * 0.36, 0, size.y * 0.04), size.y * 0.47, size.x * 0.22, 1.35, 1, materials)
			wing.rotation.y = side * PI * 0.5
		if label.contains("大慈"):
			_pavilion(root, Vector3(size.x * 0.20, 0.0, size.y * 0.14), Vector2(1.5, 1.5), 3, materials)
		else:
			_pavilion(root, Vector3(-size.x * 0.22, 0, size.y * 0.19), Vector2(1.45, 1.35), 1, materials)
	_closed_gate(root, Vector3(0, 0, size.y * 0.5 - 0.02), minf(size.x * 0.22, 1.5), label, materials)
	for side: float in [-1, 1]:
		_garden_tree(root, Vector3(side * size.x * 0.35, 0, -size.y * 0.34), 2.5, side > 0)
	_register_lot_roof(root, materials)


func _build_academy(bounds: Rect2, label: String) -> void:
	var root := _lot_root(bounds, "WenwengStoneAcademy")
	var size := bounds.size / WORLD_SCALE
	var wall := _fade_material("#d3cfb6", "plaster")
	var materials: Array[ShaderMaterial] = [wall]
	_compound_wall(root, size, 0.72, wall)
	_hall(root, Vector3(0, 0, -size.y * 0.20), size.x * 0.80, size.y * 0.42, 1.55, 1, materials)
	_closed_gate(root, Vector3(0, 0, size.y * 0.5 - 0.02), 1.25, label, materials, 1.25)
	for index: int in range(4):
		_box(root, Vector3(-size.x * 0.26 + index * 0.20, 0.48, size.y * 0.18), Vector3(0.12, 0.95, 0.09), _material("#b5c0ad", "stone"))
	_garden_tree(root, Vector3(size.x * 0.35, 0, size.y * 0.12), 2.8, false)
	_register_lot_roof(root, materials)


func _pavilion(parent: Node3D, at: Vector3, size: Vector2, levels: int, materials: Array[ShaderMaterial]) -> void:
	var node := Node3D.new()
	node.position = at
	parent.add_child(node)
	var timber := _material("#8f6746", "wood")
	var roof_mat := _fade_material("#74867b", "roof", Vector2(size.x * 1.6, 1.5))
	materials.append(roof_mat)
	_box(node, Vector3(0, 0.13, 0), Vector3(size.x, 0.26, size.y), _material("#bcc3af", "stone"))
	for level: int in range(levels):
		var y := 0.20 + level * 1.35
		var shrink := pow(0.85, level)
		var width := size.x * shrink
		var depth := size.y * shrink
		for x: float in [-0.38, 0.38]:
			for z: float in [-0.38, 0.38]:
				_box(node, Vector3(x * width, y + 0.72, z * depth), Vector3(0.10, 1.45, 0.10), timber)
		_box(node, Vector3(0, y + 0.05, 0), Vector3(width, 0.10, depth), timber)
		if level > 0:
			for side: float in [-1, 1]:
				_box(node, Vector3(0, y + 0.33, side * depth * 0.44), Vector3(width * 0.92, 0.06, 0.06), timber)
		_roof(node, Vector3(0, y + 1.42, 0), width * 1.20, depth * 1.20, roof_mat)


func _build_reference_pavilion(bounds: Rect2, label: String, levels: int) -> void:
	var root := _lot_root(bounds, "ReferencePavilion")
	var materials: Array[ShaderMaterial] = []
	_pavilion(root, Vector3.ZERO, bounds.size / WORLD_SCALE * 0.76, levels, materials)
	_sign(root, Vector3(0, 1.25, bounds.size.y / WORLD_SCALE * 0.40), label, Vector2(1.2, 0.28), 38)
	_register_lot_roof(root, materials)


func _build_cottage(bounds: Rect2, label: String) -> void:
	var root := _lot_root(bounds, "ThatchedCottageGarden")
	var size := bounds.size / WORLD_SCALE
	var materials: Array[ShaderMaterial] = []
	_hall(root, Vector3(-size.x * 0.13, 0, -size.y * 0.17), size.x * 0.61, size.y * 0.35, 1.25, 1, materials, true)
	var wing := _hall(root, Vector3(size.x * 0.29, 0, size.y * 0.04), size.y * 0.36, size.x * 0.28, 1.05, 1, materials, true)
	wing.rotation.y = PI * 0.5
	var fence := _fade_material("#9f9c7f", "wood")
	materials.append(fence)
	_compound_wall(root, size, 0.42, fence)
	_closed_gate(root, Vector3(0, 0, size.y * 0.5 - 0.02), 0.85, label, materials, 0.85)
	_garden_tree(root, Vector3(-size.x * 0.36, 0, size.y * 0.28), 2.6, true)
	_garden_tree(root, Vector3(size.x * 0.34, 0, -size.y * 0.35), 2.8, false)
	_register_lot_roof(root, materials)


func _build_shrine(bounds: Rect2, label: String) -> void:
	var root := _lot_root(bounds, "WuhouAncestralCourt")
	var size := bounds.size / WORLD_SCALE
	var wall := _fade_material("#c7cbb4", "plaster")
	var materials: Array[ShaderMaterial] = [wall]
	_compound_wall(root, size, 0.72, wall)
	_hall(root, Vector3(size.x * 0.13, 0, -size.y * 0.16), size.x * 0.62, size.y * 0.42, 1.60, 1, materials)
	_closed_gate(root, Vector3(0, 0, size.y * 0.5 - 0.02), 1.25, label, materials)
	for side: float in [-1, 1]:
		_garden_tree(root, Vector3(side * size.x * 0.37, 0, -size.y * 0.08), 3.0, false)
	_box(root, Vector3(-size.x * 0.23, 0.48, size.y * 0.16), Vector3(0.64, 0.96, 0.22), _material("#9fae9d", "stone"))
	_register_lot_roof(root, materials)


func _garden_tree(parent: Node3D, at: Vector3, height: float, peach: bool) -> void:
	var tree := Node3D.new()
	tree.position = at
	parent.add_child(tree)
	var wood := _material("#8b785c", "wood")
	_cylinder(tree, Vector3(0, height * 0.36, 0), 0.08, height * 0.72, wood, 0.5)
	for index: int in range(5):
		var angle := index * 2.39996
		var reach := 0.22 + (index % 3) * 0.17
		var crown := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.52
		sphere.height = 0.72
		sphere.radial_segments = 9
		sphere.rings = 4
		crown.mesh = sphere
		crown.position = Vector3(cos(angle) * reach, height * 0.76 + (index % 2) * 0.22, sin(angle) * reach)
		crown.material_override = _material(["#c39fa0", "#d5b4b0", "#bd999c"][index % 3] if peach else ["#869b7a", "#99ab8b", "#a3b594"][index % 3], "flat")
		tree.add_child(crown)


func _build_water(bounds: Rect2) -> void:
	var profile := _building_profile(bounds)
	var pond := str(profile.get("id", "")).contains("pool") or str(profile.get("label", "")).contains("池")
	var water := _material("#7eaaa0" if pond else "#769d98", "flat")
	water.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plane(logical_to_world(bounds.get_center()) - Vector3.UP * 0.08, bounds.size / WORLD_SCALE, water)
	solid_footprints.append(bounds)
	_reference_water.append({"id": str(profile.get("id", "")), "bounds": bounds, "pond": pond})
	var count := clampi(roundi(bounds.size.x * bounds.size.y / 22000.0), 8, 32)
	for index: int in range(count):
		var x := bounds.position.x + 20 + fposmod(index * 113.7, maxf(bounds.size.x - 40, 1))
		var y := bounds.position.y + 20 + fposmod(index * 71.3, maxf(bounds.size.y - 40, 1))
		var at := logical_to_world(Vector2(x, y)) - Vector3.UP * 0.067
		var line := _plane(at, Vector2(0.35 + (index % 4) * 0.11, 0.018), _material("#aec7b5", "flat"))
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.set_meta("origin", line.position)
		_large_water_glints.append(line)
	if pond:
		# Low bank stones lie inside the water obstacle, never across a path.
		var stone := _material("#a8b8a5", "stone")
		for side: float in [-1, 1]:
			_box(world_root, logical_to_world(Vector2(bounds.get_center().x, bounds.get_center().y + side * (bounds.size.y * 0.5 - 5))) + Vector3.UP * 0.02, Vector3(bounds.size.x / WORLD_SCALE, 0.08, 0.11), stone)
		for side: float in [-1, 1]:
			var island := Node3D.new()
			island.position = logical_to_world(bounds.get_center() + Vector2(side * bounds.size.x * 0.37, -bounds.size.y * 0.27))
			world_root.add_child(island)
			_cylinder(island, Vector3(0, -0.01, 0), 0.44, 0.15, stone, 0.92)
			_garden_tree(island, Vector3.ZERO, 2.55, false)


func _build_edges() -> void:
	# City walls are authored collision lots, not the old rectangular map edge.
	# The wider playable outskirts stay open around them, like the reference.
	for item: Dictionary in _city_layout.get("decorations", []):
		var kind := str(item.get("kind", ""))
		if kind == "bridge":
			_build_reference_bridge(_rect(item.bounds), str(item.get("axis", "north_south")), str(item.get("label", "桥")))
		elif kind == "fields" or kind == "field":
			_build_fields(_rect(item.bounds))
		elif kind == "gate":
			_build_open_gate(_rect(item.bounds), str(item.get("label", "城门")), str(item.get("axis", "north_south")))


func _build_reference_bridge(bounds: Rect2, axis: String, label: String) -> void:
	_large_paved_patch(bounds, 1.02, 0.012)
	_bridge_decks.append({"label": label, "bounds": bounds, "axis": axis, "deck_height": 0.012})
	var stone := _material("#b3c0ae", "stone")
	var long_y := axis == "north_south"
	var sides: Array = [bounds.position.x - 8, bounds.end.x + 8] if long_y else [bounds.position.y - 8, bounds.end.y + 8]
	# Rails/posts only occupy the already-declared water on either side of the
	# clear navigation gap. The bridge deck itself adds no invisible obstacle.
	for side: float in sides:
		for water: Rect2 in _water_bounds:
			if long_y and side > water.position.x + 5 and side < water.end.x - 5:
				var first := maxf(bounds.position.y, water.position.y + 6)
				var last := minf(bounds.end.y, water.end.y - 6)
				if last <= first:
					continue
				_box(world_root, logical_to_world(Vector2(side, (first + last) * 0.5)) + Vector3.UP * 0.39, Vector3(0.07, 0.07, (last - first) / WORLD_SCALE), stone)
				for y: int in range(ceili(first + 6), floori(last), 60):
					_box(world_root, logical_to_world(Vector2(side, y)) + Vector3.UP * 0.24, Vector3(0.10, 0.48, 0.10), stone)
			elif not long_y and side > water.position.y + 5 and side < water.end.y - 5:
				var first := maxf(bounds.position.x, water.position.x + 6)
				var last := minf(bounds.end.x, water.end.x - 6)
				if last <= first:
					continue
				_box(world_root, logical_to_world(Vector2((first + last) * 0.5, side)) + Vector3.UP * 0.39, Vector3((last - first) / WORLD_SCALE, 0.07, 0.07), stone)
				for x: int in range(ceili(first + 6), floori(last), 60):
					_box(world_root, logical_to_world(Vector2(x, side)) + Vector3.UP * 0.24, Vector3(0.10, 0.48, 0.10), stone)


func _build_open_gate(bounds: Rect2, label: String, axis: String) -> void:
	# The authored gap is entirely open at ground level. The beam and roof sit
	# above the protagonist; piers are deliberately omitted from the free gap.
	var root := Node3D.new()
	root.name = "OpenReferenceCityGate"
	root.position = logical_to_world(bounds.get_center())
	if axis == "east_west":
		root.rotation.y = PI * 0.5
	world_root.add_child(root)
	var width := (bounds.size.x if axis != "east_west" else bounds.size.y) / WORLD_SCALE
	var stone := _material("#b3bcaa", "stone")
	_box(root, Vector3(0, 3.88, 0), Vector3(width + 0.25, 0.36, 0.85), stone)
	_sign(root, Vector3(0, 4.15, 0.48), label, Vector2(1.35, 0.35), 44)
	var mats: Array[ShaderMaterial] = []
	_hall(root, Vector3(0, 4.02, 0), width + 0.75, 1.45, 1.1, 1, mats)
	roof_rows.append({"node": root, "body": root, "materials": mats, "fade": 0.0, "logical_bounds": bounds, "render_height": 6.4})
	_body_rows.append({"body": root, "bounds": bounds, "height": 6.4})


func _build_fields(bounds: Rect2) -> void:
	var soil := _material("#a5af94", "flat")
	soil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plane(logical_to_world(bounds.get_center()) + Vector3.UP * 0.001, bounds.size / WORLD_SCALE, soil)
	var green := _material("#9eaf88", "flat")
	green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for y: int in range(int(bounds.position.y + 10), int(bounds.end.y), 28):
		_plane(logical_to_world(Vector2(bounds.get_center().x, y)) + Vector3.UP * 0.003, Vector2(bounds.size.x / WORLD_SCALE, 0.13), green)


func _build_landmarks() -> void:
	var first := world_root.get_child_count()
	super._build_landmarks()
	for index: int in range(first, world_root.get_child_count()):
		var node := world_root.get_child(index)
		if node is Label3D and (node as Label3D).text == "成都西门":
			(node as Label3D).text = "成都南门"


func audit() -> Dictionary:
	var result := super.audit()
	result["reference_geometry"] = {"kind_counts": _reference_kinds.duplicate(), "bridge_decks": _bridge_decks.duplicate(true), "water_footprints": _reference_water.duplicate(true), "landmark_lots": _reference_lots.duplicate(true), "reference_pixels_used": false, "camera_lookahead": _active_lookahead, "camera_default_lookahead": LOOK_AHEAD, "south_target_framing_distance": SOUTH_TARGET_FRAMING_DISTANCE}
	return result
