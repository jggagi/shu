extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const CUP_IDS := ["tea.cup_first", "tea.cup_second"]
var app
var failures := 0
var checks := 0
var render_mode := false

func _initialize() -> void:
	render_mode = OS.get_cmdline_user_args().has("--render") or (DisplayServer.get_name() != "headless" and not OS.has_feature("headless") and not OS.get_cmdline_args().has("--headless"))
	app = MainScene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame

	check(app.state.tea_active == false and app.tea_entry.visible, "cultivation opens with tea inactive and commission entry visible")
	check(not app.state.tea_accepted and app.state.tea_seen.is_empty(), "new run starts without tea progress")
	check_cup_alpha()

	test_mentor_continue_gates()
	test_commission_cancel_and_accept()

	var before_tea := state_snapshot()
	var elapsed_before := float(app.weather.elapsed)
	app._open_tea()
	check(app.dialogue_text.text == app.tea_data.commission and not app.state.tea_accepted, "commission text appears before acceptance")
	check(app.sword_card.visible and app.tea_accept.visible and not app.tea_scene.visible, "unaccepted commission shows acceptance card before terrace")
	app._tea_cancel()
	check(not app.state.tea_accepted and not app.state.tea_active and app.cultivation_scene.visible, "cancelled commission returns without acceptance")
	check(state_snapshot() == before_tea, "cancelled commission changes no cultivation or tea progress")

	app._open_tea()
	var commission_session: int = app.tea_session
	check(app.dialogue_text.text == app.tea_data.commission, "reopening an unaccepted commission shows it again")
	app._tea_accept()
	check(app.state.tea_accepted and app.state.tea_active and app.tea_scene.visible, "acceptance enters the tea terrace")
	check(app.tea_hotspots.size() == 2, "tea terrace registers two distinct cup hotspots")
	for object_id in CUP_IDS:
		var hotspot: Button = app.tea_hotspots[object_id]
		check(hotspot.is_visible_in_tree() and hotspot.get_parent() == app.tea_scene, "%s hotspot is visible in the terrace" % object_id)
	check(app.tea_finish.disabled, "finish stays disabled before both clues are confirmed")

	if render_mode:
		await capture_render(Vector2i(1152, 720))
		await capture_render(Vector2i(960, 600))

	await create_timer(0.2).timeout
	check(float(app.weather.elapsed) > elapsed_before, "weather clock continues while the tea scene is active")
	check(app.state.day == before_tea.day and app.state.time_index == before_tea.time_index and app.state.energy == before_tea.energy and app.state.cultivation == before_tea.cultivation, "tea scene does not advance cultivation time or resources")

	var name_plate = app.tea_names["tea.cup_second"]
	check(name_plate is Button and name_plate.is_visible_in_tree(), "cup name plate is an independently visible hotspot")
	name_plate.emit_signal("pressed")
	var old_read := current_read()
	check(app.tea_reading and not app.state.tea_seen.has("tea.cup_second"), "clicking the cup name plate opens reading without committing")
	check(old_read.bound == ["tea.cup_second", app.tea_session, old_read.token], "name plate reading binds its object, session, and read token")
	check(not app.state.tea_seen.has("tea.cup_first"), "opening a cup does not commit its clue")
	app._tea_cancel()
	check(not app.state.tea_active and app.cultivation_scene.visible and app.state.tea_seen.is_empty(), "cancelling an unconfirmed read returns without committing it")
	var accepted_session: int = app.tea_session
	app._open_tea()
	check(app.state.tea_active and app.tea_session != accepted_session and app.state.tea_accepted, "accepted tea reopens with a fresh session")
	check(app.tea_scene.visible and app.tea_hotspots["tea.cup_first"].is_visible_in_tree() and app.tea_hotspots["tea.cup_second"].is_visible_in_tree(), "both hotspots return on a fresh visit")
	app._tea_ack("tea.cup_first", old_read.session, old_read.token)
	check(app.state.tea_seen.is_empty() and not app.tea_reading, "direct stale acknowledgement after reopen is rejected")

	var first_read := begin_read("tea.cup_first")
	check(not app.state.tea_seen.has("tea.cup_first") and app.tea_reading, "first cup opens without setting its clue")
	check(first_read.bound == ["tea.cup_first", app.tea_session, first_read.token], "first confirm button is bound to object, session, and read token")
	app.tea_confirm.emit_signal("pressed")
	check(app.state.tea_seen.has("tea.cup_first") and app.state.tea_seen.size() == 1 and not app.tea_reading, "confirm button commits only the first cup")
	app._tea_ack("tea.cup_first", first_read.session, first_read.token)
	check(app.state.tea_seen.size() == 1, "repeated acknowledgement does not add the first clue twice")

	var partial_snapshot := state_snapshot()
	app._toggle_weather()
	check(not app.weather.enabled and state_snapshot() == partial_snapshot, "static weather toggle during tea leaves resources and progress unchanged")
	app._toggle_weather()
	check(app.weather.enabled and state_snapshot() == partial_snapshot, "restoring weather during tea also leaves resources and progress unchanged")

	app._tea_cancel()
	check(not app.state.tea_active and app.cultivation_scene.visible and app.state.tea_seen.has("tea.cup_first"), "cancellation returns to cultivation and keeps the confirmed first clue")
	app._open_tea()
	check(app.state.tea_active and app.state.tea_accepted and app.state.tea_seen.size() == 1, "reopened tea retains acceptance and the first clue")

	var second_read := begin_read("tea.cup_second")
	check(second_read.bound == ["tea.cup_second", app.tea_session, second_read.token], "second confirm button is bound to object, session, and read token")
	app.tea_confirm.emit_signal("pressed")
	check(app.state.tea_seen.size() == 2 and app.state.tea_seen.has("tea.cup_second"), "confirm button commits the second cup")
	check(not app.tea_finish.disabled, "finish enables after both clues are confirmed")

	for object_id in CUP_IDS:
		var repeat_read := begin_read(object_id)
		check(app.state.tea_seen.has(object_id), "revisit keeps %s committed before acknowledgement" % object_id)
		app.tea_confirm.emit_signal("pressed")
		check(app.state.tea_seen.size() == 2, "revisiting %s keeps clue count at two" % object_id)
		app._tea_ack(object_id, repeat_read.session, repeat_read.token)
		check(app.state.tea_seen.size() == 2, "repeating %s acknowledgement does not add progress" % object_id)

	app._tea_finish()
	check(app.state.tea_stage_complete and not app.state.tea_active, "finishing both clues completes and releases the tea session")
	check(not app.tea_scene.visible and app.cultivation_scene.visible and app.tea_entry.visible, "finishing returns to the cultivation scene")
	check(app.state.tea_seen.size() == 2, "finish retains the two confirmed clues")

	var cultivation_before := state_snapshot()
	app._train()
	check(app.busy and app.state.energy == int(cultivation_before.energy) - 22 and app.state.cultivation == int(cultivation_before.cultivation) + 12, "training can start after tea returns")
	await wait_for_tween()
	check(not app.busy and app.state.time_index != int(cultivation_before.time_index), "training tween completes and advances cultivation time")
	var after_train := state_snapshot()
	app._rest()
	check(not app.busy and app.state.energy == mini(100, int(after_train.energy) + 34), "rest can run after tea returns")
	check(app.state.tea_accepted and app.state.tea_seen.size() == 2, "training and rest preserve tea progress")

	app._open_tea()
	check(app.state.tea_active and app.tea_scene.visible, "completed tea can be reopened before reset")
	var reset_read := begin_read("tea.cup_second")
	app._reset()
	check(not app.state.tea_active and not app.state.tea_accepted and app.state.tea_seen.is_empty() and not app.state.tea_stage_complete, "reset releases tea and clears its confirmed clues")
	check(not app.tea_scene.visible and app.cultivation_scene.visible and app.tea_entry.visible, "reset restores cultivation and the commission entry")
	app._tea_ack("tea.cup_second", reset_read.session, reset_read.token)
	check(app.state.tea_seen.is_empty(), "read callback from before reset cannot recommit a clue")

	print("TEA_UI_TESTS: %d checks, %d failures" % [checks, failures])
	quit(failures)

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

func begin_read(object_id: String) -> Dictionary:
	app._tea_inspect(object_id)
	var result := current_read()
	check(app.tea_reading and result.token > 0, "%s inspection opens a token-bound reading" % object_id)
	return result

func current_read() -> Dictionary:
	var result := {"session": app.tea_session, "token": -1, "bound": []}
	var connections: Array = app.tea_confirm.pressed.get_connections()
	if connections.size() == 1:
		var callback: Callable = connections[0].callable
		result.token = int(callback.get_bound_arguments()[2])
		result.bound = callback.get_bound_arguments()
	return result

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
	var output_dir := ProjectSettings.globalize_path("res://.local/qa/tea-ab")
	var mkdir_err := DirAccess.make_dir_recursive_absolute(output_dir)
	check(mkdir_err == OK or mkdir_err == ERR_ALREADY_EXISTS, "screenshot directory is available")
	var path := output_dir.path_join("tea-%dx%d.png" % [size.x, size.y])
	var save_err := image.save_png(path)
	print("TEA_RENDER: requested=%s actual=%s path=%s save_error=%d" % [size, image.get_size(), path, save_err])
	check(image.get_size() == size and save_err == OK, "rendered tea viewport captured at %s" % size)

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)