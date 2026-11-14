extends "res://addons/cultivation_mode/town_hd2d_stage.gd"
## Six authored views with city loops and a two-door teahouse. No game-state authority.

const ActorScript = preload("res://addons/cultivation_mode/chengdu_actor.gd")
const LAYOUT := "res://assets/data/chengdu-layout.json"
const ART_SOURCE := "res://assets/data/chengdu-art-source.json"
var district := "chengdu_gate"
var ambient_elapsed := 0.0
var _district_layout: Dictionary = {}
var _volume_actors: Dictionary = {}
var _last_ambient_tick := 0
var _river_glints: Array[MeshInstance3D] = []
var _river_umbrella: Node3D
var _returned_umbrella: Node3D


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	district = str(walker.get("scene_id"))
	if FileAccess.file_exists(LAYOUT):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
		if data is Dictionary:
			_district_layout = data.get("scenes", {}).get(district, {})
	super.setup(walker, font, definition)
	world_root.name = "Chengdu_" + district
	viewport.name = "Chengdu3DViewport"
	environment.background_color = Color("#c7cebd")
	environment.ambient_light_color = Color("#d1d8d5")
	environment.ambient_light_energy = 0.46
	sun.light_color = Color("#f4f2e9")
	sun.light_energy = 0.58
	_create_volume_actors()
	_last_ambient_tick = Time.get_ticks_usec()


func set_actor_frames(_player_frames: Dictionary, _seller_frames: Dictionary) -> void:
	# The city exclusively renders its original skinned models. Existing callers
	# retain their interface; old sheets cannot replace these characters.
	pass


func _create_volume_actors() -> void:
	var player_profile: Dictionary = {
		"model": "res://assets/art/town_volume_character/jiang-town.glb",
		"idle": "TownIdle", "walk": "TownWalk", "scale": 1.90 / 2.096427,
		"anchor": [0, 0.000216, 0.0], "cycle_distance": 1.4 * (1.90 / 2.096427) * WORLD_SCALE}
	_add_volume_actor("player", player_profile, _player)
	var npcs: Dictionary = {
		"tea_keeper": {"model": "res://assets/art/town_volume_cast/tea-seller.glb",
			"idle": "SellerCupWork", "scale": 0.9,
			"anchor": [0, 0.00033535502734594047, 0.09]},
		"tea_guest": {"model": "res://assets/art/town_volume_cast/tea-patron.glb",
			"idle": "PatronTea", "scale": 0.9038526507855911,
			"anchor": [0.10606449842453003, 0.33501386642456055, 0.13232819736003876],
			"seat_height": 0.302508, "yaw": PI * 0.5}}
	for id: String in npcs:
		if _definition.get("interactions", {}).has(id):
			_add_volume_actor(id, npcs[id], _interaction_point(id))
			if id == "tea_guest":
				_build_patron_seat(_interaction_point(id))
	for actor: Sprite3D in actor_nodes.values():
		actor.visible = false
	for contact: MeshInstance3D in shadow_nodes.values():
		contact.visible = false


func _add_volume_actor(id: String, profile: Dictionary, point: Vector2) -> void:
	var actor := ActorScript.new()
	actor.name = "ChengduActor_" + id
	world_root.add_child(actor)
	actor.setup(self, id, profile, point)
	_volume_actors[id] = actor


func sync(player_position: Vector2, facing: String, walking: bool, stride_distance: float, enabled: bool) -> void:
	var now := Time.get_ticks_usec()
	if enabled and _last_ambient_tick > 0:
		ambient_elapsed += clampf(float(now - _last_ambient_tick) / 1000000.0, 0.0, 0.05)
	_last_ambient_tick = now
	super.sync(player_position, facing, walking, stride_distance, enabled)
	for id: String in _volume_actors:
		_volume_actors[id].call("sync", player_position, stride_distance, walking and enabled, ambient_elapsed)
	for actor: Sprite3D in actor_nodes.values():
		actor.visible = false
	for contact: MeshInstance3D in shadow_nodes.values():
		contact.visible = false
	for index: int in range(_river_glints.size()):
		var glint := _river_glints[index]
		glint.position.x = -11.0 + fposmod(float(index) * 1.77 + ambient_elapsed * 0.055, 22.0)


func _actor_height(id: String) -> float:
	return 1.90 if id == "player" else 1.70


func target_screen_position(id: String) -> Vector2:
	if not _definition.get("interactions", {}).has(id):
		return Vector2(-1, -1)
	return logical_to_screen(_interaction_point(id), _target_height(id))


func _target_height(id: String) -> float:
	if id == "tea_keeper":
		return 1.05
	if id == "tea_guest":
		return 0.90
	if id == "market_teahouse_door":
		return 0.95
	if id == "gate_sign":
		return 0.12
	return 0.04


func _interaction_point(id: String) -> Vector2:
	var coordinates: Array = _definition.get("interactions", {}).get(id, {}).get("position", [640, 480])
	return Vector2(float(coordinates[0]), float(coordinates[1]))


func _surface_texture(kind: String) -> ImageTexture:
	if _surface_textures.has(kind):
		return _surface_textures[kind]
	var names: Dictionary = {"roof": "roof-gray-teal.svg", "plaster": "plaster-ivory.svg", "wood": "timber-honey.svg", "stone": "flagstone-graygreen.svg"}
	var path := "res://assets/art/shanxia_polish/materials/" + str(names.get(kind, "plaster-ivory.svg"))
	var source := load(path) as Texture2D
	var data := source.get_image()
	data.generate_mipmaps()
	var image_texture := ImageTexture.create_from_image(data)
	_surface_textures[kind] = image_texture
	return image_texture


func _material(color: String, kind: String = "plaster") -> StandardMaterial3D:
	var key := color + ":" + kind
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.roughness = 0.96
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if kind != "flat":
		mat.albedo_texture = _surface_texture(kind)
		if kind == "wood" or kind == "roof":
			var value := clampf(Color(color).get_luminance() * 0.32 + 0.73, 0.70, 1.0)
			mat.albedo_color = Color(value, value, value)
		elif kind == "stone":
			var value := clampf(Color(color).get_luminance() * 0.20 + 0.72, 0.72, 0.94)
			mat.albedo_color = Color(value, value, value)
	_materials[key] = mat
	return mat


func _fade_material(color: String, kind: String, repeats: Vector2 = Vector2.ONE) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _roof_shader
	mat.set_shader_parameter("surface_texture", _surface_texture(kind))
	var value := clampf(Color(color).get_luminance() * 0.18 + 0.80, 0.80, 0.98)
	mat.set_shader_parameter("surface_color", Color(value, value, value))
	mat.set_shader_parameter("repeat_uv", Vector2(maxf(repeats.x / 4.0, 1.0), 1.0) if kind == "roof" else repeats)
	mat.set_shader_parameter("fade", 0.0)
	return mat


func _build_ground() -> void:
	var earth := _material("#b5bdab", "flat")
	earth.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if district != "chengdu_river":
		_plane(Vector3(0, -0.08, 0), Vector2(42, 34), earth)
	else:
		_plane(logical_to_world(Vector2(640, -300)) - Vector3.UP * 0.08, Vector2(42, 24.0), earth)
	if district == "chengdu_teahouse":
		var timber := _material("#c1b59a", "wood").duplicate() as StandardMaterial3D
		timber.uv1_scale = Vector3(7.0, 1.0, 1.0)
		_plane(logical_to_world(Vector2(640, 405)), Vector2(14.5, 6.125), timber)
		for row: int in range(24):
			var y := 170.0 + row * 20.0
			_plane(logical_to_world(Vector2(640, y)) + Vector3.UP * 0.003, Vector2(14.4, 0.012), _material("#91866f", "flat"))
		return
	# Muted shared paving remains fully walkable; lighter authored road bands
	# explain turns and branches without introducing extra collision geometry.
	var paving := _material("#aab2a4", "stone").duplicate() as StandardMaterial3D
	paving.uv1_scale = Vector3(7.0, 3.0, 1.0)
	_plane(logical_to_world(Vector2(640, 405)), Vector2(14.5, 6.125), paving)
	for band: Array in _district_layout.get("street_bands", []):
		_paved_band(Rect2(float(band[0]), float(band[1]), float(band[2]), float(band[3])))
	if district == "chengdu_river":
		var water := _material("#7e9d99", "flat")
		water.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_plane(logical_to_world(Vector2(640, 970)) - Vector3.UP * 0.12, Vector2(44, 7.15), water)
		for index: int in range(27):
			var line := _plane(Vector3(-11 + float(index) * 0.83, -0.107, 4.05 + float(index % 7) * 0.35), Vector2(0.42 + float(index % 4) * 0.17, 0.025), _material("#a8bdb0", "flat"))
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_river_glints.append(line)


func _paved_band(bounds: Rect2) -> void:
	var mat := _material("#d0d4c8", "stone").duplicate() as StandardMaterial3D
	mat.uv1_scale = Vector3(maxf(bounds.size.x / 180.0, 0.4), maxf(bounds.size.y / 180.0, 0.4), 1)
	_plane(logical_to_world(bounds.get_center()) + Vector3.UP * 0.006, bounds.size / WORLD_SCALE, mat)


func _build_branch_portal(point: Vector2, text: String) -> void:
	var portal := Node3D.new()
	portal.name = "StreetOpening"
	portal.position = logical_to_world(point)
	world_root.add_child(portal)
	var timber := _material("#75654d", "wood")
	for side: float in [-1, 1]:
		_box(portal, Vector3(side * 0.85, 0.95, 0), Vector3(0.10, 1.9, 0.12), timber)
	_box(portal, Vector3(0, 1.88, 0), Vector3(1.95, 0.13, 0.16), timber)
	_sign(portal, Vector3(0, 1.66, 0.10), text, Vector2(1.30, 0.31), 42)
	var roof_mat := _fade_material("#78857a", "roof")
	var roof := _roof(portal, Vector3(0, 1.97, 0), 2.15, 0.68, roof_mat)
	roof_rows.append({"node": roof, "body": portal, "materials": [roof_mat], "fade": 0.0})


func _build_courtyard(bounds: Rect2) -> void:
	var court := Node3D.new()
	court.name = "ClosedWorkshopCourtyard"
	court.position = logical_to_world(bounds.get_center())
	world_root.add_child(court)
	var width := bounds.size.x / WORLD_SCALE
	var depth := bounds.size.y / WORLD_SCALE
	var timber := _material("#75634b", "wood")
	var wall := _fade_material("#d8cfb8", "plaster")
	var tiles := _fade_material("#78857a", "roof", Vector2(width * 1.6, 2))
	_box(court, Vector3(0, 0.06, 0), Vector3(width, 0.12, depth), _material("#b7baaa", "stone"))
	for side: float in [-1, 1]:
		_box(court, Vector3(side * (width * 0.5 - 0.07), 0.72, 0), Vector3(0.14, 1.44, depth), wall)
		_box(court, Vector3(0, 0.72, side * (depth * 0.5 - 0.07)), Vector3(width - 0.14, 1.44, 0.14), wall)
		_box(court, Vector3(side * (width * 0.5 - 0.07), 1.46, 0), Vector3(0.18, 0.10, depth), timber)
	var main_depth := minf(depth * 0.58, 1.9)
	_box(court, Vector3(0, 0.91, -depth * 0.5 + main_depth * 0.5), Vector3(width - 0.18, 1.7, main_depth - 0.1), wall)
	var roof := _roof(court, Vector3(0, 1.82, -depth * 0.5 + main_depth * 0.5), width, main_depth, tiles)
	# The closed street gate makes the whole private-courtyard collision clear.
	_box(court, Vector3(0, 0.76, depth * 0.5 + 0.006), Vector3(0.82, 1.4, 0.035), timber)
	for x: float in [-0.46, 0.46]:
		_box(court, Vector3(x, 0.80, depth * 0.5 + 0.04), Vector3(0.07, 1.55, 0.08), timber)
	_sign(court, Vector3(0, 1.52, depth * 0.5 + 0.08), "百工巷", Vector2(1.0, 0.27), 35)
	for x: float in [-0.22, 0.22]:
		_cylinder(court, Vector3(x, 0.85, depth * 0.5 + 0.04), 0.04, 0.03, _material("#afa07b", "flat")).rotation_degrees.x = 90
	if depth > 3.0:
		# A low lean-to and stocks remain inside the declared private footprint.
		_box(court, Vector3(-width * 0.23, 0.42, depth * 0.16), Vector3(width * 0.36, 0.7, 0.58), timber)
		_roof(court, Vector3(-width * 0.23, 1.00, depth * 0.16), width * 0.5, 0.8, tiles)
	solid_footprints.append(bounds)
	roof_rows.append({"node": roof, "body": court, "materials": [tiles, wall], "fade": 0.0})


func _build_work_stall(bounds: Rect2) -> void:
	var stall := Node3D.new()
	stall.name = "SquareWorkshopStall"
	stall.position = logical_to_world(bounds.get_center())
	world_root.add_child(stall)
	var width := bounds.size.x / WORLD_SCALE
	var depth := bounds.size.y / WORLD_SCALE
	var wood := _material("#8b7658", "wood")
	_box(stall, Vector3(0, 0.33, 0), Vector3(width, 0.66, depth), wood)
	for side: float in [-1, 1]:
		_box(stall, Vector3(side * width * 0.42, 1.0, 0), Vector3(0.09, 2.0, 0.09), wood)
	for index: int in range(4):
		_cylinder(stall, Vector3(-0.38 + index * 0.25, 0.77, 0.1), 0.09, 0.20, _material("#b3b79d"), 0.85)
	var roof_mat := _fade_material("#78857a", "roof")
	var roof := _roof(stall, Vector3(0, 1.65, 0), width + 0.16, depth, roof_mat)
	solid_footprints.append(bounds)
	roof_rows.append({"node": roof, "body": stall, "materials": [roof_mat], "fade": 0.0})


func _build_banyan(bounds: Rect2) -> void:
	var tree := Node3D.new()
	tree.name = "BanyanCourtCenter"
	tree.position = logical_to_world(bounds.get_center())
	world_root.add_child(tree)
	var size := bounds.size / WORLD_SCALE
	var stone := _material("#bac1b0", "stone")
	_box(tree, Vector3(0, 0.21, 0), Vector3(size.x, 0.42, size.y), stone)
	var trunk := _material("#827659", "wood")
	for index: int in range(3):
		_cylinder(tree, Vector3(-0.18 + index * 0.16, 1.12, 0.04 * (index % 2)), 0.18, 2.1, trunk, 0.66)
	for side: float in [-1, 1]:
		_beam(tree, Vector3(side * 0.1, 1.45, 0), Vector3(side * 1.05, 2.6, side * 0.42), 0.13, trunk)
		_beam(tree, Vector3(side * 0.1, 0.66, 0), Vector3(side * 0.78, 0.42, 0.22), 0.13, trunk)
	var leaves: Array[ShaderMaterial] = []
	for color: String in ["#7a8d72", "#8a9b7b", "#97a78b"]:
		var leaf := ShaderMaterial.new()
		leaf.shader = _roof_shader
		leaf.set_shader_parameter("surface_texture", _surface_texture("plaster"))
		leaf.set_shader_parameter("surface_color", Color(color))
		leaf.set_shader_parameter("repeat_uv", Vector2.ONE)
		leaf.set_shader_parameter("fade", 0.0)
		leaves.append(leaf)
	for index: int in range(15):
		var angle := float(index) * 2.39996
		var reach := 0.0 if index == 0 else 0.55 + (index % 3) * 0.42
		var crown := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.78
		sphere.height = 1.05
		sphere.radial_segments = 12
		sphere.rings = 5
		crown.mesh = sphere
		crown.position = Vector3(cos(angle) * reach, 2.70 + (index % 3) * 0.22, sin(angle) * reach * 0.72)
		crown.scale = Vector3(1.2, 1, 1.05)
		crown.material_override = leaves[index % leaves.size()]
		tree.add_child(crown)
	solid_footprints.append(bounds)
	roof_rows.append({"node": tree, "body": tree, "materials": leaves, "fade": 0.0})


func _build_house(bounds: Rect2, _stall: bool, backdrop: bool) -> void:
	if not backdrop:
		if district == "chengdu_teahouse":
			_build_table(bounds)
			return
		if district == "chengdu_lanes":
			_build_courtyard(bounds)
			return
		if district == "chengdu_square":
			if bounds.size.x > 150:
				_build_banyan(bounds)
			else:
				_build_work_stall(bounds)
			return
	super._build_house(bounds, false, backdrop)
	var house := world_root.get_child(world_root.get_child_count() - 1) as Node3D
	# _build_house creates the house as a single direct child, with all details.
	if house != null:
		for label: Node in house.find_children("*", "Label3D", true, false):
			(label as Label3D).text = str(_district_layout.get("shop_label", "成都铺面"))


func _build_edges() -> void:
	if district == "chengdu_teahouse":
		_build_teahouse_shell()
		return
	# A gap in each background frontage continues the actual north branch.
	var backdrops: Array = _district_layout.get("backdrop_houses", [])
	for row: Array in backdrops:
		_build_house(Rect2(float(row[0]), float(row[1]), float(row[2]), float(row[3])), false, true)
	for point: Array in _district_layout.get("edge_trees", []):
		_tree(Vector2(float(point[0]), float(point[1])), 3.0, int(point[0]))
	if district == "chengdu_gate":
		_build_city_gate()
	elif district == "chengdu_market":
		_build_teahouse_front()
	elif district == "chengdu_river":
		_build_river_quay()
	for portal: Dictionary in _district_layout.get("portals", []):
		var point: Array = portal.position
		_build_branch_portal(Vector2(float(point[0]), float(point[1])), str(portal.label))


func _build_city_gate() -> void:
	var gate := Node3D.new()
	gate.name = "ChengduWestGate"
	gate.position = logical_to_world(Vector2(640, 50))
	world_root.add_child(gate)
	var stone := _material("#a4a691", "stone")
	var wood := _material("#7b654e", "wood")
	for side: float in [-1.0, 1.0]:
		_box(gate, Vector3(side * 1.9, 1.2, 0), Vector3(1.05, 2.4, 1.3), stone)
		_box(gate, Vector3(side * 5.0, 0.8, 0), Vector3(5.3, 1.6, 0.9), stone)
		for x: int in range(7):
			_box(gate, Vector3(side * (2.6 + x * 0.75), 1.79, 0), Vector3(0.36, 0.42, 0.95), stone)
	_box(gate, Vector3(0, 2.25, 0), Vector3(4.7, 0.55, 1.4), stone)
	for side: float in [-1.0, 1.0]:
		_box(gate, Vector3(side * 1.60, 3.0, 0), Vector3(0.12, 1.2, 1.1), wood)
	_box(gate, Vector3(0, 2.65, -0.3), Vector3(3.2, 0.8, 0.12), _material("#d5c7a6"))
	_roof(gate, Vector3(0, 3.35, 0), 4.8, 1.8, _material("#75847a", "roof"))
	_sign(gate, Vector3(0, 2.15, 0.74), "成都", Vector2(1.30, 0.43), 62)
	for x: float in [-1.15, 1.15]:
		_lantern(gate, Vector3(x, 2.65, 0.84))


func _build_teahouse_front() -> void:
	# The central lane leads to an open tea doorway; both side walls lie in the
	# two existing obstacles. No invisible building blocks this entrance.
	var at := logical_to_world(Vector2(640, 170))
	_box(world_root, at + Vector3(0, 1.3, -0.18), Vector3(2.9, 0.12, 0.12), _material("#77634c", "wood"))
	for x: float in [-1.30, 1.30]:
		_box(world_root, at + Vector3(x, 0.65, -0.18), Vector3(0.11, 1.3, 0.11), _material("#77634c", "wood"))
	_sign(world_root, at + Vector3(0, 1.62, -0.15), "少城茶馆", Vector2(1.9, 0.38), 45)
	_roof(world_root, at + Vector3(0, 1.80, -0.20), 3.2, 1.05, _material("#78857a", "roof"))
	for x: float in [-1.0, 1.0]:
		_lantern(world_root, at + Vector3(x, 1.32, 0.3))


func _build_teahouse_shell() -> void:
	var timber := _material("#76624a", "wood")
	var wall := _material("#d7ccb0", "plaster")
	# Open south wall / omitted roof expose the interior, with a real courtyard
	# threshold into the street. Shell solids sit beyond floor borders.
	for x: float in [35, 1245]:
		_box(world_root, logical_to_world(Vector2(x, 400)) + Vector3.UP, Vector3(0.3, 2, 6.6), wall)
	# The rear opening is a real break in the north wall, opposite the front
	# entrance; furniture footprints come from walks.json and leave this axis.
	for bounds: Rect2 in [Rect2(24, 120, 536, 24), Rect2(720, 120, 536, 24)]:
		_box(world_root, logical_to_world(bounds.get_center()) + Vector3.UP, Vector3(bounds.size.x / WORLD_SCALE, 2, bounds.size.y / WORLD_SCALE), wall)
	for x: int in [80, 360, 920, 1200]:
		var at := logical_to_world(Vector2(x, 128))
		_box(world_root, at + Vector3.UP * 1.05, Vector3(0.13, 2.1, 0.30), timber)
		if x < 1200:
			var window_offset := 1.35 if x == 360 else 1.75
			var window_width := 1.9 if x == 360 else 2.4
			_box(world_root, at + Vector3(window_offset, 1.2, 0.17), Vector3(window_width, 0.65, 0.08), _material("#869385"))
			for offset: int in range(7):
				var lattice_x := 0.55 + offset * 0.25 if x == 360 else 0.65 + offset * 0.36
				_box(world_root, at + Vector3(lattice_x, 1.2, 0.22), Vector3(0.025, 0.65, 0.025), timber)
	for x: int in [560, 720]:
		_box(world_root, logical_to_world(Vector2(x, 132)) + Vector3.UP, Vector3(0.11, 2, 0.24), timber)
	_box(world_root, logical_to_world(Vector2(640, 132)) + Vector3.UP * 1.97, Vector3(2.11, 0.12, 0.24), timber)
	_sign(world_root, logical_to_world(Vector2(640, 138)) + Vector3.UP * 2.15, "百工巷", Vector2(1.45, 0.32), 42)
	_paved_band(Rect2(560, 65, 160, 95))
	for x: int in [180, 1100]:
		_lantern(world_root, logical_to_world(Vector2(x, 135)) + Vector3.UP * 1.7)
	# The shelves are outside the navigation floor.
	var shelf := logical_to_world(Vector2(1080, 142))
	_box(world_root, shelf + Vector3.UP * 0.55, Vector3(2.2, 1.1, 0.25), timber)
	for x: int in range(7):
		_cylinder(world_root, shelf + Vector3(-0.85 + x * 0.28, 1.16, 0), 0.09, 0.17, _material("#b5b69b"), 0.8)


func _build_table(bounds: Rect2) -> void:
	var center := logical_to_world(bounds.get_center())
	var width := bounds.size.x / WORLD_SCALE
	var depth := bounds.size.y / WORLD_SCALE
	var wood := _material("#927958", "wood")
	_box(world_root, center + Vector3.UP * 0.66, Vector3(width, 0.10, depth), wood)
	for x: float in [-width * 0.4, width * 0.4]:
		for z: float in [-depth * 0.4, depth * 0.4]:
			_box(world_root, center + Vector3(x, 0.31, z), Vector3(0.09, 0.62, 0.09), wood)
	for x: float in [-0.35, 0.25]:
		_cylinder(world_root, center + Vector3(x, 0.76, 0), 0.12, 0.12, _material("#c4c4a5"), 1.1)
	_cylinder(world_root, center + Vector3(0, 0.79, -0.24), 0.17, 0.19, _material("#8b9c8b"), 0.72)
	solid_footprints.append(bounds)


func _build_patron_seat(point: Vector2) -> void:
	var center := logical_to_world(point)
	var wood := _material("#937954", "wood")
	_box(world_root, center + Vector3.UP * 0.26, Vector3(0.62, 0.085, 0.53), wood)
	for x: float in [-0.23, 0.23]:
		for z: float in [-0.18, 0.18]:
			_box(world_root, center + Vector3(x, 0.12, z), Vector3(0.07, 0.24, 0.07), wood)


func _build_river_quay() -> void:
	var stone := _material("#a7ae9b", "stone")
	var wood := _material("#817158", "wood")
	# All high quay posts are on the non-walkable side of floor.end.y=650.
	_box(world_root, logical_to_world(Vector2(640, 674)) - Vector3.UP * 0.12, Vector3(17.5, 0.30, 0.27), stone)
	for index: int in range(18):
		var at := logical_to_world(Vector2(-40 + index * 80, 684))
		_box(world_root, at + Vector3.UP * 0.25, Vector3(0.13, 0.5, 0.13), stone)
	_box(world_root, logical_to_world(Vector2(640, 684)) + Vector3.UP * 0.40, Vector3(17.3, 0.08, 0.08), stone)
	# Cargo boat and tied crates are scenery beyond the playable riverbank.
	var boat := logical_to_world(Vector2(1040, 850)) - Vector3.UP * 0.06
	_box(world_root, boat, Vector3(3.0, 0.32, 0.9), wood)
	for side: float in [-1, 1]:
		_box(world_root, boat + Vector3(0, 0.24, side * 0.45), Vector3(3.05, 0.32, 0.07), wood)
	for index: int in range(3):
		_box(world_root, boat + Vector3(-0.65 + index * 0.6, 0.39, 0), Vector3(0.48, 0.40, 0.54), _material("#ad9974", "wood"))


func _build_landmarks() -> void:
	for id: String in _definition.get("interactions", {}):
		var at := logical_to_world(_interaction_point(id))
		var mat := _material("#b9baa0" if id.contains("exit") or id.contains("door") else "#b0af91", "flat")
		var ring := _cylinder(world_root, at + Vector3.UP * 0.012, 0.29, 0.012, mat)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if id == "market_goods":
			_box(world_root, at + Vector3.UP * 0.04, Vector3(0.60, 0.07, 0.48), _material("#a6a58c", "wood"))
			for i: int in range(3):
				_box(world_root, at + Vector3(-0.20 + i * 0.20, 0.10, 0), Vector3(0.16, 0.06, 0.36), _material(["#8a9b8f", "#b9aa83", "#b89578"][i]))
		elif id == "tea_lost_property":
			_box(world_root, at + Vector3.UP * 0.06, Vector3(0.38, 0.10, 0.28), _material("#b09c76", "wood"))
			_returned_umbrella = _make_umbrella(at + Vector3.UP * 0.10)
			_returned_umbrella.visible = false
		elif id == "river_umbrella":
			_river_umbrella = _make_umbrella(at)
		elif id == "gate_sign":
			var label := Label3D.new()
			label.text = "成都西门"
			label.font = _font
			label.font_size = 42
			label.pixel_size = 0.006
			label.modulate = Color("#5c6f62")
			label.position = at + Vector3.UP * 0.025
			label.rotation_degrees.x = -90
			label.outline_size = 0
			world_root.add_child(label)


func _make_umbrella(at: Vector3) -> Node3D:
	var umbrella := _cylinder(world_root, at + Vector3.UP * 0.065, 0.075, 0.78, _material("#aa9370", "wood"), 0.12)
	umbrella.rotation.z = PI * 0.5
	return umbrella


func set_city_flags(flags: Dictionary) -> void:
	# These nodes read the existing Session flags; presentation owns no quest
	# state, transaction or persistence. A rebuilt view receives the same flags.
	if is_instance_valid(_river_umbrella):
		_river_umbrella.visible = not bool(flags.get("chengdu_umbrella_taken", false))
	if is_instance_valid(_returned_umbrella):
		_returned_umbrella.visible = bool(flags.get("chengdu_umbrella_returned", false))


func audit() -> Dictionary:
	var result := super.audit()
	var actors := {}
	for id: String in _volume_actors:
		actors[id] = _volume_actors[id].call("audit")
	result["district"] = district
	result["layout_source"] = LAYOUT
	result["art_source"] = ART_SOURCE
	result["volume_actors"] = actors
	result["actor_count"] = _volume_actors.size()
	result["ambient_elapsed"] = ambient_elapsed
	result["river_outside_floor"] = district == "chengdu_river"
	result["river_umbrella_visible"] = is_instance_valid(_river_umbrella) and _river_umbrella.visible
	result["returned_umbrella_visible"] = is_instance_valid(_returned_umbrella) and _returned_umbrella.visible
	return result


func validate() -> Array[String]:
	var errors := super.validate()
	for id: String in _volume_actors:
		if not bool(_volume_actors[id].call("audit").get("available", false)):
			errors.append("Required Chengdu volume character did not load: " + id)
	return errors
