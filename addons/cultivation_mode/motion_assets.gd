extends RefCounted
## Data-only atlas clips. Resource preflight is complete before numerical commitment.

func validate_definition(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		errors.append("动作定义须为对象")
		return errors
	var definition: Dictionary = value
	for key: String in ["settle_seconds", "hold_seconds"]:
		var n: Variant = definition.get(key)
		if not _finite(n) or float(n) < 0.0 or float(n) > (2.0 if key == "settle_seconds" else 5.0):
			errors.append(key + "超出允许范围")
	var idle: Dictionary = _read_clip(definition.get("idle"), false)
	if not idle.get("ok", false):
		errors.append("待机：" + str(idle.get("reason", "资源无效")))
	var clips_value: Variant = definition.get("clips")
	if not clips_value is Dictionary or clips_value.is_empty() or clips_value.size() > 64:
		errors.append("需要1–64段动作")
		return errors
	var clips: Dictionary = clips_value
	for key: Variant in clips:
		var item: Variant = clips[key]
		if not key is String or not _valid_id(str(key)) or not item is Dictionary:
			errors.append("动作标识／对象无效")
			continue
		var clip: Dictionary = _read_clip(item.get("manifest"), false)
		if not clip.get("ok", false):
			errors.append(str(key) + "：" + str(clip.get("reason", "资源无效")))
			continue
		if idle.get("ok", false) and not _matching_geometry(idle, clip):
			errors.append(str(key) + "：动作与待机锚点／格尺寸不一致")
		var phases: Variant = item.get("phases")
		if not _valid_phases(phases, int(clip.get("frame_count", 0))):
			errors.append(str(key) + "：动作阶段须从首帧开始并依次排列")
	return errors


func load_idle(pack: Dictionary, motion_id: String) -> Dictionary:
	var registry: Variant = pack.get("motions", {})
	if not registry is Dictionary or not registry.get(motion_id) is Dictionary:
		return _failure("未登记动作资源：" + motion_id)
	var definition: Dictionary = registry[motion_id]
	var issues: Array[String] = validate_definition(definition)
	if not issues.is_empty():
		return _failure("；".join(issues))
	var idle: Dictionary = _read_clip(definition.get("idle"), true)
	if not idle.get("ok", false):
		return _failure(str(idle.get("reason", "待机无法载入")))
	var idle_frames: Array = idle.get("frames", [])
	var first_frame: Texture2D = idle_frames[0] as Texture2D
	var first_image: Image = first_frame.get_image()
	if first_image == null or first_image.is_empty() or first_image.get_used_rect().size.y <= 0:
		return _failure("待机首帧为空")
	var assets: Dictionary = {
		"motion_id": motion_id, "clip_id": "", "idle_frames": idle_frames,
		"action_frames": [], "idle_fps": float(idle.fps), "action_fps": float(idle.fps),
		"anchor": idle.anchor, "cell_size": idle.cell_size,
		"visible_height": float(first_image.get_used_rect().size.y), "phases": [],
		"settle_seconds": float(definition.settle_seconds), "hold_seconds": float(definition.hold_seconds),
		"idle_atlas_paths": idle.atlas_paths, "action_atlas_paths": []
	}
	return {"ok": true, "reason": "", "assets": assets}


func prepare(pack: Dictionary, motion_id: String, clip_id: String) -> Dictionary:
	var loaded: Dictionary = load_idle(pack, motion_id)
	if not loaded.get("ok", false):
		return loaded
	var definition: Dictionary = pack.motions[motion_id]
	var clips: Dictionary = definition.clips
	if not clips.get(clip_id) is Dictionary:
		return _failure("未登记动作片段：" + clip_id)
	var selected: Dictionary = clips[clip_id]
	var action: Dictionary = _read_clip(selected.get("manifest"), true)
	if not action.get("ok", false):
		return _failure(str(action.get("reason", "动作无法载入")))
	var assets: Dictionary = loaded.assets
	if assets.anchor.distance_to(action.anchor) > 0.0001 or assets.cell_size != action.cell_size:
		return _failure("动作与待机锚点／格尺寸不一致")
	assets["clip_id"] = clip_id
	assets["action_frames"] = action.frames
	assets["action_fps"] = float(action.fps)
	assets["action_atlas_paths"] = action.atlas_paths
	assets["phases"] = selected.phases.duplicate(true)
	return {"ok": true, "reason": "", "assets": assets}


func _read_clip(path_value: Variant, with_textures: bool) -> Dictionary:
	if not path_value is String or not path_value.begins_with("res://assets/") or ".." in path_value or not path_value.ends_with(".json"):
		return _failure("动作清单须为assets内JSON")
	var path: String = path_value
	if not FileAccess.file_exists(path):
		return _failure("缺少动作清单：" + path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 2097152:
		return _failure("动作清单无法读取或过大：" + path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _failure("动作清单不是JSON对象：" + path)
	var data: Dictionary = parsed
	if not _integer(data.get("version")) or int(data.get("version", 0)) != 1:
		return _failure("动作清单版本无效：" + path)
	var fps_value: Variant = data.get("fps")
	var count_value: Variant = data.get("frame_count")
	if not _finite(fps_value) or float(fps_value) < 1 or float(fps_value) > 120 or not _integer(count_value) or int(count_value) < 1 or int(count_value) > 7200:
		return _failure("动作帧率／数量无效：" + path)
	if float(count_value) / float(fps_value) > 120.0:
		return _failure("单段动作超过120秒：" + path)
	var cell: Variant = data.get("cell_size")
	var anchor: Variant = data.get("anchor_resized_px")
	if not cell is Array or cell.size() != 2 or not _integer(cell[0]) or not _integer(cell[1]) or int(cell[0]) < 1 or int(cell[1]) < 1 or int(cell[0]) > 8192 or int(cell[1]) > 8192:
		return _failure("动作格尺寸无效：" + path)
	if not anchor is Array or anchor.size() != 2 or not _finite(anchor[0]) or not _finite(anchor[1]) or float(anchor[0]) < 0 or float(anchor[1]) < 0 or float(anchor[0]) > float(cell[0]) or float(anchor[1]) > float(cell[1]):
		return _failure("动作接地锚点无效：" + path)
	var entries: Variant = data.get("frames")
	if not entries is Array or entries.size() != int(count_value):
		return _failure("动作帧记录数量不匹配：" + path)
	var declared_pages: Variant = data.get("atlas_pages")
	if not declared_pages is Array or declared_pages.is_empty() or declared_pages.size() > 512:
		return _failure("动作图集页列表无效：" + path)
	var cache: Dictionary = {}
	var pages: Array[String] = []
	var frames: Array[Texture2D] = []
	for value: Variant in entries:
		if not value is Dictionary:
			return _failure("动作帧记录无效：" + path)
		var entry: Dictionary = value
		var atlas_value: Variant = entry.get("path")
		if not atlas_value is String or not atlas_value.begins_with("res://assets/") or ".." in atlas_value or not atlas_value.ends_with(".png"):
			return _failure("动作图集路径无效：" + path)
		var atlas_path: String = atlas_value
		if not ResourceLoader.exists(atlas_path, "Texture2D"):
			return _failure("缺少动作图集：" + atlas_path)
		if not pages.has(atlas_path):
			pages.append(atlas_path)
		var region_value: Variant = entry.get("region")
		if not region_value is Array or region_value.size() != 4:
			return _failure("动作图集区域无效：" + path)
		for n: Variant in region_value:
			if not _integer(n) or float(n) < 0 or float(n) > 65536:
				return _failure("动作图集区域须为有限整数：" + path)
		if int(region_value[2]) != int(cell[0]) or int(region_value[3]) != int(cell[1]):
			return _failure("动作区域与格尺寸不匹配：" + path)
		if with_textures:
			var atlas: Texture2D = cache.get(atlas_path) as Texture2D
			if atlas == null:
				atlas = ResourceLoader.load(atlas_path, "Texture2D") as Texture2D
				if atlas == null:
					return _failure("动作图集无法载入：" + atlas_path)
				cache[atlas_path] = atlas
			var region := Rect2(float(region_value[0]), float(region_value[1]), float(region_value[2]), float(region_value[3]))
			if not Rect2(Vector2.ZERO, atlas.get_size()).encloses(region):
				return _failure("动作区域超出图集：" + atlas_path)
			var texture := AtlasTexture.new()
			texture.atlas = atlas
			texture.region = region
			texture.filter_clip = true
			frames.append(texture)
	if declared_pages.size() != pages.size():
		return _failure("动作图集页数不匹配：" + path)
	for page: Variant in declared_pages:
		if not page is String or declared_pages.count(page) != 1 or not pages.has(page):
			return _failure("动作图集页声明不匹配：" + path)
	return {"ok": true, "reason": "", "frames": frames, "atlas_paths": pages,
		"fps": float(fps_value), "frame_count": int(count_value),
		"anchor": Vector2(float(anchor[0]), float(anchor[1])), "cell_size": Vector2i(int(cell[0]), int(cell[1]))}


func _valid_phases(value: Variant, frame_count: int) -> bool:
	if not value is Array or value.is_empty():
		return false
	var prior: int = 0
	for item: Variant in value:
		if not item is Dictionary or not _integer(item.get("start_frame")) or not item.get("label") is String or item.label.strip_edges().is_empty():
			return false
		var start: int = int(item.start_frame)
		if start <= prior or start > frame_count or (prior == 0 and start != 1):
			return false
		prior = start
	return true


func _matching_geometry(first: Dictionary, second: Dictionary) -> bool:
	return first.cell_size == second.cell_size and first.anchor.distance_to(second.anchor) <= 0.0001


func _valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for c: String in value:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true


func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _integer(value: Variant) -> bool:
	return _finite(value) and float(value) == floor(float(value))


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "assets": {}}
