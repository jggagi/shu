extends "res://tests/cultivation_engine_chengdu_scale_render.gd"

func _run() -> void:
	output_dir="res://.local/qa/chengdu-compact-street/native"
	_parse_user_args()
	root.mode=Window.MODE_WINDOWED
	root.size=qa_size
	Engine.max_fps=60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name()!="headless","illustrated street uses an actual native display")
	if DisplayServer.get_name()=="headless":
		_finish()
		return
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/chengdu-compact-street-layout.json"))
	large_layout=data.scenes.chengdu_city
	test_store_dir="user://chengdu_illustrated_render_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	app=load("res://scenes/demos/cultivation_engine_chengdu_compact_street.tscn").instantiate()
	app.set("save_base_dir",test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start=Time.get_ticks_msec()
	check(_pack_id()=="shu_chengdu_scale" and _state().scene=="tingyu_corridor","illustrated variant retains the original cultivation host and package")
	await _flow()
	_finish()


var _compact_captured:=false

func _map_move(point: Vector2) -> bool:
	if not _compact_captured and point.distance_to(_region_point("north_precinct"))<1:
		_compact_captured=true
		for row: Dictionary in [{"point":Vector2(7800,8400),"file":"01a_retained_gate.png"},{"point":Vector2(7960,7660),"file":"01b_compact_south.png"},{"point":Vector2(7960,7280),"file":"01c_compact_middle.png"},{"point":Vector2(7580,7395),"file":"01d_compact_lane.png"},{"point":Vector2(8340,7280),"file":"01e_compact_east_lane.png"},{"point":Vector2(7960,6945),"file":"01f_compact_north.png"}]:
			if not await super._map_move(row.point):
				return false
			await _check_large_view()
			var audit: Dictionary=_large_audit()
			var compact: Dictionary=audit.get("compact_street",{})
			check(compact.get("moved_lots",0)==18 and compact.get("main_width_after",0)==360,"eighteen lots use the compact first street")
			var finish: Dictionary=audit.get("layered_street",{})
			check(finish.get("split_house_count",0)==18 and finish.get("mesh_sections",0)==54,"all eighteen relocated houses retain their fifty-four painted sections")
			check(finish.get("errors",["missing"]).is_empty() and finish.get("solid_footprint_errors",["missing"]).is_empty(),"painted sections and solid planters follow the relocated lots")
			check(float(finish.get("grounding",{}).get("contact_corner_max_height_error",1))<.00001,"relocated painted foundations still touch the physical floor")
			await _capture(str(row.file),"actual input follows the compact street and both internal lanes")
	return await super._map_move(point)
