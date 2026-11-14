extends "res://addons/cultivation_mode/chengdu_scale_mode_view.gd"
## Ten distinct street houses in the retained continuous Chengdu world.

const VariedStreetWalker = preload("res://addons/cultivation_mode/chengdu_varied_street_walker.gd")


func _new_city_walker() -> Control:
	var walker := VariedStreetWalker.new()
	walker.navigation_cache = _scale_navigation_cache
	return walker
