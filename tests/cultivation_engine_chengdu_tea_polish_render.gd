extends "res://tests/cultivation_engine_chengdu_market_life_render.gd"
## Keep the complete playable flow and observe the new finish at normal distance.


func _check_art_pixels() -> bool:
	if not await super._check_art_pixels():
		return false
	var walker:=app.call("ui_control","TownWalker") as Control
	var stage: Node=walker.get("_stage")
	var audit: Dictionary=stage.call("audit")
	var polish: Dictionary=audit.get("tea_polish",{})
	var grade: Dictionary=audit.get("tea_grade",{})
	check(int(polish.get("tree_count",0))==1 and int(polish.get("merchant_count",0))==1 and int(polish.get("tea_shop_count",0))==1 and int(polish.get("gallery_count",0))==1,"finish stays limited to one tree, one merchant and two facades")
	check((polish.get("errors",["missing polish"]) as Array).is_empty(),"tea-shop art loads without errors")
	check((polish.get("bounds_errors",["missing bounds"]) as Array).is_empty(),"tea polish respects solid and character placement bounds")
	check((grade.get("errors",["missing grade"]) as Array).is_empty() and bool(grade.get("fragment_only",false)),"bounded colour pass preserves the original vertex paths")
	check(int(grade.get("graded_ground_materials",0))>0 and int(grade.get("graded_surface_materials",0))>0,"street and selected facades receive the colour finish")
	var file:=FileAccess.open(_absolute_output_dir().path_join("tea-polish-audit.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"polish":polish,"grade":grade},"  "))
	file.close()
	var helper: Node=stage.get("_tea_grade")
	var bindings: Array=helper.get("_bindings")
	var saved_parameters: Array[Dictionary]=[]
	for row: Dictionary in bindings:
		var parameters: Dictionary={}
		for uniform: Dictionary in row.shader.get_shader_uniform_list():
			parameters[str(uniform.name)]=row.material.get_shader_parameter(str(uniform.name))
		saved_parameters.append(parameters)
	var was_paused:=paused
	paused=true
	await process_frame
	await RenderingServer.frame_post_draw
	var shown: Image=stage.call("texture").get_image()
	for row: Dictionary in bindings:
		row.material.shader=row.old_shader
	await process_frame
	await RenderingServer.frame_post_draw
	var original: Image=stage.call("texture").get_image()
	for index: int in range(bindings.size()):
		var row: Dictionary=bindings[index]
		row.material.shader=row.shader
		for key: String in saved_parameters[index]:
			row.material.set_shader_parameter(key,saved_parameters[index][key])
	await process_frame
	await RenderingServer.frame_post_draw
	paused=was_paused
	shown.save_png(_absolute_output_dir().path_join("tea-grade-on.png"))
	original.save_png(_absolute_output_dir().path_join("tea-grade-off.png"))
	shown.convert(Image.FORMAT_RGBA8)
	original.convert(Image.FORMAT_RGBA8)
	var a:=shown.get_data()
	var b:=original.get_data()
	var changed:=0
	for i: int in range(0,mini(a.size(),b.size()),4):
		if maxi(maxi(absi(int(a[i])-int(b[i])),absi(int(a[i+1])-int(b[i+1]))),absi(int(a[i+2])-int(b[i+2])))>=8:
			changed+=1
	var visible:=changed>shown.get_width()*shown.get_height()*0.03
	check(visible,"new street colour hierarchy is visible in the actual viewport")
	file=FileAccess.open(_absolute_output_dir().path_join("tea-grade-pixel-proof.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"changed_pixels":changed,"total_pixels":shown.get_width()*shown.get_height(),"threshold":0.03,"minimum_channel_change":8,"scope":"Real application paused; same camera/state/geometry/art; only bounded material colour shaders toggled."},"  "))
	file.close()
	return visible
