extends "res://addons/cultivation_mode/chengdu_reference_mode_view.gd"

const ScaleWalker = preload("res://addons/cultivation_mode/chengdu_scale_walker.gd")
const SCALE_LAYOUT := "res://assets/data/chengdu-scale-layout.json"
const SCALE_FONT := "res://assets/fonts/ShuChengduScaleSerif.ttf"
# Geometry caches belong to this view, never to a save or a second state host.
var _scale_navigation_cache: Dictionary = {}


func _layout_path() -> String:
	return SCALE_LAYOUT


func _new_city_walker() -> Control:
	var walker := ScaleWalker.new()
	walker.navigation_cache = _scale_navigation_cache
	return walker


func _make_theme() -> Theme:
	var result := super._make_theme()
	if ResourceLoader.exists(SCALE_FONT):
		result.default_font = load(SCALE_FONT) as Font
	return result
