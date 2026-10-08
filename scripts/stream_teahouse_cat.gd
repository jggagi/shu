extends Node

signal cat_petted

const CatDeskMotion = preload("res://scripts/tingyu_cat_desk_motion.gd")
const CAT_ART_DIR := "res://assets/art/ambient_life/"
const CAT_CURSOR_PATH := "res://assets/art/ui/cat-pet-cursor-v2.svg"
const WEATHER_FADE_SECONDS := 1.5
const PET_SECONDS := 2.4

var sprite: Sprite2D
var hotspot: Button
var motion = CatDeskMotion.new()
var elapsed := 0.0
var pet_remaining := 0.0
var pose_index := 0
var _frames: Array[AtlasTexture] = []

var _parent: Node2D
var _path: Path2D
var _home: Marker2D
var _visual_root: Node2D
var _frame_offsets: Array[Vector2] = []
var _frame_scales: Array[float] = []
var _frame_bounds: Array[Rect2] = []
var _cat_scale := 0.65
var _weather_alpha := 1.0
var _context := {
	"dynamic_enabled": true,
	"weather_id": "clear",
	"time_profile_id": "mao",
	"busy": false,
	"brightness": 1.0,
	"world_tint": Color.WHITE,
}
var _cursor_registered := false


func setup(parent: Node2D, path: Path2D, home: Marker2D, cat_scale: float = 0.65) -> void:
	_teardown_visuals()
	_parent = parent
	_path = path
	_home = home
	_cat_scale = maxf(0.0, cat_scale)
	_context = _default_context()
	_weather_alpha = 1.0

	if not is_instance_valid(_parent):
		return

	_visual_root = Node2D.new()
	_visual_root.name = "StreamTeahouseResidentCat"
	_parent.add_child(_visual_root)
	_build_visuals()
	_register_pet_cursor()
	reset()


func observe(context: Dictionary) -> void:
	var tint_value: Variant = context.get("world_tint", Color.WHITE)
	var tint: Color = Color.WHITE
	if tint_value is Color:
		tint = tint_value
	_context = {
		"dynamic_enabled": bool(context.get("dynamic_enabled", true)),
		"weather_id": str(context.get("weather_id", "clear")),
		"time_profile_id": str(context.get("time_profile_id", "mao")),
		"busy": bool(context.get("busy", false)),
		"brightness": maxf(0.0, float(context.get("brightness", 1.0))),
		"world_tint": tint,
	}
	_render()


func advance(delta: float) -> void:
	if delta <= 0.0 or not bool(_context.dynamic_enabled):
		return

	var step := delta
	elapsed += step
	var raining := _is_raining()
	var fade_target := 0.0 if raining else 1.0
	_weather_alpha = move_toward(_weather_alpha, fade_target, step / WEATHER_FADE_SECONDS)

	var travel_delta := step
	if pet_remaining > 0.0:
		var pet_step := minf(step, pet_remaining)
		pet_remaining = maxf(0.0, pet_remaining - pet_step)
		travel_delta -= pet_step

	if travel_delta > 0.0 and _can_move():
		motion.advance(travel_delta)
	_render()


func reset() -> void:
	elapsed = 0.0
	pet_remaining = 0.0
	pose_index = 0
	_weather_alpha = 1.0
	_context = _default_context()
	motion.reset()
	if is_instance_valid(_path) and is_instance_valid(_home):
		motion.start(_path, _home.global_position)
	_render()


func pet() -> bool:
	if not _can_pet():
		return false
	pet_remaining = PET_SECONDS
	_render()
	cat_petted.emit()
	return true


func _build_frames() -> void:
	_frame_offsets.clear()
	_frame_scales.clear()
	_frame_bounds.clear()
	if not is_instance_valid(_visual_root):
		return

	var sheet := load(CAT_ART_DIR + "orange-cat-painterly-v2.png") as Texture2D
	var painterly_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAT_ART_DIR + "orange-cat-layout-v2.json"))
	if sheet != null and painterly_value is Dictionary:
		var painterly: Dictionary = painterly_value
		var logical_width := float(painterly.get("logical_width", 0.0))
		var cell_width := float(painterly.get("cell_width", 0.0))
		if logical_width > 0.0 and cell_width > 0.0:
			var raster_scale := logical_width / cell_width
			for value in painterly.get("frames", []):
				if not value is Dictionary:
					continue
				var data: Dictionary = value
				if int(data.get("pose_index", -1)) != _frame_offsets.size():
					continue
				_frame_offsets.append(-_vector_from_layout(data.get("pivot", [])))
				_frame_scales.append(raster_scale)
				_frame_bounds.append(_rect_from_layout(data.get("opaque_bounds", [])))
				_add_atlas_frame(sheet, data, _frame_offsets.size() - 1)

	var desk_sheet := load(CAT_ART_DIR + "tingyu-cat-desk-v1.png") as Texture2D
	var desk_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAT_ART_DIR + "tingyu-cat-desk-layout-v1.json"))
	if desk_sheet != null and desk_value is Dictionary:
		var desk: Dictionary = desk_value
		var logical_width := float(desk.get("logical_width", 0.0))
		var cell_width := float(desk.get("cell_width", 0.0))
		if logical_width > 0.0 and cell_width > 0.0:
			var raster_scale := logical_width / cell_width
			for value in desk.get("frames", []):
				if not value is Dictionary:
					continue
				var data: Dictionary = value
				var expected_pose := int(data.get("pose_index", -1))
				if expected_pose != _frame_offsets.size():
					continue
				_frame_offsets.append(-_vector_from_layout(data.get("pivot", [])))
				_frame_scales.append(raster_scale)
				_frame_bounds.append(_rect_from_layout(data.get("opaque_bounds", [])))
				_add_atlas_frame(desk_sheet, data, expected_pose)


func _add_atlas_frame(sheet: Texture2D, data: Dictionary, pose: int) -> void:
	var region := _rect_from_layout(data.get("region", []))
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return
	var frame := AtlasTexture.new()
	frame.atlas = sheet
	frame.region = region
	frame.filter_clip = true
	frame.set_meta("pose_index", pose)
	_frames.append(frame)


func _build_visuals() -> void:
	_frames.clear()
	_frame_offsets.clear()
	_frame_scales.clear()
	_frame_bounds.clear()
	_build_frames()
	if _frames.size() != 14:
		push_error("Stream teahouse cat expected 14 authored poses, found %d" % _frames.size())
		return

	sprite = Sprite2D.new()
	sprite.name = "CatSprite"
	sprite.centered = false
	sprite.texture = _frames[0]
	sprite.offset = _frame_offsets[0]
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	sprite.material = material
	_visual_root.add_child(sprite)

	hotspot = Button.new()
	hotspot.name = "CatPetHotspot"
	hotspot.flat = true
	hotspot.focus_mode = Control.FOCUS_NONE
	hotspot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotspot.disabled = true
	hotspot.z_index = 1
	hotspot.pressed.connect(_on_hotspot_pressed)
	_visual_root.add_child(hotspot)
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		var transparent := StyleBoxFlat.new()
		transparent.bg_color = Color(0, 0, 0, 0)
		hotspot.add_theme_stylebox_override(style_name, transparent)


func _render() -> void:
	if not is_instance_valid(_visual_root) or not is_instance_valid(sprite) or _frames.size() != 14:
		return

	if motion.active:
		_visual_root.position = _parent.to_local(motion.global_position())
	elif is_instance_valid(_home):
		_visual_root.position = _parent.to_local(_home.global_position)

	var busy := bool(_context.get("busy", false))
	var static_mode := not bool(_context.get("dynamic_enabled", true))
	var raining := _is_raining()
	var walking: bool = motion.active and motion.is_walking()
	var facing: float = motion.facing_x() if motion.active else 1.0
	var body_bob := 0.0
	if static_mode or busy or raining:
		pose_index = _quiet_pose(walking)
	elif pet_remaining > 0.0:
		pose_index = 7
	elif motion.active:
		pose_index = motion.pose_index()
		if pose_index < 0:
			pose_index = 0
		else:
			body_bob = motion.body_bob()
	else:
		pose_index = 0

	pose_index = clampi(pose_index, 0, _frames.size() - 1)
	sprite.texture = _frames[pose_index]
	sprite.offset = _frame_offsets[pose_index]
	var frame_scale: float = _cat_scale * _frame_scales[pose_index]
	sprite.scale = Vector2(frame_scale * (-1.0 if facing < 0.0 else 1.0), frame_scale)
	sprite.position = Vector2(0.0, -body_bob)
	var tint: Color = _context.get("world_tint", Color.WHITE)
	var brightness: float = maxf(0.0, float(_context.get("brightness", 1.0)))
	sprite.modulate = Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, tint.a)
	_visual_root.modulate = Color(1.0, 1.0, 1.0, _weather_alpha)
	_refresh_hotspot()


func _quiet_pose(walking: bool) -> int:
	if walking:
		return 13
	var current_pose := motion.pose_index() if motion.active else -1
	return current_pose if current_pose == 12 or current_pose == 13 else 0


func _refresh_hotspot() -> void:
	if not is_instance_valid(hotspot):
		return
	var bounds: Rect2 = _frame_bounds[pose_index]
	var scale := sprite.scale
	var first := sprite.position + (bounds.position + sprite.offset) * scale
	var last := sprite.position + (bounds.position + bounds.size + sprite.offset) * scale
	var minimum := Vector2(minf(first.x, last.x), minf(first.y, last.y))
	var maximum := Vector2(maxf(first.x, last.x), maxf(first.y, last.y))
	var hit_rect := Rect2(minimum, maximum - minimum).grow(4.0)
	hotspot.position = hit_rect.position
	hotspot.size = hit_rect.size
	var can_pet := _can_pet()
	hotspot.visible = _weather_alpha > 0.001
	hotspot.disabled = not can_pet
	hotspot.mouse_filter = Control.MOUSE_FILTER_STOP if can_pet else Control.MOUSE_FILTER_IGNORE
	hotspot.mouse_default_cursor_shape = Control.CURSOR_DRAG if can_pet and _cursor_registered else Control.CURSOR_ARROW


func _can_move() -> bool:
	return motion.active and not _is_raining() and not bool(_context.get("busy", false)) and pet_remaining <= 0.0


func _can_pet() -> bool:
	return (
		is_instance_valid(sprite)
		and sprite.visible
		and _weather_alpha > 0.001
		and bool(_context.get("dynamic_enabled", true))
		and not _is_raining()
		and not bool(_context.get("busy", false))
		and pet_remaining <= 0.0
	)


func _is_raining() -> bool:
	return str(_context.get("weather_id", "clear")) == "light_rain"


func _on_hotspot_pressed() -> void:
	pet()


func _register_pet_cursor() -> void:
	var cursor := load(CAT_CURSOR_PATH) as Texture2D
	if cursor == null:
		return
	Input.set_custom_mouse_cursor(cursor, Input.CURSOR_DRAG, Vector2(8, 24))
	_cursor_registered = true


func _teardown_visuals() -> void:
	if _cursor_registered:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_DRAG)
		_cursor_registered = false
	if is_instance_valid(_visual_root):
		_visual_root.queue_free()
	_visual_root = null
	sprite = null
	hotspot = null
	_frames.clear()
	_frame_offsets.clear()
	_frame_scales.clear()
	_frame_bounds.clear()


func _exit_tree() -> void:
	_teardown_visuals()


func _default_context() -> Dictionary:
	return {
		"dynamic_enabled": true,
		"weather_id": "clear",
		"time_profile_id": "mao",
		"busy": false,
		"brightness": 1.0,
		"world_tint": Color.WHITE,
	}


func _vector_from_layout(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() < 2:
		return Vector2.ZERO
	var values: Array = value
	return Vector2(float(values[0]), float(values[1]))


func _rect_from_layout(value: Variant) -> Rect2:
	if not value is Array or (value as Array).size() < 4:
		return Rect2()
	var values: Array = value
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
