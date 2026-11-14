extends "res://addons/cultivation_mode/chengdu_scale_mode_view.gd"
## The accepted continuous city host with four refined street exteriors.

const CraftedStreetWalker = preload("res://addons/cultivation_mode/chengdu_crafted_street_walker.gd")


func _new_city_walker() -> Control:
	var walker := CraftedStreetWalker.new()
	walker.navigation_cache = _scale_navigation_cache
	return walker
