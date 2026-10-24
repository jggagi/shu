extends "res://tests/cultivation_engine_mentor_loop_render.gd"

# Reuse only the existing native capture/input helpers; this is a separate P1 flow.
const TownScene := preload("res://scenes/demos/cultivation_engine_v03_town.tscn")


func _run() -> void:
	output_dir = "res://.local/qa/cultivation-engine-town-return/render"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	check(DirAccess.make_dir_recursive_absolute(_absolute_output_dir()) == OK, "P1 capture directory is available")
	check(DisplayServer.get_name() != "headless", "P1 uses a native display server")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = TownScene.instantiate() as Control
	root.add_child(app)
	await process_frame
	await process_frame
	test_store_dir = "user://town_return_render_%d" % Time.get_ticks_usec()
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(test_store_dir)), "P1 allocates a fresh test-only save directory")
	app.get("_store").set("base_dir", test_store_dir)
	if await _click("PackSelectButton_0") and await _click("PackStartButton_0"):
		await _run_town_flow()
	_finish()


func _click_sequence(names: Array[String]) -> bool:
	for control_name: String in names:
		if not await _click(control_name):
			return false
	return true


func _run_town_flow() -> bool:
	check(_pack_id() == "shu_town_return" and _state().get("scene", "") == "tingyu_corridor", "the new route starts in its independent Shu pack")
	await _capture("00_corridor_exit.png", "corridor with visible travel cost and town exit")
	await _check_layout("corridor exit", ["HeaderPanel", "ScenePanel", "PhasePanel", "ActionScroll"])
	if not await _click("ActionButton_talk_mentor"):
		return false
	check(_button_disabled("ActionButton_go_to_town"), "town travel is unavailable during mentor dialogue")
	for _line: int in range(4):
		if not await _click("DialogContinueButton"):
			return false
	if not await _click("ChoiceButton_take_lesson"):
		return false
	if not await _click_sequence(["DialogContinueButton", "DialogContinueButton", "DialogContinueButton", "ResultContinueButton"]):
		return false
	var departure_stats: Dictionary = _state().get("stats", {}).duplicate(true)
	check(bool(_state().get("flags", {}).get("breathing_hint", false)), "the accepted lesson is present before travel")
	if not await _click("ActionButton_go_to_town"):
		return false
	var town_checkpoint: Dictionary = _state()
	check(town_checkpoint.get("scene", "") == "shanxia_town" and town_checkpoint.get("phase", "") == "result", "the exit reaches the town with a real result")
	check(town_checkpoint.get("stats", {}) == departure_stats and int(town_checkpoint.get("slot", -1)) == 2, "one-way travel charges exactly one slot and no stats")
	check(bool(town_checkpoint.get("flags", {}).get("town_visited", false)) and bool(town_checkpoint.get("flags", {}).get("breathing_hint", false)), "town arrival records the visit and retains the one-use lesson")
	check(_button_disabled("ActionButton_return_from_town"), "the arrival result blocks a second action until acknowledged")
	await _capture("01_town_arrival.png", "town route sketch, arrival receipt and unchanged cultivation stats")
	await _check_layout("town arrival", ["HeaderPanel", "ScenePanel", "PhasePanel", "ActionScroll"])
	if not await _click_sequence(["SaveButton", "ResultContinueButton"]):
		return false
	for _look: int in range(2):
		var before_look: Dictionary = _state()
		if not await _click("ActionButton_look_town"):
			return false
		check(_state().get("stats", {}) == before_look.get("stats", {}) and _state().get("slot", -1) == before_look.get("slot", -2), "looking around is informational and free")
		if not await _click("ResultContinueButton"):
			return false
	await _capture("02_town_ready.png", "town offers a free look and a clearly priced return")
	if not await _click("ActionButton_return_from_town"):
		return false
	check(_state().get("scene", "") == "tingyu_corridor" and int(_state().get("slot", -1)) == 3, "return reaches the original corridor with one further slot")
	check(bool(_state().get("flags", {}).get("town_returned", false)) and _state().get("stats", {}) == departure_stats, "return records its persistent flag without changing cultivation stats")
	await _capture("03_return_result.png", "returned corridor and original lesson preserved")
	if not await _click_sequence(["LoadButton", "ConfirmCancelButton"]):
		return false
	check(_state().get("scene", "") == "tingyu_corridor", "cancelling load retains the returned run")
	if not await _click_sequence(["LoadButton", "ConfirmAcceptButton"]):
		return false
	check(await _wait_for_snapshot(town_checkpoint, 90), "loading restores the complete saved town arrival without repeating travel")
	check(not bool(_presentation().get("playing", false)) and _voice_is_stopped(), "town restore starts no sword or voice playback")
	await _capture("04_town_restored.png", "town result restored with exact time, stats and receipts")
	if not await _click_sequence(["ResultContinueButton", "ActionButton_return_from_town", "ResultContinueButton", "ActionButton_go_to_mountain", "ResultContinueButton", "ActionButton_pine_wind"]):
		return false
	check(_state().get("phase", "") == "performing" and _button_disabled("SaveButton"), "training after return uses the original motion busy/save gate")
	await _capture("05_sword_after_return.png", "original sword motion still plays after the round trip")
	if not await _wait_for_phase("result", 240):
		check(false, "post-travel sword finishes through its real presenter callback")
		return false
	check(int(_state().get("stats", {}).get("cultivation", -1)) == 6 and int(_state().get("stats", {}).get("sword", -1)) == 10, "the preserved lesson is consumed once by the original sword settlement")
	if not await _click_sequence(["ResultContinueButton", "ActionButton_return_to_corridor", "ResultContinueButton", "ActionButton_report_practice", "ChoiceButton_with_lesson", "DialogContinueButton", "DialogContinueButton", "DialogContinueButton", "ResultContinueButton"]):
		return false
	check(bool(_state().get("flags", {}).get("mentor_reported", false)), "the original mentor report remains completable after travel")
	if not await _click_sequence(["ActionButton_rest_practice", "ResultContinueButton", "ActionButton_go_to_town"]):
		return false
	check(_state().get("scene", "") == "shanxia_town" and int(_state().get("day", -1)) == 2 and int(_state().get("slot", -1)) == 0, "a later trip naturally crosses the six-slot day boundary")
	await _capture("06_town_day_two.png", "second-day town arrival after continued mountain cultivation")
	if not await _click_sequence(["ResultContinueButton", "ActionButton_return_from_town", "SaveButton"]):
		return false
	var final_checkpoint: Dictionary = _state()
	check(final_checkpoint.get("scene", "") == "tingyu_corridor" and int(final_checkpoint.get("day", -1)) == 2 and int(final_checkpoint.get("slot", -1)) == 1, "the second return keeps the new day and spends only one slot")
	if not await _click_sequence(["SwitchPackButton", "PackSelectButton_1", "PackStartButton_1", "ConfirmAcceptButton"]):
		return false
	check(_pack_id() == "stream_study" and _state().get("scene", "") == "tea_pavilion", "the same runtime still starts the independent unvoiced Stream pack")
	if not await _click_sequence(["SaveButton", "SwitchPackButton", "PackSelectButton_0", "PackContinueButton_0"]):
		return false
	if _has_control("ConfirmAcceptButton") and not await _click("ConfirmAcceptButton"):
		return false
	check(await _wait_for_snapshot(final_checkpoint, 90), "catalog continuation restores Shu progress after saving the other pack")
	await _capture("07_return_checkpoint.png", "saved return restored after switching to the independent Stream pack")
	await _check_layout("final returned result", ["HeaderPanel", "ScenePanel", "PhasePanel", "StatsPanel"])
	return true


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	var report: Dictionary = {"test": "cultivation_engine_town_return_render", "checks": checks, "failures": failures, "failure_messages": failure_messages, "qa_size": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "captures": captures, "result": "PASS" if failures == 0 else "FAIL", "input_method": "Godot root.push_input; not OS physical input or browser"}
	var file := FileAccess.open(_absolute_output_dir().path_join("cultivation-engine-town-return-render-report.json"), FileAccess.WRITE)
	if file == null:
		failures += 1
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("CULTIVATION_ENGINE_TOWN_RETURN_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)
