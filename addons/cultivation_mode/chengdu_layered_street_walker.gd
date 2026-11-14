extends "res://addons/cultivation_mode/chengdu_illustrated_street_walker.gd"

const LayeredStage=preload("res://addons/cultivation_mode/chengdu_layered_street_stage.gd")


func _create_stage() -> Node:
	if scene_id!="chengdu_city":
		return super._create_stage()
	var stage:=LayeredStage.new()
	stage.layout_path=layout_path
	return stage
