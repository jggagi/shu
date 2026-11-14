extends "res://addons/cultivation_mode/chengdu_stage.gd"
## One persistent outdoor world. The existing walker owns all movement/state;
## only this camera and local presentation visibility change during a walk.

const LARGE_LAYOUT := "res://assets/data/chengdu-large-layout.json"
const FOLLOW_ELEVATION := 52.0
const FOLLOW_DISTANCE := 13.5
const DEADZONE := Vector2(125, 80)
const LABEL_FRAME := Rect2(35, 35, 1210, 625)
var layout_path := LARGE_LAYOUT
var _city_layout: Dictionary = {}
var _world_size := Vector2(3840, 2160)
var _world_floor := Rect2(80, 120, 3680, 1960)
var _camera_center := Vector2.ZERO
var _camera_goal := Vector2.ZERO
var _camera_limits := Rect2(440, 450, 2960, 1320)
var _camera_initialized := false
var _camera_tick := 0
var _building_count := 0
var _built_once := false
var _body_rows: Array[Dictionary] = []
var _body_by_instance: Dictionary = {}
var _water_bounds: Array[Rect2] = []
var _large_water_glints: Array[MeshInstance3D] = []


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if data is Dictionary:
		_city_layout = data.get("scenes", {}).get("chengdu_city", {})
	var dimensions: Array = definition.get("size", [3840, 2160])
	_world_size = Vector2(float(dimensions[0]), float(dimensions[1]))
	var floor_row: Array = definition.get("floor", [80, 120, 3680, 1960])
	_world_floor = _rect(floor_row)
	_camera_limits = Rect2(_world_floor.position + Vector2(360, 330), _world_floor.size - Vector2(720, 640))
	for row: Dictionary in _city_layout.get("buildings", []):
		if str(row.get("kind", "")) == "water":
			_water_bounds.append(_rect(row.bounds))
	super.setup(walker, font, definition)
	world_root.name = "ContinuousChengduWorld"
	viewport.name = "ContinuousChengduViewport"
	camera.fov = 39.0
	camera.rotation_degrees = Vector3(-FOLLOW_ELEVATION, 0, 0)
	camera.far = 150.0
	sun.directional_shadow_max_distance = 38.0
	_built_once = true
	_camera_tick = Time.get_ticks_usec()


func _rect(row: Array) -> Rect2:
	return Rect2(float(row[0]), float(row[1]), float(row[2]), float(row[3]))


func sync(player_position: Vector2, facing: String, walking: bool, stride_distance: float, enabled: bool) -> void:
	var now := Time.get_ticks_usec()
	var delta := clampf(float(now - _camera_tick) / 1000000.0, 0.0, 0.05) if _camera_tick > 0 else 0.0
	_camera_tick = now
	_update_follow_camera(player_position, delta, not _camera_initialized)
	super.sync(player_position, facing, walking, stride_distance, enabled)
	for index: int in range(_large_water_glints.size()):
		var line := _large_water_glints[index]
		line.position = (line.get_meta("origin") as Vector3) + Vector3(sin(ambient_elapsed * 0.25 + index) * 0.04, 0, 0)


func _update_follow_camera(point: Vector2, delta: float, snap: bool) -> void:
	if snap:
		_camera_goal = point
	else:
		var difference := point - _camera_goal
		for axis: int in range(2):
			if absf(difference[axis]) > DEADZONE[axis]:
				_camera_goal[axis] = point[axis] - signf(difference[axis]) * DEADZONE[axis]
	_camera_goal = _camera_goal.clamp(_camera_limits.position, _camera_limits.end)
	_camera_center = _camera_goal if snap else _camera_center.lerp(_camera_goal, 1.0 - exp(-delta / 0.13))
	var offset := Vector3(0, sin(deg_to_rad(FOLLOW_ELEVATION)), cos(deg_to_rad(FOLLOW_ELEVATION))) * FOLLOW_DISTANCE
	camera.position = logical_to_world(_camera_center) + offset
	_camera_initialized = true


func _build_ground() -> void:
	var earth := _material("#b5bdab", "flat")
	earth.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plane(logical_to_world(_world_size * 0.5) - Vector3.UP * 0.18, _world_size / WORLD_SCALE + Vector2(30, 30), earth)
	# Split the floor around actual water obstacles, never paint walkable paving
	# over the river. All non-water space remains the same navigation floor.
	var patches: Array[Rect2] = [_world_floor]
	for water: Rect2 in _water_bounds:
		var next: Array[Rect2] = []
		for patch: Rect2 in patches:
			next.append_array(_subtract_rect(patch, water))
		patches = next
	for patch: Rect2 in patches:
		_large_paved_patch(patch, 0.78, 0.0)
	for row: Array in _city_layout.get("street_bands", []):
		_large_paved_patch(_rect(row), 0.99, 0.006)


func _subtract_rect(area: Rect2, removed: Rect2) -> Array[Rect2]:
	if not area.intersects(removed):
		return [area]
	var overlap := area.intersection(removed)
	var result: Array[Rect2] = []
	for patch: Rect2 in [
		Rect2(area.position, Vector2(area.size.x, overlap.position.y - area.position.y)),
		Rect2(Vector2(area.position.x, overlap.end.y), Vector2(area.size.x, area.end.y - overlap.end.y)),
		Rect2(Vector2(area.position.x, overlap.position.y), Vector2(overlap.position.x - area.position.x, overlap.size.y)),
		Rect2(Vector2(overlap.end.x, overlap.position.y), Vector2(area.end.x - overlap.end.x, overlap.size.y))]:
		if patch.size.x > 0.01 and patch.size.y > 0.01:
			result.append(patch)
	return result


func _large_paved_patch(bounds: Rect2, tone: float, height: float) -> void:
	var mat := _material("#c0c8ba", "stone").duplicate() as StandardMaterial3D
	mat.albedo_color = Color(tone, tone, tone)
	mat.uv1_scale = Vector3(maxf(bounds.size.x / 180.0, 0.1), maxf(bounds.size.y / 180.0, 0.1), 1)
	_plane(logical_to_world(bounds.get_center()) + Vector3.UP * height, bounds.size / WORLD_SCALE, mat)


func _build_house(bounds: Rect2, _stall: bool, _backdrop: bool) -> void:
	var profile := _building_profile(bounds)
	var kind := str(profile.get("kind", "house"))
	var row_start := roof_rows.size()
	var node_start := world_root.get_child_count()
	if kind == "water":
		_build_water(bounds)
		return
	_build_lot_geometry(bounds, profile)
	_building_count += 1
	# Store primary lot bounds once. Culling/occlusion never rebuild geometry.
	for index: int in range(node_start, world_root.get_child_count()):
		var body := world_root.get_child(index) as Node3D
		if body == null:
			continue
		var row := {"body": body, "bounds": bounds, "height": maxf(float(profile.get("height", 3.4)), 3.4)}
		_body_rows.append(row)
		_body_by_instance[body.get_instance_id()] = row
	for index: int in range(row_start, roof_rows.size()):
		roof_rows[index]["logical_bounds"] = bounds
		roof_rows[index]["render_height"] = maxf(float(profile.get("height", 3.4)), 3.4)


func _build_lot_geometry(bounds: Rect2, profile: Dictionary) -> void:
	var kind := str(profile.get("kind", "house"))
	if kind == "courtyard":
		_build_courtyard(bounds)
	elif kind == "banyan":
		_build_banyan(bounds)
	elif kind == "teahouse":
		_build_shop_row(bounds, 1, str(profile.get("label", "少城茶馆")))
		_add_teahouse_rear(bounds)
	else:
		var count := maxi(1, floori(bounds.size.x / 290.0))
		_build_shop_row(bounds, count, str(profile.get("label", "成都铺面")))


func _building_profile(bounds: Rect2) -> Dictionary:
	for row: Dictionary in _city_layout.get("buildings", []):
		if _rect(row.bounds) == bounds:
			return row
	return {}


func _build_shop_row(bounds: Rect2, count: int, label: String) -> void:
	for index: int in range(count):
		var width := bounds.size.x / float(count)
		var part := Rect2(bounds.position + Vector2(index * width, 0), Vector2(width, bounds.size.y))
		# Call the base architecture helper directly; this does not recursively
		# dispatch city lots or import the old six-scene layout.
		super._build_house(part, false, true)
		var house := world_root.get_child(world_root.get_child_count() - 1) as Node3D
		if house == null:
			continue
		for sign_node: Node in house.find_children("*", "Label3D", true, false):
			(sign_node as Label3D).text = label
		# Backdrop mode suppresses the old roof-row registration; use the actual
		# local house surfaces so a person passing behind a lot stays readable.
		var materials: Array[ShaderMaterial] = []
		for node: Node in house.find_children("*", "MeshInstance3D", true, false):
			var material := (node as MeshInstance3D).material_override as ShaderMaterial
			if material != null and not materials.has(material):
				materials.append(material)
		roof_rows.append({"node": house, "body": house, "materials": materials, "fade": 0.0})


func _add_teahouse_rear(bounds: Rect2) -> void:
	var rear := Node3D.new()
	rear.name = "TeahouseRearDoor"
	rear.position = logical_to_world(Vector2(bounds.get_center().x, bounds.position.y + 2))
	rear.rotation.y = PI
	world_root.add_child(rear)
	var timber := _material("#8c7050", "wood")
	_box(rear, Vector3(0, 0.7, 0), Vector3(0.88, 1.35, 0.06), timber)
	_sign(rear, Vector3(0, 1.55, 0.06), "少城茶馆", Vector2(1.45, 0.30), 42)


func _build_water(bounds: Rect2) -> void:
	var water := _material("#7e9d99", "flat")
	water.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plane(logical_to_world(bounds.get_center()) - Vector3.UP * 0.08, bounds.size / WORLD_SCALE, water)
	solid_footprints.append(bounds)
	var stone := _material("#a7ae9b", "stone")
	var left := bounds.position.x + 8.0
	# Rail posts stay within the already-blocked river footprint.
	for y: int in range(int(bounds.position.y + 20), int(bounds.end.y), 85):
		var at := logical_to_world(Vector2(left, y))
		_box(world_root, at + Vector3.UP * 0.22, Vector3(0.11, 0.44, 0.11), stone)
	_box(world_root, logical_to_world(Vector2(left, bounds.get_center().y)) + Vector3.UP * 0.36, Vector3(0.07, 0.07, bounds.size.y / WORLD_SCALE), stone)
	for index: int in range(36):
		var at := logical_to_world(Vector2(bounds.position.x + 42 + (index % 3) * 82, bounds.position.y + 45 + index * 43))
		var line := _plane(at - Vector3.UP * 0.067, Vector2(0.44 + (index % 4) * 0.10, 0.018), _material("#a8bdb0", "flat"))
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Retain position as metadata; the original south-river loop is not used.
		line.set_meta("origin", line.position)
		_large_water_glints.append(line)


func _build_edges() -> void:
	var wall := _material("#b9bfaf", "plaster")
	var cap := _material("#7a897c", "roof")
	for bounds: Rect2 in [Rect2(15, 65, 3760, 25), Rect2(15, 2120, 3760, 25), Rect2(15, 90, 25, 1540), Rect2(15, 1890, 25, 255)]:
		var at := logical_to_world(bounds.get_center())
		_box(world_root, at + Vector3.UP * 0.58, Vector3(bounds.size.x / WORLD_SCALE, 1.16, bounds.size.y / WORLD_SCALE), wall)
		_box(world_root, at + Vector3.UP * 1.20, Vector3(bounds.size.x / WORLD_SCALE + 0.04, 0.10, bounds.size.y / WORLD_SCALE + 0.04), cap)
	_build_west_gate()
	for point: Vector2 in [Vector2(55, 1100), Vector2(1150, 85), Vector2(2990, 95), Vector2(3785, 1500), Vector2(1700, 2145)]:
		_tree(point, 3.6, int(point.x))


func _build_west_gate() -> void:
	var gate := Node3D.new()
	gate.name = "ChengduWestCityGate"
	gate.position = logical_to_world(Vector2(20, 1760))
	gate.rotation.y = PI * 0.5
	world_root.add_child(gate)
	var stone := _material("#a4a691", "stone")
	for side: float in [-1, 1]:
		_box(gate, Vector3(side * 1.55, 1.05, 0), Vector3(0.75, 2.1, 1.15), stone)
	_box(gate, Vector3(0, 2.1, 0), Vector3(3.85, 0.44, 1.15), stone)
	_box(gate, Vector3(0, 2.65, 0), Vector3(2.7, 0.9, 0.9), _material("#d1c6a8", "plaster"))
	_roof(gate, Vector3(0, 3.16, 0), 4.25, 1.55, _material("#75847a", "roof"))
	_sign(gate, Vector3(0, 2.02, 0.65), "成都", Vector2(1.15, 0.34), 52)


func _update_occlusion(delta: float, snap: bool) -> void:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	var center := logical_to_screen(_player, _actor_height("player") * 0.5)
	var player_rect := Rect2(center - Vector2(22, 40), Vector2(44, 80))
	var ground_rect := visible_ground_rect().grow(_visibility_padding())
	for row: Dictionary in _body_rows:
		(row.body as Node3D).visible = (row.bounds as Rect2).intersects(ground_rect)
	occluded_count = 0
	for row: Dictionary in roof_rows:
		var bounds: Rect2 = row.get("logical_bounds", Rect2())
		var covered := false
		if bounds.has_area() and bounds.intersects(ground_rect):
			covered = _project_lot(bounds, float(row.get("render_height", 3.5))).intersects(player_rect)
		if covered:
			occluded_count += 1
		var fade := float(row.fade)
		fade = (1.0 if covered else 0.0) if snap else lerpf(fade, 1.0 if covered else 0.0, 1.0 - exp(-delta / 0.12))
		row.fade = fade
		for material: ShaderMaterial in row.materials:
			material.set_shader_parameter("fade", fade)
			material.set_shader_parameter("player_uv", center / DISPLAY)


func _visibility_padding() -> float:
	return 230.0


func _project_lot(bounds: Rect2, height: float) -> Rect2:
	var result := Rect2()
	var initialized := false
	for point: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		for y: float in [0.0, height]:
			var at := logical_to_screen(point, y)
			if not initialized:
				result = Rect2(at, Vector2.ZERO)
				initialized = true
			else:
				result = result.expand(at)
	return result


func visible_ground_rect() -> Rect2:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return Rect2()
	var rect := Rect2(screen_to_logical(Vector2.ZERO), Vector2.ZERO)
	for point: Vector2 in [Vector2(DISPLAY.x, 0), DISPLAY, Vector2(0, DISPLAY.y)]:
		rect = rect.expand(screen_to_logical(point))
	return rect


func is_point_visible(point: Vector2, height: float = 0.0, padding: float = 0.0) -> bool:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return false
	if camera.is_position_behind(logical_to_world(point) + Vector3.UP * height):
		return false
	return Rect2(-padding, -padding, DISPLAY.x + padding * 2, DISPLAY.y + padding * 2).has_point(logical_to_screen(point, height))


func is_target_visible(id: String) -> bool:
	if not _definition.get("interactions", {}).has(id):
		return false
	var point := _interaction_point(id)
	return is_point_visible(point) and LABEL_FRAME.has_point(logical_to_screen(point))


func visible_interaction_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in _definition.get("interactions", {}):
		if is_target_visible(id):
			result.append(id)
	return result


func region_for(point: Vector2) -> Dictionary:
	for region: Dictionary in _city_layout.get("regions", []):
		if _rect(region.bounds).has_point(point):
			return region.duplicate(true)
	return {}


func audit() -> Dictionary:
	var result := super.audit()
	var region := region_for(_player)
	result["large_city"] = true
	result["scene_size"] = _world_size
	result["camera_center"] = _camera_center
	result["camera_limits"] = [_camera_limits.position.x, _camera_limits.position.y, _camera_limits.end.x, _camera_limits.end.y]
	result["camera_deadzone"] = DEADZONE
	result["visible_ground_rect"] = visible_ground_rect()
	result["visible_interaction_ids"] = visible_interaction_ids()
	result["player_screen"] = logical_to_screen(_player)
	result["player_head_screen"] = logical_to_screen(_player, 1.9)
	result["region"] = str(region.get("id", ""))
	result["region_label"] = str(region.get("label", "成都城"))
	result["layout_source"] = layout_path
	result["world_build_count"] = 1 if _built_once else 0
	result["visible_lots"] = _visible_lot_count()
	result["city_building_count"] = _building_count
	return result


func _visible_lot_count() -> int:
	var count := 0
	for row: Dictionary in _body_rows:
		if (row.body as Node3D).visible:
			count += 1
	return count
