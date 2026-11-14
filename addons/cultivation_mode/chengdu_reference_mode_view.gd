extends "res://addons/cultivation_mode/chengdu_large_mode_view.gd"

const ReferenceWalker = preload("res://addons/cultivation_mode/chengdu_reference_walker.gd")
const ReferenceMap = preload("res://addons/cultivation_mode/chengdu_reference_map.gd")
const REFERENCE_LAYOUT := "res://assets/data/chengdu-reference-layout.json"
const REFERENCE_FONT := "res://assets/fonts/ShuChengduReferenceSerif.ttf"


func _layout_path() -> String:
	return REFERENCE_LAYOUT


func _new_city_walker() -> Control:
	return ReferenceWalker.new()


func _new_city_map() -> Control:
	return ReferenceMap.new()


func _make_theme() -> Theme:
	var result := super._make_theme()
	if ResourceLoader.exists(REFERENCE_FONT):
		result.default_font = load(REFERENCE_FONT) as Font
	return result


func _next_city_step() -> String:
	var state := _snapshot()
	if not _town_scene():
		return super._next_city_step()
	var flags: Dictionary = state.get("flags", {})
	if bool(flags.get("chengdu_umbrella_returned", false)):
		return "竹伞已放回茶馆失物架。可继续逛城，或从万里桥返山。"
	if bool(flags.get("chengdu_umbrella_carrying", false)):
		return "带着竹伞，去摩诃池畔茶馆的失物架看看。"
	return "沿街闲逛 · 点城图标题可看全城 · 南门、池畔与寺前市均有岔路"
