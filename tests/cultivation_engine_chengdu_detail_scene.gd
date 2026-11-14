extends SceneTree
## Actual GPU geometry review of a local façade pass; not native input proof.

class ProbeWalker extends Control:
	var scene_id := "chengdu_city"
	var route: Array[Vector2] = []
	var player_position := Vector2(7800,10080)

var _walker: Control
var _stage: Node
var _font: Font
var _definition: Dictionary
var _output := "user://detail-scene-qa"
var _variant := "detail"
var _index := 0
var _frame := 0
var _results: Array = []
var _failures: Array = []
var _points: Array = [
	{"name":"01_bridge_south","point":Vector2(7800,10080)},
	{"name":"02_bridge_middle","point":Vector2(7800,9450)},
	{"name":"03_bridge_north","point":Vector2(7800,9010)},
	{"name":"04_gate_approach","point":Vector2(7800,8650)},
	{"name":"05_gate_underpass","point":Vector2(7800,8440)},
	{"name":"06_first_street","point":Vector2(7800,7560)},
	{"name":"07_west_shop","point":Vector2(7460,7700)},
	{"name":"08_east_shop","point":Vector2(8430,7700)}]


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--variant="):
			_variant = argument.trim_prefix("--variant=")
	DirAccess.make_dir_recursive_absolute(_output)
	call_deferred("_start")


func _start() -> void:
	_definition = JSON.parse_string(FileAccess.get_file_as_string("res://games/shu_chengdu_scale/walks.json")).scenes.chengdu_city
	_walker = ProbeWalker.new()
	root.add_child(_walker)
	_stage = load("res://addons/cultivation_mode/chengdu_detail_stage.gd" if _variant=="detail" else "res://addons/cultivation_mode/chengdu_scale_stage.gd").new()
	_walker.add_child(_stage)
	_font = load("res://assets/fonts/ShuChengduScaleSerif.ttf")
	_stage.setup(_walker,_font,_definition)
	_stage.sync(_points[0].point,"down",false,0,true)
	var audit: Dictionary = _stage.audit()
	if int(audit.scale_geometry.authored_houses)!=592 or int(audit.scale_geometry.authored_lots)!=614:
		_failures.append({"wrong_base_layout":audit.get("layout_source",""),"scale_geometry":audit.scale_geometry})
	if _variant=="detail" and (not bool(audit.detail_geometry.south_gate_built) or not bool(audit.detail_geometry.wanli_bridge_built)):
		_failures.append({"expected_detail_gate_and_bridge_not_built":audit.detail_geometry})


func _process(_delta: float) -> bool:
	if _stage == null:
		return false
	_frame += 1
	var point: Vector2 = _points[_index].point
	if _frame==1:
		_stage.call("_update_follow_camera",point,1.0,true)
	_stage.sync(point,"down",false,0.0,true)
	if _frame==30:
		var audit: Dictionary = _stage.audit()
		var errors: Array = _stage.validate()
		if not errors.is_empty():
			_failures.append({"point":_points[_index].name,"geometry_errors":errors})
		if _variant=="detail":
			for record: Dictionary in audit.detail_geometry.raised_footprints:
				if not bool(record.within_obstacle):
					_failures.append({"point":_points[_index].name,"raised_footprint_outside_old_obstacle":record})
		_stage.texture().get_image().save_png(_output.path_join(str(_points[_index].name)+".png"))
		_results.append({"point":point,"name":_points[_index].name,"audit":audit,"geometry_errors":errors,"projection_error":_stage.screen_to_logical(_stage.logical_to_screen(point)).distance_to(point)})
		print("DETAIL_SCENE_CAPTURE ",_variant," ",_points[_index].name," errors=",errors.size())
		_index += 1
		_frame = 0
		if _index >= _points.size():
			var file := FileAccess.open(_output.path_join("scene-report.json"),FileAccess.WRITE)
			file.store_string(JSON.stringify({"variant":_variant,"captures":_results,"failures":_failures,"scope":"Actual GPU geometry, contact and projection review. QA-positioned actor; not Session/native mouse input."},"  "))
			file.close()
			print("DETAIL_SCENE_DONE ",_variant," captures=",_results.size()," failures=",_failures.size())
			_walker.free()
			_stage = null
			quit(0 if _failures.is_empty() else 1)
	return false
