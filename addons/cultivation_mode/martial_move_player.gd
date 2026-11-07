extends RefCounted
## One clock for skeleton, real anchors, effects and cue scheduling. No rules access.
signal impact_reached
const Binding = preload("res://addons/cultivation_mode/martial_actor_binding.gd")
var active := false
var paused := false
var elapsed := 0.0
var speed := 1.0
var move: Dictionary = {}
var _profile: Dictionary = {}
var _actor: Node3D
var _target := Vector3.ZERO
var _blade: Node3D
var _palm: Node3D
var _light: Node3D
var _binding: RefCounted
var _bindings := {}
var _release_origin := Vector3.ZERO
var _released := false
var _impacted := false
var _counts := {"begin_count": 0, "release_count": 0, "impact_count": 0, "finish_count": 0, "cancel_count": 0}
var _reason := ""
var _recoils: Array[Dictionary] = []
var _contact_samples := 0
var _minimum_contact_extended := false
var _contact_discarded_seconds := 0.0

func begin(recipe: Dictionary, profile: Dictionary, actor: Node3D, target: Vector3, blade: Node3D, palm: Node3D, light: Node3D, rate: float = 1.0) -> Dictionary:
	cancel()
	move = recipe.duplicate(true)
	_profile = profile.duplicate(true)
	_actor = actor
	_target = target
	_blade = blade
	_palm = palm
	_light = light
	speed = clampf(rate, 0.25, 2.0)
	elapsed = 0.0
	paused = false
	_released = false
	_impacted = false
	_contact_samples = 0
	_minimum_contact_extended = false
	_contact_discarded_seconds = 0.0
	var result := _activate()
	if result.ok:
		_counts.begin_count += 1
	return result

func _activate() -> Dictionary:
	var key := str(_actor.get_instance_id())
	if not _bindings.has(key):
		_bindings[key] = Binding.new()
	_binding = _bindings[key]
	var result: Dictionary = _binding.call("bind_move", _actor, move, _profile)
	if not result.ok:
		_reason = str(result.reason)
		return result
	# Cache the actual release pose anchor; timeline scrubbing uses this same origin.
	_binding.call("sample", float(move.timing.release))
	_release_origin = _actor.call("get_palm_origin") if str(move.category) == "palm" else _actor.global_position
	_binding.call("sample", elapsed)
	var fx := _effect()
	fx.call("begin_recipe", move, _actor.global_position, _target, _anchors())
	_light.call("begin_attack", str(move.get("combat_skill", "")), _actor.global_position, _target, 0.08, false)
	_light.set_process(false)
	active = true
	_reason = ""
	_sample(false)
	return {"ok": true, "reason": ""}

func step(delta: float) -> void:
	if not active or paused:
		return
	var next_elapsed := minf(float(move.timing.total), elapsed + maxf(delta, 0.0) * speed)
	var impact := float(move.timing.impact)
	var hold := float(move.timing.get("impact_hold", 0.0))
	var requested_elapsed := next_elapsed
	# The combat-only hold must first render its exact contact pose. A slow
	# frame may cross the whole plateau; discard its overshoot at this boundary.
	if hold > 0.0 and not _impacted and elapsed < impact and next_elapsed >= impact:
		next_elapsed = impact
	elif hold > 0.0 and elapsed >= impact and elapsed < impact + hold and _contact_samples < 2 and next_elapsed >= impact + hold:
		# The first hit frame can itself be expensive. Preserve a second contact
		# sample for readability; slow devices may spend longer than nominal 70 ms.
		next_elapsed = impact + hold * 0.5
		_minimum_contact_extended = true
	_contact_discarded_seconds += maxf(0.0, requested_elapsed - next_elapsed)
	elapsed = next_elapsed
	if hold > 0.0 and elapsed >= impact and elapsed < impact + hold:
		_contact_samples += 1
	_sample(true)
	if elapsed >= float(move.timing.total):
		_finish()

func _sample(emit_events: bool) -> void:
	_binding.call("sample", elapsed)
	_sample_recoils()
	_effect().call("sample_recipe", elapsed, _anchors(), emit_events)
	_light.call("sample_timeline", elapsed, float(move.timing.impact), float(move.timing.total))
	if elapsed >= float(move.timing.release) and not _released:
		_released = true
		if emit_events:
			_counts.release_count += 1
	if elapsed >= float(move.timing.impact) and not _impacted:
		_impacted = true
		if emit_events:
			_counts.impact_count += 1
			impact_reached.emit()

func add_impact_recoil(actor: Node3D) -> void:
	# Only the combat presentation opts in. The normal hit pose was requested by
	# Stage's damage event; this clock now advances it, with no second animation.
	if not active or not is_instance_valid(actor) or actor == _actor:
		return
	for row: Dictionary in _recoils:
		if row.actor == actor:
			return
	var rate: float = maxf(0.001, float(actor.get("action_playback_speed")))
	var row := {"actor": actor, "processing": actor.is_processing(), "sampled_seconds": 0.0,
		"source_seconds": 0.06}
	actor.set_process(false)
	# A small visible compression lands with the contact pose, then holds.
	actor.call("_process", 0.06 / rate)
	_recoils.append(row)
	_sample_recoils()

func _sample_recoils() -> void:
	var after_hold := maxf(0.0, elapsed - float(move.timing.impact) - float(move.timing.get("impact_hold", 0.0)))
	for row: Dictionary in _recoils:
		var actor := row.actor as Node3D
		if is_instance_valid(actor):
			actor.call("_process", maxf(0.0, after_hold - float(row.sampled_seconds)))
			row.sampled_seconds = after_hold
			row.source_seconds = float(actor.get("_pose_time"))

func _anchors() -> Dictionary:
	var result: Dictionary = _actor.call("get_weapon_anchors") if str(move.category) == "sword" else {"palm": _actor.call("get_palm_origin")}
	if result.has("base"):
		result["blade_base"] = result.base
		result["blade_tip"] = result.tip
	result["release_origin"] = _release_origin
	return result

func _effect() -> Node3D:
	return _blade if str(move.visual.type) == "blade" else _palm

func set_paused(value: bool) -> void:
	paused = value
	if value:
		for fx: Node3D in [_blade, _palm]:
			if is_instance_valid(fx) and fx.has_method("pause_recipe_audio"):
				fx.call("pause_recipe_audio", true)
	else:
		for fx: Node3D in [_blade, _palm]:
			if is_instance_valid(fx) and fx.has_method("pause_recipe_audio"):
				fx.call("pause_recipe_audio", false)

func seek(seconds: float) -> void:
	if move.is_empty():
		return
	elapsed = clampf(seconds, 0.0, float(move.timing.total))
	if not active:
		var result := _activate()
		if not result.ok:
			return
		paused = true
	_sample(false)

func _finish() -> void:
	_counts.finish_count += 1
	_clear()

func cancel() -> void:
	if active:
		_counts.cancel_count += 1
	_clear()

func _clear() -> void:
	for fx: Node3D in [_blade, _palm, _light]:
		if is_instance_valid(fx):
			fx.call("cancel")
	if _binding != null:
		_binding.call("finish")
	for row: Dictionary in _recoils:
		var actor := row.actor as Node3D
		if is_instance_valid(actor):
			actor.call("set_motion", "idle")
			actor.set_process(bool(row.processing))
	_recoils.clear()
	active = false

func audit() -> Dictionary:
	var result: Dictionary = _counts.duplicate()
	var binding_data: Dictionary = _binding.call("audit") if _binding != null else {}
	var blade_data: Dictionary = _blade.call("audit") if is_instance_valid(_blade) else {}
	var palm_data: Dictionary = _palm.call("audit") if is_instance_valid(_palm) else {}
	var phase := "idle"
	var hold: float = float(move.get("timing", {}).get("impact_hold", 0.0))
	var recoil_data: Array[Dictionary] = []
	for row: Dictionary in _recoils:
		recoil_data.append({"actor": str((row.actor as Node3D).name) if is_instance_valid(row.actor) else "freed", "source_seconds": row.source_seconds,
			"sampled_seconds": row.sampled_seconds, "restore_processing": row.processing,
			"mode": str(row.actor.get("_mode")) if is_instance_valid(row.actor) else "freed"})
	if active:
		phase = "ready" if elapsed < float(move.timing.release) else ("strike" if elapsed < float(move.timing.impact) else ("hit_stop" if elapsed < float(move.timing.impact) + (hold if hold > 0.0 else 0.08) else "recovery"))
	result.merge({"variant_id": str(move.get("variant_id", "original")), "variant_label": str(move.get("variant_label", "原版")), "animation_asset": str(move.get("animation", {}).get("asset", "")), "move_id": str(move.get("id", "")), "actor_id": str(move.get("actor", "")), "active": active, "paused": paused, "speed": speed,
		"elapsed": elapsed, "total": float(move.get("timing", {}).get("total", 0.0)), "source_seconds": binding_data.get("source_seconds", 0.0),
		"effect_elapsed": elapsed, "phase": phase, "binding": binding_data, "reason": _reason,
		"impact_hold_seconds": hold, "impact_hold_active": active and hold > 0.0 and elapsed >= float(move.timing.impact) and elapsed < float(move.timing.impact) + hold,
		"minimum_contact_samples": 2 if hold > 0.0 else 0, "contact_samples": _contact_samples,
		"minimum_contact_extended": _minimum_contact_extended, "contact_discarded_seconds": _contact_discarded_seconds,
		"contact_hold_policy": "At least two Stage contact samples; low frame rates may extend wall-clock duration" if hold > 0.0 else "Original recipe timeline",
		"recoil_targets": recoil_data,
		"audio_play_count": int(blade_data.get("audio_play_count", 0)) + int(palm_data.get("audio_play_count", 0)),
		"live_audio": int(blade_data.get("audio_player_count", 0)) + int(palm_data.get("audio_player_count", 0)),
		"live_fx": int(blade_data.get("live_nodes", 0)) + int(palm_data.get("live_nodes", 0)),
		"clock": "single recipe clock", "authority": "presentation only"})
	return result
