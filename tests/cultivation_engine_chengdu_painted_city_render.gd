extends "res://tests/cultivation_engine_chengdu_painted_render.gd"
## The same actual application flow, including the approved gate's pixel test.

const CityScenePath := "res://scenes/demos/cultivation_engine_chengdu_painted_city.tscn"
var _city_pixels_checked := false


func _run() -> void:
	output_dir = "res://.local/qa/chengdu-painted-city/native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "painted city expansion uses an actual display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ScaleWorldData))
	large_layout = data.scenes.chengdu_city
	test_store_dir = "user://chengdu_painted_city_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	app = load(CityScenePath).instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start = Time.get_ticks_msec()
	check(_pack_id() == "shu_chengdu_scale" and _state().scene == "tingyu_corridor", "city-wide surface expansion reuses the original cultivation host and city package")
	await _flow()
	_finish()


func _map_move(point: Vector2) -> bool:
	var arrived := await super._map_move(point)
	if arrived and not _city_pixels_checked and point.distance_to(_region_point("north_precinct")) < 1:
		_city_pixels_checked = true
		if not await _check_city_surface_pixels():
			return false
		await _capture("02a_painted_north_city.png", "real walking leaves the approved gate and reaches the northern city with painted surfaces")
	return arrived


func _check_large_view() -> void:
	await super._check_large_view()
	var surfaces: Dictionary = _large_audit().get("painted_city_surfaces", {})
	check(bool(surfaces.get("atlas_loaded", false)) and int(surfaces.get("tile_count", 0)) == 6, "all six original painterly material cells are loaded in the actual city")
	check(int(surfaces.get("mesh_count", 0)) > 100, "painted surfaces are attached across real city geometry")


func _check_city_surface_pixels() -> bool:
	var walker := app.call("ui_control", "TownWalker") as Control
	var stage: Node = walker.get("_stage")
	var helper: Node = stage.get("_painted_city_surfaces")
	var materials: Array = helper.get("records")
	for record: Dictionary in materials:
		(record.node as GeometryInstance3D).material_override = record.old_material
	await process_frame
	await RenderingServer.frame_post_draw
	var before: Image = stage.call("texture").get_image()
	for record: Dictionary in materials:
		(record.node as GeometryInstance3D).material_override = record.material
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
	var visible := before.get_size() == after.get_size() and changed > pixels*0.15
	check(visible, "new hand-painted surfaces visibly change the actual far northern city after real walking")
	before.save_png(_absolute_output_dir().path_join("city-surfaces-original.png"))
	after.save_png(_absolute_output_dir().path_join("city-surfaces-painted.png"))
	var file := FileAccess.open(_absolute_output_dir().path_join("city-surface-pixel-proof.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"changed_pixels":changed,"total_pixels":pixels,"threshold":0.15,"position":_state().exploration.positions.chengdu_city,"audit":helper.call("audit"),"scope":"Actual app, far northern city reached by native input. Only environmental materials toggled; no state/player injection."}, "  "))
	file.close()
	return visible
