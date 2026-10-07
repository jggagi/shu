extends SceneTree

const ERROR_ARGUMENTS := "ERROR: expected --recipe <repo-relative-json> --pose <id>"
const ERROR_RECIPE := "ERROR: recipe unavailable or invalid"
const ERROR_POSE := "ERROR: pose data missing or invalid"
const ERROR_IMAGES := "ERROR: source images unavailable or mismatched"
const ERROR_OUTPUT := "ERROR: output could not be written"


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var arguments := _parse_arguments(OS.get_cmdline_user_args())
	if arguments.is_empty():
		push_error(ERROR_ARGUMENTS)
		return 1

	var recipe_path := _repo_path(str(arguments.recipe))
	if recipe_path.is_empty():
		push_error(ERROR_RECIPE)
		return 1
	var recipe_file := FileAccess.open(recipe_path, FileAccess.READ)
	if recipe_file == null:
		push_error(ERROR_RECIPE)
		return 1
	var recipe_value: Variant = JSON.parse_string(recipe_file.get_as_text())
	if typeof(recipe_value) != TYPE_DICTIONARY:
		push_error(ERROR_RECIPE)
		return 1
	var poses: Variant = recipe_value.get("poses")
	if typeof(poses) != TYPE_DICTIONARY or not poses.has(arguments.pose):
		push_error(ERROR_POSE)
		return 1

	var pose: Variant = poses[arguments.pose]
	if typeof(pose) != TYPE_DICTIONARY:
		push_error(ERROR_POSE)
		return 1
	var base_value: Variant = pose.get("base")
	var candidate_value: Variant = pose.get("candidate")
	var output_value: Variant = pose.get("output")
	if typeof(base_value) != TYPE_STRING or typeof(candidate_value) != TYPE_STRING or typeof(output_value) != TYPE_STRING:
		push_error(ERROR_POSE)
		return 1
	var base_path := _repo_path(base_value)
	var candidate_path := _repo_path(candidate_value)
	var output_path := _repo_path(output_value)
	var translation_value: Variant = pose.get("translation")
	var feather_value: Variant = pose.get("feather")
	var regions_value: Variant = pose.get("regions")
	if base_path.is_empty() or candidate_path.is_empty() or output_path.is_empty():
		push_error(ERROR_POSE)
		return 1
	if output_path == base_path or output_path == candidate_path:
		push_error(ERROR_POSE)
		return 1
	if not _is_number_pair(translation_value) or not _is_integral_number(translation_value[0]) or not _is_integral_number(translation_value[1]):
		push_error(ERROR_POSE)
		return 1
	if not _is_finite_number(feather_value) or float(feather_value) < 0.0:
		push_error(ERROR_POSE)
		return 1
	var regions := _parse_regions(regions_value)
	if regions.is_empty():
		push_error(ERROR_POSE)
		return 1

	var base_image: Image = Image.load_from_file(base_path)
	var candidate_image: Image = Image.load_from_file(candidate_path)
	if base_image == null or candidate_image == null or base_image.is_empty() or candidate_image.is_empty():
		push_error(ERROR_IMAGES)
		return 1
	if base_image.get_size() != candidate_image.get_size():
		push_error(ERROR_IMAGES)
		return 1

	var output_image: Image = base_image.duplicate()
	var width := base_image.get_width()
	var height := base_image.get_height()
	var dx := int(translation_value[0])
	var dy := int(translation_value[1])
	var coverage := _build_union_weights(width, height, regions, float(feather_value))
	var changed_pixels := _blend_candidate(
		output_image,
		base_image,
		candidate_image,
		coverage["weights"],
		coverage["bounds"],
		dx,
		dy
	)

	var output_directory := output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK and not DirAccess.dir_exists_absolute(output_directory):
			push_error(ERROR_OUTPUT)
			return 1
	if output_image.save_png(output_path) != OK:
		push_error(ERROR_OUTPUT)
		return 1

	print("POSE ", arguments.pose, " size=", width, "x", height, " changed_pixels=", changed_pixels)
	return 0


func _parse_arguments(user_args: PackedStringArray) -> Dictionary:
	if user_args.size() != 4:
		return {}
	var values: Dictionary = {}
	var index := 0
	while index < user_args.size():
		var option: String = user_args[index]
		if option != "--recipe" and option != "--pose":
			return {}
		if values.has(option):
			return {}
		values[option] = user_args[index + 1]
		index += 2
	if not values.has("--recipe") or not values.has("--pose"):
		return {}
	if not _is_safe_pose_id(str(values["--pose"])):
		return {}
	return {"recipe": values["--recipe"], "pose": values["--pose"]}


func _is_safe_pose_id(value: String) -> bool:
	if value.is_empty():
		return false
	var pattern := RegEx.new()
	if pattern.compile("^[A-Za-z0-9_-]+$") != OK:
		return false
	return pattern.search(value) != null


func _repo_path(relative_path: String) -> String:
	if relative_path.is_empty():
		return ""
	var normalized := relative_path.replace("\\", "/")
	if normalized.begins_with("/") or normalized.contains(":") or normalized.contains("//"):
		return ""
	for component: String in normalized.split("/", false):
		if component == "." or component == "..":
			return ""
	return ProjectSettings.globalize_path("res://" + normalized)


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_finite_number(value: Variant) -> bool:
	return _is_number(value) and is_finite(float(value))


func _is_integral_number(value: Variant) -> bool:
	if not _is_finite_number(value):
		return false
	return floorf(float(value)) == float(value)


func _is_number_pair(value: Variant) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() == 2 and _is_finite_number(value[0]) and _is_finite_number(value[1])


func _parse_regions(value: Variant) -> Array:
	var parsed: Array = []
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		return parsed
	for raw_polygon: Variant in value:
		if typeof(raw_polygon) != TYPE_ARRAY or raw_polygon.size() < 3:
			return []
		var polygon := PackedVector2Array()
		for raw_point: Variant in raw_polygon:
			if typeof(raw_point) != TYPE_ARRAY or raw_point.size() != 2:
				return []
			if not _is_finite_number(raw_point[0]) or not _is_finite_number(raw_point[1]):
				return []
			polygon.append(Vector2(float(raw_point[0]), float(raw_point[1])))
		parsed.append(polygon)
	return parsed


func _build_union_weights(width: int, height: int, regions: Array, feather: float) -> Dictionary:
	var weights := PackedFloat32Array()
	weights.resize(width * height)
	var union_min_x := width
	var union_max_x := -1
	var union_min_y := height
	var union_max_y := -1
	for region: Variant in regions:
		var polygon: PackedVector2Array = region
		var min_x := INF
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		for point: Vector2 in polygon:
			min_x = minf(min_x, point.x)
			max_x = maxf(max_x, point.x)
			min_y = minf(min_y, point.y)
			max_y = maxf(max_y, point.y)
		var start_x := maxi(0, floori(min_x - feather))
		var end_x := mini(width - 1, ceili(max_x + feather))
		var start_y := maxi(0, floori(min_y - feather))
		var end_y := mini(height - 1, ceili(max_y + feather))
		if start_x > end_x or start_y > end_y:
			continue
		union_min_x = mini(union_min_x, start_x)
		union_max_x = maxi(union_max_x, end_x)
		union_min_y = mini(union_min_y, start_y)
		union_max_y = maxi(union_max_y, end_y)
		for y in range(start_y, end_y + 1):
			for x in range(start_x, end_x + 1):
				var pixel_center := Vector2(x + 0.5, y + 0.5)
				if not Geometry2D.is_point_in_polygon(pixel_center, polygon):
					continue
				var edge_distance := INF
				for edge_index in range(polygon.size()):
					var edge_start: Vector2 = polygon[edge_index]
					var edge_end: Vector2 = polygon[(edge_index + 1) % polygon.size()]
					var closest := Geometry2D.get_closest_point_to_segment(pixel_center, edge_start, edge_end)
					edge_distance = minf(edge_distance, pixel_center.distance_to(closest))
				# Geometry2D accepts points just outside an edge within its tolerance.
				# Keep this subpixel fringe unchanged rather than quantizing tiny blends.
				if edge_distance <= 0.01:
					continue
				var weight := 1.0 if feather == 0.0 else _smoothstep01(edge_distance / feather)
				var weight_index := y * width + x
				weights[weight_index] = maxf(weights[weight_index], weight)
	var bounds := Rect2i(0, 0, 0, 0)
	if union_max_x >= union_min_x and union_max_y >= union_min_y:
		bounds = Rect2i(union_min_x, union_min_y, union_max_x - union_min_x + 1, union_max_y - union_min_y + 1)
	return {"weights": weights, "bounds": bounds}


func _blend_candidate(output_image: Image, base_image: Image, candidate_image: Image, weights: PackedFloat32Array, bounds: Rect2i, dx: int, dy: int) -> int:
	var width := base_image.get_width()
	var height := base_image.get_height()
	var changed_pixels := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var weight := weights[y * width + x]
			if weight <= 0.0:
				continue
			var candidate_x := x - dx
			var candidate_y := y - dy
			if candidate_x < 0 or candidate_x >= width or candidate_y < 0 or candidate_y >= height:
				continue
			var original := base_image.get_pixel(x, y)
			var candidate := candidate_image.get_pixel(candidate_x, candidate_y)
			var blended := Color(
				lerpf(original.r, candidate.r, weight),
				lerpf(original.g, candidate.g, weight),
				lerpf(original.b, candidate.b, weight),
				original.a
			)
			output_image.set_pixel(x, y, blended)
			var saved := output_image.get_pixel(x, y)
			if saved.r != original.r or saved.g != original.g or saved.b != original.b or saved.a != original.a:
				changed_pixels += 1
	return changed_pixels


func _smoothstep01(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)
