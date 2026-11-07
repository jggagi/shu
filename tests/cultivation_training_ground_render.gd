extends "res://tests/cultivation_first_journey_render.gd"
## Native UI route. All progress comes from real input and natural playback;
## neither Session state nor presenter completion callbacks are injected.

const TRAINING_ACTIONS := ["pine_wind", "listening_rain", "returning_tide", "rising_peak", "swift_swallow"]
const COMBO_LENGTHS := {"pine_wind": 2, "listening_rain": 2, "returning_tide": 3, "rising_peak": 2, "swift_swallow": 3}
var training_checkpoints: Array[Dictionary] = []


func _run() -> void:
	output_dir = "res://.local/qa/training-ground/render"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	check(DirAccess.make_dir_recursive_absolute(_absolute_output_dir()) == OK, "training-ground QA output is available")
	check(DisplayServer.get_name() != "headless", "training-ground QA uses a real rendered display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	test_store_dir = "user://training_ground_ui_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(test_store_dir)), "training QA uses fresh storage separate from player checkpoints")
	app = JourneyScene.instantiate() as Control
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	var deadline := Time.get_ticks_msec() + 20000
	while _state().is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _expect(not _state().is_empty(), "journey launches before the wall-clock deadline"):
		_finish()
		return
	check(str(app.get("_store").get("base_dir")) == test_store_dir, "all training UI saves use isolated QA storage")
	if not await _journey_route():
		await _capture("failure_context.png", "actual training UI where the route stopped")
	_finish()


func _journey_route() -> bool:
	if not _expect(_pack_id() == "shu_first_journey" and _state().scene == "tingyu_corridor" and _state().phase == "ready", "new training route starts in actual journey corridor"):
		return false
	check(not bool(_audit().get("training_ground_open", true)), "new journey has no transient training-ground context")
	check(not _has_control("EnterTrainingGroundButton"), "3D training entry is not offered in the corridor")
	if not await _click("ActionButton_talk_mentor"):
		return false
	for index: int in range(4):
		if not await _click("DialogContinueButton"):
			return false
	if not _expect(_state().phase == "event" and _state().event.get("node", "") == "choice", "real mentor conversation reaches its authored choice"):
		return false
	if not await _click("ChoiceButton_take_lesson") or not await _finish_event() or not await _close_result():
		return false
	check(_flag("mentor_lesson_heard") and _flag("mentor_lesson_accepted") and int(_state().stats.energy) == 92, "actual mentor choice grants existing hint at original cost")
	if not await _click("ActionButton_go_to_mountain") or not await _close_result():
		return false
	if not _expect(_state().scene == "back_mountain" and _presentation().get("route") == "painted_2d_portrait", "mountain initially retains the original 2D portrait route"):
		return false
	for action_id: String in TRAINING_ACTIONS:
		check(_has_control("ActionButton_" + action_id) and not _button_disabled("ActionButton_" + action_id), "2D mountain retains available original action: " + action_id)
	await _check_layout("2D training entry", ["ScenePanel", "EnterTrainingGroundButton", "ActionButton_pine_wind"])
	await _capture("00_painted_mountain.png", "original painted mountain before entering 3D training")
	var before_entry: Dictionary = _state()
	if not await _click("EnterTrainingGroundButton"):
		return false
	if not _expect(_training_open() and _training_actor() != null, "actual enter button opens persistent 3D training actor"):
		return false
	check(_state() == before_entry, "entering 3D training changes no date, resources, flags, receipts or revision")
	await _check_training_layout("3D training entry")
	await _capture("01_training_ground.png", "actual 3D training ground before practice")
	if not await _click("ReturnTrainingGroundButton"):
		return false
	check(not _training_open() and _state() == before_entry and _presentation().get("route") == "painted_2d_portrait", "leaving ready 3D training returns to 2D without a game action")
	if not await _click("EnterTrainingGroundButton"):
		return false
	if not _expect(_training_actor() != null and _training_open(), "3D training may be entered again"):
		return false
	var actor_id := _training_actor().get_instance_id()
	var unavailable: Control = _training_actor()
	var before_unavailable: Dictionary = _state()
	var moves_before_unavailable := _move_audit()
	# Presenter resource fixture only: keep all authoritative host state intact,
	# then use actual pointer input to exercise preflight before any settlement.
	unavailable.set("_prepared", false)
	var unavailable_clicked := await _click("ActionButton_pine_wind")
	if is_instance_valid(unavailable):
		unavailable.set("_prepared", true)
	else:
		return _expect(false, "rejected resource preflight preserves the persistent training actor")
	if not unavailable_clicked:
		return false
	check(_state() == before_unavailable, "unprepared 3D presenter rejects actual practice input before charging or writing any host receipt")
	check(bool(app.get("_status_is_error")), "unprepared 3D presenter exposes visible preflight failure")
	check(_training_actor() != null and _training_actor().get_instance_id() == actor_id and _move_audit() == moves_before_unavailable, "rejected preflight neither replaces actor nor begins or cancels real motion")
	var start_training: Dictionary = _state()
	for index: int in range(TRAINING_ACTIONS.size()):
		if int(_state().stats.energy) < 22:
			if not await _rest_in_training():
				return false
		if not await _perform_training(TRAINING_ACTIONS[index], actor_id, index == 0):
			return false
		if index < TRAINING_ACTIONS.size() - 1 and not await _close_result():
			return false
	check(int(_state().stats.sword) == int(start_training.stats.sword) + 50, "five real 3D combinations grant exactly fifty sword skill")
	for action_id: String in TRAINING_ACTIONS:
		check(int(_state().counts.get(action_id, 0)) == int(start_training.counts.get(action_id, 0)) + 1, "each 3D manual has one authoritative settlement: " + action_id)
	check(not _flag("breathing_hint") and int(_state().stats.cultivation) == 6, "five combinations consume mentor bonus once")
	await _capture("07_five_combinations_finished.png", "five real combinations have finished through host results")
	if not await _test_training_save_load(actor_id):
		return false
	if not await _test_original_2d_practice():
		return false
	if not await _test_reset_clears_training_context():
		return false
	return true


func _perform_training(action_id: String, actor_id: int, test_busy: bool) -> bool:
	var before: Dictionary = _state()
	var move_before := _move_audit()
	var completions_before := int(_presentation().get("completion_count", 0))
	var action: Control = app.call("ui_control", "ActionButton_" + action_id)
	if not _expect(action != null, "3D manual button exists: " + action_id):
		return false
	var repeat_point := action.get_global_transform_with_canvas() * (action.size * 0.5)
	if not await _click("ActionButton_" + action_id):
		return false
	if not _expect(_state().phase == "performing" and _presentation().get("route") == "workshop_3d_training", "real 3D combination enters host performing phase: " + action_id):
		return false
	var performing: Dictionary = _state()
	var pending: Dictionary = app.get("_session").pending_presentation()
	check(performing.stats.energy == int(before.stats.energy) - 22 and performing.stats.sword == int(before.stats.sword) + 10, action_id + " charges original energy22 and sword10 once")
	check(_elapsed_slots(performing) == _elapsed_slots(before) + 1 and int(performing.sequence) == int(before.sequence) + 1 and int(performing.counts.get(action_id, 0)) == int(before.counts.get(action_id, 0)) + 1, action_id + " advances one slot with one count and one receipt")
	check(not bool(app.get("_session").can_save()), "unfinished 3D practice is not a save boundary")
	check(_presentation().get("run_id", "") == pending.run_id and _presentation().get("operation_id", "") == pending.operation_id, "actual 3D presenter carries current host operation identity")
	check(_presentation().get("combo_move_ids", []).size() == int(COMBO_LENGTHS[action_id]), "selected manual starts its complete authored combination: " + action_id)
	if test_busy and not await _test_busy_input(actor_id, repeat_point, performing, pending):
		return false
	await _capture("practice_" + action_id + ".png", "actual 3D combination plays: " + action_id)
	if not _expect(await _wait_training_result(), "actual complete 3D combination reaches host result before deadline: " + action_id):
		return false
	var completed: Dictionary = _state()
	check(completed.stats == performing.stats and completed.counts == performing.counts and completed.receipts == performing.receipts and completed.sequence == performing.sequence, "natural 3D completion does not repeat any settlement: " + action_id)
	check(_training_actor() != null and _training_actor().get_instance_id() == actor_id, "training actor survives action and result UI rebuild: " + action_id)
	var presentation := _presentation()
	check(not bool(presentation.get("playing", true)) and bool(presentation.get("neutral", false)), "host result is shown after 3D actor stops in neutral: " + action_id)
	check(int(presentation.get("completion_count", 0)) == completions_before + 1, "each complete 3D combination reports completion once: " + action_id)
	var move_after := _move_audit()
	var begun := int(move_after.get("begin_count", 0)) - int(move_before.get("begin_count", 0))
	var finished := int(move_after.get("finish_count", 0)) - int(move_before.get("finish_count", 0))
	check(begun == int(COMBO_LENGTHS[action_id]) and begun == finished and int(move_after.get("cancel_count", 0)) == int(move_before.get("cancel_count", 0)), "every authored combination move begins and finishes once without cancel or replay: " + action_id)
	training_checkpoints.append({"manual": action_id, "before": before, "performing": performing,
		"completed": completed, "move_before": move_before, "move_after": move_after, "presentation": presentation})
	return true


func _test_busy_input(actor_id: int, repeat_point: Vector2, performing: Dictionary, pending: Dictionary) -> bool:
	var returning: Control = app.call("ui_control", "ReturnTrainingGroundButton")
	if not _expect(returning is BaseButton and (returning as BaseButton).disabled, "busy 3D practice keeps return control disabled"):
		return false
	var return_point := returning.get_global_transform_with_canvas() * (returning.size * 0.5)
	var cancel_before := int(_move_audit().get("cancel_count", 0))
	await _raw_click(repeat_point)
	await _raw_click(return_point)
	check(_state() == performing and _training_open(), "real busy repeat/return pointer input cannot recharge or leave training")
	if not await _click("MenuButton"):
		return false
	check(_state() == performing and _training_actor() != null and _training_actor().get_instance_id() == actor_id, "opening busy menu retains exact host state and persistent 3D actor")
	check(_button_disabled("SaveButton") and _button_disabled("LoadButton") and _button_disabled("NewRunButton"), "busy menu blocks save, load and restart")
	var save: Control = app.call("ui_control", "SaveButton")
	await _raw_click(save.get_global_transform_with_canvas() * (save.size * 0.5))
	check(_state() == performing and not bool(app.get("_store").has_save(app.get("_session").pack)), "actual pointer input on disabled save writes no checkpoint")
	await _key_escape()
	check(not _has_control("JourneyMenuPanel") and _state() == performing, "Escape closes menu without canceling or settling busy practice")
	check(_training_actor() != null and _training_actor().get_instance_id() == actor_id and _presentation().get("operation_id", "") == pending.operation_id, "menu rebuild and Escape retain same actor and in-flight operation")
	check(int(_move_audit().get("cancel_count", 0)) == cancel_before, "menu interaction never cancels real motion playback")
	check(str(_presentation().get("error", "")).is_empty() and bool(_presentation().get("playing", false)), "rejected busy UI requests do not poison or stop the in-flight presentation")
	return true


func _rest_in_training() -> bool:
	var before: Dictionary = _state()
	if not await _click("ActionButton_rest_practice"):
		return false
	check(_training_open() and _state().phase == "result" and int(_state().stats.energy) == mini(int(before.stats.energy) + 34, 100) and _elapsed_slots(_state()) == _elapsed_slots(before) + 1, "necessary rest uses existing capped recovery and one time slot inside training")
	return await _close_result()


func _test_training_save_load(actor_id: int) -> bool:
	var saved: Dictionary = _state()
	if not _expect(saved.phase == "result" and _training_open(), "completed 3D combination is an actual safe result checkpoint"):
		return false
	if not await _click("MenuButton") or not await _click("SaveButton"):
		return false
	check(_state() == saved and bool(app.get("_store").has_save(app.get("_session").pack)), "3D result saves exact host state without changing transient scene")
	if not await _click("LoadButton") or not await _click("ConfirmCancelButton"):
		return false
	check(_state() == saved and _training_open() and _training_actor() != null and _training_actor().get_instance_id() == actor_id, "canceling actual load preserves 3D context, actor and saved result")
	if not await _close_journey_menu() or not await _close_result() or not await _rest_in_training():
		return false
	var changed: Dictionary = _state()
	check(changed != saved and _training_open(), "actual rest changes state before restore while retaining 3D context")
	if not await _click("MenuButton") or not await _click("LoadButton") or not await _click("ConfirmAcceptButton") or not await _close_journey_menu():
		return false
	if not _expect(await _wait_for_snapshot(saved, 90), "successful UI load restores exactly saved date, stats, flags, counts, receipts and result"):
		return false
	check(not _training_open() and _presentation().get("route") == "painted_2d_portrait", "successful load returns transient 3D training context to original 2D mountain")
	check(not bool(_presentation().get("playing", true)), "restored result does not restart a practice or replay its completion")
	await _capture("08_saved_result_restored_2d.png", "3D result safely restores to original 2D context")
	var restored: Dictionary = _state()
	await create_timer(0.5).timeout
	check(_state() == restored and not bool(_presentation().get("playing", true)), "natural frames after load cannot emit old completion and settle again")
	return await _close_result()


func _test_original_2d_practice() -> bool:
	if int(_state().stats.energy) < 22:
		if not await _click("ActionButton_rest_practice") or not await _close_result():
			return false
	for action_id: String in TRAINING_ACTIONS:
		check(_has_control("ActionButton_" + action_id) and not _button_disabled("ActionButton_" + action_id), "loaded 2D mountain still exposes its original manual: " + action_id)
	var before: Dictionary = _state()
	if not await _click("ActionButton_pine_wind"):
		return false
	check(_state().phase == "performing" and _presentation().get("route") == "painted_2d_portrait" and not _training_open(), "real original 2D manual remains playable through painted route")
	if not _expect(await _wait_training_result(), "original 2D practice finishes naturally after 3D restore"):
		return false
	check(int(_state().stats.energy) == int(before.stats.energy) - 22 and int(_state().stats.sword) == int(before.stats.sword) + 10 and _elapsed_slots(_state()) == _elapsed_slots(before) + 1 and int(_state().counts.get("pine_wind", 0)) == int(before.counts.get("pine_wind", 0)) + 1, "original 2D route retains one original-cost settlement")
	await _capture("09_original_2d_practice.png", "old painted practice remains available after 3D training and load")
	return await _close_result()


func _test_reset_clears_training_context() -> bool:
	if not await _click("EnterTrainingGroundButton"):
		return false
	if not _expect(_training_open(), "reset test starts with an actually open 3D training context"):
		return false
	var old_run := str(_state().run_id)
	if not await _click("MenuButton") or not await _click("NewRunButton") or not await _click("ConfirmAcceptButton") or not await _close_journey_menu():
		return false
	var reset: Dictionary = _state()
	check(reset.run_id != old_run and reset.scene == "tingyu_corridor" and reset.phase == "ready" and reset.counts.is_empty() and reset.receipts.is_empty() and int(reset.stats.sword) == 0, "confirmed new game clears all earlier training settlements")
	check(not _training_open() and not _has_control("TrainingGroundSurface") and not _has_control("ReturnTrainingGroundButton"), "new game clears transient 3D context and controls")
	await create_timer(0.5).timeout
	check(_state() == reset and not bool(_presentation().get("playing", false)), "natural post-reset frames cannot finish or settle the previous run again")
	await _capture("10_training_reset.png", "new journey begins in corridor with training context cleared")
	return true


func _training_open() -> bool:
	return bool(_audit().get("training_ground_open", false))


func _training_actor() -> Control:
	var candidate: Variant = app.call("ui_control", "TrainingGroundActor")
	return candidate as Control if candidate is Control and is_instance_valid(candidate) else null


func _move_audit() -> Dictionary:
	var actor := _training_actor()
	if actor == null:
		return {}
	var snapshot: Dictionary = actor.call("presentation_snapshot")
	return snapshot.get("stage", {}).get("move_player", {}).duplicate(true)


func _check_training_layout(label: String) -> void:
	await _check_layout(label, ["HeaderPanel", "TrainingGroundSurface", "ReturnTrainingGroundButton", "ActionButton_pine_wind", "ActionButton_swift_swallow", "ActionButton_rest_practice"])
	for id: String in ["ActionButton_return_to_corridor", "ActionButton_go_to_town", "BeginAmbushButton"]:
		check(not _has_control(id), "3D practice keeps travel and combat controls outside its action list: " + id)


func _wait_training_result() -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		if str(_state().get("phase", "")) == "result":
			return true
		await process_frame
	return str(_state().get("phase", "")) == "result"


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	var report := {"test": "cultivation_training_ground_render", "checks": checks, "failures": failures,
		"failure_messages": failure_messages, "qa_size": [qa_size.x, qa_size.y],
		"display_server": DisplayServer.get_name(), "captures": captures,
		"training_checkpoints": training_checkpoints, "input_actions": input_actions,
		"input_method": "Godot root.push_input mouse/key events; natural playback; no state or completion injection",
		"result": "PASS" if failures == 0 else "FAIL"}
	var file := FileAccess.open(_absolute_output_dir().path_join("cultivation-training-ground-render-report.json"), FileAccess.WRITE)
	if file == null:
		failures += 1
		push_error("Could not write training-ground render report")
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("CULTIVATION_TRAINING_GROUND_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(0 if failures == 0 else 1)
