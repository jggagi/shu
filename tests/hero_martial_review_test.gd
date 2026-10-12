extends SceneTree

var scene: Control
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene_path := str(ProjectSettings.get_setting("application/run/main_scene"))
	var shot := ""
	if scene_path.ends_with("hero_martial_sword.tscn"):
		shot = "sword"
	elif scene_path.ends_with("hero_martial_fist.tscn"):
		shot = "fist"
	if shot.is_empty():
		check(false, "staged main scene is one of the two hero martial reviews")
		_finish()
		return
	var expected := _shot_contract(shot)
	scene = load(scene_path).instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var clip = scene.clip
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected.manifest))
	var state_before := _snapshot(scene.state)

	check(clip.manifest_path == expected.manifest, "selected scene loads its shot manifest")
	check(clip.data.shot_id == expected.shot_id, "selected manifest matches the expected shot id")
	check(clip.frames.size() == expected.frame_count, "selected native frame count loads")
	check(manifest.frame_count == expected.frame_count and manifest.fps_rational == "25/1", "manifest count and rational frame rate match the shot")
	check(is_equal_approx(clip.fps, 25.0) and is_equal_approx(clip.fps, float(manifest.fps)), "native 25 fps timing is retained")
	check(is_equal_approx(clip.duration, expected.duration) and is_equal_approx(clip.duration, float(manifest.duration)), "native shot duration is retained")
	check(manifest.width == 480 and manifest.height == 480 and manifest.cell_scale == 0.5, "manifest specifies 480 square cells at half source scale")
	check(clip.position == Vector2(1010, 565) and clip.scale == Vector2.ONE * expected.actor_scale, "review actor uses the shot calibration position and scale")
	check(scene.action_label == expected.action_label, "review presents the selected move label")
	check(scene.review_header == expected.review_header, "review header names the selected move")
	check(FileAccess.file_exists("res://" + expected.asset_dir + "/source.json"), "selected source metadata is staged")
	check(not FileAccess.file_exists("res://" + expected.asset_dir + "/source.mp4"), "source video is omitted from review staging")
	check(clip.fixed_source_anchor_override_enabled, "new review enables its fixed source-space anchor")
	var expected_anchor: Vector2 = expected.anchor * float(manifest.cell_scale)
	check(clip.anchors.size() == expected.frame_count, "one source anchor is prepared for every frame")
	check(clip.paused and clip.frame_index == 0, "review starts paused on the first frame")
	for i in clip.frames.size():
		var frame: AtlasTexture = clip.frames[i]
		var entry: Dictionary = manifest.frames[i]
		check(frame.atlas != null and frame.region.size == Vector2(480, 480), "frame %d has a fixed-size atlas cell" % i)
		check(Rect2(Vector2.ZERO, frame.atlas.get_size()).encloses(frame.region), "frame %d region stays inside its atlas page" % i)
		check(ResourceLoader.exists(entry.path), "frame %d atlas resource exists" % i)
		check(clip.anchors[i] == expected_anchor, "frame %d retains the fixed source-space anchor" % i)
		clip.seek(float(i) / clip.fps)
		check(clip.sprite.position == -expected_anchor, "frame %d does not derive its position from a changing foot pixel" % i)

	check(scene.clean_manifest_path.is_empty() and scene.clean_frames.is_empty(), "no clean-matte A/B package is loaded for this shot")
	check(not scene.matte_enabled and not scene.matte_button.visible and scene.matte_button.disabled, "matte toggle is disabled when clean manifest is empty")
	check(scene.timeline.max_value == clip.duration, "timeline maximum follows the native shot duration")

	clip.replay()
	clip.advance(0.5)
	check(not clip.paused and is_equal_approx(clip.seconds, 0.5) and clip.frame_index == 12, "normal-speed playback samples the native 25 fps timeline")
	var paused_seconds: float = clip.seconds
	clip.paused = true
	clip.advance(0.25)
	check(is_equal_approx(clip.seconds, paused_seconds), "pause freezes the source timeline")
	clip.speed = 0.5
	clip.paused = false
	clip.advance(0.2)
	check(is_equal_approx(clip.seconds, paused_seconds + 0.1), "half speed advances the same source timeline")
	clip.paused = true
	clip.seek(clip.duration * 0.5)
	check(clip.frame_index == int(floor(clip.duration * 0.5 * clip.fps)), "seek chooses the native frame for its timestamp")
	clip.replay()
	check(clip.frame_index == 0 and not clip.paused, "replay returns to frame zero and starts playback")
	clip.speed = 1.0
	var completed := [0]
	clip.completed.connect(func(): completed[0] += 1)
	clip.advance(clip.duration * 2.0)
	check(clip.paused and clip.frame_index == expected.frame_count - 1 and completed[0] == 1, "single shot stops on the last frame and emits completion once")
	clip.advance(clip.duration)
	check(clip.frame_index == expected.frame_count - 1 and completed[0] == 1, "last frame holds without looping or repeated completion")

	clip.replay()
	clip.advance(0.4)
	var playing_seconds: float = clip.seconds
	scene.set_dynamic(false)
	scene._process(0.3)
	check(not scene.dynamic_enabled and clip.paused and is_equal_approx(clip.seconds, playing_seconds), "Static pauses and holds the current review frame")
	check(_snapshot(scene.state) == state_before, "Static leaves the deep DemoState snapshot unchanged")
	scene.set_dynamic(true)
	scene._process(0.1)
	check(scene.dynamic_enabled and not clip.paused and clip.seconds > playing_seconds, "Resume continues the same review timeline")
	check(_snapshot(scene.state) == state_before, "Resume leaves the deep DemoState snapshot unchanged")
	scene._next_pilot_time()
	scene._next_pilot_weather()
	check(_snapshot(scene.state) == state_before, "time and weather review controls leave DemoState unchanged")

	scene.queue_free()
	await process_frame
	_finish()

func _shot_contract(shot: String) -> Dictionary:
	if shot == "sword":
		return {
			"manifest": "res://assets/art/hero_martial_v1/jiang-sword-horizontal-return-v1/atlas.json",
			"asset_dir": "assets/art/hero_martial_v1/jiang-sword-horizontal-return-v1",
			"shot_id": "jiang-sword-horizontal-return-v1",
			"frame_count": 50,
			"duration": 2.0,
			"actor_scale": 0.78,
			"action_label": "横抹回剑",
			"review_header": "后山 · 横抹回剑",
			"anchor": Vector2(424, 904),
		}
	return {
		"manifest": "res://assets/art/hero_martial_v1/jiang-fist-straight-punch-v1/atlas.json",
		"asset_dir": "assets/art/hero_martial_v1/jiang-fist-straight-punch-v1",
		"shot_id": "jiang-fist-straight-punch-v1",
		"frame_count": 53,
		"duration": 2.12,
		"actor_scale": 0.90,
		"action_label": "站桩冲拳",
		"review_header": "后山 · 站桩冲拳",
		"anchor": Vector2(522, 810),
	}

func _snapshot(state: Object) -> PackedByteArray:
	var values: Dictionary = {}
	for property: Dictionary in state.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = state.get(property.name)
	return var_to_bytes(values)

func _finish() -> void:
	print("HERO_MARTIAL_REVIEW_TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
