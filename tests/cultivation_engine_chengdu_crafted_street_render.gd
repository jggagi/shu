extends "res://tests/cultivation_engine_chengdu_varied_street_render.gd"
## Retained full input flow with the four-house material/detail sample.

const CraftedScenePath := "res://scenes/demos/cultivation_engine_chengdu_crafted_street.tscn"


func _run() -> void:
	output_dir = "res://.local/qa/chengdu-crafted-street/native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "crafted street uses an actual native display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ScaleWorldData))
	large_layout = data.scenes.chengdu_city
	test_store_dir = "user://chengdu_crafted_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	app = load(CraftedScenePath).instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start = Time.get_ticks_msec()
	check(_pack_id() == "shu_chengdu_scale" and _state().scene == "tingyu_corridor", "crafted sample retains the original cultivation host and city package")
	await _flow()
	_finish()


func _check_ten_houses() -> bool:
	var original := super._check_ten_houses()
	var audit: Dictionary = _large_audit().get("crafted_street", {})
	var expected := ["ward_city_22_19", "ward_city_23_15", "ward_city_23_19", "ward_city_22_16"]
	var built: Array = audit.get("built_house_ids", [])
	var all_four := built.size() == 4
	for id: String in expected:
		all_four = all_four and id in built
	check(int(audit.get("authored_house_count", 0)) == 4 and all_four, "actual first-street walking reaches exactly the four original house footprints")
	check((audit.get("footprint_errors", ["missing footprint audit"]) as Array).is_empty(), "crafted details remain inside original blocking footprints")
	check(bool(audit.get("no_new_walk_obstacles", false)) and bool(audit.get("continuous_follow_unchanged", false)) and not bool(audit.get("new_state", true)), "crafted presentation retains collisions, camera and the single state authority")
	var surfaces: Dictionary = audit.get("surfaces", {})
	var roles: Array = surfaces.get("loaded_texture_roles", [])
	check(roles.size() == 3 and "paving" in roles and "plaster" in roles and "roof" in roles, "all three actual Bailian materials are loaded")
	check(int(surfaces.get("ground_mesh_count", 0)) > 0 and int(surfaces.get("house_mesh_count", 0)) > 0, "new materials are attached to reached ground and houses")
	check(bool(surfaces.get("no_new_ground_geometry", false)), "the original ground receives material blending without a raised overlay")
	var file := FileAccess.open(_absolute_output_dir().path_join("crafted-street-audit.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(audit, "  "))
	file.close()
	return original and all_four


func _check_actual_street_pixels() -> bool:
	var original := await super._check_actual_street_pixels()
	var walker := app.call("ui_control", "TownWalker") as Control
	var stage: Node = walker.get("_stage")
	var helper: Node = stage.get("_crafted_surfaces")
	var records: Array = helper.get("records")
	var active: Array = []
	for record: Dictionary in records:
		if is_instance_valid(record.node) and (record.node as MeshInstance3D).is_visible_in_tree():
			active.append(record)
	var was_paused := paused
	paused = true
	for record: Dictionary in active:
		(record.node as MeshInstance3D).material_override = record.old_material
	await process_frame
	await RenderingServer.frame_post_draw
	var before: Image = stage.call("texture").get_image()
	for record: Dictionary in active:
		(record.node as MeshInstance3D).material_override = record.material
	await process_frame
	await RenderingServer.frame_post_draw
	var after: Image = stage.call("texture").get_image()
	paused = was_paused
	var proof := _pixel_proof(before, after, 0.005)
	proof["scope"] = "Actual native first-street walking. Tree paused during old/new material comparison; same geometry, actors, camera and state."
	proof["material_records_toggled"] = active.size()
	before.save_png(_absolute_output_dir().path_join("crafted-materials-before.png"))
	after.save_png(_absolute_output_dir().path_join("crafted-materials-after.png"))
	var file := FileAccess.open(_absolute_output_dir().path_join("crafted-material-pixel-proof.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(proof, "  "))
	file.close()
	var visible := int(proof.changed_pixels) > int(proof.total_pixels)*float(proof.threshold)
	check(visible, "actual Bailian materials visibly contribute to the reached street viewport")
	return original and visible
