extends SceneTree
func _initialize() -> void:
	var manifest := {"version":1,"fps":30,"frame_size":[384,384],"clips":{}}
	for clip in ["thrust","cut","staff"]:
		var entries: Array = []
		for sheet in 4:
			var atlas := Image.create(384*6,384*5,false,Image.FORMAT_RGBA8)
			atlas.fill(Color(0,0,0,0))
			for cell in 30:
				var index := sheet*30+cell
				var path := "res://assets/art/animation_lab/blender_frames/%s/%04d.png" % [clip,index]
				var frame := Image.load_from_file(path)
				if frame == null or frame.get_width()!=384 or frame.get_height()!=384:
					push_error("Missing or wrong-size Blender frame: "+path);quit(1);return
				frame.convert(Image.FORMAT_RGBA8)
				var dest := Vector2i((cell%6)*384,(cell/6)*384)
				atlas.blit_rect(frame,Rect2i(0,0,384,384),dest)
				entries.append({"path":"res://assets/art/animation_lab/%s_%d.png" % [clip,sheet],"region":[dest.x,dest.y,384,384]})
			var error := atlas.save_png("res://assets/art/animation_lab/%s_%d.png" % [clip,sheet])
			if error != OK:push_error("Atlas write failed");quit(1);return
		manifest.clips[clip]=entries
	FileAccess.open("res://assets/art/animation_lab/atlas.json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t")+"\n")
	print("LAB_ATLAS: 360 actual Blender frames,12 sheets")
	quit(0)
