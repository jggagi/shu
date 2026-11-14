extends "res://addons/cultivation_mode/chengdu_scale_mode_view.gd"
## The accepted continuous city, with one calibrated painted gate sample.

const PaintedWalker = preload("res://addons/cultivation_mode/chengdu_painted_walker.gd")


func _new_city_walker() -> Control:
	var walker := PaintedWalker.new()
	walker.navigation_cache = _scale_navigation_cache
	return walker
