extends "res://addons/cultivation_mode/town_walker.gd"
const Stage = preload("res://addons/cultivation_mode/dock_corner_stage.gd")
const Lamps = preload("res://addons/cultivation_mode/dock_corner_lamps.gd")
const Shadows = preload("res://addons/cultivation_mode/dock_corner_shadows.gd")
const BACKGROUND = preload("res://assets/art/dock_corner_20261113/background.png")
const WATER = preload("res://addons/cultivation_mode/dock_corner_water.gdshader")
var _stage: Node
var _background: TextureRect
var _actors: TextureRect
var _foliage: Polygon2D
const LIGHT = preload("res://addons/cultivation_mode/dock_corner_light.gdshader")
const RIPPLES = preload("res://addons/cultivation_mode/dock_corner_ripples.gdshader")
const AMBIENT_LAYOUT = "res://assets/data/dock-corner-ambient.json"
var _ambient: ColorRect
var environment_enabled := true
const INTERACTIONS = "res://assets/data/dock-corner-interactions.json"
const TIME_LIGHTS = "res://assets/data/dock-corner-time-light.json"
var time_light_id := "afternoon"
var _time_lights: Dictionary = {}
var _markers: Dictionary = {}
var _hotspot_buttons: Dictionary = {}
var _lighting: ColorRect
var elapsed := 0.0
var _lamps: Node2D
var lamp_strength := 0.0
var lighting_enabled := true
var lamps_enabled := true
var action_age := -1.0
var _splash_point := Vector2.ZERO
var _shadows: Node2D
var cast_shadows_enabled := true
var life: RefCounted

func setup(host: RefCounted, map_id: String, map: Dictionary, font: Font, enabled: bool) -> void:
	super.setup(host, map_id, map, font, enabled)
	_background = TextureRect.new()
	_background.texture = BACKGROUND
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var water := ShaderMaterial.new()
	water.shader = WATER
	_background.material = water
	add_child(_background)
	_shadows = Shadows.new()
	_shadows.name = "DockCastShadows"
	add_child(_shadows)
	_stage = Stage.new()
	add_child(_stage)
	_stage.setup(player_position)
	_actors = TextureRect.new()
	_actors.texture = _stage.viewport.get_texture()
	_actors.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_actors.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_actors)
	# Authored willow silhouette: sample original leaves, retain translucent gaps.
	_foliage = Polygon2D.new()
	_foliage.texture = BACKGROUND
	_foliage.polygon = PackedVector2Array([Vector2(0,245),Vector2(130,250),Vector2(232,350),Vector2(278,490),Vector2(243,614),Vector2(125,643),Vector2(55,590),Vector2(0,710)])
	var uv := PackedVector2Array()
	for p: Vector2 in _foliage.polygon:
		uv.append(p * 1.2)
	_foliage.uv = uv
	var material := ShaderMaterial.new()
	material.shader = WATER
	material.set_shader_parameter("foliage_only",true)
	_foliage.material = material
	add_child(_foliage)
	_ambient = ColorRect.new()
	_ambient.name = "DockBoatRipples"
	_ambient.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ripple_material := ShaderMaterial.new()
	ripple_material.shader = RIPPLES
	var anchors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AMBIENT_LAYOUT))
	for id: String in ["stern","bow"]:
		ripple_material.set_shader_parameter(id,Vector2(anchors[id][0],anchors[id][1]))
	_ambient.material = ripple_material
	add_child(_ambient)
	# One composite pass grades painting, foreground and actors together.
	_lighting = ColorRect.new()
	_lighting.name = "DockAfternoonLight"
	_lighting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var light_material := ShaderMaterial.new()
	light_material.shader = LIGHT
	light_material.set_shader_parameter("willow_source", BACKGROUND)
	_lighting.material = light_material
	add_child(_lighting)
	_lamps = Lamps.new()
	_lamps.name = "DockPaperLanterns"
	add_child(_lamps)
	var lamp_layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Lamps.LAYOUT))
	for fixture: Dictionary in lamp_layout.fixtures:
		light_material.set_shader_parameter(str(fixture.id)+"_lamp",Vector2(fixture.center[0],fixture.center[1]))
	for key: String in ["tea_pool","boat_pool","reflection"]:
		var point: Array = lamp_layout[key]
		light_material.set_shader_parameter("lamp_reflection" if key=="reflection" else key,Vector2(point[0],point[1]))
	_time_lights = JSON.parse_string(FileAccess.get_file_as_string(TIME_LIGHTS))
	set_time_light(time_light_id)
	var interactions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INTERACTIONS))
	_markers = interactions.markers
	_ambient.material.set_shader_parameter("splash_point",Vector2(interactions.splash[0],interactions.splash[1]))
	_splash_point = Vector2(interactions.splash[0],interactions.splash[1])
	for id: String in _markers:
		var button := Button.new()
		button.name = "DockObject_"+id
		button.text = str(_markers[id].label)
		button.add_theme_font_override("font",_font)
		button.add_theme_color_override("font_color",Color("#495c4d"))
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.97,0.94,0.85,0.91)
		normal.border_color = Color(0.50,0.49,0.37,0.65)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(4)
		normal.content_margin_left = 7
		normal.content_margin_right = 7
		button.add_theme_stylebox_override("normal",normal)
		button.pressed.connect(request_interaction.bind(id))
		add_child(button)
		_hotspot_buttons[id] = button
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if _background == null:
		return
	for layer: TextureRect in [_background, _actors]:
		layer.position = _map_offset()
		layer.size = Vector2(1280,720) * _map_scale()
	_ambient.position = _map_offset()
	_ambient.size = Vector2(1280,720) * _map_scale()
	_lighting.position = _map_offset()
	_lighting.size = Vector2(1280,720) * _map_scale()
	_foliage.position = _map_offset()
	_foliage.scale = Vector2.ONE * _map_scale()
	_lamps.position = _map_offset()
	_lamps.scale = Vector2.ONE * _map_scale()
	_shadows.position = _map_offset()
	_shadows.scale = Vector2.ONE * _map_scale()
	for id: String in _hotspot_buttons:
		var button: Button = _hotspot_buttons[id]
		button.add_theme_font_size_override("font_size",maxi(12,roundi(16*_map_scale())))
		button.custom_minimum_size.y = 28*_map_scale()
		button.size = button.get_combined_minimum_size()
		var at: Array = _markers[id].label_at
		button.position = logical_to_local(Vector2(at[0],at[1]))-button.size*0.5

func present(seconds: float) -> void:
	elapsed = seconds
	if _background == null:
		return
	_background.material.set_shader_parameter("elapsed", elapsed)
	_foliage.material.set_shader_parameter("elapsed",elapsed)
	_ambient.material.set_shader_parameter("elapsed",elapsed)
	_lighting.material.set_shader_parameter("elapsed", elapsed)
	_stage.sync(player_position, walk_distance, not route.is_empty() and _current(), elapsed)
	if life!=null:
		_stage.present_life(life)
	if action_age>=0.0:
		var origin: Vector2 = _stage.present_throw(action_age,_splash_point)
		if action_age<float(_stage.throw_profile.duration):
			_ambient.material.set_shader_parameter("splash_from",origin)
	_shadows.present(_stage,time_light_id)
	_lamps.present(elapsed,lamp_strength if lighting_enabled and lamps_enabled else 0.0)
	_foliage.visible = player_position.y < 680
	for button: Button in _hotspot_buttons.values():
		button.disabled = not _current()
		button.visible = _current()
	queue_redraw()

func _draw() -> void:
	# All painting is below the actor viewport; no inherited procedural town.
	pass

func set_lighting(enabled: bool) -> void:
	lighting_enabled = enabled
	_lighting.visible = enabled
	_stage.set_lighting(enabled)
	_stage.set_lamp_strength(lamp_strength if lamps_enabled else 0.0)
	_lamps.present(elapsed,lamp_strength if enabled and lamps_enabled else 0.0)
	_shadows.visible = enabled and cast_shadows_enabled

func set_cast_shadows(enabled: bool) -> void:
	cast_shadows_enabled = enabled
	_shadows.visible = enabled and lighting_enabled

func set_time_light(id: String) -> bool:
	if not _time_lights.has(id):
		return false
	time_light_id = id
	var profile: Dictionary = _time_lights[id]
	lamp_strength = float(profile.get("lamplight",0.0))
	set_lamp_effects(lamps_enabled)
	for key: String in profile.paint:
		var value: Variant = profile.paint[key]
		if value is Array:
			value = Vector2(value[0],value[1]) if value.size()==2 else Vector3(value[0],value[1],value[2])
		_lighting.material.set_shader_parameter(key,value)
	_stage.set_time_light(profile.actor)
	return true

func set_lamp_effects(enabled: bool) -> void:
	# Diagnostic A/B keeps the same moonlight, pose and host state.
	lamps_enabled = enabled
	var amount := lamp_strength if enabled else 0.0
	_lighting.material.set_shader_parameter("lamp_strength",amount)
	_stage.set_lamp_strength(amount)
	_lamps.present(elapsed,amount if lighting_enabled else 0.0)

func set_environment_effects(enabled: bool) -> void:
	# Diagnostic comparison; the player's Static control keeps populated effects
	# visible at the frozen phase, including the boat rings.
	environment_enabled = enabled
	_background.material.set_shader_parameter("environment_enabled",enabled)
	_foliage.material.set_shader_parameter("environment_enabled",enabled)
	_ambient.visible = enabled

func request_interaction(id: String) -> bool:
	if not definition.interactions.has(id):
		return false
	var at: Array = definition.interactions[id].position
	return super.click_at(Vector2(at[0],at[1]))

func click_at(point: Vector2) -> bool:
	for id: String in _markers:
		var marker: Dictionary = _markers[id]
		var at: Array = marker.pick_at
		if point.distance_to(Vector2(at[0],at[1]))<float(marker.pick_radius):
			return request_interaction(id)
	return super.click_at(point)

func walk_only(point: Vector2) -> bool:
	# Existing route shortcuts remain movement, with no second action entry.
	if not _current():
		return false
	cancel_walk()
	route.assign(navigation.call("route",player_position,point.round(),0.0))
	feedback.emit("沿石岸走过去。" if not route.is_empty() else "那里走不到。")
	queue_redraw()
	return not route.is_empty()

func set_splash(started: float, origin: Vector2) -> void:
	_ambient.material.set_shader_parameter("splash_started",started)
	_ambient.material.set_shader_parameter("splash_from",origin)

func set_throw_age(age: float) -> void:
	action_age = age
	_ambient.material.set_shader_parameter("action_age",age)
	_ambient.material.set_shader_parameter("splash_started",0.0 if age>=0.0 else -99.0)
