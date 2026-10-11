extends SceneTree
# Package existing Blender RGBA frames; no image synthesis or pose interpolation.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -- <frame-directory> <asset-directory>");quit(1);return
	var source: String = args[0]
	var output: String = args[1]
	var asset_id: String = args[2] if args.size() > 2 else "sword_jiang"
	if asset_id not in ["sword_jiang", "sword_jiang_legacy"]:
		push_error("Unknown Jiang study variant");quit(1);return
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/" + asset_id + "/study.json"))
	var count: int = int(metadata.frame_count)
	var columns := 5
	var rows := 5
	var cell := 384
	var entries: Array = []
	var min_margin := cell
	DirAccess.make_dir_recursive_absolute(output)
	for sheet in int(ceil(float(count) / float(columns * rows))):
		var atlas := Image.create(cell*columns, cell*rows, false, Image.FORMAT_RGBA8)
		atlas.fill(Color.TRANSPARENT)
		var filename := "atlas-%03d.png" % sheet
		for local_index in columns*rows:
			var index := sheet*columns*rows+local_index
			if index >= count:break
			var frame := Image.load_from_file(source.path_join("frame-%04d.png" % index))
			if frame == null or frame.get_size() != Vector2i(cell, cell):
				push_error("Missing or wrong-size frame %d" % index);quit(1);return
			frame.convert(Image.FORMAT_RGBA8)
			var used := frame.get_used_rect()
			if used.size.x <= 0 or used.size.y <= 0:
				push_error("Empty rendered frame %d" % index);quit(1);return
			min_margin = mini(min_margin, mini(mini(used.position.x,used.position.y), mini(cell-used.end.x,cell-used.end.y)))
			if min_margin < 3:
				push_error("Rendered actor/weapon is clipped");quit(1);return
			var pos := Vector2i((local_index%columns)*cell,int(local_index/columns)*cell)
			atlas.blit_rect(frame, Rect2i(0,0,cell,cell), pos)
			entries.append({"path":"res://assets/art/"+asset_id+"/"+filename,"region":[pos.x,pos.y,cell,cell]})
		if atlas.save_png(output.path_join(filename)) != OK:
			push_error("Cannot write atlas");quit(1);return
	var manifest := {"schema_version":1,"fps":60,"width":cell,"height":cell,
		"frame_count":count,"duration":metadata.duration,"frames":entries,"minimum_frame_margin_px":min_margin,
		"atlas_count":int(ceil(float(count)/25.0)),"decoded_rgba_bytes":int(ceil(float(count)/25.0))*1920*1920*4}
	var file := FileAccess.open(output.path_join("atlas.json"), FileAccess.WRITE)
	if file == null:push_error("Cannot write atlas manifest");quit(1);return
	file.store_string(JSON.stringify(manifest,"  ")+"\n")
	print("JIANG_ATLAS: %d frames, %d sheets, minimum margin %d px" % [count,manifest.atlas_count,min_margin])
	quit(0)
