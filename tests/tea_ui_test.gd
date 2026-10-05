extends SceneTree
const MainScene = preload("res://scenes/main.tscn")
const CUP_IDS := ["tea.cup_first", "tea.cup_second"]
var app
var failures := 0
var checks := 0
var render_mode := false

func _initialize() -> void:
	render_mode = OS.get_cmdline_user_args().has("--render")
	app = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	check(not app.state.tea_active and app.tea_entry.visible,"initial cultivation and tea entry unchanged")
	check_cup_alpha()
	test_mentor_continue_gates()
	test_commission_cancel_and_accept()
	app._open_tea()
	check(app.sword_card.visible and app.tea_accept.visible,"commission acceptance remains outside terrace")
	app.tea_accept.emit_signal("pressed")
	check(app.state.tea_accepted and app.tea_scene.visible,"acceptance enters terrace")
	check(app.selected_object_id.is_empty() and not app.object_popover.visible,"entry needs no dialogue or selected object")
	check(not app.dialogue_panel.visible and not app.actions_panel.visible,"old large dialogue and action panels hidden")
	check(app.tea_journal.visible and app.tea_journal.size.y < app.layout.dialogue[3]/2,"passive journal less than half old panel height")
	check(app.tea_journal.get_children().filter(func(child): return child is Button).is_empty(),"journal contains no flow buttons")
	check(app.tea_status.text.contains("0 / 2"),"initial progress 0/2")
	check(not app.tea_return.visible,"unfinished sidequest has no main-panel return button")
	check(app.shortcut_label.text == "Esc 收起物品 · 3 歇息", "shortcut label matches unfinished branch gate")
	app._tea_cancel()
	check(app.state.tea_active and app.tea_scene.visible and not app.awaiting_continue,"early return request stays in sidequest with passive feedback")
	var before := state_snapshot()
	var weather_before: float = app.weather.elapsed
	var first = app.tea_hotspots[CUP_IDS[0]]
	if render_mode:
		root.warp_mouse(first.get_global_rect().get_center())
		await process_frame
		await process_frame
	first._hover(true)
	check(first.hint.visible and first.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,"hover reveals small view hint and hand cursor")
	await create_timer(0.2).timeout
	check(first.emphasis > 0.4,"hover ink contour animates")
	first.emit_signal("pressed")
	check(app.state.tea_seen.size() == 1 and app.selected_object_id == CUP_IDS[0],"one click immediately inspects and selects first cup")
	check(app.tea_status.text.contains("1 / 2"),"progress 1/2 after click")
	check(first.selected and first.inspected and not first.hint.visible,"selected cup has inspected state without duplicate hover label")
	check(app.object_popover.visible and app.object_popover.object_id == CUP_IDS[0],"first cup opens associated popover")
	check(app.tea_journal_text.text == app.tea_data.objects[CUP_IDS[0]].text,"inspection narrative comes from data")
	check(app.object_popover.buttons.has("repair") and app.object_popover.buttons.has("ask_mentor"),"first popover contains contextual repair and ask")
	check(app.state.energy == before.energy and app.state.time_index == before.time_index,"view consumes neither energy nor time")
	check_popover_bounds()
	await create_timer(0.2).timeout
	check(first.prop.position.y == -2.0,"selected cup rises two pixels")
	check(app.weather.elapsed > weather_before,"weather presentation clock remains independent")
	if render_mode:
		await capture_render(Vector2i(1152,720))
		await capture_render(Vector2i(960,600))
		await capture_render(Vector2i(1440,900))
		await capture_render(Vector2i(1280,720))
		await capture_render(Vector2i(800,600))
	app.object_popover.buttons.repair.emit_signal("pressed")
	check(app.state.energy == 78 and app.tea_journal_text.text == app.tea_data.feedback.repair,"repair immediately costs22 and publishes feedback")
	check(app.object_popover.buttons.repair.disabled,"completed repair visibly disabled")
	app._tea_action(CUP_IDS[0],"repair",app.tea_session)
	check(app.state.energy == 78,"repeated repair cannot charge again")
	app.object_popover.buttons.ask_mentor.emit_signal("pressed")
	check(app.state.energy == 70 and app.tea_journal_text.text == app.tea_data.rumor,"ask immediately costs8 and reuses rumor")
	check(app.state.time_index == before.time_index and app.state.cultivation == before.cultivation,"object actions preserve core time and cultivation")
	var old_session: int = app.tea_session
	var second = app.tea_hotspots[CUP_IDS[1]]
	second.emit_signal("pressed")
	check(app.selected_object_id == CUP_IDS[1] and not first.selected and second.selected,"second cup naturally switches selection")
	check(app.object_popover.object_id == CUP_IDS[1] and app.object_popover.buttons.size() == 1,"single popover switches description and actions")
	check(app.state.tea_seen.size() == 2 and app.tea_status.text.contains("2 / 2"),"progress2/2 without confirmation")
	check(app.state.tea_stage_complete and app.state.tea_active and not app.state.tea_quest_complete,"both cups complete only the stage, not whole quest")
	check(not app.tea_return.visible,"nonterminal completed stage still hides main return")
	check(app.tea_journal_text.text.contains(app.tea_data.impression),"existing impression revealed only after both cups")
	check_popover_bounds()
	app._tea_action(CUP_IDS[0],"ask_mentor",old_session)
	check(app.state.energy == 70,"replaced popover callback cannot spend")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	app._unhandled_key_input(escape)
	check(app.selected_object_id.is_empty() and not app.object_popover.visible and app.state.tea_active,"Escape closes popover first")
	first.emit_signal("pressed")
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	outside.position = Vector2(50,350)
	Input.parse_input_event(outside)
	await process_frame
	check(app.selected_object_id.is_empty() and not app.object_popover.visible,"outside pointer closes popover")
	outside.pressed = false
	Input.parse_input_event(outside)
	first.emit_signal("pressed")
	app.tea_rest.emit_signal("pressed")
	check(app.state.energy == 100 and app.state.time_index == 1,"secondary rest uses actual clamped gain and one time slot")
	check(app.state.tea_active and app.state.tea_seen.size() == 2 and not app.object_popover.visible,"rest preserves progress and closes popover")
	app._tea_cancel()
	check(app.state.tea_active and app.tea_scene.visible and not app.cultivation_scene.visible,"2/2 cannot return before whole sidequest completes")
	app._unhandled_key_input(escape)
	check(app.state.tea_active,"Escape without a popover does not leave unfinished branch")
	first.emit_signal("pressed")
	check(app.object_popover.buttons.repair.disabled,"completed action receipts persist while branch stays open")
	# Future terminal return fixture only; today's playable A/B never sets this flag.
	app.state.tea_quest_complete = true
	app._refresh()
	check(app.tea_return.visible,"synthetic terminal flag unlocks explicit return")
	app.tea_return.emit_signal("pressed")
	check(not app.state.tea_active and app.cultivation_scene.visible and app.dialogue_panel.visible,"terminal fixture return releases branch and restores cultivation")
	app._train()
	check(app.state.energy == 78 and app.state.cultivation == 12,"training still settles after tea return")
	await wait_for_tween()
	app._rest()
	check(app.state.energy == 100,"cultivation rest still works")
	app._reset()
	check(app.state.tea_seen.is_empty() and app.state.tea_action_done.is_empty() and not app.tea_scene.visible,"reset clears progress, receipts and selection")
	app._tea_action(CUP_IDS[0],"repair",old_session)
	check(app.state.energy == 100,"stale UI callback after reset has no effect")
	app.state.energy = 7
	app._open_tea()
	app._tea_accept()
	first.emit_signal("pressed")
	check(app.object_popover.buttons.repair.disabled and app.object_popover.buttons.ask_mentor.disabled,"insufficient energy disables both contextual actions")
	app._tea_action(CUP_IDS[0],"repair",app.tea_session)
	check(app.state.energy == 7 and app.state.tea_active and not app.awaiting_continue,"rejection remains passive without confirmation gate")
	app._tea_rest()
	first.emit_signal("pressed")
	check(not app.object_popover.buttons.repair.disabled,"rest re-enables an unperformed affordable action")
	print("TEA_UI_TESTS: %d checks, %d failures" % [checks,failures])
	quit(failures)

func check_popover_bounds() -> void:
	var rect: Rect2 = app.object_popover.get_rect()
	var cup: Rect2 = app._tea_rect(app.selected_object_id)
	check(Rect2(Vector2.ZERO,app.tea_scene.size).encloses(rect),"popover stays inside scene below HUD")
	check(rect.end.y <= cup.position.y-5,"popover does not obscure its cup")
	check(absf(app.object_popover.anchor_point.x + rect.position.x - cup.get_center().x) < 1,"popover anchor follows selected object")

func test_mentor_continue_gates() -> void:
	app._ask()
	check(app.state.dialogue_open, "mentor dialogue opens")
	app._choose("breathing")
	check(app.awaiting_continue and not app.state.dialogue_open, "mentor choice awaits continuation")
	var mentor_snapshot := state_snapshot()
	check(app.tea_entry.disabled, "tea entry is locked during mentor continuation")
	app._open_tea()
	app._train()
	app._rest()
	check(state_snapshot() == mentor_snapshot and not app.state.tea_active, "mentor continuation blocks tea, training, and rest")
	app._continue()
	check(not app.awaiting_continue, "mentor continuation unlocks after continue")

	app.state.energy = 0
	app._ask()
	check(app.awaiting_continue and app.failure_notice and not app.state.dialogue_open, "insufficient energy opens a blocking notice")
	var failure_snapshot := state_snapshot()
	check(app.tea_entry.disabled, "tea entry is locked during insufficient-energy notice")
	app._open_tea()
	app._train()
	app._rest()
	check(state_snapshot() == failure_snapshot and not app.state.tea_active, "insufficient-energy notice blocks tea, training, and rest")
	app._continue()
	check(not app.awaiting_continue and not app.failure_notice, "insufficient-energy notice unlocks after continue")
	app._reset()
	check(app.state.energy == 100 and not app.state.tea_active, "reset restores resources after gating checks")

func test_commission_cancel_and_accept() -> void:
	app._open_tea()
	check(app.dialogue_text.text == app.tea_data.commission and not app.state.tea_accepted, "commission begins as an unaccepted choice")
	app._tea_cancel()
	check(not app.state.tea_accepted and not app.state.tea_active and app.cultivation_scene.visible, "commission cancellation leaves no accepted quest")

func wait_for_tween() -> void:
	var waited := 0.0
	while app.busy and waited < 2.0:
		await create_timer(0.05).timeout
		waited += 0.05
	check(not app.busy, "training tween settles")

func state_snapshot() -> Dictionary:
	return {
		"day": app.state.day,
		"time_index": app.state.time_index,
		"energy": app.state.energy,
		"cultivation": app.state.cultivation,
		"understanding": app.state.understanding,
		"lesson_bonus": app.state.lesson_bonus,
		"tea_accepted": app.state.tea_accepted,
		"tea_seen": app.state.tea_seen.duplicate(true),
		"tea_stage_complete": app.state.tea_stage_complete,
		"tea_quest_complete": app.state.tea_quest_complete,
		"tea_active": app.state.tea_active,

	}

func check_cup_alpha() -> void:
	var path := ProjectSettings.globalize_path("res://assets/art/tea/tea-cups-v1.png")
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		check(false, "tea cup source PNG loads for alpha audit")
		return
	image.convert(Image.FORMAT_RGBA8)
	var mode := image.detect_alpha()
	print("CUP_ALPHA: size=%s format=%d alpha_mode=%d" % [image.get_size(), image.get_format(), mode])
	check(mode != Image.ALPHA_NONE, "cup PNG includes alpha")
	for object_id in CUP_IDS:
		var values: Array = app.tea_layout[object_id + ".atlas"]
		var region := Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))
		var used := alpha_used_bounds(image, region)
		print("CUP_ALPHA: %s atlas=%s used_local=%s" % [object_id, region, used])
		check(used.size.x > 0 and used.size.y > 0, "%s has visible alpha pixels" % object_id)
		var transparent_edges := 0
		transparent_edges += 1 if used.position.x > 0 else 0
		transparent_edges += 1 if used.position.y > 0 else 0
		transparent_edges += 1 if used.end.x < region.size.x else 0
		transparent_edges += 1 if used.end.y < region.size.y else 0
		print("CUP_ALPHA: %s transparent_edge_margins=%d/4" % [object_id, transparent_edges])
		check(transparent_edges == 4, "%s has transparent margins on all four atlas edges" % object_id)

func alpha_used_bounds(image: Image, region: Rect2i) -> Rect2i:
	var left := region.size.x
	var top := region.size.y
	var right := -1
	var bottom := -1
	for y in range(region.position.y, mini(region.end.y, image.get_height())):
		for x in range(region.position.x, mini(region.end.x, image.get_width())):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x - region.position.x)
				top = mini(top, y - region.position.y)
				right = maxi(right, x - region.position.x)
				bottom = maxi(bottom, y - region.position.y)
	if right < left or bottom < top:
		return Rect2i()
	return Rect2i(left, top, right - left + 1, bottom - top + 1)

func capture_render(size: Vector2i) -> void:
	root.size = size
	await process_frame
	await create_timer(0.15).timeout
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		check(false, "rendered viewport texture is available")
		return
	var image: Image = viewport_texture.get_image()
	var output_dir := ProjectSettings.globalize_path("res://.local/qa/tea-object-ui")
	var mkdir_err := DirAccess.make_dir_recursive_absolute(output_dir)
	check(mkdir_err == OK or mkdir_err == ERR_ALREADY_EXISTS, "screenshot directory is available")
	var path := output_dir.path_join("tea-%dx%d.png" % [size.x, size.y])
	var save_err := image.save_png(path)
	print("TEA_RENDER: requested=%s actual=%s path=%s save_error=%d" % [size, image.get_size(), path, save_err])
	check(save_err == OK and root.size == size and image.get_width() > 0, "rendered tea viewport captured for window %s" % size)
	check_popover_bounds()

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)