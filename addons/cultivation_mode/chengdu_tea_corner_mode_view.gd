extends "res://addons/cultivation_mode/chengdu_compact_street_mode_view.gd"

const CornerWalker=preload("res://addons/cultivation_mode/chengdu_tea_corner_walker.gd")
const CORNER_DATA="res://assets/data/chengdu-tea-corner-layout.json"
const CORNER_FONT_SOURCE="res://assets/fonts/source-chengdu-tea-corner.json"


func _make_theme() -> Theme:
	var result:=super._make_theme()
	result.default_font=load("res://assets/fonts/ShuChengduTeaCornerSerif.ttf")
	return result


func _new_city_walker() -> Control:
	var walker:=CornerWalker.new()
	walker.navigation_cache=_scale_navigation_cache
	return walker


func _build_header() -> PanelContainer:
	var panel:=super._build_header()
	if str(_snapshot().get("scene",""))!="chengdu_city":
		return panel
	var column:=panel.get_child(0)
	column.get_child(0).get_child(0).text="蜀 · 茶铺街角"
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	column.add_child(row)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(CORNER_DATA))
	for stop: Dictionary in data.stops:
		row.add_child(_make_button(str(stop.label),"CornerStop_"+str(stop.id),_walk_corner_stop.bind(stop.point)))
	return panel


func _walk_corner_stop(coordinates: Array) -> void:
	if not is_instance_valid(_town_walker) or _menu_open or not _confirmation.is_empty():
		return
	_town_walker.call("click_at",Vector2(float(coordinates[0]),float(coordinates[1])))


func _next_city_step() -> String:
	if str(_snapshot().get("scene",""))=="chengdu_city":
		return "点石路闲逛，也可沿茶铺、窄巷与街角走一圈。"
	return super._next_city_step()


func _district_at(point: Vector2) -> String:
	if Rect2(7480,7080,1060,650).has_point(point):
		return "茶铺街角"
	return super._district_at(point)
