extends "res://addons/cultivation_mode/chengdu_compact_street_walker.gd"

const CornerStage=preload("res://addons/cultivation_mode/chengdu_tea_corner_stage.gd")


func _create_stage() -> Node:
	if scene_id!="chengdu_city":
		return super._create_stage()
	var stage:=CornerStage.new()
	stage.layout_path=layout_path
	return stage
