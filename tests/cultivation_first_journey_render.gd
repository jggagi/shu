extends "res://tests/cultivation_engine_mentor_loop_render.gd"
## One uninterrupted player route, using actual Godot mouse input throughout.
## No state injection, direct action settlement or simulated motion completion.

const JourneyScene := preload("res://scenes/demos/cultivation_engine_v07_first_journey.tscn")
var route_checkpoints: Dictionary = {}
var expected_victory := false
var input_actions: Array[String] = []
var layout_measurements: Array[Dictionary] = []


func _run() -> void:
	output_dir = "res://.local/qa/first-journey/render"
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	check(DirAccess.make_dir_recursive_absolute(_absolute_output_dir()) == OK, "journey QA output directory is available")
	check(DisplayServer.get_name() != "headless", "journey QA uses a real rendered display")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	test_store_dir = "user://first_journey_ui_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(test_store_dir)), "fresh QA storage is separate from all player checkpoints")
	app = JourneyScene.instantiate() as Control
	app.set("save_base_dir", test_store_dir)
	root.add_child(app)
	var launch_deadline := Time.get_ticks_msec() + 20000
	while _state().is_empty() and Time.get_ticks_msec() < launch_deadline:
		await process_frame
	check(str(app.get("_store").get("base_dir")) == test_store_dir, "the first catalog scan and every UI save use only QA storage")
	if not _expect(not _state().is_empty(), "the chapter automatically launches its fresh session within the wall-clock deadline"):
		_finish()
		return
	if not await _journey_route():
		await _capture("failure_context.png", "the actual visible UI where the route stopped")
	_finish()


func _journey_route() -> bool:
	check(_pack_id() == "shu_first_journey", "new journey entry loads its own isolated content pack")
	if not _expect(_state().get("scene") == "tingyu_corridor" and _state().get("phase") == "ready", "a new journey begins with cultivation in the corridor"):
		return false
	check(_battle_view() == null, "new game does not skip cultivation and jump into combat")
	route_checkpoints["opening"] = _state()
	await _check_default_page("opening corridor")
	await _capture("00_corridor.png", "first journey begins in the mentor's corridor")
	if not await _check_journey_menu():
		return false
	if not await _click("ActionButton_talk_mentor"):
		return false
	for index: int in range(4):
		if not await _click("DialogContinueButton"):
			return false
	check(_state().get("phase") == "event" and _state().get("event", {}).get("node") == "choice", "same-scene mentor dialogue reaches its real choice")
	await _check_layout("mentor choice", ["ScenePanel", "PhasePanel", "ChoiceButton_take_lesson", "ChoiceButton_return_to_practice"])
	await _capture("01_mentor_choice.png", "mentor offers the cost-bearing and independent-practice choices")
	if not await _click("ChoiceButton_take_lesson") or not await _finish_event():
		return false
	check(_flag("mentor_lesson_heard") and _flag("mentor_lesson_accepted"), "finishing the real dialogue records the accepted lesson")
	check(int(_state().stats.energy) == 92, "the mentor choice charges its actual eight energy once")
	if not await _close_result() or not await _click("ActionButton_go_to_mountain") or not await _close_result():
		return false
	check(_presentation().get("route") == "painted_2d_portrait" and bool(_presentation().get("prepared", false)), "the painted mountain uses its actual matching 2D portrait presenter")
	check(_presentation().get("texture_path") == "res://assets/art/back_mountain_training/actor-sheet.png", "the visible mountain actor comes from the original painted sheet")
	await _capture("02a_painted_mountain.png", "the 2D mountain and original 2D portrait share the same painted style")
	var portrait: Control = app.get("_presentation_player")
	var before_missing: Dictionary = _state()
	portrait.set("_prepared", false)
	if not await _click("ActionButton_pine_wind"):
		return false
	check(_state() == before_missing, "an unavailable painted presenter rejects practice before any charge or receipt")
	check(bool(app.get("_status_is_error")), "unavailable portrait produces a visible error instead of silently charging")
	portrait.set("_prepared", true)
	if not await _click("ActionButton_pine_wind"):
		return false
	check(_state().get("phase") == "performing", "clicking the sword action starts the real painted practice presentation")
	check(not bool(app.get("_session").can_save()), "unfinished sword motion remains outside safe checkpoint phases")
	await create_timer(0.3).timeout
	check(_presentation().get("route") == "painted_2d_portrait" and bool(_presentation().get("playing", false)), "actual training continues through the painted route")
	check(_presentation().get("loaded_action_atlas_paths") == ["res://assets/art/back_mountain_training/actor-sheet.png"], "practice draws original art instead of the model render atlas")
	await _capture("02_training.png", "the painted portrait practices before returning a real host result")
	if not _expect(await _wait_for_phase("result", 240), "the real practice presentation completes within its bounded deadline"):
		return false
	check(_flag("mentor_practice_finished") and int(_state().stats.sword) == 10, "completed practice has the real training result")
	check(int(_state().counts.get("pine_wind", 0)) == 1, "one UI practice submits exactly one stable manual count")
	route_checkpoints["trained"] = _state()
	if not await _close_result() or not await _click("ActionButton_return_to_corridor") or not await _close_result() or not await _click("ActionButton_go_to_town") or not await _close_result():
		return false
	check(_state().scene == "shanxia_town" and _flag("town_visited"), "the same cultivated session reaches the town")
	await _check_default_page("town arrival")
	await _check_layout("town walking surface", ["TownWalker"])
	await _capture("03_town.png", "arrival in the walkable HD2D town after training")
	if not await _check_town_menu_block():
		return false
	var before_greeting: Dictionary = _state()
	if not await _walk_to_interaction("tea_seller"):
		return false
	check(_flag("town_tea_greeted"), "walking to the tea seller triggers the registered near interaction")
	check(_state().stats == before_greeting.stats and _state().day == before_greeting.day and _state().slot == before_greeting.slot, "ordinary walking and reading do not spend cultivation resources or time")
	if not await _close_result():
		return false
	if not _flag("journey_commission"):
		var commission := _action_setting("journey_commission")
		if not _expect(not commission.is_empty(), "the journey exposes a registered commission action") or not await _click("ActionButton_" + commission) or not await _finish_event() or not await _close_result():
			return false
	if not _expect(_flag("journey_commission"), "the accepted commission survives in the authoritative session"):
		return false
	route_checkpoints["commission"] = _state()
	await _check_default_page("commission accepted")
	await _check_layout("commission action", ["BeginAmbushButton"])
	await _capture("04_commission.png", "the town commission is accepted before the encounter")
	if not await _click("BeginAmbushButton"):
		return false
	for frame: int in range(6):
		await process_frame
	if not _expect(_battle_view() != null and _state().phase == "ambush", "the commissioned journey enters the real battle"):
		return false
	check(not bool(app.get("_session").can_save()), "live battle is not a safe checkpoint")
	await _check_battle_layout()
	await _capture("05_encounter.png", "the existing spatial encounter is reached from the chapter")
	var before_battle: Dictionary = route_checkpoints.commission
	if not await _resolve_journey_encounter():
		return false
	for frame: int in range(6):
		await process_frame
	check(_battle_view() == null and _state().scene == "shanxia_town", "the actual encounter returns to the same town session")
	check(_flag("ambush_resolved") and _flag("ambush_victory") == expected_victory and _flag("ambush_defeat") != expected_victory, "the real encounter records its actual expected outcome")
	check(int(_state().sequence) == int(before_battle.sequence) + 1, "the encounter submits one battle settlement")
	check(_elapsed_slots(_state()) == _elapsed_slots(before_battle) + 1, "the encounter spends exactly one game time unit")
	await _capture("06_retreat.png", "the encounter returns to a safe result without blocking the chapter")
	if not await _close_result() or not await _walk_to_interaction("mountain_exit"):
		return false
	check(_state().scene == "tingyu_corridor" and _flag("town_returned"), "the player walks to the exit and returns to the mentor")
	if not await _close_result():
		return false
	var report_action := _action_setting("journey_complete")
	if report_action.is_empty():
		report_action = "journey_report"
	if not await _click("ActionButton_" + report_action) or not await _finish_event():
		return false
	if not _expect(_flag("journey_complete") and _flag("journey_victory") == expected_victory and _flag("journey_defeat") != expected_victory, "the real encounter route reaches its truthful chapter ending"):
		return false
	route_checkpoints["ending"] = _state()
	check(bool(_audit().get("journey_ending_visible", false)), "the completed journey presents its distinct ending page")
	await _check_layout("chapter ending", ["HeaderPanel", "MenuButton", "JourneyEndingView", "JourneyEndingPanel", "JourneyEndingTitle", "JourneyEndingSummary", "JourneySaveButton", "JourneyContinueButton", "JourneyReplayButton"])
	check(not _has_control("LoadButton") and not _has_control("NewRunButton") and not _has_control("JournalPanel"), "the ending keeps secondary file controls and the journal inside the menu")
	await _capture("07_ending.png", "the chapter ends after reporting the actual escort outcome")
	if not await _click("JourneySaveButton"):
		return false
	var saved: Dictionary = _state()
	check(app.get("_store").has_save(app.get("_session").pack), "the actual save button creates an ending checkpoint")
	if not await _click("MenuButton") or not await _click("LoadButton") or not await _click("ConfirmAcceptButton"):
		return false
	if not await _close_journey_menu():
		return false
	check(await _wait_for_snapshot(saved, 90), "loading through the UI restores the exact ending, date, stats, flags, counts and receipts")
	check(_battle_view() == null and _voice_is_stopped() and not bool(_presentation().get("playing", false)), "continuing the ending does not replay battle, voice or practice rewards")
	await _capture("08_ending_restored.png", "the ending survives an actual UI save and continue")
	if not await _click("JourneyContinueButton"):
		return false
	check(not bool(_audit().get("journey_ending_visible", true)) and _flag("journey_complete") and _state().scene == "tingyu_corridor" and _state().phase == "ready", "the ending's continue button returns to cultivation while preserving the completed journey")
	check(int(_state().counts.get("journey_report", 0)) == 1 and int(_state().counts.get("ambush_win" if expected_victory else "ambush_loss", 0)) == 1, "continuing the ending adds no repeated report or battle settlement")
	await _check_default_page("continued cultivation")
	await _capture("09_continue_cultivation.png", "the finished chapter continues into the same cultivation session")
	if not await _click("MenuButton") or not await _click("NewRunButton") or not await _click("ConfirmAcceptButton"):
		return false
	if not await _close_journey_menu():
		return false
	check(_state().run_id != saved.run_id and _state().scene == "tingyu_corridor" and _state().phase == "ready", "confirmed restart creates a distinct ready corridor run")
	check(not _flag("journey_complete") and not _flag("journey_commission") and int(_state().stats.sword) == 0 and _state().counts.is_empty(), "restart clears the chapter, commission, training and old battle progress")
	check(_battle_view() == null, "restart still begins with cultivation instead of an automatic encounter")
	await _check_default_page("restarted cultivation")
	await _capture("10_restarted.png", "restart returns to the beginning of the complete journey")
	return true


func _resolve_journey_encounter() -> bool:
	# Default legacy route remains actual supported withdrawal.
	return await _check_battle_settings() and await _click("BattleSettingsButton") and await _click("ReturnButton")


func _action_setting(flag: String) -> String:
	var pack: Dictionary = app.get("_session").pack
	for id: String in pack.actions:
		var action: Dictionary = pack.actions[id]
		if bool(action.get("menu", false)) and bool(action.get("set_flags", {}).get(flag, false)) and _state().scene in action.get("scenes", []):
			return id
	return ""


func _flag(id: String) -> bool:
	return bool(_state().get("flags", {}).get(id, false))


func _elapsed_slots(state: Dictionary) -> int:
	var slots: Array = app.get("_session").pack.rules.clock.slots
	return int(state.day) * slots.size() + int(state.slot)


func _expect(condition: bool, description: String) -> bool:
	check(condition, description)
	return condition


func _finish_event() -> bool:
	for index: int in range(20):
		if str(_state().get("phase", "")) != "event":
			return true
		if not await _click("DialogContinueButton"):
			return false
	return _expect(false, "the event reaches its end within twenty real continue clicks")


func _close_result() -> bool:
	return await _click("ResultContinueButton") if str(_state().get("phase", "")) == "result" else true


func _battle_view() -> Control:
	return app.get("_ambush_view") as Control if is_instance_valid(app) and is_instance_valid(app.get("_ambush_view")) else null


func _fresh_control(control_name: String) -> Control:
	for frame: int in range(CONTROL_WAIT_FRAMES):
		var battle := _battle_view()
		var candidate: Variant = battle.call("ui_control", control_name) if battle != null else app.call("ui_control", control_name)
		if candidate is Control and is_instance_valid(candidate) and candidate.is_visible_in_tree():
			return candidate as Control
		await process_frame
	check(false, "visible real UI control %s appears within the bounded wait" % control_name)
	return null


func _click(control_name: String) -> bool:
	input_actions.append(control_name)
	return await super._click(control_name)


func _walk_to_interaction(id: String) -> bool:
	var session: RefCounted = app.get("_session")
	var map: Dictionary = session.pack.walks.scenes.get(_state().scene, {})
	var target: Dictionary = map.get("interactions", {}).get(id, {})
	if not _expect(not target.is_empty(), "the town registers the actual target " + id):
		return false
	var walker: Control = app.call("ui_control", "TownWalker")
	if not _expect(walker != null, "the actual town input surface exists"):
		return false
	var position: Array = target.position
	var local: Vector2 = walker.call("logical_to_local", Vector2(position[0], position[1]))
	var point: Vector2 = root.get_final_transform() * (walker.get_global_transform_with_canvas() * local)
	var before: Dictionary = _state()
	input_actions.append("TownWalker:" + id)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if int(_state().get("sequence", 0)) > int(before.sequence):
			await process_frame
			await process_frame
			return _expect(true, "walking reaches and executes the real " + id + " interaction")
		await process_frame
	return _expect(false, "walking reaches " + id + " within the real-time deadline")


func _check_battle_layout() -> void:
	var battle := _battle_view()
	var controls: Dictionary = battle.call("audit_snapshot").get("controls", {})
	var bounds := Rect2(Vector2.ZERO, app.size)
	for id: String in ["AmbushStage", "EndRoundButton", "BattleSettingsButton"]:
		var control: Control = battle.call("ui_control", id)
		check(control != null and control.is_visible_in_tree(), "battle core control is visible: " + id)
		if control != null:
			check(bounds.encloses(control.get_global_rect()), "battle core control fits the usable canvas: " + id)
	if controls.has("AmbushStage") and controls.has("EndRoundButton"):
		check(not (controls.AmbushStage as Rect2).intersects(controls.EndRoundButton), "end-round control does not cover the battlefield")
	var retreat: Control = battle.call("ui_control", "ReturnButton")
	check(retreat == null or not retreat.is_visible_in_tree(), "retreat is available through settings instead of the default tactical toolbar")


func _check_default_page(label: String) -> void:
	var names: Array[String] = ["HeaderPanel", "ScenePanel", "JourneyNextStep", "MenuButton"]
	await _check_layout(label, names)
	var measured: Dictionary = {}
	for id: String in names:
		var control: Control = app.call("ui_control", id)
		if control == null:
			continue
		var rect := control.get_global_rect()
		var a: Vector2 = root.get_final_transform() * rect.position
		var b: Vector2 = root.get_final_transform() * rect.end
		var physical := Rect2(a, b - a)
		check(Rect2(Vector2.ZERO, Vector2(qa_size)).encloses(physical), label + " keeps " + id + " inside the requested physical window")
		measured[id] = {"logical": rect, "physical": physical}
	var next_step: Control = app.call("ui_control", "JourneyNextStep")
	if next_step is Label:
		check((next_step as Label).get_line_count() == 1, label + " presents its next goal on one line")
	for id: String in ["InformationColumn", "StatsPanel", "GoalsPanel", "JourneyProgressPanel", "JournalPanel", "TownHelpPanel", "LocalSavePanel", "SceneDescription", "PhasePanel", "SaveButton", "LoadButton", "VoiceToggleButton", "NewRunButton"]:
		check(not _has_control(id), label + " does not keep the secondary control visible: " + id)
	layout_measurements.append({"label": label, "window": [qa_size.x, qa_size.y], "controls": measured})


func _check_journey_menu() -> bool:
	var before: Dictionary = _state()
	var behind: Control = app.call("ui_control", "ActionButton_talk_mentor")
	if not _expect(behind != null, "a real default activity is available before opening the menu"):
		return false
	var behind_point := behind.get_global_transform_with_canvas() * (behind.size * 0.5)
	if not await _click("MenuButton"):
		return false
	check(_state() == before, "opening the menu does not change date, phase, resources, flags, receipts or revision")
	await _check_layout("journey menu", ["JourneyMenuPanel", "SaveButton", "LoadButton", "VoiceToggleButton", "NewRunButton", "JournalPanel", "CloseJourneyMenuButton"])
	await _capture("00b_menu.png", "secondary file, voice and journal controls are grouped in the menu")
	await _raw_click(behind_point)
	check(_state() == before, "actual input at an underlying activity cannot settle through the open menu")
	if not await _close_journey_menu():
		return false
	check(_state() == before, "closing the menu preserves the entire authoritative state")
	if not await _click("MenuButton"):
		return false
	await _key_escape()
	check(not _has_control("JourneyMenuPanel") and _state() == before, "Escape closes the menu without entering dialogue or spending a game action")
	return true


func _close_journey_menu() -> bool:
	if _has_control("JourneyMenuPanel"):
		return await _click("CloseJourneyMenuButton")
	return true


func _check_town_menu_block() -> bool:
	var before: Dictionary = _state()
	var walker: Control = app.call("ui_control", "TownWalker")
	var map: Dictionary = app.get("_session").pack.walks.scenes.get(_state().scene, {})
	var target: Array = map.interactions.tea_seller.position
	var local: Vector2 = walker.call("logical_to_local", Vector2(target[0], target[1]))
	var point := walker.get_global_transform_with_canvas() * local
	if not await _click("MenuButton"):
		return false
	await _raw_click(point)
	check(_state() == before, "the open menu intercepts a real town NPC click without walking, accepting a commission or changing position")
	if not await _close_journey_menu():
		return false
	check(_state() == before, "closing the town menu restores scene input without a delayed queued interaction")
	return true


func _check_battle_settings() -> bool:
	var before: Dictionary = _state()
	var battle: Dictionary = _battle_view().call("audit_snapshot").get("battle", {}).duplicate(true)
	if not await _click("BattleSettingsButton"):
		return false
	var close: Control = _battle_view().call("ui_control", "CloseBattleSettingsButton")
	var retreat: Control = _battle_view().call("ui_control", "ReturnButton")
	check(close != null and close.is_visible_in_tree() and retreat != null and retreat.is_visible_in_tree(), "battle settings expose close and retreat controls")
	check(_state() == before and _battle_view().call("audit_snapshot").get("battle", {}) == battle, "opening battle settings changes neither the chapter nor the live battle")
	await _capture("05b_battle_settings.png", "non-tactical settings and retreat are available on demand")
	if not await _click("CloseBattleSettingsButton"):
		return false
	check(_state() == before and _battle_view().call("audit_snapshot").get("battle", {}) == battle, "closing battle settings does not consume a turn or settle the encounter")
	if not await _click("BattleSettingsButton"):
		return false
	await _key_escape()
	close = _battle_view().call("ui_control", "CloseBattleSettingsButton")
	check((close == null or not close.is_visible_in_tree()) and _state() == before and _battle_view().call("audit_snapshot").get("battle", {}) == battle, "Escape closes battle settings without a gameplay side effect")
	return true


func _raw_click(canvas_point: Vector2) -> void:
	var point: Vector2 = root.get_final_transform() * canvas_point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame
	await process_frame


func _key_escape() -> void:
	input_actions.append("KEY_ESCAPE")
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await process_frame
	await process_frame


func _capture(filename: String, description: String) -> void:
	await super._capture(filename, description)
	var item: Dictionary = captures[captures.size() - 1]
	item["sha256"] = FileAccess.get_sha256(_absolute_output_dir().path_join(str(item.file)))
	item["flags"] = _state().get("flags", {}).duplicate(true)
	item["battle_visible"] = _battle_view() != null


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_cleanup_store_dir()
	var report := {"test": "cultivation_first_journey_render", "checks": checks, "failures": failures,
		"failure_messages": failure_messages, "qa_size": [qa_size.x, qa_size.y],
		"display_server": DisplayServer.get_name(), "captures": captures,
		"route_checkpoints": route_checkpoints, "input_actions": input_actions, "layout_measurements": layout_measurements,
		"input_method": "Godot root.push_input mouse events; not browser or physical input",
		"result": "PASS" if failures == 0 else "FAIL"}
	var file := FileAccess.open(_absolute_output_dir().path_join("cultivation-first-journey-render-report.json"), FileAccess.WRITE)
	if file == null:
		failures += 1
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("CULTIVATION_FIRST_JOURNEY_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(0 if failures == 0 else 1)
