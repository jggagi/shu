extends Node
class_name CourtyardEnvironment

const Presenter = preload("res://scripts/environment_presenter.gd")
var presenter = Presenter.new()
var elapsed := 0.0
var gust := 0.0
var _config: Dictionary
var _art_material: ShaderMaterial
var _rain_material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _next_gust := 5.0
var _gust_age := -1.0
var _gust_gain := 1.0

func configure(art: TextureRect, world: Node2D) -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/courtyard_environment.json"))
	presenter.configure(_config)
	_art_material = ShaderMaterial.new()
	_art_material.shader = preload("res://assets/shaders/courtyard_art.gdshader")
	_art_material.set_shader_parameter("foliage_mask", preload("res://assets/art/courtyard/foliage-mask.svg"))
	_art_material.set_shader_parameter("distance_mask", preload("res://assets/art/courtyard/distance-mask.svg"))
	_art_material.set_shader_parameter("sway_pixels", float(_config.wind.sway_pixels))
	art.material = _art_material
	var rain := ColorRect.new()
	rain.name = "ExposedCourtyardRain"
	rain.size = Vector2(1280, 720)
	rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = preload("res://assets/shaders/courtyard_rain.gdshader")
	_rain_material.set_shader_parameter("exposed_mask", preload("res://assets/art/courtyard/exposed-rain-mask.svg"))
	_rain_material.set_shader_parameter("opacity", float(_config.rain.opacity))
	rain.material = _rain_material
	world.add_child(rain)
	reset()

func reset() -> void:
	presenter.configure(_config)
	elapsed = 0.0
	gust = 0.0
	_gust_age = -1.0
	_next_gust = float(_config.wind.first_delay)
	_rng.seed = int(_config.wind.seed)
	_apply()

func observe(time_index: int, weather_id: String, smooth := true) -> void:
	presenter.set_time_profile(str(_config.time_index_mapping[clampi(time_index, 0, 5)]), smooth)
	presenter.set_weather(weather_id, smooth)

func advance(delta: float, dynamic_enabled: bool) -> void:
	# Explicit preview transitions still progress in Static; motion clocks do not.
	presenter.advance(delta)
	if dynamic_enabled:
		elapsed += delta
		if _gust_age < 0.0 and elapsed >= _next_gust:
			_gust_age = 0.0
			_gust_gain = _rng.randf_range(0.72, 1.0)
		if _gust_age >= 0.0:
			_gust_age += delta
			var duration := float(_config.wind.duration)
			if _gust_age >= duration:
				_gust_age = -1.0
				_next_gust = elapsed + _rng.randf_range(float(_config.wind.gap_min), float(_config.wind.gap_max))
				gust = 0.0
			else:
				var envelope := pow(sin(PI * _gust_age / duration), 1.5)
				gust = envelope * _gust_gain * float(presenter.get_current_environment().wind_strength)
	_apply()

func snapshot() -> Dictionary:
	var result: Dictionary = presenter.get_current_environment()
	result.merge({"time_profile_id": presenter.time_profile_id, "weather_id": presenter.weather_id, "night_preview": false, "elapsed": elapsed, "gust": gust})
	return result

func _apply() -> void:
	var e: Dictionary = presenter.get_current_environment()
	for key in ["brightness", "world_tint", "sky_tint", "sky_strength", "far_contrast"]:
		_art_material.set_shader_parameter(key, e[key])
	_art_material.set_shader_parameter("mist_strength", float(e.mist_multiplier))
	_art_material.set_shader_parameter("elapsed", elapsed)
	_art_material.set_shader_parameter("gust", gust)
	_rain_material.set_shader_parameter("elapsed", elapsed)
	_rain_material.set_shader_parameter("rain_amount", float(e.rain_amount))
