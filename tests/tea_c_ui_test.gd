extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const CUP_IDS := ["tea.cup_first", "tea.cup_second"]
const COURTYARD_ID := "tea.old_courtyard"
const TERRACE_ID := "tea.sword_terrace"
const C_OBJECT_IDS := ["tea.household", "tea.coats", "tea.medicine_pot", "tea.window", "tea.ledger"]

var app
var checks := 0
var failures := 0
var capture_render := false

func _initialize() -> void:
	capture_render = OS.get_cmdline_user_args().has("--render") and DisplayServer.get_name() != "headless"
	if capture_render: root.mode = Window.MODE_WINDOWED
	app = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	check(app.state.tea_scene_id == app.state.TEA_TERRACE_ID, "new UI run starts on the sword terrace")
	check(not app.tea_paths["tea.path_old_courtyard"].visible, "courtyard entrance is hidden before A/B is complete")
	check(not app.tea_hotspots["tea.household"].visible, "courtyard props are hidden on the initial terrace")
	app._open_tea()
	app._tea_accept()
	check(app.state.tea_active and app.state.tea_accepted, "accepted commission opens the tea branch")
	check(not app.tea_paths["tea.path_old_courtyard"].visible, "courtyard remains locked before either cup is viewed")
	app.tea_hotspots[CUP_IDS[0]].emit_signal("pressed")
	check(app.state.tea_seen.size() == 1 and not app.tea_paths["tea.path_old_courtyard"].visible, "one cup does not reveal the courtyard path")
	app.tea_hotspots[CUP_IDS[1]].emit_signal("pressed")
	check(app.state.tea_seen.size() == 2 and app.tea_paths["tea.path_old_courtyard"].visible, "viewing both cups reveals the courtyard path")
	check_path_hint("tea.path_old_courtyard", "前往旧院 →")
	check(not app.state.tea_c_complete and not app.state.tea_quest_complete, "A/B UI completion leaves C and whole-quest completion separate")
	check_branch_chrome_hidden()

	var terrace_backdrop: String = app.tea_backdrop.texture.resource_path
	var terrace_session: int = app.tea_session
	app.tea_paths["tea.path_old_courtyard"].emit_signal("pressed")
	check(app.state.tea_scene_id == COURTYARD_ID and app.tea_session > terrace_session, "entering the courtyard updates the scene and session")
	check(app.tea_title.text == app.tea_data.courtyard.title, "courtyard title replaces terrace title")
	check(app.tea_backdrop.texture.resource_path.ends_with("tea-courtyard-reference-v1.png") and app.tea_backdrop.texture.resource_path != terrace_backdrop, "courtyard backdrop replaces terrace artwork")
	check_courtyard_props()
	check_branch_chrome_hidden()
	check(not app.tea_return.visible and app.tea_rest.visible, "incomplete C stays in the branch and keeps in-branch rest available")
	if capture_render:
		await capture_current_state("courtyard-entry")

	var before_rejected_ledger: Dictionary = c_progress_snapshot()
	app.tea_hotspots["tea.ledger"].emit_signal("pressed")
	check(c_progress_snapshot() == before_rejected_ledger, "ledger rejection leaves C progress unchanged")
	check(app.selected_object_id.is_empty() and not app.object_popover.visible, "rejected ledger view leaves no selected object or popover")
	check(app.tea_journal_text.text.contains("先看看院中两副碗筷"), "ledger rejection is explained in the passive journal")
	check(not app.state.tea_c_complete, "rejected ledger does not complete C")

	app.tea_hotspots["tea.household"].emit_signal("pressed")
	await process_frame
	check(app.selected_object_id == "tea.household" and app.object_popover.visible, "household clue opens its anchored popover")
	check(app.object_popover.buttons.is_empty() and not popover_has_button(), "household clue needs no action or confirmation button")
	check_popover_bounds("tea.household")
	check_popover_text_fits("tea.household")
	check(app.tea_journal_entries.back() == app.tea_data.courtyard.objects["tea.household"].text, "household text is recorded as passive journal feedback")

	for object_id: String in ["tea.coats", "tea.medicine_pot", "tea.window"]:
		app.tea_hotspots[object_id].emit_signal("pressed")
		check(app.state.tea_c_seen.has(object_id) and not app.state.tea_c_complete, "%s is optional and cannot complete C" % object_id)
		check(app.tea_journal_text.text == app.tea_data.courtyard.objects[object_id].text, "%s publishes only its own short clue" % object_id)
		check(app.object_popover.buttons.is_empty() and not popover_has_button(), "%s has no action or confirmation path" % object_id)
		check_popover_bounds(object_id)
	check(not app.tea_journal_text.text.contains(app.tea_data.courtyard.impression), "optional props do not reveal the C impression")
	check(not app.state.tea_c_complete, "optional props do not set the C completion flag")

	app.tea_hotspots["tea.household"].emit_signal("pressed")
	app.tea_hotspots["tea.ledger"].emit_signal("pressed")
	await process_frame
	var ledger: Dictionary = app.tea_data.courtyard.objects["tea.ledger"]
	check(app.selected_object_id == "tea.ledger" and app.object_popover.visible, "ledger opens after the household prerequisite")
	check(app.object_popover.buttons.is_empty() and not popover_has_button(), "ledger is read directly without an action or confirmation button")
	check(popover_description_text() == ledger.text, "ledger popover presents the complete two-page source text")
	check(popover_description_text().contains("迁居问天峰") and popover_description_text().contains("其后第十一年"), "ledger popover preserves both dated entries")
	check(app.tea_journal_entries.size() >= 2 and app.tea_journal_entries[-2] == ledger.text, "complete ledger text enters the passive journal")
	check(app.tea_journal_text.text.contains(app.tea_data.courtyard.impression), "ledger reveal publishes the changed impression in the passive journal")
	check(app.state.tea_c_complete and not app.state.tea_quest_complete, "ledger completes C without completing the whole quest")
	check(not app.tea_return.visible, "C completion does not reveal a main-panel return")
	check_popover_bounds("tea.ledger")
	check_popover_text_fits("tea.ledger")
	if capture_render:
		await capture_current_state("ledger")

	var courtyard_session: int = app.tea_session
	app.tea_paths["tea.path_sword_terrace"].emit_signal("pressed")
	check(app.state.tea_scene_id == TERRACE_ID and app.tea_session > courtyard_session, "returning to the terrace creates a fresh scene session")
	check(app.state.tea_c_seen.has("tea.household") and app.state.tea_c_seen.has("tea.ledger") and app.state.tea_c_complete, "returning to the terrace preserves C clues and completion")
	check(app.tea_paths["tea.path_old_courtyard"].visible and not app.tea_paths["tea.path_sword_terrace"].visible, "completed C keeps the old-courtyard path available")
	app.tea_paths["tea.path_old_courtyard"].emit_signal("pressed")
	check(app.state.tea_scene_id == COURTYARD_ID and app.state.tea_c_complete, "re-entering the courtyard preserves C completion")
	check(app.state.tea_c_seen.size() == C_OBJECT_IDS.size(), "all five visible courtyard props retain their read flags")
	check(not app.state.tea_quest_complete and not app.tea_return.visible, "revisiting after C still cannot complete or exit the whole quest")
	var courtyard_clues_before_rest: Dictionary = app.state.tea_c_seen.duplicate(true)
	var cultivation_slot_before_rest: int = int(app.state.day) * app.state.rules.times.size() + int(app.state.time_index)
	app.state.energy = 50
	app._tea_rest()
	var cultivation_slot_after_rest: int = int(app.state.day) * app.state.rules.times.size() + int(app.state.time_index)
	check(app.state.energy > 50 and cultivation_slot_after_rest == cultivation_slot_before_rest + 1, "in-courtyard rest settles energy and advances one cultivation slot")
	check(app.state.tea_scene_id == COURTYARD_ID and app.state.tea_c_seen == courtyard_clues_before_rest and app.state.tea_c_complete, "in-courtyard rest preserves scene, C clues, and C completion")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	app._unhandled_key_input(escape)
	check(app.state.tea_active and app.state.tea_scene_id == COURTYARD_ID and app.state.tea_c_complete and not app.state.tea_quest_complete, "Escape after C completion keeps the player in the unfinished branch")

	var stale_session: int = app.tea_session
	app.tea_paths["tea.path_sword_terrace"].emit_signal("pressed")
	app.tea_hotspots[CUP_IDS[0]].emit_signal("pressed")
	var energy_before_stale_callback: int = app.state.energy
	var action_receipts_before_stale_callback: Dictionary = app.state.tea_action_done.duplicate(true)
	app._tea_action(CUP_IDS[0], "repair", stale_session)
	check(app.state.energy == energy_before_stale_callback and app.state.tea_action_done == action_receipts_before_stale_callback, "callback from the prior scene session cannot spend energy")
	check(app.state.tea_active and not app.state.tea_quest_complete, "stale action callback leaves the active branch intact")
	app._reset()
	check(app.state.tea_scene_id == app.state.TEA_TERRACE_ID and app.state.tea_c_seen.is_empty(), "reset returns to the terrace and clears C clues")
	check(not app.state.tea_c_complete and not app.state.tea_stage_complete and not app.state.tea_quest_complete, "reset clears C, A/B, and whole-quest completion flags")
	check(app.selected_object_id.is_empty() and not app.object_popover.visible and not app.tea_scene.visible, "reset clears the selected object, popover, and tea scene")
	check(not app.tea_paths["tea.path_old_courtyard"].visible and not app.tea_paths["tea.path_sword_terrace"].visible, "reset hides both scene paths")

	print("TEA_C_UI_TESTS: %d checks, %d failures" % [checks, failures])
	quit(failures)

func check_courtyard_props() -> void:
	for object_id: String in app.tea_hotspots:
		var expected_visible: bool = object_id in C_OBJECT_IDS
		check(app.tea_hotspots[object_id].visible == expected_visible, "%s visibility matches the courtyard prop set" % object_id)
	check(app.tea_paths["tea.path_sword_terrace"].visible, "courtyard exposes its return-to-terrace path")
	check_path_hint("tea.path_sword_terrace", "← 重访剑坪")
	check(not app.tea_paths["tea.path_old_courtyard"].visible, "courtyard hides its current-scene entrance path")

func check_path_hint(path_id: String, expected_text: String) -> void:
	var path = app.tea_paths[path_id]
	check(path.hint.visible and path.hint.text == expected_text, "%s shows its persistent navigation hint" % path_id)
	var hint_center: Vector2 = path.position + path.hint.position + path.hint.size / 2
	check(path.get_rect().has_point(hint_center), "%s navigation hint lies inside its clickable hit area" % path_id)

func check_branch_chrome_hidden() -> void:
	for node in [app.dialogue_panel, app.actions_panel, app.speaker, app.dialogue_text, app.result_text, app.shortcut_label, app.train_button, app.mentor_button, app.rest_button]:
		check(not node.visible, "%s stays hidden inside the tea branch" % node.name)
	check(app.tea_journal.visible and app.tea_rest.visible, "passive journal and branch rest remain available")

func check_popover_bounds(object_id: String) -> void:
	var rect: Rect2 = app.object_popover.get_rect()
	var object_rect: Rect2 = app._tea_rect(object_id)
	var should_be_below: bool = bool(app.tea_data.courtyard.objects[object_id].get("popover_below", false))
	check(Rect2(Vector2.ZERO, app.tea_scene.size).encloses(rect), "%s popover stays inside the scene" % object_id)
	if should_be_below:
		check(app.object_popover.below_object and rect.position.y >= object_rect.end.y + 5, "%s popover and pointer sit below its object" % object_id)
		check(absf(rect.position.y + app.object_popover.anchor_point.y - (object_rect.end.y + 5)) < 1, "%s below-object pointer anchor follows its lower edge" % object_id)
	else:
		check(not app.object_popover.below_object and rect.end.y <= object_rect.position.y - 5, "%s popover stays above its object" % object_id)
	check(absf(app.object_popover.anchor_point.x + rect.position.x - object_rect.get_center().x) < 1, "%s popover anchor follows its object" % object_id)

func check_popover_text_fits(object_id: String) -> void:
	var description := popover_description_label()
	check(description != null, "%s popover exposes a measured description label" % object_id)
	if description == null:
		return
	var required_height: float = float(description.get_line_count()) * float(description.get_line_height())
	print("TEA_C_TEXT_BOUNDS: id=%s position=%s size=%s popover_size=%s lines=%d visible=%d required_height=%.1f" % [object_id, description.position, description.size, app.object_popover.size, description.get_line_count(), description.get_visible_line_count(), required_height])
	check(description.get_visible_line_count() == description.get_line_count(), "%s description shows every measured text line" % object_id)
	check(required_height <= description.size.y + 1.0, "%s description text fits its measured line height" % object_id)
	check(description.position.x >= 0 and description.position.x + description.size.x <= app.object_popover.size.x, "%s description stays within popover width" % object_id)

func popover_has_button() -> bool:
	for child in app.object_popover.get_children():
		if child is Button:
			return true
	return false

func popover_description_label() -> Label:
	for child in app.object_popover.get_children():
		if child is Label and child.text == app.tea_data.courtyard.objects[app.selected_object_id].text:
			return child
	return null

func popover_description_text() -> String:
	var label := popover_description_label()
	return label.text if label != null else ""

func c_progress_snapshot() -> Dictionary:
	return {
		"scene": app.state.tea_scene_id,
		"clues": app.state.tea_c_seen.duplicate(true),
		"complete": app.state.tea_c_complete,
		"selected": app.selected_object_id,
		"energy": app.state.energy,
		"day": app.state.day,
		"time_index": app.state.time_index,
	}

func capture_current_state(state_name: String) -> void:
	root.mode = Window.MODE_WINDOWED
	await create_timer(0.2).timeout
	var original_size: Vector2i = root.size
	for size in [Vector2i(1152, 720), Vector2i(920, 575)]:
		root.size = size
		await process_frame
		await process_frame
		await create_timer(0.12).timeout
		var texture := root.get_texture()
		if texture == null:
			check(false, "%s render texture is available at %s" % [state_name, size])
			continue
		var image: Image = texture.get_image()
		# macOS applies native window/backbuffer resize asynchronously.
		for retry in range(20):
			if image.get_size() == size: break
			root.size = size
			await create_timer(0.05).timeout
			image = root.get_texture().get_image()
		var output_dir := ProjectSettings.globalize_path("res://.local/qa/tea-c")
		var mkdir_err := DirAccess.make_dir_recursive_absolute(output_dir)
		check(mkdir_err == OK or mkdir_err == ERR_ALREADY_EXISTS, "stage C screenshot directory is available")
		var path := output_dir.path_join("%s-%dx%d.png" % [state_name, size.x, size.y])
		var save_err := image.save_png(path)
		print("TEA_C_RENDER: state=%s requested=%s actual=%s path=%s save_error=%d" % [state_name, size, image.get_size(), path, save_err])
		check(save_err == OK and image.get_size() == size, "%s screenshot saves at %s" % [state_name, size])
	root.size = original_size
	await process_frame

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
