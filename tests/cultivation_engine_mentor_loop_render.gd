extends SceneTree

const MentorScene := preload("res://scenes/demos/cultivation_engine_v02_mentor.tscn")
const DEFAULT_OUTPUT := "res://.local/qa/cultivation-engine-mentor-loop/render"
const LOGICAL_SIZE := Vector2i(1440, 900)
const ALLOWED_QA_SIZES := [Vector2i(1152, 720), Vector2i(960, 600)]
const CONTROL_WAIT_FRAMES := 45

var app: Control
var output_dir: String = DEFAULT_OUTPUT
var qa_size: Vector2i = Vector2i(1152, 720)
var test_store_dir: String = ""
var checks: int = 0
var failures: int = 0
var captures: Array[Dictionary] = []
var failure_messages: Array[String] = []
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	var absolute_output: String = _absolute_output_dir()
	var mkdir_result: Error = DirAccess.make_dir_recursive_absolute(absolute_output)
	check(mkdir_result == OK or mkdir_result == ERR_ALREADY_EXISTS, "the mentor-loop render output directory is available")
	check(DisplayServer.get_name() != "headless", "the render harness has a native display server")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = MentorScene.instantiate() as Control
	if app == null:
		check(false, "the mentor-loop demo scene instantiates as a Control")
		_finish()
		return
	root.add_child(app)
	await process_frame
	await process_frame
	var store: Variant = app.get("_store")
	check(store != null, "the mentor-loop UI initializes its local SaveStore")
	if store == null:
		_finish()
		return
	test_store_dir = _allocate_store_dir()
	check(not test_store_dir.is_empty(), "a unique isolated user-data directory is available")
	if test_store_dir.is_empty():
		_finish()
		return
	store.set("base_dir", test_store_dir)
	check(str(store.get("base_dir")) == test_store_dir, "every UI save uses the isolated render-test directory")
	if not await _click("PackSelectButton_0"):
		_finish()
		return
	await _capture("00_library.png", "mentor-loop pack selected in the catalog")
	await _check_layout("library", ["HeaderPanel", "LibraryIntro", "PackCardsScroll"])
	if not await _click("PackStartButton_0"):
		_finish()
		return
	if not await _run_mentor_flow():
		_finish()
		return
	check(captures.size() >= 8, "the report contains library, dialogue, motion, report, rest and restore captures")
	_finish()


func _run_mentor_flow() -> bool:
	var state: Dictionary = _state()
	check(_pack_id() == "shu_mentor_loop", "the first catalog start opens the mentor-loop pack")
	check(state.get("scene", "") == "tingyu_corridor" and state.get("phase", "") == "ready", "the new pack starts ready in the listening corridor")
	await _capture("01_corridor_start.png", "mentor-loop opening corridor")
	await _check_layout("opening corridor", ["HeaderPanel", "ScenePanel", "SceneDescription", "StatsPanel", "PhasePanel", "ActionScroll"])

	if not await _click("ActionButton_talk_mentor"):
		return false
	state = _state()
	check(state.get("phase", "") == "event" and state.get("event", {}).get("id", "") == "mentor_tip" and state.get("event", {}).get("node", "") == "opening", "the real action button opens the voiced mentor event")
	var voice: Dictionary = _voice_audit()
	check(int(voice.get("play_count", 0)) >= 1 and int(voice.get("clip_count", 0)) == 14, "the first line starts from the local fourteen-clip voice registry")
	check(_has_control("VoiceToggleButton"), "a real voice toggle appears for the voiced pack")
	var initial_play_count: int = int(voice.get("play_count", 0))
	if not await _click("VoiceToggleButton"):
		return false
	voice = _voice_audit()
	var muted_button: Button = await _fresh_button("VoiceToggleButton")
	check(muted_button != null and muted_button.text == "语音：关" and not bool(voice.get("enabled", true)) and not bool(voice.get("playing", true)), "muting stops the current voice and updates the real toggle")
	if not await _click("VoiceToggleButton"):
		return false
	voice = _voice_audit()
	var enabled_button: Button = await _fresh_button("VoiceToggleButton")
	check(enabled_button != null and enabled_button.text == "语音：开" and bool(voice.get("enabled", false)), "unmuting restores the enabled voice state")
	app.call("_set_status", "QA status redraw")
	app.call("_render")
	await process_frame
	voice = _voice_audit()
	check(int(voice.get("play_count", 0)) == initial_play_count, "mute, unmute and a same-node status redraw do not replay the opening line")
	check(str(_state().get("event", {}).get("node", "")) == "opening", "voice controls and status redraw preserve the active line")
	await _capture("02_opening_line.png", "first mentor line with local audio available")

	if not await _click("DialogContinueButton"):
		return false
	if not await _continue_until_node("choice", ["sit", "hurry", "advice"], initial_play_count + 1):
		return false
	state = _state()
	check(state.get("event", {}).get("node", "") == "choice" and _visible_label_contains("先陪我听一会儿雨"), "the readable two-dimensional corridor shows the authored lesson question")
	var take_lesson: Button = await _fresh_button("ChoiceButton_take_lesson")
	var skip_lesson: Button = await _fresh_button("ChoiceButton_return_to_practice")
	check(take_lesson != null and not take_lesson.disabled and skip_lesson != null and not skip_lesson.disabled, "both paid lesson and free practice choices are visible and enabled")
	await _capture("03_lesson_question.png", "readable corridor scene and mentor lesson question")
	await _check_layout("lesson question", ["HeaderPanel", "ScenePanel", "PhasePanel"])
	if not await _click("ChoiceButton_take_lesson"):
		return false
	state = _state()
	check(int(state.get("stats", {}).get("energy", -1)) == 92 and int(state.get("stats", {}).get("understanding", -1)) == 1 and int(state.get("slot", -1)) == 1, "the real choice click settles its eight-energy, one-understanding, one-slot cost")
	check(bool(state.get("flags", {}).get("breathing_hint", false)), "the accepted lesson arms its one-use training hint")
	check(int(_voice_audit().get("play_count", 0)) == initial_play_count + 5, "the paid branch starts its first response clip exactly once")
	if not await _click("DialogContinueButton"):
		return false
	if not await _click("DialogContinueButton"):
		return false
	check(int(_voice_audit().get("play_count", 0)) == initial_play_count + 6, "the mentor reply starts once and the following end remains unvoiced")
	check(_state().get("event", {}).get("node", "") == "end", "the paid mentor branch reaches its authored end")
	check(not bool(_state().get("flags", {}).get("mentor_lesson_heard", true)), "the UI leaves lesson progress uncommitted at the end node")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("phase", "") == "result" and bool(state.get("flags", {}).get("mentor_lesson_heard", false)), "continuing the event end commits the heard flag")
	check(_voice_is_stopped(), "voice playback stops when the event ends")
	await _capture("04_lesson_result.png", "lesson result with the event voice stopped")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_go_to_mountain"):
		return false
	state = _state()
	check(state.get("scene", "") == "back_mountain" and int(state.get("slot", -1)) == 1, "zero-slot travel reaches the mountain without moving time")
	if not await _click("ResultContinueButton"):
		return false
	var energy_before_sword: int = int(_state().get("stats", {}).get("energy", -1))
	if not await _click("ActionButton_pine_wind"):
		return false
	state = _state()
	check(state.get("phase", "") == "performing" and int(state.get("stats", {}).get("energy", -1)) == energy_before_sword - 22, "the real mountain action enters performing after one energy settlement")
	check(_button_disabled("SaveButton") and _button_disabled("ActionButton_return_to_corridor"), "the real UI prevents saving or leaving during the sword presentation")
	var mid_presentation: Dictionary = _presentation()
	check(bool(mid_presentation.get("playing", false)) and str(mid_presentation.get("clip_id", "")) == "songfeng", "the selected real sword clip is visibly playing")
	await _capture("05_mountain_midaction.png", "mountain sword presentation while the selected clip is playing")
	if not await _wait_for_phase("result", 240):
		check(false, "the real sword presentation finishes through the UI callback")
		return false
	state = _state()
	var sword_delta: Dictionary = state.get("last_result", {}).get("delta", {}).get("stats", {})
	check(int(state.get("stats", {}).get("cultivation", -1)) == 6 and int(state.get("stats", {}).get("sword", -1)) == 10 and int(sword_delta.get("cultivation", -1)) == 6, "the completed motion records the one-use cultivation bonus in its real receipt")
	check(not bool(state.get("flags", {}).get("breathing_hint", true)) and bool(state.get("flags", {}).get("mentor_practice_finished", false)), "the actual sword consumes the hint and unlocks the report")
	check(_voice_is_stopped(), "voice remains stopped when the motion result is shown")
	await _capture("06_mountain_result.png", "actual completed mountain action result")
	if not await _click("SaveButton"):
		return false
	var sword_checkpoint: Dictionary = _state()
	check(sword_checkpoint.get("phase", "") == "result" and not _button_disabled("LoadButton"), "the completed action result is a real UI save boundary")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_return_to_corridor"):
		return false
	if not await _click("ResultContinueButton"):
		return false
	var report_voice_before: int = int(_voice_audit().get("play_count", 0))
	if not await _click("ActorButton_mentor_zhixian"):
		return false
	state = _state()
	check(state.get("event", {}).get("node", "") == "report_question" and _visible_label_contains("方才那套剑，练得如何？"), "the corridor displays the authored report question after practice")
	var with_lesson: Button = await _fresh_button("ChoiceButton_with_lesson")
	var self_practice: Button = await _fresh_button("ChoiceButton_self_practice")
	check(with_lesson != null and not with_lesson.disabled and self_practice != null and self_practice.disabled, "the report exposes only the branch matching the accepted lesson")
	check(int(_voice_audit().get("play_count", 0)) == report_voice_before + 1, "the mentor portrait opens the report and starts its question voice once")
	await _capture("07_report_question.png", "report question with the accepted-lesson branch enabled")
	if not await _click("ChoiceButton_with_lesson"):
		return false
	check(int(_voice_audit().get("play_count", 0)) == report_voice_before + 2, "the accepted report branch starts its voiced response")
	if not await _click("DialogContinueButton"):
		return false
	if not await _click("DialogContinueButton"):
		return false
	check(int(_voice_audit().get("play_count", 0)) == report_voice_before + 3, "the mentor's report reply starts once before the unvoiced ending")
	check(_state().get("event", {}).get("node", "") == "end" and not bool(_state().get("flags", {}).get("mentor_reported", true)), "report progress remains pending until the explicit ending is continued")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("phase", "") == "result" and bool(state.get("flags", {}).get("mentor_reported", false)), "the report ending commits its completion flag")
	check(_voice_is_stopped(), "the current report voice stops on its result screen")
	await _capture("08_report_result_saved.png", "completed report result checkpoint")
	if not await _click("SaveButton"):
		return false
	var saved_report: Dictionary = _state()
	if not await _click("ResultContinueButton"):
		return false
	for rest_index: int in range(4):
		if not await _click("ActionButton_rest_practice"):
			return false
		state = _state()
		check(state.get("phase", "") == "result", "rest %d settles through the real corridor action button" % (rest_index + 1))
		if rest_index < 3 and not await _click("ResultContinueButton"):
			return false
	state = _state()
	check(int(state.get("day", -1)) == 2 and int(state.get("slot", -1)) == 0, "four real rests carry the clock across the day boundary")
	await _capture("09_rest_day_two.png", "day-two rest result before restoring the saved report")
	if not await _click("LoadButton"):
		return false
	check(_has_control("ConfirmAcceptButton") and _has_control("ConfirmCancelButton"), "loading the earlier report checkpoint asks before replacing the run")
	if not await _click("ConfirmAcceptButton"):
		return false
	if not await _wait_for_snapshot(saved_report, 90):
		check(false, "the actual load control restores the saved report checkpoint")
		return false
	state = _state()
	check(state == saved_report and state.get("phase", "") == "result" and state.get("scene", "") == "tingyu_corridor", "load restores exact scene, time, stats, flags, receipts and result")
	check(_voice_is_stopped() and not bool(_presentation().get("playing", false)), "restoring a result does not resume dialogue audio or sword motion")
	await _capture("10_report_checkpoint_restored.png", "saved report result restored after rest and day rollover")
	if not await _click("SwitchPackButton"):
		return false
	var left_voice: Dictionary = _voice_audit()
	check(_audit().get("view_mode", "") == "library" and not bool(left_voice.get("playing", false)) and str(left_voice.get("current_id", "")).is_empty(), "leaving the voiced pack for the library stops and clears its active clip")
	return true


func _continue_until_node(target_node: String, expected_current_nodes: Array[String], first_play_count: int) -> bool:
	var expected_play_count: int = first_play_count
	for node_id: String in expected_current_nodes:
		if str(_state().get("event", {}).get("node", "")) != node_id:
			check(false, "expected dialogue node %s before continuing" % node_id)
			return false
		check(int(_voice_audit().get("play_count", 0)) == expected_play_count, "voiced dialogue node %s plays exactly once" % node_id)
		if not await _click("DialogContinueButton"):
			return false
		expected_play_count += 1
	check(str(_state().get("event", {}).get("node", "")) == target_node, "dialogue advances to %s" % target_node)
	check(int(_voice_audit().get("play_count", 0)) == expected_play_count, "the target voiced choice starts without replaying earlier lines")
	return true


func _wait_for_phase(phase: String, _max_frames: int) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if str(_state().get("phase", "")) == phase:
			return true
		await process_frame
	return str(_state().get("phase", "")) == phase


func _wait_for_snapshot(expected: Dictionary, max_frames: int) -> bool:
	for _frame: int in range(max_frames):
		if _state() == expected:
			return true
		await process_frame
	return _state() == expected


func _parse_user_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < args.size():
		var argument: String = args[index]
		if argument == "--qa-size" and index + 1 < args.size():
			index += 1
			_parse_size(args[index])
		elif argument.begins_with("--qa-size="):
			_parse_size(argument.trim_prefix("--qa-size="))
		elif argument == "--output" and index + 1 < args.size():
			index += 1
			output_dir = args[index]
		elif argument.begins_with("--output="):
			output_dir = argument.trim_prefix("--output=")
		index += 1


func _parse_size(value: String) -> void:
	var parts: PackedStringArray = value.to_lower().split("x")
	if parts.size() != 2:
		push_error("--qa-size must use WIDTHxHEIGHT, received: " + value)
		failures += 1
		return
	var requested: Vector2i = Vector2i(int(parts[0]), int(parts[1]))
	if not ALLOWED_QA_SIZES.has(requested):
		push_error("--qa-size must be 1152x720 or 960x600, received: " + value)
		failures += 1
		return
	qa_size = requested


func _allocate_store_dir() -> String:
	for attempt: int in range(20):
		var candidate: String = "user://cultivation_engine_mentor_loop_render_%d_%d" % [Time.get_ticks_usec(), attempt]
		var absolute_path: String = ProjectSettings.globalize_path(candidate)
		if not DirAccess.dir_exists_absolute(absolute_path) and not FileAccess.file_exists(candidate):
			return candidate
	return ""


func _absolute_output_dir() -> String:
	if output_dir.begins_with("res://") or output_dir.begins_with("user://"):
		return ProjectSettings.globalize_path(output_dir)
	return output_dir


func _click(control_name: String) -> bool:
	var control: Control = await _fresh_control(control_name)
	if control == null:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		check(false, "real UI control %s is enabled before clicking" % control_name)
		return false
	await _ensure_control_visible(control)
	control = await _fresh_control(control_name)
	if control == null:
		return false
	var prior_rect: Rect2 = Rect2()
	var stable_frames: int = 0
	for _frame: int in range(30):
		await process_frame
		var current_rect: Rect2 = control.get_global_rect()
		stable_frames = stable_frames + 1 if current_rect == prior_rect and current_rect.size.x > 0.0 else 0
		prior_rect = current_rect
		if stable_frames >= 3:
			break
	if control is BaseButton and (control as BaseButton).disabled:
		check(false, "real UI control %s remains enabled after scrolling into view" % control_name)
		return false
	var point: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
	var fired: Array[bool] = [false]
	if control is BaseButton:
		(control as BaseButton).pressed.connect(func() -> void: fired[0] = true, CONNECT_ONE_SHOT)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame
	check(fired[0], "root.push_input dispatches actual mouse input to %s" % control_name)
	if not fired[0]:
		return false
	await process_frame
	await process_frame
	return true


func _fresh_control(control_name: String) -> Control:
	for _frame: int in range(CONTROL_WAIT_FRAMES):
		if app != null and is_instance_valid(app):
			var candidate: Variant = app.call("ui_control", control_name)
			if candidate is Control and is_instance_valid(candidate) and (candidate as Control).is_visible_in_tree():
				return candidate as Control
		await process_frame
	check(false, "visible real UI control %s appears within the bounded wait" % control_name)
	return null


func _fresh_button(control_name: String) -> Button:
	var control: Control = await _fresh_control(control_name)
	if control is Button:
		return control as Button
	if control != null:
		check(false, "real UI control %s is a Button" % control_name)
	return null


func _ensure_control_visible(control: Control) -> void:
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(control)
		parent = parent.get_parent()
	await process_frame
	await process_frame


func _check_layout(label: String, core_names: Array[String]) -> void:
	await process_frame
	await process_frame
	var viewport_size: Vector2i = Vector2i(app.get_viewport_rect().size.round())
	check(viewport_size == LOGICAL_SIZE, "%s uses the 1440x900 logical viewport" % label)
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(LOGICAL_SIZE))
	for control_name: String in core_names:
		var control: Variant = app.call("ui_control", control_name)
		if not control is Control or not is_instance_valid(control) or not (control as Control).is_visible_in_tree():
			check(false, "%s exposes visible core control %s" % [label, control_name])
			continue
		var current: Control = control as Control
		var rect: Rect2 = current.get_global_rect()
		check(rect.size.x > 0.0 and rect.size.y > 0.0, "%s lays out core control %s" % [label, control_name])
		if not _has_scroll_ancestor(current):
			check(bounds.encloses(rect), "%s keeps core control %s inside the logical viewport" % [label, control_name])


func _has_scroll_ancestor(control: Control) -> bool:
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


func _has_control(control_name: String) -> bool:
	if app == null or not is_instance_valid(app):
		return false
	var candidate: Variant = app.call("ui_control", control_name)
	return candidate is Control and is_instance_valid(candidate) and (candidate as Control).is_visible_in_tree()


func _button_disabled(control_name: String) -> bool:
	var candidate: Variant = app.call("ui_control", control_name) if app != null and is_instance_valid(app) else null
	if candidate is BaseButton and is_instance_valid(candidate):
		return (candidate as BaseButton).disabled
	check(false, "%s exposes its real button state" % control_name)
	return true


func _visible_label_contains(fragment: String) -> bool:
	var label: Label = _find_label(app, fragment)
	return label != null and label.is_visible_in_tree() and label.get_global_rect().intersects(Rect2(Vector2.ZERO, Vector2(LOGICAL_SIZE)))


func _find_label(node: Node, fragment: String) -> Label:
	if node == null:
		return null
	if node is Label and (node as Label).text.contains(fragment):
		return node as Label
	for child: Node in node.get_children():
		var found: Label = _find_label(child, fragment)
		if found != null:
			return found
	return null


func _state() -> Dictionary:
	var value: Variant = _audit().get("state", {})
	return value as Dictionary if value is Dictionary else {}


func _audit() -> Dictionary:
	if app == null or not is_instance_valid(app):
		return {}
	var value: Variant = app.call("audit_snapshot")
	return value as Dictionary if value is Dictionary else {}


func _voice_audit() -> Dictionary:
	var value: Variant = _audit().get("voice", {})
	return value as Dictionary if value is Dictionary else {}


func _voice_is_stopped() -> bool:
	var voice: Dictionary = _voice_audit()
	return not bool(voice.get("playing", true)) and str(voice.get("current_id", "")).is_empty()


func _presentation() -> Dictionary:
	var value: Variant = _audit().get("presentation", {})
	return value as Dictionary if value is Dictionary else {}


func _pack_id() -> String:
	return str(_audit().get("pack_id", ""))


func _capture(filename: String, description: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var prefix: String = "%dx%d_" % [qa_size.x, qa_size.y]
	var full_path: String = _absolute_output_dir().path_join(prefix + filename)
	var save_result: Error = image.save_png(full_path)
	check(save_result == OK, "native capture is written: " + filename)
	check(image.get_size() == qa_size, "capture is at the requested native window size: " + filename)
	captures.append({
		"file": prefix + filename,
		"description": description,
		"pixels": [image.get_width(), image.get_height()],
		"pack_id": _pack_id(),
		"phase": str(_state().get("phase", "")),
		"scene": str(_state().get("scene", "")),
		"voice": _voice_audit().duplicate(true),
		"presentation": _presentation().duplicate(true),
	})


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		failure_messages.append(message)
		push_error("FAIL: " + message)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	var report: Dictionary = {
		"test": "cultivation_engine_mentor_loop_render",
		"checks": checks,
		"failures": failures,
		"failure_messages": failure_messages,
		"qa_size": [qa_size.x, qa_size.y],
		"logical_size": [LOGICAL_SIZE.x, LOGICAL_SIZE.y],
		"display_server": DisplayServer.get_name(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"captures": captures,
	}
	var report_path: String = _absolute_output_dir().path_join("cultivation-engine-mentor-loop-render-report.json")
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		failures += 1
		push_error("Could not write mentor-loop render report: " + report_path)
	else:
		report["failures"] = failures
		report["result"] = "PASS" if failures == 0 else "FAIL"
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.flush()
		if file.get_error() != OK:
			failures += 1
			push_error("Mentor-loop render report write failed: " + report_path)
		file.close()
	print("CULTIVATION_ENGINE_MENTOR_LOOP_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)


func _cleanup_store_dir() -> void:
	if test_store_dir.is_empty():
		return
	_cleanup_tree(ProjectSettings.globalize_path(test_store_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_store_dir))


func _cleanup_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for dirname: String in directory.get_directories():
		_cleanup_tree(path.path_join(dirname))
		DirAccess.remove_absolute(path.path_join(dirname))
