extends "res://addons/cultivation_mode/chengdu_scale_walker.gd"
## Keep navigation and following camera authority in the accepted scale walker.

const PaintedStage = preload("res://addons/cultivation_mode/chengdu_painted_gate_stage.gd")


func _create_stage() -> Node:
	if scene_id != "chengdu_city":
		return super._create_stage()
	var stage := PaintedStage.new()
	stage.layout_path = layout_path
	return stage
