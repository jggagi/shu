extends Node

signal changed

const EnvironmentPresenterScript = preload("res://scripts/environment_presenter.gd")
const AMBIENT = preload("res://assets/shaders/ambient.gdshader")
const WIND = preload("res://assets/shaders/bamboo_wind.gdshader")
const MIST = preload("res://assets/shaders/mist.gdshader")
const RAIN = preload("res://assets/shaders/rain.gdshader")
const WEATHER_IDS := ["clear", "cloudy", "light_rain"]
const WEATHER_LABELS := {
	"clear": "晴",
	"cloudy": "多云",
	"light_rain": "小雨",
}
const MIST_LAYER_FACTORS := [0.62, 0.38]

var enabled := true
var elapsed := 0.0
var phase := "多云"
var motion_paused := false # Render audit only; presentation transitions continue.
var config: Dictionary = {}
var geometry_config: Dictionary = {}
var scene_root: Control
var art_root: Control
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


func setup(scene: Control, backdrop: TextureRect) -> void:
	scene_root = scene
	art_root = backdrop.get_parent()
	config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/tingyu_environment.json"))
	geometry_config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/weather.json"))
	_time_index_mapping = config.get("time_index_mapping", [])
	presenter = EnvironmentPresenterScript.new()
	presenter.configure(config)
	phase = _weather_label(presenter.weather_id)

	noise = NoiseTexture2D.new()
	noise.width = 128
	noise.height = 128
	noise.seamless = true
	var generator := FastNoiseLite.new()
	generator.seed = 4712
	generator.frequency = 0.025
	noise.noise = generator

	_register_lit_art(backdrop, false)
	for i in range(2):
		var mist := TextureRect.new()
		mist.position = Vector2(265, 23)
		mist.size = Vector2(875, 343)
		mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mist.texture = noise
		mist.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var material := ShaderMaterial.new()
		material.shader = MIST
		material.set_shader_parameter("mist_noise", noise)
		material.set_shader_parameter("drift_speed", 0.011 if i == 0 else -0.007)
		material.set_shader_parameter("phase_offset", float(i) * 0.43)
		mist.material = material
		art_root.add_child(mist)
		mist_layers.append(mist)

	_make_rain(Rect2(269, 20, 706, 360), float(geometry_config.rain_main) / 2.0, 270.0, 180.0)
	_make_rain(Rect2(1058, 20, 82, 340), float(geometry_config.rain_side) / 2.0, 240.0, 170.0)
	_make_rain(Rect2(549, 45, 346, 185), float(geometry_config.eave_drops), 150.0, 185.0)
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
	lit.append({"art": art, "original": art.material, "weather": material, "sheltered": sheltered})
	art.material = material


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


func _process(delta: float) -> void:
	advance_environment(delta, false)


func advance_environment(delta: float, apply_immediately: bool = true) -> void:
	if presenter == null:
		return
	var step := maxf(delta, 0.0)
	if enabled and not motion_paused:
		elapsed += step
	presenter.advance(step)
	update_accumulator += step
	var update_hz := maxf(float(geometry_config.get("shader_update_hz", 30.0)), 1.0)
	var update_interval := 1.0 / update_hz
	if apply_immediately:
		update_accumulator = 0.0
		_apply()
	elif update_accumulator >= update_interval:
		update_accumulator = fposmod(update_accumulator, update_interval)
		_apply()


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
		material.set_shader_parameter("weather_time", weather_time)
		material.set_shader_parameter("brightness", brightness)
		material.set_shader_parameter("world_tint", world_tint)
		material.set_shader_parameter("sky_tint", sky_tint)
		material.set_shader_parameter("sky_strength", float(values.sky_strength))
		material.set_shader_parameter("far_contrast", float(values.far_contrast))
		material.set_shader_parameter("cloud_strength", weather_cloud * weather_scale)
		material.set_shader_parameter("rain_strength", weather_rain * weather_scale)

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
		material.set_shader_parameter("wind_strength", weather_wind)
		material.set_shader_parameter("cloud_strength", weather_cloud)
		material.set_shader_parameter("rain_strength", weather_rain)
	bamboo_shadow.visible = weather_cloud > 0.001

	var mist_multiplier := float(values.mist_multiplier)
	var total_mist_density := clampf(mist_multiplier * 0.08, 0.0, 0.32)
	var mist_tint := Color("#d8e2e2").lerp(world_tint, 0.30).lerp(sky_tint, clampf(float(values.sky_strength), 0.0, 1.0) * 0.28)
	for i in range(mist_layers.size()):
		var mist := mist_layers[i]
		var material: ShaderMaterial = mist.material
		var layer_factor := float(MIST_LAYER_FACTORS[i])
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
	_apply()
	return true


func set_weather(id: String, smooth: bool = true) -> bool:
	if presenter == null or not presenter.set_weather(id, smooth):
		return false
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
	var profile_id := str(_time_index_mapping[time_index]) if time_index >= 0 and time_index < _time_index_mapping.size() else "mao"
	presenter.set_time_profile(profile_id, false)
	presenter.set_weather("cloudy", false)
	presenter.finish_transition()
	phase = _weather_label(presenter.weather_id)
	_apply()
	changed.emit()


func _weather_label(id: String) -> String:
	return str(WEATHER_LABELS.get(id, "多云"))
