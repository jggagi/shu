extends Node3D
## A finite palm presentation. Stage advances body, hand anchor and this clock.
const CONFIG_PATH := "res://assets/art/mountain_ambush/palm_lab/v2/palm-impact.json"
const IMPACT_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha;
uniform sampler2D atlas_tex : filter_linear, repeat_disable;
uniform float frame = 0.0;
uniform float angle = 0.0;
void vertex() {
	vec2 p = VERTEX.xy;
	VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * p;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 cell = vec2(mod(frame, 8.0), floor(frame / 8.0));
	vec4 pixel = texture(atlas_tex, (UV + cell) / vec2(8.0, 4.0));
	ALBEDO = pixel.rgb;
	ALPHA = pixel.a;
}
"""
var _config: Dictionary = {}
var _textures: Dictionary = {}
var _streams: Dictionary = {}
var _audio_players: Array[AudioStreamPlayer] = []
var _muted := false
var _volume_db := -12.0
var _audio_play_count := 0
var _audio_history: Array[Dictionary] = []
var _ready := false
var _active := false
var _elapsed := 0.0
var _phase := "idle"
var _root: Node3D
var _charge: Sprite3D
var _bands: Array[MeshInstance3D] = []
var _tails: Array[MeshInstance3D] = []
var _dust: Array[MeshInstance3D] = []
var _chips: Array[MeshInstance3D] = []
var _impact: MeshInstance3D
var _light: OmniLight3D
var _target := Vector3.ZERO
var _origin := Vector3.ZERO
var _release_origin := Vector3.ZERO
var _direction := Vector3.FORWARD
var _side := Vector3.RIGHT
var _released := false
var _impacted := false
var _begin_count := 0
var _release_count := 0
var _impact_count := 0
var _finish_count := 0
var _frame := 0
var _vertex_count := 0
var _default_config: Dictionary = {}
var _recipe_mode := false
var _pattern := "pressure"
var _move_id := ""
var _aim_target := Vector3.ZERO
var _release_origin_locked := false
var _recipe_total_sampled := false

func setup() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not data is Dictionary:
		return {"ok": false, "reason": "Palm impact configuration is missing"}
	_default_config = data.duplicate(true)
	return _load_config(data)

func _load_config(data: Dictionary) -> Dictionary:
	var textures: Dictionary = {}
	var streams: Dictionary = {}
	for id: String in ["wind", "dust", "impact"]:
		var tex := load(str(data.assets[id])) as Texture2D
		if tex == null:
			return {"ok": false, "reason": "Palm impact texture is missing"}
		textures[id] = tex
	var atlas: Texture2D = textures.impact
	if atlas.get_width() != 2048 or atlas.get_height() != 1024:
		return {"ok": false, "reason": "Palm impact expects the authored 32-frame atlas"}
	for kind: String in ["release", "impact"]:
		var stream := load(str(data.audio[kind])) as AudioStreamWAV
		if stream == null or stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			return {"ok": false, "reason": "Palm cue is missing or loops"}
		streams[kind] = stream
	_config = data.duplicate(true)
	_textures = textures
	_streams = streams
	_ready = true
	return {"ok": true, "reason": ""}

func begin_demo(palm: Vector3, target: Vector3) -> void:
	cancel()
	if not _ready or not palm.is_finite() or not target.is_finite() or not bool(_load_config(_default_config).ok):
		return
	_begin_configured_demo(palm, target)

func begin_recipe(move: Dictionary, from: Vector3, to: Vector3, anchors: Dictionary = {}) -> void:
	cancel()
	if not _ready or not from.is_finite() or not to.is_finite():
		return
	var visual: Dictionary = move.get("visual", {})
	var timing: Dictionary = move.get("timing", {})
	var pattern := str(visual.get("pattern", ""))
	if str(visual.get("type", "")) != "palm" or pattern not in ["pressure", "curve", "brace"] or not visual.get("config") is Dictionary:
		return
	var config: Dictionary = (visual.config as Dictionary).duplicate(true)
	config["release_seconds"] = float(timing.get("release", 0.0))
	config["flight_seconds"] = float(timing.get("impact", 0.0)) - float(timing.get("release", 0.0))
	config["duration"] = float(timing.get("total", 0.0))
	config["audio"] = (move.get("audio", {}) as Dictionary).duplicate(true)
	if float(config.flight_seconds) <= 0.0 or float(config.duration) <= 0.0 or not bool(_load_config(config).ok):
		return
	_recipe_mode = true
	_pattern = pattern
	_move_id = str(move.get("id", ""))
	var palm: Vector3 = anchors.get("palm", from)
	_begin_configured_demo(palm, to)
	if anchors.get("release_origin") is Vector3:
		_set_release_origin(to_local(anchors.release_origin))
		_release_origin_locked = true

func _begin_configured_demo(palm: Vector3, target: Vector3) -> void:
	_origin = to_local(palm)
	_target = to_local(target)
	_aim_target = _target
	_active = true
	_released = false
	_impacted = false
	_frame = 0
	_begin_count += 1
	_root = Node3D.new()
	_root.name = "TransientPalmImpact"
	add_child(_root)
	_charge = Sprite3D.new()
	_charge.name = "PalmGatheredAir"
	_charge.texture = _textures.wind
	_charge.pixel_size = 0.48 / float((_textures.wind as Texture2D).get_width())
	_charge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_charge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge.modulate = Color("#bedcd2")
	_root.add_child(_charge)
	for index: int in range(3):
		_bands.append(_air_mesh("PressureFront" + str(index)))
		_tails.append(_air_mesh("ShortWindTail" + str(index)))
	_impact = MeshInstance3D.new()
	_impact.name = "EffekseerBrokenPressure"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(_config.impact_size)
	_impact.mesh = quad
	_impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = IMPACT_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("atlas_tex", _textures.impact)
	_impact.material_override = mat
	_impact.position = _target
	_root.add_child(_impact)
	for index: int in range(6):
		var dust := MeshInstance3D.new()
		dust.name = "LowDust" + str(index)
		dust.mesh = PlaneMesh.new()
		(dust.mesh as PlaneMesh).size = Vector2.ONE
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.albedo_texture = _textures.dust
		material.albedo_color = Color("#9f9078")
		dust.material_override = material
		dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(dust)
		_dust.append(dust)
	for index: int in range(8):
		var chip := MeshInstance3D.new()
		chip.name = "LooseGrit" + str(index)
		var mesh := PrismMesh.new()
		mesh.size = Vector3(0.045, 0.035, 0.07) * (0.75 + float(index % 3) * 0.22)
		chip.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#716d56") if index % 2 == 0 else Color("#a49573")
		material.roughness = 1.0
		chip.material_override = material
		chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(chip)
		_chips.append(chip)
	_light = OmniLight3D.new()
	_light.name = "BriefPalmBounce"
	_light.light_color = Color("#d7ebc8")
	_light.omni_range = 2.8
	_light.omni_attenuation = 1.8
	_light.shadow_enabled = false
	_light.position = _target + Vector3.UP * 0.22
	_root.add_child(_light)
	_update(palm)

func sample_recipe(seconds: float, anchors: Dictionary = {}, emit_events: bool = true) -> void:
	if not _active or not _recipe_mode or not is_finite(seconds):
		return
	if not emit_events:
		_clear_audio()
	_elapsed = maxf(0.0, seconds)
	if anchors.get("release_origin") is Vector3:
		_set_release_origin(to_local(anchors.release_origin))
		_release_origin_locked = true
	var palm: Vector3 = anchors.get("palm", to_global(_origin))
	_update(palm, emit_events)
	if _elapsed >= float(_config.duration):
		if not _recipe_total_sampled:
			_recipe_total_sampled = true
			_finish_count += 1
		_phase = "finished"
		for node: Node in _root.get_children():
			if node is Node3D and not node is Light3D:
				(node as Node3D).visible = false
		_light.light_energy = 0.0

func _set_release_origin(origin: Vector3) -> void:
	_release_origin = origin
	_direction = (_aim_target - _release_origin).normalized()
	if _direction.length_squared() < 0.00001:
		_direction = Vector3.FORWARD
	_side = _direction.cross(Vector3.UP).normalized()
	_target = _release_origin + _direction * 0.75 if _pattern == "brace" else _aim_target
	_impact.position = _target
	_light.position = _target + Vector3.UP * 0.22
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var screen_direction: Vector2 = camera.unproject_position(to_global(_target)) - camera.unproject_position(to_global(origin))
		(_impact.material_override as ShaderMaterial).set_shader_parameter("angle", -screen_direction.angle())

func _air_mesh(label_text: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label_text
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.vertex_color_use_as_albedo = true
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(node)
	return node

func step(delta: float, palm: Vector3) -> void:
	if not _active:
		return
	var dt: float = maxf(0.0, delta) if is_finite(delta) else 0.0
	if _recipe_mode:
		sample_recipe(_elapsed + dt, {"palm": palm})
		if _active and _elapsed >= float(_config.duration):
			cancel()
		return
	_elapsed += dt
	if _elapsed >= float(_config.duration):
		_finish_count += 1
		cancel()
		return
	_update(palm)

func _update(palm: Vector3, emit_events: bool = true) -> void:
	var release: float = float(_config.release_seconds)
	var hit: float = release + float(_config.flight_seconds)
	var gathering: float = clampf(_elapsed / release, 0.0, 1.0)
	_charge.position = to_local(palm)
	_charge.scale = Vector3.ONE * lerpf(0.35, 1.05, gathering)
	_charge.modulate.a = sin(gathering * PI) * 0.24
	_charge.visible = _elapsed < release
	if not _released and _elapsed >= release:
		_released = true
		_release_count += 1
		if emit_events:
			_play_audio("release")
		if not _release_origin_locked:
			_set_release_origin(to_local(palm))
	_phase = "gather" if _elapsed < 0.38 else ("drive" if _elapsed < release else "flight")
	_vertex_count = 0
	for index: int in range(3):
		var lag: float = float(index) * 0.028
		var progress: float = clampf((_elapsed - release - lag) / float(_config.flight_seconds), 0.0, 1.0)
		var hold: float = float(_config.get("hold_seconds", 0.4)) if _pattern == "brace" else 0.0
		var visible_now: bool = _elapsed >= release + lag and _elapsed < hit + lag + hold
		_bands[index].visible = visible_now
		_tails[index].visible = visible_now
		if visible_now:
			var center := _release_origin.lerp(_target, progress)
			var radius: float = lerpf(0.28, 0.68, progress) * (1.0 - float(index) * 0.15)
			var alpha: float = sin(clampf(progress * 0.85 + 0.12, 0.0, 1.0) * PI) * (0.84 - float(index) * 0.20)
			if _pattern == "curve":
				center += _side * sin(progress * PI) * float(_config.get("curve_amount", 0.35)) + Vector3.UP * sin(progress * PI) * 0.10
			elif _pattern == "brace":
				# A short held pressure front, rather than a second long projectile.
				center = _release_origin + _direction * (0.60 + 0.10 * progress) + _side * float(index - 1) * 0.035
				radius = lerpf(0.38, 0.70, progress) * (1.0 - float(index) * 0.10)
				alpha = (0.72 - float(index) * 0.16) * clampf((_elapsed - release - lag) / 0.06, 0.0, 1.0) * clampf((hit + lag + hold - _elapsed) / 0.12, 0.0, 1.0)
			_bands[index].mesh = _front(center, radius, alpha, index)
			_tails[index].mesh = _tail(center, radius, alpha * 0.45, index)
	_impact.visible = _elapsed >= hit and _elapsed < hit + float(_config.impact_seconds)
	_light.light_energy = 0.0
	if not _impacted and _elapsed >= hit:
		_impacted = true
		_impact_count += 1
		if emit_events:
			_play_audio("impact")
	var since: float = _elapsed - hit
	if since >= 0.0:
		_phase = "impact" if since < 0.14 else "settling"
		_frame = clampi(int(since / float(_config.impact_seconds) * 32.0), 0, 31)
		(_impact.material_override as ShaderMaterial).set_shader_parameter("frame", float(_frame))
		_light.light_energy = maxf(0.0, 1.0 - since / 0.12) * 0.85
	else:
		_frame = 0
		(_impact.material_override as ShaderMaterial).set_shader_parameter("frame", 0.0)
	for index: int in range(_dust.size()):
		var age: float = since - float(index % 3) * 0.034
		var p: float = clampf(age / float(_config.dust_seconds), 0.0, 1.0)
		var spread: float = (float(index) - 2.5) * 0.24
		var dust: MeshInstance3D = _dust[index]
		dust.visible = age > 0.0 and p < 1.0
		dust.position = _target + _direction * (p * (0.65 + float(index % 2) * 0.30)) + _side * spread * p
		dust.position.y = 0.045 + float(index) * 0.007
		dust.rotation.y = atan2(_direction.x, _direction.z) + spread * 0.6
		dust.scale = Vector3(lerpf(0.35, 1.10, p), 1.0, lerpf(0.45, 1.60, p))
		(dust.material_override as StandardMaterial3D).albedo_color.a = sin(p * PI) * (0.31 if index % 2 == 0 else 0.22)
	for index: int in range(_chips.size()):
		var p: float = clampf(since / (0.46 + float(index % 3) * 0.045), 0.0, 1.0)
		var chip: MeshInstance3D = _chips[index]
		chip.visible = since >= 0.0 and p < 1.0
		chip.position = _target + _direction * p * (0.42 + float(index % 4) * 0.13) + _side * p * (float(index) - 3.5) * 0.18
		chip.position.y = 0.04 + sin(p * PI) * (0.15 + float(index % 3) * 0.035)
		chip.rotation = Vector3(p * 4.0, float(index) + p * 3.0, p * 2.0)
		chip.scale = Vector3.ONE * (1.0 - smoothstep(0.6, 1.0, p))

func _front(center: Vector3, radius: float, alpha: float, index: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var count := 32
	for i: int in range(count + 1):
		var t: float = float(i) / float(count)
		var angle: float = lerpf(-1.85, 1.52, t) + float(index) * 0.32
		var radial := _side * sin(angle) + Vector3.UP * cos(angle) * 0.70
		var edge: float = sin(t * PI)
		var width: float = (0.16 - float(index) * 0.026) * pow(maxf(0.0, edge), 0.65)
		for j: int in range(2):
			vertices.append(center + radial * (radius + (float(j) - 0.5) * width) + _direction * cos(angle) * radius * 0.15)
			var color := Color("#f0ecd2") if j == 1 and index == 0 else Color("#b0d9cc")
			color.a = alpha * pow(maxf(0.0, edge), 0.45) * (1.0 if j == 1 else 0.40)
			colors.append(color)
		if i < count:
			var k := i * 2
			indices.append_array(PackedInt32Array([k, k + 1, k + 2, k + 1, k + 3, k + 2]))
	return _mesh(vertices, colors, indices)

func _tail(center: Vector3, radius: float, alpha: float, index: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i: int in range(13):
		var t: float = float(i) / 12.0
		var offset: float = (float(index) - 1.0) * radius * 0.5
		var pos := center - _direction * t * 0.58 + _side * (offset + sin(t * 3.0 + float(index)) * 0.08) + Vector3.UP * (0.08 + cos(t * PI) * radius * 0.20)
		for j: int in range(2):
			vertices.append(pos + Vector3.UP * (float(j) - 0.5) * 0.075 * (1.0 - t))
			var color := Color("#c2d6c7")
			color.a = alpha * (1.0 - t) * (1.0 if j == 1 else 0.05)
			colors.append(color)
		if i < 12:
			var k := i * 2
			indices.append_array(PackedInt32Array([k, k + 1, k + 2, k + 1, k + 3, k + 2]))
	return _mesh(vertices, colors, indices)

func _mesh(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	_vertex_count += vertices.size()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func set_audio(muted: bool, volume_db: float = -12.0) -> void:
	_muted = muted
	_volume_db = volume_db
	if _muted:
		_clear_audio()

func pause_recipe_audio(paused: bool) -> void:
	for player: AudioStreamPlayer in _audio_players:
		if is_instance_valid(player):
			player.stream_paused = paused

func _play_audio(kind: String) -> void:
	if _muted or not is_instance_valid(_root):
		return
	var player := AudioStreamPlayer.new()
	player.name = "Palm" + kind.capitalize() + "Audio"
	player.stream = _streams[kind]
	player.volume_db = _volume_db
	_root.add_child(player)
	_audio_players.append(player)
	player.finished.connect(_audio_finished.bind(player))
	player.play()
	_audio_play_count += 1
	_audio_history.append({"kind": kind, "at_seconds": _elapsed, "begin_count": _begin_count, "stream": _config.audio[kind], "volume_db": _volume_db})
	if _audio_history.size() > 12:
		_audio_history.pop_front()

func _audio_finished(player: AudioStreamPlayer) -> void:
	_audio_players.erase(player)
	if is_instance_valid(player):
		player.queue_free()

func _clear_audio() -> void:
	for player: AudioStreamPlayer in _audio_players:
		if is_instance_valid(player):
			player.stop()
			player.free()
	_audio_players.clear()

func cancel() -> void:
	_clear_audio()
	if is_instance_valid(_root):
		_root.free()
	_root = null
	_charge = null
	_impact = null
	_light = null
	_bands.clear()
	_tails.clear()
	_dust.clear()
	_chips.clear()
	_active = false
	_phase = "idle"
	_elapsed = 0.0
	_vertex_count = 0
	_recipe_mode = false
	_pattern = "pressure"
	_move_id = ""
	_release_origin_locked = false
	_recipe_total_sampled = false

func audit() -> Dictionary:
	var visible_count := 0
	var visible_mesh_vertices := 0
	var paused_audio := 0
	for player: AudioStreamPlayer in _audio_players:
		paused_audio += 1 if is_instance_valid(player) and player.stream_paused else 0
	if is_instance_valid(_root):
		for child: Node in _root.get_children():
			if child is Node3D and (child as Node3D).visible and not child is Light3D:
				visible_count += 1
			if child is MeshInstance3D and (child as MeshInstance3D).is_visible_in_tree():
				var mesh: Mesh = (child as MeshInstance3D).mesh
				if mesh != null:
					for surface: int in range(mesh.get_surface_count()):
						var arrays: Array = mesh.surface_get_arrays(surface)
						if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
							visible_mesh_vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return {"ready": _ready, "active": _active, "phase": _phase, "elapsed": _elapsed,
		"audio_paused_count": paused_audio,
		"recipe_mode": _recipe_mode, "pattern": _pattern, "move_id": _move_id,
		"begin_count": _begin_count, "release_count": _release_count, "impact_count": _impact_count, "finish_count": _finish_count,
		"live_nodes": _root.get_child_count() if is_instance_valid(_root) else 0,
		"visible_nodes": visible_count, "vertex_count": _vertex_count, "impact_frame": _frame,
		"visible_mesh_vertices": visible_mesh_vertices,
		"release_origin": to_global(_release_origin), "target": to_global(_target),
		"light_count": 1 if is_instance_valid(_light) else 0,
		"light_energy": _light.light_energy if is_instance_valid(_light) else 0.0,
		"assets": _config.get("assets", {}).duplicate(true), "clock": "Stage palm timeline only", "authority": "presentation only", "audio_player_count": _audio_players.size(), "audio_play_count": _audio_play_count, "audio_history": _audio_history.duplicate(true), "muted": _muted}
