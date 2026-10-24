extends SceneTree

const DemoScene := preload("res://scenes/demos/cultivation_engine_v02.tscn")
const DEFAULT_OUTPUT := "res://.local/qa/cultivation-engine-v02/render"
const LOGICAL_SIZE := Vector2i(1440, 900)
const ALLOWED_QA_SIZES := [Vector2i(1152, 720), Vector2i(960, 600)]
const CONTROL_WAIT_FRAMES := 90
const BUSY_ACTION_IDS := [
	"pine_wind", "listening_rain", "returning_tide", "rising_peak", "swift_swallow",
	"train_mountain", "rest_practice", "return_to_corridor"
]
const MOTIONS := [
	{"action": "pine_wind", "clip": "songfeng", "label": "松风剑"},
	{"action": "listening_rain", "clip": "chuanyun", "label": "穿云剑"},
	{"action": "returning_tide", "clip": "huilan", "label": "回澜剑"},
	{"action": "rising_peak", "clip": "tiaoyue", "label": "挑月剑"},
	{"action": "swift_swallow", "clip": "xieying", "label": "斜影剑"}
]

var app: Control
var output_dir: String = DEFAULT_OUTPUT
var _store_dir: String = ""
var qa_size: Vector2i = Vector2i(1152, 720)
var checks: int = 0
var failures: int = 0
var captures: Array[Dictionary] = []
var failure_messages: Array[String] = []
var _finished: bool = false
var _seen_attack_clips: Dictionary = {}
var _seen_attack_pages: Dictionary = {}
var _shu_checkpoint: Dictionary = {}
var _stream_checkpoint: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Keep native QA input/frame waits comparable across offscreen vsync modes.
	# Animation still advances only by the engine's real delta, never a test clock.
	Engine.max_fps = 60
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	var mkdir_result: Error = DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(mkdir_result == OK or mkdir_result == ERR_ALREADY_EXISTS, "the isolated render output directory is available")
	check(DisplayServer.get_name() != "headless", "the v0.2 render harness has a native display server")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = DemoScene.instantiate() as Control
	if app == null:
		check(false, "the v0.2 demo instantiates as a Control")
		_finish()
		return
	root.add_child(app)
	await process_frame
	await process_frame
	var store: Variant = app.get("_store")
	check(store != null, "the v0.2 view initializes its local SaveStore")
	if store == null:
		_finish()
		return
	_store_dir = _allocate_store_dir()
	if _store_dir.is_empty():
		check(false, "an unused per-run save directory is available")
		_finish()
		return
	store.set("base_dir", _store_dir)
	check(str(store.get("base_dir")) == _store_dir, "render journey saves use an isolated per-run directory")
	await process_frame
	if not await _click("PackSelectButton_0"):
		_finish()
		return
	await _capture("00_library.png", "two-pack library before the native journey")
	if not await _click("PackStartButton_0"):
		_finish()
		return
	if not await _run_shu_journey():
		_finish()
		return
	if not await _run_stream_journey():
		_finish()
		return
	if not await _verify_independent_pack_checkpoints():
		_finish()
		return
	check(_seen_attack_clips.size() == 5, "all five approved clips produced an in-phase native capture")
	check(_seen_attack_pages.size() == 5, "each captured attack loaded its distinct approved atlas page")
	_finish()


func _run_shu_journey() -> bool:
	var state: Dictionary = _state()
	check(_pack_id() == "shu_entry", "real pack-start input opens shu_entry")
	check(str(state.get("phase", "")) == "ready" and str(state.get("scene", "")) == "tingyu_corridor", "shu starts in its authored corridor scene")
	await _capture("01_shu_corridor.png", "shu corridor before mountain travel")
	if not await _click("ActionButton_go_to_mountain"):
		return false
	state = _state()
	check(str(state.get("phase", "")) == "result" and str(state.get("scene", "")) == "back_mountain", "actual travel input enters the mountain result")
	if not await _click("ResultContinueButton"):
		return false
	state = _state()
	check(str(state.get("phase", "")) == "ready" and str(state.get("scene", "")) == "back_mountain", "result continuation exposes the mountain action panel")
	await _capture("02_mountain_ready.png", "mountain scene with idle sword actor")
	await _check_layout("mountain ready", ["HeaderPanel", "SwitchPackButton", "SaveButton", "LoadButton", "NewRunButton", "ScenePanel", "PhasePanel", "ActionScroll"])
	if not await _click("SaveButton"):
		return false
	check(not _button_disabled("LoadButton"), "a real baseline save makes the load control otherwise available for the busy guard probe")

	# The first full sword run is checkpointed at its completed result. A later
	# real rest action mutates the run; loading must restore this exact result.
	var first: Dictionary = MOTIONS[0]
	if not await _start_and_finish_motion(first, 1, true):
		return false
	_shu_checkpoint = _state().duplicate(true)
	if not await _click("SaveButton"):
		return false
	check(_state() == _shu_checkpoint, "saving a completed sword result preserves the exact state snapshot")
	check(not _button_disabled("LoadButton"), "the completed sword result enables the shu load control")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_rest_practice"):
		return false
	state = _state()
	check(str(state.get("phase", "")) == "result" and int(state.get("stats", {}).get("energy", -1)) == 100, "a real rest action mutates the saved run after the sword result")
	if not await _click("LoadButton"):
		return false
	check(_has_control("ConfirmAcceptButton") and _has_control("ConfirmCancelButton"), "loading the sword checkpoint asks before replacing the mutated run")
	await _capture("03_shu_load_confirmation.png", "restore confirmation over a later rest result")
	if not await _click("ConfirmAcceptButton"):
		return false
	if not await _wait_for_snapshot(_shu_checkpoint, 120):
		check(false, "loading returns to the saved sword result")
		return false
	state = _state()
	var restored_presentation: Dictionary = _presentation()
	check(str(state.get("phase", "")) == "result" and state == _shu_checkpoint, "load restores identical sword counts, receipt, time, resources and run state")
	check(not bool(restored_presentation.get("playing", true)) and bool(restored_presentation.get("neutral", false)) and str(restored_presentation.get("phase", "")) == "idle", "restoring a result never resumes or replays its finished motion")
	await _capture("04_shu_restored_result.png", "saved sword result restored without playback")
	if not await _click("ResultContinueButton"):
		return false

	# The remaining actions run on the same actual UI journey, with ordinary
	# rest selected when the authored energy cost requires it.
	for index: int in range(1, MOTIONS.size()):
		if int(_state().get("stats", {}).get("energy", 0)) < 22:
			if not await _click("ActionButton_rest_practice"):
				return false
			state = _state()
			check(str(state.get("phase", "")) == "result" and int(state.get("stats", {}).get("energy", 0)) > 22, "real rest restores enough energy for the next full sword motion")
			if not await _click("ResultContinueButton"):
				return false
		var motion_number: int = index + 1
		if not await _start_and_finish_motion(MOTIONS[index], motion_number, false):
			return false
		if index < MOTIONS.size() - 1:
			if not await _click("ResultContinueButton"):
				return false

	state = _state()
	var counts: Dictionary = state.get("counts", {})
	for row: Dictionary in MOTIONS:
		check(int(counts.get(str(row.action), 0)) == 1, "%s settled exactly once in the real five-motion journey" % str(row.action))
	check(str(state.get("phase", "")) == "result" and int(state.get("stats", {}).get("sword", -1)) == 50, "five completed motions settle five sword gains and finish at a result")
	await _capture("10_five_swords_result.png", "five full motions and one settlement each")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_return_to_corridor"):
		return false
	state = _state()
	check(str(state.get("phase", "")) == "result" and str(state.get("scene", "")) == "tingyu_corridor", "the explicit return action reaches the corridor after all motions")
	await _capture("11_corridor_return_result.png", "result after explicitly returning from the mountain")
	if not await _click("ResultContinueButton"):
		return false
	check(str(_state().get("phase", "")) == "ready", "acknowledging the return result leaves a normal ready session")
	return true


func _start_and_finish_motion(row: Dictionary, motion_number: int, save_busy_probes: bool) -> bool:
	var action_id: String = str(row.get("action", ""))
	var clip_id: String = str(row.get("clip", ""))
	var before: Dictionary = _state()
	var before_energy: int = int(before.get("stats", {}).get("energy", -1))
	var before_sword: int = int(before.get("stats", {}).get("sword", -1))
	var before_slot: int = int(before.get("slot", -1))
	var before_day: int = int(before.get("day", -1))
	if not await _click("ActionButton_" + action_id):
		return false
	var state: Dictionary = _state()
	check(str(state.get("phase", "")) == "performing", "%s enters performing after a real UI click" % action_id)
	check(int(state.get("counts", {}).get(action_id, 0)) == 1, "%s count settles exactly once before animation completion" % action_id)
	check(int(state.get("stats", {}).get("energy", -1)) == before_energy - 22 and before_energy >= 22, "%s spends its configured energy at action acceptance" % action_id)
	check(int(state.get("stats", {}).get("sword", -1)) == before_sword + 10 and before_sword == (motion_number - 1) * 10, "%s applies one configured sword gain at action acceptance" % action_id)
	var expected_slot: int = (before_slot + 1) % 6
	var expected_day: int = before_day + (1 if before_slot + 1 >= 6 else 0)
	check(int(state.get("slot", -1)) == expected_slot and int(state.get("day", -1)) == expected_day, "%s advances exactly one authored time slot at action acceptance" % action_id)
	if not await _wait_for_attack_capture(row, "%02d_attack_%s.png" % [motion_number + 4, action_id]):
		return false
	if save_busy_probes:
		if not await _probe_busy_controls():
			return false
	if not await _wait_for_motion_completion(action_id):
		return false
	state = _state()
	var receipt: Dictionary = state.get("last_result", {})
	var delta: Dictionary = receipt.get("delta", {})
	check(str(state.get("phase", "")) == "result", "%s completes only after the player's neutral finish" % action_id)
	check(int(state.get("stats", {}).get("energy", -1)) == before_energy - 22 and int(delta.get("slots", -1)) == 1, "%s receipt contains the one authored cost and duration" % action_id)
	check(int(delta.get("stats", {}).get("sword", -1)) == 10 and int(state.get("counts", {}).get(action_id, 0)) == 1 and int(state.get("stats", {}).get("sword", -1)) == motion_number * 10, "%s receipt and cumulative sword total remain single-settlement" % action_id)
	check(not bool(_presentation().get("playing", true)) and bool(_presentation().get("neutral", false)), "%s returns naturally to neutral idle before the result is shown" % action_id)
	await _capture("%02d_result_%s.png" % [motion_number + 4, action_id], "%s completed result" % str(row.get("label", action_id)))
	return true


func _probe_busy_controls() -> bool:
	var actor := app.get("_presentation_player") as Node
	var was_processing := is_instance_valid(actor) and actor.is_processing()
	if is_instance_valid(actor):
		actor.set_process(false)
	var passed := await _probe_busy_controls_held()
	if is_instance_valid(actor):
		actor.set_process(was_processing)
	return passed


func _probe_busy_controls_held() -> bool:
	var before: Dictionary = _state().duplicate(true)
	for control_name: String in ["SaveButton", "LoadButton", "NewRunButton", "SwitchPackButton"]:
		if not await _attempt_disabled_click(control_name, before):
			return false
	for action_id: String in BUSY_ACTION_IDS:
		if not _has_control("ActionButton_" + action_id):
			continue
		if not await _attempt_disabled_click("ActionButton_" + action_id, before):
			return false
	check(not _has_control("ResultContinueButton"), "no result continuation is exposed while a motion is performing")
	check(_state() == before, "all disabled busy-control clicks leave the performing transaction unchanged")
	return true


func _attempt_disabled_click(control_name: String, expected_state: Dictionary) -> bool:
	var control: Control = await _fresh_control(control_name)
	if control == null:
		return false
	if not control is BaseButton:
		check(false, "%s is an input button during performing" % control_name)
		return false
	var button: BaseButton = control as BaseButton
	check(button.disabled, "%s is disabled during performing" % control_name)
	if not button.disabled:
		return false
	await _ensure_control_visible(button)
	control = await _fresh_control(control_name)
	if control == null or not control is BaseButton:
		return false
	button = control as BaseButton
	var fired: Array[bool] = [false]
	var callback: Callable = func() -> void: fired[0] = true
	button.pressed.connect(callback)
	await _push_mouse_click(button)
	if is_instance_valid(button) and button.pressed.is_connected(callback):
		button.pressed.disconnect(callback)
	check(not fired[0], "%s ignores a real click while disabled" % control_name)
	check(_state() == expected_state, "%s click changes no session state" % control_name)
	return not fired[0] and _state() == expected_state


func _wait_for_attack_capture(row: Dictionary, filename: String) -> bool:
	var action_id: String = str(row.get("action", ""))
	var clip_id: String = str(row.get("clip", ""))
	var deadline: int = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		var presentation: Dictionary = _presentation()
		if bool(presentation.get("playing", false)) and not bool(presentation.get("neutral", true)) and str(presentation.get("phase", "")) == "action" and str(presentation.get("phase_label", "")) == "出剑" and str(presentation.get("clip_id", "")) == clip_id:
			var capture_index: int = captures.size()
			await _capture(filename, "%s attack phase %s" % [action_id, str(presentation.get("phase_label", ""))])
			var captured: Dictionary = captures[capture_index] if capture_index < captures.size() else {}
			check(str(captured.get("clip_id", "")) == clip_id and str(captured.get("phase_label", "")) == "出剑", "%s attack capture records the expected clip and phase" % action_id)
			var paths: Array = captured.get("loaded_action_atlas_paths", [])
			check(not paths.is_empty(), "%s attack capture has a loaded action atlas" % action_id)
			if not paths.is_empty():
				_seen_attack_clips[clip_id] = true
				_seen_attack_pages[str(paths[0])] = true
			return true
		await process_frame
	check(false, "%s reaches its distinct authored attack phase before timeout; last=%s" % [action_id, JSON.stringify(_presentation())])
	return false


func _wait_for_motion_completion(action_id: String) -> bool:
	var saw_playing: bool = false
	var saw_attack: bool = false
	var deadline: int = Time.get_ticks_msec() + 18000
	while Time.get_ticks_msec() < deadline:
		var presentation: Dictionary = _presentation()
		if bool(presentation.get("playing", false)):
			saw_playing = true
			if str(presentation.get("phase", "")) == "action":
				saw_attack = true
		else:
			var state: Dictionary = _state()
			if saw_playing and saw_attack and bool(presentation.get("neutral", false)) and str(state.get("phase", "")) == "result":
				check(true, "%s played through action frames and returned to idle before result" % action_id)
				return true
		await process_frame
	check(false, "%s completes a full playing/action/neutral cycle within the bounded wait" % action_id)
	return false


func _run_stream_journey() -> bool:
	if not await _click("SwitchPackButton"):
		return false
	if not await _click("PackStartButton_1"):
		return false
	if _has_control("ConfirmAcceptButton"):
		if not await _click("ConfirmAcceptButton"):
			return false
	var state: Dictionary = _state()
	check(_pack_id() == "stream_study" and str(state.get("scene", "")) == "tea_pavilion", "real pack replacement opens the unchanged stream study")
	check(not _presentation().has("clip_id") and not bool(_presentation().get("playing", false)), "the stream scene has no sword player or active clip")
	await _capture("20_stream_initial.png", "unchanged static stream study opening")
	if not await _click("ActionButton_walk_to_river"):
		return false
	state = _state()
	check(str(state.get("phase", "")) == "result" and str(state.get("scene", "")) == "riverbank", "stream travel remains the immediate text-only result flow")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_read_by_river"):
		return false
	state = _state()
	var stream_receipt: Dictionary = state.get("last_result", {})
	check(str(state.get("phase", "")) == "result" and int(state.get("stats", {}).get("insight", -1)) == 8, "stream reading applies its ordinary immediate insight settlement")
	check(int(stream_receipt.get("delta", {}).get("stats", {}).get("insight", -1)) == 8, "the stream reading receipt retains the authored gain")
	check(not state.get("stats", {}).has("sword") and _presentation().is_empty(), "stream study has no sword stat, pending clip or motion player")
	_stream_checkpoint = state.duplicate(true)
	if not await _click("SaveButton"):
		return false
	check(_state() == _stream_checkpoint and not _button_disabled("LoadButton"), "stream save creates its own result checkpoint without player state")
	await _capture("21_stream_read_result.png", "static reading result saved independently")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_pause_by_stream"):
		return false
	state = _state()
	check(str(state.get("phase", "")) == "result" and state != _stream_checkpoint, "a later stream pause mutates only the active stream run")
	if not await _click("LoadButton"):
		return false
	if not await _click("ConfirmAcceptButton"):
		return false
	if not await _wait_for_snapshot(_stream_checkpoint, 120):
		check(false, "the stream pack reloads its own exact saved result")
		return false
	state = _state()
	check(_pack_id() == "stream_study" and state == _stream_checkpoint, "stream load restores exact counts, last_result, receipt and static state")
	check(_presentation().is_empty(), "stream load remains static and cannot replay a sword animation")
	await _capture("22_stream_restored_result.png", "stream result restored from its independent checkpoint")
	return true


func _verify_independent_pack_checkpoints() -> bool:
	if not await _click("SwitchPackButton"):
		return false
	var shu_continue: Button = await _fresh_button("PackContinueButton_0")
	var stream_continue: Button = await _fresh_button("PackContinueButton_1")
	check(shu_continue != null and not shu_continue.disabled and stream_continue != null and not stream_continue.disabled, "library exposes independent continue slots after both packs save")
	if not await _click("PackContinueButton_0"):
		return false
	if _has_control("ConfirmAcceptButton"):
		if not await _click("ConfirmAcceptButton"):
			return false
	if not await _wait_for_snapshot(_shu_checkpoint, 120):
		check(false, "stream save did not overwrite shu checkpoint")
		return false
	check(_pack_id() == "shu_entry" and _state() == _shu_checkpoint, "continue restores the exact saved shu sword result after stream save")
	if not await _click("SwitchPackButton"):
		return false
	if not await _click("PackContinueButton_1"):
		return false
	if _has_control("ConfirmAcceptButton"):
		if not await _click("ConfirmAcceptButton"):
			return false
	if not await _wait_for_snapshot(_stream_checkpoint, 120):
		check(false, "shu save did not overwrite stream checkpoint")
		return false
	check(_pack_id() == "stream_study" and _state() == _stream_checkpoint, "continue restores the exact independent stream result after shu load")
	return true


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
			_parse_size(str(args[index + 1]))
			index += 1
		elif argument.begins_with("--qa-size="):
			_parse_size(argument.trim_prefix("--qa-size="))
		elif argument == "--output" and index + 1 < args.size():
			output_dir = str(args[index + 1])
			index += 1
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
		var candidate: String = "user://cultivation_engine_v02_render_%d_%d" % [Time.get_ticks_usec(), attempt]
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
		check(false, "real UI button %s is enabled before clicking" % control_name)
		return false
	await _ensure_control_visible(control)
	control = await _fresh_control(control_name)
	if control == null:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		check(false, "real UI button %s remains enabled after scrolling into view" % control_name)
		return false
	for _frame: int in range(30):
		await process_frame
	# Scene replacement and scroll layout can retire the earlier Control. Resolve
	# it again, then require a stable hit rectangle before a single real click.
	var prior_rect: Rect2 = Rect2()
	var stable_frames: int = 0
	for _frame: int in range(CONTROL_WAIT_FRAMES):
		control = await _fresh_control(control_name)
		if control == null:
			return false
		var rect: Rect2 = control.get_global_rect()
		stable_frames = stable_frames + 1 if rect == prior_rect else 0
		prior_rect = rect
		if stable_frames >= 3:
			break
		await process_frame
	check(stable_frames >= 3, "real UI hit rectangle stabilizes for " + control_name)
	if stable_frames < 3:
		return false
	var fired: Array[bool] = [false]
	var callback: Callable = func() -> void: fired[0] = true
	if control is BaseButton:
		(control as BaseButton).pressed.connect(callback, CONNECT_ONE_SHOT)
	await _push_mouse_click(control)
	check(fired[0], "root.push_input dispatches real mouse input to " + control_name)
	if not fired[0]:
		await _capture("input_failure_%s.png" % control_name, "single-click failure after stable layout: " + control_name)
		return false
	await process_frame
	await process_frame
	return true


func _push_mouse_click(control: Control) -> void:
	var canvas_point: Vector2 = control.get_global_transform_with_canvas() * (control.size * 0.5)
	var point: Vector2 = root.get_final_transform() * canvas_point
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	var hovered: Control = root.gui_get_hovered_control()
	if hovered != control and not (is_instance_valid(hovered) and control.is_ancestor_of(hovered)):
		print("INPUT_HIT_TRACE ", JSON.stringify({"wanted":str(control.get_path()),"rect":str(control.get_global_rect()),"point":str(point),"hovered":str(hovered.get_path()) if is_instance_valid(hovered) else "none"}))
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
	# Keep one complete gesture together so a native mouse-exit notification
	# cannot retire hover state between the synthetic press and release.
	await process_frame


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
		check(false, "%s is a Button" % control_name)
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
	check(viewport_size == LOGICAL_SIZE, "%s uses the fixed 1440x900 logical viewport" % label)
	var logical_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(LOGICAL_SIZE))
	for control_name: String in core_names:
		var control: Variant = app.call("ui_control", control_name)
		if not control is Control or not is_instance_valid(control) or not (control as Control).is_visible_in_tree():
			check(false, "%s exposes visible core control %s" % [label, control_name])
			continue
		var rect: Rect2 = (control as Control).get_global_rect()
		check(rect.size.x > 0.0 and rect.size.y > 0.0, "%s lays out core control %s" % [label, control_name])
		if not _has_scroll_ancestor(control as Control):
			check(logical_bounds.encloses(rect), "%s keeps core control %s inside the logical viewport" % [label, control_name])


func _has_scroll_ancestor(control: Control) -> bool:
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return true
		ancestor = ancestor.get_parent()
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
	check(false, "%s exposes its real button disabled state" % control_name)
	return true


func _state() -> Dictionary:
	var value: Variant = _audit().get("state", {})
	return value as Dictionary if value is Dictionary else {}


func _audit() -> Dictionary:
	if app == null or not is_instance_valid(app):
		return {}
	var value: Variant = app.call("audit_snapshot")
	return value as Dictionary if value is Dictionary else {}


func _presentation() -> Dictionary:
	var value: Variant = _audit().get("presentation", {})
	return value as Dictionary if value is Dictionary else {}


func _pack_id() -> String:
	return str(_audit().get("pack_id", ""))


func _capture(filename: String, description: String) -> void:
	# Hold only the presentation clock across GPU readback, so pixels and phase
	# metadata describe the same pose. Gameplay state is never modified here.
	var actor := app.get("_presentation_player") as Node
	var was_processing := is_instance_valid(actor) and actor.is_processing()
	if is_instance_valid(actor):
		actor.set_process(false)
	await process_frame
	# A held pose can leave no dirty canvas item, so request a synchronous draw
	# instead of waiting for an automatic frame that may never be submitted.
	RenderingServer.force_draw(false)
	var image: Image = root.get_texture().get_image()
	var prefix: String = "%dx%d_" % [qa_size.x, qa_size.y]
	var full_path: String = _absolute_output_dir().path_join(prefix + filename)
	var save_result: Error = image.save_png(full_path)
	check(save_result == OK, "native capture is written: " + filename)
	check(image.get_size() == qa_size, "capture is at requested native window size: " + filename)
	var presentation: Dictionary = _presentation()
	var state: Dictionary = _state()
	captures.append({
		"file": prefix + filename,
		"description": description,
		"pixels": [image.get_width(), image.get_height()],
		"pack_id": _pack_id(),
		"phase": str(state.get("phase", "")),
		"scene": str(state.get("scene", "")),
		"action_id": str(state.get("last_result", {}).get("action_id", "")),
		"clip_id": str(presentation.get("clip_id", "")),
		"phase_label": str(presentation.get("phase_label", "")),
		"frame": int(presentation.get("frame", -1)),
		"playing": bool(presentation.get("playing", false)),
		"neutral": bool(presentation.get("neutral", false)),
		"loaded_action_atlas_paths": presentation.get("loaded_action_atlas_paths", []).duplicate(true)
	})
	if is_instance_valid(actor):
		actor.set_process(was_processing)


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
	var adapter: String = RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else ""
	var report: Dictionary = {
		"test": "cultivation_engine_motion_render",
		"checks": checks,
		"failures": failures,
		"failure_messages": failure_messages,
		"qa_size": [qa_size.x, qa_size.y],
		"logical_size": [LOGICAL_SIZE.x, LOGICAL_SIZE.y],
		"display_server": DisplayServer.get_name(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"adapter": adapter,
		"shu_checkpoint": _shu_checkpoint,
		"stream_checkpoint": _stream_checkpoint,
		"captures": captures,
		"seen_attack_clips": _seen_attack_clips.keys(),
		"seen_attack_pages": _seen_attack_pages.keys()
	}
	var report_path: String = _absolute_output_dir().path_join("cultivation-engine-motion-render-report.json")
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		failures += 1
		push_error("Could not write motion render report: " + report_path)
	else:
		report["failures"] = failures
		report["result"] = "PASS" if failures == 0 else "FAIL"
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.flush()
		if file.get_error() != OK:
			failures += 1
			push_error("Motion render report write failed: " + report_path)
		file.close()
	print("CULTIVATION_ENGINE_MOTION_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)


func _cleanup_store_dir() -> void:
	if _store_dir.is_empty():
		return
	var root_path: String = ProjectSettings.globalize_path(_store_dir)
	for pack_id: String in ["shu_entry", "stream_study"]:
		var pack_path: String = root_path.path_join(pack_id)
		for slot: int in range(2):
			for suffix: String in [".json", ".json.pending"]:
				var candidate: String = pack_path.path_join("checkpoint_%d%s" % [slot, suffix])
				if FileAccess.file_exists(candidate):
					DirAccess.remove_absolute(candidate)
		if DirAccess.dir_exists_absolute(pack_path):
			DirAccess.remove_absolute(pack_path)
	if DirAccess.dir_exists_absolute(root_path):
		DirAccess.remove_absolute(root_path)
	check(not DirAccess.dir_exists_absolute(root_path), "the test removes only its exact isolated temporary save files")
