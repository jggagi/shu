extends SceneTree

const SCENE_PATH := "res://scenes/demos/back_mountain_training.tscn"
const STATE_FIELDS := [
	"day", "time_index", "energy", "cultivation", "understanding", "lesson_bonus",
	"dialogue_open", "tea_accepted", "tea_seen", "tea_stage_complete", "tea_quest_complete",
	"tea_action_done", "tea_active"
]

var failures := 0
var checks: Dictionary = {}
var game: Control

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	check(packed != null, "standalone back mountain training scene loads")
	if packed == null:
		_finish()
		return

	game = packed.instantiate()
	root.add_child(game)
	await process_frame
	check(game.state != null, "scene owns its DemoState instance")
	check(game.config is Dictionary and game.config.has("training_seconds"), "scene exposes mutable training timing config")
	if game.state == null or not (game.config is Dictionary) or not game.config.has("training_seconds"):
		_finish()
		return
	# Keep the original tint checks below pinned to the v0 presentation path.
	game.set_lighting(false)

	game.config.training_seconds = 0.05
	game.qa_motion_paused = true
	var expected = game.state.get_script().new()
	check(_state_snapshot(game.state) == _state_snapshot(expected), "initial state matches a fresh DemoState")
	check(game.state.time_text() == expected.time_text(), "initial day and time come from DemoState rules")

	# Exercise the real DemoState rule table as the oracle. The test does not
	# restate energy, progress, or time increments as a second set of constants.
	var expected_train: Dictionary = expected.train()
	var start_clock: String = game.state.time_text()
	var start_day: int = game.state.day
	var start_time_index: int = game.state.time_index
	game.set_dynamic(true)
	var request: Dictionary = game.request_training()
	check(bool(request.get("ok", false)), "training request is accepted while idle")
	check(game.busy, "accepted training enters busy synchronously")
	var after_train_request := _state_snapshot(game.state)
	var duplicate: Dictionary = game.request_training()
	check(not bool(duplicate.get("ok", false)), "a second request is rejected while busy")
	check(not game.reset_demo(), "reset is rejected while busy")
	check(_state_snapshot(game.state) == after_train_request, "busy rejection and blocked reset do not settle again")
	check(game.state.time_text() != start_clock or game.state.day != start_day or game.state.time_index != start_time_index, "training advances the rules-based cultivation clock")
	check(_state_snapshot(game.state) == _state_snapshot(expected), "training state matches fresh DemoState.train()")

	# Toggling presentation during an action must leave both the settled result
	# and the in-flight action untouched.
	var settled_snapshot := _state_snapshot(game.state)
	var elapsed_before_toggle: float = game.training_elapsed
	game.set_dynamic(false)
	check(not game.dynamic_enabled and game.busy, "static mode can be selected during training")
	check(is_equal_approx(game.training_elapsed, elapsed_before_toggle), "static toggle does not restart elapsed training")
	check(_state_snapshot(game.state) == settled_snapshot, "switching to static mode does not mutate cultivation state")
	game.set_dynamic(true)
	check(game.dynamic_enabled and game.busy, "dynamic mode resumes without restarting training")
	check(is_equal_approx(game.training_elapsed, elapsed_before_toggle), "dynamic toggle does not restart elapsed training")
	check(_state_snapshot(game.state) == settled_snapshot, "switching back to dynamic mode does not settle training twice")
	await _wait_until_idle()
	check(not game.busy, "training completes asynchronously")
	check(bool(game.last_result.get("ok", false)), "last_result records the successful action")
	check(int(game.last_result.get("gain", -1)) == int(expected_train.get("gain", -2)), "last_result reports the rule-derived gain")
	check(int(game.last_result.get("energy_cost", -1)) == int(expected.rules.training_cost), "last_result reports the rule-derived energy cost")
	check(is_equal_approx(float(game.last_result.get("duration", -1.0)), float(expected.rules.training_duration)), "last_result reports the rule-derived game duration")
	check(game.training_elapsed >= elapsed_before_toggle, "presentation toggles do not restart elapsed training time")

	# Static presentation must not disable the gameplay request or its environment
	# refresh path.
	var expected_static = _fresh_matching(game.state)
	var expected_static_result: Dictionary = expected_static.train()
	var expected_static_time := str(expected_static.rules.times[expected_static.time_index])
	var expected_static_tint := Color(str(game.config.get("time_tints", {}).get(expected_static_time, "#f4f0e5")))
	game.set_dynamic(false)
	var before_static_train := _state_snapshot(game.state)
	var before_static_clock: String = game.state.time_text()
	var static_request: Dictionary = game.request_training()
	check(bool(static_request.get("ok", false)) and game.busy, "training remains available in static mode")
	check(_state_snapshot(game.state) != before_static_train, "static-mode training settles the DemoState")
	check(_state_snapshot(game.state) == _state_snapshot(expected_static), "static-mode result follows DemoState.train() rules")
	check(game.state.time_text() != before_static_clock, "static-mode training advances the rules-based day/time")
	var static_settled := _state_snapshot(game.state)
	game.refresh_environment()
	check(not game.dynamic_enabled and _state_snapshot(game.state) == static_settled, "environment refresh works in static mode without enabling animation or changing state")
	await _wait_until_idle()
	check(bool(game.last_result.get("ok", false)), "static-mode action completes and records feedback")
	check(int(game.last_result.get("gain", -1)) == int(expected_static_result.get("gain", -2)), "static-mode feedback uses the rule-derived gain")
	check(game._date_label.text == game.state.time_text(), "static-mode training refreshes the displayed cultivation clock")
	check(game._displayed_tint == expected_static_tint, "static-mode training refreshes the time-based environment tint")

	# Failed low-energy action: preserve every gameplay field exposed by the
	# current DemoState and leave the presentation clock alone.
	var session_before_reset: int = game.state.tea_session
	check(game.reset_demo(), "idle reset succeeds")
	var reset_reference = game.state.get_script().new()
	check(_state_snapshot(game.state) == _state_snapshot(reset_reference), "reset restores the fresh DemoState values")
	check(game.state.tea_session > session_before_reset, "reset advances the DemoState tea session to invalidate stale context")
	check(not game.state.tea_active and not game.state.tea_accepted and game.state.tea_seen.is_empty() and game.state.tea_action_done.is_empty(), "reset clears all tea phase flags")
	check(game._date_label.text == game.state.time_text(), "reset refreshes the visible day/time UI")
	game.state.energy = int(game.state.rules.training_cost) - 1
	game.state.cultivation = int(game.state.rules.training_gain) + 3
	game.state.understanding = 2
	game.state.lesson_bonus = 4
	game.state.day = 3
	game.state.time_index = 1
	var low_energy_snapshot := _state_snapshot(game.state)
	var session_before_failure: int = game.state.tea_session
	var presentation_before_failure: float = game.presentation_time
	var rejected: Dictionary = game.request_training()
	check(not bool(rejected.get("ok", false)), "low-energy training is rejected")
	check(not game.busy, "failed low-energy action does not become busy")
	check(_state_snapshot(game.state) == low_energy_snapshot, "low-energy failure is atomic across all DemoState fields")
	check(game.state.tea_session == session_before_failure, "failed training does not invalidate unrelated DemoState session context")
	check(is_equal_approx(game.presentation_time, presentation_before_failure), "failed training does not advance presentation time")
	check(game.reset_demo(), "reset succeeds after a rejected action")
	check(_state_snapshot(game.state) == _state_snapshot(reset_reference), "reset clears the full cultivation phase")
	check(not game.state.tea_active and not game.state.tea_accepted and game.state.tea_seen.is_empty() and game.state.tea_action_done.is_empty(), "second reset clears all phase flags")

	# Presentation toggles are independent of idle numeric state and do not
	# advance/restart the QA clock.
	var idle_snapshot := _state_snapshot(game.state)
	game.seek_presentation(6.25)
	var held_presentation: float = game.presentation_time
	game.set_dynamic(true)
	game.set_dynamic(false)
	game.refresh_environment()
	check(_state_snapshot(game.state) == idle_snapshot, "idle dynamic/static toggles preserve numeric cultivation state")
	check(is_equal_approx(game.presentation_time, held_presentation), "QA presentation seek remains stable while motion is paused")
	check(not game.dynamic_enabled, "static mode remains selected after refresh")
	game.set_dynamic(true)
	var gust: Dictionary = game._gust_schedule[0]
	var later_gust: float = float(gust.start) + float(gust.duration) * 0.5 + game._gust_cycle_seconds * 10.0
	game.seek_presentation(later_gust)
	check(not game._active_gust(later_gust).is_empty(), "gusts remain available after ten presentation cycles")
	var blink: Dictionary = game._blink_schedule[0]
	check(game._is_blinking(float(blink.start) + float(blink.duration) * 0.5 + game._blink_cycle_seconds * 10.0), "blinks remain available after ten presentation cycles")
	check(_state_snapshot(game.state) == idle_snapshot, "extended presentation leaves gameplay state unchanged")

	# Lighting is presentation-only. Exercise every real rules time as a profile
	# lookup while preserving the complete state, displayed clock, and QA clock.
	var lighting = game.lighting
	check(lighting != null, "scene exposes its Lighting v1 helper")
	check(game.lighting_button is Button, "Lighting v1 has a visible button control")
	if lighting == null or not (game.lighting_button is Button):
		_finish()
		return

	var state_before_lighting := _full_state_snapshot()
	var presentation_before_lighting: float = game.presentation_time
	game.set_lighting(true)
	check(game.lighting_enabled, "lighting can be enabled independently of dynamic presentation")
	check(_full_state_snapshot() == state_before_lighting, "enabling lighting preserves every DemoState field and clock")
	check(is_equal_approx(game.presentation_time, presentation_before_lighting), "enabling lighting preserves the QA presentation clock")
	var enabled_profile: Dictionary = lighting.current_profile.duplicate(true)
	var enabled_target_index: int = lighting.target_time_index
	var enabled_profile_index: int = lighting.profile_index
	game.set_lighting(false)
	check(not game.lighting_enabled, "lighting can be disabled without changing dynamic presentation")
	check(_full_state_snapshot() == state_before_lighting, "disabling lighting preserves every DemoState field and clock")
	game.set_lighting(true)
	check(lighting.current_profile == enabled_profile, "lighting OFF then ON restores the exact settled profile")
	check(lighting.target_time_index == enabled_target_index and lighting.profile_index == enabled_profile_index, "lighting round trip restores the exact target and profile indices")
	check(_full_state_snapshot() == state_before_lighting, "lighting round trip preserves every DemoState field and clock")
	check(is_equal_approx(game.presentation_time, presentation_before_lighting), "lighting round trip preserves the QA presentation clock")

	# All four presentation combinations remain independent and do not alter the
	# rule state or either clock.
	for dynamic_mode in [false, true]:
		for lighting_mode in [false, true]:
			game.set_dynamic(dynamic_mode)
			game.set_lighting(lighting_mode)
			check(game.dynamic_enabled == dynamic_mode and game.lighting_enabled == lighting_mode, "dynamic/lighting combination %s/%s is selectable" % [dynamic_mode, lighting_mode])
			check(_full_state_snapshot() == state_before_lighting, "dynamic/lighting combination %s/%s preserves full state" % [dynamic_mode, lighting_mode])
			check(is_equal_approx(game.presentation_time, presentation_before_lighting), "dynamic/lighting combination %s/%s preserves presentation time" % [dynamic_mode, lighting_mode])
	game.set_dynamic(false)
	game.set_lighting(true)

	# Profiles are keyed by the active DemoState rule labels, not by copied or
	# hard-coded gameplay time rules.
	var saved_time_index: int = game.state.time_index
	var rule_times: Array = game.state.rules.times
	check(lighting.profiles.size() == rule_times.size(), "Lighting v1 defines one profile for each DemoState rules time")
	for time_index in range(rule_times.size()):
		game.state.time_index = time_index
		game.refresh_environment(false)
		var time_name := str(rule_times[time_index])
		check(lighting.profiles.has(time_name), "Lighting v1 maps the rules time %s" % time_name)
		check(lighting.target_time_index == time_index, "Lighting v1 target index follows rules time %s" % time_name)
		check(lighting.profile_index == time_index, "Lighting v1 settles on rules profile %s" % time_name)
		check(lighting.current_profile == lighting.profiles[time_name], "Lighting v1 current profile matches %s" % time_name)
	game.state.time_index = saved_time_index
	game.refresh_environment(false)
	lighting.finish_transition()

	# During an action the lighting toggle must not settle gameplay, restart the
	# action, or reset its elapsed timer. After completion, the profile transition
	# is allowed to progress while QA motion remains paused.
	game.set_dynamic(true)
	game.config.training_seconds = 0.8
	var busy_request: Dictionary = game.request_training()
	check(bool(busy_request.get("ok", false)) and game.busy, "lighting busy-path fixture starts a real training action")
	var busy_snapshot := _full_state_snapshot()
	var busy_elapsed: float = game.training_elapsed
	var busy_presentation: float = game.presentation_time
	game.set_lighting(false)
	game.set_lighting(true)
	game.set_lighting(false)
	game.set_lighting(true)
	check(game.busy, "lighting toggles do not finish an in-flight training action")
	check(is_equal_approx(game.training_elapsed, busy_elapsed), "lighting toggles do not restart or advance elapsed training")
	check(_full_state_snapshot() == busy_snapshot, "lighting toggles during training preserve settled state and clock")
	check(is_equal_approx(game.presentation_time, busy_presentation), "lighting toggles during training preserve presentation time")
	await _wait_until_idle()
	var finish_deadline := Time.get_ticks_msec() + 1600
	var finish_time_name := str(rule_times[game.state.time_index])
	var finish_profile: Dictionary = lighting.profiles[finish_time_name]
	while lighting.current_profile != finish_profile and Time.get_ticks_msec() < finish_deadline:
		await process_frame
	check(lighting.target_time_index == game.state.time_index, "training finish targets the newly settled DemoState time")
	check(lighting.profile_index == game.state.time_index, "training finish profile transition settles while QA motion is paused")
	check(lighting.current_profile == finish_profile, "training finish uses the exact profile for its new rules time")

	# Verify the native 2D rendering boundary and a hard occluder-count budget.
	check(game._world_canvas is CanvasLayer and game._world_canvas.layer == 1, "Lighting v1 owns the dedicated world canvas layer")
	check(lighting.sun is DirectionalLight2D, "Lighting v1 uses one native DirectionalLight2D")
	if lighting.sun is DirectionalLight2D and game._world_canvas is CanvasLayer:
		check(lighting.sun.get_canvas() == game._world_canvas.get_canvas(), "native sun is attached to the world canvas")
		check(game._date_label.get_canvas() != game._world_canvas.get_canvas(), "HUD labels remain on a separate UI canvas")
	var far_art := game._far_layer.get_node_or_null("FarArtwork") as TextureRect
	var mid_art := game._mid_layer.get_node_or_null("MiddleArtwork") as TextureRect
	check(far_art != null and far_art.material is CanvasItemMaterial and far_art.material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, "far mountain artwork stays unshaded")
	check(mid_art != null and mid_art.material is CanvasItemMaterial and mid_art.material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, "middle mountain artwork stays unshaded")
	check(lighting.occluders is Array and lighting.occluders.size() <= 2, "native lighting uses no more than two occluders")
	if lighting.occluders is Array:
		for occluder in lighting.occluders:
			check(occluder is LightOccluder2D, "lighting occluder is a native LightOccluder2D")
			if occluder is LightOccluder2D and lighting.sun is DirectionalLight2D:
				check((occluder.occluder_light_mask & lighting.sun.shadow_item_cull_mask) != 0, "occluder shadow mask intersects the native sun")

	# The helper's cloud clock follows motion availability, while time-profile
	# changes above remain independent of the paused QA motion clock.
	game.set_dynamic(false)
	var frozen_cloud_time: float = lighting.cloud_time
	for _frame in 4:
		await process_frame
	check(is_equal_approx(lighting.cloud_time, frozen_cloud_time), "static presentation freezes the cloud clock")
	game.set_dynamic(true)
	game.set_lighting(false)
	var cloud_time_while_off: float = lighting.cloud_time
	for _frame in 4:
		await process_frame
	check(is_equal_approx(lighting.cloud_time, cloud_time_while_off), "lighting OFF keeps cloud enhancements disabled")

	# Reset restores both the DemoState dawn and its matching settled profile.
	game.config.training_seconds = 0.05
	check(game.reset_demo(), "lighting checks leave an idle scene that can reset")
	check(not game.lighting_enabled, "reset does not silently enable Lighting v1")
	lighting.finish_transition()
	check(lighting.target_time_index == game.state.time_index and lighting.profile_index == game.state.time_index, "reset snaps Lighting v1 to the fresh DemoState dawn")
	game.set_lighting(true)
	check(lighting.current_profile == lighting.profiles[str(rule_times[game.state.time_index])], "reset dawn profile matches the active DemoState rules")

	# Clouds v1 is a presentation-only system with bounded numeric tuning.
	var cloud_config: Dictionary = game.config.get("clouds", {})
	check(not cloud_config.is_empty(), "cloud configuration is exposed in the scene data")
	var far_speed := float(cloud_config.get("far_speed", NAN))
	var valley_speed := float(cloud_config.get("valley_speed", NAN))
	var far_alpha := float(cloud_config.get("far_alpha", NAN))
	var valley_alpha := float(cloud_config.get("valley_alpha", NAN))
	var cloud_distortion := float(cloud_config.get("distortion", NAN))
	var density_cycle := float(cloud_config.get("density_cycle_seconds", NAN))
	check(not is_nan(far_speed) and not is_inf(far_speed) and far_speed > 0.0, "far cloud speed is finite and positive")
	check(not is_nan(valley_speed) and not is_inf(valley_speed) and valley_speed > 0.0 and far_speed > valley_speed, "far clouds move faster than positive-speed valley clouds")
	check(not is_nan(far_alpha) and not is_inf(far_alpha) and far_alpha >= 0.0 and far_alpha <= 1.0, "far cloud alpha is finite and within 0..1")
	check(not is_nan(valley_alpha) and not is_inf(valley_alpha) and valley_alpha >= 0.0 and valley_alpha <= 1.0, "valley cloud alpha is finite and within 0..1")
	check(not is_nan(cloud_distortion) and not is_inf(cloud_distortion) and cloud_distortion >= 0.0 and cloud_distortion <= 0.006, "cloud distortion is finite and within 0..0.006")
	check(not is_nan(density_cycle) and not is_inf(density_cycle) and density_cycle >= 15.0 and density_cycle <= 30.0, "cloud density cycle is finite and within 15..30 seconds")

	var cloud_materials: Array = game._cloud_materials
	check(cloud_materials.size() == 3, "Clouds v1 exposes three independent shader layers")
	var far_cloud = game._far_layer.get_node_or_null("FarCloud")
	var valley_behind = game._far_layer.get_node_or_null("ValleyCloudBehindPeaks")
	var valley_across = game._mid_layer.get_node_or_null("ValleyCloudAcrossWaists")
	var cloud_far_art = game._far_layer.get_node_or_null("FarArtwork")
	var cloud_mid_art = game._mid_layer.get_node_or_null("MiddleArtwork")
	check(far_cloud != null and valley_behind != null and valley_across != null, "cloud layer nodes exist at their assigned mountain depths")
	if far_cloud != null and valley_behind != null and valley_across != null and cloud_far_art != null and cloud_mid_art != null and cloud_materials.size() == 3:
		check(cloud_far_art.get_parent() == game._far_layer and cloud_far_art.get_index() < far_cloud.get_index(), "FarCloud follows FarArtwork on the far layer")
		check(valley_behind.get_parent() == game._far_layer and far_cloud.get_index() < valley_behind.get_index() and game._far_layer.z_index < game._mid_layer.z_index, "ValleyCloudBehindPeaks follows FarCloud and stays behind middle peaks")
		check(valley_across.get_parent() == game._mid_layer and cloud_mid_art.get_index() < valley_across.get_index() and game._mid_layer.z_index < game._near_layer.z_index, "ValleyCloudAcrossWaists follows MiddleArtwork and stays behind the near layer")
		check(far_cloud.material == cloud_materials[0] and valley_behind.material == cloud_materials[1] and valley_across.material == cloud_materials[2], "cloud layer order matches the three exposed shader materials")

	# Check the real _process path with QA clock motion enabled. Static mode must
	# hold existing cloud uniforms; dynamic mode advances them with the shared
	# presentation clock while Lighting remains disabled.
	var prior_qa_pause: bool = game.qa_motion_paused
	var prior_dynamic: bool = game.dynamic_enabled
	var prior_lighting: bool = game.lighting_enabled
	game.qa_motion_paused = false
	game.set_dynamic(false)
	game.set_lighting(false)
	var gameplay_before_clouds := [game.state.day, game.state.time_index, game.state.energy, game.state.cultivation]
	var frozen_cloud_times := _cloud_times()
	for _frame in 4:
		await process_frame
	check(_cloud_times() == frozen_cloud_times, "static mode freezes cloud uniforms through actual process frames")
	game.set_dynamic(true)
	var advancing_cloud_times := _cloud_times()
	for _frame in 4:
		await process_frame
	var advanced_cloud_times := _cloud_times()
	check(advanced_cloud_times.size() == 3 and advancing_cloud_times.size() == 3, "dynamic cloud clock exposes all three synchronized uniforms")
	if advanced_cloud_times.size() == 3 and advancing_cloud_times.size() == 3:
		check(advanced_cloud_times != advancing_cloud_times, "dynamic mode advances cloud uniforms through actual process frames")
		for cloud_time in advanced_cloud_times:
			check(is_equal_approx(float(cloud_time), game.presentation_time), "dynamic cloud uniform follows the shared presentation clock")
	check(not game.lighting_enabled, "cloud clock advances with Lighting disabled")
	check(gameplay_before_clouds == [game.state.day, game.state.time_index, game.state.energy, game.state.cultivation], "cloud processing preserves day, time index, energy, and cultivation")
	game.set_dynamic(false)
	game.qa_motion_paused = prior_qa_pause
	check(game.reset_demo(), "cloud clock checks leave an idle scene that resets")
	for material in game._cloud_materials:
		check(is_equal_approx(float(material.get_shader_parameter("cloud_time")), 0.0), "reset_demo explicitly resets each cloud uniform to time zero in static mode")
	game.set_dynamic(prior_dynamic)
	game.set_lighting(prior_lighting)

	_finish()

func _wait_until_idle() -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while game.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not game.busy, "training completes within the bounded time wait")

func _fresh_matching(source: Object) -> Object:
	var fresh = source.get_script().new()
	for field in STATE_FIELDS:
		fresh.set(field, source.get(field))
	return fresh

func _state_snapshot(state: Object) -> Dictionary:
	var snapshot: Dictionary = {}
	for field in STATE_FIELDS:
		var value = state.get(field)
		if value is Dictionary or value is Array:
			snapshot[field] = value.duplicate(true)
		else:
			snapshot[field] = value
	return snapshot

func _full_state_snapshot() -> Dictionary:
	var snapshot := _state_snapshot(game.state)
	snapshot["tea_session"] = game.state.tea_session
	snapshot["time_text"] = game.state.time_text()
	return snapshot

func _cloud_times() -> Array:
	var times: Array = []
	for material in game._cloud_materials:
		times.append(float(material.get_shader_parameter("cloud_time")))
	return times

func check(condition: bool, label: String) -> void:
	checks[label] = condition
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1
		push_error(label)

func _finish() -> void:
	print("BACK_MOUNTAIN_TESTS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
