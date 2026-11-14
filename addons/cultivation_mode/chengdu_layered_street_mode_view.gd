extends "res://addons/cultivation_mode/chengdu_illustrated_street_mode_view.gd"

const LayeredWalker=preload("res://addons/cultivation_mode/chengdu_layered_street_walker.gd")


func _new_city_walker() -> Control:
	var walker:=LayeredWalker.new()
	walker.navigation_cache=_scale_navigation_cache
	return walker
