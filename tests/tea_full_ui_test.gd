extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const CUP_IDS := ["tea.cup_first", "tea.cup_second"]
const STORY_STAGE_RANGE := [1, 2, 3, 4, 5, 6]
const CAPTURE_SIZES := [Vector2i(1152, 720), Vector2i(920, 575)]

var app
var checks := 0
var failures := 0
var capture_render := false
var original_cup_instances: Dictionary = {}

func _initialize() -> void:
	capture_render = OS.get_cmdline_user_args().has("--render") and DisplayServer.get_name() != "headless"
	if capture_render:
		root.mode = Window.MODE_WINDOWED
	app = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	for cup_id in CUP_IDS:
		original_cup_instances[cup_id] = app.tea_hotspots[cup_id].get_instance_id()
	await test_full_chain()
	await test_pending_pacing_reset()
	print("TEA_FULL_UI_TESTS: %d checks, %d failures" % [checks, failures])
	quit(failures)

func test_full_chain() -> void:
	check(not app.state.tea_active and app.tea_entry.visible, "full-chain run begins in cultivation with the tea entry available")
	app._open_tea()
	check(app.tea_accept.visible and not app.state.tea_accepted, "commission begins before branch acceptance")
	app.tea_accept.emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_active and app.state.tea_accepted and app.tea_scene.visible, "accepting the commission enters the branch")
	check(app.tea_title.text.begins_with("归剑问天"), "the opening title does not reveal the ending title")
	check_branch_chrome_hidden()
	check(not app.tea_return.visible, "main-panel return is hidden before the whole quest is complete")

	var first_cup = app.tea_hotspots[CUP_IDS[0]]
	first_cup.emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_seen.has(CUP_IDS[0]) and app.selected_object_id == CUP_IDS[0], "first cup is inspected directly from its scene hotspot")
	check(app.object_popover.visible and app.object_popover.buttons.has("repair"), "first cup opens its contextual action popover")
	app.object_popover.buttons.repair.emit_signal("pressed")
	await settle_ui()
	check(app.state.energy == 78 and app.object_popover.buttons.repair.disabled, "repair uses its real contextual button and settles once")
	app.tea_hotspots[CUP_IDS[1]].emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_seen.has(CUP_IDS[1]) and app.state.tea_stage_complete, "inspecting both cups completes the opening stage")
	check(not app.state.tea_quest_complete and not app.tea_return.visible, "opening-stage completion does not end the branch")
	check(not app.tea_hotspots["tea.medical_early"].visible, "later-stage hotspots stay hidden before the medical stage")
	check_branch_chrome_hidden()
	app._tea_cancel()
	await settle_ui()
	check(app.state.tea_active and app.tea_scene.visible and not app.tea_return.visible, "cancel cannot leave the unfinished branch")

	app._close_object_popover()
	var courtyard_path: Control = app.tea_paths["tea.path_old_courtyard"]
	check(courtyard_path.visible, "completing both cups exposes the old-courtyard path")
	courtyard_path.emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_scene_id == app.state.TEA_COURTYARD_ID and app.state.tea_story_stage == 0, "the C evidence stage opens in the courtyard before D")
	var c_seen_before_ledger: Dictionary = app.state.tea_c_seen.duplicate(true)
	app.tea_hotspots["tea.ledger"].emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_c_seen == c_seen_before_ledger and not app.state.tea_c_complete, "ledger cannot be read before its household prerequisite")
	app.tea_hotspots["tea.household"].emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_c_seen.has("tea.household") and not app.state.tea_c_complete, "household evidence remains a prerequisite rather than a completion by itself")
	app.tea_hotspots["tea.ledger"].emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_c_complete and app.state.tea_story_stage == 0, "reading the ledger completes C while keeping D unopened")
	check(not app.state.tea_quest_complete and not app.tea_return.visible, "C completion still cannot return to cultivation")
	check_branch_chrome_hidden()
	app._close_object_popover()
	var c_next: Control = app.tea_paths["tea.story_next"]
	check(c_next.visible, "the completed C stage exposes its in-scene route to the next story stage")
	c_next.emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_story_stage == 1 and app.state.tea_scene_id == app.state.TEA_COURTYARD_ID, "the stage route opens D in the courtyard")
	check(app.state.energy == 78, "opening the next story stage does not settle an extra action")
	await exercise_stage(1, "", true)

	for stage_index in STORY_STAGE_RANGE:
		if stage_index == 1:
			continue
		await exercise_stage(stage_index, stage_capture_name(stage_index), false)

	check(app.state.tea_story_stage == 7 and app.state.tea_scene_id == app.state.TEA_TERRACE_ID, "I returns the investigation to the original sword terrace")
	check(app.tea_title.text.begins_with("归剑问天") and not app.state.tea_quest_complete, "return to the cups keeps the quest unfinished")
	check(app.tea_hotspots[CUP_IDS[0]].get_instance_id() == original_cup_instances[CUP_IDS[0]] and app.tea_hotspots[CUP_IDS[1]].get_instance_id() == original_cup_instances[CUP_IDS[1]], "ending reuses the original two cup hotspot nodes")
	check_stage_hotspots(7)
	check(not app.tea_return.visible and not app.cultivation_scene.visible, "reading both ending clues still keeps the player in the branch")
	await read_story_object(CUP_IDS[0], "", false)
	check(app.object_popover.buttons.is_empty(), "the first ending cup cannot be filled before both cups are reread")
	await read_story_object(CUP_IDS[1], "", false)
	check(app.state.story_stage_complete() and not app.state.tea_quest_complete, "both ending cups are reread before the filling action")
	check(not app.object_popover.buttons.has("fill:%d" % app.state.tea_story_token), "the second cup cannot be filled first")
	check(not app.state.tea_quest_complete and not app.tea_return.visible, "ending clues alone do not expose the main-panel return")
	for view in app.tea_fill_views:
		check(not view.visible, "cup-fill presentation stays hidden before the first cup is filled")

	app._close_object_popover()
	app.tea_hotspots[CUP_IDS[0]].emit_signal("pressed")
	await settle_ui()
	var first_fill_id := "fill:%d" % app.state.tea_story_token
	check(app.object_popover.buttons.has(first_fill_id), "reopening the first original cup offers its contextual fill button")
	var old_final_fill: Button = app.object_popover.buttons[first_fill_id]
	old_final_fill.emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_ending_step == 1 and not app.state.tea_quest_complete, "filling the first cup starts the ending pause")
	check(app.tea_fill_views.size() == 2 and app.tea_fill_views[0].visible and not app.tea_fill_views[1].visible, "only the first rendered cup receives tea")
	check(not app.tea_return.visible and not app.tea_journal.visible and not app.tea_rest.visible, "the pause keeps the branch on screen without an early return")
	if capture_render:
		await capture_current_state("first-filled-cup")

	app.tea_hotspots[CUP_IDS[1]].emit_signal("pressed")
	await settle_ui()
	var second_fill_id := "fill:%d" % app.state.tea_story_token
	check(find_description_label("") != null, "the second-cup pause view keeps its body compact and blank")
	check(app.object_popover.buttons.has(second_fill_id), "the second contextual fill button is present after the first pour")
	var second_fill: Button = app.object_popover.buttons[second_fill_id]
	check(second_fill.disabled == app.tea_pour_waiting and (not app.tea_pour_waiting or second_fill.tooltip_text.contains("等一会")), "the second fill is disabled with a wait hint while the pause remains active")
	if not capture_render:
		check(app.tea_pour_waiting, "headless immediate second view observes the enforced pause")
		var step_before := int(app.state.tea_ending_step)
		second_fill.emit_signal("pressed")
		check(app.state.tea_ending_step == step_before, "even a programmatic rapid second pour cannot bypass the visible pause")
	await wait_for_pacing("tea_pour_waiting")
	await settle_ui()
	second_fill_id = "fill:%d" % app.state.tea_story_token
	check(not app.tea_pour_waiting and app.object_popover.buttons.has(second_fill_id), "the pause timer enables the second fill in the same view")
	second_fill = app.object_popover.buttons[second_fill_id]
	check(not second_fill.disabled, "the second fill button enables after the authored pause")
	second_fill.emit_signal("pressed")
	await settle_ui()
	check(app.state.tea_ending_step == 2 and app.state.tea_quest_complete, "after the pause, the second contextual fill completes the whole quest")
	check(app.tea_title.text == "两盏茶", "the completed ending changes the title to 两盏茶")
	check(app.tea_ending_waiting and not app.tea_return.visible and app.tea_scene.visible, "two filled cups remain alone before the return entry appears")
	app._tea_cancel()
	check(app.state.tea_active, "Escape/direct return cannot cut short the final quiet beat")
	check(app.tea_fill_views[0].visible and app.tea_fill_views[1].visible, "both original cup presentation layers show tea")
	check_branch_chrome_hidden()
	if capture_render:
		await capture_current_state("filled-cups")

	await wait_for_pacing("tea_ending_waiting")
	check(app.tea_return.visible and not app.cultivation_scene.visible, "the quiet beat ends with a contextual return entry")
	var ending_session: int = app.tea_session
	var ending_token: int = app.state.tea_story_token
	app.tea_return.emit_signal("pressed")
	await settle_ui()
	check(not app.state.tea_active and app.cultivation_scene.visible and not app.tea_scene.visible, "whole-quest return restores the cultivation scene")
	check(app.tea_entry.visible and not app.tea_return.visible, "returned cultivation exposes the tea entry and removes branch return")
	app.train_button.emit_signal("pressed")
	await wait_for_training()
	check(app.state.cultivation == 12 and app.state.energy == 78, "training still settles after leaving the completed branch")
	app.mentor_button.emit_signal("pressed")
	check(app.state.dialogue_open, "mentor interaction remains available after tea return")
	app.choices[0].emit_signal("pressed")
	check(app.awaiting_continue and app.state.understanding == 1 and app.state.lesson_bonus == 6, "mentor choice still settles its normal cultivation result")
	app.continue_button.emit_signal("pressed")
	await settle_ui()
	check(not app.awaiting_continue and not app.state.dialogue_open, "mentor continuation returns to the cultivation loop")
	check(app.state.tea_story_seen.has(CUP_IDS[0]) and app.state.tea_story_seen.has(CUP_IDS[1]), "the ending used the same stable cup IDs as the opening investigation")

	var reset_button := find_button_by_text(app, "重新开始")
	check(reset_button != null, "cultivation screen still exposes its reset button")
	if reset_button != null:
		reset_button.emit_signal("pressed")
	else:
		app._reset()
	await settle_ui()
	check(not app.state.tea_active and app.state.tea_story_stage == 0 and app.state.tea_story_seen.is_empty(), "reset clears the full-story stage and read progress")
	check(not app.state.tea_stage_complete and not app.state.tea_quest_complete and app.state.tea_ending_step == 0, "reset clears stage, whole-quest, and ending flags")
	check(app.state.energy == 100 and app.state.cultivation == 0 and app.state.understanding == 0, "reset restores cultivation resources and progression")
	check(not app.tea_scene.visible and app.cultivation_scene.visible and app.selected_object_id.is_empty(), "reset returns to the cultivation scene and clears selection")
	app._tea_action(CUP_IDS[1], "fill:%d" % ending_token, ending_session)
	check(not app.state.tea_quest_complete and app.state.energy == 100 and app.state.cultivation == 0, "stale ending callback after reset has no effect")
	for cup_id in CUP_IDS:
		check(app.tea_hotspots[cup_id].get_instance_id() == original_cup_instances[cup_id], "reset retains original hotspot node for %s" % cup_id)

func exercise_stage(stage_index: int, render_name: String, check_rest: bool) -> void:
	check(app.state.tea_story_stage == stage_index, "stage %d becomes active in sequence" % stage_index)
	var stage: Dictionary = app.state.story_stage()
	var items: Array = stage.get("items", [])
	check(not items.is_empty(), "stage %d has authored story items" % stage_index)
	check_stage_hotspots(stage_index)
	check_branch_chrome_hidden()
	check(not app.tea_return.visible and app.state.tea_active, "stage %d remains inside the active branch" % stage_index)
	check(not app.state.story_stage_complete(), "stage %d starts incomplete" % stage_index)
	await reject_locked_items(items)

	if check_rest:
		var first_item := str(items[0])
		app.tea_hotspots[first_item].emit_signal("pressed")
		await settle_ui()
		var stale_id := "page:%d" % app.state.tea_story_token
		var stale_button: Button = app.object_popover.buttons.get(stale_id)
		check(stale_button != null, "multi-page document exposes a real page-turn button before resting")
		var stage_before_rest: int = int(app.state.tea_story_stage)
		var token_before_rest: int = int(app.state.tea_story_token)
		var time_before_rest: int = int(app.state.day) * app.state.rules.times.size() + int(app.state.time_index)
		app.tea_rest.emit_signal("pressed")
		await settle_ui()
		var time_after_rest: int = int(app.state.day) * app.state.rules.times.size() + int(app.state.time_index)
		check(app.state.tea_active and app.state.tea_story_stage == stage_before_rest, "branch rest preserves the active story stage")
		check(time_after_rest == time_before_rest + 1, "branch rest advances one cultivation time slot")
		check(app.state.tea_story_object.is_empty() and app.state.tea_story_token > token_before_rest, "rest closes the document and invalidates its page token")
		if stale_button != null and is_instance_valid(stale_button):
			stale_button.emit_signal("pressed")
			await settle_ui()
		check(app.state.tea_story_stage == stage_before_rest and not app.state.tea_story_seen.has(first_item), "a pre-rest page callback cannot advance the closed document")

	for item_variant in items:
		var item_id := str(item_variant)
		await read_story_object(item_id, render_name, item_id == longest_page_item(items))
		var item_position := items.find(item_id)
		var should_be_complete := item_position == items.size() - 1
		check(app.state.story_stage_complete() == should_be_complete, "stage %d completes only after its final required item" % stage_index)
		if not should_be_complete:
			check(not app.tea_return.visible, "partial stage %d still hides return" % stage_index)

	check(app.state.story_stage_complete(), "stage %d is complete after every required item is fully read" % stage_index)
	check(not app.state.tea_quest_complete and not app.tea_return.visible, "completed stage %d is not mistaken for the whole quest" % stage_index)
	check(app.tea_hotspots[str(items.back())].visible, "the final stage %d hotspot remains the active evidence" % stage_index)
	if app.selected_object_id.is_empty():
		check(app.tea_paths["tea.story_next"].visible, "stage %d exposes its next-story route after the past memory closes" % stage_index)
		app.tea_paths["tea.story_next"].emit_signal("pressed")
		await settle_ui()
	else:
		check(not app.tea_paths["tea.story_next"].visible, "stage %d does not expose a duplicate scene route while a document is selected" % stage_index)
		var next_button: Button = _reading_buttons().get("story_next")
		check(next_button != null and not next_button.disabled, "stage %d exposes its next-story action in the final document popover" % stage_index)
		if next_button == null or next_button.disabled:
			return
		next_button.emit_signal("pressed")
		await settle_ui()
	check(app.state.tea_story_stage == stage_index + 1, "the contextual next-story button advances from stage %d" % stage_index)
	if stage_index < 6:
		check(app.state.tea_scene_id == app.state.TEA_COURTYARD_ID, "stage %d continues in the courtyard" % stage_index)
	else:
		check(app.state.tea_scene_id == app.state.TEA_TERRACE_ID, "the final evidence stage returns to the sword terrace")

func reject_locked_items(items: Array) -> void:
	var objects: Dictionary = app.tea_full.objects
	for item_variant in items:
		var item_id := str(item_variant)
		var object_data: Dictionary = objects[item_id]
		var requirements: Array = object_data.get("requires", [])
		var locked := false
		for requirement_variant in requirements:
			if not app.state.tea_story_seen.has(str(requirement_variant)):
				locked = true
				break
		if not locked:
			continue
		var seen_before: Dictionary = app.state.tea_story_seen.duplicate(true)
		app.tea_hotspots[item_id].emit_signal("pressed")
		await settle_ui()
		check(app.state.tea_story_seen == seen_before, "%s stays unread while a required clue is missing" % item_id)
		check(app.selected_object_id.is_empty() and not app.object_popover.visible, "%s does not open before its prerequisite" % item_id)
		check(not app.state.story_stage_complete(), "locked %s cannot complete the current stage" % item_id)

func read_story_object(object_id: String, render_name: String, capture_longest: bool) -> void:
	app.tea_hotspots[object_id].emit_signal("pressed")
	await settle_ui()
	var source: Dictionary = app.tea_full.objects[object_id]
	var pages: Array = source.get("pages", [])
	check(app.selected_object_id == object_id, "%s selects its current story document" % object_id)
	check(not pages.is_empty(), "%s has one or more authored reading pages" % object_id)
	if not pages.is_empty():
		check(_reading_view_matches(object_id, 0), "%s opens in its authored reading presentation" % object_id)
	await advance_story_pages(object_id, capture_longest, render_name)
	if _object_uses_memory_view(object_id, pages.size() - 1):
		await close_memory_view(object_id)

func advance_story_pages(object_id: String, capture_longest: bool, render_name: String) -> void:
	var source: Dictionary = app.tea_full.objects[object_id]
	var pages: Array = source.get("pages", [])
	var longest_index := longest_page_index(pages)
	for page_index in pages.size():
		var expected_page: Dictionary = pages[page_index] as Dictionary
		await settle_ui()
		check(_reading_view_matches(object_id, page_index), "%s page %d switches to the authored reading presentation" % [object_id, page_index + 1])
		var description := find_description_label(str(expected_page.text))
		check(description != null, "%s page %d displays its exact authored text" % [object_id, page_index + 1])
		var header := find_label_with_prefix(str(expected_page.speaker) + " · %d / %d" % [page_index + 1, pages.size()])
		check(header != null, "%s page %d displays the correct speaker and page order" % [object_id, page_index + 1])
		check_document_bounds(object_id, page_index, description)
		check_branch_chrome_hidden()
		if capture_render and capture_longest and page_index == longest_index and not render_name.is_empty():
			await capture_current_state(render_name)
		if capture_render and object_id == "tea.memory" and page_index in [0, 11]:
			await capture_current_state("memory-standing" if page_index == 0 else "memory-tea")
		if capture_render and object_id == "tea.last_day" and page_index in [2, 5]:
			if page_index == 5: await create_timer(1.4).timeout
			await capture_current_state("memory-last-evening" if page_index == 2 else "memory-night")
		if capture_render:
			var past_capture_name := _past_capture_name(object_id, page_index)
			if not past_capture_name.is_empty():
				await capture_current_state(past_capture_name)
		if page_index >= pages.size() - 1:
			break
		await wait_for_memory_hold()
		var old_token: int = int(app.state.tea_story_token)
		var page_action := "page:%d" % old_token
		var turn_button: Button = _reading_buttons().get(page_action)
		check(turn_button != null and not turn_button.disabled, "%s page %d offers its next page as a real button" % [object_id, page_index + 1])
		if turn_button == null or turn_button.disabled:
			return
		turn_button.emit_signal("pressed")
		await settle_ui()
		check(app.state.tea_story_page == page_index + 1 and app.state.tea_story_token > old_token, "%s advances in order and rotates its reading token" % object_id)
		if not app.tea_memory.visible:
			check(app.tea_journal_text.text == str(expected_page.text).replace("\n", " ") or app.tea_journal_text.text == str((pages[page_index + 1] as Dictionary).text).replace("\n", " "), "%s page turn updates passive journal text" % object_id)
		if page_index == 0:
			var page_after_turn: int = app.state.tea_story_page
			var token_after_turn: int = app.state.tea_story_token
			var seen_after_turn: Dictionary = app.state.tea_story_seen.duplicate(true)
			app._tea_action(object_id, page_action, app.tea_session)
			await settle_ui()
			check(app.state.tea_story_page == page_after_turn and app.state.tea_story_token == token_after_turn and app.state.tea_story_seen == seen_after_turn, "%s rejects a stale page token without changing progress" % object_id)
			var current_page: Dictionary = pages[page_index + 1] as Dictionary
			check(find_description_label(str(current_page.text)) != null, "%s keeps the current page visible after a stale callback" % object_id)
		if object_id == "tea.memory" and page_index == 9:
			var shot_token: int = int(app.state.tea_story_token)
			await create_timer(1.8).timeout
			check(app.state.tea_story_page == page_index + 1 and app.state.tea_story_token == shot_token, "the delayed memory shot does not advance the host reading page")

func check_stage_hotspots(stage_index: int) -> void:
	var stage: Dictionary = app.state.story_stage()
	var expected: Array = stage.get("items", [])
	for object_id in app.tea_hotspots:
		var expected_visible: bool = str(object_id) in expected
		if stage_index == 7:
			expected_visible = str(object_id) in CUP_IDS
		check(app.tea_hotspots[object_id].visible == expected_visible, "%s visibility is limited to stage %d evidence" % [object_id, stage_index])
	check(not app.tea_paths["tea.path_old_courtyard"].visible, "old-courtyard entrance stays hidden while stage %d is active" % stage_index)
	check(app.tea_paths["tea.path_sword_terrace"].visible == (stage_index < 7), "return-to-terrace path visibility matches stage %d" % stage_index)
	check(not app.tea_paths["tea.story_next"].visible, "scene route stays hidden until stage %d evidence is complete and its popover closes" % stage_index)

func check_document_bounds(object_id: String, page_index: int, description: Label) -> void:
	if description == null:
		return
	var reading_view: Control = _reading_view()
	var view_rect: Rect2 = reading_view.get_rect()
	var description_rect := Rect2(description.position, description.size)
	var scene_bounds: Vector2 = Vector2(1440, 900) if reading_view == app.tea_memory else app.tea_scene.size
	check(Rect2(Vector2.ZERO, scene_bounds).encloses(view_rect), "%s page %d reading view stays inside the scene" % [object_id, page_index + 1])
	if reading_view == app.tea_memory:
		var bubble: Control = _direct_child_under(reading_view, description) as Control
		if bubble == null:
			check(false, "%s page %d body has a containing memory bubble" % [object_id, page_index + 1])
		else:
			var bubble_global: Rect2 = bubble.get_global_rect()
			check(reading_view.get_global_rect().encloses(bubble_global), "%s page %d bubble stays inside the memory canvas" % [object_id, page_index + 1])
			check(bubble_global.encloses(description.get_global_rect()), "%s page %d body stays inside its memory bubble" % [object_id, page_index + 1])
	else:
		check(Rect2(Vector2.ZERO, reading_view.size).encloses(description_rect), "%s page %d text stays inside the reading frame" % [object_id, page_index + 1])
	var required_height := float(description.get_line_count()) * float(description.get_line_height())
	print("TEA_FULL_TEXT_BOUNDS: id=%s page=%d lines=%d visible=%d text_size=%s view_size=%s" % [object_id, page_index + 1, description.get_line_count(), description.get_visible_line_count(), description.size, reading_view.size])
	check(description.get_visible_line_count() == description.get_line_count(), "%s page %d shows every wrapped text line" % [object_id, page_index + 1])
	check(required_height <= description.size.y + 1.0, "%s page %d fits its measured text height" % [object_id, page_index + 1])

func _direct_child_under(parent: Node, descendant: Node) -> Node:
	var current := descendant
	while current.get_parent() != null and current.get_parent() != parent:
		current = current.get_parent()
	return current if current.get_parent() == parent else null

func find_description_label(expected_text: String) -> Label:
	var reading_view := _reading_view()
	if reading_view == app.tea_memory:
		return app.tea_memory.body if app.tea_memory.body.text == expected_text else null
	for child in reading_view.get_children():
		if child is Label and child.text == expected_text:
			return child as Label
	return null

func find_label_with_prefix(prefix: String) -> Label:
	var reading_view := _reading_view()
	if reading_view == app.tea_memory:
		return app.tea_memory.heading if app.tea_memory.heading.text == prefix else null
	for child in reading_view.get_children():
		if child is Label and child.text == prefix:
			return child as Label
	return null

func _reading_view() -> Control:
	return app.tea_memory if app.tea_memory.visible else app.object_popover

func _reading_buttons() -> Dictionary:
	return app.tea_memory.buttons if app.tea_memory.visible else app.object_popover.buttons

func _object_uses_memory_view(object_id: String, page_index: int) -> bool:
	if object_id in ["tea.memory", "tea.record_early", "tea.record_late", "tea.record_last", "tea.last_day", "tea.letter", "tea.notice_cups"]:
		return true
	if object_id in ["tea.cabinet", "tea.medical_early", "tea.notice_death"]:
		return page_index >= 1
	return object_id == "tea.medical_habits" and page_index == 0

func _past_capture_name(object_id: String, page_index: int) -> String:
	if object_id == "tea.medical_early" and page_index == 1:
		return "medical"
	if object_id == "tea.letter" and page_index == 0:
		return "writing"
	if object_id == "tea.notice_death" and page_index == 1:
		return "after-question"
	if object_id == "tea.notice_cups" and page_index == 0:
		return "after-cups"
	return ""

func _reading_view_matches(object_id: String, page_index: int) -> bool:
	var uses_memory := _object_uses_memory_view(object_id, page_index)
	return app.tea_memory.visible == uses_memory and app.object_popover.visible != uses_memory

func close_memory_view(object_id: String) -> void:
	await wait_for_memory_hold()
	check(app.tea_memory.visible and app.tea_memory.buttons.has("memory_close"), "%s completed past view offers the explicit close action" % object_id)
	if app.tea_memory.buttons.has("memory_close"):
		var close_button: Button = app.tea_memory.buttons["memory_close"]
		check(close_button.text.ends_with(" · 回到旧院"), "%s close action clearly returns to the present courtyard" % object_id)
		close_button.emit_signal("pressed")
	await settle_ui()
	check(not app.tea_memory.visible and not app.object_popover.visible and app.selected_object_id.is_empty(), "%s close clears the reading view and current selection" % object_id)
	check(app.state.tea_scene_id == app.state.TEA_COURTYARD_ID, "%s close preserves the physical courtyard" % object_id)
	check(app.state.tea_story_object.is_empty(), "%s close invalidates the current story reading" % object_id)
	check(app.tea_recollection_waiting and not app.tea_paths["tea.story_next"].visible, "%s returns to an empty courtyard before showing the next route" % object_id)
	await wait_for_pacing("tea_recollection_waiting")

func find_button_by_text(parent: Node, expected_text: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text == expected_text:
			return child as Button
		var nested := find_button_by_text(child, expected_text)
		if nested != null:
			return nested
	return null

func check_branch_chrome_hidden() -> void:
	for node in [app.dialogue_panel, app.actions_panel, app.speaker, app.dialogue_text, app.result_text, app.shortcut_label, app.train_button, app.mentor_button, app.rest_button]:
		check(not node.visible, "%s stays hidden inside the tea branch" % node.name)
	var journal_buttons: Array = app.tea_journal.get_children().filter(func(child): return child is Button)
	check(app.tea_journal.visible or app.state.tea_ending_step > 0 or app.tea_memory.visible, "passive journal is visible outside the ending pause or past view")
	check(journal_buttons.is_empty(), "passive journal has no bottom confirmation or flow buttons")
	if app.tea_memory.visible:
		for hotspot in app.tea_hotspots.values():
			check(not hotspot.visible, "%s stays hidden during a past memory" % hotspot.name)
		for path in app.tea_paths.values():
			check(not path.visible, "%s stays hidden during a past memory" % path.name)
		check(not app.tea_rest.visible and not app.tea_journal.visible, "present rest and journal stay hidden during a past memory")

func longest_page_item(items: Array) -> String:
	var longest_item := ""
	var longest_text_length := -1
	for item_variant in items:
		var item_id := str(item_variant)
		var source: Dictionary = app.tea_full.objects[item_id]
		var pages: Array = source.get("pages", [])
		for page_variant in pages:
			var page: Dictionary = page_variant as Dictionary
			var page_length := str(page.text).length()
			if page_length > longest_text_length:
				longest_text_length = page_length
				longest_item = item_id
	return longest_item

func longest_page_index(pages: Array) -> int:
	var longest_index := 0
	var longest_text_length := -1
	for i in pages.size():
		var page: Dictionary = pages[i] as Dictionary
		var page_length := str(page.text).length()
		if page_length > longest_text_length:
			longest_text_length = page_length
			longest_index = i
	return longest_index

func stage_capture_name(stage_index: int) -> String:
	match stage_index:
		2: return "letter-longest"
		3: return "memory-longest"
		6: return "public-notice-longest"
	return ""

func capture_current_state(state_name: String) -> void:
	root.mode = Window.MODE_WINDOWED
	await create_timer(0.2).timeout
	var original_size: Vector2i = root.size
	for size in CAPTURE_SIZES:
		root.size = size
		var image: Image
		var bright_samples := 0
		var attempts := 0
		for retry in range(20):
			attempts = retry + 1
			await process_frame
			await RenderingServer.frame_post_draw
			await create_timer(0.05).timeout
			var texture := root.get_texture()
			if texture == null:
				continue
			var candidate: Image = texture.get_image()
			if candidate.get_size() != size:
				# macOS window/backbuffer resize is asynchronous; reassert the target.
				root.size = size
				continue
			image = candidate
			bright_samples = nonblank_sample_count(image)
			if bright_samples >= 3:
				break
			root.size = size
		print("TEA_FULL_FRAME_SAMPLE: state=%s size=%s bright=%d scene-and-reading samples tries=%d" % [state_name, size, bright_samples, attempts])
		var size_matches: bool = image != null and image.get_size() == size
		check(size_matches, "%s rendered image reaches requested size %s" % [state_name, size])
		check(bright_samples >= 3, "%s rendered image has at least three nonblank samples" % state_name)
		if not size_matches:
			continue
		var output_dir := ProjectSettings.globalize_path("res://.local/qa/tea-past-all")
		var mkdir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		check(mkdir_error == OK or mkdir_error == ERR_ALREADY_EXISTS, "full-chain screenshot directory is available")
		var path := output_dir.path_join("%s-%dx%d.png" % [state_name, size.x, size.y])
		var save_error := image.save_png(path)
		print("TEA_FULL_RENDER: state=%s requested=%s actual=%s path=%s save_error=%d" % [state_name, size, image.get_size(), path, save_error])
		check(save_error == OK and image.get_size() == size, "%s screenshot saves at %s" % [state_name, size])
	root.size = original_size
	await process_frame

func nonblank_sample_count(image: Image) -> int:
	var bright_samples := 0
	for y_fraction in [0.08, 0.5, 0.85]:
		for x_fraction in [0.15, 0.5, 0.85]:
			var x := clampi(roundi(float(image.get_width()) * x_fraction), 0, image.get_width() - 1)
			var y := clampi(roundi(float(image.get_height()) * y_fraction), 0, image.get_height() - 1)
			var color: Color = image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.05:
				bright_samples += 1
	# Night intentionally darkens the scene; the paper dialogue must still render.
	if app.tea_memory.visible and app.tea_memory.current_shot == "near_black":
		var text_rect: Rect2 = app.tea_memory.body.get_global_rect()
		for fraction in [0.15, 0.5, 0.85]:
			var logical := text_rect.position + text_rect.size * Vector2(fraction, 0.5)
			var x := clampi(roundi(logical.x * image.get_width() / 1440.0), 0, image.get_width()-1)
			var y := clampi(roundi(logical.y * image.get_height() / 900.0), 0, image.get_height()-1)
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.05: bright_samples += 1
	return bright_samples

func settle_ui() -> void:
	await process_frame
	await process_frame

func wait_for_training() -> void:
	var waited := 0.0
	while app.busy and waited < 2.0:
		await create_timer(0.05).timeout
		waited += 0.05
	check(not app.busy, "training animation settles after tea return")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func wait_for_memory_hold() -> void:
	if not app.tea_memory.visible:
		return
	# Capture/resize can stall real frames. Wait for the actual button, with a
	# bound, rather than assuming its SceneTreeTimer has fired at the wall deadline.
	var elapsed := 0.0
	while app.tea_memory.visible and elapsed < 5.0:
		var button: Button = app.tea_memory.buttons.get("continue")
		if app.tea_memory.remaining_hold_seconds() <= 0.0 and button != null and not button.disabled:
			break
		await create_timer(0.05).timeout
		elapsed += 0.05
	await settle_ui()
	var ready: Button = app.tea_memory.buttons.get("continue")
	check(not app.tea_memory.visible or (app.tea_memory.remaining_hold_seconds() <= 0.0 and ready != null and not ready.disabled), "the past hold settles into an actually enabled continue button")

func test_pending_pacing_reset() -> void:
	# Synthetic completed-investigation fixture, separate from the full real route.
	app._reset()
	app._open_tea()
	app._tea_accept()
	app.state.tea_story_stage = 7
	app.state.tea_scene_id = app.state.TEA_TERRACE_ID
	app.state.tea_stage_complete = true
	app.state.tea_story_seen = {"tea.cup_first":true,"tea.cup_second":true}
	app._refresh()
	app._tea_inspect("tea.cup_first")
	app._tea_action("tea.cup_first", "fill:%d" % app.state.tea_story_token, app.tea_session)
	check(app.tea_pour_waiting, "fixture starts a pending first-cup timer")
	app._reset()
	app._open_tea()
	app._tea_accept()
	var session_after_reset: int = app.tea_session
	await create_timer(float(app.tea_pacing.first_cup_pause_ms) / 1000.0 + 0.05).timeout
	check(app.tea_session == session_after_reset and app.state.tea_ending_step == 0 and not app.state.tea_quest_complete, "old first-cup timer cannot change a new run")
	check(not app.tea_pour_waiting and not app.tea_ending_waiting and not app.tea_recollection_waiting and not app.tea_return.visible, "reset cancels presentation holds without exposing a return")
	app._reset()

func wait_for_pacing(flag_name: String) -> void:
	var elapsed := 0.0
	while bool(app.get(flag_name)) and elapsed < 5.0:
		await create_timer(0.05).timeout
		elapsed += 0.05
	check(not bool(app.get(flag_name)), "%s finishes within its bounded presentation time" % flag_name)
