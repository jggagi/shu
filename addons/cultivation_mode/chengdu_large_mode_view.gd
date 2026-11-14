extends "res://addons/cultivation_mode/chengdu_mode_view.gd"
## Continuous city presentation; original Session remains the state authority.

const LargeWalker = preload("res://addons/cultivation_mode/chengdu_large_walker.gd")
const CityMap = preload("res://addons/cultivation_mode/chengdu_city_map.gd")
const LARGE_LAYOUT := "res://assets/data/chengdu-large-layout.json"
const LARGE_FONT := "res://assets/fonts/ShuChengduLargeSerif.ttf"
var _city_location: Label
var _large_layout: Dictionary = {}
var _last_place := ""


func _make_theme() -> Theme:
	var result := super._make_theme()
	if ResourceLoader.exists(LARGE_FONT):
		result.default_font = load(LARGE_FONT) as Font
	return result


func _layout() -> Dictionary:
	if _large_layout.is_empty() and FileAccess.file_exists(_layout_path()):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_layout_path()))
		if data is Dictionary:
			_large_layout = data.get("scenes", {}).get("chengdu_city", {})
	return _large_layout


func _layout_path() -> String:
	return LARGE_LAYOUT


func _new_city_walker() -> Control:
	return LargeWalker.new()


func _new_city_map() -> Control:
	return CityMap.new()


func _build_header() -> PanelContainer:
	var panel := super._build_header()
	if _view_mode == "game" and _session != null:
		var row := panel.get_child(0).get_child(0)
		if row.get_child_count() > 1 and row.get_child(1) is Label:
			_city_location = row.get_child(1)
			_city_location.name = "CityLocationLabel"
			_register_control(_city_location)
	return panel


func _process(_delta: float) -> void:
	if is_instance_valid(_city_location) and is_instance_valid(_town_walker) and str(_town_walker.get("scene_id")) == "chengdu_city" and _view_mode == "game":
		var place := _district_at(_town_walker.get("player_position"))
		if place != _last_place:
			_city_location.text = _clock_and_location_text()


func _clock_and_location_text() -> String:
	var text := super._clock_and_location_text()
	if _session == null or str(_snapshot().get("scene", "")) != "chengdu_city":
		return text
	var coordinates: Array = _snapshot().exploration.positions.chengdu_city
	var point := Vector2(float(coordinates[0]), float(coordinates[1]))
	_last_place = _district_at(point)
	return text + (" / " + _last_place if not _last_place.is_empty() else "")


func _district_at(point: Vector2) -> String:
	for region: Dictionary in _layout().get("regions", []):
		var bounds: Array = region.bounds
		if Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3])).has_point(point):
			return str(region.label)
	return ""


func _next_city_step() -> String:
	var state := _snapshot()
	if str(state.get("scene", "")) == "chengdu_city" and not bool(state.get("flags", {}).get("chengdu_umbrella_carrying", false)) and not bool(state.get("flags", {}).get("chengdu_umbrella_returned", false)):
		return "点石路行走，镜头随人移动 · 右上城图可规划远路 · 茶馆前后门都可进入"
	return super._next_city_step()


func _on_town_feedback(message: String) -> void:
	var label := ui_control("StatusLabel") as Label
	if is_instance_valid(label):
		label.text = message


func _build_scene_surface(scene_info: Dictionary) -> void:
	if not _town_scene():
		super._build_scene_surface(scene_info)
		return
	_town_walker = _new_city_walker()
	_town_walker.name = "TownWalker"
	_town_walker.set("layout_path", _layout_path())
	_town_walker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_surface.add_child(_town_walker)
	_register_control(_town_walker)
	var state := _snapshot()
	var map_id := str(state.scene)
	var map: Dictionary = _current_pack().walks.scenes[map_id]
	var enabled: bool = state.phase == "ready" and _confirmation.is_empty() and not _menu_open and not _input_busy
	_town_walker.call("setup", _session, map_id, map, _theme_resource.default_font, enabled)
	var stage: Node = _town_walker.get("_stage")
	if stage != null and stage.has_method("set_city_flags"):
		stage.call("set_city_flags", state.get("flags", {}))
	_town_walker.connect("interaction_requested", _on_town_interaction)
	_town_walker.connect("feedback", _on_town_feedback)
	if map_id == "chengdu_city":
		var city_map := _new_city_map()
		city_map.name = "CityMap"
		city_map.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		city_map.offset_left = -292
		city_map.offset_right = -12
		city_map.offset_top = 12
		city_map.offset_bottom = 202
		_scene_surface.add_child(city_map)
		city_map.call("setup", _town_walker, map, _layout(), _theme_resource.default_font)
		_register_control(city_map)
