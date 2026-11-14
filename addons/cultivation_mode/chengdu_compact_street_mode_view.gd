extends "res://addons/cultivation_mode/chengdu_finished_street_mode_view.gd"

const CompactWalker=preload("res://addons/cultivation_mode/chengdu_compact_street_walker.gd")


func _layout_path() -> String:
	return "res://assets/data/chengdu-compact-street-layout.json"


func _new_city_walker() -> Control:
	var walker:=CompactWalker.new()
	walker.navigation_cache=_scale_navigation_cache
	return walker
