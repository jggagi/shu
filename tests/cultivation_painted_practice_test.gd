extends SceneTree
## Presenter contract only: real motion resources provide timing; no Session
## receipt, cultivation result or business settlement is fabricated here.

const ActorScript = preload("res://addons/cultivation_mode/painted_practice_actor.gd")
const LoaderScript = preload("res://addons/cultivation_mode/pack_loader.gd")
const MotionAssetsScript = preload("res://addons/cultivation_mode/motion_assets.gd")
const MANIFEST := "res://games/shu_first_journey/game.json"
const PORTRAIT_PATH := "res://assets/art/back_mountain_training/actor-sheet.png"
const MOTION_ID := "jiang_sword"
const CLIP_ID := "songfeng"
var checks := 0
var failures := 0
var pack: Dictionary = {}
var idle_assets: Dictionary = {}
var action_assets: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = LoaderScript.new().load_pack(MANIFEST)
	check(bool(loaded.get("ok", false)), "real chapter pack loads: " + str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	pack = loaded.pack
	var assets_loader: RefCounted = MotionAssetsScript.new()
	var idle: Dictionary = assets_loader.call("load_idle", pack, MOTION_ID)
	var action: Dictionary = assets_loader.call("prepare", pack, MOTION_ID, CLIP_ID)
	check(bool(idle.get("ok", false)), "actual registered idle assets preflight: " + str(idle.get("reason", "")))
	check(bool(action.get("ok", false)), "actual registered action assets preflight: " + str(action.get("reason", "")))
	if not bool(idle.get("ok", false)) or not bool(action.get("ok", false)):
		_finish()
		return
	idle_assets = idle.assets
	action_assets = action.assets
	check(not action_assets.action_frames.is_empty() and not action_assets.action_atlas_paths.is_empty(), "timing input contains the real registered model frames so portrait routing is exercised")
	_test_resource_preflight_and_rejections()
	_test_phases_and_operation_identity()
	_test_large_delta_and_completed_replay()
	_finish()


func _new_actor() -> Control:
	var actor: Control = ActorScript.new()
	root.add_child(actor)
	# Every clock step below is explicit; live scene processing cannot race the
	# phase assertions or hide a completion behind a background frame.
	actor.set_process(false)
	return actor


func _configure(actor: Control) -> bool:
	var configured: Dictionary = actor.call("configure_idle", pack.motions[MOTION_ID], idle_assets)
	check(bool(configured.get("ok", false)), "painted actor checks actual portrait resource: " + str(configured.get("reason", "")))
	check(bool(actor.call("is_prepared")), "successful preflight makes the portrait ready")
	return bool(configured.get("ok", false))


func _pending(operation: String = "practice-one", run: String = "painted-presenter-test-run") -> Dictionary:
	# Test identities exercise the presenter protocol, while every timing and
	# source frame comes from MotionAssets.prepare. There is no fake receipt.
	return {"run_id": run, "operation_id": operation, "motion_id": MOTION_ID,
		"clip_id": CLIP_ID, "assets": action_assets}


func _test_resource_preflight_and_rejections() -> void:
	var actor := _new_actor()
	var unprepared: Dictionary = actor.call("presentation_snapshot")
	check(not bool(actor.call("is_prepared")), "new actor starts unprepared")
	_rejected(actor, actor.call("play_presentation", _pending()), unprepared, "unprepared actor cannot begin a practice")
	var invalid_idle: Dictionary = idle_assets.duplicate()
	invalid_idle.motion_id = ""
	_rejected(actor, actor.call("configure_idle", pack.motions[MOTION_ID], invalid_idle), unprepared, "missing registered motion identity cannot prepare the portrait")
	invalid_idle = idle_assets.duplicate()
	invalid_idle.hold_seconds = -1.0
	_rejected(actor, actor.call("configure_idle", pack.motions[MOTION_ID], invalid_idle), unprepared, "invalid recovery duration cannot prepare the portrait")
	if not _configure(actor):
		actor.free()
		return
	actor.call("set_scene_layout", Vector2(1280.0, 720.0), 0.68, 0.9, 0.65, false)
	check(actor.size.x > 0.0 and actor.size.y > 0.0, "prepared portrait supports existing scene-layout API")
	_assert_painted_texture(actor, false)
	var ready: Dictionary = actor.call("presentation_snapshot")
	for key: String in ["run_id", "operation_id", "motion_id", "clip_id"]:
		var missing: Dictionary = _pending().duplicate()
		missing[key] = ""
		_rejected(actor, actor.call("play_presentation", missing), ready, "missing " + key + " cannot begin practice")
	var malformed: Dictionary = _pending().duplicate()
	malformed["assets"] = {"action_frames": [], "action_fps": 30.0}
	_rejected(actor, actor.call("play_presentation", malformed), ready, "missing real action duration cannot begin practice")
	malformed = _pending().duplicate()
	malformed["assets"] = action_assets.duplicate()
	malformed.assets.action_fps = 0.0
	_rejected(actor, actor.call("play_presentation", malformed), ready, "zero frame rate cannot begin practice")
	check(int(ready.completion_count) == 0, "resource preflight and rejected starts never finish a practice")
	actor.free()


func _test_phases_and_operation_identity() -> void:
	var actor := _new_actor()
	if not _configure(actor):
		actor.free()
		return
	var completions: Array[Dictionary] = []
	var phases: Array[String] = []
	_observe(actor, completions, phases)
	var pending := _pending()
	check(bool(actor.call("play_presentation", pending).get("ok", false)), "real motion timing begins painted presentation")
	var begun: Dictionary = actor.call("presentation_snapshot")
	check(begun.playing and not begun.neutral and begun.phase == "settle", "practice begins busy in prepare phase")
	check(begun.run_id == pending.run_id and begun.operation_id == pending.operation_id and begun.clip_id == CLIP_ID, "presenter retains exact run, operation and selected clip identity")
	check(is_equal_approx(float(begun.action_duration), float(action_assets.action_frames.size()) / float(action_assets.action_fps)), "painted duration follows actual selected motion timing")
	_rejected(actor, actor.call("configure_idle", pack.motions[MOTION_ID], idle_assets), begun, "busy actor cannot replace prepared portrait")
	_rejected(actor, actor.call("play_presentation", _pending("other-operation")), begun, "busy actor refuses another operation")
	_rejected(actor, actor.call("play_presentation", _pending("practice-one", "other-run")), begun, "busy actor refuses another run")
	var duplicate: Dictionary = actor.call("play_presentation", pending)
	check(bool(duplicate.get("already_playing", false)) and actor.call("presentation_snapshot") == begun, "same live operation is idempotent and does not restart clock")
	actor.call("_process", float(begun.settle_seconds))
	var active: Dictionary = actor.call("presentation_snapshot")
	check(active.phase == "action" and active.playing and completions.is_empty(), "elapsed preparation enters actual practice without completing early")
	_assert_painted_texture(actor, true)
	actor.call("_process", float(active.action_duration))
	var recovering: Dictionary = actor.call("presentation_snapshot")
	check(recovering.phase == "neutral_hold" and recovering.playing and not recovering.neutral and completions.is_empty(), "actual practice duration enters recovery while host completion remains pending")
	_assert_painted_texture(actor, false)
	var remaining := float(recovering.hold_seconds)
	check(remaining > 0.0, "selected real motion has a recovery hold to test")
	actor.call("_process", remaining * 0.5)
	check(completions.is_empty() and actor.call("presentation_snapshot").playing, "half of recovery cannot release busy state")
	actor.call("_process", remaining * 0.5)
	var finished: Dictionary = actor.call("presentation_snapshot")
	check(not finished.playing and finished.neutral and finished.phase == "idle" and int(finished.completion_count) == 1, "recovery completes once and returns to neutral idle")
	check(phases == ["settle", "action", "neutral_hold", "idle"], "phase observer sees one ordered prepare/practice/recovery/idle sequence")
	check(completions.size() == 1 and completions[0].run_id == pending.run_id and completions[0].operation_id == pending.operation_id, "one finished callback carries exact original operation identity")
	if completions.size() == 1:
		var at_callback: Dictionary = completions[0].snapshot
		check(not at_callback.playing and at_callback.neutral and at_callback.phase == "idle", "finished observer sees stopped neutral presenter before host may release action")
	_assert_painted_texture(actor, false)
	actor.free()


func _test_large_delta_and_completed_replay() -> void:
	var actor := _new_actor()
	if not _configure(actor):
		actor.free()
		return
	var completions: Array[Dictionary] = []
	var phases: Array[String] = []
	_observe(actor, completions, phases)
	var pending := _pending("large-wall-clock-step")
	check(bool(actor.call("play_presentation", pending).get("ok", false)), "large-delta case begins ordinary registered practice")
	var before: Dictionary = actor.call("presentation_snapshot")
	for invalid_delta: float in [-1.0, INF, NAN]:
		actor.call("_process", invalid_delta)
		check(actor.call("presentation_snapshot") == before and completions.is_empty(), "invalid wall-clock delta cannot advance or finish presentation")
	var total_duration := float(before.settle_seconds) + float(before.action_duration) + float(before.hold_seconds)
	actor.call("_process", total_duration + 60.0)
	var finished: Dictionary = actor.call("presentation_snapshot")
	check(not finished.playing and finished.neutral and finished.phase == "idle" and int(finished.completion_count) == 1 and completions.size() == 1, "one large finite wall-clock delta consumes all phases and finishes exactly once")
	check(phases == ["settle", "action", "neutral_hold", "idle"], "large delta still reports ordered phases")
	var duplicate: Dictionary = actor.call("play_presentation", pending)
	check(bool(duplicate.get("already_completed", false)) and actor.call("presentation_snapshot") == finished, "replayed completed operation neither restarts nor emits another callback")
	var wrong_clip: Dictionary = pending.duplicate()
	wrong_clip.clip_id = "chuanyun"
	_rejected(actor, actor.call("play_presentation", wrong_clip), finished, "completed operation cannot be reused for another clip")
	check(bool(actor.call("configure_idle", pack.motions[MOTION_ID], idle_assets).get("ok", false)), "scene may safely refresh same prepared motion after completion")
	check(bool(actor.call("play_presentation", pending).get("already_completed", false)), "same-motion reconfiguration preserves completed operation identity")
	actor.call("_process", total_duration + 120.0)
	check(completions.size() == 1 and int(actor.call("presentation_snapshot").completion_count) == 1, "further idle time cannot repeat completed callback")
	check(bool(actor.call("play_presentation", _pending("new-independent-operation")).get("ok", false)), "a distinct next practice can begin after neutral return")
	actor.call("_process", total_duration + 60.0)
	check(completions.size() == 2 and completions[1].operation_id == "new-independent-operation", "next operation receives its own single completion")
	_assert_painted_texture(actor, false)
	actor.free()


func _observe(actor: Control, completions: Array[Dictionary], phases: Array[String]) -> void:
	actor.connect("phase_changed", func(phase: String, _label: String) -> void: phases.append(phase))
	actor.connect("finished", func(run_id: String, operation_id: String) -> void:
		completions.append({"run_id": run_id, "operation_id": operation_id,
			"snapshot": actor.call("presentation_snapshot")})
	)


func _assert_painted_texture(actor: Control, closed: bool) -> void:
	var snapshot: Dictionary = actor.call("presentation_snapshot")
	check(snapshot.route == "painted_2d_portrait" and snapshot.texture_path == PORTRAIT_PATH, "presenter declares original painted-portrait route")
	for key: String in ["loaded_action_atlas_paths", "loaded_idle_atlas_paths", "idle_atlas_paths"]:
		var paths: Array = snapshot.get(key, [])
		check(paths == [PORTRAIT_PATH], key + " contains only original portrait sheet, never model atlases")
	var frame := actor.get_node_or_null("PaintedPortraitFrame") as TextureRect
	check(frame != null and frame.texture is AtlasTexture, "actual rendered texture is an original-portrait atlas cell")
	if frame == null or not frame.texture is AtlasTexture:
		return
	var painted := frame.texture as AtlasTexture
	check(painted.atlas != null and painted.atlas.resource_path == PORTRAIT_PATH and Vector2i(painted.atlas.get_size()) == Vector2i(1774, 887), "actual rendered atlas is the real 1774x887 painted resource")
	check(painted.region == Rect2(887 if closed else 0, 0, 887, 887), "actual painted cell follows open/closed practice state")
	var pixels: Image = painted.get_image()
	check(pixels != null and not pixels.is_empty() and pixels.get_size() == Vector2i(887, 887) and pixels.get_used_rect().size != Vector2i.ZERO, "selected original portrait cell contains real nonempty pixels")
	if pixels == null or pixels.is_empty():
		return
	if pixels.is_compressed():
		check(pixels.decompress() == OK, "painted cell pixels decode for transparency inspection")
	check(pixels.detect_alpha() != Image.ALPHA_NONE and pixels.get_pixel(0, 0).a <= 0.01 and pixels.get_pixel(886, 0).a <= 0.01, "actual original portrait retains transparent background and clear outer margin")


func _rejected(actor: Control, result: Dictionary, before: Dictionary, label: String) -> void:
	check(not bool(result.get("ok", false)) and actor.call("presentation_snapshot") == before, label + " without presenter-state mutation")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _finish() -> void:
	print("PAINTED_PRACTICE_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
