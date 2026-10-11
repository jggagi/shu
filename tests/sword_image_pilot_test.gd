extends SceneTree
var scene: Control
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	scene = load("res://scenes/demos/sword_image_back_mountain.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var clip = scene.clip
	var before := _snapshot(scene.state)
	check(clip.frames.size() == 61 and is_equal_approx(clip.fps, 25.0), "all 61 native 25 fps frames load")
	check(clip.paused and clip.frame_index == 0, "initial frame is visible and waiting")
	check(scene.blend_enabled, "scene blending starts enabled")
	check(clip.sprite.material is ShaderMaterial, "blended mode assigns the actor shader")
	check(scene.contact_shadow.visible and not scene.legacy_contact_shadow.visible, "blended mode uses the soft contact shadow")
	check(scene.paper_enabled and is_equal_approx(float(scene.blend_material.get_shader_parameter("paper_strength")), 0.85), "light paper texture starts enabled")
	check(scene.paper_button.text == "轻纸感" and not scene.paper_button.disabled, "paper control starts available with its enabled label")
	check(scene.matte_enabled and scene.clip.frames == scene.clean_frames, "clean matte starts selected")
	check(scene.matte_button.text == "干净边缘" and not scene.matte_button.disabled, "matte control starts enabled with its clean label")
	check(scene.original_frames.size() == 61 and scene.clean_frames.size() == 61, "original and clean matte arrays each contain 61 frames")
	check(scene.actor_hotspot == null and scene.sword_hotspot == null and scene.lighting == null, "no old training actions or lighting harness")
	for i in clip.frames.size():
		var frame: AtlasTexture = clip.frames[i]
		check(frame.atlas != null and Rect2(Vector2.ZERO, frame.atlas.get_size()).encloses(frame.region), "valid atlas region %d" % i)
		check(frame.region.size == Vector2(384, 576), "fixed full-frame crop %d" % i)
	clip.replay()
	clip.advance(1.0)
	check(clip.frame_index == 25 and not clip.paused, "25 fps playback samples correct frame")
	_exercise_blend_preservation("live playback")
	_exercise_paper_preservation("live playback")
	_exercise_matte_preservation("live playback")
	var saved: float = clip.seconds
	clip.paused = true
	clip.advance(0.5)
	check(is_equal_approx(clip.seconds, saved), "pause freezes the clip")
	_exercise_blend_preservation("paused playback")
	_exercise_paper_preservation("paused playback")
	_exercise_matte_preservation("paused playback")
	clip.paused = false
	scene.set_dynamic(false)
	scene._process(0.4)
	check(is_equal_approx(clip.seconds, saved), "Static freezes actor")
	_exercise_blend_preservation("Static scene")
	_exercise_paper_preservation("Static scene")
	_exercise_matte_preservation("Static scene")
	scene.set_dynamic(true)
	scene._process(0.1)
	check(clip.seconds > saved, "Dynamic resumes current frame")
	var fired := [0]
	clip.completed.connect(func(): fired[0] += 1)
	clip.advance(10.0)
	check(clip.paused and clip.frame_index == 60 and fired[0] == 1, "one-shot holds last frame and emits once")
	clip.advance(10.0)
	check(clip.frame_index == 60 and fired[0] == 1, "end never loops or repeatedly completes")
	clip.replay()
	clip.speed = 0.5
	clip.advance(0.8)
	check(is_equal_approx(clip.seconds, 0.4) and clip.frame_index == 10, "half-speed uses same source frames")
	var scale_before: Vector2 = clip.scale
	for i in 61:
		clip.seek(float(i) / 25.0)
		check(clip.scale == scale_before and clip.sprite.modulate.a == 1.0, "constant scale/opacity %d" % i)
	scene._next_pilot_time()
	scene._next_pilot_weather()
	var prior_tint: Color = scene._displayed_tint
	scene.environment_presenter.set_time_profile("you", false)
	scene.environment_presenter.set_weather("light_rain", false)
	scene._apply_environment()
	check(scene._displayed_tint != prior_tint, "dusk and rain still change the painted world tint")
	check(clip.modulate == scene._displayed_tint, "blended actor follows dusk and rain world modulation")
	scene.set_scene_blending(false)
	check(clip.modulate == scene._displayed_tint, "original-color actor still follows dusk and rain world modulation")
	scene.set_scene_blending(true)
	for paper_enabled in [false, true]:
		scene.set_paper_texture(paper_enabled)
		var expected_strength := 0.85 if paper_enabled else 0.0
		scene.set_scene_blending(false)
		check(scene.paper_button.disabled and scene.paper_enabled == paper_enabled, "original-color mode disables the paper control and retains its preference")
		check(is_equal_approx(float(scene.blend_material.get_shader_parameter("paper_strength")), expected_strength), "original-color mode retains paper strength")
		scene.set_scene_blending(true)
		check(not scene.paper_button.disabled and scene.paper_enabled == paper_enabled, "returning to blended mode restores the retained paper preference")
		check(scene.paper_button.text == ("轻纸感" if paper_enabled else "无纸感"), "paper control label matches the retained preference")
	_exercise_matte_source_color_independence()
	check(_snapshot(scene.state) == before, "all gameplay-authoritative fields unchanged by playback/seek/weather/time")
	scene.queue_free()
	await process_frame
	print("SWORD_IMAGE_PILOT_TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
func _exercise_blend_preservation(label: String) -> void:
	for enabled in [false, true]:
		var seconds_before: float = scene.clip.seconds
		var frame_before: int = scene.clip.frame_index
		var paused_before: bool = scene.clip.paused
		var speed_before: float = scene.clip.speed
		var scale_before: Vector2 = scene.clip.scale
		var position_before: Vector2 = scene.clip.sprite.position
		var dynamic_before: bool = scene.dynamic_enabled
		var presentation_before: float = scene.presentation_time
		var state_before: PackedByteArray = _snapshot(scene.state)
		var environment_before: PackedByteArray = _snapshot(scene.environment_presenter)
		var tint_before: Color = scene._displayed_tint
		scene.set_scene_blending(enabled)
		var mode := "on" if enabled else "off"
		check(scene.blend_enabled == enabled, "%s blend toggle reaches %s mode" % [label, mode])
		check((scene.clip.sprite.material is ShaderMaterial) == enabled, "%s %s mode has the expected actor material" % [label, mode])
		check(scene.contact_shadow.visible == enabled and scene.legacy_contact_shadow.visible == not enabled, "%s %s mode selects its contact shadow" % [label, mode])
		check(is_equal_approx(scene.clip.seconds, seconds_before) and scene.clip.frame_index == frame_before, "%s %s toggle preserves clip time and frame" % [label, mode])
		check(scene.clip.paused == paused_before and is_equal_approx(scene.clip.speed, speed_before), "%s %s toggle preserves pause and speed" % [label, mode])
		check(scene.clip.scale == scale_before and scene.clip.sprite.position == position_before, "%s %s toggle preserves actor scale and anchor position" % [label, mode])
		check(scene.dynamic_enabled == dynamic_before and is_equal_approx(scene.presentation_time, presentation_before), "%s %s toggle preserves Dynamic and presentation time" % [label, mode])
		check(_snapshot(scene.state) == state_before, "%s %s toggle preserves DemoState snapshot bytes" % [label, mode])
		check(_snapshot(scene.environment_presenter) == environment_before, "%s %s toggle preserves the environment presenter" % [label, mode])
		check(scene._displayed_tint == tint_before and scene.clip.modulate == tint_before, "%s %s toggle preserves current world modulation" % [label, mode])

func _exercise_paper_preservation(label: String) -> void:
	for enabled in [false, true]:
		var seconds_before: float = scene.clip.seconds
		var frame_before: int = scene.clip.frame_index
		var paused_before: bool = scene.clip.paused
		var speed_before: float = scene.clip.speed
		var scale_before: Vector2 = scene.clip.scale
		var position_before: Vector2 = scene.clip.sprite.position
		var presentation_before: float = scene.presentation_time
		var state_before: PackedByteArray = _snapshot(scene.state)
		var environment_before: PackedByteArray = _snapshot(scene.environment_presenter)
		var dynamic_before: bool = scene.dynamic_enabled
		var shadow_transform_before: Transform2D = scene.contact_shadow.get_global_transform_with_canvas()
		var shadow_texture_before: Texture2D = scene.contact_shadow.texture
		var shadow_visible_before: bool = scene.contact_shadow.visible
		scene.set_paper_texture(enabled)
		var expected_strength := 0.85 if enabled else 0.0
		var mode := "on" if enabled else "off"
		check(scene.paper_enabled == enabled and is_equal_approx(float(scene.blend_material.get_shader_parameter("paper_strength")), expected_strength), "%s paper toggle reaches %s strength" % [label, mode])
		check(scene.paper_button.text == ("轻纸感" if enabled else "无纸感") and not scene.paper_button.disabled, "%s paper control reflects %s preference" % [label, mode])
		check(scene.clip.seconds == seconds_before and scene.clip.frame_index == frame_before and scene.clip.paused == paused_before, "%s paper toggle preserves exact clip time, frame, and pause" % label)
		check(scene.clip.speed == speed_before and scene.clip.scale == scale_before and scene.clip.sprite.position == position_before, "%s paper toggle preserves speed, scale, and anchor" % label)
		check(scene.presentation_time == presentation_before and scene.dynamic_enabled == dynamic_before, "%s paper toggle preserves presentation time and Dynamic state" % label)
		check(scene.contact_shadow.get_global_transform_with_canvas() == shadow_transform_before and scene.contact_shadow.texture == shadow_texture_before and scene.contact_shadow.visible == shadow_visible_before, "%s paper toggle preserves contact-shadow geometry and texture" % label)
		check(_snapshot(scene.state) == state_before and _snapshot(scene.environment_presenter) == environment_before, "%s paper toggle preserves DemoState and environment snapshots" % label)


func _exercise_matte_preservation(label: String) -> void:
	for enabled in [false, true]:
		var clip = scene.clip
		var seconds_before: float = clip.seconds
		var frame_before: int = clip.frame_index
		var paused_before: bool = clip.paused
		var speed_before: float = clip.speed
		var fps_before: float = clip.fps
		var duration_before: float = clip.duration
		var clip_position_before: Vector2 = clip.position
		var clip_scale_before: Vector2 = clip.scale
		var sprite_position_before: Vector2 = clip.sprite.position
		var sprite_scale_before: Vector2 = clip.sprite.scale
		var sprite_rect_before: Rect2 = clip.sprite.get_rect()
		var sprite_size_before: Vector2 = clip.sprite.texture.get_size()
		var sprite_transform_before: Transform2D = clip.sprite.get_global_transform_with_canvas()
		var anchors_before: PackedByteArray = var_to_bytes(clip.anchors)
		var data_before: PackedByteArray = var_to_bytes(clip.data)
		var dynamic_before: bool = scene.dynamic_enabled
		var presentation_before: float = scene.presentation_time
		var state_before: PackedByteArray = _snapshot(scene.state)
		var environment_before: PackedByteArray = _snapshot(scene.environment_presenter)
		var tint_before: Color = scene._displayed_tint
		var blend_before: bool = scene.blend_enabled
		var material_before: Material = clip.sprite.material
		var paper_before: bool = scene.paper_enabled
		var paper_strength_before: float = float(scene.blend_material.get_shader_parameter("paper_strength"))
		var paper_label_before: String = scene.paper_button.text
		var paper_disabled_before: bool = scene.paper_button.disabled
		var blend_label_before: String = scene.blend_button.text
		var expected_frames: Array = scene.clean_frames if enabled else scene.original_frames

		scene.set_matte_cleanup(enabled)
		var mode := "clean" if enabled else "original"
		check(scene.matte_enabled == enabled and clip.frames == expected_frames, "%s matte toggle selects the %s frame array" % [label, mode])
		check(clip.sprite.texture == expected_frames[frame_before], "%s %s mode displays the chosen array's current texture" % [label, mode])
		check(scene.matte_button.text == ("干净边缘" if enabled else "原始边缘") and not scene.matte_button.disabled, "%s matte button reflects %s and stays enabled" % [label, mode])
		check(clip.seconds == seconds_before and clip.frame_index == frame_before and clip.paused == paused_before, "%s %s toggle preserves exact seconds, frame, and pause" % [label, mode])
		check(clip.speed == speed_before and clip.fps == fps_before and clip.duration == duration_before, "%s %s toggle preserves speed, fps, and duration" % [label, mode])
		check(clip.position == clip_position_before and clip.scale == clip_scale_before and clip.sprite.position == sprite_position_before and clip.sprite.scale == sprite_scale_before, "%s %s toggle preserves actor position and scale" % [label, mode])
		check(clip.sprite.get_rect() == sprite_rect_before and clip.sprite.texture.get_size() == sprite_size_before and clip.sprite.get_global_transform_with_canvas() == sprite_transform_before, "%s %s toggle preserves actor bounds and transform" % [label, mode])
		check(var_to_bytes(clip.anchors) == anchors_before and var_to_bytes(clip.data) == data_before, "%s %s toggle preserves clip anchors and data" % [label, mode])
		check(scene.dynamic_enabled == dynamic_before and scene.presentation_time == presentation_before, "%s %s toggle preserves Dynamic and presentation time" % [label, mode])
		check(_snapshot(scene.state) == state_before and _snapshot(scene.environment_presenter) == environment_before, "%s %s toggle preserves DemoState and environment snapshots" % [label, mode])
		check(scene._displayed_tint == tint_before and clip.modulate == tint_before, "%s %s toggle preserves current world modulation" % [label, mode])
		check(scene.blend_enabled == blend_before and clip.sprite.material == material_before, "%s %s toggle leaves scene blending and actor material unchanged" % [label, mode])
		check(scene.paper_enabled == paper_before and is_equal_approx(float(scene.blend_material.get_shader_parameter("paper_strength")), paper_strength_before), "%s %s toggle leaves paper preference and shader strength unchanged" % [label, mode])
		check(scene.paper_button.text == paper_label_before and scene.paper_button.disabled == paper_disabled_before and scene.blend_button.text == blend_label_before, "%s %s toggle leaves blend and paper controls unchanged" % [label, mode])

func _exercise_matte_source_color_independence() -> void:
	for enabled in [true, false]:
		scene.set_matte_cleanup(enabled)
		var expected_frames: Array = scene.clean_frames if enabled else scene.original_frames
		var paper_before: bool = scene.paper_enabled
		var paper_strength_before: float = float(scene.blend_material.get_shader_parameter("paper_strength"))
		scene.set_scene_blending(false)
		check(not scene.blend_enabled and scene.clip.sprite.material == null, "source-color mode removes only the actor shader")
		check(scene.matte_enabled == enabled and scene.clip.frames == expected_frames and scene.clip.sprite.texture == expected_frames[scene.clip.frame_index], "source-color mode retains the selected %s matte" % ("clean" if enabled else "original"))
		check(scene.matte_button.text == ("干净边缘" if enabled else "原始边缘") and not scene.matte_button.disabled, "matte control remains available in source-color mode")
		check(scene.paper_enabled == paper_before and scene.paper_button.disabled and is_equal_approx(float(scene.blend_material.get_shader_parameter("paper_strength")), paper_strength_before), "source-color mode retains paper preference while disabling its control")
		scene.set_scene_blending(true)
		check(scene.matte_enabled == enabled and scene.clip.frames == expected_frames and scene.clip.sprite.texture == expected_frames[scene.clip.frame_index], "returning to blended mode retains the selected matte preference")
		check(not scene.paper_button.disabled and scene.paper_enabled == paper_before, "returning to blended mode restores paper control without changing its preference")
	scene.set_matte_cleanup(true)

func _snapshot(state) -> PackedByteArray:
	var snapshot: Dictionary = {}
	for property: Dictionary in state.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			snapshot[property.name] = state.get(property.name)
	return var_to_bytes(snapshot)
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
