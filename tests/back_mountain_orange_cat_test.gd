extends SceneTree

const SCENE_PATH := "res://scenes/demos/back_mountain_training.tscn"
const CAT_RASTER_PATH := "res://assets/art/ambient_life/orange-cat-painterly-v2.png"

var failures := 0
var checks: Dictionary = {}
var game: Control
var life: Node
var cat_petted_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	check(packed != null, "standalone Back Mountain scene loads")
	if packed == null:
		_finish()
		return
	game = packed.instantiate() as Control
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.state != null and game.environment_presenter != null, "existing DemoState and Environment presenter load")
	check(game.ambient_life != null, "Ambient Life adapter loads")
	if game.ambient_life == null:
		_finish()
		return
	life = game.ambient_life
	game.qa_motion_paused = true
	game.set_process(false)
	game.set_dynamic(true)
	game.set_ambient_life(true)
	_set_weather("clear")
	_set_profile("mao")
	game.set_night_preview(false, false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	life.reset()
	life.observe_environment()

	var hotspot: Button = life.cat_hotspot
	var cat_root: Node2D = life.visual_nodes.get("cat") as Node2D
	check(hotspot != null, "adapter exposes the clickable cat hotspot")
	check(cat_root != null and cat_root.get_child_count() > 0, "adapter exposes the rendered cat root and sprite")
	if hotspot == null or cat_root == null or cat_root.get_child_count() == 0:
		_finish()
		return
	var cat_sprite := cat_root.get_child(0) as Sprite2D
	check(cat_sprite != null and cat_sprite.texture is AtlasTexture, "cat uses the existing Sprite2D child with an atlas texture")
	if cat_sprite == null or not (cat_sprite.texture is AtlasTexture):
		_finish()
		return
	check(life._cat_frames.size() == 8, "cat adapter has all eight documented poses")
	check(_cat_frame(cat_sprite) == 0, "frame zero remains the resting cat pose")
	_validate_cat_raster(life)
	var initial_cat_texture := cat_sprite.texture as AtlasTexture
	var displayed_cat_width := initial_cat_texture.region.size.x * cat_sprite.scale.x
	var expected_cat_width := 96.0 * float(life.config.visuals.cat_scale)
	check(absf(displayed_cat_width - expected_cat_width) <= 1.0, "painterly sheet resolution preserves the original logical cat width")
	check(is_equal_approx(float(life.config.visuals.cat_scale), 1.15), "cat keeps the decided 1.15 scale")
	check(life.cat_spot == null, "reset cat has no selected spot before an event starts")
	check(hotspot.get_parent() == game._foreground_layer, "cat hotspot is mounted in the foreground interaction layer")
	check(hotspot.visible == cat_root.visible and hotspot.disabled, "idle hotspot is hidden and inactive with the hidden cat")

	check(life.force_event("cat"), "clear Mao accepts a controlled cat fixture")
	life.advance(1.1)
	check(cat_root.visible and hotspot.visible and not hotspot.disabled, "visible dynamic cat exposes an active hotspot")
	check(is_instance_valid(life.cat_spot) and cat_root.position == life.cat_spot.position, "rendered cat stays on its selected authored spot")
	var hotspot_rect := hotspot.get_global_rect()
	var cat_rect := _canvas_rect(cat_sprite)
	check(cat_rect.intersects(hotspot_rect) and cat_rect.has_point(hotspot_rect.get_center()), "hotspot center lies within the rendered cat bounds")
	check(not hotspot_rect.intersects(game.actor_hotspot.get_global_rect()), "cat hit region does not overlap the actor hit region")
	for button in game.find_children("*", "Button", true, false):
		if button == hotspot or button == game.actor_hotspot:
			continue
		check(not hotspot_rect.intersects((button as Control).get_global_rect()), "cat hit region avoids other UI: %s" % button.name)
	var authored_spot_before_pet: Vector2 = life.cat_spot.position
	var state_before_pet := _script_snapshot(game.state)
	var environment_before_pet := _script_snapshot(game.environment_presenter)
	life.cat_petted.connect(_on_cat_petted)
	# Emitting the actual hotspot button signal exercises the same production
	# connection as a mouse click; the render companion sends viewport input.
	hotspot.emit_signal("pressed")
	life.advance(0.1)
	check(cat_petted_count == 1 and _cat_frame(cat_sprite) == 7, "clicking the cat starts one visible frame-seven pet reaction")
	check(hotspot.visible and hotspot.disabled, "pet reaction temporarily disables repeat clicks")
	# Bring an otherwise later quick-event opportunity into the pet window to
	# prove adapter attention suppresses its automatic start without editing config.
	life.presenter.auto_enabled = true
	life.presenter.next_due["birds"] = float(life.presenter.elapsed) + 0.05
	life.advance(0.2)
	var pet_events: Dictionary = life.presenter.get_active_events()
	check(not pet_events.has("birds") and not pet_events.has("squirrel"), "automatic quick events are suppressed while the cat is being petted")
	check(game.pet_cat() == false, "a repeated wrapper click cannot restart an active pet reaction")
	hotspot.emit_signal("pressed")
	check(cat_petted_count == 1, "rejected repeat click does not emit a second cat-petted signal")
	check(life.cat_spot.position == authored_spot_before_pet, "pet feedback leaves the authored cat spot unchanged")
	check(_script_snapshot(game.state) == state_before_pet, "button pet reaction preserves every DemoState field")
	check(_script_snapshot(game.environment_presenter) == environment_before_pet, "button pet reaction preserves every Environment presenter field")
	life.advance(3.2)
	check(not hotspot.disabled, "hotspot re-enables after the 3.2-second pet reaction")
	check(_cat_frame(cat_sprite) != 7, "cat leaves the petted pose when the reaction ends")
	check(cat_root.position == authored_spot_before_pet, "cat returns to its authored spot after the nuzzle ends")
	check(_script_snapshot(game.state) == state_before_pet and _script_snapshot(game.environment_presenter) == environment_before_pet, "pet completion still preserves all gameplay and Environment state")

	# The public controller wrapper is independently exercised on a fresh event.
	life.reset()
	check(game.force_ambient_life("cat"), "fresh wrapper fixture accepts a cat event")
	life.advance(1.1)
	check(game.pet_cat(), "game-level pet wrapper accepts an available cat")
	check(cat_petted_count == 2, "controller wrapper emits the adapter's cat-petted signal")
	game.busy = true
	life.observe_environment()
	check(hotspot.disabled and not game.pet_cat(), "busy training blocks pet input and disables its hotspot")
	game.busy = false
	life.observe_environment()

	# A real seeded automatic cat appears within its new short interval; advancing
	# that same event to the self-play portion keeps it clearly labeled as auto.
	life.reset()
	life.resume_auto()
	var automatic_cat: Dictionary = {}
	for _step in 60:
		life.advance(0.1)
		var active: Dictionary = life.presenter.get_active_events()
		if active.has("cat") and not bool(active.cat.get("forced", true)):
			automatic_cat = active.cat
			break
	check(not automatic_cat.is_empty(), "fixed seed produces an automatic cat during the configured 3-to-6-second interval")
	if not automatic_cat.is_empty():
		var automatic_age := float(life.presenter.elapsed) - float(automatic_cat.start)
		check(automatic_age <= 6.0 and not bool(automatic_cat.forced), "early cat is a naturally scheduled event, not a forced fixture")
		life.advance(maxf(0.0, 20.4 - automatic_age))
		check(life.presenter.get_active_events().has("cat"), "long-lived automatic cat remains present through self-play age 20.4")
		check(_cat_frame(cat_sprite) in [5, 6], "automatic cat self-play uses the roll/play or paw-leaf frame")
		check(life.cat_is_playing(), "age-20.4 automatic pose marks foreground attention as busy")
		life.presenter.next_due["birds"] = float(life.presenter.elapsed) + 0.05
		life.advance(0.2)
		var selfplay_events: Dictionary = life.presenter.get_active_events()
		check(not selfplay_events.has("birds") and not selfplay_events.has("squirrel"), "automatic quick events are suppressed during cat self-play")
		check(_script_snapshot(game.state) == state_before_pet and _script_snapshot(game.environment_presenter) == environment_before_pet, "automatic self-play preserves all DemoState and Environment fields")

	# Weather and presentation gates operate through the live scene controls.
	_set_weather("cloudy")
	life.reset()
	check(game.force_ambient_life("cat"), "cloudy weather allows the unsheltered cat")
	life.advance(1.1)
	check(cat_root.visible and hotspot.visible and not hotspot.disabled, "cloudy cat remains rendered and clickable")
	_set_weather("light_rain")
	life.reset()
	check(not game.force_ambient_life("cat"), "light rain rejects the unsheltered authored cat spot")
	check(not cat_root.visible and not hotspot.visible and hotspot.disabled, "light rain hides the unsheltered cat and disables its hotspot")
	_set_weather("clear")
	game.set_night_preview(true, false)
	life.reset()
	life.observe_environment()
	check(not game.force_ambient_life("cat"), "night preview rejects a cat without an authored night spot")
	check(not hotspot.visible and hotspot.disabled, "night preview leaves no cat hotspot active")
	game.set_night_preview(false, false)
	game.environment_presenter.finish_transition()
	game._apply_environment()

	life.reset()
	check(game.force_ambient_life("cat"), "dynamic-off fixture starts from a visible cat")
	life.advance(7.0)
	game.set_dynamic(false)
	life.observe_environment()
	check(cat_root.visible and hotspot.visible and hotspot.disabled, "static mode keeps the cat visible while disabling pet input")
	check(_cat_frame(cat_sprite) == 0, "static mode restores the cat to frame zero")
	game.set_dynamic(true)
	life.observe_environment()

	life.reset()
	check(game.force_ambient_life("cat"), "Ambient Life off fixture starts from a visible cat")
	game.set_ambient_life(false)
	check(not cat_root.visible and not hotspot.visible and hotspot.disabled, "Ambient Life off hides the cat and disables the hotspot")
	check(not game.pet_cat(), "Ambient Life off blocks controller pet input")
	game.set_ambient_life(true)

	life.reset()
	check(game.force_ambient_life("cat"), "reset fixture starts from a visible cat")
	life.advance(1.1)
	check(game.pet_cat(), "reset fixture enters the pet reaction")
	check(_cat_frame(cat_sprite) == 7 and hotspot.disabled, "reset fixture has an active pet reaction")
	check(game.reset_demo(), "normal demo reset remains available after cat interaction")
	check(life.presenter.get_active_events().is_empty() and life.presenter.enabled, "normal reset clears active Ambient Life state and reaction")
	check(not cat_root.visible and not hotspot.visible and hotspot.disabled and _cat_frame(cat_sprite) == 0, "normal reset hides the cat, disables its hotspot, and restores frame zero")
	var reset_state := _script_snapshot(game.state)
	var reset_environment := _script_snapshot(game.environment_presenter)
	check(reset_state.energy == int(game.state.rules.energy_max) and reset_state.cultivation == 0, "cat interaction and reset preserve the game's ordinary starting rules")
	check(str(reset_environment.get("time_profile_id", "")) == "mao" and not bool(reset_environment.get("night_preview", true)), "reset restores Mao day with night preview off")

	_finish()


func _set_weather(weather_id: String) -> void:
	game.set_weather(weather_id, false)
	game.environment_presenter.finish_transition()
	game._apply_environment()
	if life != null:
		life.observe_environment()


func _set_profile(profile_id: String) -> void:
	var times: Array = game.state.rules.times
	var labels := {"mao": "卯时", "chen": "辰时", "wu": "午时", "you": "酉时"}
	var index: int = times.find(labels.get(profile_id, "卯时"))
	if index >= 0:
		game.state.time_index = index
		game._refresh_hud()
		game.refresh_environment(false)
		game.environment_presenter.finish_transition()
		game._apply_environment()
		if life != null:
			life.observe_environment()


func _cat_frame(sprite: Sprite2D) -> int:
	var texture := sprite.texture as AtlasTexture
	return int(texture.get_meta("pose_index", -1)) if texture != null else -1


func _validate_cat_raster(adapter: Node) -> void:
	var atlas_textures: Array = adapter._cat_frames
	var atlas := (atlas_textures[0] as AtlasTexture).atlas as Texture2D if not atlas_textures.is_empty() else null
	var image := Image.load_from_file(ProjectSettings.globalize_path(CAT_RASTER_PATH))
	check(atlas != null and atlas.resource_path == CAT_RASTER_PATH, "cat art is loaded from the painterly raster asset path")
	check(not image.is_empty() and image.get_width() == 1774 and image.get_height() == 887, "painterly cat raster has its authored 1774 by 887 dimensions")
	if image.is_empty() or atlas_textures.size() != 8:
		return
	var occupied_counts: Array[int] = []
	var transparent_counts: Array[int] = []
	var covered_cells: Dictionary = {}
	for expected_pose in 8:
		var texture := atlas_textures[expected_pose] as AtlasTexture
		if texture == null:
			check(false, "cat pose %d remains an AtlasTexture" % expected_pose)
			continue
		var pose_index := int(texture.get_meta("pose_index", -1))
		check(pose_index == expected_pose, "cat atlas metadata names pose %d" % expected_pose)
		var region: Rect2 = texture.region
		check(region.size.x > 0.0 and region.size.y > 0.0 and Rect2(Vector2.ZERO, Vector2(image.get_width(), image.get_height())).encloses(region), "cat pose %d region fits inside the raster atlas" % expected_pose)
		var column := clampi(floori((region.position.x + region.size.x * 0.5) / float(image.get_width()) * 4.0), 0, 3)
		var row := clampi(floori((region.position.y + region.size.y * 0.5) / float(image.get_height()) * 2.0), 0, 1)
		covered_cells[row * 4 + column] = true
		var transparent := 0
		var occupied := 0
		var x_start := clampi(floori(region.position.x), 0, image.get_width())
		var y_start := clampi(floori(region.position.y), 0, image.get_height())
		var x_end := clampi(ceili(region.end.x), x_start, image.get_width())
		var y_end := clampi(ceili(region.end.y), y_start, image.get_height())
		for y in range(y_start, y_end):
			for x in range(x_start, x_end):
				var alpha := image.get_pixel(x, y).a
				if alpha <= 0.02:
					transparent += 1
				elif alpha >= 0.5:
					occupied += 1
		occupied_counts.append(occupied)
		transparent_counts.append(transparent)
		check(transparent > 256 and occupied > 256, "cat pose %d has transparent background and visible raster pixels" % expected_pose)
	check(covered_cells.size() == 8, "eight pose regions cover eight distinct cells of the 4-by-2 raster sheet")
	check(occupied_counts.size() == 8 and transparent_counts.size() == 8, "all eight raster poses received alpha-occupancy checks")


func _canvas_rect(item: CanvasItem) -> Rect2:
	var local_rect: Rect2 = item.get_rect()
	return item.get_global_transform_with_canvas() * local_rect


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


func _on_cat_petted() -> void:
	cat_petted_count += 1


func check(condition: bool, label: String) -> void:
	checks[label] = condition
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1
		push_error(label)


func _finish() -> void:
	print("BACK_MOUNTAIN_ORANGE_CAT_TEST: %s" % ("PASS" if failures == 0 else "FAIL"))
	print(JSON.stringify({"checks": checks, "failure_count": failures}, "  "))
	quit(0 if failures == 0 else 1)
