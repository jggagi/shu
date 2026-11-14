extends "res://addons/cultivation_mode/chengdu_scale_walker.gd"

const IllustratedStage=preload("res://addons/cultivation_mode/chengdu_illustrated_street_stage.gd")


func _create_stage() -> Node:
	if scene_id!="chengdu_city":
		return super._create_stage()
	var stage:=IllustratedStage.new()
	stage.layout_path=layout_path
	return stage
