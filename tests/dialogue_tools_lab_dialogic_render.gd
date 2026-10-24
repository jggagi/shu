extends "res://tests/dialogue_tools_lab_render.gd"
## Real native Dialogic layout/choice input; shared screenshot/store helpers only.

var cleanup_started := false


func _finish() -> void:
	if cleanup_started:
		return
	cleanup_started = true
	if is_instance_valid(app) and bool(app.audit().get("busy",false)):
		app._cancel()
		await create_timer(0.25).timeout
	super._finish()


func _run() -> void:
	deadline_msec = Time.get_ticks_msec() + 45000
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size if qa_size != Vector2i.ZERO else Vector2i(1152,720)
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(_absolute_output_dir())
	check(DisplayServer.get_name() != "headless", "Dialogic uses actual Compatibility rendering")
	app = TrialScene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	isolated_store_dir = _allocate_store_dir()
	app.saves.base_dir = isolated_store_dir
	await _click_ui_rect("backend_dialogic")
	# Switching tools intentionally selects its own store. Override after switch.
	app.saves.base_dir = isolated_store_dir
	check(_audit().backend == "dialogic" and _is_ready_snapshot(_snapshot()), "B starts with the same new game")
	await _click_ui_rect("action_talk")
	await _pause(0.8)
	if not _healthy():
		_finish()
		return
	check(bool(_audit().tool.get("used_real_timeline",false)), "B runs the real Dialogic timeline")
	await _capture("00_native_opening.png", "Dialogic native text layout")
	if not await _reach_native_question():
		_finish()
		return
	await _capture("01_native_choices.png", "Dialogic native choices")
	var take: Button = _native_button("坐下来，随师父调息（精力8 · 1时辰）")
	check(take != null, "Native lesson choice button exists")
	if take == null:
		_finish()
		return
	await _click_rect(take.get_global_rect())
	await _pause(0.4)
	check(_stat(_snapshot(),"energy") == 92 and int(_snapshot().slot) == 1, "Native choice settles exactly 8 energy and one slot")
	check(_stat(_snapshot(),"understanding") == 1 and bool(_snapshot().flags.breathing_hint), "Native choice records lesson in Session")
	check(int(_snapshot().counts.get("claim_mentor_lesson",0)) == 1, "Lesson receipt/count is once")
	await _capture("02_native_accepted.png", "Native accepted branch and real HUD")
	if not await _finish_native_dialogue():
		_finish()
		return
	check(_audit().tool.get("used_real_timeline",false), "Completed trial retains real timeline evidence")
	await _click_ui_rect("advance")
	await _click_ui_rect("action_train")
	check(_stat(_snapshot(),"energy") == 70 and _stat(_snapshot(),"cultivation") == 18 and int(_snapshot().slot) == 3, "Returning from B gives exactly one training bonus")
	await _capture("03_native_training_result.png", "B returns to cultivation with actual result")
	await _click_ui_rect("advance")
	var saved: Dictionary = _snapshot().duplicate(true)
	await _click_ui_rect("footer_save")
	check(_has_checkpoint(), "B saved through shared SaveStore")
	await _click_ui_rect("footer_reset")
	await _click_ui_rect("footer_load")
	check(_snapshot() == saved, "B checkpoint restores the exact Session")
	await _click_ui_rect("footer_reset")
	await _click_ui_rect("action_talk")
	if not await _reach_native_question():
		_finish()
		return
	var decline: Button = _native_button("先回去自己试试")
	check(decline != null, "Native decline button exists")
	if decline != null:
		await _click_rect(decline.get_global_rect())
	if not await _finish_native_dialogue():
		_finish()
		return
	check(_stat(_snapshot(),"energy") == 100 and int(_snapshot().slot) == 0 and not bool(_snapshot().flags.breathing_hint), "B decline has no cost or bonus")
	await _click_ui_rect("advance")
	await _click_ui_rect("action_talk")
	await _pause(0.1)
	_send_escape_immediate()
	await _pause(0.2)
	check(not bool(_audit().busy) and _snapshot().phase != "event", "Escape retires native layout and Session dialogue")
	await _click_ui_rect("backend_dm")
	check(_audit().backend == "dm", "After B cancellation, tool A can be selected")
	check(get_nodes_in_group("dialogic_dialog_text").filter(func(n): return n.is_visible_in_tree()).is_empty(), "No visible Dialogic text left behind")
	check(str(_audit().failure).is_empty(), "No tool/controller failure")
	_finish()


func _pause(seconds: float) -> void:
	await create_timer(seconds).timeout


func _space() -> void:
	for pressed in [true,false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.physical_keycode = KEY_SPACE
		key.pressed = pressed
		Input.parse_input_event(key)
		await process_frame
	await _pause(0.25)


func _healthy() -> bool:
	if not str(_audit().get("failure", "")).is_empty():
		check(false, str(_audit().failure))
		return false
	return Time.get_ticks_msec() < deadline_msec


func _native_button(label: String) -> Button:
	for node in get_nodes_in_group("dialogic_choice_button"):
		if node is Button and node.is_visible_in_tree() and node.text == label:
			return node
	return null


func _reach_native_question() -> bool:
	for unused in range(25):
		if not _healthy():
			return false
		if _native_button("坐下来，随师父调息（精力8 · 1时辰）") != null and _audit().event.get("node_id", "") == "choice":
			await _pause(0.35)
			return true
		await _space()
	check(false, "Native question appeared in the bounded wait")
	return false


func _finish_native_dialogue() -> bool:
	for unused in range(15):
		if not _healthy():
			return false
		if not bool(_audit().busy) and _snapshot().phase == "result":
			return true
		await _space()
	check(false, "Native timeline returned to result")
	return false
