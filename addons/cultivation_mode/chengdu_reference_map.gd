extends "res://addons/cultivation_mode/chengdu_city_map.gd"
## Original schematic drawn from the authored world, with an expanded overview.

var _detail := false


func setup(view: Control, map: Dictionary, composition: Dictionary, font: Font) -> void:
	super.setup(view, map, composition, font)
	get_parent().resized.connect(_resize_mode)
	call_deferred("_resize_mode")


func _title_text() -> String:
	if _collapsed:
		return "展开城图"
	return "全城图 · 点标题缩小" if _detail else "城图 · 点标题查看全城"


func _handle_title_click(point: Vector2) -> void:
	if _collapsed:
		_collapsed = false
	elif point.x > size.x - 62:
		_collapsed = true
		_detail = false
	else:
		_detail = not _detail
	_resize_mode()


func _resize_mode() -> void:
	var dimensions := Vector2(330, 250)
	if _collapsed:
		dimensions.y = 30
	elif _detail:
		dimensions = Vector2(minf(760, get_parent().size.x - 24), minf(620, get_parent().size.y - 24))
		dimensions = dimensions.max(Vector2(330, 250))
	offset_left = -dimensions.x - 12
	offset_right = -12
	offset_top = 12
	offset_bottom = 12 + dimensions.y
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(walker) or not bool(walker.call("_current")):
		return
	var body_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.position.y >= 28
	super._gui_input(event)
	if body_click and _detail and is_instance_valid(walker) and not (walker.get("route") as Array).is_empty():
		_detail = false
		_resize_mode()


func _label_entries() -> Array:
	if not _detail:
		var regions: Array = layout.get("regions", []).duplicate(true)
		for region: Dictionary in regions:
			region.label = str(region.label).split("·")[0]
		return regions
	var labels: Array = layout.get("landmarks", []).duplicate(true)
	for bridge: Dictionary in layout.get("bridges", []):
		labels.append(_area_label(bridge))
	for gate: Dictionary in layout.get("gates", []):
		if str(gate.get("id", "")) == "south_gate":
			labels.append(_area_label(gate))
	labels.append_array(layout.get("map_labels", []))
	return labels


func _area_label(area: Dictionary) -> Dictionary:
	var bounds: Array = area.bounds
	return {"label": str(area.label), "position": [float(bounds[0]) + float(bounds[2]) * 0.5, float(bounds[1]) + float(bounds[3]) * 0.5]}


func _building_color(building: Dictionary) -> Color:
	match str(building.get("kind", "")):
		"water":
			return Color("#7ba4a1")
		"wall", "city_wall":
			return Color("#8e846c")
		"temple", "palace", "citadel", "inner_palace", "academy", "shrine", "pavilion":
			return Color("#b0a17d")
	return Color("#9ca58b")


func _draw_map_details() -> void:
	for bridge: Dictionary in layout.get("bridges", []):
		_paint_rect(bridge.bounds, Color("#d0b78c"))
	for gate: Dictionary in layout.get("gates", []):
		_paint_rect(gate.bounds, Color("#f0d6a5"))
	var at := Vector2(_map_rect().end.x - 15, _map_rect().position.y + 6)
	draw_line(at + Vector2(0, 20), at, Color("#3e5549"), 2)
	draw_line(at, at + Vector2(-4, 7), Color("#3e5549"), 2)
	draw_line(at, at + Vector2(4, 7), Color("#3e5549"), 2)
	draw_string(_font, at + Vector2(-6, 36), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#3e5549"))


func _draw() -> void:
	super._draw()
	if _font != null and not _collapsed:
		draw_string(_font, Vector2(size.x - 48, 21), "收起", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#40564d"))
