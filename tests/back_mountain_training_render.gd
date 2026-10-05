extends SceneTree

# Captures the standalone scene with the project's real Compatibility renderer.
# Synthetic mouse events are routed through the rendered viewport hit testing.
# Native OS input / human playtesting is recorded separately.
const SCENE_PATH := "res://scenes/demos/back_mountain_training.tscn"
const OUTPUT_DIR := "res://.local/qa/back-mountain-lighting-v1"
const STATE_FIELDS := [
	"day", "time_index", "energy", "cultivation", "understanding", "lesson_bonus",
	"dialogue_open", "tea_accepted", "tea_seen", "tea_stage_complete", "tea_quest_complete",
	"tea_action_done", "tea_active"
]

var game: Control
var failures := 0
var checks: Dictionary = {}
var captures: Dictionary = {}
var report: Dictionary = {"checks": {}, "screenshots": [], "pixel_deltas": {}}
var frame_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1152, 720)
	OS.low_processor_usage_mode = false
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)

	var packed: PackedScene = load(SCENE_PATH)
	check(packed != null, "standalone scene loads for real rendering")
	if packed == null:
		await _finish()
		return
	game = packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.state != null and game.config is Dictionary, "scene exposes its state and test config")
	if game.state == null or not (game.config is Dictionary):
		await _finish()
		return
	# Preserve the established v0 captures and tint checks before exercising the
	# new Lighting v1 path later in this renderer run.
	game.set_lighting(false)
	check(is_equal_approx(float(game.config.get("training_seconds", -1.0)), 1.8), "renderer keeps the normal 1.8 second action for an intermediate frame")
	game.qa_motion_paused = true
	game.set_dynamic(true)
	game.seek_presentation(4.0)
	game.refresh_environment()
	await process_frame
	await process_frame

	var renderer_method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
	var adapter := RenderingServer.get_video_adapter_name()
	var display_server := DisplayServer.get_name()
	report.renderer = {"method_setting": renderer_method, "adapter": adapter, "display_server": display_server}
	check(renderer_method.to_lower().contains("compat"), "project is running with the Compatibility renderer setting")
	check(display_server.to_lower() != "headless", "renderer check has a windowed display server")
	check(not adapter.is_empty(), "renderer adapter identity is available")
	report.initial_size = [1152, 720]

	check(game.dynamic_enabled, "scene starts in dynamic presentation mode")
	check(_controls_are_visible([game.actor_hotspot, game.sword_hotspot, game.reset_button, game.dynamic_button, game.lighting_button]), "all interaction controls are visible at 1152x720")
	var start_state := _state_snapshot(game.state)
	var state_text_before := _state_text_tokens()
	check(state_text_before.has(str(game.state.energy)) and state_text_before.has(str(game.state.cultivation)) and state_text_before.has(game.state.time_text()), "energy, progress, and day/time are rendered as labels")
	var first_image: Image = await _capture("01_idle_dynamic.png")
	var initial_presentation: float = game.presentation_time

	# A/B at one frozen clock value: the real button is used to switch modes.
	await _click(game.dynamic_button)
	check(not game.dynamic_enabled, "dynamic button switches to static mode through mouse input")
	check(_state_snapshot(game.state) == start_state, "dynamic/static control does not alter numeric or clock state")
	check(is_equal_approx(game.presentation_time, initial_presentation), "dynamic/static control preserves the QA presentation clock")
	var state_text_after := _state_text_tokens()
	check(state_text_before == state_text_after, "rendered energy, cultivation, and day/time labels stay equal across A/B")
	var static_image: Image = await _capture("02_idle_static.png")
	var ab_delta := _pixel_delta(_crop_art(first_image), _crop_art(static_image))
	report.pixel_deltas["dynamic_static_same_clock"] = ab_delta
	check(int(ab_delta.changed_samples) > 0, "dynamic and static artwork differs at the same presentation time")
	var header_delta := _pixel_delta(_crop(first_image, Rect2i(0, 0, 860, 72)), _crop(static_image, Rect2i(0, 0, 860, 72)))
	var footer_delta := _pixel_delta(_crop(first_image, Rect2i(0, 645, 1152, 75)), _crop(static_image, Rect2i(0, 645, 1152, 75)))
	report.pixel_deltas["numeric_header_excluding_toggle"] = header_delta
	report.pixel_deltas["footer_excluding_hover_hint"] = footer_delta
	check(int(header_delta.changed_samples) == 0, "numeric and clock header pixels stay fixed across the A/B toggle")
	check(int(footer_delta.changed_samples) == 0, "footer pixels stay fixed across the A/B toggle")

	# Hover is verified separately from parallax. The actual art area receives
	# viewport mouse events, while QA clock motion stays frozen; drive only the
	# controller's smoothing step so elapsed presentation time remains constant.
	await _click(game.dynamic_button)
	check(game.dynamic_enabled, "dynamic presentation resumes through the button")
	await _move_pointer_to_control(game.actor_hotspot)
	check(game.actor_hotspot.is_hovered(), "actor hotspot receives viewport pointer hover")
	var frozen_clock: float = game.presentation_time
	await _move_pointer(_art_window_point(Vector2(360.0, 260.0)))
	for _i in 12:
		game._update_parallax(0.05)
		await process_frame
	var positions_a := _parallax_positions()
	var pointer_a := await _capture("pointer_world_a.png")
	await _move_pointer(_art_window_point(Vector2(1060.0, 440.0)))
	for _i in 12:
		game._update_parallax(0.05)
		await process_frame
	var positions_b := _parallax_positions()
	var pointer_b := await _capture("pointer_world_b.png")
	var parallax_delta := _pixel_delta(_crop_art(pointer_a), _crop_art(pointer_b))
	report.pixel_deltas["pointer_motion_frozen_clock"] = parallax_delta
	check(positions_a != positions_b, "viewport pointer movement changes smoothed parallax layer transforms")
	check(int(parallax_delta.changed_samples) > 0, "pointer parallax changes artwork with presentation time frozen")
	check(is_equal_approx(game.presentation_time, frozen_clock), "parallax checks keep the QA presentation clock frozen")

	# Restore dynamic mode using the visible button, then capture the pre-action
	# frame. Two distinct actual hotspots are clicked back-to-back in one frame.
	game.seek_presentation(4.0)
	game.refresh_environment()
	await process_frame
	game.qa_motion_paused = false
	var before_action_state := _state_snapshot(game.state)
	var fresh_expected = _fresh_matching(game.state)
	var expected_result: Dictionary = fresh_expected.train()
	await _capture("03_before_training.png")
	_push_click(game.actor_hotspot)
	_push_click(game.sword_hotspot)
	await process_frame
	check(game.busy, "hotspot click starts a visible training action")
	check(_state_snapshot(game.state) == _state_snapshot(fresh_expected), "two rapid hotspot clicks settle DemoState.train() exactly once")
	check(_state_snapshot(game.state) != before_action_state, "hotspot action changes the displayed cultivation state")
	await _capture("04_training_feedback.png")
	check(game.busy or bool(game.last_result.get("ok", false)), "training feedback frame shows either busy progress or the completed result")
	await _wait_until_idle()
	check(not game.busy, "hotspot training finishes asynchronously")
	check(bool(game.last_result.get("ok", false)), "training result feedback is recorded")
	check(int(game.last_result.get("gain", -1)) == int(expected_result.get("gain", -2)), "training feedback uses the rules-derived gain")
	check(game.state.time_text() == fresh_expected.time_text(), "training advances the displayed day/time from DemoState rules")
	var after_action := await _capture("05_after_training_new_time.png")
	game.qa_motion_paused = true
	report.pixel_deltas["before_after_training"] = _pixel_delta(first_image, after_action)

	# Deterministic later-frame pair: dynamic art responds to the QA clock while
	# static art remains visually fixed over the same seeks.
	game.set_dynamic(true)
	game.seek_presentation(4.0)
	var dynamic_later_a: Image = await _capture("06_dynamic_later_a.png")
	game.seek_presentation(10.0)
	var dynamic_later_b: Image = await _capture("07_dynamic_later_b.png")
	var dynamic_clock_delta := _pixel_delta(_crop_art(dynamic_later_a), _crop_art(dynamic_later_b))
	report.pixel_deltas["dynamic_later_clock_pair"] = dynamic_clock_delta
	check(int(dynamic_clock_delta.changed_samples) > 0, "dynamic presentation changes between later QA clock frames")
	game.set_dynamic(false)
	game.seek_presentation(4.0)
	var static_later_a: Image = await _capture("08_static_later_a.png")
	game.seek_presentation(10.0)
	var static_later_b: Image = await _capture("09_static_later_b.png")
	var static_clock_delta := _pixel_delta(_crop_art(static_later_a), _crop_art(static_later_b))
	report.pixel_deltas["static_later_clock_pair"] = static_clock_delta
	check(int(static_clock_delta.changed_samples) == 0, "static presentation stays visually fixed between later QA clock frames")

	# Compare only wind shader strength at an identical presentation instant.
	game.set_dynamic(true)
	var first_gust: Dictionary = game._gust_schedule[0]
	game.seek_presentation(float(first_gust.start) + float(first_gust.duration) * 0.5)
	game.set_process(false)
	var gust_strength: float = game._near_material.get_shader_parameter("wind_strength")
	check(gust_strength > 0.0, "scheduled gust drives the local wind shaders")
	game._set_wind_strength(0.0)
	var wind_zero: Image = await _capture("11_gust_without_wind.png")
	game._set_wind_strength(gust_strength)
	var wind_active: Image = await _capture("12_gust_wind_response.png")
	var wind_delta := _pixel_delta(_crop_art(wind_zero), _crop_art(wind_active))
	report.pixel_deltas["wind_strength_only"] = wind_delta
	check(int(wind_delta.changed_samples) > 0, "wind shaders visibly move foliage and hair at a frozen clock")
	game.set_process(true)

	# Time fixtures deliberately use labels absent from the reachable set of
	# normal training turns, so the UI can be checked without inventing new rules.
	var reachable := _reachable_time_indices(game.state)
	var rules_times: Array = game.state.rules.times
	var noon_index := rules_times.find("午时")
	var evening_index := rules_times.find("酉时")
	check(noon_index >= 0 and not reachable.has(noon_index), "午时 is a valid but unreachable normal-training fixture")
	check(evening_index >= 0 and not reachable.has(evening_index), "酉时 is a valid but unreachable normal-training fixture")
	var saved_day: int = game.state.day
	var saved_time_index: int = game.state.time_index
	game.state.time_index = noon_index
	game._refresh_hud()
	game.refresh_environment()
	var noon_labels := _state_text_tokens()
	check(_label_text_contains("午时"), "午时 fixture is visible in the rendered clock label")
	var noon_image: Image = await _capture("fixture_unreachable_午时.png")
	game.state.time_index = evening_index
	game._refresh_hud()
	game.refresh_environment()
	check(_label_text_contains("酉时"), "酉时 fixture is visible in the rendered clock label")
	var evening_image: Image = await _capture("fixture_unreachable_酉时.png")
	var noon_tint_delta := _pixel_delta(_crop_art(first_image), _crop_art(noon_image))
	var evening_tint_delta := _pixel_delta(_crop_art(first_image), _crop_art(evening_image))
	report.pixel_deltas["unreachable_noon_tint_vs_dawn"] = noon_tint_delta
	report.pixel_deltas["unreachable_evening_tint_vs_dawn"] = evening_tint_delta
	check(int(noon_tint_delta.changed_samples) > 0, "unreachable 午时 fixture changes the art tint from dawn")
	check(int(evening_tint_delta.changed_samples) > 0, "unreachable 酉时 fixture changes the art tint from dawn")
	game.state.day = saved_day
	game.state.time_index = saved_time_index
	game._refresh_hud()
	game.refresh_environment()
	report.time_fixture = {"reachable_indices": reachable, "午时_index": noon_index, "酉时_index": evening_index, "noon_label_snapshot": noon_labels}

	await _run_lighting_sequence()

	# Reset remains a real button path. The narrow window check is performed after
	# reset so the final layout evidence starts from a known UI state.
	var session_before_reset: int = game.state.tea_session
	await _click(game.reset_button)
	var fresh_reset = game.state.get_script().new()
	check(_state_snapshot(game.state) == _state_snapshot(fresh_reset), "reset button restores fresh DemoState values")
	check(game.state.tea_session > session_before_reset, "reset button invalidates stale DemoState session context")
	check(not game.state.tea_active and not game.state.tea_accepted and game.state.tea_seen.is_empty() and game.state.tea_action_done.is_empty(), "reset button clears all phase flags")
	root.size = Vector2i(960, 600)
	await process_frame
	await process_frame
	check(_controls_are_visible([game.actor_hotspot, game.sword_hotspot, game.reset_button, game.dynamic_button, game.lighting_button]), "all interaction controls remain visible at 960x600")
	report.narrow_size = [960, 600]
	await _capture("10_narrow_960x600.png")
	check(_controls_fit_window([game.actor_hotspot, game.sword_hotspot, game.reset_button, game.dynamic_button, game.lighting_button]), "interactive controls fit inside the 960x600 window")

	await _finish()

func _run_lighting_sequence() -> void:
	check(game.reset_demo(), "Lighting v1 render sequence starts from a fresh DemoState")
	game.qa_motion_paused = true
	game.set_dynamic(false)
	game._set_actor_hover(false)
	game._set_sword_hover(false)
	game.set_process(false)
	game.set_lighting(false)
	game.seek_presentation(0.0)
	game.refresh_environment(false)
	game.lighting.finish_transition()
	await process_frame
	await process_frame
	var original_state := _state_snapshot(game.state)
	var original_frame: Image = await _capture("01_original_lighting.png")
	check(not game.lighting_enabled, "original lighting capture uses the preserved v0 rendering path")

	# Capture every rules-backed profile using explicit state fixtures. Noon and
	# dusk remain QA-only fixtures; these assignments do not add gameplay actions.
	game.set_lighting(true)
	var rules_times: Array = game.state.rules.times
	var fixture_state := _state_snapshot(game.state)
	var fixture_files := [
		"02_lighting_v1_mao.png",
		"02b_lighting_v1_chen.png",
		"03_lighting_v1_si.png",
		"04_lighting_v1_noon.png",
		"05_lighting_v1_shen.png",
		"06_lighting_v1_you.png",
	]
	var fixture_names := ["卯时", "辰时", "巳时", "午时", "申时", "酉时"]
	for fixture_i in range(fixture_names.size()):
		var time_index := rules_times.find(fixture_names[fixture_i])
		check(time_index >= 0, "Lighting v1 render fixture exists in DemoState rules: %s" % fixture_names[fixture_i])
		if time_index < 0:
			continue
		game.state.time_index = time_index
		game._refresh_hud()
		game.refresh_environment(false)
		game.lighting.finish_transition()
		await process_frame
		await process_frame
		check(game.lighting.profile_index == time_index and game.lighting.target_time_index == time_index, "render fixture settles on the %s Lighting v1 profile" % fixture_names[fixture_i])
		check(_label_text_contains(fixture_names[fixture_i]), "render fixture shows the %s rules clock" % fixture_names[fixture_i])
		await _capture(fixture_files[fixture_i])
	check(_without_time_index(_state_snapshot(game.state)) == _without_time_index(fixture_state), "Lighting v1 fixtures leave every non-clock DemoState field intact")
	var contact_detail := await _capture_region("07_contact_shadow_detail.png", Rect2(Vector2(850, 450), Vector2(520, 140)))
	check(contact_detail.get_width() > 0 and contact_detail.get_height() > 0, "contact-shadow detail is a crop from the actual engine image")
	report.contact_shadow_detail = {"file": "07_contact_shadow_detail.png", "art_rect": [850, 450, 520, 140]}

	# Change only the cloud shader uniform at one frozen world frame. Presentation
	# state, labels, and the fixed HUD regions are sampled as independent evidence.
	var noon_index: int = rules_times.find("午时")
	if noon_index >= 0:
		game.state.time_index = noon_index
		game._refresh_hud()
		game.refresh_environment(false)
		game.lighting.finish_transition()
	game.set_dynamic(true)
	game.qa_motion_paused = true
	game.seek_presentation(8.0)
	var cloud_labels := _state_text_tokens()
	var state_before_cloud := _state_snapshot(game.state)
	var cloud_material: ShaderMaterial = game.lighting.cloud_material
	check(cloud_material is ShaderMaterial, "Lighting v1 exposes its cloud shader material for a frozen comparison")
	if cloud_material is ShaderMaterial:
		cloud_material.set_shader_parameter("cloud_time", 0.0)
		await process_frame
		var cloud_clear: Image = await _capture("09_cloud_clear.png")
		cloud_material.set_shader_parameter("cloud_time", 8.0)
		await process_frame
		var cloud_shadow: Image = await _capture("08_cloud_shadow.png")
		var cloud_delta := _pixel_delta(_crop_art(cloud_clear), _crop_art(cloud_shadow))
		report.pixel_deltas["cloud_uniform_only"] = cloud_delta
		check(int(cloud_delta.changed_samples) > 0, "cloud_time alone changes rendered world pixels")
		var cloud_header := _pixel_delta(_crop(cloud_clear, Rect2i(0, 0, 860, 72)), _crop(cloud_shadow, Rect2i(0, 0, 860, 72)))
		var cloud_footer := _pixel_delta(_crop(cloud_clear, Rect2i(0, 645, 1152, 75)), _crop(cloud_shadow, Rect2i(0, 645, 1152, 75)))
		report.pixel_deltas["cloud_numeric_header"] = cloud_header
		report.pixel_deltas["cloud_footer"] = cloud_footer
		check(int(cloud_header.changed_samples) == 0 and int(cloud_footer.changed_samples) == 0, "cloud shadow leaves numeric header and footer pixels unchanged")
		check(cloud_labels == _state_text_tokens(), "cloud shadow leaves energy, cultivation, and time labels unchanged")
		check(state_before_cloud == _state_snapshot(game.state), "cloud rendering does not mutate DemoState")
	else:
		await _capture("09_cloud_clear.png")
		await _capture("08_cloud_shadow.png")

	# Static mode freezes both the dynamic cloud clock and disabled cloud output
	# across seeks of the QA presentation clock.
	game.set_dynamic(false)
	game.seek_presentation(4.0)
	await process_frame
	var static_cloud_a: Image = await _capture("static_cloud_seek_4.png")
	game.seek_presentation(10.0)
	await process_frame
	var static_cloud_b: Image = await _capture("static_cloud_seek_10.png")
	var static_cloud_delta := _pixel_delta(_crop_art(static_cloud_a), _crop_art(static_cloud_b))
	report.pixel_deltas["static_cloud_seek_pair"] = static_cloud_delta
	check(int(static_cloud_delta.changed_samples) == 0, "static cloud frame is identical across presentation clock seeks")
	game.set_lighting(false)
	game.seek_presentation(4.0)
	await process_frame
	var cloud_off_a: Image = await _capture("static_lighting_off_seek_4.png")
	game.seek_presentation(10.0)
	await process_frame
	var cloud_off_b: Image = await _capture("static_lighting_off_seek_10.png")
	var cloud_off_delta := _pixel_delta(_crop_art(cloud_off_a), _crop_art(cloud_off_b))
	report.pixel_deltas["lighting_off_static_seek_pair"] = cloud_off_delta
	check(int(cloud_off_delta.changed_samples) == 0, "Lighting OFF hides cloud enhancements at every static presentation seek")

	# Native lighting is tested by toggling the actual Light2D at a frozen frame.
	# The world must change while the far/mid field and UI pixels stay fixed.
	game.set_lighting(true)
	game.refresh_environment(false)
	game.lighting.finish_transition()
	game.qa_motion_paused = true
	game.set_dynamic(false)
	game.seek_presentation(0.0)
	var cloud_overlay := cloud_material.get_meta("overlay_node") as ColorRect
	var cloud_overlay_was_visible := cloud_overlay.visible if cloud_overlay != null else false
	if cloud_overlay != null:
		cloud_overlay.visible = false
	var numeric_tokens := _state_text_tokens()
	game.lighting.sun.enabled = false
	await process_frame
	var native_sun_off: Image = await _capture("10_native_sun_off.png")
	game.lighting.sun.enabled = true
	await process_frame
	var native_sun_on: Image = await _capture("11_native_sun_on.png")
	var sun_world_delta := _pixel_delta(_crop_art_rect(native_sun_off, Rect2(Vector2(800, 300), Vector2(570, 380))), _crop_art_rect(native_sun_on, Rect2(Vector2(800, 300), Vector2(570, 380))))
	var sun_far_delta := _pixel_delta(_crop_art_rect(native_sun_off, Rect2(Vector2(30, 20), Vector2(480, 75))), _crop_art_rect(native_sun_on, Rect2(Vector2(30, 20), Vector2(480, 75))))
	var sun_ui_header := _pixel_delta(_crop(native_sun_off, Rect2i(0, 0, 860, 72)), _crop(native_sun_on, Rect2i(0, 0, 860, 72)))
	var sun_ui_footer := _pixel_delta(_crop(native_sun_off, Rect2i(0, 645, 1152, 75)), _crop(native_sun_on, Rect2i(0, 645, 1152, 75)))
	report.pixel_deltas["native_sun_world"] = sun_world_delta
	report.pixel_deltas["native_sun_far_mid"] = sun_far_delta
	report.pixel_deltas["native_sun_ui_header"] = sun_ui_header
	report.pixel_deltas["native_sun_ui_footer"] = sun_ui_footer
	check(int(sun_world_delta.changed_samples) > 0, "native Light2D changes actual rendered world pixels")
	check(int(sun_far_delta.changed_samples) == 0, "native Light2D leaves the unshaded far/mid pixel region unchanged")
	check(int(sun_ui_header.changed_samples) == 0 and int(sun_ui_footer.changed_samples) == 0, "native Light2D leaves numeric UI pixels unchanged")
	check(numeric_tokens == _state_text_tokens(), "native Light2D leaves cultivation labels unchanged")

	# Toggling native occluders must alter their rendered contact-shadow pixels,
	# which distinguishes a real shadow effect from merely having nodes present.
	for occluder in game.lighting.occluders:
		occluder.visible = false
	await process_frame
	var occluders_off: Image = await _capture("12_native_occluders_off.png")
	for occluder in game.lighting.occluders:
		occluder.visible = true
	await process_frame
	var occluders_on: Image = await _capture("13_native_occluders_on.png")
	var occluder_delta := _pixel_delta(_crop_art_rect(occluders_off, Rect2(Vector2(850, 450), Vector2(520, 140))), _crop_art_rect(occluders_on, Rect2(Vector2(850, 450), Vector2(520, 140))))
	report.pixel_deltas["native_occluder_contact_region"] = occluder_delta
	check(int(occluder_delta.changed_samples) > 0, "native LightOccluder2D toggles visibly change contact-shadow pixels")
	check(_without_time_index(_state_snapshot(game.state)) == _without_time_index(original_state) and game.state.time_index == noon_index, "native effect comparisons alter presentation only apart from the explicit clock fixture")
	if cloud_overlay != null:
		cloud_overlay.visible = cloud_overlay_was_visible

	# A same-frame OFF/ON/OFF lighting round trip must return to identical art;
	# HUD comparisons exclude both toggle buttons but retain the numeric display.
	game.set_lighting(true)
	game.refresh_environment(false)
	game.lighting.finish_transition()
	await process_frame
	var reversible_on_a: Image = await _capture("14_lighting_roundtrip_on_a.png")
	var state_before_roundtrip := _state_snapshot(game.state)
	var text_before_roundtrip := _state_text_tokens()
	game.set_lighting(false)
	game.set_lighting(true)
	game.refresh_environment(false)
	game.lighting.finish_transition()
	await process_frame
	var reversible_on_b: Image = await _capture("15_lighting_roundtrip_on_b.png")
	var roundtrip_art := _pixel_delta(_crop_art(reversible_on_a), _crop_art(reversible_on_b))
	var roundtrip_header := _pixel_delta(_crop(reversible_on_a, Rect2i(0, 0, 860, 72)), _crop(reversible_on_b, Rect2i(0, 0, 860, 72)))
	var roundtrip_footer := _pixel_delta(_crop(reversible_on_a, Rect2i(0, 645, 1152, 75)), _crop(reversible_on_b, Rect2i(0, 645, 1152, 75)))
	report.pixel_deltas["lighting_same_frame_roundtrip_art"] = roundtrip_art
	report.pixel_deltas["lighting_same_frame_roundtrip_header"] = roundtrip_header
	report.pixel_deltas["lighting_same_frame_roundtrip_footer"] = roundtrip_footer
	check(int(roundtrip_art.changed_samples) == 0, "lighting OFF/ON round trip restores identical artwork at the same frame")
	check(int(roundtrip_header.changed_samples) == 0 and int(roundtrip_footer.changed_samples) == 0, "lighting round trip preserves numeric UI pixels, excluding the toggle")
	check(state_before_roundtrip == _state_snapshot(game.state) and text_before_roundtrip == _state_text_tokens(), "lighting round trip preserves gameplay labels and state")
	check(_without_time_index(_state_snapshot(game.state)) == _without_time_index(original_state), "QA profile fixtures preserve every numeric state field")

	# Capture the actual 1.05 second profile blend after gameplay settles the new
	# clock. The app's process is frozen and _process is advanced explicitly so
	# only the lighting profile changes between these three rendered frames.
	game.set_lighting(true)
	game.set_dynamic(false)
	game.set_process(false)
	check(game.reset_demo(), "training transition render starts from the fresh dawn state")
	game.set_lighting(true)
	game.refresh_environment(false)
	game.lighting.finish_transition()
	await process_frame
	var old_profile_image: Image = await _capture("training_profile_before.png")
	var old_profile_index: int = game.lighting.profile_index
	var transition_request: Dictionary = game.request_training()
	check(bool(transition_request.get("ok", false)) and game.busy, "training transition fixture begins through the real request path")
	game._process(1.8)
	check(not game.busy, "explicit deterministic process step finishes training and begins the profile blend")
	var transition_target: int = game.state.time_index
	check(game.lighting.target_time_index == transition_target, "training blend targets the settled DemoState time")
	check(game.lighting.profile_index == old_profile_index, "rendered profile index stays old at transition start")
	var transition_start: Image = await _capture("16_training_profile_start.png")
	var transition_initial_delta := _pixel_delta(_crop_art(old_profile_image), _crop_art(transition_start))
	report.pixel_deltas["training_profile_no_initial_jump"] = transition_initial_delta
	check(int(transition_initial_delta.changed_samples) == 0, "training completion preserves the old world lighting on the first transition frame")
	var transition_state := _state_snapshot(game.state)
	var transition_labels := _state_text_tokens()
	game._process(0.525)
	var transition_mid: Image = await _capture("17_training_profile_mid.png")
	check(game.lighting.profile_index == old_profile_index, "rendered profile index stays old at transition midpoint")
	game._process(0.525)
	var transition_end: Image = await _capture("18_training_profile_end.png")
	check(game.lighting.profile_index == transition_target, "rendered profile index advances when the transition finishes")
	var transition_start_mid := _pixel_delta(_crop_art(transition_start), _crop_art(transition_mid))
	var transition_mid_end := _pixel_delta(_crop_art(transition_mid), _crop_art(transition_end))
	var transition_start_end := _pixel_delta(_crop_art(transition_start), _crop_art(transition_end))
	report.pixel_deltas["training_profile_start_mid"] = transition_start_mid
	report.pixel_deltas["training_profile_mid_end"] = transition_mid_end
	report.pixel_deltas["training_profile_start_end"] = transition_start_end
	check(int(transition_start_mid.changed_samples) > 0 and int(transition_mid_end.changed_samples) > 0, "training profile transition visibly changes world pixels at start, middle, and end")
	check(transition_state == _state_snapshot(game.state) and transition_labels == _state_text_tokens(), "training profile transition keeps settled state and clock labels fixed")
	var transition_header_start_mid := _pixel_delta(_crop(transition_start, Rect2i(0, 0, 860, 72)), _crop(transition_mid, Rect2i(0, 0, 860, 72)))
	var transition_header_mid_end := _pixel_delta(_crop(transition_mid, Rect2i(0, 0, 860, 72)), _crop(transition_end, Rect2i(0, 0, 860, 72)))
	var transition_footer_start_mid := _pixel_delta(_crop(transition_start, Rect2i(0, 645, 1152, 75)), _crop(transition_mid, Rect2i(0, 645, 1152, 75)))
	var transition_footer_mid_end := _pixel_delta(_crop(transition_mid, Rect2i(0, 645, 1152, 75)), _crop(transition_end, Rect2i(0, 645, 1152, 75)))
	report.pixel_deltas["training_transition_numeric_header"] = [transition_header_start_mid, transition_header_mid_end]
	report.pixel_deltas["training_transition_footer"] = [transition_footer_start_mid, transition_footer_mid_end]
	check(int(transition_header_start_mid.changed_samples) == 0 and int(transition_header_mid_end.changed_samples) == 0, "training profile blend leaves numeric header pixels unchanged")
	check(int(transition_footer_start_mid.changed_samples) == 0 and int(transition_footer_mid_end.changed_samples) == 0, "training profile blend leaves footer pixels unchanged")
	check(int(transition_start_end.changed_samples) > 0 and old_profile_image.get_size() == transition_start.get_size(), "profile transition has a comparable before-training frame")

	# Keep the surrounding renderer test and its final narrow-window reset active.
	game.set_process(true)
	game.set_lighting(true)
	check(game.reset_demo(), "Lighting v1 captures finish with a real reset path available")
	game.set_lighting(true)
	game.refresh_environment(false)
	game.lighting.finish_transition()
	game.qa_motion_paused = true
	game.set_dynamic(false)

func _wait_until_idle() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while game.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not game.busy, "training completes within bounded real time")

func _click(control: Control) -> void:
	_push_click(control)
	await process_frame
	await process_frame

func _push_click(control: Control) -> void:
	var point := _window_position(control)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	var down := InputEventMouseButton.new()
	down.position = point
	down.global_position = point
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down)
	var up := InputEventMouseButton.new()
	up.position = point
	up.global_position = point
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	root.push_input(up)

func _move_pointer_to_control(control: Control) -> void:
	await _move_pointer(_window_position(control))

func _move_pointer(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await process_frame

func _window_position(control: Control) -> Vector2:
	var canvas_point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	return root.get_final_transform() * canvas_point

func _art_window_point(local_point: Vector2) -> Vector2:
	var canvas_point: Vector2 = game._art_root.get_global_transform_with_canvas() * local_point
	return root.get_final_transform() * canvas_point

func _controls_are_visible(controls: Array) -> bool:
	for control in controls:
		if not is_instance_valid(control) or not control.is_visible_in_tree():
			return false
	return true

func _controls_fit_window(controls: Array) -> bool:
	for control in controls:
		var point := _window_position(control)
		var half_size: Vector2 = control.size * root.get_final_transform().get_scale() * 0.5
		if point.x - half_size.x < 0.0 or point.y - half_size.y < 0.0:
			return false
		if point.x + half_size.x > float(root.size.x) or point.y + half_size.y > float(root.size.y):
			return false
	return true

func _capture(filename: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_DIR + "/" + filename)
	var error := image.save_png(absolute_path)
	check(error == OK, "screenshot saved: " + filename)
	report.screenshots.append(filename)
	captures[filename] = image
	frame_count += 1
	return image

func _capture_region(filename: String, art_rect: Rect2) -> Image:
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	var image := _crop_art_rect(frame, art_rect)
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_DIR + "/" + filename)
	var error := image.save_png(absolute_path)
	check(error == OK, "cropped screenshot saved: " + filename)
	report.screenshots.append(filename)
	captures[filename] = image
	frame_count += 1
	return image

func _crop_art(image: Image) -> Image:
	var transform: Transform2D = root.get_final_transform() * game._art_root.get_global_transform_with_canvas()
	var origin: Vector2 = transform * Vector2.ZERO
	var scale: Vector2 = transform.get_scale()
	var rect := Rect2i(
		floori(origin.x), floori(origin.y),
		ceili(game._art_root.size.x * scale.x), ceili(game._art_root.size.y * scale.y)
	)
	return _crop(image, rect)

func _crop_art_rect(image: Image, art_rect: Rect2) -> Image:
	var transform: Transform2D = root.get_final_transform() * game._art_root.get_global_transform_with_canvas()
	var origin: Vector2 = transform * art_rect.position
	var scale: Vector2 = transform.get_scale()
	var rect := Rect2i(
		floori(origin.x), floori(origin.y),
		ceili(art_rect.size.x * scale.x), ceili(art_rect.size.y * scale.y)
	)
	return _crop(image, rect)

func _crop(image: Image, rect: Rect2i) -> Image:
	var clipped := rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	return image.get_region(clipped)

func _parallax_positions() -> Array:
	var positions: Array = []
	for layer in game._parallax_layers:
		positions.append(layer.position)
	return positions

func _pixel_delta(left: Image, right: Image) -> Dictionary:
	if left == null or right == null or left.get_size() != right.get_size():
		return {"changed_samples": -1, "sample_count": 0, "mean_rgb_delta": -1.0}
	var changed := 0
	var total := 0
	var delta_sum := 0.0
	for y in range(0, left.get_height(), 3):
		for x in range(0, left.get_width(), 3):
			var a := left.get_pixel(x, y)
			var b := right.get_pixel(x, y)
			var delta := (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			total += 1
			delta_sum += delta
			if delta > 0.012:
				changed += 1
	return {"changed_samples": changed, "sample_count": total, "mean_rgb_delta": delta_sum / float(maxi(1, total))}

func _state_snapshot(state: Object) -> Dictionary:
	var result: Dictionary = {}
	for field in STATE_FIELDS:
		var value = state.get(field)
		if value is Dictionary or value is Array:
			result[field] = value.duplicate(true)
		else:
			result[field] = value
	return result

func _without_time_index(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	result.erase("time_index")
	return result

func _fresh_matching(source: Object) -> Object:
	var fresh = source.get_script().new()
	for field in STATE_FIELDS:
		fresh.set(field, source.get(field))
	return fresh

func _reachable_time_indices(state: Object) -> Array:
	var reference = state.get_script().new()
	var reachable: Array = []
	var max_attempts := int(reference.rules.times.size()) * 3
	for _i in range(max_attempts):
		if not reachable.has(reference.time_index):
			reachable.append(reference.time_index)
		var result: Dictionary = reference.train()
		if not bool(result.get("ok", false)):
			break
	return reachable

func _state_text_tokens() -> Dictionary:
	var expected := [str(game.state.energy), str(game.state.cultivation), game.state.time_text()]
	var found: Dictionary = {}
	for node in game.find_children("*", "Label", true, false):
		for token in expected:
			if str(node.text).contains(token):
				found[token] = str(node.text)
	return found

func _label_text_contains(token: String) -> bool:
	for node in game.find_children("*", "Label", true, false):
		if str(node.text).contains(token):
			return true
	return false

func check(condition: bool, label: String) -> void:
	checks[label] = condition
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1
		push_error(label)

func _finish() -> void:
	if failures > 0 and is_instance_valid(root):
		await _capture("failure.png")
	report.checks = checks
	report.failures = failures
	report.captured_frames = frame_count
	var report_path := ProjectSettings.globalize_path(OUTPUT_DIR + "/qa-report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ") + "\n")
	else:
		push_error("could not write QA report: " + report_path)
		failures += 1
	print("BACK_MOUNTAIN_RENDER: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
