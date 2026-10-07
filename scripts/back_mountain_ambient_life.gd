extends Node

signal cat_petted

const LifePresenter = preload("res://scripts/ambient_life_presenter.gd")
const CatMotion = preload("res://scripts/ambient_cat_motion.gd")
const CONFIG_PATH := "res://assets/data/back_mountain_ambient_life.json"
const ART_PATH := "res://assets/art/ambient_life/"

var presenter = LifePresenter.new()
var visual_nodes: Dictionary = {}
var capabilities: Dictionary = {}
var config: Dictionary = {}
var cat_spot: Marker2D
var cat_hotspot: Button
var _game: Control
var _markers: Node2D
var _bird_lane: Path2D
var _squirrel_path: Path2D
var _cat_spots: Array[Marker2D] = []
var _bird_frames: Array[AtlasTexture] = []
var _squirrel_frames: Array[AtlasTexture] = []
var _cat_frames: Array[AtlasTexture] = []
var _cat_offsets: Array[Vector2] = []
var _cat_pixel_scale := 1.0
var _cat_serial := -1
var _cat_pet_start := -100.0


func setup(game: Control) -> void:
	_game = game
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	presenter.configure(config)
	_markers = game.get_node_or_null("AmbientCapabilities") as Node2D
	if _markers != null:
		_markers.reparent(game._art_root, false)
	refresh_capabilities()
	_build_visuals()
	observe_environment()


func refresh_capabilities() -> void:
	_cat_spots.clear()
	_bird_lane = null
	_squirrel_path = null
	var water_present := false
	if _markers != null:
		_bird_lane = _markers.get_node_or_null("SkyBirdLane") as Path2D
		_squirrel_path = _markers.get_node_or_null("SquirrelPath") as Path2D
		for marker in _markers.get_children():
			if marker is Marker2D and str(marker.name).begins_with("CatSpot_"):
				_cat_spots.append(marker)
			if str(marker.name).begins_with("FishArea_"):
				water_present = true
	var sheltered := false
	var cat_night := false
	for spot in _cat_spots:
		sheltered = sheltered or bool(spot.get_meta("sheltered", false))
		# No night spot is authored in this wilderness scene.
		cat_night = cat_night or bool(spot.get_meta("night_allowed", false))
	capabilities = {
		"birds": _valid_path(_bird_lane), "squirrel": _valid_path(_squirrel_path),
		"cat": not _cat_spots.is_empty(), "fish": water_present,
		"cat_sheltered": sheltered, "cat_night_allowed": cat_night,
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
	var birds := _make_root("DistantBirds", _game._far_layer)
	for index in 3:
		var bird := _sprite("Bird%d" % index, _bird_frames[0], birds)
		bird.scale = Vector2.ONE * float(config.visuals.bird_scale)
	visual_nodes.birds = birds
	var squirrel := _make_root("BranchSquirrel", _game._near_layer)
	_squirrel_frames = _pose_frames("squirrel.svg", Vector2i(68, 44))
	var runner := _sprite("Squirrel", _squirrel_frames[0], squirrel)
	runner.centered = false
	runner.offset = Vector2(-34, -38)
	runner.scale = Vector2.ONE * float(config.visuals.squirrel_scale)
	visual_nodes.squirrel = squirrel
	var cat := _make_root("RestingCat", _game._near_layer)
	_build_cat_frames()
	var sleeper := _sprite("Cat", _cat_frames[0], cat)
	sleeper.centered = false
	_set_cat_pose(sleeper, 0)
	sleeper.scale = Vector2.ONE * float(config.visuals.cat_scale) * _cat_pixel_scale
	visual_nodes.cat = cat
	cat_hotspot = _game._make_hotspot("OrangeCatHotspot", Rect2(0, 0, 112, 84), "摸摸大橘")
	cat_hotspot.visible = false
	cat_hotspot.pressed.connect(pet_cat)


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


func _set_cat_pose(sprite: Sprite2D, index: int) -> void:
	sprite.texture = _cat_frames[index]
	sprite.offset = _cat_offsets[index]


func _pose_frames(file_name: String, size: Vector2i, count: int = 4) -> Array[AtlasTexture]:
	var sheet: Texture2D = load(ART_PATH + file_name)
	var frames: Array[AtlasTexture] = []
	for index in count:
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(index * size.x, 0, size.x, size.y)
		frame.filter_clip = true
		frames.append(frame)
	return frames


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
	presenter.observe({
		"time_profile_id": _game.environment_presenter.time_profile_id,
		"weather_id": _game.environment_presenter.weather_id,
		"night_preview": _game.environment_presenter.night_preview,
		"dynamic_enabled": _game.dynamic_enabled,
	}, capabilities)
	_render()


func advance(delta: float, foreground_attention_busy: bool = false) -> void:
	observe_environment()
	presenter.advance(delta, foreground_attention_busy or _cat_pet_active() or cat_is_playing())
	_render()


func pet_cat() -> bool:
	observe_environment()
	if not presenter.enabled or not _game.dynamic_enabled or _game.busy or _cat_pet_active():
		return false
	if not presenter.get_active_events().has("cat") or not visual_nodes.cat.visible or visual_nodes.cat.modulate.a < 0.9:
		return false
	_cat_pet_start = float(presenter.elapsed)
	_render()
	cat_petted.emit()
	return true


func _cat_pet_active() -> bool:
	return _game.dynamic_enabled and _cat_pet_start >= 0.0 and float(presenter.elapsed) - _cat_pet_start < float(config.motion.cat_pet_seconds)


func cat_is_playing() -> bool:
	if not _game.dynamic_enabled or _game.busy or not visual_nodes.cat.visible:
		return false
	var texture := visual_nodes.cat.get_child(0).texture as AtlasTexture
	return texture != null and _cat_frames.find(texture) in [5, 6]


func set_enabled(value: bool) -> void:
	presenter.set_enabled(value)
	observe_environment()


func force_event(kind: String) -> bool:
	observe_environment()
	var event: Dictionary = presenter.force_event(kind)
	_render()
	return not event.is_empty()


func resume_auto() -> void:
	presenter.resume_auto()
	observe_environment()


func reset() -> void:
	presenter.reset()
	cat_spot = null
	_cat_serial = -1
	_cat_pet_start = -100.0
	if visual_nodes.has("cat"):
		var cat_sprite := visual_nodes.cat.get_child(0) as Sprite2D
		_set_cat_pose(cat_sprite, 0)
	observe_environment()


func _render() -> void:
	for node in visual_nodes.values():
		node.visible = false
	if cat_hotspot != null:
		cat_hotspot.visible = false
		cat_hotspot.disabled = true
	if not _game.dynamic_enabled or _game.busy:
		_cat_pet_start = -100.0
	if not _game.dynamic_enabled and visual_nodes.has("squirrel"):
		var resting_runner := visual_nodes.squirrel.get_child(0) as Sprite2D
		resting_runner.texture = _squirrel_frames[0]
		resting_runner.position = Vector2.ZERO
	var events: Dictionary = presenter.get_active_events()
	var tint: Color = _game._displayed_tint
	var environment: Dictionary = _game.environment_presenter.get_current_environment()
	var wind := clampf(float(environment.get("wind_strength", 0.0)), 0.0, 1.0)
	var cat_attention_busy: bool = _game.busy or events.has("birds") or events.has("squirrel") or events.has("fish")
	for kind in events:
		if not visual_nodes.has(kind):
			continue
		var event: Dictionary = events[kind]
		var age := maxf(0.0, float(presenter.elapsed) - float(event.start))
		var duration := maxf(0.01, float(event.duration))
		var node: Node2D = visual_nodes[kind]
		node.modulate = tint
		if kind == "birds" and _valid_path(_bird_lane):
			node.visible = true
			var progress := clampf(age / duration, 0.0, 1.0)
			var point := _bird_lane.curve.sample_baked(progress * _bird_lane.curve.get_baked_length())
			node.position = point
			node.modulate.a = float(config.visuals.bird_alpha) * _fade(age, duration, 1.0)
			for i in node.get_child_count():
				var bird := node.get_child(i) as Sprite2D
				bird.visible = i < int(event.count)
				bird.texture = _bird_frames[int(age * 4.0 + i) % 3]
				bird.position = Vector2(-i * 26.0, i * 10.0 + sin(age * 1.8 + i) * 2.0)
		elif kind == "squirrel" and _valid_path(_squirrel_path):
			node.visible = true
			var progress := clampf(age / duration, 0.0, 1.0)
			var distance := 0.52
			if progress < 0.44:
				distance = progress / 0.44 * 0.52
			elif progress > 0.62:
				distance = 0.52 + (progress - 0.62) / 0.38 * 0.48
			node.position = _squirrel_path.curve.sample_baked(distance * _squirrel_path.curve.get_baked_length())
			node.modulate.a = _fade(age, duration, 0.35)
			var runner := node.get_child(0) as Sprite2D
			var running := progress < 0.44 or progress > 0.62
			var stride := age * float(config.motion.squirrel_run_fps) * lerpf(0.85, 1.15, wind)
			runner.texture = _squirrel_frames[1 + int(stride) % 3] if running else _squirrel_frames[0]
			runner.position = Vector2(0, -absf(sin(stride * PI)) * float(config.motion.squirrel_bob_pixels)) if running else Vector2.ZERO
			# One small tail adjustment while pausing; feet stay on the branch.
			if not running and progress > 0.52 and progress < 0.57:
				runner.texture = _squirrel_frames[3]
		elif kind == "cat":
			if _cat_serial != int(event.serial):
				_cat_serial = int(event.serial)
				_cat_pet_start = -100.0
				cat_spot = _choose_cat_spot(int(event.serial))
			if not is_instance_valid(cat_spot) or not _cat_spots.has(cat_spot):
				continue
			if _game.environment_presenter.weather_id == "light_rain" and not bool(cat_spot.get_meta("sheltered", false)):
				continue
			node.visible = true
			node.position = cat_spot.position
			if _cat_pet_active():
				var pet_progress := (float(presenter.elapsed) - _cat_pet_start) / float(config.motion.cat_pet_seconds)
				node.position.x += sin(pet_progress * PI) * 4.0
			node.modulate.a = _fade(age, duration, 1.0) if _game.dynamic_enabled else 1.0
			var sprite := node.get_child(0) as Sprite2D
			var scale := float(config.visuals.cat_scale) * _cat_pixel_scale
			sprite.scale = Vector2(scale, scale * (1.0 + sin(age * 1.1) * 0.003)) if _game.dynamic_enabled else Vector2.ONE * scale
			_set_cat_pose(sprite, _cat_pose_frame(age, wind, cat_attention_busy) if _game.dynamic_enabled else 0)
			var foot: Vector2 = _game._foreground_layer.get_global_transform_with_canvas().affine_inverse() * node.get_global_transform_with_canvas().origin
			cat_hotspot.position = foot - Vector2(56, 80)
			cat_hotspot.visible = node.modulate.a >= 0.9
			cat_hotspot.disabled = not _game.dynamic_enabled or _game.busy or _cat_pet_active()


func _cat_pose_frame(age: float, wind: float, attention_busy: bool) -> int:
	if _cat_pet_active() and not _game.busy:
		return 7
	return CatMotion.idle_pose(
		age,
		wind,
		str(_game.environment_presenter.time_profile_id),
		str(_game.environment_presenter.weather_id),
		config.motion,
		attention_busy
	)


func _choose_cat_spot(serial: int) -> Marker2D:
	var candidates: Array[Marker2D] = []
	var sunny: Array[Marker2D] = []
	var weather_id: String = _game.environment_presenter.weather_id
	for spot in _cat_spots:
		if weather_id == "light_rain" and not bool(spot.get_meta("sheltered", false)):
			continue
		candidates.append(spot)
		if bool(spot.get_meta("sunny", false)):
			sunny.append(spot)
	if weather_id == "clear" and not sunny.is_empty():
		candidates = sunny
	return candidates[posmod(serial, candidates.size())] if not candidates.is_empty() else null


func _fade(age: float, duration: float, seconds: float) -> float:
	return clampf(minf(age / seconds, (duration - age) / seconds), 0.0, 1.0)
