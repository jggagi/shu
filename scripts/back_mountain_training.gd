extends Control

const State = preload("res://scripts/demo_state.gd")
const Lighting = preload("res://scripts/back_mountain_lighting.gd")
const CONFIG_PATH := "res://assets/data/back_mountain_training.json"
const ART_DIR := "res://assets/art/back_mountain_training/"
const FONT_PATH := "res://assets/fonts/ShuBackMountainSerif.ttf"
const FALLBACK_FONT_PATH := "res://assets/fonts/ShuDemoSerif.ttf"
const INK := Color("354137")
const JADE := Color("32695c")
const GOLD := Color("ad8959")
const PAPER := Color("f4eddf")
const MUTED := Color("6d6658")
const VIEW_SIZE := Vector2(1440, 900)
const ART_SIZE := Vector2(1440, 716)
const ART_TOP := 90.0
const FOOTER_TOP := 806.0

var state = State.new()
var config: Dictionary = {}
var dynamic_enabled := true
var lighting_enabled := true
var lighting: Node
var busy := false
var presentation_time := 0.0
var qa_motion_paused := false
var training_elapsed := 0.0
var last_result: Dictionary = {}

var actor_hotspot: Button
var sword_hotspot: Button
var reset_button: Button
var dynamic_button: Button
var lighting_button: Button

var _world_canvas: CanvasLayer

var _art_root: Control
var _far_layer: Control
var _mid_layer: Control
var _near_layer: Control
var _foreground_layer: Control
var _parallax_layers: Array[Control] = []
var _parallax_depths: Array[float] = []
var _art_nodes: Array[CanvasItem] = []
var _actor_sprite: TextureRect
var _actor_open_texture: AtlasTexture
var _actor_closed_texture: AtlasTexture
var _actor_base_position := Vector2.ZERO
var _actor_base_scale := Vector2.ONE
var _actor_hovered := false
var _sword_hovered := false
var _sword_base_position := Vector2.ZERO
var _sword_sprite: TextureRect
var _near_art: TextureRect
var _hair_material: ShaderMaterial
var _near_material: ShaderMaterial
var _waterfall_material: ShaderMaterial
var _mist_materials: Array[ShaderMaterial] = []
var _leaf_nodes: Array[Polygon2D] = []
var _gust_schedule: Array[Dictionary] = []
var _blink_schedule: Array[Dictionary] = []
var _gust_cycle_seconds := 1.0
var _blink_cycle_seconds := 1.0
var _training_leaf_data: Array[Dictionary] = []

var _date_label: Label
var _energy_label: Label
var _cultivation_label: Label
var _energy_bar: ProgressBar
var _result_label: Label
var _hint_label: Label
var _training_receipt: Dictionary = {}
var _training_motion_elapsed := 0.0
var _training_leaf_count := 1
var _training_count := 0
var _displayed_tint := Color.WHITE
var _art_pointer := Vector2.INF
var _default_hint := "点击江砚秋可修炼，点击旧剑也可修炼。"


func _ready() -> void:
	get_window().title = "蜀山后山 · 独自修炼 · 光影 v1"
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (config is Dictionary):
		config = {}
	_build_theme()
	_build_gust_schedule()
	_build_blink_schedule()
	_build_scene()
	lighting = Lighting.new()
	lighting.name = "BackMountainLighting"
	add_child(lighting)
	lighting.setup(self)
	_refresh_hud()
	refresh_environment()
	_hint_label.text = _default_hint
	_update_controls()


func _build_theme() -> void:
	var game_theme := Theme.new()
	var font: Font = load(FONT_PATH)
	if font == null:
		font = load(FALLBACK_FONT_PATH)
	if font != null:
		game_theme.default_font = font
	game_theme.default_font_size = 20
	theme = game_theme


func _build_scene() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = VIEW_SIZE
	mouse_filter = MOUSE_FILTER_IGNORE

	var ground := ColorRect.new()
	ground.name = "PaperGround"
	ground.color = Color("d9cfbd")
	ground.mouse_filter = MOUSE_FILTER_IGNORE
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ground)

	# DirectionalLight2D ignores item light masks; isolate the painted world canvas.
	_world_canvas = CanvasLayer.new()
	_world_canvas.name = "WorldCanvas"
	_world_canvas.layer = 1
	add_child(_world_canvas)

	_art_root = Control.new()
	_art_root.name = "ArtArea"
	_art_root.position = Vector2(0, ART_TOP)
	_art_root.size = ART_SIZE
	_art_root.clip_contents = true
	_art_root.mouse_filter = MOUSE_FILTER_IGNORE
	_art_root.z_index = 1
	_world_canvas.add_child(_art_root)

	var depths: Array = config.get("parallax_strengths", [1, 2, 4, 6])
	_far_layer = _make_parallax_layer("FarMountains", 0, float(depths[0]))
	_mid_layer = _make_parallax_layer("MiddlePeaks", 1, float(depths[1]))
	_near_layer = _make_parallax_layer("NearLedge", 2, float(depths[2]))
	_foreground_layer = _make_parallax_layer("Foreground", 3, float(depths[3]))

	_add_art_texture(ART_DIR + "far.png", Rect2(Vector2.ZERO, ART_SIZE), _far_layer, TextureRect.STRETCH_SCALE, "FarArtwork")
	_add_art_texture(ART_DIR + "mid.png", Rect2(Vector2.ZERO, ART_SIZE), _mid_layer, TextureRect.STRETCH_SCALE, "MiddleArtwork")
	_build_waterfall()
	_build_mist()
	_near_art = _add_art_texture(ART_DIR + "near.png", Rect2(Vector2.ZERO, ART_SIZE), _near_layer, TextureRect.STRETCH_SCALE, "NearArtwork")
	_build_near_wind()
	_build_actor_and_sword()
	_build_leaves()
	_build_header()
	_build_footer()
	_build_scene_frame()


func _make_parallax_layer(layer_name: String, z: int, depth: float) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.position = Vector2.ZERO
	layer.size = ART_SIZE
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	layer.z_index = z
	_art_root.add_child(layer)
	_parallax_layers.append(layer)
	_parallax_depths.append(depth)
	return layer


func _add_art_texture(path: String, rect: Rect2, parent: Node, stretch: int, node_name: String) -> TextureRect:
	var image := TextureRect.new()
	image.name = node_name
	image.texture = load(path)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = stretch
	image.mouse_filter = MOUSE_FILTER_IGNORE
	_place(image, rect, parent)
	if parent == _far_layer or parent == _mid_layer:
		image.material = _painted_material()
	_art_nodes.append(image)
	return image


func _build_actor_and_sword() -> void:
	var actor_rect := _read_rect("actor_rect", Rect2(880, 260, 290, 290))
	var actor_texture := load(ART_DIR + "actor-sheet.png") as Texture2D
	_actor_open_texture = AtlasTexture.new()
	_actor_closed_texture = AtlasTexture.new()
	if actor_texture != null:
		var tile_width := actor_texture.get_width() / 2.0
		_actor_open_texture.atlas = actor_texture
		_actor_open_texture.region = Rect2(0, 0, tile_width, actor_texture.get_height())
		_actor_open_texture.filter_clip = true
		_actor_closed_texture.atlas = actor_texture
		_actor_closed_texture.region = Rect2(tile_width, 0, tile_width, actor_texture.get_height())
		_actor_closed_texture.filter_clip = true

	_actor_sprite = TextureRect.new()
	_actor_sprite.name = "SeatedActor"
	_actor_sprite.texture = _actor_open_texture
	_actor_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_actor_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_actor_sprite.mouse_filter = MOUSE_FILTER_IGNORE
	_place(_actor_sprite, actor_rect, _foreground_layer)
	_actor_base_position = actor_rect.position
	_actor_base_scale = _actor_sprite.scale
	_art_nodes.append(_actor_sprite)

	var hair_shader := load("res://assets/shaders/back_mountain_hair_wind.gdshader") as Shader
	if hair_shader != null:
		_hair_material = ShaderMaterial.new()
		_hair_material.shader = hair_shader
		_hair_material.set_shader_parameter("hair_uv_rect", _read_vector4("hair_uv_rect", Vector4(0.27, 0.02, 0.73, 0.29)))
		_hair_material.set_shader_parameter("wind_time", presentation_time)
		_hair_material.set_shader_parameter("wind_strength", 0.0)
		_hair_material.set_shader_parameter("tile_origin", 0.0)
		_actor_sprite.material = _hair_material

	var actor_inset: Array = config.get("actor_hotspot_inset", [20, 8, 20, 8])
	var actor_hotspot_rect := Rect2(
		actor_rect.position.x + float(actor_inset[0]),
		actor_rect.position.y + float(actor_inset[1]),
		actor_rect.size.x - float(actor_inset[0]) - float(actor_inset[2]),
		actor_rect.size.y - float(actor_inset[1]) - float(actor_inset[3]))
	actor_hotspot = _make_hotspot("ActorHotspot", actor_hotspot_rect, "点击江砚秋修炼")
	actor_hotspot.pressed.connect(request_training)
	actor_hotspot.mouse_entered.connect(_set_actor_hover.bind(true))
	actor_hotspot.mouse_exited.connect(_set_actor_hover.bind(false))

	var sword_rect := _read_rect("sword_rect", Rect2(1145, 515, 200, 90))
	_sword_sprite = _add_art_texture(ART_DIR + "sword.svg", sword_rect, _foreground_layer, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "OldSwordArtwork")
	_sword_base_position = sword_rect.position
	var sword_inset: Array = config.get("sword_hotspot_inset", [0, 2, 0, 0])
	var sword_hotspot_rect := Rect2(
		sword_rect.position.x + float(sword_inset[0]),
		sword_rect.position.y + float(sword_inset[1]),
		sword_rect.size.x - float(sword_inset[0]) - float(sword_inset[2]),
		sword_rect.size.y - float(sword_inset[1]) - float(sword_inset[3]))
	var sword_uv := _make_hotspot("SwordHotspot", sword_hotspot_rect, "点击旧剑修炼")
	sword_uv.pressed.connect(request_training)
	sword_uv.mouse_entered.connect(_set_sword_hover.bind(true))
	sword_uv.mouse_exited.connect(_set_sword_hover.bind(false))
	sword_hotspot = sword_uv

	_actor_sprite.pivot_offset = Vector2(actor_rect.size.x * 0.5, actor_rect.size.y)
	_actor_base_position = actor_rect.position
	_actor_base_scale = _actor_sprite.scale


func _make_hotspot(node_name: String, rect: Rect2, tooltip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.flat = true
	button.text = ""
	button.tooltip_text = tooltip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_place(button, rect, _foreground_layer)
	button.z_index = 10
	return button


func _build_waterfall() -> void:
	var rect := _read_rect("waterfall_rect", Rect2(774, 355, 38, 145))
	var water := ColorRect.new()
	water.name = "DistantWaterfall"
	water.color = Color.WHITE
	water.mouse_filter = MOUSE_FILTER_IGNORE
	_place(water, rect, _mid_layer)
	var shader := load("res://assets/shaders/waterfall_flow.gdshader") as Shader
	if shader != null:
		_waterfall_material = ShaderMaterial.new()
		_waterfall_material.shader = shader
		_waterfall_material.set_shader_parameter("flow_time", presentation_time)
		_waterfall_material.set_shader_parameter("flow_alpha", float(config.get("waterfall_alpha", 0.22)))
		_waterfall_material.set_shader_parameter("flow_tint", Color("e2e9e3"))
		water.material = _waterfall_material


func _build_mist() -> void:
	var noise := NoiseTexture2D.new()
	noise.width = 128
	noise.height = 128
	noise.seamless = true
	var generator := FastNoiseLite.new()
	generator.seed = int(config.get("mist_seed", 471205))
	generator.frequency = 0.025
	noise.noise = generator
	var shader := load("res://assets/shaders/back_mountain_mist.gdshader") as Shader
	if shader == null:
		return
	var mist_rects: Array = config.get("mist_rects", [[230, 120, 920, 230], [540, 260, 720, 195]])
	for i in mist_rects.size():
		var rect_values: Array = mist_rects[i]
		var mist := ColorRect.new()
		mist.name = "MountainMist%d" % (i + 1)
		mist.color = Color.WHITE
		mist.mouse_filter = MOUSE_FILTER_IGNORE
		var rect := Rect2(rect_values[0], rect_values[1], rect_values[2], rect_values[3])
		_place(mist, rect, _mid_layer)
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("mist_noise", noise)
		material.set_shader_parameter("mist_time", presentation_time)
		material.set_shader_parameter("mist_density", float(config.get("mist_density", 0.12)) * _mist_layer_factor(i))
		material.set_shader_parameter("mist_tint", Color("dfe7e2"))
		mist.material = material
		_mist_materials.append(material)


func _build_near_wind() -> void:
	var shader := load("res://assets/shaders/back_mountain_near_wind.gdshader") as Shader
	if shader == null:
		return
	_near_material = ShaderMaterial.new()
	_near_material.shader = shader
	_near_material.set_shader_parameter("pine_uv_rect", _read_vector4("pine_uv_rect", Vector4(0.0, 0.0, 0.42, 0.64)))
	_near_material.set_shader_parameter("grass_uv_rect", _read_vector4("grass_uv_rect", Vector4(0.0, 0.68, 1.0, 0.16)))
	_near_material.set_shader_parameter("wind_time", presentation_time)
	_near_material.set_shader_parameter("wind_strength", 0.0)
	_near_art.material = _near_material


func _build_leaves() -> void:
	var leaf_colors: Array[Color] = [Color("b69a66"), Color("829875"), Color("c1aa76"), Color("b69a66"), Color("829875")]
	for i in 5:
		var leaf := Polygon2D.new()
		leaf.name = "GustLeaf%d" % (i + 1)
		leaf.polygon = PackedVector2Array([Vector2(-7, 0), Vector2(-2, -4), Vector2(7, -2), Vector2(4, 2), Vector2(-3, 4)])
		leaf.color = leaf_colors[i]
		leaf.material = _painted_material()
		leaf.visible = false
		_foreground_layer.add_child(leaf)
		_leaf_nodes.append(leaf)


func _build_gust_schedule() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.get("leaf_seed", 20261005))
	var interval_min := float(config.get("gust_interval_min", 8.0))
	var interval_max := float(config.get("gust_interval_max", 14.0))
	var duration_min := float(config.get("gust_duration_min", 1.0))
	var duration_max := float(config.get("gust_duration_max", 3.0))
	var leaf_min := int(config.get("gust_leaf_count_min", 1))
	var leaf_max := int(config.get("gust_leaf_count_max", 2))
	var start := rng.randf_range(interval_min, interval_max)
	for _gust_index in 64:
		var duration := rng.randf_range(duration_min, duration_max)
		var leaves: Array[Dictionary] = []
		var leaf_count := rng.randi_range(leaf_min, leaf_max)
		for _leaf_index in leaf_count:
			leaves.append({
				"origin": Vector2(rng.randf_range(250.0, 1380.0), rng.randf_range(105.0, 500.0)),
				"velocity": Vector2(rng.randf_range(28.0, 72.0), rng.randf_range(48.0, 112.0)),
				"rotation": rng.randf_range(-1.1, 1.1),
			})
		_gust_schedule.append({"start": start, "duration": duration, "leaves": leaves})
		start += duration + rng.randf_range(interval_min, interval_max)
	_gust_cycle_seconds = float(_gust_schedule[-1].start) + float(_gust_schedule[-1].duration)


func _build_blink_schedule() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.get("blink_seed", 194705))
	var interval_min := float(config.get("blink_interval_min", 4.0))
	var interval_max := float(config.get("blink_interval_max", 7.0))
	var start := rng.randf_range(interval_min, interval_max)
	var duration := float(config.get("blink_duration", 0.12))
	for _blink_index in 128:
		_blink_schedule.append({"start": start, "duration": duration})
		start += duration + rng.randf_range(interval_min, interval_max)
	_blink_cycle_seconds = float(_blink_schedule[-1].start) + float(_blink_schedule[-1].duration)


func _build_header() -> void:
	_add_panel(Rect2(0, 0, VIEW_SIZE.x, ART_TOP), Color("eee7d9"), Color("ad8959"), 1)
	_add_line(Vector2(28, 81), Vector2(1412, 81), Color("cdbb99"), 1)
	_make_label("蜀山行记", Rect2(34, 8, 256, 43), 34, INK)
	_make_label("后山 · 山间静修", Rect2(37, 51, 252, 25), 17, MUTED)
	_add_line(Vector2(310, 18), Vector2(310, 70), Color("cdbb99"), 1)
	_date_label = _make_label("", Rect2(342, 18, 242, 30), 23, INK)
	_energy_label = _make_label("", Rect2(610, 12, 210, 27), 18, INK)
	_energy_bar = _make_bar(Rect2(612, 49, 188, 12), int(state.rules.energy_max), Color("548d9a"))
	_cultivation_label = _make_label("", Rect2(843, 19, 214, 27), 18, INK)
	dynamic_button = _make_button("静态对比", Rect2(1084, 23, 143, 42), _toggle_dynamic, true)
	dynamic_button.tooltip_text = "切换环境与人物微动；快捷键 4。"
	lighting_button = _make_button("光影：增强 · L", Rect2(854, 52, 184, 24), _toggle_lighting, true)
	lighting_button.add_theme_font_size_override("font_size", 16)
	lighting_button.tooltip_text = "对比增强光影与原画；快捷键 L。"
	reset_button = _make_button("重新开始", Rect2(1252, 23, 154, 42), _reset_from_button)
	reset_button.tooltip_text = "恢复首日初始状态；快捷键 R。"


func _build_footer() -> void:
	_add_panel(Rect2(0, FOOTER_TOP, VIEW_SIZE.x, VIEW_SIZE.y - FOOTER_TOP), Color("eee7d9"), Color("ad8959"), 1)
	_add_line(Vector2(28, FOOTER_TOP + 11), Vector2(1412, FOOTER_TOP + 11), Color("cdbb99"), 1)
	_hint_label = _make_label("", Rect2(38, 820, 934, 25), 17, MUTED)
	_result_label = _make_label("", Rect2(38, 848, 990, 38), 22, INK)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_make_label("1 修炼 · 4 静态", Rect2(1110, 829, 285, 25), 17, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_make_label("R 重新开始", Rect2(1110, 855, 285, 24), 17, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)


func _build_scene_frame() -> void:
	var frame := Panel.new()
	frame.name = "ArtFrame"
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color("ad8959")
	style.set_border_width_all(1)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	frame.add_theme_stylebox_override("panel", style)
	frame.material = _painted_material()
	_place(frame, Rect2(0, ART_TOP, VIEW_SIZE.x, ART_SIZE.y), _world_canvas)
	frame.z_index = 100


func _add_panel(rect: Rect2, fill: Color, border: Color, border_width: int) -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	_place(panel, rect, self)
	panel.z_index = 15
	return panel


func _add_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.default_color = color
	line.width = width
	line.z_index = 16
	add_child(line)


func _make_label(text: String, rect: Rect2, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = MOUSE_FILTER_IGNORE
	_place(label, rect, self)
	label.z_index = 18
	return label


func _make_bar(rect: Rect2, maximum: int, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.show_percentage = false
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _style(Color("ddd3c1"), Color("cbb895"), 1))
	bar.add_theme_stylebox_override("fill", _style(fill, fill, 0))
	_place(bar, rect, self)
	bar.z_index = 18
	return bar


func _make_button(text: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", JADE)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_disabled_color", Color("9b988c"))
	var normal_fill := Color(0.85, 0.73, 0.50, 0.17) if primary else Color(1, 1, 1, 0.04)
	button.add_theme_stylebox_override("normal", _style(normal_fill, GOLD, 1))
	button.add_theme_stylebox_override("hover", _style(Color(0.85, 0.73, 0.50, 0.24), GOLD, 2))
	button.add_theme_stylebox_override("pressed", _style(Color("245345"), Color("245345"), 1))
	button.add_theme_stylebox_override("disabled", _style(Color(0.35, 0.38, 0.35, 0.14), GOLD, 1))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), GOLD, 2))
	button.pressed.connect(callback)
	_place(button, rect, self)
	button.z_index = 19
	return button


func _style(fill: Color, border: Color = GOLD, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _place(node: Control, rect: Rect2, parent: Node) -> void:
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size


func _read_rect(key: String, fallback: Rect2) -> Rect2:
	var value: Variant = config.get(key, null)
	if value is Array and value.size() == 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return fallback


func _read_vector4(key: String, fallback: Vector4) -> Vector4:
	var value: Variant = config.get(key, null)
	if value is Array and value.size() == 4:
		return Vector4(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return fallback


func _refresh_hud() -> void:
	if _date_label == null:
		return
	_date_label.text = state.time_text()
	_energy_label.text = "精力  %d / %d" % [state.energy, int(state.rules.energy_max)]
	_cultivation_label.text = "修为  %d" % state.cultivation
	_energy_bar.max_value = int(state.rules.energy_max)
	_energy_bar.value = state.energy


func request_training() -> Dictionary:
	if busy:
		return {"ok": false, "busy": true, "reason": "正在修炼。"}
	var energy_before: int = state.energy
	var cultivation_before: int = state.cultivation
	var day_before: int = state.day
	var time_index_before: int = state.time_index
	var result: Dictionary = state.train()
	if not bool(result.get("ok", false)):
		last_result = result.duplicate(true)
		var reason := str(result.get("reason", "修炼暂不可用。"))
		_set_result(reason + " 可重新开始。", true)
		return result

	busy = true
	training_elapsed = 0.0
	_training_motion_elapsed = 0.0
	_training_receipt = {
		"ok": true,
		"gain": state.cultivation - cultivation_before,
		"energy_cost": energy_before - state.energy,
		"duration": int(state.rules.training_duration),
		"day_before": day_before,
		"time_index_before": time_index_before,
		"day_after": state.day,
		"time_index_after": state.time_index,
	}
	_training_count += 1
	_training_leaf_count = int(config.get("training_leaf_count_min", 1))
	if int(config.get("training_leaf_count_max", 2)) > _training_leaf_count:
		_training_leaf_count += _training_count % 2
	_build_training_leaf_data()
	last_result = _training_receipt.duplicate(true)
	_update_actor_face()
	_hint_label.text = "修炼"
	_sync_shader_times()
	_update_controls()
	return last_result


func reset_demo() -> bool:
	if busy:
		return false
	state.reset()
	presentation_time = 0.0
	training_elapsed = 0.0
	_training_motion_elapsed = 0.0
	_training_receipt.clear()
	_training_leaf_data.clear()
	_training_leaf_count = 1
	_training_count = 0
	last_result = {}
	_actor_sprite.texture = _actor_open_texture
	_actor_sprite.position = _actor_base_position
	_actor_sprite.scale = _actor_base_scale
	_update_actor_face()
	_refresh_hud()
	refresh_environment()
	if lighting != null:
		lighting.cloud_time = 0.0
		lighting.advance(0.0, 0.0, dynamic_enabled, -1.0)
	for material in _mist_materials:
		material.set_shader_parameter("mist_time", 0.0)
	if _waterfall_material != null:
		_waterfall_material.set_shader_parameter("flow_time", 0.0)
	_set_wind_strength(0.0)
	_update_leaf_art(0.0)
	_hint_label.text = "点选江砚秋可修炼，点选旧剑也可修炼。"
	_result_label.text = ""
	_update_controls()
	return true


func set_dynamic(value: bool) -> void:
	if dynamic_enabled == value:
		return
	dynamic_enabled = value
	if not dynamic_enabled:
		for i in _parallax_layers.size():
			_parallax_layers[i].position = Vector2.ZERO
		_sword_sprite.position = _sword_base_position
		_update_leaf_art(presentation_time)
		_actor_sprite.position = _actor_base_position
		_actor_sprite.scale = _actor_base_scale
		_update_actor_face()
		_set_wind_strength(0.0)
	else:
		_sync_shader_times()
		_update_actor_face()
		_update_breath_pose()
		_update_leaf_art(presentation_time)
	_update_dynamic_button()
	if lighting != null:
		lighting.advance(0.0, presentation_time, dynamic_enabled, _lighting_training_progress())


func seek_presentation(seconds: float) -> void:
	presentation_time = maxf(0.0, seconds)
	if not dynamic_enabled:
		return
	_sync_shader_times()
	_update_leaf_art(presentation_time)
	_update_breath_pose()
	_update_actor_face()
	if lighting != null:
		lighting.advance(0.0, presentation_time, dynamic_enabled, _lighting_training_progress())


func refresh_environment(smooth: bool = false) -> void:
	var times: Array = state.rules.times
	if times.is_empty():
		return
	var shown_index := int(_training_receipt.get("time_index_before", state.time_index)) if busy else int(state.time_index)
	var safe_index := clampi(shown_index, 0, times.size() - 1)
	var time_name := str(times[safe_index])
	var tints: Dictionary = config.get("time_tints", {})
	var tint_text := str(tints.get(time_name, "#f4f0e5"))
	_displayed_tint = Color(tint_text)
	for art_node in _art_nodes:
		art_node.modulate = _displayed_tint
	for leaf in _leaf_nodes:
		leaf.modulate = _displayed_tint
	if _waterfall_material != null:
		_waterfall_material.set_shader_parameter("flow_tint", Color("e2e9e3") * _displayed_tint)
	for material in _mist_materials:
		material.set_shader_parameter("mist_tint", Color("dfe7e2") * _displayed_tint)
	var densities: Dictionary = config.get("mist_densities", {})
	var base_density := float(densities.get(time_name, config.get("mist_density", 0.12)))
	for i in _mist_materials.size():
		_mist_materials[i].set_shader_parameter("mist_density", base_density * _mist_layer_factor(i))
	if lighting != null:
		lighting.set_time_index(safe_index, smooth)


func _process(delta: float) -> void:
	if busy:
		training_elapsed = minf(training_elapsed + delta, float(config.get("training_seconds", 1.8)))
	if dynamic_enabled:
		if not qa_motion_paused:
			presentation_time += delta
			if busy:
				_training_motion_elapsed += delta
		_update_breath_pose()
		_update_actor_face()
		_update_parallax(delta)
		_update_leaf_art(presentation_time)
		if not qa_motion_paused:
			_sync_shader_times()
	if lighting != null:
		lighting.advance(delta, presentation_time, dynamic_enabled, _lighting_training_progress())
	if busy and training_elapsed >= float(config.get("training_seconds", 1.8)):
		_finish_training()


func _update_parallax(delta: float) -> void:
	var pointer := _art_pointer if _art_pointer.is_finite() else _art_root.get_local_mouse_position()
	var center := ART_SIZE * 0.5
	if not Rect2(Vector2.ZERO, ART_SIZE).has_point(pointer):
		return
	var normalized := (pointer - center) / center
	var target := -normalized.normalized() if normalized.length() > 1.0 else -normalized
	var blend := 1.0 - exp(-4.5 * delta)
	for i in _parallax_layers.size():
		var depth := _parallax_depths[i]
		var desired := target * depth
		_parallax_layers[i].position = _parallax_layers[i].position.lerp(desired, blend)


func _update_breath_pose() -> void:
	if _actor_sprite == null or not dynamic_enabled:
		return
	var amount := sin(presentation_time * 1.65) * 0.0032
	if busy:
		amount += sin(_training_motion_elapsed * 3.2) * 0.0045
	_actor_sprite.scale = _actor_base_scale * Vector2(1.0 - amount, 1.0 + amount)
	_actor_sprite.position = _actor_base_position + Vector2(0, -absf(amount) * 5.0 - (2.0 if _actor_hovered and not busy else 0.0))
	_sword_sprite.position = _sword_base_position + Vector2(0, -2.0 if _sword_hovered and not busy else 0.0)


func _update_leaf_art(at_time: float) -> void:
	for leaf in _leaf_nodes:
		leaf.visible = false
	if not dynamic_enabled:
		return
	var gust := _active_gust(at_time)
	if not gust.is_empty():
		var gust_start := float(gust.start)
		var gust_duration := float(gust.duration)
		var gust_progress := (at_time - gust_start) / gust_duration
		var gust_leaves: Array = gust.leaves
		for i in mini(gust_leaves.size(), 3):
			_apply_leaf(i, gust_leaves[i], at_time - gust_start, gust_progress)
	if busy and _training_motion_elapsed < float(config.get("training_seconds", 1.8)):
		var train_duration := maxf(float(config.get("training_seconds", 1.8)), 0.01)
		var train_progress := clampf(_training_motion_elapsed / train_duration, 0.0, 1.0)
		for i in mini(_training_leaf_count, _training_leaf_data.size()):
			_apply_leaf(3 + i, _training_leaf_data[i], _training_motion_elapsed, train_progress)


func _apply_leaf(node_index: int, leaf_data: Dictionary, elapsed: float, progress: float) -> void:
	if node_index >= _leaf_nodes.size():
		return
	var leaf := _leaf_nodes[node_index]
	leaf.visible = true
	leaf.position = leaf_data.origin + leaf_data.velocity * elapsed
	leaf.rotation = float(leaf_data.rotation) + progress * 2.1


func _active_gust(at_time: float) -> Dictionary:
	var cycle_offset := floorf(at_time / _gust_cycle_seconds) * _gust_cycle_seconds
	var cycle_time := at_time - cycle_offset
	for gust in _gust_schedule:
		var start := float(gust.start)
		if cycle_time >= start and cycle_time < start + float(gust.duration):
			var active := gust.duplicate()
			active.start = start + cycle_offset
			return active
	return {}


func _build_training_leaf_data() -> void:
	_training_leaf_data.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.get("training_leaf_seed", 20261005)) + _training_count
	for i in _training_leaf_count:
		_training_leaf_data.append({
			"origin": Vector2(rng.randf_range(725.0, 955.0), rng.randf_range(480.0, 535.0)),
			"velocity": Vector2(rng.randf_range(58.0, 105.0), rng.randf_range(-44.0, 8.0)),
			"rotation": rng.randf_range(-0.7, 0.7),
		})


func _sync_shader_times() -> void:
	if not dynamic_enabled:
		_set_wind_strength(0.0)
		return
	if _waterfall_material != null:
		_waterfall_material.set_shader_parameter("flow_time", presentation_time)
	for material in _mist_materials:
		material.set_shader_parameter("mist_time", presentation_time)
	var gust := _active_gust(presentation_time)
	var wind_strength := 0.0
	if not gust.is_empty():
		var gust_progress := (presentation_time - float(gust.start)) / float(gust.duration)
		wind_strength = float(config.get("gust_wind_strength", 0.06)) * sin(PI * gust_progress)
	if busy:
		var progress := clampf(training_elapsed / maxf(float(config.get("training_seconds", 1.8)), 0.01), 0.0, 1.0)
		wind_strength = maxf(wind_strength, float(config.get("training_wind_strength", 0.11)) * sin(PI * progress))
	_set_wind_strength(wind_strength)


func _set_wind_strength(value: float) -> void:
	if _near_material != null:
		_near_material.set_shader_parameter("wind_time", presentation_time)
		_near_material.set_shader_parameter("wind_strength", value)
	if _hair_material != null:
		_hair_material.set_shader_parameter("wind_time", presentation_time)
		_hair_material.set_shader_parameter("wind_strength", value)


func _mist_layer_factor(index: int) -> float:
	var factors: Array = config.get("mist_layer_factors", [0.72, 0.48])
	if index >= 0 and index < factors.size():
		return float(factors[index])
	return 0.5


func _update_actor_face() -> void:
	if _actor_sprite == null:
		return
	if dynamic_enabled and (busy or _is_blinking(presentation_time)):
		_actor_sprite.texture = _actor_closed_texture
		if _hair_material != null:
			_hair_material.set_shader_parameter("tile_origin", 0.5)
	else:
		_actor_sprite.texture = _actor_open_texture
		if _hair_material != null:
			_hair_material.set_shader_parameter("tile_origin", 0.0)


func _is_blinking(at_time: float) -> bool:
	at_time = fmod(at_time, _blink_cycle_seconds)
	for blink in _blink_schedule:
		var start := float(blink.start)
		if at_time >= start and at_time < start + float(blink.duration):
			return true
	return false


func _set_actor_hover(hovered: bool) -> void:
	_actor_hovered = hovered
	if _actor_sprite != null:
		_actor_sprite.self_modulate = Color(1.035, 1.035, 1.02) if hovered else Color.WHITE
	if _hint_label != null:
		_hint_label.text = "修炼" if hovered else _default_hint


func _set_sword_hover(hovered: bool) -> void:
	_sword_hovered = hovered
	if _sword_sprite != null:
		_sword_sprite.self_modulate = Color(1.035, 1.035, 1.02) if hovered else Color.WHITE
	if _hint_label != null:
		_hint_label.text = "修炼" if hovered else _default_hint


func _finish_training() -> void:
	busy = false
	training_elapsed = float(config.get("training_seconds", 1.8))
	_update_actor_face()
	if dynamic_enabled:
		_update_breath_pose()
		_update_leaf_art(presentation_time)
	else:
		_actor_sprite.position = _actor_base_position
		_actor_sprite.scale = _actor_base_scale
	last_result = _training_receipt.duplicate(true)
	var gain := int(_training_receipt.gain)
	var energy_cost := int(_training_receipt.energy_cost)
	var duration := int(_training_receipt.duration)
	_hint_label.text = _default_hint
	_set_result("修为 +%d · 精力 -%d · 时间 +%d 时辰" % [gain, energy_cost, duration])
	_refresh_hud()
	refresh_environment(true)
	_sync_shader_times()
	_update_controls()


func _set_result(message: String, insufficient: bool = false) -> void:
	if _result_label != null:
		_result_label.text = message
		_result_label.add_theme_color_override("font_color", Color("8e5547") if insufficient else INK)


func _update_controls() -> void:
	if actor_hotspot != null:
		actor_hotspot.disabled = busy
	if sword_hotspot != null:
		sword_hotspot.disabled = busy
	if reset_button != null:
		reset_button.disabled = busy
	_update_dynamic_button()
	_update_lighting_button()


func _update_dynamic_button() -> void:
	if dynamic_button == null:
		return
	dynamic_button.text = "静态对比" if dynamic_enabled else "开启动态"
	dynamic_button.tooltip_text = "关闭或开启环境与人物微动；快捷键 4。"


func _painted_material() -> CanvasItemMaterial:
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return material


func _lighting_training_progress() -> float:
	if not busy:
		return -1.0
	return training_elapsed / maxf(float(config.get("training_seconds", 1.8)), 0.01)


func set_lighting(value: bool) -> void:
	lighting_enabled = value
	if lighting != null:
		lighting.set_enabled(value)
	refresh_environment()
	_update_lighting_button()


func _update_lighting_button() -> void:
	if lighting_button != null:
		lighting_button.text = "光影：增强 · L" if lighting_enabled else "光影：原画 · L"


func _toggle_lighting() -> void:
	set_lighting(not lighting_enabled)


func _toggle_dynamic() -> void:
	set_dynamic(not dynamic_enabled)


func _reset_from_button() -> void:
	reset_demo()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _art_root != null:
		# Use the delivered viewport event, which works for native input and QA
		# without a second window's desktop pointer overriding this scene.
		_art_pointer = _art_root.get_global_transform_with_canvas().affine_inverse() * event.position


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			request_training()
		KEY_L:
			_toggle_lighting()
		KEY_4:
			_toggle_dynamic()
		KEY_R:
			reset_demo()
