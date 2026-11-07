extends Node
## Shu P1b spatial presentation, adapted selectively from Chengping
## a4a6c1cc1ed9ab4ad7d49291bc8b8d7222c9f6c6 hd2d_street/street_details.
## See docs/P1B_HD2D_SOURCE_AUDIT.md. No runtime, save or action authority.
##
## SubViewport composition derives from Godot's MIT 3D-in-2D demo, fixed source
## cae8dc567a56d3e7936f171bcb85f0ccb9634ad0. Notice for that portion:
## Copyright (c) 2014-present Godot Engine contributors.
## Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to deal
## in the Software without restriction, including without limitation the rights
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
## of the Software, and to permit persons to whom the Software is furnished to
## do so, subject to the following conditions:
## The above copyright notice and this permission notice shall be included in
## all copies or substantial portions of the Software.
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
## THE SOFTWARE.

const PaintedStreetArt = preload("res://addons/cultivation_mode/town_painted_street_art.gd")
const TeaShopArt = preload("res://addons/cultivation_mode/town_tea_shop_art.gd")
const SellerLife = preload("res://addons/cultivation_mode/town_tea_seller_life.gd")
const TeaPatronLife = preload("res://addons/cultivation_mode/town_tea_patron_life.gd")
const StreetSurfaceArt = preload("res://addons/cultivation_mode/town_street_surface_art.gd")
const RiverReflection = preload("res://addons/cultivation_mode/town_river_reflection.gd")
const PANORAMA = preload("res://assets/art/shanxia_polish/mountain-panorama.png")
const WillowTexture = preload("res://assets/art/shanxia_polish/willow.svg")
const WILLOW_SOURCE = "res://assets/art/shanxia_polish/willow-source.json"
const RoofTexture = preload("res://assets/art/shanxia_polish/materials/roof-gray-teal.svg")
const WallTexture = preload("res://assets/art/shanxia_polish/materials/plaster-ivory.svg")
const TimberTexture = preload("res://assets/art/shanxia_polish/materials/timber-honey.svg")
const StoneTexture = preload("res://assets/art/shanxia_polish/materials/flagstone-graygreen.svg")
const MATERIAL_SOURCE = "res://assets/art/shanxia_polish/materials/source.json"
const POLISH_SOURCE = "res://assets/art/shanxia_polish/source.json"
const WORLD_SCALE: float = 80.0
const DISPLAY: Vector2 = Vector2(1280, 720)
const ORIGIN: Vector2 = Vector2(640, 400)
const CAMERA_ANGLE: float = 40.0
const CAMERA_DISTANCE: float = 17.1
const ROOF_SHADER: String = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 surface_color : source_color = vec4(1.0);
uniform vec4 reference_color : source_color = vec4(1.0);
uniform float tint_strength = 0.0;
uniform vec2 repeat_uv = vec2(1.0);
uniform vec2 player_uv = vec2(0.5);
uniform float fade = 0.0;
uniform float lighting_strength = 1.0;
uniform float surface_roughness = 0.95;
uniform float wall_height = -1.0;
uniform float roof_detail = 0.0;
varying float height_world;
varying vec3 position_world;
varying float mesh_local_y;
float age_hash(vec2 p) {
    p = fract(p * vec2(0.1031, 0.11369));
    p += dot(p, p.yx + 33.33);
    return fract((p.x + p.y) * p.x);
}
float age_noise(vec2 p) {
    vec2 c = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(age_hash(c), age_hash(c + vec2(1.0, 0.0)), f.x),
        mix(age_hash(c + vec2(0.0, 1.0)), age_hash(c + vec2(1.0)), f.x), f.y);
}
void vertex() {
    position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    height_world = position_world.y;
    mesh_local_y = VERTEX.y;
}
void fragment() {
    vec2 delta = (SCREEN_UV - player_uv) * vec2(1280.0, 720.0);
    float local = 1.0 - smoothstep(44.0, 92.0, length(delta));
    float pattern = fract(sin(dot(floor(UV * vec2(680.0, 300.0)), vec2(12.9898, 78.233))) * 43758.5453);
    if (pattern < local * fade * 0.88) { discard; }
    vec3 painted = texture(surface_texture, UV * repeat_uv).rgb;
    vec3 tint_ratio = clamp(surface_color.rgb / max(reference_color.rgb, vec3(0.03)), vec3(0.80), vec3(1.20));
    ALBEDO = mix(painted, painted * tint_ratio, tint_strength);
    float broad_age = age_noise(position_world.xz * 0.38 + vec2(4.7, 19.3));
    ALBEDO *= 0.99 + (broad_age - 0.5) * 0.025;
    if (wall_height > 0.0) {
        float patches = smoothstep(0.35, 0.78, age_noise(position_world.xz * 1.5 + vec2(13.1, 7.4)));
        float damp_height = 0.12 + broad_age * 0.18;
        float damp = (1.0 - smoothstep(damp_height - 0.06, damp_height + 0.12, height_world)) * patches;
        ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.87, 0.94, 0.88), damp * 0.34);
    }
    if (roof_detail > 0.0) {
        float low_eave = 1.0 - smoothstep(0.20, 0.35, mesh_local_y);
        float moss_patch = smoothstep(0.60, 0.83, age_noise(position_world.xz * vec2(0.83, 0.31) + vec2(27.3, 2.6)));
        ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.88, 1.04, 0.84), low_eave * moss_patch * 0.36);
    }
    ROUGHNESS = mix(0.95, surface_roughness, lighting_strength);
    if (wall_height > 0.0) {
        float base = 1.0 - smoothstep(0.06, 0.42, height_world);
        float eave = smoothstep(wall_height - 0.62, wall_height - 0.04, height_world);
        AO = 1.0 - max(base * 0.36, eave * 0.33) * lighting_strength;
        AO_LIGHT_AFFECT = 0.25;
    }
    if (roof_detail > 0.0) {
        vec2 tile_uv = UV * repeat_uv;
        vec3 tile_normal = vec3(0.5 + sin(tile_uv.x * 100.53) * 0.08,
            0.5 + sin(tile_uv.y * 50.26) * 0.025, 1.0);
        NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), tile_normal, lighting_strength);
        NORMAL_MAP_DEPTH = 0.35;
    }
}
"""

var _seller_life: RefCounted = SellerLife.new()
var _paving_count: int = 0
var _tea_house: Node3D
var viewport: SubViewport
var world_root: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var geometry: Array[Rect2] = []
var solid_footprints: Array[Rect2] = []
var roof_rows: Array[Dictionary] = []
var actor_nodes: Dictionary = {}
var shadow_nodes: Dictionary = {}
var occluded_count: int = 0

var _view: Control
var _font: Font
var _definition: Dictionary = {}
var _materials: Dictionary = {}
var _surface_textures: Dictionary = {}
var _actor_frames: Dictionary = {}
var _roof_shader: Shader
var _player: Vector2 = Vector2(150, 560)
var _facing: String = "down"
var _walking: bool = false
var _stride: float = 0.0
var _active: bool = false
var _last_tick: int = 0
var _first_sync: bool = true
var motion_enabled: bool = true
var ambient_elapsed: float = 0.0
var conversation_role: String = ""
var _steam: Array[Sprite3D] = []
var _cloth: Array[Node3D] = []
var _cloth_materials: Array[ShaderMaterial] = []
var _leaf_groups: Array[Node3D] = []
var _slot: int = -1
var _backdrop: Sprite3D
var _lantern_materials: Array[StandardMaterial3D] = []
var lighting_enabled: bool = true
var _character_fill: DirectionalLight3D
var _lighting_materials: Array[ShaderMaterial] = []
var _contact_nodes: Array[MeshInstance3D] = []
var _actor_casters: Dictionary = {}
var _tree_casters: Array[Sprite3D] = []
var _sun_occluders: Array[AABB] = []
var _contact_shader: Shader
var _sky: Sky
var _water_material: ShaderMaterial
var _patron_life = TeaPatronLife.new()
var _tea_patron: Sprite3D
var _patron_shadow: Sprite3D
var _painted_street: Node
var _river_reflection: Node
var _reflection_exclusions: Array[GeometryInstance3D] = []
var _lantern_lights: Array[OmniLight3D] = []


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	_view = walker
	_font = font
	_definition = definition.duplicate(true)
	viewport = SubViewport.new()
	viewport.name = "Town3DViewport"
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.positional_shadow_atlas_size = 1024
	add_child(viewport)
	world_root = Node3D.new()
	world_root.name = "TownWorld"
	viewport.add_child(world_root)
	camera = Camera3D.new()
	camera.name = "TownCamera"
	camera.fov = 39.0
	camera.near = 0.1
	camera.far = 100.0
	camera.position = Vector3(0.0, sin(deg_to_rad(CAMERA_ANGLE)), cos(deg_to_rad(CAMERA_ANGLE))) * CAMERA_DISTANCE
	camera.position.x = 2.2
	camera.look_at_from_position(camera.position, Vector3(0, 0.25, 0.25))
	world_root.add_child(camera)
	camera.current = true
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#c3d2ce")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c9d4d7")
	environment.ambient_light_energy = 0.68
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sky: WorldEnvironment = WorldEnvironment.new()
	sky.environment = environment
	world_root.add_child(sky)
	sun = DirectionalLight3D.new()
	sun.name = "WarmAfternoonSun"
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("#fff4e6")
	sun.light_energy = 0.92
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 32.0
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 0.8
	world_root.add_child(sun)
	_character_fill = DirectionalLight3D.new()
	_character_fill.name = "SoftSkyFillForIllustratedActors"
	_character_fill.rotation_degrees = camera.rotation_degrees
	_character_fill.light_color = Color("#c3d5e5")
	_character_fill.light_energy = 0.19
	_character_fill.light_specular = 0.0
	_character_fill.light_cull_mask = 2
	_character_fill.shadow_enabled = false
	world_root.add_child(_character_fill)
	_sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#8faac3")
	sky_material.sky_horizon_color = Color("#c9d4d3")
	sky_material.ground_bottom_color = Color("#8b8269")
	sky_material.ground_horizon_color = Color("#c0bc9f")
	sky_material.sky_energy_multiplier = 0.55
	sky_material.ground_energy_multiplier = 0.30
	_sky.sky_material = sky_material
	environment.sky = _sky
	_contact_shader = Shader.new()
	_contact_shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform float strength = 0.28;
void fragment() {
    vec2 edge = max(abs(UV - vec2(0.5)) - vec2(0.30), vec2(0.0));
    float fade = 1.0 - smoothstep(0.0, 0.20, length(edge));
    ALBEDO = vec3(0.20, 0.24, 0.23);
    ALPHA = fade * strength;
}
"""
	_roof_shader = Shader.new()
	_roof_shader.code = ROOF_SHADER
	_build_backdrop()
	_build_ground()
	var boxes: Array = _definition.get("obstacles", [])
	for index: int in range(boxes.size()):
		var box: Array = boxes[index]
		var bounds: Rect2 = Rect2(float(box[0]), float(box[1]), float(box[2]), float(box[3]))
		geometry.append(bounds)
		if index == 0:
			_build_tea_island(bounds)
		else:
			_tea_house = TeaShopArt.new().build(self, bounds, _font)
	_build_edges()
	_build_landmarks()
	_build_tea_details()
	_build_tea_awning()
	_build_riverfront()
	_build_riverbank_plants()
	_build_tea_patron()
	_create_actor("player")
	_create_actor("tea_seller")
	if is_inside_tree():
		_setup_river_reflection()
	_last_tick = Time.get_ticks_usec()
	_first_sync = true


func _ready() -> void:
	if is_instance_valid(camera):
		# The UI normally authors this stage before mounting its page. Shared
		# World3D and camera resources are available only after entering the tree.
		_setup_river_reflection()
		_update_occlusion(1.0, true)
		_setup_painted_street()


func _setup_painted_street() -> void:
	if is_instance_valid(_painted_street):
		return
	_painted_street = PaintedStreetArt.new()
	_painted_street.name = "PaintedStreetPresentation"
	add_child(_painted_street)
	_painted_street.call("setup", self)
	_painted_street.call("apply", lighting_enabled)
	var cast := _painted_street.get("_volume_cast") as Node
	if is_instance_valid(cast):
		cast.call("set_attention_enabled", bool(_definition.get("character_reactions", false)))


func logical_to_world(point: Vector2) -> Vector3:
	return Vector3((point.x - ORIGIN.x) / WORLD_SCALE, 0, (point.y - ORIGIN.y) / WORLD_SCALE)


func world_to_logical(point: Vector3) -> Vector2:
	return Vector2(point.x * WORLD_SCALE + ORIGIN.x, point.z * WORLD_SCALE + ORIGIN.y)


func logical_to_screen(point: Vector2, height: float = 0.0) -> Vector2:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return Vector2(-1, -1)
	return camera.unproject_position(logical_to_world(point) + Vector3.UP * height) * (DISPLAY / Vector2(viewport.size))


func screen_to_logical(screen: Vector2) -> Vector2:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return Vector2(-1, -1)
	var local: Vector2 = screen * Vector2(viewport.size) / DISPLAY
	var from: Vector3 = camera.project_ray_origin(local)
	var direction: Vector3 = camera.project_ray_normal(local)
	if absf(direction.y) < 0.00001:
		return Vector2(-1, -1)
	var distance: float = -from.y / direction.y
	if distance <= 0.0:
		return Vector2(-1, -1)
	return world_to_logical(from + direction * distance)


func target_screen_position(id: String) -> Vector2:
	var interactions: Dictionary = _definition.get("interactions", {})
	if not interactions.has(id):
		return Vector2(-1, -1)
	var coordinates: Array = interactions[id].position
	var point: Vector2 = Vector2(float(coordinates[0]), float(coordinates[1]))
	# The seated patron's reachable interaction anchor is outside the table.
	# Draw its marker on the person, while navigation still targets clear ground.
	if id == "tea_patron" and is_instance_valid(_tea_patron):
		return logical_to_screen(world_to_logical(_tea_patron.position), 1.05)
	var height: float = _actor_height("tea_seller") * 0.52 if id == "tea_seller" else 2.1 if id == "street_sign" else 0.04
	return logical_to_screen(point, height)


func resize_view(size: Vector2i) -> void:
	if not is_instance_valid(viewport):
		return
	var scale: float = clampf(minf(float(size.x) / DISPLAY.x, float(size.y) / DISPLAY.y), 0.375, 1.0)
	var desired: Vector2i = Vector2i(maxi(480, roundi(DISPLAY.x * scale)), maxi(270, roundi(DISPLAY.y * scale)))
	if viewport.size != desired:
		viewport.size = desired
		if is_instance_valid(_river_reflection):
			_river_reflection.call("sync_camera")
			_river_reflection.call("bind_water_material", _water_material)


func texture() -> Texture2D:
	return viewport.get_texture() if is_instance_valid(viewport) else null


func set_actor_frames(player: Dictionary, npc: Dictionary) -> void:
	_actor_frames = {"player": player.duplicate(), "tea_seller": npc.duplicate()}
	_update_actor("player", _player, _facing, _walking and _active, _stride)
	var npc_point: Array = _definition.get("interactions", {}).get("tea_seller", {}).get("position", [1010, 350])
	_update_actor("tea_seller", Vector2(float(npc_point[0]), float(npc_point[1])), "down", false, 0.0)


func sync(player_position: Vector2, facing: String, walking: bool, stride_distance: float, active: bool) -> void:
	_player = player_position
	_facing = facing
	_walking = walking
	_stride = stride_distance
	_active = active
	var now: int = Time.get_ticks_usec()
	var delta: float = clampf(float(now - _last_tick) / 1000000.0, 0.0, 0.05)
	_last_tick = now
	_update_actor("player", _player, _facing, walking and active, _stride)
	if is_instance_valid(camera) and camera.is_inside_tree():
		_update_occlusion(delta, _first_sync)
		_first_sync = false
	if active and motion_enabled:
		ambient_elapsed += delta
	_update_ambient()
	if is_instance_valid(_painted_street):
		var cast := _painted_street.get("_volume_cast") as Node
		if is_instance_valid(cast) and bool(_definition.get("character_reactions", false)):
			cast.call("set_attention_state", conversation_role, logical_to_world(_player), not conversation_role.is_empty())
			cast.call("advance_presentation", delta, motion_enabled and _view.is_visible_in_tree())
		_painted_street.call("sync")


func audit() -> Dictionary:
	var footprints: Array = []
	for bounds: Rect2 in solid_footprints:
		footprints.append([bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y])
	return {"render_size": viewport.size if is_instance_valid(viewport) else Vector2i.ZERO,
		"viewport_size": viewport.size if is_instance_valid(viewport) else Vector2i.ZERO,
		"camera_position": camera.position if is_instance_valid(camera) else Vector3.ZERO,
		"geometry": geometry.duplicate(), "solid_footprints": footprints, "occluded_roofs": occluded_count,
		"actor_count": actor_nodes.size(), "building_count": geometry.size(), "projection": "perspective",
		"actor_position": _player, "active": _active, "motion_enabled": motion_enabled,
		"ambient_elapsed": ambient_elapsed, "time_slot": _slot, "steam_count": _steam.size(),
		"composition": "enclosed_river_tea_street", "foliage_count": _leaf_groups.size(),
		"river_phase": ambient_elapsed if is_instance_valid(_water_material) else -1.0,
		"lighting_enabled": lighting_enabled, "actor_shadow_casters": _actor_casters.size(),
		"tree_shadow_casters": _tree_casters.size(), "contact_patches": _contact_nodes.size(),
		"player_light": light_at(_player),
		"merchant_sheet": "res://assets/art/shanxia_polish/tea-seller-life.svg",
		"merchant_pose": _seller_life.call("audit_at", ambient_elapsed, motion_enabled, _active),
		"tea_house": "recessed_service_and_half_open_doors", "paving_count": _paving_count,
		"canopy": "sagged_linen_and_ochre_stripes", "cloth_materials": _cloth_materials.size(),
		"ground_surface": "deterministic_world_mineral_wear",
		"river_reflection": _river_reflection.call("audit") if is_instance_valid(_river_reflection) else {},
		"building_finish": "calibrated_tints_and_restrained_age",
		"street_fronts": "two_inward_facing_inset_windows_and_doors", "wall_foot_growth": "three_sheltered_groups",
		"tea_patron_sheet": "res://assets/art/shanxia_polish/tea-patron.svg",
		"tea_patron_pose": _patron_life.call("audit_at", ambient_elapsed, motion_enabled, _active),
		"painted_street": _painted_street.call("audit") if is_instance_valid(_painted_street) else {}}


func validate() -> Array[String]:
	var errors: Array[String] = []
	var floor: Array = _definition.get("floor", [60, 160, 1160, 490])
	var floor_rect: Rect2 = Rect2(float(floor[0]), float(floor[1]), float(floor[2]), float(floor[3]))
	var clearance: float = float(_definition.get("actor_radius", 12))
	for bounds: Rect2 in solid_footprints:
		if not bounds.intersects(floor_rect):
			continue
		var included: bool = false
		for obstacle: Rect2 in geometry:
			if obstacle.grow(clearance).encloses(bounds):
				included = true
				break
		if not included:
			errors.append("Solid presentation footprint leaves declared obstacles: " + str(bounds))
	return errors


func _material(color: String, kind: String = "plaster") -> StandardMaterial3D:
	var key: String = color + ":" + kind
	if _materials.has(key):
		return _materials[key]
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	if kind in ["plaster", "wood", "roof", "ceramic"]:
		var value: float = clampf(Color(color).get_luminance() * 0.32 + 0.76, 0.70, 1.04)
		mat.albedo_color = Color(value, value, value)
	mat.roughness = 0.96
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if kind != "flat":
		mat.albedo_texture = _surface_texture("plaster" if kind == "ceramic" else kind)
	mat.set_meta("baseline_color", mat.albedo_color)
	mat.set_meta("baseline_texture", mat.albedo_texture)
	mat.set_meta("kind", kind)
	mat.set_meta("original_color", Color(color))
	_materials[key] = mat
	return mat


func _surface_texture(kind: String) -> Texture2D:
	if kind == "roof":
		return RoofTexture
	if kind == "plaster":
		return WallTexture
	if kind == "wood":
		return TimberTexture
	if kind == "paving":
		return StoneTexture
	if _surface_textures.has(kind):
		return _surface_textures[kind]
	var image: Image = Image.create(128, 128, false, Image.FORMAT_RGB8)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 281028
	noise.frequency = 0.055
	for y: int in range(128):
		for x: int in range(128):
			var wash: float = noise.get_noise_2d(float(x), float(y))
			var grain: float = float((x * 13 + y * 7 + x * y % 19) % 11) / 10.0
			var value: float = 0.94 + wash * 0.10 + grain * 0.018
			if kind == "wood":
				value = 0.80 + wash * 0.12 + sin(float(x) * 0.22 + wash * 1.4) * 0.045
			elif kind == "stone":
				value = 0.89 + wash * 0.12 + grain * 0.025
			elif kind == "roof":
				value = 0.73 + sin(float(x % 16) / 16.0 * PI) * 0.20 + wash * 0.06
				if y % 32 < 2:
					value -= 0.08
			image.set_pixel(x, y, Color(value, value, value))
	image.generate_mipmaps()
	var texture_value: ImageTexture = ImageTexture.create_from_image(image)
	_surface_textures[kind] = texture_value
	return texture_value


func _fade_material(color: String, kind: String, repeats: Vector2 = Vector2.ONE) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _roof_shader
	mat.set_shader_parameter("surface_texture", _surface_texture(kind))
	mat.set_shader_parameter("surface_color", Color(color))
	mat.set_shader_parameter("reference_color", Color("#ded8c5") if kind == "plaster" else Color("#68786f"))
	mat.set_shader_parameter("tint_strength", 0.32 if kind == "plaster" else 0.40)
	mat.set_shader_parameter("repeat_uv", repeats)
	mat.set_shader_parameter("fade", 0.0)
	mat.set_shader_parameter("roof_detail", 1.0 if kind == "roof" else 0.0)
	mat.set_shader_parameter("surface_roughness", 0.61 if kind == "roof" else 0.93)
	_lighting_materials.append(mat)
	return mat


func _box(parent: Node3D, point: Vector3, dimensions: Vector3, mat: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = point
	parent.add_child(node)
	return node


func _plane(point: Vector3, dimensions: Vector2, mat: Material) -> MeshInstance3D:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = dimensions
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.position = point
	node.material_override = mat
	world_root.add_child(node)
	return node


func _cylinder(parent: Node3D, point: Vector3, radius: float, height: float, mat: Material, top: float = 1.0) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius * top
	mesh.height = height
	mesh.radial_segments = 10
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.position = point
	node.material_override = mat
	parent.add_child(node)
	return node


func _beam(parent: Node3D, from: Vector3, to: Vector3, thickness: float, mat: Material) -> MeshInstance3D:
	var mesh: MeshInstance3D = _box(parent, (from + to) * 0.5, Vector3(thickness, from.distance_to(to), thickness), mat)
	mesh.basis = Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	return mesh


func _build_ground() -> void:
	# Earth remains walkable between authored stone groups. It need not cast a
	# shadow onto itself; disabling only its casting avoids flat-plane acne.
	var surface_art = StreetSurfaceArt.new()
	var earth: MeshInstance3D = _plane(Vector3(0, -0.035, -10.2), Vector2(46, 27.6), surface_art.make_earth_material())
	earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var placements: Array = [[], [], [], [], [], []]
	var tones: Array = [[], [], [], [], [], []]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 291029
	# Courses alternate broad and narrow stones, with chipped silhouettes and
	# quieter joints. The edge dissolves into a level earth shoulder.
	var z: float = -10.2
	var course: int = 0
	while z < 3.65:
		var row_depth: float = [0.37, 0.46, 0.34, 0.51, 0.42][course % 5]
		var x: float = -13.8 + rng.randf_range(-0.35, 0.25)
		while x < 13.8:
			var width: float = rng.randf_range(0.55, 1.02)
			var px: float = x + width * 0.5
			var pz: float = z + row_depth * 0.5
			var path_center: float = 0.25 - sin(px * 0.28) * 0.70
			var broad_street: bool = px > -7.3 and px < 7.4 and absf(pz - path_center) < 2.22 + sin(px * 0.9) * 0.17
			var shop_apron: bool = px > -4.3 and px < 7.4 and pz > -2.15 and pz < -0.45
			var uphill_lane: bool = px > -6.65 and px < -5.05
			var sparse_edge: bool = absf(pz - path_center) < 2.62 and rng.randf() < 0.32
			if (broad_street or shop_apron or uphill_lane or sparse_edge) and pz < 3.45:
				var variant: int = rng.randi_range(0, 5)
				var at: Vector3 = Vector3(px, -0.008, pz + rng.randf_range(-0.008, 0.008))
				var basis: Basis = Basis(Vector3.UP, rng.randf_range(-0.024, 0.024)).scaled(Vector3(width - 0.020, 1.0, row_depth - 0.018))
				placements[variant].append(Transform3D(basis, at))
				var value: float = rng.randf_range(0.90, 1.05)
				tones[variant].append(Color(value * 0.99, value * 0.99, value * rng.randf_range(0.97, 1.0)))
			x += width
		z += row_depth
		course += 1
	var stone: ShaderMaterial = surface_art.make_flagstone_material()
	for variant: int in range(6):
		var group: MultiMeshInstance3D = MultiMeshInstance3D.new()
		group.name = "WornFlagstones_%d" % variant
		group.multimesh = MultiMesh.new()
		group.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		group.multimesh.use_colors = true
		group.multimesh.mesh = _flagstone_mesh(variant)
		group.material_override = stone
		group.multimesh.instance_count = placements[variant].size()
		for i: int in range(placements[variant].size()):
			group.multimesh.set_instance_transform(i, placements[variant][i])
			group.multimesh.set_instance_color(i, tones[variant][i])
		_paving_count += placements[variant].size()
		world_root.add_child(group)
	_build_wall_foot_growth()


func _build_wall_foot_growth() -> void:
	# Three quiet accumulations replace the old ruler-spaced moss rectangles.
	# These are level surface marks, never new collision or raised paving.
	var centers: Array[Vector2] = [Vector2(-3.45, -1.47), Vector2(2.85, -1.48), Vector2(-7.55, 1.78)]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 291047
	for group: int in range(centers.size()):
		for patch: int in range(6):
			var center: Vector2 = centers[group] + Vector2(rng.randf_range(-0.38, 0.38), rng.randf_range(-0.045, 0.09))
			var size: Vector2 = Vector2(rng.randf_range(0.08, 0.24), rng.randf_range(0.035, 0.09))
			var mesh: SurfaceTool = SurfaceTool.new()
			mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
			var rim: Array[Vector3] = []
			for point: int in range(9):
				var angle: float = TAU * float(point) / 9.0
				var radius: float = rng.randf_range(0.68, 1.0)
				rim.append(Vector3(cos(angle) * size.x * radius, 0, sin(angle) * size.y * radius))
			for point: int in range(rim.size()):
				for vertex: Vector3 in [Vector3.ZERO, rim[(point + 1) % rim.size()], rim[point]]:
					mesh.set_normal(Vector3.UP)
					mesh.add_vertex(vertex)
			var mark: MeshInstance3D = MeshInstance3D.new()
			mark.name = "ShelteredMoss_%d_%d" % [group, patch]
			mark.mesh = mesh.commit()
			mark.position = Vector3(center.x, 0.003 + float(patch) * 0.0015, center.y)
			mark.material_override = _material(["#81876d", "#8d9074", "#777f68"][patch % 3], "flat")
			mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world_root.add_child(mark)


func _flagstone_mesh(seed: int) -> ArrayMesh:
	# Six individually chipped corner profiles share the same footprint scale.
	var c: float = 0.065 + float(seed % 3) * 0.018
	var rim: Array[Vector2] = [Vector2(-0.5 + c, -0.5), Vector2(0.5 - c * 1.3, -0.5),
		Vector2(0.5, -0.5 + c), Vector2(0.5, 0.5 - c * 1.5),
		Vector2(0.5 - c, 0.5), Vector2(-0.5 + c * 1.4, 0.5),
		Vector2(-0.5, 0.5 - c), Vector2(-0.5, -0.5 + c * 1.1)]
	var mesh: SurfaceTool = SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(rim.size()):
		var a: Vector2 = rim[i]
		var b: Vector2 = rim[(i + 1) % rim.size()]
		for v: Vector3 in [Vector3.ZERO, Vector3(b.x * 0.975, 0, b.y * 0.97), Vector3(a.x * 0.975, 0, a.y * 0.97)]:
			mesh.set_color(Color(0.98, 0.99, 0.96))
			mesh.set_normal(Vector3.UP)
			mesh.set_uv(Vector2(v.x + 0.5, v.z + 0.5))
			mesh.add_vertex(v)
		var vertices: Array[Vector3] = [Vector3(a.x * 0.975, 0, a.y * 0.97), Vector3(b.x * 0.975, 0, b.y * 0.97), Vector3(b.x, -0.018, b.y), Vector3(a.x, -0.018, a.y)]
		for index: int in [0, 2, 1, 0, 3, 2]:
			var v: Vector3 = vertices[index]
			mesh.set_color(Color(0.91, 0.91, 0.88))
			mesh.set_normal(Vector3(0, 0.72, 0.0).lerp(Vector3(a.x, 0, a.y).normalized(), 0.28).normalized())
			mesh.set_uv(Vector2(v.x + 0.5, v.z + 0.5))
			mesh.add_vertex(v)
	return mesh.commit()


func _build_tea_island(bounds: Rect2) -> void:
	var table: Node3D = Node3D.new()
	table.name = "SharedTeaTableAndTwoBenches"
	table.position = logical_to_world(bounds.get_center())
	world_root.add_child(table)
	solid_footprints.append(bounds)
	_contact_pad(table.position, bounds.size / WORLD_SCALE, 0.30)
	var width: float = bounds.size.x / WORLD_SCALE
	var depth: float = bounds.size.y / WORLD_SCALE
	var wood: StandardMaterial3D = _material("#896e4a", "wood")
	var dark: StandardMaterial3D = _material("#63563e", "wood")
	# The narrow spaces between table and benches are smaller than actor width.
	_box(table, Vector3(0, 0.055, 0), Vector3(width, 0.11, depth), _material("#aaa58f", "stone"))
	for board: int in range(4):
		_box(table, Vector3(0, 0.74, -0.36 + float(board) * 0.24), Vector3(width - 0.10, 0.08, 0.233), wood)
	for x: float in [-width * 0.34, width * 0.34]:
		_box(table, Vector3(x, 0.41, 0), Vector3(0.12, 0.64, 0.70), dark)
	_box(table, Vector3(0, 0.30, 0), Vector3(width - 0.35, 0.09, 0.10), dark)
	for side: float in [-1.0, 1.0]:
		var bz: float = side * (depth * 0.5 - 0.19)
		_box(table, Vector3(0, 0.37, bz), Vector3(width - 0.15, 0.085, 0.30), wood)
		for x: float in [-width * 0.35, width * 0.35]:
			_box(table, Vector3(x, 0.23, bz), Vector3(0.09, 0.29, 0.22), dark)
		_box(table, Vector3(0, 0.22, bz), Vector3(width - 0.28, 0.065, 0.07), dark)
	var tray: Vector3 = Vector3(0.26, 0.80, -0.02)
	_box(table, tray, Vector3(0.83, 0.035, 0.42), dark)
	_teapot(table, tray + Vector3(0.17, 0.045, -0.02), 0.78)
	for x: float in [-0.20, 0.01]:
		_cylinder(table, tray + Vector3(x, 0.055, 0.09), 0.064, 0.075, _material("#becbb7", "ceramic"), 1.15)
	_box(table, Vector3(-0.73, 0.80, 0.15), Vector3(0.33, 0.018, 0.27), _material("#b7ab8a", "flat"))
	_basket(table, Vector3(-0.70, 0.22, -0.22), 0.20)
	_make_steam(table.position + tray + Vector3(0.17, 0.28, -0.02))


func _build_tea_patron() -> void:
	# Unnamed environmental extra: no hotspot, Session actor or new obstacle.
	# Seat lies on the back edge of the near bench. Keeping the illustrated
	# seated body upright avoids leaning its face into the tabletop; the shorter
	# authored lower legs land on the existing 0.11m stone island top.
	var table: Node3D = world_root.get_node("SharedTeaTableAndTwoBenches") as Node3D
	_tea_patron = Sprite3D.new()
	_tea_patron.name = "SeatedTeaPatron"
	_tea_patron.position = table.position + Vector3(-0.86, 0.4125, 0.61)
	_tea_patron.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_tea_patron.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_tea_patron.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_tea_patron.alpha_scissor_threshold = 0.18
	_tea_patron.layers = 3
	_tea_patron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tea_patron.pixel_size = 1.26 / 96.0
	_tea_patron.offset = Vector2(1, 10) # frame center minus the authored seat (31,58).
	world_root.add_child(_tea_patron)
	_patron_shadow = Sprite3D.new()
	_patron_shadow.name = "SeatedPatronSunShadow"
	_patron_shadow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_patron_shadow.alpha_scissor_threshold = 0.25
	_patron_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_patron_shadow.shaded = true
	world_root.add_child(_patron_shadow)
	# Use a foot-anchored shadow plane while the visible art is seat-anchored.
	var foot: Vector3 = _tea_patron.position + camera.basis.x * _tea_patron.pixel_size - Vector3.UP * (22.0 * _tea_patron.pixel_size)
	foot.y = 0.118
	_patron_shadow.position = foot
	_contact_pad(foot, Vector2(0.26, 0.13), 0.17)
	_update_tea_patron()


func _update_tea_patron() -> void:
	if not is_instance_valid(_tea_patron):
		return
	var frame: Texture2D = _patron_life.call("frame_at", ambient_elapsed, motion_enabled, _active)
	_tea_patron.texture = frame
	_tea_patron.shaded = lighting_enabled
	var dusk: float = clampf(float(_slot - 3) / 2.0, 0.0, 1.0)
	_tea_patron.modulate = Color(0.86, 0.88, 0.90).lerp(Color("#bab0b0"), dusk) if lighting_enabled else Color.WHITE.lerp(Color("#cbb9af"), dusk)
	_patron_shadow.texture = frame
	_patron_shadow.pixel_size = _tea_patron.pixel_size
	_patron_shadow.offset = Vector2(0, 32) # (32,80) foot anchor in the same 64x96 art.
	_patron_shadow.rotation.y = sun.rotation.y
	_patron_shadow.visible = lighting_enabled


func _build_house(bounds: Rect2, stall: bool, backdrop: bool) -> void:
	var house: Node3D = Node3D.new()
	house.name = "MarketShelter" if stall else "NorthShop" if not backdrop else "BackgroundHouse"
	house.position = logical_to_world(bounds.get_center())
	world_root.add_child(house)
	var width: float = bounds.size.x / WORLD_SCALE
	var depth: float = bounds.size.y / WORLD_SCALE
	var style: int = posmod(roundi(bounds.position.x) * 7 + roundi(bounds.position.y) * 11, 3)
	var height: float = 1.38 if stall else ([2.18, 2.48, 2.30][style] if backdrop else 2.62)
	var plaster_colors: Array[String] = ["#e1d8be", "#d1d7cf", "#daccb6"]
	var roof_colors: Array[String] = ["#62796e", "#6b7276", "#7a7769"]
	var timber: StandardMaterial3D = _material("#6d5845", "wood")
	var stone: StandardMaterial3D = _material("#aaa18a", "stone")
	var wall: ShaderMaterial = _fade_material(plaster_colors[style] if backdrop else "#ded8c4", "plaster", Vector2(maxf(width / 2.5, 1.0), 1.0))
	wall.set_shader_parameter("wall_height", height)
	var tiles: ShaderMaterial = _fade_material(roof_colors[style] if backdrop else "#586e6b" if not stall else "#667369", "roof", Vector2(maxf(width / 2.0, 1.0), maxf(depth * 0.5 / 2.4, 0.6)))
	solid_footprints.append(bounds)
	_contact_pad(house.position, bounds.size / WORLD_SCALE, 0.26)
	_sun_occluders.append(AABB(house.position - Vector3(width * 0.5, 0, depth * 0.5), Vector3(width, height + 0.25, depth)))
	_box(house, Vector3(0, 0.075, 0), Vector3(width, 0.15, depth), stone)
	if stall:
		# The full blocked stall footprint reads as stocked, rather than an empty
		# passage under a canopy that the walking rules inexplicably reject.
		_box(house, Vector3(0, 0.36, -0.12), Vector3(width - 0.16, 0.57, depth - 0.36), wall)
		_box(house, Vector3(0, 0.68, depth * 0.18), Vector3(width - 0.12, 0.09, depth * 0.48), timber)
		for x: float in [-width * 0.3, 0.0, width * 0.3]:
			_box(house, Vector3(x, 0.85, depth * 0.05), Vector3(0.30, 0.26, 0.32), _material("#b79265", "wood"))
	else:
		var street_side: float = 1.0 if bounds.position.x < 0 and bounds.position.y > 400 else -1.0 if bounds.position.x > 1200 else 0.0
		if street_side != 0.0:
			_build_street_house_shell(house, width, depth, height, street_side, wall, timber, stone)
		else:
			_box(house, Vector3(0, height * 0.5, -0.04), Vector3(width - 0.10, height, depth - 0.13), wall)
		_box(house, Vector3(0, 0.24, 0), Vector3(width - 0.06, 0.22, depth - 0.06), stone)
		for x: float in [-width * 0.31, width * 0.31]:
			_box(house, Vector3(x, 1.00, depth * 0.5 - 0.015), Vector3(1.02, 0.65, 0.04), _material("#4f5f56" if style == 1 else "#646a59", "flat"))
			for offset: float in [-0.36, -0.12, 0.12, 0.36]:
				_box(house, Vector3(x + offset, 1.00, depth * 0.5 + 0.014), Vector3(0.035, 0.65, 0.035), timber)
			for offset: float in [-0.22, 0.0, 0.22]:
				_box(house, Vector3(x, 1.00 + offset, depth * 0.5 + 0.024), Vector3(1.02, 0.035, 0.035), timber)
			_box(house, Vector3(x, 0.64, depth * 0.5 + 0.018), Vector3(1.16, 0.075, 0.16), timber)
			if backdrop and style == 1 and x < 0:
				var shutter: Node3D = Node3D.new()
				shutter.name = "OpenWindowShutter"
				shutter.position = Vector3(x - 0.54, 1.0, depth * 0.5 + 0.06)
				shutter.rotation.y = deg_to_rad(-34.0)
				house.add_child(shutter)
				_box(shutter, Vector3(-0.18, 0, 0), Vector3(0.36, 0.68, 0.045), timber)
				for line: float in [-0.20, 0.20]:
					_box(shutter, Vector3(-0.18, line, 0.033), Vector3(0.32, 0.045, 0.028), _material("#554c3b", "flat"))
		_box(house, Vector3(0, 1.02, depth * 0.5 - 0.012), Vector3(0.80, 1.93, 0.06), _material("#8c7050", "wood"))
		for x: float in [-0.38, 0.38]:
			_box(house, Vector3(x * 1.16, 1.05, depth * 0.5 + 0.035), Vector3(0.075, 2.06, 0.075), timber)
		_box(house, Vector3(0, 2.09, depth * 0.5 + 0.035), Vector3(0.83, 0.09, 0.07), timber)
		_box(house, Vector3(0, 0.10, depth * 0.5 + 0.06), Vector3(0.91, 0.13, 0.13), stone)
	if not stall and not backdrop:
		var service: Vector3 = Vector3(width * 0.31, 1.14, depth * 0.5 + 0.065)
		_box(house, service, Vector3(1.63, 1.12, 0.07), _material("#414c43", "flat"))
		_box(house, service + Vector3(0, -0.49, 0.10), Vector3(1.76, 0.12, 0.30), timber)
		for x: float in [-0.82, 0.82]:
			_box(house, service + Vector3(x, 0, 0.01), Vector3(0.08, 1.3, 0.10), timber)
		for i: int in range(5):
			_cylinder(house, service + Vector3(-0.55 + float(i) * 0.26, -0.28, 0.09), 0.085, 0.31, _material("#899683", "flat"), 0.85)
		_box(house, service + Vector3(0, 0.62, 0.02), Vector3(1.77, 0.10, 0.13), timber)

	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			_box(house, Vector3(side * (width * 0.5 - 0.08), height * 0.5, end * (depth * 0.5 - 0.07)), Vector3(0.11, height, 0.11), timber)
		_box(house, Vector3(0, height - 0.05, side * (depth * 0.5 - 0.02)), Vector3(width, 0.13, 0.10), timber)
		_box(house, Vector3(side * (width * 0.5 - 0.05), height - 0.05, 0), Vector3(0.10, 0.13, depth), timber)
	var roof: Node3D = _roof(house, Vector3(0, height + 0.02, 0), width, depth, tiles)
	if backdrop and style == 1:
		_build_plaster_gables(house, width, depth, height, wall)
	if not backdrop:
		roof_rows.append({"node": roof, "body": house, "materials": [tiles, wall], "fade": 0.0})
	_decorate_house(house, width, depth, height, stall, backdrop)
	if not stall and not backdrop:
		for side: float in [-1.0, 1.0]:
			_lantern(house, Vector3(side * width * 0.40, height - 0.20, depth * 0.5 + 0.11))
		_sign(house, Vector3(0, 2.29, depth * 0.5 + 0.08), "山下茶寮" if not backdrop else "客舍", Vector2(1.60 if not backdrop else 0.72, 0.35), 42 if not backdrop else 36)


func _build_street_house_shell(house: Node3D, width: float, depth: float, height: float, side: float, wall: ShaderMaterial, timber: StandardMaterial3D, stone: StandardMaterial3D) -> void:
	# The two flanking houses now address the street on their inward end wall.
	# Replace the solid body with a closed shell and authored openings, so the
	# inset window has real depth rather than sitting on an opaque white slab.
	for end: float in [-1.0, 1.0]:
		_box(house, Vector3(0, height * 0.5, end * (depth * 0.5 - 0.10)), Vector3(width - 0.10, height, 0.10), wall)
	_box(house, Vector3(-side * (width * 0.5 - 0.10), height * 0.5, -0.04), Vector3(0.10, height, depth - 0.13), wall)
	var facade: Node3D = Node3D.new()
	facade.name = "StreetFacingDoorAndInsetWindow"
	facade.position.x = side * (width * 0.5 - 0.10)
	facade.rotation.y = side * PI * 0.5
	house.add_child(facade)
	var span: float = depth - 0.20
	var door_x: float = -span * 0.245
	var window_x: float = span * 0.235
	var window_width: float = minf(1.45, span * 0.37)
	var openings: Array[Rect2] = [Rect2(door_x - 0.36, 0.17, 0.72, 1.78), Rect2(window_x - window_width * 0.5, 0.83, window_width, 0.88)]
	var previous: float = -span * 0.5
	for opening: Rect2 in openings:
		var gap: float = opening.position.x - previous
		if gap > 0.001:
			_box(facade, Vector3(previous + gap * 0.5, height * 0.5, -0.012), Vector3(gap, height, 0.10), wall)
		if opening.position.y > 0.0:
			_box(facade, Vector3(opening.get_center().x, opening.position.y * 0.5, -0.012), Vector3(opening.size.x, opening.position.y, 0.10), wall)
		var upper: float = height - opening.end.y
		_box(facade, Vector3(opening.get_center().x, opening.end.y + upper * 0.5, -0.012), Vector3(opening.size.x, upper, 0.10), wall)
		previous = opening.end.x
	var remaining: float = span * 0.5 - previous
	_box(facade, Vector3(previous + remaining * 0.5, height * 0.5, -0.012), Vector3(remaining, height, 0.10), wall)
	var dark: StandardMaterial3D = _material("#48544b", "flat")
	var door: StandardMaterial3D = _material("#78654b", "flat")
	# A closed paired door is recessed behind the jamb; no enter-interior action.
	_box(facade, Vector3(door_x, 1.06, -0.041), Vector3(0.72, 1.78, 0.025), door)
	for i: int in range(7):
		_box(facade, Vector3(door_x - 0.31 + float(i) * 0.103, 1.06, -0.023), Vector3(0.012, 1.70, 0.012), _material("#5c503e", "flat"))
	for y: float in [0.38, 1.12, 1.75]:
		_box(facade, Vector3(door_x, y, -0.011), Vector3(0.69, 0.046, 0.024), timber)
	for x: float in [door_x - 0.40, door_x + 0.40]:
		_box(facade, Vector3(x, 1.08, 0.016), Vector3(0.075, 1.96, 0.075), timber)
	_box(facade, Vector3(door_x, 2.035, 0.022), Vector3(0.92, 0.12, 0.075), timber)
	_box(facade, Vector3(door_x, 0.17, -0.010), Vector3(0.89, 0.14, 0.14), stone)
	# Window bars stay at the outer wall while the dark backing sits 8 cm in.
	_box(facade, Vector3(window_x, 1.27, -0.085), Vector3(window_width, 0.88, 0.022), dark)
	for i: int in range(5):
		var x: float = lerpf(window_x - window_width * 0.45, window_x + window_width * 0.45, float(i) / 4.0)
		_box(facade, Vector3(x, 1.27, 0.022), Vector3(0.029, 0.83, 0.039), timber)
	for y: float in [0.85, 1.12, 1.42, 1.69]:
		_box(facade, Vector3(window_x, y, 0.022), Vector3(window_width + 0.10, 0.042, 0.05), timber)
	for x: float in [window_x - window_width * 0.5 - 0.032, window_x + window_width * 0.5 + 0.032]:
		_box(facade, Vector3(x, 1.27, 0.022), Vector3(0.07, 0.98, 0.055), timber)
	_box(facade, Vector3(window_x, 0.785, 0.005), Vector3(window_width + 0.22, 0.095, 0.14), stone)
	for x: float in [-span * 0.49, span * 0.49]:
		_box(facade, Vector3(x, height * 0.5, 0.018), Vector3(0.075, height, 0.065), timber)
	_box(facade, Vector3(0, height - 0.08, 0.016), Vector3(span, 0.11, 0.065), timber)


func _build_plaster_gables(house: Node3D, width: float, depth: float, height: float, wall: ShaderMaterial) -> void:
	for side: float in [-1.0, 1.0]:
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var x: float = side * (width * 0.5 - 0.035)
		var bottom: Vector3 = Vector3(x, height - 0.04, 0)
		var outline: Array[Vector3] = [Vector3(x, height - 0.04, -depth * 0.5)]
		for i: int in range(13):
			var across: float = -1.0 + float(i) / 6.0
			var point: Vector3 = _roof_point(x, absf(across), width, depth, -1 if across < 0 else 1)
			point.y += height - 0.015
			outline.append(point)
		outline.append(Vector3(x, height - 0.04, depth * 0.5))
		for i: int in range(outline.size() - 1):
			for point: Vector3 in [bottom, outline[i], outline[i + 1]]:
				surface.set_normal(Vector3(side, 0, 0))
				surface.set_uv(Vector2(point.z / maxf(depth, 0.1) + 0.5, point.y / maxf(height, 0.1)))
				surface.add_vertex(point)
		var gable: MeshInstance3D = MeshInstance3D.new()
		gable.name = "PlasterGableEnd"
		gable.mesh = surface.commit()
		gable.material_override = wall
		house.add_child(gable)


func _roof(parent: Node3D, at: Vector3, width: float, depth: float, mat: Material) -> Node3D:
	var roof: Node3D = Node3D.new()
	roof.position = at
	parent.add_child(roof)
	for side: int in [-1, 1]:
		var panel: MeshInstance3D = MeshInstance3D.new()
		panel.mesh = _roof_surface(width, depth, side)
		panel.material_override = mat
		roof.add_child(panel)
		var trim: StandardMaterial3D = _material("#5f6253", "wood")
		for i: int in range(8):
			var a: Vector3 = _roof_point(lerpf(-width * 0.5 - 0.16, width * 0.5 + 0.16, float(i) / 8.0), 1.0, width, depth, side)
			var b: Vector3 = _roof_point(lerpf(-width * 0.5 - 0.16, width * 0.5 + 0.16, float(i + 1) / 8.0), 1.0, width, depth, side)
			_beam(roof, a - Vector3.UP * 0.035, b - Vector3.UP * 0.035, 0.065, trim)
	var ridge: MeshInstance3D = _cylinder(roof, Vector3(0, 0.49, 0), 0.065, width + 0.25, _material("#68756d", "roof"))
	ridge.rotation.z = PI * 0.5
	for side: float in [-1.0, 1.0]:
		_beam(roof, Vector3(side * width * 0.5, 0.48, 0), Vector3(side * (width * 0.5 + 0.16), 0.62, 0), 0.045, _material("#68756d", "roof"))
	return roof


func _roof_point(x: float, t: float, width: float, depth: float, side: int) -> Vector3:
	var tip: float = pow(absf(x) / (width * 0.5 + 0.16), 6.0)
	return Vector3(x, 0.49 * (1.0 - t) + 0.11 * pow(t, 4.0) + tip * 0.10 * t * t, float(side) * (depth * 0.5 + 0.16) * t)


func _roof_surface(width: float, depth: float, side: int) -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: int in range(10):
		for z: int in range(8):
			var x0: float = lerpf(-width * 0.5 - 0.16, width * 0.5 + 0.16, float(x) / 10.0)
			var x1: float = lerpf(-width * 0.5 - 0.16, width * 0.5 + 0.16, float(x + 1) / 10.0)
			var t0: float = float(z) / 8.0
			var t1: float = float(z + 1) / 8.0
			var points: Array[Vector3] = [_roof_point(x0, t0, width, depth, side), _roof_point(x1, t0, width, depth, side), _roof_point(x1, t1, width, depth, side), _roof_point(x0, t1, width, depth, side)]
			var uvs: Array[Vector2] = [Vector2(float(x) / 10.0, t0), Vector2(float(x + 1) / 10.0, t0), Vector2(float(x + 1) / 10.0, t1), Vector2(float(x) / 10.0, t1)]
			var normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
			if normal.y < 0.0:
				normal = -normal
			var order: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3]) if side == 1 else PackedInt32Array([0, 2, 1, 0, 3, 2])
			for index: int in order:
				surface.set_normal(normal)
				surface.set_uv(uvs[index])
				surface.add_vertex(points[index])
	surface.index()
	surface.generate_tangents()
	return surface.commit()


func _sign(parent: Node3D, point: Vector3, text: String, dimensions: Vector2, font_size: int = 38) -> void:
	_box(parent, point, Vector3(dimensions.x, dimensions.y, 0.055), _material("#775b3e", "wood"))
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = font_size
	label.pixel_size = 0.0043
	label.outline_size = 0
	label.modulate = Color("#efe0b9")
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.shaded = false
	label.double_sided = true
	label.position = point + Vector3(0, 0, 0.034)
	parent.add_child(label)


func _lantern(parent: Node3D, point: Vector3) -> void:
	var mat: StandardMaterial3D = _material("#d9a060")
	mat.emission_enabled = true
	mat.emission = Color("#eab977")
	mat.emission_energy_multiplier = 0.22
	_lantern_materials.append(mat)
	var glow: OmniLight3D = OmniLight3D.new()
	glow.position = point + Vector3(0, -0.08, 0.23)
	glow.light_color = Color("#efbd77")
	glow.light_energy = 0.0
	glow.omni_range = 2.1
	glow.shadow_enabled = false
	parent.add_child(glow)
	_lantern_lights.append(glow)

	_cylinder(parent, point, 0.12, 0.30, mat, 0.92)
	for y: float in [-0.17, 0.17]:
		_cylinder(parent, point + Vector3.UP * y, 0.125, 0.035, _material("#6f533a", "wood"))
	_beam(parent, point + Vector3.UP * 0.17, point + Vector3.UP * 0.35, 0.025, _material("#6f533a", "wood"))
	_beam(parent, point - Vector3.UP * 0.18, point - Vector3.UP * 0.33, 0.018, _material("#ae7441"))


func _build_edges() -> void:
	# Roofs, retaining walls and wooded banks continue beyond the playable street.
	# Every new solid lies outside the old walking plane.
	for row: Array in [[-10, 325, 3.8, 1], [1300, 495, 3.3, 2], [-70, 735, 4.6, 3], [1130, 50, 4.8, 4], [490, -230, 5.1, 5], [50, -120, 4.7, 6]]:
		_tree(Vector2(float(row[0]), float(row[1])), float(row[2]), int(row[3]))
	_build_house(Rect2(-245, -100, 365, 230), false, true)
	_build_house(Rect2(840, -130, 440, 260), false, true)
	_build_house(Rect2(300, -360, 350, 205), false, true)
	_build_house(Rect2(690, -395, 280, 195), false, true)
	_build_house(Rect2(1255, 180, 250, 380), false, true)
	_build_house(Rect2(-315, 520, 350, 220), false, true)
	# A visible uphill alley remains the exit destination, behind the flat anchor.
	for step: int in range(13):
		var bounds: Rect2 = Rect2(100, 135 - step * 19, 140, 19)
		var at: Vector3 = logical_to_world(bounds.get_center())
		var height: float = 0.07 + float(step) * 0.105
		_box(world_root, at + Vector3.UP * height * 0.5, Vector3(1.75, height, 0.237), _material("#b6b6a2", "stone"))
		solid_footprints.append(bounds)
	for side: float in [85, 255]:
		for i: int in range(6):
			var y: float = 125 - float(i) * 35
			var at: Vector3 = logical_to_world(Vector2(side, y))
			var rise: float = float(i) * 0.19
			_box(world_root, at + Vector3.UP * (0.43 + rise), Vector3(0.10, 0.86, 0.10), _material("#746649", "wood"))
			if i < 5:
				_beam(world_root, at + Vector3.UP * (0.65 + rise), at + Vector3(0, 0.84 + rise, -0.4375), 0.055, _material("#746649", "wood"))
	_build_hills()


func _build_hills() -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz: int in range(12):
		for ix: int in range(28):
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var x: float = -25 + float(ix + offset.x) * 50.0 / 28.0
				var t: float = float(iz + offset.y) / 12.0
				var z: float = -5.8 - t * 12.0
				var y: float = -0.06 + t * t * (2.5 + sin(x * 0.35) * 1.3 + cos(x * 0.71) * 0.4)
				surface.set_color(Color("#8c9e87").lerp(Color("#a7b8a0"), t * 0.5 + sin(x * 0.3) * 0.12))
				surface.add_vertex(Vector3(x, y, z))
	surface.generate_normals()
	var hills: MeshInstance3D = MeshInstance3D.new()
	hills.name = "RollingRearBank"
	hills.mesh = surface.commit()
	# This shallow backdrop receives the town's shadows. Self-shadowing its
	# broad low-poly slope creates contour bands at the fixed distant camera.
	hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hills.material_override = mat
	world_root.add_child(hills)


func _tree(point: Vector2, height: float, seed: int) -> void:
	var node: Node3D = Node3D.new()
	node.name = "Willow_%d" % seed
	node.position = logical_to_world(point)
	world_root.add_child(node)
	solid_footprints.append(Rect2(point - Vector2(7, 7), Vector2(14, 14)))
	# Authored transparent foliage shares the native illustrated character style.
	# A narrow 3D trunk provides a grounded contact and a restrained real shadow.
	_cylinder(node, Vector3(0, height * 0.23, 0), 0.065, height * 0.46, _material("#79715c", "wood"), 0.55)
	var foliage: Sprite3D = Sprite3D.new()
	foliage.texture = WillowTexture
	foliage.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	foliage.pixel_size = height / 896.0
	foliage.offset = Vector2(0, 422)
	foliage.shaded = true
	foliage.layers = 3
	foliage.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	foliage.alpha_scissor_threshold = 0.18
	foliage.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	foliage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foliage.modulate = Color("#d4d7b7") if seed % 2 else Color("#c6d4c1")
	foliage.set_meta("day_tint", foliage.modulate)
	node.add_child(foliage)
	_leaf_groups.append(foliage)
	var caster: Sprite3D = Sprite3D.new()
	caster.name = "WillowSunShadow"
	caster.texture = WillowTexture
	caster.pixel_size = foliage.pixel_size
	caster.offset = foliage.offset
	caster.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	caster.alpha_scissor_threshold = 0.24
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.shaded = true
	node.add_child(caster)
	_tree_casters.append(caster)
	_contact_pad(node.position, Vector2(0.40, 0.32), 0.28)


func _leaf_spray(parent: Node3D, at: Vector3, seed: int) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors: Array[Color] = [Color("#4b695b"), Color("#617d5c"), Color("#7b9066"), Color("#94a774")]
	for i: int in range(15):
		var angle: float = float(i) * 2.4 + float(seed) * 0.3
		var center: Vector3 = at + Vector3(cos(angle) * 0.38, sin(angle * 1.8) * 0.17, sin(angle) * 0.24)
		var axis: Vector3 = Vector3(cos(angle), sin(angle) * 0.5, 0) * (0.18 + float(i % 3) * 0.045)
		var cross_axis: Vector3 = Vector3(-axis.y, axis.x, 0).normalized() * 0.09
		var points: Array[Vector3] = [center - axis, center - axis * 0.55 + cross_axis * 0.65, center + cross_axis,
			center + axis * 0.6 + cross_axis * 0.65, center + axis, center + axis * 0.55 - cross_axis * 0.55,
			center - cross_axis * 0.9, center - axis * 0.6 - cross_axis * 0.65]
		for edge: int in range(points.size()):
			for vertex: Vector3 in [center, points[edge], points[(edge + 1) % points.size()]]:
				surface.set_color(colors[(i + seed) % colors.size()])
				surface.set_normal(Vector3(0, 0.6, 0.8))
				surface.add_vertex(vertex)
	var leaves: MeshInstance3D = MeshInstance3D.new()
	leaves.mesh = surface.commit()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	leaves.material_override = mat
	parent.add_child(leaves)


func _build_landmarks() -> void:
	var items: Dictionary = _definition.get("interactions", {})
	for id: String in items:
		var position: Array = items[id].position
		var at: Vector3 = logical_to_world(Vector2(float(position[0]), float(position[1])))
		if id == "street_sign":
			# The plaque is suspended from the declared stall. Its support is above
			# head height; the marked ground remains fully walkable.
			var base: Vector3 = logical_to_world(Vector2(690, 470))
			_box(world_root, base + Vector3.UP * 1.25, Vector3(0.06, 2.5, 0.06), _material("#7c674b", "wood"))
			var anchor: Vector3 = base + Vector3.UP * 2.5
			_beam(world_root, anchor, at + Vector3.UP * 2.5, 0.045, _material("#7c674b", "wood"))
			_beam(world_root, at + Vector3.UP * 2.5, at + Vector3.UP * 2.3, 0.012, _material("#7c674b", "wood"))
			_sign(world_root, at + Vector3.UP * 2.1, "集", Vector2(0.44, 0.38), 52)
		elif id == "tea_seller":
			# A light hanging sign suggests the trade without inventing a counter
			# or a new solid obstacle under the NPC's existing free-ground target.
			var outside: Vector3 = logical_to_world(Vector2(1240, 300))
			_box(world_root, outside + Vector3.UP * 1.365, Vector3(0.10, 2.73, 0.10), _material("#7c674b", "wood"))
			solid_footprints.append(Rect2(1236, 296, 8, 8))
			var attachment: Vector3 = logical_to_world(Vector2(850, 260)) + Vector3.UP * 2.45
			_beam(world_root, attachment, outside + Vector3.UP * 2.45, 0.05, _material("#7c674b", "wood"))


func _actor_height(id: String) -> float:
	return float((_actor_frames.get(id, {}) as Dictionary).get("world_height", 1.35))


func _create_actor(id: String) -> void:
	var actor: Sprite3D = Sprite3D.new()
	actor.name = "PlayerBillboard" if id == "player" else "TeaSellerBillboard"
	actor.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	actor.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	actor.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	actor.alpha_scissor_threshold = 0.18
	actor.shaded = true
	actor.layers = 3
	actor.no_depth_test = false
	actor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.visible = false
	world_root.add_child(actor)
	actor_nodes[id] = actor
	var caster: Sprite3D = Sprite3D.new()
	caster.name = id + "SunShadow"
	caster.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	caster.alpha_scissor_threshold = 0.25
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.shaded = true
	world_root.add_child(caster)
	_actor_casters[id] = caster
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.16, 0.16, 0.11, 0.26)
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var fade: GradientTexture2D = GradientTexture2D.new()
	fade.gradient = gradient
	fade.fill = GradientTexture2D.FILL_RADIAL
	fade.fill_from = Vector2(0.5, 0.5)
	fade.fill_to = Vector2(0.5, 1.0)
	fade.width = 32
	fade.height = 32
	mat.albedo_texture = fade
	var shadow: MeshInstance3D = _plane(Vector3.ZERO, Vector2(0.54, 0.27), mat)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow_nodes[id] = shadow


func _update_actor(id: String, point: Vector2, direction: String, walking: bool, stride: float) -> void:
	if not actor_nodes.has(id):
		return
	var actor: Sprite3D = actor_nodes[id]
	actor.position = logical_to_world(point) + Vector3.UP * 0.005
	(shadow_nodes[id] as MeshInstance3D).position = logical_to_world(point) + Vector3.UP * 0.014
	var frames: Dictionary = _actor_frames.get(id, {})
	var row: Array = frames.get(direction, frames.get("down", []))
	if row.is_empty():
		actor.visible = false
		return
	var index: int = posmod(floori(stride / 13.0), row.size()) if walking else 0
	var frame: Texture2D = row[index] as Texture2D
	if frame == null:
		actor.visible = false
		return
	actor.visible = true
	var dusk_tint: float = clampf(float(_slot - 3) / 2.0, 0.0, 1.0)
	# The illustrated source was painted for unlit display. Calibrate its albedo
	# before adding real scene light so sunlit skin retains the painted detail.
	actor.modulate = Color(0.86, 0.88, 0.90).lerp(Color("#bab0b0"), dusk_tint) if lighting_enabled else Color.WHITE.lerp(Color("#cbb9af"), dusk_tint)
	actor.texture = frame
	var frame_size: Vector2 = frames.get("frame_size", frame.get_size())
	var anchor: Vector2 = frames.get("foot_anchor", Vector2(frame_size.x * 0.5, frame_size.y))
	actor.pixel_size = _actor_height(id) / maxf(frame_size.y, 1.0)
	actor.offset = Vector2(frame_size.x * 0.5 - anchor.x, anchor.y - frame_size.y * 0.5)
	var caster: Sprite3D = _actor_casters[id]
	caster.position = logical_to_world(point) + Vector3.UP * 0.005
	caster.texture = frame
	caster.pixel_size = actor.pixel_size
	caster.offset = actor.offset
	caster.rotation.y = sun.rotation.y
	caster.visible = lighting_enabled


func _projected_bounds(node: Node3D) -> Rect2:
	var result: Rect2 = Rect2()
	var initialized: bool = false
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		var aabb: AABB = mesh.get_aabb()
		for index: int in range(8):
			var projected: Vector2 = camera.unproject_position(mesh.global_transform * aabb.get_endpoint(index)) * (DISPLAY / Vector2(viewport.size))
			if not initialized:
				result = Rect2(projected, Vector2.ZERO)
				initialized = true
			else:
				result = result.expand(projected)
	return result


func _update_occlusion(delta: float, snap: bool) -> void:
	var center: Vector2 = logical_to_screen(_player, _actor_height("player") * 0.5)
	var body: Rect2 = Rect2(center - Vector2(22, 40), Vector2(44, 80))
	occluded_count = 0
	for row: Dictionary in roof_rows:
		var nearer: bool = camera.to_local((row.body as Node3D).global_position).z > camera.to_local(logical_to_world(_player)).z - 0.15
		var covered: bool = nearer and _projected_bounds(row.body).intersects(body)
		if covered:
			occluded_count += 1
		var fade: float = float(row.fade)
		if snap:
			fade = 1.0 if covered else 0.0
		elif _active:
			fade = lerpf(fade, 1.0 if covered else 0.0, 1.0 - exp(-delta / 0.12))
		row.fade = fade
		for mat: ShaderMaterial in row.materials:
			mat.set_shader_parameter("fade", fade)
			mat.set_shader_parameter("player_uv", center / DISPLAY)


func _build_backdrop() -> void:
	_backdrop = Sprite3D.new()
	_backdrop.name = "PaintedMountainValley"
	_backdrop.texture = PANORAMA
	_backdrop.pixel_size = 0.024
	_backdrop.scale.x = 1.45
	_backdrop.position = Vector3(0, 5.3, -16.0)
	_backdrop.shaded = false
	_backdrop.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(_backdrop)


func set_time_slot(slot: int) -> void:
	if slot == _slot:
		return
	_slot = clampi(slot, 0, 5)
	_apply_lighting()


func _apply_lighting() -> void:
	var dusk: float = clampf(float(_slot - 3) / 2.0, 0.0, 1.0)
	sun.light_color = Color("#fff4e6").lerp(Color("#edb17e"), dusk)
	sun.light_energy = lerpf(0.70, 0.47, dusk)
	sun.rotation_degrees = Vector3(lerpf(-46, -24, dusk), -32, 0)
	environment.ambient_light_color = Color("#c9d4d7").lerp(Color("#aab5c9"), dusk)
	environment.ambient_light_energy = lerpf(0.48, 0.38, dusk)
	if is_instance_valid(_backdrop):
		_backdrop.modulate = Color.WHITE.lerp(Color("#c9b4a4"), dusk)
	for mat: StandardMaterial3D in _lantern_materials:
		mat.emission_energy_multiplier = lerpf(0.22, 1.1, dusk)
	for light: OmniLight3D in _lantern_lights:
		light.light_energy = dusk * 0.52
	if lighting_enabled:
		sun.light_color = Color("#ffe8cb").lerp(Color("#efad79"), dusk)
		sun.light_energy = lerpf(0.76, 0.58, dusk)
		sun.rotation_degrees = Vector3(lerpf(-38, -23, dusk), -58, 0)
		environment.ambient_light_color = Color("#b4cadc").lerp(Color("#9eabc4"), dusk)
		environment.ambient_light_energy = lerpf(0.34, 0.29, dusk)
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		environment.fog_enabled = true
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		environment.fog_depth_begin = 20.0
		environment.fog_depth_end = 47.0
		environment.fog_density = 0.30
		environment.fog_light_color = Color("#bdcbd0").lerp(Color("#b2a8a2"), dusk)
		environment.fog_light_energy = 0.65
	else:
		environment.fog_enabled = false
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	sun.shadow_blur = 1.8 if lighting_enabled else 1.0
	sun.shadow_bias = 0.045 if lighting_enabled else 0.035
	sun.shadow_normal_bias = 0.85 if lighting_enabled else 0.8
	_character_fill.light_energy = lerpf(0.25, 0.20, dusk) if lighting_enabled else 0.0
	for key: String in _materials:
		var mat: StandardMaterial3D = _materials[key]
		var kind: String = mat.get_meta("kind", "plaster")
		mat.roughness = 0.96
		mat.albedo_color = mat.get_meta("baseline_color")
		mat.albedo_texture = mat.get_meta("baseline_texture")
		if lighting_enabled:
			mat.roughness = 0.62 if kind == "wood" else 0.82 if kind == "stone" else 0.93
			if kind == "ceramic":
				mat.roughness = 0.24
				mat.albedo_texture = null
				mat.albedo_color = mat.get_meta("original_color")
	for mat: ShaderMaterial in _lighting_materials:
		mat.set_shader_parameter("lighting_strength", 1.0 if lighting_enabled else 0.0)
	for patch: MeshInstance3D in _contact_nodes:
		patch.visible = lighting_enabled
	for id: String in actor_nodes:
		(actor_nodes[id] as Sprite3D).shaded = lighting_enabled
		(_actor_casters[id] as Sprite3D).visible = lighting_enabled
		var contact: MeshInstance3D = shadow_nodes[id]
		(contact.material_override as StandardMaterial3D).albedo_color.a = 0.18 if lighting_enabled else 0.26
	for caster: Sprite3D in _tree_casters:
		caster.visible = lighting_enabled
		caster.rotation.y = sun.rotation.y
	if is_instance_valid(_water_material):
		_water_material.set_shader_parameter("lighting_strength", 1.0 if lighting_enabled else 0.0)
	for node: Node3D in _leaf_groups:
		if node is Sprite3D:
			(node as Sprite3D).shaded = lighting_enabled
			var tint: Color = node.get_meta("day_tint", Color.WHITE)
			(node as Sprite3D).modulate = tint.lerp(Color("#9ba69c"), dusk * 0.65)
	_update_tea_patron()
	if is_instance_valid(_painted_street):
		_painted_street.call("apply", lighting_enabled)


func set_motion_enabled(enabled: bool) -> void:
	motion_enabled = enabled


func _decorate_house(house: Node3D, width: float, depth: float, height: float, stall: bool, backdrop: bool) -> void:
	var wood: StandardMaterial3D = _material("#6d5845", "wood")
	var front: float = depth * 0.5 + 0.02
	if not stall:
		# Timber bay rhythm and a dark eave make the pale facade readable.
		for fraction: float in [-0.47, -0.19, 0.19, 0.47]:
			_box(house, Vector3(width * fraction, height * 0.5, front), Vector3(0.065, height, 0.065), wood)
		_box(house, Vector3(0, 0.49, front + 0.005), Vector3(width - 0.10, 0.06, 0.05), wood)
		for i: int in range(14):
			var x: float = lerpf(-width * 0.49, width * 0.49, float(i) / 13.0)
			_beam(house, Vector3(x, height - 0.10, front - 0.06), Vector3(x, height + 0.04, front + 0.22), 0.035, wood)
		if not backdrop:
			var cloth: Node3D = Node3D.new()
			cloth.position = Vector3(-width * 0.36, 1.72, front + 0.09)
			house.add_child(cloth)
			_cloth.append(cloth)
			for i: int in range(3):
				_box(cloth, Vector3(float(i - 1) * 0.19, -0.25, 0), Vector3(0.175, 0.50 + float(i % 2) * 0.04, 0.014), _material("#748e8a"))
			_sign(cloth, Vector3(0, -0.24, 0.013), "茶", Vector2(0.15, 0.23), 36)
	else:
		var tray: Vector3 = Vector3(0.42, 0.76, depth * 0.23)
		_box(house, tray, Vector3(0.90, 0.045, 0.45), wood)
		_teapot(house, tray + Vector3(0.12, 0.10, 0), 0.72)
		for x: float in [-0.25, -0.05]:
			_cylinder(house, tray + Vector3(x, 0.055, 0.12), 0.065, 0.075, _material("#d7ded0", "ceramic"), 1.15)
		for x: float in [-width * 0.36, -width * 0.12]:
			_basket(house, Vector3(x, 0.79, -0.20), 0.22)
		# Stool stays inside the already blocked stall footprint.
		_box(house, Vector3(width * 0.33, 0.25, -depth * 0.30), Vector3(0.36, 0.08, 0.30), wood)
		for x: float in [-0.11, 0.11]:
			_box(house, Vector3(width * 0.33 + x, 0.12, -depth * 0.30), Vector3(0.05, 0.22, 0.24), wood)
		_make_steam(house.position + tray + Vector3(0.12, 0.30, 0))


func _teapot(parent: Node3D, at: Vector3, scale_value: float) -> void:
	var pot: Node3D = Node3D.new()
	pot.position = at
	pot.scale = Vector3.ONE * scale_value
	parent.add_child(pot)
	var clay: StandardMaterial3D = _material("#597e79", "ceramic")
	_cylinder(pot, Vector3(0, 0.08, 0), 0.16, 0.22, clay, 0.8)
	_cylinder(pot, Vector3(0, 0.21, 0), 0.12, 0.025, clay)
	_cylinder(pot, Vector3(0, 0.24, 0), 0.036, 0.045, clay)
	_beam(pot, Vector3(0.10, 0.08, 0), Vector3(0.30, 0.19, 0), 0.065, clay)
	var handle: MeshInstance3D = MeshInstance3D.new()
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 0.065
	ring.outer_radius = 0.105
	ring.rings = 12
	ring.ring_segments = 8
	handle.mesh = ring
	handle.material_override = clay
	handle.position = Vector3(-0.14, 0.1, 0)
	handle.rotation.x = PI * 0.5
	pot.add_child(handle)


func _basket(parent: Node3D, at: Vector3, radius: float) -> void:
	var wicker: StandardMaterial3D = _material("#b39b6c", "wood")
	_cylinder(parent, at, radius, 0.20, wicker, 1.14)
	for i: int in range(8):
		var angle: float = float(i) / 8.0 * TAU
		_beam(parent, at + Vector3(cos(angle) * radius, -0.1, sin(angle) * radius), at + Vector3(cos(angle) * radius * 1.14, 0.1, sin(angle) * radius * 1.14), 0.015, _material("#76664d", "wood"))


func _build_tea_details() -> void:
	# The tea counter belongs to the right-side shop, clear of the walkable floor.
	var wood: StandardMaterial3D = _material("#917650", "wood")
	var side: Vector3 = logical_to_world(Vector2(1260, 385))
	_box(world_root, side + Vector3.UP * 0.42, Vector3(0.75, 0.84, 1.75), wood)
	solid_footprints.append(Rect2(1230, 315, 60, 140))
	_teapot(world_root, side + Vector3(0, 0.87, 0.25), 0.9)
	_make_steam(side + Vector3(0, 1.16, 0.25))
	for z: float in [-0.45, -0.15]:
		_cylinder(world_root, side + Vector3(-0.15, 0.88, z), 0.075, 0.09, _material("#d7ded0", "ceramic"), 1.1)
	_basket(world_root, side + Vector3(0, 0.13, 1.1), 0.31)


func _make_steam(at: Vector3) -> void:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
	var texture_value: GradientTexture2D = GradientTexture2D.new()
	texture_value.gradient = gradient
	texture_value.width = 48
	texture_value.height = 48
	texture_value.fill = GradientTexture2D.FILL_RADIAL
	texture_value.fill_from = Vector2(0.5, 0.5)
	texture_value.fill_to = Vector2(0.5, 1)
	for i: int in range(7):
		var puff: Sprite3D = Sprite3D.new()
		puff.texture = texture_value
		puff.pixel_size = 0.011
		puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		puff.shaded = false
		puff.no_depth_test = false
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.set_meta("origin", at)
		puff.set_meta("phase", float(i) / 7.0)
		world_root.add_child(puff)
		_steam.append(puff)
	_update_ambient()


func _update_ambient() -> void:
	_update_tea_patron()
	if actor_nodes.has("tea_seller"):
		var frame: Texture2D = _seller_life.call("frame_at", ambient_elapsed, motion_enabled, _active)
		var seller: Sprite3D = actor_nodes["tea_seller"]
		seller.texture = frame
		if _actor_casters.has("tea_seller"):
			var caster: Sprite3D = _actor_casters["tea_seller"]
			caster.texture = frame
			caster.pixel_size = seller.pixel_size
			caster.offset = seller.offset

	if is_instance_valid(_water_material):
		_water_material.set_shader_parameter("phase", ambient_elapsed)
	for cloth_material: ShaderMaterial in _cloth_materials:
		cloth_material.set_shader_parameter("phase", ambient_elapsed)
	for puff: Sprite3D in _steam:
		var phase: float = fposmod(ambient_elapsed * 0.22 + float(puff.get_meta("phase")), 1.0)
		var at: Vector3 = puff.get_meta("origin")
		puff.position = at + Vector3(sin(phase * 4.0 + ambient_elapsed * 0.4) * phase * 0.13, phase * 0.85, 0)
		puff.scale = Vector3.ONE * (0.23 + phase * 0.7)
		puff.modulate.a = sin(phase * PI) * 0.7
	for i: int in range(_cloth.size()):
		_cloth[i].rotation.z = sin(ambient_elapsed * 1.1 + float(i)) * 0.035
	for i: int in range(_leaf_groups.size()):
		_leaf_groups[i].rotation.z = sin(ambient_elapsed * 0.75 + float(i) * 0.6) * 0.012


func _build_tea_awning() -> void:
	var canopy: Node3D = Node3D.new()
	canopy.name = "TeaClothAwning"
	canopy.position = logical_to_world(Vector2(1035, 180)) + Vector3.UP * 2.72
	world_root.add_child(canopy)
	# All anchors are fixed above head height. Only the cloth's free surface
	# deforms; poles and the building connection do not rock with the wind.
	_sun_occluders.append(AABB(canopy.position + Vector3(-2.38, -0.42, 0), Vector3(4.73, 0.55, 1.64)))
	var timber: StandardMaterial3D = _material("#786244", "wood")
	_beam(canopy, Vector3(-2.43, 0.10, 0), Vector3(2.43, 0.10, 0), 0.065, timber)
	_beam(canopy, Vector3(-2.43, -0.18, 1.62), Vector3(2.57, -0.18, 1.62), 0.055, timber)
	for side: float in [-1.0, 1.0]:
		_beam(canopy, Vector3(side * 2.36, 0.11, -0.02), Vector3(side * 2.36, -0.18, 1.65), 0.025,
			_material("#9b8660", "flat"))
		# The small lashings sit at the actual rail corners.
		for z: float in [0.02, 1.58]:
			for i: int in range(3):
				_box(canopy, Vector3(side * 2.36, 0.13 - z * 0.18, z + float(i) * 0.016),
					Vector3(0.09, 0.075, 0.009), _material("#b9a67e", "flat"))
	var canvas_material: ShaderMaterial = _make_canvas_material(false)
	var cloth: MeshInstance3D = MeshInstance3D.new()
	cloth.name = "SaggedWovenLinen"
	cloth.material_override = canvas_material
	canopy.add_child(cloth)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix: int in range(24):
		for iz: int in range(12):
			var u0: float = float(ix) / 24.0
			var u1: float = float(ix + 1) / 24.0
			var v0: float = float(iz) / 12.0
			var v1: float = float(iz + 1) / 12.0
			for uv: Vector2 in [Vector2(u0, v0), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1)]:
				surface.set_uv(uv)
				surface.add_vertex(_canopy_point(uv))
	surface.generate_normals()
	cloth.mesh = surface.commit()
	# A short scalloped valance is cloth geometry, rather than rigid box strips.
	var valance: MeshInstance3D = MeshInstance3D.new()
	valance.name = "LinenScallopedEdge"
	valance.material_override = _make_canvas_material(true)
	canopy.add_child(valance)
	surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(72):
		var u0: float = float(i) / 72.0
		var u1: float = float(i + 1) / 72.0
		for uv: Vector2 in [Vector2(u0, 0), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1)]:
			var at: Vector3 = _canopy_point(Vector2(uv.x, 1.0))
			at.y -= 0.012 + uv.y * (0.16 + sin(uv.x * TAU * 6.0 - PI * 0.5) * 0.028)
			at.z += 0.012 + sin(uv.x * TAU * 6.0) * uv.y * 0.008
			surface.set_uv(uv)
			surface.add_vertex(at)
	surface.generate_normals()
	valance.mesh = surface.commit()
	_build_linen_tea_flag()


func _canopy_point(uv: Vector2) -> Vector3:
	var sag: float = sin(uv.y * PI) * 0.145
	var seams: float = cos(uv.x * TAU * 6.0) * 0.014 * sin(uv.y * PI)
	return Vector3(-2.38 + uv.x * 4.73, 0.11 - uv.y * 0.28 - sag + seams, uv.y * 1.62)


func _make_canvas_material(hanging: bool) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 linen_color : source_color = vec4(0.85, 0.79, 0.64, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.60, 0.38, 0.25, 1.0);
uniform float phase = 0.0;
uniform float hanging = 0.0;
void vertex() {
    float wave = sin(UV.x * 12.0 + UV.y * 5.0 + phase * 0.85);
    float envelope = sin(UV.x * 3.141593) * sin(UV.y * 3.141593);
    VERTEX.y += wave * envelope * 0.012 * (1.0 - hanging);
    VERTEX.z += wave * UV.y * 0.010 * hanging;
}
void fragment() {
    float stripe_distance = abs(fract(UV.x * 6.0) - 0.5);
    float stripe = 1.0 - smoothstep(0.12, 0.16, stripe_distance);
    float seam = 1.0 - smoothstep(0.007, 0.020, abs(stripe_distance - 0.19));
    float wash = sin(UV.x * 19.0 + sin(UV.y * 9.0)) * 0.018 + sin(UV.y * 15.0) * 0.012;
    float grain_lod = 1.0 - smoothstep(0.25, 0.65, max(fwidth(UV.x) * 70.0, fwidth(UV.y) * 37.0));
    float weave = sin(UV.x * 440.0) * sin(UV.y * 230.0) * 0.012 * grain_lod;
    ALBEDO = mix(linen_color.rgb, stripe_color.rgb, stripe * 0.79) * (0.97 + wash + weave - seam * 0.045);
    ROUGHNESS = 0.94;
    SPECULAR = 0.12;
}
"""
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("linen_color", Color("#d9c9a4"))
	mat.set_shader_parameter("stripe_color", Color("#9b6242"))
	mat.set_shader_parameter("hanging", 1.0 if hanging else 0.0)
	_cloth_materials.append(mat)
	return mat


func _build_linen_tea_flag() -> void:
	var flag: Node3D = Node3D.new()
	flag.name = "HangingLinenTeaFlag"
	# Suspend it from the outside support, away from the traversable shop front.
	# A central hanging flag covered the face of a player walking behind it.
	flag.position = logical_to_world(Vector2(1238, 307)) + Vector3.UP * 2.65
	world_root.add_child(flag)
	_cloth.append(flag)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(8):
		var x0: float = -0.27 + float(i) * 0.54 / 8.0
		var x1: float = -0.27 + float(i + 1) * 0.54 / 8.0
		for at: Vector3 in [Vector3(x0, -0.015, 0), Vector3(x1, -0.76, 0), Vector3(x1, -0.015, 0), Vector3(x0, -0.015, 0), Vector3(x0, -0.76, 0), Vector3(x1, -0.76, 0)]:
			at.z = cos(at.x * 9.0) * 0.018
			surface.set_uv(Vector2((at.x + 0.27) / 0.54, -at.y / 0.76))
			surface.add_vertex(at)
	surface.generate_normals()
	var cloth: MeshInstance3D = MeshInstance3D.new()
	cloth.name = "LinenTeaFlagCloth"
	cloth.mesh = surface.commit()
	var mat: StandardMaterial3D = _material("#d4bd91", "flat")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = mat
	flag.add_child(cloth)
	for y: float in [-0.015, -0.76]:
		_box(flag, Vector3(0, y, 0.005), Vector3(0.59, 0.035, 0.045), _material("#8a6042", "flat"))
	for x: float in [-0.25, 0.25]:
		_box(flag, Vector3(x, -0.385, 0.021), Vector3(0.027, 0.70, 0.014), _material("#a6774e", "flat"))
	var tea_letter: Label3D = Label3D.new()
	tea_letter.text = "茶"
	tea_letter.font = _font
	tea_letter.font_size = 86
	tea_letter.pixel_size = 0.0048
	tea_letter.outline_size = 0
	tea_letter.modulate = Color("#71523d")
	tea_letter.position = Vector3(0, -0.38, 0.044)
	flag.add_child(tea_letter)


func _build_riverfront() -> void:
	# Water and masonry lie beyond the playable floor (bottom y=650).
	var river_shader: Shader = Shader.new()
	river_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float phase = 0.0;
uniform float lighting_strength = 1.0;
uniform sampler2D reflection_texture : source_color, filter_linear, repeat_disable;
uniform mat4 reflection_view_projection;
uniform float reflection_strength = 0.0;
varying vec3 world_at;
void vertex() {
    world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    float ribbon = sin(UV.y * 180.0 + sin(UV.x * 25.0 + phase * 0.15) * 0.45 + phase * 0.4);
    float cross = sin(UV.y * 360.0 + UV.x * 28.0 - phase * 0.20);
    vec3 water_color = mix(vec3(0.22, 0.37, 0.36), vec3(0.39, 0.54, 0.49), ribbon * 0.028 + cross * 0.013 + 0.43);
    float bank = exp(-max(UV.y, 0.0) * 17.0);
    float wash = sin(UV.x * 17.0 + UV.y * 8.0) * 0.025 + sin(UV.y * 36.0) * 0.012;
    water_color *= 1.0 - bank * 0.20 + wash;
    vec4 clip = reflection_view_projection * vec4(world_at, 1.0);
    vec2 projected_uv = clip.xy / max(clip.w, 0.0001) * 0.5 + 0.5;
    projected_uv.y = 1.0 - projected_uv.y;
    vec2 ripple = vec2(sin(world_at.z * 8.0 + phase * 0.65 + sin(world_at.x * 3.0)) * 0.0021,
        sin(world_at.x * 5.0 - phase * 0.38) * 0.0009);
    vec2 reflected_uv = clamp(projected_uv + ripple, vec2(0.003), vec2(0.997));
    vec2 texel = vec2(1.0 / 512.0, 1.0 / 288.0);
    vec3 reflected = texture(reflection_texture, reflected_uv).rgb * 0.40;
    reflected += texture(reflection_texture, reflected_uv + vec2(texel.x * 1.2, 0.0)).rgb * 0.15;
    reflected += texture(reflection_texture, reflected_uv - vec2(texel.x * 1.2, 0.0)).rgb * 0.15;
    reflected += texture(reflection_texture, reflected_uv + vec2(0.0, texel.y * 1.2)).rgb * 0.15;
    reflected += texture(reflection_texture, reflected_uv - vec2(0.0, texel.y * 1.2)).rgb * 0.15;
    float in_view = step(0.0001, clip.w) * step(0.0, projected_uv.x) * step(projected_uv.x, 1.0)
        * step(0.0, projected_uv.y) * step(projected_uv.y, 1.0);
    float reflection_mix = reflection_strength * in_view * (0.85 + 0.15 * bank);
    // The sampled view already contains scene lighting. Add its radiance only
    // once, while the base water still receives the existing sun and shadows.
    ALBEDO = water_color * (1.0 - reflection_mix * 0.65);
    EMISSION = reflected * vec3(0.77, 0.91, 0.87) * reflection_mix;
    ROUGHNESS = mix(0.85, 0.34, lighting_strength);
    NORMAL_MAP = vec3(0.5 + cos(UV.x * 25.0 + phase * 0.15) * 0.035 * lighting_strength,
        0.5 + sin(UV.y * 90.0 + phase * 0.4) * 0.035 * lighting_strength, 1.0);
    NORMAL_MAP_DEPTH = 0.55;
}
"""
	_water_material = ShaderMaterial.new()
	_water_material.shader = river_shader
	var river: MeshInstance3D = _plane(Vector3(0, -0.28, 8.0), Vector2(46, 8.0), _water_material)
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reflection_exclusions.append(river)
	var surface_art = StreetSurfaceArt.new()
	var stone: ShaderMaterial = surface_art.make_bank_material()
	var cap_stone: ShaderMaterial = surface_art.make_flagstone_material()
	cap_stone.set_shader_parameter("base_color", Color("#aeb49f"))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 291030
	var bank_x: float = -14.0
	while bank_x < 14.0:
		var span: float = rng.randf_range(0.60, 1.04)
		var center: float = bank_x + span * 0.5
		var bank_z: float = 3.94 + sin(center * 0.72) * 0.06
		var bank_body: MeshInstance3D = _box(world_root, Vector3(center, -0.17, bank_z), Vector3(span - 0.015, 0.43, 0.58), stone)
		_reflection_exclusions.append(bank_body)
		var cap: MeshInstance3D = MeshInstance3D.new()
		cap.mesh = _flagstone_mesh(rng.randi_range(0, 5))
		cap.scale = Vector3(span + 0.025, 2.0, 0.82)
		cap.position = Vector3(center, 0.09 + rng.randf_range(-0.006, 0.006), bank_z - 0.03)
		cap.material_override = cap_stone
		world_root.add_child(cap)
		if rng.randf() < 0.28:
			var moss: MeshInstance3D = _plane(Vector3(center, 0.095, bank_z - 0.33), Vector2(span * 0.43, 0.07), _material("#6f8067", "flat"))
			moss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bank_x += span
	# Worn landing steps and a mooring post are scenery beyond the floor edge.
	for i: int in range(3):
		_box(world_root, Vector3(-3.25, -0.025 - float(i) * 0.085, 4.24 + float(i) * 0.27), Vector3(1.52 - float(i) * 0.08, 0.14, 0.42), stone)
	_cylinder(world_root, Vector3(-2.33, 0.25, 4.03), 0.075, 0.48, _material("#7f6b4c", "wood"), 0.86)
	for i: int in range(10):
		var u0: float = float(i) / 10.0
		var u1: float = float(i + 1) / 10.0
		var a: Vector3 = Vector3(-2.33, 0.34, 4.03).lerp(Vector3(0.84, 0.19, 5.67), u0)
		var b: Vector3 = Vector3(-2.33, 0.34, 4.03).lerp(Vector3(0.84, 0.19, 5.67), u1)
		a.y -= sin(u0 * PI) * 0.13
		b.y -= sin(u1 * PI) * 0.13
		_beam(world_root, a, b, 0.018, _material("#a38f63", "flat"))
	# A moored skiff gives the foreground water a human scale.
	var boat: Node3D = Node3D.new()
	boat.name = "MooredRiverSkiff"
	boat.position = Vector3(3.0, -0.16, 6.0)
	boat.rotation.y = -0.15
	world_root.add_child(boat)
	var wood: StandardMaterial3D = _material("#705b42", "wood")
	for i: int in range(22):
		var x0: float = -2.2 + float(i) * 0.2
		var x1: float = x0 + 0.2
		var w0: float = sqrt(maxf(0, 1.0 - pow(x0 / 2.2, 2.0))) * 0.55
		var w1: float = sqrt(maxf(0, 1.0 - pow(x1 / 2.2, 2.0))) * 0.55
		var rise0: float = pow(absf(x0) / 2.2, 4.0) * 0.28
		var rise1: float = pow(absf(x1) / 2.2, 4.0) * 0.28
		_box(boat, Vector3((x0 + x1) * 0.5, 0.015, 0), Vector3(0.195, 0.08, maxf(0.06, w0 + w1 - 0.09)), wood)
		for side: float in [-1, 1]:
			for course: int in range(3):
				_beam(boat, Vector3(x0, 0.04 + float(course) * 0.09 + rise0, w0 * side), Vector3(x1, 0.04 + float(course) * 0.09 + rise1, w1 * side), 0.10, wood)
	for x: float in [-1.05, 0.10, 1.05]:
		_box(boat, Vector3(x, 0.23, 0), Vector3(0.23, 0.08, 0.90), _material("#a08a60", "wood"))
	_basket(boat, Vector3(0.5, 0.18, 0), 0.26)
	_beam(boat, Vector3(-0.7, 0.30, -0.3), Vector3(1.5, 0.40, 0.8), 0.045, wood)


func _setup_river_reflection() -> void:
	if is_instance_valid(_river_reflection) or not is_inside_tree() or _water_material == null:
		return
	var reflection = RiverReflection.new()
	reflection.name = "RiverPlanarReflection"
	add_child(reflection)
	if not reflection.setup(viewport, camera, -0.28):
		reflection.queue_free()
		return
	_river_reflection = reflection
	for item: GeometryInstance3D in _reflection_exclusions:
		reflection.exclude_geometry(item)
	reflection.bind_water_material(_water_material)
	_water_material.set_shader_parameter("reflection_strength", 0.30)


func _build_riverbank_plants() -> void:
	# Sparse reeds grow in wet joints beyond the old floor boundary (z=3.125).
	# Each clump pivots at its own root on the shared ambient clock.
	for location: Vector3 in [Vector3(-6.7, -0.20, 4.34), Vector3(-4.85, -0.18, 4.16), Vector3(6.1, -0.18, 4.20)]:
		var clump: Node3D = Node3D.new()
		clump.name = "RiverbankReeds"
		clump.position = location
		world_root.add_child(clump)
		_leaf_groups.append(clump)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 291030 + roundi(absf(location.x) * 37.0)
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for blade: int in range(23):
			var angle: float = rng.randf_range(0, TAU)
			var height: float = rng.randf_range(0.22, 0.58)
			var lean: Vector3 = Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(0.08, 0.24)
			var root_at: Vector3 = Vector3(rng.randf_range(-0.20, 0.20), 0, rng.randf_range(-0.11, 0.11))
			var across: Vector3 = Vector3(-sin(angle), 0, cos(angle)) * rng.randf_range(0.014, 0.029)
			var tone: Color = Color("#758568").lerp(Color("#a49e6e"), rng.randf() * 0.65)
			for step: int in range(3):
				var u0: float = float(step) / 3.0
				var u1: float = float(step + 1) / 3.0
				var a: Vector3 = root_at + Vector3.UP * height * u0 + lean * u0 * u0
				var b: Vector3 = root_at + Vector3.UP * height * u1 + lean * u1 * u1
				var points: Array[Vector3] = [a - across * (1.0 - u0), a + across * (1.0 - u0), b + across * (1.0 - u1), b - across * (1.0 - u1)]
				for index: int in [0, 2, 1, 0, 3, 2]:
					surface.set_color(tone.lerp(Color("#b7ad7b"), u0 * 0.18))
					surface.set_normal(Vector3(0, 0.7, 0.7))
					surface.add_vertex(points[index])
		var reeds: MeshInstance3D = MeshInstance3D.new()
		reeds.mesh = surface.commit()
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		reeds.material_override = mat
		reeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		clump.add_child(reeds)


func _contact_pad(at: Vector3, footprint: Vector2, opacity: float) -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _contact_shader
	mat.set_shader_parameter("strength", opacity)
	var pad: MeshInstance3D = _plane(at + Vector3.UP * 0.006, footprint + Vector2(0.55, 0.55), mat)
	pad.name = "LocalContactOcclusion"
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_contact_nodes.append(pad)


func set_lighting_enabled(enabled: bool) -> void:
	lighting_enabled = enabled
	if is_instance_valid(sun):
		_apply_lighting()


func light_at(point: Vector2) -> Dictionary:
	# Read-only approximate ray audit for opaque architecture. Rendered pixel
	# captures remain the evidence for shadows actually received by the sprites.
	var sample: Vector3 = logical_to_world(point) + Vector3(0, 1.1, -0.50)
	var direction: Vector3 = sun.basis.z.normalized()
	var visibility: float = 1.0
	for box: AABB in _sun_occluders:
		var hit: Variant = box.intersects_ray(sample, direction)
		if hit is Vector3 and (hit as Vector3).distance_to(sample) < 30.0:
			visibility = 0.0
			break
	return {"sun_visibility": visibility, "occlusion": 1.0 - visibility,
		"sample_height": 1.1, "method": "architecture_ray_approximation",
		"lighting_enabled": lighting_enabled}
