extends Node

# Scene adapter only: the presenter never sees these painted layers or materials.
var rain_material: ShaderMaterial
var shadow_material: ShaderMaterial
var far_material: ShaderMaterial
var middle_material: ShaderMaterial
var sun_material: ShaderMaterial
var current_environment: Dictionary = {}
var _game: Control
var _cloud_alphas: Array[float] = []
var _low_cloud: ColorRect
var _low_cloud_y := 0.0
var _sun_layer: ColorRect


func setup(game: Control) -> void:
	_game = game
	for material in game._cloud_materials:
		_cloud_alphas.append(float(material.get_shader_parameter("cloud_alpha")))
	_low_cloud = game._mid_layer.get_node("ValleyCloudAcrossWaists")
	_low_cloud_y = _low_cloud.position.y
	var far_art := game._far_layer.get_node("FarArtwork") as TextureRect
	far_material = ShaderMaterial.new()
	far_material.shader = preload("res://assets/shaders/back_mountain_environment_art.gdshader")
	far_art.material = far_material
	# MiddleArtwork also contains painted sky and peaks; haze must reach both
	# backgrounds, with a lighter wash on the nearer mountain ridge.
	middle_material = ShaderMaterial.new()
	middle_material.shader = far_material.shader
	game._mid_layer.get_node("MiddleArtwork").material = middle_material
	_build_sun()
	# Reuse the small artistic shadow shader, independently of realtime lighting.
	shadow_material = _overlay("EnvironmentCloudShadow", preload("res://assets/shaders/back_mountain_cloud_shadow.gdshader"), 40)
	shadow_material.set_shader_parameter("cloud_noise", game._mist_noise)
	shadow_material.set_shader_parameter("envelope_seconds", 16.0)
	# Keep relative z at zero: mid parent z=1 must stay below ledge z=2
	# and actor z=3. A positive child z would jump in front of both.
	rain_material = _overlay("MountainFineRain", preload("res://assets/shaders/back_mountain_rain.gdshader"), 0, game._mid_layer)


func _build_sun() -> void:
	_sun_layer = ColorRect.new()
	_sun_layer.name = "PaintedSun"
	_sun_layer.size = Vector2(160.0, 160.0)
	_sun_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun_material = ShaderMaterial.new()
	sun_material.shader = preload("res://assets/shaders/back_mountain_sun.gdshader")
	_sun_layer.material = sun_material
	_game._far_layer.add_child(_sun_layer)
	# Behind the drifting clouds and the nearer opaque mountain artwork.
	_game._far_layer.move_child(_sun_layer, _game._far_layer.get_node("FarArtwork").get_index() + 1)


func _overlay(node_name: String, shader: Shader, z: int, parent: Control = null) -> ShaderMaterial:
	var layer := ColorRect.new()
	layer.name = node_name
	layer.size = _game.ART_SIZE
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = z
	var material := ShaderMaterial.new()
	material.shader = shader
	layer.material = material
	(parent if parent != null else _game._art_root).add_child(layer)
	return material


func apply_environment(params: Dictionary) -> void:
	current_environment = params.duplicate(true)
	var tint: Color = params.world_tint
	var brightness := float(params.brightness)
	tint = Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, 1.0)
	_game._displayed_tint = tint
	for item in _game._art_nodes:
		item.modulate = tint
	for leaf in _game._leaf_nodes:
		leaf.modulate = tint
	far_material.set_shader_parameter("far_contrast", float(params.far_contrast))
	far_material.set_shader_parameter("sky_tint", params.sky_tint)
	far_material.set_shader_parameter("sky_strength", float(params.sky_strength))
	middle_material.set_shader_parameter("far_contrast", lerpf(1.0, float(params.far_contrast), 0.55))
	middle_material.set_shader_parameter("sky_tint", params.sky_tint)
	middle_material.set_shader_parameter("sky_strength", float(params.sky_strength))
	_sun_layer.position = Vector2(float(params.sun_x), float(params.sun_y)) * _game.ART_SIZE - _sun_layer.size * 0.5
	sun_material.set_shader_parameter("sun_opacity", float(params.sun_opacity))
	sun_material.set_shader_parameter("sun_radius", float(params.sun_radius))
	sun_material.set_shader_parameter("sun_tint", Color("fff0b4").lerp(Color("efa36e"), float(params.sun_warmth)))
	for i in _game._cloud_materials.size():
		var multiplier := float(params.far_cloud_multiplier if i == 0 else params.valley_cloud_multiplier)
		_game._cloud_materials[i].set_shader_parameter("cloud_alpha", clampf(_cloud_alphas[i] * multiplier, 0.0, 0.85))
		_game._cloud_materials[i].set_shader_parameter("cloud_tint", Color("f6f4ed") * tint)
	for i in _game._mist_materials.size():
		var material: ShaderMaterial = _game._mist_materials[i]
		material.set_shader_parameter("mist_density", clampf(float(_game.config.mist_density) * float(params.mist_multiplier) * _game._mist_layer_factor(i), 0.0, 0.3))
		material.set_shader_parameter("mist_tint", Color("dfe7e2") * tint)
	if _game._waterfall_material != null:
		_game._waterfall_material.set_shader_parameter("flow_tint", Color("e2e9e3") * tint)
	shadow_material.set_shader_parameter("cloud_min_brightness", 1.0 - float(params.cloud_shadow_strength))
	_low_cloud.position.y = _low_cloud_y + float(params.rain_amount) * 28.0
	rain_material.set_shader_parameter("rain_amount", float(params.rain_amount))
	rain_material.set_shader_parameter("rain_tint", Color("c7d4d7") * tint)
	# Avoid two stacked cloud shadows when comparing the preserved experiment.
	if _game.lighting != null and _game.lighting.cloud_material != null:
		var legacy_overlay: ColorRect = _game.lighting.cloud_material.get_meta("overlay_node")
		legacy_overlay.visible = false


func sync_motion(seconds: float) -> void:
	rain_material.set_shader_parameter("rain_time", seconds)
	shadow_material.set_shader_parameter("cloud_time", seconds)
