extends SceneTree

# Captures the standalone scene with the project's real Compatibility renderer.
# Synthetic mouse events are routed through the rendered viewport hit testing.
# Native OS input / human playtesting is recorded separately.
const SCENE_PATH := "res://scenes/demos/back_mountain_training.tscn"
const OUTPUT_DIR := "res://.local/qa/back-mountain-lighting-v1"
const CLOUD_OUTPUT_DIR := "res://.local/qa/back-mountain-clouds-v1"
const AMBIENT_OUTPUT_DIR := "res://.local/qa/back-mountain-ambient-life-v1"
const AMBIENT_MOTION_OUTPUT_DIR := "res://.local/qa/back-mountain-ambient-life-v1-1"
const CLOUD_DETAIL_RECT := Rect2(Vector2(330.0, 220.0), Vector2(520.0, 290.0))
const CLOUD_COMPARISON_RECT := Rect2(Vector2(110.0, 75.0), Vector2(1220.0, 175.0))
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
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if user_args.has("--ambient-motion") or OS.get_cmdline_args().has("--ambient-motion"):
		await _run_ambient_pose_motion_v1_1()
		return
	if user_args.has("--ambient-life") or OS.get_cmdline_args().has("--ambient-life"):
		await _run_ambient_life_v1()
		return
	await _run_environment_v1()

func _run_legacy_lighting_clouds() -> void:
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
	await _run_clouds_sequence()

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

func _run_clouds_sequence() -> void:
	var previous_process := game.is_processing()
	var previous_dynamic: bool = game.dynamic_enabled
	var previous_lighting: bool = game.lighting_enabled
	var previous_qa_pause: bool = game.qa_motion_paused
	var previous_presentation_time: float = game.presentation_time
	var previous_cloud_times := _cloud_times()
	var state_before_clouds := _state_snapshot(game.state)
	var cloud_report := {"screenshots": [], "pixel_deltas": {}}
	report["clouds_v1"] = cloud_report

	# The cloud comparisons share one deterministic world fixture. Disable
	# lighting and pause QA motion so only explicit seeks and cloud uniforms vary.
	game.qa_motion_paused = true
	game.set_process(false)
	game.set_lighting(false)
	game.set_dynamic(true)
	game.seek_presentation(0.0)
	game.set_dynamic(false)
	var static_frame: Image = await _capture_cloud("01_static.png")
	game.set_dynamic(true)
	game.seek_presentation(0.0)
	var dynamic_t0: Image = await _capture_cloud("02_dynamic_t0.png")
	game.seek_presentation(5.0)
	await _capture_cloud("02b_dynamic_t5.png")
	game.seek_presentation(10.0)
	var dynamic_t10: Image = await _capture_cloud("03_dynamic_t10.png")
	game.seek_presentation(20.0)
	var dynamic_t20: Image = await _capture_cloud("04_dynamic_t20.png")
	var valley_detail := await _capture_cloud_region("05_valley_cloud.png", dynamic_t20, CLOUD_DETAIL_RECT)
	check(valley_detail.get_width() > 0 and valley_detail.get_height() > 0, "valley cloud detail is cropped from the actual t20 engine frame")

	var static_to_dynamic := _pixel_delta(_crop_art_rect(static_frame, CLOUD_COMPARISON_RECT), _crop_art_rect(dynamic_t0, CLOUD_COMPARISON_RECT))
	var t0_to_t10 := _pixel_delta(_crop_art_rect(dynamic_t0, CLOUD_COMPARISON_RECT), _crop_art_rect(dynamic_t10, CLOUD_COMPARISON_RECT))
	var t10_to_t20 := _pixel_delta(_crop_art_rect(dynamic_t10, CLOUD_COMPARISON_RECT), _crop_art_rect(dynamic_t20, CLOUD_COMPARISON_RECT))
	cloud_report.pixel_deltas["static_vs_dynamic_t0"] = static_to_dynamic
	cloud_report.pixel_deltas["dynamic_t0_to_t10"] = t0_to_t10
	cloud_report.pixel_deltas["dynamic_t10_to_t20"] = t10_to_t20
	check(int(static_to_dynamic.changed_samples) == 0, "static presentation keeps clouds visible at the same cloud time as dynamic t0")
	check(int(t0_to_t10.changed_samples) > 0 and int(t10_to_t20.changed_samples) > 0, "mountain cloud band changes across explicit dynamic time seeks")

	# Isolate cloud output at t20 by temporarily zeroing only the three cloud
	# alpha uniforms. Restore their configured values before the frozen capture.
	var cloud_alphas: Array = []
	for material in game._cloud_materials:
		cloud_alphas.append(float(material.get_shader_parameter("cloud_alpha")))
		material.set_shader_parameter("cloud_alpha", 0.0)
	var clouds_hidden_t20: Image = await _capture_cloud("clouds_hidden_t20.png")
	for material_index in game._cloud_materials.size():
		game._cloud_materials[material_index].set_shader_parameter("cloud_alpha", cloud_alphas[material_index])
	var hidden_delta := _pixel_delta(_crop_art_rect(clouds_hidden_t20, CLOUD_COMPARISON_RECT), _crop_art_rect(dynamic_t20, CLOUD_COMPARISON_RECT))
	cloud_report.pixel_deltas["clouds_visible_vs_hidden_t20"] = hidden_delta
	check(int(hidden_delta.changed_samples) > 0, "cloud shader alpha changes mountain pixels while Lighting is disabled")

	var t20_cloud_times := _cloud_times()
	game.set_dynamic(false)
	var static_frozen_t20: Image = await _capture_cloud("static_frozen_t20.png")
	game.seek_presentation(25.0)
	var static_frozen_seek25: Image = await _capture_cloud("static_frozen_seek25.png")
	var frozen_delta := _pixel_delta(_crop_art_rect(static_frozen_t20, CLOUD_COMPARISON_RECT), _crop_art_rect(static_frozen_seek25, CLOUD_COMPARISON_RECT))
	cloud_report.pixel_deltas["static_t20_vs_static_seek25"] = frozen_delta
	check(_cloud_times() == t20_cloud_times, "static mode holds t20 cloud uniforms across a later presentation seek")
	check(int(frozen_delta.changed_samples) == 0, "static cloud band is identical after seeking beyond t20")
	check(not game.lighting_enabled, "all Clouds v1 captures run with Lighting disabled")
	check(state_before_clouds == _state_snapshot(game.state), "cloud render sequence preserves DemoState")

	# Restore the enclosing renderer fixture before its reset-button checks.
	game.set_process(previous_process)
	game.qa_motion_paused = previous_qa_pause
	game.set_dynamic(previous_dynamic)
	game.seek_presentation(previous_presentation_time)
	for material_index in mini(game._cloud_materials.size(), previous_cloud_times.size()):
		game._cloud_materials[material_index].set_shader_parameter("cloud_time", previous_cloud_times[material_index])
	game.set_lighting(previous_lighting)
	game.refresh_environment(false)
	if previous_lighting and game.lighting != null:
		game.lighting.finish_transition()
	check(game.is_processing() == previous_process, "cloud render sequence restores the enclosing process state")
	check(game.dynamic_enabled == previous_dynamic and game.lighting_enabled == previous_lighting, "cloud render sequence restores dynamic and lighting controls")
	check(state_before_clouds == _state_snapshot(game.state), "restoring the renderer fixture preserves DemoState")
	var cloud_report_path := ProjectSettings.globalize_path(CLOUD_OUTPUT_DIR + "/qa-report.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLOUD_OUTPUT_DIR))
	var cloud_report_file := FileAccess.open(cloud_report_path, FileAccess.WRITE)
	if cloud_report_file != null:
		cloud_report_file.store_string(JSON.stringify(cloud_report, "  ") + "\n")
	else:
		check(false, "cloud QA report can be written")

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

func _capture_cloud(filename: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var output_path := ProjectSettings.globalize_path(CLOUD_OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	var error := image.save_png(output_path.path_join(filename))
	check(error == OK, "cloud screenshot saved: " + filename)
	report.clouds_v1.screenshots.append(filename)
	captures["clouds-v1/" + filename] = image
	frame_count += 1
	return image

func _capture_cloud_region(filename: String, source: Image, art_rect: Rect2) -> Image:
	var image := _crop_art_rect(source, art_rect)
	var output_path := ProjectSettings.globalize_path(CLOUD_OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	var error := image.save_png(output_path.path_join(filename))
	check(error == OK, "cloud detail screenshot saved: " + filename)
	report.clouds_v1.screenshots.append(filename)
	captures["clouds-v1/" + filename] = image
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

func _cloud_times() -> Array:
	var times: Array = []
	for material in game._cloud_materials:
		times.append(float(material.get_shader_parameter("cloud_time")))
	return times

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


func _run_environment_v1() -> void:
	failures = 0
	checks.clear()
	captures.clear()
	frame_count = 0
	report = {"checks": {}, "screenshots": [], "failures": [], "screenshot_dimensions": {}, "world_weather_luma": {}, "sun_weather_opacity": {}, "sun_time_positions": {}, "pixel_deltas": {}}
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 600)
	OS.low_processor_usage_mode = false
	var output_path := ProjectSettings.globalize_path("res://.local/qa/back-mountain-environment-v1")
	DirAccess.make_dir_recursive_absolute(output_path)

	var packed := load(SCENE_PATH) as PackedScene
	_env_check(packed != null, "standalone scene loads for Environment v1 rendering")
	if packed == null:
		await _finish_environment_v1()
		return
	game = packed.instantiate() as Control
	root.add_child(game)
	await process_frame
	await process_frame
	_env_check(game.state != null and game.environment_presenter != null and game.environment_adapter != null, "scene exposes state, presenter, and real material adapter")
	if game.state == null or game.environment_presenter == null or game.environment_adapter == null:
		await _finish_environment_v1()
		return

	var renderer_method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
	var adapter := RenderingServer.get_video_adapter_name()
	var display_server := DisplayServer.get_name()
	report.renderer = {"method_setting": renderer_method, "adapter": adapter, "display_server": display_server}
	report.window_size = [960, 600]
	_env_check(renderer_method.to_lower().contains("compat"), "render branch runs with the Compatibility renderer setting")
	_env_check(display_server.to_lower() != "headless", "render branch has a real windowed display server")
	_env_check(not adapter.is_empty(), "rendering adapter identity is available")
	_env_check(root.size == Vector2i(960, 600), "render window is configured to 960x600")
	# Verify rendered pixel dimensions on every Image capture below; the initial
	# ViewportTexture metadata can still reflect the previous window size.

	game.qa_motion_paused = true
	game.set_lighting(false)
	game.set_process(false)
	game.set_dynamic(true)
	game.seek_presentation(5.0)
	game.set_dynamic(false)
	game.environment_presenter.finish_transition()
	game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
	game.environment_adapter.sync_motion(game.presentation_time)
	await process_frame
	await RenderingServer.frame_post_draw
	_env_check(not game.lighting_enabled and not game.dynamic_enabled and game.qa_motion_paused, "scene is frozen in static mode with Lighting disabled")
	_env_check(_env_controls_fit([game.actor_hotspot, game.sword_hotspot, game.reset_button, game.dynamic_button, game.lighting_button, game.night_button] + game.weather_buttons.values()), "training and environment controls fit the 960x600 window")
	_env_check(game.environment_presenter.time_profile_id == "mao" and is_equal_approx(game.presentation_time, 5.0), "render clock is deterministically sought to five seconds at Mao")

	var expected_weather_ids := ["clear", "cloudy", "light_rain"]
	var weather_ids := _env_sorted_keys(game.weather_buttons)
	_env_check(weather_ids == expected_weather_ids, "viewport QA sees the three configured weather buttons")
	var state_before_clicks := _env_state_snapshot(game.state)
	var nonclock_before_clicks := _env_without_time_index(state_before_clicks)
	var time_profiles := ["mao", "wu", "you"]
	var fixture_number := 1
	var filename_for_weather := {"clear": "clear", "cloudy": "cloudy", "light_rain": "rain"}
	var time_mapping: Dictionary = game.environment_config.get("time_mapping", {})
	for profile_id in time_profiles:
		var fixture_index := _env_time_index_for_profile(profile_id, time_mapping, game.state.rules.times)
		_env_check(fixture_index >= 0, "real DemoState time fixture exists for %s" % profile_id)
		if fixture_index < 0:
			continue
		game.state.time_index = fixture_index
		game._refresh_hud()
		game.refresh_environment(false)
		game.environment_presenter.finish_transition()
		game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
		_env_check(game.environment_presenter.time_profile_id == profile_id, "render fixture selects actual DemoState %s time" % profile_id)
		var weather_frames: Dictionary = {}
		for weather_id in expected_weather_ids:
			var weather_button: Button = game.weather_buttons[weather_id]
			await _env_click(weather_button)
			_env_check(game.environment_presenter.weather_id == weather_id, "viewport click selects %s weather" % weather_id)
			game.environment_presenter.finish_transition()
			game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
			_env_check(_env_without_time_index(_env_state_snapshot(game.state)) == nonclock_before_clicks, "weather click preserves all non-clock DemoState and tea fields")
			var settled_environment: Dictionary = game.environment_presenter.get_current_environment()
			var settled_sun_opacity := float(settled_environment.get("sun_opacity", -1.0))
			var weather_profiles: Dictionary = game.environment_config.get("weather_profiles", {})
			var weather_profile: Dictionary = weather_profiles.get(weather_id, {})
			var sun_visibility := float(weather_profile.get("sun_visibility", -1.0))
			report.sun_weather_opacity[profile_id + "_" + weather_id] = {"sun_visibility": sun_visibility, "sun_opacity": settled_sun_opacity}
			if weather_id == "clear":
				_env_check(is_equal_approx(sun_visibility, 1.0) and settled_sun_opacity > 0.0, "%s clear has full visibility and nonzero time-driven sun opacity" % profile_id)
			else:
				_env_check(is_zero_approx(sun_visibility) and is_zero_approx(settled_sun_opacity), "%s %s fully hides the sun" % [profile_id, weather_id])
			var screenshot_name := "%02d_%s_%s.png" % [fixture_number, profile_id, filename_for_weather[weather_id]]
			var weather_image: Image = await _env_capture(screenshot_name)
			weather_frames[weather_id] = weather_image
			if profile_id == "mao" and weather_id == "clear":
				# Reuse the real Mao/clear viewport capture, then change only the sun
				# opacity uniform to prove the painted sun contributes visible pixels.
				var sun_material: ShaderMaterial = game.environment_adapter.sun_material
				var sun_parameter_on := float(sun_material.get_shader_parameter("sun_opacity"))
				_env_check(is_equal_approx(sun_parameter_on, settled_sun_opacity), "sun shader opacity matches the stable Mao/clear presenter output")
				sun_material.set_shader_parameter("sun_opacity", 0.0)
				var sun_off_image: Image = await _env_capture("sun_uniform_off.png")
				var sun_world_delta := _env_image_delta(_crop_art(weather_image), _crop_art(sun_off_image))
				var sun_header_delta := _env_image_delta(_crop(weather_image, _env_header_rect(weather_image)), _crop(sun_off_image, _env_header_rect(sun_off_image)))
				var sun_footer_delta := _env_image_delta(_crop(weather_image, _env_footer_rect(weather_image)), _crop(sun_off_image, _env_footer_rect(sun_off_image)))
				var sun_face_delta := _env_image_delta(_env_crop_actor_face(weather_image), _env_crop_actor_face(sun_off_image))
				report.pixel_deltas["sun_opacity_only"] = {
					"world_art": sun_world_delta,
					"header_ui": sun_header_delta,
					"footer_ui": sun_footer_delta,
					"actor_face_patch": sun_face_delta,
					"sun_opacity_on": sun_parameter_on,
					"sun_opacity_off": 0.0,
					"on_capture": screenshot_name,
					"off_capture": "sun_uniform_off.png",
				}
				_env_check(int(sun_world_delta.changed_pixels) > 200, "sun_opacity alone changes more than 200 rendered art pixels (changed %d)" % int(sun_world_delta.changed_pixels))
				_env_check(int(sun_header_delta.changed_pixels) == 0 and int(sun_footer_delta.changed_pixels) == 0, "sun_opacity alone leaves header and footer UI pixel-identical")
				_env_check(int(sun_face_delta.changed_pixels) == 0, "sun_opacity alone leaves the actor face patch pixel-identical")
				sun_material.set_shader_parameter("sun_opacity", sun_parameter_on)
				await RenderingServer.frame_post_draw
			fixture_number += 1
		var clear_luma := _env_mean_luma(_crop_art(weather_frames["clear"]))
		var cloudy_luma := _env_mean_luma(_crop_art(weather_frames["cloudy"]))
		var rain_luma := _env_mean_luma(_crop_art(weather_frames["light_rain"]))
		var clear_to_cloudy := clear_luma - cloudy_luma
		var cloudy_to_rain := cloudy_luma - rain_luma
		report.world_weather_luma[profile_id] = {
			"region": "full rendered ArtArea crop, excluding header and footer UI",
			"clear": clear_luma,
			"cloudy": cloudy_luma,
			"light_rain": rain_luma,
			"clear_minus_cloudy": clear_to_cloudy,
			"cloudy_minus_light_rain": cloudy_to_rain,
			"minimum_adjacent_gap": 0.035,
		}
		_env_check(clear_luma > cloudy_luma and cloudy_luma > rain_luma, "%s rendered world luma orders clear > cloudy > light rain" % profile_id)
		_env_check(clear_to_cloudy >= 0.035 and cloudy_to_rain >= 0.035, "%s rendered world luma gaps are each at least 0.035 (clear/cloudy %.4f, cloudy/rain %.4f)" % [profile_id, clear_to_cloudy, cloudy_to_rain])

	# Check all six true rules-time fixtures to ensure their settled sun centers
	# follow the time profiles, rather than depending on a hard-coded noon sun.
	var sun_centers: Array[Vector2] = []
	var rules_times: Array = game.state.rules.times
	for time_index in range(rules_times.size()):
		var time_label := str(rules_times[time_index])
		var sun_profile_id := str(time_mapping.get(time_label, ""))
		_env_check(not sun_profile_id.is_empty(), "sun position fixture maps actual rules time %s" % time_label)
		game.state.time_index = time_index
		game._refresh_hud()
		game.refresh_environment(false)
		game.environment_presenter.finish_transition()
		game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
		await _env_select_weather_and_settle("clear")
		var sun_environment: Dictionary = game.environment_presenter.get_current_environment()
		var sun_center := Vector2(float(sun_environment.get("sun_x", -1.0)), float(sun_environment.get("sun_y", -1.0)))
		sun_centers.append(sun_center)
		report.sun_time_positions[sun_profile_id] = {"sun_x": sun_center.x, "sun_y": sun_center.y}
	var unique_sun_centers: Array[Vector2] = []
	for sun_center in sun_centers:
		if not unique_sun_centers.has(sun_center):
			unique_sun_centers.append(sun_center)
	_env_check(sun_centers.size() == rules_times.size() and unique_sun_centers.size() == rules_times.size(), "all six settled true-time profiles use distinct normalized sun centers")

	# Exercise the visible dynamic control, then prove the real process path keeps
	# motion uniforms fixed while static mode is selected.
	var state_before_dynamic := _env_state_snapshot(game.state)
	await _env_click(game.dynamic_button)
	_env_check(game.dynamic_enabled, "dynamic button enables motion through viewport input")
	_env_check(_env_state_snapshot(game.state) == state_before_dynamic, "dynamic button preserves the full DemoState and tea state")
	await _env_click(game.dynamic_button)
	_env_check(not game.dynamic_enabled, "dynamic button returns to static mode through viewport input")
	game.environment_presenter.finish_transition()
	game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
	var frozen_motion := _env_motion_uniforms()
	game.set_process(true)
	for _frame in 4:
		await process_frame
	var held_motion := _env_motion_uniforms()
	game.set_process(false)
	_env_check(frozen_motion == held_motion, "static mode freezes cloud, rain, and cloud-shadow motion uniforms across real frames")
	_env_check(_env_state_snapshot(game.state) == state_before_dynamic, "static-mode process frames preserve the full DemoState and tea state")
	var static_hold_a: Image = await _env_capture("static_hold_a.png")
	var static_hold_b: Image = await _env_capture("static_hold_b.png")
	_env_check(_pixel_delta(static_hold_a, static_hold_b).changed_samples == 0, "frozen static viewport produces identical consecutive frames")

	# The night control is a real UI click from a clear scene. It must hide the
	# sun while leaving the cultivation clock and every other state property alone.
	await _env_select_weather_and_settle("clear")
	var state_before_night := _env_state_snapshot(game.state)
	var state_time_before_night: String = game.state.time_text()
	var clear_sun_environment: Dictionary = game.environment_presenter.get_current_environment()
	_env_check(float(clear_sun_environment.get("sun_opacity", 0.0)) > 0.0, "clear sky exposes the time-driven sun before night preview")
	await _env_click(game.night_button)
	_env_check(game.environment_presenter.night_preview, "night preview control toggles through viewport input")
	_env_check(game.state.time_text() == state_time_before_night and _env_state_snapshot(game.state) == state_before_night, "night preview preserves the full state and rules clock")
	game.environment_presenter.finish_transition()
	game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
	var night_environment: Dictionary = game.environment_presenter.get_current_environment()
	_env_check(is_zero_approx(float(night_environment.get("sun_opacity", -1.0))), "night preview fully hides the sun")
	report.sun_weather_opacity["night_preview_clear"] = float(night_environment.get("sun_opacity", -1.0))
	await _env_capture("10_night_preview.png")
	await _env_click(game.night_button)
	game.environment_presenter.finish_transition()
	game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
	_env_check(not game.environment_presenter.night_preview, "second night control click exits preview")
	_env_check(float(game.environment_presenter.get_current_environment().get("sun_opacity", 0.0)) > 0.0, "exiting night preview restores the clear time-profile sun")

	# Capture rain moving through the real shader at two deterministic dynamic
	# times, then return the static presentation clock to five seconds.
	await _env_select_weather_and_settle("light_rain")
	game.set_dynamic(true)
	game.seek_presentation(5.0)
	var rain_time_five: float = game.environment_adapter.rain_material.get_shader_parameter("rain_time")
	var rain_motion_five: Image = await _env_capture("rain_motion_t5.png")
	game.seek_presentation(10.0)
	var rain_time_ten: float = game.environment_adapter.rain_material.get_shader_parameter("rain_time")
	var rain_motion_ten: Image = await _env_capture("rain_motion_t10.png")
	var rain_motion_delta := _pixel_delta(_crop_art(rain_motion_five), _crop_art(rain_motion_ten))
	report.pixel_deltas["rain_motion_t5_to_t10"] = rain_motion_delta
	_env_check(not game.lighting_enabled and float(game.environment_presenter.get_current_environment().rain_amount) > 0.0, "rain motion captures use light rain with Lighting disabled")
	_env_check(is_equal_approx(rain_time_five, 5.0) and is_equal_approx(rain_time_ten, 10.0), "rain shader clock follows deterministic dynamic seeks")
	_env_check(int(rain_motion_delta.changed_samples) > 0, "rain and mountain art change between rendered dynamic clock frames")
	game.seek_presentation(5.0)
	game.set_dynamic(false)
	var frozen_rain_time: float = game.environment_adapter.rain_material.get_shader_parameter("rain_time")
	for _frame in 3:
		await process_frame
	_env_check(is_equal_approx(float(game.environment_adapter.rain_material.get_shader_parameter("rain_time")), frozen_rain_time), "static mode freezes the rain clock after dynamic render captures")

	# Hold every scene uniform and presentation state fixed while changing only
	# the rain shader clock. This isolates moving rain from cloud, shadow, and tint.
	var rain_time_only_before: float = game.environment_adapter.rain_material.get_shader_parameter("rain_time")
	var motion_uniforms_before_rain_seek := _env_motion_uniforms()
	var rain_only_t5: Image = await _env_capture("rain_only_motion_t5.png")
	game.environment_adapter.rain_material.set_shader_parameter("rain_time", 10.0)
	var rain_only_t10: Image = await _env_capture("rain_only_motion_t10.png")
	var rain_only_motion_delta := _env_image_delta(
		_crop_art_rect(rain_only_t5, Rect2(Vector2.ZERO, Vector2(1440.0, 445.0))),
		_crop_art_rect(rain_only_t10, Rect2(Vector2.ZERO, Vector2(1440.0, 445.0))))
	var motion_uniforms_after_rain_seek := _env_motion_uniforms()
	report.pixel_deltas["rain_time_only_t5_to_t10"] = rain_only_motion_delta
	_env_check(_env_nonrain_motion_uniforms_equal(motion_uniforms_before_rain_seek, motion_uniforms_after_rain_seek), "rain-only time pair holds cloud and cloud-shadow clocks fixed")
	_env_check(int(rain_only_motion_delta.changed_pixels) > 100, "changing only rain_time moves more than 100 rendered pixels in the rain region (changed %d)" % int(rain_only_motion_delta.changed_pixels))
	game.environment_adapter.rain_material.set_shader_parameter("rain_time", rain_time_only_before)
	await RenderingServer.frame_post_draw

	# Isolate rain visibility at one frozen rendered frame. Only rain_amount is
	# changed between these captures; check that UI and the actor's opaque face
	# patch remain bit-for-bit identical while the rain region visibly changes.
	var rain_amount_on: float = game.environment_adapter.rain_material.get_shader_parameter("rain_amount")
	var rain_uniforms_before_toggle := _env_motion_uniforms()
	var rain_on_image: Image = await _env_capture("rain_uniform_on.png")
	game.environment_adapter.rain_material.set_shader_parameter("rain_amount", 0.0)
	var rain_off_image: Image = await _env_capture("rain_uniform_off.png")
	var rain_amount_region := Rect2(Vector2.ZERO, Vector2(1440.0, 445.0))
	var rain_amount_delta := _env_image_delta(
		_crop_art_rect(rain_on_image, rain_amount_region),
		_crop_art_rect(rain_off_image, rain_amount_region))
	var header_rect := _env_header_rect(rain_on_image)
	var footer_rect := _env_footer_rect(rain_on_image)
	var header_delta := _env_image_delta(_crop(rain_on_image, header_rect), _crop(rain_off_image, header_rect))
	var footer_delta := _env_image_delta(_crop(rain_on_image, footer_rect), _crop(rain_off_image, footer_rect))
	var actor_face_on := _env_crop_actor_face(rain_on_image)
	var actor_face_off := _env_crop_actor_face(rain_off_image)
	var actor_face_delta := _env_image_delta(actor_face_on, actor_face_off)
	var rain_uniforms_after_toggle := _env_motion_uniforms()
	report.pixel_deltas["rain_amount_only"] = {
		"world_rain_region": rain_amount_delta,
		"header_ui": header_delta,
		"footer_ui": footer_delta,
		"actor_face_patch": actor_face_delta,
		"rain_amount_on": rain_amount_on,
		"rain_amount_off": 0.0,
		"rain_region_art_rect": [0, 0, 1440, 445],
		"actor_face_local_rect": [170, 104, 38, 32],
	}
	_env_check(rain_amount_on > 0.0, "rain-only visibility pair starts with nonzero rendered rain amount")
	_env_check(int(rain_amount_delta.changed_pixels) > 100, "rain_amount alone changes more than 100 rendered pixels in the rain region (changed %d)" % int(rain_amount_delta.changed_pixels))
	_env_check(int(header_delta.changed_pixels) == 0 and int(footer_delta.changed_pixels) == 0, "rain_amount alone leaves the complete header and footer UI pixel-identical")
	_env_check(int(actor_face_delta.changed_pixels) == 0, "rain_amount alone leaves the actor's opaque face patch pixel-identical")
	_env_check(rain_uniforms_before_toggle == rain_uniforms_after_toggle, "rain_amount comparison holds all cloud, rain-time, and cloud-shadow motion uniforms fixed")
	game.environment_adapter.rain_material.set_shader_parameter("rain_amount", rain_amount_on)
	await RenderingServer.frame_post_draw

	# A clear-to-cloudy weather change must fade the sun from its current visible
	# value over the existing eight-second blend instead of hiding it immediately.
	await _env_select_weather_and_settle("clear")
	var clear_sun_frame: Dictionary = game.environment_presenter.get_current_environment().duplicate(true)
	var clear_sun_start := float(clear_sun_frame.get("sun_opacity", -1.0))
	await _env_click(game.weather_buttons["cloudy"])
	_env_check(game.environment_presenter.get_current_environment() == clear_sun_frame, "clear-to-cloudy sun transition starts without a frame jump")
	var clear_sun_target := float(game.environment_presenter.get_target_environment().get("sun_opacity", -1.0))
	_env_check(clear_sun_start > 0.0 and is_zero_approx(clear_sun_target), "clear-to-cloudy sun fade targets hidden")
	game.environment_presenter.advance(4.0)
	var clear_cloudy_mid_environment: Dictionary = game.environment_presenter.get_current_environment()
	var clear_cloudy_sun_mid := float(clear_cloudy_mid_environment.get("sun_opacity", -1.0))
	game.environment_adapter.apply_environment(clear_cloudy_mid_environment)
	_env_check(clear_cloudy_sun_mid > clear_sun_target and clear_cloudy_sun_mid < clear_sun_start, "clear-to-cloudy midpoint sun opacity fades without a jump")
	_env_check(is_equal_approx(float(game.environment_adapter.sun_material.get_shader_parameter("sun_opacity")), clear_cloudy_sun_mid), "clear-to-cloudy midpoint sun opacity reaches the rendered shader")
	report.sun_weather_opacity["clear_to_cloudy_midpoint"] = clear_cloudy_sun_mid
	await _env_capture("sun_clear_to_cloudy_mid.png")

	# Interrupt each weather blend halfway to clear. The source frame must remain
	# continuous when the target changes, and each real viewport state is saved.
	await _env_select_weather_and_settle("cloudy")
	var cloudy_frame: Dictionary = game.environment_presenter.get_current_environment().duplicate(true)
	await _env_click(game.weather_buttons["clear"])
	_env_check(game.environment_presenter.get_current_environment() == cloudy_frame, "cloudy-to-clear transition begins without a frame jump")
	var cloudy_sun_start := float(game.environment_presenter.get_current_environment().get("sun_opacity", -1.0))
	var cloudy_sun_target := float(game.environment_presenter.get_target_environment().get("sun_opacity", -1.0))
	_env_check(is_zero_approx(cloudy_sun_start) and cloudy_sun_target > 0.0, "cloudy-to-clear sun fade starts hidden and targets visible")
	game.environment_presenter.advance(4.0)
	var cloudy_mid_environment: Dictionary = game.environment_presenter.get_current_environment()
	var cloudy_sun_mid := float(cloudy_mid_environment.get("sun_opacity", -1.0))
	game.environment_adapter.apply_environment(cloudy_mid_environment)
	_env_check(game.environment_presenter.get_current_environment() != game.environment_presenter.get_target_environment(), "cloudy-to-clear capture is midway through its eight-second blend")
	_env_check(cloudy_sun_mid > cloudy_sun_start and cloudy_sun_mid < cloudy_sun_target, "cloudy-to-clear midpoint sun opacity fades without a jump")
	_env_check(is_equal_approx(float(game.environment_adapter.sun_material.get_shader_parameter("sun_opacity")), cloudy_sun_mid), "cloudy-to-clear midpoint sun opacity reaches the rendered shader")
	report.sun_weather_opacity["cloudy_to_clear_midpoint"] = cloudy_sun_mid
	await _env_capture("11_cloudy_to_clear_mid.png")

	await _env_select_weather_and_settle("light_rain")
	var rain_frame: Dictionary = game.environment_presenter.get_current_environment().duplicate(true)
	await _env_click(game.weather_buttons["clear"])
	_env_check(game.environment_presenter.get_current_environment() == rain_frame, "rain-to-clear transition begins without a frame jump")
	var rain_sun_start := float(game.environment_presenter.get_current_environment().get("sun_opacity", -1.0))
	var rain_sun_target := float(game.environment_presenter.get_target_environment().get("sun_opacity", -1.0))
	_env_check(is_zero_approx(rain_sun_start) and rain_sun_target > 0.0, "rain-to-clear sun fade starts hidden and targets visible")
	game.environment_presenter.advance(4.0)
	var rain_mid_environment: Dictionary = game.environment_presenter.get_current_environment()
	var rain_sun_mid := float(rain_mid_environment.get("sun_opacity", -1.0))
	game.environment_adapter.apply_environment(rain_mid_environment)
	_env_check(game.environment_presenter.get_current_environment() != game.environment_presenter.get_target_environment(), "rain-to-clear capture is midway through its eight-second blend")
	_env_check(rain_sun_mid > rain_sun_start and rain_sun_mid < rain_sun_target, "rain-to-clear midpoint sun opacity fades without a jump")
	_env_check(is_equal_approx(float(game.environment_adapter.sun_material.get_shader_parameter("sun_opacity")), rain_sun_mid), "rain-to-clear midpoint sun opacity reaches the rendered shader")
	report.sun_weather_opacity["rain_to_clear_midpoint"] = rain_sun_mid
	await _env_capture("12_rain_to_clear_mid.png")
	_env_check(_env_without_time_index(_env_state_snapshot(game.state)) == nonclock_before_clicks, "weather transitions preserve all non-clock DemoState and tea fields")

	# Restore a live rules state through the real reset button, then exercise the
	# actor hotspot and retain start, midpoint, and completion renderer evidence.
	var fresh_state = _env_matching_state(game.state)
	fresh_state.reset()
	await _env_click(game.reset_button)
	game.environment_presenter.finish_transition()
	game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
	_env_check(game.state.time_index == 0 and game.environment_presenter.time_profile_id == "mao", "reset button returns rules and environment to Mao")
	_env_check(_env_state_snapshot(game.state) == _env_state_snapshot(fresh_state), "reset button restores the complete fresh DemoState")
	var expected_training = _env_matching_state(game.state)
	var expected_training_result: Dictionary = expected_training.train()
	game.config.training_seconds = 1.8
	game.set_process(false)
	_push_click(game.actor_hotspot)
	await process_frame
	await process_frame
	_env_check(game.busy, "actor hotspot starts training through viewport mouse input")
	_env_check(_env_state_snapshot(game.state) == _env_state_snapshot(expected_training), "actor hotspot settles the authoritative DemoState exactly once")
	var training_time_label := str(game.state.rules.times[game.state.time_index])
	_env_check(game.environment_presenter.time_profile_id == str(time_mapping.get(training_time_label, "")), "training immediately retargets the actual new rules time")
	game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
	await _env_capture("13_training_start.png")
	game._process(0.9)
	await _env_capture("14_training_mid.png")
	game._process(1.0)
	_env_check(not game.busy and bool(game.last_result.get("ok", false)), "explicit renderer clock completes the training action")
	_env_check(int(game.last_result.get("gain", -1)) == int(expected_training_result.get("gain", -2)), "rendered training uses the rule-derived cultivation gain")
	await _env_capture("15_training_end.png")
	_env_check(_env_state_snapshot(game.state) == _env_state_snapshot(expected_training), "training transition preserves the settled state after completion")

	await _finish_environment_v1()


func _run_ambient_pose_motion_v1_1() -> void:
	failures = 0
	checks.clear()
	captures.clear()
	frame_count = 0
	report = {"checks": {}, "screenshots": [], "failures": [], "screenshot_dimensions": {}, "pixel_deltas": {}, "pose_frames": {}, "fixture_labels": {}}
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 600)
	OS.low_processor_usage_mode = false
	var output_path := ProjectSettings.globalize_path(AMBIENT_MOTION_OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)

	var packed := load(SCENE_PATH) as PackedScene
	_env_check(packed != null, "training scene loads for Ambient Life v1.1 pose rendering")
	if packed == null:
		await _finish_ambient_pose_motion_v1_1()
		return
	game = packed.instantiate() as Control
	root.add_child(game)
	await process_frame
	await process_frame
	root.size = Vector2i(960, 600)
	await process_frame
	_env_check(game.state != null and game.environment_presenter != null and game.ambient_life != null, "pose render uses the real state, Environment, and Ambient Life adapters")
	if game.state == null or game.environment_presenter == null or game.ambient_life == null:
		await _finish_ambient_pose_motion_v1_1()
		return
	var renderer_method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
	var adapter_name := RenderingServer.get_video_adapter_name()
	var display_server := DisplayServer.get_name()
	report.renderer = {"method_setting": renderer_method, "adapter": adapter_name, "display_server": display_server}
	report.window_size = [960, 600]
	_env_check(renderer_method.to_lower().contains("compat"), "pose captures use the Compatibility renderer")
	_env_check(display_server.to_lower() != "headless" and not adapter_name.is_empty(), "pose captures use a real rendered window and adapter")
	_env_check(root.size == Vector2i(960, 600), "pose render window is reset to the 960x600 viewport after scene readiness")

	game.qa_motion_paused = true
	game.set_process(false)
	game.set_lighting(false)
	game.set_dynamic(true)
	game.state.time_index = 0
	game._refresh_hud()
	game.refresh_environment(false)
	game.environment_presenter.set_weather("clear", false)
	game.environment_presenter.set_night_preview(false, false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	game.ambient_life.reset()
	var initial_state := _env_state_snapshot(game.state)
	var mao_environment := _ambient_environment_snapshot()
	var cat_root: Node2D = game.ambient_life.visual_nodes.cat
	var cat_sprite := cat_root.get_child(0) as Sprite2D
	_env_check(cat_sprite != null and cat_sprite.texture is AtlasTexture, "cat render uses its atlas sprite child")
	if cat_sprite == null or not (cat_sprite.texture is AtlasTexture):
		await _finish_ambient_pose_motion_v1_1()
		return

	_env_check(game.force_ambient_life("cat"), "clear Mao accepts a forced cat pose fixture")
	game.ambient_life.advance(1.0)
	var cat_age_1_frame := _ambient_atlas_frame(cat_sprite, 96.0)
	var cat_age_1: Image = await _env_capture("cat_age1.png", AMBIENT_MOTION_OUTPUT_DIR)
	game.ambient_life.advance(6.0)
	var cat_age_7_frame := _ambient_atlas_frame(cat_sprite, 96.0)
	var cat_age_7: Image = await _env_capture("cat_age7.png", AMBIENT_MOTION_OUTPUT_DIR)
	game.ambient_life.advance(5.2)
	var cat_age_12_2_frame := _ambient_atlas_frame(cat_sprite, 96.0)
	var cat_age_12_2: Image = await _env_capture("cat_age12_2.png", AMBIENT_MOTION_OUTPUT_DIR)
	game.ambient_life.advance(0.6)
	var cat_age_12_8_frame := _ambient_atlas_frame(cat_sprite, 96.0)
	var cat_age_12_8: Image = await _env_capture("cat_age12_8.png", AMBIENT_MOTION_OUTPUT_DIR)
	report.pose_frames.cat = {"age1": cat_age_1_frame, "age7": cat_age_7_frame, "age12_2": cat_age_12_2_frame, "age12_8": cat_age_12_8_frame}
	var cat_head_delta := _env_image_delta(_crop_art(cat_age_1), _crop_art(cat_age_7))
	var cat_tail_delta := _env_image_delta(_crop_art(cat_age_7), _crop_art(cat_age_12_2))
	report.pixel_deltas["cat_pose_timeline"] = {"age1_to_age7": cat_head_delta, "age7_to_age12_2": cat_tail_delta}
	_env_check(cat_age_1_frame == 0 and cat_age_7_frame == 2, "Mao clear cat render changes from sleeping frame to the age-seven head lift")
	_env_check(cat_age_12_2_frame == 3 and cat_age_12_8_frame == 0, "wind-driven tail flick is visible at age 12.2 and returns to sleep by 12.8")
	_env_check(int(cat_head_delta.changed_pixels) > 0 and int(cat_tail_delta.changed_pixels) > 0, "cat atlas poses visibly alter rendered pixels at the sampled ages")
	_env_check(float(game.environment_presenter.get_current_environment().get("wind_strength", 0.0)) > 0.1, "tail-pose captures use the existing clear-weather wind parameter")
	_env_check(_env_state_snapshot(game.state) == initial_state and _ambient_environment_snapshot() == mao_environment, "cat pose captures preserve every state and Environment presenter field")
	report.fixture_labels["cat_age1.png"] = "forced cat; event age 1.0, Mao clear"
	report.fixture_labels["cat_age7.png"] = "same forced cat; event age 7.0 head lift, Mao clear"
	report.fixture_labels["cat_age12_2.png"] = "same forced cat; event age 12.2 tail flick with clear wind"
	report.fixture_labels["cat_age12_8.png"] = "same forced cat; event age 12.8, tail flick ended"

	# The same age in sunny Wu remains asleep; this is a state-backed time
	# profile fixture, not a directly edited Environment value.
	game.ambient_life.reset()
	var wu_index: int = game.state.rules.times.find("午时")
	_env_check(wu_index >= 0, "DemoState provides the real Wu time fixture")
	if wu_index >= 0:
		game.state.time_index = wu_index
		game._refresh_hud()
		game.refresh_environment(false)
		game.environment_presenter.set_weather("clear", false)
		game.environment_presenter.finish_transition()
		game._apply_environment()
		var wu_state := _env_state_snapshot(game.state)
		var wu_environment := _ambient_environment_snapshot()
		_env_check(str(wu_environment.get("time_profile_id", "")) == "wu", "Wu cat sample follows the actual state-to-profile mapping")
		_env_check(game.force_ambient_life("cat"), "Wu sample accepts the same forced cat fixture")
		game.ambient_life.advance(7.0)
		var cat_wu_frame := _ambient_atlas_frame(cat_sprite, 96.0)
		await _env_capture("cat_wu_age7.png", AMBIENT_MOTION_OUTPUT_DIR)
		report.pose_frames.cat_wu_age7 = cat_wu_frame
		_env_check(cat_wu_frame == 0, "sunny Wu cat stays asleep at age seven")
		_env_check(_env_state_snapshot(game.state) == wu_state and _ambient_environment_snapshot() == wu_environment, "sunny Wu pose preserves its rules state and Environment fields")
		report.fixture_labels["cat_wu_age7.png"] = "forced cat; event age 7.0, sunny Wu sleep comparison"

	# Pose suppression is a presentation response to concurrent activity and
	# foreground attention; each frame leaves DemoState untouched.
	game.ambient_life.reset()
	game.state.time_index = 0
	game._refresh_hud()
	game.refresh_environment(false)
	game.environment_presenter.set_weather("clear", false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	var suppression_state := _env_state_snapshot(game.state)
	var suppression_environment := _ambient_environment_snapshot()
	game.force_ambient_life("cat")
	game.ambient_life.advance(7.0)
	game.ambient_life.force_event("birds")
	var quick_suppressed_frame := _ambient_atlas_frame(cat_sprite, 96.0)
	await _env_capture("cat_quick_suppressed.png", AMBIENT_MOTION_OUTPUT_DIR)
	report.pose_frames.cat_quick_suppressed = quick_suppressed_frame
	_env_check(quick_suppressed_frame == 0 and game.ambient_life.presenter.get_active_events().has("cat"), "bird pass suppresses the cat pose while leaving its event active")
	game.ambient_life.reset()
	game.force_ambient_life("cat")
	game.ambient_life.advance(7.0)
	game.busy = true
	game.ambient_life.advance(0.0)
	var busy_suppressed_frame := _ambient_atlas_frame(cat_sprite, 96.0)
	await _env_capture("cat_busy_suppressed.png", AMBIENT_MOTION_OUTPUT_DIR)
	game.busy = false
	report.pose_frames.cat_busy_suppressed = busy_suppressed_frame
	_env_check(busy_suppressed_frame == 0, "foreground busy state suppresses the rendered cat pose")
	_env_check(_env_state_snapshot(game.state) == suppression_state and _ambient_environment_snapshot() == suppression_environment, "quick-event and busy captures preserve all state and Environment fields")

	game.ambient_life.reset()
	game.force_ambient_life("cat")
	game.ambient_life.advance(7.0)
	game.set_dynamic(false)
	var cat_static_frame := _ambient_atlas_frame(cat_sprite, 96.0)
	var cat_static_scale := cat_sprite.scale
	await _env_capture("cat_dynamic_off.png", AMBIENT_MOTION_OUTPUT_DIR)
	report.pose_frames.cat_dynamic_off = cat_static_frame
	_env_check(cat_static_frame == 0 and cat_root.visible, "dynamic off holds a visible cat on its frame-zero static pose")
	_env_check(cat_static_scale == Vector2.ONE * float(game.ambient_life.config.visuals.cat_scale), "dynamic-off cat restores its baseline sprite scale")
	game.set_dynamic(true)

	game.ambient_life.reset()
	game.ambient_life.force_event("squirrel")
	var squirrel_root: Node2D = game.ambient_life.visual_nodes.squirrel
	var squirrel_sprite := squirrel_root.get_child(0) as Sprite2D
	var squirrel_state_before := _env_state_snapshot(game.state)
	var squirrel_environment_before := _ambient_environment_snapshot()
	_env_check(squirrel_sprite != null and squirrel_sprite.texture is AtlasTexture, "squirrel render uses its atlas sprite child")
	if squirrel_sprite == null or not (squirrel_sprite.texture is AtlasTexture):
		await _finish_ambient_pose_motion_v1_1()
		return
	game.ambient_life.advance(0.5)
	var squirrel_early_frame := _ambient_atlas_frame(squirrel_sprite, 68.0)
	var squirrel_early: Image = await _env_capture("squirrel_early.png", AMBIENT_MOTION_OUTPUT_DIR)
	game.ambient_life.advance(0.5)
	var squirrel_run_frame := _ambient_atlas_frame(squirrel_sprite, 68.0)
	var squirrel_run: Image = await _env_capture("squirrel_run.png", AMBIENT_MOTION_OUTPUT_DIR)
	game.ambient_life.advance(1.5)
	var squirrel_pause_frame := _ambient_atlas_frame(squirrel_sprite, 68.0)
	var squirrel_pause: Image = await _env_capture("squirrel_pause.png", AMBIENT_MOTION_OUTPUT_DIR)
	var squirrel_early_run_delta := _env_image_delta(_crop_art(squirrel_early), _crop_art(squirrel_run))
	var squirrel_run_pause_delta := _env_image_delta(_crop_art(squirrel_run), _crop_art(squirrel_pause))
	report.pose_frames.squirrel = {"age0_5": squirrel_early_frame, "age1": squirrel_run_frame, "age2_5": squirrel_pause_frame}
	report.pixel_deltas["squirrel_pose_phases"] = {"early_to_run": squirrel_early_run_delta, "run_to_pause": squirrel_run_pause_delta}
	_env_check(squirrel_early_frame >= 1 and squirrel_early_frame <= 3 and squirrel_run_frame >= 1 and squirrel_run_frame <= 3, "squirrel early and run captures use cycling run atlas frames")
	_env_check(squirrel_pause_frame == 0 and squirrel_pause_frame != squirrel_run_frame, "squirrel pause capture uses frame zero and differs from its running pose")
	_env_check(int(squirrel_early_run_delta.changed_pixels) > 0 and int(squirrel_run_pause_delta.changed_pixels) > 0, "squirrel phase changes appear in actual rendered world pixels")
	_env_check(absf(squirrel_sprite.position.y) <= 2.2 and _ambient_inside_squirrel_curve(squirrel_root.position), "squirrel bob and path position stay within their authored bounds")
	_env_check(_env_state_snapshot(game.state) == squirrel_state_before and _ambient_environment_snapshot() == squirrel_environment_before, "squirrel pose captures preserve every state and Environment presenter field")
	report.fixture_labels["squirrel_early.png"] = "forced squirrel; event age 0.5 run cycle"
	report.fixture_labels["squirrel_run.png"] = "same forced squirrel; event age 1.0 run cycle"
	report.fixture_labels["squirrel_pause.png"] = "same forced squirrel; event age 2.5 pause phase"

	game.set_dynamic(false)
	var squirrel_static_frame := _ambient_atlas_frame(squirrel_sprite, 68.0)
	var squirrel_static_scale := squirrel_sprite.scale
	await _env_capture("squirrel_dynamic_off.png", AMBIENT_MOTION_OUTPUT_DIR)
	_env_check(not squirrel_root.visible and squirrel_static_frame == 0 and squirrel_sprite.position.y == 0.0, "dynamic-off hides squirrel and restores frame-zero pose with no bob")
	_env_check(squirrel_static_scale == Vector2.ONE * float(game.ambient_life.config.visuals.squirrel_scale), "dynamic-off squirrel restores its baseline scale")

	await _finish_ambient_pose_motion_v1_1()


func _ambient_atlas_frame(sprite: Sprite2D, frame_width: float) -> int:
	var texture := sprite.texture as AtlasTexture
	if texture == null or frame_width <= 0.0:
		return -1
	return roundi(texture.region.position.x / frame_width)


func _ambient_inside_squirrel_curve(point: Vector2) -> bool:
	var path := game._art_root.get_node("AmbientCapabilities/SquirrelPath") as Path2D
	if path == null or path.curve == null:
		return false
	var baked := path.curve.get_baked_points()
	if baked.is_empty():
		return false
	var minimum := baked[0]
	var maximum := baked[0]
	for sample in baked:
		minimum.x = minf(minimum.x, sample.x)
		minimum.y = minf(minimum.y, sample.y)
		maximum.x = maxf(maximum.x, sample.x)
		maximum.y = maxf(maximum.y, sample.y)
	return Rect2(minimum, maximum - minimum).grow(1.0).has_point(point)


func _finish_ambient_pose_motion_v1_1() -> void:
	report.checks = checks
	report.failure_count = failures
	report.captured_frames = frame_count
	var report_path := ProjectSettings.globalize_path(AMBIENT_MOTION_OUTPUT_DIR.path_join("report.json"))
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ") + "\n")
	else:
		push_error("could not write Ambient Life v1.1 pose report: " + report_path)
		failures += 1
	print("BACK_MOUNTAIN_AMBIENT_POSE_MOTION: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _run_ambient_life_v1() -> void:
	failures = 0
	checks.clear()
	captures.clear()
	frame_count = 0
	report = {"checks": {}, "screenshots": [], "failures": [], "screenshot_dimensions": {}, "pixel_deltas": {}, "fixture_labels": {}}
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 600)
	OS.low_processor_usage_mode = false
	var output_path := ProjectSettings.globalize_path(AMBIENT_OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)

	var packed := load(SCENE_PATH) as PackedScene
	_env_check(packed != null, "standalone scene loads for Ambient Life v1 real rendering")
	if packed == null:
		await _finish_ambient_life_v1()
		return
	game = packed.instantiate() as Control
	root.add_child(game)
	await process_frame
	await process_frame
	_env_check(game.state != null and game.environment_presenter != null and game.environment_adapter != null, "existing state and Environment v1 remain available beside Ambient Life")
	_env_check(game.ambient_life != null and game.ambient_life.presenter != null and game.ambient_life.visual_nodes is Dictionary, "scene exposes the Ambient Life adapter, presenter, and rendered roots")
	if game.state == null or game.environment_presenter == null or game.ambient_life == null:
		await _finish_ambient_life_v1()
		return

	var renderer_method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
	var adapter_name := RenderingServer.get_video_adapter_name()
	var display_server := DisplayServer.get_name()
	report.renderer = {"method_setting": renderer_method, "adapter": adapter_name, "display_server": display_server}
	report.window_size = [960, 600]
	_env_check(renderer_method.to_lower().contains("compat"), "Ambient Life render uses the Compatibility renderer setting")
	_env_check(display_server.to_lower() != "headless" and not adapter_name.is_empty(), "Ambient Life captures use a real rendered viewport and adapter")
	_env_check(root.size == Vector2i(960, 600), "Ambient Life viewport is configured to 960x600")

	game.qa_motion_paused = true
	game.set_process(false)
	game.set_lighting(false)
	game.set_dynamic(true)
	game.seek_presentation(5.0)
	game.set_weather("clear", false)
	game.set_night_preview(false, false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	game.ambient_life.reset()
	game.ambient_life.observe_environment()
	_env_check(game.dynamic_enabled and game.qa_motion_paused, "render fixtures freeze unrelated motion while Ambient Life remains eligible")
	_env_check(_env_controls_fit([game.actor_hotspot, game.sword_hotspot, game.reset_button, game.dynamic_button, game.lighting_button, game.night_button] + game.weather_buttons.values() + game.ambient_buttons.values()), "existing and Ambient Life controls fit the 960x600 viewport")
	_env_check(game.ambient_buttons.has_all(["toggle", "birds", "squirrel", "cat", "auto"]), "viewport exposes toggle, forced-event, and automatic-schedule controls")
	var markers: Node2D = game._art_root.get_node_or_null("AmbientCapabilities") as Node2D
	_env_check(markers != null and game.ambient_life.get_capabilities().birds and game.ambient_life.get_capabilities().squirrel and game.ambient_life.get_capabilities().cat, "render fixture uses scene-discovered bird, squirrel, and cat markers")
	if markers == null or not game.ambient_buttons.has("toggle") or not game.ambient_buttons.has("birds"):
		await _finish_ambient_life_v1()
		return

	# Begin with an explicitly empty scene. Every named event capture below is a
	# forced, labeled fixture; natural scheduling is exercised separately by the
	# seeded headless integration check, not presented as a short render sample.
	game.set_ambient_life(false)
	var no_life_image: Image = await _env_capture("01_base_no_life.png", AMBIENT_OUTPUT_DIR)
	report.fixture_labels["01_base_no_life.png"] = "no ambient events; scene markers remain authored"
	await _env_click(game.ambient_buttons.toggle)
	_env_check(game.ambient_life.presenter.enabled, "ambient life toggle enables the scheduler through viewport input")
	var initial_state := _env_state_snapshot(game.state)
	var initial_environment := _ambient_environment_snapshot()

	await _env_click(game.ambient_buttons.birds)
	var bird_events: Dictionary = game.ambient_life.presenter.get_active_events()
	_env_check(bird_events.has("birds") and bool(bird_events.birds.get("forced", false)), "bird button creates a clearly forced event through viewport input")
	_env_check(game.ambient_life.visual_nodes.birds.visible, "forced bird event has a visible rendered root")
	# Compare two visible flight times: tiny distant silhouettes need not cover
	# an arbitrary minimum area, but must visibly move while other clocks hold.
	game.ambient_life.advance(3.0)
	var bird_position_before: Vector2 = game.ambient_life.visual_nodes.birds.position
	var birds_before: Image = await _env_capture("02_birds_motion_start.png", AMBIENT_OUTPUT_DIR)
	game.ambient_life.advance(3.0)
	var birds_after: Image = await _env_capture("02_birds.png", AMBIENT_OUTPUT_DIR)
	var bird_motion_delta := _env_image_delta(_crop_art(birds_before), _crop_art(birds_after))
	var bird_actor_delta := _env_image_delta(_env_crop_actor_face(birds_before), _env_crop_actor_face(birds_after))
	var bird_header_delta := _env_image_delta(_crop(birds_before, _env_header_rect(birds_before)), _crop(birds_after, _env_header_rect(birds_after)))
	var bird_footer_delta := _env_image_delta(_crop(birds_before, _env_footer_rect(birds_before)), _crop(birds_after, _env_footer_rect(birds_after)))
	report.pixel_deltas["bird_forced_motion"] = {"world": bird_motion_delta, "actor_face": bird_actor_delta, "header": bird_header_delta, "footer": bird_footer_delta}
	_env_check(game.ambient_life.visual_nodes.birds.position.distance_to(bird_position_before) > 100.0, "bird group traverses more than 100 art-coordinate pixels along the authored sky lane")
	_env_check(int(bird_motion_delta.changed_pixels) > 0, "tiny distant bird motion changes actual rendered world pixels while other clocks hold (changed %d)" % int(bird_motion_delta.changed_pixels))
	_env_check(int(bird_actor_delta.changed_pixels) == 0, "bird motion leaves the actor face patch pixel-identical")
	_env_check(int(bird_header_delta.changed_pixels) == 0 and int(bird_footer_delta.changed_pixels) == 0, "bird motion leaves header and footer UI pixel-identical")
	_env_check(_env_state_snapshot(game.state) == initial_state and _ambient_environment_snapshot() == initial_environment, "forced bird time and rendering preserve all DemoState and Environment presenter fields")
	report.fixture_labels["02_birds.png"] = "forced birds; manual adapter advance, all other clocks frozen"

	await _env_click(game.ambient_buttons.squirrel)
	var squirrel_events: Dictionary = game.ambient_life.presenter.get_active_events()
	_env_check(squirrel_events.has("squirrel") and bool(squirrel_events.squirrel.get("forced", false)), "squirrel button creates a forced event through viewport input")
	game.ambient_life.advance(0.7)
	var squirrel_early: Image = await _env_capture("03_squirrel_early.png", AMBIENT_OUTPUT_DIR)
	game.ambient_life.advance(1.8)
	var squirrel_middle: Image = await _env_capture("03_squirrel_middle.png", AMBIENT_OUTPUT_DIR)
	game.ambient_life.advance(1.7)
	var squirrel_after: Image = await _env_capture("03_squirrel.png", AMBIENT_OUTPUT_DIR)
	var squirrel_early_delta := _env_image_delta(_crop_art(squirrel_early), _crop_art(squirrel_middle))
	var squirrel_late_delta := _env_image_delta(_crop_art(squirrel_middle), _crop_art(squirrel_after))
	report.pixel_deltas["squirrel_forced_motion"] = {"early_to_middle": squirrel_early_delta, "middle_to_late": squirrel_late_delta}
	_env_check(int(squirrel_early_delta.changed_pixels) > 100, "squirrel moves during its early branch traversal (changed %d pixels from age 0.7 to 2.5)" % int(squirrel_early_delta.changed_pixels))
	_env_check(int(squirrel_late_delta.changed_pixels) > 100, "squirrel moves during its late branch traversal (changed %d pixels from age 2.5 to 4.2)" % int(squirrel_late_delta.changed_pixels))
	_env_check(_env_state_snapshot(game.state) == initial_state and _ambient_environment_snapshot() == initial_environment, "forced squirrel time preserves all DemoState and Environment presenter fields")
	report.fixture_labels["03_squirrel.png"] = "forced squirrel; manual adapter advance, all other clocks frozen"

	await _env_click(game.ambient_buttons.cat)
	game.ambient_life.advance(1.0)
	_env_check(game.ambient_life.presenter.get_active_events().has("cat") and game.ambient_life.visual_nodes.cat.visible, "cat button renders its forced quiet event through viewport input")
	var cat_image: Image = await _env_capture("04_cat.png", AMBIENT_OUTPUT_DIR)
	var cat_actor_delta := _env_image_delta(_env_crop_actor_face(birds_after), _env_crop_actor_face(cat_image))
	report.pixel_deltas["cat_actor_face_unchanged"] = cat_actor_delta
	_env_check(int(cat_actor_delta.changed_pixels) == 0, "cat rendering leaves the actor face patch unchanged")
	report.fixture_labels["04_cat.png"] = "forced cat on the authored clear-weather sunny rock spot"
	await _env_click(game.ambient_buttons.auto)
	_env_check(game.ambient_life.presenter.auto_enabled and game.ambient_life.presenter.get_active_events().is_empty(), "resume-auto button clears forced previews and restores automatic scheduling through viewport input")
	await _env_click(game.ambient_buttons.toggle)
	_env_check(not game.ambient_life.presenter.enabled and _env_state_snapshot(game.state) == initial_state and _ambient_environment_snapshot() == initial_environment, "ambient-off button disables life through viewport input without changing state or Environment")
	await _env_click(game.ambient_buttons.toggle)

	# Natural-state captures use the checked-in seed and a controlled life clock.
	# Forced examples above remain separate and explicitly labeled.
	game.ambient_life.reset()
	game.ambient_life.observe_environment()
	game._update_ambient_controls()
	report.scheduler_seed = int(game.ambient_life.config.get("seed", -1))
	report.auto_search_limit_seconds = 240.0
	var clear_environment_before_auto := _ambient_environment_snapshot()
	var clear_auto := await _ambient_wait_for_auto_event(240.0)
	report.natural_events = []
	if not clear_auto.is_empty():
		report.natural_events.append({"weather": "clear", "kind": clear_auto.kind, "elapsed": clear_auto.elapsed, "event_age": clear_auto.event_age, "forced": false})
	var clear_life_image: Image = await _env_capture("05_clear_life.png", AMBIENT_OUTPUT_DIR)
	_env_check(not clear_auto.is_empty() and not bool(clear_auto.event.get("forced", true)), "clear-life capture follows a naturally scheduled event from the fixed seed")
	_env_check(not clear_auto.is_empty() and game.ambient_life.visual_nodes.has(str(clear_auto.get("kind", ""))) and game.ambient_life.visual_nodes[str(clear_auto.kind)].visible, "clear-life event is visibly rendered after its reveal age")
	_env_check(_env_state_snapshot(game.state) == initial_state and _ambient_environment_snapshot() == clear_environment_before_auto, "clear automatic intervals preserve all DemoState and Environment presenter fields")
	report.fixture_labels["05_clear_life.png"] = "clear weather; naturally scheduled seeded event (see natural_events elapsed and kind)"

	await _env_select_weather_and_settle("cloudy")
	game.ambient_life.reset()
	game.ambient_life.observe_environment()
	game._update_ambient_controls()
	var cloudy_environment_before_auto := _ambient_environment_snapshot()
	var cloudy_auto := await _ambient_wait_for_auto_event(240.0)
	if not cloudy_auto.is_empty():
		report.natural_events.append({"weather": "cloudy", "kind": cloudy_auto.kind, "elapsed": cloudy_auto.elapsed, "event_age": cloudy_auto.event_age, "forced": false})
	var cloudy_life_image: Image = await _env_capture("06_cloudy_life.png", AMBIENT_OUTPUT_DIR)
	_env_check(game.environment_presenter.weather_id == "cloudy" and not cloudy_auto.is_empty() and not bool(cloudy_auto.event.get("forced", true)), "cloudy-life capture follows a naturally scheduled event from the fixed seed")
	_env_check(not cloudy_auto.is_empty() and game.ambient_life.visual_nodes.has(str(cloudy_auto.get("kind", ""))) and game.ambient_life.visual_nodes[str(cloudy_auto.kind)].visible, "cloudy-life event is visibly rendered after its reveal age")
	_env_check(_env_state_snapshot(game.state) == initial_state and _ambient_environment_snapshot() == cloudy_environment_before_auto, "cloudy automatic intervals preserve all DemoState and Environment presenter fields")
	report.fixture_labels["06_cloudy_life.png"] = "cloudy weather; naturally scheduled seeded event (see natural_events elapsed and kind)"

	await _env_select_weather_and_settle("light_rain")
	game.ambient_life.reset()
	game.ambient_life.observe_environment()
	game._update_ambient_controls()
	var rain_state_before := _env_state_snapshot(game.state)
	_env_check(not game.ambient_life.get_capabilities().cat_sheltered, "rain render uses authored production capability: no sheltered cat spot")
	_env_check(not game.ambient_life.presenter.can_spawn("cat") and game.ambient_buttons.cat.disabled, "unsheltered authored rock gates cat scheduling during rain")
	var rain_life_baseline: Image = await _env_capture("07_light_rain_no_animals_baseline.png", AMBIENT_OUTPUT_DIR)
	_env_check(not game.force_ambient_life("cat") and not game.force_ambient_life("birds") and not game.force_ambient_life("squirrel") and game.ambient_life.presenter.get_active_events().is_empty(), "rain keeps every event hidden under the authored production markers")
	var rain_life_image: Image = await _env_capture("07_light_rain_life.png", AMBIENT_OUTPUT_DIR)
	var rain_actor_delta := _env_image_delta(_env_crop_actor_face(rain_life_baseline), _env_crop_actor_face(rain_life_image))
	var rain_world_delta := _env_image_delta(_crop_art(rain_life_baseline), _crop_art(rain_life_image))
	report.pixel_deltas["rain_no_animals"] = {"actor_face": rain_actor_delta, "world": rain_world_delta}
	_env_check(int(rain_actor_delta.changed_pixels) == 0 and int(rain_world_delta.changed_pixels) == 0 and _env_state_snapshot(game.state) == rain_state_before, "authored rain scene keeps actor/world pixels and all DemoState/tea fields unchanged after rejected forces")
	report.fixture_labels["07_light_rain_life.png"] = "light rain with authored production capabilities; no animals because the only cat spot is unsheltered"
	game.ambient_life.refresh_capabilities()
	game.ambient_life.observe_environment()
	game._update_ambient_controls()

	await _env_select_weather_and_settle("clear")
	await _env_click(game.ambient_buttons.cat)
	game.ambient_life.advance(1.0)
	await _env_click(game.ambient_buttons.birds)
	var elapsed_before_static := float(game.ambient_life.presenter.elapsed)
	await _env_click(game.dynamic_button)
	game.ambient_life.observe_environment()
	game.ambient_life.advance(3.0)
	var active_static: Dictionary = game.ambient_life.presenter.get_active_events()
	var cat_sprite := game.ambient_life.visual_nodes.cat.get_child(0) as Sprite2D
	_env_check(not game.dynamic_enabled and not game.ambient_life.visual_nodes.birds.visible and not game.ambient_life.visual_nodes.squirrel.visible, "dynamic-off control hides quick events and squirrel through viewport input")
	_env_check(active_static.has("cat") and game.ambient_life.visual_nodes.cat.visible, "dynamic off keeps an active cat in its quiet visible pose")
	_env_check(is_equal_approx(float(game.ambient_life.presenter.elapsed), elapsed_before_static) and is_equal_approx(cat_sprite.scale.x, float(game.ambient_life.config.visuals.cat_scale)) and is_equal_approx(cat_sprite.scale.y, float(game.ambient_life.config.visuals.cat_scale)), "static cat pose is frozen while the ambient clock holds")
	var static_life_image: Image = await _env_capture("08_dynamic_off.png", AMBIENT_OUTPUT_DIR)
	game.ambient_life.advance(3.0)
	var static_hold_image: Image = await _env_capture("08_dynamic_off_hold.png", AMBIENT_OUTPUT_DIR)
	var cat_static_delta := _env_image_delta(_crop_art(static_life_image), _crop_art(static_hold_image))
	report.pixel_deltas["static_cat_world_hold"] = cat_static_delta
	_env_check(int(cat_static_delta.changed_pixels) == 0, "dynamic-off world and quiet cat stay pixel-identical across frozen adapter frames")
	report.fixture_labels["08_dynamic_off.png"] = "forced cat held quietly; bird and squirrel roots hidden by dynamic-off mode"

	var before_reset = _env_matching_state(game.state)
	before_reset.reset()
	await _env_click(game.reset_button)
	game.environment_presenter.finish_transition()
	game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())
	_env_check(_env_state_snapshot(game.state) == _env_state_snapshot(before_reset), "reset button restores normal rules state and invalidates stale tea session")
	_env_check(is_zero_approx(float(game.ambient_life.presenter.elapsed)) and game.ambient_life.presenter.get_active_events().is_empty(), "reset button clears life events and resets its schedule")
	game.set_dynamic(true)
	game.set_process(false)
	var expected_training = _env_matching_state(game.state)
	var expected_training_result: Dictionary = expected_training.train()
	await _env_click(game.actor_hotspot)
	_env_check(game.busy, "actor hotspot still starts normal training after life reset")
	_env_check(_env_state_snapshot(game.state) == _env_state_snapshot(expected_training), "post-reset training changes DemoState exactly once by its normal rules")
	game._process(float(game.config.get("training_seconds", 1.8)))
	_env_check(not game.busy and bool(game.last_result.get("ok", false)) and int(game.last_result.get("gain", -1)) == int(expected_training_result.get("gain", -2)), "post-reset training completes with the rules-derived gain")
	await _env_capture("09_training_after_reset.png", AMBIENT_OUTPUT_DIR)
	report.screenshots = report.screenshots.duplicate()
	report.pixel_deltas["clear_cloudy_images"] = {"clear": clear_life_image.get_size(), "cloudy": cloudy_life_image.get_size(), "rain": rain_life_image.get_size(), "static": static_life_image.get_size(), "base": no_life_image.get_size()}

	await _finish_ambient_life_v1()


func _ambient_environment_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for property in game.environment_presenter.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property.name)
		var value: Variant = game.environment_presenter.get(name)
		result[name] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result


func _ambient_wait_for_auto_event(max_seconds: float) -> Dictionary:
	var step := 0.25
	var steps := ceili(max_seconds / step)
	for _index in steps:
		game.ambient_life.advance(step)
		var active: Dictionary = game.ambient_life.presenter.get_active_events()
		for kind in active:
			var event: Dictionary = active[kind]
			if not bool(event.get("forced", true)):
				var reveal_age := 1.2
				if str(kind) == "birds":
					reveal_age = 4.0
				game.ambient_life.advance(reveal_age)
				var revealed: Dictionary = game.ambient_life.presenter.get_active_events()
				if revealed.has(kind) and int(revealed[kind].get("serial", -1)) == int(event.get("serial", -2)):
					return {
						"kind": str(kind), "event": revealed[kind].duplicate(true),
						"elapsed": float(game.ambient_life.presenter.elapsed),
						"event_age": float(game.ambient_life.presenter.elapsed) - float(event.get("start", 0.0)),
					}
	return {}


func _finish_ambient_life_v1() -> void:
	report.checks = checks
	report.failure_count = failures
	report.captured_frames = frame_count
	var report_path := ProjectSettings.globalize_path(AMBIENT_OUTPUT_DIR.path_join("report.json"))
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ") + "\n")
	else:
		push_error("could not write Ambient Life v1 QA report: " + report_path)
		failures += 1
	print("BACK_MOUNTAIN_AMBIENT_LIFE_RENDER: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _env_select_weather_and_settle(weather_id: String) -> void:
	await _env_click(game.weather_buttons[weather_id])
	game.environment_presenter.finish_transition()
	game.environment_adapter.apply_environment(game.environment_presenter.get_current_environment())


func _env_click(control: Control) -> void:
	var point := root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
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
	await process_frame
	await process_frame


func _env_capture(filename: String, output_dir: String = "res://.local/qa/back-mountain-environment-v1") -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var directory := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(directory)
	var error := image.save_png(directory.path_join(filename))
	_env_check(error == OK, "real Compatibility screenshot saved: " + filename)
	_env_check(image.get_size() == Vector2i(960, 600), "screenshot has the requested 960x600 viewport: " + filename)
	report.screenshots.append(filename)
	report.screenshot_dimensions[filename] = [image.get_width(), image.get_height()]
	captures[filename] = image
	frame_count += 1
	return image


func _env_motion_uniforms() -> Array:
	var result: Array = []
	for material in game._cloud_materials:
		result.append(float(material.get_shader_parameter("cloud_time")))
	result.append(float(game.environment_adapter.rain_material.get_shader_parameter("rain_time")))
	result.append(float(game.environment_adapter.shadow_material.get_shader_parameter("cloud_time")))
	return result


func _env_mean_luma(image: Image) -> float:
	if image == null or image.is_empty():
		return -1.0
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return total / float(image.get_width() * image.get_height())


func _env_image_delta(left: Image, right: Image) -> Dictionary:
	if left == null or right == null or left.is_empty() or right.is_empty() or left.get_size() != right.get_size():
		return {"changed_pixels": -1, "pixel_count": 0, "mean_rgb_delta": -1.0}
	var changed := 0
	var delta_sum := 0.0
	var pixel_count := left.get_width() * left.get_height()
	for y in left.get_height():
		for x in left.get_width():
			var a := left.get_pixel(x, y)
			var b := right.get_pixel(x, y)
			var delta := (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			delta_sum += delta
			if a.r != b.r or a.g != b.g or a.b != b.b or a.a != b.a:
				changed += 1
	return {"changed_pixels": changed, "pixel_count": pixel_count, "mean_rgb_delta": delta_sum / float(maxi(1, pixel_count))}


func _env_nonrain_motion_uniforms_equal(before: Array, after: Array) -> bool:
	if before.size() != after.size() or before.size() <= game._cloud_materials.size():
		return false
	var rain_clock_index: int = game._cloud_materials.size()
	for index in before.size():
		if index == rain_clock_index:
			continue
		if before[index] != after[index]:
			return false
	return true


func _env_crop_control_rect(image: Image, control: Control, local_rect: Rect2) -> Image:
	var transform: Transform2D = root.get_final_transform() * control.get_global_transform_with_canvas()
	var origin := transform * local_rect.position
	var scale := transform.get_scale()
	var rect := Rect2i(
		floori(origin.x), floori(origin.y),
		ceili(local_rect.size.x * scale.x), ceili(local_rect.size.y * scale.y)
	)
	return _crop(image, rect)


func _env_crop_actor_face(image: Image) -> Image:
	# This local patch falls over the painted face inside the sprite atlas, away
	# from its transparent margins, so rain occlusion cannot pass via empty pixels.
	# Inner eyes/nose area; the larger head box includes translucent hair edges.
	return _env_crop_control_rect(image, game._actor_sprite, Rect2(170.0, 104.0, 38.0, 32.0))


func _env_header_rect(image: Image) -> Rect2i:
	var transform: Transform2D = root.get_final_transform() * game.get_global_transform_with_canvas()
	var bottom := floori((transform * Vector2(0.0, game._art_root.position.y)).y)
	return Rect2i(0, 0, image.get_width(), clampi(bottom, 0, image.get_height()))


func _env_footer_rect(image: Image) -> Rect2i:
	var transform: Transform2D = root.get_final_transform() * game.get_global_transform_with_canvas()
	var art_bottom: float = game._art_root.position.y + game._art_root.size.y
	var top := floori((transform * Vector2(0.0, art_bottom)).y)
	top = clampi(top, 0, image.get_height())
	return Rect2i(0, top, image.get_width(), image.get_height() - top)


func _env_controls_fit(controls: Array) -> bool:
	for control in controls:
		if not is_instance_valid(control) or not control.is_visible_in_tree():
			return false
		var point: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
		var half_size: Vector2 = control.size * root.get_final_transform().get_scale() * 0.5
		if point.x - half_size.x < 0.0 or point.y - half_size.y < 0.0:
			return false
		if point.x + half_size.x > 960.0 or point.y + half_size.y > 600.0:
			return false
	return true


func _env_sorted_keys(value: Dictionary) -> Array:
	var keys: Array = value.keys()
	keys.sort()
	return keys


func _env_time_index_for_profile(profile_id: String, mapping: Dictionary, times: Array) -> int:
	for index in range(times.size()):
		if str(mapping.get(str(times[index]), "")) == profile_id:
			return index
	return -1


func _env_state_snapshot(state: Object) -> Dictionary:
	var result: Dictionary = {}
	for property in state.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property.name)
		var value = state.get(name)
		if value is Dictionary or value is Array:
			result[name] = value.duplicate(true)
		else:
			result[name] = value
	result["time_text"] = state.time_text()
	return result


func _env_matching_state(source: Object) -> Object:
	var reference = source.get_script().new()
	for property in source.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property.name)
		var value = source.get(name)
		reference.set(name, value.duplicate(true) if value is Dictionary or value is Array else value)
	return reference


func _env_without_time_index(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	result.erase("time_index")
	result.erase("time_text")
	return result


func _env_check(condition: bool, label: String) -> void:
	checks[label] = condition
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1
		report.failures.append(label)
		push_error(label)


func _finish_environment_v1() -> void:
	report.checks = checks
	report.failure_count = failures
	report.captured_frames = frame_count
	var report_path := ProjectSettings.globalize_path("res://.local/qa/back-mountain-environment-v1/report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ") + "\n")
	else:
		push_error("could not write Environment v1 QA report: " + report_path)
		failures += 1
	print("BACK_MOUNTAIN_ENVIRONMENT_RENDER: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
