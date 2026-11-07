extends Control
## Workshop-backed 3D practice. No EngineSession reference or settlement access.

signal phase_changed(phase: String, label: String)
signal finished(run_id: String, operation_id: String)

const StageScript = preload("res://addons/cultivation_mode/ambush_stage.gd")
const CatalogScript = preload("res://addons/cultivation_mode/martial_move_catalog.gd")
const BindingScript = preload("res://addons/cultivation_mode/martial_actor_binding.gd")
const RulesScript = preload("res://addons/cultivation_mode/ambush_rules.gd")
const COMBINATIONS_PATH := "res://assets/data/martial_workshop/training_combinations.json"
const CLIP_IDS := ["songfeng", "chuanyun", "huilan", "tiaoyue", "xieying"]
const CLOCK_EPSILON := 0.000001

var playing := false
var neutral := true
var motion_id := ""
var clip_id := ""
var run_id := ""
var operation_id := ""
var current_phase := "idle"
var current_phase_label := "静息"
var last_error := ""
var muted := true

var _definition: Dictionary = {}
var _font: Font
var _stage: Control
var _training_dummy: Node3D
var _catalog: Dictionary = {}
var _combinations: Dictionary = {}
var _clip_durations: Dictionary = {}
var _validated_moves: Dictionary = {}
var _binding: RefCounted
var _prepared := false
var _ground_ready := false
var _sequence: Array[Dictionary] = []
var _index := -1
var _rate := 1.0
var _source_duration := 0.0
var _combo_duration := 0.0
var _settle_seconds := 0.0
var _hold_seconds := 0.0
var _phase_elapsed := 0.0
var _expected_begin := 0
var _expected_finish := 0
var _expected_cancel := 0
var _completed_operations: Dictionary = {}
var _completion_count := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func configure_ground(definition: Dictionary, font: Font) -> void:
	_definition = definition.duplicate(true)
	_font = font


func configure_idle(motion: Dictionary, assets: Dictionary) -> Dictionary:
	if playing:
		return _failure("当前练武尚未收势，不能重建练武场。")
	var requested: Variant = assets.get("motion_id")
	var settle: Variant = assets.get("settle_seconds", motion.get("settle_seconds"))
	var hold: Variant = assets.get("hold_seconds", motion.get("hold_seconds"))
	if not requested is String or str(requested).is_empty() or not _duration(settle, 2.0) or not _duration(hold, 5.0):
		return _failure("练武场动作身份或准备时长无效。")
	_prepared = false
	_clip_durations.clear()
	for id: String in CLIP_IDS:
		var path := str(motion.get("clips", {}).get(id, {}).get("manifest", ""))
		if not path.begins_with("res://assets/") or not FileAccess.file_exists(path):
			return _failure("原剑法时长清单无法读取。")
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or not _number(data.get("fps")) or float(data.fps) < 1.0 or float(data.fps) > 120.0 or not _number(data.get("frame_count")) or float(data.frame_count) < 1.0 or not data.get("frames") is Array or data.frames.size() != int(data.frame_count):
			return _failure("原剑法时长清单无效。")
		_clip_durations[id] = float(data.frame_count) / float(data.fps)
	if not is_instance_valid(_stage) or not _ground_ready:
		_discard_ground()
		var prepared := _prepare_ground()
		if not bool(prepared.get("ok", false)):
			_discard_ground()
			return prepared
	if motion_id != str(requested):
		_completed_operations.clear()
		clip_id = ""
		run_id = ""
		operation_id = ""
	motion_id = str(requested)
	_settle_seconds = float(settle)
	_hold_seconds = float(hold)
	for id: String in CLIP_IDS:
		var check := preflight_clip(id)
		if not bool(check.get("ok", false)):
			return check
	_prepared = true
	neutral = true
	last_error = ""
	_set_phase("idle", "静息")
	_stage.call("show_workshop_move", "sword_cleave", "enhanced")
	return {"ok": true}


func _prepare_ground() -> Dictionary:
	if not is_inside_tree() or _definition.is_empty():
		return _failure("练武场需要已挂入场景并准备好场地资料。")
	var loaded: Dictionary = CatalogScript.load_catalog()
	if not bool(loaded.get("ok", false)):
		return _failure(str(loaded.get("reason", "武学资源未通过检查。")))
	if not FileAccess.file_exists(COMBINATIONS_PATH):
		return _failure("缺少练武场组合演练目录。")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COMBINATIONS_PATH))
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("combinations") is Dictionary:
		return _failure("练武场组合演练目录无效。")
	var local_rules: RefCounted = RulesScript.new()
	var configured: Dictionary = local_rules.call("configure", _definition.duplicate(true))
	if not bool(configured.get("ok", false)):
		return _failure(str(configured.get("reason", "练武场显示资料无效。")))
	var display: Dictionary = local_rules.call("snapshot")
	var player_rows: Array = []
	for row: Dictionary in display.get("units", []):
		if str(row.get("id", "")) == "player":
			player_rows.append(row.duplicate(true))
	if player_rows.size() != 1:
		return _failure("练武场缺少江砚秋显示资料。")
	display["units"] = player_rows
	display["plans"] = []
	_catalog = loaded.catalog
	_combinations = parsed.combinations.duplicate(true)
	_stage = StageScript.new() as Control
	_stage.name = "TrainingGroundStage"
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)
	_stage.call("setup", _definition.duplicate(true), _font)
	if not bool(_stage.get("_initialized")):
		return _failure("3D练武场尚未准备完成。")
	_stage.call("sync_state", display, "player", [], {})
	var catalog_result: Dictionary = _stage.call("set_workshop_catalog", _catalog)
	if not bool(catalog_result.get("ok", false)):
		return _failure(str(catalog_result.get("reason", "武学目录未能接入练武场。")))
	_stage.call("show_workshop_move", "sword_cleave", "enhanced")
	_stage.call("set_workshop_camera", "close")
	_stage.call("set_skill_audio", muted)
	_dress_training_ground()
	# The player chooses practice in the action column. Stage is display only.
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.set_process_input(false)
	_stage.set_process_unhandled_input(false)
	_stage.call("set_camera_input_enabled", false)
	_stage.call("set_detail_input_enabled", false)
	_binding = BindingScript.new()
	_ground_ready = true
	return {"ok": true}


func _dress_training_ground() -> void:
	if is_instance_valid(_training_dummy):
		return
	var world := _stage.get("world_root") as Node3D
	if world == null:
		return
	# A visual practice target at Stage's real workshop aim. It has no collision,
	# health, targeting or rules identity, and does not alter the shared landscape.
	_training_dummy = Node3D.new()
	_training_dummy.name = "TrainingDummy"
	_training_dummy.position = Vector3(1.45, 0.0, 0.0)
	world.add_child(_training_dummy)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#795135")
	wood.roughness = 0.96
	wood.metallic_specular = 0.12
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color("#c3aa7a")
	rope.roughness = 1.0
	rope.metallic_specular = 0.08
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#74786a")
	stone.roughness = 1.0
	stone.metallic_specular = 0.08
	var footing := CylinderMesh.new()
	footing.top_radius = 0.27
	footing.bottom_radius = 0.33
	footing.height = 0.13
	footing.radial_segments = 8
	_practice_mesh("StoneFooting", footing, Vector3(0.0, 0.065, 0.0), stone)
	var post := CylinderMesh.new()
	post.top_radius = 0.095
	post.bottom_radius = 0.115
	post.height = 1.30
	post.radial_segments = 12
	_practice_mesh("WoodenPost", post, Vector3(0.0, 0.78, 0.0), wood)
	var arm := CylinderMesh.new()
	arm.top_radius = 0.045
	arm.bottom_radius = 0.045
	arm.height = 0.76
	arm.radial_segments = 10
	var cross_arm := _practice_mesh("CrossArm", arm, Vector3(0.0, 1.03, 0.0), wood)
	cross_arm.rotation.x = PI * 0.5
	for index: int in range(5):
		var wrap := TorusMesh.new()
		wrap.inner_radius = 0.105
		wrap.outer_radius = 0.127
		wrap.rings = 20
		wrap.ring_segments = 6
		_practice_mesh("RopeWrap%d" % index, wrap, Vector3(0.0, 0.80 + float(index) * 0.035, 0.0), rope)


func _practice_mesh(node_name: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	_training_dummy.add_child(instance)
	return instance


func _discard_ground() -> void:
	_prepared = false
	_ground_ready = false
	_validated_moves.clear()
	if _binding != null:
		_binding.call("finish")
	_binding = null
	if is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null
	_training_dummy = null


func preflight_clip(requested_clip: String) -> Dictionary:
	if playing:
		return _failure("练武尚未收势，不能预备另一套剑法。")
	if not _ground_ready or not is_instance_valid(_stage) or not bool(_stage.get("_initialized")) or not CLIP_IDS.has(requested_clip):
		return _failure("练武场或所选剑法尚未准备好。")
	var entry: Variant = _combinations.get(requested_clip)
	if not entry is Dictionary or not entry.get("moves") is Array or entry.moves.is_empty():
		return _failure("所选剑法缺少组合动作。")
	var actors: Dictionary = _stage.get("actor_nodes")
	var actor := actors.get("player") as Node3D
	if actor == null:
		return _failure("练武场人物模型无法载入。")
	var total := 0.0
	for part: Variant in entry.moves:
		if not part is Dictionary or not part.get("id") is String or not part.get("variant_id") is String:
			return _failure("组合动作身份无效。")
		var recipe: Dictionary = CatalogScript.find_move(_catalog, str(part.id), str(part.variant_id))
		if recipe.is_empty() or str(recipe.get("actor", "")) != "player" or str(recipe.get("category", "")) != "sword":
			return _failure("组合演练必须使用江砚秋现有的剑法动作。")
		var key := str(part.id) + "@" + str(part.variant_id)
		if not _validated_moves.has(key):
			var profile: Dictionary = _catalog.profiles.get(str(recipe.profile), {})
			var adapter := actor.call("workshop_adapter") as Node3D
			var animation_player: AnimationPlayer = adapter.get("animation_player") as AnimationPlayer if adapter != null else null
			var existing_clips: PackedStringArray = animation_player.get_animation_list() if animation_player != null else PackedStringArray()
			var bound: Dictionary = _binding.call("bind_move", actor, recipe, profile)
			_binding.call("finish")
			if not bool(bound.get("ok", false)):
				return _failure(str(bound.get("reason", "动作与真实人物骨架不匹配。")))
			# Preflight binds the actual model but does not leave a second owner's
			# Workshop clip installed before Stage's own player first binds it.
			var installed_clip := str(bound.get("clip", ""))
			if animation_player != null and installed_clip.begins_with("Workshop/") and not existing_clips.has(installed_clip):
				animation_player.get_animation_library("Workshop").remove_animation(installed_clip.trim_prefix("Workshop/"))
			_validated_moves[key] = {"asset": str(recipe.animation.asset), "clip": str(recipe.animation.clip),
				"profile": str(recipe.profile), "rest_error": bound.get("rest_error", 0.0), "actual_model_bound": true}
		total += float(recipe.timing.total)
	if not is_finite(total) or total <= 0.0:
		return _failure("组合演练时长无效。")
	var source_duration := float(_clip_durations.get(requested_clip, 0.0))
	if not is_finite(source_duration) or source_duration <= 0.0 or source_duration > 120.0:
		return _failure("原剑法时长尚未准备好。")
	var rate := total / source_duration
	if not is_finite(rate) or rate < 0.25 or rate > 2.0:
		return _failure("现有3D组合不能保持原剑法的有效时长。")
	return {"ok": true, "clip_id": requested_clip, "total": total, "source_duration": source_duration, "rate": rate}


func is_prepared() -> bool:
	return _prepared and _ground_ready and is_instance_valid(_stage) and bool(_stage.get("_initialized")) and not motion_id.is_empty()


func set_scene_layout(surface_size: Vector2, _x: float, _y: float, _height: float, _flip: bool) -> void:
	if surface_size.is_finite() and surface_size.x > 0.0 and surface_size.y > 0.0:
		size = surface_size
		if is_instance_valid(_stage):
			_stage.position = Vector2.ZERO
			_stage.size = surface_size


func play_presentation(pending: Dictionary) -> Dictionary:
	var requested_run: Variant = pending.get("run_id")
	var requested_operation: Variant = pending.get("operation_id")
	var requested_clip: Variant = pending.get("clip_id")
	if not requested_run is String or str(requested_run).is_empty() or not requested_operation is String or str(requested_operation).is_empty() or not requested_clip is String:
		return _failure("练武请求缺少真实的开局或行动身份。")
	if str(pending.get("motion_id", "")) != motion_id:
		return _failure("练武请求与当前人物不匹配。")
	if playing:
		if run_id == str(requested_run) and operation_id == str(requested_operation) and clip_id == str(requested_clip):
			if current_phase == "error":
				return {"ok": false, "reason": last_error}
			return {"ok": true, "already_playing": true}
		return _failure("本次练武尚未收势，不能开始另一行动。")
	var identity := JSON.stringify([requested_run, requested_operation])
	if _completed_operations.has(identity):
		return {"ok": true, "already_completed": true} if str(_completed_operations[identity]) == str(requested_clip) else _failure("行动身份已用于另一套剑法。")
	if not is_prepared():
		return _failure("真实3D练武场尚未准备好。")
	var checked := preflight_clip(str(requested_clip))
	if not bool(checked.get("ok", false)):
		return checked
	var assets: Variant = pending.get("assets")
	if not assets is Dictionary or not assets.get("action_frames") is Array or assets.action_frames.is_empty() or not _number(assets.get("action_fps")) or float(assets.action_fps) <= 0.0:
		return _failure("原行动的练武时长无效。")
	var duration := float(assets.action_frames.size()) / float(assets.action_fps)
	if not is_finite(duration) or duration <= 0.0 or duration > 120.0:
		return _failure("原行动的练武时长无效。")
	var settle: Variant = assets.get("settle_seconds", _settle_seconds)
	var hold: Variant = assets.get("hold_seconds", _hold_seconds)
	var rate := float(checked.total) / duration
	if not is_finite(rate) or rate < 0.25 or rate > 2.0 or not _duration(settle, 2.0) or not _duration(hold, 5.0):
		return _failure("组合演练无法保持原行动的有效时长。")
	_sequence.clear()
	for row: Dictionary in _combinations[str(requested_clip)].moves:
		_sequence.append(row.duplicate(true))
	clip_id = str(requested_clip)
	run_id = str(requested_run)
	operation_id = str(requested_operation)
	_rate = rate
	_source_duration = duration
	_combo_duration = float(checked.total)
	_settle_seconds = float(settle)
	_hold_seconds = float(hold)
	_index = -1
	_phase_elapsed = 0.0
	playing = true
	neutral = false
	last_error = ""
	_set_phase("settle", "准备")
	return {"ok": true}


func _process(delta: float) -> void:
	if not playing or current_phase == "error" or not is_finite(delta) or delta < 0.0:
		return
	if not is_instance_valid(_stage) or not _stage.is_inside_tree():
		_fail_busy("真实3D练武场已离开场景，修习尚未完成。")
		return
	if current_phase == "settle" or current_phase == "neutral_hold":
		_phase_elapsed += delta
		var duration := _settle_seconds if current_phase == "settle" else _hold_seconds
		if _phase_elapsed + CLOCK_EPSILON < duration:
			return
		_phase_elapsed = 0.0
		if current_phase == "settle":
			_start_next_move()
		else:
			_complete_presentation()
	elif current_phase == "action":
		var player: Dictionary = _stage.call("workshop_audit")
		if int(player.get("cancel_count", 0)) != _expected_cancel or not str(player.get("reason", "")).is_empty():
			_fail_busy(str(player.get("reason", "组合动作被取消，修习尚未完成。")))
			return
		var part: Dictionary = _sequence[_index]
		if str(player.get("move_id", "")) != str(part.id) or str(player.get("variant_id", "")) != str(part.variant_id) or int(player.get("begin_count", 0)) != _expected_begin:
			_fail_busy("当前3D动作已经改变，修习尚未完成。")
			return
		if not bool(player.get("active", false)) and not bool(_stage.get("_animating")):
			if int(player.get("finish_count", 0)) != _expected_finish:
				_fail_busy("当前3D动作没有真正完成收势。")
				return
			_start_next_move()


func _start_next_move() -> void:
	_index += 1
	if _index >= _sequence.size():
		_phase_elapsed = 0.0
		_set_phase("neutral_hold", "收息")
		return
	var before: Dictionary = _stage.call("workshop_audit")
	_expected_begin = int(before.get("begin_count", 0)) + 1
	_expected_finish = int(before.get("finish_count", 0)) + 1
	_expected_cancel = int(before.get("cancel_count", 0))
	var part: Dictionary = _sequence[_index]
	_stage.call("show_workshop_move", str(part.id), str(part.variant_id))
	_stage.call("preview_workshop_move", str(part.id), _rate, str(part.variant_id))
	var actual: Dictionary = _stage.call("workshop_audit")
	if int(actual.get("begin_count", 0)) != _expected_begin or not bool(actual.get("active", false)) or not str(actual.get("reason", "")).is_empty():
		_fail_busy(str(actual.get("reason", "真实3D组合动作未能开始。")))
		return
	_set_phase("action", "组合演练 %d / %d" % [_index + 1, _sequence.size()])


func _complete_presentation() -> void:
	var completed_run := run_id
	var completed_operation := operation_id
	_completed_operations[JSON.stringify([completed_run, completed_operation])] = clip_id
	_completion_count += 1
	playing = false
	neutral = true
	_set_phase("idle", "静息")
	finished.emit(completed_run, completed_operation)


func presentation_snapshot() -> Dictionary:
	var player: Dictionary = _stage.call("workshop_audit") if is_instance_valid(_stage) else {}
	var stage: Dictionary = _stage.call("audit") if is_instance_valid(_stage) else {}
	var ids: Array[String] = []
	for part: Dictionary in _sequence:
		ids.append(str(part.id) + "@" + str(part.variant_id))
	return {"route": "workshop_3d_training", "playing": playing, "neutral": neutral, "prepared": is_prepared(),
		"frame": -1, "phase": current_phase, "phase_label": current_phase_label,
		"motion_id": motion_id, "clip_id": clip_id, "run_id": run_id, "operation_id": operation_id,
		"loaded_action_atlas_paths": [], "loaded_idle_atlas_paths": [], "idle_atlas_paths": [],
		"combo_index": _index, "combo_move_ids": ids, "combo_rate": _rate,
		"source_duration": _source_duration, "combo_duration": _combo_duration,
		"completion_count": _completion_count, "error": last_error, "stage": stage, "player": player,
		"validated_moves": _validated_moves.duplicate(true), "direct_stage_input": false,
		"training_dummy_visible": is_instance_valid(_training_dummy) and _training_dummy.is_visible_in_tree(),
		"description": "现有武学工坊动作的组合演练，不声称逐招还原旧五套动作。"}


func _set_phase(phase: String, label: String) -> void:
	current_phase = phase
	current_phase_label = label
	phase_changed.emit(phase, label)


func _fail_busy(reason: String) -> void:
	last_error = reason if not reason.is_empty() else "真实3D组合动作未能完成，修习仍被占用。"
	_set_phase("error", last_error)


func _failure(reason: String) -> Dictionary:
	# Rejecting another request must not interrupt an already valid operation.
	if not playing:
		last_error = reason
	return {"ok": false, "reason": reason}


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _duration(value: Variant, maximum: float) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) <= maximum
