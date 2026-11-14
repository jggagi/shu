extends "res://addons/cultivation_mode/chengdu_crafted_street_stage.gd"
## Eighteen real exteriors form one street composition before painting.
## Curved, thick roofs and recessed facades are actual stable mesh geometry.

const ART_LAYOUT := "res://assets/data/chengdu-art-street-layout.json"
const ART_HELPER := "res://addons/cultivation_mode/chengdu_art_street_art.gd"
var _art_config: Dictionary = {}
var _art_profiles: Dictionary = {}
var _art_roots: Dictionary = {}
var _art_errors: Array[String] = []
var _art_batches: Dictionary = {}
var _art_materials: Dictionary = {}
var _art_street_art: Node
var _art_mesh_count := 0
var _art_crown_minimum := 100.0
var _concept_materials: Node
var _concept_details: Node
var _market_life: Node
var _tea_polish: Node
var _tea_grade: Node
var _blender_kit: Node
var _afternoon_light: Node


func _init() -> void:
	super()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART_LAYOUT))
	if data is Dictionary:
		_art_config = data
		for row: Dictionary in data.get("houses", []):
			_art_profiles[str(row.id)] = row
		# Instance-local configuration: the accepted0.7.5 helper/source stay intact.
		_crafted_config["ground"] = data.ground.duplicate(true)


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	super.setup(walker, font, definition)
	for body: Node3D in _art_roots.values():
		_art_fallback(body)
	if ResourceLoader.exists(ART_HELPER):
		var script := load(ART_HELPER) as Script
		_art_street_art = script.new()
		_art_street_art.name = "ArtStreetWorldPainting"
		add_child(_art_street_art)
		_art_street_art.call("setup", self)
	_concept_materials=load("res://addons/cultivation_mode/chengdu_concept_materials.gd").new()
	_concept_materials.name="ConceptSurfaceFinish"
	add_child(_concept_materials)
	_concept_materials.call("setup",self)
	if ResourceLoader.exists("res://addons/cultivation_mode/chengdu_concept_details.gd"):
		_concept_details=load("res://addons/cultivation_mode/chengdu_concept_details.gd").new()
		_concept_details.name="ConceptArchitecturalDetails"
		add_child(_concept_details)
		_concept_details.call("setup",self,_concept_materials)
	_market_life=load("res://addons/cultivation_mode/chengdu_market_life.gd").new()
	_market_life.name="StreetMarketLife"
	add_child(_market_life)
	_market_life.call("setup",self,_concept_materials,font)
	_tea_polish=load("res://addons/cultivation_mode/chengdu_tea_polish.gd").new()
	_tea_polish.name="TeaShopPolish"
	add_child(_tea_polish)
	_tea_polish.call("setup",self,_concept_materials,font)
	_tea_grade=load("res://addons/cultivation_mode/chengdu_tea_grade.gd").new()
	_tea_grade.name="TeaStreetColour"
	add_child(_tea_grade)
	_tea_grade.call("setup",self)
	_blender_kit=load("res://addons/cultivation_mode/chengdu_blender_kit.gd").new()
	_blender_kit.name="BlenderAuthoredStreetKit"
	add_child(_blender_kit)
	_blender_kit.call("setup",self)
	_afternoon_light=load("res://addons/cultivation_mode/chengdu_afternoon_light.gd").new()
	_afternoon_light.name="TeaStreetAfternoonLight"
	add_child(_afternoon_light)
	_afternoon_light.call("setup",self)


func _materialize_house(row: Dictionary) -> void:
	super._materialize_house(row)
	var id := str(_building_profile(row.bounds).get("id", ""))
	if not _art_roots.has(id) or not _varied_heights.has(id):
		return
	# The retained parent only patches its original ten varied-house IDs.
	# Apply the measured presentation height to every one of these18 bodies.
	var body: Node3D = _art_roots[id]
	for roof: Dictionary in roof_rows:
		if roof.get("body") == body:
			roof["render_height"] = _varied_heights[id]
	var instance := body.get_instance_id()
	if _body_by_instance.has(instance):
		_body_by_instance[instance]["height"] = _varied_heights[id]


func _build_dense_ward(bounds: Rect2, label: String) -> void:
	var id := str(_building_profile(bounds).get("id", ""))
	if not _art_profiles.has(id):
		var first := world_root.get_child_count()
		super._build_dense_ward(bounds, label)
		if is_instance_valid(_art_street_art):
			for index: int in range(first, world_root.get_child_count()):
				_art_street_art.call("attach_tree", world_root.get_child(index))
		return
	var profile: Dictionary = _art_profiles[id]
	var body := _lot_root(bounds, "ArtStreetHouse_" + id)
	body.set_meta("art_street_id", id)
	body.set_meta("art_street_role", str(profile.role))
	if _varied_houses.has(id):
		body.set_meta("varied_street_id", id)
	if _crafted_houses.has(id):
		body.set_meta("crafted_street_id", id)
	var front := Node3D.new()
	front.name = "StreetFacingStructure"
	front.rotation_degrees.y = float(profile.yaw_degrees)
	body.add_child(front)
	_art_batches = {}
	_art_materials = {"stone": _detail_material("#afb1a8", "stone"),
		"plaster": _detail_material("#ddd7c9", "plaster"), "wood": _detail_material("#80674d", "wood"),
		"dark": _detail_material("#37413a", "flat"), "roof": _detail_material("#687b7b", "roof", Vector2(1.5, 1.0)),
		"cloth": _detail_material("#b9956e", "flat"), "leaf": _detail_material("#879461", "flat"),
		"ceramic": _detail_material("#aab6ad", "flat")}
	var width := bounds.size.y / WORLD_SCALE
	var depth := bounds.size.x / WORLD_SCALE
	var role := str(profile.role)
	var eave := float(profile.eave_height)
	var rise := float(profile.roof_rise)
	_art_box("stone", Vector3(0, 0.10, 0), Vector3(width - 0.04, 0.20, depth - 0.04))
	if bool(profile.get("courtyard_tree", false)):
		_art_courtyard(width, depth, eave, rise)
	elif role in ["two_storey", "gallery_house"]:
		_art_two_storey(width, depth, eave, rise, role == "gallery_house")
	else:
		var shop := role in ["tea_shop", "cloth_shop", "corner_shop", "workshop"]
		_art_storey(width - 0.18, depth - 0.22, eave, 0.18, shop)
		if role == "corner_shop":
			_art_hip_roof(Vector3(0, eave, 0), width - 0.04, depth - 0.04, rise)
		else:
			_art_roof(Vector3(0, eave, 0), width - 0.04, depth - 0.04, rise, bool(profile.ridge_along_front))
		if shop:
			_art_shop(width, depth, eave, role)
		elif role == "timber_home":
			for x: float in [-width * 0.35, 0, width * 0.35]:
				_art_box("wood", Vector3(x, eave * 0.5, depth * 0.5 - 0.10), Vector3(0.055, eave - 0.10, 0.055))
		elif id == "ward_city_23_19":
			_art_basket(Vector3(width * 0.35, 0.23, depth * 0.5 - 0.20))
	var materials: Array[ShaderMaterial] = []
	for kind: String in ["stone", "plaster", "wood", "dark", "roof", "cloth", "leaf", "ceramic"]:
		if not _art_batches.has(kind):
			continue
		var mesh := MeshInstance3D.new()
		mesh.name = "ArtSurface_" + kind
		mesh.mesh = (_art_batches[kind] as SurfaceTool).commit()
		mesh.material_override = _art_materials[kind]
		mesh.set_meta("art_street_surface", true)
		mesh.set_meta("art_surface_role", kind)
		if kind == "leaf":
			mesh.set_meta("painted_city_preserve", true)
		front.add_child(mesh)
		materials.append(_art_materials[kind])
		_art_mesh_count += 1
	_register_lot_roof(body, materials)
	_built_houses += 1
	_art_roots[id] = body
	if _varied_houses.has(id):
		_varied_roots[id] = body
		_varied_built.append(id)
		_varied_types[str(_varied_houses[id].type)] = int(_varied_types.get(str(_varied_houses[id].type), 0)) + 1
		_varied_bounds[id] = _row(bounds)
	if _detail_houses.has(id):
		_detail_built_houses.append(id)
	if _crafted_houses.has(id):
		_crafted_roots[id] = body
		for mesh: MeshInstance3D in front.get_children():
			_crafted_meshes.append({"house_id": id, "node": mesh})
	_measure_sample(id, body, bounds)
	if is_instance_valid(_painted_city_surfaces):
		_painted_city_surfaces.call("attach_tree", body)
	if is_instance_valid(_crafted_surfaces) and _crafted_houses.has(id):
		_crafted_surfaces.call("attach_house", body)
	_art_fallback(body)
	_exclude_sample_overlays()
	if is_instance_valid(_art_street_art):
		_art_street_art.call("attach_tree", body)
	if is_instance_valid(_concept_materials):
		_concept_materials.call("attach_house",body)
	if is_instance_valid(_concept_details):
		_concept_details.call("attach_house",body)
	if is_instance_valid(_market_life):
		_market_life.call("attach_house",body)
	if is_instance_valid(_tea_polish):
		_tea_polish.call("attach_house",body)
	if is_instance_valid(_tea_grade):
		_tea_grade.call("attach_house",body)
	if is_instance_valid(_blender_kit):
		_blender_kit.call("attach_house",body)
	if is_instance_valid(_afternoon_light):
		_afternoon_light.call("attach_house",body)


func _art_tool(kind: String) -> SurfaceTool:
	if not _art_batches.has(kind):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_art_batches[kind] = surface
	return _art_batches[kind]


func _art_box(kind: String, at: Vector3, size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_art_append(kind, mesh, Transform3D(Basis.IDENTITY, at))


func _art_append(kind: String, mesh: Mesh, transform: Transform3D) -> void:
	# Primitive meshes include tangents, while authored roof surfaces do not.
	# Emit one consistent NORMAL+UV format into every material batch.
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := transform.basis.inverse().transposed()
	var surface := _art_tool(kind)
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for item: int in range(count):
		var index := indices[item] if not indices.is_empty() else item
		surface.set_normal((normal_basis * normals[index]).normalized())
		surface.set_uv(uvs[index])
		surface.add_vertex(transform * vertices[index])


func _art_cylinder(kind: String, at: Vector3, radius: float, height: float, rotation: Vector3 = Vector3.ZERO, taper: float = 1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius * taper
	mesh.height = height
	mesh.radial_segments = 12
	_art_append(kind, mesh, Transform3D(Basis.from_euler(rotation), at))


func _art_beam(kind: String, first: Vector3, last: Vector3, thickness: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, first.distance_to(last), thickness)
	var basis := Basis(Quaternion(Vector3.UP, (last - first).normalized()))
	_art_append(kind, mesh, Transform3D(basis, (first + last) * 0.5))


func _art_triangle(kind: String, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, upward: bool = false) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.length_squared() < 0.1:
		return
	if upward and normal.y < 0:
		var previous := b
		b = c
		c = previous
		var uv := ub
		ub = uc
		uc = uv
		normal = -normal
	var tool := _art_tool(kind)
	for index: int in range(3):
		tool.set_normal(normal)
		tool.set_uv([ua, ub, uc][index])
		tool.add_vertex([a, b, c][index])


func _art_quad(kind: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, upward: bool = false) -> void:
	_art_triangle(kind, a, b, c, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), upward)
	_art_triangle(kind, a, c, d, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1), upward)


func _art_roof_point(x: float, progress: float, side: float, width: float, depth: float, rise: float) -> Vector3:
	var lift := float(_art_config.roof.eave_lift) * smoothstep(0.70, 1.0, progress)
	var corner := float(_art_config.roof.corner_lift) * pow(absf(x) / (width * 0.5), 6.0) * pow(progress, 4.0)
	return Vector3(x, rise * pow(1.0 - progress, 1.55) + lift + corner, side * depth * 0.5 * progress)


func _art_roof(at: Vector3, width: float, depth: float, rise: float, along_front: bool = false) -> void:
	var transform := Transform3D(Basis(Vector3.UP, PI * 0.5 if along_front else 0.0), at)
	if along_front:
		var previous := width
		width = depth
		depth = previous
	var across := int(_art_config.roof.width_segments)
	var slopes := int(_art_config.roof.slope_segments)
	var thickness := float(_art_config.roof.thickness)
	for side: float in [-1, 1]:
		for ix: int in range(across):
			var x0 := lerpf(-width * 0.5, width * 0.5, float(ix) / across)
			var x1 := lerpf(-width * 0.5, width * 0.5, float(ix + 1) / across)
			for iz: int in range(slopes):
				var v0 := float(iz) / slopes
				var v1 := float(iz + 1) / slopes
				var a := transform * _art_roof_point(x0, v0, side, width, depth, rise)
				var b := transform * _art_roof_point(x1, v0, side, width, depth, rise)
				var c := transform * _art_roof_point(x1, v1, side, width, depth, rise)
				var d := transform * _art_roof_point(x0, v1, side, width, depth, rise)
				_art_triangle("roof", a, b, c, Vector2(float(ix) / across, v0), Vector2(float(ix + 1) / across, v0), Vector2(float(ix + 1) / across, v1), true)
				_art_triangle("roof", a, c, d, Vector2(float(ix) / across, v0), Vector2(float(ix + 1) / across, v1), Vector2(float(ix) / across, v1), true)
				if iz == slopes - 1:
					_art_quad("roof", d, c, c - Vector3.UP * thickness, d - Vector3.UP * thickness)
		for edge: float in [-1, 1]:
			for iz: int in range(slopes):
				var a := transform * _art_roof_point(edge * width * 0.5, float(iz) / slopes, side, width, depth, rise)
				var b := transform * _art_roof_point(edge * width * 0.5, float(iz + 1) / slopes, side, width, depth, rise)
				_art_quad("roof", a, b, b - Vector3.UP * thickness, a - Vector3.UP * thickness)
		for ix: int in range(5):
			var x := lerpf(-width * 0.40, width * 0.40, ix / 4.0)
			for iz: int in range(3):
				var a := transform * _art_roof_point(x, 0.30 + iz * 0.23, side, width, depth, rise) - Vector3.UP * 0.11
				var b := transform * _art_roof_point(x, 0.30 + (iz + 1) * 0.23, side, width, depth, rise) - Vector3.UP * 0.11
				_art_beam("wood", a, b, 0.045)
	# Rounded ridge with gently raised ends is geometry, not a printed line.
	for ix: int in range(across):
		for arc: int in range(8):
			var points: Array[Vector3] = []
			for pair: Vector2i in [Vector2i(ix, arc), Vector2i(ix + 1, arc), Vector2i(ix + 1, arc + 1), Vector2i(ix, arc + 1)]:
				var x := lerpf(-width * 0.5 + 0.01, width * 0.5 - 0.01, float(pair.x) / across)
				var angle := float(pair.y) * PI / 8.0
				var radius := float(_art_config.roof.ridge_radius)
				points.append(transform * Vector3(x, rise + 0.02 + sin(angle) * radius + pow(absf(x) / (width * 0.5), 6.0) * 0.08, cos(angle) * radius))
			_art_quad("roof", points[0], points[1], points[2], points[3], true)
	# Real gable infill and a dark underside close the raised roof volume.
	for edge: float in [-1, 1]:
		for side: float in [-1, 1]:
			for iz: int in range(slopes):
				var x := edge * (width * 0.5 - 0.09)
				var a := transform * Vector3(x, -0.04, 0)
				var b := transform * _art_roof_point(x, float(iz) / slopes, side, width, depth, rise) - Vector3.UP * thickness
				var c := transform * _art_roof_point(x, float(iz + 1) / slopes, side, width, depth, rise) - Vector3.UP * thickness
				if edge * side < 0:
					_art_triangle("plaster", a, c, b, Vector2.ZERO, Vector2(1, 1), Vector2(0, 1))
				else:
					_art_triangle("plaster", a, b, c, Vector2.ZERO, Vector2(0, 1), Vector2(1, 1))
	_art_box("dark", at - Vector3.UP * 0.06, Vector3(depth - 0.12, 0.06, width - 0.12) if along_front else Vector3(width - 0.12, 0.06, depth - 0.12))


func _art_hip_point(edge: Vector2, progress: float, at: Vector3, rise: float, corner: float) -> Vector3:
	var lift := float(_art_config.roof.eave_lift) * smoothstep(0.70, 1.0, progress)
	var y := rise * pow(1.0 - progress, 1.45) + lift + corner * pow(progress, 4.0)
	return at + Vector3(edge.x * progress, y, edge.y * progress)


func _art_hip_roof(at: Vector3, width: float, depth: float, rise: float) -> void:
	var outline: Array[Vector2] = [Vector2(-width * 0.5, -depth * 0.5), Vector2(width * 0.5, -depth * 0.5), Vector2(width * 0.5, depth * 0.5), Vector2(-width * 0.5, depth * 0.5)]
	var count := int(_art_config.roof.slope_segments)
	for side: int in range(4):
		for across: int in range(8):
			var u0 := across / 8.0
			var u1 := (across + 1) / 8.0
			var edge0 := outline[side].lerp(outline[(side + 1) % 4], u0)
			var edge1 := outline[side].lerp(outline[(side + 1) % 4], u1)
			var corner0 := float(_art_config.roof.corner_lift) * pow(absf(u0 * 2.0 - 1.0), 6.0)
			var corner1 := float(_art_config.roof.corner_lift) * pow(absf(u1 * 2.0 - 1.0), 6.0)
			for slope: int in range(count):
				var v0 := float(slope) / count
				var v1 := float(slope + 1) / count
				var a := _art_hip_point(edge0, v0, at, rise, corner0)
				var b := _art_hip_point(edge1, v0, at, rise, corner1)
				var c := _art_hip_point(edge1, v1, at, rise, corner1)
				var d := _art_hip_point(edge0, v1, at, rise, corner0)
				_art_triangle("roof", a, b, c, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), true)
				_art_triangle("roof", a, c, d, Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1), true)
				if slope == count - 1:
					_art_quad("roof", d, c, c - Vector3.UP * 0.085, d - Vector3.UP * 0.085)
	_art_cylinder("roof", at + Vector3.UP * (rise + 0.055), 0.055, 0.11)
	_art_box("dark", at - Vector3.UP * 0.04, Vector3(width - 0.12, 0.055, depth - 0.12))


func _art_storey(width: float, depth: float, height: float, base: float, shop: bool) -> void:
	var front := depth * 0.5
	_art_box("plaster", Vector3(0, (height + base) * 0.5, -depth * 0.5), Vector3(width, height - base, 0.10))
	for side: float in [-1, 1]:
		var side_hole := Rect2(-depth * 0.10 - 0.29, height * 0.59 - 0.25, 0.58, 0.50)
		var panels: Array[Rect2] = _subtract_rect(Rect2(-depth * 0.5, base, depth, height - base), side_hole)
		for panel: Rect2 in panels:
			_art_box("plaster", Vector3(side * (width * 0.5 - 0.04), panel.get_center().y, panel.get_center().x), Vector3(0.09, panel.size.y, panel.size.x))
	var openings: Array[Rect2] = [Rect2(width * 0.16, base, width * 0.27, minf(1.48, height - base - 0.16))]
	if shop:
		openings.append(Rect2(-width * 0.44, 0.99, width * 0.57, maxf(0.3, height - 1.18)))
	else:
		openings.append(Rect2(-width * 0.43, minf(0.78, height * 0.40), width * 0.43, minf(0.66, height * 0.32)))
	_art_front_wall(width, height, base, front, openings)
	for index: int in range(openings.size()):
		var opening: Rect2 = openings[index]
		var dark_z := front - (0.26 if shop and index == 1 else 0.12)
		_art_box("dark", Vector3(opening.get_center().x, opening.get_center().y, dark_z), Vector3(opening.size.x, opening.size.y, 0.045))
		for side: float in [-1, 1]:
			_art_box("wood", Vector3(opening.get_center().x + side * (opening.size.x * 0.5 + 0.025), opening.get_center().y, front + 0.014), Vector3(0.055, opening.size.y + 0.10, 0.11))
			_art_box("wood", Vector3(opening.get_center().x, opening.get_center().y + side * (opening.size.y * 0.5 + 0.025), front + 0.014), Vector3(opening.size.x + 0.10, 0.055, 0.11))
		if index == 0:
			_art_box("wood", Vector3(opening.get_center().x, opening.get_center().y, front - 0.075), Vector3(opening.size.x - 0.035, opening.size.y - 0.025, 0.035))
			_art_box("wood", Vector3(opening.get_center().x, opening.position.y + 0.035, front + 0.035), Vector3(opening.size.x + 0.13, 0.07, 0.14))
		elif not shop:
			for bar: int in range(4):
				_art_box("wood", Vector3(lerpf(opening.position.x + 0.04, opening.end.x - 0.04, bar / 3.0), opening.get_center().y, front - 0.015), Vector3(0.027, opening.size.y, 0.045))
			_art_box("wood", Vector3(opening.get_center().x, opening.get_center().y, front - 0.012), Vector3(opening.size.x, 0.028, 0.045))
	for side: float in [-1, 1]:
		_art_box("wood", Vector3(side * (width * 0.5 - 0.06), height * 0.5, front + 0.018), Vector3(0.075, height - 0.06, 0.10))
	_art_box("wood", Vector3(0, height - 0.11, front + 0.025), Vector3(width + 0.025, 0.095, 0.12))
	# Side-wall windows sit in a recessed dark surround, visible to north view.
	for side: float in [-1, 1]:
		_art_box("dark", Vector3(side * (width * 0.5 - 0.13), height * 0.59, -depth * 0.10), Vector3(0.025, 0.50, 0.57))
		for z: float in [-0.23, -0.08, 0.08, 0.23]:
			_art_box("wood", Vector3(side * (width * 0.5 + 0.014), height * 0.59, z - depth * 0.10), Vector3(0.045, 0.54, 0.025))
		for vertical: float in [-1, 1]:
			_art_box("wood", Vector3(side * (width * 0.5 + 0.014), height * 0.59 + vertical * 0.26, -depth * 0.10), Vector3(0.045, 0.03, 0.62))


func _art_front_wall(width: float, height: float, base: float, z: float, openings: Array[Rect2]) -> void:
	var panels: Array[Rect2] = [Rect2(-width * 0.5, base, width, height - base)]
	for hole: Rect2 in openings:
		var next: Array[Rect2] = []
		for panel: Rect2 in panels:
			next.append_array(_subtract_rect(panel, hole))
		panels = next
	for panel: Rect2 in panels:
		_art_box("plaster", Vector3(panel.get_center().x, panel.get_center().y, z - 0.035), Vector3(panel.size.x, panel.size.y, 0.08))


func _art_shop(width: float, depth: float, eave: float, role: String) -> void:
	var z := depth * 0.5 - 0.15
	_art_box("wood", Vector3(-width * 0.15, 0.61, z - 0.07), Vector3(width * 0.63, 0.76, 0.28))
	_art_box("wood", Vector3(-width * 0.15, 1.015, z - 0.06), Vector3(width * 0.66, 0.07, 0.34))
	for height: float in [1.28, 1.58]:
		if height < eave - 0.12:
			_art_box("wood", Vector3(-width * 0.15, height, z - 0.32), Vector3(width * 0.60, 0.045, 0.18))
	if role in ["tea_shop", "corner_shop"]:
		for index: int in range(4):
			var x := -width * 0.36 + index * 0.18
			_art_cylinder("ceramic", Vector3(x, 1.10, z - 0.07), 0.055, 0.10, Vector3.ZERO, 1.15)
			_art_cylinder("dark", Vector3(x, 1.153, z - 0.07), 0.044, 0.004)
		_art_cylinder("ceramic", Vector3(width * 0.09, 1.16, z - 0.08), 0.11, 0.22, Vector3.ZERO, 0.82)
		_art_cylinder("wood", Vector3(width * 0.09, 1.29, z - 0.08), 0.032, 0.04)
		# Rolled blind and its supports belong to the same real facade.
		_art_cylinder("cloth", Vector3(-width * 0.15, eave - 0.30, z - 0.02), 0.055, width * 0.60, Vector3(0, 0, PI * 0.5))
	elif role == "cloth_shop":
		for index: int in range(3):
			_art_cylinder("cloth", Vector3(-width * 0.35 + index * 0.26, 1.12, z - 0.05), 0.065, 0.24, Vector3(0, 0, PI * 0.5))
		_art_canopy(width * 0.94, depth, eave)
		for side: float in [-1, 1]:
			_art_box("wood", Vector3(side * width * 0.39, 0.70, z - 0.02), Vector3(0.045, 1.12, 0.045))
		_art_box("wood", Vector3(0, 1.23, z - 0.02), Vector3(width * 0.80, 0.045, 0.045))
	else:
		_art_basket(Vector3(-width * 0.38, 0.23, depth * 0.5 - 0.20))


func _art_canopy(width: float, depth: float, eave: float) -> void:
	var back := depth * 0.5 - 0.48
	var front := depth * 0.5 - 0.04
	for step: int in range(6):
		var v0 := step / 6.0
		var v1 := (step + 1) / 6.0
		var y0 := eave - 0.26 - sin(v0 * PI * 0.5) * 0.20
		var y1 := eave - 0.26 - sin(v1 * PI * 0.5) * 0.20
		_art_quad("cloth", Vector3(-width * 0.5, y0, lerpf(back, front, v0)), Vector3(width * 0.5, y0, lerpf(back, front, v0)), Vector3(width * 0.5, y1, lerpf(back, front, v1)), Vector3(-width * 0.5, y1, lerpf(back, front, v1)), true)
	_art_box("wood", Vector3(0, eave - 0.46, front - 0.01), Vector3(width, 0.045, 0.045))


func _art_two_storey(width: float, depth: float, eave: float, rise: float, gallery: bool) -> void:
	_art_storey(width - 0.18, depth - 0.22, 1.85, 0.18, false)
	var upper_width := width - (0.28 if gallery else 0.48)
	var upper_depth := depth - 0.42
	# Upper-storey surfaces are assembled at a local offset without new nodes.
	var before: Dictionary = {}
	for kind: String in _art_batches:
		before[kind] = _art_batches[kind]
	_art_batches = {}
	_art_storey(upper_width, upper_depth, eave - 1.89, 0.0, false)
	var upper := _art_batches
	_art_batches = before
	for kind: String in upper:
		_art_append(kind, (upper[kind] as SurfaceTool).commit(), Transform3D(Basis.IDENTITY, Vector3(0, 1.89, -0.08)))
	_art_box("wood", Vector3(0, 1.88, 0), Vector3(width - 0.10, 0.12, depth - 0.12))
	if gallery:
		var z := depth * 0.5 - 0.09
		for index: int in range(7):
			_art_box("wood", Vector3(lerpf(-width * 0.42, width * 0.42, index / 6.0), 2.16, z), Vector3(0.03, 0.46, 0.035))
		_art_box("wood", Vector3(0, 2.41, z), Vector3(width * 0.88, 0.05, 0.06))
	else:
		_art_roof(Vector3(0, 1.91, 0), width - 0.05, depth - 0.04, 0.30)
	_art_roof(Vector3(0, eave, -0.06), width - 0.04, depth - 0.15, rise, not gallery)


func _art_basket(at: Vector3) -> void:
	_art_cylinder("wood", at + Vector3.UP * 0.16, 0.12, 0.30, Vector3.ZERO, 1.1)
	_art_cylinder("dark", at + Vector3.UP * 0.315, 0.105, 0.008)
	for side: float in [-1, 1]:
		_art_box("wood", at + Vector3(side * 0.105, 0.35, 0), Vector3(0.022, 0.18, 0.025))
	_art_box("wood", at + Vector3.UP * 0.44, Vector3(0.23, 0.025, 0.025))


func _art_courtyard(width: float, depth: float, eave: float, rise: float) -> void:
	_art_box("plaster", Vector3(0, eave * 0.5, -depth * 0.28), Vector3(width - 0.20, eave, depth * 0.36))
	_art_roof(Vector3(0, eave, -depth * 0.26), width - 0.06, depth * 0.46, rise)
	_art_box("plaster", Vector3(0, 0.57, depth * 0.40), Vector3(width - 0.18, 0.80, 0.08))
	_art_box("wood", Vector3(0.26, 0.76, depth * 0.40 + 0.045), Vector3(0.46, 1.10, 0.05))
	_art_cylinder("wood", Vector3(0, 1.44, 0.15), 0.075, 2.65, Vector3.ZERO, 0.65)
	for tip: Vector3 in [Vector3(-0.40, 3.12, 0.12), Vector3(0.35, 3.13, 0.40), Vector3(0.0, 3.23, -0.10)]:
		_art_beam("wood", Vector3(0, 1.90, 0.15), tip, 0.055)
	for row: Array in [[Vector3(0, 3.50, 0.15), Vector3(1.55, 1.20, 1.45)], [Vector3(-0.35, 3.43, 0.20), Vector3(1.10, 1.0, 1.15)], [Vector3(0.35, 3.43, 0.20), Vector3(1.10, 1.0, 1.15)]]:
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 16
		mesh.rings = 8
		_art_append("leaf", mesh, Transform3D(Basis.from_scale(row[1]), row[0]))
		_art_crown_minimum = minf(_art_crown_minimum, row[0].y - row[1].y * 0.5)


func _art_fallback(body: Node3D) -> void:
	if not is_instance_valid(_crafted_surfaces):
		return
	var textures: Dictionary = _crafted_surfaces.get("_textures")
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var role := str(mesh.get_meta("art_surface_role", ""))
		var material := mesh.material_override as ShaderMaterial
		if material == null:
			continue
		if role in ["plaster", "roof", "stone"]:
			var texture_role := "paving" if role == "stone" else role
			if textures.has(texture_role):
				material.set_shader_parameter("surface_texture", textures[texture_role])
			material.set_shader_parameter("surface_color", Color(0.86, 0.86, 0.86))
		elif role == "wood":
			material.set_shader_parameter("surface_color", Color(0.88, 0.86, 0.82))
		elif role in ["dark", "cloth", "ceramic"]:
			material.set_shader_parameter("surface_texture", _detail_flat_texture)
			material.set_shader_parameter("surface_color", Color({"dark": "#37413a", "cloth": "#b9956e", "ceramic": "#aab6ad"}[role]))


func sync(player_position: Vector2, facing: String, walking: bool, stride_distance: float, enabled: bool) -> void:
	super.sync(player_position, facing, walking, stride_distance, enabled)
	if is_instance_valid(_art_street_art):
		_art_street_art.call("sync")
	if is_instance_valid(_market_life):
		_market_life.call("sync")
	if is_instance_valid(_tea_polish):
		_tea_polish.call("sync")


func audit() -> Dictionary:
	var result := super.audit()
	var ids: Array = _art_roots.keys()
	ids.sort()
	result["art_street"] = {"layout_source": ART_LAYOUT, "authored_house_count": _art_profiles.size(), "built_house_ids": ids,
		"geometry_bounds": _art_config.get("geometry_bounds", []), "mesh_count": _art_mesh_count,
		"footprint_errors": _varied_errors.duplicate(), "canopy_clearance_min": _art_crown_minimum if _art_crown_minimum < 100 else 0,
		"changed_geometry_count": _art_roots.size(),
		"real_curved_roofs": true, "roof_thickness": _art_config.get("roof", {}).get("thickness", 0),
		"closed_exteriors": true, "no_new_walk_obstacles": true, "continuous_follow_unchanged": true, "new_state": false,
		"art": _art_street_art.call("audit") if is_instance_valid(_art_street_art) else {}}
	result["concept_finish"]={"materials":_concept_materials.call("audit") if is_instance_valid(_concept_materials) else {},
		"details":_concept_details.call("audit") if is_instance_valid(_concept_details) else {}}
	result["market_life"]=_market_life.call("audit") if is_instance_valid(_market_life) else {}
	result["tea_polish"]=_tea_polish.call("audit") if is_instance_valid(_tea_polish) else {}
	result["tea_grade"]=_tea_grade.call("audit") if is_instance_valid(_tea_grade) else {}
	result["blender_kit"]=_blender_kit.call("audit") if is_instance_valid(_blender_kit) else {}
	result["afternoon_light"]=_afternoon_light.call("audit") if is_instance_valid(_afternoon_light) else {}
	return result
