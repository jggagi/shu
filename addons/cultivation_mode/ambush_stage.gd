extends Control
## Orthographic combat presentation with a stable tactical view and local action focus.
## Authored Songfeng layout, open nature assets and original combat effects.

signal tile_clicked(tile: Array)
signal tile_hovered(tile: Array)
signal feedback_changed(text: String, tone: String)
signal cancel_action_requested

const StaffMotion = preload("res://addons/cultivation_mode/ambush_staff_motion.gd")
const Actor = preload("res://addons/cultivation_mode/ambush_actor.gd")
const Landscape = preload("res://addons/cultivation_mode/ambush_environment.gd")
const LIGHTING_PATH := "res://assets/art/mountain_ambush/environment/lighting.json"
const CombatLightScript = preload("res://addons/cultivation_mode/ambush_combat_light.gd")
const SkillFxScript = preload("res://addons/cultivation_mode/ambush_skill_fx.gd")
const PalmVfxScript = preload("res://addons/cultivation_mode/ambush_palm_vfx.gd")
const PalmImpactScript = preload("res://addons/cultivation_mode/ambush_palm_impact.gd")
const MoveCatalog = preload("res://addons/cultivation_mode/martial_move_catalog.gd")
const MovePlayer = preload("res://addons/cultivation_mode/martial_move_player.gd")
const CELL: float = 1.15
## Local combat presentation only. Source poses, walking and the host clock retain their units.
const ACTION_PLAYBACK_SPEED: float = 0.65
const ATTACK_TIMING := {"ready_seconds": 0.24, "strike_seconds": 0.10,
	"hit_stop_seconds": 0.08, "follow_through_seconds": 0.13, "recover_seconds": 0.30,
	"hit_at_seconds": 0.34, "total_seconds": 0.85, "source_hit_seconds": 0.13}
const CAMERA_HOME := Vector3(8.0, 10.8, 14.8)
const CAMERA_TARGET := Vector3(0, 0.70, -0.30)
const CAMERA_YAW_LIMITS := Vector2(-32.0, 32.0)
const CAMERA_PITCH_LIMITS := Vector2(-10.0, 12.0)
const CAMERA_ZOOM_LIMITS := Vector2(0.82, 1.20)
const CAMERA_DRAG_THRESHOLD := 6.0
const CAMERA_DRAG_SENSITIVITY := Vector2(0.22, 0.18)
var viewport: SubViewport
var camera: Camera3D
var world_root: Node3D
var actor_nodes: Dictionary = {}
var barricade_nodes: Dictionary = {}
var _texture: TextureRect
var _font: Font
var _definition: Dictionary = {}
var _state: Dictionary = {}
var _selected: String = ""
var _width: int = 9
var _height: int = 7
var _materials: Dictionary = {}
var _tile_meshes: Dictionary = {}
var _tile_borders: Dictionary = {}
var _hover: Array = []
var _events: Array = []
var _animating: bool = false
var _objective: Node3D
var _selection: MeshInstance3D
var _reach: Array = []
var _preview: Dictionary = {}
var _initialized: bool = false
var _presentation_phase: String = "idle"
var _active_event: Dictionary = {}
var _feedback_history: Array[Dictionary] = []
var _active_attack_cells: Array = []
var _objective_warning: MeshInstance3D
var _danger_cells: Array = []
var _objective_threat_count: int = 0
var _resolved_plans: Array = []
var _floating_feedback: Array[Dictionary] = []
var _landscape: Node3D
var _lighting_profiles: Dictionary = {}
var _enhanced_lighting := true
var _environment: Environment
var _sun: DirectionalLight3D
var _sky_fill: DirectionalLight3D
var _combat_light: Node3D
var _skill_fx: Node3D
var _skill_actor: Node3D
var _palm_vfx: Node3D
var _palm_impact: Node3D
var _light_preview_zoom := 1.0
var _camera_home_transform := Transform3D.IDENTITY
var _camera_yaw := 0.0
var _camera_pitch := 0.0
var _camera_zoom := 1.0
var _camera_input_enabled := true
var _camera_drag_button := 0
var _camera_drag_origin := Vector2.ZERO
var _camera_drag_last := Vector2.ZERO
var _camera_dragging := false
var _action_camera_blend := 0.0
var _action_camera_focus := Vector3.ZERO
var _action_camera_tween: Tween
var _move_catalog: Dictionary = {}
var _move_player := MovePlayer.new()
var _workshop_mode := false
var _workshop_camera := "close"
var _workshop_selected := ""
var _workshop_variant := "original"
var _workshop_token := 0
var _workshop_actor: Node3D
var _workshop_transform := Transform3D.IDENTITY
var _workshop_visibility := {}
var _unified_combat_count := 0
var _combat_presentation: Dictionary = {}
var _combat_pending_impacts: Array[Dictionary] = []
var _combat_contact_presented := false
var _combat_pushes: Array[Dictionary] = []
var _staff_attack_actor: Node3D
var _staff_attack_elapsed := 0.0
var _staff_attack_active := false
var _staff_contact_samples := 0
var _staff_attack_context: Dictionary = {}
var _refined_details := true
var _detail_input_enabled := true

func setup(definition: Dictionary, font: Font) -> void:
	_definition = definition.duplicate(true)
	_move_player.impact_reached.connect(_on_recipe_impact)
	# Sample weapon anchors after the actors have advanced their bone poses.
	process_priority = 10
	_font = font if font != null else ThemeDB.fallback_font
	_width = int(_definition.get("width", 9))
	_height = int(_definition.get("height", 7))
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	viewport = SubViewport.new()
	viewport.name = "AmbushWorldViewport"
	viewport.size = Vector2i(1000, 650)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.positional_shadow_atlas_size = 1024
	add_child(viewport)
	_texture = TextureRect.new()
	_texture.name = "BattlePainting"
	_texture.texture = viewport.get_texture()
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_texture)
	# The overlay must draw above the texture; _draw itself is below children.
	var overlay: Control = Control.new()
	overlay.name = "NamesAndHealth"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	overlay.draw.connect(_draw_labels.bind(overlay))
	world_root = Node3D.new()
	world_root.name = "MountainRoad"
	viewport.add_child(world_root)
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = Environment.new()
	_environment = world_environment.environment
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("#cbd5cc")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_environment.fog_enabled = true
	_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_environment.fog_light_color = Color("#b6c8c7")
	_environment.fog_light_energy = 0.65
	_environment.fog_depth_begin = 24.0
	_environment.fog_depth_end = 54.0
	_environment.fog_depth_curve = 1.4
	_environment.fog_sky_affect = 0.0
	world_root.add_child(world_environment)
	_sun = DirectionalLight3D.new()
	_sun.name = "LateMorningLight"
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	world_root.add_child(_sun)
	_sky_fill = DirectionalLight3D.new()
	_sky_fill.name = "CoolSkyFill"
	_sky_fill.shadow_enabled = false
	world_root.add_child(_sky_fill)
	var lighting_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIGHTING_PATH))
	if not lighting_data is Dictionary or not lighting_data.has("original") or not lighting_data.has("enhanced"):
		push_error("Songfeng lighting profiles are missing or invalid")
		return
	_lighting_profiles = lighting_data
	set_enhanced_lighting(true)
	camera = Camera3D.new()
	camera.name = "FixedBattleCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.05
	camera.far = 80.0
	camera.position = CAMERA_HOME
	world_root.add_child(camera)
	camera.look_at(CAMERA_TARGET)
	_camera_home_transform = camera.transform
	camera.current = true
	_landscape = Landscape.new()
	world_root.add_child(_landscape)
	var landscape_result: Dictionary = _landscape.call("setup", _width, _height, CELL)
	if not bool(landscape_result.get("ok", false)):
		push_error("Songfeng environment setup failed; inspect the missing asset or layout error above")
	_build_board()
	_landscape.call("bind_scene_details", world_root)
	_build_barricades()
	_build_objective()
	_combat_light = CombatLightScript.new() as Node3D
	_combat_light.name = "CombatLightExperiment"
	world_root.add_child(_combat_light)
	_combat_light.call("setup", _environment, _sun, _sky_fill)
	_combat_light.set("action_playback_speed", ACTION_PLAYBACK_SPEED)
	_combat_light.set("windup_wall_seconds", float(ATTACK_TIMING.hit_at_seconds))
	_combat_light.set("recovery_wall_seconds", float(ATTACK_TIMING.recover_seconds))
	_skill_fx = SkillFxScript.new() as Node3D
	_skill_fx.name = "MartialSkillEffects"
	world_root.add_child(_skill_fx)
	var skill_fx_result: Dictionary = _skill_fx.call("setup", false, -10.0)
	if not bool(skill_fx_result.get("ok", false)):
		push_error("Martial skill effects setup failed: " + str(skill_fx_result.get("reason", "")))
	_palm_vfx = PalmVfxScript.new() as Node3D
	_palm_vfx.name = "PalmWindSample"
	world_root.add_child(_palm_vfx)
	var palm_result: Dictionary = _palm_vfx.call("setup")
	if not bool(palm_result.get("ok", false)):
		push_error("Palm-wind assets failed: " + str(palm_result.get("reason", "")))
	_palm_impact = PalmImpactScript.new() as Node3D
	_palm_impact.name = "PalmImpactSample"
	world_root.add_child(_palm_impact)
	var impact_result: Dictionary = _palm_impact.call("setup")
	if not bool(impact_result.get("ok", false)):
		push_error("Palm impact setup failed: " + str(impact_result.get("reason", "")))
	_objective_warning = _ring(world_root, _objective.position + Vector3.UP * 0.06, 0.62, Color("#bd6549"))
	_objective_warning.visible = false
	_selection = _ring(world_root, Vector3.ZERO, 0.36, Color("#e8cb7e"))
	_selection.visible = false
	resized.connect(_resize)
	mouse_exited.connect(_on_mouse_exited)
	_initialized = true
	_resize()

func set_enhanced_lighting(enabled: bool) -> void:
	if _animating:
		return
	_enhanced_lighting = enabled
	if _lighting_profiles.is_empty() or not is_instance_valid(_sun):
		return
	var row: Dictionary = _lighting_profiles["enhanced" if enabled else "original"]
	_environment.ambient_light_color = Color(str(row.ambient.color))
	_environment.ambient_light_energy = float(row.ambient.energy)
	_environment.ssao_enabled = bool(row.ssao.enabled)
	_environment.ssao_radius = float(row.ssao.radius)
	_environment.ssao_intensity = float(row.ssao.intensity)
	_sun.rotation_degrees = _lighting_rotation(row.sun.rotation)
	_sun.light_color = Color(str(row.sun.color))
	_sun.light_energy = float(row.sun.energy)
	_sun.directional_shadow_max_distance = float(row.sun.shadow_distance)
	_sun.directional_shadow_fade_start = float(row.sun.shadow_fade_start)
	_sun.shadow_bias = float(row.sun.shadow_bias)
	_sun.shadow_normal_bias = float(row.sun.shadow_normal_bias)
	_sky_fill.rotation_degrees = _lighting_rotation(row.fill.rotation)
	_sky_fill.light_color = Color(str(row.fill.color))
	_sky_fill.light_energy = float(row.fill.energy)
	_sky_fill.visible = bool(row.fill.enabled)

func _lighting_rotation(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func lighting_audit() -> Dictionary:
	return {"enhanced": _enhanced_lighting, "profile": "enhanced" if _enhanced_lighting else "original",
		"ambient": {"color": _environment.ambient_light_color.to_html(), "energy": _environment.ambient_light_energy},
		"sun": {"color": _sun.light_color.to_html(), "energy": _sun.light_energy, "rotation": _sun.rotation_degrees,
			"shadow_enabled": _sun.shadow_enabled, "shadow_distance": _sun.directional_shadow_max_distance,
			"shadow_fade_start": _sun.directional_shadow_fade_start, "shadow_bias": _sun.shadow_bias, "shadow_normal_bias": _sun.shadow_normal_bias},
		"ssao": {"enabled": _environment.ssao_enabled, "radius": _environment.ssao_radius, "intensity": _environment.ssao_intensity},
		"fill": {"enabled": _sky_fill.visible, "color": _sky_fill.light_color.to_html(), "energy": _sky_fill.light_energy,
			"shadow_enabled": _sky_fill.shadow_enabled}}

func _resize() -> void:
	if not is_instance_valid(viewport):
		return
	viewport.size = Vector2i(maxi(320, roundi(size.x)), maxi(240, roundi(size.y)))
	var aspect: float = float(viewport.size.x) / float(viewport.size.y)
	camera.size = maxf(float(_height) * CELL * 0.62 + 2.30, (float(_width) * CELL + 1.2) / aspect) * _camera_zoom * _light_preview_zoom * lerpf(1.0, 0.88, _action_camera_blend)
	camera.transform = _user_camera_transform()
	var shift := Vector3(clampf(_action_camera_focus.x, -2.5, 2.5), 0, clampf(_action_camera_focus.z, -2.0, 2.0))
	camera.position += shift * _action_camera_blend * 0.42
	if _workshop_mode:
		_apply_workshop_camera()
	queue_redraw()

func set_detail_input_enabled(enabled: bool) -> void:
	_detail_input_enabled = enabled

func set_refined_details(enabled: bool) -> bool:
	if _animating or _workshop_mode or not _detail_input_enabled:
		return false
	_refined_details = enabled
	for actor: Node3D in actor_nodes.values():
		actor.call("set_refined_details", enabled)
	if is_instance_valid(_landscape):
		_landscape.call("set_refined_details", enabled)
	return true

func detail_audit() -> Dictionary:
	var actors := {}
	for id: String in actor_nodes:
		actors[id] = (actor_nodes[id] as Node3D).call("detail_audit")
	return {"enabled": _refined_details, "input_enabled": _detail_input_enabled and not _animating and not _workshop_mode,
		"actors": actors, "environment": _landscape.call("detail_audit") if is_instance_valid(_landscape) else {},
		"authority": "presentation only"}

func _material(hex: String, grain: bool = false) -> StandardMaterial3D:
	var key: String = hex + (":grain" if grain else "")
	if _materials.has(key):
		return _materials[key]
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(hex)
	mat.roughness = 0.98
	if grain:
		var image: Image = Image.create(48, 48, false, Image.FORMAT_RGB8)
		for y: int in range(48):
			for x: int in range(48):
				var value: float = 0.975 + float((x * 17 + y * 11 + x * y * 3) % 23) / 920.0
				image.set_pixel(x, y, Color(value, value, value))
		image.generate_mipmaps()
		mat.albedo_texture = ImageTexture.create_from_image(image)
		mat.uv1_scale = Vector3(5, 5, 1)
	_materials[key] = mat
	return mat

func _overlay_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _mesh(parent: Node3D, resource: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = resource
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node

func _box(parent: Node3D, at: Vector3, dimensions: Vector3, mat: Material) -> MeshInstance3D:
	var resource: BoxMesh = BoxMesh.new()
	resource.size = dimensions
	return _mesh(parent, resource, at, mat)

func _sphere(parent: Node3D, at: Vector3, radii: Vector3, mat: Material) -> MeshInstance3D:
	var resource: SphereMesh = SphereMesh.new()
	resource.radius = 1.0
	resource.height = 2.0
	resource.radial_segments = 10
	resource.rings = 5
	var node: MeshInstance3D = _mesh(parent, resource, at, mat)
	node.scale = radii
	return node

func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, mat: Material, taper: float = 1.0) -> MeshInstance3D:
	var resource: CylinderMesh = CylinderMesh.new()
	resource.bottom_radius = radius
	resource.top_radius = radius * taper
	resource.height = height
	resource.radial_segments = 12
	return _mesh(parent, resource, at, mat)

func _beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var node: MeshInstance3D = _cylinder(parent, (a + b) * 0.5, radius, a.distance_to(b), mat)
	node.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return node

func _plane(parent: Node3D, at: Vector3, dimensions: Vector2, mat: Material) -> MeshInstance3D:
	var resource: PlaneMesh = PlaneMesh.new()
	resource.size = dimensions
	var node: MeshInstance3D = _mesh(parent, resource, at, mat)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _ring(parent: Node3D, at: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var resource: TorusMesh = TorusMesh.new()
	resource.inner_radius = radius - 0.018
	resource.outer_radius = radius + 0.018
	resource.rings = 28
	resource.ring_segments = 5
	var node: MeshInstance3D = _mesh(parent, resource, at + Vector3.UP * 0.055, _overlay_material(color))
	node.scale.y = 0.16
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _tile_world(tile: Array, height: float = 0.0) -> Vector3:
	if tile.size() < 2:
		return Vector3.ZERO
	return Vector3((float(tile[0]) - float(_width - 1) * 0.5) * CELL, height, (float(tile[1]) - float(_height - 1) * 0.5) * CELL)

func _key(tile: Array) -> String:
	return str(int(tile[0])) + ":" + str(int(tile[1])) if tile.size() > 1 else ""

func _build_terrain() -> void:
	_plane(world_root, Vector3(0, -0.28, -1.5), Vector2(50, 42), _material("#acb7a0", true))
	var width: float = float(_width) * CELL
	var depth: float = float(_height) * CELL
	_plane(world_root, Vector3(0, 0.003, 0), Vector2(width + 1.7, 28.0), _material("#b9b49d", true))
	# Irregular shoulders blend the broad mountain path into the vegetation.
	for i: int in range(35):
		var side: float = -1.0 if i % 2 else 1.0
		var z: float = -depth * 0.64 + float(i / 2) * depth / 13.0
		var x: float = side * (width * 0.5 + 0.65 + float(i % 4) * 0.12)
		_sphere(world_root, Vector3(x, -0.10, z), Vector3(0.50, 0.19, 0.44), _material(["#a6ad91", "#b1b499", "#a0a78d"][i % 3], true))
	# Small embedded road stones; none imply an undeclared impassable object.
	for i: int in range(50):
		var x: float = sin(float(i) * 5.2) * (width * 0.48)
		var z: float = cos(float(i) * 3.7) * (depth * 0.48)
		var stone: MeshInstance3D = _sphere(world_root, Vector3(x, 0.006, z), Vector3(0.045 + float(i % 3) * 0.012, 0.012, 0.027), _material("#a9a48a"))
		stone.rotation.y = float(i) * 0.71

func _build_board() -> void:
	var border_mat: StandardMaterial3D = _overlay_material(Color(0.36, 0.38, 0.30, 0.24))
	for y: int in range(_height):
		for x: int in range(_width):
			var tile: Array = [x, y]
			var key: String = _key(tile)
			var at: Vector3 = _tile_world(tile, 0.023)
			var fill: MeshInstance3D = _plane(world_root, at, Vector2.ONE * (CELL - 0.035), _overlay_material(Color(0.9, 0.85, 0.67, 0.035)))
			_tile_meshes[key] = fill
			var edges: Array = []
			for side: int in [-1, 1]:
				edges.append(_plane(world_root, at + Vector3(side * CELL * 0.5, 0.006, 0), Vector2(0.012, CELL), border_mat))
				edges.append(_plane(world_root, at + Vector3(0, 0.006, side * CELL * 0.5), Vector2(CELL, 0.012), border_mat))
			_tile_borders[key] = edges
	var obstacles: Array = _definition.get("obstacles", [])
	for i: int in range(obstacles.size()):
		var tile: Array = obstacles[i]
		var at: Vector3 = _tile_world(tile)
		var rock: Node3D = (load(Landscape.ROCK_PATHS[i % 2]) as PackedScene).instantiate() as Node3D
		rock.name = "DeclaredObstacle" + str(i)
		rock.position = at
		rock.rotation.y = float(i) * 1.7
		world_root.add_child(rock)
		for n: int in range(3):
			_grass(at + Vector3(-0.29 + float(n) * 0.24, 0.02, 0.35), n)

func _build_barricades() -> void:
	var timber := _material("#8b6341")
	var cut_wood := _material("#b49265")
	var rope := _material("#514e38")
	for row: Dictionary in _definition.get("barricades", []):
		var gate := Node3D.new()
		gate.name = "Barricade_" + str(row.id)
		gate.position = _tile_world(row.pos)
		world_root.add_child(gate)
		var standing := Node3D.new()
		standing.name = "Standing"
		gate.add_child(standing)
		for side: int in [-1, 1]:
			_box(standing, Vector3(0, 0.37, float(side) * 0.42), Vector3(0.13, 0.74, 0.13), timber)
			_cylinder(standing, Vector3(0, 0.75, float(side) * 0.42), 0.065, 0.035, cut_wood)
		for index: int in range(5):
			var slat := _box(standing, Vector3(0.035, 0.40, float(index - 2) * 0.17), Vector3(0.065, 0.65 + float(index % 2) * 0.05, 0.13), timber)
			slat.rotation.x = float(index - 2) * 0.015
		for height: float in [0.25, 0.58]:
			_box(standing, Vector3(-0.035, height, 0), Vector3(0.10, 0.075, 0.98), cut_wood)
		_beam(standing, Vector3(-0.095, 0.15, -0.36), Vector3(-0.095, 0.65, 0.36), 0.026, rope)
		var broken := Node3D.new()
		broken.name = "Broken"
		broken.visible = false
		gate.add_child(broken)
		# Broken pieces are below the tactical overlay plane and never block a cell.
		for index: int in range(5):
			var piece := _box(broken, Vector3(float(index % 2) * 0.21 - 0.11, 0.006, float(index - 2) * 0.15), Vector3(0.48 + float(index % 3) * 0.10, 0.012, 0.075), cut_wood)
			piece.rotation.y = float(index) * 0.81 - 0.7
		barricade_nodes[str(row.id)] = gate

func _sync_barricades() -> void:
	for row: Dictionary in _state.get("barricades", []):
		var gate: Node3D = barricade_nodes.get(str(row.id)) as Node3D
		if gate == null:
			continue
		var intact: bool = int(row.hp) > 0
		var standing: Node3D = gate.get_node("Standing") as Node3D
		standing.visible = intact
		standing.rotation = Vector3.ZERO
		standing.scale = Vector3.ONE
		(gate.get_node("Broken") as Node3D).visible = not intact

func _barricade_audit() -> Array:
	var result: Array = []
	for row: Dictionary in _state.get("barricades", []):
		var gate: Node3D = barricade_nodes.get(str(row.id)) as Node3D
		result.append({"id": str(row.id), "pos": row.pos.duplicate(), "hp": int(row.hp), "alive": int(row.hp) > 0,
			"standing_visible": gate != null and (gate.get_node("Standing") as Node3D).visible,
			"broken_visible": gate != null and (gate.get_node("Broken") as Node3D).visible,
			"body_screen": _world_to_screen(gate.position + Vector3.UP * 0.45) if gate != null else Vector2.ZERO})
	return result

func _rock(at: Vector3, radii: Vector3, seed_value: int) -> void:
	var rock: MeshInstance3D = _sphere(world_root, at, radii, _material(["#8a9588", "#a2a994", "#b2b09a"][posmod(seed_value, 3)], true))
	rock.rotation = Vector3(0.14 * float(seed_value % 3), float(seed_value) * 0.77, 0.11)
	var moss: MeshInstance3D = _sphere(world_root, at + Vector3(-radii.x * 0.16, radii.y * 0.70, -radii.z * 0.1), radii * Vector3(0.61, 0.09, 0.57), _material("#8a9a76"))
	moss.rotation.y = float(seed_value) * 0.77

func _grass(at: Vector3, seed_value: int) -> void:
	for i: int in range(3):
		var offset: float = (float(i) - 1.0) * 0.065
		_beam(world_root, at + Vector3(offset, 0, 0), at + Vector3(offset * 1.9, 0.16 + float((seed_value + i) % 3) * 0.06, 0.035), 0.012, _material("#8f9b70"))

func _build_landscape() -> void:
	var width: float = float(_width) * CELL
	var depth: float = float(_height) * CELL
	# Three distant silhouettes use progressively paler stone, rather than
	# heavy fog/postprocessing that would change Compatibility behaviour.
	for layer: int in range(3):
		for i: int in range(8):
			var x: float = -21.0 + float(i) * 5.2 + float(layer) * 0.9
			var mountain: SphereMesh = SphereMesh.new()
			mountain.radius = 1.0
			mountain.height = 2.0
			mountain.radial_segments = 12
			mountain.rings = 5
			var node: MeshInstance3D = _mesh(world_root, mountain, Vector3(x, -0.8, -6.5 - float(layer) * 1.2), _material(["#93a396", "#a6b3a4", "#bcc6b7"][layer]))
			node.scale = Vector3(3.4 + float(i % 3) * 0.45, 1.6 + float((i + layer) % 4) * 0.25, 1.2)
			node.rotation.y = float(i % 3) * 0.31
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for row: Array in [[-width * 0.5 - 1.0, -depth * 0.5 - 0.8, 3.9, 2], [width * 0.5 + 1.2, -depth * 0.5 - 0.1, 4.0, 5], [-width * 0.5 - 1.45, depth * 0.5 - 0.7, 2.9, 7], [width * 0.5 + 1.9, depth * 0.5 + 0.7, 3.7, 9]]:
		_pine(Vector3(float(row[0]), 0, float(row[1])), float(row[2]), int(row[3]))
	# A low roadside timber rail frames the path without hiding any tile.
	for i: int in range(7):
		var at: Vector3 = Vector3(width * 0.5 + 0.93, 0, -depth * 0.5 + float(i) * 1.13)
		_beam(world_root, at, at + Vector3(0.02, 0.70, 0), 0.055, _material("#887257", true))
		if i < 6:
			_beam(world_root, at + Vector3(0, 0.52, 0), at + Vector3(0, 0.55, 1.13), 0.045, _material("#927b5b", true))
	for i: int in range(13):
		var side: float = -1.0 if i % 2 else 1.0
		var at: Vector3 = Vector3(side * (width * 0.5 + 0.8), 0.25, -depth * 0.5 + float(i / 2) * 1.1)
		_rock(at, Vector3(0.35, 0.29, 0.32), i)
		_grass(at + Vector3(0.25, -0.22, 0.3), i)

func _pine(at: Vector3, height: float, seed_value: int) -> void:
	var tree: Node3D = Node3D.new()
	tree.position = at
	world_root.add_child(tree)
	var trunk: Material = _material("#796a53", true)
	_beam(tree, Vector3.ZERO, Vector3(0.13, height * 0.88, -0.07), 0.095, trunk)
	for i: int in range(6):
		var angle: float = float(i) * 2.28 + float(seed_value)
		var reach: float = 0.54 + float(i % 3) * 0.27
		var start: Vector3 = Vector3(0.04, height * (0.38 + float(i) * 0.075), 0)
		var end: Vector3 = start + Vector3(cos(angle) * reach, 0.20 + float(i % 2) * 0.10, sin(angle) * reach)
		_beam(tree, start, end, 0.037, trunk)
		for lobe: int in range(3):
			var p: Vector3 = end + Vector3(cos(angle + float(lobe)) * 0.24, float(lobe % 2) * 0.10, sin(angle + float(lobe)) * 0.24)
			_sphere(tree, p, Vector3(0.61, 0.18, 0.48), _material(["#647e68", "#768c70", "#899978"][(i + lobe) % 3], true))
	_sphere(tree, Vector3(0.13, height * 0.91, -0.07), Vector3(0.42, 0.22, 0.39), _material("#7f9271", true))

func _build_objective() -> void:
	var objective: Dictionary = _definition.get("objective", {})
	var tile: Array = objective.get("pos", [4, 2])
	_objective = Node3D.new()
	_objective.name = "HerbCart"
	_objective.position = _tile_world(tile)
	world_root.add_child(_objective)
	var wood: Material = _material("#9c7f59", true)
	var dark: Material = _material("#6b5b46", true)
	_box(_objective, Vector3(0, 0.35, 0), Vector3(0.61, 0.09, 0.74), wood)
	for side: int in [-1, 1]:
		var wheel: MeshInstance3D = _cylinder(_objective, Vector3(side * 0.35, 0.24, 0), 0.245, 0.045, dark)
		wheel.rotation.z = PI * 0.5
		var rim: MeshInstance3D = _ring(_objective, Vector3(side * 0.35, 0.185, 0), 0.21, Color("#b69c6f"))
		rim.rotation.z = PI * 0.5
		for spoke: int in range(6):
			var angle: float = float(spoke) * PI / 3.0
			_beam(_objective, Vector3(side * 0.376, 0.24, 0), Vector3(side * 0.376, 0.24 + cos(angle) * 0.22, sin(angle) * 0.22), 0.013, wood)
		_beam(_objective, Vector3(side * 0.20, 0.35, 0.30), Vector3(side * 0.20, 0.26, 0.78), 0.023, dark)
		_box(_objective, Vector3(side * 0.28, 0.45, 0), Vector3(0.04, 0.16, 0.72), wood)
	for i: int in range(3):
		var at: Vector3 = Vector3(-0.16 + float(i % 2) * 0.28, 0.52, -0.20 + float(i / 2) * 0.31)
		_cylinder(_objective, at, 0.17, 0.27, _material("#b89d71", true), 1.10)
		_ring(_objective, at + Vector3.UP * 0.08, 0.174, Color("#89734d"))
		for stem: int in range(4):
			var p: Vector3 = at + Vector3(sin(float(stem) * 2.3) * 0.11, 0.16, cos(float(stem) * 2.3) * 0.10)
			_beam(_objective, p, p + Vector3(0.04, 0.18, 0.03), 0.010, _material("#73865b"))
			var leaf: MeshInstance3D = _sphere(_objective, p + Vector3(0.06, 0.16, 0.02), Vector3(0.08, 0.027, 0.035), _material("#91a06e"))
			leaf.rotation.z = -0.5
	_box(_objective, Vector3(0.14, 0.62, 0.20), Vector3(0.22, 0.19, 0.23), _material("#d6ccb1", true))
	_box(_objective, Vector3(0.14, 0.72, 0.20), Vector3(0.045, 0.012, 0.24), _material("#a8735e"))

func sync_state(state: Dictionary, selected_id: String, reachable: Array, preview: Dictionary) -> void:
	_state = state.duplicate(true)
	_selected = selected_id
	_reach = reachable.duplicate(true)
	_preview = preview.duplicate(true)
	_sync_barricades()
	var units: Array = _state.get("units", [])
	for unit: Dictionary in units:
		var id: String = str(unit.get("id", ""))
		if id.is_empty():
			continue
		if not actor_nodes.has(id):
			var actor: Node3D = Actor.new()
			actor.name = "Combat_" + id
			world_root.add_child(actor)
			actor.call("setup", id, str(unit.get("role", "")), str(unit.get("team", "")) in ["player", "ally", "friendly", "heroes"])
			actor.call("set_refined_details", _refined_details)
			actor.set("action_playback_speed", ACTION_PLAYBACK_SPEED)
			actor.call("set_attack_timing", ATTACK_TIMING)
			actor.rotation.y = -0.25 if id in ["player", "tinglan"] else PI + 0.30
			actor_nodes[id] = actor
		var node: Node3D = actor_nodes[id]
		node.visible = int(unit.get("hp", 0)) > 0
		node.scale = Vector3.ONE
		node.rotation.z = 0.0
		node.position = _tile_world(unit.get("pos", []))
		if not _animating:
			node.call("set_motion", "idle")
			if str(unit.get("team", "")) == "enemy":
				var aim: Array = _state.get("objective", {}).get("pos", [4, 2])
				for plan: Dictionary in _state.get("plans", []):
					if str(plan.get("unit_id", "")) == id:
						aim = plan.get("target", aim)
						if id == "brute" and bool(node.call("staff_motion_active")) and not bool(plan.get("interrupted", false)):
							node.call("set_motion", "intent")
				node.call("face_toward", _tile_world(aim))
	if actor_nodes.has(_selected):
		_selection.visible = (actor_nodes[_selected] as Node3D).visible
		_selection.position = (actor_nodes[_selected] as Node3D).position + Vector3.UP * 0.053
	else:
		_selection.visible = false
	_update_tiles()
	queue_redraw()

func _update_tiles() -> void:
	var danger: Dictionary = {}
	_danger_cells.clear()
	_objective_threat_count = 0
	for plan: Dictionary in _state.get("plans", []):
		if bool(plan.get("interrupted", false)):
			continue
		if (_state.get("objective", {}).get("pos", []) as Array) in plan.get("cells", []):
			_objective_threat_count += 1
		for tile: Array in plan.get("cells", []):
			danger[_key(tile)] = true
			if not _danger_cells.has(tile):
				_danger_cells.append(tile)
	_objective_warning.visible = _objective_threat_count > 0 and str(_state.get("phase", "")) == "player"
	var preview_cells: Array = _preview.get("cells", [])
	var target_cells: Array = _preview.get("target_cells", [])
	var path: Array = _preview.get("push_path", [])
	for y: int in range(_height):
		for x: int in range(_width):
			var tile: Array = [x, y]
			var key: String = _key(tile)
			var color: Color = Color(0.88, 0.83, 0.66, 0.035)
			var line: Color = Color(0.35, 0.38, 0.29, 0.22)
			if _reach.has(tile):
				color = Color(0.36, 0.66, 0.58, 0.25)
				line = Color(0.35, 0.61, 0.51, 0.60)
			if danger.has(key):
				color = Color(0.77, 0.33, 0.23, 0.30)
				line = Color(0.72, 0.28, 0.18, 0.90)
			if _active_attack_cells.has(tile):
				color = Color(0.95, 0.49, 0.19, 0.62)
				line = Color(1.0, 0.77, 0.37, 1.0)
			if path.has(tile):
				color = Color(0.84, 0.72, 0.30, 0.35)
				line = Color(0.9, 0.78, 0.40, 0.9)
			if target_cells.has(tile):
				color = Color(0.93, 0.74, 0.28, 0.28)
				line = Color(0.97, 0.84, 0.47, 0.96)
			if preview_cells.has(tile):
				color = Color(0.93, 0.74, 0.28, 0.52) if bool(_preview.get("ok", true)) else Color(0.80, 0.26, 0.20, 0.45)
				line = Color(0.97, 0.84, 0.47, 0.96)
			if bool(_preview.get("ok", false)) and _preview.get("collision_barricade_pos", []) == tile:
				color = Color(0.94, 0.62, 0.22, 0.54)
				line = Color(1.0, 0.81, 0.38, 0.96)
			if _hover == tile:
				color = color.lerp(Color(1.0, 0.93, 0.68, 0.47), 0.62)
				line = Color(0.99, 0.91, 0.61, 0.96)
			((_tile_meshes[key] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = color
			var edge_mat: StandardMaterial3D = _overlay_material(line)
			for edge: MeshInstance3D in _tile_borders[key]:
				edge.material_override = edge_mat

func tile_to_screen(tile: Array) -> Vector2:
	if camera == null or not camera.is_inside_tree() or tile.size() < 2:
		return Vector2(-100, -100)
	return _world_to_screen(_tile_world(tile, 0.03))

func _world_to_screen(at: Vector3) -> Vector2:
	return camera.unproject_position(at) * size / Vector2(viewport.size)

func screen_to_tile(local_position: Vector2) -> Array:
	if camera == null or not camera.is_inside_tree() or size.x <= 0 or size.y <= 0 or not Rect2(Vector2.ZERO, size).has_point(local_position):
		return []
	var point: Vector2 = local_position * Vector2(viewport.size) / size
	var origin: Vector3 = camera.project_ray_origin(point)
	var direction: Vector3 = camera.project_ray_normal(point)
	if absf(direction.y) < 0.00001:
		return []
	var distance: float = (0.03 - origin.y) / direction.y
	if distance < 0.0:
		return []
	var at: Vector3 = origin + direction * distance
	var x: int = floori(at.x / CELL + float(_width) * 0.5)
	var y: int = floori(at.z / CELL + float(_height) * 0.5)
	return [x, y] if x >= 0 and y >= 0 and x < _width and y < _height else []

func _pointer_tile(point: Vector2) -> Array:
	var ground: Array = screen_to_tile(point)
	# A figure in the next row may project across a walkable tile. Preserve the
	# whole highlighted ground target before considering any body hitbox.
	if not ground.is_empty() and _reach.has(ground):
		return ground
	# Every exact tile centre is an unambiguous board target, including empty
	# and obstructed cells. Body picking is only an additional off-centre aid.
	if not ground.is_empty():
		var centre: Vector2 = tile_to_screen(ground)
		var horizontal: Array = [int(ground[0]) + (1 if int(ground[0]) + 1 < _width else -1), int(ground[1])]
		var vertical: Array = [int(ground[0]), int(ground[1]) + (1 if int(ground[1]) + 1 < _height else -1)]
		var spacing: float = minf(centre.distance_to(tile_to_screen(horizontal)), centre.distance_to(tile_to_screen(vertical)))
		var centre_radius: float = clampf(spacing * 0.24, 5.0, 14.0)
		if point.distance_squared_to(centre) <= centre_radius * centre_radius:
			return ground
	var best_tile: Array = []
	var nearest: float = INF
	for unit: Dictionary in _state.get("units", []):
		var id: String = str(unit.get("id", ""))
		if not actor_nodes.has(id) or int(unit.get("hp", 0)) <= 0:
			continue
		var node: Node3D = actor_nodes[id]
		var foot: Vector2 = _world_to_screen(node.position + Vector3.UP * 0.08)
		var head: Vector2 = _world_to_screen(node.position + Vector3.UP * 1.68)
		var bounds: Rect2 = Rect2(Vector2(head.x - 18, head.y - 3), Vector2(36, foot.y - head.y + 5))
		if bounds.has_point(point):
			var distance: float = point.distance_squared_to((head + foot) * 0.5)
			if distance < nearest:
				nearest = distance
				best_tile = unit.get("pos", []).duplicate()
	for row: Dictionary in _state.get("barricades", []):
		if int(row.hp) <= 0 or not barricade_nodes.has(str(row.id)):
			continue
		var gate: Node3D = barricade_nodes[str(row.id)]
		var foot: Vector2 = _world_to_screen(gate.position + Vector3.UP * 0.03)
		var head: Vector2 = _world_to_screen(gate.position + Vector3.UP * 0.85)
		var bounds := Rect2(Vector2(head.x - 22, head.y - 5), Vector2(44, foot.y - head.y + 8))
		if bounds.has_point(point):
			var distance: float = point.distance_squared_to((head + foot) * 0.5)
			if distance < nearest:
				nearest = distance
				best_tile = row.pos.duplicate()
	return best_tile if not best_tile.is_empty() else ground

func _user_camera_transform() -> Transform3D:
	# The untouched pose remains byte-for-byte the original tactical camera.
	if is_zero_approx(_camera_yaw) and is_zero_approx(_camera_pitch):
		return _camera_home_transform
	var offset: Vector3 = CAMERA_HOME - CAMERA_TARGET
	var azimuth: float = atan2(offset.x, offset.z) + deg_to_rad(_camera_yaw)
	var elevation: float = atan2(offset.y, Vector2(offset.x, offset.z).length()) + deg_to_rad(_camera_pitch)
	var orbit: Vector3 = Vector3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation)) * offset.length()
	return Transform3D(Basis.looking_at(-orbit, Vector3.UP), CAMERA_TARGET + orbit)

func set_camera_input_enabled(enabled: bool) -> void:
	_camera_input_enabled = enabled
	if not enabled:
		_end_camera_drag()

func _can_control_camera() -> bool:
	return _initialized and _camera_input_enabled and not _animating and not _workshop_mode and is_visible_in_tree()

func reset_camera_view() -> bool:
	if not _can_control_camera():
		return false
	_end_camera_drag()
	_camera_yaw = 0.0
	_camera_pitch = 0.0
	_camera_zoom = 1.0
	_resize()
	_refresh_camera_hover(get_local_mouse_position())
	return true

func _end_camera_drag() -> void:
	_camera_drag_button = 0
	_camera_dragging = false

func _refresh_camera_hover(point: Vector2) -> void:
	var tile: Array = _pointer_tile(point) if Rect2(Vector2.ZERO, size).has_point(point) else []
	if tile != _hover:
		_hover = tile
		_update_tiles()
		tile_hovered.emit(tile)

func _input(event: InputEvent) -> void:
	# GUI controls retain pointer capture after a press. Explicitly end a drag
	# at the board boundary, including releases delivered to another control.
	if _camera_drag_button == 0:
		return
	if not _can_control_camera():
		_end_camera_drag()
		return
	if event is InputEventMouse:
		var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not Rect2(Vector2.ZERO, size).has_point(local_point):
			_end_camera_drag()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_camera_drag()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_end_camera_drag()

func _gui_input(event: InputEvent) -> void:
	if not _initialized:
		return
	if event is InputEventMouseMotion:
		if _camera_drag_button != 0:
			var held_mask: int = 1 << (_camera_drag_button - 1)
			if not _can_control_camera() or not Rect2(Vector2.ZERO, size).has_point(event.position) or (event.button_mask & held_mask) == 0:
				_end_camera_drag()
				return
			var delta: Vector2 = event.position - _camera_drag_last
			if not _camera_dragging:
				if event.position.distance_to(_camera_drag_origin) < CAMERA_DRAG_THRESHOLD:
					accept_event()
					return
				_camera_dragging = true
				delta = event.position - _camera_drag_origin
				_hover = []
				tile_hovered.emit([])
			_camera_drag_last = event.position
			_camera_yaw = clampf(_camera_yaw + delta.x * CAMERA_DRAG_SENSITIVITY.x, CAMERA_YAW_LIMITS.x, CAMERA_YAW_LIMITS.y)
			_camera_pitch = clampf(_camera_pitch - delta.y * CAMERA_DRAG_SENSITIVITY.y, CAMERA_PITCH_LIMITS.x, CAMERA_PITCH_LIMITS.y)
			_resize()
			_update_tiles()
			accept_event()
			return
		_refresh_camera_hover(event.position)
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				if _can_control_camera() and Rect2(Vector2.ZERO, size).has_point(event.position) and _camera_drag_button == 0:
					_camera_drag_button = event.button_index
					_camera_drag_origin = event.position
					_camera_drag_last = event.position
					_camera_dragging = false
			elif event.button_index == _camera_drag_button:
				var cancel_action: bool = event.button_index == MOUSE_BUTTON_RIGHT and not _camera_dragging and event.position.distance_to(_camera_drag_origin) < CAMERA_DRAG_THRESHOLD and _can_control_camera() and Rect2(Vector2.ZERO, size).has_point(event.position)
				_end_camera_drag()
				_refresh_camera_hover(event.position)
				if cancel_action:
					cancel_action_requested.emit()
			accept_event()
			return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed and _can_control_camera() and Rect2(Vector2.ZERO, size).has_point(event.position):
				_camera_zoom = clampf(_camera_zoom * (0.92 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.92), CAMERA_ZOOM_LIMITS.x, CAMERA_ZOOM_LIMITS.y)
				_resize()
				_refresh_camera_hover(event.position)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _camera_drag_button != 0:
				accept_event()
				return
			var tile: Array = _pointer_tile(event.position)
			if not tile.is_empty() and not _animating:
				tile_clicked.emit(tile)
			accept_event()

func _on_mouse_exited() -> void:
	_end_camera_drag()
	_hover = []
	_update_tiles()
	tile_hovered.emit([])

func set_environment_static(enabled: bool) -> void:
	if is_instance_valid(_landscape):
		_landscape.call("set_static", enabled)

func reset_environment() -> void:
	if is_instance_valid(_landscape):
		_landscape.call("reset")

func _process(delta: float) -> void:
	if not _initialized:
		return
	_advance_staff_attack(delta)
	var recipe_active: bool = _move_player.active
	if recipe_active:
		_move_player.step(delta)
		_sample_combat_pushes()
	if is_instance_valid(_skill_fx) and not recipe_active:
		if is_instance_valid(_skill_actor):
			var anchors: Dictionary = _skill_actor.call("get_weapon_anchors")
			if bool(anchors.get("valid", false)):
				_skill_fx.call("update_blade", anchors.base, anchors.tip)
		_skill_fx.call("step", delta)
	if is_instance_valid(_palm_vfx):
		_palm_vfx.call("step", delta)
	if is_instance_valid(_landscape):
		_landscape.call("step", delta)
	while not _floating_feedback.is_empty() and Time.get_ticks_msec() - int(_floating_feedback[0].started_ms) > 1000:
		_floating_feedback.pop_front()
	var overlay: Control = get_node_or_null("NamesAndHealth") as Control
	if overlay != null:
		overlay.queue_redraw()
	if _selection != null and actor_nodes.has(_selected):
		_selection.position = (actor_nodes[_selected] as Node3D).position + Vector3.UP * 0.053
	if _objective_warning != null and _objective_warning.visible:
		var pulse: float = 1.0 + sin(float(Time.get_ticks_msec()) * 0.004) * 0.045
		_objective_warning.scale = Vector3(pulse, 1.0, pulse)

func _advance_staff_attack(delta: float) -> void:
	if not _staff_attack_active or not is_instance_valid(_staff_attack_actor):
		return
	var times := StaffMotion.timing()
	var hit := float(times.impact)
	var contact_end := float(times.contact_end)
	var next := minf(float(times.duration), _staff_attack_elapsed + maxf(delta, 0.0))
	if _staff_attack_elapsed < hit and next >= hit:
		next = hit
		_staff_contact_samples = 0
	elif _staff_attack_elapsed >= hit and _staff_attack_elapsed < contact_end:
		_staff_contact_samples += 1
		if _staff_contact_samples < 2:
			next = minf(next, hit)
	_staff_attack_elapsed = next
	_staff_attack_actor.call("sample_staff_motion", "attack", _staff_attack_elapsed, _staff_attack_context)
	if _staff_attack_elapsed >= float(times.duration):
		_staff_attack_active = false

func _sample_staff_reaction(actor: Node3D, clip: String, context: Dictionary = {}) -> void:
	# A local presentation phrase is sampled from one Stage-owned elapsed value.
	# No new gameplay action or reaction timer runs inside the actor/rig.
	if not is_instance_valid(actor) or not bool(actor.call("staff_motion_active")):
		return
	var processing := actor.is_processing()
	var old_pose: Dictionary = (actor.call("staff_motion_audit") as Dictionary).get("pose", {})
	var entry := context.duplicate(true)
	entry["source_pose"] = old_pose
	actor.set_process(false)
	var elapsed := maxf(0.0, float(context.get("start_seconds", 0.0)))
	var duration := StaffMotion.duration(clip)
	actor.call("sample_staff_motion", clip, elapsed, entry)
	while elapsed < duration and is_inside_tree() and is_instance_valid(actor):
		await get_tree().process_frame
		elapsed = minf(duration, elapsed + get_process_delta_time())
		actor.call("sample_staff_motion", clip, elapsed, entry)
	if is_instance_valid(actor):
		actor.call("set_motion", "idle")
		actor.set_process(processing)

func _draw_labels(overlay: Control) -> void:
	if _workshop_mode:
		return
	if not _initialized or _font == null:
		return
	_draw_preview_guides(overlay)
	# A small ground mark survives low contrast terrain without covering figures.
	for tile: Array in _danger_cells:
		var centre: Vector2 = _world_to_screen(_tile_world(tile, 0.06))
		var mark_color := Color("#efc498") if _active_attack_cells.has(tile) else Color(0.54, 0.18, 0.10, 0.85)
		overlay.draw_line(centre + Vector2(-3, -2), centre + Vector2(3, 2), mark_color, 1.5, true)
		overlay.draw_line(centre + Vector2(-3, 2), centre + Vector2(3, -2), mark_color, 1.5, true)
	for unit: Dictionary in _state.get("units", []):
		var id: String = str(unit.get("id", ""))
		if not actor_nodes.has(id):
			continue
		var node: Node3D = actor_nodes[id]
		if not node.visible:
			continue
		var label_height: float = float(node.call("get_visual_height")) + 0.24
		var at: Vector2 = _world_to_screen(node.position + Vector3.UP * label_height)
		var ratio: float = clampf(float(unit.get("hp", 0)) / maxf(1.0, float(unit.get("max_hp", 1))), 0, 1)
		var detailed: bool = not _animating and (id == _selected or unit.get("pos", []) == _hover)
		var health_color := Color("#a4c4bb") if id in ["player", "tinglan"] else Color("#d09a80")
		if detailed:
			var label: String = str(unit.get("name", id))
			var font_size: int = 13
			var text_width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var width: float = maxf(48.0, text_width + 12.0)
			var rect := Rect2(at - Vector2(width * 0.5, 10), Vector2(width, 25))
			overlay.draw_style_box(_label_style(id == _selected), rect)
			overlay.draw_string(_font, at + Vector2(-text_width * 0.5, 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#f1e8d0"))
			overlay.draw_rect(Rect2(rect.position + Vector2(5, 19), Vector2(width - 10, 3)), Color("#43483e"))
			overlay.draw_rect(Rect2(rect.position + Vector2(5, 19), Vector2((width - 10) * ratio, 3)), health_color)
		else:
			overlay.draw_rect(Rect2(at - Vector2(17, 2), Vector2(34, 5)), Color(0.12, 0.18, 0.16, 0.82))
			overlay.draw_rect(Rect2(at - Vector2(15, 1), Vector2(30 * ratio, 3)), health_color)
	for row: Dictionary in _state.get("barricades", []):
		if int(row.hp) <= 0 or not barricade_nodes.has(str(row.id)):
			continue
		if _animating or (row.get("pos", []) != _hover and str(_preview.get("target_id", "")) != str(row.id)):
			continue
		var gate: Node3D = barricade_nodes[str(row.id)]
		var at: Vector2 = _world_to_screen(gate.position + Vector3.UP * 0.96)
		var label: String = "木栅 %d/%d" % [int(row.hp), int(row.max_hp)]
		var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var rect := Rect2(at - Vector2(width * 0.5 + 6, 13), Vector2(width + 12, 23))
		var style: StyleBoxFlat = _label_style(false)
		style.bg_color = Color(0.30, 0.23, 0.15, 0.92)
		overlay.draw_style_box(style, rect)
		overlay.draw_string(_font, at + Vector2(-width * 0.5, 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#f1dfb6"))
	# Screen-sized feedback remains readable on the compact board and above names.
	for entry: Dictionary in _floating_feedback:
		var age: float = float(Time.get_ticks_msec() - int(entry.started_ms)) / 1000.0
		var alpha: float = clampf((1.0 - age) / 0.3, 0.0, 1.0)
		var at: Vector2 = _world_to_screen(entry.at) + Vector2(0, -29 - age * 16 - int(entry.lane) * 25)
		var text_width: float = _font.get_string_size(str(entry.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		at.x = clampf(at.x, text_width * 0.5 + 9, size.x - text_width * 0.5 - 9)
		at.y = maxf(27.0, at.y)
		var box := Rect2(at - Vector2(text_width * 0.5 + 7, 18), Vector2(text_width + 14, 25))
		var style: StyleBoxFlat = _label_style(false)
		style.bg_color = Color(0.15, 0.21, 0.18, alpha * 0.94)
		style.border_color = Color(0.83, 0.78, 0.59, alpha * 0.7)
		overlay.draw_style_box(style, box)
		var ink: Color = entry.color
		ink.a = alpha
		overlay.draw_string(_font, at + Vector2(-text_width * 0.5, 0), str(entry.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ink)
	# The host displays the cart HP in its objective panel. A second floating
	# label would collide with the adjacent fighter in the opening position.

func _draw_preview_guides(overlay: Control) -> void:
	if _animating:
		return
	var tactic: Array = _preview.get("tactic_tile", [])
	if tactic.size() == 2:
		var at := _world_to_screen(_tile_world(tactic, 0.07))
		overlay.draw_arc(at, 9.0, 0.0, TAU, 24, Color("#f1d895"), 2.5, true)
		overlay.draw_string(_font, at + Vector2(-19.5, 25.0), "出掌位", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffe5ac"))
	if not bool(_preview.get("ok", false)):
		return
	var path: Array = _preview.get("push_path", [])
	var collision: Array = _preview.get("collision_barricade_pos", [])
	if path.size() > 1:
		var start := _world_to_screen(_tile_world(path[0], 0.09))
		var finish := _world_to_screen(_tile_world(path[-1], 0.09))
		var direction := (finish - start).normalized()
		var side := Vector2(-direction.y, direction.x)
		overlay.draw_line(start, finish, Color("#403e29"), 5.5, true)
		overlay.draw_line(start, finish, Color("#f1d58b"), 3.0, true)
		overlay.draw_polyline(PackedVector2Array([finish - direction * 10.0 + side * 5.0, finish, finish - direction * 10.0 - side * 5.0]), Color("#f1d58b"), 3.0, true)
	if collision.size() == 2:
		var at := _world_to_screen(_tile_world(collision, 0.12))
		overlay.draw_line(at + Vector2(-5, -5), at + Vector2(5, 5), Color("#ffd39c"), 3.0, true)
		overlay.draw_line(at + Vector2(-5, 5), at + Vector2(5, -5), Color("#ffd39c"), 3.0, true)
		overlay.draw_string(_font, at + Vector2(-13.0, 23.0), "撞栅", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffe5ac"))

func _label_style(selected: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.25, 0.22, 0.88)
	style.border_color = Color("#d5bf81") if selected else Color(0.76, 0.74, 0.58, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style

func animate_events(events: Array, resolved_state: Dictionary = {}) -> void:
	_resolved_plans = (resolved_state.get("plans", []) as Array).duplicate(true)
	for event: Dictionary in events:
		_events.append(event.duplicate(true))
	if not _animating and not _events.is_empty():
		_animating = true
		_end_camera_drag()
		call_deferred("_drain_events")

func is_animating() -> bool:
	return _animating

func set_combat_light_mode(mode: int) -> bool:
	if _animating or not is_instance_valid(_combat_light):
		return false
	return bool(_combat_light.call("set_mode", mode))

func set_skill_audio(muted: bool, volume_db: float = -10.0) -> void:
	if is_instance_valid(_skill_fx):
		_skill_fx.call("set_audio", muted, volume_db)
	if is_instance_valid(_palm_impact):
		_palm_impact.call("set_audio", muted, volume_db - 2.0)

func _begin_skill_effect(skill_id: String, actor: Node3D, to: Vector3) -> void:
	if not skill_id in ["pierce", "sweep"] or not is_instance_valid(_skill_fx):
		return
	_skill_actor = actor
	var anchors: Dictionary = actor.call("get_weapon_anchors")
	var base: Vector3 = anchors.get("base", actor.global_position + Vector3.UP)
	var tip: Vector3 = anchors.get("tip", base + actor.global_basis.z * 0.7)
	_skill_fx.call("begin_attack", skill_id, actor.global_position, to, base, tip)

func _cancel_skill_effect() -> void:
	_skill_actor = null
	if is_instance_valid(_skill_fx):
		_skill_fx.call("cancel")

func preview_combat_lighting(skill_id: String = "push") -> void:
	if _animating or not actor_nodes.has("player") or not is_instance_valid(_combat_light):
		return
	if not skill_id in ["push", "pierce", "sweep"]:
		return
	var actor: Node3D = actor_nodes.player
	var alive := false
	for member: Dictionary in _state.get("units", []):
		if str(member.id) == "player":
			alive = int(member.hp) > 0
	if not alive:
		return
	_animating = true
	_presentation_phase = "light_preview"
	var camera_in: Tween = create_tween()
	camera_in.tween_method(_set_light_preview_zoom, 1.0, 0.78, 0.12).set_trans(Tween.TRANS_SINE)
	await camera_in.finished
	var original_transform: Transform3D = actor.transform
	var original_processing: bool = actor.is_processing()
	var aim: Vector3 = actor.position + Vector3(1.4, 0, 0)
	if actor_nodes.has("brute") and (actor_nodes.brute as Node3D).visible:
		aim = (actor_nodes.brute as Node3D).position
	var is_new_skill := skill_id in ["pierce", "sweep"]
	if is_new_skill:
		aim = actor.position + Vector3(CELL * (2.0 if skill_id == "pierce" else 1.0), 0, 0)
	actor.call("face_toward", aim)
	actor.set_process(false)
	actor.call("set_motion", "attack", 1.0, skill_id)
	_combat_light.call("begin_attack", skill_id, actor.position, aim, -1.0, not is_new_skill)
	_begin_skill_effect(skill_id, actor, aim)
	if is_new_skill:
		var remaining: float = float(ATTACK_TIMING.hit_at_seconds)
		while remaining > 0.0:
			await get_tree().process_frame
			var step: float = minf(remaining, get_process_delta_time())
			actor.call("_process", step)
			remaining -= step
	else:
		await get_tree().create_timer(float(ATTACK_TIMING.hit_at_seconds)).timeout
	# Hold the actual approved pose for comparison; no combat event is invented.
	# The same source animation time makes the three lighting captures comparable.
	if not is_new_skill:
		actor.call("_process", float(ATTACK_TIMING.hit_at_seconds))
	_combat_light.call("impact")
	if is_new_skill:
		_skill_fx.call("impact")
	await get_tree().create_timer(0.70).timeout
	_combat_light.call("recover")
	await get_tree().create_timer(float(ATTACK_TIMING.recover_seconds) + 0.04).timeout
	_combat_light.call("cancel")
	_cancel_skill_effect()
	actor.call("set_motion", "idle")
	actor.transform = original_transform
	actor.set_process(original_processing)
	var camera_out: Tween = create_tween()
	camera_out.tween_method(_set_light_preview_zoom, 0.78, 1.0, 0.12).set_trans(Tween.TRANS_SINE)
	await camera_out.finished
	_presentation_phase = "idle"
	_animating = false

func preview_palm_vfx(style: int = 0) -> void:
	if style == 1:
		await _preview_palm_rings()
		return
	if _animating:
		return
	await _play_recipe_preview("palm_gale", 1.0)

func _preview_palm_rings() -> void:
	if _animating or not actor_nodes.has("tinglan") or not is_instance_valid(_palm_vfx) or not bool(_palm_vfx.call("audit").ready):
		return
	var actor: Node3D = actor_nodes.tinglan
	if not actor.visible:
		return
	var target: Array = _palm_sample_target()
	if target.is_empty():
		return
	_animating = true
	_presentation_phase = "palm_preview"
	var original_transform: Transform3D = actor.transform
	var original_processing: bool = actor.is_processing()
	var aim: Vector3 = _tile_world(target)
	_focus_attack_camera(actor.position, aim)
	actor.call("face_toward", aim)
	actor.set_process(false)
	# A retained interrupt pose supplies an honest hand reference for this VFX
	# study. It is not advertised as a newly authored palm technique.
	actor.call("set_motion", "attack", 1.0, "interrupt")
	var remaining: float = float(ATTACK_TIMING.hit_at_seconds)
	while remaining > 0.0:
		await get_tree().process_frame
		var step: float = minf(remaining, get_process_delta_time())
		actor.call("_process", step)
		remaining -= step
	var origin: Vector3 = actor.call("get_action_origin", "interrupt")
	_palm_vfx.call("begin_demo", origin, aim + Vector3.UP * 0.72)
	while bool(_palm_vfx.call("audit").active):
		await get_tree().process_frame
	actor.call("set_motion", "idle")
	actor.transform = original_transform
	actor.set_process(original_processing)
	await _restore_attack_camera()
	_presentation_phase = "idle"
	_animating = false

func _palm_sample_target() -> Array:
	var origin: Array = []
	for member: Dictionary in _state.get("units", []):
		if str(member.id) == "tinglan":
			origin = member.pos
	if origin.is_empty():
		return []
	for offset: Vector2i in [Vector2i(-2, 0), Vector2i(0, -2), Vector2i(2, 0), Vector2i(0, 2), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1)]:
		var tile: Array = [int(origin[0]) + offset.x, int(origin[1]) + offset.y]
		if int(tile[0]) < 0 or int(tile[0]) >= _width or int(tile[1]) < 0 or int(tile[1]) >= _height or tile in _definition.get("obstacles", []) or tile == _state.get("objective", {}).get("pos", []):
			continue
		var occupied := false
		for member: Dictionary in _state.get("units", []):
			occupied = occupied or (int(member.hp) > 0 and member.pos == tile)
		for gate: Dictionary in _state.get("barricades", []):
			occupied = occupied or (int(gate.hp) > 0 and gate.pos == tile)
		if not occupied:
			return tile
	return []

func _set_light_preview_zoom(amount: float) -> void:
	_light_preview_zoom = amount
	_resize()

func _action_seconds(source_seconds: float) -> float:
	return source_seconds / ACTION_PLAYBACK_SPEED

func _set_action_camera_blend(amount: float) -> void:
	_action_camera_blend = amount
	_resize()

func _focus_attack_camera(from: Vector3, to: Vector3) -> void:
	_action_camera_focus = (from + to) * 0.5
	if is_instance_valid(_action_camera_tween):
		_action_camera_tween.kill()
	_action_camera_tween = create_tween()
	_action_camera_tween.tween_method(_set_action_camera_blend, _action_camera_blend, 1.0, 0.20).set_trans(Tween.TRANS_SINE)

func _restore_attack_camera() -> void:
	if is_instance_valid(_action_camera_tween):
		_action_camera_tween.kill()
	_action_camera_tween = create_tween()
	_action_camera_tween.tween_method(_set_action_camera_blend, _action_camera_blend, 0.0, 0.16).set_trans(Tween.TRANS_SINE)
	await _action_camera_tween.finished
	_action_camera_focus = Vector3.ZERO
	_set_action_camera_blend(0.0)

func _exit_tree() -> void:
	_end_camera_drag()
	_move_player.cancel()
	if is_instance_valid(_action_camera_tween):
		_action_camera_tween.kill()
	_cancel_skill_effect()
	if is_instance_valid(_palm_vfx):
		_palm_vfx.call("cancel")
	if is_instance_valid(_palm_impact):
		_palm_impact.call("cancel")
	if is_instance_valid(_combat_light):
		_combat_light.call("cancel")

func _drain_events() -> void:
	while not _events.is_empty() and is_inside_tree():
		var event: Dictionary = _events.pop_front()
		_active_event = event.duplicate(true)
		if str(event.get("type", "")) == "attack":
			var impacts: Array[Dictionary] = []
			while not _events.is_empty():
				var next: Dictionary = _events[0]
				var kind: String = str(next.get("type", ""))
				if kind not in ["damage", "push", "interrupt", "defeat", "barricade_damage", "barricade_destroyed"] or (kind == "defeat" and str(next.get("unit_id", "")).is_empty()):
					break
				impacts.append(_events.pop_front())
			await _show_attack(event, impacts)
		else:
			await _show_event(event)
	_active_event = {}
	_presentation_phase = "idle"
	_animating = false

func _announce(kind: String, text: String, tone: String = "neutral") -> void:
	_feedback_history.append({"type": kind, "text": text, "tone": tone, "phase": _presentation_phase, "at_ms": Time.get_ticks_msec()})
	if _feedback_history.size() > 80:
		_feedback_history.pop_front()
	feedback_changed.emit(text, tone)

func _unit_name(id: String) -> String:
	if id == "objective":
		return str(_state.get("objective", {}).get("name", "药篓"))
	for row: Dictionary in _state.get("barricades", []):
		if str(row.id) == id:
			return str(row.name)
	for member: Dictionary in _state.get("units", []):
		if str(member.get("id", "")) == id:
			return str(member.get("name", id))
	return id

func _show_attack(event: Dictionary, impacts: Array[Dictionary]) -> void:
	var id: String = str(event.get("unit_id", ""))
	var node: Node3D = actor_nodes.get(id) as Node3D
	var target: Node3D = actor_nodes.get(str(event.get("target_id", ""))) as Node3D
	if str(event.get("target_kind", "")) == "barricade":
		target = barricade_nodes.get(str(event.get("target_id", ""))) as Node3D
	if node == null:
		return
	var staff_attack := id == "brute" and bool(node.call("staff_motion_active"))
	var staff_processing := node.is_processing()
	var staff_times := StaffMotion.timing()
	var recipe := _combat_recipe(str(event.get("skill_id", "")), id)
	var is_new_skill: bool = not recipe.is_empty()
	var is_fullbody: bool = recipe.has("presentation")
	_combat_pending_impacts = impacts.duplicate(true)
	_combat_contact_presented = false
	_combat_pushes.clear()
	var aim: Vector3 = _tile_world(event.get("to", [])) if is_new_skill else (target.position if target != null else _tile_world(event.get("to", [])))
	var attack_started_ms: int = Time.get_ticks_msec()
	node.call("face_toward", aim)
	_presentation_phase = "windup"
	_active_attack_cells = (event.get("cells", []) as Array).duplicate(true)
	_update_tiles()
	if staff_attack:
		_staff_attack_context = {"source_pose": (node.call("staff_motion_audit") as Dictionary).get("pose", {}).duplicate(true)}
		node.set_process(false)
		_staff_attack_actor = node
		_staff_attack_elapsed = 0.0
		_staff_contact_samples = 0
		_staff_attack_active = true
		node.call("sample_staff_motion", "attack", 0.0, _staff_attack_context)
	else:
		node.call("set_motion", "attack", 1.0, str(event.get("skill_id", "")))
	var uses_combat_light: bool = id in ["player", "tinglan"] and is_instance_valid(_combat_light)
	if uses_combat_light:
		_focus_attack_camera(node.position, aim)
		if not is_new_skill:
			_combat_light.call("begin_attack", str(event.get("skill_id", "")), node.position, aim, float(ATTACK_TIMING.hit_stop_seconds) + float(ATTACK_TIMING.follow_through_seconds), true)
	if is_new_skill:
		var effect_target := _tile_world(event.get("effect_to", event.to))
		if str(recipe.get("category", "")) == "palm":
			effect_target += Vector3.UP * 0.72
		var result := _move_player.begin(recipe, _move_catalog.profiles[recipe.profile], node, effect_target, _skill_fx, _palm_impact, _combat_light)
		if not result.ok:
			# A failed presentation asset cannot prevent the authoritative strike.
			_move_player.cancel()
			is_new_skill = false
			is_fullbody = false
			node.call("set_motion", "attack", 1.0, str(event.get("skill_id", "")))
			if uses_combat_light:
				_combat_light.call("begin_attack", str(event.get("skill_id", "")), node.position, aim, float(ATTACK_TIMING.hit_stop_seconds) + float(ATTACK_TIMING.follow_through_seconds), true)
		else:
			_unified_combat_count += 1
	_combat_presentation = {"actor_id": id, "skill_id": str(event.get("skill_id", "")),
		"move_id": str(recipe.get("id", "")) if is_new_skill else "", "fullbody": is_fullbody,
		"variant_id": str(recipe.get("variant_id", "original")), "active": true,
		"animation_asset": str(recipe.get("animation", {}).get("asset", "")) if is_new_skill else "",
		"timing": recipe.get("timing", {}).duplicate(true) if is_new_skill else (staff_times.duplicate(true) if staff_attack else ATTACK_TIMING.duplicate(true)),
		"staff_motion": staff_attack, "staff_contact_samples": 0,
		"source_preview_only": bool(recipe.get("preview_only", false)), "authority": "presentation only",
		"started_ms": attack_started_ms, "impact_elapsed": -1.0, "damage_events": 0,
		"push_events": 0, "push_completed": 0, "push_clock": "recipe elapsed" if is_fullbody else "legacy event tween"}
	var move_name: String = "出招"
	var collision: bool = false
	for skill: Dictionary in _definition.get("skills", []):
		if str(skill.get("id", "")) == str(event.get("skill_id", "")):
			move_name = str(skill.get("label", move_name))
			collision = str(skill.get("effect", "")) == "push" and int(event.get("amount", 0)) > int(skill.get("damage", 0))
	for plan: Dictionary in _state.get("plans", []):
		if str(plan.get("unit_id", "")) == id:
			move_name = str(plan.get("label", move_name))
	if is_fullbody:
		move_name = str(recipe.presentation.label)
	_announce("attack", _unit_name(id) + " · " + move_name, "neutral" if id in ["player", "tinglan"] else "danger")
	# The nonlinear actor clock reaches source 0.13 s after preparation and strike.
	# Damage, control and recoil share this hit, rather than playing as extra turns.
	if id == "archer":
		_arrow(node.position + Vector3.UP * 1.08, aim + Vector3.UP * 0.65, float(ATTACK_TIMING.hit_at_seconds))
	if is_new_skill:
		while _move_player.active and _move_player.elapsed < float(recipe.timing.impact):
			await get_tree().process_frame
	elif staff_attack:
		while _staff_attack_active and _staff_attack_elapsed < float(staff_times.impact):
			await get_tree().process_frame
	else:
		await get_tree().create_timer(float(ATTACK_TIMING.hit_at_seconds)).timeout
	_presentation_phase = "impact"
	if not _combat_contact_presented:
		_combat_presentation.impact_elapsed = _move_player.elapsed if is_new_skill else (_staff_attack_elapsed if staff_attack else float(ATTACK_TIMING.hit_at_seconds))
		_combat_presentation.impact_at_ms = Time.get_ticks_msec()
	if uses_combat_light and not is_new_skill:
		_combat_light.call("impact")
	if id != "archer":
		if str(event.get("skill_id", "")) == "interrupt":
			var trace: Node3D = Node3D.new()
			trace.name = "InterruptTrace"
			world_root.add_child(trace)
			var trace_mat: StandardMaterial3D = _overlay_material(Color("#b8e3cc"))
			var from: Vector3 = node.call("get_action_origin", "interrupt")
			_beam(trace, from, aim + Vector3.UP * 0.9, 0.025, trace_mat)
			var fade: Tween = create_tween()
			fade.tween_property(trace_mat, "albedo_color:a", 0.0, _action_seconds(0.20))
			fade.tween_callback(trace.queue_free)
		elif not is_new_skill and not staff_attack and (not uses_combat_light or int(_combat_light.call("audit").mode) == 0):
			_slash(node.position, node.rotation.y, id in ["player", "tinglan"])
	var has_hit := false
	var damage_total: int = 0
	var has_push: bool = false
	for impact: Dictionary in impacts:
		if str(impact.get("type", "")) == "damage":
			if not _combat_contact_presented:
				_present_damage(impact)
				_combat_presentation.damage_events += 1
			damage_total += int(impact.get("amount", 0))
			has_hit = true
		elif str(impact.get("type", "")) == "barricade_damage" and str(event.get("target_kind", "")) == "barricade":
			if not _combat_contact_presented:
				_present_barricade_damage(impact)
			has_hit = true
	if not has_hit:
		_float_text(aim + Vector3.UP * 0.9, "落空", Color("#e2dbc3"))
		_announce("miss", _unit_name(id) + "的攻势落空。")
	_presentation_phase = "hit_stop"
	if is_fullbody:
		while _move_player.active and _move_player.elapsed < float(recipe.timing.impact) + float(recipe.timing.impact_hold):
			await get_tree().process_frame
	elif staff_attack:
		while _staff_attack_active and _staff_attack_elapsed < float(staff_times.contact_end):
			await get_tree().process_frame
		_combat_presentation.staff_contact_samples = _staff_contact_samples
	else:
		await get_tree().create_timer(float(ATTACK_TIMING.hit_stop_seconds)).timeout
	for impact: Dictionary in impacts:
		var kind: String = str(impact.get("type", ""))
		if kind in ["push", "interrupt"]:
			if kind == "push":
				has_push = true
				impact["collision"] = collision
				impact["damage_total"] = damage_total
				if is_fullbody:
					# Registered by the contact signal and sampled by the same
					# recipe clock. Never start a second wall-clock shove.
					while _move_player.active and int(_combat_presentation.push_completed) < int(_combat_presentation.push_events):
						await get_tree().process_frame
					continue
			await _show_event(impact)
		elif kind == "barricade_damage" and str(event.get("target_kind", "")) != "barricade":
			if not _combat_contact_presented or bool(_combat_presentation.get("deferred_barricade_damage", false)):
				_present_barricade_damage(impact)
		elif kind == "barricade_destroyed":
			await _break_barricade(impact)
		elif kind == "defeat" and id in ["player", "tinglan"]:
			_apply_resolved_plans()
	if collision and not has_push and target != null:
		_float_text(target.position + Vector3.UP * 1.65, "撞击 · 含加伤", Color("#ecd38b"))
		_announce("collision", "%s撞上阻挡，共受到 %d 点伤害（含撞击加成），来敌退场。" % [_unit_name(str(event.get("target_id", ""))), damage_total], "control")
	# Allow both the source sword phrase and hit recoil to recover naturally.
	_presentation_phase = "recovery"
	if is_fullbody:
		# Do not cut the 1.55 s source phrase at the old 0.85 s attack timeout.
		while _move_player.active:
			await get_tree().process_frame
	elif staff_attack:
		while _staff_attack_active:
			await get_tree().process_frame
	else:
		var remaining: float = float(ATTACK_TIMING.total_seconds) - float(Time.get_ticks_msec() - attack_started_ms) / 1000.0
		await get_tree().create_timer(maxf(0.12, remaining)).timeout
	if uses_combat_light:
		_combat_light.call("cancel")
		await _restore_attack_camera()
	_cancel_skill_effect()
	node.call("set_motion", "idle")
	if staff_attack:
		node.set_process(staff_processing)
		_staff_attack_actor = null
		_staff_attack_context.clear()
	_combat_presentation.active = false
	_combat_presentation.finished_elapsed = _move_player.elapsed if is_new_skill else (_staff_attack_elapsed if staff_attack else float(Time.get_ticks_msec() - attack_started_ms) / 1000.0)
	_combat_presentation.finished_at_ms = Time.get_ticks_msec()
	for impact: Dictionary in impacts:
		if str(impact.get("type", "")) == "defeat":
			await _show_event(impact)
	_active_attack_cells.clear()
	_combat_pending_impacts.clear()
	for pushed: Dictionary in _combat_pushes:
		if is_instance_valid(pushed.actor):
			(pushed.actor as Node3D).call("set_staff_clock_external", false)
	_combat_pushes.clear()
	_update_tiles()

func _on_recipe_impact() -> void:
	if not bool(_combat_presentation.get("active", false)) or not bool(_combat_presentation.get("fullbody", false)) or _combat_contact_presented:
		return
	# The player's crossing sample already applied the contact skeleton, sound
	# and effect. Apply the existing presentation-only damage/recoil this frame.
	_combat_contact_presented = true
	_presentation_phase = "impact"
	_combat_presentation.impact_elapsed = _move_player.elapsed
	_combat_presentation.impact_at_ms = Time.get_ticks_msec()
	var has_push := false
	for impact: Dictionary in _combat_pending_impacts:
		if str(impact.get("type", "")) == "push":
			has_push = true
	_combat_presentation["deferred_barricade_damage"] = has_push
	for impact: Dictionary in _combat_pending_impacts:
		if str(impact.get("type", "")) == "damage":
			_present_damage(impact)
			_combat_presentation.damage_events += 1
			var struck := actor_nodes.get(str(impact.get("target_id", ""))) as Node3D
			if struck != null:
				_move_player.add_impact_recoil(struck)
		elif str(impact.get("type", "")) == "barricade_damage" and not has_push:
			_present_barricade_damage(impact)
	for impact: Dictionary in _combat_pending_impacts:
		if str(impact.get("type", "")) == "push":
			_register_combat_push(impact)
	_presentation_phase = "hit_stop"

func _register_combat_push(event: Dictionary) -> void:
	var target := actor_nodes.get(str(event.get("target_id", ""))) as Node3D
	if target == null or (event.get("from", []) as Array).size() != 2 or (event.get("to", []) as Array).size() != 2:
		return
	var damage_total := 0
	for impact: Dictionary in _combat_pending_impacts:
		if str(impact.get("type", "")) == "damage" and str(impact.get("target_id", "")) == str(event.target_id):
			damage_total += int(impact.get("amount", 0))
	var collision := false
	for skill: Dictionary in _definition.get("skills", []):
		if str(skill.get("id", "")) == str(_combat_presentation.get("skill_id", "")):
			collision = int(_active_event.get("amount", 0)) > int(skill.get("damage", 0))
	var record := {"event": event.duplicate(true), "actor": target,
		"from": _tile_world(event.from), "to": _tile_world(event.to),
		"start": float(_move_player.move.timing.impact) + float(_move_player.move.timing.get("impact_hold", 0.0)),
		"duration": 0.48 if bool(target.call("staff_motion_active")) else _action_seconds(0.18), "completed": false,
		"staff_recoil_context": (target.get("_staff_context") as Dictionary).duplicate(true),
		"collision": collision, "damage_total": damage_total}
	if bool(target.call("staff_motion_active")):
		record["staff_stagger_context"] = {"source_pose": StaffMotion.sample("recoil", 0.06, record.staff_recoil_context),
			"root_delta": target.global_basis.inverse() * ((record.to as Vector3) - (record.from as Vector3)), "collision": collision}
		target.call("set_staff_clock_external", true)
	_combat_pushes.append(record)
	_combat_presentation.push_events += 1
	_combat_presentation["push_registered_elapsed"] = _move_player.elapsed
	_combat_presentation["push_start_elapsed"] = float(record.start)

func _sample_combat_pushes() -> void:
	for row: Dictionary in _combat_pushes:
		if not is_instance_valid(row.actor):
			continue
		var staff_target := row.actor as Node3D
		if bool(staff_target.call("staff_motion_active")):
			if _move_player.elapsed < float(row.start):
				staff_target.call("sample_staff_motion", "recoil", 0.06, row.staff_recoil_context)
			else:
				var since_start := _move_player.elapsed - float(row.start)
				var travel := float(row.duration)
				var recovery := maxf(0.001, float(_move_player.move.timing.total) - float(row.start) - travel)
				var pose_seconds := 0.68 * minf(1.0, since_start / travel) if since_start < travel else 0.68 + 0.40 * clampf((since_start - travel) / recovery, 0.0, 1.0)
				staff_target.call("sample_staff_motion", "stagger", pose_seconds, row.staff_stagger_context)
		if bool(row.completed):
			continue
		var amount := clampf((_move_player.elapsed - float(row.start)) / float(row.duration), 0.0, 1.0)
		var target := row.actor as Node3D
		if amount > 0.0 and not _combat_presentation.has("push_started_elapsed"):
			_combat_presentation["push_started_elapsed"] = _move_player.elapsed
		# Contact holds the hit root still, then the same clock carries it to
		# the authoritative landing tile with the existing ease-out weight.
		target.position = (row.from as Vector3).lerp(row.to as Vector3, 1.0 - (1.0 - amount) * (1.0 - amount))
		if amount < 1.0:
			continue
		row.completed = true
		var event: Dictionary = row.event
		for member: Dictionary in _state.get("units", []):
			if str(member.get("id", "")) == str(event.target_id):
				member.pos = event.to.duplicate()
		_spark(target.position + Vector3.UP * 0.2, Color("#d9ba7d"))
		_float_text(target.position + Vector3.UP * 1.65, "撞击 · 含加伤" if row.collision else "击退 %d 格" % int(event.get("amount", 0)), Color("#ecd38b"))
		_announce("collision" if row.collision else "push", _unit_name(str(event.target_id)) + ("撞上阻挡，共受到 %d 点伤害（含撞击加成）。" % int(row.damage_total) if row.collision else "被击退 %d 格，攻击位置已改变。" % int(event.get("amount", 0))), "control")
		_combat_presentation.push_completed += 1
		_combat_presentation["push_finished_elapsed"] = _move_player.elapsed
		_apply_resolved_plans()

func _present_barricade_damage(event: Dictionary) -> void:
	var id: String = str(event.get("target_id", ""))
	var gate: Node3D = barricade_nodes.get(id) as Node3D
	if gate == null:
		return
	var amount: int = int(event.get("amount", 0))
	for row: Dictionary in _state.get("barricades", []):
		if str(row.id) == id:
			row.hp = int(event.get("hp_after", maxi(0, int(row.hp) - amount)))
	var at: Vector3 = gate.position + Vector3.UP * 0.48
	_spark(at, Color("#eacb8e"))
	_float_text(at + Vector3.UP * 0.65, "木栅 −%d" % amount, Color("#edcf96"))
	_announce("barricade_hit", "%s受损 %d。" % [_unit_name(id), amount], "control")

func _break_barricade(event: Dictionary) -> void:
	var id: String = str(event.get("target_id", ""))
	var gate: Node3D = barricade_nodes.get(id) as Node3D
	if gate == null:
		return
	_presentation_phase = "barricade_break"
	var standing: Node3D = gate.get_node("Standing") as Node3D
	var fall: Tween = create_tween()
	fall.tween_property(standing, "rotation:z", 1.32, _action_seconds(0.18)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fall.finished
	standing.visible = false
	(gate.get_node("Broken") as Node3D).visible = true
	for row: Dictionary in _state.get("barricades", []):
		if str(row.id) == id:
			row.hp = 0
	_spark(gate.position + Vector3.UP * 0.10, Color("#d7b576"))
	_float_text(gate.position + Vector3.UP * 1.05, "栅破 · 可通行", Color("#ead29f"))
	_announce("barricade_destroyed", _unit_name(id) + "已破，路口打开。", "control")
	_apply_resolved_plans()

func _present_damage(event: Dictionary) -> void:
	var target_id: String = str(event.get("target_id", ""))
	var amount: int = int(event.get("amount", 0))
	var struck: Node3D = actor_nodes.get(target_id) as Node3D
	var at: Vector3 = _objective.position + Vector3.UP * 0.65
	if struck != null:
		struck.call("set_motion", "hit")
		at = struck.position + Vector3.UP * 0.9
	for member: Dictionary in _state.get("units", []):
		if str(member.get("id", "")) == target_id:
			member.hp = maxi(0, int(member.hp) - amount)
	if target_id == "objective":
		_state.objective.hp = maxi(0, int(_state.objective.hp) - amount)
	_spark(at, Color("#f7d79e"))
	_float_text(at + Vector3.UP * 0.85, "挡住" if amount == 0 else "−" + str(amount), Color("#f4c498"))
	_announce("objective_hit" if target_id == "objective" else "hit", "%s%s" % [_unit_name(target_id), "挡住了这一击。" if amount == 0 else "受损 %d。" % amount if target_id == "objective" else "受到 %d 点伤害。" % amount], "danger" if target_id == "objective" else "hit")

func _show_event(event: Dictionary) -> void:
	var kind: String = str(event.get("type", event.get("kind", "")))
	var id: String = str(event.get("unit_id", event.get("actor", "")))
	var target_id: String = str(event.get("target_id", event.get("target", "")))
	var node: Node3D = actor_nodes.get(id) as Node3D
	var target: Node3D = actor_nodes.get(target_id) as Node3D
	if kind in ["move", "push"]:
		_presentation_phase = "movement" if kind == "move" else "push"
		var moving: Node3D = target if kind == "push" and target != null else node
		if moving == null:
			return
		var moving_processing := moving.is_processing()
		var staff_push_context: Dictionary = {}
		var from: Array = event.get("from", [])
		var to: Array = event.get("to", [])
		if from.size() == 2:
			moving.position = _tile_world(from)
		if to.size() != 2:
			return
		if kind == "move":
			moving.call("set_motion", "walk")
		elif str(moving.get("_mode")) != "hit":
			# The hit-stop already started this recoil; do not snap it back to zero.
			moving.call("set_motion", "hit")
		var route: Array = event.get("path", [to]) if kind == "move" else [to]
		if route.is_empty():
			route = [to]
		var tween: Tween = create_tween()
		var step_seconds: float = clampf(0.36 / float(route.size()), 0.07, 0.18) if kind == "move" else _action_seconds(0.18)
		if kind == "push" and bool(moving.call("staff_motion_active")):
			step_seconds = 0.48
		for step: Array in route:
			var destination: Vector3 = _tile_world(step)
			if kind == "move":
				tween.tween_callback(moving.call.bind("face_toward", destination))
			if kind == "push" and bool(moving.call("staff_motion_active")):
				var push_origin := moving.position
				staff_push_context = {"root_delta": moving.global_basis.inverse() * (destination - push_origin), "collision": bool(event.get("collision", false)),
					"source_pose": (moving.call("staff_motion_audit") as Dictionary).get("pose", {}).duplicate(true)}
				moving.set_process(false)
				tween.tween_method(func(weight: float) -> void:
					moving.position = push_origin.lerp(destination, weight)
					moving.call("sample_staff_motion", "stagger", weight * 0.68, staff_push_context), 0.0, 1.0, step_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			else:
				tween.tween_property(moving, "position", destination, step_seconds).set_trans(Tween.TRANS_QUAD if kind == "push" else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if kind == "push" else Tween.EASE_IN_OUT)
		await tween.finished
		if kind == "push":
			var collision: bool = bool(event.get("collision", false))
			_spark(moving.position + Vector3.UP * 0.2, Color("#d9ba7d"))
			_float_text(moving.position + Vector3.UP * 1.65, "撞击 · 含加伤" if collision else "击退 %d 格" % int(event.get("amount", 0)), Color("#ecd38b"))
			_announce("collision" if collision else "push", _unit_name(target_id) + ("撞上阻挡，共受到 %d 点伤害（含撞击加成）。" % int(event.get("damage_total", 0)) if collision else "被击退 %d 格，攻击位置已改变。" % int(event.get("amount", 0))), "control")
			# A short local recoil marks a blocked shove; no camera shake.
			if collision:
				var recoil: Tween = create_tween()
				recoil.tween_property(moving, "rotation:z", 0.08, _action_seconds(0.045))
				recoil.tween_property(moving, "rotation:z", 0.0, _action_seconds(0.10))
				await recoil.finished
			for member: Dictionary in _state.get("units", []):
				if str(member.get("id", "")) == target_id:
					member.pos = to.duplicate()
			_apply_resolved_plans()
		if kind == "push" and bool(moving.call("staff_motion_active")):
			staff_push_context["start_seconds"] = 0.68
			await _sample_staff_reaction(moving, "stagger", staff_push_context)
			moving.set_process(moving_processing)
		moving.call("set_motion", "idle")
	elif kind in ["damage", "objective"]:
		_presentation_phase = "impact"
		_present_damage(event)
		await get_tree().create_timer(_action_seconds(0.16)).timeout
	elif kind in ["interrupt", "guard"]:
		_presentation_phase = "control"
		var marked: Node3D = target if target != null else node
		if marked != null:
			_spark(marked.position + Vector3.UP * 0.90, Color("#abd9c1"))
			_float_text(marked.position + Vector3.UP * 1.65, "打断 · 本轮停手" if kind == "interrupt" else "守势 · 减伤 3", Color("#c1e2c0"))
			var ring: MeshInstance3D = _ring(world_root, marked.position + Vector3.UP * 0.08, 0.45, Color("#a6d5bf"))
			var fade: Tween = create_tween()
			fade.tween_property(ring, "scale", Vector3.ONE * 1.5, _action_seconds(0.32))
			fade.tween_callback(ring.queue_free)
		_announce(kind, _unit_name(target_id if not target_id.is_empty() else id) + ("蓄势已打断，本轮移动和攻击取消。" if kind == "interrupt" else "进入守势，本轮每次受击减少 3 点伤害。"), "control")
		if kind == "interrupt":
			_apply_resolved_plans()
			if marked != null and bool(marked.call("staff_motion_active")):
				await _sample_staff_reaction(marked, "interrupt")
		await get_tree().create_timer(_action_seconds(0.16)).timeout
	elif kind == "defeat" and not id.is_empty():
		var fallen: Node3D = target if target != null else node
		if fallen != null:
			var tween: Tween = create_tween()
			tween.tween_property(fallen, "scale", Vector3.ONE * 0.02, _action_seconds(0.20)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			await tween.finished
			fallen.visible = false
	elif kind in ["victory", "defeat"]:
		_announce(kind, "药篓保住了，护送成功。" if kind == "victory" else "护送未成，可以重新挑战。", "control" if kind == "victory" else "danger")

func _apply_resolved_plans() -> void:
	# Consume the session-owned result; presentation never recomputes targeting.
	_state.plans = _resolved_plans.duplicate(true)
	_active_attack_cells.clear()
	_update_tiles()

func _slash(at: Vector3, facing: float, friendly: bool) -> void:
	var effect: Node3D = Node3D.new()
	effect.position = at + Vector3.UP * 0.72
	effect.rotation.y = facing
	world_root.add_child(effect)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(13):
		var a: float = -0.90 + float(i) * 1.8 / 13.0
		var b: float = -0.90 + float(i + 1) * 1.8 / 13.0
		var p0: Vector3 = Vector3(sin(a), 0.05 * sin(a * 3), cos(a)) * 0.53
		var p1: Vector3 = Vector3(sin(b), 0.05 * sin(b * 3), cos(b)) * 0.53
		var p2: Vector3 = Vector3(sin(b), 0.05 * sin(b * 3), cos(b)) * 1.10
		var p3: Vector3 = Vector3(sin(a), 0.05 * sin(a * 3), cos(a)) * 1.10
		for point: Vector3 in [p0, p1, p2, p0, p2, p3]:
			surface.add_vertex(point)
	surface.generate_normals()
	var mat: StandardMaterial3D = _overlay_material(Color(0.87, 0.96, 0.80, 0.72) if friendly else Color(0.96, 0.66, 0.42, 0.72))
	var mesh: MeshInstance3D = _mesh(effect, surface.commit(), Vector3.ZERO, mat)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(effect, "scale", Vector3(1.25, 1.0, 1.25), _action_seconds(0.24))
	tween.tween_property(mat, "albedo_color:a", 0.0, _action_seconds(0.24))
	tween.chain().tween_callback(effect.queue_free)

func _arrow(from: Vector3, to: Vector3, duration: float = 0.18) -> void:
	var arrow: Node3D = Node3D.new()
	arrow.position = from
	world_root.add_child(arrow)
	if from.distance_squared_to(to) > 0.001:
		arrow.look_at(to, Vector3.UP, true)
	_beam(arrow, Vector3(0, 0, -0.27), Vector3(0, 0, 0.10), 0.012, _material("#725940"))
	var tip: MeshInstance3D = _cylinder(arrow, Vector3(0, 0, 0.12), 0.033, 0.10, _material("#d9d4b5"), 0.0)
	tip.rotation.x = PI * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(arrow, "position", to, duration).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(arrow.queue_free)

func _spark(at: Vector3, color: Color) -> void:
	var effect: Node3D = Node3D.new()
	effect.position = at
	world_root.add_child(effect)
	var mat: StandardMaterial3D = _overlay_material(color)
	for i: int in range(6):
		var angle: float = float(i) * TAU / 6.0
		var dir: Vector3 = Vector3(cos(angle), sin(angle), sin(angle * 2) * 0.4)
		_beam(effect, dir * 0.06, dir * 0.25, 0.014, mat)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(effect, "scale", Vector3.ONE * 1.7, _action_seconds(0.22))
	tween.tween_property(mat, "albedo_color:a", 0.0, _action_seconds(0.22))
	tween.chain().tween_callback(effect.queue_free)

func _float_text(at: Vector3, text: String, color: Color) -> void:
	var lane: int = 0
	for existing: Dictionary in _floating_feedback:
		if Time.get_ticks_msec() - int(existing.started_ms) < 180 and (existing.at as Vector3).distance_to(at) < 0.7:
			lane += 1
	_floating_feedback.append({"at": at, "text": text, "color": color, "lane": mini(lane, 2), "started_ms": Time.get_ticks_msec()})

func audit() -> Dictionary:
	var projections: Array = []
	for y: int in range(_height):
		for x: int in range(_width):
			var tile: Array = [x, y]
			projections.append({"tile": tile, "screen": tile_to_screen(tile), "roundtrip": screen_to_tile(tile_to_screen(tile))})
	var hp: Dictionary = {"objective": _state.get("objective", {}).get("hp", 0)}
	for unit: Dictionary in _state.get("units", []):
		hp[str(unit.id)] = int(unit.hp)
	return {"width": _width, "height": _height, "actor_count": actor_nodes.size(), "viewport_size": viewport.size, "display_size": size, "animating": _animating, "projections": projections, "camera": "orthographic tactical view with local action focus", "authority": "presentation only", "action_playback_speed": ACTION_PLAYBACK_SPEED, "attack_timing": ATTACK_TIMING.duplicate(true), "camera_action_blend": _action_camera_blend, "camera_control": camera_control_audit(), "presentation_phase": _presentation_phase, "active_event": _active_event.duplicate(true), "feedback_history": _feedback_history.duplicate(true), "combat_presentation": _combat_presentation.duplicate(true), "move_player": _move_player.audit(), "danger_cells": _danger_cells.duplicate(true), "active_attack_cells": _active_attack_cells.duplicate(true), "objective_threat_count": _objective_threat_count, "presented_hp": hp, "presented_barricade_hp": _presented_barricade_hp(), "barricades": _barricade_audit(), "barricade_count": barricade_nodes.size(), "combat_light": _combat_light.call("audit") if is_instance_valid(_combat_light) else {}, "skill_fx": _skill_fx.call("audit") if is_instance_valid(_skill_fx) else {}, "palm_vfx": _palm_vfx.call("audit") if is_instance_valid(_palm_vfx) else {}, "palm_impact": _palm_impact.call("audit") if is_instance_valid(_palm_impact) else {}, "environment": _landscape.call("audit") if is_instance_valid(_landscape) else {}}

func camera_control_audit() -> Dictionary:
	return {"yaw_degrees": _camera_yaw, "pitch_degrees": _camera_pitch, "zoom": _camera_zoom,
		"yaw_limits": [CAMERA_YAW_LIMITS.x, CAMERA_YAW_LIMITS.y], "pitch_limits": [CAMERA_PITCH_LIMITS.x, CAMERA_PITCH_LIMITS.y],
		"zoom_limits": [CAMERA_ZOOM_LIMITS.x, CAMERA_ZOOM_LIMITS.y], "drag_button": _camera_drag_button,
		"dragging": _camera_dragging, "drag_pending": _camera_drag_button != 0 and not _camera_dragging,
		"drag_threshold_pixels": CAMERA_DRAG_THRESHOLD, "input_enabled": _can_control_camera(),
		"is_default": is_zero_approx(_camera_yaw) and is_zero_approx(_camera_pitch) and is_equal_approx(_camera_zoom, 1.0),
		"camera_transform": camera.transform, "camera_size": camera.size,
		"user_transform": _user_camera_transform(), "default_transform": _camera_home_transform,
		"projection": camera.projection, "authority": "presentation only"}

func _presented_barricade_hp() -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in _state.get("barricades", []):
		result[str(row.id)] = int(row.hp)
	return result

func _ensure_move_catalog() -> bool:
	if not _move_catalog.is_empty():
		return true
	var result := MoveCatalog.load_catalog()
	if result.ok:
		_move_catalog = result.catalog
	return bool(result.ok)

func _combat_recipe(skill: String, actor_id: String = "player") -> Dictionary:
	if not _ensure_move_catalog():
		return {}
	var fullbody_id := "sword_cleave" if skill == "strike" and actor_id == "player" else ("palm_gale" if skill == "palm" and actor_id == "tinglan" else "")
	if not fullbody_id.is_empty():
		# Explicit visual adapters for authoritative encounter skills. The
		# validated source remains preview-only in its catalog and sidecar.
		var enhanced := MoveCatalog.find_move(_move_catalog, fullbody_id, "enhanced")
		if not enhanced.is_empty() and str(enhanced.actor) == actor_id:
			var impact := float(enhanced.timing.impact)
			var hold := 0.07
			var source := float(enhanced.animation.source_seconds)
			enhanced.timing.duration = source + hold
			enhanced.timing.total = float(enhanced.timing.total) + hold
			enhanced.timing.impact_hold = hold
			enhanced.timing.source_map = [[0.0, 0.0], [impact, impact], [impact + hold, impact], [source + hold, source]]
			enhanced["presentation"] = {"actor_id": actor_id, "skill_id": skill,
				"label": "松风剑·落雁斩" if fullbody_id == "sword_cleave" else "劲风掌", "authority": "presentation only"}
			return enhanced
	for recipe: Dictionary in _move_catalog.moves:
		if not bool(recipe.preview_only) and str(recipe.combat_skill) == skill and str(recipe.actor) == actor_id:
			return recipe.duplicate(true)
	return {}

func set_workshop_catalog(catalog: Dictionary) -> Dictionary:
	var result := MoveCatalog.validate_catalog(catalog)
	if result.ok:
		_move_catalog = catalog.duplicate(true)
		_workshop_mode = true
		_hide_workshop_tactical_props()
	return result

func preview_workshop_move(move_id: String, speed: float = 1.0, variant_id: String = "original") -> void:
	stop_workshop_move()
	_workshop_variant = variant_id
	await _play_recipe_preview(move_id, speed, variant_id)

func _play_recipe_preview(move_id: String, speed: float, variant_id: String = "original") -> void:
	if not _ensure_move_catalog():
		return
	var recipe := MoveCatalog.find_move(_move_catalog, move_id, variant_id)
	if recipe.is_empty() or not actor_nodes.has(str(recipe.actor)):
		return
	var actor := actor_nodes[str(recipe.actor)] as Node3D
	if not actor.visible and not _workshop_mode:
		return
	var aim := actor.position + Vector3(CELL * 2.0, 0.0, 0.0)
	if not _workshop_mode:
		var empty := _palm_sample_target()
		if not empty.is_empty():
			aim = _tile_world(empty)
	_workshop_token += 1
	var token := _workshop_token
	_workshop_actor = actor
	_workshop_transform = actor.transform
	_animating = true
	_presentation_phase = "workshop" if _workshop_mode else "palm_preview"
	if _workshop_mode:
		for id: String in actor_nodes:
			_workshop_visibility[id] = (actor_nodes[id] as Node3D).visible
			(actor_nodes[id] as Node3D).visible = id == str(recipe.actor)
		actor.position = Vector3(-0.8, 0.0, 0.0)
		aim = Vector3(1.45, 0.0, 0.0)
		_selection.visible = false
	else:
		_focus_attack_camera(actor.position, aim)
		_set_light_preview_zoom(float(recipe.camera.get("zoom", 0.82)))
	actor.call("face_toward", aim)
	var target := aim + Vector3.UP * (0.72 if str(recipe.category) == "palm" else 0.0)
	var result := _move_player.begin(recipe, _move_catalog.profiles[recipe.profile], actor, target, _skill_fx, _palm_impact, _combat_light, speed)
	if not result.ok:
		push_error(str(result.reason))
	while _move_player.active and is_inside_tree() and token == _workshop_token:
		await get_tree().process_frame
	if token != _workshop_token or not is_inside_tree():
		return
	if not _workshop_mode:
		_restore_workshop_actor()
	if not _workshop_mode:
		_set_light_preview_zoom(1.0)
		await _restore_attack_camera()
	_presentation_phase = "idle"
	_animating = false

func _restore_workshop_actor() -> void:
	if is_instance_valid(_workshop_actor):
		_workshop_actor.transform = _workshop_transform
	for id: String in _workshop_visibility:
		if actor_nodes.has(id):
			(actor_nodes[id] as Node3D).visible = bool(_workshop_visibility[id])
	_workshop_visibility.clear()
	_workshop_actor = null

func stop_workshop_move() -> void:
	_workshop_token += 1
	_move_player.cancel()
	_restore_workshop_actor()
	_animating = false
	_presentation_phase = "idle"
	if _workshop_mode and not _workshop_selected.is_empty():
		show_workshop_move(_workshop_selected, _workshop_variant)

func set_workshop_paused(paused: bool) -> void:
	_move_player.set_paused(paused)

func seek_workshop_move(seconds: float) -> void:
	_move_player.seek(seconds)

func set_workshop_camera(mode: String) -> void:
	if mode not in ["tactical", "front", "side", "close"]:
		return
	_workshop_camera = mode
	_resize()

func _apply_workshop_camera() -> void:
	if _workshop_camera == "close":
		camera.size = 2.8
		var close_focus := Vector3(0.1, 1.15, 0.0)
		camera.position = close_focus + Vector3(4.0, 2.3, 8.0)
		camera.look_at(close_focus)
		return
	camera.size = 4.7
	var focus := Vector3(0.1, 0.9, 0.0)
	match _workshop_camera:
		"front": camera.position = focus + Vector3(7.0, 3.6, 0.0)
		"side": camera.position = focus + Vector3(0.0, 3.6, 8.0)
		_: camera.position = focus + Vector3(5.5, 6.2, 8.0)
	camera.look_at(focus)

func _hide_workshop_tactical_props() -> void:
	if not _workshop_mode:
		return
	# Only this independent workshop Stage hides tactical props. Keep its real
	# ground, landscape lighting and character contact shadows for motion review.
	for tile: MeshInstance3D in _tile_meshes.values():
		tile.visible = false
	for edges: Array in _tile_borders.values():
		for edge: MeshInstance3D in edges:
			edge.visible = false
	for gate: Node3D in barricade_nodes.values():
		gate.visible = false
	for node: Node in world_root.get_children():
		if node is Node3D and str(node.name).begins_with("DeclaredObstacle"):
			(node as Node3D).visible = false
	for node: Node3D in [_selection, _objective, _objective_warning]:
		if is_instance_valid(node):
			node.visible = false

func workshop_audit() -> Dictionary:
	var result := _move_player.audit()
	result["selected_move_id"] = _workshop_selected
	result["selected_variant_id"] = _workshop_variant
	result["camera_mode"] = _workshop_camera
	result["unified_combat_count"] = _unified_combat_count
	result["catalog_sha256"] = str(_move_catalog.get("catalog_sha256", ""))
	return result

func show_workshop_move(move_id: String, variant_id: String = "original") -> void:
	if not _workshop_mode:
		return
	var recipe := MoveCatalog.find_move(_move_catalog, move_id, variant_id)
	if recipe.is_empty() or not actor_nodes.has(str(recipe.actor)):
		return
	_workshop_selected = move_id
	_workshop_variant = variant_id
	for id: String in actor_nodes:
		(actor_nodes[id] as Node3D).visible = id == str(recipe.actor)
	var actor := actor_nodes[str(recipe.actor)] as Node3D
	actor.position = Vector3(-0.8, 0.0, 0.0)
	actor.call("face_toward", Vector3(1.45, 0.0, 0.0))
	_hide_workshop_tactical_props()
