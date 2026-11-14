extends "res://addons/cultivation_mode/town_walker.gd"
## Connected city presentation keeps the existing navigation / arrival gate.

const StageScript = preload("res://addons/cultivation_mode/chengdu_stage.gd")
const ART_SOURCE_PATH := "res://assets/data/chengdu-art-source.json"
var _stage: Node


func setup(host: RefCounted, map_id: String, map: Dictionary, font: Font, enabled: bool) -> void:
	super.setup(host, map_id, map, font, enabled)
	name = "TownWalker"
	_stage = _create_stage()
	_stage.name = "ChengduStage"
	add_child(_stage)
	_stage.call("setup", self, font, map)
	_stage.call("sync", player_position, facing, false, walk_distance, active)
	resized.connect(_resize_stage)
	_resize_stage()


func _create_stage() -> Node:
	return StageScript.new()


func audit() -> Dictionary:
	var result := super.audit()
	result["chengdu"] = _stage.call("audit") if is_instance_valid(_stage) else {}
	result["hd2d"] = result["chengdu"]
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
	if not is_instance_valid(_stage):
		return ""
	var nearest := 43.0
	var found := ""
	for id: String in definition.get("interactions", {}):
		var item: Dictionary = definition.interactions[id]
		var point := Vector2(float(item.position[0]), float(item.position[1]))
		var foot: Vector2 = _stage.call("logical_to_screen", point, 0.0)
		var marker: Vector2 = _stage.call("target_screen_position", id)
		var distance := minf(render_point.distance_to(foot), render_point.distance_to(marker))
		if id == "tea_keeper" or id == "tea_guest":
			var head: Vector2 = _stage.call("logical_to_screen", point, 1.80 if id == "tea_keeper" else 1.45)
			if Rect2(Vector2(foot.x - 30, head.y - 8), Vector2(60, foot.y - head.y + 22)).has_point(render_point):
				distance = minf(distance, 10.0)
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
			var target := _target_at(point)
			if target.is_empty():
				click_at(local_to_logical(mouse.position))
			else:
				var at: Array = definition.interactions[target].position
				click_at(Vector2(float(at[0]), float(at[1])))
			accept_event()


func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_stage):
		_stage.call("sync", player_position, facing, not route.is_empty(), walk_distance, active and is_visible_in_tree())
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#dedfcb"))
	if not is_instance_valid(_stage) or _font == null:
		return
	var frame: Texture2D = _stage.call("texture")
	if frame == null:
		return
	draw_set_transform(_map_offset(), 0, Vector2.ONE * _map_scale())
	draw_texture_rect(frame, Rect2(0, 0, 1280, 720), false)
	if not route.is_empty():
		var points := PackedVector2Array()
		points.append(_stage.call("logical_to_screen", player_position, 0.025))
		for point: Vector2 in route:
			points.append(_stage.call("logical_to_screen", point, 0.025))
		if points.size() > 1:
			draw_polyline(points, Color(0.88, 0.88, 0.70, 0.75), 2.5, true)
		draw_arc(points[-1], 7, 0, TAU, 24, Color("#e7dec2"), 2)
	for id: String in definition.get("interactions", {}):
		var item: Dictionary = definition.interactions[id]
		var at := Vector2(float(item.position[0]), float(item.position[1]))
		var ground: Vector2 = _stage.call("logical_to_screen", at, 0.025)
		var highlighted := _hover == id or pending_target == id
		draw_arc(ground, 15 if highlighted else 10, 0, TAU, 32, Color("#e1d5ac") if highlighted else Color(0.88, 0.87, 0.72, 0.6), 2)
		var height := 1.88 if id == "tea_keeper" else 1.48 if id == "tea_guest" else 0.03
		var label_at: Vector2 = _stage.call("logical_to_screen", at, height)
		label_at += Vector2(0, -10 if id == "tea_keeper" or id == "tea_guest" else 35)
		var text := str(item.label)
		var label_width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_style_box(_label_style(), Rect2(label_at - Vector2(label_width * 0.5 + 8, 21), Vector2(label_width + 16, 28)))
		_label(label_at, text, Color("#3e5147"), 20)


func _label_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.94, 0.85, 0.90)
	style.set_corner_radius_all(4)
	return style
