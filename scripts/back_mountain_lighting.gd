extends Node

const CONFIG_PATH := "res://assets/data/back_mountain_lighting.json"
const CONTACT_SHADER_PATH := "res://assets/shaders/back_mountain_contact_shadow.gdshader"
const CLOUD_SHADER_PATH := "res://assets/shaders/back_mountain_cloud_shadow.gdshader"
const SCENE_PROFILE_KEYS := [
	"scene_brightness", "sun_energy", "sun_rotation", "shadow_opacity",
	"shadow_length", "mist_multiplier"
]
const COLOR_PROFILE_KEYS := ["ambient_tint", "sun_color"]

var enabled := true
var profiles: Dictionary = {}
var target_time_index := 0
var profile_index := 0
var current_profile: Dictionary = {}
var sun: DirectionalLight2D
var occluders: Array[LightOccluder2D] = []
var contact_shadows: Array[ColorRect] = []
var projected_shadows: Array[ColorRect] = []
var cloud_material: ShaderMaterial
var cloud_time := 0.0
var cloud_min_brightness := 0.88

var _game: Control
var _art_root: Control
var _foreground_layer: Control
var _near_layer: Control
var _times: Array[String] = []
var _shadow_config: Dictionary = {}
var _transition_duration := 1.05
var _transition_elapsed := 0.0
var _transition_from: Dictionary = {}
var _transition_to: Dictionary = {}
var _transitioning := false
var _training_pulse := 0.0
var _setup_done := false


func setup(game: Control) -> void:
	if _setup_done or game == null:
		return
	_game = game
	_art_root = game.get("_art_root") as Control
	_foreground_layer = game.get("_foreground_layer") as Control
	_near_layer = game.get("_near_layer") as Control
	if _art_root == null or _foreground_layer == null or _near_layer == null:
		push_error("BackMountainLighting requires the art root, foreground and near layers.")
		return

	var raw_config: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not raw_config is Dictionary:
		push_error("BackMountainLighting could not load its profile data.")
		return
	var config: Dictionary = raw_config
	profiles = config.get("profiles", {}).duplicate(true)
	_shadow_config = config.get("shadows", {}).duplicate(true)
	_transition_duration = maxf(0.01, float(config.get("transition_seconds", 1.05)))

	var cloud_config: Dictionary = config.get("cloud", {})
	cloud_min_brightness = clampf(float(cloud_config.get("min_brightness", 0.88)), 0.7, 1.0)
	_create_sun(int(_shadow_config.get("native_occluder_mask", 2)))
	_create_occluders()
	_create_contact_shadows()
	_create_projected_shadows()
	_create_cloud_overlay(cloud_config)
	_read_rule_times()
	_setup_done = true
	if not _times.is_empty():
		var state = _game.get("state")
		var initial_index := int(state.get("time_index")) if state != null else 0
		set_time_index(initial_index, false)
	else:
		push_warning("BackMountainLighting found no cultivation time profiles.")
	_set_effects_visible(enabled)
	if enabled and not current_profile.is_empty():
		_apply()


func set_enabled(value: bool) -> void:
	enabled = value
	if not _setup_done:
		return
	_set_effects_visible(enabled)
	if enabled:
		_snap_to_target()
		_apply()


func set_time_index(index: int, smooth: bool = false) -> void:
	if _times.is_empty():
		_read_rule_times()
	if _times.is_empty():
		return
	target_time_index = clampi(index, 0, _times.size() - 1)
	var target := _profile_at(target_time_index)
	if target.is_empty():
		return
	if not enabled:
		_transitioning = false
		current_profile = target.duplicate(true)
		profile_index = target_time_index
		return
	if current_profile.is_empty() or not smooth:
		_transitioning = false
		current_profile = target.duplicate(true)
		profile_index = target_time_index
		_apply()
		return
	if _transitioning and _profiles_equal(_transition_to, target):
		_apply()
		return
	if not _transitioning and _profiles_equal(current_profile, target):
		_apply()
		return
	_transition_from = current_profile.duplicate(true)
	_transition_to = target.duplicate(true)
	_transition_elapsed = 0.0
	_transitioning = true
	# refresh_environment first restores legacy colors; keep the old profile
	# on this very frame rather than showing a one-frame time-tint jump.
	_apply()


func advance(
	delta: float,
	presentation_seconds: float,
	motion_enabled: bool,
	training_progress: float = -1.0
) -> void:
	if not _setup_done or not enabled:
		return
	if _transitioning:
		_transition_elapsed = minf(_transition_elapsed + maxf(delta, 0.0), _transition_duration)
		var linear_weight := clampf(_transition_elapsed / _transition_duration, 0.0, 1.0)
		var weight := linear_weight * linear_weight * (3.0 - 2.0 * linear_weight)
		current_profile = _blend_profiles(_transition_from, _transition_to, weight)
		if _transition_elapsed >= _transition_duration:
			current_profile = _transition_to.duplicate(true)
			_transitioning = false
			profile_index = target_time_index
	if motion_enabled:
		cloud_time = maxf(presentation_seconds, 0.0)
		var distance := absf(training_progress - 0.5)
		_training_pulse = 0.025 * clampf(1.0 - distance / 0.06, 0.0, 1.0) if training_progress >= 0.0 else 0.0
	else:
		_training_pulse = 0.0
	if cloud_material != null:
		cloud_material.set_shader_parameter("cloud_time", cloud_time)
	_apply()


func finish_transition() -> void:
	if not _transitioning:
		return
	current_profile = _transition_to.duplicate(true)
	profile_index = target_time_index
	_transition_elapsed = _transition_duration
	_transitioning = false
	if enabled:
		_apply()


func _read_rule_times() -> void:
	_times.clear()
	if _game == null:
		return
	var state = _game.get("state")
	if state == null:
		return
	var rules: Dictionary = state.get("rules")
	for value in rules.get("times", []):
		_times.append(str(value))


func _profile_at(index: int) -> Dictionary:
	if _times.is_empty():
		return {}
	var profile: Variant = profiles.get(_times[clampi(index, 0, _times.size() - 1)], {})
	return profile.duplicate(true) if profile is Dictionary else {}


func _snap_to_target() -> void:
	_transitioning = false
	_transition_elapsed = 0.0
	current_profile = _profile_at(target_time_index)
	profile_index = target_time_index
	_training_pulse = 0.0


func _blend_profiles(from_profile: Dictionary, to_profile: Dictionary, weight: float) -> Dictionary:
	var blended: Dictionary = {}
	for key in SCENE_PROFILE_KEYS:
		blended[key] = lerpf(float(from_profile.get(key, to_profile.get(key, 0.0))), float(to_profile.get(key, 0.0)), weight)
	for key in COLOR_PROFILE_KEYS:
		var from_color := _as_color(from_profile.get(key, to_profile.get(key, "#ffffff")))
		var to_color := _as_color(to_profile.get(key, "#ffffff"))
		blended[key] = from_color.lerp(to_color, weight)
	return blended


func _profiles_equal(left: Dictionary, right: Dictionary) -> bool:
	for key in SCENE_PROFILE_KEYS:
		if not is_equal_approx(float(left.get(key, -1.0)), float(right.get(key, -1.0))):
			return false
	for key in COLOR_PROFILE_KEYS:
		if _as_color(left.get(key, "#000000")) != _as_color(right.get(key, "#000000")):
			return false
	return true


func _as_color(value: Variant) -> Color:
	return value if value is Color else Color(str(value))


func _create_sun(shadow_mask: int) -> void:
	sun = DirectionalLight2D.new()
	sun.name = "BackMountainSun"
	sun.blend_mode = Light2D.BLEND_MODE_ADD
	sun.shadow_enabled = true
	sun.shadow_filter = DirectionalLight2D.SHADOW_FILTER_PCF5
	sun.shadow_filter_smooth = 1.5
	sun.shadow_item_cull_mask = shadow_mask
	sun.range_layer_min = 1
	sun.range_layer_max = 1
	sun.energy = 0.055
	sun.color = Color("f3e4cf")
	sun.rotation = deg_to_rad(49.0)
	_art_root.add_child(sun)


func _create_occluders() -> void:
	var mask := int(_shadow_config.get("native_occluder_mask", 2))
	var actor_rect := _game_rect("actor_rect", Rect2(880.0, 260.0, 290.0, 290.0))
	var actor := _make_occluder("ActorSilhouetteOccluder", actor_rect.position, PackedVector2Array([
		Vector2(19, 276), Vector2(31, 169), Vector2(48, 82),
		Vector2(143, 5), Vector2(227, 39), Vector2(279, 119),
		Vector2(287, 190), Vector2(270, 248), Vector2(242, 283), Vector2(199, 270),
		Vector2(151, 286), Vector2(99, 280), Vector2(56, 288)
	]), mask)
	var sword_rect := _game_rect("sword_rect", Rect2(1145.0, 480.0, 200.0, 90.0))
	var sword := _make_occluder("SwordSilhouetteOccluder", sword_rect.position, PackedVector2Array([
		Vector2(22, 69), Vector2(201, 22), Vector2(211, 48), Vector2(27, 84)
	]), mask)
	occluders.append(actor)
	occluders.append(sword)


func _make_occluder(node_name: String, base_position: Vector2, polygon: PackedVector2Array, mask: int) -> LightOccluder2D:
	var node := LightOccluder2D.new()
	node.name = node_name
	node.position = base_position
	node.occluder = OccluderPolygon2D.new()
	node.occluder.polygon = polygon
	node.occluder_light_mask = mask
	_foreground_layer.add_child(node)
	return node


func _create_contact_shadows() -> void:
	var shader := load(CONTACT_SHADER_PATH) as Shader
	if shader == null:
		push_error("BackMountainLighting could not load the contact-shadow shader.")
		return
	var contact_color := Color(str(_shadow_config.get("contact_color", "#665d53")))
	var specs := [
		{"name": "ActorContactShadow", "rect": _rect_data("actor_contact_rect", [925, 523, 225, 29]), "opacity": 0.30, "softness": 0.78, "irregularity": 0.045},
		{"name": "SwordContactShadow", "rect": _rect_data("sword_contact_rect", [1150, 523, 185, 15]), "opacity": 0.23, "softness": 0.64, "irregularity": 0.055},
		{"name": "LedgeContactShadow", "rect": _rect_data("ledge_contact_rect", [420, 489, 140, 18]), "opacity": 0.17, "softness": 0.82, "irregularity": 0.11}
	]
	for spec in specs:
		var shadow := ColorRect.new()
		shadow.name = str(spec.name)
		shadow.color = Color.WHITE
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(shadow, spec.rect)
		shadow.z_index = -1
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("shadow_color", contact_color)
		material.set_shader_parameter("opacity", float(spec.opacity))
		material.set_shader_parameter("softness", float(spec.softness))
		material.set_shader_parameter("irregularity", float(spec.irregularity))
		shadow.material = material
		if shadow.name == "SwordContactShadow":
			shadow.pivot_offset = shadow.size * 0.5
			shadow.rotation = deg_to_rad(-18.0)
		_foreground_layer.add_child(shadow)
		contact_shadows.append(shadow)


func _create_projected_shadows() -> void:
	var shader := load(CONTACT_SHADER_PATH) as Shader
	if shader == null:
		return
	var shadow_color := Color(str(_shadow_config.get("projected_color", "#625a51")))
	var specs := [
		{"name": "ActorProjectedShadow", "rect": _rect_data("actor_projected_rect", [980, 536, 78, 16]), "opacity": 0.16, "softness": 1.38},
		{"name": "SwordProjectedShadow", "rect": _rect_data("sword_projected_rect", [1200, 529, 46, 12]), "opacity": 0.11, "softness": 1.3}
	]
	for spec in specs:
		var shadow := ColorRect.new()
		shadow.name = str(spec.name)
		shadow.color = Color.WHITE
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_rect(shadow, spec.rect)
		shadow.pivot_offset = shadow.size * 0.5
		shadow.rotation = deg_to_rad(float(_shadow_config.get("projected_rotation_degrees", 135.0)))
		shadow.z_index = -2
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("shadow_color", shadow_color)
		material.set_shader_parameter("opacity", float(spec.opacity))
		material.set_shader_parameter("softness", float(spec.softness))
		material.set_shader_parameter("irregularity", 0.035)
		material.set_shader_parameter("lobe_offset", 0.1)
		shadow.material = material
		_foreground_layer.add_child(shadow)
		projected_shadows.append(shadow)


func _create_cloud_overlay(cloud_config: Dictionary) -> void:
	var shader := load(CLOUD_SHADER_PATH) as Shader
	if shader == null:
		push_error("BackMountainLighting could not load the cloud-shadow shader.")
		return
	var width := maxi(16, int(cloud_config.get("noise_size", 128)))
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = float(cloud_config.get("noise_frequency", 0.006))
	noise.fractal_octaves = 2
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.42
	var noise_texture := NoiseTexture2D.new()
	noise_texture.width = width
	noise_texture.height = width
	noise_texture.seamless = true
	noise_texture.normalize = true
	noise_texture.noise = noise
	var overlay := ColorRect.new()
	overlay.name = "BackMountainCloudShadow"
	overlay.color = Color.WHITE
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.position = Vector2.ZERO
	overlay.size = _art_root.size
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 40
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = shader
	cloud_material.set_shader_parameter("cloud_noise", noise_texture)
	cloud_material.set_shader_parameter("cloud_time", cloud_time)
	cloud_material.set_shader_parameter("cloud_min_brightness", cloud_min_brightness)
	cloud_material.set_shader_parameter("envelope_seconds", float(cloud_config.get("envelope_seconds", 16.0)))
	cloud_material.set_shader_parameter("drift_rate", Vector2(cloud_config.get("drift_rate", [0.00065, 0.00022])[0], cloud_config.get("drift_rate", [0.00065, 0.00022])[1]))
	overlay.material = cloud_material
	_art_root.add_child(overlay)
	cloud_material.set_meta("overlay_node", overlay)


func _set_effects_visible(value: bool) -> void:
	if sun != null:
		sun.enabled = value
		sun.visible = value
	for occluder in occluders:
		occluder.visible = value
	for shadow in contact_shadows:
		shadow.visible = value
	for shadow in projected_shadows:
		shadow.visible = value
	if cloud_material != null:
		var overlay: ColorRect = cloud_material.get_meta("overlay_node") as ColorRect
		if overlay != null:
			overlay.visible = value


func _apply() -> void:
	if not enabled or current_profile.is_empty():
		return
	var ambient := _as_color(current_profile.get("ambient_tint", "#ffffff"))
	var brightness := float(current_profile.get("scene_brightness", 1.0)) + _training_pulse
	var tint := Color(ambient.r * brightness, ambient.g * brightness, ambient.b * brightness, 1.0)
	var art_nodes: Array = _game.get("_art_nodes")
	for art_node in art_nodes:
		if art_node is CanvasItem and is_instance_valid(art_node):
			art_node.modulate = tint
	var flow_material = _game.get("_waterfall_material")
	if flow_material is ShaderMaterial:
		var flow_tint := Color("e2e9e3")
		flow_material.set_shader_parameter("flow_tint", Color(flow_tint.r * tint.r, flow_tint.g * tint.g, flow_tint.b * tint.b, 1.0))
	var leaves: Array = _game.get("_leaf_nodes")
	for leaf in leaves:
		if leaf is CanvasItem and is_instance_valid(leaf):
			leaf.modulate = tint
	var default_density := float(_game.get("config").get("mist_density", 0.12))
	var mist_density := default_density * float(current_profile.get("mist_multiplier", 1.0))
	var mist_materials: Array = _game.get("_mist_materials")
	for i in mist_materials.size():
		var material = mist_materials[i]
		if material is ShaderMaterial:
			var layer_factors: Array = _game.get("config").get("mist_layer_factors", [0.72, 0.48])
			var factor := float(layer_factors[i]) if i < layer_factors.size() else 1.0
			var mist_tint := Color("dfe7e2")
			material.set_shader_parameter("mist_tint", Color(mist_tint.r * tint.r, mist_tint.g * tint.g, mist_tint.b * tint.b, 1.0))
			material.set_shader_parameter("mist_density", mist_density * factor)
	if sun != null:
		sun.color = _as_color(current_profile.get("sun_color", "#ffffff"))
		sun.energy = float(current_profile.get("sun_energy", 0.055))
		sun.rotation = deg_to_rad(float(current_profile.get("sun_rotation", 45.0)))
		var shadow_color := Color("665d53")
		shadow_color.a = clampf(float(current_profile.get("shadow_opacity", 0.1)) * 0.45, 0.02, 0.08)
		sun.shadow_color = shadow_color
	var shadow_opacity := float(current_profile.get("shadow_opacity", 0.1))
	var shadow_length := float(current_profile.get("shadow_length", 30.0))
	for shadow in contact_shadows:
		var material := shadow.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("opacity", maxf(shadow_opacity, 0.085) * (1.5 if shadow.name == "ActorContactShadow" else 1.0))
	for shadow in projected_shadows:
		var material := shadow.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("opacity", shadow_opacity * (0.9 if shadow.name == "ActorProjectedShadow" else 0.72))
			var base_length := 38.0 if shadow.name == "ActorProjectedShadow" else 28.0
			shadow.scale.x = maxf(0.18, shadow_length / base_length)
			var ray_rotation := deg_to_rad(float(current_profile.get("sun_rotation", 45.0)))
			var ray := Vector2(-sin(ray_rotation), cos(ray_rotation))
			shadow.rotation = ray.angle()
			var anchor := Vector2(1037, 536) if shadow.name == "ActorProjectedShadow" else Vector2(1230, 530)
			shadow.position = anchor + ray * shadow_length * 0.4 - shadow.pivot_offset


func _game_rect(key: String, fallback: Rect2) -> Rect2:
	var config = _game.get("config")
	var value: Variant = config.get(key, [fallback.position.x, fallback.position.y, fallback.size.x, fallback.size.y])
	return _rect_from_array(value, fallback)


func _rect_data(key: String, fallback: Array) -> Rect2:
	return _rect_from_array(_shadow_config.get(key, fallback), Rect2(float(fallback[0]), float(fallback[1]), float(fallback[2]), float(fallback[3])))


func _rect_from_array(value: Variant, fallback: Rect2) -> Rect2:
	if not value is Array or value.size() < 4:
		return fallback
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
