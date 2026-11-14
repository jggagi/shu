extends "res://tests/cultivation_engine_chengdu_detail_render.gd"
## Real input through the painted gate, then the retained complete city flow.

const PaintedScenePath := "res://scenes/demos/cultivation_engine_chengdu_painted.tscn"
var _painted_gate_captured := false


func _run() -> void:
	output_dir = "res://.local/qa/chengdu-painted-follow/native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "painted follow workflow uses an actual display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ScaleWorldData))
	large_layout = data.scenes.chengdu_city
	test_store_dir = "user://chengdu_painted_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	app = load(PaintedScenePath).instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start = Time.get_ticks_msec()
	check(_pack_id() == "shu_chengdu_scale" and _state().scene == "tingyu_corridor", "painted follow sample reuses the approved scale package and cultivation host")
	await _flow()
	_finish()


func _map_move(point: Vector2) -> bool:
	if not _painted_gate_captured and point.distance_to(_region_point("north_precinct")) < 1:
		_painted_gate_captured = true
		if not await super._map_move(Vector2(7800, 8400)):
			return false
		var painted: Dictionary = _large_audit().get("painted_gate", {})
		check(bool(painted.get("has_art", false)), "painted gate artwork is loaded in the actual walking scene")
		check(bool(painted.get("has_mask", false)) and bool(painted.get("world_projective", false)) and not bool(painted.get("reference_screen_uv", true)), "painting uses source-masked world projection while the actual camera follows")
		check(int(painted.get("overlay_source_count", 0)) > 0, "painted surfaces are attached to real city geometry")
		if not await _check_actual_painted_pixels():
			return false
		await _capture("01a_painted_gate.png", "actual map walking reaches the calibrated painted gate with the existing continuous-follow camera")
	return await super._map_move(point)


func _check_actual_painted_pixels() -> bool:
	# Exercise the actual application's lifecycle and adaptive SubViewport.
	# Installed materials alone did not catch detached-setup signature failure.
	var walker := app.call("ui_control", "TownWalker") as Control
	var stage: Node = walker.get("_stage")
	var helper: Node = stage.get("_painted_gate")
	var installed: Array = helper.get("_installed")
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
	before.convert(Image.FORMAT_RGBA8)
	after.convert(Image.FORMAT_RGBA8)
	var a := before.get_data()
	var b := after.get_data()
	var changed := 0
	for index: int in range(0, mini(a.size(), b.size()), 4):
		if maxi(maxi(absi(int(a[index])-int(b[index])), absi(int(a[index+1])-int(b[index+1]))), absi(int(a[index+2])-int(b[index+2]))) >= 15:
			changed += 1
	var pixels := after.get_width()*after.get_height()
	var visible := before.get_size() == after.get_size() and changed > pixels*0.10
	check(visible, "painting visibly changes over ten percent of the actual application viewport after real gate walking")
	before.save_png(_absolute_output_dir().path_join("painted-gate-overlay-off.png"))
	after.save_png(_absolute_output_dir().path_join("painted-gate-overlay-on.png"))
	var file := FileAccess.open(_absolute_output_dir().path_join("painted-pixel-proof.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"changed_pixels":changed,"total_pixels":pixels,"viewport_size":[after.get_width(),after.get_height()],"threshold":0.10,"scope":"Actual app reached by native input. Only presentation overlays temporarily toggled; no player/state injection."}, "  "))
	file.close()
	return visible
