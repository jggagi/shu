extends "res://addons/cultivation_mode/chengdu_scale_mode_view.gd"
## The accepted gate painting with the same surface language across the city.

const CityWalker = preload("res://addons/cultivation_mode/chengdu_painted_city_walker.gd")


func _new_city_walker() -> Control:
	var walker := CityWalker.new()
	walker.navigation_cache = _scale_navigation_cache
	return walker
