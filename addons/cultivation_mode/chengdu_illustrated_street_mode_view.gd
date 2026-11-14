extends "res://addons/cultivation_mode/chengdu_scale_mode_view.gd"

const IllustratedWalker=preload("res://addons/cultivation_mode/chengdu_illustrated_street_walker.gd")


func _new_city_walker() -> Control:
	var walker:=IllustratedWalker.new()
	walker.navigation_cache=_scale_navigation_cache
	return walker
