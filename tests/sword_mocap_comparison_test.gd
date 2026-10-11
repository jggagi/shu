extends SceneTree

const SCENE_PATH := "res://scenes/demos/sword_mocap_comparison.tscn"
const ATLAS_PATH := "res://assets/art/sword_mocap/atlas.json"
const STUDY_PATH := "res://assets/data/sword_mocap/study.json"

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	check(packed != null, "comparison scene is a loadable PackedScene")
	if packed == null:
		_finish()
		return
	var lab := packed.instantiate()
	root.add_child(lab)
	await process_frame
	check(FileAccess.file_exists(ATLAS_PATH) and FileAccess.file_exists(STUDY_PATH), "study metadata and atlas manifest are present")
	if not FileAccess.file_exists(ATLAS_PATH) or not FileAccess.file_exists(STUDY_PATH):
		_finish()
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_PATH))
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STUDY_PATH))
	var diagnostics: Dictionary = lab.diagnostics()
	check(lab.cards.size() == 2 and lab.cards[0].name == "CandidateB" and lab.cards[1].name == "CandidateC", "comparison exposes exactly the B and C candidate cards")
	var required_assets_loaded: bool = lab.frame_count > 0 and lab.duration > 0.0 and lab.live_model != null and lab.live_camera != null and lab.live_player != null
	check(required_assets_loaded, "study sequence, model, exported camera, and named animation are loaded")
	if not required_assets_loaded:
		_finish()
		return
	lab.playing = false
	check(float(metadata.get("fps", 0.0)) == 60.0 and is_equal_approx(float(diagnostics.fps), 60.0), "shared playback uses the declared 60 fps source clock")
	check(lab.frame_count == int(manifest.get("frame_count", -1)) and lab.frame_count == manifest.get("frames", []).size(), "every declared baked frame is loaded")
	check(lab.live_viewport.size == Vector2i(int(manifest.width), int(manifest.height)), "live transparent viewport uses the atlas source dimensions")
	check(int(manifest.minimum_frame_margin_px) > 48, "identical fixed view crop retains every frame inside the stage")
	check(lab.background_layers[0][0].size == lab.stage_rect.size, "painted background fits its card without covering controls")
	check(lab.live_viewport.transparent_bg and lab.live_viewport.own_world_3d, "live 3D view is isolated and transparent")
	check(lab.live_model != null and lab.live_camera != null and lab.live_camera.current, "C uses the exported study model camera")
	var skeletons: Array[Node] = lab._find_nodes(lab.live_model, "Skeleton3D")
	var cameras: Array[Node] = lab._find_nodes(lab.live_model, "Camera3D")
	check(skeletons.size() == 1 and lab.live_skeleton.get_bone_count() > 0, "C uses the study model's single real Skeleton3D")
	check(cameras.size() == 1 and lab.live_camera == cameras[0], "C retains the one exported study camera")
	var matching_animations: Array[String] = []
	for node: Node in lab._find_nodes(lab.live_model, "AnimationPlayer"):
		for animation_name: StringName in (node as AnimationPlayer).get_animation_list():
			if str(animation_name).to_lower().contains("swordstudy"):
				matching_animations.append(str(animation_name))
	check(matching_animations.size() == 1 and matching_animations[0] == lab.live_animation, "C selects the SwordStudy animation by name containment")
	check(not lab.loop_enabled and lab.duration > 0.0, "clock starts in once mode with a positive study duration")
	check(diagnostics.gameplay_state_instances == 0 and lab.find_children("DemoState", "Node", true, false).is_empty(), "comparison has no gameplay state instance")
	check(str(diagnostics.clip_label) == str(metadata.get("source_label", "")), "diagnostics expose the source clip label")

	var sample_times: Array[float] = [0.0, 0.137, minf(1.237, lab.duration * 0.73), maxf(0.0, lab.duration - 0.002), lab.duration]
	for sample_time: float in sample_times:
		lab.seek_motion(sample_time)
		await process_frame
		diagnostics = lab.diagnostics()
		var expected_index: int = clampi(int(floor(sample_time * lab.fps)), 0, lab.frame_count - 1)
		check(is_equal_approx(float(diagnostics.seconds), sample_time), "shared clock preserves requested seek %.4f" % sample_time)
		check(int(diagnostics.frame_index) == expected_index, "B selects floor(t × fps), clamped to the final frame at %.4f" % sample_time)
		check(lab.baked_actor.texture == lab.baked_frames[expected_index], "B displays the indexed atlas frame at %.4f" % sample_time)
		check(is_equal_approx(float(diagnostics.live_time), sample_time), "C receives the same exact, zero-offset seek at %.4f" % sample_time)
		check(str(diagnostics.assigned_animation).to_lower().contains("swordstudy"), "C retains its assigned SwordStudy clip at %.4f" % sample_time)
	check(int(lab.diagnostics().frame_index) == lab.frame_count - 1, "duration endpoint holds the final available baked frame")

	lab.playing = false
	lab.seek_motion(0.0)
	lab.step_frame(-1)
	check(lab.seconds == 0.0 and int(lab.diagnostics().frame_index) == 0 and not lab.playing, "previous frame clamps at the start and pauses")
	lab.seek_motion(10.25 / lab.fps)
	lab.step_frame(1)
	check(is_equal_approx(lab.seconds, 11.0 / lab.fps) and not lab.playing, "next frame advances one 60 Hz sample from a non-grid seek")
	lab.seek_motion(lab.duration)
	lab.step_frame(1)
	check(lab.seconds == lab.duration and int(lab.diagnostics().frame_index) == lab.frame_count - 1, "next frame at the end remains on the final frame")

	lab.set_speed(0.5)
	check(is_equal_approx(lab.speed, 0.5), "half speed is selectable")
	lab.set_speed(0.25)
	check(is_equal_approx(lab.speed, 0.25), "quarter speed is selectable")
	lab.set_speed(0.75)
	check(is_equal_approx(lab.speed, 0.25), "unsupported speed leaves the selected speed unchanged")
	lab.set_speed(1.0)
	lab.reset_motion()
	check(lab.seconds == 0.0 and is_equal_approx(float(lab.diagnostics().live_time), 0.0), "restart returns both render paths to time zero")
	lab.playing = false
	lab._process(0.5)
	check(lab.seconds == 0.0, "paused processing leaves the shared clock unchanged")
	lab.toggle_play()
	lab._process(0.1)
	check(is_equal_approx(lab.seconds, 0.1), "play advances the shared clock")
	lab.toggle_play()
	var paused_at: float = lab.seconds
	lab._process(0.25)
	check(is_equal_approx(lab.seconds, paused_at), "pause holds the shared clock")

	lab.loop_enabled = false
	lab.seek_motion(lab.duration - 0.01)
	lab.playing = true
	lab._process(0.1)
	check(lab.seconds == lab.duration and not lab.playing, "once mode stops and holds at duration")
	lab.loop_enabled = true
	lab.seek_motion(lab.duration - 0.02)
	lab.playing = true
	lab._process(0.05)
	check(is_equal_approx(lab.seconds, 0.03) and lab.playing, "repeat mode wraps the one shared clock")

	lab.set_single_mode(0)
	check(lab.cards[0].visible and not lab.cards[1].visible, "B-only mode retains the baked candidate")
	lab.set_single_mode(1)
	check(not lab.cards[0].visible and lab.cards[1].visible, "C-only mode retains the live candidate")
	lab.set_single_mode(-1)
	check(lab.cards[0].visible and lab.cards[1].visible, "compare mode restores both equal candidate cards")
	lab.set_background(false)
	check(not lab.background_layers[0][0].visible and not lab.background_layers[1][0].visible, "paper background applies to both candidates")
	lab.set_background(true)
	check(lab.background_layers[0][0].visible and lab.background_layers[1][0].visible, "painted mountain background applies to both candidates")
	_finish()

func check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures.append(detail)
		push_error(detail)

func _finish() -> void:
	print("SWORD_MOCAP_COMPARISON_TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
