extends RefCounted
## Original Shu tea-shop geometry, authored 2026-10-29.
## Blender-authored shell with the current stage's fade and lighting contract.
## One original Shu illustration forms the recessed back wall; shelves,
## opening, doors, structure and lighting remain actual scene geometry.
## The recessed openings are scenery inside the existing blocked footprint;
## they do not create a second navigation surface or an enterable interior.

const ProductShop = preload("res://assets/art/town_product_shop/town-product-shop.glb")
const ProductRoofTexture = preload("res://assets/art/town_product_shop/roof-wash.png")
const ProductWallTexture = preload("res://assets/art/town_product_shop/plaster-wash.png")
const PRODUCT_SHOP_SOURCE = "res://assets/art/town_product_shop/source.json"

const InteriorWallTexture = preload("res://assets/art/shanxia_polish/tea-shop-inner-wall-reference.png")
const INTERIOR_WALL_SOURCE = "res://assets/art/shanxia_polish/tea-shop-inner-wall-source.json"

var _stage: Node
var _font: Font
var _house: Node3D
var _wood: StandardMaterial3D
var _dark_wood: StandardMaterial3D
var _stone: StandardMaterial3D
var _wall: ShaderMaterial
var _roof_material: ShaderMaterial


func build(stage: Node, bounds: Rect2, font: Font) -> Node3D:
	_stage = stage
	_font = font
	_house = Node3D.new()
	_house.name = "TeaHouseOpenServiceBay"
	_house.position = _stage.call("logical_to_world", bounds.get_center())
	(_stage.get("world_root") as Node3D).add_child(_house)
	var corner: Vector3 = _stage.call("logical_to_world", bounds.position)
	var opposite: Vector3 = _stage.call("logical_to_world", bounds.end)
	var width: float = opposite.x - corner.x
	var depth: float = opposite.z - corner.z
	var height: float = 2.42
	var front: float = depth * 0.5 - 0.075
	_wood = _stage.call("_material", "#8a6d4e", "wood") as StandardMaterial3D
	_dark_wood = _stage.call("_material", "#62513b", "flat") as StandardMaterial3D
	_stone = _stage.call("_material", "#a3a38f", "stone") as StandardMaterial3D
	_wall = _stage.call("_fade_material", "#e0dac5", "plaster", Vector2(width / 2.5, 1.0)) as ShaderMaterial
	_wall.set_shader_parameter("wall_height", height)
	_wall.set_shader_parameter("surface_texture", ProductWallTexture)
	_wall.set_shader_parameter("tint_strength", 0.0)
	_wall.set_shader_parameter("repeat_uv", Vector2.ONE)
	_roof_material = _stage.call("_fade_material", "#60716a", "roof", Vector2(width / 2.0, 0.60)) as ShaderMaterial
	_roof_material.set_shader_parameter("surface_texture", ProductRoofTexture)
	_roof_material.set_shader_parameter("tint_strength", 0.0)
	_roof_material.set_shader_parameter("repeat_uv", Vector2.ONE)
	# The model supplies its own roof colour grouping; keep shared occlusion
	# and lighting, without layering the old tile-coordinate moss pattern.
	_roof_material.set_shader_parameter("roof_detail", 0.0)
	var footprints: Array = _stage.get("solid_footprints")
	footprints.append(bounds)
	_stage.call("_contact_pad", _house.position, Vector2(width, depth), 0.26)
	var occluders: Array = _stage.get("_sun_occluders")
	occluders.append(AABB(_house.position - Vector3(width * 0.5, 0, depth * 0.5), Vector3(width, height + 0.2, depth)))

	# Four material-merged meshes replace the old shell. No scripts, cameras,
	# lights, collision or gameplay state are imported with this original asset.
	var structure: Node3D = ProductShop.instantiate() as Node3D
	_house.add_child(structure)
	var roof: MeshInstance3D = structure.get_node("ProductTeaShop/Roof") as MeshInstance3D
	roof.material_override = _roof_material
	(structure.get_node("ProductTeaShop/Wall") as MeshInstance3D).material_override = _wall
	# Dark interior is an inset rear surface, not a painted black rectangle on
	# the front wall. Shelves and the half-open leaves occupy the shallow room.
	var interior: StandardMaterial3D = _stage.call("_material", "#47463b", "flat") as StandardMaterial3D
	_box(Vector3(0.85, 1.23, -depth * 0.5 + 0.118), Vector3(4.70, 2.10, 0.022), interior)
	_box(Vector3(-1.95, 1.20, -depth * 0.5 + 0.12), Vector3(1.34, 2.00, 0.025), interior)
	# Recess the floor behind the stone threshold. Their old front faces were
	# coplanar and could swap two edge pixels when the scene was rebuilt.
	_box(Vector3(0, 0.185, -0.02), Vector3(width - 0.22, 0.035, depth - 0.15), _dark_wood)

	_build_front_panels(width, height, front)
	_build_half_open_door(front, depth)
	_build_service_bay(front, depth)
	_build_shop_plaque(depth)
	_build_small_age_marks(width, front)

	var rows: Array = _stage.get("roof_rows")
	rows.append({"node": roof, "body": _house,
		"materials": [_roof_material, _wall], "fade": 0.0})
	return _house


func _build_front_panels(width: float, height: float, front: float) -> void:
	# Unequal bays distinguish this working shop from the generic guest houses.
	for panel: Vector3 in [Vector3(-2.99, 0.60, 0), Vector3(-0.82, 0.80, 0), Vector3(2.98, 0.62, 0)]:
		_box(Vector3(panel.x, height * 0.5, front - 0.055), Vector3(panel.y, height - 0.08, 0.10), _wall)
	_box(Vector3(0, 2.245, front - 0.05), Vector3(width - 0.14, 0.30, 0.10), _wall)
	for x: float in [-3.25, -2.64, -1.27, -0.34, 2.64, 3.25]:
		_box(Vector3(x, 1.20, front), Vector3(0.12, 2.40, 0.12), _dark_wood)
		# Visible tenon collar and stone plinth give the posts a weight-bearing foot.
		_box(Vector3(x, 0.23, front - 0.008), Vector3(0.18, 0.25, 0.16), _stone)
		_box(Vector3(x, 2.12, front + 0.012), Vector3(0.16, 0.15, 0.14), _wood)
	_box(Vector3(0, 2.17, front + 0.012), Vector3(width - 0.13, 0.15, 0.17), _dark_wood)
	for x: float in [-2.98, -0.82, 2.98]:
		_box(Vector3(x, 0.47, front + 0.012), Vector3(0.57 if x != -0.82 else 0.73, 0.085, 0.055), _wood)
	# Small ventilating lattice over the left plaster pier.
	_box(Vector3(-2.99, 1.54, front + 0.008), Vector3(0.39, 0.41, 0.025), _dark_wood)
	for i: int in range(4):
		_box(Vector3(-3.12 + float(i) * 0.087, 1.54, front + 0.027), Vector3(0.024, 0.34, 0.025), _wood)
	for y: float in [1.43, 1.65]:
		_box(Vector3(-2.99, y, front + 0.03), Vector3(0.36, 0.024, 0.027), _wood)


func _build_half_open_door(front: float, depth: float) -> void:
	var center: float = -1.95
	var pivot_z: float = front - 0.035
	for side: float in [-1.0, 1.0]:
		var leaf: Node3D = Node3D.new()
		leaf.name = "InwardDoorLeft" if side < 0 else "InwardDoorRight"
		leaf.position = Vector3(center + side * 0.64, 0.19, pivot_z)
		leaf.rotation.y = deg_to_rad(39.0 if side < 0 else -28.0)
		_house.add_child(leaf)
		var across: float = -side * 0.295
		_stage.call("_box", leaf, Vector3(across, 0.91, 0), Vector3(0.59, 1.82, 0.055), _wood)
		for i: int in range(5):
			_stage.call("_box", leaf, Vector3(-side * (0.055 + float(i) * 0.116), 0.87, 0.032), Vector3(0.014, 1.62, 0.014), _dark_wood)
		for y: float in [0.15, 0.78, 1.67]:
			_stage.call("_box", leaf, Vector3(across, y, 0.038), Vector3(0.56, 0.065, 0.025), _dark_wood)
		_stage.call("_cylinder", leaf, Vector3(-side * 0.48, 0.92, 0.065), 0.035, 0.055,
			_stage.call("_material", "#8d805b", "flat"), 1.0)
	# A shallow threshold and visible stock make this an occupied shop opening,
	# while the original scene obstacle still determines where players can walk.
	_box(Vector3(center, 0.19, front - 0.08), Vector3(1.30, 0.10, 0.16), _stone)
	_box(Vector3(center + 0.19, 0.36, -depth * 0.5 + 0.33), Vector3(0.43, 0.34, 0.39), _dark_wood)
	_stage.call("_basket", _house, Vector3(center - 0.28, 0.39, -depth * 0.5 + 0.33), 0.20)
	_box(Vector3(center, 2.08, front), Vector3(1.47, 0.13, 0.18), _wood)


func _build_service_bay(front: float, depth: float) -> void:
	var center: float = 1.15
	var width: float = 2.86
	var shelf_back: float = -depth * 0.5 + 0.23
	_build_illustrated_back_wall(center, depth)
	# The serving ledge remains entirely within the declared footprint.
	_box(Vector3(center, 0.79, front - 0.12), Vector3(width, 0.14, 0.33), _dark_wood)
	_box(Vector3(center, 0.46, front - 0.10), Vector3(width - 0.14, 0.53, 0.15), _wood)
	for x: float in [-0.12, 0.55, 1.21, 1.87, 2.48]:
		_box(Vector3(x, 0.45, front - 0.011), Vector3(0.055, 0.45, 0.045), _dark_wood)
	# A low left group and a short raised right group reveal the illustration
	# between them; the service bay no longer reads as two uniform dark stripes.
	_box(Vector3(center, 1.10, shelf_back + 0.08), Vector3(width - 0.18, 0.075, 0.34), _wood)
	_box(Vector3(2.00, 1.58, shelf_back + 0.08), Vector3(1.16, 0.075, 0.34), _wood)
	for support: Vector3 in [Vector3(-0.10, 1.10, 0), Vector3(2.35, 1.10, 0), Vector3(1.47, 1.58, 0), Vector3(2.50, 1.58, 0)]:
		_box(Vector3(support.x, support.y - 0.14, shelf_back - 0.04), Vector3(0.045, 0.30, 0.06), _dark_wood)
	_stock_jar(Vector3(0.05, 1.1375, shelf_back + 0.10), 0.15, 0.34, "#7b9988")
	_stock_jar(Vector3(0.49, 1.1375, shelf_back + 0.11), 0.105, 0.22, "#a89972")
	_stock_jar(Vector3(1.72, 1.6175, shelf_back + 0.10), 0.14, 0.29, "#a89972")
	_stock_jar(Vector3(2.20, 1.6175, shelf_back + 0.11), 0.10, 0.19, "#7b9988")
	_stack_bowls(Vector3(1.08, 1.1375, shelf_back + 0.12))
	# Rolled bamboo screen and its two tie cords expose, rather than cover, stock.
	_stage.call("_cylinder", _house, Vector3(center, 2.035, front - 0.015), 0.075, width + 0.08, _wood, 1.0)
	var roll: Node3D = _house.get_child(_house.get_child_count() - 1) as Node3D
	roll.rotation.z = PI * 0.5
	for x: float in [0.05, 2.20]:
		_box(Vector3(x, 2.04, front + 0.045), Vector3(0.024, 0.21, 0.023), _dark_wood)
	_box(Vector3(1.23, 0.887, front - 0.15), Vector3(0.98, 0.045, 0.27), _wood)
	_stage.call("_teapot", _house, Vector3(1.43, 0.930, front - 0.15), 0.66)
	for x: float in [0.93, 1.14]:
		_stage.call("_cylinder", _house, Vector3(x, 0.95, front - 0.15), 0.065, 0.075,
			_stage.call("_material", "#a8bcb0", "ceramic"), 1.15)
	_counter_cloth(front)
	# A real, very weak warm interior light is attached to the visible paper shade.
	_stage.call("_lantern", _house, Vector3(0.02, 1.97, shelf_back + 0.10))
	_stage.call("_lantern", _house, Vector3(2.35, 1.97, shelf_back + 0.10))


func _stock_jar(foot: Vector3, radius: float, height: float, color: String) -> void:
	var ceramic: Material = _stage.call("_material", color, "ceramic") as Material
	var at: Vector3 = foot + Vector3.UP * (height * 0.5)
	_stage.call("_cylinder", _house, at, radius, height, ceramic, 0.82)
	_stage.call("_cylinder", _house, foot + Vector3.UP * (height + 0.017), radius * 0.87, 0.034, _dark_wood, 1.0)
	_box(at + Vector3(0, 0, radius + 0.004), Vector3(radius * 0.75, height * 0.38, 0.012),
		_stage.call("_material", "#d0c3a0", "flat") as Material)


func _stack_bowls(foot: Vector3) -> void:
	var ceramic: Material = _stage.call("_material", "#b4c4b1", "ceramic") as Material
	for index: int in range(3):
		var at: Vector3 = foot + Vector3.UP * (0.026 + float(index) * 0.042)
		_stage.call("_cylinder", _house, at, 0.10, 0.052, ceramic, 1.27)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.115
		ring.outer_radius = 0.132
		ring.rings = 16
		ring.ring_segments = 6
		var lip := MeshInstance3D.new()
		lip.mesh = ring
		lip.material_override = ceramic
		lip.position = at + Vector3.UP * 0.026
		_house.add_child(lip)
	var inner: Material = _stage.call("_material", "#53675c", "flat") as Material
	_stage.call("_cylinder", _house, foot + Vector3.UP * 0.136, 0.105, 0.008, inner, 1.0)


func _counter_cloth(front: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left: float = 0.02
	var right: float = 0.42
	var fold: float = front + 0.049
	_append_quad(surface, Vector3(left, 0.866, front - 0.25), Vector3(left, 0.866, fold),
		Vector3(right, 0.866, fold), Vector3(right, 0.866, front - 0.25), Vector2.ZERO)
	_append_quad(surface, Vector3(left, 0.866, fold), Vector3(left + 0.012, 0.65, fold + 0.008),
		Vector3(right - 0.012, 0.65, fold + 0.008), Vector3(right, 0.866, fold), Vector2(0, 0.2))
	var cloth := MeshInstance3D.new()
	cloth.name = "FoldedCounterCloth"
	cloth.mesh = surface.commit()
	cloth.material_override = _stage.call("_material", "#c7c0a7", "flat") as Material
	_house.add_child(cloth)
	var stripe: Material = _stage.call("_material", "#84938c", "flat") as Material
	for x: float in [0.09, 0.35]:
		_box(Vector3(x, 0.869, (front - 0.25 + fold) * 0.5), Vector3(0.012, 0.003, fold - front + 0.25), stripe)
		_box(Vector3(x, 0.758, fold + 0.011), Vector3(0.012, 0.20, 0.003), stripe)


func _build_illustrated_back_wall(center: float, depth: float) -> void:
	# The complete image keeps its aspect and UVs. The real service opening,
	# shelves and objects provide the crop and all foreground depth cues.
	var panel_width: float = 2.74
	var aspect: float = float(InteriorWallTexture.get_width()) / float(InteriorWallTexture.get_height())
	var panel_height: float = panel_width / aspect
	var at := Vector3(center, 1.26, -depth * 0.5 + 0.135)
	var quad := QuadMesh.new()
	quad.size = Vector2(panel_width, panel_height)
	var material := StandardMaterial3D.new()
	material.albedo_texture = InteriorWallTexture
	material.albedo_color = Color(0.74, 0.74, 0.74)
	material.roughness = 0.95
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var panel := MeshInstance3D.new()
	panel.name = "IllustratedInteriorBackWall"
	panel.mesh = quad
	panel.material_override = material
	panel.position = at
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_house.add_child(panel)
	for side: float in [-1.0, 1.0]:
		_box(at + Vector3(side * (panel_width * 0.5 + 0.015), 0, 0.023), Vector3(0.055, panel_height + 0.06, 0.045), _dark_wood)
		_box(at + Vector3(0, side * (panel_height * 0.5 + 0.015), 0.023), Vector3(panel_width + 0.08, 0.055, 0.045), _wood)


func _build_shop_plaque(depth: float) -> void:
	# The main shop name hangs over the doorway; no new navigation affordance.
	var plaque: Vector3 = Vector3(-0.83, 1.60, depth * 0.5 - 0.05)
	_box(plaque, Vector3(0.58, 0.94, 0.045), _dark_wood)
	var label := Label3D.new()
	label.text = "山下\n茶铺"
	label.font = _font
	label.font_size = 48
	label.pixel_size = 0.0046
	label.outline_size = 0
	label.modulate = Color("#e2d3ad")
	label.position = plaque + Vector3(0, 0, 0.026)
	label.shaded = false
	_house.add_child(label)


func _append_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv: Vector2) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	var points: Array[Vector3] = [a, b, c, d]
	var uvs: Array[Vector2] = [uv, uv + Vector2(0.15, 0), uv + Vector2(0.15, 0.20), uv + Vector2(0, 0.20)]
	for index: int in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(normal)
		surface.set_uv(uvs[index])
		surface.add_vertex(points[index])


func _build_small_age_marks(width: float, front: float) -> void:
	# Restrained wear follows feet and exposed timber. No random wall-wide noise.
	var pale_stone: Material = _stage.call("_material", "#bbb9a3", "stone") as Material
	for i: int in range(11):
		var x: float = -width * 0.46 + float(i) * width * 0.91 / 10.0
		if x > -2.65 and x < -1.26:
			continue
		_box(Vector3(x, 0.15 + float(i % 2) * 0.012, front - 0.01), Vector3(0.12 + float(i % 3) * 0.04, 0.026, 0.025), pale_stone)
	for x: float in [-3.20, -0.34, 2.63]:
		_box(Vector3(x + 0.026, 0.64, front + 0.065), Vector3(0.018, 0.21, 0.009), _wood)


func _box(at: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	return _stage.call("_box", _house, at, dimensions, material) as MeshInstance3D
