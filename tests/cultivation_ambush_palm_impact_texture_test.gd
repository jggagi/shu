extends SceneTree
## Export exact imported pixels for a separate raw RGBA/premul comparison.
func _initialize() -> void:
	var output := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-rgba="):
			output = arg.trim_prefix("--output-rgba=")
	var texture := load("res://assets/art/mountain_ambush/palm_lab/v2/effekseer/palm-gust-v2-atlas.png") as Texture2D
	if texture == null or output.is_empty():
		push_error("Atlas or explicit output missing")
		quit(1)
		return
	var image := texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	if image.get_size() != Vector2i(2048, 1024) or image.get_data().size() != 8388608:
		push_error("Imported atlas dimensions or pixels differ")
		quit(1)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_buffer(image.get_data())
	print("PALM IMPORT: actual2048x1024 RGBA8 pixels saved")
	quit(0)
