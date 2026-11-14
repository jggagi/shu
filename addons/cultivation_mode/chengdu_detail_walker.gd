extends "res://addons/cultivation_mode/chengdu_scale_walker.gd"
## Presentation only; the Scale walker retains movement and navigation authority.

const DetailStageScript = preload("res://addons/cultivation_mode/chengdu_detail_stage.gd")


func _create_stage() -> Node:
	if scene_id != "chengdu_city":
		return super._create_stage()
	var stage := DetailStageScript.new()
	stage.layout_path = layout_path
	return stage
