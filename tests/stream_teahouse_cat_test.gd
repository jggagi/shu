extends SceneTree

const CatPresenter := preload("res://scripts/stream_teahouse_cat.gd")
const CatDeskMotion := preload("res://scripts/tingyu_cat_desk_motion.gd")
const PAINTERLY_LAYOUT_PATH := "res://assets/art/ambient_life/orange-cat-layout-v2.json"
const DESK_LAYOUT_PATH := "res://assets/art/ambient_life/tingyu-cat-desk-layout-v1.json"

var failures := 0
var checks := 0
var cat
var world: Node2D
var path: Path2D
var home: Marker2D
var observed_context := {
	"dynamic_enabled": true,
	"weather_id": "clear",
	"time_profile_id": "mao",
	"busy": false,
	"brightness": 1.0,
	"world_tint": Color.WHITE,
}
var pet_signal_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = Node2D.new()
	world.name = "TestLogicalWorld"
	world.scale = Vector2(1.25, 1.25)
	root.add_child(world)
	path = Path2D.new()
	path.name = "ExposedStonePath"
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2(346, 516))
	path.curve.add_point(Vector2(446, 516))
	path.curve.add_point(Vector2(511, 509))
	world.add_child(path)
	home = Marker2D.new()
	home.name = "CatHome"
	home.position = Vector2(346, 516)
	world.add_child(home)

	cat = CatPresenter.new()
	root.add_child(cat)
	cat.setup(world, path, home)
	cat.cat_petted.connect(_on_cat_petted)
	await process_frame
	await process_frame

	check(cat.sprite != null and cat.hotspot != null, "setup creates the resident sprite and pet hotspot")
	check(cat.sprite != null and cat.sprite.texture is AtlasTexture, "resident uses an atlas pose")
	check(cat.motion.active and cat.elapsed == 0.0 and cat.pet_remaining == 0.0, "setup starts the resident at its authored home")
	check(cat.pose_index == 0 and _hotspot_available(), "resident starts visible and pettable in clear Dynamic state")
	if cat.sprite == null or not (cat.sprite.texture is AtlasTexture):
		_finish()
		return

	_test_forward_pose_and_contact()
	_test_busy_pause()
	_test_pet_and_static_freeze()
	_test_reverse_pose_and_contact()
	_test_rain_fade_and_static_resume()
	_test_reset()
	_finish()


func _test_forward_pose_and_contact() -> void:
	cat.advance(8.3)
	var root_node := cat.sprite.get_parent() as Node2D
	check(cat.pose_index >= 8 and cat.pose_index <= 11, "initial route reaches a walking atlas pose")
	check(root_node.position.x > home.position.x and cat.motion.facing_x() > 0.0, "outbound travel follows the authored route facing right")
	_assert_current_contact(1.0, "right-facing walk")


func _test_busy_pause() -> void:
	var before_position: Vector2 = cat.motion.global_position()
	var before_motion_time: float = cat.motion.activity_elapsed
	_set_context({"busy": true})
	cat.advance(1.0)
	check(cat.motion.global_position().is_equal_approx(before_position), "Busy pauses route position")
	check(is_equal_approx(cat.motion.activity_elapsed, before_motion_time), "Busy pauses the movement phase clock")
	check(cat.pose_index == 13, "Busy settles a traveling cat into the standing pose")
	check(not _hotspot_available() and cat.hotspot.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Busy disables the hotspot and passes controls through")
	_set_context({"busy": false})
	cat.advance(0.25)
	check(not cat.motion.global_position().is_equal_approx(before_position), "clearing Busy resumes travel from its paused contact")


func _test_pet_and_static_freeze() -> void:
	var before_pet_position: Vector2 = cat.motion.global_position()
	var before_facing: float = cat.motion.facing_x()
	check(cat.pet(), "pet() accepts an available visible cat")
	check(cat.pose_index == 7 and is_equal_approx(cat.pet_remaining, 2.4), "pet starts the approved response pose and timer")
	check(pet_signal_count == 1, "pet emits one local response signal")
	check(cat.motion.global_position().is_equal_approx(before_pet_position), "pet begins without moving the cat")
	cat.advance(1.0)
	check(cat.pose_index == 7 and is_equal_approx(cat.pet_remaining, 1.4), "pet response advances on Dynamic delta while travel stays paused")
	check(cat.motion.global_position().is_equal_approx(before_pet_position), "pet response preserves its contact position")

	var before_static_elapsed: float = cat.elapsed
	var before_static_pet: float = cat.pet_remaining
	var before_static_alpha: float = _cat_alpha()
	_set_context({"dynamic_enabled": false})
	check(cat.pose_index == 13 and not _hotspot_available(), "Static settles travel and disables interaction")
	cat.advance(5.0)
	check(is_equal_approx(cat.elapsed, before_static_elapsed), "Static freezes the adapter clock")
	check(is_equal_approx(cat.pet_remaining, before_static_pet), "Static freezes the pet response clock")
	check(cat.motion.global_position().is_equal_approx(before_pet_position), "Static preserves the route contact position")
	check(is_equal_approx(_cat_alpha(), before_static_alpha), "Static preserves the current fade alpha")
	check(cat.motion.facing_x() == before_facing, "Static preserves the route facing")

	_set_context({"dynamic_enabled": true})
	cat.advance(before_static_pet)
	check(cat.pet_remaining == 0.0 and cat.pose_index != 7, "pet response finishes after Dynamic resumes")
	check(cat.motion.global_position().is_equal_approx(before_pet_position), "route does not jump when the pet response ends")
	check(cat.motion.facing_x() == before_facing, "route resumes with its original facing")
	cat.advance(0.25)
	check(not cat.motion.global_position().is_equal_approx(before_pet_position), "route resumes after the pet response")


func _test_reverse_pose_and_contact() -> void:
	var return_start := 6.0 + 2.0 + path.curve.get_baked_length() / CatDeskMotion.WALK_SPEED + 3.0 + 8.0
	var remaining := return_start - float(cat.motion.activity_elapsed) + 0.25
	cat.advance(remaining)
	check(cat.pose_index >= 8 and cat.pose_index <= 11, "return route uses a walking atlas pose")
	check(cat.motion.facing_x() < 0.0, "return travel faces left along the same path")
	_assert_current_contact(-1.0, "left-facing walk")


func _test_rain_fade_and_static_resume() -> void:
	var before_rain: Vector2 = cat.motion.global_position()
	var before_motion_time: float = cat.motion.activity_elapsed
	_set_context({"weather_id": "light_rain"})
	check(not cat.pet(), "exposed-bank rain blocks petting immediately")
	cat.advance(0.75)
	check(is_equal_approx(_cat_alpha(), 0.5), "rain fades the resident to half alpha over 0.75 dynamic seconds")
	check(cat.motion.global_position().is_equal_approx(before_rain), "rain pauses travel at its current contact")
	check(is_equal_approx(cat.motion.activity_elapsed, before_motion_time), "rain pauses the route phase clock")
	check(not _hotspot_available(), "rain disables the pet hotspot")

	_set_context({"dynamic_enabled": false})
	var frozen_alpha := _cat_alpha()
	cat.advance(0.75)
	check(is_equal_approx(_cat_alpha(), frozen_alpha), "Static freezes a rain fade in progress")
	_set_context({"weather_id": "clear"})
	cat.advance(0.75)
	check(is_equal_approx(_cat_alpha(), frozen_alpha), "Static freezes alpha while weather changes")
	_set_context({"dynamic_enabled": true})
	cat.advance(0.75)
	check(is_equal_approx(_cat_alpha(), 1.0), "clear weather restores the resident over 0.75 dynamic seconds")
	check(not cat.motion.global_position().is_equal_approx(before_rain), "clear Dynamic weather resumes travel")
	check(_hotspot_available(), "the restored clear-weather resident is pettable")

	# A fully hidden resident must become perceptible before input is captured.
	_set_context({"weather_id": "light_rain"})
	cat.advance(1.5)
	check(is_zero_approx(_cat_alpha()), "rain can fully hide the resident")
	_set_context({"weather_id": "clear"})
	cat.advance(1.0 / 60.0)
	check(not _hotspot_available(), "first fade-in frame does not expose an invisible hotspot")
	check(not cat.pet(), "first fade-in frame cannot pet an unseen cat")
	check(cat.hotspot.mouse_filter == Control.MOUSE_FILTER_IGNORE, "faint resident passes pointer input through")
	check(cat.hotspot.mouse_default_cursor_shape == Control.CURSOR_ARROW, "faint resident does not reveal a pet cursor")
	cat.advance(0.6)
	check(not _hotspot_available(), "resident below half opacity remains noninteractive")
	cat.advance(0.15)
	check(_hotspot_available(), "perceptible resident enables petting during fade-in")


func _test_reset() -> void:
	check(cat.pet(), "reset fixture enters an active pet response")
	_set_context({"weather_id": "light_rain", "brightness": 0.35, "world_tint": Color(0.7, 0.8, 0.9)})
	cat.advance(0.4)
	check(cat.pet_remaining > 0.0 and _cat_alpha() < 1.0, "reset fixture has active response and weather state")
	cat.reset()
	check(cat.elapsed == 0.0 and cat.pet_remaining == 0.0, "reset clears elapsed and pet response clocks")
	check(cat.pose_index == 0 and is_equal_approx(_cat_alpha(), 1.0), "reset restores the quiet starting pose and alpha")
	check(cat.motion.active and cat.motion.global_position().is_equal_approx(home.global_position), "reset returns the resident to its authored home")
	check(_hotspot_available(), "reset restores the clear resident interaction")
	check(is_equal_approx(cat.sprite.modulate.r, 1.0) and is_equal_approx(cat.sprite.modulate.g, 1.0), "reset clears observed tint and brightness")


func _assert_current_contact(expected_facing: float, label: String) -> void:
	var texture := cat.sprite.texture as AtlasTexture
	if texture == null:
		check(false, "%s keeps its AtlasTexture" % label)
		return
	var pose := int(texture.get_meta("pose_index", -1))
	var layout: Dictionary = _layout_for_pose(pose)
	var frame_data: Dictionary = _frame_for_pose(layout, pose)
	var pivot := _vector(frame_data.get("pivot", []))
	var bounds := _rect(frame_data.get("opaque_bounds", []))
	check(cat.sprite.offset.is_equal_approx(-pivot), "%s uses the pose's recorded contact pivot" % label)
	var contact_offset: Vector2 = (pivot + cat.sprite.offset) * cat.sprite.scale
	check(contact_offset.is_equal_approx(Vector2.ZERO), "%s keeps both mirrored feet on the root contact" % label)
	check(signf(cat.sprite.scale.x) == expected_facing, "%s applies the expected sprite facing" % label)
	var first: Vector2 = cat.sprite.position + (bounds.position + cat.sprite.offset) * cat.sprite.scale
	var last: Vector2 = cat.sprite.position + (bounds.position + bounds.size + cat.sprite.offset) * cat.sprite.scale
	var minimum := Vector2(minf(first.x, last.x), minf(first.y, last.y))
	var maximum := Vector2(maxf(first.x, last.x), maxf(first.y, last.y))
	var expected_hotspot := Rect2(minimum, maximum - minimum).grow(4.0)
	check(cat.hotspot.position.is_equal_approx(expected_hotspot.position), "%s hotspot follows the mirrored opaque bounds" % label)
	check(cat.hotspot.size.is_equal_approx(expected_hotspot.size), "%s hotspot uses the scaled opaque bounds" % label)


func _layout_for_pose(pose: int) -> Dictionary:
	var file_path := PAINTERLY_LAYOUT_PATH if pose < 8 else DESK_LAYOUT_PATH
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	return value as Dictionary if value is Dictionary else {}


func _frame_for_pose(layout: Dictionary, pose: int) -> Dictionary:
	var index := pose if pose < 8 else pose - 8
	var frames: Array = layout.get("frames", [])
	return frames[index] as Dictionary if index >= 0 and index < frames.size() and frames[index] is Dictionary else {}


func _vector(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() < 2:
		return Vector2.ZERO
	var values: Array = value
	return Vector2(float(values[0]), float(values[1]))


func _rect(value: Variant) -> Rect2:
	if not value is Array or (value as Array).size() < 4:
		return Rect2()
	var values: Array = value
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


func _set_context(overrides: Dictionary) -> void:
	for key in overrides:
		observed_context[key] = overrides[key]
	cat.observe(observed_context.duplicate())


func _hotspot_available() -> bool:
	return cat.hotspot.visible and not cat.hotspot.disabled and cat.hotspot.mouse_filter == Control.MOUSE_FILTER_STOP


func _cat_alpha() -> float:
	return cat.sprite.get_parent().modulate.a


func _on_cat_petted() -> void:
	pet_signal_count += 1


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _finish() -> void:
	print("Stream Teahouse cat checks: %d total, %d failures" % [checks, failures])
	if is_instance_valid(cat):
		cat.queue_free()
	if is_instance_valid(world):
		world.queue_free()
	quit(1 if failures else 0)
