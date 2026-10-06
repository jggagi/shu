extends SceneTree

const SCENE_PATH := "res://scenes/demos/back_mountain_training.tscn"
const REQUIRED_CAPABILITIES := ["birds", "squirrel", "cat", "fish", "cat_sheltered", "cat_night_allowed"]

var failures := 0
var checks: Dictionary = {}
var game: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	check(packed != null, "standalone training scene loads")
	if packed == null:
		_finish()
		return
	game = packed.instantiate() as Control
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.state != null and game.environment_presenter != null, "scene exposes the existing DemoState and Environment presenter")
	check(game.ambient_life != null and game.ambient_life.presenter != null, "scene exposes the Ambient Life adapter and presenter")
	if game.ambient_life == null or game.ambient_life.presenter == null:
		_finish()
		return

	var life: Node = game.ambient_life
	var config_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/back_mountain_ambient_life.json"))
	check(life.config == config_file and int(life.config.get("seed", -1)) == 20261006, "adapter uses the checked-in scheduler configuration and deterministic seed unchanged")
	game.qa_motion_paused = true
	game.set_process(false)
	game.set_dynamic(true)
	game.set_lighting(false)
	game.set_weather("clear", false)
	game.set_night_preview(false, false)
	game.refresh_environment(false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	life.reset()
	life.observe_environment()

	var capabilities: Dictionary = life.get_capabilities()
	for kind in REQUIRED_CAPABILITIES:
		check(capabilities.has(kind), "capability result declares %s" % kind)
	check(capabilities.birds and capabilities.squirrel and capabilities.cat, "authored sky lane, branch path, and rock spot enable their events")
	check(not capabilities.fish and not capabilities.cat_sheltered and not capabilities.cat_night_allowed, "scene has no fish area, sheltered cat spot, or night cat spot")
	var marker_root := game._art_root.get_node_or_null("AmbientCapabilities") as Node2D
	check(marker_root != null, "authored AmbientCapabilities marker root is mounted under the art root")
	if marker_root == null:
		_finish()
		return
	var rock := marker_root.get_node_or_null("CatSpot_Rock") as Marker2D
	check(rock != null and rock.get_meta("spot_type", "") == "rock" and bool(rock.get_meta("sunny", false)) and not bool(rock.get_meta("sheltered", true)), "rock marker keeps its declared sunny, unsheltered metadata")
	_test_animal_pose_motion(life)

	var saved_state := _clone_state(game.state)
	saved_state.day = 3
	saved_state.time_index = 0
	saved_state.energy = 67
	saved_state.cultivation = 29
	saved_state.understanding = 4
	saved_state.lesson_bonus = 6
	saved_state.dialogue_open = true
	saved_state.tea_accepted = true
	saved_state.tea_seen = {"tea.cup_first": true}
	saved_state.tea_stage_complete = false
	saved_state.tea_quest_complete = false
	# Include parallel story fields when present, while remaining runnable against
	# the archived A/B DemoState without introducing story code into this slice.
	var optional_story_fields := {
		"tea_scene_id": "tea.old_courtyard", "tea_c_seen": {"tea.ledger": true}, "tea_c_complete": false,
		"tea_story_stage": 2, "tea_story_seen": {"D": true}, "tea_story_page": 1,
		"tea_story_object": "tea.medicine_pot", "tea_story_token": 8,
		"tea_ending_step": 1, "_tea_ending_first_fill_msec": 23,
	}
	var saved_fields := _script_snapshot(saved_state)
	for field in optional_story_fields:
		if saved_fields.has(field):
			saved_state.set(field, optional_story_fields[field])
	saved_state.tea_action_done = {"tea.cup_first": "repair"}
	saved_state.tea_active = true
	saved_state.tea_session = 19
	saved_state._tea_read_counter = 3
	saved_state._tea_pending_object_id = "tea.cup_second"
	saved_state._tea_pending_read_token = 3
	game.state = saved_state
	game._refresh_hud()
	game.refresh_environment(false)
	game.environment_presenter.finish_transition()
	life.observe_environment()
	var state_before_ambient := _script_snapshot(game.state)
	var environment_before_ambient := _script_snapshot(game.environment_presenter)

	check(game.force_ambient_life("birds"), "controller force API accepts a clear-weather bird event")
	var bird_events: Dictionary = life.presenter.get_active_events()
	check(bird_events.has("birds"), "forced bird event is active")
	if bird_events.has("birds"):
		var event: Dictionary = bird_events.birds
		for key in ["kind", "start", "duration", "count", "serial", "forced"]:
			check(event.has(key), "active bird record contains %s" % key)
		check(event.kind == "birds" and bool(event.forced), "accepted fixture is labeled as forced")
	check(not life.presenter.auto_enabled, "a forced encounter pauses the automatic schedule")
	check(_script_snapshot(game.state) == state_before_ambient, "forced encounter preserves every DemoState and tea field")
	check(_script_snapshot(game.environment_presenter) == environment_before_ambient, "forced encounter preserves all Environment presenter fields")

	var elapsed_before_toggle := float(life.presenter.elapsed)
	game.set_ambient_life(false)
	life.advance(2.0)
	check(not life.presenter.enabled and life.presenter.get_active_events().is_empty(), "ambient toggle off clears active life")
	check(not life.visual_nodes.birds.visible and not life.visual_nodes.squirrel.visible and not life.visual_nodes.cat.visible, "ambient toggle off hides every visual root")
	check(is_equal_approx(float(life.presenter.elapsed), elapsed_before_toggle), "ambient toggle off freezes the life clock")
	check(_script_snapshot(game.state) == state_before_ambient, "ambient toggle preserves every DemoState and tea field")
	game.set_ambient_life(true)
	check(life.presenter.enabled, "ambient toggle can be re-enabled")

	var elapsed_before_static := float(life.presenter.elapsed)
	game.set_dynamic(false)
	life.advance(2.0)
	check(not life.visual_nodes.birds.visible and not life.visual_nodes.squirrel.visible, "dynamic off hides bird and squirrel events")
	check(is_equal_approx(float(life.presenter.elapsed), elapsed_before_static), "dynamic off freezes the ambient clock")
	check(_script_snapshot(game.state) == state_before_ambient, "dynamic/static mode preserves every DemoState and tea field")
	game.set_dynamic(true)

	game.set_night_preview(true, false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	life.observe_environment()
	var state_before_night_force := _script_snapshot(game.state)
	check(not game.force_ambient_life("cat"), "night preview rejects a cat where no night spot is authored")
	check(_script_snapshot(game.state) == state_before_night_force, "night-gated force preserves the complete DemoState")
	game.set_night_preview(false, false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	life.observe_environment()

	game.set_weather("light_rain", false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	life.observe_environment()
	check(not game.force_ambient_life("birds") and not game.force_ambient_life("squirrel"), "zero-rain-chance quick events remain weather-gated when forced")
	check(not game.force_ambient_life("cat"), "unsheltered authored rock spot rejects cat during rain")
	var sheltered := Marker2D.new()
	sheltered.name = "CatSpot_TestEave"
	sheltered.position = Vector2(570, 522)
	sheltered.set_meta("spot_type", "eave")
	sheltered.set_meta("sunny", false)
	sheltered.set_meta("sheltered", true)
	marker_root.add_child(sheltered)
	life.refresh_capabilities()
	life.observe_environment()
	check(life.get_capabilities().cat_sheltered, "capability refresh detects an added sheltered spot marker")
	check(game.force_ambient_life("cat"), "a synthetic sheltered fixture permits the rain cat event")
	check(life.cat_spot == sheltered and bool(life.cat_spot.get_meta("sheltered", false)), "rain cat selection uses only the sheltered marker")
	check(not life.presenter.get_active_events().has("birds"), "weather-rejected birds were not activated as a combined weather bypass")
	check(_script_snapshot(game.state) == state_before_ambient, "rain gating and sheltered fixture preserve every DemoState and tea field")
	sheltered.get_parent().remove_child(sheltered)
	sheltered.free()
	life.refresh_capabilities()
	life.observe_environment()
	check(not life.get_capabilities().cat_sheltered and not life.presenter.get_active_events().has("cat"), "removing the synthetic shelter removes its capability and invalidates the event")

	# Verify real marker discovery, rather than a config-only capability claim.
	var lane := marker_root.get_node_or_null("SkyBirdLane") as Path2D
	marker_root.remove_child(lane)
	life.refresh_capabilities()
	life.observe_environment()
	check(not life.get_capabilities().birds, "removing the bird-lane marker removes bird capability")
	check(not game.force_ambient_life("birds"), "controller cannot force an event after its marker is removed")
	marker_root.add_child(lane)
	life.refresh_capabilities()
	life.observe_environment()
	check(life.get_capabilities().birds, "restoring the bird-lane marker restores capability")
	game.set_weather("clear", false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	var squirrel_path := marker_root.get_node_or_null("SquirrelPath") as Path2D
	marker_root.remove_child(squirrel_path)
	life.refresh_capabilities()
	life.observe_environment()
	check(not life.get_capabilities().squirrel and not game.force_ambient_life("squirrel"), "removing the squirrel path marker removes capability and blocks force")
	marker_root.add_child(squirrel_path)
	life.refresh_capabilities()
	life.observe_environment()
	check(life.get_capabilities().squirrel, "restoring the squirrel path marker restores capability")
	marker_root.remove_child(rock)
	life.refresh_capabilities()
	life.observe_environment()
	check(not life.get_capabilities().cat and not game.force_ambient_life("cat"), "removing the cat spot marker removes capability and blocks force")
	marker_root.add_child(rock)
	life.refresh_capabilities()
	life.observe_environment()
	check(life.get_capabilities().cat, "restoring the cat spot marker restores capability")
	check(_script_snapshot(game.state) == state_before_ambient, "capability discovery and force rejection preserve every DemoState and tea field")

	game.set_weather("clear", false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	life.observe_environment()
	life.reset()
	life.resume_auto()
	var automatic_event: Dictionary = {}
	for _step in 960:
		life.advance(0.25)
		var active: Dictionary = life.presenter.get_active_events()
		if not active.is_empty():
			for kind in active:
				if not bool(active[kind].get("forced", true)):
					automatic_event = active[kind]
					break
		if not automatic_event.is_empty():
			break
	check(not automatic_event.is_empty(), "fixed seed and controlled scheduler clock produce an observable automatic event")
	if not automatic_event.is_empty():
		check(not bool(automatic_event.forced), "automatic smoke event is distinct from forced QA fixtures")
		check(automatic_event.has("serial") and automatic_event.has("start") and automatic_event.has("duration"), "automatic event records its serial and clock window")
	check(_script_snapshot(game.state) == state_before_ambient, "automatic schedule intervals preserve every DemoState and tea field")

	var expected_after_reset := _clone_state(game.state)
	expected_after_reset.reset()
	check(game.reset_demo(), "normal demo reset remains available after Ambient Life controls")
	check(_script_snapshot(game.state) == _script_snapshot(expected_after_reset), "reset restores normal DemoState rules and clears existing tea state")
	check(is_zero_approx(float(life.presenter.elapsed)) and life.presenter.auto_enabled and life.presenter.get_active_events().is_empty(), "normal demo reset returns Ambient Life to its seeded initial schedule")
	var reset_environment := _script_snapshot(game.environment_presenter)
	check(str(reset_environment.get("time_profile_id", "")) == "mao" and not bool(reset_environment.get("night_preview", true)), "normal reset returns the existing environment preview to Mao day")

	_finish()


func _clone_state(source: Object) -> Object:
	var result: Object = source.get_script().new()
	for property in source.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property.name)
		var value: Variant = source.get(name)
		result.set(name, value.duplicate(true) if value is Dictionary or value is Array else value)
	return result


func _test_animal_pose_motion(life: Node) -> void:
	game.set_dynamic(true)
	game.busy = false
	game.state.time_index = 0
	game.refresh_environment(false)
	game.environment_presenter.set_weather("clear", false)
	game.environment_presenter.set_night_preview(false, false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	life.reset()
	var initial_state := _script_snapshot(game.state)
	var mao_environment := _script_snapshot(game.environment_presenter)
	var cat_root: Node2D = life.visual_nodes.cat
	var cat_sprite := cat_root.get_child(0) as Sprite2D
	check(cat_sprite != null and cat_sprite.texture is AtlasTexture, "cat pose uses the authored atlas child without changing the visual root")
	if cat_sprite == null or not (cat_sprite.texture is AtlasTexture):
		return
	check(_cat_pose_index(cat_sprite) == 0, "cat atlas begins on its original frame-zero artwork")
	check(game.force_ambient_life("cat"), "Mao clear fixture accepts the cat pose event")
	life.advance(1.0)
	var cat_idle_frame := _cat_pose_index(cat_sprite)
	var cat_idle_scale := cat_sprite.scale
	life.advance(6.0)
	var cat_morning_head_lift := _cat_pose_index(cat_sprite)
	check(cat_idle_frame == 0 and cat_morning_head_lift == 2, "Mao clear cat raises its head at age seven while age one sleeps")
	var cat_seven_state := _script_snapshot(game.state)
	var cat_seven_environment := _script_snapshot(game.environment_presenter)
	check(cat_seven_state == initial_state and cat_seven_environment == mao_environment, "cat head-lift pose preserves the full state and Environment presenter")
	var current_environment: Dictionary = game.environment_presenter.get_current_environment()
	check(float(current_environment.get("wind_strength", 0.0)) > 0.1, "clear Mao fixture supplies the existing wind threshold for a tail pose")
	life.advance(5.2)
	var cat_tail_frame := _cat_pose_index(cat_sprite)
	check(cat_tail_frame != 0 and cat_tail_frame != cat_morning_head_lift, "cat returns to a distinct tail-flick frame at age 12.2 under existing wind")
	check(_script_snapshot(game.state) == initial_state and _script_snapshot(game.environment_presenter) == mao_environment, "cat pose timeline leaves all DemoState and Environment fields unchanged")

	# At the same age, sunny Wu keeps the cat asleep; only the real time profile
	# changes between these otherwise identical presenter-controlled poses.
	life.reset()
	var wu_index: int = game.state.rules.times.find("午时")
	check(wu_index >= 0, "sunny Wu fixture is a real DemoState rules time")
	if wu_index < 0:
		return
	game.state.time_index = wu_index
	game._refresh_hud()
	game.refresh_environment(false)
	game.environment_presenter.set_weather("clear", false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	var wu_state_before := _script_snapshot(game.state)
	var wu_environment_before := _script_snapshot(game.environment_presenter)
	check(str(wu_environment_before.get("time_profile_id", "")) == "wu", "cat sleep comparison uses the actual sunny Wu profile")
	check(game.force_ambient_life("cat"), "sunny Wu accepts the same cat event fixture")
	life.advance(7.0)
	check(_cat_pose_index(cat_sprite) == 0, "sunny Wu cat stays asleep at age seven")
	check(_script_snapshot(game.state) == wu_state_before and _script_snapshot(game.environment_presenter) == wu_environment_before, "same-age sunny Wu pose preserves its state and environment snapshots")

	# A quick event and foreground attention each suppress the lifted pose while
	# leaving the cat event active and its clock untouched.
	life.reset()
	game.state.time_index = 0
	game._refresh_hud()
	game.refresh_environment(false)
	game.environment_presenter.set_weather("clear", false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	var suppression_state := _script_snapshot(game.state)
	var suppression_environment := _script_snapshot(game.environment_presenter)
	check(game.force_ambient_life("cat"), "suppression fixture starts a cat encounter")
	life.advance(7.0)
	var lifted_before_suppression := _cat_pose_index(cat_sprite)
	check(lifted_before_suppression == 2, "suppression fixture reaches the Mao head-lift pose")
	check(life.force_event("birds"), "quick-event fixture starts an overlapping bird pass")
	var cat_events: Dictionary = life.presenter.get_active_events()
	check(cat_events.has("cat") and cat_events.has("birds") and _cat_pose_index(cat_sprite) == 0, "active quick event suppresses the cat pose without ending its event")
	check(_script_snapshot(game.state) == suppression_state and _script_snapshot(game.environment_presenter) == suppression_environment, "quick-event pose suppression preserves all state and Environment fields")

	life.reset()
	check(game.force_ambient_life("cat"), "busy-pose fixture starts a fresh cat event")
	life.advance(7.0)
	game.busy = true
	life.advance(0.0)
	check(_cat_pose_index(cat_sprite) == 0 and life.presenter.get_active_events().has("cat"), "foreground busy state suppresses the cat pose while its event remains active")
	game.busy = false
	life.advance(0.0)
	check(_cat_pose_index(cat_sprite) == 2, "cat head-lift resumes after foreground attention clears")
	check(_script_snapshot(game.state) == suppression_state and _script_snapshot(game.environment_presenter) == suppression_environment, "busy-pose suppression preserves all state and Environment fields")

	life.reset()
	check(game.force_ambient_life("cat"), "static-pose fixture starts a fresh cat event")
	life.advance(7.0)
	game.set_dynamic(false)
	var static_elapsed := float(life.presenter.elapsed)
	var static_scale := cat_sprite.scale
	life.advance(2.0)
	check(_cat_pose_index(cat_sprite) == 0 and cat_root.visible, "dynamic off keeps the active cat visible on frame zero")
	var static_texture := cat_sprite.texture as AtlasTexture
	var expected_static_scale := float(life._cat_pixel_scale) * float(life.config.visuals.cat_scale)
	var desired_static_width := 96.0 * float(life.config.visuals.cat_scale)
	var displayed_static_width := static_texture.region.size.x * cat_sprite.scale.x if static_texture != null else -1.0
	check(static_scale == cat_sprite.scale and cat_sprite.scale == Vector2.ONE * expected_static_scale and absf(displayed_static_width - desired_static_width) <= 1.0, "dynamic off restores the original logical cat width at its adjusted raster scale")
	check(is_equal_approx(float(life.presenter.elapsed), static_elapsed), "dynamic off freezes the cat presentation clock")
	check(_script_snapshot(game.state) == suppression_state and _script_snapshot(game.environment_presenter) == suppression_environment, "static cat pose preserves all state and Environment fields")
	game.set_dynamic(true)

	# The squirrel uses atlas frames for both phases and travels only within its
	# authored path. Replaying the same seeded forced event must reproduce pose.
	life.reset()
	var squirrel_state_before := _script_snapshot(game.state)
	var squirrel_environment_before := _script_snapshot(game.environment_presenter)
	check(life.force_event("squirrel"), "squirrel pose fixture starts through the adapter")
	life.advance(0.8)
	var squirrel_root: Node2D = life.visual_nodes.squirrel
	var squirrel_sprite := squirrel_root.get_child(0) as Sprite2D
	check(squirrel_sprite != null and squirrel_sprite.texture is AtlasTexture, "squirrel animation uses the authored atlas child")
	if squirrel_sprite == null or not (squirrel_sprite.texture is AtlasTexture):
		return
	var squirrel_run_frame := _atlas_frame(squirrel_sprite, 68.0)
	var squirrel_run_position := squirrel_root.position
	var squirrel_run_bob := squirrel_sprite.position.y
	check(squirrel_run_frame >= 1 and squirrel_run_frame <= 3, "running squirrel uses one of atlas frames one through three")
	check(_inside_squirrel_curve(squirrel_root.position), "running squirrel root stays within the authored path bounds")
	check(absf(squirrel_run_bob) <= 2.2, "squirrel bob remains within 2.2 art pixels")
	life.advance(1.7)
	var squirrel_pause_frame := _atlas_frame(squirrel_sprite, 68.0)
	check(squirrel_pause_frame == 0 and squirrel_pause_frame != squirrel_run_frame, "squirrel pause phase changes to its frame-zero pose")
	check(_inside_squirrel_curve(squirrel_root.position), "paused squirrel remains bounded by the authored path")
	life.reset()
	check(life.force_event("squirrel"), "deterministic replay restarts the same squirrel fixture")
	life.advance(0.8)
	check(squirrel_root.position == squirrel_run_position and _atlas_frame(squirrel_sprite, 68.0) == squirrel_run_frame and is_equal_approx(squirrel_sprite.position.y, squirrel_run_bob), "same event age reproduces the squirrel frame, position, and bob without per-frame randomness")
	game.set_dynamic(false)
	life.advance(1.0)
	check(not squirrel_root.visible and _atlas_frame(squirrel_sprite, 68.0) == 0 and squirrel_sprite.position.y == 0.0, "static mode hides the squirrel and restores frame zero with no bob")
	check(_script_snapshot(game.state) == squirrel_state_before and _script_snapshot(game.environment_presenter) == squirrel_environment_before, "squirrel pose timeline preserves all DemoState and Environment fields")
	game.set_dynamic(true)
	life.reset()
	game.state.time_index = 0
	game._refresh_hud()
	game.refresh_environment(false)
	game.environment_presenter.set_weather("clear", false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	game.qa_motion_paused = true
	game.set_process(false)
	var restored_environment: Dictionary = game.environment_presenter.get_current_environment()
	check(_script_snapshot(game.state) == initial_state and str(game.environment_presenter.time_profile_id) == "mao" and str(game.environment_presenter.weather_id) == "clear" and not game.environment_presenter.night_preview and restored_environment == game.environment_presenter.get_target_environment(), "pose fixtures restore the original state and settled Mao-clear environment")


func _atlas_frame(sprite: Sprite2D, frame_width: float) -> int:
	var texture := sprite.texture as AtlasTexture
	if texture == null or frame_width <= 0.0:
		return -1
	return roundi(texture.region.position.x / frame_width)


func _cat_pose_index(sprite: Sprite2D) -> int:
	var texture := sprite.texture as AtlasTexture
	return int(texture.get_meta("pose_index", -1)) if texture != null else -1


func _inside_squirrel_curve(point: Vector2) -> bool:
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


func _script_snapshot(value: Object) -> Dictionary:
	var result: Dictionary = {}
	for property in value.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := str(property.name)
		var property_value: Variant = value.get(name)
		result[name] = property_value.duplicate(true) if property_value is Dictionary or property_value is Array else property_value
	if value.has_method("time_text"):
		result["time_text"] = value.time_text()
	return result


func check(condition: bool, label: String) -> void:
	checks[label] = condition
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1
		push_error(label)


func _finish() -> void:
	var report := {"checks": checks, "failure_count": failures}
	print("BACK_MOUNTAIN_AMBIENT_LIFE_TEST: %s" % ("PASS" if failures == 0 else "FAIL"))
	print(JSON.stringify(report, "  "))
	quit(0 if failures == 0 else 1)
