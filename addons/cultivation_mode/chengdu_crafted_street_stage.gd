extends "res://addons/cultivation_mode/chengdu_varied_street_stage.gd"
## A local refinement of the accepted ten-house sample; no new walk geometry.

const CRAFTED_LAYOUT := "res://assets/data/chengdu-crafted-street-layout.json"
const CraftedSurfaces = preload("res://addons/cultivation_mode/chengdu_crafted_street_surfaces.gd")
var _crafted_config: Dictionary = {}
var _crafted_houses: Dictionary = {}
var _crafted_roots: Dictionary = {}
var _crafted_meshes: Array[Dictionary] = []
var _crafted_surfaces: Node


func _init() -> void:
	super()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CRAFTED_LAYOUT))
	if data is Dictionary:
		_crafted_config = data
		for row: Dictionary in data.get("houses", []):
			_crafted_houses[str(row.id)] = row


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	super.setup(walker, font, definition)
	_crafted_surfaces = CraftedSurfaces.new()
	_crafted_surfaces.name = "CraftedStreetSurfaces"
	add_child(_crafted_surfaces)
	_crafted_surfaces.call("setup", self, _crafted_config)


func _build_dense_ward(bounds: Rect2, label: String) -> void:
	super._build_dense_ward(bounds, label)
	var id := str(_building_profile(bounds).get("id", ""))
	if not _crafted_houses.has(id) or _crafted_roots.has(id):
		return
	var body := _varied_roots[id] as Node3D
	body.set_meta("crafted_street_id", id)
	var front := body.get_child(0) as Node3D
	var details := Node3D.new()
	details.name = "CraftedExteriorDetails"
	front.add_child(details)
	var width := bounds.size.y / WORLD_SCALE
	var depth := bounds.size.x / WORLD_SCALE
	var profile: Dictionary = _varied_houses[id]
	var eave := float(profile.eave_height)
	var role := str(_crafted_houses[id].role)
	var stone := _detail_material("#a7aaa2", "stone")
	var wood := _detail_material("#80674f", "wood")
	var ceramic := _detail_material("#a5aaa0", "flat")
	var dark := _detail_material("#424c46", "flat")
	var linen := _detail_material("#c4b497", "flat")
	var materials: Array[ShaderMaterial] = [stone, wood, ceramic, dark, linen]
	# All steps and plinths remain behind the existing closed exterior boundary.
	_box(details, Vector3(0, 0.19, 0), Vector3(width - 0.08, 0.09, depth - 0.08), stone)
	var door_x := 0.25 if role == "two_storey_home" else width * 0.26
	_box(details, Vector3(door_x, 0.185, depth * 0.5 - 0.12), Vector3(0.54, 0.08, 0.18), stone)
	var beam_z := depth * 0.5 - 0.15
	_box(details, Vector3(0, eave - 0.16, beam_z), Vector3(width - 0.20, 0.09, 0.10), wood)
	for x: float in [-width * 0.35, -width * 0.13, width * 0.13, width * 0.35]:
		_box(details, Vector3(x, eave - 0.26, beam_z), Vector3(0.075, 0.16, 0.15), wood)
	if role == "two_storey_home":
		_window_lip(details, Vector3(-0.45, 1.40, depth * 0.5 - 0.07), 0.65, wood)
		_window_lip(details, Vector3(0, (1.90 + eave) * 0.5 + 0.42, depth * 0.5 - 0.33), width * 0.74, wood)
	elif role == "home":
		var window_y := minf(eave * 0.59, 1.12)
		_window_lip(details, Vector3(-width * 0.20, window_y + eave * 0.165 + 0.045, depth * 0.5 - 0.06), width * 0.42, wood)
		_box(details, Vector3(-width * 0.20, window_y - eave * 0.165 - 0.04, depth * 0.5 - 0.06), Vector3(width * 0.42, 0.06, 0.09), stone)
	elif role == "tea_shop":
		_tea_details(details, width, depth, wood, ceramic, dark, linen)
	elif role == "cloth_shop":
		var blue_cloth := _detail_material("#879a97", "flat")
		materials.append(blue_cloth)
		for index: int in range(2):
			var at := Vector3(-0.57 + index * 0.39, 1.095, depth * 0.5 - 0.22)
			var finish: ShaderMaterial = linen if index == 0 else blue_cloth
			var roll := _cylinder(details, at, 0.075, 0.30, finish)
			roll.rotation.z = PI * 0.5
			var end := _cylinder(details, at + Vector3(0.154, 0, 0), 0.047, 0.008, dark)
			end.rotation.z = PI * 0.5
	for roof: Dictionary in roof_rows:
		if roof.get("body") == body:
			for material: ShaderMaterial in materials:
				(roof.materials as Array).append(material)
			break
	_crafted_roots[id] = body
	for mesh: MeshInstance3D in details.find_children("*", "MeshInstance3D", true, false):
		mesh.set_meta("crafted_street_detail", true)
		_crafted_meshes.append({"house_id": id, "node": mesh})
	_measure_sample(id, body, bounds)
	if is_instance_valid(_painted_city_surfaces):
		_painted_city_surfaces.call("attach_tree", details)
	if is_instance_valid(_crafted_surfaces):
		_crafted_surfaces.call("attach_house", body)
	_exclude_sample_overlays()


func _window_lip(parent: Node3D, at: Vector3, width: float, material: ShaderMaterial) -> void:
	_box(parent, at, Vector3(width, 0.055, 0.09), material)
	for side: float in [-1, 1]:
		_box(parent, at + Vector3(side * width * 0.40, -0.07, -0.018), Vector3(0.045, 0.11, 0.055), material)


func _tea_details(parent: Node3D, width: float, depth: float, wood: ShaderMaterial, ceramic: ShaderMaterial, dark: ShaderMaterial, linen: ShaderMaterial) -> void:
	var z := depth * 0.5 - 0.22
	_box(parent, Vector3(-0.25, 1.012, z), Vector3(0.76, 0.028, 0.25), wood)
	for side: float in [-1, 1]:
		_box(parent, Vector3(-0.25, 1.037, z + side * 0.115), Vector3(0.76, 0.025, 0.02), wood)
	for x: float in [-0.47, -0.25, -0.03]:
		_cylinder(parent, Vector3(x, 1.163, z), 0.046, 0.006, dark)
	var kettle := Vector3(-width * 0.36, 1.095, z)
	_cylinder(parent, kettle, 0.105, 0.18, ceramic, 0.85)
	_cylinder(parent, kettle + Vector3.UP * 0.10, 0.09, 0.025, ceramic)
	_cylinder(parent, kettle + Vector3.UP * 0.13, 0.027, 0.035, wood)
	_box(parent, kettle + Vector3(0.13, 0.015, 0), Vector3(0.10, 0.045, 0.045), ceramic)
	_box(parent, Vector3(0.14, 1.035, z + 0.035), Vector3(0.16, 0.025, 0.20), linen)


func audit() -> Dictionary:
	var result := super.audit()
	var ids: Array = _crafted_roots.keys()
	ids.sort()
	result["crafted_street"] = {"layout_source": CRAFTED_LAYOUT, "authored_house_count": _crafted_houses.size(),
		"built_house_ids": ids, "added_mesh_count": _crafted_meshes.size(), "footprint_errors": _varied_errors.duplicate(),
		"no_new_walk_obstacles": true, "continuous_follow_unchanged": true, "new_state": false,
		"closed_exteriors": true, "render_height_by_id": _varied_heights.duplicate(),
		"surfaces": _crafted_surfaces.call("audit") if is_instance_valid(_crafted_surfaces) else {}}
	return result
