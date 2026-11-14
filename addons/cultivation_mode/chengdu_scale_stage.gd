extends "res://addons/cultivation_mode/chengdu_reference_stage.gd"
## The enlarged, authored city keeps the same person, house and camera scale.
## Navigation owns every obstacle from the outset. Only ordinary house meshes
## are prepared near the camera; this presenter never changes walk geometry.

const SCALE_LAYOUT := "res://assets/data/chengdu-scale-layout.json"
const HOUSE_PREFETCH := 800.0
const HOUSE_BATCH_SIZE := 4
var _pending_houses: Array[Dictionary] = []
var _house_profiles: Dictionary = {}
var _authored_lots := 0
var _authored_houses := 0
var _built_houses := 0
var _streaming_ready := false
var _initial_build_usec := 0
var _largest_stream_batch_usec := 0
var _stream_batches := 0
var _last_batch_count := 0


func _init() -> void:
	layout_path = SCALE_LAYOUT


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	# Indexing uses the same authored bounds as walks.json, not generated mesh
	# positions. LargeStage's setup will read this layout for its other helpers.
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if data is Dictionary:
		for profile: Dictionary in data.get("scenes", {}).get("chengdu_city", {}).get("buildings", []):
			_house_profiles[_rect(profile.bounds)] = profile
			if str(profile.get("kind", "house")) != "water":
				_authored_lots += 1
			if bool(profile.get("individual_house", false)):
				_authored_houses += 1
	super.setup(walker, font, definition)
	world_root.name = "EnlargedChengduWorld"
	viewport.name = "EnlargedChengduViewport"
	_player = walker.get("player_position") as Vector2
	_update_follow_camera(_player, 0.0, true)
	_streaming_ready = true
	# New scenes and restored saves show their complete nearby streets before
	# the first drawable frame. Ordinary movement subsequently builds at most
	# four prefetched lots per frame, well ahead of the visible road.
	_build_nearby_houses(true)
	_update_occlusion(1.0, true)
	_initial_build_usec = Time.get_ticks_usec() - started


func _building_profile(bounds: Rect2) -> Dictionary:
	return _house_profiles.get(bounds, {})


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
	for row: Array in _city_layout.get("city_paving", []):
		_paving_without_water(_rect(row), 0.78, 0.001)
	for row: Array in _city_layout.get("street_bands", []):
		_paving_without_water(_rect(row), 0.99, 0.006)


func _build_house(bounds: Rect2, stall: bool, backdrop: bool) -> void:
	if bool(_building_profile(bounds).get("individual_house", false)):
		_pending_houses.append({"bounds": bounds, "stall": stall, "backdrop": backdrop})
		return
	# Water, the authored city walls, temples, palace and tea entrances remain
	# available immediately. Those distinctive silhouettes frame long streets.
	super._build_house(bounds, stall, backdrop)


func _build_dense_ward(bounds: Rect2, label: String) -> void:
	if not bool(_building_profile(bounds).get("individual_house", false)):
		# The named weaving compound is authored as a larger closed workshop;
		# it retains the reference architecture rather than becoming a wide home.
		super._build_dense_ward(bounds, label)
		return
	# Each authored ordinary lot is one small building, with real traversable
	# streets between lots. No oversized block is subdivided into false lanes.
	var root := _lot_root(bounds, "ChengduStreetHouse")
	var size := bounds.size / WORLD_SCALE
	var variation := posmod(roundi(bounds.position.x + bounds.position.y), 3)
	var wall := _fade_material(["#d1cbb6", "#c9c8b2", "#d8cfb7"][variation], "plaster")
	var tiles := _fade_material(["#75887c", "#7b8b7e", "#71857a"][variation], "roof", Vector2(maxf(size.x * 1.6, 1.0), 1.4))
	var timber := _material("#81684f", "wood")
	_box(root, Vector3(0, 0.07, 0), Vector3(size.x, 0.14, size.y), _material("#b1bca9", "stone"))
	_box(root, Vector3(0, 0.87, 0), Vector3(size.x - 0.06, 1.65, size.y - 0.05), wall)
	for side: float in [-1, 1]:
		_box(root, Vector3(side * (size.x * 0.5 - 0.07), 0.86, size.y * 0.5 - 0.015), Vector3(0.075, 1.65, 0.075), timber)
	_box(root, Vector3(size.x * 0.22, 0.78, size.y * 0.5 + 0.01), Vector3(size.x * 0.32, 1.40, 0.05), timber)
	_box(root, Vector3(-size.x * 0.22, 1.03, size.y * 0.5 + 0.015), Vector3(size.x * 0.30, 0.54, 0.035), _material("#667c6c", "flat"))
	_small_roof(root, Vector3(0, 1.76, 0), size.x - 0.40, size.y - 0.36, tiles)
	_register_lot_roof(root, [wall, tiles])
	_built_houses += 1


func _build_nearby_houses(immediate: bool) -> void:
	if not _streaming_ready or _pending_houses.is_empty():
		_last_batch_count = 0
		return
	var nearby := visible_ground_rect().grow(HOUSE_PREFETCH)
	var ready: Array[Dictionary] = []
	for row: Dictionary in _pending_houses:
		var bounds: Rect2 = row.bounds
		if bounds.intersects(nearby):
			ready.append({"row": row, "distance": bounds.get_center().distance_squared_to(_player)})
	ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var count := ready.size() if immediate else mini(HOUSE_BATCH_SIZE, ready.size())
	_last_batch_count = count
	if count == 0:
		return
	var started := Time.get_ticks_usec()
	for index: int in range(count):
		_materialize_house(ready[index].row)
	if not immediate:
		_stream_batches += 1
		_largest_stream_batch_usec = maxi(_largest_stream_batch_usec, Time.get_ticks_usec() - started)


func _materialize_house(row: Dictionary) -> void:
	_pending_houses.erase(row)
	# LargeStage also registers the new body's bounds and its fading materials;
	# the ordinary reference architecture dispatches to our single-house helper.
	super._build_house(row.bounds, bool(row.stall), bool(row.backdrop))


func build_all_lots_for_overview() -> void:
	# Explicit QA overview preparation; normal gameplay never calls this method
	# and retains its close following camera and incremental preparation.
	var remaining := _pending_houses.duplicate()
	for row: Dictionary in remaining:
		_materialize_house(row)


func _update_occlusion(delta: float, snap: bool) -> void:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	_build_nearby_houses(snap)
	var center := logical_to_screen(_player, _actor_height("player") * 0.5)
	var player_rect := Rect2(center - Vector2(22, 40), Vector2(44, 80))
	var ground_rect := visible_ground_rect().grow(_visibility_padding())
	for row: Dictionary in _body_rows:
		(row.body as Node3D).visible = (row.bounds as Rect2).intersects(ground_rect)
	occluded_count = 0
	for row: Dictionary in roof_rows:
		var bounds: Rect2 = row.get("logical_bounds", Rect2())
		var nearby := bounds.has_area() and bounds.intersects(ground_rect)
		var previous := float(row.fade)
		# Distant opaque roofs need neither projection tests nor per-material
		# shader writes. A roof finishing a fade still settles completely.
		if not nearby and previous <= 0.0001:
			continue
		var covered := nearby and _project_lot(bounds, float(row.get("render_height", 3.5))).intersects(player_rect)
		if covered:
			occluded_count += 1
		var target := 1.0 if covered else 0.0
		var fade := target if snap else lerpf(previous, target, 1.0 - exp(-delta / 0.12))
		if absf(fade - target) < 0.0001:
			fade = target
		row.fade = fade
		if not covered and fade == previous:
			continue
		for material: ShaderMaterial in row.materials:
			material.set_shader_parameter("fade", fade)
			if fade > 0.0:
				material.set_shader_parameter("player_uv", center / DISPLAY)


func audit() -> Dictionary:
	var result := super.audit()
	result["scale_geometry"] = {
		"authored_lots": _authored_lots,
		"built_lots": _building_count,
		"visible_lots": _visible_authored_lot_count(),
		"visible_lot_bodies": _visible_lot_count(),
		"authored_houses": _authored_houses,
		"built_houses": _built_houses,
		"pending_houses": _pending_houses.size(),
		"house_roof_panels": _built_houses * 2,
		"roof_groups": roof_rows.size(),
		"prefetch_distance": HOUSE_PREFETCH,
		"max_houses_per_moving_frame": HOUSE_BATCH_SIZE,
		"last_batch_houses": _last_batch_count,
		"incremental_batches": _stream_batches,
		"largest_incremental_batch_usec": _largest_stream_batch_usec,
		"initial_build_usec": _initial_build_usec,
		"all_navigation_obstacles_present": geometry.size() == _definition.get("obstacles", []).size(),
		"camera_distance_unchanged": FOLLOW_DISTANCE,
		"world_size": _world_size}
	return result


func _visible_authored_lot_count() -> int:
	var visible: Dictionary = {}
	for row: Dictionary in _body_rows:
		var bounds: Rect2 = row.bounds
		if (row.body as Node3D).visible and _house_profiles.has(bounds):
			visible[bounds] = true
	return visible.size()
