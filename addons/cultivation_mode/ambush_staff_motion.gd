extends RefCounted
## Authored staff poses. The caller supplies seconds; this producer owns no clock.
## Rig convention: +Z forward, anatomical right is -X, feet describe soles.

const ATTACK_SECONDS := 1.72
const SUPPORT_KNEE_FLEX := 0.022
const RIGHT_FOOT := Vector3(-0.15, 0.0, -0.08)
const LEFT_FOOT := Vector3(0.15, 0.0, 0.10)

static func timing() -> Dictionary:
	return {
		"duration": ATTACK_SECONDS, "windup_end": 0.55, "release": 0.66,
		"impact": 0.82, "contact_end": 0.90, "followthrough_end": 1.08,
		"recovery_end": ATTACK_SECONDS,
		"markers": [
			{"seconds": 0.0, "phase": "ready"},
			{"seconds": 0.55, "phase": "loaded"},
			{"seconds": 0.66, "phase": "release"},
			{"seconds": 0.82, "phase": "contact"},
			{"seconds": 0.90, "phase": "followthrough"},
			{"seconds": 1.08, "phase": "recover"},
			{"seconds": ATTACK_SECONDS, "phase": "guard"},
		],
	}

static func duration(clip: String) -> float:
	match clip:
		"intent": return 2.4
		"attack": return ATTACK_SECONDS
		"interrupt": return 0.74
		"recoil": return 0.52
		"stagger": return 1.08
		"walk": return 0.76
		_: return 2.4

static func sample(clip: String, seconds: float, context: Dictionary = {}) -> Dictionary:
	var t := maxf(seconds, 0.0)
	var pose: Dictionary
	match clip:
		"intent": pose = _intent(t)
		"attack": pose = _attack_entry(t, context)
		"interrupt": pose = _interrupt(t, context)
		"recoil": pose = _recoil(t, context)
		"stagger": pose = _stagger(t, context)
		"walk": pose = _walk(t)
		_: pose = _idle(t)
	# The authored offsets share a softly bent support stance, avoiding a straight-leg overreach.
	pose["pelvis_position"] += Vector3.DOWN * SUPPORT_KNEE_FLEX
	pose["finished"] = t >= duration(clip) if clip not in ["idle", "walk", "intent"] else false
	return pose

static func audit_catalog() -> Dictionary:
	return {
		"version": "staff-authored-poses-1",
		"authoring": "Original local authored control poses; no imported animation or motion capture",
		"authority": "Externally sampled seconds only; no root transform, timers, damage or gameplay",
		"space": "+Z front, anatomical right -X, sole positions, Euler radians",
		"clips": {"idle": 2.4, "intent": 2.4, "walk": 0.76, "attack": ATTACK_SECONDS,
			"interrupt": 0.74, "recoil": 0.52, "stagger": 1.08},
		"attack_timing": timing(),
		"staff_length": 1.65,
		"right_grip": Vector3(0.0, -0.20, 0.0),
		"left_grip": Vector3(0.0, 0.20, 0.0),
		"right_rest_sole": RIGHT_FOOT, "left_rest_sole": LEFT_FOOT,
		"support_knee_flex": SUPPORT_KNEE_FLEX,
		"five_beats": ["lower and load", "waist and shoulder lead", "staff contact",
			"followthrough", "recover guard"],
		"intent": "Looping breath at attack .43s load pose; no release or contact",
		"contexts": ["source_pose (attack load, interrupt/recoil and stagger entry continuity)",
			"root_delta (stagger direction only)", "collision (stagger landing emphasis)"],
	}

static func _rest() -> Dictionary:
	return {
		"pelvis_position": Vector3.ZERO, "pelvis_rotation": Vector3.ZERO,
		"chest_rotation": Vector3.ZERO, "head_rotation": Vector3.ZERO,
		"staff_position": Vector3(0.0, 0.96, 0.24),
		"staff_rotation": Vector3(-0.12, 0.0, -1.08),
		"left_foot": LEFT_FOOT, "right_foot": RIGHT_FOOT,
		"left_foot_rotation": Vector3(0.0, -0.10, 0.0),
		"right_foot_rotation": Vector3(0.0, 0.10, 0.0),
		"left_pole": Vector3(0.49, 0.83, 0.03),
		"right_pole": Vector3(-0.49, 0.83, 0.03),
		"phase": "guard", "foot_plant_weights": {"left": 1.0, "right": 1.0},
	}

static func _pose(values: Dictionary) -> Dictionary:
	var pose := _rest()
	pose.merge(values, true)
	return pose

static func _blend(a: Dictionary, b: Dictionary, weight: float, phase: String) -> Dictionary:
	var output := a.duplicate(true)
	var w := clampf(weight, 0.0, 1.0)
	for key: String in a:
		if a[key] is Vector3 and b.has(key):
			output[key] = (a[key] as Vector3).lerp(b[key] as Vector3, w)
	var aw: Dictionary = a["foot_plant_weights"]
	var bw: Dictionary = b["foot_plant_weights"]
	output["foot_plant_weights"] = {"left": lerpf(aw["left"], bw["left"], w),
		"right": lerpf(aw["right"], bw["right"], w)}
	output["phase"] = phase
	return output

static func _ease(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func _segment(a: Dictionary, b: Dictionary, t: float, start: float, end: float, phase: String) -> Dictionary:
	return _blend(a, b, _ease((t - start) / (end - start)), phase)

static func _loaded() -> Dictionary:
	return _pose({"pelvis_position": Vector3(0.0, -0.075, -0.035),
		"pelvis_rotation": Vector3(0.05, -0.17, 0.01),
		"chest_rotation": Vector3(-0.10, -0.25, 0.02),
		"head_rotation": Vector3(0.04, 0.30, 0.0),
		"staff_position": Vector3(-0.14, 1.20, 0.02),
		"staff_rotation": Vector3(0.15, -0.38, -1.05),
		"phase": "loaded"})

static func _contact() -> Dictionary:
	return _pose({"pelvis_position": Vector3(0.0, -0.045, 0.055),
		"pelvis_rotation": Vector3(0.08, 0.16, 0.0),
		"chest_rotation": Vector3(0.13, 0.13, -0.025),
		"head_rotation": Vector3(-0.07, -0.18, 0.0),
		"staff_position": Vector3(0.01, 0.99, 0.32),
		"staff_rotation": Vector3(1.02, 0.18, -0.82),
		"left_foot": LEFT_FOOT + Vector3(0.0, 0.0, 0.17),
		"left_foot_rotation": Vector3(0.0, -0.19, 0.0),
		"phase": "contact"})

static func _attack_entry(t: float, context: Dictionary) -> Dictionary:
	var source: Variant = context.get("source_pose", {})
	if t < 0.55 and source is Dictionary and source.has("staff_position"):
		return _segment(_source_pose(context, _rest()), _loaded(), t, 0.0, 0.55, "load")
	return _attack(t)

static func _attack(t: float) -> Dictionary:
	var ready := _pose({"pelvis_position": Vector3(0.0, -0.04, -0.015),
		"chest_rotation": Vector3(-0.03, -0.08, 0.0),
		"staff_position": Vector3(-0.05, 1.02, 0.17),
		"staff_rotation": Vector3(-0.10, -0.12, -0.96)})
	var release := _pose({"pelvis_position": Vector3(0.0, -0.06, 0.0),
		"pelvis_rotation": Vector3(0.08, -0.03, 0.0),
		"chest_rotation": Vector3(-0.02, -0.15, 0.01),
		"head_rotation": Vector3(0.0, 0.15, 0.0),
		"staff_position": Vector3(-0.12, 1.19, 0.08),
		"staff_rotation": Vector3(0.43, -0.28, -1.02),
		"left_foot": LEFT_FOOT + Vector3(0.0, 0.075, 0.075),
		"foot_plant_weights": {"left": 0.0, "right": 1.0}})
	var follow := _pose({"pelvis_position": Vector3(0.015, -0.07, 0.045),
		"pelvis_rotation": Vector3(0.08, 0.21, -0.02),
		"chest_rotation": Vector3(0.16, 0.17, -0.035),
		"head_rotation": Vector3(-0.09, -0.27, 0.0),
		"staff_position": Vector3(0.08, 0.86, 0.27),
		"staff_rotation": Vector3(1.39, 0.26, -0.80),
		"left_foot": LEFT_FOOT + Vector3(0.0, 0.0, 0.17)})
	var returning := _pose({"pelvis_position": Vector3(0.0, -0.025, 0.0),
		"chest_rotation": Vector3(0.02, 0.05, 0.0),
		"staff_position": Vector3(0.04, 0.94, 0.24),
		"staff_rotation": Vector3(0.22, 0.05, -1.01),
		"left_foot": LEFT_FOOT + Vector3(0.0, 0.065, 0.075),
		"foot_plant_weights": {"left": 0.0, "right": 1.0}})
	if t < 0.18: return _segment(_rest(), ready, t, 0.0, 0.18, "ready")
	if t < 0.55: return _segment(ready, _loaded(), t, 0.18, 0.55, "load")
	if t < 0.66: return _segment(_loaded(), release, t, 0.55, 0.66, "waist_lead")
	if t < 0.82: return _segment(release, _contact(), t, 0.66, 0.82, "strike")
	if t < 0.90: return _contact()
	if t < 1.08: return _segment(_contact(), follow, t, 0.90, 1.08, "followthrough")
	if t < 1.40: return _segment(follow, returning, t, 1.08, 1.40, "recover_step")
	return _segment(returning, _rest(), t, 1.40, ATTACK_SECONDS, "guard")

static func _idle(t: float) -> Dictionary:
	var p := _rest()
	var breath := sin(t * TAU / 2.4)
	p["pelvis_position"] = Vector3(0.0, breath * 0.003, 0.0)
	p["chest_rotation"] = Vector3(breath * 0.009, 0.0, 0.0)
	p["staff_position"] += Vector3(0.0, breath * 0.004, 0.0)
	return p

static func _intent(t: float) -> Dictionary:
	# A pending turn is a held preparation, not a clock that can advance into an attack.
	var p := _attack(0.43)
	var breath := sin(t * TAU / 2.4)
	p["pelvis_position"] += Vector3.UP * breath * 0.0025
	p["chest_rotation"] += Vector3(breath * 0.006, 0.0, 0.0)
	p["staff_position"] += Vector3.UP * breath * 0.003
	p["staff_rotation"] += Vector3(breath * 0.004, 0.0, 0.0)
	p["phase"] = "waiting"
	return p

static func _walk(t: float) -> Dictionary:
	var p := _rest()
	var cycle := fposmod(t, duration("walk")) / duration("walk")
	var left_swing := cycle < 0.5
	var step := fposmod(cycle * 2.0, 1.0)
	var stride := lerpf(-0.11, 0.11, _ease(step))
	var lift := sin(step * PI) * 0.085
	p["pelvis_position"] = Vector3(sin(cycle * TAU) * 0.012, -0.025 + absf(sin(cycle * TAU)) * 0.012, 0.0)
	p["chest_rotation"] = Vector3(0.035, sin(cycle * TAU) * 0.035, 0.0)
	p["left_foot"] = LEFT_FOOT + Vector3(0.0, lift if left_swing else 0.0, stride if left_swing else -stride)
	p["right_foot"] = RIGHT_FOOT + Vector3(0.0, 0.0 if left_swing else lift, -stride if left_swing else stride)
	p["foot_plant_weights"] = {"left": 0.0 if left_swing else 1.0, "right": 1.0 if left_swing else 0.0}
	p["phase"] = "left_step" if left_swing else "right_step"
	return p

static func _source_pose(context: Dictionary, fallback: Dictionary) -> Dictionary:
	var source: Variant = context.get("source_pose", {})
	if source is Dictionary and source.has("staff_position"):
		var result := fallback.duplicate(true)
		for key: String in result:
			if source.has(key): result[key] = source[key]
		# source_pose is a previous public sample; undo the shared stance offset before blending.
		result["pelvis_position"] += Vector3.UP * SUPPORT_KNEE_FLEX
		return result
	return fallback

static func _interrupt(t: float, context: Dictionary) -> Dictionary:
	var start := _source_pose(context, _loaded())
	var broken := _pose({"pelvis_position": Vector3(-0.025, -0.06, -0.035),
		"pelvis_rotation": Vector3(-0.05, -0.10, 0.045),
		"chest_rotation": Vector3(-0.17, 0.10, 0.055),
		"head_rotation": Vector3(-0.16, -0.10, 0.025),
		"staff_position": Vector3(-0.10, 1.04, 0.10),
		"staff_rotation": Vector3(0.24, -0.20, -0.90),
		"right_foot": RIGHT_FOOT + Vector3(0.0, 0.0, -0.10)})
	var brace := _pose({"pelvis_position": Vector3(-0.01, -0.075, -0.02),
		"chest_rotation": Vector3(0.07, 0.03, 0.0),
		"staff_position": Vector3(-0.03, 0.88, 0.27),
		"staff_rotation": Vector3(0.20, 0.0, -1.02),
		"right_foot": RIGHT_FOOT + Vector3(0.0, 0.0, -0.10)})
	if t < 0.16: return _segment(start, broken, t, 0.0, 0.16, "charge_broken")
	if t < 0.34: return _segment(broken, brace, t, 0.16, 0.34, "brace")
	return _segment(brace, _rest(), t, 0.34, 0.74, "recover_guard")

static func _recoil(t: float, context: Dictionary) -> Dictionary:
	var start := _source_pose(context, _rest())
	var struck := _pose({"pelvis_position": Vector3(0.0, -0.045, -0.025),
		"pelvis_rotation": Vector3(-0.07, -0.06, 0.02),
		"chest_rotation": Vector3(-0.16, 0.08, 0.025),
		"head_rotation": Vector3(-0.12, -0.06, 0.0),
		"staff_position": Vector3(-0.03, 1.02, 0.14),
		"staff_rotation": Vector3(0.08, -0.12, -0.98)})
	if t < 0.12: return _segment(start, struck, t, 0.0, 0.12, "recoil")
	if t < 0.19:
		struck["phase"] = "absorb"
		return struck
	return _segment(struck, _rest(), t, 0.19, 0.52, "recover_guard")

static func _stagger(t: float, context: Dictionary) -> Dictionary:
	var delta: Vector3 = context.get("root_delta", Vector3(0.0, 0.0, -1.0))
	delta.y = 0.0
	var direction := delta.normalized() if delta.length_squared() > 0.000001 else Vector3(0.0, 0.0, -1.0)
	var collision := bool(context.get("collision", false))
	var p := _rest()
	var reaction := _ease(t / 0.10) * (1.0 - _ease((t - 0.68) / 0.40))
	p["pelvis_position"] = Vector3(-direction.x * 0.025, -0.06 * reaction, -direction.z * 0.015) * reaction
	p["pelvis_rotation"] = Vector3(-direction.z * 0.08, 0.0, direction.x * 0.08) * reaction
	p["chest_rotation"] = Vector3(direction.z * 0.11, 0.08, -direction.x * 0.11) * reaction
	p["head_rotation"] = Vector3(direction.z * 0.10, -0.06, 0.0) * reaction
	p["staff_position"] = Vector3(-0.04 * reaction, 0.96 - 0.07 * reaction, 0.24 - 0.08 * reaction)
	p["staff_rotation"] = Vector3(0.16 * reaction, -0.13 * reaction, -1.08 + 0.12 * reaction)
	# Two deliberately separate recovery steps: the actor root is still owned by Stage.
	if t < 0.34:
		var u := clampf(t / 0.34, 0.0, 1.0)
		p["right_foot"] = RIGHT_FOOT + direction * (0.13 * _ease(u)) + Vector3.UP * sin(u * PI) * 0.085
		p["foot_plant_weights"] = {"left": 1.0, "right": 0.0 if u < 0.97 else 1.0}
		p["phase"] = "first_backstep"
	elif t < 0.68:
		var u := (t - 0.34) / 0.34
		p["right_foot"] = RIGHT_FOOT + direction * (0.13 * (1.0 - _ease(u)))
		p["left_foot"] = LEFT_FOOT + direction * (0.13 * sin(u * PI)) + Vector3.UP * sin(u * PI) * 0.08
		p["foot_plant_weights"] = {"left": 0.0, "right": 1.0}
		p["phase"] = "second_backstep"
	else:
		var settle := 1.0 - _ease((t - 0.68) / 0.40)
		var impact_bend := sin(clampf((t - 0.68) / 0.22, 0.0, 1.0) * PI)
		p["pelvis_position"] += Vector3.DOWN * impact_bend * (0.035 if collision else 0.012)
		p["chest_rotation"] += Vector3(0.07, 0.0, 0.0) * impact_bend if collision else Vector3.ZERO
		p["staff_position"] += Vector3.DOWN * impact_bend * 0.025
		p["phase"] = "collision_brace" if collision and settle > 0.1 else "settle_guard"
	var source: Variant = context.get("source_pose", {})
	if t < 0.14 and source is Dictionary and source.has("staff_position"):
		p = _blend(_source_pose(context, _rest()), p, _ease(t / 0.14), str(p["phase"]))
	return p
