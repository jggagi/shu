extends SceneTree

const SCENE_PATH := "res://scenes/demos/sword_mocap_comparison.tscn"
const DEFAULT_OUTPUT := "res://.local/qa/sword-mocap-v1/render"
const WINDOW_SIZES := [Vector2i(1152, 720), Vector2i(960, 600)]

var output_path := ""
var failures := 0
var checks := 0
var captures: Array = []
var report: Dictionary = {"captures": [], "checks": []}
var lab: Control
var requested_size := Vector2i.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZES[0]
	OS.low_processor_usage_mode = false
	output_path = _resolve_output_path()
	DirAccess.make_dir_recursive_absolute(output_path)
	var method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
	var display := DisplayServer.get_name()
	var adapter := RenderingServer.get_video_adapter_name()
	report["renderer"] = {"method": method, "adapter": adapter, "display_server": display}
	check(method.to_lower().contains("compat"), "project uses the Compatibility renderer")
	check(display.to_lower() != "headless", "render runner has a real windowed display server")
	check(not adapter.is_empty(), "rendering adapter identity is available")
	if display.to_lower() == "headless":
		await _finish()
		return

	var packed := load(SCENE_PATH) as PackedScene
	check(packed != null, "comparison scene loads for Compatibility rendering")
	if packed == null:
		await _finish()
		return
	lab = packed.instantiate() as Control
	root.add_child(lab)
	await process_frame
	await process_frame
	check(lab != null and lab.live_model != null and lab.frame_count > 0, "both study assets are active in the rendered scene")
	if lab == null or lab.live_model == null or lab.frame_count <= 0:
		await _finish()
		return
	lab.playing = false
	lab.set_process(false)
	lab.seek_motion(0.0)
	lab.set_background(true)
	lab.set_single_mode(-1)

	for window_size: Vector2i in WINDOW_SIZES:
		root.size = window_size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		requested_size = window_size
		lab.seek_motion(0.0)
		lab.set_background(false)
		await process_frame
		var size_dir := output_path.path_join("%dx%d" % [window_size.x, window_size.y])
		DirAccess.make_dir_recursive_absolute(size_dir)
		check(absi(root.size.x - window_size.x) <= 1 and absi(root.size.y - window_size.y) <= 1, "window reaches %dx%d" % [window_size.x, window_size.y])
		var image := await _capture(size_dir, "phase-00-start.png")
		check(_near_size(image.get_size(), window_size), "start capture is near %dx%d" % [window_size.x, window_size.y])
		lab.set_background(true)
		var seen_times: Array[float] = [0.0]
		var phase_index := 0
		for phase_value: Variant in lab.phases:
			if not phase_value is Dictionary:
				continue
			var phase: Dictionary = phase_value
			var phase_time: float = clampf(float(phase.get("start", 0.0)), 0.0, lab.duration)
			if _contains_time(seen_times, phase_time):
				continue
			seen_times.append(phase_time)
			phase_index += 1
			lab.seek_motion(phase_time)
			await process_frame
			var phase_name := str(phase.get("label", "phase"))
			var filename := "phase-%02d-%0.3f.png" % [phase_index, phase_time]
			var phase_image := await _capture(size_dir, filename)
			check(_near_size(phase_image.get_size(), window_size), "phase %s captures at requested output size" % phase_name)
		lab.seek_motion(lab.duration)
		await process_frame
		var final_image := await _capture(size_dir, "phase-final.png")
		check(_near_size(final_image.get_size(), window_size), "final frame captures at requested output size")

		var frozen_time: float = lab.duration * 0.37
		lab.seek_motion(frozen_time)
		await process_frame
		var paused_a := await _capture(size_dir, "paused-a.png")
		await create_timer(0.2).timeout
		var paused_b := await _capture(size_dir, "paused-b.png")
		var identical := paused_a.get_size() == paused_b.get_size() and paused_a.get_data() == paused_b.get_data()
		report["paused_identical_%dx%d" % [window_size.x, window_size.y]] = identical
		check(identical, "paused B/C composition is pixel-identical over time at %dx%d" % [window_size.x, window_size.y])

	await _finish()

func _resolve_output_path() -> String:
	var args := OS.get_cmdline_user_args()
	var requested := ""
	for index in range(args.size() - 1):
		if args[index] == "--output":
			requested = args[index + 1]
			break
	if requested.is_empty():
		requested = DEFAULT_OUTPUT
	if requested.begins_with("res://"):
		return ProjectSettings.globalize_path(requested)
	return requested

func _near_size(actual: Vector2i, expected: Vector2i) -> bool:
	return absi(actual.x - expected.x) <= 2 and absi(actual.y - expected.y) <= 2

func _contains_time(values: Array[float], target: float) -> bool:
	for value: float in values:
		if is_equal_approx(value, target):
			return true
	return false

func _capture(directory: String, filename: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := directory.path_join(filename)
	var result := image.save_png(path)
	check(result == OK, "saved Compatibility capture %s" % filename)
	captures.append({
		"name": filename,
		"requested_window_size": [requested_size.x, requested_size.y],
		"window_size": [root.size.x, root.size.y],
		"image_size": [image.get_width(), image.get_height()]
	})
	return image

func check(condition: bool, label: String) -> void:
	checks += 1
	report.checks.append({"ok": condition, "label": label})
	if not condition:
		failures += 1
		push_error(label)

func _finish() -> void:
	report["check_count"] = checks
	report["failure_count"] = failures
	report["captures"] = captures
	var report_file := FileAccess.open(output_path.path_join("render-report.json"), FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "  ") + "\n")
	print("SWORD_MOCAP_RENDER: %d checks, %d captures, %d failures" % [checks, captures.size(), failures])
	quit(0 if failures == 0 else 1)
