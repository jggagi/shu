extends "res://addons/cultivation_mode/chengdu_layered_street_mode_view.gd"

const FinishedWalker=preload("res://addons/cultivation_mode/chengdu_finished_street_walker.gd")


func _new_city_walker() -> Control:
	var walker:=FinishedWalker.new()
	walker.navigation_cache=_scale_navigation_cache
	return walker
