extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const Catalog := preload("res://scripts/sword_manual_catalog.gd")
const StateScript := preload("res://scripts/demo_state.gd")
const FORMAL_FONT_PATH := "res://assets/fonts/ShuCultivationSwordSerif.ttf"
const FRAME_DELTA := 1.0 / 30.0
const MANUAL_IDS := ["pine_wind", "listening_rain", "returning_tide", "rising_peak", "swift_swallow"]
const CLIP_IDS := ["songfeng", "chuanyun", "huilan", "tiaoyue", "xieying"]
const REQUIRED_FONT_TEXT := "后山选择剑谱松风剑穿云剑回澜剑挑月剑斜影剑练剑收势后返回听雨廊待机下劈平刺进步双刺横扫反斩低扫上挑斜斩连击剑术精力不足暂时无法"

var app: Control
var checks := 0
var failures := 0
var finished_action_ids: Array[int] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_formal_font_coverage()
	var packed: PackedScene = MainScene
	check(packed != null, "the real cultivation main scene loads")
	if packed == null:
		_finish()
		return

	app = packed.instantiate() as Control
	root.add_child(app)
	await process_frame
	await process_frame
	check(app.state != null and app.scene_router.current_scene_id == "tingyu", "the main scene starts in Tingyu with its live DemoState")
	if app.state == null:
		_finish()
		return

	app.set_ambient_life_enabled(false)
	app._reset()
	_seed_completed_tea_progress()
	app.state.day = 2
	app.state.time_index = app.state.rules.times.size() - 1
	app.state.energy = int(app.state.rules.energy_max)
	app.state.cultivation = 23
	app.state.swordsmanship = 7
	app.state.understanding = 3
	app.state.lesson_bonus = int(app.state.rules.lesson_bonus)
	app._refresh()

	_check_manual_catalog_contract()
	await _check_five_real_manual_cycles()
	_check_reset_clears_manual_progress()
	await _check_insufficient_energy_is_atomic()
	await _check_mentor_bonus_survives_sword_training()
	await _check_tea_gates_remain_active()
	_finish()


func _check_formal_font_coverage() -> void:
	var font := load(FORMAL_FONT_PATH) as FontFile
	check(font != null, "the formal cultivation font loads from its project resource path")
	if font == null:
		return
	var checked: Dictionary = {}
	for char_index in range(REQUIRED_FONT_TEXT.length()):
		var value := REQUIRED_FONT_TEXT.unicode_at(char_index)
		if checked.has(value):
			continue
		checked[value] = true
		check(font.has_char(value), "the formal font includes player-facing codepoint U+%04X" % value)


func _check_manual_catalog_contract() -> void:
	var manuals: Array = Catalog.manuals()
	check(manuals.size() == MANUAL_IDS.size(), "the formal catalog contains exactly five selectable manuals")
	for index in range(MANUAL_IDS.size()):
		var manual_id := str(MANUAL_IDS[index])
		var clip_id := str(CLIP_IDS[index])
		var manual: Dictionary = Catalog.manual(manual_id)
		check(not manual.is_empty(), "%s resolves from the formal manual catalog" % manual_id)
		check(str(manual.get("clip_id", "")) == clip_id, "%s maps to its approved %s clip" % [manual_id, clip_id])
		var techniques: Array = manual.get("techniques", [])
		check(techniques.size() == 1, "%s exposes only its approved combination" % manual_id)
		check(Catalog.technique(manual_id, 0) == Catalog.technique(manual_id, 17), "%s keeps one stable combination regardless of practice count" % manual_id)


func _check_five_real_manual_cycles() -> void:
	for index in range(MANUAL_IDS.size()):
		if app.scene_router.current_scene_id == "tingyu":
			check(app.request_back_mountain(), "manual cycle %d enters the formal Back Mountain view" % (index + 1))
			await process_frame
			await process_frame
		var view: Variant = app.back_mountain_view
		check(view != null and app.scene_router.current_scene_id == "back_mountain", "manual cycle %d mounts the real host view" % (index + 1))
		if view == null:
			return

		var manual_id := str(MANUAL_IDS[index])
		var clip_id := str(CLIP_IDS[index])
		check(view.manual_buttons.size() == MANUAL_IDS.size(), "the real view exposes five manual buttons")
		var selection_before := _script_variable_snapshot(app.state)
		var manual_button: Button = view.manual_buttons.get(manual_id)
		check(manual_button != null, "%s has a real selectable manual button" % manual_id)
		if manual_button == null:
			return
		manual_button.emit_signal("pressed")
		var selection_after := _script_variable_snapshot(app.state)
		check(app.state.selected_sword_manual_id == manual_id, "%s becomes selected through its real view button" % manual_id)
		check(_snapshot_without(selection_after, ["selected_sword_manual_id"]) == _snapshot_without(selection_before, ["selected_sword_manual_id"]), "selecting %s is free and state-neutral" % manual_id)

		var practice: Variant = view.sword_practice
		check(practice != null, "%s uses the formal image-cycle practice node" % manual_id)
		if practice == null:
			return
		var technique: Dictionary = Catalog.technique(manual_id, int(app.state.sword_manual_practice_counts.get(manual_id, 0)))
		check(practice.selected_manual_id == manual_id and practice.selected_clip_id == clip_id, "%s selects the mapped %s frames through the real view" % [manual_id, clip_id])
		check(practice.selected_technique_id == str(technique.get("id", "")), "%s selects its single approved combination" % manual_id)
		check(practice.resource_ready() and view.prepare_sword_training(), "%s loads all required resources before settlement" % manual_id)
		check(practice._idle_frames.size() == 60 and practice._action_frames.size() == 180, "%s has the approved 60 idle and 180 action frames" % manual_id)
		check(is_equal_approx(float(practice.CYCLE_FPS), 30.0), "%s runs at the approved 30 fps" % manual_id)

		if index == 0:
			# Use the explicit synthetic clock to visit the last idle frame, then
			# verify that Static freezes the idle and scene clocks.
			view.set_dynamic(true)
			practice._idle_elapsed = 0.0
			practice._apply_idle_frame(0)
			_advance_practice(practice, 59)
			check(not practice.playing and practice.current_frame_index == 59, "the dynamic idle cycle reaches its 60th authored frame")
		view.set_dynamic(false)
		var frozen_frame := int(practice.current_frame_index)
		var frozen_presentation_time := float(view.presentation_time)
		var frozen_environment: Dictionary = view.environment_presenter.get_current_environment()
		practice._process(1.0)
		view._process(1.0)
		check(not practice.playing and practice.current_frame_index == frozen_frame, "Static freezes idle character playback")
		check(is_equal_approx(float(view.presentation_time), frozen_presentation_time), "Static freezes the scene presentation clock")
		check(view.environment_presenter.get_current_environment() == frozen_environment, "Static preserves the current environment")
		# Begin every real action from a stable authored idle frame. This keeps the
		# synthetic clock focused on the 180-frame approved combination.
		practice._apply_idle_frame(0)
		practice.phase = "待机"
		practice.elapsed = 0.0
		practice._action_elapsed = 0.0
		practice._receipt_elapsed = 0.0
		practice._settle_elapsed = 0.0
		practice._actor_state = "idle"
		practice.playing = false

		var manual_count_before := int(app.state.sword_manual_practice_counts.get(manual_id, 0))
		var before := _script_variable_snapshot(app.state)
		var day_before := int(app.state.day)
		var time_before := int(app.state.time_index)
		var energy_before := int(app.state.energy)
		var sword_before := int(app.state.swordsmanship)
		finished_action_ids.clear()
		practice.finished.connect(_record_finished_action)
		view.sword_training_button.emit_signal("pressed")
		var receipt: Dictionary = view.sword_receipt.duplicate(true)
		check(app.busy and view.busy and practice.playing, "%s starts through the real training button and continues in Static" % manual_id)
		check(receipt.get("manual_id", "") == manual_id and receipt.get("technique_id", "") == technique.get("id", ""), "%s action receives its frozen selected-form receipt" % manual_id)
		check(int(receipt.get("energy_cost", 0)) == 22 and int(receipt.get("gain", 0)) == 10 and int(receipt.get("duration", 0)) == 1, "%s receipt records the authored -22/+10/+1 rules" % manual_id)
		var expected_time_count := int(app.state.rules.times.size())
		var expected_day := day_before + (1 if time_before == expected_time_count - 1 else 0)
		var expected_time := (time_before + 1) % expected_time_count
		check(app.state.energy == energy_before - 22 and app.state.swordsmanship == sword_before + 10, "%s settles exactly once before its presentation" % manual_id)
		check(app.state.day == expected_day and app.state.time_index == expected_time, "%s advances exactly one time slot with rollover" % manual_id)
		var expected_counts: Dictionary = before.sword_manual_practice_counts.duplicate(true)
		expected_counts[manual_id] = manual_count_before + 1
		check(app.state.sword_manual_practice_counts == expected_counts, "%s increments only its own practice count once" % manual_id)
		check(_snapshot_without(_script_variable_snapshot(app.state), ["day", "time_index", "energy", "swordsmanship", "sword_manual_practice_counts"]) == _snapshot_without(before, ["day", "time_index", "energy", "swordsmanship", "sword_manual_practice_counts"]), "%s leaves cultivation, mentor and Tea state unchanged" % manual_id)

		var action_id := int(app._sword_action_serial)
		var settled_snapshot := _script_variable_snapshot(app.state)
		var prior_title: String = app.speaker.text
		var prior_dialogue: String = app.dialogue_text.text
		var prior_result: String = app.result_text.text
		check(not app.return_to_tingyu(), "%s cannot leave while presentation is active" % manual_id)
		check(not app._select_sword_manual(str(MANUAL_IDS[(index + 1) % MANUAL_IDS.size()])).get("ok", false), "%s locks manual selection during presentation" % manual_id)
		check(not app._request_sword_training().get("ok", false), "%s rejects a duplicate host request" % manual_id)
		view.return_button.emit_signal("pressed")
		view.sword_training_button.emit_signal("pressed")
		var escape := InputEventKey.new()
		escape.pressed = true
		escape.keycode = KEY_ESCAPE
		view._unhandled_key_input(escape)
		app._finish_sword_training(action_id + 1)
		app._finish_sword_training(action_id)
		check(app.busy and practice.playing and app.scene_router.current_scene_id == "back_mountain", "%s ignores stale and premature current completion, return, Escape, and duplicate button calls" % manual_id)
		check(_script_variable_snapshot(app.state) == settled_snapshot, "%s guard attempts cannot settle a second time" % manual_id)
		check(app.speaker.text == prior_title and app.dialogue_text.text == prior_dialogue and app.result_text.text == prior_result, "%s stale completion cannot show results" % manual_id)

		_advance_practice(practice, 179)
		check(practice.playing and practice._action_elapsed < 6.0 and practice.current_frame_index >= 178, "%s stays active through the first 179 action frames" % manual_id)
		practice._process(FRAME_DELTA)
		practice._process(0.00001)
		check(practice.playing and absf(float(practice._action_elapsed) - 6.0) < 0.001, "%s completes 180 action frames before its receipt hold" % manual_id)
		_advance_practice(practice, 23)
		check(practice.playing and absf(float(practice._receipt_elapsed) - 23.0 * FRAME_DELTA) < 0.001, "%s remains active through 23 receipt-hold frames" % manual_id)
		practice._process(FRAME_DELTA + 0.00001)
		check(not practice.playing and finished_action_ids == [action_id], "%s emits one completion after the action and receipt hold" % manual_id)
		check(app.scene_router.current_scene_id == "tingyu" and app.back_mountain_view == null and not app.busy, "%s returns to Tingyu when its presentation completes" % manual_id)
		check(app.result_text.visible and app.result_text.text.contains("剑术 +10"), "%s shows its result exactly after completion" % manual_id)
		var completed_snapshot := _script_variable_snapshot(app.state)
		var completed_title: String = app.speaker.text
		var completed_dialogue: String = app.dialogue_text.text
		var completed_result: String = app.result_text.text
		app._finish_sword_training(action_id)
		check(_script_variable_snapshot(app.state) == completed_snapshot and finished_action_ids.size() == 1, "%s ignores repeated completion without another reward" % manual_id)
		check(app.speaker.text == completed_title and app.dialogue_text.text == completed_dialogue and app.result_text.text == completed_result, "%s keeps the one completion result" % manual_id)
		check(app.state.sword_manual_practice_counts.get(manual_id, 0) == manual_count_before + 1, "%s retains one count after return" % manual_id)
		if index + 1 < MANUAL_IDS.size():
			app.state.energy = int(app.state.rules.energy_max)
			app._refresh()
			await process_frame


func _check_reset_clears_manual_progress() -> void:
	app._reset()
	check(app.scene_router.current_scene_id == "tingyu", "reset starts from the retained Tingyu scene")
	check(app.state.selected_sword_manual_id == Catalog.DEFAULT_ID, "reset restores the default formal manual")
	for manual_id in MANUAL_IDS:
		check(int(app.state.sword_manual_practice_counts.get(str(manual_id), -1)) == 0, "reset clears the %s practice count" % str(manual_id))
	check(app.state.energy == int(app.state.rules.energy_max) and app.state.swordsmanship == 0 and app.state.time_index == 0, "reset preserves the existing cultivation reset rules")


func _check_insufficient_energy_is_atomic() -> void:
	app.state.energy = int(app.state.rules.sword_training_cost) - 1
	app.state.cultivation = 12
	app._refresh()
	check(app.request_back_mountain(), "the low-energy fixture enters through the real host route")
	await process_frame
	await process_frame
	var view: Variant = app.back_mountain_view
	check(view != null and view.prepare_sword_training(), "the low-energy case has its selected clip prepared")
	if view == null:
		return
	var practice: Variant = view.sword_practice
	var before := _script_variable_snapshot(app.state)
	var rejected: Dictionary = app._request_sword_training()
	check(not bool(rejected.get("ok", false)), "one point below the energy cost rejects formal training")
	check(_script_variable_snapshot(app.state) == before, "insufficient energy preserves the entire DemoState, including Tea")
	check(not app.busy and not view.busy and not practice.playing, "insufficient energy never starts presentation")
	check(app.return_to_tingyu(), "the failed attempt can return to Tingyu")
	await process_frame
	await process_frame


func _check_mentor_bonus_survives_sword_training() -> void:
	app._reset()
	app.mentor_button.emit_signal("pressed")
	check(app.state.dialogue_open, "the real mentor action opens the breathing dialogue")
	app.choices[0].emit_signal("pressed")
	check(app.awaiting_continue and app.state.lesson_bonus == int(app.state.rules.lesson_bonus), "the real breathing choice grants its pending bonus")
	app.continue_button.emit_signal("pressed")
	check(not app.awaiting_continue and app.state.lesson_bonus > 0, "Continue releases the host gate and retains the bonus")
	# Navigation also waits for the existing mentor pose to finish returning.
	var actor_guard := 0
	while app.actor_life.is_action_active() and actor_guard < 240:
		await process_frame
		actor_guard += 1
	check(not app.actor_life.is_action_active(), "the mentor pose returns before entering Back Mountain")
	app.weather.set_dynamic(false)
	check(app.request_back_mountain(), "the mentor fixture enters Back Mountain through the real route")
	await process_frame
	await process_frame
	var view: Variant = app.back_mountain_view
	if view == null:
		check(false, "the mentor fixture mounts a formal view")
		return
	view.set_dynamic(false)
	var practice: Variant = view.sword_practice
	practice._apply_idle_frame(0)
	check(view.prepare_sword_training(), "the mentor fixture prepares the approved default form")
	var bonus_before := int(app.state.lesson_bonus)
	view.sword_training_button.emit_signal("pressed")
	check(app.busy and view.busy and practice.playing, "the mentor fixture starts the real formal action")
	_advance_practice_to_finish(practice)
	check(app.scene_router.current_scene_id == "tingyu" and app.state.lesson_bonus == bonus_before, "formal sword practice leaves the mentor bonus pending")
	var breathing: Dictionary = app.state.train()
	check(bool(breathing.get("ok", false)) and int(breathing.get("gain", 0)) == 18, "the next breathing action still consumes its full mentor bonus")
	check(app.state.lesson_bonus == 0 and app.state.swordsmanship == 10, "breathing consumes only its own bonus and preserves swordsmanship")


func _check_tea_gates_remain_active() -> void:
	app._reset()
	app._open_tea()
	app.tea_accept.emit_signal("pressed")
	await process_frame
	check(app.state.tea_active and app.state.tea_accepted, "the real Tea commission remains active after acceptance")
	var before := _script_variable_snapshot(app.state)
	check(not app.request_back_mountain(), "the host still blocks Back Mountain during an active Tea branch")
	var state_rejection: Dictionary = app.state.train_sword()
	check(not bool(state_rejection.get("ok", false)), "DemoState still rejects sword settlement during Tea")
	check(not bool(app._request_sword_training().get("ok", false)), "the host rejects a formal training request outside Back Mountain")
	check(_script_variable_snapshot(app.state) == before, "Tea gating preserves the active Tea state")
	app._reset()
	check(not app.state.tea_active and not app.state.tea_accepted, "reset still clears the active Tea session")


func _seed_completed_tea_progress() -> void:
	app.state.tea_accepted = true
	app.state.tea_seen = {"tea.cup_first": true, "tea.cup_second": true}
	app.state.tea_stage_complete = true
	app.state.tea_quest_complete = true
	app.state.tea_scene_id = StateScript.TEA_TERRACE_ID
	app.state.tea_c_seen = {"tea.household": true, "tea.ledger": true}
	app.state.tea_c_complete = true
	app.state.tea_action_done = {"tea.cup_first": {"repair": true}}
	app.state.tea_story_stage = 7
	app.state.tea_story_seen = {"tea.cup_first": true, "tea.cup_second": true}
	app.state.tea_ending_step = 2
	app.state.tea_session = 9
	app.state._tea_read_counter = 4
	app.state._tea_pending_object_id = ""
	app.state._tea_pending_read_token = 0
	app.state._tea_ending_first_fill_msec = 123456
	app.state.tea_active = false


func _advance_practice(practice: Variant, frames: int) -> void:
	for _frame in range(frames):
		practice._process(FRAME_DELTA)


func _advance_practice_to_finish(practice: Variant) -> void:
	var guard := 0
	while practice.playing and guard < 240:
		practice._process(FRAME_DELTA)
		guard += 1
	check(not practice.playing and guard < 240, "the prepared formal practice completes on the synthetic 30 fps clock")


func _record_finished_action(action_id: int) -> void:
	finished_action_ids.append(action_id)


func _script_variable_snapshot(state: Object) -> Dictionary:
	var snapshot: Dictionary = {}
	for property_info in state.get_property_list():
		if (int(property_info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property_info.name)
		var value: Variant = state.get(name)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		snapshot[name] = value
	return snapshot


func _snapshot_without(snapshot: Dictionary, excluded: Array) -> Dictionary:
	var result := snapshot.duplicate(true)
	for key in excluded:
		result.erase(str(key))
	return result


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("FORMAL_SWORD_CYCLE_TESTS: %d checks, %d failures" % [checks, failures])
	quit(failures)
