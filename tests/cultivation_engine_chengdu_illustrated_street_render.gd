extends "res://tests/cultivation_engine_chengdu_art_street_render.gd"
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
	app=load("res://scenes/demos/cultivation_engine_chengdu_illustrated_street.tscn").instantiate()
	app.set("save_base_dir",test_store_dir)
	root.add_child(app)
	await process_frame
	await process_frame
	_trace_start=Time.get_ticks_msec()
	check(_pack_id()=="shu_chengdu_scale" and _state().scene=="tingyu_corridor","illustrated variant retains the original cultivation host and package")
	await _flow()
	_finish()


func _check_art_street() -> bool:
	var audit: Dictionary=_large_audit().get("illustrated_street",{})
	var present:=int(audit.get("painted_houses",0))==18
	check(present and int(audit.get("layer_count",0))==6,"six paintings provide eighteen original street silhouettes")
	check((audit.get("errors",["missing painting"]) as Array).is_empty(),"painted layers and original occlusion rows load without errors")
	check(int(audit.get("new_obstacles",-1))==0 and not bool(audit.get("new_state",true)),"painted comparison preserves original navigation and state")
	check(bool(audit.get("continuous_follow",false)) and float(audit.get("fixed_yaw_degrees",0))==45.0,"fixed illustrated angle retains continuous camera translation")
	check(int(audit.get("reoriented_cast_cards",0))>0 and int(audit.get("painted_signs",0))>0,"existing merchants and real text signs adapt to the illustrated angle")
	var file:=FileAccess.open(_absolute_output_dir().path_join("illustrated-street-audit.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(audit,"  "))
	file.close()
	return present


func _check_art_pixels() -> bool:
	var walker:=app.call("ui_control","TownWalker") as Control
	var stage: Node=walker.get("_stage")
	var helper: Node=stage.get("_illustrated_street")
	var was_paused:=paused
	paused=true
	await process_frame
	await RenderingServer.frame_post_draw
	var painted: Image=stage.call("texture").get_image()
	helper.call("set_enabled",false)
	await process_frame
	await RenderingServer.frame_post_draw
	var models: Image=stage.call("texture").get_image()
	helper.call("set_enabled",true)
	await process_frame
	await RenderingServer.frame_post_draw
	paused=was_paused
	painted.save_png(_absolute_output_dir().path_join("illustrated-on.png"))
	models.save_png(_absolute_output_dir().path_join("illustrated-model-control.png"))
	painted.convert(Image.FORMAT_RGBA8)
	models.convert(Image.FORMAT_RGBA8)
	var a:=painted.get_data()
	var b:=models.get_data()
	var changed:=0
	for i: int in range(0,mini(a.size(),b.size()),4):
		if maxi(maxi(absi(int(a[i])-int(b[i])),absi(int(a[i+1])-int(b[i+1]))),absi(int(a[i+2])-int(b[i+2])))>=12:
			changed+=1
	var visible:=changed>painted.get_width()*painted.get_height()*.12
	check(visible,"painted silhouettes visibly change the actual same-camera game viewport")
	var file:=FileAccess.open(_absolute_output_dir().path_join("illustrated-pixel-proof.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"changed_pixels":changed,"total_pixels":painted.get_width()*painted.get_height(),"threshold":.12,"minimum_channel_change":12,"scope":"Same paused actual app, same45-degree camera, original state/ground/actors; only painted street presentation versus retained model colour."},"  "))
	file.close()
	return visible
