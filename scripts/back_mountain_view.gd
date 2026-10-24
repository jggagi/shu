extends Control

const Presenter = preload("res://scripts/environment_presenter.gd")
const EnvironmentAdapter = preload("res://scripts/back_mountain_environment.gd")
const AmbientAdapter = preload("res://scripts/back_mountain_ambient_life.gd")
const CONFIG_PATH := "res://assets/data/back_mountain_training.json"
const ART_DIR := "res://assets/art/back_mountain_training/"
const FONT_PATH := "res://assets/fonts/ShuBackMountainSerif.ttf"
const FALLBACK_FONT_PATH := "res://assets/fonts/ShuCultivationSwordSerif.ttf"
const INK := Color("354137")
const JADE := Color("32695c")
const GOLD := Color("ad8959")
const PAPER := Color("f4eddf")
const MUTED := Color("6d6658")
const VIEW_SIZE := Vector2(1440, 900)
const ART_SIZE := Vector2(1440, 716)
const ART_TOP := 90.0
const FOOTER_TOP := 806.0

# Borrowed from the cultivation host; this view never constructs gameplay state.
signal return_requested
signal sword_manual_selected(manual_id: String)
signal sword_training_requested
signal sword_training_finished(action_id: int)
const Catalog = preload("res://scripts/sword_manual_catalog.gd")
var manual_buttons: Dictionary = {}
var _selected_manual_title := "剑谱"
var manual_progress_label: Label
var manual_description_label: Label
const SwordPractice = preload("res://scripts/hero_lookdev/formal_sword_practice.gd")
var sword_audio_policy := Callable()
var sword_training_button: Button
var sword_status: Label
var sword_receipt: Dictionary = {}
var sword_practice: Node
var _sword_label: Label
var state
var return_button: Button
var _shared_weather_id := "cloudy"
var config: Dictionary = {}
var dynamic_enabled := true
var environment_config: Dictionary = {}
var environment_presenter = Presenter.new()
var environment_adapter: Node
var ambient_life: Node
var lighting: Node
var busy := false
var presentation_time := 0.0
var qa_motion_paused := false
var training_elapsed := 0.0


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
var _mist_noise: NoiseTexture2D
var _cloud_materials: Array[ShaderMaterial] = []
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
var _hint_label: Label
var _training_motion_elapsed := 0.0
var _training_leaf_count := 1
var _displayed_tint := Color.WHITE
var _art_pointer := Vector2.INF


func configure(shared_state, weather_id: String, dynamic: bool) -> void:
	state = shared_state
	_shared_weather_id = weather_id
	dynamic_enabled = dynamic


func _ready() -> void:
	assert(state != null, "Back Mountain requires the host DemoState")
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (config is Dictionary):
		config = {}
	_build_theme()
	_build_gust_schedule()
	_build_blink_schedule()
	_build_scene()
	environment_config = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/back_mountain_environment.json"))
	environment_presenter.configure(environment_config)
	environment_adapter = EnvironmentAdapter.new()
	environment_adapter.name = "BackMountainEnvironment"
	add_child(environment_adapter)
	environment_adapter.setup(self)
	refresh_environment()
	set_weather(_shared_weather_id, false)
	environment_presenter.finish_transition()
	_apply_environment()
	ambient_life = AmbientAdapter.new()
	ambient_life.name = "BackMountainAmbientLife"
	add_child(ambient_life)
	ambient_life.setup(self)
	ambient_life.cat_petted.connect(_on_cat_petted)
	_refresh_hud()
	_hint_label.text = "山风过松间。往返不消耗时辰、精力或修为。"
	_sync_shader_times()
	_update_leaf_art(0.0)
	_update_actor_face()
	sword_practice = SwordPractice.new()
	sword_practice.name = "SwordPractice"
	add_child(sword_practice)
	sword_practice.setup(self)
	sword_practice.finished.connect(_sword_presentation_finished)
	refresh_sword_manual()


func _build_theme() -> void:
	var game_theme := Theme.new()
	game_theme.default_font = load(FALLBACK_FONT_PATH)
	game_theme.default_font_size = 20
	theme = game_theme


func _build_header() -> void:
	_add_panel(Rect2(0, 0, VIEW_SIZE.x, ART_TOP), Color("eee7d9"), GOLD, 1)
	_make_label("后山", Rect2(34, 12, 250, 40), 34, INK)
	_make_label("蜀山行记", Rect2(37, 53, 250, 25), 17, MUTED)
	_date_label = _make_label("", Rect2(342, 15, 260, 32), 23, INK)
	_energy_label = _make_label("", Rect2(640, 12, 240, 27), 18, INK)
	_energy_bar = _make_bar(Rect2(642, 48, 188, 6), int(state.rules.energy_max), Color("548d9a"))
	_cultivation_label = _make_label("", Rect2(900, 18, 210, 27), 18, INK)
	_sword_label = _make_label("剑术 %d" % state.swordsmanship, Rect2(900, 52, 210, 24), 18, JADE)
	return_button = _make_button("返回听雨廊", Rect2(1190, 23, 216, 42), _request_return, true)
	return_button.name = "ReturnToTingyu"
	return_button.tooltip_text = "返回听雨廊；Esc。往返不消耗资源。"


func _build_footer() -> void:
	_add_panel(Rect2(0, FOOTER_TOP, VIEW_SIZE.x, VIEW_SIZE.y - FOOTER_TOP), Color("eee7d9"), GOLD, 1)
	_hint_label = _make_label("", Rect2(38, 818, 950, 28), 20, MUTED)
	sword_status = _make_label("", Rect2(38, 854, 950, 28), 18, INK)
	sword_training_button = _make_button("练剑 · 剑术 +%d" % int(state.rules.sword_training_gain), Rect2(1045, 825, 360, 48), _request_sword_training, true)
	sword_training_button.name = "SwordTraining"
	sword_training_button.tooltip_text = "精力 -%d · 时间 +%d 时辰；结束后返回听雨廊。" % [int(state.rules.sword_training_cost), int(state.rules.sword_training_duration)]
	_refresh_sword_controls()


func _build_manuals() -> void:
	var prior_children := get_children()
	_add_panel(Rect2(28, 124, 338, 542), PAPER, GOLD, 1)
	_make_label("选择剑谱", Rect2(48, 140, 298, 34), 26, INK)
	_make_label("换谱不消耗精力或时辰", Rect2(48, 176, 298, 24), 17, MUTED)
	var index := 0
	for manual: Dictionary in Catalog.manuals():
		var id := str(manual.id)
		var button := _make_button("", Rect2(48, 212 + index * 62, 298, 52), request_sword_manual.bind(id), true)
		button.name = "Manual_" + id
		button.add_theme_font_size_override("font_size", 20)
		button.tooltip_text = str(manual.description)
		manual_buttons[id] = button
		index += 1
	manual_progress_label = _make_label("", Rect2(48, 532, 298, 52), 19, JADE)
	manual_description_label = _make_label("", Rect2(48, 596, 298, 52), 18, MUTED)
	manual_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The painted world lives on layer 1; put this foreground selector above it.
	var manual_canvas := CanvasLayer.new()
	manual_canvas.name = "SwordManualCanvas"
	manual_canvas.layer = 2
	add_child(manual_canvas)
	var manual_controls := Control.new()
	manual_controls.name = "SwordManualControls"
	manual_controls.theme = theme
	manual_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	manual_canvas.add_child(manual_controls)
	for child in get_children():
		if child is Control and not prior_children.has(child):
			remove_child(child)
			manual_controls.add_child(child)



func request_sword_manual(manual_id: String) -> void:
	if not busy:
		sword_manual_selected.emit(manual_id)


func refresh_sword_manual() -> void:
	var id: String = state.selected_sword_manual_id
	var manual: Dictionary = Catalog.manual(id)
	_selected_manual_title = str(manual.get("title", "剑谱"))
	var count := int(state.sword_manual_practice_counts.get(id, 0))
	var form: Dictionary = Catalog.technique(id, count)
	if manual.is_empty() or form.is_empty():
		return
	for candidate: Dictionary in Catalog.manuals():
		var button: Button = manual_buttons.get(str(candidate.id))
		if button != null:
			button.text = ("● " if str(candidate.id) == id else "") + str(candidate.title) + " · " + str(candidate.style)
	if manual_progress_label != null:
		manual_progress_label.text = "已修习 %d 遍\n下一式：%s" % [count, form.title]
		manual_description_label.text = str(manual.description)
	if sword_practice != null:
		sword_practice.select_form(id, str(form.id))
	_hint_label.text = "%s · %s" % [manual.title, form.title]
	_refresh_sword_controls()


func _refresh_sword_controls() -> void:
	if sword_training_button == null:
		return
	sword_training_button.disabled = busy or state.energy < int(state.rules.sword_training_cost)
	return_button.disabled = busy
	for button: Button in manual_buttons.values():
		button.disabled = busy
	if not busy:
		sword_training_button.text = "修习 · %s" % _selected_manual_title
		sword_status.text = "剑术 %d · 精力 -%d · 一时辰 · %s" % [state.swordsmanship, int(state.rules.sword_training_cost), environment_label(_shared_weather_id)]
		if state.energy < int(state.rules.sword_training_cost):
			sword_status.text = "精力不足，返回听雨廊休息后再来。"


func _request_sword_training() -> void:
	if not busy:
		sword_training_requested.emit()


func show_sword_failure(reason: String) -> void:
	_hint_label.text = reason
	sword_status.text = reason


func play_sword_training(action_id: int, receipt: Dictionary) -> void:
	busy = true
	sword_receipt = receipt.duplicate(true)
	refresh_environment(true)
	_refresh_hud()
	_sword_label.text = "剑术 %d" % state.swordsmanship
	_refresh_sword_controls()
	_hint_label.text = "后山练剑 · 起手，站稳，再挥出。"
	sword_status.text = "%s · 修习中 · 收势后返回听雨廊" % receipt.technique_title
	sword_practice.play(action_id, sword_receipt)


func prepare_sword_training() -> bool:
	if busy or sword_practice == null:
		return false
	var manual_id: String = state.selected_sword_manual_id
	var count := int(state.sword_manual_practice_counts.get(manual_id, 0))
	var form: Dictionary = Catalog.technique(manual_id, count)
	return not form.is_empty() and sword_practice.select_form(manual_id, str(form.id)) and sword_practice.resource_ready()


func _sword_presentation_finished(action_id: int) -> void:
	sword_training_finished.emit(action_id)


func environment_label(id: String) -> String:
	return str({"clear": "晴", "cloudy": "多云", "light_rain": "小雨"}.get(id, id))


func _request_return() -> void:
	if not busy:
		return_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_request_return()


# Standalone harness overrides these presentation hooks for its QA controls.
func _update_dynamic_button() -> void:
	pass

func _update_environment_controls() -> void:
	pass

func _update_ambient_controls() -> void:
	pass

func _lighting_training_progress() -> float:
	return -1.0


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
	_build_clouds()
	_near_art = _add_art_texture(ART_DIR + "near.png", Rect2(Vector2.ZERO, ART_SIZE), _near_layer, TextureRect.STRETCH_SCALE, "NearArtwork")
	_build_near_wind()
	_build_actor_and_sword()
	_build_leaves()
	_build_header()
	_build_footer()
	_build_manuals()
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

	var sword_rect := _read_rect("sword_rect", Rect2(1145, 515, 200, 90))
	_sword_sprite = _add_art_texture(ART_DIR + "sword.svg", sword_rect, _foreground_layer, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "OldSwordArtwork")
	_sword_base_position = sword_rect.position
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
	_mist_noise = noise
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


func _build_clouds() -> void:
	# The opaque far painting contains the sky. Place its sky wash above it,
	# then let the separate middle peaks naturally occlude the distant washes.
	var clouds: Dictionary = config.get("clouds", {})
	var shader := load("res://assets/shaders/back_mountain_cloud.gdshader") as Shader
	if shader == null or _mist_noise == null:
		return
	_add_cloud("FarCloud", Rect2(-24, 8, 1488, 160), _far_layer, shader,
		float(clouds.get("far_speed", 14.0)), float(clouds.get("far_alpha", 0.18)), 0.3)
	_add_cloud("ValleyCloudBehindPeaks", Rect2(-24, 125, 1488, 280), _far_layer, shader,
		float(clouds.get("valley_speed", 12.0)) * 0.8, float(clouds.get("valley_alpha", 0.44)) * 0.8, 2.2)
	# Above the middle mountain waists, below the pine, stone ledge and actor.
	_add_cloud("ValleyCloudAcrossWaists", Rect2(-24, 195, 1488, 270), _mid_layer, shader,
		float(clouds.get("valley_speed", 12.0)), float(clouds.get("valley_alpha", 0.44)), 1.1)


func _add_cloud(node_name: String, rect: Rect2, parent: Control, shader: Shader,
	speed: float, alpha: float, phase: float) -> void:
	var cloud := ColorRect.new()
	cloud.name = node_name
	cloud.color = Color.WHITE
	cloud.mouse_filter = MOUSE_FILTER_IGNORE
	_place(cloud, rect, parent)
	var clouds: Dictionary = config.get("clouds", {})
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("cloud_noise", _mist_noise)
	material.set_shader_parameter("cloud_time", presentation_time)
	material.set_shader_parameter("speed_uv", speed / rect.size.x)
	material.set_shader_parameter("cloud_alpha", clampf(alpha, 0.0, 1.0))
	material.set_shader_parameter("distortion", clampf(float(clouds.get("distortion", 0.004)), 0.0, 0.006))
	material.set_shader_parameter("density_cycle_seconds", maxf(float(clouds.get("density_cycle_seconds", 24.0)), 0.01))
	material.set_shader_parameter("phase", phase)
	cloud.material = material
	_cloud_materials.append(material)


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
	_apply_environment()


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
	_apply_environment()


func refresh_environment(smooth: bool = false) -> void:
	var times: Array = state.rules.times
	if times.is_empty() or environment_config.is_empty():
		return
	var time_name := str(times[clampi(state.time_index, 0, times.size() - 1)])
	var profile_id := str(environment_config.time_mapping.get(time_name, ""))
	environment_presenter.set_time_profile(profile_id, smooth)
	if lighting != null:
		lighting.set_time_index(state.time_index, smooth)
	_apply_environment()


func _apply_environment() -> void:
	if environment_adapter != null:
		environment_adapter.apply_environment(environment_presenter.get_current_environment())
	if ambient_life != null:
		ambient_life.observe_environment()
		_update_ambient_controls()


func set_weather(id: String, smooth: bool = true) -> bool:
	if not environment_presenter.set_weather(id, smooth):
		return false
	_apply_environment()
	_update_environment_controls()
	return true


func pet_cat() -> bool:
	return ambient_life.pet_cat()


func _on_cat_petted() -> void:
	_hint_label.text = "大橘眯着眼，蹭了蹭你的手。"


func _process(delta: float) -> void:
	if sword_training_button != null:
		_refresh_sword_controls()
	if dynamic_enabled:
		if not qa_motion_paused:
			presentation_time += delta
		_update_breath_pose()
		_update_actor_face()
		_update_parallax(delta)
		_update_leaf_art(presentation_time)
		if not qa_motion_paused:
			_sync_shader_times()
	if lighting != null:
		lighting.advance(delta, presentation_time, dynamic_enabled, _lighting_training_progress())
	environment_presenter.advance(delta)
	_apply_environment()
	if ambient_life != null and not qa_motion_paused:
		ambient_life.advance(delta, busy)


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


func _sync_shader_times() -> void:
	if not dynamic_enabled:
		_set_wind_strength(0.0)
		return
	if _waterfall_material != null:
		_waterfall_material.set_shader_parameter("flow_time", presentation_time)
	for material in _mist_materials:
		material.set_shader_parameter("mist_time", presentation_time)
	for material in _cloud_materials:
		material.set_shader_parameter("cloud_time", presentation_time)
	if environment_adapter != null:
		environment_adapter.sync_motion(presentation_time)
	var gust := _active_gust(presentation_time)
	var wind_strength := 0.0
	if not gust.is_empty():
		var gust_progress := (presentation_time - float(gust.start)) / float(gust.duration)
		wind_strength = float(config.get("gust_wind_strength", 0.06)) * sin(PI * gust_progress)
	if busy:
		var progress := clampf(training_elapsed / maxf(float(config.get("training_seconds", 1.8)), 0.01), 0.0, 1.0)
		wind_strength = maxf(wind_strength, float(config.get("training_wind_strength", 0.11)) * sin(PI * progress))
	var environment := environment_presenter.get_current_environment()
	wind_strength *= float(environment.get("wind_strength", 1.0))
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


func _painted_material() -> CanvasItemMaterial:
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return material


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _art_root != null:
		# Use the delivered viewport event, which works for native input and QA
		# without a second window's desktop pointer overriding this scene.
		_art_pointer = _art_root.get_global_transform_with_canvas().affine_inverse() * event.position


