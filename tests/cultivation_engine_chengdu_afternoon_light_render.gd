extends "res://tests/cultivation_engine_chengdu_blender_kit_render.gd"
## Original playable workflow plus a same-camera shadow diagnostic.


func _check_art_pixels() -> bool:
	var walker:=app.call("ui_control","TownWalker") as Control
	var stage: Node=walker.get("_stage")
	var helper: Node=stage.get("_afternoon_light")
	# Parent diagnostics temporarily swap their older shaders. Let each helper
	# own its own comparison, then restore this final lighting layer last.
	helper.call("set_enabled",false)
	var previous_ok: bool=await super._check_art_pixels()
	helper.call("set_enabled",true)
	if not previous_ok:
		return false
	var audit: Dictionary=helper.call("audit")
	check((audit.get("errors",["missing lighting"]) as Array).is_empty(),"afternoon receiver shaders bind without errors")
	check(int(audit.counts.art_ground)==7 and int(audit.counts.gate_ground)==8,"both existing painted ground passes receive the same sun")
	check(int(audit.counts.model)>0 and bool(audit.all_vertices_unchanged),"selected models share warm light while every vertex path remains unchanged")
	check(not bool(audit.new_floor) and int(audit.new_lights)==0 and int(audit.new_material_samplers)==0,"lighting adds no floor, light or material texture sampler")
	var was_paused:=paused
	paused=true
	await process_frame
	await RenderingServer.frame_post_draw
	var shown: Image=stage.call("texture").get_image()
	helper.call("set_receiver_shadows_enabled",false)
	await process_frame
	await RenderingServer.frame_post_draw
	var without_shadow: Image=stage.call("texture").get_image()
	helper.call("set_receiver_shadows_enabled",true)
	await process_frame
	await RenderingServer.frame_post_draw
	paused=was_paused
	shown.save_png(_absolute_output_dir().path_join("afternoon-on.png"))
	without_shadow.save_png(_absolute_output_dir().path_join("afternoon-no-shadow.png"))
	var file:=FileAccess.open(_absolute_output_dir().path_join("afternoon-audit.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"lighting":audit,"scope":"Actual application, same paused camera/state. Only painted ground ATTENUATION bypassed/restored; original sun shadow flag and GLES additive pass remain unchanged. Ground pixels separately reviewed in shopfront probe."},"  "))
	file.close()
	return true
