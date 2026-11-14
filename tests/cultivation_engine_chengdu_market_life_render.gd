extends "res://tests/cultivation_engine_chengdu_art_street_render.gd"
## Retain the complete input flow; additionally observe the market in the real viewport.


func _check_art_pixels() -> bool:
	if not await super._check_art_pixels():
		return false
	var walker := app.call("ui_control","TownWalker") as Control
	var stage: Node = walker.get("_stage")
	var audit: Dictionary = stage.call("audit").get("market_life",{})
	var file := FileAccess.open(_absolute_output_dir().path_join("market-life-audit.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(audit,"  "))
	file.close()
	check(int(audit.get("stall_count",0))==6,"six different street stalls are installed")
	check(int(audit.get("vendor_count",0))==6 and int(audit.get("sign_count",0))==6,"each stall has a merchant and a real Chinese sign")
	check(int(audit.get("plant_count",0))>=12,"planters and low greenery populate the street edges")
	check((audit.get("errors",["missing audit"]) as Array).is_empty(),"market signs and assets load without errors")
	check((audit.get("bounds_errors",["missing bounds audit"]) as Array).is_empty(),"market solids stay in their lots and nonblocking merchants stay in their authored frontage")
	var containers: Array[Node3D] = []
	for node: Node in stage.find_children("*","Node3D",true,false):
		if node.has_meta("market_life_root"):
			containers.append(node)
	var was_paused := paused
	paused=true
	await process_frame
	await RenderingServer.frame_post_draw
	var shown: Image = stage.call("texture").get_image()
	for node: Node3D in containers:
		node.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden: Image = stage.call("texture").get_image()
	for node: Node3D in containers:
		node.show()
	await process_frame
	await RenderingServer.frame_post_draw
	paused=was_paused
	shown.save_png(_absolute_output_dir().path_join("market-life-on.png"))
	hidden.save_png(_absolute_output_dir().path_join("market-life-off.png"))
	shown.convert(Image.FORMAT_RGBA8)
	hidden.convert(Image.FORMAT_RGBA8)
	var a:=shown.get_data()
	var b:=hidden.get_data()
	var changed:=0
	for i: int in range(0,mini(a.size(),b.size()),4):
		if maxi(maxi(absi(int(a[i])-int(b[i])),absi(int(a[i+1])-int(b[i+1]))),absi(int(a[i+2])-int(b[i+2])))>=15:
			changed+=1
	var visible:=changed>shown.get_width()*shown.get_height()*0.003
	check(visible,"market additions visibly contribute at the normal follow-camera distance")
	file=FileAccess.open(_absolute_output_dir().path_join("market-life-pixel-proof.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"changed_pixels":changed,"total_pixels":shown.get_width()*shown.get_height(),"threshold":0.003,"scope":"Real application paused at the same camera and state; only market containers hidden."},"  "))
	file.close()
	return visible
