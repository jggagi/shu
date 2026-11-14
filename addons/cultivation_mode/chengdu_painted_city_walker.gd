extends "res://addons/cultivation_mode/chengdu_scale_walker.gd"

const CityStage = preload("res://addons/cultivation_mode/chengdu_painted_city_stage.gd")


func _create_stage() -> Node:
	if scene_id != "chengdu_city":
		return super._create_stage()
	var stage := CityStage.new()
	stage.layout_path = layout_path
	return stage
