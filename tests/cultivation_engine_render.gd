extends SceneTree

const DemoScene := preload("res://scenes/demos/cultivation_engine_v01.tscn")
const DEFAULT_OUTPUT := "res://.local/qa/cultivation-engine-v01/render"
const LOGICAL_SIZE := Vector2i(1440, 900)
const ALLOWED_QA_SIZES := [Vector2i(1152, 720), Vector2i(960, 600)]
const CONTROL_WAIT_FRAMES := 45

var app: Control
var output_dir := DEFAULT_OUTPUT
var qa_size := Vector2i(1152, 720)
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var check_records: Array[Dictionary] = []
var failure_messages: Array[String] = []
var _finished := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	var absolute_output := _absolute_output_dir()
	var mkdir_result := DirAccess.make_dir_recursive_absolute(absolute_output)
	check(mkdir_result == OK or mkdir_result == ERR_ALREADY_EXISTS, "the render output directory is available")
	var display_name := DisplayServer.get_name()
	check(display_name != "headless", "the render harness has a native display server")
	if display_name == "headless":
		_finish()
		return

	app = DemoScene.instantiate() as Control
	if app == null:
		check(false, "the cultivation demo scene instantiates as a Control")
		_finish()
		return
	root.add_child(app)
	await process_frame
	await process_frame
	var store: Variant = app.get("_store")
	check(store != null, "the demo has an initialized SaveStore")
	if store == null:
		_finish()
		return
	var isolated_store_dir := "user://engine_render_%d" % Time.get_ticks_usec()
	store.set("base_dir", isolated_store_dir)
	check(str(store.get("base_dir")) == isolated_store_dir, "all render-harness save operations use an isolated per-run directory")

	# Refresh the library through its real pack-selection button after the sandbox
	# path is installed, so the first screenshot and all later UI use isolated saves.
	if not await _click("PackSelectButton_0"):
		_finish()
		return
	await _capture("00_library.png", "isolated two-pack library")
	await _check_layout("library", ["HeaderPanel", "LibraryIntro", "PackCardsScroll"])
	if not await _click("PackStartButton_0"):
		_finish()
		return

	if not await _run_shu_flow():
		_finish()
		return
	if not await _run_stream_flow():
		_finish()
		return
	check(captures.size() == 18, "the native report contains eighteen named library, scene, dialogue, result and sandbox captures")
	_finish()


func _run_shu_flow() -> bool:
	var state := _state()
	check(_pack_id() == "shu_entry", "the first real UI start opens the shu_entry pack")
	check(state.get("scene", "") == "tingyu_corridor" and state.get("phase", "") == "ready", "shu starts ready in the corridor")
	var stats: Dictionary = state.get("stats", {})
	check(int(stats.get("energy", -1)) == 100 and int(stats.get("cultivation", -1)) == 0, "shu starts with 100 energy and zero cultivation")
	await _capture("01_shu_initial.png", "shu initial corridor")
	await _check_layout("shu initial scene", ["HeaderPanel", "SwitchPackButton", "SaveButton", "LoadButton", "NewRunButton", "StatsPanel", "GoalsPanel", "JournalPanel", "ScenePanel", "SceneDescription", "PhasePanel", "ActionScroll"])

	if not await _click("ActorButton_mentor_zhixian"):
		return false
	state = _state()
	check(state.get("phase", "") == "event" and state.get("event", {}).get("id", "") == "mentor_tip", "the real mentor portrait opens its authored event")
	check(state.get("event", {}).get("node", "") == "opening", "the mentor event begins at its opening line")
	check(_button_disabled("SaveButton"), "saving is disabled while the mentor event is active")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("event", {}).get("node", "") == "choice", "the real continue control advances the mentor event to its choice")
	check(_button_disabled("SaveButton"), "saving remains disabled at the mentor choice")
	var take_lesson: Button = await _fresh_button("ChoiceButton_take_lesson")
	var return_to_practice: Button = await _fresh_button("ChoiceButton_return_to_practice")
	check(take_lesson != null and not take_lesson.disabled, "the explicitly priced mentor lesson choice is available")
	check(return_to_practice != null and not return_to_practice.disabled, "the mentor choice includes an unconditional escape")
	await _capture("02_mentor_choice.png", "mentor dialogue choice")
	await _check_layout("mentor choice", ["HeaderPanel", "SwitchPackButton", "SaveButton", "LoadButton", "NewRunButton", "PhasePanel", "ScenePanel"])
	if not await _click("ChoiceButton_take_lesson"):
		return false
	state = _state()
	stats = state.get("stats", {})
	var flags: Dictionary = state.get("flags", {})
	check(int(stats.get("energy", -1)) == 92 and int(stats.get("understanding", -1)) == 1, "accepting the lesson spends eight energy and grants one understanding")
	check(int(state.get("slot", -1)) == 1 and bool(flags.get("breathing_hint", false)), "the lesson advances one slot and arms its pending hint")
	check(state.get("event", {}).get("node", "") == "lesson_taken", "the paid choice advances to its authored say node")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("event", {}).get("node", "") == "end", "the accepted lesson branch reaches its explicit end node")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("phase", "") == "result", "closing the mentor end produces the choice result")
	await _capture("03_mentor_result.png", "mentor lesson result")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_go_to_mountain"):
		return false
	state = _state()
	check(state.get("scene", "") == "back_mountain" and int(state.get("slot", -1)) == 1, "zero-slot travel reaches the mountain without advancing time")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_train_mountain"):
		return false
	state = _state()
	stats = state.get("stats", {})
	flags = state.get("flags", {})
	var receipt: Dictionary = state.get("last_result", {})
	var delta: Dictionary = receipt.get("delta", {})
	var delta_stats: Dictionary = delta.get("stats", {})
	check(int(delta_stats.get("cultivation", -1)) == 18 and int(stats.get("cultivation", -1)) == 18, "the first mountain training consumes the pending hint for an actual +18")
	check(int(stats.get("energy", -1)) == 70 and not bool(flags.get("breathing_hint", true)), "hinted training costs 22 energy and consumes the one-use flag")
	check(int(delta.get("slots", -1)) == 2, "mountain training advances exactly two slots")
	var shu_receipt_visible: bool = await _assert_receipt_and_journal_visible("cultivation", 18)
	check(shu_receipt_visible, "the actual receipt and a journal entry are visible after hinted training")
	await _capture("04_shu_hint_training_result.png", "18-point hinted training result")
	await _check_layout("shu training result", ["HeaderPanel", "SwitchPackButton", "SaveButton", "LoadButton", "NewRunButton", "StatsPanel", "GoalsPanel", "JournalPanel", "ScenePanel", "PhasePanel", "ActionScroll"])
	if not await _click("SaveButton"):
		return false
	check(not _button_disabled("LoadButton"), "saving the shu result enables this pack's load control")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_train_mountain"):
		return false
	state = _state()
	stats = state.get("stats", {})
	check(int(stats.get("cultivation", -1)) == 30 and int(stats.get("energy", -1)) == 48, "the next training returns to its base +12 gain")
	check(not bool(state.get("flags", {}).get("breathing_hint", true)), "the consumed mentor hint is not duplicated by the next training")
	if not await _click("LoadButton"):
		return false
	check(_has_control("ConfirmAcceptButton") and _has_control("ConfirmCancelButton"), "loading the saved shu checkpoint asks for inline confirmation")
	await _capture("05_shu_load_confirmation.png", "load confirmation over unsaved second training")
	await _check_layout("shu load confirmation", ["HeaderPanel", "ConfirmAcceptButton", "ConfirmCancelButton", "ActionScroll", "ScenePanel"])
	if not await _click("ConfirmAcceptButton"):
		return false
	state = _state()
	stats = state.get("stats", {})
	check(_pack_id() == "shu_entry" and state.get("scene", "") == "back_mountain", "the shu load restores the saved pack and mountain location")
	check(state.get("phase", "") == "result" and int(stats.get("cultivation", -1)) == 18 and int(stats.get("energy", -1)) == 70, "load restores the saved 18-point result rather than the later unsaved run")
	check(not bool(state.get("flags", {}).get("breathing_hint", true)), "loading does not duplicate the already-consumed pending bonus")
	await _capture("06_shu_restored_result.png", "restored shu training checkpoint")
	if not await _click("ResultContinueButton"):
		return false

	var action_count := 0
	while int(_state().get("stats", {}).get("cultivation", 0)) < 60 and action_count < 12:
		state = _state()
		stats = state.get("stats", {})
		var action_name := "ActionButton_train_mountain" if int(stats.get("energy", 0)) >= 22 else "ActionButton_rest_practice"
		if not await _click(action_name):
			return false
		state = _state()
		stats = state.get("stats", {})
		if action_name == "ActionButton_train_mountain":
			check(int(state.get("last_result", {}).get("delta", {}).get("stats", {}).get("cultivation", -1)) == 12, "post-load mountain training uses its unboosted +12 result")
		else:
			check(int(stats.get("energy", -1)) <= 100, "real rest action stays within the authored energy cap")
		if not await _click("ResultContinueButton"):
			return false
		action_count += 1
	state = _state()
	check(int(state.get("stats", {}).get("cultivation", 0)) >= 60, "real training and rest clicks reach the shu cultivation goal")
	check(action_count < 12, "the shu cultivation loop terminates within its explicit action guard")
	if not await _click("ActionButton_return_to_corridor"):
		return false
	check(_state().get("scene", "") == "tingyu_corridor", "real return travel brings the player back to the corridor")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_report_practice"):
		return false
	state = _state()
	check(state.get("phase", "") == "event" and state.get("event", {}).get("id", "") == "practice_report", "the qualified report action opens its authored goal event")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("event", {}).get("node", "") == "end", "the goal report reaches its authored ending")
	await _capture("07_shu_report_end.png", "shu goal report ending")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("phase", "") == "result" and bool(state.get("flags", {}).get("cultivation_goal_reported", false)), "closing the report records goal completion and returns a result")
	if not await _click("ResultContinueButton"):
		return false
	state = _state()
	check(state.get("phase", "") == "ready" and int(state.get("stats", {}).get("cultivation", 0)) >= 60, "the completed shu report returns to an ongoing sandbox")
	check(_has_visible_label("已达成"), "the completed goal is visible in the goals panel")
	check(not _button_disabled("LoadButton"), "the earlier shu checkpoint remains available without overwriting it")
	await _capture("08_shu_goal_sandbox.png", "shu goal completed with sandbox controls")
	await _check_layout("shu goal sandbox", ["HeaderPanel", "SwitchPackButton", "SaveButton", "LoadButton", "NewRunButton", "StatsPanel", "GoalsPanel", "JournalPanel", "ScenePanel", "PhasePanel", "ActionScroll"])

	if not await _click("SwitchPackButton"):
		return false
	if not await _click("PackStartButton_1"):
		return false
	check(_has_control("ConfirmAcceptButton"), "starting the second pack warns before replacing unsaved shu progress")
	if not await _click("ConfirmAcceptButton"):
		return false
	return true


func _run_stream_flow() -> bool:
	var state := _state()
	var stats: Dictionary = state.get("stats", {})
	check(_pack_id() == "stream_study", "the second real UI start opens the independent stream_study pack")
	check(state.get("scene", "") == "tea_pavilion" and state.get("phase", "") == "ready", "stream_study starts ready in its own tea pavilion")
	check(int(stats.get("stamina", -1)) == 80 and int(stats.get("insight", -1)) == 0, "stream_study starts with its own 80 stamina and zero insight")
	await _capture("09_stream_initial.png", "stream study initial pavilion")
	await _check_layout("stream initial scene", ["HeaderPanel", "SwitchPackButton", "SaveButton", "LoadButton", "NewRunButton", "StatsPanel", "GoalsPanel", "JournalPanel", "ScenePanel", "SceneDescription", "PhasePanel", "ActionScroll"])

	if not await _click("ActorButton_pavilion_keeper"):
		return false
	state = _state()
	stats = state.get("stats", {})
	check(state.get("phase", "") == "event" and state.get("event", {}).get("id", "") == "study_tip", "the real text-only keeper card opens its own study-tip event")
	check(int(stats.get("stamina", -1)) == 77 and int(state.get("slot", -1)) == 1, "asking the keeper applies its authored stamina and time cost")
	check(_button_disabled("SaveButton"), "saving is disabled during the stream dialogue")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("event", {}).get("node", "") == "choice", "the real continue control advances the keeper dialogue to its choice")
	check(_button_disabled("SaveButton"), "saving remains disabled at the stream choice")
	var accept_tip: Button = await _fresh_button("ChoiceButton_keep_tip")
	var skip_tip: Button = await _fresh_button("ChoiceButton_continue_reading")
	check(accept_tip != null and not accept_tip.disabled, "the authored one-use study-tip option is available")
	check(skip_tip != null and not skip_tip.disabled, "the keeper choice includes an unconditional escape")
	await _capture("10_keeper_choice.png", "keeper study-tip choice")
	await _check_layout("keeper choice", ["HeaderPanel", "SwitchPackButton", "SaveButton", "LoadButton", "NewRunButton", "PhasePanel", "ScenePanel"])
	if not await _click("ChoiceButton_keep_tip"):
		return false
	state = _state()
	stats = state.get("stats", {})
	var flags: Dictionary = state.get("flags", {})
	check(int(stats.get("stamina", -1)) == 77 and int(stats.get("insight", -1)) == 0, "accepting the tip does not grant its reading bonus immediately")
	check(bool(flags.get("study_tip_claimed", false)) and bool(flags.get("study_hint", false)), "accepting the tip arms a pending hint and records its one-time claim")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("event", {}).get("node", "") == "end", "the accepted stream tip reaches its authored end node")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("phase", "") == "result", "closing the keeper event produces the action result")
	await _capture("11_stream_tip_result.png", "pending stream study tip result")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_walk_to_river"):
		return false
	state = _state()
	check(state.get("scene", "") == "riverbank" and int(state.get("slot", -1)) == 2, "real stream travel changes location and advances its authored one slot")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_read_by_river"):
		return false
	state = _state()
	stats = state.get("stats", {})
	flags = state.get("flags", {})
	var receipt: Dictionary = state.get("last_result", {})
	var delta: Dictionary = receipt.get("delta", {})
	var delta_stats: Dictionary = delta.get("stats", {})
	check(int(delta_stats.get("insight", -1)) == 12 and int(stats.get("insight", -1)) == 12, "the first river reading consumes the pending hint for an actual +12")
	check(int(stats.get("stamina", -1)) == 62 and not bool(flags.get("study_hint", true)), "hinted reading costs 15 stamina and consumes the one-use hint")
	check(int(delta.get("slots", -1)) == 1, "river reading advances exactly one slot")
	var stream_receipt_visible: bool = await _assert_receipt_and_journal_visible("insight", 12)
	check(stream_receipt_visible, "the actual reading receipt and journal entry are visible")
	await _capture("12_stream_hint_read_result.png", "12-point hinted reading result")
	await _check_layout("stream reading result", ["HeaderPanel", "SwitchPackButton", "SaveButton", "LoadButton", "NewRunButton", "StatsPanel", "GoalsPanel", "JournalPanel", "ScenePanel", "PhasePanel", "ActionScroll"])
	if not await _click("SaveButton"):
		return false
	check(not _button_disabled("LoadButton"), "saving enables the stream pack's own load control")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_read_by_river"):
		return false
	state = _state()
	stats = state.get("stats", {})
	check(int(stats.get("insight", -1)) == 20 and int(stats.get("stamina", -1)) == 47, "later river reading uses its unboosted base +8")
	if not await _click("LoadButton"):
		return false
	check(_has_control("ConfirmAcceptButton"), "loading stream_study also requests confirmation before replacing progress")
	if not await _click("ConfirmAcceptButton"):
		return false
	state = _state()
	stats = state.get("stats", {})
	check(_pack_id() == "stream_study" and state.get("scene", "") == "riverbank", "stream load restores only the stream pack and its reading location")
	check(state.get("phase", "") == "result" and int(stats.get("insight", -1)) == 12 and int(stats.get("stamina", -1)) == 62, "stream load restores the saved 12-point hinted-reading receipt")
	check(not bool(state.get("flags", {}).get("study_hint", true)), "load does not apply or recreate the consumed stream bonus")
	await _capture("13_stream_restored_result.png", "restored stream reading checkpoint")
	if not await _click("ResultContinueButton"):
		return false

	var action_count := 0
	while int(_state().get("stats", {}).get("insight", 0)) < 30 and action_count < 16:
		state = _state()
		stats = state.get("stats", {})
		var action_name := "ActionButton_read_by_river" if int(stats.get("stamina", 0)) >= 15 else "ActionButton_pause_by_stream"
		if not await _click(action_name):
			return false
		state = _state()
		stats = state.get("stats", {})
		if action_name == "ActionButton_read_by_river":
			check(int(state.get("last_result", {}).get("delta", {}).get("stats", {}).get("insight", -1)) == 8, "post-load reading uses its unboosted +8 result")
		else:
			check(int(stats.get("stamina", -1)) <= 80, "real stream rest stays within the authored stamina cap")
		if not await _click("ResultContinueButton"):
			return false
		action_count += 1
	state = _state()
	check(int(state.get("stats", {}).get("insight", 0)) >= 30, "real reading and rest clicks reach the stream goal")
	check(action_count < 16, "the stream reading loop terminates within its explicit action guard")
	if not await _click("ActionButton_return_to_tea_pavilion"):
		return false
	check(_state().get("scene", "") == "tea_pavilion", "real return travel brings the reader back to the pavilion")
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_submit_reading_note"):
		return false
	state = _state()
	check(state.get("phase", "") == "event" and state.get("event", {}).get("id", "") == "study_report", "the qualified submission opens its authored report event")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("event", {}).get("node", "") == "end", "the stream report reaches its authored ending")
	if not await _click("DialogContinueButton"):
		return false
	state = _state()
	check(state.get("phase", "") == "result" and bool(state.get("flags", {}).get("study_goal_complete", false)), "closing the stream report records goal completion")
	if not await _click("ResultContinueButton"):
		return false
	state = _state()
	check(state.get("phase", "") == "ready" and int(state.get("stats", {}).get("insight", 0)) >= 30, "the completed stream report returns to an ongoing sandbox")
	check(_has_visible_label("已达成"), "the stream completion remains visible in its goal panel")
	await _capture("14_stream_goal_sandbox.png", "stream goal completed with sandbox controls")
	await _check_layout("stream goal sandbox", ["HeaderPanel", "SwitchPackButton", "SaveButton", "LoadButton", "NewRunButton", "StatsPanel", "GoalsPanel", "JournalPanel", "ScenePanel", "PhasePanel", "ActionScroll"])
	if not await _click("SaveButton"):
		return false
	check(not _button_disabled("LoadButton"), "the completed stream pack has its own saved checkpoint")
	if not await _click("SwitchPackButton"):
		return false
	if not await _click("PackContinueButton_0"):
		return false
	check(_has_control("ConfirmAcceptButton"), "continuing shu warns before replacing the stream session")
	if not await _click("ConfirmAcceptButton"):
		return false
	state = _state()
	stats = state.get("stats", {})
	check(_pack_id() == "shu_entry" and state.get("scene", "") == "back_mountain", "the first pack's Continue button restores the first pack save")
	check(state.get("phase", "") == "result" and int(stats.get("cultivation", -1)) == 18 and int(stats.get("energy", -1)) == 70, "shu keeps its own 18 cultivation and 70 energy checkpoint")
	check(stats.has("understanding") and not stats.has("insight") and not stats.has("stamina"), "the restored shu save contains no stream-specific stat IDs")
	await _capture("15_shu_continue.png", "shu pack continued after stream save")
	if not await _click("SwitchPackButton"):
		return false
	var continue_shu: Button = await _fresh_button("PackContinueButton_0")
	var continue_stream: Button = await _fresh_button("PackContinueButton_1")
	check(continue_shu != null and not continue_shu.disabled and continue_stream != null and not continue_stream.disabled, "the library keeps independent Continue saves for both packs")
	if not await _click("PackContinueButton_1"):
		return false
	check(_has_control("ConfirmAcceptButton"), "continuing the stream save asks before replacing the restored shu run")
	if not await _click("ConfirmAcceptButton"):
		return false
	state = _state()
	stats = state.get("stats", {})
	check(_pack_id() == "stream_study" and int(stats.get("insight", -1)) >= 30, "the independently saved stream goal state still loads after shu is restored")
	check(bool(state.get("flags", {}).get("study_goal_complete", false)) and not stats.has("cultivation"), "the loaded stream save retains its goal and its own stat IDs")

	var before_new_run := state.duplicate(true)
	if not await _click("NewRunButton"):
		return false
	check(_has_control("ConfirmAcceptButton") and _has_control("ConfirmCancelButton"), "new-run replacement shows inline accept and cancel controls")
	await _capture("16_new_run_confirmation.png", "new-run confirmation over saved stream progress")
	if not await _click("ConfirmCancelButton"):
		return false
	check(_state() == before_new_run, "cancelling new run preserves the entire active stream snapshot")
	if not await _click("NewRunButton"):
		return false
	if not await _click("ConfirmAcceptButton"):
		return false
	state = _state()
	stats = state.get("stats", {})
	check(_pack_id() == "stream_study" and state.get("phase", "") == "ready", "confirming new run resets only the active stream pack")
	check(int(stats.get("stamina", -1)) == 80 and int(stats.get("insight", -1)) == 0 and int(state.get("sequence", -1)) == 0, "the confirmed stream new run restores its authored initial stats and sequence")
	check(not bool(state.get("flags", {}).get("study_goal_complete", false)), "the reset stream run clears its in-memory completion flag")
	await _capture("17_stream_new_run_reset.png", "confirmed clean stream run")
	if not await _click("SwitchPackButton"):
		return false
	continue_shu = await _fresh_button("PackContinueButton_0")
	continue_stream = await _fresh_button("PackContinueButton_1")
	check(continue_shu != null and not continue_shu.disabled and continue_stream != null and not continue_stream.disabled, "resetting the active stream run leaves both independent saves available")
	if not await _click("PackContinueButton_0"):
		return false
	state = _state()
	stats = state.get("stats", {})
	check(_pack_id() == "shu_entry" and int(stats.get("cultivation", -1)) == 18 and state.get("phase", "") == "result", "the stream reset did not replace the saved shu checkpoint")
	if not await _click("SwitchPackButton"):
		return false
	if not await _click("PackContinueButton_1"):
		return false
	check(_has_control("ConfirmAcceptButton"), "returning to saved stream progress confirms replacing the current shu run")
	if not await _click("ConfirmAcceptButton"):
		return false
	state = _state()
	check(_pack_id() == "stream_study" and bool(state.get("flags", {}).get("study_goal_complete", false)), "the active new-run reset did not overwrite the saved stream goal checkpoint")
	return true


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
	var requested := Vector2i(int(parts[0]), int(parts[1]))
	if not ALLOWED_QA_SIZES.has(requested):
		push_error("--qa-size must be 1152x720 or 960x600, received: " + value)
		failures += 1
		return
	qa_size = requested


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
	# Scrolling and layout can invalidate child references; resolve the UI node again.
	control = await _fresh_control(control_name)
	if control == null:
		return false
	# A rebuilt Control can exist before all container/font layout passes settle.
	# Wait for a stable hit rectangle, then verify this physical input fired it.
	var prior_rect := Rect2()
	var stable_frames: int = 0
	for _layout_frame: int in range(30):
		await process_frame
		var current_rect: Rect2 = control.get_global_rect()
		stable_frames = stable_frames + 1 if current_rect == prior_rect and current_rect.size.x > 0 else 0
		prior_rect = current_rect
		if stable_frames >= 3:
			break
	if control is BaseButton and (control as BaseButton).disabled:
		check(false, "real UI control %s remains enabled after scrolling into view" % control_name)
		return false
	var canvas_point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var point := root.get_final_transform() * canvas_point
	var fired: Array[bool] = [false]
	if control is BaseButton:
		(control as BaseButton).pressed.connect(func() -> void: fired[0] = true, CONNECT_ONE_SHOT)
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
	await process_frame
	check(fired[0], "actual mouse input dispatches " + control_name)
	if not fired[0]:
		print("CLICK_DIAGNOSTIC ", control_name, " target=", prior_rect, " point=", point, " phase=", _state().get("phase", ""))
	return fired[0]


func _fresh_control(control_name: String) -> Control:
	for _frame in range(CONTROL_WAIT_FRAMES):
		if app != null and is_instance_valid(app):
			var candidate: Variant = app.call("ui_control", control_name)
			if candidate is Control and is_instance_valid(candidate) and (candidate as Control).is_visible_in_tree():
				return candidate as Control
		await process_frame
	check(false, "expected real UI control %s appears after a bounded wait" % control_name)
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


func _has_control(control_name: String) -> bool:
	if app == null or not is_instance_valid(app):
		return false
	var control: Variant = app.call("ui_control", control_name)
	return control is Control and is_instance_valid(control) and (control as Control).is_visible_in_tree()


func _button_disabled(control_name: String) -> bool:
	var candidate: Variant = app.call("ui_control", control_name) if app != null and is_instance_valid(app) else null
	if candidate is BaseButton and is_instance_valid(candidate):
		return (candidate as BaseButton).disabled
	check(false, "UI control %s exposes a disabled state" % control_name)
	return true


func _state() -> Dictionary:
	var audit := _audit()
	var value: Variant = audit.get("state", {})
	return value as Dictionary if value is Dictionary else {}


func _audit() -> Dictionary:
	if app == null or not is_instance_valid(app):
		return {}
	var value: Variant = app.call("audit_snapshot")
	return value as Dictionary if value is Dictionary else {}


func _pack_id() -> String:
	return str(_audit().get("pack_id", ""))


func _assert_receipt_and_journal_visible(stat_id: String, expected_amount: int) -> bool:
	var matching_receipt: Label = _find_label(app, "实际变化：")
	var visible_receipt := false
	if matching_receipt != null:
		visible_receipt = matching_receipt.is_visible_in_tree() and _intersects_logical_view(matching_receipt.get_global_rect())
	var expected_token := "+%d" % expected_amount
	var receipt_has_actual_delta := matching_receipt != null and matching_receipt.text.contains(expected_token)
	var journal_scroll_control := app.call("ui_control", "JournalScroll") as ScrollContainer
	var journal_label: Label = _first_label(journal_scroll_control) if journal_scroll_control != null else null
	if journal_label != null:
		await _ensure_control_visible(journal_label)
	var journal_visible := false
	if journal_label != null and journal_scroll_control != null:
		journal_visible = journal_label.is_visible_in_tree() and journal_label.get_global_rect().intersects(journal_scroll_control.get_global_rect()) and not journal_label.text.strip_edges().is_empty()
	check(visible_receipt and receipt_has_actual_delta, "visible result receipt contains the actual %s +%d delta" % [stat_id, expected_amount])
	check(journal_visible, "the latest journal entry is visible inside JournalScroll")
	return visible_receipt and receipt_has_actual_delta and journal_visible


func _find_label(node: Node, text_fragment: String) -> Label:
	if node == null:
		return null
	if node is Label and (node as Label).text.contains(text_fragment):
		return node as Label
	for child in node.get_children():
		var found := _find_label(child, text_fragment)
		if found != null:
			return found
	return null


func _first_label(node: Node) -> Label:
	if node == null:
		return null
	if node is Label and not (node as Label).text.strip_edges().is_empty():
		return node as Label
	for child in node.get_children():
		var found := _first_label(child)
		if found != null:
			return found
	return null


func _has_visible_label(text_fragment: String) -> bool:
	var label := _find_label(app, text_fragment)
	if label == null or not label.is_visible_in_tree():
		return false
	return _intersects_logical_view(label.get_global_rect())


func _intersects_logical_view(rect: Rect2) -> bool:
	return rect.intersects(Rect2(Vector2.ZERO, Vector2(LOGICAL_SIZE)))


func _check_layout(label: String, core_names: Array[String]) -> void:
	await process_frame
	await process_frame
	var viewport_size := Vector2i(app.get_viewport_rect().size.round())
	check(viewport_size == LOGICAL_SIZE, "%s uses the 1440x900 logical viewport" % label)
	var logical_bounds := Rect2(Vector2.ZERO, Vector2(LOGICAL_SIZE))
	for control_name in core_names:
		var control: Variant = app.call("ui_control", control_name)
		if not control is Control or not is_instance_valid(control) or not (control as Control).is_visible_in_tree():
			check(false, "%s exposes visible core control %s" % [label, control_name])
			continue
		var current := control as Control
		if _has_scroll_ancestor(current):
			continue
		var rect := current.get_global_rect()
		check(rect.size.x > 0.0 and rect.size.y > 0.0 and logical_bounds.encloses(rect), "%s keeps core control %s inside the logical viewport" % [label, control_name])
	var audit := _audit()
	var registered_rects: Dictionary = audit.get("ui_rects", {})
	for raw_name in registered_rects.keys():
		var control_name := str(raw_name)
		var control: Variant = app.call("ui_control", control_name)
		if not control is Control or not is_instance_valid(control) or _has_scroll_ancestor(control as Control):
			continue
		var rect_value: Variant = registered_rects[raw_name]
		if rect_value is Rect2:
			check(logical_bounds.encloses(rect_value as Rect2), "%s keeps visible registered control %s inside the viewport" % [label, control_name])


func _has_scroll_ancestor(control: Control) -> bool:
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return true
		ancestor = ancestor.get_parent()
	return false


func _capture(filename: String, description: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var full_path := _absolute_output_dir().path_join(filename)
	var save_result := image.save_png(full_path)
	check(save_result == OK, "capture %s is written" % filename)
	check(image.get_size() == qa_size, "capture %s has the actual native window pixel size" % filename)
	var state := _state()
	var record: Dictionary = {
		"file": filename,
		"description": description,
		"pixels": [image.get_width(), image.get_height()],
		"view_mode": str(_audit().get("view_mode", "")),
		"pack_id": _pack_id(),
		"phase": str(state.get("phase", "")),
		"scene": str(state.get("scene", "")),
		"day": int(state.get("day", 0)),
		"slot": int(state.get("slot", 0)),
		"stats": state.get("stats", {}).duplicate(true),
		"flags": state.get("flags", {}).duplicate(true),
	}
	captures.append(record)


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		failure_messages.append(message)
		push_error("FAIL: " + message)
	check_records.append({"ok": condition, "label": message})


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var adapter_name := ""
	if DisplayServer.get_name() != "headless":
		adapter_name = RenderingServer.get_video_adapter_name()
	var report := {
		"checks": checks,
		"failures": failures,
		"failure_messages": failure_messages,
		"qa_size": [qa_size.x, qa_size.y],
		"logical_size": [LOGICAL_SIZE.x, LOGICAL_SIZE.y],
		"display_server": DisplayServer.get_name(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"adapter": adapter_name,
		"captures": captures,
		"check_records": check_records,
	}
	var report_path := _absolute_output_dir().path_join("cultivation-engine-render-report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	else:
		failures += 1
		push_error("Could not save the cultivation engine render report: " + report_path)
	print("CULTIVATION_ENGINE_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)
