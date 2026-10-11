extends SceneTree
var scene: Control
var output := ""
var report: Dictionary = {"captures": [], "checks": [], "failures": 0}
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://.local/qa/image-motion-pilot/render")
	DirAccess.make_dir_recursive_absolute(output)
	root.mode = Window.MODE_WINDOWED
	report.renderer = {"display":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"method":ProjectSettings.get_setting("rendering/renderer/rendering_method")}
	check(DisplayServer.get_name() != "headless", "real display server")
	scene = load("res://scenes/demos/sword_image_back_mountain.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	scene.set_dynamic(false)
	check(scene.matte_enabled and scene.clip.frames == scene.clean_frames, "render starts with the clean matte selected")
	check(scene.matte_button.text == "干净边缘" and not scene.matte_button.disabled, "render matte control starts enabled")
	for size in [Vector2i(1152, 720), Vector2i(960, 600)]:
		root.size = size
		await process_frame
		await process_frame
		for index in [0, 15, 28, 40, 60]:
			scene.clip.seek(float(index) / 25.0)
			scene._refresh_pilot_ui()
			var image := await capture("%dx%d-frame-%02d.png" % [size.x,size.y,index])
			check(image.get_size() == size, "correct actual rendered size")
			var used: Rect2i = scene.clip.sprite.texture.get_image().get_used_rect()
			var bounds: Rect2 = scene.clip.sprite.get_global_transform() * Rect2(used)
			check(scene._art_root.get_global_rect().encloses(bounds), "stage adds no clipping at frame %d" % index)
		var a := await capture("%dx%d-freeze-a.png" % [size.x,size.y])
		await create_timer(0.2).timeout
		var b := await capture("%dx%d-freeze-b.png" % [size.x,size.y])
		check(a.get_data() == b.get_data(), "paused full-frame identical")
		for index in [0, 28, 60]:
			await _capture_scene_blend_pair(size, index, "daylight")
		for index in [0, 28]:
			await _capture_paper_pair(size, index)
		for index in [28, 40, 50]:
			await _capture_matte_pair(size, index)
	# Source-edge frames remain intact; daylight/weather grading reaches the actor.
	root.size = Vector2i(1152,720)
	for weather in ["clear","light_rain"]:
		scene.environment_presenter.set_time_profile("you",false)
		scene.time_button.text = "酉时"
		scene.environment_presenter.set_weather(weather,false)
		scene.weather_button.text = "晴" if weather == "clear" else "小雨"
		scene._apply_environment()
		await capture("1152x720-you-%s.png" % weather)
		check(scene.clip.modulate == scene._displayed_tint, "actor follows scene grading")
	await _capture_scene_blend_pair(Vector2i(1152, 720), 28, "you-light_rain")
	var f := FileAccess.open(output.path_join("render-report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"  ")+"\n")
	print("SWORD_IMAGE_PILOT_RENDER: %d checks, %d captures, %d failures" % [report.checks.size(),report.captures.size(),report.failures])
	quit(0 if report.failures == 0 else 1)
func _capture_scene_blend_pair(size: Vector2i, frame: int, environment_name: String) -> void:
	scene.clip.seek(float(frame) / scene.clip.fps)
	scene._refresh_pilot_ui()
	var environment_before: PackedByteArray = _script_snapshot(scene.environment_presenter)
	var presentation_before: float = scene.presentation_time
	var matte_enabled_before: bool = scene.matte_enabled
	var matte_frames_before: Array = scene.clip.frames.duplicate()
	var matte_texture_before: Texture2D = scene.clip.sprite.texture
	scene.set_scene_blending(false)
	var off := await capture("%dx%d-%s-frame-%02d-blend-off.png" % [size.x, size.y, environment_name, frame])
	check(scene.clip.frame_index == frame, "blend-off capture keeps requested frame %d" % frame)
	scene.set_scene_blending(true)
	var on := await capture("%dx%d-%s-frame-%02d-blend-on.png" % [size.x, size.y, environment_name, frame])
	check(scene.clip.frame_index == frame and scene.clip.paused, "blend-on capture keeps the same paused frame %d" % frame)
	check(_script_snapshot(scene.environment_presenter) == environment_before and is_equal_approx(scene.presentation_time, presentation_before), "scene-blend pair freezes environment and presentation time")
	check(scene.matte_enabled == matte_enabled_before and scene.clip.frames == matte_frames_before and scene.clip.sprite.texture == matte_texture_before, "scene-blend pair leaves the selected matte unchanged")
	var sprite_bounds: Rect2 = scene.clip.sprite.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, scene.clip.sprite.texture.get_size())
	var actor_rect := _to_image_rect(sprite_bounds.grow(2.0), off)
	var contact_bounds: Rect2 = scene.contact_shadow.get_global_transform_with_canvas() * Rect2(-Vector2(scene.contact_shadow.texture.get_size()) * 0.5, Vector2(scene.contact_shadow.texture.get_size()))
	var legacy_bounds := _polygon_bounds(scene.legacy_contact_shadow)
	var shadow_rect := _to_image_rect(contact_bounds.merge(legacy_bounds).grow(2.0), off)
	var actor_and_shadow := actor_rect.merge(shadow_rect)
	var button_bounds: Rect2 = scene.blend_button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, scene.blend_button.size)
	var button_rect := _to_image_rect(button_bounds.grow(4.0), off)
	var paper_button_bounds: Rect2 = scene.paper_button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, scene.paper_button.size)
	var paper_button_rect := _to_image_rect(paper_button_bounds.grow(4.0), off)
	report.get_or_add("comparison_regions", []).append({"frame":frame,"window":[size.x,size.y],"logical_viewport":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"actor":[actor_rect.position.x,actor_rect.position.y,actor_rect.size.x,actor_rect.size.y],"shadow":[shadow_rect.position.x,shadow_rect.position.y,shadow_rect.size.x,shadow_rect.size.y]})
	check(_outside_regions_match(off, on, [actor_and_shadow, button_rect, paper_button_rect]), "blend pair changes only actor, contact shadow, and toggle-button UI")
	check(off.get_region(actor_rect).get_data() != on.get_region(actor_rect).get_data(), "blended actor visibly changes at frame %d" % frame)
	var used: Rect2 = scene.clip.sprite.get_global_transform() * Rect2(scene.clip.sprite.texture.get_image().get_used_rect())
	check(scene._art_root.get_global_rect().encloses(used), "scene blending adds no clipping at frame %d" % frame)

func _capture_paper_pair(size: Vector2i, frame: int) -> void:
	scene.set_scene_blending(true)
	scene.set_paper_texture(true)
	scene.clip.seek(float(frame) / scene.clip.fps)
	scene._refresh_pilot_ui()
	var environment_before: PackedByteArray = _script_snapshot(scene.environment_presenter)
	var presentation_before: float = scene.presentation_time
	var matte_enabled_before: bool = scene.matte_enabled
	var matte_frames_before: Array = scene.clip.frames.duplicate()
	var matte_texture_before: Texture2D = scene.clip.sprite.texture
	var actor_transform_before: Transform2D = scene.clip.sprite.get_global_transform_with_canvas()
	var shadow_transform_before: Transform2D = scene.contact_shadow.get_global_transform_with_canvas()
	var shadow_texture_before: Texture2D = scene.contact_shadow.texture
	var shadow_visible_before: bool = scene.contact_shadow.visible
	scene.set_paper_texture(false)
	var off := await capture("%dx%d-paper-frame-%02d-off.png" % [size.x, size.y, frame])
	check(not scene.paper_enabled and is_equal_approx(float(scene.blend_material.get_shader_parameter("paper_strength")), 0.0), "paper-off capture uses zero paper strength")
	scene.set_paper_texture(true)
	var on := await capture("%dx%d-paper-frame-%02d-on.png" % [size.x, size.y, frame])
	check(scene.paper_enabled and is_equal_approx(float(scene.blend_material.get_shader_parameter("paper_strength")), 0.85), "paper-on capture uses light paper strength")
	check(scene.clip.frame_index == frame and scene.clip.paused, "paper pair keeps the same paused frame %d" % frame)
	check(_script_snapshot(scene.environment_presenter) == environment_before and scene.presentation_time == presentation_before, "paper pair freezes environment and presentation time")
	check(scene.matte_enabled == matte_enabled_before and scene.clip.frames == matte_frames_before and scene.clip.sprite.texture == matte_texture_before, "paper pair leaves the selected matte unchanged")
	check(scene.clip.sprite.get_global_transform_with_canvas() == actor_transform_before and scene.contact_shadow.get_global_transform_with_canvas() == shadow_transform_before and scene.contact_shadow.texture == shadow_texture_before and scene.contact_shadow.visible == shadow_visible_before, "paper toggle preserves actor and footprint geometry")
	var sprite_bounds: Rect2 = actor_transform_before * Rect2(Vector2.ZERO, scene.clip.sprite.texture.get_size())
	var actor_rect := _to_image_rect(sprite_bounds.grow(2.0), off)
	var button_bounds: Rect2 = scene.paper_button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, scene.paper_button.size)
	var button_rect := _to_image_rect(button_bounds.grow(4.0), off)
	check(_outside_regions_match(off, on, [actor_rect, button_rect]), "paper pair leaves all pixels outside actor and paper-button regions unchanged")
	check(off.get_region(actor_rect).get_data() != on.get_region(actor_rect).get_data(), "light paper changes actor pigment at frame %d" % frame)


func _capture_matte_pair(size: Vector2i, frame: int) -> void:
	scene.set_scene_blending(true)
	scene.set_matte_cleanup(true)
	scene.clip.seek(float(frame) / scene.clip.fps)
	scene._refresh_pilot_ui()
	var clip = scene.clip
	var seconds_before: float = clip.seconds
	var frame_before: int = clip.frame_index
	var paused_before: bool = clip.paused
	var speed_before: float = clip.speed
	var fps_before: float = clip.fps
	var duration_before: float = clip.duration
	var clip_position_before: Vector2 = clip.position
	var clip_scale_before: Vector2 = clip.scale
	var sprite_position_before: Vector2 = clip.sprite.position
	var sprite_scale_before: Vector2 = clip.sprite.scale
	var sprite_rect_before: Rect2 = clip.sprite.get_rect()
	var sprite_size_before: Vector2 = clip.sprite.texture.get_size()
	var actor_transform_before: Transform2D = clip.sprite.get_global_transform_with_canvas()
	var anchors_before: PackedByteArray = var_to_bytes(clip.anchors)
	var data_before: PackedByteArray = var_to_bytes(clip.data)
	var environment_before: PackedByteArray = _script_snapshot(scene.environment_presenter)
	var presentation_before: float = scene.presentation_time
	var state_before: PackedByteArray = _script_snapshot(scene.state)
	var dynamic_before: bool = scene.dynamic_enabled
	var tint_before: Color = scene._displayed_tint
	var blend_before: bool = scene.blend_enabled
	var material_before: Material = clip.sprite.material
	var paper_before: bool = scene.paper_enabled
	var paper_strength_before: float = float(scene.blend_material.get_shader_parameter("paper_strength"))
	var paper_label_before: String = scene.paper_button.text
	var paper_disabled_before: bool = scene.paper_button.disabled
	var blend_label_before: String = scene.blend_button.text
	var clean_frames: Array = scene.clean_frames
	var original_frames: Array = scene.original_frames
	var button_bounds_before: Rect2 = scene.matte_button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, scene.matte_button.size)

	scene.set_matte_cleanup(false)
	var original := await capture("%dx%d-frame-%02d-matte-original.png" % [size.x, size.y, frame])
	check(not scene.matte_enabled and clip.frames == original_frames and clip.sprite.texture == original_frames[frame_before], "original matte capture uses the original frame at %d" % frame)
	check(clip.seconds == seconds_before and clip.frame_index == frame_before and clip.paused == paused_before and clip.speed == speed_before, "original matte preserves exact clip time, frame, pause, and speed")
	check(clip.fps == fps_before and clip.duration == duration_before and clip.position == clip_position_before and clip.scale == clip_scale_before, "original matte preserves clip fps, duration, position, and scale")
	check(clip.sprite.position == sprite_position_before and clip.sprite.scale == sprite_scale_before and clip.sprite.get_rect() == sprite_rect_before and clip.sprite.texture.get_size() == sprite_size_before and clip.sprite.get_global_transform_with_canvas() == actor_transform_before, "original matte preserves sprite anchor and geometry")
	check(var_to_bytes(clip.anchors) == anchors_before and var_to_bytes(clip.data) == data_before, "original matte preserves clip anchors and data")
	check(scene.dynamic_enabled == dynamic_before and scene.presentation_time == presentation_before and _script_snapshot(scene.state) == state_before and _script_snapshot(scene.environment_presenter) == environment_before, "original matte preserves Dynamic, presentation time, and snapshots")
	check(scene._displayed_tint == tint_before and clip.modulate == tint_before and scene.blend_enabled == blend_before and clip.sprite.material == material_before, "original matte preserves world modulation and scene shader mode")
	check(scene.paper_enabled == paper_before and scene.paper_button.text == paper_label_before and scene.paper_button.disabled == paper_disabled_before and scene.blend_button.text == blend_label_before and is_equal_approx(float(scene.blend_material.get_shader_parameter("paper_strength")), paper_strength_before), "original matte leaves paper and blend preferences unchanged")
	check(scene.matte_button.text == "原始边缘" and not scene.matte_button.disabled, "original matte button label remains enabled")
	var button_bounds_after_original: Rect2 = scene.matte_button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, scene.matte_button.size)

	scene.set_matte_cleanup(true)
	var clean := await capture("%dx%d-frame-%02d-matte-clean.png" % [size.x, size.y, frame])
	check(scene.matte_enabled and clip.frames == clean_frames and clip.sprite.texture == clean_frames[frame_before], "clean matte capture uses the clean frame at %d" % frame)
	check(scene.matte_button.text == "干净边缘" and not scene.matte_button.disabled, "clean matte button label remains enabled")
	check(clip.seconds == seconds_before and clip.frame_index == frame_before and clip.paused == paused_before and clip.speed == speed_before, "matte pair preserves exact clip time, frame, pause, and speed")
	check(clip.fps == fps_before and clip.duration == duration_before and clip.position == clip_position_before and clip.scale == clip_scale_before, "matte pair preserves clip fps, duration, position, and scale")
	check(clip.sprite.position == sprite_position_before and clip.sprite.scale == sprite_scale_before and clip.sprite.get_rect() == sprite_rect_before and clip.sprite.texture.get_size() == sprite_size_before, "matte pair preserves sprite anchor and geometry")
	check(clip.sprite.get_global_transform_with_canvas() == actor_transform_before and var_to_bytes(clip.anchors) == anchors_before and var_to_bytes(clip.data) == data_before, "matte pair preserves actor transform, anchors, and clip data")
	check(scene.dynamic_enabled == dynamic_before and scene.presentation_time == presentation_before and _script_snapshot(scene.state) == state_before, "matte pair freezes presentation time and DemoState")
	check(_script_snapshot(scene.environment_presenter) == environment_before and scene._displayed_tint == tint_before and clip.modulate == tint_before, "matte pair freezes environment state and world modulation")
	check(scene.blend_enabled == blend_before and clip.sprite.material == material_before and scene.paper_enabled == paper_before and is_equal_approx(float(scene.blend_material.get_shader_parameter("paper_strength")), paper_strength_before), "matte pair leaves scene blending, actor shader, and paper preference unchanged")
	check(scene.paper_button.text == paper_label_before and scene.paper_button.disabled == paper_disabled_before and scene.blend_button.text == blend_label_before and not scene.matte_button.disabled, "matte pair leaves blend and paper controls unchanged and keeps matte control enabled")

	var sprite_bounds: Rect2 = actor_transform_before * Rect2(Vector2.ZERO, sprite_size_before)
	var actor_rect := _to_image_rect(sprite_bounds.grow(4.0), original)
	var button_bounds_after_clean: Rect2 = scene.matte_button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, scene.matte_button.size)
	var button_bounds := button_bounds_before.merge(button_bounds_after_original).merge(button_bounds_after_clean).grow(4.0)
	var matte_button_rect := _to_image_rect(button_bounds, original)
	check(_outside_regions_match(original, clean, [actor_rect, matte_button_rect]), "matte pair changes only actor and matte-button pixels at frame %d" % frame)
	check(original.get_region(actor_rect).get_data() != clean.get_region(actor_rect).get_data(), "matte cleanup visibly changes actor pixels at frame %d" % frame)
	var used: Rect2 = actor_transform_before * Rect2(clip.sprite.texture.get_image().get_used_rect())
	check(scene._art_root.get_global_rect().encloses(used), "clean matte adds no clipping at frame %d" % frame)
	if frame == 40:
		var patch_bounds: Rect2 = actor_transform_before * Rect2(Vector2(10.0, 235.0), Vector2(20.0, 10.0))
		var patch_rect := _to_image_rect(patch_bounds.grow(2.0), original)
		check(patch_rect.size.x > 0 and patch_rect.size.y > 0, "audited frame40 patch maps inside the actor capture")
		check(original.get_region(patch_rect).get_data() != clean.get_region(patch_rect).get_data(), "clean matte changes the audited frame40 backdrop patch")

func _to_image_rect(rect: Rect2, image: Image) -> Rect2i:
	var factor := Vector2(image.get_size()) / root.get_visible_rect().size
	var start_f := rect.position * factor
	var end_f := rect.end * factor
	var start := Vector2i(floori(start_f.x), floori(start_f.y))
	var finish := Vector2i(ceili(end_f.x), ceili(end_f.y))
	return Rect2i(start, finish - start).intersection(Rect2i(Vector2i.ZERO, image.get_size()))

func _polygon_bounds(polygon: Polygon2D) -> Rect2:
	var points: PackedVector2Array = polygon.polygon
	if points.is_empty():
		return Rect2()
	var transform := polygon.get_global_transform_with_canvas()
	var result := Rect2(transform * points[0], Vector2.ZERO)
	for point in points:
		result = result.expand(transform * point)
	return result

func _outside_regions_match(left: Image, right: Image, exclusions: Array[Rect2i]) -> bool:
	var regions: Array[Rect2i] = [Rect2i(Vector2i.ZERO, left.get_size())]
	for exclusion in exclusions:
		var next_regions: Array[Rect2i] = []
		for region in regions:
			next_regions.append_array(_subtract_rect(region, exclusion))
		regions = next_regions
	for region in regions:
		if region.size.x > 0 and region.size.y > 0 and left.get_region(region).get_data() != right.get_region(region).get_data():
			return false
	return true

func _subtract_rect(source: Rect2i, cut: Rect2i) -> Array[Rect2i]:
	var overlap := source.intersection(cut)
	if overlap.size.x <= 0 or overlap.size.y <= 0:
		return [source]
	var pieces: Array[Rect2i] = []
	if overlap.position.y > source.position.y:
		pieces.append(Rect2i(source.position, Vector2i(source.size.x, overlap.position.y - source.position.y)))
	if overlap.end.y < source.end.y:
		pieces.append(Rect2i(Vector2i(source.position.x, overlap.end.y), Vector2i(source.size.x, source.end.y - overlap.end.y)))
	if overlap.position.x > source.position.x:
		pieces.append(Rect2i(Vector2i(source.position.x, overlap.position.y), Vector2i(overlap.position.x - source.position.x, overlap.size.y)))
	if overlap.end.x < source.end.x:
		pieces.append(Rect2i(Vector2i(overlap.end.x, overlap.position.y), Vector2i(source.end.x - overlap.end.x, overlap.size.y)))
	return pieces

func _script_snapshot(instance) -> PackedByteArray:
	var snapshot: Dictionary = {}
	for property: Dictionary in instance.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			snapshot[property.name] = instance.get(property.name)
	return var_to_bytes(snapshot)

func capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(output.path_join(name)) == OK,"saved "+name)
	report.captures.append({"file":name,"image_size":[image.get_width(),image.get_height()],"frame":scene.clip.frame_index})
	return image
func check(ok: bool,label: String) -> void:
	report.checks.append({"ok":ok,"label":label})
	if not ok:
		report.failures += 1
		push_error(label)
