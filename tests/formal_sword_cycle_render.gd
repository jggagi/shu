extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const DEFAULT_OUTPUT := "res://.local/qa/formal-sword-cycle"
const MANUAL_IDS := ["pine_wind", "listening_rain", "returning_tide", "rising_peak", "swift_swallow"]
const CLIP_IDS := ["songfeng", "chuanyun", "huilan", "tiaoyue", "xieying"]
const FRAME_DELTA := 1.0 / 30.0

var app: Control
var output_dir := DEFAULT_OUTPUT
var qa_size := Vector2i(1152, 720)
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var check_records: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	var absolute_dir := _absolute_output_dir()
	var mkdir_result := DirAccess.make_dir_recursive_absolute(absolute_dir)
	check(mkdir_result == OK or mkdir_result == ERR_ALREADY_EXISTS, "the render output directory is available")
	check(DisplayServer.get_name() != "headless", "the renderer uses a real display server")
	if DisplayServer.get_name() == "headless":
		_finish()
		return

	app = MainScene.instantiate() as Control
	root.add_child(app)
	await process_frame
	await process_frame
	check(app.state != null and app.scene_router.current_scene_id == "tingyu", "the rendered app starts in Tingyu")
	if app.state == null:
		_finish()
		return

	app.set_ambient_life_enabled(false)
	app.weather.set_weather("cloudy", false)
	app.weather.set_dynamic(false)
	await _capture("00_tingyu_initial.png", {"scene": "tingyu", "state": "initial"})

	for index in range(MANUAL_IDS.size()):
		var manual_id := str(MANUAL_IDS[index])
		var clip_id := str(CLIP_IDS[index])
		app.state.energy = int(app.state.rules.energy_max)
		app._refresh()
		await click(app.back_mountain_entry)
		check(app.scene_router.current_scene_id == "back_mountain", "%s enters Back Mountain through the real Tingyu button" % manual_id)
		var view: Variant = app.back_mountain_view
		if view == null:
			check(false, "%s mounts the formal view" % manual_id)
			_finish()
			return
		view.set_dynamic(false)
		view.ambient_life.set_enabled(false)
		var manual_button: Button = view.manual_buttons.get(manual_id)
		check(manual_button != null, "%s exposes its real manual selector" % manual_id)
		if manual_button == null:
			_finish()
			return
		await click(manual_button)
		var practice: Variant = view.sword_practice
		check(app.state.selected_sword_manual_id == manual_id and practice.selected_clip_id == clip_id, "%s selects its approved %s clip from the actual host UI" % [manual_id, clip_id])
		check(view.prepare_sword_training() and practice.resource_ready(), "%s prepares image resources before a formal action" % manual_id)
		practice._idle_elapsed = 0.0
		practice._apply_idle_frame(0)
		await _capture("%02d_%s_idle.png" % [index + 1, manual_id], {
			"scene": "back_mountain",
			"state": "idle",
			"manual_id": manual_id,
			"clip_id": clip_id,
			"frame_index": practice.current_frame_index,
			"dynamic": view.dynamic_enabled,
		})

		await click(view.sword_training_button)
		check(app.busy and view.busy and practice.playing and not view.dynamic_enabled, "%s begins a real Static practice action" % manual_id)
		var keypose_frame := _first_outgoing_frame(practice, clip_id)
		var frames_to_keypose := maxi(0, keypose_frame - int(practice.current_frame_index))
		_advance_practice(practice, frames_to_keypose)
		check(practice.phase == "出剑" and practice.current_frame_index >= keypose_frame, "%s reaches the outgoing strike pose" % manual_id)
		await _capture("%02d_%s_action-keypose.png" % [index + 1, manual_id], {
			"scene": "back_mountain",
			"state": "action_keypose",
			"manual_id": manual_id,
			"clip_id": clip_id,
			"phase": practice.phase,
			"frame_index": practice.current_frame_index,
			"static": true,
		})
		_advance_practice_to_finish(practice)
		check(app.scene_router.current_scene_id == "tingyu" and not app.busy, "%s completes and returns after its rendered action" % manual_id)
		await _capture("%02d_%s_return.png" % [index + 1, manual_id], {
			"scene": "tingyu",
			"state": "returned_result",
			"manual_id": manual_id,
			"clip_id": clip_id,
			"energy": app.state.energy,
			"swordsmanship": app.state.swordsmanship,
			"time_index": app.state.time_index,
		})

	# Exercise the low-energy message on the mounted real view. The disabled
	# button is not clicked; the host entry is invoked to prove it stays atomic.
	app.state.energy = int(app.state.rules.sword_training_cost) - 1
	app._refresh()
	await click(app.back_mountain_entry)
	var low_view: Variant = app.back_mountain_view
	if low_view != null:
		low_view.set_dynamic(false)
		low_view.ambient_life.set_enabled(false)
		await _capture("16_insufficient_energy.png", {
			"scene": "back_mountain",
			"state": "insufficient_energy_before_request",
			"energy": app.state.energy,
		})
		var before := _script_variable_snapshot(app.state)
		var result: Dictionary = app._request_sword_training()
		check(not bool(result.get("ok", false)) and _script_variable_snapshot(app.state) == before, "insufficient energy keeps the real host state unchanged")
		check(not app.busy and not low_view.sword_practice.playing, "insufficient energy does not play a clip")
		await _capture("17_insufficient_energy_notice.png", {
			"scene": "back_mountain",
			"state": "insufficient_energy_notice",
			"energy": app.state.energy,
			"status": low_view.sword_status.text,
		})
		check(app.return_to_tingyu(), "the low-energy notice can return to Tingyu")
		await _capture("18_tingyu_after_insufficient.png", {"scene": "tingyu", "state": "after_insufficient_energy"})
	else:
		check(false, "the insufficient-energy view mounts")

	check(captures.size() == 19, "render report contains Tingyu, fifteen five-manual cycle captures, and three low-energy captures")
	_finish()


func _parse_user_args() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var argument := str(args[index])
		if argument == "--output" and index + 1 < args.size():
			index += 1
			output_dir = str(args[index])
		elif argument.begins_with("--output="):
			output_dir = argument.trim_prefix("--output=")
		elif argument == "--qa-size" and index + 1 < args.size():
			index += 1
			_parse_size(str(args[index]))
		elif argument.begins_with("--qa-size="):
			_parse_size(argument.trim_prefix("--qa-size="))
		index += 1


func _parse_size(value: String) -> void:
	var parts := value.to_lower().split("x")
	if parts.size() != 2:
		push_error("--qa-size must use WIDTHxHEIGHT, received: " + value)
		failures += 1
		return
	var width := int(parts[0])
	var height := int(parts[1])
	if width < 320 or height < 240:
		push_error("--qa-size is too small: " + value)
		failures += 1
		return
	qa_size = Vector2i(width, height)


func _absolute_output_dir() -> String:
	if output_dir.begins_with("res://") or output_dir.begins_with("user://"):
		return ProjectSettings.globalize_path(output_dir)
	return output_dir


func _first_outgoing_frame(practice: Variant, clip_id: String) -> int:
	var entry: Dictionary = practice._set_catalog.get(clip_id, {})
	for phase_value in entry.get("phases", []):
		if phase_value is Dictionary and str(phase_value.get("label", "")) == "出剑":
			return int(phase_value.get("start_frame", 1)) - 1
	return 44


func _advance_practice(practice: Variant, frames: int) -> void:
	for _frame in range(frames):
		practice._process(FRAME_DELTA)


func _advance_practice_to_finish(practice: Variant) -> void:
	var guard := 0
	while practice.playing and guard < 240:
		practice._process(FRAME_DELTA)
		guard += 1
	check(not practice.playing and guard < 240, "the actual rendered action completes on a synthetic 30 fps clock")


func click(button: Control) -> void:
	var canvas_point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var point := root.get_final_transform() * canvas_point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame


func _capture(filename: String, metadata: Dictionary) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var full_path := _absolute_output_dir().path_join(filename)
	var save_result := image.save_png(full_path)
	check(save_result == OK, "capture %s saves" % filename)
	check(image.get_size() == qa_size, "capture %s uses the one requested QA viewport size" % filename)
	var record: Dictionary = {
		"file": filename,
		"pixels": [image.get_width(), image.get_height()],
		"capture_kind": str(metadata.get("state", "scene")),
	}
	for key in metadata:
		record[str(key)] = metadata[key]
	captures.append(record)


func _script_variable_snapshot(state: Object) -> Dictionary:
	var snapshot: Dictionary = {}
	for property_info in state.get_property_list():
		if (int(property_info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property_info.name)
		var value: Variant = state.get(name)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		snapshot[name] = value
	return snapshot


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
	check_records.append({"ok": condition, "label": message})


func _finish() -> void:
	var report := {
		"checks": checks,
		"failures": failures,
		"qa_size": [qa_size.x, qa_size.y],
		"display_server": DisplayServer.get_name(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"adapter": RenderingServer.get_video_adapter_name(),
		"captures": captures,
		"check_records": check_records,
	}
	var report_path := _absolute_output_dir().path_join("render-report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	else:
		push_error("Could not save the formal sword render report: " + report_path)
		failures += 1
	print("FORMAL_SWORD_CYCLE_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)
