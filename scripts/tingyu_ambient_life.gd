extends Node

signal cat_petted
signal bird_started

const LifePresenter = preload("res://scripts/ambient_life_presenter.gd")
const CatMotion = preload("res://scripts/ambient_cat_motion.gd")
const CatDeskMotion = preload("res://scripts/tingyu_cat_desk_motion.gd")
const CONFIG_PATH := "res://assets/data/tingyu_ambient_life.json"
const ART_PATH := "res://assets/art/ambient_life/"
const CAT_PET_CURSOR_PATH := "res://assets/art/ui/cat-pet-cursor-v2.svg"

var presenter = LifePresenter.new()
var config: Dictionary = {}
var capabilities: Dictionary = {}
var visual_nodes: Dictionary = {}
var cat_spot: Marker2D
var _game: Control
var _scene_root: Control
var _background_root: Control
var _foreground_root: Control
var _markers: Node2D
var _bird_lane: Path2D
var _cat_walk_path: Path2D
var _cat_spots: Array[Marker2D] = []
var _bird_frames: Array[AtlasTexture] = []
var _cat_frames: Array[AtlasTexture] = []
var _cat_offsets: Array[Vector2] = []
var _cat_frame_scales: Array[float] = []
var _cat_frame_bounds: Array[Rect2] = []
var _cat_desk_motion = CatDeskMotion.new()
var _cat_pixel_scale := 1.0
var _cat_desk_frames_available := false
var _cat_serial := -1
var _cat_motion_serial := -1
var _bird_serial := -1
var _static_bird_event: Dictionary = {}
var _observed_dynamic := true
var _cat_retire_start := -1.0
var _cat_retire_alpha := 0.0
var _cat_pet_until := -1.0
var _cat_pose_index := 0
var _cat_hotspot: Button
var _cat_pet_cursor_registered := false
var _initial_cat_pending := false
var _initial_bird_pending := false
var _regular_cat_weather_chance: Dictionary = {}
var _regular_bird_weather_chance: Dictionary = {}


func setup(game: Control, scene_root: Control, background_root: Control, foreground_root: Control) -> void:
	_game = game
	_scene_root = scene_root
	_background_root = background_root
	_foreground_root = foreground_root
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	presenter.configure(config)
	_markers = scene_root.get_node_or_null("AmbientCapabilities") as Node2D
	refresh_capabilities()
	_schedule_initial_arrivals()
	_build_visuals()
	observe_environment()


func refresh_capabilities() -> void:
	_cat_spots.clear()
	_bird_lane = null
	_cat_walk_path = null
	if _markers != null:
		_bird_lane = _markers.get_node_or_null("BirdLane") as Path2D
		_cat_walk_path = _markers.get_node_or_null("CatWalk_Desk") as Path2D
		for marker in _markers.get_children():
			if marker is Marker2D and str(marker.name).begins_with("CatSpot_"):
				_cat_spots.append(marker)
	var sheltered := false
	for spot in _cat_spots:
		sheltered = sheltered or bool(spot.get_meta("sheltered", false))
	capabilities = {
		"birds": _valid_path(_bird_lane),
		"squirrel": false,
		"cat": not _cat_spots.is_empty(),
		"fish": false,
		"cat_sheltered": sheltered,
		"cat_night_allowed": false,
		"cat_desk_walk": _valid_path(_cat_walk_path) and bool(_cat_walk_path.get_meta("sheltered", false)),
	}


func _valid_path(path: Path2D) -> bool:
	return path != null and path.curve != null and path.curve.get_point_count() >= 2 and path.curve.get_baked_length() > 0.0


func get_capabilities() -> Dictionary:
	return capabilities.duplicate()


func _build_visuals() -> void:
	var sheet: Texture2D = load(ART_PATH + "birds.svg")
	for frame in 3:
		var texture := AtlasTexture.new()
		texture.atlas = sheet
		texture.region = Rect2(frame * 24, 0, 24, 14)
		texture.filter_clip = true
		_bird_frames.append(texture)
	var birds := _make_root("TingyuDistantBirds", _background_root)
	for index in 3:
		var bird := _sprite("Bird%d" % index, _bird_frames[0], birds)
		bird.scale = Vector2.ONE * float(config.visuals.bird_scale)
	visual_nodes.birds = birds

	var cat := _make_root("TingyuRestingCat", _foreground_root)
	_build_cat_frames()
	var sleeper := _sprite("Cat", _cat_frames[0], cat)
	sleeper.centered = false
	_set_cat_pose(sleeper, 0)
	sleeper.scale = Vector2.ONE * float(config.visuals.cat_scale) * _cat_pixel_scale
	visual_nodes.cat = cat
	_cat_hotspot = Button.new()
	_cat_hotspot.name = "TingyuCatPet"
	_cat_hotspot.flat = true
	_cat_hotspot.tooltip_text = "摸摸猫"
	_cat_hotspot.focus_mode = Control.FOCUS_ALL
	# This otherwise unused shape keeps the pet hand separate from ordinary buttons.
	Input.set_custom_mouse_cursor(load(CAT_PET_CURSOR_PATH), Input.CURSOR_DRAG, Vector2(8, 24))
	_cat_pet_cursor_registered = true
	_cat_hotspot.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_cat_hotspot.z_index = 1
	_cat_hotspot.disabled = true
	_cat_hotspot.pressed.connect(_on_cat_petted)
	_foreground_root.add_child(_cat_hotspot)
	var transparent_style := StyleBoxFlat.new()
	transparent_style.bg_color = Color(0, 0, 0, 0)
	_cat_hotspot.add_theme_stylebox_override("normal", transparent_style)
	_cat_hotspot.add_theme_stylebox_override("hover", transparent_style)
	_cat_hotspot.add_theme_stylebox_override("pressed", transparent_style)
	_cat_hotspot.add_theme_stylebox_override("disabled", transparent_style)
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color(0, 0, 0, 0)
	focus_style.border_color = Color("c9a65b")
	focus_style.set_border_width_all(1)
	focus_style.set_corner_radius_all(3)
	_cat_hotspot.add_theme_stylebox_override("focus", focus_style)
	_cat_hotspot.size = Vector2(110, 74)


func _build_cat_frames() -> void:
	var sheet: Texture2D = load(ART_PATH + "orange-cat-painterly-v2.png")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART_PATH + "orange-cat-layout-v2.json"))
	_cat_pixel_scale = float(layout.logical_width) / float(layout.cell_width)
	for index in layout.frames.size():
		var data: Dictionary = layout.frames[index]
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(data.region[0], data.region[1], data.region[2], data.region[3])
		frame.filter_clip = true
		frame.set_meta("pose_index", index)
		_cat_frames.append(frame)
		_cat_offsets.append(-Vector2(data.pivot[0], data.pivot[1]))
		_cat_frame_scales.append(_cat_pixel_scale)
		_cat_frame_bounds.append(_rect_from_layout(data.get("opaque_bounds", [])))
	_load_cat_desk_frames()


func _load_cat_desk_frames() -> void:
	var sheet_path := ART_PATH + "tingyu-cat-desk-v1.png"
	var layout_path := ART_PATH + "tingyu-cat-desk-layout-v1.json"
	if not FileAccess.file_exists(sheet_path) or not FileAccess.file_exists(layout_path):
		return
	var layout_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if not layout_value is Dictionary:
		return
	var layout: Dictionary = layout_value
	var frames_value: Variant = layout.get("frames", [])
	if not frames_value is Array or (frames_value as Array).size() != 6:
		return
	var cell_width := float(layout.get("cell_width", 0.0))
	var logical_width := float(layout.get("logical_width", 0.0))
	if cell_width <= 0.0 or logical_width <= 0.0:
		return
	var frames: Array = frames_value
	for index in 6:
		var value: Variant = frames[index]
		if not value is Dictionary:
			return
		var data: Dictionary = value
		if int(data.get("pose_index", -1)) != 8 + index:
			return
		if not _layout_array_has_size(data.get("region", []), 4):
			return
		if not _layout_array_has_size(data.get("pivot", []), 2):
			return
		if not _layout_array_has_size(data.get("opaque_bounds", []), 4):
			return
		var region := _rect_from_layout(data.region)
		var bounds := _rect_from_layout(data.opaque_bounds)
		if region.size.x <= 0.0 or region.size.y <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
			return
	var desk_sheet := load(sheet_path) as Texture2D
	if desk_sheet == null:
		return
	var frame_scale := logical_width / cell_width
	for index in 6:
		var data: Dictionary = frames[index]
		var frame := AtlasTexture.new()
		frame.atlas = desk_sheet
		frame.region = _rect_from_layout(data.region)
		frame.filter_clip = true
		frame.set_meta("pose_index", 8 + index)
		_cat_frames.append(frame)
		_cat_offsets.append(-Vector2(float(data.pivot[0]), float(data.pivot[1])))
		_cat_frame_scales.append(frame_scale)
		_cat_frame_bounds.append(_rect_from_layout(data.opaque_bounds))
	_cat_desk_frames_available = true


func _layout_array_has_size(value: Variant, expected_size: int) -> bool:
	return value is Array and (value as Array).size() == expected_size


func _rect_from_layout(value: Variant) -> Rect2:
	if not _layout_array_has_size(value, 4):
		return Rect2()
	var values: Array = value
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


func _set_cat_pose(sprite: Sprite2D, index: int) -> void:
	sprite.texture = _cat_frames[index]
	sprite.offset = _cat_offsets[index]


func _ensure_cat_event(event: Dictionary) -> void:
	var serial := int(event.serial)
	if not is_instance_valid(cat_spot) or _cat_serial != serial:
		_cat_serial = serial
		cat_spot = _choose_cat_spot(serial)
		_cat_retire_start = -1.0
		_cat_retire_alpha = 0.0
		_cat_desk_motion.reset()
		_cat_motion_serial = -1
	if _cat_motion_serial == serial or not is_instance_valid(cat_spot):
		return
	_cat_motion_serial = serial
	if _cat_walk_available():
		_cat_desk_motion.start(_cat_walk_path, cat_spot.to_global(Vector2.ZERO))


func _cat_walk_available() -> bool:
	return bool(capabilities.get("cat_desk_walk", false)) and _cat_desk_frames_available


func _cat_motion_can_advance(events: Dictionary) -> bool:
	return (
		_cat_desk_motion.active
		and _game.weather.enabled
		and not _life_attention_busy()
		and not events.has("birds")
		and not pet_active()
		and _cat_retire_start < 0.0
	)


func _advance_cat_motion(elapsed_before: float) -> void:
	var events: Dictionary = presenter.get_active_events()
	if not events.has("cat"):
		return
	var event: Dictionary = events.cat
	_ensure_cat_event(event)
	if not _cat_desk_motion.active:
		return
	var activity_start := maxf(elapsed_before, float(event.start))
	var activity_delta := maxf(0.0, float(presenter.elapsed) - activity_start)
	if _cat_motion_can_advance(events):
		_cat_desk_motion.advance(activity_delta)


func _make_root(node_name: String, parent: Control) -> Node2D:
	var node := Node2D.new()
	node.name = node_name
	node.visible = false
	parent.add_child(node)
	return node


func _sprite(node_name: String, texture: Texture2D, parent: Node2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	sprite.material = material
	parent.add_child(sprite)
	return sprite


func observe_environment() -> void:
	var dynamic: bool = _game.weather.enabled
	if _observed_dynamic and not dynamic:
		_static_bird_event = presenter.get_active_events().get("birds", {}).duplicate(true)
	elif not _observed_dynamic and dynamic and not _static_bird_event.is_empty():
		# Restore only this frozen encounter, with unchanged elapsed and serial.
		presenter._active_events["birds"] = _static_bird_event.duplicate(true)
		_static_bird_event.clear()
	_observed_dynamic = dynamic
	if _game.weather.presenter.weather_id == "light_rain":
		_static_bird_event.clear()
	var environment_presenter = _game.weather.presenter
	presenter.observe({
		"time_profile_id": environment_presenter.time_profile_id,
		"weather_id": environment_presenter.weather_id,
		"night_preview": environment_presenter.night_preview,
		"dynamic_enabled": _game.weather.enabled,
	}, capabilities)
	_render()


func advance(delta: float) -> Array:
	var elapsed_before := float(presenter.elapsed)
	observe_environment()
	var attention_busy := _life_attention_busy() or is_salient_active()
	_defer_initial_arrivals(delta, attention_busy)
	var requests: Array = presenter.advance(delta, attention_busy)
	_finish_initial_arrivals_if_started(requests)
	_advance_cat_motion(elapsed_before)
	_render()
	return requests


func is_salient_active() -> bool:
	if pet_active():
		return true
	if _game == null or not is_instance_valid(_game.weather):
		return false
	var events: Dictionary = presenter.get_active_events()
	if events.has("birds") and _valid_path(_bird_lane) and _game.weather.enabled:
		return true
	return visual_nodes.has("cat") and (visual_nodes.cat as Node2D).visible and _cat_pose_index != 0


func pet_active() -> bool:
	return (
		_game != null
		and is_instance_valid(_game.weather)
		and _game.weather.enabled
		and _cat_pet_until > float(presenter.elapsed) + 0.000001
		and not _life_attention_busy()
	)


func force_event(kind: String) -> bool:
	observe_environment()
	var event: Dictionary = presenter.force_event(kind)
	_render()
	return not event.is_empty()


func resume_auto() -> void:
	presenter.resume_auto()
	observe_environment()


func set_enabled(value: bool) -> void:
	presenter.set_enabled(value)
	observe_environment()


func reset() -> void:
	presenter.reset()
	cat_spot = null
	_cat_serial = -1
	_bird_serial = -1
	_static_bird_event.clear()
	_observed_dynamic = _game.weather.enabled
	_cat_retire_start = -1.0
	_cat_retire_alpha = 0.0
	_cat_pet_until = -1.0
	_cat_pose_index = 0
	_cat_desk_motion.reset()
	_cat_motion_serial = -1
	_initial_cat_pending = false
	_initial_bird_pending = false
	_schedule_initial_arrivals()
	if visual_nodes.has("cat"):
		_set_cat_pose(visual_nodes.cat.get_child(0) as Sprite2D, 0)
		(visual_nodes.cat.get_child(0) as Sprite2D).modulate = Color.WHITE
	if is_instance_valid(_cat_hotspot):
		_cat_hotspot.disabled = true
	observe_environment()


func _render() -> void:
	for node in visual_nodes.values():
		node.visible = false
	var events: Dictionary = presenter.get_active_events()
	if not _game.weather.enabled and not _static_bird_event.is_empty():
		events["birds"] = _static_bird_event
	if not events.has("cat"):
		_cat_pet_until = -1.0
		_cat_desk_motion.reset()
		_cat_motion_serial = -1
	elif not _game.weather.enabled or _life_attention_busy():
		_cat_pet_until = -1.0
	if events.has("birds") and _valid_path(_bird_lane) and (_game.weather.enabled or not _static_bird_event.is_empty()):
		var event: Dictionary = events.birds
		var bird_serial := int(event.serial)
		if bird_serial != _bird_serial:
			_bird_serial = bird_serial
			if not bool(event.get("forced", false)):
				bird_started.emit()
		var age := maxf(0.0, float(presenter.elapsed) - float(event.start))
		var duration := maxf(0.01, float(event.duration))
		var birds: Node2D = visual_nodes.birds
		birds.visible = true
		var progress := clampf(age / duration, 0.0, 1.0)
		birds.position = _bird_lane.curve.sample_baked(progress * _bird_lane.curve.get_baked_length())
		birds.modulate.a = float(config.visuals.bird_alpha) * _fade(age, duration, 1.4)
		for index in birds.get_child_count():
			var bird := birds.get_child(index) as Sprite2D
			bird.visible = index < int(event.count)
			bird.texture = _bird_frames[int(age * 3.0 + index) % _bird_frames.size()]
			bird.position = Vector2(-index * 13.0, index * 7.0 + sin(age * 1.1 + index) * 1.2)

	if events.has("cat"):
		var event: Dictionary = events.cat
		_ensure_cat_event(event)
		if is_instance_valid(cat_spot) and _cat_spots.has(cat_spot):
			var raining: bool = _game.weather.presenter.weather_id == "light_rain"
			var cat: Node2D = visual_nodes.cat
			if raining and not bool(cat_spot.get_meta("sheltered", false)) and _cat_retire_start < 0.0:
				# Retire this encounter in place; the next event may choose shelter.
				_cat_retire_start = float(presenter.elapsed)
				_cat_retire_alpha = cat.modulate.a
			var retire_weight := 1.0
			if _cat_retire_start >= 0.0:
				var fade_seconds := maxf(0.001, float(config.motion.get("cat_weather_fade_seconds", 1.2)))
				retire_weight = clampf(1.0 - (float(presenter.elapsed) - _cat_retire_start) / fade_seconds, 0.0, 1.0)
			if retire_weight > 0.0:
				var age := maxf(0.0, float(presenter.elapsed) - float(event.start))
				cat.visible = true
				var motion_active: bool = _cat_desk_motion.active and _cat_motion_serial == int(event.serial)
				if motion_active:
					cat.position = _foreground_root.get_global_transform().affine_inverse() * _cat_desk_motion.global_position()
				else:
					cat.position = cat_spot.position
				# Static freezes elapsed, including the current fade opacity.
				var alpha := float(config.visuals.cat_alpha) * _fade(age, float(event.duration), 1.0)
				cat.modulate.a = minf(alpha, _cat_retire_alpha * retire_weight) if _cat_retire_start >= 0.0 else alpha
				var sprite := cat.get_child(0) as Sprite2D
				var values: Dictionary = _game.weather.presenter.get_current_environment()
				var wind := clampf(float(values.get("wind_strength", 0.0)), 0.0, 1.0)
				var attention_busy: bool = _life_attention_busy() or events.has("birds") or _cat_retire_start >= 0.0
				var pose := 0
				var facing := _cat_desk_motion.facing_x() if motion_active else 1.0
				var body_bob := 0.0
				var motion_allowed: bool = motion_active and _cat_motion_can_advance(events)
				if pet_active():
					pose = 7
				elif motion_active:
					if not motion_allowed:
						pose = 13 if _cat_desk_motion.is_walking() else maxi(0, _cat_desk_motion.pose_index())
					else:
						pose = _cat_desk_motion.pose_index()
						if pose < 0:
							pose = CatMotion.idle_pose(
								_cat_desk_motion.activity_elapsed,
								wind,
								str(_game.weather.presenter.time_profile_id),
								str(_game.weather.presenter.weather_id),
								config.motion,
								false
							)
						else:
							body_bob = _cat_desk_motion.body_bob()
				elif _game.weather.enabled:
					pose = CatMotion.idle_pose(
						age,
						wind,
						str(_game.weather.presenter.time_profile_id),
						str(_game.weather.presenter.weather_id),
						config.motion,
						attention_busy
					)
				_set_cat_pose(sprite, pose)
				_cat_pose_index = pose
				var frame_scale := _cat_frame_scales[pose] if pose < _cat_frame_scales.size() else _cat_pixel_scale
				var scale := float(config.visuals.cat_scale) * frame_scale
				sprite.scale = Vector2(scale * (-1.0 if facing < 0.0 else 1.0), scale)
				sprite.position = Vector2(0.0, -body_bob)
				sprite.modulate = _game.weather.get_lantern_tint(cat.position)
	_refresh_cat_hotspot()


func _choose_cat_spot(serial: int) -> Marker2D:
	var candidates: Array[Marker2D] = []
	var sunny: Array[Marker2D] = []
	var weather_id: String = _game.weather.presenter.weather_id
	for spot in _cat_spots:
		if weather_id == "light_rain" and not bool(spot.get_meta("sheltered", false)):
			continue
		candidates.append(spot)
		if bool(spot.get_meta("sunny", false)):
			sunny.append(spot)
	if weather_id == "clear" and not sunny.is_empty():
		candidates = sunny
	return candidates[posmod(serial, candidates.size())] if not candidates.is_empty() else null


func _schedule_initial_arrivals() -> void:
	_regular_cat_weather_chance = config.get("cat", {}).get("weather_chance", {}).duplicate(true)
	_regular_bird_weather_chance = config.get("birds", {}).get("weather_chance", {}).duplicate(true)
	_initial_cat_pending = false
	_initial_bird_pending = false
	if presenter.next_due.has("cat") and bool(capabilities.get("cat", false)):
		var cat_rng := RandomNumberGenerator.new()
		cat_rng.seed = int(config.get("seed", 0)) + 731
		var cat_settings: Dictionary = config.get("cat", {})
		presenter.next_due["cat"] = cat_rng.randf_range(
			float(cat_settings.get("first_opportunity_min_seconds", 18.0)),
			float(cat_settings.get("first_opportunity_max_seconds", 26.0))
		)
		_set_presenter_weather_chance("cat", _all_weather_chance(_regular_cat_weather_chance))
		_initial_cat_pending = true
	if presenter.next_due.has("birds") and bool(capabilities.get("birds", false)):
		var bird_rng := RandomNumberGenerator.new()
		bird_rng.seed = int(config.get("seed", 0)) + 137
		var bird_settings: Dictionary = config.get("birds", {})
		presenter.next_due["birds"] = bird_rng.randf_range(
			float(bird_settings.get("first_opportunity_min_seconds", 70.0)),
			float(bird_settings.get("first_opportunity_max_seconds", 100.0))
		)
		var first_bird_chance := _regular_bird_weather_chance.duplicate(true)
		first_bird_chance["clear"] = 1.0
		_set_presenter_weather_chance("birds", first_bird_chance)
		_initial_bird_pending = true


func _all_weather_chance(chances: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for weather_id in chances:
		result[weather_id] = 1.0
	return result


func _set_presenter_weather_chance(kind: String, chances: Dictionary) -> void:
	var presenter_config: Dictionary = presenter._config
	var kind_settings: Dictionary = presenter_config.get(kind, {}).duplicate(true)
	kind_settings["weather_chance"] = chances.duplicate(true)
	presenter_config[kind] = kind_settings
	presenter._config = presenter_config


func _defer_initial_arrivals(delta: float, attention_busy: bool) -> void:
	var target_time := float(presenter.elapsed) + maxf(delta, 0.0)
	if _initial_cat_pending and float(presenter.next_due.get("cat", INF)) <= target_time:
		if attention_busy or not presenter.can_spawn("cat"):
			presenter.next_due["cat"] = target_time + 0.25
	if _initial_bird_pending:
		var bird_due := float(presenter.next_due.get("birds", INF))
		var cloudy_quiet_gap: bool = _game.weather.presenter.weather_id == "cloudy" and target_time < 120.0
		if cloudy_quiet_gap:
			presenter.next_due["birds"] = maxf(bird_due, 120.0)
		elif bird_due <= target_time and (attention_busy or not presenter.can_spawn("birds")):
			presenter.next_due["birds"] = target_time + 0.25


func _finish_initial_arrivals_if_started(requests: Array) -> void:
	var events: Dictionary = presenter.get_active_events()
	var cat_started := events.has("cat") and not bool(events.cat.get("forced", false))
	var bird_started := events.has("birds") and not bool(events.birds.get("forced", false))
	for request in requests:
		if bool(request.get("forced", false)):
			continue
		cat_started = cat_started or str(request.get("kind", "")) == "cat"
		bird_started = bird_started or str(request.get("kind", "")) == "birds"
	if _initial_cat_pending and cat_started:
		_initial_cat_pending = false
		_set_presenter_weather_chance("cat", _regular_cat_weather_chance)
	if _initial_bird_pending and bird_started:
		_initial_bird_pending = false
		_set_presenter_weather_chance("birds", _regular_bird_weather_chance)


func _life_attention_busy() -> bool:
	var busy: bool = _game.foreground_attention_busy()
	if _game.has_method("scene_life_attention_busy"):
		busy = busy or bool(_game.call("scene_life_attention_busy"))
	return busy


func _can_pet_cat() -> bool:
	if not visual_nodes.has("cat") or not is_instance_valid(_cat_hotspot):
		return false
	var cat: Node2D = visual_nodes.cat
	return (
		cat.visible
		and cat.modulate.a > 0.001
		and _game.weather.enabled
		and not _life_attention_busy()
		and _cat_retire_start < 0.0
		and is_instance_valid(cat_spot)
		and not presenter.get_active_events().has("birds")
		and not pet_active()
	)


func _refresh_cat_hotspot() -> void:
	if not is_instance_valid(_cat_hotspot) or not visual_nodes.has("cat"):
		return
	var cat: Node2D = visual_nodes.cat
	var hit_rect := _cat_hotspot_rect(cat)
	_cat_hotspot.position = hit_rect.position
	_cat_hotspot.size = hit_rect.size
	var hotspot_visible := cat.visible and cat.modulate.a > 0.001
	var can_pet := _can_pet_cat()
	_cat_hotspot.visible = hotspot_visible
	_cat_hotspot.mouse_filter = Control.MOUSE_FILTER_STOP if hotspot_visible and can_pet else Control.MOUSE_FILTER_IGNORE
	_cat_hotspot.disabled = not can_pet
	_cat_hotspot.mouse_default_cursor_shape = Control.CURSOR_DRAG if can_pet else Control.CURSOR_ARROW


func _cat_hotspot_rect(cat: Node2D) -> Rect2:
	var fallback := Rect2(cat.position + Vector2(-55, -70), Vector2(110, 74))
	if _cat_pose_index < 0 or _cat_pose_index >= _cat_frame_bounds.size():
		return fallback
	var bounds := _cat_frame_bounds[_cat_pose_index]
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return fallback
	var sprite := cat.get_child(0) as Sprite2D
	var first := cat.position + sprite.position + (bounds.position + sprite.offset) * sprite.scale
	var last := cat.position + sprite.position + (bounds.position + bounds.size + sprite.offset) * sprite.scale
	var minimum := Vector2(minf(first.x, last.x), minf(first.y, last.y))
	var maximum := Vector2(maxf(first.x, last.x), maxf(first.y, last.y))
	return Rect2(minimum, maximum - minimum).grow(4.0)


func _on_cat_petted() -> void:
	if not _can_pet_cat():
		_refresh_cat_hotspot()
		return
	_cat_pet_until = float(presenter.elapsed) + float(config.get("cat", {}).get("pet_seconds", 2.4))
	_render()
	cat_petted.emit()


func _fade(age: float, duration: float, seconds: float) -> float:
	return clampf(minf(age / seconds, (duration - age) / seconds), 0.0, 1.0)


func _exit_tree() -> void:
	if _cat_pet_cursor_registered:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_DRAG)
