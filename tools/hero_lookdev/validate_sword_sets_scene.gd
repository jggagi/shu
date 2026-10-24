extends SceneTree
## Focused runtime QA for the optional five-set sword-cycle catalog.

const SCENE_PATH := "res://scenes/demos/jiang_sword_cycle.tscn"
const EXPECTED_SET_IDS := ["songfeng", "chuanyun", "huilan", "tiaoyue", "xieying"]
const EXPECTED_ACTION_PAGES := 8
const IDLE_FRAME_COUNT := 60
const ACTION_FRAME_COUNT := 180
const CYCLE_FPS := 30.0
const ACTION_SECONDS := 6.0
const EXPECTED_ANCHOR := Vector2(245.22732544, 466.50038784)
const EXPECTED_ACTOR_SCALE := 0.62

var scene: Node
var output := ""
var qa_size := Vector2i(1152, 720)
var argument_error := ""
var report := {"checks": [], "captures": [], "failures": 0}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--qa-size="):
			var value := argument.trim_prefix("--qa-size=")
			if value == "1152x720":
				qa_size = Vector2i(1152, 720)
			elif value == "960x600":
				qa_size = Vector2i(960, 600)
			else:
				argument_error = "--qa-size must be 1152x720 or 960x600"
	call_deferred("run")


func snapshot(instance: Object) -> PackedByteArray:
	var values: Dictionary = {}
	for property: Dictionary in instance.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = instance.get(property.name)
	return var_to_bytes(values)


func environment_snapshot() -> PackedByteArray:
	return var_to_bytes({
		"presenter": snapshot(scene.environment_presenter),
		"profile_id": scene.environment_presenter.time_profile_id,
		"weather_id": scene.environment_presenter.weather_id,
		"presentation_time": scene.presentation_time,
	})


func button_states() -> Array:
	var states: Array = []
	for button in scene._set_buttons:
		states.append({"text": button.text, "pressed": button.button_pressed})
	return states


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	var item := {"ok": ok, "label": label}
	if not details.is_empty():
		item["details"] = details
	report.checks.append(item)
	if not ok:
		report.failures += 1
		push_error(label)


func capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var save_result := image.save_png(output.path_join(name))
	check(save_result == OK, "saved " + name)
	report.captures.append({
		"file": name,
		"size": [image.get_width(), image.get_height()],
		"selected_set_id": str(scene.qa_state().selected_set_id),
		"state": scene.qa_state(),
	})
	return image


func check_font_coverage(entries: Array) -> void:
	var font: Font = scene.theme.default_font
	var missing: Array[String] = []
	for entry_value: Variant in entries:
		var entry: Dictionary = entry_value
		for text_value in [str(entry.get("label", "")), str(entry.get("description", ""))]:
			var text_value_string := str(text_value)
			for char_index in text_value_string.length():
				var codepoint := text_value_string.unicode_at(char_index)
				if not font.has_char(codepoint):
					missing.append("%s U+%04X" % [text_value_string, codepoint])
		for phase_value: Variant in entry.get("phases", []):
			var phase: Dictionary = phase_value
			var phase_label := str(phase.get("label", ""))
			for char_index in phase_label.length():
				var codepoint := phase_label.unicode_at(char_index)
				if not font.has_char(codepoint):
					missing.append("%s U+%04X" % [phase_label, codepoint])
	check(missing.is_empty(), "active font covers every set label, description, and phase label", {"missing_codepoints": missing})


func second_strike_frame(entry: Dictionary) -> int:
	var phases: Array = entry.get("phases", [])
	var candidates: Array[int] = []
	for phase_index in phases.size():
		var phase: Dictionary = phases[phase_index]
		if str(phase.get("label", "")) != "出剑":
			continue
		var first_frame := int(phase.get("start_frame", 1)) - 1
		var last_frame := ACTION_FRAME_COUNT - 1
		if phase_index + 1 < phases.size():
			last_frame = int(phases[phase_index + 1].get("start_frame", ACTION_FRAME_COUNT + 1)) - 2
		if last_frame < 46:
			continue
		# With multiple strike intervals, sample the last one; for a single long interval,
		# sample its midpoint after the explicit frame-45 pose.
		var sample_frame := first_frame
		if sample_frame <= 45:
			sample_frame = maxi(46, int((maxi(first_frame, 46) + last_frame) / 2))
		if sample_frame <= last_frame and sample_frame >= 46:
			candidates.append(sample_frame)
	if candidates.is_empty():
		return -1
	return candidates.back()


func run() -> void:
	if not argument_error.is_empty():
		push_error(argument_error)
		quit(2)
		return
	if output.is_empty() or not output.is_absolute_path():
		push_error("Absolute --output directory required")
		quit(2)
		return
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
		push_error("--output must name a new directory; refusing to overwrite: " + output)
		quit(2)
		return
	var mkdir_result := DirAccess.make_dir_recursive_absolute(output)
	if mkdir_result != OK:
		push_error("Could not create --output directory: " + error_string(mkdir_result))
		quit(2)
		return

	root.size = qa_size
	var packed_scene: PackedScene = load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		check(false, "loads the sword-cycle review scene")
		write_report_and_quit()
		return
	scene = packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.reset_review()
	var initial_demo_state := snapshot(scene.state)

	var entries: Array = scene._set_catalog_entries
	var actual_ids: Array[String] = []
	for entry_value: Variant in entries:
		actual_ids.append(str(entry_value.get("id", "")))
	check(scene._sets_catalog_enabled and entries.size() == 5 and actual_ids == EXPECTED_SET_IDS,
		"catalog loads the five sword sets in the approved order", {"ids": actual_ids})
	var initial: Dictionary = scene.qa_state()
	check(initial.selected_set_index == 0 and initial.selected_set_id == "songfeng" and initial.set_count == 5,
		"initial selection is set zero: songfeng")
	check(initial.actor_state == "idle" and not initial.busy and initial.dynamic_enabled and is_equal_approx(initial.playback_speed, 1.0),
		"initial actor is neutral idle in normal Dynamic mode")
	check(initial.frame_index == 0 and initial.loaded_action_atlas_pages == EXPECTED_ACTION_PAGES,
		"initial action loads exactly eight atlas pages and idle starts at frame zero", {"state": initial})
	check(scene._idle_frames.size() == IDLE_FRAME_COUNT and scene._action_frames.size() == ACTION_FRAME_COUNT,
		"shared 60-frame idle and selected 180-frame action are loaded")
	check(is_equal_approx(scene.IDLE_SECONDS, 2.0) and is_equal_approx(scene.ACTION_SECONDS, ACTION_SECONDS),
		"clip durations remain two-second idle and six-second action")
	check(scene._resized_anchor.distance_to(EXPECTED_ANCHOR) < 0.001 and is_equal_approx(scene._cycle_actor.scale.x, EXPECTED_ACTOR_SCALE) and is_equal_approx(scene._cycle_actor.scale.y, EXPECTED_ACTOR_SCALE),
		"shared source anchor and actor scale 0.62 are preserved")
	check(scene._cycle_actor.get_child_count() == 1 and scene._cycle_actor.get_child(0) == scene._cycle_sprite,
		"actor still presents through one character Sprite2D")
	check_font_coverage(entries)

	for set_index in entries.size():
		scene.reset_review()
		var entry: Dictionary = entries[set_index]
		var before_environment := environment_snapshot()
		var before_demo_state := snapshot(scene.state)
		var before_clock: float = scene.presentation_time
		check(scene.select_set(set_index), "selects set %s while idle" % str(entry.id))
		var selected: Dictionary = scene.qa_state()
		check(selected.selected_set_index == set_index and selected.selected_set_id == str(entry.id),
			"selecting %s updates selected ID and index" % str(entry.id))
		check(scene._set_buttons[set_index].button_pressed and scene._set_buttons[set_index].text == str(entry.label),
			"selected button is pressed and displays %s" % str(entry.label))
		check(selected.actor_state == "idle" and selected.frame_index == 0 and not selected.busy,
			"selecting %s resets shared idle to neutral frame zero" % str(entry.id))
		check(selected.loaded_action_atlas_pages == EXPECTED_ACTION_PAGES,
			"selecting %s keeps only its eight active action atlas pages" % str(entry.id), {"pages": selected.loaded_action_atlas_pages})
		check(environment_snapshot() == before_environment and snapshot(scene.state) == before_demo_state and is_equal_approx(scene.presentation_time, before_clock),
			"selecting %s leaves environment transitions, world clock, and DemoState unchanged" % str(entry.id))
		await capture("%s-neutral.png" % str(entry.id))

		# Practice from a non-neutral idle frame verifies the short settle and busy guards.
		scene._process(20.0 / CYCLE_FPS)
		check(scene.practice(), "practice starts for %s" % str(entry.id))
		check(not scene.practice(), "repeated practice is ignored while %s settles" % str(entry.id))
		check(not scene.select_set(set_index) and not scene.select_set((set_index + 1) % entries.size()),
			"same-set and other-set selection are rejected while %s is busy" % str(entry.id))
		check(scene.qa_state().actor_state == "settle" and scene.qa_state().busy,
			"%s enters settle before action" % str(entry.id))
		scene._process(0.25)
		check(scene.qa_state().actor_state == "action" and scene.qa_state().frame_index == 0,
			"%s starts action at frame zero after neutral settle" % str(entry.id))
		scene._process(45.0 / CYCLE_FPS)
		var first_pose: Dictionary = scene.qa_state()
		check(first_pose.frame_index == 45 and first_pose.frame_count == ACTION_FRAME_COUNT,
			"%s reaches deterministic first cut at action frame 45" % str(entry.id), {"state": first_pose})
		await capture("%s-cut-1-frame-45.png" % str(entry.id))
		var second_cut := second_strike_frame(entry)
		check(second_cut > 45, "%s catalog provides a later 出剑 pose" % str(entry.id), {"frame_index": second_cut})
		if second_cut > 45:
			scene._process(float(second_cut - int(scene.qa_state().frame_index)) / CYCLE_FPS)
			var second_pose: Dictionary = scene.qa_state()
			check(second_pose.frame_index == second_cut and second_pose.phase == "出剑",
				"%s reaches its catalog-derived final 出剑 sample" % str(entry.id), {"state": second_pose})
			await capture("%s-cut-2-frame-%03d.png" % [str(entry.id), second_cut])
		var active: Dictionary = scene.qa_state()
		var cycle_before := int(active.cycle_count)
		scene._process(maxf(0.0, ACTION_SECONDS - float(active.action_time_seconds)))
		var returned: Dictionary = scene.qa_state()
		check(returned.actor_state == "idle" and returned.frame_index == 0 and not returned.busy and returned.cycle_count == cycle_before + 1,
			"%s returns to idle frame zero after one complete six-second action" % str(entry.id), {"state": returned})
		await capture("%s-returned-idle.png" % str(entry.id))

	# Invalid set indexes must not mutate the current neutral presentation.
	scene.reset_review()
	var invalid_before: Dictionary = scene.qa_state().duplicate(true)
	var invalid_environment := environment_snapshot()
	var invalid_demo_state := snapshot(scene.state)
	var invalid_buttons := button_states()
	check(not scene.select_set(-1) and not scene.select_set(5), "rejects set indexes -1 and 5")
	check(scene.qa_state() == invalid_before and environment_snapshot() == invalid_environment and snapshot(scene.state) == invalid_demo_state and button_states() == invalid_buttons,
		"invalid set indexes leave selection, actor, buttons, environment, and DemoState unchanged")

	# One Static freeze pair exercises the exact current frame and transition state.
	scene.reset_review()
	scene.set_time("you", true)
	scene.set_weather("light_rain", true)
	scene._process(20.0 / CYCLE_FPS)
	scene.practice()
	scene._process(0.25 + 1.0)
	check(scene.qa_state().actor_state == "action" and is_equal_approx(scene.qa_state().action_time_seconds, 1.0),
		"Static test begins one second into an action")
	scene.set_dynamic(false)
	var frozen_state: Dictionary = scene.qa_state().duplicate(true)
	var frozen_environment := environment_snapshot()
	check(not scene.practice(), "practice is disabled in Static")
	check(not scene.select_set(scene.qa_state().selected_set_index) and not scene.select_set(1), "same-set and other-set selection are disabled in Static")
	var static_a := await capture("songfeng-static-a.png")
	scene._process(0.7)
	var static_b := await capture("songfeng-static-b.png")
	check(static_a.get_data() == static_b.get_data(), "chosen Static image pair is byte-identical")
	check(scene.qa_state() == frozen_state and environment_snapshot() == frozen_environment,
		"Static preserves exact actor, world clock, and environment transition state")
	scene.set_dynamic(true)
	scene._process(0.25)
	check(is_equal_approx(scene.qa_state().action_time_seconds, 1.25) and is_equal_approx(scene.presentation_time, float(frozen_state.presentation_time) + 0.25),
		"Resume continues action and environment clocks from their frozen values")

	# World time runs at real delta while source animation runs at half speed.
	scene.reset_review()
	scene.set_speed(0.5)
	check(scene.practice(), "half-speed practice starts from neutral idle")
	var half_speed_start: Dictionary = scene.qa_state()
	var half_world_start := float(scene.presentation_time)
	scene._process(2.0)
	var half_mid: Dictionary = scene.qa_state()
	check(is_equal_approx(float(half_mid.action_time_seconds), 1.0) and half_mid.frame_index == 30 and is_equal_approx(float(half_mid.actor_clock) - float(half_speed_start.actor_clock), 1.0),
		"two world seconds advance source animation by one second at half speed", {"state": half_mid})
	check(is_equal_approx(float(scene.presentation_time) - half_world_start, 2.0),
		"presentation/world clock remains independent of actor playback speed")
	scene._process(10.0)
	var half_returned: Dictionary = scene.qa_state()
	check(half_returned.actor_state == "idle" and half_returned.frame_index == 0 and half_returned.cycle_count == 1 and is_equal_approx(float(scene.presentation_time) - half_world_start, 12.0),
		"half-speed action returns after its remaining ten world seconds")

	# Reset key behavior restores the approved defaults and preserves DemoState.
	check(scene.select_set(4), "selects a non-default set before reset")
	scene.set_time("you", true)
	scene.set_weather("light_rain", true)
	scene.set_speed(0.5)
	scene.set_dynamic(false)
	scene.reset_review()
	var reset_state: Dictionary = scene.qa_state()
	check(reset_state.selected_set_index == 0 and reset_state.selected_set_id == "songfeng" and reset_state.actor_state == "idle" and reset_state.frame_index == 0 and reset_state.cycle_count == 0,
		"R reset returns to set zero and neutral idle")
	check(reset_state.dynamic_enabled and is_equal_approx(reset_state.playback_speed, 1.0) and reset_state.time_profile_id == "wu" and reset_state.weather_id == "clear" and is_zero_approx(scene.presentation_time),
		"R reset restores normal Dynamic, noon, clear weather, and presentation clock zero")
	check(snapshot(scene.state) == initial_demo_state and reset_state.state_unchanged,
		"all DemoState script variables remain unchanged throughout QA")

	write_report_and_quit()


func write_report_and_quit() -> void:
	report["qa_size"] = "%dx%d" % [qa_size.x, qa_size.y]
	report["status"] = "PASS" if int(report.failures) == 0 else "FAIL"
	var file := FileAccess.open(output.path_join("scene-verification.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write scene-verification.json")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("JIANG_SWORD_SETS_SCENE: %d checks, %d captures, %d failures at %s" % [report.checks.size(), report.captures.size(), report.failures, report.qa_size])
	quit(0 if int(report.failures) == 0 else 1)
