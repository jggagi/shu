extends "res://tests/cultivation_engine_ambush_render.gd"
## Real native Compatibility input and packed-game lighting comparisons.
## Pixel differences establish an effect, never aesthetic approval or Web QA.

var _world_captures: Array[Dictionary] = []
var _lighting_states: Array[Dictionary] = []
var _pixel_comparison: Dictionary = {}
var _busy_rejections: Array[Dictionary] = []


func _run() -> void:
	output = "res://.local/qa/songfeng-lighting/render"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output = argument.trim_prefix("--output-dir=")
		elif argument.begins_with("--qa-size="):
			var dimensions := argument.trim_prefix("--qa-size=").split("x")
			qa_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	root.mode = Window.MODE_WINDOWED
	root.size = qa_size
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_check(DisplayServer.get_name() != "headless", "Lighting review uses an actual rendered window")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	app = Entry.instantiate() as Control
	app.set("save_base_dir", ProjectSettings.globalize_path(output.path_join("qa-checkpoints-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])))
	root.add_child(app)
	for frame: int in range(90):
		await process_frame
		if is_instance_valid(_view()):
			break
	_check(is_instance_valid(_view()), "The real two-versus-three encounter opens")
	if not is_instance_valid(_view()):
		_finish()
		return
	await _idle()
	_check_layout()
	var stage: Control = _view().get("_stage")
	_check(stage.has_method("set_enhanced_lighting") and stage.has_method("lighting_audit"), "The real stage exposes the lighting contract")
	if not stage.has_method("lighting_audit"):
		_finish()
		return
	_check_profile(true)
	_lighting_states.append(stage.call("lighting_audit"))
	await _capture("00-enhanced-arrival.png")
	# Freeze scenery through the shipped UI. Pause only actor presentation clocks
	# in this comparison fixture so idle breathing cannot masquerade as lighting.
	await _click("EnvironmentMotionButton")
	_check(bool(stage.get("_landscape").call("audit").static), "The shipped scenery button freezes environmental motion")
	_set_actor_processing(false)
	# The objective warning ring has its own real-time pulse in Stage._process.
	# Suspend that presentation callback as well during exact pixel comparisons.
	stage.set_process(false)
	var initial_nodes: int = _node_count(stage.get("world_root"))
	var comparison_state: Dictionary = _authoritative_context()
	var enhanced: Image = await _world_image(stage)
	await _save_world(enhanced, "world-enhanced.png")
	var enhanced_repeat: Image = await _world_image(stage)
	_check(enhanced.get_data() == enhanced_repeat.get_data(), "Frozen same-mode enhanced SubViewport pixels remain exactly stable")
	await _capture("01-enhanced-frozen.png")
	await _lighting_click()
	_check_profile(false)
	var original: Image = await _world_image(stage)
	await _save_world(original, "world-original.png")
	var original_repeat: Image = await _world_image(stage)
	_check(original.get_data() == original_repeat.get_data(), "Frozen same-mode original SubViewport pixels remain exactly stable")
	_pixel_comparison = _compare_images(enhanced, original)
	_check(float(_pixel_comparison.get("mean_rgb_difference_0_to_1", 0.0)) > 0.001 and float(_pixel_comparison.get("changed_pixel_fraction", 0.0)) > 0.01, "Enhanced and original lighting change actual rendered scene pixels")
	await _capture("02-original-frozen.png")
	for cycle: int in range(2):
		await _lighting_click()
		var restored_enhanced: Image = await _world_image(stage)
		_check(restored_enhanced.get_data() == enhanced.get_data(), "A/B cycle %d exactly restores enhanced pixels" % cycle)
		await _lighting_click()
		var restored_original: Image = await _world_image(stage)
		_check(restored_original.get_data() == original.get_data(), "A/B cycle %d exactly restores original pixels" % cycle)
	_check(_node_count(stage.get("world_root")) == initial_nodes, "Repeated lighting changes create no accumulated world nodes")
	_check(_authoritative_context() == comparison_state, "Lighting comparisons preserve exact host, battle, selection, action and current preview state")
	var lighting_before: Dictionary = stage.call("lighting_audit")
	stage.call("reset_environment")
	_check(stage.call("lighting_audit") == lighting_before, "Resetting scenery preserves the current lighting profile")
	_check(is_zero_approx(float(stage.get("_landscape").call("audit").elapsed)), "Scenery reset still resets only its own clock")
	# A lighting toggle itself must not manufacture environment time, even when
	# scenery is dynamic. Suspend its owner briefly to make this exact.
	await _click("EnvironmentMotionButton")
	_check(stage.call("lighting_audit") == lighting_before, "The scenery motion button cannot change lighting")
	stage.set_process(false)
	var controlled_elapsed: float = float(stage.get("_landscape").call("audit").elapsed)
	await _lighting_click()
	_check(is_equal_approx(float(stage.get("_landscape").call("audit").elapsed), controlled_elapsed), "The lighting callback does not step or reset environment time")
	_check(not bool(stage.get("_landscape").call("audit").static), "Changing lighting does not freeze dynamic scenery")
	stage.set_process(true)
	await create_timer(0.20).timeout
	_check(float(stage.get("_landscape").call("audit").elapsed) > controlled_elapsed, "Scenery continues advancing normally after a lighting change")
	_set_actor_processing(true)
	# Resolve a complete real knockback under the original profile.
	await _lighting_click()
	_check_profile(false)
	await _click("Skill_push")
	await _hover_tile([4, 3])
	_check(not (_view().audit_snapshot().preview as Dictionary).is_empty(), "Original lighting retains the actual targeted skill preview")
	_check_threats(stage)
	await _capture("03-original-push-preview.png")
	await _tile([4, 3])
	_check(_unit("brute").pos == [5, 3] and int(_unit("brute").hp) == 9 and int(_barricade("north_gate").hp) == 0, "Original lighting preserves real barricade-collision knockback and exact damage")
	await _capture("04-original-push-result.png")
	# Start and finish a real pointing interrupt in enhanced mode. Temporary
	# skill lighting owns its baseline while busy, so profile changes are rejected.
	await _lighting_click()
	_check_profile(true)
	await _click("Unit_tinglan")
	await _click("Skill_interrupt")
	await _hover_tile([5, 4])
	_check(not (_view().audit_snapshot().preview as Dictionary).is_empty(), "Enhanced lighting retains the actual interrupt preview")
	_check_threats(stage)
	await _capture("05-enhanced-interrupt-preview.png")
	var interrupt_profile_before: Dictionary = stage.call("lighting_audit")
	await _mouse(_view().audit_tile_center([5, 4]), true)
	_check(bool(_view().audit_snapshot().busy), "The real interrupt enters its busy attack presentation")
	await _lighting_click()
	await _lighting_click()
	_check(_busy_rejections.size() >= 2, "The real lighting button rejects both attempted changes during ongoing combat presentation")
	await _idle()
	_check_profile(true)
	_check(stage.call("lighting_audit") == interrupt_profile_before, "Rejected busy changes leave the exact enhanced profile restored after combat lighting recovers")
	_check(bool(_plan("blade").get("interrupted", false)) and int(_unit("blade").hp) == 8, "Enhanced lighting preserves the real interrupt and exact damage")
	_check_threats(stage)
	await _capture("06-enhanced-interrupt-result.png")
	var old_viewport: WeakRef = weakref(stage.get("viewport"))
	var old_world: WeakRef = weakref(stage.get("world_root"))
	var sequence_before: int = int(app.get("_session").snapshot().sequence)
	# Leave original selected so restart's enhanced default is not accidental.
	await _lighting_click()
	_check_profile(false)
	await _click("RestartButton")
	_check(old_viewport.get_ref() == null and old_world.get_ref() == null, "Restart releases the previous lighting world and viewport")
	_check_profile(true)
	_check(int(app.get("_session").snapshot().sequence) == sequence_before + 1, "Restart retains its single original abandoned-attempt settlement")
	stage = _view().get("_stage")
	_lighting_states.append(stage.call("lighting_audit"))
	_check_layout()
	await _capture("07-enhanced-restart-default.png")
	old_viewport = weakref(stage.get("viewport"))
	old_world = weakref(stage.get("world_root"))
	await _click("ReturnButton")
	_check(not is_instance_valid(_view()) and old_viewport.get_ref() == null and old_world.get_ref() == null, "Returning to town releases lighting nodes and their render viewport")
	_check(app.get("_session").snapshot().scene == "shanxia_town" and app.get("_session").snapshot().phase == "result", "Lighting keeps the original town-return result")
	await _capture("08-lighting-return.png")
	_finish()


func _lighting_click() -> void:
	var button := _view().ui_control("LightingModeButton") as Button
	if bool(_view().audit_snapshot().busy):
		await _reject_busy_lighting_click(button)
		return
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "The actual lighting button is visible and usable")
	if button == null or button.disabled:
		return
	_check(button.focus_mode == Control.FOCUS_NONE, "Lighting comparison cannot capture the battle's Space shortcut focus")
	var position: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	# Moving off the board legitimately clears hover; compare the callback from
	# this settled pointer state rather than blaming it for mouse-exit behavior.
	await _mouse(position, false)
	var before: Dictionary = _authoritative_context()
	var stage: Control = _view().get("_stage")
	var enhanced_before: bool = bool(stage.call("lighting_audit").enhanced)
	var actual: Vector2 = root.get_final_transform() * position
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = actual
		event.global_position = actual
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	var current: Dictionary = stage.call("lighting_audit")
	_check(bool(current.enhanced) != enhanced_before, "A real mouse click switches the current stage lighting mode")
	_check(_authoritative_context() == before, "Lighting callback retains exact authoritative and tactical selection/preview state")
	_check(button.text == ("光影：增强" if bool(current.enhanced) else "光影：原版"), "The shipped lighting label matches the current profile")
	_lighting_states.append(current)


func _reject_busy_lighting_click(button: Button) -> void:
	_check(button != null and button.is_visible_in_tree() and button.disabled, "The actual lighting control is disabled while combat presentation owns its baseline")
	if button == null:
		return
	var stage: Control = _view().get("_stage")
	var before: Dictionary = _authoritative_context()
	var view_mode: bool = bool(_view().get("_enhanced_lighting"))
	var stage_mode: bool = bool(stage.get("_enhanced_lighting"))
	var cached_profiles: Dictionary = (stage.get("_lighting_profiles") as Dictionary).duplicate(true)
	var point: Vector2 = root.get_final_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
	await process_frame
	_check(_authoritative_context() == before, "Rejected busy lighting input preserves exact host, battle and tactical context")
	_check(bool(_view().get("_enhanced_lighting")) == view_mode and bool(stage.get("_enhanced_lighting")) == stage_mode and stage.get("_lighting_profiles") == cached_profiles, "Rejected busy lighting input preserves the logical profile and cached profile definitions")
	_busy_rejections.append({"before": view_mode, "after": _view().get("_enhanced_lighting"), "accepted": false, "phase": stage.call("audit").presentation_phase})


func _authoritative_context() -> Dictionary:
	var audit: Dictionary = _view().audit_snapshot()
	return {"host": app.get("_session").snapshot().duplicate(true), "battle": _battle().duplicate(true), "selected": audit.selected, "action": audit.action, "preview": (audit.preview as Dictionary).duplicate(true)}


func _check_profile(enhanced: bool) -> void:
	var audit: Dictionary = _view().get("_stage").call("lighting_audit")
	_check(bool(audit.get("enhanced", not enhanced)) == enhanced and not str(audit.get("profile", "")).is_empty(), "The current lighting profile reports its actual mode")
	_check(audit.has("ssao") and not bool(audit.ssao.get("enabled", true)), "Both shipped profiles keep experimental SSAO disabled after visual artifact review")
	_check(bool(audit.get("fill", {}).get("enabled", false)) == enhanced, "The supplementary fill follows the selected lighting mode")
	_check(audit.has("sun") and audit.has("ambient"), "Sun and ambient parameters are available for review")


func _set_actor_processing(enabled: bool) -> void:
	for actor: Node3D in _view().get("_stage").get("actor_nodes").values():
		actor.set_process(enabled)


func _world_image(stage: Control) -> Image:
	for frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var viewport: SubViewport = stage.get("viewport")
	var captured: Image = viewport.get_texture().get_image()
	captured.convert(Image.FORMAT_RGBA8)
	return captured


func _save_world(captured: Image, filename: String) -> void:
	var path: String = ProjectSettings.globalize_path(output.path_join(filename))
	_check(captured.save_png(path) == OK, "Actual SubViewport comparison captured: " + filename)
	_world_captures.append({"file": path, "size": [captured.get_width(), captured.get_height()], "sha256": FileAccess.get_sha256(path)})


func _compare_images(first: Image, second: Image) -> Dictionary:
	if first.get_size() != second.get_size():
		return {"error": "Lighting viewport dimensions changed"}
	var a: PackedByteArray = first.get_data()
	var b: PackedByteArray = second.get_data()
	var total := 0
	var changed := 0
	var any_changed := 0
	var maximum := 0
	var pixels: int = first.get_width() * first.get_height()
	for index: int in range(0, a.size(), 4):
		var difference: int = absi(int(a[index]) - int(b[index])) + absi(int(a[index + 1]) - int(b[index + 1])) + absi(int(a[index + 2]) - int(b[index + 2]))
		total += difference
		maximum = maxi(maximum, difference)
		if difference > 3:
			changed += 1
		if difference > 0:
			any_changed += 1
	return {"pixels": pixels, "changed_pixels": changed, "changed_pixel_fraction": float(changed) / float(pixels), "changed_pixel_any_fraction": float(any_changed) / float(pixels), "mean_rgb_difference_0_to_1": float(total) / float(pixels * 3 * 255), "max_rgb_sum_difference": maximum, "meaning": "Only proves visible numerical change; no aesthetic quality claim"}


func _check_threats(stage: Control) -> void:
	var expected: Array = []
	for plan: Dictionary in _battle().plans:
		if bool(plan.interrupted) or int(_unit(str(plan.unit_id)).hp) <= 0:
			continue
		for tile: Array in plan.cells:
			if not expected.has(tile):
				expected.append(tile)
	var actual: Array = stage.call("audit").danger_cells
	_check(actual.size() == expected.size() and expected.all(func(tile: Array) -> bool: return actual.has(tile)), "Lighting retains the exact real enemy-threat cells")
	var visible := 0
	for tile: Array in actual:
		var fill: MeshInstance3D = stage.get("_tile_meshes").get(stage.call("_key", tile))
		if fill != null and fill.is_visible_in_tree():
			visible += 1
	_check(visible == actual.size(), "Every real threat overlay remains visible under the selected lighting")


func _node_count(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _node_count(child)
	return count


func _finish() -> void:
	var report := {"test": "mountain_ambush_lighting_ui", "checks": checks, "failures": failures, "captures": captures, "world_captures": _world_captures, "pixel_comparison": _pixel_comparison, "ssao": "Disabled in both shipped profiles; experimental SSAO produced distant-mountain artifacts and is not delivered", "lighting_states": _lighting_states, "busy_lighting_rejections": _busy_rejections, "window": [qa_size.x, qa_size.y], "display_server": DisplayServer.get_name(), "input": "Actual Godot root.push_input events; not physical input or browser", "visual_acceptance": "Pixel comparison proves change, not user aesthetic approval", "result": "PASS" if failures.is_empty() else "FAIL"}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("AMBUSH LIGHTING: %d checks, %d failures, %d UI captures, %d world captures" % [checks, failures.size(), captures.size(), _world_captures.size()])
	quit(0 if failures.is_empty() else 1)
