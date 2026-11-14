extends "res://addons/cultivation_mode/chengdu_scale_walker.gd"

const ArtStreetStage = preload("res://addons/cultivation_mode/chengdu_art_street_stage.gd")


func _create_stage() -> Node:
	if scene_id != "chengdu_city":
		return super._create_stage()
	var stage := ArtStreetStage.new()
	stage.layout_path = layout_path
	return stage
