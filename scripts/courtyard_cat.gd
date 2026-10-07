extends Node2D
class_name CourtyardCat

signal petted

const LifePresenter = preload("res://scripts/ambient_life_presenter.gd")
const CatMotion = preload("res://scripts/ambient_cat_motion.gd")
const ResidentMotion = preload("res://scripts/cat_resident_motion.gd")
const CONFIG_PATH := "res://assets/data/courtyard_ambient_life.json"
const ART_PATH := "res://assets/art/ambient_life/"
const CURSOR_PATH := "res://assets/art/ui/cat-pet-cursor-v2.svg"
const DEFAULT_PATH := [[958.0, 495.0], [1066.0, 500.0]]
const DEFAULT_WIDTH := 78.0
const DEFAULT_REST_SECONDS := 19.0

var presenter = LifePresenter.new()
var config: Dictionary = {}
var capabilities: Dictionary = {}
var _layout: Dictionary = {}
var _route_path: Path2D
var _sprite: Sprite2D
var _hotspot: Button
var _motion = ResidentMotion.new()
var _frames: Array[AtlasTexture] = []
var _pivots: Array[Vector2] = []
var _opaque_bounds: Array[Rect2] = []
var _home_local := Vector2(958.0, 495.0)
var _foot_local := Vector2(958.0, 495.0)
var _opaque_rect := Rect2()
var _cat_width := DEFAULT_WIDTH
var _event_serial := -1
var _pose_index := 0
var _facing := 1.0
var _pet_until := -1.0
var _last_environment: Dictionary = {
	"time_profile_id": "mao",
	"weather_id": "clear",
	"night_preview": false,
	"dynamic_enabled": false,
	"foreground_busy": false,
	"gust": 0.0,
}
var _configured := false
var _cursor_registered := false
var _path_available := false
var _cat_sheltered := true


func configure(layout: Dictionary) -> void:
	_release_cursor()
	_layout = layout.duplicate(true)
	_configured = false
	_frames.clear()
	_pivots.clear()
	_opaque_bounds.clear()
	_event_serial = -1
	_pet_until = -1.0
	_motion.reset()

	var config_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	config = config_value if config_value is Dictionary else {}
	presenter.configure(config)

	_build_path()
	_cat_width = maxf(1.0, float(_layout.get("cat_width", DEFAULT_WIDTH)))
	_cat_sheltered = bool(_layout.get("cat_sheltered", true))
	var rest_seconds := maxf(0.0, float(_layout.get("rest_seconds", DEFAULT_REST_SECONDS)))
	_motion.configure({
		"walk_speed": float(_layout.get("cat_speed", _layout.get("travel_speed", 6.0))),
		"gait_cadence": float(_layout.get("gait_cadence", 3.6)),
		"phase_durations": {
			"initial_rest": rest_seconds,
			"stand": float(_layout.get("stand_seconds", 2.0)),
			"sniff": float(_layout.get("sniff_seconds", 3.0)),
			"sit": float(_layout.get("sit_seconds", 8.0)),
			"home_rest": rest_seconds,
		},
	})
	var frames_ready := _load_pose_atlas(
		ART_PATH + "orange-cat-painterly-v2.png",
		ART_PATH + "orange-cat-layout-v2.json",
		8
	)
	frames_ready = _load_pose_atlas(
		ART_PATH + "tingyu-cat-desk-v1.png",
		ART_PATH + "tingyu-cat-desk-layout-v1.json",
		6
	) and frames_ready

	capabilities = {
		"birds": false,
		"squirrel": false,
		"cat": _path_available and frames_ready and _frames.size() == 14,
		"fish": false,
		"cat_sheltered": _cat_sheltered,
		"cat_night_allowed": bool(_layout.get("cat_night_allowed", true)),
	}
	_build_visual_nodes()
	_last_environment = _normalize_environment({}, false)
	presenter.observe(_last_environment, capabilities)
	_configured = true
	_render()


func _build_path() -> void:
	if is_instance_valid(_route_path):
		remove_child(_route_path)
		_route_path.free()
	_route_path = Path2D.new()
	_route_path.name = "CourtyardCatPath"
	var curve := Curve2D.new()
	curve.bake_interval = 1.0
	_route_path.curve = curve
	add_child(_route_path)
	_path_available = false

	var points: Variant = _layout.get("path", _layout.get("cat_path", DEFAULT_PATH))
	if not points is Array or (points as Array).size() < 2:
		return
	var valid := true
	for point_value in points:
		if not point_value is Array or (point_value as Array).size() != 2:
			valid = false
			break
		var point: Array = point_value
		curve.add_point(Vector2(float(point[0]), float(point[1])))
	if valid and curve.get_point_count() >= 2 and curve.get_baked_length() > 1.0:
		_path_available = true
		_home_local = curve.sample_baked(0.0)
		_foot_local = _home_local


func _load_pose_atlas(sheet_path: String, layout_path: String, expected_frames: int) -> bool:
	var sheet := load(sheet_path) as Texture2D
	var layout_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if sheet == null or not layout_value is Dictionary:
		return false
	var layout: Dictionary = layout_value
	var frame_values: Variant = layout.get("frames", [])
	if not frame_values is Array or (frame_values as Array).size() != expected_frames:
		return false
	var parsed_frames: Array[AtlasTexture] = []
	var parsed_pivots: Array[Vector2] = []
	var parsed_bounds: Array[Rect2] = []
	for frame_value in frame_values:
		if not frame_value is Dictionary:
			return false
		var data: Dictionary = frame_value
		if not _array_has_size(data.get("region", []), 4):
			return false
		if not _array_has_size(data.get("pivot", []), 2):
			return false
		if not _array_has_size(data.get("opaque_bounds", []), 4):
			return false
		var region := _rect_from_array(data.region)
		var pivot_values: Array = data.pivot
		var bounds := _rect_from_array(data.opaque_bounds)
		if region.size.x <= 0.0 or region.size.y <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
			return false
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = region
		frame.filter_clip = true
		parsed_frames.append(frame)
		parsed_pivots.append(Vector2(float(pivot_values[0]), float(pivot_values[1])))
		parsed_bounds.append(bounds)
	_frames.append_array(parsed_frames)
	_pivots.append_array(parsed_pivots)
	_opaque_bounds.append_array(parsed_bounds)
	return true


func _array_has_size(value: Variant, expected_size: int) -> bool:
	return value is Array and (value as Array).size() == expected_size


func _rect_from_array(value: Variant) -> Rect2:
	if not _array_has_size(value, 4):
		return Rect2()
	var values: Array = value
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


func _build_visual_nodes() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "CourtyardOrangeCat"
	_sprite.centered = false
	if not _frames.is_empty():
		_sprite.texture = _frames[0]
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_sprite.material = material
	add_child(_sprite)

	_hotspot = Button.new()
	_hotspot.name = "CourtyardCatPetHotspot"
	_hotspot.flat = true
	_hotspot.tooltip_text = "摸摸猫"
	_hotspot.focus_mode = Control.FOCUS_NONE
	_hotspot.visible = false
	_hotspot.disabled = true
	_hotspot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotspot.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_hotspot.pressed.connect(_on_hotspot_pressed)
	add_child(_hotspot)
	var transparent_style := StyleBoxFlat.new()
	transparent_style.bg_color = Color(0, 0, 0, 0)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_hotspot.add_theme_stylebox_override(state, transparent_style)

	var cursor := load(CURSOR_PATH) as Texture2D
	if cursor != null:
		Input.set_custom_mouse_cursor(cursor, Input.CURSOR_DRAG, Vector2(8, 24))
		_cursor_registered = true


func update_presentation(environment: Dictionary, dynamic_enabled: bool, delta: float) -> void:
	if not _configured:
		return
	var elapsed_before := float(presenter.elapsed)
	_last_environment = _normalize_environment(environment, dynamic_enabled)
	presenter.observe(_last_environment, capabilities)
	var foreground_busy := bool(_last_environment.get("foreground_busy", false))
	presenter.advance(delta, foreground_busy)
	var events: Dictionary = presenter.get_active_events()
	if events.has("cat"):
		var event: Dictionary = events.cat
		_ensure_route(event)
		_advance_route(elapsed_before, event, dynamic_enabled, foreground_busy)
	_render()


func _normalize_environment(environment: Dictionary, dynamic_enabled: bool) -> Dictionary:
	return {
		"time_profile_id": str(environment.get("time_profile_id", "mao")),
		"weather_id": str(environment.get("weather_id", "clear")),
		"night_preview": bool(environment.get("night_preview", false)),
		"dynamic_enabled": dynamic_enabled,
		"foreground_busy": bool(environment.get("foreground_busy", false)),
		"gust": float(environment.get("gust", environment.get("wind_strength", 0.0))),
		"wind_strength": float(environment.get("wind_strength", environment.get("gust", 0.0))),
	}


func _ensure_route(event: Dictionary) -> void:
	var serial := int(event.get("serial", -1))
	if serial == _event_serial:
		return
	_event_serial = serial
	_pet_until = -1.0
	_motion.reset()
	if _path_available:
		_motion.start(_route_path, _route_path.to_global(_home_local))
		_foot_local = _home_local
		_facing = _motion.facing_x()


func _advance_route(
	elapsed_before: float,
	event: Dictionary,
	dynamic_enabled: bool,
	foreground_busy: bool
) -> void:
	if not _motion.active or not dynamic_enabled or foreground_busy:
		return
	var movement_start := maxf(elapsed_before, float(event.get("start", elapsed_before)))
	if _pet_until > movement_start:
		movement_start = _pet_until
	var movement_delta := maxf(0.0, float(presenter.elapsed) - movement_start)
	if movement_delta > 0.0:
		_motion.advance(movement_delta)


func _render() -> void:
	if not is_instance_valid(_sprite) or not is_instance_valid(_hotspot):
		return
	var events: Dictionary = presenter.get_active_events()
	if not events.has("cat"):
		_pet_until = -1.0
		_event_serial = -1
		_motion.reset()
		_foot_local = _home_local
		_facing = 1.0
		_sprite.visible = false
		_sprite.modulate = Color.WHITE
		_sprite.position = _foot_local
		_set_pose(0, _facing)
		_refresh_hotspot(false)
		return

	var event: Dictionary = events.cat
	_ensure_route(event)
	if _motion.active:
		_foot_local = to_local(_motion.global_position())
	var age := maxf(0.0, float(presenter.elapsed) - float(event.get("start", 0.0)))
	var duration := maxf(0.01, float(event.get("duration", 0.01)))
	var fade_seconds := maxf(0.001, float(config.get("visuals", {}).get("cat_fade_seconds", 1.0)))
	var alpha := float(config.get("visuals", {}).get("cat_alpha", 1.0)) * clampf(
		minf(age / fade_seconds, (duration - age) / fade_seconds),
		0.0,
		1.0
	)
	_sprite.visible = alpha > 0.001
	_sprite.modulate = Color(1.0, 1.0, 1.0, alpha)
	_sprite.position = _foot_local

	var dynamic_enabled := bool(_last_environment.get("dynamic_enabled", false))
	var foreground_busy := bool(_last_environment.get("foreground_busy", false))
	var pet_active := _pet_response_active(dynamic_enabled, foreground_busy)
	var pose := _paused_pose()
	if dynamic_enabled and not foreground_busy:
		if pet_active:
			pose = 7
		elif _motion.active:
			pose = _motion.pose_index()
			if pose < 0:
				pose = CatMotion.idle_pose(
					_motion.activity_elapsed,
					float(_last_environment.get("gust", 0.0)),
					str(_last_environment.get("time_profile_id", "mao")),
					str(_last_environment.get("weather_id", "clear")),
					config.get("motion", {}),
					false
				)
	_facing = _motion.facing_x() if _motion.active else _facing
	_set_pose(pose, _facing)
	_refresh_hotspot(dynamic_enabled and not foreground_busy and not pet_active)


func _paused_pose() -> int:
	if not _motion.active:
		return 0
	var current_pose := _motion.pose_index()
	if current_pose == 12 or current_pose == 13:
		return current_pose
	return 13 if _motion.is_walking() else 0


func _set_pose(index: int, facing: float) -> void:
	if not is_instance_valid(_sprite) or _frames.is_empty():
		return
	_pose_index = clampi(index, 0, _frames.size() - 1)
	_sprite.texture = _frames[_pose_index]
	_sprite.offset = -_pivots[_pose_index]
	var bounds := _opaque_bounds[_pose_index]
	var scale := _cat_width / bounds.size.x
	var direction := -1.0 if facing < 0.0 else 1.0
	_sprite.scale = Vector2(scale * direction, scale)
	var first := _sprite.position + (bounds.position + _sprite.offset) * _sprite.scale
	var last := _sprite.position + (bounds.position + bounds.size + _sprite.offset) * _sprite.scale
	var minimum := Vector2(minf(first.x, last.x), minf(first.y, last.y))
	var maximum := Vector2(maxf(first.x, last.x), maxf(first.y, last.y))
	_opaque_rect = Rect2(minimum, maximum - minimum)
	_hotspot.position = _opaque_rect.position
	_hotspot.size = _opaque_rect.size


func _refresh_hotspot(interaction_allowed: bool) -> void:
	var has_visible_cat := _sprite.visible and _sprite.modulate.a > 0.001
	_hotspot.visible = has_visible_cat
	var can_interact := has_visible_cat and interaction_allowed and _path_available
	_hotspot.disabled = not can_interact
	_hotspot.mouse_filter = Control.MOUSE_FILTER_STOP if can_interact else Control.MOUSE_FILTER_IGNORE
	_hotspot.mouse_default_cursor_shape = Control.CURSOR_DRAG if can_interact else Control.CURSOR_ARROW


func _can_pet_now() -> bool:
	if not _configured or not is_instance_valid(_sprite) or not is_instance_valid(_hotspot):
		return false
	var events: Dictionary = presenter.get_active_events()
	return (
		events.has("cat")
		and _sprite.visible
		and _sprite.modulate.a > 0.001
		and bool(_last_environment.get("dynamic_enabled", false))
		and not bool(_last_environment.get("foreground_busy", false))
		and float(_pet_until) <= float(presenter.elapsed)
	)


func _on_hotspot_pressed() -> void:
	if not _can_pet_now():
		_refresh_hotspot(false)
		return
	var cat_config: Dictionary = config.get("cat", {})
	_pet_until = float(presenter.elapsed) + maxf(0.0, float(cat_config.get("pet_seconds", 1.6)))
	_render()
	petted.emit()


func _pet_response_active(dynamic_enabled: bool, foreground_busy: bool) -> bool:
	return (
		dynamic_enabled
		and not foreground_busy
		and _pet_until > float(presenter.elapsed) + 0.000001
		and presenter.get_active_events().has("cat")
	)


func reset() -> void:
	if not _configured:
		return
	presenter.reset()
	_motion.reset()
	_event_serial = -1
	_pet_until = -1.0
	_foot_local = _home_local
	_facing = 1.0
	presenter.observe(_last_environment, capabilities)
	_render()


func get_snapshot() -> Dictionary:
	var event: Dictionary = presenter.get_active_events().get("cat", {})
	var event_age := maxf(0.0, float(presenter.elapsed) - float(event.get("start", presenter.elapsed)))
	var dynamic_enabled := bool(_last_environment.get("dynamic_enabled", false))
	var foreground_busy := bool(_last_environment.get("foreground_busy", false))
	return {
		"visible": is_instance_valid(_sprite) and _sprite.visible and _sprite.modulate.a > 0.001,
		"pose": _pose_index,
		"pose_name": _pose_name(_pose_index),
		"foot": _foot_local,
		"facing": _facing,
		"hotspot_rect": _opaque_rect,
		"hotspot_visible": is_instance_valid(_hotspot) and _hotspot.visible,
		"hotspot_enabled": is_instance_valid(_hotspot) and not _hotspot.disabled and _hotspot.mouse_filter == Control.MOUSE_FILTER_STOP,
		"visible_width": _opaque_rect.size.x,
		"contact_foot": _sprite.position if is_instance_valid(_sprite) else Vector2.ZERO,
		"route_active": _motion.active,
		"route_phase": _motion.phase_name() if _motion.active else "inactive",
		"route_phase_elapsed": _motion.phase_elapsed(),
		"route_elapsed": _motion.activity_elapsed,
		"route_distance": _motion.route_distance(),
		"event_age": event_age,
		"presentation_elapsed": presenter.elapsed,
		"next_cat_opportunity": float(presenter.next_due.get("cat", -1.0)),
		"pet_response_active": _pet_response_active(dynamic_enabled, foreground_busy),
		"pet_response_remaining": maxf(0.0, _pet_until - float(presenter.elapsed)),
	}


func _pose_name(index: int) -> String:
	if index == 0:
		return "rest"
	if index == 7:
		return "pet"
	if index >= 8 and index <= 11:
		return "walk_%d" % (index - 7)
	if index == 12:
		return "sit"
	if index == 13:
		return "stand_sniff"
	return "idle_%d" % index


func _release_cursor() -> void:
	if _cursor_registered:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_DRAG)
		_cursor_registered = false


func _exit_tree() -> void:
	_release_cursor()
