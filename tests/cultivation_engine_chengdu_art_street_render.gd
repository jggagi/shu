extends "res://tests/cultivation_engine_chengdu_scale_render.gd"
## Retained full input flow with the eighteen-house whole-street art slice.

const ArtStreetScenePath := "res://scenes/demos/cultivation_engine_chengdu_art_street.tscn"


func _run() -> void:
	output_dir = "res://.local/qa/chengdu-art-street/native"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "art street uses an actual native display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ScaleWorldData))
	large_layout = data.scenes.chengdu_city
	test_store_dir = "user://chengdu_art_render_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	app = load(ArtStreetScenePath).instantiate()
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start = Time.get_ticks_msec()
	check(_pack_id() == "shu_chengdu_scale" and _state().scene == "tingyu_corridor", "art street sample retains the original cultivation host and city package")
	await _flow()
	_finish()


var _art_captured := false

func _map_move(point: Vector2) -> bool:
	if not _art_captured and point.distance_to(_region_point("north_precinct")) < 1:
		_art_captured = true
		for row: Dictionary in [{"point":Vector2(7800,8400),"file":"01a_retained_gate.png"},{"point":Vector2(7800,7560),"file":"01b_art_street_south.png"},{"point":Vector2(7800,7290),"file":"01c_art_street_middle.png"},{"point":Vector2(7450,7420),"file":"01d_art_street_lane.png"},{"point":Vector2(7800,7010),"file":"01e_art_street_north.png"}]:
			if not await super._map_move(row.point):
				return false
			await _check_large_view()
			if str(row.file)=="01c_art_street_middle.png":
				if not _check_art_street() or not await _check_art_pixels():
					return false
			await _capture(str(row.file), "actual continuous-camera full-street artwork")
	return await super._map_move(point)

func _check_art_street() -> bool:
	var audit: Dictionary = _large_audit().get("art_street", {})
	var ids: Array = audit.get("built_house_ids", [])
	var present := ids.size() == 18
	check(int(audit.get("authored_house_count",0))==18 and present,"all eighteen authored houses remain original lots")
	check((audit.get("footprint_errors",["missing footprint audit"]) as Array).is_empty(),"new solid details remain inside original collision footprints")
	check(bool(audit.get("no_new_walk_obstacles",false)) and bool(audit.get("continuous_follow_unchanged",false)) and not bool(audit.get("new_state",true)),"complete street preserves navigation, continuous camera and state")
	var art: Dictionary = audit.get("art",{})
	check(int(art.get("view_count",0))==3 and int(art.get("installed_mesh_count",0))>0,"three actual paintings are installed on world surfaces")
	check(bool(art.get("world_projective",false)) and bool(art.get("no_screen_locked_art",false)),"paint stays attached to world geometry during following")
	check(not bool(art.get("painting_rgb_blended",true)) and not bool(art.get("current_camera_affects_art_selection",true)),"fixed world surfaces use one painting without camera-driven ghosting")
	var file:=FileAccess.open(_absolute_output_dir().path_join("art-street-audit.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(audit,"  "));file.close()
	return present

func _check_art_pixels() -> bool:
	var walker := app.call("ui_control","TownWalker") as Control
	var stage: Node = walker.get("_stage")
	var helper: Node = stage.get("_art_street_art")
	var records: Array = helper.get("records")
	var was_paused:=paused
	paused=true
	for record: Dictionary in records:
		if is_instance_valid(record.node):
			record.node.material_overlay=record.old_overlay
	await process_frame
	await RenderingServer.frame_post_draw
	var before: Image=stage.call("texture").get_image()
	for record: Dictionary in records:
		if is_instance_valid(record.node):
			record.node.material_overlay=record.material
	await process_frame
	await RenderingServer.frame_post_draw
	var after: Image=stage.call("texture").get_image()
	paused=was_paused
	before.save_png(_absolute_output_dir().path_join("art-street-paint-off.png"))
	after.save_png(_absolute_output_dir().path_join("art-street-paint-on.png"))
	before.convert(Image.FORMAT_RGBA8);after.convert(Image.FORMAT_RGBA8)
	var a:=before.get_data();var b:=after.get_data();var changed:=0
	for i: int in range(0,mini(a.size(),b.size()),4):
		if maxi(maxi(absi(int(a[i])-int(b[i])),absi(int(a[i+1])-int(b[i+1]))),absi(int(a[i+2])-int(b[i+2])))>=15:
			changed+=1
	var visible:=changed>after.get_width()*after.get_height()*0.12
	check(visible,"whole-street painting visibly contributes to the actual native viewport")
	var proof:={"changed_pixels":changed,"total_pixels":after.get_width()*after.get_height(),"threshold":0.12,"scope":"Same real application, paused tree; only the new world-projective paintings toggled, no actor/state/camera changes."}
	var file:=FileAccess.open(_absolute_output_dir().path_join("art-street-pixel-proof.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(proof,"  "));file.close()
	return visible
