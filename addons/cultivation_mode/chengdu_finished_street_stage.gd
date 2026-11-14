extends "res://addons/cultivation_mode/chengdu_layered_street_stage.gd"


func _create_layered_street() -> Node:
	return load("res://addons/cultivation_mode/chengdu_grounded_street.gd").new()
