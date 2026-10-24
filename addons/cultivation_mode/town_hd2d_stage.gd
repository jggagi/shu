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

const WORLD_SCALE: float = 80.0
const DISPLAY: Vector2 = Vector2(1280, 720)
const ORIGIN: Vector2 = Vector2(640, 400)
const CAMERA_ANGLE: float = 38.0
const CAMERA_DISTANCE: float = 17.1
const ROOF_SHADER: String = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 surface_color : source_color = vec4(1.0);
uniform vec2 repeat_uv = vec2(1.0);
uniform vec2 player_uv = vec2(0.5);
uniform float fade = 0.0;
void fragment() {
    vec2 delta = (SCREEN_UV - player_uv) * vec2(1280.0, 720.0);
    float local = 1.0 - smoothstep(44.0, 92.0, length(delta));
    float pattern = fract(sin(dot(floor(UV * vec2(680.0, 300.0)), vec2(12.9898, 78.233))) * 43758.5453);
    if (pattern < local * fade * 0.88) { discard; }
    ALBEDO = texture(surface_texture, UV * repeat_uv).rgb * surface_color.rgb;
    ROUGHNESS = 0.95;
}
"""

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
	camera.rotation_degrees = Vector3(-CAMERA_ANGLE, 0, 0)
	world_root.add_child(camera)
	camera.current = true
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#cbd0b9")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c9d4d7")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sky: WorldEnvironment = WorldEnvironment.new()
	sky.environment = environment
	world_root.add_child(sky)
	sun = DirectionalLight3D.new()
	sun.name = "WarmAfternoonSun"
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("#fff1dc")
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 32.0
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 0.8
	world_root.add_child(sun)
	_roof_shader = Shader.new()
	_roof_shader.code = ROOF_SHADER
	_build_ground()
	var boxes: Array = _definition.get("obstacles", [])
	for index: int in range(boxes.size()):
		var box: Array = boxes[index]
		var bounds: Rect2 = Rect2(float(box[0]), float(box[1]), float(box[2]), float(box[3]))
		geometry.append(bounds)
		_build_house(bounds, index == 0, false)
	_build_edges()
	_build_landmarks()
	_create_actor("player")
	_create_actor("tea_seller")
	_last_tick = Time.get_ticks_usec()
	_first_sync = true


func _ready() -> void:
	if is_instance_valid(camera):
		_update_occlusion(1.0, true)


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
	var height: float = _actor_height("tea_seller") * 0.52 if id == "tea_seller" else 1.0 if id == "street_sign" else 0.04
	return logical_to_screen(point, height)


func resize_view(size: Vector2i) -> void:
	if not is_instance_valid(viewport):
		return
	var scale: float = clampf(minf(float(size.x) / DISPLAY.x, float(size.y) / DISPLAY.y), 0.375, 1.0)
	var desired: Vector2i = Vector2i(maxi(480, roundi(DISPLAY.x * scale)), maxi(270, roundi(DISPLAY.y * scale)))
	if viewport.size != desired:
		viewport.size = desired


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


func audit() -> Dictionary:
	var footprints: Array = []
	for bounds: Rect2 in solid_footprints:
		footprints.append([bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y])
	return {"render_size": viewport.size if is_instance_valid(viewport) else Vector2i.ZERO,
		"viewport_size": viewport.size if is_instance_valid(viewport) else Vector2i.ZERO,
		"camera_position": camera.position if is_instance_valid(camera) else Vector3.ZERO,
		"geometry": geometry.duplicate(), "solid_footprints": footprints, "occluded_roofs": occluded_count,
		"actor_count": actor_nodes.size(), "building_count": geometry.size(), "projection": "perspective",
		"actor_position": _player, "active": _active}


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
	mat.roughness = 0.96
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if kind != "flat":
		mat.albedo_texture = _surface_texture(kind)
	_materials[key] = mat
	return mat


func _surface_texture(kind: String) -> ImageTexture:
	if _surface_textures.has(kind):
		return _surface_textures[kind]
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y: int in range(64):
		for x: int in range(64):
			var grain: float = float((x * 13 + y * 7 + (x * y) % 19) % 11) / 10.0
			var value: float = 0.93 + grain * 0.055
			if kind == "wood":
				value = 0.83 + grain * 0.04 + sin(float(x) * 0.57 + sin(float(y) * 0.15)) * 0.045
			elif kind == "stone":
				value = 0.93 + grain * 0.035
				if x < 1 or y < 1:
					value -= 0.08
			elif kind == "roof":
				value = 0.76 + sin(float(x % 16) / 16.0 * PI) * 0.19
				if y % 16 < 2:
					value -= 0.10
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
	mat.set_shader_parameter("repeat_uv", repeats)
	mat.set_shader_parameter("fade", 0.0)
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
	_plane(Vector3(0, -0.08, 0), Vector2(42, 34), _material("#b3b7a4", "flat"))
	var stones: MultiMeshInstance3D = MultiMeshInstance3D.new()
	stones.name = "StoneStreet"
	stones.multimesh = MultiMesh.new()
	stones.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	stones.multimesh.use_colors = true
	var slab: BoxMesh = BoxMesh.new()
	slab.size = Vector3(0.55, 0.055, 0.38)
	stones.multimesh.mesh = slab
	stones.material_override = _material("#d3c6a6", "stone")
	(stones.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
	stones.multimesh.instance_count = 29 * 18
	for z: int in range(18):
		for x: int in range(29):
			var index: int = z * 29 + x
			var at: Vector3 = Vector3(-8.15 + float(x) * 0.565 + (0.14 if z % 2 else 0.0), -0.028, -3.5 + float(z) * 0.395)
			stones.multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, at))
			var tone: float = 0.94 + float((index * 17 + z) % 7) * 0.011
			stones.multimesh.set_instance_color(index, Color(tone, tone, tone))
	world_root.add_child(stones)
	# An inset border and flat path inlays are walkable ground, never extra walls.
	for x: float in [-7.7, 7.7]:
		_plane(Vector3(x, 0.003, 0), Vector2(0.10, 6.6), _material("#9b9b7d", "stone"))
	for y: int in range(185, 260, 15):
		_plane(logical_to_world(Vector2(160, y)) + Vector3.UP * 0.006, Vector2(0.75, 0.07), _material("#b5b599", "stone"))


func _build_house(bounds: Rect2, stall: bool, backdrop: bool) -> void:
	var house: Node3D = Node3D.new()
	house.name = "MarketShelter" if stall else "NorthShop" if not backdrop else "BackgroundHouse"
	house.position = logical_to_world(bounds.get_center())
	world_root.add_child(house)
	var width: float = bounds.size.x / WORLD_SCALE
	var depth: float = bounds.size.y / WORLD_SCALE
	var height: float = 1.18 if stall else 1.78
	var timber: StandardMaterial3D = _material("#705941", "wood")
	var stone: StandardMaterial3D = _material("#aaa18a", "stone")
	var wall: ShaderMaterial = _fade_material("#d9c7a1", "plaster")
	var tiles: ShaderMaterial = _fade_material("#77847a" if not stall else "#987a5d", "roof", Vector2(maxf(width * 1.6, 1.0), 2.0))
	solid_footprints.append(bounds)
	_box(house, Vector3(0, 0.075, 0), Vector3(width, 0.15, depth), stone)
	if stall:
		# The full blocked stall footprint reads as stocked, rather than an empty
		# passage under a canopy that the walking rules inexplicably reject.
		_box(house, Vector3(0, 0.36, -0.12), Vector3(width - 0.16, 0.57, depth - 0.36), wall)
		_box(house, Vector3(0, 0.68, depth * 0.18), Vector3(width - 0.12, 0.09, depth * 0.48), timber)
		for x: float in [-width * 0.3, 0.0, width * 0.3]:
			_box(house, Vector3(x, 0.85, depth * 0.05), Vector3(0.30, 0.26, 0.32), _material("#b79265", "wood"))
	else:
		_box(house, Vector3(0, height * 0.5, -0.04), Vector3(width - 0.10, height, depth - 0.13), wall)
		_box(house, Vector3(0, 0.24, 0), Vector3(width - 0.06, 0.22, depth - 0.06), stone)
		for x: float in [-width * 0.31, width * 0.31]:
			_box(house, Vector3(x, 1.00, depth * 0.5 - 0.015), Vector3(1.02, 0.65, 0.04), _material("#7a8070"))
			for offset: float in [-0.36, -0.12, 0.12, 0.36]:
				_box(house, Vector3(x + offset, 1.00, depth * 0.5 + 0.014), Vector3(0.035, 0.65, 0.035), timber)
			for offset: float in [-0.22, 0.0, 0.22]:
				_box(house, Vector3(x, 1.00 + offset, depth * 0.5 + 0.024), Vector3(1.02, 0.035, 0.035), timber)
		_box(house, Vector3(0, 0.71, depth * 0.5 - 0.012), Vector3(0.67, 1.24, 0.06), _material("#8c7050", "wood"))
		for x: float in [-0.38, 0.38]:
			_box(house, Vector3(x, 0.75, depth * 0.5 + 0.035), Vector3(0.065, 1.39, 0.065), timber)
		_box(house, Vector3(0, 1.47, depth * 0.5 + 0.035), Vector3(0.83, 0.09, 0.07), timber)
		_box(house, Vector3(0, 0.10, depth * 0.5 + 0.06), Vector3(0.91, 0.13, 0.13), stone)
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			_box(house, Vector3(side * (width * 0.5 - 0.08), height * 0.5, end * (depth * 0.5 - 0.07)), Vector3(0.11, height, 0.11), timber)
		_box(house, Vector3(0, height - 0.05, side * (depth * 0.5 - 0.02)), Vector3(width, 0.13, 0.10), timber)
		_box(house, Vector3(side * (width * 0.5 - 0.05), height - 0.05, 0), Vector3(0.10, 0.13, depth), timber)
	var roof: Node3D = _roof(house, Vector3(0, height + 0.02, 0), width, depth, tiles)
	if not backdrop:
		roof_rows.append({"node": roof, "body": house, "materials": [tiles, wall], "fade": 0.0})
	if not stall:
		for side: float in [-1.0, 1.0]:
			_lantern(house, Vector3(side * width * 0.40, height - 0.20, depth * 0.5 + 0.11))
		_sign(house, Vector3(0, 1.57, depth * 0.5 + 0.08), "山下集镇", Vector2(1.15, 0.25), 34)


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
	_cylinder(parent, point, 0.12, 0.30, mat, 0.92)
	for y: float in [-0.17, 0.17]:
		_cylinder(parent, point + Vector3.UP * y, 0.125, 0.035, _material("#6f533a", "wood"))
	_beam(parent, point + Vector3.UP * 0.17, point + Vector3.UP * 0.35, 0.025, _material("#6f533a", "wood"))
	_beam(parent, point - Vector3.UP * 0.18, point - Vector3.UP * 0.33, 0.018, _material("#ae7441"))


func _build_edges() -> void:
	# Everything solid in this section is beyond the existing walkable floor.
	for row: Array in [[40, 420, 2.9, 1], [1242, 330, 3.1, 2], [1260, 650, 3.4, 3], [-20, 690, 3.5, 4]]:
		_tree(Vector2(float(row[0]), float(row[1])), float(row[2]), int(row[3]))
	for i: int in range(8):
		var mountain: MeshInstance3D = MeshInstance3D.new()
		var mesh: PrismMesh = PrismMesh.new()
		mesh.size = Vector3(6.0 + float(i % 3), 3.1 + float(i % 4) * 0.8, 2.0)
		mountain.mesh = mesh
		mountain.material_override = _material("#97a48d" if i % 2 else "#84998a")
		mountain.position = Vector3(-20.0 + float(i) * 5.7, 0.9, -14.0 - float(i % 2) * 2.0)
		mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(mountain)
	_build_house(Rect2(80, -100, 310, 170), false, true)
	_build_house(Rect2(955, -85, 290, 155), false, true)
	for step: int in range(9):
		var bounds: Rect2 = Rect2(110, 135 - step * 16, 100, 16)
		var at: Vector3 = logical_to_world(bounds.get_center())
		var height: float = 0.10 + float(step) * 0.12
		_box(world_root, at + Vector3.UP * height * 0.5, Vector3(1.25, height, 0.20), _material("#aeb098", "stone"))
		solid_footprints.append(bounds)


func _tree(point: Vector2, height: float, seed: int) -> void:
	var node: Node3D = Node3D.new()
	node.position = logical_to_world(point)
	world_root.add_child(node)
	var radius: float = 0.09
	solid_footprints.append(Rect2(point - Vector2.ONE * radius * WORLD_SCALE, Vector2.ONE * radius * WORLD_SCALE * 2.0))
	var wood: StandardMaterial3D = _material("#827258", "wood")
	_cylinder(node, Vector3(0, height * 0.32, 0), radius, height * 0.64, wood, 0.55)
	for i: int in range(7):
		var angle: float = float(i) * 2.39996 + float(seed) * 0.47
		var reach: float = 0.2 if i == 0 else 0.5 + float(i % 3) * 0.16
		var at: Vector3 = Vector3(cos(angle) * reach, height * (0.65 + float(i % 3) * 0.10), sin(angle) * reach)
		if i < 4:
			_beam(node, Vector3(0, height * 0.4, 0), at, 0.065, wood)
		var crown: MeshInstance3D = MeshInstance3D.new()
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = 0.72
		mesh.height = 0.92
		mesh.radial_segments = 12
		mesh.rings = 5
		crown.mesh = mesh
		crown.position = at
		crown.scale = Vector3(1.0 + float(i % 2) * 0.2, 1, 0.9)
		crown.material_override = _material(["#829467", "#92a272", "#a5ac7d"][i % 3])
		node.add_child(crown)


func _build_landmarks() -> void:
	var items: Dictionary = _definition.get("interactions", {})
	for id: String in items:
		var position: Array = items[id].position
		var at: Vector3 = logical_to_world(Vector2(float(position[0]), float(position[1])))
		var marker: StandardMaterial3D = StandardMaterial3D.new()
		marker.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.albedo_color = Color("#d9c999") if id == "mountain_exit" else Color("#a0b09b")
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = 0.28
		mesh.bottom_radius = 0.28
		mesh.height = 0.008
		mesh.radial_segments = 32
		var disk: MeshInstance3D = MeshInstance3D.new()
		disk.mesh = mesh
		disk.material_override = marker
		disk.position = at + Vector3.UP * 0.008
		disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(disk)
		if id == "street_sign":
			# The plaque is suspended from the declared stall. Its support is above
			# head height; the marked ground remains fully walkable.
			var anchor: Vector3 = logical_to_world(Vector2(690, 470)) + Vector3.UP * 1.6
			_beam(world_root, anchor, at + Vector3.UP * 1.35, 0.045, _material("#7c674b", "wood"))
			_beam(world_root, at + Vector3.UP * 1.35, at + Vector3.UP * 1.15, 0.012, _material("#7c674b", "wood"))
			_sign(world_root, at + Vector3.UP * 1.0, "集", Vector2(0.44, 0.38), 52)
		elif id == "tea_seller":
			# A light hanging sign suggests the trade without inventing a counter
			# or a new solid obstacle under the NPC's existing free-ground target.
			var outside: Vector3 = logical_to_world(Vector2(1240, 300))
			_box(world_root, outside + Vector3.UP * 1.0, Vector3(0.10, 2.0, 0.10), _material("#7c674b", "wood"))
			solid_footprints.append(Rect2(1236, 296, 8, 8))
			var attachment: Vector3 = logical_to_world(Vector2(850, 280)) + Vector3.UP * 1.90
			_beam(world_root, attachment, outside + Vector3.UP * 1.90, 0.05, _material("#7c674b", "wood"))
			var sign_at: Vector3 = at + Vector3(0.6, 1.70, -0.16)
			_beam(world_root, sign_at + Vector3.UP * 0.3, sign_at + Vector3.UP * 0.13, 0.015, _material("#7c674b", "wood"))
			_sign(world_root, sign_at, "茶", Vector2(0.35, 0.40), 48)


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
	actor.no_depth_test = false
	actor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.visible = false
	world_root.add_child(actor)
	actor_nodes[id] = actor
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
	actor.texture = frame
	var frame_size: Vector2 = frames.get("frame_size", frame.get_size())
	var anchor: Vector2 = frames.get("foot_anchor", Vector2(frame_size.x * 0.5, frame_size.y))
	actor.pixel_size = _actor_height(id) / maxf(frame_size.y, 1.0)
	actor.offset = Vector2(frame_size.x * 0.5 - anchor.x, anchor.y - frame_size.y * 0.5)


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
		var covered: bool = _projected_bounds(row.body).intersects(body)
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
