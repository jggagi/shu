extends "res://addons/cultivation_mode/chengdu_scale_mode_view.gd"
## The approved city scale with an independently reviewable visual first pass.

const DetailWalker = preload("res://addons/cultivation_mode/chengdu_detail_walker.gd")


func _new_city_walker() -> Control:
	var walker := DetailWalker.new()
	walker.navigation_cache = _scale_navigation_cache
	return walker
