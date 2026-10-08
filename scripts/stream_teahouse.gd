extends Control

const EnvironmentModel = preload("res://scripts/environment_presenter.gd")
const CatAdapter = preload("res://scripts/stream_teahouse_cat.gd")
const TIMES := ["mao", "chen", "si", "wu", "shen", "you"]
const TIME_NAMES := ["卯 · 清晨", "辰 · 晨光", "巳 · 日高", "午 · 正午", "申 · 斜阳", "酉 · 暮色"]
const WEATHER_NAMES := {"clear": "晴", "cloudy": "多云", "light_rain": "小雨"}

var presenter = EnvironmentModel.new()
var cat: Node
var config: Dictionary
var time_index := 0
var weather_id := "cloudy"
var dynamic_enabled := true
var presentation_time := 0.0
var qa_motion_paused := false
var world: Node2D
var bank_path: Path2D
var cat_home: Marker2D
var water: Polygon2D
var waterfall: Polygon2D
var waterfall_mist: ColorRect
var waterfall_material: ShaderMaterial
var waterfall_mist_material: ShaderMaterial
var atmosphere: Polygon2D
var grade_material: ShaderMaterial
var water_material: ShaderMaterial
var atmosphere_material: ShaderMaterial
var dynamic_button: Button
var reset_button: Button
var time_buttons: Array[Button] = []
var weather_buttons: Dictionary = {}
var status_label: Label
var hint_label: Label
var feedback_remaining := 0.0
var art_frame: Control

func _ready() -> void:
	get_window().title = "溪边茶亭 · 独立试玩 v1.3"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var game_theme := Theme.new()
	game_theme.default_font = load("res://assets/fonts/ShuStreamTeahouseSerif.ttf")
	game_theme.default_font_size = 20
	theme = game_theme
	config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/stream_teahouse.json"))
	presenter.configure(config.environment)
	presenter.set_time_profile(TIMES[time_index], false)
	presenter.set_weather(weather_id, false)
	_build_scene()
	_build_controls()
	cat = CatAdapter.new()
	add_child(cat)
	cat.setup(world, bank_path, cat_home, float(config.cat.scale))
	cat.cat_petted.connect(_on_cat_petted)
	resized.connect(_layout)
	_layout()
	_apply_environment()
	_refresh_controls()

func _build_scene() -> void:
	var paper := ColorRect.new()
	paper.color = Color("e9e1d1")
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(paper)
	art_frame = Control.new()
	art_frame.name = "ArtFrame"
	art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.clip_contents = true
	add_child(art_frame)
	world = Node2D.new()
	world.name = "PaintedWorld"
	art_frame.add_child(world)
	var painting := Sprite2D.new()
	painting.name = "OriginalPainting"
	painting.centered = false
	painting.texture = load("res://assets/art/stream_teahouse/stream-teahouse-v1.png")
	painting.scale = Vector2(1280, 720) / painting.texture.get_size()
	grade_material = ShaderMaterial.new()
	grade_material.shader = load("res://assets/shaders/stream_grade.gdshader")
	painting.material = grade_material
	world.add_child(painting)
	# Trace the original two-tier distant waterfall; keep the painted mountain fixed.
	waterfall = _polygon("DistantWaterfall", config.waterfall.polygon)
	waterfall_material = ShaderMaterial.new()
	waterfall_material.shader = load("res://assets/shaders/stream_waterfall.gdshader")
	waterfall_material.set_shader_parameter("painting", painting.texture)
	waterfall_material.set_shader_parameter("flow_origin", Vector2(config.waterfall.flow_origin[0], config.waterfall.flow_origin[1]))
	waterfall_material.set_shader_parameter("flow_size", Vector2(config.waterfall.flow_size[0], config.waterfall.flow_size[1]))
	waterfall_material.set_shader_parameter("flow_strength", config.waterfall.flow_strength)
	waterfall.material = waterfall_material
	waterfall_mist = ColorRect.new()
	waterfall_mist.name = "WaterfallFootMist"
	waterfall_mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mist_rect: Array = config.waterfall.mist_rect
	waterfall_mist.position = Vector2(mist_rect[0], mist_rect[1])
	waterfall_mist.size = Vector2(mist_rect[2], mist_rect[3])
	waterfall_mist_material = ShaderMaterial.new()
	waterfall_mist_material.shader = load("res://assets/shaders/stream_waterfall_mist.gdshader")
	waterfall_mist_material.set_shader_parameter("opacity", config.waterfall.mist_opacity)
	waterfall_mist.material = waterfall_mist_material
	world.add_child(waterfall_mist)
	water = _polygon("WaterSurface", config.water_polygon)
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://assets/shaders/stream_water.gdshader")
	water.material = water_material
	water_material.set_shader_parameter("painting", painting.texture)
	water_material.set_shader_parameter("river_polygon", water.polygon)
	water_material.set_shader_parameter("river_point_count", water.polygon.size())
	var flow_centers := PackedVector2Array()
	for point in config.river_flow.centers:
		flow_centers.append(Vector2(point[0], point[1]))
	water_material.set_shader_parameter("flow_centers", flow_centers)
	water_material.set_shader_parameter("flow_strength", config.river_flow.strength)
	water_material.set_shader_parameter("bank_feather", config.river_flow.bank_feather)
	atmosphere = _polygon("OpenAir", config.open_air_polygon)
	atmosphere_material = ShaderMaterial.new()
	atmosphere_material.shader = load("res://assets/shaders/stream_atmosphere.gdshader")
	atmosphere.material = atmosphere_material
	atmosphere_material.set_shader_parameter("air_polygon", atmosphere.polygon)
	atmosphere_material.set_shader_parameter("air_point_count", atmosphere.polygon.size())
	atmosphere_material.set_shader_parameter("edge_feather", 40.0)
	bank_path = Path2D.new()
	bank_path.name = "CatWalk_StoneBank"
	bank_path.curve = Curve2D.new()
	for point in config.cat.path:
		bank_path.curve.add_point(Vector2(point[0], point[1]))
	world.add_child(bank_path)
	cat_home = Marker2D.new()
	cat_home.name = "CatSpot_ExposedStone"
	cat_home.position = Vector2(config.cat.path[0][0], config.cat.path[0][1])
	cat_home.set_meta("sheltered", false)
	world.add_child(cat_home)

func _polygon(node_name: String, points: Array) -> Polygon2D:
	var node := Polygon2D.new()
	node.name = node_name
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	for point in points:
		var vertex := Vector2(point[0], point[1])
		vertices.append(vertex)
		uvs.append(vertex / Vector2(1280, 720))
	node.polygon = vertices
	node.uv = uvs
	world.add_child(node)
	return node

func _build_controls() -> void:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.position = Vector2(28, 12)
	header.add_theme_constant_override("separation", 20)
	add_child(header)
	var title := Label.new()
	title.text = "溪边茶亭"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("384a42"))
	header.add_child(title)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("71634e"))
	header.add_child(status_label)
	var panel := VBoxContainer.new()
	panel.name = "Controls"
	panel.position = Vector2(28, 0)
	panel.add_theme_constant_override("separation", 7)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	panel.add_child(row)
	for index in 6:
		var button := _button(TIME_NAMES[index], row)
		button.pressed.connect(set_time_index.bind(index))
		time_buttons.append(button)
	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 12)
	panel.add_child(weather_row)
	for id in ["clear", "cloudy", "light_rain"]:
		var button := _button(WEATHER_NAMES[id], weather_row)
		button.custom_minimum_size.x = 82
		button.pressed.connect(set_weather.bind(id))
		weather_buttons[id] = button
	dynamic_button = _button("Static · 静止", weather_row)
	dynamic_button.custom_minimum_size.x = 150
	dynamic_button.pressed.connect(_toggle_dynamic)
	reset_button = _button("Reset · 重置", weather_row)
	reset_button.custom_minimum_size.x = 148
	reset_button.pressed.connect(reset_scene)
	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", 17)
	hint_label.add_theme_color_override("font_color", Color("756b5b"))
	panel.add_child(hint_label)

func _button(text_value: String, parent: Node) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(135, 34)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("f4eedf") if state == "normal" else Color("dcd8c1")
		style.border_color = Color("aa9774")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("3b4b40"))
	button.add_theme_color_override("font_disabled_color", Color("756344"))
	button.add_theme_color_override("font_hover_color", Color("3b4b40"))
	button.add_theme_color_override("font_pressed_color", Color("3b4b40"))
	parent.add_child(button)
	return button

func _layout() -> void:
	if art_frame == null:
		return
	var canvas := size
	var scale_value := minf((canvas.x - 40) / 1280.0, (canvas.y - 220) / 720.0)
	scale_value = maxf(0.1, scale_value)
	art_frame.size = Vector2(1280, 720) * scale_value
	art_frame.position = Vector2((canvas.x - art_frame.size.x) / 2, 64)
	world.scale = Vector2.ONE * scale_value
	get_node("Controls").position = Vector2(28, 76 + art_frame.size.y)

func _process(delta: float) -> void:
	if not qa_motion_paused:
		advance_presentation(delta)

func advance_presentation(delta: float) -> void:
	presenter.advance(delta) # Explicit profile changes still blend in Static.
	if dynamic_enabled:
		presentation_time += maxf(delta, 0.0)
		feedback_remaining = maxf(0, feedback_remaining - delta)
	_apply_environment()
	cat.advance(delta)
	_refresh_controls()

func _apply_environment() -> void:
	var values: Dictionary = presenter.get_current_environment()
	grade_material.set_shader_parameter("brightness", values.brightness)
	grade_material.set_shader_parameter("world_tint", values.world_tint)
	grade_material.set_shader_parameter("sky_tint", values.sky_tint)
	grade_material.set_shader_parameter("sky_strength", values.sky_strength)
	for material in [waterfall_material, waterfall_mist_material]:
		material.set_shader_parameter("elapsed", presentation_time)
		material.set_shader_parameter("brightness", values.brightness)
		material.set_shader_parameter("world_tint", values.world_tint)
	water_material.set_shader_parameter("elapsed", presentation_time)
	water_material.set_shader_parameter("rain_amount", values.rain_amount)
	water_material.set_shader_parameter("brightness", values.brightness)
	water_material.set_shader_parameter("world_tint", values.world_tint)
	atmosphere_material.set_shader_parameter("elapsed", presentation_time)
	atmosphere_material.set_shader_parameter("rain_amount", values.rain_amount)
	atmosphere_material.set_shader_parameter("mist_amount", values.mist_multiplier)
	atmosphere_material.set_shader_parameter("brightness", values.brightness)
	atmosphere_material.set_shader_parameter("world_tint", values.world_tint)
	atmosphere_material.set_shader_parameter("sky_tint", values.sky_tint)
	atmosphere_material.set_shader_parameter("sky_strength", values.sky_strength)
	if cat != null:
		cat.observe({"dynamic_enabled": dynamic_enabled, "weather_id": weather_id,
			"time_profile_id": TIMES[time_index], "busy": false,
			"brightness": values.brightness, "world_tint": values.world_tint})

func set_time_index(index: int, smooth: bool = true) -> void:
	time_index = clampi(index, 0, 5)
	presenter.set_time_profile(TIMES[time_index], smooth)
	_apply_environment()
	_refresh_controls()

func set_weather(id: String, smooth: bool = true) -> void:
	if not WEATHER_NAMES.has(id):
		return
	weather_id = id
	presenter.set_weather(id, smooth)
	_apply_environment()
	_refresh_controls()

func set_dynamic(enabled: bool) -> void:
	dynamic_enabled = enabled
	_apply_environment()
	_refresh_controls()

func _toggle_dynamic() -> void:
	set_dynamic(not dynamic_enabled)

func reset_scene() -> void:
	time_index = 0
	weather_id = "cloudy"
	dynamic_enabled = true
	presentation_time = 0
	feedback_remaining = 0
	presenter.configure(config.environment)
	presenter.set_time_profile(TIMES[0], false)
	presenter.set_weather(weather_id, false)
	cat.reset()
	_apply_environment()
	_refresh_controls()

func _on_cat_petted() -> void:
	feedback_remaining = 2.4
	_refresh_controls()

func _refresh_controls() -> void:
	if status_label == null:
		return
	status_label.text = "%s  /  %s  /  %s" % [TIME_NAMES[time_index], WEATHER_NAMES[weather_id], "流动" if dynamic_enabled else "静止"]
	for index in time_buttons.size():
		time_buttons[index].disabled = index == time_index
	for id in weather_buttons:
		weather_buttons[id].disabled = id == weather_id
	dynamic_button.text = "Static · 静止" if dynamic_enabled else "Resume · 恢复"
	hint_label.text = "大橘眯起眼，轻轻蹭了蹭你的手。" if feedback_remaining > 0 else "点击岸边大橘摸摸。1–6 时辰 · 7/8/9 天气 · 空格 静止/恢复 · R 重置"

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_6:
		set_time_index(event.keycode - KEY_1)
	elif event.keycode == KEY_7:
		set_weather("clear")
	elif event.keycode == KEY_8:
		set_weather("cloudy")
	elif event.keycode == KEY_9:
		set_weather("light_rain")
	elif event.keycode == KEY_SPACE:
		_toggle_dynamic()
	elif event.keycode == KEY_R:
		reset_scene()
	else:
		return
	get_viewport().set_input_as_handled()
