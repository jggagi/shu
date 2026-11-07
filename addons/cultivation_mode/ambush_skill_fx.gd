extends Node3D
## Original pierce/sweep presentation. The stage owns the only ticking clock.
## All supplied positions are global; nothing here reads or changes Rules.

const CONFIG_PATH := "res://assets/art/mountain_ambush/skills/skill-fx.json"
const SHADER_CODE := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
varying float vertex_alpha;
void vertex() { vertex_alpha = COLOR.a; }
void fragment() { ALBEDO = tint.rgb; ALPHA = tint.a * opacity * vertex_alpha; }
"""

var _config: Dictionary = {}
var _streams: Dictionary = {}
var _configured := false
var _muted := false
var _volume_db: float = -10.0
var _active := false
var _skill_id := ""
var _last_skill_id := ""
var _skill: Dictionary = {}
var _phase := "idle"
var _elapsed := 0.0
var _impact_at := -1.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _forward := Vector3.FORWARD
var _side := Vector3.RIGHT
var _blade_base := Vector3.ZERO
var _blade_tip := Vector3.ZERO
var _samples: Array[Dictionary] = []
var _fx_root: Node3D
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _audio_players: Array[AudioStreamPlayer] = []
var _shader: Shader
var _begin_count := 0
var _impact_count := 0
var _audio_play_count := 0
var _audio_history: Array[Dictionary] = []
var _blade_sample_count := 0
var _pattern := ""
var _recipe_mode := false
var _recipe_timing: Dictionary = {}
var _recipe_released := false
var _recipe_impacted := false
var _release_count := 0
var _finish_count := 0
var _recipe_total_sampled := false


func setup(muted: bool = false, volume_db: float = -10.0) -> Dictionary:
	cancel()
	_configured = false
	_streams.clear()
	set_audio(muted, volume_db)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary or not parsed.get("skills") is Dictionary or not parsed.get("trail") is Dictionary:
		return {"ok": false, "reason": "Skill FX configuration is missing or invalid"}
	_config = parsed
	for id: String in ["pierce", "sweep"]:
		if not _config.skills.get(id) is Dictionary:
			return {"ok": false, "reason": "Skill FX configuration lacks " + id}
		for kind: String in ["whoosh", "hit"]:
			var path: String = str((_config.skills[id] as Dictionary).get(kind, ""))
			if not path.begins_with("res://assets/art/mountain_ambush/skills/sfx/") or not ResourceLoader.exists(path):
				return {"ok": false, "reason": "Original skill cue is missing: " + path}
			var stream := ResourceLoader.load(path) as AudioStream
			if stream == null:
				return {"ok": false, "reason": "Original skill cue cannot be decoded: " + path}
			_streams[id + ":" + kind] = stream
	_configured = true
	return {"ok": true, "reason": ""}


func set_audio(muted: bool, volume_db: float = -10.0) -> void:
	_muted = muted
	_volume_db = clampf(volume_db if is_finite(volume_db) else -10.0, -40.0, 0.0)
	if _muted:
		_clear_audio()
	else:
		for player: AudioStreamPlayer in _audio_players:
			if is_instance_valid(player):
				player.volume_db = _volume_db


func pause_recipe_audio(paused: bool) -> void:
	for player: AudioStreamPlayer in _audio_players:
		if is_instance_valid(player):
			player.stream_paused = paused


func begin_attack(skill_id: String, from: Vector3, to: Vector3, blade_base: Vector3, blade_tip: Vector3) -> void:
	cancel()
	if not _configured or not _config.skills.has(skill_id) or not from.is_finite() or not to.is_finite():
		return
	_pattern = skill_id
	_start_attack(skill_id, _config.skills[skill_id], from, to, blade_base, blade_tip)
	_play_audio("whoosh")


func begin_recipe(move: Dictionary, from: Vector3, to: Vector3, anchors: Dictionary = {}) -> void:
	cancel()
	if not _configured or not from.is_finite() or not to.is_finite():
		return
	var visual: Dictionary = move.get("visual", {})
	var timing: Dictionary = move.get("timing", {})
	var pattern := str(visual.get("pattern", ""))
	if str(visual.get("type", "")) != "blade" or pattern not in ["pierce", "sweep", "cleave"] or not visual.get("config") is Dictionary:
		return
	if float(timing.get("total", 0.0)) <= 0.0:
		return
	var skill: Dictionary = (visual.config as Dictionary).duplicate(true)
	skill["flight_start"] = float(timing.get("release", 0.0))
	skill["flight_seconds"] = maxf(0.001, float(timing.get("impact", 0.0)) - float(timing.get("release", 0.0)))
	var cues: Dictionary = move.get("audio", {})
	var id := str(move.get("id", ""))
	for pair: Array in [["whoosh", "release"], ["hit", "impact"]]:
		var path := str(cues.get(pair[1], ""))
		var stream := load(path) as AudioStreamWAV
		if stream == null or stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			return
		skill[pair[0]] = path
		_streams[id + ":" + str(pair[0])] = stream
	_recipe_mode = true
	_recipe_timing = timing.duplicate(true)
	_pattern = pattern
	_start_attack(id, skill, from, to, anchors.get("blade_base", from + Vector3.UP), anchors.get("blade_tip", to + Vector3.UP))


func _start_attack(skill_id: String, skill: Dictionary, from: Vector3, to: Vector3, blade_base: Vector3, blade_tip: Vector3) -> void:
	_skill_id = skill_id
	_last_skill_id = skill_id
	_skill = skill.duplicate(true)
	_from = to_local(from)
	_to = to_local(to)
	_forward = Vector3(_to.x - _from.x, 0.0, _to.z - _from.z).normalized()
	if _forward.length_squared() < 0.00001:
		_forward = Vector3(0.0, 0.0, 1.0)
	_side = Vector3.UP.cross(_forward).normalized()
	_active = true
	_phase = "windup"
	_elapsed = 0.0
	_impact_at = -1.0
	_begin_count += 1
	_fx_root = Node3D.new()
	_fx_root.name = "TransientSkillFX"
	add_child(_fx_root)
	_shader = Shader.new()
	_shader.code = SHADER_CODE
	_make_mesh("trail", Color(str(_skill.color)))
	_make_mesh("air", Color(str(_skill.color)))
	_make_mesh("core", Color(str(_skill.core_color)), 1)
	_make_mesh("dust", Color(str(_skill.dust_color)))
	update_blade(blade_base, blade_tip)


func sample_recipe(seconds: float, anchors: Dictionary = {}, emit_events: bool = true) -> void:
	if not _active or not _recipe_mode or not is_finite(seconds):
		return
	if not emit_events:
		_clear_audio()
	_elapsed = maxf(0.0, seconds)
	if anchors.get("blade_base") is Vector3 and anchors.get("blade_tip") is Vector3:
		update_blade(anchors.blade_base, anchors.blade_tip)
	var release: float = float(_recipe_timing.release)
	var hit: float = float(_recipe_timing.impact)
	if _elapsed >= release and not _recipe_released:
		_recipe_released = true
		_release_count += 1
		if emit_events:
			_play_audio("whoosh")
	if _elapsed >= hit and not _recipe_impacted:
		_recipe_impacted = true
		_impact_count += 1
		if emit_events:
			_play_audio("hit")
	if _elapsed >= float(_recipe_timing.total):
		if not _recipe_total_sampled:
			_recipe_total_sampled = true
			_finish_count += 1
		_phase = "finished"
		for id: String in _meshes:
			_upload(id, PackedVector3Array(), PackedFloat32Array(), 0.0)
		return
	# Consumption is monotonic, while geometry is derived from the requested
	# clock. Rewinding a paused pose cannot fire an already consumed cue again.
	_impact_at = hit if _elapsed >= hit else -1.0
	_phase = "windup" if _elapsed < release else ("strike" if _elapsed < hit else ("impact" if _elapsed < hit + 0.10 else "recovery"))
	_build_recipe_trail(release, hit)
	if _elapsed >= hit and _elapsed - hit < float(_skill.life_seconds):
		_build_air(_elapsed - hit)
	elif _pattern == "pierce" and _elapsed >= release and _elapsed < hit:
		_build_air(-1.0)
	else:
		for id: String in ["air", "core", "dust"]:
			_upload(id, PackedVector3Array(), PackedFloat32Array(), 0.0)


func _build_recipe_trail(release: float, hit: float) -> void:
	var vertices := PackedVector3Array()
	var alphas := PackedFloat32Array()
	var fade: float = clampf((_elapsed - release) / 0.06, 0.0, 1.0) * clampf((hit + 0.18 - _elapsed) / 0.18, 0.0, 1.0)
	if fade > 0.0:
		# A short pressure echo anchored to the actual current blade. This is
		# deterministic at a seek time, not a fabricated history of bone poses.
		var echo := -_forward * 0.12
		if _pattern == "sweep":
			echo = -_side * 0.15
		elif _pattern == "cleave":
			echo = Vector3.UP * 0.17 - _forward * 0.035
		_strip(vertices, alphas, _blade_base + echo, _blade_tip + echo, _blade_tip, _blade_base, 0.0, 0.85)
	_upload("trail", vertices, alphas, fade * (0.66 if _pattern == "sweep" else 0.44))


func update_blade(blade_base: Vector3, blade_tip: Vector3) -> void:
	if not _active or not blade_base.is_finite() or not blade_tip.is_finite():
		return
	var base: Vector3 = to_local(blade_base)
	var tip: Vector3 = to_local(blade_tip)
	if base.distance_squared_to(tip) < 0.0001 or base.distance_squared_to(tip) > 16.0:
		return
	_blade_base = base
	_blade_tip = tip
	var distance: float = float(_config.trail.min_distance)
	if not _samples.is_empty() and base.distance_to(_samples[-1].base) + tip.distance_to(_samples[-1].tip) < distance:
		return
	_samples.append({"base": base, "tip": tip, "age": 0.0})
	_blade_sample_count += 1
	while _samples.size() > int(_config.trail.max_samples):
		_samples.pop_front()


func set_blade(blade_base: Vector3, blade_tip: Vector3) -> void:
	update_blade(blade_base, blade_tip)


func impact() -> void:
	if not _active or _impact_at >= 0.0:
		return
	_impact_at = _elapsed
	_phase = "impact"
	_impact_count += 1
	_play_audio("hit")
	_build_air(0.0)


func step(delta: float) -> void:
	if not _active:
		return
	var dt: float = maxf(0.0, delta) if is_finite(delta) else 0.0
	if _recipe_mode:
		sample_recipe(_elapsed + dt)
		if _active and _elapsed >= float(_recipe_timing.total):
			cancel()
		return
	_elapsed += dt
	for sample: Dictionary in _samples:
		sample.age = float(sample.age) + dt
	while not _samples.is_empty() and float(_samples[0].age) > float(_config.trail.seconds):
		_samples.pop_front()
	_build_trail()
	if _impact_at < 0.0:
		if _pattern == "pierce" and _elapsed >= float(_skill.flight_start):
			_build_air(-1.0)
		return
	var since: float = _elapsed - _impact_at
	var life: float = float(_skill.life_seconds)
	if since >= life:
		_finish_count += 1
		cancel()
		return
	_phase = "impact" if since < 0.10 else "recovery"
	_build_air(since)


func cancel() -> void:
	_clear_audio()
	if is_instance_valid(_fx_root):
		_fx_root.free()
	_fx_root = null
	_meshes.clear()
	_materials.clear()
	_samples.clear()
	_shader = null
	_active = false
	_skill_id = ""
	_skill = {}
	_phase = "idle"
	_elapsed = 0.0
	_impact_at = -1.0
	_pattern = ""
	_recipe_mode = false
	_recipe_timing.clear()
	_recipe_released = false
	_recipe_impacted = false
	_recipe_total_sampled = false


func _make_mesh(id: String, color: Color, priority: int = 0) -> void:
	var node := MeshInstance3D.new()
	node.name = id.capitalize() + "Mesh"
	node.mesh = ArrayMesh.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.render_priority = priority
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("opacity", 0.0)
	node.material_override = mat
	_fx_root.add_child(node)
	_meshes[id] = node
	_materials[id] = mat


func _upload(id: String, vertices: PackedVector3Array, alphas: PackedFloat32Array, opacity: float) -> void:
	var node: MeshInstance3D = _meshes[id]
	var mesh: ArrayMesh = node.mesh as ArrayMesh
	mesh.clear_surfaces()
	node.visible = not vertices.is_empty() and opacity > 0.001
	(_materials[id] as ShaderMaterial).set_shader_parameter("opacity", opacity)
	if vertices.is_empty():
		return
	var colors := PackedColorArray()
	for alpha: float in alphas:
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.custom_aabb = mesh.get_aabb().grow(0.02)


func _triangle(vertices: PackedVector3Array, alphas: PackedFloat32Array, a: Vector3, b: Vector3, c: Vector3, aa: float = 1.0, ab: float = 1.0, ac: float = 1.0) -> void:
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	alphas.append(aa)
	alphas.append(ab)
	alphas.append(ac)


func _strip(vertices: PackedVector3Array, alphas: PackedFloat32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, first: float = 1.0, last: float = 1.0) -> void:
	_triangle(vertices, alphas, a, b, c, first, first, last)
	_triangle(vertices, alphas, a, c, d, first, last, last)


func _across(direction: Vector3, at: Vector3) -> Vector3:
	var view := Vector3(8.0, 10.8, 14.8).normalized()
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		view = (to_local(camera.global_position) - at).normalized()
	var result: Vector3 = direction.cross(view).normalized()
	return _side if result.length_squared() < 0.00001 else result


func _line(vertices: PackedVector3Array, alphas: PackedFloat32Array, start: Vector3, finish: Vector3, width: float, first: float = 0.0, last: float = 1.0) -> void:
	var across: Vector3 = _across((finish - start).normalized(), (start + finish) * 0.5) * width
	_strip(vertices, alphas, start - across, start + across, finish + across, finish - across, first, last)


func _build_trail() -> void:
	var vertices := PackedVector3Array()
	var alphas := PackedFloat32Array()
	var lifetime: float = float(_config.trail.seconds)
	for index: int in range(1, _samples.size()):
		var previous: Dictionary = _samples[index - 1]
		var current: Dictionary = _samples[index]
		var first: float = pow(clampf(1.0 - float(previous.age) / lifetime, 0.0, 1.0), 1.7)
		var last: float = pow(clampf(1.0 - float(current.age) / lifetime, 0.0, 1.0), 1.7)
		_strip(vertices, alphas, previous.base, previous.tip, current.tip, current.base, first, last)
	_upload("trail", vertices, alphas, 0.66 if _pattern == "sweep" else 0.44)


func _build_air(since: float) -> void:
	var air := PackedVector3Array()
	var core := PackedVector3Array()
	var dust := PackedVector3Array()
	var aa := PackedFloat32Array()
	var ca := PackedFloat32Array()
	var da := PackedFloat32Array()
	var progress: float = clampf(maxf(0.0, since) / float(_skill.life_seconds), 0.0, 1.0)
	var opacity: float = pow(1.0 - progress, 1.45)
	if _pattern == "pierce":
		var start: Vector3 = _from + Vector3.UP * 0.93 + _forward * minf(0.35, _from.distance_to(_to) * 0.2)
		var finish: Vector3 = _to + Vector3.UP * 0.93
		# The stage's one elapsed clock launches the beam during the strike.
		# A hit confirms its full legal endpoint, including a low-frame-rate hit.
		var travel: float = 1.0 if _impact_at >= 0.0 else clampf((_elapsed - float(_skill.flight_start)) / float(_skill.flight_seconds), 0.0, 1.0)
		var front: Vector3 = start.lerp(finish, travel)
		var tail: Vector3 = start.lerp(finish, progress * 0.70)
		opacity *= clampf(travel * 3.0, 0.0, 1.0)
		_line(air, aa, tail, front, float(_skill.width), 0.0, 0.9)
		_line(core, ca, tail.lerp(front, 0.20), front, float(_skill.core_width), 0.0, 1.0)
		for index: int in range(int(_skill.streak_count)):
			var ratio: float = float(index + 1) / float(int(_skill.streak_count) + 1)
			var offset: Vector3 = _side * sin(float(index) * 2.4) * 0.11 + Vector3.UP * cos(float(index) * 1.7) * 0.09
			var at: Vector3 = start.lerp(finish, clampf(ratio * travel + progress * 0.20, 0.0, 1.0)) + offset
			_line(dust, da, at - _forward * 0.13, at + _forward * 0.05, 0.009, 0.0, 0.65)
	elif _pattern == "cleave":
		var radius: float = float(_skill.radius) + progress * 0.08
		var span: float = deg_to_rad(float(_skill.span_degrees))
		var previous := Vector3.ZERO
		var previous_core := Vector3.ZERO
		for index: int in range(25):
			var ratio := float(index) / 24.0
			var angle := lerpf(-span * 0.5, span * 0.5, ratio)
			var point: Vector3 = _from + _forward * (0.32 + cos(angle) * radius * 0.72) + Vector3.UP * (float(_skill.height) - sin(angle) * radius * 0.70)
			var glow := point + _forward * 0.012
			if index > 0:
				var taper: float = sin(ratio * PI)
				_line(air, aa, previous, point, float(_skill.width) * taper, sin((ratio - 1.0 / 24.0) * PI), taper)
				_line(core, ca, previous_core, glow, float(_skill.core_width) * taper, 0.8, 1.0)
			previous = point
			previous_core = glow
		for index: int in range(int(_skill.streak_count)):
			var offset := float(index) - float(int(_skill.streak_count) - 1) * 0.5
			var at := _to + _side * offset * 0.07 + _forward * progress * 0.26 + Vector3.UP * (0.05 + sin(progress * PI) * 0.12)
			_line(dust, da, at - _side * 0.045, at + _side * 0.065 + Vector3.UP * 0.05, 0.018, 0.0, 0.5)
	else:
		var radius: float = float(_skill.radius) + progress * 0.16
		var span: float = deg_to_rad(float(_skill.span_degrees))
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		var core_left := PackedVector3Array()
		var core_right := PackedVector3Array()
		var edges := PackedFloat32Array()
		var core_lift: Vector3 = Vector3.UP * (float(_skill.core_height) - float(_skill.height))
		# Each sampled point owns one tangent/camera-facing width. Adjacent
		# strips reuse those endpoints instead of making separate line caps.
		for index: int in range(25):
			var ratio: float = float(index) / 24.0
			var angle: float = lerpf(-span * 0.5, span * 0.5, ratio)
			var point: Vector3 = _from + (_forward * cos(angle) + _side * sin(angle)) * radius + Vector3.UP * (float(_skill.height) + sin(angle) * 0.12)
			var tangent: Vector3 = ((_side * cos(angle) - _forward * sin(angle)) * radius + Vector3.UP * cos(angle) * 0.12).normalized()
			var across: Vector3 = _across(tangent, point)
			var taper: float = maxf(0.0, sin(ratio * PI))
			left.append(point - across * float(_skill.width) * taper)
			right.append(point + across * float(_skill.width) * taper)
			core_left.append(point + core_lift - across * float(_skill.core_width) * taper)
			core_right.append(point + core_lift + across * float(_skill.core_width) * taper)
			edges.append(taper)
		for index: int in range(24):
			_strip(air, aa, left[index], right[index], right[index + 1], left[index + 1], edges[index], edges[index + 1])
			_strip(core, ca, core_left[index], core_right[index], core_right[index + 1], core_left[index + 1], edges[index], edges[index + 1])
		for index: int in range(int(_skill.streak_count)):
			var angle: float = lerpf(-span * 0.48, span * 0.48, float(index) / float(maxi(1, int(_skill.streak_count) - 1)))
			var outward: Vector3 = _forward * cos(angle) + _side * sin(angle)
			var at: Vector3 = _from + outward * (radius + 0.08 + progress * 0.20) + Vector3.UP * (0.06 + sin(progress * PI) * 0.10)
			_line(dust, da, at - _side * 0.07, at + _side * 0.10 + Vector3.UP * 0.06, 0.025, 0.0, 0.48)
	_upload("air", air, aa, opacity * 0.78)
	_upload("core", core, ca, opacity * 0.96)
	_upload("dust", dust, da, opacity * 0.60)


func _play_audio(kind: String) -> void:
	if _muted or not is_instance_valid(_fx_root):
		return
	var stream: AudioStream = _streams.get(_skill_id + ":" + kind) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = kind.capitalize() + "Audio"
	player.stream = stream
	player.volume_db = _volume_db
	_fx_root.add_child(player)
	_audio_players.append(player)
	player.finished.connect(_audio_finished.bind(player))
	player.play()
	_audio_play_count += 1
	_audio_history.append({"kind": kind, "skill_id": _skill_id, "volume_db": _volume_db,
		"at_seconds": _elapsed, "begin_count": _begin_count, "stream": str(_skill.get(kind, ""))})
	while _audio_history.size() > 24:
		_audio_history.pop_front()


func _audio_finished(player: AudioStreamPlayer) -> void:
	_audio_players.erase(player)
	if is_instance_valid(player):
		# A signal emitter is locked until its finished callback returns.
		player.queue_free()


func _clear_audio() -> void:
	for player: AudioStreamPlayer in _audio_players:
		if is_instance_valid(player):
			player.stop()
			player.free()
	_audio_players.clear()


func audit() -> Dictionary:
	var visible_meshes := 0
	var vertex_count := 0
	var visible_mesh_vertices := 0
	var paused_audio := 0
	for player: AudioStreamPlayer in _audio_players:
		paused_audio += 1 if is_instance_valid(player) and player.stream_paused else 0
	for node: MeshInstance3D in _meshes.values():
		if is_instance_valid(node):
			visible_meshes += 1 if node.visible and (node.mesh as ArrayMesh).get_surface_count() > 0 else 0
			if (node.mesh as ArrayMesh).get_surface_count() > 0:
				vertex_count += (node.mesh as ArrayMesh).surface_get_array_len(0)
				if node.is_visible_in_tree():
					for surface: int in range(node.mesh.get_surface_count()):
						var arrays: Array = node.mesh.surface_get_arrays(surface)
						if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
							visible_mesh_vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return {"active": _active, "configured": _configured, "skill_id": _skill_id, "last_skill_id": _last_skill_id,
		"recipe_mode": _recipe_mode, "pattern": _pattern, "release_count": _release_count, "finish_count": _finish_count,
		"live_nodes": _fx_root.get_child_count() if is_instance_valid(_fx_root) else 0,
		"phase": _phase, "mesh_count": _meshes.size(), "visible_mesh_count": visible_meshes,
		"vertex_count": vertex_count, "trail_sample_count": _samples.size(), "blade_sample_count": _blade_sample_count,
		"visible_mesh_vertices": visible_mesh_vertices,
		"audio_player_count": _audio_players.size(), "muted": _muted, "audio_enabled": not _muted,
		"audio_paused_count": paused_audio,
		"volume_db": _volume_db, "begin_count": _begin_count, "impact_count": _impact_count,
		"audio_play_count": _audio_play_count, "audio_history": _audio_history.duplicate(true),
		"elapsed": _elapsed, "from": _from, "to": _to, "blade_base": _blade_base, "blade_tip": _blade_tip,
		"clock": "Stage.step only", "authority": "presentation only", "light_count": 0}


func _exit_tree() -> void:
	cancel()
