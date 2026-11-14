extends "res://tests/cultivation_engine_chengdu_scale_render.gd"
## The original complete input flow, plus the ten-house presentation slice.

const VariedScenePath := "res://scenes/demos/cultivation_engine_chengdu_varied_street.tscn"
var _street_captured := false


func _run() -> void:
	output_dir = "res://.local/qa/chengdu-varied-street/native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "varied street uses an actual native display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ScaleWorldData))
	large_layout = data.scenes.chengdu_city
	test_store_dir = "user://chengdu_varied_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	app = load(VariedScenePath).instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start = Time.get_ticks_msec()
	check(_pack_id() == "shu_chengdu_scale" and _state().scene == "tingyu_corridor", "ten-house presentation retains the cultivation host and original city package")
	await _flow()
	_finish()


func _map_move(point: Vector2) -> bool:
	if not _street_captured and point.distance_to(_region_point("north_precinct")) < 1:
		_street_captured = true
		if not await super._map_move(Vector2(7800, 8400)):
			return false
		if not await _check_actual_painted_pixels():
			return false
		await _capture("01a_retained_painted_gate.png", "the accepted gate painting remains visible before entering the varied street")
		if not await super._map_move(Vector2(7800, 7560)):
			return false
		await _check_large_view()
		if not _check_ten_houses() or not await _check_actual_street_pixels():
			return false
		await _capture("01b_varied_street_south.png", "actual walking reaches ten varied street houses from the south")
		for row: Dictionary in [{"point":Vector2(7800,7290),"file":"01c_varied_street_middle.png"},{"point":Vector2(7800,7010),"file":"01d_varied_street_north.png"},{"point":Vector2(7450,7420),"file":"01e_varied_street_side_lane.png"}]:
			if not await super._map_move(row.point):
				return false
			await _check_large_view()
			await _capture(row.file, "actual continuous walking shows street-facing doors and varied building heights")
	return await super._map_move(point)


func _check_large_view() -> void:
	await super._check_large_view()
	var audit := _large_audit()
	var surfaces: Dictionary = audit.get("painted_city_surfaces", {})
	check(bool(surfaces.get("atlas_loaded", false)) and int(surfaces.get("tile_count", 0)) == 6, "existing six painterly material cells remain loaded")
	var detail: Dictionary = audit.get("detail_geometry", {})
	check(bool(detail.get("south_gate_built", false)) and bool(detail.get("wanli_bridge_built", false)), "the original detailed south gate and bridge are both constructed")
	var street: Dictionary = audit.get("varied_street", {})
	check(int(street.get("authored_house_count", 0)) == 10, "presentation selects exactly ten existing houses")


func _check_ten_houses() -> bool:
	var street: Dictionary = _large_audit().get("varied_street", {})
	var built: Array = street.get("built_house_ids", [])
	var present := built.size() == 10
	check(present, "all ten varied houses are prepared after actual first-street walking")
	var expected_types := {"home":4,"shop":3,"two_storey":2,"corner_shop":1}
	check(street.get("built_type_counts", {}) == expected_types, "the reached street contains four homes, three shops, two upper-floor houses and one corner shop")
	check((street.get("footprint_errors", ["missing footprint audit"]) as Array).is_empty(), "new house geometry remains inside the original blocking footprints")
	check(int(street.get("gate_overlay_count_on_sample", -1)) == 0, "the old gate painting does not overwrite the ten new house silhouettes")
	check(bool(street.get("no_new_walk_obstacles", false)), "the ten-house slice keeps every original walk obstacle")
	var file := FileAccess.open(_absolute_output_dir().path_join("ten-house-audit.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(street, "  "))
	file.close()
	return present


func _check_actual_street_pixels() -> bool:
	var walker := app.call("ui_control", "TownWalker") as Control
	var stage: Node = walker.get("_stage")
	var houses: Array[Node3D] = []
	for child: Node in (stage.get("world_root") as Node3D).get_children():
		if child is Node3D and child.has_meta("varied_street_id") and (child as Node3D).visible:
			houses.append(child)
	var meshes: Array[MeshInstance3D] = []
	for house: Node3D in houses:
		_collect_visible_street_meshes(house, meshes)
	await process_frame
	await RenderingServer.frame_post_draw
	var after: Image = stage.call("texture").get_image()
	for mesh: MeshInstance3D in meshes:
		mesh.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var before: Image = stage.call("texture").get_image()
	for mesh: MeshInstance3D in meshes:
		mesh.visible = true
	await process_frame
	await RenderingServer.frame_post_draw
	var proof := _pixel_proof(before, after, 0.08)
	proof["scope"] = "Actual app reached by native mouse input. Only currently visible sample house geometry temporarily hidden; player, state, camera and materials unchanged."
	proof["sample_houses_in_view"] = houses.size()
	proof["toggled_meshes"] = meshes.size()
	before.save_png(_absolute_output_dir().path_join("ten-houses-hidden.png"))
	after.save_png(_absolute_output_dir().path_join("ten-houses-visible.png"))
	var file := FileAccess.open(_absolute_output_dir().path_join("ten-house-pixel-proof.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(proof, "  "))
	file.close()
	var visible := int(proof.changed_pixels) > int(proof.total_pixels)*float(proof.threshold)
	check(visible, "new street houses visibly contribute to the real application viewport")
	return visible


func _collect_visible_street_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).visible:
		result.append(node)
	for child: Node in node.get_children():
		_collect_visible_street_meshes(child, result)


func _pixel_proof(before: Image, after: Image, threshold: float) -> Dictionary:
	check(before.get_size() == after.get_size(), "pixel controls keep the same actual viewport dimensions")
	if before.get_size() != after.get_size():
		return {"changed_pixels":0,"total_pixels":after.get_width()*after.get_height(),"threshold":threshold,"error":"viewport size changed"}
	before.convert(Image.FORMAT_RGBA8)
	after.convert(Image.FORMAT_RGBA8)
	var a := before.get_data()
	var b := after.get_data()
	var changed := 0
	for index: int in range(0, mini(a.size(), b.size()), 4):
		if maxi(maxi(absi(int(a[index])-int(b[index])), absi(int(a[index+1])-int(b[index+1]))), absi(int(a[index+2])-int(b[index+2]))) >= 15:
			changed += 1
	return {"changed_pixels":changed,"total_pixels":after.get_width()*after.get_height(),"threshold":threshold,"viewport_size":[after.get_width(),after.get_height()]}


func _check_actual_painted_pixels() -> bool:
	var walker := app.call("ui_control", "TownWalker") as Control
	var stage: Node = walker.get("_stage")
	var helper: Node = stage.get("_painted_gate")
	var installed: Array = helper.get("_installed")
	var gate_core := 0
	for record: Dictionary in installed:
		var ancestor: Node = record.node
		while ancestor != null and ancestor != stage.get("world_root"):
			if str(ancestor.name).begins_with("DetailedOpenSouthGate"):
				gate_core += 1
				break
			ancestor = ancestor.get_parent()
	check(gate_core > 0, "retained painting is still attached to the actual south gate core")
	for record: Dictionary in installed:
		(record.node as GeometryInstance3D).material_overlay = null
	await process_frame
	await RenderingServer.frame_post_draw
	var before: Image = stage.call("texture").get_image()
	for record: Dictionary in installed:
		(record.node as GeometryInstance3D).material_overlay = record.material
	await process_frame
	await RenderingServer.frame_post_draw
	var after: Image = stage.call("texture").get_image()
	var proof := _pixel_proof(before, after, 0.10)
	proof["gate_core_overlay_count"] = gate_core
	proof["scope"] = "Actual app reached by native input. Only retained gate overlays temporarily toggled; no player/state injection."
	before.save_png(_absolute_output_dir().path_join("painted-gate-overlay-off.png"))
	after.save_png(_absolute_output_dir().path_join("painted-gate-overlay-on.png"))
	var file := FileAccess.open(_absolute_output_dir().path_join("painted-pixel-proof.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(proof, "  "))
	file.close()
	var visible := int(proof.changed_pixels) > int(proof.total_pixels)*float(proof.threshold)
	check(visible, "retained gate painting visibly changes the actual application viewport")
	return visible
