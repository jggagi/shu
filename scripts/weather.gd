extends Node

signal changed
const Cycle = preload("res://scripts/weather_cycle.gd")
const AMBIENT = preload("res://assets/shaders/ambient.gdshader")
const WIND = preload("res://assets/shaders/bamboo_wind.gdshader")
const MIST = preload("res://assets/shaders/mist.gdshader")
const RAIN = preload("res://assets/shaders/rain.gdshader")

var enabled := true
var elapsed := 0.0
var phase := "薄云过境"
var motion_paused := false # Render audit only; normal weather follows presentation time.
var config: Dictionary
var scene_root: Control
var art_root: Control
var lit: Array[Dictionary] = []
var mist_layers: Array[TextureRect] = []
var rain_nodes: Array[TextureRect] = []
var bamboo: TextureRect
var bamboo_shadow: TextureRect
var bamboo_material: ShaderMaterial
var shadow_material: ShaderMaterial
var noise: NoiseTexture2D
var update_accumulator := 0.0

func setup(scene: Control, backdrop: TextureRect) -> void:
	scene_root = scene
	art_root = backdrop.get_parent()
	config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/weather.json"))
	noise = NoiseTexture2D.new()
	noise.width = 128
	noise.height = 128
	noise.seamless = true
	var generator := FastNoiseLite.new()
	generator.seed = 4712
	generator.frequency = 0.025
	noise.noise = generator
	add_lit_art(backdrop)
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
	_make_rain(Rect2(269,20,706,360), float(config.rain_main) / 2.0, 270.0, 180.0)
	_make_rain(Rect2(1058,20,82,340), float(config.rain_side) / 2.0, 240.0, 170.0)
	_make_rain(Rect2(549,45,346,185), float(config.eave_drops), 150.0, 185.0)
	var rect: Array = config.bamboo_rect
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
	var material := ShaderMaterial.new()
	material.shader = AMBIENT
	material.set_shader_parameter("cloud_noise", noise)
	material.set_shader_parameter("layer_origin", art.position)
	lit.append({"art": art, "original": art.material, "weather": material})
	art.material = material if enabled else art.material

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
	if not motion_paused:
		elapsed += delta
	update_accumulator += delta
	if update_accumulator < 1.0 / float(config.shader_update_hz):
		return
	update_accumulator = 0.0
	_apply()

func _apply() -> void:
	var values := Cycle.sample(elapsed, float(config.cycle_seconds)) if enabled else {"cloud":0.0, "wind":0.0, "rain":0.0, "phase":"静态画面"}
	var clock := elapsed if enabled else 0.0
	var new_phase: String = values.phase
	if phase != new_phase:
		phase = new_phase
		changed.emit()
	for item in lit:
		var material: ShaderMaterial = item.weather
		material.set_shader_parameter("weather_time", clock)
		material.set_shader_parameter("cloud_strength", values.cloud)
		material.set_shader_parameter("rain_strength", values.rain)
	for material: ShaderMaterial in [bamboo_material, shadow_material]:
		material.set_shader_parameter("weather_time", clock)
		material.set_shader_parameter("wind_strength", values.wind)
		material.set_shader_parameter("cloud_strength", values.cloud)
		material.set_shader_parameter("rain_strength", values.rain)
	bamboo_shadow.visible = enabled and float(values.cloud) > 0.01
	for i in range(mist_layers.size()):
		var mist := mist_layers[i]
		mist.visible = enabled and float(values.cloud) > 0.01
		mist.material.set_shader_parameter("weather_time", clock)
		mist.material.set_shader_parameter("density", float(config.mist_max_alpha) * (0.7 if i == 0 else 0.4) * float(values.cloud))
	for rain in rain_nodes:
		var running := enabled and float(values.rain) > 0.01
		rain.visible = running
		rain.process_mode = Node.PROCESS_MODE_INHERIT if running else Node.PROCESS_MODE_DISABLED
		rain.material.set_shader_parameter("weather_time", clock)
		rain.material.set_shader_parameter("rain_strength", values.rain)

func set_dynamic(value: bool) -> void:
	enabled = value
	for item in lit:
		item.art.material = item.weather if enabled else item.original
	bamboo.material = bamboo_material if enabled else null
	set_process(enabled)
	_apply()
	changed.emit()

func toggle() -> void:
	set_dynamic(not enabled)

func next_phase() -> void:
	var t := fposmod(elapsed, float(config.cycle_seconds)) * 30.0 / float(config.cycle_seconds)
	var target := 10.0 if t < 7.0 else (19.0 if t < 14.0 else (27.0 if t < 25.0 else 2.0))
	elapsed = target * float(config.cycle_seconds) / 30.0
	if not enabled:
		set_dynamic(true)
	_apply()

func seek(seconds: float) -> void:
	elapsed = seconds
	_apply()
