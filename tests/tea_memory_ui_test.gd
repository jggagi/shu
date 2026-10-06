extends SceneTree

const MainScene = preload("res://scenes/main.tscn")

var app
var checks := 0
var failures := 0
var standing_texture: Texture2D

func _initialize() -> void:
	app = MainScene.instantiate()
	root.add_child(app)
	await settle_ui()
	await test_cabinet_transition_and_present_guards()
	await test_full_memory_route_and_delayed_shot()
	await test_last_day_fade_and_reset_cancellation()
	await test_new_past_routing_and_guards()
	print("TEA_MEMORY_UI_TESTS: %d checks, %d failures" % [checks, failures])
	quit(failures)

func test_cabinet_transition_and_present_guards() -> void:
	await begin_fixture_branch()
	set_fixture_stage(2)
	var present_texture: Texture2D = app.tea_backdrop.texture
	var present_session: int = app.tea_session
	app.tea_hotspots["tea.cabinet"].emit_signal("pressed")
	await settle_ui()
	check(app.selected_object_id == "tea.cabinet" and app.object_popover.visible, "cabinet page one opens as an ordinary present-day document")
	check(not app.tea_memory.visible, "present-day cabinet page does not show the past view")
	check(_body_text() == _source_page("tea.cabinet", 0).text, "cabinet first page displays its exact authored text")
	check(app.object_popover.buttons.size() == 1, "cabinet first page exposes only its page-turn action")
	var first_turn: Button = _reading_buttons().get("page:%d" % app.state.tea_story_token)
	check(first_turn != null, "cabinet first page has a token-bound page action")
	check(first_turn != null and not first_turn.disabled, "ordinary present-day cabinet pages remain immediate")
	if first_turn == null:
		return
	first_turn.emit_signal("pressed")
	await settle_ui()
	check(app.tea_memory.visible and not app.object_popover.visible, "turning to the early diary excerpt enters the full-screen past")
	check(app.tea_memory.current_shot == "standing", "cabinet page two uses the standing past shot")
	# Check the first presentation before any stale callback refresh can resize it.
	var first_bubble: Control = app.tea_memory.body.get_parent()
	check(app.tea_memory.get_global_rect().encloses(first_bubble.get_global_rect()), "first past bubble fits the canvas without a second presentation")
	check(first_bubble.get_global_rect().encloses(app.tea_memory.body.get_global_rect()), "first past body fits its bubble")
	check(first_bubble.get_global_rect().encloses(app.tea_memory.buttons["continue"].get_global_rect()), "first past continue action is inside the visible bubble")
	check(app.tea_memory.backdrop.texture != null and app.tea_memory.backdrop.texture.resource_path != present_texture.resource_path, "past backdrop uses a different texture from the present courtyard")
	check(_body_text() == _source_page("tea.cabinet", 1).text, "cabinet past page keeps the exact original source text")
	check(_heading_text() == _expected_heading("tea.cabinet", 1), "cabinet past page keeps its source speaker and page order")
	check(app.tea_session == present_session and app.state.tea_scene_id == app.state.TEA_COURTYARD_ID, "entering the cabinet memory keeps the current courtyard session")
	check_present_scene_blocked()

	var read_snapshot := _host_snapshot()
	var saved_page_token: int = app.state.tea_story_token
	app._tea_rest()
	app._tea_path("tea.path_sword_terrace")
	app._tea_inspect("tea.record_early")
	await settle_ui()
	check(_host_snapshot() == read_snapshot, "direct rest, path, and inspection calls cannot alter state during the past")
	check(app.tea_memory.visible and app.selected_object_id == "tea.cabinet", "blocked present actions leave the current past view open")

	var outside_click := InputEventMouseButton.new()
	outside_click.button_index = MOUSE_BUTTON_LEFT
	outside_click.pressed = true
	outside_click.position = Vector2(28, 28)
	app._input(outside_click)
	await settle_ui()
	check(app.tea_memory.visible and app.state.tea_story_token == saved_page_token, "clicking outside the past reading frame does not close or advance it")

	var stale_action := "page:%d" % saved_page_token
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	app._unhandled_key_input(escape)
	await settle_ui()
	check(not app.tea_memory.visible and not app.object_popover.visible and app.selected_object_id.is_empty(), "Escape closes the past and clears the selected document")
	check(app.state.tea_scene_id == app.state.TEA_COURTYARD_ID and app.tea_backdrop.texture.resource_path == present_texture.resource_path, "Escape returns to the same present courtyard")
	check(app.state.tea_story_object.is_empty() and app.state.tea_story_token > saved_page_token, "closing the past invalidates its read token")
	check(not app.state.tea_story_seen.has("tea.cabinet"), "closing a partly read cabinet does not falsely mark it complete")
	app._tea_action("tea.cabinet", stale_action, present_session)
	await settle_ui()
	check(app.state.tea_story_page == 0 and not app.state.tea_story_seen.has("tea.cabinet"), "a callback from the closed cabinet cannot advance or complete it")

	await read_all_pages("tea.cabinet", true)
	check(app.state.tea_story_seen.has("tea.cabinet"), "cabinet read flag commits on its final authored page")
	check(app.tea_scene.visible and app.tea_memory.visible == false and app.selected_object_id.is_empty(), "memory_close returns to the present after the completed cabinet read")
	check(app.state.tea_story_seen.has("tea.cabinet"), "closing the completed cabinet retains its read flag")
	await read_all_pages("tea.letter", true)
	check(app.state.story_stage_complete(), "reading every past letter page completes stage E")
	check(not app.tea_memory.visible and not app.object_popover.visible and app.selected_object_id.is_empty(), "closing the letter returns to the empty present courtyard")
	check(app.tea_paths["tea.story_next"].visible, "closing the completed letter exposes the present-day next-stage route")
	app.tea_paths["tea.story_next"].emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_story_stage == 3 and app.state.tea_scene_id == app.state.TEA_COURTYARD_ID, "the host story route opens F in the same courtyard")
	check(not app.tea_memory.visible and not app.object_popover.visible and app.selected_object_id.is_empty(), "opening F starts with no stale reading view")

func test_new_past_routing_and_guards() -> void:
	await test_medical_chronology_and_cancel()
	await test_medical_habits_present_conclusion()
	await test_after_question_and_cups_past()

func test_medical_chronology_and_cancel() -> void:
	set_fixture_stage(1)
	var present_texture: Texture2D = app.tea_backdrop.texture
	var session_before: int = app.tea_session
	app.tea_hotspots["tea.medical_early"].emit_signal("pressed")
	await settle_ui()
	check(app.object_popover.visible and not app.tea_memory.visible, "the earliest medical record starts in the present chronology view")
	check(app.tea_memory.current_shot != "diagnosis", "medical page one does not show the diagnosis past shot")
	check(app.tea_backdrop.texture.resource_path == present_texture.resource_path, "chronology-first medical page keeps the present courtyard backdrop")
	check(_body_text() == str(_source_page("tea.medical_early", 0).text), "medical page one shows the exact date evidence")
	check(_heading_text() == _expected_heading("tea.medical_early", 0), "medical page one retains its source speaker and order")
	var page_turn: Button = app.object_popover.buttons.get("page:%d" % app.state.tea_story_token)
	check(page_turn != null, "medical chronology page exposes its token-bound next page")
	if page_turn == null:
		return
	page_turn.emit_signal("pressed")
	await settle_ui()
	check(app.tea_memory.visible and not app.object_popover.visible, "the diagnosis excerpt enters the past after the date evidence")
	check(app.tea_memory.current_shot == "diagnosis", "the medical excerpt uses the diagnosis shot")
	check(app.tea_memory.backdrop.texture.resource_path == "res://assets/art/tea-memory/past-diagnosis-v1.png", "the diagnosis excerpt loads its assigned shot asset")
	check(_body_text() == str(_source_page("tea.medical_early", 1).text), "the past diagnosis page shows its exact source text")
	check(_heading_text() == _expected_heading("tea.medical_early", 1), "the past diagnosis page retains its source speaker and order")
	var past_token: int = app.state.tea_story_token
	var before_cancel := _host_snapshot()
	var close_button: Button = app.tea_memory.buttons.get("close")
	check(close_button != null and not close_button.disabled, "the medical past can be cancelled during its transition")
	if close_button != null:
		close_button.emit_signal("pressed")
	await settle_ui()
	check(not app.tea_memory.visible and not app.object_popover.visible and app.selected_object_id.is_empty(), "cancelling the medical past returns to the empty present view")
	check(app.tea_session == session_before and app.state.tea_scene_id == app.state.TEA_COURTYARD_ID, "cancelling medical past preserves its branch session and courtyard")
	check(app.state.tea_story_token > past_token and app.state.tea_story_seen.has("tea.medical_early"), "cancelling the viewed final diagnosis page invalidates its token and retains completed source progress")
	check(not app.state.story_stage_complete() and not app.tea_paths["tea.story_next"].visible, "the medical stage stays open until the separate habits conclusion is read")
	var after_cancel := _host_snapshot()
	var stale_result: Dictionary = app.state.turn_tea_story("tea.medical_early", session_before, past_token)
	check(not stale_result.ok and _host_snapshot() == after_cancel, "the cancelled medical page token cannot advance the host story")
	check(before_cancel["session"] == session_before and before_cancel["object"] == "tea.medical_early" and before_cancel["page"] == 1, "immediate cancellation begins on the second medical source page in its original session")
	await wait_for_recollection_return()

func test_medical_habits_present_conclusion() -> void:
	set_fixture_stage(1)
	app.state.tea_story_seen["tea.medical_early"] = true
	app._refresh()
	var habits_session: int = app.tea_session
	app.tea_hotspots["tea.medical_habits"].emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_story_page == 0 and app.tea_session == habits_session, "medical habits starts at page one in the current branch session")
	check(app.tea_memory.visible and app.tea_memory.current_shot == "diagnosis", "medical habits begin in the diagnosis past")
	check(app.tea_memory.backdrop.texture.resource_path == "res://assets/art/tea-memory/past-diagnosis-v1.png", "medical habits use the assigned diagnosis shot asset")
	check(_body_text() == str(_source_page("tea.medical_habits", 0).text), "medical habits page one shows its exact source text")
	check(_heading_text() == _expected_heading("tea.medical_habits", 0), "medical habits page one retains its source speaker and order")
	await wait_for_memory_hold()
	var page_turn: Button = app.tea_memory.buttons.get("page:%d" % app.state.tea_story_token)
	check(page_turn != null, "medical habits past page exposes its token-bound next page")
	if page_turn == null:
		return
	page_turn.emit_signal("pressed")
	await settle_ui()
	check(not app.tea_memory.visible and app.object_popover.visible, "Jiang's medical conclusion returns to the present reading view")
	check(app.state.tea_story_page == 1 and app.tea_session == habits_session, "the conclusion keeps its source page and branch session")
	check(_body_text() == str(_source_page("tea.medical_habits", 1).text), "Jiang's conclusion shows its exact source text")
	check(_heading_text() == _expected_heading("tea.medical_habits", 1), "Jiang's conclusion retains its source speaker and order")
	check(app.tea_journal.visible and app.tea_rest.visible, "returning from medical past restores present journal and rest")
	check(app.tea_hotspots["tea.medical_early"].visible and app.tea_hotspots["tea.medical_habits"].visible, "returning from medical past restores active medical evidence hotspots")
	check(app.state.story_stage_complete(), "the present medical conclusion completes the medical stage")
	app._close_object_popover()

func test_after_question_and_cups_past() -> void:
	set_fixture_stage(6)
	app.tea_hotspots["tea.notice_death"].emit_signal("pressed")
	await settle_ui()
	check(app.object_popover.visible and not app.tea_memory.visible, "the death notice begins as present-day evidence")
	check(_body_text() == str(_source_page("tea.notice_death", 0).text), "the first death notice page shows its exact source text")
	check(_heading_text() == _expected_heading("tea.notice_death", 0), "the first death notice page retains its source speaker and order")
	var death_turn: Button = app.object_popover.buttons.get("page:%d" % app.state.tea_story_token)
	check(death_turn != null, "the death notice exposes its next authored page")
	if death_turn == null:
		return
	death_turn.emit_signal("pressed")
	await settle_ui()
	check(app.tea_memory.visible and app.tea_memory.current_shot == "after_question", "the second death notice page enters the after-question past")
	check(app.tea_memory.backdrop.texture.resource_path == "res://assets/art/tea-memory/past-after-question-v1.png", "the after-question page loads its assigned shot asset")
	check(_body_text() == str(_source_page("tea.notice_death", 1).text), "the after-question page shows its exact source text")
	check(_heading_text() == _expected_heading("tea.notice_death", 1), "the after-question page keeps the source speaker and order")
	check(not str(_source_page("tea.notice_death", 1).speaker).contains("谢长安"), "the after-question past is narrated by the disciple record, without Xie as speaker")
	var death_session: int = app.tea_session
	await wait_for_memory_hold()
	var death_close: Button = app.tea_memory.buttons.get("memory_close")
	check(death_close != null, "the after-question final page offers memory_close")
	if death_close != null:
		death_close.emit_signal("pressed")
	await settle_ui()
	check(not app.tea_memory.visible and app.state.tea_active and app.tea_session == death_session, "closing the death past retains the active branch session")
	await wait_for_recollection_return()
	check(app.tea_hotspots["tea.notice_cups"].visible, "closing the death past unlocks the next present evidence")
	app.tea_hotspots["tea.notice_cups"].emit_signal("pressed")
	await settle_ui()
	var cups_pages: Array = app.tea_full.objects["tea.notice_cups"].pages
	for page_index in cups_pages.size():
		var expected_page: Dictionary = cups_pages[page_index] as Dictionary
		check(app.tea_memory.visible and not app.object_popover.visible, "cups page %d remains in the past" % [page_index + 1])
		check(app.tea_memory.current_shot == "after_cups", "cups page %d keeps the after-cups shot" % [page_index + 1])
		check(app.tea_memory.backdrop.texture.resource_path == "res://assets/art/tea-memory/past-after-cups-v1.png", "cups page %d loads the assigned after-cups asset" % [page_index + 1])
		check(_body_text() == str(expected_page.text), "cups page %d shows its exact source text" % [page_index + 1])
		check(_heading_text() == _expected_heading("tea.notice_cups", page_index), "cups page %d keeps its source speaker and order" % [page_index + 1])
		if page_index >= cups_pages.size() - 1:
			break
		await wait_for_memory_hold()
		var cups_turn: Button = app.tea_memory.buttons.get("page:%d" % app.state.tea_story_token)
		check(cups_turn != null, "cups page %d exposes its next token-bound page" % [page_index + 1])
		if cups_turn == null:
			return
		cups_turn.emit_signal("pressed")
		await settle_ui()
	check(app.state.story_stage_complete(), "reading every cups page completes the public-notice stage")
	var cups_session: int = app.tea_session
	await wait_for_memory_hold()
	var cups_close: Button = app.tea_memory.buttons.get("memory_close")
	check(cups_close != null, "the final cups page offers memory_close")
	if cups_close != null:
		cups_close.emit_signal("pressed")
	await settle_ui()
	check(not app.tea_memory.visible and not app.object_popover.visible and app.selected_object_id.is_empty(), "closing the cups past clears the reading view")
	check(app.state.tea_active and app.tea_session == cups_session and not app.state.tea_quest_complete, "closing the cups past retains the unfinished branch")
	check(app.state.tea_story_object.is_empty() and app.tea_recollection_waiting and not app.tea_paths["tea.story_next"].visible, "closing the cups past invalidates its page and starts the return pause")
	await wait_for_recollection_return()
	check(app.tea_paths["tea.story_next"].visible, "the completed cups evidence exposes the route after the return pause")

func test_full_memory_route_and_delayed_shot() -> void:
	check(app.state.tea_story_stage == 3, "F fixture is reached through the host stage route")
	var present_texture: Texture2D = app.tea_backdrop.texture
	app.tea_hotspots["tea.memory"].emit_signal("pressed")
	await settle_ui()
	check(app.tea_memory.visible and not app.object_popover.visible, "F opens in the full-screen memory view")
	check(app.tea_memory.current_shot == "standing", "F opens on the standing shot")
	check(app.tea_memory.backdrop.texture != null and app.tea_memory.backdrop.texture.resource_path != present_texture.resource_path, "F displays actual past art instead of the present courtyard")
	standing_texture = app.tea_memory.backdrop.texture
	check(app.tea_memory.buttons.keys().has("page:%d" % app.state.tea_story_token), "F first page offers its current token as the advance action")
	check_present_scene_blocked()
	var first_page_button: Button = app.tea_memory.buttons["continue"]
	var initial_hold: float = app.tea_memory.remaining_hold_seconds()
	var initial_snapshot := _host_snapshot()
	check(initial_hold > 0.4 and first_page_button.disabled, "entering the past holds its continue action through the transition")
	first_page_button.emit_signal("pressed")
	check(_host_snapshot() == initial_snapshot, "an emitted button signal cannot skip the entry hold")
	app.tea_memory.present("tea.memory", app.tea_full.objects["tea.memory"], app.state.tea_story_page, app.state.tea_story_token, app.tea_session)
	await create_timer(0.1).timeout
	check(app.tea_memory.remaining_hold_seconds() > 0.0 and app.tea_memory.remaining_hold_seconds() < initial_hold, "re-presenting the same page does not restart or bypass its hold")
	check(app.tea_memory.buttons["continue"] == first_page_button and first_page_button.disabled, "same-key presentation keeps the original held button")

	var old_read_hold: float = app.tea_memory.remaining_hold_seconds()
	var old_read_button: Button = app.tea_memory.buttons["continue"]
	var old_read_button_id: int = old_read_button.get_instance_id()
	var old_read_callback: Callable = old_read_button.get_signal_connection_list("pressed")[0]["callable"]
	app._tea_memory_close()
	await settle_ui()
	await create_timer(old_read_hold * 0.6).timeout
	app._tea_inspect("tea.memory")
	await settle_ui()
	var replacement_button: Button = app.tea_memory.buttons["continue"]
	await create_timer(old_read_hold * 0.5).timeout
	check(old_read_button_id != replacement_button.get_instance_id(), "reopening the memory creates a new page button")
	check(app.tea_memory.remaining_hold_seconds() > 0.1 and replacement_button.disabled, "a closed read's timer cannot enable the replacement read")
	var replacement_snapshot := _host_snapshot()
	check(old_read_callback.is_valid(), "the saved callback from the closed button is callable")
	old_read_callback.call()
	check(_host_snapshot() == replacement_snapshot, "a button from a closed read cannot advance the replacement page")
	await wait_for_memory_hold()

	var pages: Array = app.tea_full.objects["tea.memory"].pages
	var retired_button: Button = app.tea_memory.buttons["continue"]
	await wait_for_memory_hold()
	retired_button.emit_signal("pressed")
	var after_real_turn := _host_snapshot()
	retired_button.emit_signal("pressed")
	check(_host_snapshot() == after_real_turn, "retired page button cannot borrow the next page token")
	check(app.state.tea_story_page == 1, "duplicate retired callback leaves F on its first advanced page")
	app._tea_memory_close()
	app._tea_inspect("tea.memory")
	await settle_ui()
	for page_index in pages.size():
		await settle_ui()
		check(app.tea_memory.visible and not app.object_popover.visible, "F page %d remains in the past view" % [page_index + 1])
		check(_body_text() == str((pages[page_index] as Dictionary).text), "F page %d displays its exact original text" % [page_index + 1])
		check(_heading_text() == _expected_heading("tea.memory", page_index), "F page %d displays its exact speaker and order" % [page_index + 1])
		check_present_scene_blocked()
		var expected_shot := "standing" if page_index <= 9 else ("alone" if page_index == 10 else "tea")
		check(app.tea_memory.current_shot == expected_shot, "F page %d uses the authored %s shot" % [page_index + 1, expected_shot])
		if page_index == 1:
			check(app.tea_memory.remaining_hold_seconds() == 0.0 and not app.tea_memory.buttons["continue"].disabled, "unchanged-shot F pages remain immediate")
		if page_index == 3:
			check(app.tea_memory.remaining_hold_seconds() > 0.5 and app.tea_memory.buttons["continue"].disabled, "F page 4 keeps its authored 850 ms pause")
		if page_index == 10:
			var host_page := int(app.state.tea_story_page)
			var host_token := int(app.state.tea_story_token)
			var early_turn: Button = app.tea_memory.buttons.get("page:%d" % host_token)
			var early_snapshot := _host_snapshot()
			check(early_turn != null and early_turn.disabled and app.tea_memory.remaining_hold_seconds() > 2.0, "F page 11 holds the lonely shot before its authored arrival")
			if early_turn != null:
				early_turn.emit_signal("pressed")
			check(_host_snapshot() == early_snapshot and app.tea_memory.current_shot == "alone", "rapid continue cannot skip the lonely shot")
			await create_timer(2.05).timeout
			check(app.tea_memory.current_shot == "tea", "F page 11 changes from alone to the tea shot after its pause")
			check(app.state.tea_story_page == host_page and app.state.tea_story_token == host_token, "F delayed shot leaves story page and token unchanged")
		if page_index >= pages.size() - 1:
			break
		var action_id := "page:%d" % app.state.tea_story_token
		var turn: Button = app.tea_memory.buttons.get(action_id)
		check(turn != null, "F page %d exposes a token-bound continue button" % [page_index + 1])
		if turn == null:
			return
		await wait_for_memory_hold()
		check(not turn.disabled, "F page %d enables continue after its authored hold" % [page_index + 1])
		turn.emit_signal("pressed")
		await settle_ui()
		check(app.state.tea_story_page == page_index + 1, "F advances exactly one authored page")

	check(app.state.story_stage_complete() and app.state.tea_story_seen.has("tea.memory"), "F completion commits after its final source page")
	check(app.tea_memory.buttons.has("memory_close"), "F final page offers memory_close")
	check(not app.tea_memory.buttons.has("story_next"), "F final page does not advance the story directly")
	var memory_close: Button = app.tea_memory.buttons.get("memory_close")
	var final_memory_token: int = app.state.tea_story_token
	var final_memory_session: int = app.tea_session
	if memory_close != null:
		check(memory_close.text == "合上旧记 · 回到旧院", "F uses the authored close label")
		await wait_for_memory_hold()
		memory_close.emit_signal("pressed")
	await settle_ui()
	check(not app.tea_memory.visible and not app.object_popover.visible and app.selected_object_id.is_empty(), "memory_close returns from F to the old courtyard")
	check(app.state.tea_story_object.is_empty() and app.state.tea_story_token > final_memory_token, "memory_close invalidates F's current read token")
	check(app.tea_session == final_memory_session and app.state.tea_scene_id == app.state.TEA_COURTYARD_ID, "memory_close preserves the same courtyard session")
	check(app.state.tea_story_seen.has("tea.memory"), "memory_close retains F completion")
	await wait_for_recollection_return()
	check(app.tea_paths["tea.story_next"].visible, "closing completed F reveals the courtyard next-stage route")
	check(app.tea_paths["tea.story_next"].hint.text == "翻阅几册旧记 →", "the visible route points to the next records stage")
	app.tea_paths["tea.story_next"].emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_story_stage == 4 and app.tea_memory.visible == false, "the present courtyard route opens the records stage after F closes")

func test_last_day_fade_and_reset_cancellation() -> void:
	set_fixture_stage(5)
	app.tea_hotspots["tea.last_day"].emit_signal("pressed")
	await settle_ui()
	check(app.tea_memory.visible and app.tea_memory.current_shot == "dusk", "last-day reading enters the dusk shot")
	var dusk_texture: Texture2D = app.tea_memory.backdrop.texture
	check(dusk_texture != null and standing_texture != null, "standing and dusk memory artwork are both loaded")
	if dusk_texture != null and standing_texture != null:
		check(_texture_luminance(dusk_texture) < _texture_luminance(standing_texture), "last-day artwork is visibly darker than the ordinary past scene")
	var last_pages: Array = app.tea_full.objects["tea.last_day"].pages
	for page_index in last_pages.size():
		await settle_ui()
		check(app.tea_memory.current_shot == "dusk", "last-day page %d remains in the dusk scene" % [page_index + 1])
		check(_body_text() == str((last_pages[page_index] as Dictionary).text), "last-day page %d keeps the original text" % [page_index + 1])
		if page_index == 3:
			check(app.tea_memory.remaining_hold_seconds() > 1.2 and app.tea_memory.buttons["continue"].disabled, "last-day page 4 keeps its authored 1500 ms pause")
		if page_index == 5:
			check(app.tea_memory.remaining_hold_seconds() > 1.4 and app.tea_memory.buttons["memory_close"].disabled, "last-day final page holds reading through the fade")
			check(not app.tea_memory.buttons["close"].disabled, "top-right close stays available during the final hold")
		if page_index >= last_pages.size() - 1:
			break
		var turn: Button = app.tea_memory.buttons.get("page:%d" % app.state.tea_story_token)
		check(turn != null, "last-day page %d offers its next source page" % [page_index + 1])
		if turn == null:
			return
		await wait_for_memory_hold()
		turn.emit_signal("pressed")
		await settle_ui()
		check(app.state.tea_story_page == page_index + 1, "last-day reading advances by one page")
	check(app.state.tea_story_seen.has("tea.last_day"), "last-day read flag commits on the final page")
	await create_timer(1.5).timeout
	check(app.tea_memory.visible and app.tea_memory.current_shot == "near_black", "last-page fade dims the dusk memory after its final passage")
	var last_day_token: int = app.state.tea_story_token
	var last_day_close: Button = app.tea_memory.buttons.get("close")
	check(last_day_close != null, "last-day memory exposes its close control after the fade")
	if last_day_close != null:
		last_day_close.emit_signal("pressed")
	await settle_ui()
	check(not app.tea_memory.visible and app.state.tea_story_object.is_empty(), "closing the last-day past removes its rendered actors with the view")
	check(app.state.tea_story_token > last_day_token, "closing last day invalidates its final read token")

	set_fixture_stage(3)
	app.tea_hotspots["tea.memory"].emit_signal("pressed")
	await settle_ui()
	await advance_to_memory_page(10)
	check(app.tea_memory.current_shot == "alone", "the delayed F shot is pending while the man is alone")
	var stale_session: int = app.tea_session
	var stale_token: int = app.state.tea_story_token
	var delayed_close: Button = app.tea_memory.buttons.get("close")
	check(delayed_close != null, "delayed F shot exposes its close control")
	if delayed_close != null:
		delayed_close.emit_signal("pressed")
	await settle_ui()
	await create_timer(1.8).timeout
	check(not app.tea_memory.visible, "closing during the delayed F shot cancels its queued appearance")
	check(app.state.tea_story_page == 0 and app.state.tea_story_token > stale_token, "closing cancels the pending shot and invalidates its host page callback")
	var stale_result: Dictionary = app.state.turn_tea_story("tea.memory", stale_session, stale_token)
	check(not stale_result.ok and app.state.tea_story_page == 0, "the old F token is rejected after the past closes")

	app.tea_hotspots["tea.memory"].emit_signal("pressed")
	await settle_ui()
	await advance_to_memory_page(10)
	var reset_session: int = app.tea_session
	var reset_token: int = app.state.tea_story_token
	app._reset()
	await settle_ui()
	await create_timer(1.8).timeout
	check(not app.state.tea_active and app.cultivation_scene.visible and not app.tea_scene.visible, "reset during the past restores cultivation")
	check(not app.tea_memory.visible and app.selected_object_id.is_empty(), "reset leaves no past overlay or selected object")
	check(app.state.tea_story_stage == 0 and app.state.tea_story_seen.is_empty(), "reset clears the synthetic branch and memory read flags")
	app._tea_action("tea.memory", "page:%d" % reset_token, reset_session)
	await settle_ui()
	check(not app.state.tea_active and app.state.tea_story_page == 0 and not app.tea_memory.visible, "a stale memory callback after reset cannot restore the view")
	check(not app.tea_hotspots["tea.memory"].visible and not app.tea_paths["tea.story_next"].visible, "reset hides every story interaction in cultivation")

	await begin_fixture_branch()
	set_fixture_stage(3)
	app.tea_hotspots["tea.memory"].emit_signal("pressed")
	await settle_ui()
	var pending_reset_button: Button = app.tea_memory.buttons["continue"]
	var pending_reset_button_id: int = pending_reset_button.get_instance_id()
	var pending_reset_callback: Callable = pending_reset_button.get_signal_connection_list("pressed")[0]["callable"]
	var pending_reset_hold: float = app.tea_memory.remaining_hold_seconds()
	await create_timer(0.15).timeout
	app._reset()
	await settle_ui()
	await begin_fixture_branch()
	set_fixture_stage(3)
	app.tea_hotspots["tea.memory"].emit_signal("pressed")
	await settle_ui()
	var post_reset_button: Button = app.tea_memory.buttons["continue"]
	var wait_for_old_reset_callback := maxf(0.05, pending_reset_hold - 0.15 + 0.05)
	await create_timer(wait_for_old_reset_callback).timeout
	check(pending_reset_button_id != post_reset_button.get_instance_id(), "a fresh read after reset has a replacement button")
	check(app.tea_memory.remaining_hold_seconds() > 0.05 and post_reset_button.disabled, "a pre-reset timer cannot enable a new read")
	var post_reset_snapshot := _host_snapshot()
	check(pending_reset_callback.is_valid(), "the saved callback from the pre-reset button is callable")
	pending_reset_callback.call()
	check(_host_snapshot() == post_reset_snapshot, "a pre-reset button cannot progress the new read")

func begin_fixture_branch() -> void:
	app._open_tea()
	app._tea_accept()
	await settle_ui()
	check(app.state.tea_active and app.state.tea_accepted, "fixture begins through the host commission and acceptance flow")

func set_fixture_stage(stage_index: int) -> void:
	app.state.tea_seen["tea.cup_first"] = true
	app.state.tea_seen["tea.cup_second"] = true
	app.state.tea_stage_complete = true
	app.state.tea_c_seen["tea.household"] = true
	app.state.tea_c_seen["tea.ledger"] = true
	app.state.tea_c_complete = true
	app.state.tea_scene_id = app.state.TEA_COURTYARD_ID
	app.state.tea_story_stage = stage_index
	app.state.tea_story_seen.clear()
	app._close_object_popover()
	app._refresh()

func read_all_pages(object_id: String, closes_as_memory: bool) -> void:
	var pages: Array = app.tea_full.objects[object_id].pages
	app.tea_hotspots[object_id].emit_signal("pressed")
	await settle_ui()
	for page_index in pages.size():
		await settle_ui()
		var expected_page: Dictionary = pages[page_index]
		check(_body_text() == str(expected_page.text), "%s page %d shows the source body" % [object_id, page_index + 1])
		check(_heading_text() == _expected_heading(object_id, page_index), "%s page %d shows the source speaker and page order" % [object_id, page_index + 1])
		if object_id == "tea.letter":
			check(app.tea_memory.visible and not app.object_popover.visible, "the letter page is read in the past")
			check(app.tea_memory.current_shot == "writing", "the letter uses the writing shot on every page")
			check(app.tea_memory.backdrop.texture.resource_path == "res://assets/art/tea-memory/past-writing-v1.png", "the letter loads its assigned writing shot asset")
		if page_index >= pages.size() - 1:
			break
		var turn: Button = _reading_buttons().get("page:%d" % app.state.tea_story_token)
		check(turn != null, "%s page %d has a live page-turn action" % [object_id, page_index + 1])
		if turn == null:
			return
		await wait_for_memory_hold()
		turn.emit_signal("pressed")
		await settle_ui()
	if closes_as_memory:
		check(app.tea_memory.buttons.has("memory_close"), "%s final past page exposes memory_close" % object_id)
		var close: Button = app.tea_memory.buttons.get("memory_close")
		if close != null:
			await wait_for_memory_hold()
			close.emit_signal("pressed")
		await settle_ui()
		check(not app.tea_memory.visible and app.selected_object_id.is_empty(), "%s closes back to the present after its final page" % object_id)
		await wait_for_recollection_return()

func advance_to_memory_page(target_page: int) -> void:
	while app.state.tea_story_page < target_page:
		var turn: Button = app.tea_memory.buttons.get("page:%d" % app.state.tea_story_token)
		if turn == null:
			check(false, "F has the expected page turn through page %d" % target_page)
			return
		await wait_for_memory_hold()
		turn.emit_signal("pressed")
		await settle_ui()
	check(app.state.tea_story_page == target_page, "F fixture reaches the delayed-shot page")

func check_present_scene_blocked() -> void:
	for hotspot in app.tea_hotspots.values():
		check(not hotspot.visible, "%s hotspot is hidden during the past" % hotspot.name)
	for path in app.tea_paths.values():
		check(not path.visible, "%s route is hidden during the past" % path.name)
	check(not app.tea_rest.visible and not app.tea_journal.visible, "rest and journal are hidden during the past")
	check(not app.tea_memory.buttons.has("story_next"), "past reading has no story_next action")

func _host_snapshot() -> Dictionary:
	return {
		"energy": app.state.energy,
		"day": app.state.day,
		"time_index": app.state.time_index,
		"scene": app.state.tea_scene_id,
		"stage": app.state.tea_story_stage,
		"session": app.tea_session,
		"token": app.state.tea_story_token,
		"object": app.state.tea_story_object,
		"page": app.state.tea_story_page,
		"seen": app.state.tea_story_seen.duplicate(true),
	}

func _source_page(object_id: String, page_index: int) -> Dictionary:
	return app.tea_full.objects[object_id].pages[page_index]

func _expected_heading(object_id: String, page_index: int) -> String:
	var pages: Array = app.tea_full.objects[object_id].pages
	var page: Dictionary = pages[page_index]
	return "%s · %d / %d" % [page.speaker, page_index + 1, pages.size()]

func _reading_buttons() -> Dictionary:
	return app.tea_memory.buttons if app.tea_memory.visible else app.object_popover.buttons

func _body_text() -> String:
	return app.tea_memory.body.text if app.tea_memory.visible else _popover_body_text()

func _heading_text() -> String:
	return app.tea_memory.heading.text if app.tea_memory.visible else _popover_heading_text()

func _popover_body_text() -> String:
	if app.selected_object_id.is_empty():
		return ""
	var expected_page: Dictionary = _source_page(app.selected_object_id, app.state.tea_story_page)
	for child in app.object_popover.get_children():
		if child is Label and child.text == str(expected_page.text):
			return child.text
	return ""

func _popover_heading_text() -> String:
	if app.selected_object_id.is_empty():
		return ""
	var expected := _expected_heading(app.selected_object_id, app.state.tea_story_page)
	for child in app.object_popover.get_children():
		if child is Label and child.text == expected:
			return child.text
	return ""

func _texture_luminance(texture: Texture2D) -> float:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return 1.0
	var total := 0.0
	var samples := 0
	for y_fraction in [0.2, 0.4, 0.6, 0.8]:
		for x_fraction in [0.2, 0.4, 0.6, 0.8]:
			var x := clampi(roundi(float(image.get_width()) * x_fraction), 0, image.get_width() - 1)
			var y := clampi(roundi(float(image.get_height()) * y_fraction), 0, image.get_height() - 1)
			var pixel := image.get_pixel(x, y)
			total += pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
			samples += 1
	return total / float(samples) if samples > 0 else 1.0

func settle_ui() -> void:
	await process_frame
	await process_frame

func wait_for_memory_hold() -> void:
	if app.tea_memory == null:
		return
	var remaining: float = app.tea_memory.remaining_hold_seconds()
	if remaining > 0.0:
		await create_timer(remaining + 0.03).timeout
	await settle_ui()

func wait_for_recollection_return() -> void:
	if app.tea_recollection_waiting:
		await create_timer(1.2).timeout
		await settle_ui()
	check(not app.tea_recollection_waiting, "the memory return pause ends before the next route is used")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
