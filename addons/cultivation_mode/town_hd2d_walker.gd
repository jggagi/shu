extends "res://addons/cultivation_mode/town_walker.gd"
## A projected 3D view of the existing P1b logical walking plane.
## All movement, arrival, host validation and persistence remain in the parent.

const StageScript = preload("res://addons/cultivation_mode/town_hd2d_stage.gd")
const PlayerSheet = preload("res://assets/art/shanxia_hd2d/player-walk.svg")
const SellerSheet = preload("res://assets/art/shanxia_hd2d/tea-seller-walk.svg")
const ART_SOURCE_PATH := "res://assets/art/shanxia_hd2d/source.json"
var _stage: Node


func setup(host: RefCounted, map_id: String, map: Dictionary, font: Font, enabled: bool) -> void:
	super.setup(host, map_id, map, font, enabled)
	_stage = StageScript.new()
	_stage.name = "TownHD2DStage"
	add_child(_stage)
	_stage.call("setup", self, font, map)
	_stage.call("set_actor_frames", _frames(PlayerSheet), _frames(SellerSheet))
	_stage.call("sync", player_position, facing, false, walk_distance, active)
	resized.connect(_resize_stage)
	_resize_stage()
	queue_redraw()


func _frames(sheet: Texture2D) -> Dictionary:
	var result: Dictionary = {"world_height": 1.35, "frame_size": Vector2(80, 112), "foot_anchor": Vector2(40, 104)}
	var directions: Array[String] = ["down", "up", "left", "right"]
	for row: int in range(directions.size()):
		var frames: Array[Texture2D] = []
		for column: int in range(4):
			var frame := AtlasTexture.new()
			frame.atlas = sheet
			frame.region = Rect2(column * 80, row * 112, 80, 112)
			frame.filter_clip = true
			frames.append(frame)
		result[directions[row]] = frames
	return result


func audit() -> Dictionary:
	var result := super.audit()
	result["hd2d"] = _stage.call("audit") if is_instance_valid(_stage) and _stage.has_method("audit") else {}
	return result


func logical_to_local(point: Vector2) -> Vector2:
	if not is_instance_valid(_stage):
		return super.logical_to_local(point)
	var projected: Vector2 = _stage.call("logical_to_screen", point, 0.0)
	return _map_offset() + projected * _map_scale()


func local_to_logical(point: Vector2) -> Vector2:
	if not is_instance_valid(_stage):
		return Vector2(-1, -1)
	return _stage.call("screen_to_logical", (point - _map_offset()) / maxf(_map_scale(), 0.001))


func _resize_stage() -> void:
	if is_instance_valid(_stage) and size.x > 0 and size.y > 0:
		var width := clampi(ceili(size.x), 640, 1280)
		_stage.call("resize_view", Vector2i(width, ceili(float(width) * 9.0 / 16.0)))
	queue_redraw()


func _target_at(render_point: Vector2) -> String:
	var nearest := 46.0
	var found := ""
	for id: String in definition.get("interactions", {}):
		var item: Dictionary = definition.interactions[id]
		var at := Vector2(float(item.position[0]), float(item.position[1]))
		var foot: Vector2 = _stage.call("logical_to_screen", at, 0.0)
		var marker: Vector2 = _stage.call("target_screen_position", id)
		var distance := minf(render_point.distance_to(foot), render_point.distance_to(marker))
		if id == "tea_seller":
			var head: Vector2 = _stage.call("logical_to_screen", at, 1.35)
			if Rect2(Vector2(foot.x - 28, head.y - 6), Vector2(56, foot.y - head.y + 20)).has_point(render_point):
				distance = minf(distance, 12.0)
		if distance < nearest:
			nearest = distance
			found = id
	return found


func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(_stage):
		return
	if event is InputEventMouseMotion:
		var point := ((event as InputEventMouseMotion).position - _map_offset()) / maxf(_map_scale(), 0.001)
		_hover = _target_at(point)
		queue_redraw()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var point := (mouse.position - _map_offset()) / maxf(_map_scale(), 0.001)
			if not Rect2(0, 0, 1280, 720).has_point(point):
				return
			var target_id := _target_at(point)
			if target_id.is_empty():
				click_at(local_to_logical(mouse.position))
			else:
				var coordinates: Array = definition.interactions[target_id].position
				# Reuse the original selection/arrival rules with the real ground anchor.
				click_at(Vector2(float(coordinates[0]), float(coordinates[1])))
			accept_event()


func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_stage):
		_stage.call("sync", player_position, facing, not route.is_empty(), walk_distance, active and is_visible_in_tree())
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#e5dcc6"))
	if not is_instance_valid(_stage) or _font == null:
		return
	var texture: Texture2D = _stage.call("texture")
	if texture == null:
		return
	draw_set_transform(_map_offset(), 0.0, Vector2.ONE * _map_scale())
	draw_texture_rect(texture, Rect2(0, 0, 1280, 720), false)
	if not route.is_empty():
		var points := PackedVector2Array()
		points.append(_stage.call("logical_to_screen", player_position, 0.025))
		for point: Vector2 in route:
			points.append(_stage.call("logical_to_screen", point, 0.025))
		if points.size() > 1:
			draw_polyline(points, Color(0.85, 0.85, 0.65, 0.75), 2.5, true)
		draw_arc(points[-1], 7, 0, TAU, 24, Color("#e1d5ac"), 2)
	for id: String in definition.get("interactions", {}):
		var item: Dictionary = definition.interactions[id]
		var at := Vector2(float(item.position[0]), float(item.position[1]))
		var ground: Vector2 = _stage.call("logical_to_screen", at, 0.02)
		var highlighted := _hover == id or pending_target == id
		draw_arc(ground, 15 if highlighted else 11, 0, TAU, 32, Color("#e1d5ac") if highlighted else Color(0.91, 0.87, 0.73, 0.7), 2)
		var height := 1.55 if id == "tea_seller" else 0.9 if id == "street_sign" else 0.1
		var label_at: Vector2 = _stage.call("logical_to_screen", at, height)
		label_at += Vector2(0, -10 if id == "tea_seller" else 26)
		var label_text := str(item.label)
		var label_width := _font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_style_box(_label_style(), Rect2(label_at - Vector2(label_width * 0.5 + 8, 21), Vector2(label_width + 16, 28)))
		_label(label_at, label_text, Color("#3e4a40"), 20)


func _label_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.92, 0.81, 0.88)
	style.set_corner_radius_all(4)
	return style
