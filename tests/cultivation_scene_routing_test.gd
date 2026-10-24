extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const ROUTE_WEATHER_IDS := ["clear", "cloudy", "light_rain"]
const ROUTE_DYNAMIC_VALUES := [false, true, false]
const FORMAL_FORBIDDEN_NODE_NAMES := [
	"ActorHotspot",
	"SwordHotspot",
	"ResetButton",
	"LightingButton",
	"NightButton",
	"AmbientButtons",
]
const FORMAL_FORBIDDEN_BUTTON_TEXT := [
	"重新开始", "重置", "夜景预览", "调试", "测试", "静态对比", "光影",
	"晴 · 7", "多云 · 8", "小雨 · 9", "生趣", "自动 · U",
]

var app: Control
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	check(packed != null, "the real Tingyu main scene loads")
	if packed == null:
		_finish()
		return

	app = packed.instantiate() as Control
	root.add_child(app)
	await process_frame
	await process_frame
	check(app.state != null and app.weather != null, "the live host owns its gameplay state and Tingyu weather adapter")
	if app.state == null or app.weather == null:
		_finish()
		return

	# Keep the navigation checks deterministic while preserving the real host UI.
	app.set_ambient_life_enabled(false)
	await _check_live_gates()
	await _prepare_completed_progress_fixture()
	await _check_three_round_trips()
	await _check_real_actions_after_return()

	print("CULTIVATION_SCENE_ROUTING_TESTS: %d checks, %d failures" % [checks, failures])
	_finish()

func _check_live_gates() -> void:
	check(app.scene_router.current_scene_id == "tingyu", "the host begins in Tingyu")
	check(app.back_mountain_entry != null and app.back_mountain_entry.visible, "Tingyu exposes the real Back Mountain entry")
	check(app.can_visit_back_mountain(), "an idle cultivation host can visit Back Mountain")

	# A real training button makes the host busy for its authored action duration.
	app.train_button.emit_signal("pressed")
	check(app.busy and not app.can_visit_back_mountain(), "an in-progress training action blocks navigation")
	check(not app.request_back_mountain(), "the host rejects a direct navigation request while training is busy")
	var training_settled := await _wait_for_action_idle()
	check(training_settled, "training and its actor animation settle before the next gate check")
	check(app.can_visit_back_mountain(), "the route becomes available after the training action settles")

	app.mentor_button.emit_signal("pressed")
	check(app.actor_life.is_action_active(), "the mentor's listen pose remains held during the open conversation")
	check(app.state.dialogue_open and not app.can_visit_back_mountain(), "an open mentor conversation blocks navigation")
	check(not app.request_back_mountain(), "the host rejects navigation while mentor dialogue is open")
	app.choices[2].emit_signal("pressed")
	var cancelled_dialogue_idle := await _wait_for_actor_idle()
	check(not app.state.dialogue_open, "the real mentor cancel choice closes the dialogue gate")
	check(cancelled_dialogue_idle and app.can_visit_back_mountain(), "closing dialogue releases the held pose before navigation becomes available")

	app.mentor_button.emit_signal("pressed")
	check(app.actor_life.is_action_active(), "the listen pose remains held until a mentor choice is made")
	app.choices[0].emit_signal("pressed")
	check(app.actor_life.is_action_active(), "the teach pose remains held while the result awaits Continue")
	check(app.awaiting_continue and not app.can_visit_back_mountain(), "a mentor result awaiting Continue blocks navigation")
	check(not app.request_back_mountain(), "the host rejects navigation while Continue is pending")
	app.continue_button.emit_signal("pressed")
	check(not app.awaiting_continue, "the real Continue button releases the dialogue gate")
	var continued_actor_idle := await _wait_for_actor_idle()
	check(continued_actor_idle and app.can_visit_back_mountain(), "Continue releases the held pose before the route becomes available")

	var prop_ids: Array = app.corridor_props.keys()
	check(not prop_ids.is_empty(), "Tingyu retains its authored corridor props")
	if not prop_ids.is_empty():
		app._select_corridor_prop(str(prop_ids[0]))
		await process_frame
		check(app.corridor_popover.visible and not app.can_visit_back_mountain(), "an open corridor prop popover blocks navigation")
		check(not app.request_back_mountain(), "the host rejects navigation while a corridor prop is selected")
		app._close_corridor_prop()
		check(app.can_visit_back_mountain(), "closing the corridor prop releases its navigation gate")

	# Exercise Tea's real commission, accepted branch, object popover, and past view.
	app._open_tea()
	check(app.state.tea_active and not app.state.tea_accepted, "opening the real commission creates the pending Tea state")
	check(not app.back_mountain_entry.visible and not app.can_visit_back_mountain(), "the pending commission hides and blocks Back Mountain entry")
	check(not app.request_back_mountain(), "the host rejects navigation during the pending commission")
	app.tea_accept.emit_signal("pressed")
	await process_frame
	check(app.state.tea_active and app.state.tea_accepted and not app.state.tea_quest_complete, "accepting the commission enters an incomplete Tea branch")
	check(not app.back_mountain_entry.visible and not app.can_visit_back_mountain(), "an accepted incomplete Tea branch hides and blocks Back Mountain entry")
	var accepted_incomplete_snapshot := _script_variable_snapshot(app.state)
	check(not app.request_back_mountain(), "the host rejects navigation during an accepted incomplete Tea branch")
	check(_script_variable_snapshot(app.state) == accepted_incomplete_snapshot, "rejected navigation preserves the full accepted-incomplete Tea state")
	app.tea_hotspots["tea.cup_first"].emit_signal("pressed")
	await process_frame
	check(app.object_popover.visible and not app.can_visit_back_mountain(), "the active Tea cup opens its real object popover while navigation stays blocked")
	var popover_snapshot := _script_variable_snapshot(app.state)
	check(not app.request_back_mountain(), "the host rejects navigation while the Tea object popover is open")
	check(_script_variable_snapshot(app.state) == popover_snapshot, "rejected navigation preserves the open Tea object state")

	# The F-stage authored memory is entered through its normal Tea hotspot.
	app._close_object_popover()
	app.state.tea_story_stage = 3
	app.state.tea_scene_id = app.state.TEA_COURTYARD_ID
	app._refresh()
	check(app.tea_hotspots.has("tea.memory") and app.tea_hotspots["tea.memory"].visible, "the memory-stage hotspot is available in the authored courtyard stage")
	app.tea_hotspots["tea.memory"].emit_signal("pressed")
	await process_frame
	check(app.tea_memory.visible and not app.object_popover.visible, "the real Tea memory hotspot opens the full-screen past view")
	check(not app.can_visit_back_mountain() and not app.back_mountain_entry.visible, "the current Tea memory view keeps Back Mountain unavailable")
	var memory_snapshot := _script_variable_snapshot(app.state)
	check(not app.request_back_mountain(), "the host rejects navigation while a Tea memory is open")
	check(_script_variable_snapshot(app.state) == memory_snapshot, "rejected navigation preserves the full current Tea memory state")

	app._close_object_popover()
	app.state.tea_story_stage = 7
	app.state.tea_scene_id = app.state.TEA_TERRACE_ID
	app.state.tea_story_seen = {"tea.cup_first": true, "tea.cup_second": true}
	app.state.tea_seen = {"tea.cup_first": true, "tea.cup_second": true}
	app.state.tea_stage_complete = true
	app.state.tea_ending_step = 2
	app.state.tea_quest_complete = true
	app._refresh()
	check(app.state.tea_active and app.state.tea_quest_complete and app.tea_return.visible, "a completed Tea quest remains active until its explicit return action")
	check(not app.can_visit_back_mountain() and not app.back_mountain_entry.visible, "a completed but active Tea branch still hides and blocks Back Mountain entry")
	var completed_active_snapshot := _script_variable_snapshot(app.state)
	check(not app.request_back_mountain(), "the host rejects navigation while a completed Tea branch awaits its return action")
	check(_script_variable_snapshot(app.state) == completed_active_snapshot, "rejected navigation preserves the completed active Tea state")

	app._reset()
	await process_frame
	await process_frame
	check(not app.state.tea_active and not app.tea_memory.visible, "the real reset closes Tea and its current memory view")
	check(app.scene_router.current_scene_id == "tingyu" and app.can_visit_back_mountain(), "reset leaves the host in an available Tingyu scene")

func _prepare_completed_progress_fixture() -> void:
	app.state.reset()
	app.state.energy = 78
	app.state.cultivation = 12
	app.state.time_index = 2
	app.state.understanding = 1
	app.state.lesson_bonus = 6
	app.state.tea_accepted = true
	app.state.tea_seen = {"tea.cup_first": true, "tea.cup_second": true}
	app.state.tea_stage_complete = true
	app.state.tea_c_seen = {"tea.household": true, "tea.ledger": true}
	app.state.tea_c_complete = true
	app.state.tea_action_done = {"tea.cup_first": {"repair": true, "ask_mentor": true}}
	app.state.tea_quest_complete = true
	app.state.tea_story_stage = 7
	app.state.tea_story_seen = {"tea.cup_first": true, "tea.cup_second": true}
	app.state.tea_ending_step = 2
	app.state.tea_session = 9
	app.state._tea_read_counter = 4
	app.state._tea_pending_object_id = ""
	app.state._tea_pending_read_token = 0
	app.state._tea_ending_first_fill_msec = 123456
	app.state.tea_active = false
	app._refresh()
	await process_frame

	check(app.state.energy == 78 and app.state.cultivation == 12 and app.state.time_index == 2, "the navigation fixture starts from nondefault cultivation values")
	check(app.state.lesson_bonus == 6, "the fixture retains an unused mentor lesson bonus")
	check(app.state.tea_accepted and app.state.tea_quest_complete and app.state.tea_story_seen.size() == 2, "the fixture retains a completed Tea quest outside the active branch")
	check(app.state.tea_c_complete and app.state.tea_c_seen.size() == 2 and app.state.tea_action_done["tea.cup_first"].size() == 2, "the fixture retains completed courtyard clues and Tea action receipts")
	var initial_snapshot := _script_variable_snapshot(app.state)
	check(initial_snapshot.has("_tea_read_counter") and initial_snapshot.has("_tea_pending_read_token") and initial_snapshot.has("_tea_ending_first_fill_msec"), "the dynamic snapshot includes private Tea counters and tokens")
	check(initial_snapshot.has("_tea_story_source") and not (initial_snapshot["_tea_story_source"] as Dictionary).is_empty(), "the dynamic snapshot includes the pinned Tea story source")
	check(app.back_mountain_entry.visible and app.can_visit_back_mountain(), "completed Tea progress outside an active branch permits navigation")

func _check_three_round_trips() -> void:
	var state_identity: Object = app.state
	var original_weather: Node = app.weather
	var before: Dictionary = _script_variable_snapshot(app.state)
	var return_methods := ["host", "button", "escape"]

	for index in range(ROUTE_WEATHER_IDS.size()):
		var weather_id := str(ROUTE_WEATHER_IDS[index])
		var dynamic_enabled := bool(ROUTE_DYNAMIC_VALUES[index])
		check(app.weather.set_weather(weather_id, false), "Tingyu selects the %s profile before trip %d" % [weather_id, index + 1])
		app.weather.set_dynamic(dynamic_enabled)
		await process_frame
		check(app.shared_weather_id == weather_id and app.shared_dynamic_enabled == dynamic_enabled, "weather.changed carries %s / dynamic=%s into host preferences" % [weather_id, dynamic_enabled])
		check(_script_variable_snapshot(app.state) == before, "selecting weather before trip %d preserves every DemoState script property" % (index + 1))

		if index == 1:
			check(app.request_back_mountain(), "trip 2 enters through the host request method")
		else:
			app.back_mountain_entry.emit_signal("pressed")
		await process_frame
		await process_frame
		check(app.scene_router.current_scene_id == "back_mountain", "trip %d changes the router to Back Mountain" % (index + 1))
		check(app.back_mountain_view != null and app.back_mountain_view.visible, "trip %d displays the formal mountain view" % (index + 1))
		check(not app.cultivation_scene.visible, "trip %d hides the retained Tingyu scene" % (index + 1))
		check(app.state == state_identity, "trip %d borrows the original DemoState object" % (index + 1))
		check(app.back_mountain_view.get("state") == state_identity, "trip %d passes the same DemoState reference into the view" % (index + 1))
		check(app.back_mountain_view.get("dynamic_enabled") == dynamic_enabled, "trip %d configures the requested Static/Dynamic state" % (index + 1))
		var mountain_environment: Object = app.back_mountain_view.get("environment_presenter")
		check(mountain_environment != null, "trip %d configures a scene environment presenter" % (index + 1))
		if mountain_environment != null:
			check(str(mountain_environment.get("weather_id")) == weather_id, "trip %d carries the selected %s profile into Back Mountain" % [index + 1, weather_id])
			check(str(mountain_environment.get("time_profile_id")) == str(app.weather.presenter.get("time_profile_id")), "trip %d carries Tingyu's actual cultivation time profile into Back Mountain" % (index + 1))
		check(app.weather == original_weather and is_instance_valid(original_weather) and original_weather.is_inside_tree(), "trip %d retains the original live Tingyu weather adapter" % (index + 1))
		check(_script_variable_snapshot(app.state) == before, "entering trip %d preserves every DemoState script property" % (index + 1))
		check(not app.request_back_mountain(), "trip %d rejects an invalid re-entry request" % (index + 1))
		check(app.scene_router.current_scene_id == "back_mountain", "invalid re-entry leaves trip %d in Back Mountain" % (index + 1))
		_check_formal_view_controls(app.back_mountain_view)

		await create_timer(0.12).timeout
		check(_script_variable_snapshot(app.state) == before, "staying in trip %d does not settle or mutate any DemoState property" % (index + 1))
		if index == 2:
			await _check_ignored_formal_keys(weather_id, dynamic_enabled, before)

		var mounted_view: Control = app.back_mountain_view
		if str(return_methods[index]) == "host":
			check(app.return_to_tingyu(), "trip 1 returns through the host method")
		elif str(return_methods[index]) == "button":
			var return_button := mounted_view.get("return_button") as Button
			check(return_button != null, "trip 2 exposes its formal return button")
			if return_button != null:
				return_button.emit_signal("pressed")
		else:
			await _inject_key(KEY_ESCAPE)
		await process_frame
		await process_frame
		check(app.scene_router.current_scene_id == "tingyu", "trip %d returns to Tingyu" % (index + 1))
		check(app.back_mountain_view == null, "trip %d releases the mounted mountain view" % (index + 1))
		check(app.cultivation_scene.visible, "trip %d restores the retained Tingyu scene" % (index + 1))
		check(app.state == state_identity and _script_variable_snapshot(app.state) == before, "trip %d returns the same state with every script property unchanged" % (index + 1))
		check(app.weather == original_weather and is_instance_valid(original_weather), "trip %d keeps the original Tingyu adapter after return" % (index + 1))
		check(app.weather.presenter.weather_id == weather_id and app.weather.enabled == dynamic_enabled, "trip %d restores the same %s / Static-Dynamic preference" % [index + 1, weather_id])
		check(not app.return_to_tingyu(), "trip %d rejects an invalid second return" % (index + 1))
		check(app.scene_router.current_scene_id == "tingyu", "invalid return leaves trip %d in Tingyu" % (index + 1))

func _check_ignored_formal_keys(weather_id: String, dynamic_enabled: bool, before: Dictionary) -> void:
	for keycode in [KEY_1, KEY_R, KEY_0, KEY_7, KEY_C]:
		await _inject_key(keycode)
		check(app.scene_router.current_scene_id == "back_mountain", "formal Back Mountain ignores debug key %s" % OS.get_keycode_string(keycode))
		check(_script_variable_snapshot(app.state) == before, "debug key %s cannot settle or reset gameplay state" % OS.get_keycode_string(keycode))
		check(app.weather.presenter.weather_id == weather_id and app.weather.enabled == dynamic_enabled, "debug key %s cannot change the formal weather preference" % OS.get_keycode_string(keycode))

func _check_formal_view_controls(view: Control) -> void:
	var stack: Array[Node] = [view]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		check(str(node.name) not in FORMAL_FORBIDDEN_NODE_NAMES, "formal view omits debug node %s" % node.name)
		if node is Button:
			var button := node as Button
			for forbidden_text in FORMAL_FORBIDDEN_BUTTON_TEXT:
				check(not button.text.contains(str(forbidden_text)), "formal button %s omits debug label %s" % [button.name, forbidden_text])
		for child in node.get_children():
			stack.append(child)
	check(not view.has_method("request_training") and not view.has_method("reset_demo"), "formal view exposes no standalone training or reset actions")
	var has_return_signal := false
	for signal_info in view.get_signal_list():
		if str(signal_info.name) == "return_requested":
			has_return_signal = true
			break
	check(has_return_signal, "formal view provides the host return_requested signal")

func _check_real_actions_after_return() -> void:
	check(app.scene_router.current_scene_id == "tingyu" and app.can_visit_back_mountain(), "real cultivation actions begin after returning to Tingyu")
	check(app.state.energy == 78 and app.state.cultivation == 12 and app.state.time_index == 2 and app.state.lesson_bonus == 6, "the round-trip fixture is still intact before the real action flow")
	app.train_button.emit_signal("pressed")
	check(app.busy, "the original training button still enters its existing action animation after return")
	var training_settled := await _wait_for_action_idle()
	check(training_settled, "the post-return training animation settles")
	check(app.state.energy == 56 and app.state.cultivation == 30 and app.state.lesson_bonus == 0, "post-return training consumes the preserved one-time lesson bonus")

	app.mentor_button.emit_signal("pressed")
	check(app.state.dialogue_open and app.actor_life.is_action_active(), "the original mentor interaction opens in its held listen pose after return")
	check(not app.can_visit_back_mountain(), "the post-return open mentor conversation blocks navigation")
	app.choices[0].emit_signal("pressed")
	check(app.awaiting_continue and app.actor_life.is_action_active(), "the original mentor choice holds its teach pose until Continue")
	check(app.state.understanding == 2 and app.state.lesson_bonus == 6, "the original mentor choice settles and restores its next-training bonus")
	check(not app.can_visit_back_mountain(), "the post-return mentor result awaiting Continue blocks navigation")
	app.continue_button.emit_signal("pressed")
	check(not app.awaiting_continue and not app.state.dialogue_open, "the original Continue control remains usable after return")
	var mentor_result_idle := await _wait_for_actor_idle()
	check(mentor_result_idle and app.can_visit_back_mountain(), "post-return Continue releases the held pose before navigation is available")
	app.rest_button.emit_signal("pressed")
	check(app.state.energy == 82 and app.state.cultivation == 30, "the original rest control restores 34 energy after return")
	check(app.state.day == 2 and app.state.time_index == 0, "training, mentor choice, Continue, and rest retain the original cultivation clock")
	await _wait_for_actor_idle()

func _script_variable_snapshot(target: Object) -> Dictionary:
	var result: Dictionary = {}
	for property_info in target.get_property_list():
		if (int(property_info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property_info.name)
		var value: Variant = target.get(name)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		result[name] = value
	return result

func _wait_for_actor_idle() -> bool:
	for _attempt in range(50):
		if app.actor_life == null or not app.actor_life.is_action_active():
			return true
		await create_timer(0.1).timeout
	return app.actor_life == null or not app.actor_life.is_action_active()

func _wait_for_action_idle() -> bool:
	for _attempt in range(60):
		if not app.busy and (app.actor_life == null or not app.actor_life.is_action_active()):
			return true
		await create_timer(0.1).timeout
	return not app.busy and (app.actor_life == null or not app.actor_life.is_action_active())

func _inject_key(keycode: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = keycode
	pressed.physical_keycode = keycode
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	var released := InputEventKey.new()
	released.keycode = keycode
	released.physical_keycode = keycode
	released.pressed = false
	Input.parse_input_event(released)
	await process_frame

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _finish() -> void:
	quit(failures)
