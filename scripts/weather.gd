extends Node

signal changed

const EnvironmentPresenterScript = preload("res://scripts/environment_presenter.gd")
const AMBIENT = preload("res://assets/shaders/ambient.gdshader")
const WIND = preload("res://assets/shaders/bamboo_wind.gdshader")
const MIST = preload("res://assets/shaders/mist.gdshader")
const RAIN = preload("res://assets/shaders/rain.gdshader")
const AmbientAudio = preload("res://scripts/tingyu_ambient_audio.gd")
const EAVE_DRIPS = preload("res://assets/shaders/eave_drips.gdshader")
const WEATHER_IDS := ["clear", "cloudy", "light_rain"]
const WEATHER_LABELS := {
	"clear": "晴",
	"cloudy": "多云",
	"light_rain": "小雨",
}

var enabled := true
var elapsed := 0.0
var phase := "多云"
var motion_paused := false # Render audit only; presentation transitions continue.
var config: Dictionary = {}
var geometry_config: Dictionary = {}
var scene_root: Control
var art_root: Control
var backdrop_art: TextureRect
var presenter: EnvironmentPresenter
var lit: Array[Dictionary] = []
var mist_layers: Array[TextureRect] = []
var rain_nodes: Array[TextureRect] = []
var bamboo: TextureRect
var bamboo_shadow: TextureRect
var bamboo_material: ShaderMaterial
var shadow_material: ShaderMaterial
var noise: NoiseTexture2D
var _time_index_mapping: Array = []
var update_accumulator := 0.0
var salient_attention_getter := Callable()
var foreground_attention_getter := Callable()
var _mist_layer_config: Array = []
var _steam_config: Dictionary = {}
var _incense_smoke_config: Dictionary = {}
var _wetness_config: Dictionary = {}
var _window_light_config: Dictionary = {}
var tea_steam: TextureRect
var _steam_material: ShaderMaterial
var incense_smoke: TextureRect
var _incense_smoke_material: ShaderMaterial
var _steam_wind_strength := 0.0
var _steam_wind_direction := 1.0
var _wetness := 0.0
var _window_light_strength := 0.0
var _window_light_from := 0.0
var _window_light_target := 0.0
var _window_light_elapsed := 0.0
var _window_light_duration := 0.0
var _wind_config: Dictionary = {}
var _wind_rng := RandomNumberGenerator.new()
var _next_gust_at := 0.0
var _gust_started_at := -1.0
var _gust_direction := 1.0
var _wind_attention_gain := 1.0
var _gust_bamboo_sway := 0.0
var _gust_tassel_sway := 0.0
var eave_drops: TextureRect
var _eave_material: ShaderMaterial
var _eave_config: Dictionary = {}
var _eave_rng := RandomNumberGenerator.new()
var _eave_pools: Array[Dictionary] = []
var _eave_was_raining := false
var _eave_tail_deadline := -1.0
var ambient_audio: Node
var _lamp_config: Dictionary = {}
var _lamp_profile_id := ""
var _lamp_strength := 0.0
var _lamp_from := 0.0
var _lamp_target := 0.0
var _lamp_blend_elapsed := 0.0
var _lamp_flicker := 1.0


func setup(scene: Control, backdrop: TextureRect, attention_getter: Callable = Callable()) -> void:
	scene_root = scene
	salient_attention_getter = attention_getter
	foreground_attention_getter = attention_getter
	art_root = backdrop.get_parent()
	backdrop_art = backdrop
	config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/tingyu_environment.json"))
	geometry_config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/weather.json"))
	_time_index_mapping = config.get("time_index_mapping", [])
	_mist_layer_config = config.get("mist_layers", [])
	_steam_config = config.get("tea_steam", {})
	_incense_smoke_config = config.get("incense_smoke", {})
	_wetness_config = config.get("wetness", {})
	_window_light_config = config.get("window_light", {})
	_wind_config = config.get("wind_moments", {})
	_reset_wind_moments()
	_eave_config = config.get("eave_drips", {})
	_reset_eave_drips()
	_lamp_config = config.get("lantern_light", {})
	_set_lamp_profile("mao", false)
	presenter = EnvironmentPresenterScript.new()
	presenter.configure(config)
	phase = _weather_label(presenter.weather_id)
	_set_window_light_target(false, 0.0)
	_steam_wind_strength = get_current_wind_strength()

	noise = NoiseTexture2D.new()
	noise.width = 128
	noise.height = 128
	noise.seamless = true
	var generator := FastNoiseLite.new()
	generator.seed = 4712
	generator.frequency = 0.025
	noise.noise = generator

	_register_lit_art(backdrop, false)
	(backdrop.material as ShaderMaterial).set_shader_parameter("tassel_motion_enabled", true)
	(backdrop.material as ShaderMaterial).set_shader_parameter("lamp_core_enabled", true)
	for i in range(2):
		var layer: Dictionary = _mist_layer_config[i] if i < _mist_layer_config.size() else {}
		var mist := TextureRect.new()
		mist.position = Vector2(265, 23)
		mist.size = Vector2(875, 343)
		mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mist.texture = noise
		mist.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var material := ShaderMaterial.new()
		material.shader = MIST
		material.set_shader_parameter("mist_noise", noise)
		var lower_fade: Array = layer.get("lower_fade", [40, 100] if i == 0 else [155, 215])
		var upper_fade: Array = layer.get("upper_fade", [195, 270] if i == 0 else [315, 365])
		var noise_scale: Array = layer.get("noise_scale", [1.7, 0.65] if i == 0 else [2.2, 0.9])
		material.set_shader_parameter("lower_fade", Vector2(lower_fade[0], lower_fade[1]))
		material.set_shader_parameter("upper_fade", Vector2(upper_fade[0], upper_fade[1]))
		material.set_shader_parameter("noise_scale", Vector2(noise_scale[0], noise_scale[1]))
		material.set_shader_parameter("drift_speed", float(layer.get("drift_speed", 0.011 if i == 0 else -0.007)))
		material.set_shader_parameter("phase_offset", float(layer.get("phase_offset", float(i) * 0.43)))
		mist.material = material
		art_root.add_child(mist)
		mist_layers.append(mist)

	_build_tea_steam()
	_build_incense_smoke()

	_make_rain(Rect2(269, 20, 706, 360), float(geometry_config.rain_main) / 2.0, 270.0, 180.0)
	_make_rain(Rect2(1058, 20, 82, 340), float(geometry_config.rain_side) / 2.0, 240.0, 170.0)
	_build_eave_drips()
	ambient_audio = AmbientAudio.new()
	ambient_audio.name = "TingyuAmbientAudio"
	add_child(ambient_audio)
	ambient_audio.setup(self, config.get("ambient_audio", {}))
	var rect: Array = geometry_config.bamboo_rect
	bamboo_shadow = _bamboo(Rect2(83, 5, 188, 503))
	shadow_material = ShaderMaterial.new()
	shadow_material.shader = WIND
	shadow_material.set_shader_parameter("shadow_pass", true)
	bamboo_shadow.material = shadow_material
	bamboo = _bamboo(Rect2(rect[0], rect[1], rect[2], rect[3]))
	bamboo_material = ShaderMaterial.new()
	bamboo_material.shader = WIND
	bamboo.material = bamboo_material
	_apply()


func _bamboo(rect: Rect2) -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.texture = load("res://assets/art/weather3/bamboo-wind-v3.png")
	image.position = rect.position
	image.size = rect.size
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_root.add_child(image)
	return image


func add_lit_art(art: TextureRect) -> void:
	_register_lit_art(art, true)
	if presenter != null:
		_apply()


func _register_lit_art(art: TextureRect, sheltered: bool) -> void:
	var material := ShaderMaterial.new()
	material.shader = AMBIENT
	material.set_shader_parameter("cloud_noise", noise)
	material.set_shader_parameter("layer_origin", art.position)
	material.set_shader_parameter("sheltered", sheltered)
	for pair in [["lamp_center", "center", [1368, 403]], ["lamp_core_half_size", "core_half_size", [24, 58]], ["lamp_spill_center", "spill_center", [1368, 428]], ["lamp_spill_radius", "spill_radius", [235, 108]]]:
		var coordinates: Array = _lamp_config.get(pair[1], pair[2])
		material.set_shader_parameter(pair[0], Vector2(coordinates[0], coordinates[1]))
	material.set_shader_parameter("lamp_warm_color", Color(str(_lamp_config.get("warm_color", "#ffba66"))))
	material.set_shader_parameter("lamp_core_gain", float(_lamp_config.get("core_gain", 0.7)))
	material.set_shader_parameter("lamp_spill_gain", float(_lamp_config.get("spill_gain", 0.6)))
	lit.append({"art": art, "original": art.material, "weather": material, "sheltered": sheltered})
	art.material = material


func _build_tea_steam() -> void:
	var patch: Array = _steam_config.get("patch", [924, 385, 66, 78])
	tea_steam = TextureRect.new()
	tea_steam.name = "TingyuTeaSteam"
	tea_steam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tea_steam.stretch_mode = TextureRect.STRETCH_SCALE
	tea_steam.texture = noise
	tea_steam.position = Vector2(patch[0], patch[1])
	tea_steam.size = Vector2(patch[2], patch[3])
	tea_steam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tea_steam.z_index = 3
	_steam_material = ShaderMaterial.new()
	_steam_material.shader = preload("res://assets/shaders/tea_steam.gdshader")
	var origin: Array = _steam_config.get("origin", [30, 71])
	_steam_material.set_shader_parameter("steam_origin", Vector2(origin[0], origin[1]))
	_steam_material.set_shader_parameter("rise_pixels", float(_steam_config.get("rise_pixels", 54.0)))
	_steam_material.set_shader_parameter("curl_pixels", float(_steam_config.get("curl_pixels", 2.4)))
	_steam_material.set_shader_parameter("wind_drift_pixels", float(_steam_config.get("wind_drift_pixels", 3.5)))
	tea_steam.material = _steam_material
	scene_root.add_child(tea_steam)


func _build_incense_smoke() -> void:
	var patch: Array = _incense_smoke_config.get("patch", [785, 310, 76, 104])
	incense_smoke = TextureRect.new()
	incense_smoke.name = "TingyuIncenseSmoke"
	incense_smoke.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	incense_smoke.stretch_mode = TextureRect.STRETCH_SCALE
	incense_smoke.texture = noise
	incense_smoke.position = Vector2(patch[0], patch[1])
	incense_smoke.size = Vector2(patch[2], patch[3])
	incense_smoke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	incense_smoke.z_index = 3
	_incense_smoke_material = ShaderMaterial.new()
	_incense_smoke_material.shader = preload("res://assets/shaders/incense_smoke.gdshader")
	var origin: Array = _incense_smoke_config.get("origin", [36, 97])
	_incense_smoke_material.set_shader_parameter("smoke_origin", Vector2(origin[0], origin[1]))
	_incense_smoke_material.set_shader_parameter("patch_size", Vector2(patch[2], patch[3]))
	_incense_smoke_material.set_shader_parameter("rise_pixels", float(_incense_smoke_config.get("rise_pixels", 87.0)))
	_incense_smoke_material.set_shader_parameter("curl_pixels", float(_incense_smoke_config.get("curl_pixels", 3.4)))
	_incense_smoke_material.set_shader_parameter("wind_drift_pixels", float(_incense_smoke_config.get("wind_drift_pixels", 4.0)))
	_incense_smoke_material.set_shader_parameter("smoke_noise", noise)
	incense_smoke.material = _incense_smoke_material
	scene_root.add_child(incense_smoke)


func _make_rain(rect: Rect2, columns: float, speed: float, row_height: float) -> void:
	var rain := TextureRect.new()
	rain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rain.texture = noise
	rain.stretch_mode = TextureRect.STRETCH_SCALE
	rain.position = rect.position
	rain.size = rect.size
	rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rain.z_index = 1
	var material := ShaderMaterial.new()
	material.shader = RAIN
	material.set_shader_parameter("patch_origin", rect.position)
	material.set_shader_parameter("patch_size", rect.size)
	material.set_shader_parameter("columns", columns)
	material.set_shader_parameter("fall_speed", speed)
	material.set_shader_parameter("row_height", row_height)
	rain.material = material
	scene_root.add_child(rain)
	rain_nodes.append(rain)


func _build_eave_drips() -> void:
	var patch: Array = _eave_config.get("patch", [550, 26, 250, 225])
	eave_drops = TextureRect.new()
	eave_drops.name = "TingyuEaveDrips"
	eave_drops.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eave_drops.stretch_mode = TextureRect.STRETCH_SCALE
	eave_drops.texture = noise
	eave_drops.position = Vector2(patch[0], patch[1])
	eave_drops.size = Vector2(patch[2], patch[3])
	eave_drops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eave_drops.z_index = 1
	_eave_material = ShaderMaterial.new()
	_eave_material.shader = EAVE_DRIPS
	_eave_material.set_shader_parameter("patch_origin", eave_drops.position)
	_eave_material.set_shader_parameter("patch_size", eave_drops.size)
	var anchors: Array = _eave_config.get("anchors", [[561, 78], [630, 33], [725, 32]])
	for index in 3:
		_eave_material.set_shader_parameter("anchor_%d" % index, Vector2(anchors[index][0], anchors[index][1]) - eave_drops.position)
	_eave_material.set_shader_parameter("fall_seconds", float(_eave_config.get("fall_seconds", 1.0)))
	_eave_material.set_shader_parameter("fall_distance", float(_eave_config.get("fall_distance", 175.0)))
	eave_drops.material = _eave_material
	scene_root.add_child(eave_drops)


func _reset_eave_drips() -> void:
	_eave_rng.seed = int(_eave_config.get("seed", 20261022))
	_eave_pools.clear()
	_eave_was_raining = false
	_eave_tail_deadline = -1.0
	var first_delays: Array = _eave_config.get("first_collection_seconds", [2.6, 4.8, 7.3])
	for index in 3:
		_eave_pools.append({
			"anchor": index,
			"fill": 0.0,
			"collection_seconds": maxf(0.1, float(first_delays[index])),
			"drop_started_at": -1.0,
			"tail_at": -1.0,
		})


func _release_eave_drop(pool: Dictionary) -> void:
	pool.drop_started_at = elapsed
	if ambient_audio != null:
		ambient_audio.queue_drop(int(pool.anchor), elapsed, float(_eave_config.get("fall_seconds", 1.0)))
	pool.fill = 0.0
	pool.collection_seconds = _eave_rng.randf_range(
		float(_eave_config.get("collection_min_seconds", 6.0)),
		float(_eave_config.get("collection_max_seconds", 10.0))
	)


func _advance_eave_drips(step: float) -> void:
	var raining := presenter.weather_id == "light_rain"
	var fall_seconds := maxf(0.01, float(_eave_config.get("fall_seconds", 1.0)))
	if _eave_was_raining and not raining:
		var retained_water := 0.0
		for pool in _eave_pools:
			retained_water += float(pool.fill)
			if float(pool.drop_started_at) >= 0.0:
				retained_water += 0.5
		if retained_water > 0.15:
			_eave_tail_deadline = elapsed + float(_eave_config.get("tail_limit_seconds", 9.0))
			var tail_count := clampi(int(_eave_config.get("tail_drop_count", 3)), 0, _eave_pools.size())
			for index in tail_count:
				_eave_pools[index].tail_at = elapsed + float(_eave_config.get("tail_first_seconds", 2.8)) + index * float(_eave_config.get("tail_spacing_seconds", 1.8))
	if raining:
		_eave_tail_deadline = -1.0
		for pool in _eave_pools:
			pool.tail_at = -1.0
	_eave_was_raining = raining
	var rain_amount := clampf(float(presenter.get_current_environment().rain_amount), 0.0, 1.0)
	for pool in _eave_pools:
		if float(pool.drop_started_at) >= 0.0 and elapsed - float(pool.drop_started_at) >= fall_seconds:
			pool.drop_started_at = -1.0
		if raining:
			pool.fill = minf(1.0, float(pool.fill) + step * rain_amount / float(pool.collection_seconds))
			if float(pool.fill) >= 1.0 and float(pool.drop_started_at) < 0.0:
				_release_eave_drop(pool)
		elif float(pool.tail_at) >= 0.0 and elapsed <= _eave_tail_deadline:
			if elapsed >= float(pool.tail_at) and float(pool.drop_started_at) < 0.0:
				_release_eave_drop(pool)
				pool.tail_at = -1.0
			else:
				var remaining := maxf(step, float(pool.tail_at) - elapsed)
				pool.fill = minf(1.0, float(pool.fill) + step * (1.0 - float(pool.fill)) / maxf(0.01, remaining))
		else:
			pool.tail_at = -1.0
			pool.fill = maxf(0.0, float(pool.fill) - step * 0.8)


func _apply_eave_drips() -> void:
	if _eave_material == null:
		return
	var fill := Vector3.ZERO
	var ages := Vector3(-1.0, -1.0, -1.0)
	var has_water := false
	for index in _eave_pools.size():
		var pool: Dictionary = _eave_pools[index]
		fill[index] = float(pool.fill)
		if float(pool.drop_started_at) >= 0.0:
			ages[index] = maxf(0.0, elapsed - float(pool.drop_started_at))
		has_water = has_water or fill[index] > 0.001 or ages[index] >= 0.0
	_eave_material.set_shader_parameter("bead_fill", fill)
	_eave_material.set_shader_parameter("drop_age", ages)
	_eave_material.set_shader_parameter("opacity", float(_eave_config.get("opacity", 0.65)) * (0.65 + 0.35 * _wind_attention_gain))
	eave_drops.visible = has_water


func _process(delta: float) -> void:
	advance_environment(delta, false)


func advance_environment(delta: float, apply_immediately: bool = true) -> void:
	if presenter == null:
		return
	var step := maxf(delta, 0.0)
	if enabled and not motion_paused:
		elapsed += step
	presenter.advance(step)
	_advance_window_light(step)
	if enabled and not motion_paused:
		_advance_wind_moments(step)
		_advance_eave_drips(step)
		_advance_wetness(step)
	_advance_lantern(step)
	if ambient_audio != null:
		ambient_audio.advance(step)
	update_accumulator += step
	var update_hz := maxf(float(geometry_config.get("shader_update_hz", 30.0)), 1.0)
	var update_interval := 1.0 / update_hz
	if apply_immediately:
		update_accumulator = 0.0
		_apply()
	elif update_accumulator >= update_interval:
		update_accumulator = fposmod(update_accumulator, update_interval)
		_apply()


func _reset_wind_moments() -> void:
	_wind_rng.seed = int(_wind_config.get("seed", 20261021))
	_next_gust_at = float(_wind_config.get("first_delay_seconds", 8.0))
	_gust_started_at = -1.0
	_gust_direction = 1.0
	_wind_attention_gain = 1.0
	_gust_bamboo_sway = 0.0
	_gust_tassel_sway = 0.0
	_steam_wind_strength = 0.0
	_steam_wind_direction = 1.0


func _gust_wave(age: float, duration: float) -> float:
	if age <= 0.0 or age >= duration:
		return 0.0
	var envelope := pow(sin(PI * age / duration), 2.0)
	return envelope * sin(age * 2.15 + 0.4)


func _advance_wind_moments(step: float) -> void:
	var salient_busy := salient_attention_getter.is_valid() and bool(salient_attention_getter.call())
	var target_gain := float(_wind_config.get("busy_multiplier", 0.18)) if salient_busy else 1.0
	var response_seconds := maxf(0.01, float(_wind_config.get("attention_response_seconds", 0.4)))
	_wind_attention_gain = lerpf(_wind_attention_gain, target_gain, 1.0 - exp(-step / response_seconds))
	var duration := maxf(0.1, float(_wind_config.get("duration_seconds", 7.0)))
	if _gust_started_at >= 0.0 and elapsed >= _gust_started_at + duration:
		_next_gust_at = elapsed + _wind_rng.randf_range(
			float(_wind_config.get("interval_min_seconds", 22.0)),
			float(_wind_config.get("interval_max_seconds", 34.0))
		)
		_gust_started_at = -1.0
	if _gust_started_at < 0.0 and elapsed >= _next_gust_at:
		if salient_busy:
			# Delay the opportunity; a foreground interaction never starts a gust.
			_next_gust_at = elapsed + 1.0
		else:
			_gust_started_at = elapsed
			_gust_direction = 1.0 if _wind_rng.randf() >= 0.5 else -1.0
	var age := elapsed - _gust_started_at if _gust_started_at >= 0.0 else -1.0
	var observed_wind := float(presenter.get_current_environment().wind_strength)
	var gain := observed_wind * _wind_attention_gain * _gust_direction
	_gust_bamboo_sway = _gust_wave(age, duration) * float(_wind_config.get("bamboo_sway_pixels", 19.0)) * gain
	var tassel_delay := maxf(0.0, float(_wind_config.get("tassel_delay_seconds", 0.65)))
	_gust_tassel_sway = _gust_wave(age - tassel_delay, maxf(0.1, duration - tassel_delay)) * float(_wind_config.get("tassel_source_pixels", 12.0)) * gain
	_steam_wind_strength = get_current_wind_strength()
	_steam_wind_direction = _gust_direction


func _gust_envelope(age: float, duration: float) -> float:
	if age <= 0.0 or age >= duration:
		return 0.0
	return pow(sin(PI * age / duration), 2.0)


func get_current_wind_strength() -> float:
	if presenter == null:
		return 0.0
	var environment := presenter.get_current_environment()
	var weather_wind := clampf(float(environment.wind_strength), 0.0, 1.0)
	var calm_multiplier := clampf(float(_wind_config.get("calm_multiplier", 0.22)), 0.0, 1.0)
	var gust := 0.0
	if get_gust_active():
		var duration := maxf(0.1, float(_wind_config.get("duration_seconds", 7.0)))
		gust = _gust_envelope(elapsed - _gust_started_at, duration) * _wind_attention_gain
	return clampf(weather_wind * (calm_multiplier + (1.0 - calm_multiplier) * gust), 0.0, 1.0)


func get_gust_active() -> bool:
	if _gust_started_at < 0.0:
		return false
	return elapsed < _gust_started_at + maxf(0.1, float(_wind_config.get("duration_seconds", 7.0)))


func _set_window_light_target(smooth: bool, duration: float) -> void:
	var strengths: Dictionary = _window_light_config.get("profile_strength", {})
	var weather_multipliers: Dictionary = _window_light_config.get("weather_multiplier", {})
	var target := clampf(
		float(strengths.get(presenter.time_profile_id, 0.0))
		* float(weather_multipliers.get(presenter.weather_id, 1.0)),
		0.0,
		1.0
	)
	_window_light_from = _window_light_strength
	_window_light_target = target
	_window_light_elapsed = 0.0
	_window_light_duration = maxf(duration, 0.0)
	if not smooth or _window_light_duration <= 0.0:
		_window_light_strength = target
		_window_light_elapsed = _window_light_duration


func _advance_window_light(step: float) -> void:
	if _window_light_elapsed >= _window_light_duration:
		return
	_window_light_elapsed = minf(_window_light_duration, _window_light_elapsed + step)
	var weight := smoothstep(0.0, 1.0, _window_light_elapsed / maxf(_window_light_duration, 0.001))
	_window_light_strength = lerpf(_window_light_from, _window_light_target, weight)


func _advance_wetness(step: float) -> void:
	var rain_amount := clampf(float(presenter.get_current_environment().rain_amount), 0.0, 1.0)
	var wet_seconds := maxf(0.1, float(_wetness_config.get("rain_fill_seconds", 4.0)))
	var dry_seconds := maxf(0.1, float(_wetness_config.get("dry_seconds", 35.0)))
	var target := 1.0 if rain_amount > 0.01 else 0.0
	var duration := wet_seconds if target > 0.5 else dry_seconds
	_wetness = move_toward(_wetness, target, step / duration)


func _set_lamp_profile(profile_id: String, smooth: bool) -> void:
	if _lamp_profile_id == profile_id and smooth:
		return
	_lamp_profile_id = profile_id
	var strengths: Dictionary = _lamp_config.get("profile_strength", {})
	_lamp_from = _lamp_strength
	_lamp_target = clampf(float(strengths.get(profile_id, 0.0)), 0.0, 1.0)
	_lamp_blend_elapsed = 0.0
	if not smooth:
		_lamp_strength = _lamp_target
		_lamp_blend_elapsed = float(_lamp_config.get("transition_seconds", 1.6))


func _advance_lantern(step: float) -> void:
	_set_lamp_profile(presenter.time_profile_id, true)
	var duration := maxf(0.01, float(_lamp_config.get("transition_seconds", 1.6)))
	_lamp_blend_elapsed = minf(duration, _lamp_blend_elapsed + step)
	var weight := smoothstep(0.0, 1.0, _lamp_blend_elapsed / duration)
	_lamp_strength = lerpf(_lamp_from, _lamp_target, weight)
	if enabled and not motion_paused:
		var pulse := sin(elapsed * float(_lamp_config.get("flicker_slow_frequency", 0.63))) * float(_lamp_config.get("flicker_slow_amplitude", 0.025))
		pulse += sin(elapsed * float(_lamp_config.get("flicker_fast_frequency", 1.47)) + 0.9) * float(_lamp_config.get("flicker_fast_amplitude", 0.01))
		_lamp_flicker = 1.0 + pulse * _wind_attention_gain


func get_lantern_tint(point: Vector2) -> Color:
	var center: Array = _lamp_config.get("spill_center", [1368, 428])
	var radius: Array = _lamp_config.get("spill_radius", [235, 108])
	var distance := ((point - Vector2(center[0], center[1])) / Vector2(maxf(0.001, radius[0]), maxf(0.001, radius[1]))).length()
	var mask := 1.0 - smoothstep(0.15, 1.0, distance)
	var weight := clampf(_lamp_strength * _lamp_flicker * mask * float(_lamp_config.get("cat_warmth", 0.65)), 0.0, 1.0)
	return Color.WHITE.lerp(Color(1.12, 1.02, 0.77, 1.0), weight)


func _apply() -> void:
	if presenter == null:
		return
	var values := presenter.get_current_environment()
	var weather_time := elapsed
	var brightness := float(values.brightness)
	var world_tint: Color = values.world_tint
	var sky_tint: Color = values.sky_tint
	var weather_cloud := float(values.cloud_shadow_strength)
	var weather_rain := float(values.rain_amount)
	var weather_wind := float(values.wind_strength)

	for item in lit:
		var material: ShaderMaterial = item.weather
		var weather_scale := 0.0 if bool(item.sheltered) else 1.0
		material.set_shader_parameter("lamp_strength", _lamp_strength * _lamp_flicker)
		material.set_shader_parameter("weather_time", weather_time)
		material.set_shader_parameter("brightness", brightness)
		material.set_shader_parameter("world_tint", world_tint)
		material.set_shader_parameter("sky_tint", sky_tint)
		material.set_shader_parameter("sky_strength", float(values.sky_strength))
		material.set_shader_parameter("far_contrast", float(values.far_contrast))
		material.set_shader_parameter("cloud_strength", weather_cloud * weather_scale)
		material.set_shader_parameter("rain_strength", weather_rain * weather_scale)
		material.set_shader_parameter("tassel_sway_px", _gust_tassel_sway if not bool(item.sheltered) else 0.0)
		if item.art == backdrop_art:
			var light_rect: Array = _window_light_config.get("patch_rect", [270, 315, 970, 360])
			var light_center: Array = _window_light_config.get("center", [620, 337])
			var light_radius: Array = _window_light_config.get("radius", [350, 20])
			material.set_shader_parameter("daylight_strength", _window_light_strength)
			material.set_shader_parameter("daylight_rect", Vector4(light_rect[0], light_rect[1], light_rect[2], light_rect[3]))
			material.set_shader_parameter("daylight_center", Vector2(light_center[0], light_center[1]))
			material.set_shader_parameter("daylight_radius", Vector2(light_radius[0], light_radius[1]))
			material.set_shader_parameter("daylight_color", Color(str(_window_light_config.get("warm_color", "#fff0ce"))))
			material.set_shader_parameter("wetness", _wetness)

	var environment_modulate := Color(
		world_tint.r * brightness,
		world_tint.g * brightness,
		world_tint.b * brightness,
		1.0
	)
	bamboo.modulate = environment_modulate
	bamboo_shadow.modulate = environment_modulate
	for material: ShaderMaterial in [bamboo_material, shadow_material]:
		material.set_shader_parameter("weather_time", weather_time)
		material.set_shader_parameter("wind_strength", weather_wind * float(_wind_config.get("calm_multiplier", 0.22)))
		material.set_shader_parameter("gust_sway_px", _gust_bamboo_sway)
		material.set_shader_parameter("cloud_strength", weather_cloud)
		material.set_shader_parameter("rain_strength", weather_rain)
	bamboo_shadow.visible = weather_cloud > 0.001

	var mist_multiplier := float(values.mist_multiplier)
	var residual_humidity := _wetness * (1.0 - weather_rain)
	var total_mist_density := clampf(
		mist_multiplier * 0.075 + residual_humidity * float(_wetness_config.get("residual_mist_density", 0.055)),
		0.0,
		0.36
	)
	var mist_tint := Color("#d8e2e2").lerp(world_tint, 0.30).lerp(sky_tint, clampf(float(values.sky_strength), 0.0, 1.0) * 0.28)
	for i in range(mist_layers.size()):
		var mist := mist_layers[i]
		var material: ShaderMaterial = mist.material
		var layer: Dictionary = _mist_layer_config[i] if i < _mist_layer_config.size() else {}
		var layer_factor := float(layer.get("density_weight", 0.5))
		var density := clampf(total_mist_density * layer_factor, 0.0, 0.32)
		mist.visible = density > 0.001
		material.set_shader_parameter("weather_time", weather_time)
		material.set_shader_parameter("density", density)
		material.set_shader_parameter("mist_tint", mist_tint)

	for rain in rain_nodes:
		var running := weather_rain > 0.01
		rain.visible = running
		rain.process_mode = Node.PROCESS_MODE_INHERIT if running else Node.PROCESS_MODE_DISABLED
		rain.material.set_shader_parameter("weather_time", weather_time)
		rain.material.set_shader_parameter("rain_strength", weather_rain)
	_apply_eave_drips()
	if _steam_material != null:
		var day_alpha := float(_steam_config.get("day_alpha", 0.15))
		var accent_alpha := float(_steam_config.get("accent_alpha", 0.24))
		var dusk_gain := smoothstep(0.0, 1.0, _lamp_strength)
		var accent_gain := maxf(dusk_gain, clampf(weather_rain, 0.0, 1.0))
		_steam_material.set_shader_parameter("elapsed", elapsed)
		_steam_material.set_shader_parameter("wind_strength", _steam_wind_strength)
		_steam_material.set_shader_parameter("wind_direction", _steam_wind_direction)
		_steam_material.set_shader_parameter("attention_gain", _wind_attention_gain)
		_steam_material.set_shader_parameter("opacity", lerpf(day_alpha, accent_alpha, accent_gain))
		_steam_material.set_shader_parameter("gust_active", get_gust_active())
	if _incense_smoke_material != null:
		_incense_smoke_material.set_shader_parameter("elapsed", elapsed)
		_incense_smoke_material.set_shader_parameter("wind_strength", _steam_wind_strength)
		_incense_smoke_material.set_shader_parameter("wind_direction", _steam_wind_direction)
		_incense_smoke_material.set_shader_parameter("attention_gain", _wind_attention_gain)
		_incense_smoke_material.set_shader_parameter("opacity", float(_incense_smoke_config.get("opacity", 0.30)))


func set_dynamic(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	_apply()
	changed.emit()


func toggle() -> void:
	set_dynamic(not enabled)


func next_phase() -> void:
	if presenter == null:
		return
	var current_index := WEATHER_IDS.find(presenter.weather_id)
	var next_index := (current_index + 1) % WEATHER_IDS.size()
	set_weather(WEATHER_IDS[next_index])


func set_time_index(index: int, smooth: bool = true) -> bool:
	if presenter == null or index < 0 or index >= _time_index_mapping.size():
		return false
	var profile_id := str(_time_index_mapping[index])
	if not presenter.set_time_profile(profile_id, smooth):
		return false
	_set_lamp_profile(profile_id, smooth)
	var transition: Dictionary = config.get("transition", {})
	_set_window_light_target(smooth, float(transition.get("time_seconds", 1.6)))
	_apply()
	return true


func set_weather(id: String, smooth: bool = true) -> bool:
	if presenter == null or not presenter.set_weather(id, smooth):
		return false
	var transition: Dictionary = config.get("transition", {})
	_set_window_light_target(smooth, float(transition.get("weather_seconds", 4.5)))
	var new_phase := _weather_label(id)
	if phase != new_phase:
		phase = new_phase
		changed.emit()
	_apply()
	return true


func reset_environment(time_index: int = 0) -> void:
	if presenter == null:
		return
	enabled = true
	motion_paused = false
	elapsed = 0.0
	_reset_wind_moments()
	_reset_eave_drips()
	_wetness = 0.0
	var profile_id := str(_time_index_mapping[time_index]) if time_index >= 0 and time_index < _time_index_mapping.size() else "mao"
	_set_lamp_profile(profile_id, false)
	_lamp_flicker = 1.0
	if ambient_audio != null:
		ambient_audio.reset()
	presenter.set_time_profile(profile_id, false)
	presenter.set_weather("cloudy", false)
	presenter.finish_transition()
	_set_window_light_target(false, 0.0)
	_steam_wind_strength = get_current_wind_strength()
	phase = _weather_label(presenter.weather_id)
	_apply()
	changed.emit()


func _weather_label(id: String) -> String:
	return str(WEATHER_LABELS.get(id, "多云"))
