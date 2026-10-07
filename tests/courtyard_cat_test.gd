extends SceneTree

const Cat = preload("res://scripts/courtyard_cat.gd")
const Presenter = preload("res://scripts/ambient_life_presenter.gd")

var failures := 0
var pet_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node2D.new()
	world.scale = Vector2(0.75, 0.75)
	root.add_child(world)
	var cat = Cat.new()
	world.add_child(cat)
	cat.configure({
		"path": [[958.0, 495.0], [1066.0, 500.0]],
		"cat_sheltered": true,
		"cat_width": 78.0,
		"cat_speed": 60.0,
		"rest_seconds": 0.35,
		"stand_seconds": 0.2,
		"sniff_seconds": 0.15,
		"sit_seconds": 0.2,
	})
	cat.petted.connect(_on_petted)
	await process_frame
	check(cat.presenter is Presenter, "CourtyardCat owns the reusable AmbientLifePresenter")
	check(bool(cat.capabilities.get("cat", false)) and bool(cat.capabilities.get("cat_sheltered", false)), "authored route enables one sheltered cat")
	check(not bool(cat.capabilities.get("birds", true)) and not bool(cat.capabilities.get("squirrel", true)) and not bool(cat.capabilities.get("fish", true)), "courtyard does not enable birds, squirrel, or fish")
	check(cat.config.get("cat", {}).get("duration_min", 0.0) >= 240.0, "resident opportunity lasts at least 240 seconds")
	var first_due := float(cat.presenter.next_due.get("cat", -1.0))
	check(first_due >= 2.0 and first_due <= 3.0, "seeded first opportunity is scheduled between two and three seconds")
	var replay := Presenter.new()
	replay.configure(cat.config)
	check(is_equal_approx(first_due, float(replay.next_due.get("cat", -2.0))), "the configured seed reproduces the first arrival deadline")

	var environment := _environment("light_rain")
	for _step in 13:
		cat.update_presentation(environment, true, 0.25)
	var first_snapshot: Dictionary = cat.get_snapshot()
	check(first_snapshot.visible and first_snapshot.route_active, "sheltered cat appears naturally in rain and starts its own route")
	check(is_equal_approx(float(first_snapshot.visible_width), 78.0), "resting atlas pose renders at the configured opaque width")
	check(first_snapshot.foot == first_snapshot.contact_foot, "resting pose contact pivot stays at the authored foot")
	check(is_equal_approx(first_snapshot.hotspot_rect.size.x, 78.0), "pet hotspot matches the visible opaque width")
	check(is_equal_approx(cat._hotspot.get_global_rect().size.x, 58.5), "hotspot follows the cat through the scaled world transform")

	var host_state := {"time": 12, "energy": 83, "cultivation": 17, "quest": "unchanged"}
	var outbound_snapshot: Dictionary = {}
	for _step in 180:
		cat.update_presentation(environment, true, 0.025)
		var snapshot: Dictionary = cat.get_snapshot()
		if str(snapshot.route_phase) == "outbound" and float(snapshot.foot.x) > 958.2:
			outbound_snapshot = snapshot
			break
	check(not outbound_snapshot.is_empty(), "route reaches a moving outbound pose")
	if not outbound_snapshot.is_empty():
		check(float(outbound_snapshot.facing) > 0.0, "outbound pose faces along the authored route")
		check(int(outbound_snapshot.pose) >= 8 and int(outbound_snapshot.pose) <= 11, "outbound uses the desk walking atlas")
		check(is_equal_approx(float(outbound_snapshot.visible_width), 78.0), "walking pose keeps the same visible width")
		check(outbound_snapshot.foot == outbound_snapshot.contact_foot, "walking frame pivots preserve foot contact")
		check(outbound_snapshot.hotspot_rect.size == cat._opaque_rect.size, "moving hotspot tracks the current pose bounds")

	var frozen: Dictionary = cat.get_snapshot()
	cat.update_presentation(environment, false, 7.0)
	var static_snapshot: Dictionary = cat.get_snapshot()
	check(is_equal_approx(float(static_snapshot.presentation_elapsed), float(frozen.presentation_elapsed)), "Static freezes schedule and presentation clocks")
	check(static_snapshot.foot == frozen.foot and is_equal_approx(float(static_snapshot.route_distance), float(frozen.route_distance)), "Static preserves the current route position")
	check(is_equal_approx(float(static_snapshot.route_phase_elapsed), float(frozen.route_phase_elapsed)), "Static preserves the route phase clock")
	check(int(static_snapshot.pose) == 13 and not static_snapshot.hotspot_enabled, "Static stands at the current foot and disables pet input")
	cat.update_presentation(environment, true, 0.05)
	var resumed: Dictionary = cat.get_snapshot()
	check(float(resumed.foot.x) > float(static_snapshot.foot.x), "Dynamic resumes the route continuously from its frozen point")

	var before_pet: Dictionary = cat.get_snapshot()
	check(before_pet.hotspot_enabled, "visible Dynamic cat exposes its moving hotspot")
	cat._hotspot.emit_signal("pressed")
	var petted: Dictionary = cat.get_snapshot()
	check(pet_count == 1 and petted.pet_response_active, "petting emits the scene signal and starts the local response")
	check(int(petted.pose) == 7 and petted.foot == before_pet.foot and petted.facing == before_pet.facing, "pet response preserves pose contact and facing")
	check(is_equal_approx(float(petted.visible_width), 78.0), "pet response keeps the configured opaque width")
	var pet_distance := float(petted.route_distance)
	cat.update_presentation(environment, true, 0.8)
	var pet_paused: Dictionary = cat.get_snapshot()
	check(is_equal_approx(float(pet_paused.route_distance), pet_distance), "pet response pauses route movement")
	check(is_equal_approx(float(pet_paused.pet_response_remaining), 0.8), "pet response uses the configured 1.6 second duration")
	cat.update_presentation(environment, false, 5.0)
	var static_pet: Dictionary = cat.get_snapshot()
	check(not static_pet.pet_response_active and is_equal_approx(float(static_pet.pet_response_remaining), 0.8), "Static pauses the pet response without consuming its remaining time")
	check(not static_pet.hotspot_enabled and int(static_pet.pose) == 13, "Static stands and disables the hotspot while a response is paused")
	cat.update_presentation(environment, true, 0.1)
	check(cat.get_snapshot().pet_response_active, "resuming Dynamic continues the paused pet response")
	cat.update_presentation(environment, true, 1.0)
	var after_pet: Dictionary = cat.get_snapshot()
	check(not after_pet.pet_response_active and float(after_pet.route_distance) > pet_distance, "route resumes after the pet response expires")

	var return_seen := false
	var sit_seen := false
	var stand_seen := false
	var return_snapshot: Dictionary = {}
	for _step in 240:
		cat.update_presentation(environment, true, 0.025)
		var snapshot: Dictionary = cat.get_snapshot()
		if str(snapshot.route_phase) == "return" and float(snapshot.facing) < 0.0:
			return_seen = true
			return_snapshot = snapshot
		if int(snapshot.pose) == 12:
			sit_seen = true
		if int(snapshot.pose) == 13:
			stand_seen = true
		if return_seen and sit_seen and stand_seen:
			break
	check(return_seen, "return route faces back toward the resident home point")
	check(sit_seen and stand_seen, "route includes authored sit and stand/sniff poses")
	if return_seen:
		check(is_equal_approx(float(return_snapshot.visible_width), 78.0), "return pose keeps the configured width")
		check(return_snapshot.foot == return_snapshot.contact_foot, "return facing preserves its contact foot")
		check(is_equal_approx(return_snapshot.hotspot_rect.size.x, 78.0), "return hotspot follows mirrored opaque bounds")

	cat.reset()
	var reset_snapshot: Dictionary = cat.get_snapshot()
	check(cat.presenter.get_active_events().is_empty() and not reset_snapshot.route_active, "reset clears the active resident and route")
	check(is_equal_approx(float(cat.presenter.next_due.get("cat", -1.0)), first_due), "reset restarts the seeded arrival schedule")
	check(not reset_snapshot.pet_response_active and is_zero_approx(float(reset_snapshot.pet_response_remaining)), "reset clears pet response state")
	check(host_state == {"time": 12, "energy": 83, "cultivation": 17, "quest": "unchanged"}, "presentation updates leave host-owned gameplay state untouched")

	world.queue_free()
	await process_frame
	_finish()


func _environment(weather_id: String) -> Dictionary:
	return {
		"time_profile_id": "mao",
		"weather_id": weather_id,
		"night_preview": false,
		"foreground_busy": false,
		"gust": 0.2,
	}


func _on_petted() -> void:
	pet_count += 1


func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1


func _finish() -> void:
	print("COURTYARD_CAT_TEST: " + ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
