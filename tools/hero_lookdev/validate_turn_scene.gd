extends SceneTree
## Actual Compatibility renderer integration check for the isolated shot stage.

var scene
var output := ""
var report := {"checks": [], "captures": [], "failures": 0}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	call_deferred("run")

func snapshot(instance: Object) -> PackedByteArray:
	var values: Dictionary = {}
	for property: Dictionary in instance.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = instance.get(property.name)
	return var_to_bytes(values)

func check(ok: bool, label: String) -> void:
	report.checks.append({"ok": ok, "label": label})
	if not ok:
		report.failures += 1
		push_error(label)

func capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(output.path_join(name)) == OK, "saved " + name)
	report.captures.append({"file": name, "size": [image.get_width(), image.get_height()], "state": scene.qa_state()})
	return image

func run() -> void:
	if output.is_empty() or not output.is_absolute_path():
		push_error("Absolute --output directory required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scenes/demos/jiang_turn_review.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var state_before := snapshot(scene.state)
	var frame_count: int = scene.REVIEW_FRAME_COUNT
	check((frame_count == 60 or frame_count == 120) and scene._old_frames.size() == frame_count and scene._refined_frames.size() == frame_count, "two complete %d-frame variants" % frame_count)
	check(is_equal_approx(scene.REVIEW_DURATION, float(frame_count) / 30.0), "shared duration derives from frame count at 30 fps")
	check(scene._resized_anchor.distance_to(Vector2(245.2273,466.5004)) < .01, "source-camera ground anchor retained")
	var quarter_frame := roundi(float(frame_count - 1) * 0.25)
	var half_frame := roundi(float(frame_count - 1) * 0.5)
	var three_quarter_frame := roundi(float(frame_count - 1) * 0.75)
	var sampled_frames := [0, quarter_frame, half_frame, three_quarter_frame, frame_count - 1]
	for size in [Vector2i(1152,720), Vector2i(960,600)]:
		root.size = size
		await process_frame
		for frame in sampled_frames:
			scene.seek_frame(frame)
			var environment_before := snapshot(scene.environment_presenter)
			var seconds: float = scene._clip_seconds
			var presentation: float = scene.presentation_time
			scene.set_variant(0)
			var old := await capture("%dx%d-old-%02d.png" % [size.x,size.y,frame+1])
			scene.set_variant(1)
			var improved := await capture("%dx%d-refined-%02d.png" % [size.x,size.y,frame+1])
			check(scene._frame_index == frame and scene._clip_seconds == seconds and scene.presentation_time == presentation, "A/B retains clock at frame %d" % (frame+1))
			check(snapshot(scene.environment_presenter) == environment_before, "A/B retains environment")
			check(old.get_region(Rect2i(0,int(size.y*.13),int(size.x*.55),int(size.y*.73))).get_data() == improved.get_region(Rect2i(0,int(size.y*.13),int(size.x*.55),int(size.y*.73))).get_data(), "A/B preserves painted background")
			var bounds: Rect2 = scene._review_sprite.get_global_transform() * Rect2(Vector2.ZERO,Vector2(512,512))
			check(scene._art_root.get_global_rect().encloses(bounds), "complete actor cell stays within art area")
	# Static freezes the populated world, actor, transitions and controlled shaders.
	scene.seek_frame(12); scene.set_speed(.5); scene.set_playing(true); scene.set_dynamic(false)
	var frozen: Dictionary = scene.qa_state(); var environment_frozen := snapshot(scene.environment_presenter)
	var still_a := await capture("static-a.png")
	scene._process(.7)
	var still_b := await capture("static-b.png")
	check(still_a.get_data() == still_b.get_data(), "Static images are byte-identical")
	check(scene.qa_state() == frozen and snapshot(scene.environment_presenter) == environment_frozen, "Static retains presentation and environment state")
	scene.set_dynamic(true); scene._process(.4)
	check(absf(scene._clip_seconds - .6) < .0001 and scene._frame_index == 18, "half-speed Resume continues from frozen frame")
	scene.seek_frame(3); scene.set_speed(1.0); scene.set_playing(true); scene._process(.3)
	check(scene._frame_index == 12, "normal speed advances native timing")
	scene._process(10.)
	check(scene._frame_index == frame_count - 1 and scene._clip_paused, "single-shot holds final frame")
	scene._replay_review()
	check(scene._frame_index == 0 and not scene._clip_paused, "replay restarts the shot")
	scene.set_playing(false); scene.seek_frame(three_quarter_frame)
	check(scene.set_time("you", false) and scene.set_weather("light_rain",false), "existing time and weather profiles apply")
	await capture("960x600-dusk-rain-refined.png")
	# Palette changes must stay on the actor in both bright and cool conditions.
	root.size = Vector2i(1152,720)
	scene.seek_frame(0)
	for environment in [["wu","clear"],["mao","cloudy"]]:
		check(scene.set_time(environment[0],false) and scene.set_weather(environment[1],false), "color review environment applies")
		scene.set_variant(0)
		var original_color := await capture("1152x720-%s-%s-original.png" % environment)
		scene.set_variant(1)
		var warm_color := await capture("1152x720-%s-%s-warm.png" % environment)
		check(original_color.get_data() != warm_color.get_data(), "palette comparison visibly changes")
		check(original_color.get_region(Rect2i(0,72,650,570)).get_data() == warm_color.get_region(Rect2i(0,72,650,570)).get_data(), "palette preserves painted world and its lighting")
	check(snapshot(scene.state) == state_before and scene.qa_state().demo_state_unchanged, "all DemoState script variables remain unchanged")
	report["status"] = "PASS" if report.failures == 0 else "FAIL"
	var file := FileAccess.open(output.path_join("scene-verification.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	print("JIANG_TURN_SCENE: %d checks, %d captures, %d failures" % [report.checks.size(),report.captures.size(),report.failures])
	quit(0 if report.failures == 0 else 1)
