extends "res://addons/cultivation_mode/chengdu_large_walker.gd"
## Reference-map geometry; the same Session-authorized movement and picking.

const ReferenceStageScript = preload("res://addons/cultivation_mode/chengdu_reference_stage.gd")
const REFERENCE_LAYOUT := "res://assets/data/chengdu-reference-layout.json"


func _init() -> void:
	layout_path = REFERENCE_LAYOUT


func _create_stage() -> Node:
	if scene_id != "chengdu_city":
		return super._create_stage()
	var stage := ReferenceStageScript.new()
	stage.layout_path = layout_path
	return stage
