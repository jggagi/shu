extends "res://tests/cultivation_engine_chengdu_tea_polish_render.gd"
## Retain the playable flow and compare the imported assets at the real camera.


func _check_art_pixels() -> bool:
	if not await super._check_art_pixels():
		return false
	var walker:=app.call("ui_control","TownWalker") as Control
	var stage: Node=walker.get("_stage")
	var helper: Node=stage.get("_blender_kit")
	var audit: Dictionary=helper.call("audit")
	check((audit.get("models",[]) as Array).size()==2,"two selected Blender models stream into the original lots")
	check((audit.get("errors",["missing kit"]) as Array).is_empty(),"Blender kit loads and preserves the courtyard batch contract")
	check((audit.get("bounds_errors",["missing bounds"]) as Array).is_empty(),"all imported solid vertices remain inside the original blocked lots")
	check(int(audit.get("retained_courtyard_vertices",0))>0 and int(audit.get("replaced_tree_vertices",0))>0,"old courtyard door and roof beams survive the exact trunk replacement")
	check(int(audit.get("fade_materials",0))>0 and bool(audit.get("new_ground",true))==false,"new material instances use original fade rows without adding ground")
	var was_paused:=paused
	paused=true
	await process_frame
	await RenderingServer.frame_post_draw
	var shown: Image=stage.call("texture").get_image()
	helper.call("set_models_enabled",false)
	await process_frame
	await RenderingServer.frame_post_draw
	var previous: Image=stage.call("texture").get_image()
	helper.call("set_models_enabled",true)
	await process_frame
	await RenderingServer.frame_post_draw
	paused=was_paused
	shown.save_png(_absolute_output_dir().path_join("blender-kit-on.png"))
	previous.save_png(_absolute_output_dir().path_join("blender-kit-off.png"))
	shown.convert(Image.FORMAT_RGBA8)
	previous.convert(Image.FORMAT_RGBA8)
	var a:=shown.get_data()
	var b:=previous.get_data()
	var changed:=0
	for i: int in range(0,mini(a.size(),b.size()),4):
		if maxi(maxi(absi(int(a[i])-int(b[i])),absi(int(a[i+1])-int(b[i+1]))),absi(int(a[i+2])-int(b[i+2])))>=8:
			changed+=1
	var visible:=changed>shown.get_width()*shown.get_height()*.015
	check(visible,"authored model replacements visibly change the normal game viewport")
	var file:=FileAccess.open(_absolute_output_dir().path_join("blender-kit-audit.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"kit":audit,"changed_pixels":changed,"total_pixels":shown.get_width()*shown.get_height(),"minimum_channel_change":8,"threshold":.015,"scope":"Actual application, identical camera and state; only two model replacements toggled with exact old visibility restoration."},"  "))
	file.close()
	return visible
