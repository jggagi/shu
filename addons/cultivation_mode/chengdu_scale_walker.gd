extends "res://addons/cultivation_mode/chengdu_reference_walker.gd"
## One Session-authorized walker; large-city routing can survive UI rebuilds.

const ScaleStageScript = preload("res://addons/cultivation_mode/chengdu_scale_stage.gd")
const ScaleNavigationScript = preload("res://addons/cultivation_mode/chengdu_scale_navigation.gd")
const SCALE_LAYOUT := "res://assets/data/chengdu-scale-layout.json"
var navigation_cache: Dictionary = {}


func _init() -> void:
	layout_path = SCALE_LAYOUT


func _create_stage() -> Node:
	if scene_id != "chengdu_city":
		return super._create_stage()
	var stage := ScaleStageScript.new()
	stage.layout_path = layout_path
	return stage


func _new_navigation() -> RefCounted:
	if scene_id != "chengdu_city":
		return super._new_navigation()
	if navigation_cache.has(scene_id):
		return navigation_cache[scene_id] as RefCounted
	var router := ScaleNavigationScript.new()
	navigation_cache[scene_id] = router
	return router
