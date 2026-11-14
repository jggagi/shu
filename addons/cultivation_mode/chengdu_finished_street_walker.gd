extends "res://addons/cultivation_mode/chengdu_layered_street_walker.gd"

const FinishedStage=preload("res://addons/cultivation_mode/chengdu_finished_street_stage.gd")


func _create_stage() -> Node:
	if scene_id!="chengdu_city":
		return super._create_stage()
	var stage:=FinishedStage.new()
	stage.layout_path=layout_path
	return stage
