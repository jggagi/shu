extends SceneTree
# Compare imported Godot skeleton positions against the independent ASF/AMC solution.
var failures: Array[String] = []
var poses := 0
var maximum := 0.0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var asset_id := "sword_jiang_legacy" if OS.get_cmdline_user_args().has("--legacy") else "sword_jiang"
	var packed := load("res://scenes/demos/" + asset_id + "_comparison.tscn") as PackedScene
	if packed == null:push_error("Missing comparison");quit(1);return
	var lab = packed.instantiate()
	root.add_child(lab)
	await process_frame
	lab.playing = false
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/" + asset_id + "/pose_reference.json"))
	var samples: Array = reference.samples
	if lab.live_skeleton == null:push_error("Missing actual imported skeleton");quit(1);return
	if lab.live_skeleton.get_bone_count() != 31:failures.append("Expected root plus 30 real bones")
	var indices: Array[int] = []
	for index in range(samples.size()):indices.append(index)
	for index in indices:
		lab.seek_motion(float(index)/60.0)
		await process_frame
		var source: Dictionary = samples[index].bones
		for name: String in source:
			var bone: int = lab.live_skeleton.find_bone(name)
			if bone < 0:failures.append("Missing bone "+name);continue
			var point: Array = source[name].head
			var expected := Vector3(point[0],point[2],-point[1])
			var transform: Transform3D = lab.live_skeleton.global_transform * lab.live_skeleton.get_bone_global_pose(bone)
			var error := transform.origin.distance_to(expected)
			maximum = maxf(maximum,error)
			if error > 0.001:failures.append("%s frame %d differs by %.6f m" % [name,index,error])
			if not transform.basis.is_finite():failures.append("Nonfinite bone basis")
			if absf(transform.basis.determinant()-1.0)>0.001:failures.append("Unexpected bone scale "+name)
			poses+=1
	for message in failures.slice(0,12):push_error(message)
	print("JIANG_IMPORT: %d bone poses across all 517 frames, 31 bones, maximum endpoint error %.9f m, %d failures" % [poses,maximum,failures.size()])
	quit(0 if failures.is_empty() else 1)
