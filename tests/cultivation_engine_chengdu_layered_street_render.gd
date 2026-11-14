extends "res://tests/cultivation_engine_chengdu_illustrated_street_render.gd"
## Reuse the complete original native input journey with the painted variant.


func _run() -> void:
	output_dir="res://.local/qa/chengdu-illustrated-street/native"
	_parse_user_args()
	root.mode=Window.MODE_WINDOWED
	root.size=qa_size
	Engine.max_fps=60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name()!="headless","illustrated street uses an actual native display")
	if DisplayServer.get_name()=="headless":
		_finish()
		return
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ScaleWorldData))
	large_layout=data.scenes.chengdu_city
	test_store_dir="user://chengdu_illustrated_render_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	app=load("res://scenes/demos/cultivation_engine_chengdu_layered_street.tscn").instantiate()
	app.set("save_base_dir",test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start=Time.get_ticks_msec()
	check(_pack_id()=="shu_chengdu_scale" and _state().scene=="tingyu_corridor","illustrated variant retains the original cultivation host and package")
	await _flow()
	_finish()


func _check_art_street() -> bool:
	var original: bool=super._check_art_street()
	var audit: Dictionary=_large_audit().get("layered_street",{})
	check(int(audit.get("split_house_count",0))==4,"four authored tea/corner/lane lots use separate painted sections")
	check(int(audit.get("mesh_sections",0))==12 and int(audit.get("contact_strips",0))==8,"painted relief sections and soft foundation contacts are present")
	check(int(audit.get("motion_materials",0))==3,"one vessel steam and two cloth pennants are present")
	check((audit.get("errors",["missing helper"]) as Array).is_empty(),"layered composition has no geometry errors")
	return original


func _check_art_pixels() -> bool:
	var walker:=app.call("ui_control","TownWalker") as Control
	var stage: Node=walker.get("_stage")
	var helper: Node=stage.get("_layered_street")
	var was_paused:=paused
	paused=true
	await process_frame
	await RenderingServer.frame_post_draw
	var layered: Image=stage.call("texture").get_image()
	helper.call("set_enabled",false)
	await process_frame
	await RenderingServer.frame_post_draw
	var flat: Image=stage.call("texture").get_image()
	layered.save_png(_absolute_output_dir().path_join("layered-on.png"))
	flat.save_png(_absolute_output_dir().path_join("layered-flat-control.png"))
	layered.convert(Image.FORMAT_RGBA8)
	flat.convert(Image.FORMAT_RGBA8)
	var a:=layered.get_data()
	var b:=flat.get_data()
	var changed:=0
	for i: int in range(0,mini(a.size(),b.size()),4):
		if maxi(maxi(absi(int(a[i])-int(b[i])),absi(int(a[i+1])-int(b[i+1]))),absi(int(a[i+2])-int(b[i+2])))>=8:
			changed+=1
	check(changed>1000,"layered finish visibly changes the same paused painted street")
	var f:=FileAccess.open(_absolute_output_dir().path_join("layered-pixel-proof.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"changed_pixels":changed,"minimum_channel_change":8,"same_camera":true,"scope":"Four-lot finish versus accepted flat paintings; paused actual app."},"  "))
	f.close()
	var inherited: bool=await super._check_art_pixels()
	helper.call("set_enabled",true)
	paused=was_paused
	return inherited and changed>1000
