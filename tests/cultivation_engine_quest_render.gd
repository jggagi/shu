extends SceneTree

const TeaScene := preload("res://scenes/demos/cultivation_engine_v02_tea.tscn")
const DEFAULT_OUTPUT := "res://.local/qa/cultivation-engine-v02-tea/native"
const ALLOWED_QA_SIZES := [Vector2i(1152, 720), Vector2i(960, 600)]
const CONTROL_TIMEOUT_MS := 3500

var app: Control
var output_dir: String = DEFAULT_OUTPUT
var store_dir: String = ""
var qa_size: Vector2i = Vector2i(1152, 720)
var checks: int = 0
var failures: int = 0
var failure_messages: Array[String] = []
var captures: Array[Dictionary] = []
var _finished: bool = false
var _resource_floor_fixture_used: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.max_fps = 60
	_parse_user_args()
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	var absolute_output := ProjectSettings.globalize_path(_absolute_output_dir())
	var output_error := DirAccess.make_dir_recursive_absolute(absolute_output)
	check(output_error == OK or output_error == ERR_ALREADY_EXISTS, "the per-size native QA output directory is available")
	check(DisplayServer.get_name() != "headless", "native Tea UI test has a real display server")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = TeaScene.instantiate() as Control
	check(app != null, "the dedicated v0.2 Tea scene instantiates")
	if app == null:
		_finish()
		return
	root.add_child(app)
	await process_frame
	await process_frame
	var store: Variant = app.get("_store")
	check(store != null, "the Tea view creates its SaveStore")
	if store == null:
		_finish()
		return
	store_dir = _allocate_store_dir()
	if store_dir.is_empty():
		check(false, "an unused isolated native-save directory is allocated")
		_finish()
		return
	store.set("base_dir", store_dir)
	check(str(store.get("base_dir")) == store_dir, "all native save/load clicks use the isolated test directory")
	await process_frame
	if not await _click("PackSelectButton_0") or not await _click("PackStartButton_0"):
		_finish()
		return
	check(str(_audit().get("pack_id", "")) == "shu_entry" and str(_state().get("scene", "")) == "tingyu_corridor", "the real UI starts the authored Shu pack at its corridor")
	await _capture("00_corridor.png", "native Tea entry before the invitation")
	if not await _run_native_tea_journey():
		_finish()
		return
	if not await _run_native_motion_and_stream_regression():
		_finish()
		return
	_finish()


func _run_native_tea_journey() -> bool:
	var initial_run := str(_state().get("run_id", ""))
	if not await _click("ActionButton_tea_invitation"):
		return false
	check(str(_state().get("phase", "")) == "event", "a real UI click opens the commission dialogue")
	if not await _click("DialogCancelButton"):
		return false
	check(str(_state().get("phase", "")) == "ready" and str(_state().get("scene", "")) == "tingyu_corridor" and not bool(_state().get("flags", {}).get("tea_active", true)), "cancel before acceptance stays in the corridor without activating Tea")
	if not await _click("ActionButton_tea_invitation"):
		return false
	if not await _click("DialogContinueButton"):
		return false
	if not await _click("ChoiceButton_accept"):
		return false
	check(str(_state().get("phase", "")) == "ready" and str(_state().get("scene", "")) == "tea.sword_terrace" and bool(_audit().get("quest", {}).get("stage_complete", false)) == false, "real acceptance directly enters the ready Tea scene without a result acknowledgement")
	check(not _has_control("ResultContinueButton") and _has_control("QuestRestButton"), "accepted Tea shows in-branch controls and no primary acknowledgement button")
	if not _has_control("Object_tea_cup_first") or not _has_control("Object_tea_cup_second"):
		check(false, "the two authored cup hotspots are visible in the actual scene")
		return false
	await _capture("01_accepted_cups.png", "accepted quest with both actual scene object hotspots")

	var before_inspection: Dictionary = _state()
	if not await _click("Object_tea_cup_first"):
		return false
	check(str(_audit().get("selected_object", "")) == "tea.cup_first" and str(_state().get("phase", "")) == "ready", "a real first-cup click immediately opens its object popover")
	var after_inspection: Dictionary = _state()
	check(int(after_inspection.get("stats", {}).get("energy", -1)) == int(before_inspection.get("stats", {}).get("energy", -2)) and int(after_inspection.get("day", -1)) == int(before_inspection.get("day", -2)) and int(after_inspection.get("slot", -1)) == int(before_inspection.get("slot", -2)), "real cup inspection changes neither energy nor the authored clock")
	check(int(_audit().get("quest", {}).get("seen", -1)) == 1 and not bool(_audit().get("quest", {}).get("stage_complete", true)), "first native cup click moves the A/B progress to 1 / 2")
	if not await _check_anchor_layout("tea.cup_first", "tea.cup_second"):
		return false
	var repair_button := await _fresh_button("ObjectAction_tea_repair_cup_first")
	var ask_first_button := await _fresh_button("ObjectAction_tea_ask_first_cup")
	if repair_button == null or ask_first_button == null:
		return false
	check(repair_button.text.contains("22") and repair_button.text.contains("精力") and ask_first_button.text.contains("8") and ask_first_button.text.contains("精力"), "first-cup popover displays its actual 22 and 8 energy costs")
	await _capture("02_first_cup_popover.png", "first object anchor, description and authored action costs")

	# Checkpoint before the later popover-switch test inspects the second cup.
	if not await _click("SaveButton"):
		return false
	var one_cup_saved: Dictionary = _state()
	var store: Variant = app.get("_store")
	var active_session: Variant = app.get("_session")
	var active_pack: Dictionary = active_session.get("pack")
	check(bool(store.call("has_save", active_pack)), "the actual Save button writes an available one-cup checkpoint")
	check(one_cup_saved.get("flags", {}).get("tea_cup_first_seen", false) and not one_cup_saved.get("flags", {}).get("tea_cup_second_seen", false), "the saved checkpoint contains exactly one inspected cup")
	await _capture("04_one_cup_saved.png", "saved one-cup checkpoint before a later action")

	if not await _click("Object_tea_cup_second"):
		return false
	check(str(_audit().get("selected_object", "")) == "tea.cup_second" and _count_named(app, "ObjectPopover") == 1, "clicking the other cup replaces the popover instead of stacking one")
	if not await _check_anchor_layout("tea.cup_second", "tea.cup_first"):
		return false
	await _capture("03_second_cup_popover.png", "second object anchor after popover replacement")

	if not await _push_key(KEY_ESCAPE):
		return false
	check(str(_audit().get("selected_object", "")) == "" and not _has_control("ObjectCloseButton"), "Escape closes only the selected object popover")
	if not await _click("Object_tea_cup_first") or not await _click("ObjectCloseButton"):
		return false
	check(str(_audit().get("selected_object", "")) == "", "the popover's own close button clears its transient selection")
	if not await _click("Object_tea_cup_first"):
		return false
	var outside_target: Control = await _fresh_control("QuestProgressPanel")
	if outside_target == null:
		return false
	await _send_mouse_click(outside_target)
	check(str(_audit().get("selected_object", "")) == "", "an actual click outside the popover closes it without a gameplay acknowledgement")
	
	if not await _click("Object_tea_cup_first"):
		return false

	if not await _click("ObjectAction_tea_repair_cup_first"):
		return false
	var after_repair := _state()
	check(int(after_repair.get("stats", {}).get("energy", -1)) == int(one_cup_saved.get("stats", {}).get("energy", -2)) - 22 and str(after_repair.get("phase", "")) == "ready", "a real first-cup repair click spends 22 energy and needs no extra result click")
	check(_button_disabled("ObjectAction_tea_repair_cup_first"), "a once-settled repair control is disabled after its single real click")
	if not await _click("LoadButton"):
		return false
	check(_has_control("ConfirmAcceptButton") and _has_control("ConfirmCancelButton"), "loading over live Tea progress exposes the explicit confirmation controls")
	var before_load_cancel := _state()
	if not await _click("ConfirmCancelButton"):
		return false
	check(_state() == before_load_cancel and not _has_control("ConfirmAcceptButton"), "cancelling a load confirmation preserves the current transaction")
	if not await _click("LoadButton") or not await _click("ConfirmAcceptButton"):
		return false
	check(_state() == one_cup_saved and str(_audit().get("selected_object", "")) == "", "confirming Load restores the exact one-cup checkpoint and clears transient selection")
	check(bool(_audit().get("quest", {}).get("stage_complete", false)) == false and bool(_state().get("flags", {}).get("tea_first_repair_done", false)) == false, "one-cup load does not retain the later unsaved repair")
	await _capture("05_one_cup_loaded.png", "one-cup checkpoint after explicit load confirmation")

	if not await _click("Object_tea_cup_first") or not await _click("ObjectAction_tea_repair_cup_first"):
		return false
	check(int(_state().get("stats", {}).get("energy", -1)) == int(one_cup_saved.get("stats", {}).get("energy", -2)) - 22, "the restored checkpoint can settle its first repair exactly once")
	if not await _click("ObjectAction_tea_ask_first_cup"):
		return false
	check(int(_state().get("stats", {}).get("energy", -1)) == int(one_cup_saved.get("stats", {}).get("energy", -2)) - 30, "a real first-cup question settles its separate 8 energy cost")

	if not await _click("Object_tea_cup_second"):
		return false
	var second_ask_button := await _fresh_button("ObjectAction_tea_ask_second_cup")
	if second_ask_button == null:
		return false
	check(second_ask_button.text.contains("8") and second_ask_button.text.contains("精力"), "second-cup popover displays its authored 8 energy cost")
	var session: Variant = app.get("_session")
	var resource_fixture: Dictionary = _state().duplicate(true)
	resource_fixture["stats"]["energy"] = 7
	var resource_restore: Dictionary = session.call("restore", resource_fixture)
	_resource_floor_fixture_used = true
	check(bool(resource_restore.get("ok", false)), "explicit test-only Session.restore fixture sets energy below the ask cost without adding a player cheat")
	app.call("_render")
	second_ask_button = await _fresh_button("ObjectAction_tea_ask_second_cup")
	if second_ask_button == null:
		return false
	check(second_ask_button.disabled, "the actual second-cup question button is disabled below its 8 energy floor")
	var floor_state: Dictionary = _state()
	if not await _attempt_disabled_click("ObjectAction_tea_ask_second_cup", floor_state):
		return false
	var restored_resource: Dictionary = resource_fixture.duplicate(true)
	restored_resource["stats"]["energy"] = 70
	check(bool(session.call("restore", restored_resource).get("ok", false)), "test-only energy fixture restores the legal authored-cost journey")
	app.call("_render")
	if not await _click("ObjectAction_tea_ask_second_cup"):
		return false
	check(int(_state().get("stats", {}).get("energy", -1)) == 62, "second-cup question spends exactly 8 energy after the restored fixture")
	check(int(_audit().get("quest", {}).get("seen", -1)) == 2 and bool(_audit().get("quest", {}).get("stage_complete", false)) and not bool(_audit().get("quest", {}).get("complete", true)), "real second-cup click completes B while the whole quest remains incomplete")
	check(not _has_control("QuestReturnButton") and not _has_control("ResultContinueButton") and _has_control("QuestRestButton"), "B shows the boundary and rest control but no return or primary acknowledgement")
	await _capture("06_b_complete_boundary.png", "actual two-cup B boundary with the full quest still active")

	var rest_before := _state()
	if not await _click("QuestRestButton"):
		return false
	check(int(_state().get("stats", {}).get("energy", -1)) == 96 and int(_state().get("day", -1)) == int(rest_before.get("day", 0)) and int(_state().get("slot", -1)) == (int(rest_before.get("slot", 0)) + 1) % 6, "real in-branch rest restores authored energy and advances one slot without leaving B")
	check(str(_state().get("scene", "")) == "tea.sword_terrace" and bool(_audit().get("quest", {}).get("stage_complete", false)) and not bool(_audit().get("quest", {}).get("complete", true)), "rest preserves the active, nonterminal two-cup boundary")
	if not await _click("SaveButton"):
		return false
	active_session = app.get("_session")
	active_pack = active_session.get("pack")
	check(bool(store.call("has_save", active_pack)), "Save remains usable at the completed-stage boundary")

	var boundary_run := str(_state().get("run_id", ""))
	if not await _click("NewRunButton"):
		return false
	check(_has_control("ConfirmAcceptButton") and _has_control("ConfirmCancelButton"), "resetting a progressed quest requires its explicit confirmation")
	if not await _click("ConfirmCancelButton"):
		return false
	check(str(_state().get("run_id", "")) == boundary_run and str(_state().get("scene", "")) == "tea.sword_terrace", "cancelling the reset prompt preserves the completed-stage run")
	if not await _click("NewRunButton") or not await _click("ConfirmAcceptButton"):
		return false
	check(str(_state().get("run_id", "")) != boundary_run and str(_state().get("scene", "")) == "tingyu_corridor" and not bool(_state().get("flags", {}).get("tea_active", true)), "confirmed reset creates a clean new run without editing quest progress directly")
	check(str(_audit().get("quest", {}).get("id", "")) == "", "confirmed reset clears active quest presentation")
	await _capture("07_reset_corridor.png", "confirmed new run returns the UI to its authored start")
	return true


func _run_native_motion_and_stream_regression() -> bool:
	if not await _click("ActionButton_go_to_mountain"):
		return false
	if not await _click("ResultContinueButton"):
		return false
	if not await _click("ActionButton_pine_wind"):
		return false
	check(str(_state().get("phase", "")) == "performing" and int(_state().get("counts", {}).get("pine_wind", 0)) == 1, "the v0.2 Tea entry still settles a normal sword motion through real native input")
	var motion_deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < motion_deadline and str(_state().get("phase", "")) == "performing":
		await process_frame
	check(str(_state().get("phase", "")) == "result" and int(_state().get("stats", {}).get("energy", -1)) == 78 and int(_state().get("stats", {}).get("sword", -1)) == 10, "one native sword motion reaches its ordinary result with the authored cost and gain")
	if str(_state().get("phase", "")) != "result":
		await _capture("08_motion_timeout.png", "native sword motion did not reach its bounded real-clock result")
		return false
	await _capture("08_motion_result.png", "one ordinary sword motion after the Tea branch reset")
	if not await _click("ResultContinueButton") or not await _click("SwitchPackButton"):
		return false
	if not await _click("PackSelectButton_1") or not await _click("PackStartButton_1"):
		return false
	if _has_control("ConfirmAcceptButton") and not await _click("ConfirmAcceptButton"):
		return false
	check(str(_audit().get("pack_id", "")) == "stream_study" and str(_audit().get("quest", {}).get("id", "")) == "", "the independent Stream pack opens without inherited Tea quest state")
	if not await _click("ActionButton_walk_to_river"):
		return false
	check(str(_state().get("scene", "")) == "riverbank" and str(_state().get("phase", "")) == "result" and _state().get("stats", {}).get("stamina", -1) == 80, "Stream retains its ordinary real-input travel result in the Tea-enabled entry scene")
	await _capture("09_stream_result.png", "unchanged Stream pack input regression after Tea UI journey")
	return true


func _check_anchor_layout(selected_id: String, other_id: String) -> bool:
	for control_name: String in ["SceneSurface", "Object_" + _safe_name(selected_id), "Object_" + _safe_name(other_id), "ObjectPopover"]:
		var control: Control = await _fresh_control(control_name)
		if control == null:
			return false
	var scene_surface: Control = app.call("ui_control", "SceneSurface")
	var selected: Control = app.call("ui_control", "Object_" + _safe_name(selected_id))
	var other: Control = app.call("ui_control", "Object_" + _safe_name(other_id))
	var popover: Control = app.call("ui_control", "ObjectPopover")
	var scene_rect := scene_surface.get_global_rect()
	var selected_rect := selected.get_global_rect()
	var other_rect := other.get_global_rect()
	var popover_rect := popover.get_global_rect()
	check(scene_rect.encloses(selected_rect) and scene_rect.encloses(other_rect), "both authored cup anchors remain inside the visible Tea scene surface at %s" % selected_id)
	check(popover_rect.size.x > 0.0 and popover_rect.size.y > 0.0 and scene_rect.encloses(popover_rect), "popover for the %s anchor is clamped inside the scene surface" % selected_id)
	check(selected_rect.size.x > 0.0 and selected_rect.size.y > 0.0, "selected cup anchor %s keeps a clickable hit area" % selected_id)
	return scene_rect.encloses(popover_rect)


func _click(control_name: String) -> bool:
	var control: Control = await _fresh_control(control_name)
	if control == null:
		return false
	await _ensure_control_visible(control)
	control = await _fresh_control(control_name)
	if control == null:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		check(false, "real UI button %s is enabled before its click" % control_name)
		return false
	for _frame: int in range(3):
		await process_frame
	var prior_rect := Rect2()
	var stable_frames := 0
	var deadline := Time.get_ticks_msec() + CONTROL_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		control = await _fresh_control(control_name)
		if control == null:
			return false
		var rect := control.get_global_rect()
		stable_frames = stable_frames + 1 if rect == prior_rect else 0
		prior_rect = rect
		if stable_frames >= 3:
			break
		await process_frame
	check(stable_frames >= 3, "real UI hit rectangle stabilizes before clicking %s" % control_name)
	if stable_frames < 3:
		return false
	control = await _fresh_control(control_name)
	if control == null:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		check(false, "real UI button %s remains enabled at click time" % control_name)
		return false
	var was_button: bool = control is BaseButton
	var fired: Array[bool] = [false]
	if was_button:
		var callback: Callable = func() -> void: fired[0] = true
		(control as BaseButton).pressed.connect(callback, CONNECT_ONE_SHOT)
	await _send_mouse_click(control)
	if was_button:
		check(fired[0], "root.push_input dispatches an actual native click to %s" % control_name)
		if not fired[0]:
			await _capture("input_failure_%s.png" % _safe_name(control_name), "real mouse input failed for " + control_name)
			return false
	await process_frame
	await process_frame
	return true


func _send_mouse_click(control: Control) -> void:
	var canvas_point: Vector2 = control.get_global_transform_with_canvas() * (control.size * 0.5)
	var point: Vector2 = root.get_final_transform() * canvas_point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await process_frame
	await process_frame
	var hovered: Control = root.gui_get_hovered_control()
	if hovered != control and not (is_instance_valid(hovered) and control.is_ancestor_of(hovered)):
		print("INPUT_HIT_TRACE ", JSON.stringify({"wanted":str(control.get_path()),"rect":str(control.get_global_rect()),"point":str(point),"hovered":str(hovered.get_path()) if is_instance_valid(hovered) else "none"}))
	for pressed: bool in [true, false]:
		# One gesture stays in one dispatch frame so unrelated desktop pointer
		# updates cannot split a synthetic native press from its release.
		root.push_input(motion.duplicate())
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
	await process_frame
	await process_frame


func _push_key(key: int) -> bool:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	root.push_input(event)
	await process_frame
	return true


func _ensure_control_visible(control: Control) -> void:
	var ancestor: Node = control
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(control)
		ancestor = ancestor.get_parent()
	await process_frame
	await process_frame


func _attempt_disabled_click(control_name: String, expected_state: Dictionary) -> bool:
	var control: Control = await _fresh_control(control_name)
	if control == null or not control is BaseButton:
		check(false, "%s is exposed as a real disabled button" % control_name)
		return false
	await _ensure_control_visible(control)
	control = await _fresh_control(control_name)
	if control == null or not control is BaseButton:
		check(false, "%s remains an actual disabled button after scrolling into view" % control_name)
		return false
	var button := control as BaseButton
	var was_disabled: bool = button.disabled
	check(was_disabled, "%s is disabled at the tested resource floor" % control_name)
	await _send_mouse_click(button)
	check(_state() == expected_state, "a real click on disabled %s leaves the complete game state unchanged" % control_name)
	return was_disabled and _state() == expected_state


func _fresh_button(control_name: String) -> Button:
	var control: Control = await _fresh_control(control_name)
	if control is Button:
		return control as Button
	if control != null:
		check(false, "%s is an actual Button control" % control_name)
	return null


func _fresh_control(control_name: String) -> Control:
	var deadline := Time.get_ticks_msec() + CONTROL_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		if app != null and is_instance_valid(app):
			var candidate: Variant = app.call("ui_control", control_name)
			if candidate is Control and is_instance_valid(candidate) and (candidate as Control).is_visible_in_tree():
				return candidate as Control
		await process_frame
	check(false, "visible UI control %s appears before the real-clock deadline" % control_name)
	return null


func _button_disabled(control_name: String) -> bool:
	var control: Control = app.call("ui_control", control_name) if app != null and is_instance_valid(app) else null
	if control is BaseButton and is_instance_valid(control):
		return (control as BaseButton).disabled
	check(false, "%s exposes its actual button state" % control_name)
	return true


func _has_control(control_name: String) -> bool:
	if app == null or not is_instance_valid(app):
		return false
	var control: Variant = app.call("ui_control", control_name)
	return control is Control and is_instance_valid(control) and (control as Control).is_visible_in_tree()


func _count_named(root_node: Node, wanted_name: String) -> int:
	var count := 1 if root_node.name == wanted_name and root_node is Control and (root_node as Control).is_visible_in_tree() else 0
	for child: Node in root_node.get_children():
		count += _count_named(child, wanted_name)
	return count


func _state() -> Dictionary:
	var state_value: Variant = _audit().get("state", {})
	return state_value as Dictionary if state_value is Dictionary else {}


func _audit() -> Dictionary:
	if app == null or not is_instance_valid(app):
		return {}
	var value: Variant = app.call("audit_snapshot")
	return value as Dictionary if value is Dictionary else {}


func _capture(filename: String, description: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var prefix := "%dx%d_" % [qa_size.x, qa_size.y]
	var path := _absolute_output_dir().path_join(prefix + filename)
	var saved := image.save_png(path)
	check(saved == OK and image.get_size() == qa_size, "native QA capture is written at the requested size: " + filename)
	captures.append({
		"file": prefix + filename,
		"description": description,
		"pixels": [image.get_width(), image.get_height()],
		"pack_id": str(_audit().get("pack_id", "")),
		"phase": str(_state().get("phase", "")),
		"scene": str(_state().get("scene", "")),
		"quest": _audit().get("quest", {}).duplicate(true),
		"selected_object": str(_audit().get("selected_object", ""))
	})


func _parse_user_args() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var argument := str(args[index])
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
	var parts := value.to_lower().split("x")
	if parts.size() != 2:
		check(false, "--qa-size uses WIDTHxHEIGHT")
		return
	var requested := Vector2i(int(parts[0]), int(parts[1]))
	if not ALLOWED_QA_SIZES.has(requested):
		check(false, "--qa-size is one of the two contract viewport sizes")
		return
	qa_size = requested


func _absolute_output_dir() -> String:
	if output_dir.begins_with("res://") or output_dir.begins_with("user://"):
		return ProjectSettings.globalize_path(output_dir)
	return output_dir


func _allocate_store_dir() -> String:
	for attempt: int in range(20):
		var candidate := "user://cultivation_engine_v02_tea_native_%d_%d" % [Time.get_ticks_usec(), attempt]
		var absolute := ProjectSettings.globalize_path(candidate)
		if not DirAccess.dir_exists_absolute(absolute) and not FileAccess.file_exists(candidate):
			return candidate
	return ""


func _safe_name(value: String) -> String:
	var result := ""
	for character: String in value:
		result += character if character.is_valid_identifier() else "_"
	return result


func _cleanup_store_dir() -> void:
	if store_dir.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(store_dir)
	for pack_id: String in ["shu_entry", "stream_study"]:
		var pack_path := absolute.path_join(pack_id)
		for slot: int in range(2):
			for suffix: String in [".json", ".json.pending"]:
				var candidate := pack_path.path_join("checkpoint_%d%s" % [slot, suffix])
				if FileAccess.file_exists(candidate):
					DirAccess.remove_absolute(candidate)
		if DirAccess.dir_exists_absolute(pack_path):
			DirAccess.remove_absolute(pack_path)
	if DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)
	DirAccess.remove_absolute(absolute)


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
		"test": "cultivation_engine_quest_render",
		"checks": checks,
		"failures": failures,
		"failure_messages": failure_messages,
		"captures": captures,
		"qa_size": [qa_size.x, qa_size.y],
		"display_server": DisplayServer.get_name(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"engine_max_fps": Engine.max_fps,
		"isolated_save_directory": true,
		"resource_floor_fixture_uses_session_restore": _resource_floor_fixture_used,
		"result": "PASS" if failures == 0 else "FAIL"
	}
	var report_path := _absolute_output_dir().path_join("cultivation-engine-quest-render-report.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		failures += 1
		push_error("Could not write quest render report: " + report_path)
	else:
		report["failures"] = failures
		report["result"] = "PASS" if failures == 0 else "FAIL"
		report_file.store_string(JSON.stringify(report, "\t") + "\n")
		report_file.flush()
		if report_file.get_error() != OK:
			failures += 1
			push_error("Quest render report write failed: " + report_path)
		report_file.close()
	print("CULTIVATION_ENGINE_QUEST_RENDER: %d checks / %d captures / %d failures" % [checks, captures.size(), failures])
	quit(failures)
