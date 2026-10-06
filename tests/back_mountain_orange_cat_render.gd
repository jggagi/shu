extends SceneTree

# Real Compatibility-window captures for the orange-cat interaction. This is a
# small independent harness so the existing Environment/Ambient render modes
# and their output paths stay unchanged.
const SCENE_PATH := "res://scenes/demos/back_mountain_training.tscn"
const OUTPUT_DIR := "res://.local/qa/back-mountain-orange-cat-v2"
const WINDOW_SIZE := Vector2i(960, 600)

var game: Control
var failures := 0
var checks: Dictionary = {}
var report: Dictionary = {"checks": {}, "screenshots": [], "pixel_deltas": {}, "fixtures": {}, "capture_metrics": {}}
var captured_cat_rects: Dictionary = {}
var captured_frames := 0
var cat_petted_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZE
	OS.low_processor_usage_mode = false
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	var packed := load(SCENE_PATH) as PackedScene
	check(packed != null, "Back Mountain scene loads for orange-cat rendering")
	if packed == null:
		await _finish()
		return
	game = packed.instantiate() as Control
	root.add_child(game)
	await process_frame
	await process_frame
	root.size = WINDOW_SIZE
	await process_frame
	check(game.state != null and game.environment_presenter != null and game.ambient_life != null, "capture runs through the current state, Environment, and Ambient Life scene")
	if game.state == null or game.environment_presenter == null or game.ambient_life == null:
		await _finish()
		return
	var renderer_method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
	var adapter_name := RenderingServer.get_video_adapter_name()
	var display_server := DisplayServer.get_name()
	report.renderer = {"method_setting": renderer_method, "adapter": adapter_name, "display_server": display_server}
	report.viewport = [root.size.x, root.size.y]
	check(renderer_method.to_lower().contains("compat"), "real captures use the Compatibility renderer")
	check(display_server.to_lower() != "headless" and not adapter_name.is_empty(), "real captures use a visible window and renderer adapter")
	check(root.size == WINDOW_SIZE, "render window is reset to 960x600 after scene readiness")

	game.qa_motion_paused = true
	game.set_process(false)
	game.set_lighting(false)
	game.set_dynamic(true)
	game.set_ambient_life(true)
	game.state.time_index = 0
	game._refresh_hud()
	game.set_weather("clear", false)
	game.set_night_preview(false, false)
	_settle_environment()
	var life: Node = game.ambient_life
	var hotspot: Button = life.cat_hotspot
	var cat_root: Node2D = life.visual_nodes.get("cat") as Node2D
	if hotspot == null or cat_root == null or cat_root.get_child_count() == 0:
		check(false, "current adapter exposes a cat hotspot and rendered root")
		await _finish()
		return
	var cat_sprite := cat_root.get_child(0) as Sprite2D
	life.cat_petted.connect(_on_cat_petted)
	life.reset()
	life.resume_auto()
	var automatic_cat: Dictionary = await _advance_to_auto_cat(life, 6.0)
	check(not automatic_cat.is_empty() and not bool(automatic_cat.get("forced", true)), "clear capture uses a naturally scheduled cat event")
	if automatic_cat.is_empty():
		await _finish()
		return
	var auto_age := float(life.presenter.elapsed) - float(automatic_cat.start)
	life.advance(maxf(0.0, 1.1 - auto_age))
	auto_age = float(life.presenter.elapsed) - float(automatic_cat.start)
	report.fixtures.clear_cat = {"forced": false, "event_start": automatic_cat.start, "capture_age_seconds": auto_age}
	var state_before := _script_snapshot(game.state)
	var environment_before := _script_snapshot(game.environment_presenter)
	var clear_cat_image: Image = await _capture("01_clear_auto_cat.png")
	var cat_rect_before: Rect2 = captured_cat_rects["01_clear_auto_cat.png"]
	check(cat_root.visible and hotspot.visible and not hotspot.disabled, "clear capture shows an active rendered cat hit target")
	check(_script_snapshot(game.state) == state_before and _script_snapshot(game.environment_presenter) == environment_before, "natural clear-cat capture preserves all gameplay and Environment fields")
	var authored_spot_before_pet: Vector2 = life.cat_spot.position
	check(cat_rect_before.size.x > 0 and cat_rect_before.size.y > 0, "cat art has a measurable rendered viewport region")

	# Send mouse motion and down/up through the actual viewport input path. This
	# proves hit testing reaches the foreground Button at the visible cat.
	await _click(hotspot)
	life.advance(0.25)
	check(cat_petted_count == 1 and _cat_frame(cat_sprite) == 7, "viewport mouse click starts the frame-seven pet reaction")
	check(hotspot.disabled and hotspot.visible, "visible pet reaction blocks a second click")
	var pet_image: Image = await _capture("02_mouse_pet_reaction.png")
	var cat_rect_after: Rect2 = captured_cat_rects["02_mouse_pet_reaction.png"]
	var pixel_crop_rect := cat_rect_before.merge(cat_rect_after).grow(8.0)
	var pet_crop_before := _crop(clear_cat_image, pixel_crop_rect)
	var pet_crop_after := _crop(pet_image, pixel_crop_rect)
	var pet_delta := _image_delta(pet_crop_before, pet_crop_after)
	report.pixel_deltas.pet_reaction = pet_delta
	report.capture_metrics.pet_crop_rect = _rect_array(pixel_crop_rect)
	check(int(pet_delta.changed_pixels) > 20, "pet reaction changes visible cat pixels in the real render")
	check(_script_snapshot(game.state) == state_before, "mouse pet leaves every DemoState field unchanged")
	check(_script_snapshot(game.environment_presenter) == environment_before, "mouse pet leaves every Environment presenter field unchanged")
	check(life.cat_spot.position == authored_spot_before_pet, "mouse pet leaves the original cat spot unchanged")
	life.advance(3.2)
	check(not hotspot.disabled and _cat_frame(cat_sprite) != 7, "pet reaction ends after its 3.2-second clock without a restart")
	check(cat_root.position == authored_spot_before_pet, "cat returns to its authored spot after the nuzzle ends")

	# Finish the pet reaction and reset it before taking natural pose captures.
	# One automatic encounter supplies the wash, existing age-20.4, and roll frames.
	life.reset()
	life.resume_auto()
	var selfplay_cat: Dictionary = await _advance_to_auto_cat(life, 6.0)
	check(not selfplay_cat.is_empty() and not bool(selfplay_cat.get("forced", true)), "natural-pose captures start from a naturally scheduled cat event")
	if not selfplay_cat.is_empty():
		var selfplay_age := float(life.presenter.elapsed) - float(selfplay_cat.start)
		life.advance(maxf(0.0, 15.2 - selfplay_age))
		var groom_age := float(life.presenter.elapsed) - float(selfplay_cat.start)
		var groom_frame := _cat_frame(cat_sprite)
		report.fixtures.grooming = {"forced": false, "event_start": selfplay_cat.start, "capture_age_seconds": groom_age, "pose_index": groom_frame}
		await _capture("03_auto_groom_age15_2.png")
		check(is_equal_approx(groom_age, 15.2) and groom_frame == 4, "age-15.2 natural grooming capture uses wash pose")
		life.advance(maxf(0.0, 20.4 - groom_age))
		selfplay_age = float(life.presenter.elapsed) - float(selfplay_cat.start)
		var selfplay_frame := _cat_frame(cat_sprite)
		report.fixtures.self_play_age20_4 = {"forced": false, "event_start": selfplay_cat.start, "capture_age_seconds": selfplay_age, "pose_index": selfplay_frame}
		await _capture("04_auto_self_play_age20_4.png")
		check(is_equal_approx(selfplay_age, 20.4) and selfplay_frame in [5, 6], "age-20.4 natural self-play capture uses roll/play or paw-leaf artwork")
		life.advance(maxf(0.0, 21.0 - selfplay_age))
		var roll_age := float(life.presenter.elapsed) - float(selfplay_cat.start)
		var roll_frame := _cat_frame(cat_sprite)
		report.fixtures.roll_age21 = {"forced": false, "event_start": selfplay_cat.start, "capture_age_seconds": roll_age, "pose_index": roll_frame}
		await _capture("05_auto_roll_age21.png")
		check(is_equal_approx(roll_age, 21.0) and roll_frame in [5, 6], "age-21 natural play capture uses roll/play or paw-leaf artwork")
		check(_script_snapshot(game.state) == state_before and _script_snapshot(game.environment_presenter) == environment_before, "self-play capture preserves all gameplay and Environment fields")

	game.set_weather("cloudy", false)
	_settle_environment()
	life.reset()
	var cloudy_state := _script_snapshot(game.state)
	var cloudy_environment := _script_snapshot(game.environment_presenter)
	check(game.force_ambient_life("cat"), "cloudy visual fixture accepts the unsheltered cat")
	life.advance(1.0)
	report.fixtures.cloudy_cat = {"forced": true, "weather": "cloudy"}
	await _capture("06_cloudy_forced_cat.png")
	check(cat_root.visible and hotspot.visible and not hotspot.disabled, "cloudy capture shows the rendered cat and active hotspot")
	check(_script_snapshot(game.state) == state_before and _script_snapshot(game.state) == cloudy_state, "cloudy capture preserves the original DemoState")
	check(_script_snapshot(game.environment_presenter) == cloudy_environment, "cloudy cat capture preserves its settled Environment fixture")

	game.set_weather("light_rain", false)
	_settle_environment()
	life.reset()
	var rain_state := _script_snapshot(game.state)
	var rain_environment := _script_snapshot(game.environment_presenter)
	report.fixtures.light_rain = {"forced": false, "weather": "light_rain", "cat_spot_sheltered": false}
	await _capture("07_light_rain_no_cat.png")
	check(not game.force_ambient_life("cat") and not cat_root.visible and not hotspot.visible and hotspot.disabled, "light-rain capture has no unsheltered cat or active hit target")
	check(_script_snapshot(game.state) == state_before and _script_snapshot(game.state) == rain_state, "light-rain capture preserves the original DemoState")
	check(_script_snapshot(game.environment_presenter) == rain_environment, "light-rain capture preserves its settled Environment fixture")

	game.set_weather("clear", false)
	_settle_environment()
	life.reset()
	check(game.force_ambient_life("cat"), "static comparison fixture accepts the cat before freezing motion")
	life.advance(7.0)
	game.set_dynamic(false)
	life.observe_environment()
	var static_state := _script_snapshot(game.state)
	var static_environment := _script_snapshot(game.environment_presenter)
	report.fixtures.static_cat = {"forced": true, "dynamic": false, "atlas_frame": _cat_frame(cat_sprite)}
	await _capture("08_static_cat_frame0.png")
	check(cat_root.visible and hotspot.visible and hotspot.disabled and _cat_frame(cat_sprite) == 0, "static capture keeps the cat visible on frame zero and disables pet input")
	check(_script_snapshot(game.state) == state_before and _script_snapshot(game.state) == static_state, "static capture preserves the original DemoState")
	check(_script_snapshot(game.environment_presenter) == static_environment, "static cat capture preserves its settled Environment fixture")

	await _finish()


func _advance_to_auto_cat(life: Node, max_seconds: float) -> Dictionary:
	var steps := ceili(max_seconds * 10.0)
	for _step in steps:
		life.advance(0.1)
		var events: Dictionary = life.presenter.get_active_events()
		if events.has("cat") and not bool(events.cat.get("forced", true)):
			return events.cat
	return {}


func _settle_environment() -> void:
	game.environment_presenter.finish_transition()
	game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
	game.ambient_life.observe_environment()


func _click(control: Control) -> void:
	var point := root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	var down := InputEventMouseButton.new()
	down.position = point
	down.global_position = point
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down)
	var up := InputEventMouseButton.new()
	up.position = point
	up.global_position = point
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	root.push_input(up)
	await process_frame
	await process_frame


func _capture(filename: String) -> Image:
	root.size = WINDOW_SIZE
	await process_frame
	var size_after_first_frame := root.size
	root.size = WINDOW_SIZE
	await process_frame
	var size_after_second_frame := root.size
	root.size = WINDOW_SIZE
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var cat_sprite: Sprite2D = game.ambient_life.visual_nodes.get("cat").get_child(0) as Sprite2D
	var cat_rect := _screen_cat_rect(cat_sprite)
	captured_cat_rects[filename] = cat_rect
	report.capture_metrics[filename] = {
		"viewport_image_size": [image.get_width(), image.get_height()],
		"root_size_after_first_frame": [size_after_first_frame.x, size_after_first_frame.y],
		"root_size_after_second_frame": [size_after_second_frame.x, size_after_second_frame.y],
		"root_size_at_capture": [root.size.x, root.size.y],
		"window_final_transform": _transform_array(root.get_final_transform()),
		"cat_global_canvas_transform": _transform_array(cat_sprite.get_global_transform_with_canvas()),
		"cat_image_rect": _rect_array(cat_rect),
	}
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(filename))
	var error := image.save_png(output_path)
	check(error == OK, "real rendered screenshot saved: " + filename)
	check(image.get_size() == WINDOW_SIZE, "screenshot is 960x600: " + filename)
	check(size_after_first_frame == WINDOW_SIZE and size_after_second_frame == WINDOW_SIZE, "window remains 960x600 across capture frames: " + filename)
	check(root.size == WINDOW_SIZE, "actual render window is reset to 960x600 for capture: " + filename)
	report.screenshots.append(filename)
	captured_frames += 1
	return image


func _screen_cat_rect(sprite: Sprite2D) -> Rect2:
	var viewport_to_window := root.get_final_transform()
	var canvas_to_viewport := sprite.get_global_transform_with_canvas()
	return viewport_to_window * canvas_to_viewport * sprite.get_rect()


func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _transform_array(transform: Transform2D) -> Array:
	return [
		[transform.x.x, transform.x.y],
		[transform.y.x, transform.y.y],
		[transform.origin.x, transform.origin.y],
	]


func _crop(image: Image, rect: Rect2) -> Image:
	var left := clampi(floori(rect.position.x), 0, image.get_width())
	var top := clampi(floori(rect.position.y), 0, image.get_height())
	var right := clampi(ceili(rect.end.x), left, image.get_width())
	var bottom := clampi(ceili(rect.end.y), top, image.get_height())
	return image.get_region(Rect2i(left, top, maxi(1, right - left), maxi(1, bottom - top)))


func _image_delta(left: Image, right: Image) -> Dictionary:
	if left == null or right == null or left.get_size() != right.get_size():
		return {"changed_pixels": -1, "mean_rgb_delta": -1.0}
	var changed := 0
	var delta_sum := 0.0
	for y in left.get_height():
		for x in left.get_width():
			var a := left.get_pixel(x, y)
			var b := right.get_pixel(x, y)
			var delta := (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			delta_sum += delta
			if a != b:
				changed += 1
	return {"changed_pixels": changed, "mean_rgb_delta": delta_sum / float(maxi(1, left.get_width() * left.get_height()))}


func _cat_frame(sprite: Sprite2D) -> int:
	var texture := sprite.texture as AtlasTexture
	return int(texture.get_meta("pose_index", -1)) if texture != null else -1


func _script_snapshot(value: Object) -> Dictionary:
	var result: Dictionary = {}
	for property in value.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property.name)
		var property_value: Variant = value.get(name)
		result[name] = property_value.duplicate(true) if property_value is Dictionary or property_value is Array else property_value
	if value.has_method("time_text"):
		result["time_text"] = value.time_text()
	return result


func _on_cat_petted() -> void:
	cat_petted_count += 1


func check(condition: bool, label: String) -> void:
	checks[label] = condition
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1
		push_error(label)


func _finish() -> void:
	report.checks = checks
	report.failure_count = failures
	report.captured_frames = captured_frames
	var report_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join("report.json"))
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ") + "\n")
	else:
		push_error("could not write orange-cat render report: " + report_path)
		failures += 1
	print("BACK_MOUNTAIN_ORANGE_CAT_RENDER: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
