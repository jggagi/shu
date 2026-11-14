extends "res://addons/cultivation_mode/chengdu_walker.gd"
## The same Session movement/arrival contract with an outdoor follow camera.

const LargeStageScript = preload("res://addons/cultivation_mode/chengdu_large_stage.gd")
var layout_path := "res://assets/data/chengdu-large-layout.json"


func _create_stage() -> Node:
	if scene_id != "chengdu_city":
		return super._create_stage()
	var stage := LargeStageScript.new()
	stage.layout_path = layout_path
	return stage


func _target_at(render_point: Vector2) -> String:
	if scene_id != "chengdu_city":
		return super._target_at(render_point)
	if not is_instance_valid(_stage):
		return ""
	var nearest := 43.0
	var found := ""
	var ids: Array = _stage.call("visible_interaction_ids")
	for id: String in ids:
		var item: Dictionary = definition.interactions[id]
		var point := Vector2(float(item.position[0]), float(item.position[1]))
		var foot: Vector2 = _stage.call("logical_to_screen", point, 0.0)
		var marker: Vector2 = _stage.call("target_screen_position", id)
		var distance := minf(render_point.distance_to(foot), render_point.distance_to(marker))
		if _font != null:
			var label_width := _font.get_string_size(str(item.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			var label_at := foot + Vector2(0, 35)
			label_at.x = clampf(label_at.x, label_width * 0.5 + 10, 1270 - label_width * 0.5)
			if Rect2(label_at - Vector2(label_width * 0.5 + 8, 21), Vector2(label_width + 16, 28)).has_point(render_point):
				distance = minf(distance, 10.0)
		if distance < nearest:
			nearest = distance
			found = id
	return found


func _draw() -> void:
	if scene_id != "chengdu_city":
		super._draw()
		return
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
			if not bool(_stage.call("is_point_visible", point, 0.025, 40.0)):
				break
			points.append(_stage.call("logical_to_screen", point, 0.025))
		if points.size() > 1:
			draw_polyline(points, Color(0.88, 0.88, 0.70, 0.75), 2.5, true)
		if bool(_stage.call("is_point_visible", route[-1], 0.025, 0.0)):
			draw_arc(_stage.call("logical_to_screen", route[-1], 0.025), 7, 0, TAU, 24, Color("#e7dec2"), 2)
	var ids: Array = _stage.call("visible_interaction_ids")
	for id: String in ids:
		var item: Dictionary = definition.interactions[id]
		var at := Vector2(float(item.position[0]), float(item.position[1]))
		var ground: Vector2 = _stage.call("logical_to_screen", at, 0.025)
		var highlighted := _hover == id or pending_target == id
		draw_arc(ground, 15 if highlighted else 10, 0, TAU, 32, Color("#e1d5ac") if highlighted else Color(0.88, 0.87, 0.72, 0.6), 2)
		var label_at := ground + Vector2(0, 35)
		var text := str(item.label)
		var label_width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		# Keep the entire label inside the same 1280x720 view used for picking.
		label_at.x = clampf(label_at.x, label_width * 0.5 + 10, 1270 - label_width * 0.5)
		draw_style_box(_label_style(), Rect2(label_at - Vector2(label_width * 0.5 + 8, 21), Vector2(label_width + 16, 28)))
		_label(label_at, text, Color("#3e5147"), 20)
