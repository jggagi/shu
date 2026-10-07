extends Node

const PLAYER_BASE_PATH := "res://assets/art/v2/jiang-yanqiu-v2.png"
const MENTOR_BASE_PATH := "res://assets/art/v2/ye-zhixian-v2.png"
const PLAYER_CLOSED_PATH := "res://assets/art/tingyu_actors/player-closed.png"
const PLAYER_REST_PATH := "res://assets/art/tingyu_actors/player-rest.png"
const MENTOR_LISTEN_PATH := "res://assets/art/tingyu_actors/mentor-listen.png"
const MENTOR_TEACH_PATH := "res://assets/art/tingyu_actors/mentor-teach.png"
const BREATH_STRENGTH_PARAM := "actor_breath_strength"
const BREATH_PHASE_PARAM := "actor_breath_phase"
const BREATH_ACTOR_PARAM := "actor_breath_is_mentor"
const BLINK_DURATION := 0.13
const BLINK_MIN_INTERVAL := 6.0
const BLINK_MAX_INTERVAL := 10.0
const IDLE_BREATH_PERIOD := 4.8
const TRAIN_DURATION := 1.8
const REST_DURATION := 1.6

var _host: Control
var _player: TextureRect
var _mentor: TextureRect
var _player_material: ShaderMaterial
var _mentor_material: ShaderMaterial
var _player_base: Texture2D
var _mentor_base: Texture2D
var _player_closed: Texture2D
var _player_rest: Texture2D
var _mentor_listen: Texture2D
var _mentor_teach: Texture2D
var _action_kind := ""
var _action_elapsed := 0.0
var _blink_active := false
var _blink_started_at := -1.0
var _next_blink_at := 6.0
var _observed_weather_elapsed := 0.0
var _blink_rng := RandomNumberGenerator.new()
var _shader_uniform_cache: Dictionary = {}


func setup(host: Control, player: TextureRect, mentor: TextureRect) -> void:
	_host = host
	_player = player
	_mentor = mentor
	_player_material = player.material as ShaderMaterial
	_mentor_material = mentor.material as ShaderMaterial
	_shader_uniform_cache.clear()
	_cache_shader_parameters(_player_material)
	_cache_shader_parameters(_mentor_material)

	# Keep the original v2 art as the stable fallback. Optional actor poses are
	# loaded at runtime so the module remains usable before those files exist.
	_player_base = _load_optional_texture(PLAYER_BASE_PATH)
	_mentor_base = _load_optional_texture(MENTOR_BASE_PATH)
	if _player_base == null:
		_player_base = player.texture
	if _mentor_base == null:
		_mentor_base = mentor.texture
	_player_closed = _load_optional_texture(PLAYER_CLOSED_PATH)
	_player_rest = _load_optional_texture(PLAYER_REST_PATH)
	_mentor_listen = _load_optional_texture(MENTOR_LISTEN_PATH)
	_mentor_teach = _load_optional_texture(MENTOR_TEACH_PATH)

	_blink_rng.seed = 20261007
	_observed_weather_elapsed = _weather_elapsed()
	_next_blink_at = _observed_weather_elapsed + _next_blink_interval()
	_restore_actor_textures()
	_set_actor_kind(_player_material, false)
	_set_actor_kind(_mentor_material, true)
	_set_breath(_player_material, 0.0, 0.0)
	_set_breath(_mentor_material, 0.0, 0.0)


func advance(delta: float) -> void:
	if _host == null or _player == null or _mentor == null:
		return

	var weather_elapsed := _weather_elapsed()
	if weather_elapsed < _observed_weather_elapsed:
		# A host reset rewinds the environment-owned presentation clock.
		_cancel_action()
		_blink_active = false
		_blink_rng.seed = 20261007
		_next_blink_at = weather_elapsed + _next_blink_interval()
		_restore_actor_textures()
	_observed_weather_elapsed = weather_elapsed
	if _host_tea_active():
		_cancel_action()
		_blink_active = false
		_blink_started_at = -1.0
		_restore_actor_textures()
		_set_breath(_player_material, 0.0, 0.0)
		_set_breath(_mentor_material, 0.0, 0.0)
		return

	_advance_action(delta)
	var dynamic_enabled := _weather_dynamic_enabled()
	var foreground_busy := _foreground_busy()
	var active := is_action_active()

	if active:
		_update_action_pose()
		if dynamic_enabled:
			_update_action_breath()
		_set_breath(_mentor_material, 0.0, 0.0)
		# A core action pose still completes in Static; only idle motion is frozen.
		return

	if foreground_busy:
		if _blink_active:
			_blink_active = false
			_blink_started_at = -1.0
			_player.texture = _player_base
			_next_blink_at = weather_elapsed + _next_blink_interval()
		else:
			_player.texture = _player_base
		_mentor.texture = _mentor_base
		_set_breath(_player_material, 0.0, 0.0)
		_set_breath(_mentor_material, 0.0, 0.0)
		return
	if not _blink_active:
		_player.texture = _player_base
		_mentor.texture = _mentor_base

	# Static keeps the current actor art and freezes both breathing and blink.
	if not dynamic_enabled:
		var frozen_phase := TAU * weather_elapsed / IDLE_BREATH_PERIOD
		_set_breath(_player_material, 3.0, frozen_phase)
		_set_breath(_mentor_material, 3.0, frozen_phase)
		return

	_mentor.texture = _mentor_base
	_set_breath(_player_material, 3.0, TAU * weather_elapsed / IDLE_BREATH_PERIOD)
	_set_breath(_mentor_material, 3.0, TAU * weather_elapsed / IDLE_BREATH_PERIOD)
	_advance_idle_blink(weather_elapsed)


func play_action(kind: String) -> void:
	if not ["train", "rest", "listen", "teach"].has(kind):
		return
	_action_kind = kind
	_action_elapsed = 0.0
	_blink_active = false
	_blink_started_at = -1.0
	_next_blink_at = _weather_elapsed() + _next_blink_interval()
	_player.texture = _player_base
	_mentor.texture = _mentor_base
	if kind == "train":
		if _player_closed != null:
			_player.texture = _player_closed
	elif kind == "rest":
		if _player_rest != null:
			_player.texture = _player_rest
	elif kind == "listen":
		if _mentor_listen != null:
			_mentor.texture = _mentor_listen
	elif kind == "teach":
		if _mentor_teach != null:
			_mentor.texture = _mentor_teach
	_set_breath(_mentor_material, 0.0, 0.0)


func is_action_active() -> bool:
	return _action_kind != ""


func reset() -> void:
	_cancel_action()
	_blink_active = false
	_blink_started_at = -1.0
	_blink_rng.seed = 20261007
	_observed_weather_elapsed = _weather_elapsed()
	_next_blink_at = _observed_weather_elapsed + _next_blink_interval()
	_restore_actor_textures()
	_set_breath(_player_material, 0.0, 0.0)
	_set_breath(_mentor_material, 0.0, 0.0)


func _advance_action(delta: float) -> void:
	if _action_kind == "":
		return
	if _action_kind == "train":
		_action_elapsed += maxf(0.0, delta)
		if _action_elapsed >= TRAIN_DURATION:
			_cancel_action()
	elif _action_kind == "rest":
		_action_elapsed += maxf(0.0, delta)
		if _action_elapsed >= REST_DURATION:
			_cancel_action()
	elif _action_kind == "listen" and not _host_dialogue_open():
		_cancel_action()
	elif _action_kind == "teach" and not _host_awaiting_continue():
		_cancel_action()


func _update_action_pose() -> void:
	_player.texture = _player_base
	_mentor.texture = _mentor_base
	match _action_kind:
		"train":
			if _player_closed != null:
				_player.texture = _player_closed
		"rest":
			if _player_rest != null:
				_player.texture = _player_rest
		"listen":
			if _mentor_listen != null:
				_mentor.texture = _mentor_listen
		"teach":
			if _mentor_teach != null:
				_mentor.texture = _mentor_teach


func _update_action_breath() -> void:
	var strength := 0.0
	var phase := 0.0
	if _action_kind == "train":
		var elapsed := clampf(_action_elapsed, 0.0, TRAIN_DURATION)
		if elapsed < 0.55:
			strength = lerpf(0.0, 8.0, _smoothstep01(elapsed / 0.55))
		elif elapsed < 1.2:
			strength = 8.0
		else:
			strength = lerpf(8.0, 0.0, _smoothstep01((elapsed - 1.2) / 0.6))
		phase = PI * 0.5
	_set_breath(_player_material, strength, phase)


func _advance_idle_blink(weather_elapsed: float) -> void:
	if _blink_active:
		if weather_elapsed - _blink_started_at >= BLINK_DURATION:
			_blink_active = false
			_blink_started_at = -1.0
			_player.texture = _player_base
		return
	if weather_elapsed >= _next_blink_at:
		_blink_active = true
		_blink_started_at = weather_elapsed
		_next_blink_at = weather_elapsed + _next_blink_interval()
		if _player_closed != null:
			_player.texture = _player_closed


func _next_blink_interval() -> float:
	return _blink_rng.randf_range(BLINK_MIN_INTERVAL, BLINK_MAX_INTERVAL)


func _smoothstep01(value: float) -> float:
	var weight := clampf(value, 0.0, 1.0)
	return weight * weight * (3.0 - 2.0 * weight)


func _load_optional_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _restore_actor_textures() -> void:
	if _player != null:
		_player.texture = _player_base
	if _mentor != null:
		_mentor.texture = _mentor_base


func _cancel_action() -> void:
	_action_kind = ""
	_action_elapsed = 0.0


func _set_breath(material: ShaderMaterial, strength: float, phase: float) -> void:
	if material == null or material.shader == null:
		return
	if _has_shader_parameter(material, BREATH_STRENGTH_PARAM):
		material.set_shader_parameter(BREATH_STRENGTH_PARAM, strength)
	if _has_shader_parameter(material, BREATH_PHASE_PARAM):
		material.set_shader_parameter(BREATH_PHASE_PARAM, phase)


func _set_actor_kind(material: ShaderMaterial, is_mentor: bool) -> void:
	if material == null or material.shader == null:
		return
	if _has_shader_parameter(material, BREATH_ACTOR_PARAM):
		material.set_shader_parameter(BREATH_ACTOR_PARAM, is_mentor)


func _cache_shader_parameters(material: ShaderMaterial) -> void:
	if material == null or material.shader == null:
		return
	var available: Dictionary = {}
	for parameter: Dictionary in material.shader.get_shader_uniform_list():
		available[str(parameter.get("name", ""))] = true
	_shader_uniform_cache[material.get_instance_id()] = available


func _has_shader_parameter(material: ShaderMaterial, parameter_name: String) -> bool:
	if material == null:
		return false
	var available: Dictionary = _shader_uniform_cache.get(material.get_instance_id(), {})
	return bool(available.get(parameter_name, false))


func _weather_elapsed() -> float:
	if _host == null:
		return 0.0
	var weather: Object = _host.get("weather")
	return float(weather.get("elapsed")) if weather != null else 0.0


func _weather_dynamic_enabled() -> bool:
	if _host == null:
		return false
	var weather: Object = _host.get("weather")
	return bool(weather.get("enabled")) if weather != null else false


func _foreground_busy() -> bool:
	if _host == null:
		return false
	var busy_method := Callable(_host, "foreground_attention_busy")
	if busy_method.is_valid():
		return bool(busy_method.call())
	return bool(_host.get("busy")) or _host_dialogue_open() or _host_awaiting_continue()


func _host_dialogue_open() -> bool:
	if _host == null:
		return false
	var state: Object = _host.get("state")
	return bool(state.get("dialogue_open")) if state != null else false


func _host_awaiting_continue() -> bool:
	return _host != null and bool(_host.get("awaiting_continue"))


func _host_tea_active() -> bool:
	if _host == null:
		return false
	var state: Object = _host.get("state")
	return bool(state.get("tea_active")) if state != null else false
