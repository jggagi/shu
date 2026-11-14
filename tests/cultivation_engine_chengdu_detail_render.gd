extends "res://tests/cultivation_engine_chengdu_scale_render.gd"
## Replays the approved-scale input workflow against the visual-only entry.
## The extra street capture is reached by mouse navigation, without placement.

const DetailScenePath := "res://scenes/demos/cultivation_engine_chengdu_detail.tscn"
var _detail_street_captured := false


func _run() -> void:
	output_dir = "res://.local/qa/chengdu-detail/native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "detail workflow uses an actual display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ScaleWorldData))
	large_layout = data.scenes.chengdu_city
	test_store_dir = "user://chengdu_detail_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	app = load(DetailScenePath).instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start = Time.get_ticks_msec()
	check(_pack_id() == "shu_chengdu_scale" and _state().scene == "tingyu_corridor", "visual refinement reuses the approved city package and original cultivation entry")
	await _flow()
	_finish()


func _map_move(point: Vector2) -> bool:
	if not _detail_street_captured and point.distance_to(_region_point("north_precinct")) < 1:
		_detail_street_captured = true
		if not await super._map_move(Vector2(7800, 7560)):
			return false
		await _check_large_view()
		var detail: Dictionary = _large_audit().get("detail_geometry", {})
		check((detail.get("built_house_ids", []) as Array).size() == 8, "all eight refined houses are actually prepared on the reached first street")
		await _capture("01a_detail_first_street.png", "actual walking reaches the refined first street north of the south gate")
	return await super._map_move(point)


func _check_large_view() -> void:
	await super._check_large_view()
	var detail: Dictionary = _large_audit().get("detail_geometry", {})
	check(detail.get("base_layout_source", "") == ScaleWorldData, "the running detail stage uses the approved-scale layout")
	check(bool(detail.get("south_gate_built", false)) and bool(detail.get("wanli_bridge_built", false)), "the running city contains the refined gate and bridge")
	check(int(detail.get("authored_house_count", 0)) == 8, "the refinement is limited to eight existing houses")
