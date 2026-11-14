extends "res://addons/cultivation_mode/chengdu_scale_walker.gd"

const CraftedStreetStage = preload("res://addons/cultivation_mode/chengdu_crafted_street_stage.gd")


func _create_stage() -> Node:
	if scene_id != "chengdu_city":
		return super._create_stage()
	var stage := CraftedStreetStage.new()
	stage.layout_path = layout_path
	return stage
