extends Control
## A navigation view of the authored city. Walking still goes through the host.

var walker: Control
var definition: Dictionary = {}
var layout: Dictionary = {}
var _font: Font
var _collapsed := false
var _hint := "点石路规划路线"


func setup(view: Control, map: Dictionary, composition: Dictionary, font: Font) -> void:
	walker = view
	definition = map
	layout = composition
	_font = font
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	tooltip_text = "点击城图中的石路前往；点击标题可收起。"


func _process(_delta: float) -> void:
	queue_redraw()


func _map_rect() -> Rect2:
	return Rect2(10, 32, maxf(size.x - 20, 1), maxf(size.y - 58, 1))


func logical_to_local(point: Vector2) -> Vector2:
	var world: Array = definition.get("size", [3840, 2160])
	return _map_rect().position + point / Vector2(float(world[0]), float(world[1])) * _map_rect().size


func local_to_logical(point: Vector2) -> Vector2:
	var world: Array = definition.get("size", [3840, 2160])
	return (point - _map_rect().position) / _map_rect().size * Vector2(float(world[0]), float(world[1]))


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not is_instance_valid(walker) or not bool(walker.call("_current")):
		return
	if event.position.y < 28:
		_handle_title_click(event.position)
	elif not _collapsed and _map_rect().has_point(event.position):
		var destination := local_to_logical(event.position).round()
		var accepted: bool = walker.call("click_at", destination)
		_hint = "沿石路走过去" if accepted else "此处走不到，请点石路"
	accept_event()
	queue_redraw()


func _handle_title_click(_point: Vector2) -> void:
	_collapsed = not _collapsed
	offset_bottom = offset_top + (30 if _collapsed else 190)


func _title_text() -> String:
	return "展开城图" if _collapsed else "城图 · 点标题收起"


func _label_entries() -> Array:
	return layout.get("regions", [])


func _building_color(building: Dictionary) -> Color:
	return Color("#799d9b") if building.get("kind", "") == "water" else Color("#8e9b87")


func _draw_map_details() -> void:
	pass


func _paint_rect(raw: Array, color: Color) -> void:
	var start := logical_to_local(Vector2(float(raw[0]), float(raw[1])))
	var end := logical_to_local(Vector2(float(raw[0]) + float(raw[2]), float(raw[1]) + float(raw[3])))
	draw_rect(Rect2(start, end - start), color)


func _draw() -> void:
	if _font == null or definition.is_empty():
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.94, 0.86, 0.95)
	style.border_color = Color("#a79e80")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	draw_style_box(style, Rect2(Vector2.ZERO, size))
	draw_string(_font, Vector2(11, 21), _title_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#40564d"))
	if _collapsed:
		return
	draw_rect(_map_rect(), Color("#c5cdb8"))
	for band: Array in layout.get("street_bands", []):
		_paint_rect(band, Color("#e4ddc2"))
	for building: Dictionary in layout.get("buildings", []):
		_paint_rect(building.bounds, _building_color(building))
		if building.get("kind", "") == "teahouse":
			var bounds: Array = building.bounds
			var center := logical_to_local(Vector2(float(bounds[0]) + float(bounds[2]) * 0.5, float(bounds[1]) + float(bounds[3]) * 0.5))
			draw_string(_font, center - Vector2(13, 0), "茶馆", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#fbf3d9"))
	_draw_map_details()
	if is_instance_valid(walker):
		var route: Array = walker.get("route")
		var player: Vector2 = walker.get("player_position")
		if not route.is_empty():
			var points := PackedVector2Array([logical_to_local(player)])
			for point: Vector2 in route:
				points.append(logical_to_local(point))
			draw_polyline(points, Color("#9b793e"), 2)
		for region: Dictionary in _label_entries():
			var at: Array = region.get("label_position", region.get("position", []))
			if at.size() != 2:
				continue
			var text := str(region.label)
			var label_point := logical_to_local(Vector2(float(at[0]), float(at[1])))
			var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string_outline(_font, label_point - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color("#eee9d8"))
			draw_string(_font, label_point - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#35483d"))
		var marker := logical_to_local(player)
		draw_circle(marker, 5, Color("#344f48"))
		draw_circle(marker, 3, Color("#fff2b4"))
	draw_string(_font, Vector2(11, size.y - 8), _hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#606450"))
