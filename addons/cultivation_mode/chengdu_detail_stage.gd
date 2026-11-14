extends "res://addons/cultivation_mode/chengdu_scale_stage.gd"
## A local craft pass over the accepted city. Authored walk geometry and the
## normal following camera remain owned by the existing ScaleStage/Session.

const DETAIL_LAYOUT := "res://assets/data/chengdu-detail-layout.json"
var _detail: Dictionary = {}
var _detail_houses: Dictionary = {}
var _detail_built_houses: Array[String] = []
var _detail_solids: Array[Dictionary] = []
var _detail_groups: Array[Dictionary] = []
var _detail_instances := 0
var _detail_draw_groups := 0
var _detail_gate_built := false
var _detail_bridge_built := false
var _detail_bridge_posts := 0
var _detail_flat_texture: ImageTexture


func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DETAIL_LAYOUT))
	if data is Dictionary:
		_detail = data
		layout_path = str(data.get("base_layout",SCALE_LAYOUT))
		for house: Dictionary in data.get("houses", []):
			_detail_houses[str(house.id)] = house


func _build_house(bounds: Rect2, stall: bool, backdrop: bool) -> void:
	var first_roof := roof_rows.size()
	super._build_house(bounds,stall,backdrop)
	if str(_building_profile(bounds).get("id","")) in _detail.get("south_gate",{}).get("wall_ids",[]):
		for index: int in range(first_roof,roof_rows.size()):
			roof_rows[index]["render_height"] = 4.3


func _build_city_wall(bounds: Rect2, profile: Dictionary) -> void:
	var id := str(profile.get("id", ""))
	if not id in _detail.get("south_gate", {}).get("wall_ids", []):
		super._build_city_wall(bounds, profile)
		return
	# Replace only the short returns beside the existing gate. The wall's
	# original collision is untouched, and the facing/door leaves fit inside it.
	var length := float(_detail.south_gate.wall_return_length)
	var west := id == "south_wall_west"
	var remainder := Rect2(bounds.position, bounds.size - Vector2(length, 0)) if west else Rect2(bounds.position + Vector2(length,0), bounds.size - Vector2(length,0))
	super._build_city_wall(remainder, profile)
	var returned := Rect2(Vector2(bounds.end.x-length,bounds.position.y), Vector2(length,bounds.size.y)) if west else Rect2(bounds.position,Vector2(length,bounds.size.y))
	var root := _lot_root(returned,"SouthGateStoneReturn")
	var size := returned.size / WORLD_SCALE
	var stone := _detail_material(str(_detail.south_gate.stone),"stone",Vector2(3.0,2.0))
	var dark := _detail_material("#7d8e80","flat")
	var pale := _detail_material("#bdc1ac","stone")
	var wood := _detail_material(str(_detail.south_gate.wood),"wood",Vector2(0.6,2.5))
	var metal := _detail_material("#b6a378","flat")
	var mats: Array[ShaderMaterial] = [stone,dark,pale,wood,metal]
	_box(root,Vector3(0,1.9,-0.025),Vector3(size.x,3.8,size.y-0.07),stone)
	_box(root,Vector3(0,0.18,0),Vector3(size.x,0.36,size.y),pale)
	_box(root,Vector3(0,3.79,0),Vector3(size.x,0.18,size.y),pale)
	var seams: Array[Vector3] = []
	for row: int in range(7):
		seams.append(Vector3(0,0.48+row*0.46,size.y*0.5-0.025))
	_repeat_boxes(root,seams,Vector3(size.x,0.022,0.012),dark)
	var upright: Array[Vector3] = []
	for row: int in range(7):
		for column: int in range(7):
			var x := -size.x*0.5+0.28+column*0.88+(0.44 if row%2 else 0.0)
			if x < size.x*0.5-0.05:
				upright.append(Vector3(x,0.70+row*0.46,size.y*0.5-0.024))
	_repeat_boxes(root,upright,Vector3(0.018,0.42,0.012),dark)
	var leaf_x := (size.x*0.5-0.82) * (1.0 if west else -1.0)
	var leaf_z := size.y*0.5-0.035
	_box(root,Vector3(leaf_x,1.46,leaf_z),Vector3(1.40,2.64,0.045),wood)
	for side: float in [-1,1]:
		_box(root,Vector3(leaf_x+side*0.65,1.46,leaf_z+0.012),Vector3(0.055,2.66,0.035),dark)
	var studs: Array[Vector3] = []
	for row: int in range(6):
		for column: int in range(4):
			studs.append(Vector3(leaf_x-0.48+column*0.32,0.45+row*0.39,leaf_z+0.020))
	_repeat_boxes(root,studs,Vector3(0.048,0.048,0.018),metal)
	for y: float in [0.44,2.50]:
		_box(root,Vector3(leaf_x,y,leaf_z+0.022),Vector3(1.36,0.075,0.020),dark)
	var merlons: Array[Vector3] = []
	for index: int in range(8):
		merlons.append(Vector3(-size.x*0.5+(index+0.5)*size.x/8.0,4.03,0))
	_repeat_boxes(root,merlons,Vector3(0.34,0.36,size.y*0.72),pale)
	_register_lot_roof(root,mats)
	_detail_solids.append({"kind":"gate_wall_return_and_folded_leaf","bounds":_row(returned),"within_obstacle":true})


func _build_open_gate(bounds: Rect2, label: String, axis: String) -> void:
	if label != "南门":
		super._build_open_gate(bounds,label,axis)
		return
	var root := Node3D.new()
	root.name = "DetailedOpenSouthGate"
	root.position = logical_to_world(bounds.get_center())
	world_root.add_child(root)
	var stone := _detail_material("#b9c0ac","stone")
	var dark := _detail_material("#80735c","wood")
	var wood := _detail_material("#8b7050","wood")
	var tile := _detail_material(str(_detail.south_gate.tile),"roof",Vector2(4,1.5))
	var mats: Array[ShaderMaterial] = [stone,dark,wood,tile]
	var width := bounds.size.x/WORLD_SCALE
	# The entire arch is overhead; the old 280px ground-level gap stays open.
	var radius := width*0.5+0.10
	for index: int in range(15):
		var angle := (index+0.5)*PI/15.0
		var voussoir := _box(root,Vector3(cos(angle)*radius,2.10+sin(angle)*radius,0),Vector3(0.35,0.28,2.17),stone)
		voussoir.rotation.z = angle-PI*0.5
	_box(root,Vector3(0,3.83,0),Vector3(width+0.65,0.33,2.17),stone)
	_box(root,Vector3(0,4.36,-0.16),Vector3(width+0.35,0.77,1.52),_detail_material("#d5ccb2","plaster"))
	for x: float in [-1.65,-0.82,0,0.82,1.65]:
		_box(root,Vector3(x,4.37,0.68),Vector3(0.095,0.88,0.12),wood)
		_box(root,Vector3(x,4.84,0.75),Vector3(0.28,0.10,0.28),wood)
		_box(root,Vector3(x,4.96,0.77),Vector3(0.46,0.10,0.38),dark)
	_small_roof(root,Vector3(0,5.06,-0.12),width+1.10,2.27,tile)
	_box(root,Vector3(0,5.08,1.05),Vector3(width+1.29,0.10,0.09),dark)
	_small_roof(root,Vector3(0,3.50,0.91),width+0.46,0.88,tile)
	_detail_sign(root,Vector3(0,3.15,1.34),str(_detail.south_gate.inscription),Vector2(1.25,0.36),46,dark,mats)
	# This façade plaster also needs the same occlusion treatment as the arch.
	for child: Node in root.find_children("*","MeshInstance3D",true,false):
		var material := (child as MeshInstance3D).material_override as ShaderMaterial
		if material != null and not mats.has(material):
			mats.append(material)
	_detail_register_group(root,bounds.grow(30),5.9,mats,"south_gate_overhead")
	_detail_gate_built = true


func _build_reference_bridge(bounds: Rect2, axis: String, label: String) -> void:
	if label != "万里桥":
		super._build_reference_bridge(bounds,axis,label)
		return
	# Keep the original flat paving/deck. All new raised stonework is in the
	# already impassable water outside the navigation gap, never on the deck.
	_large_paved_patch(bounds,1.02,0.012)
	_bridge_decks.append({"label":label,"bounds":bounds,"axis":axis,"deck_height":0.012})
	var root := Node3D.new()
	root.name = "DetailedWanliBridgeWaterSideStonework"
	root.position = logical_to_world(bounds.get_center())
	world_root.add_child(root)
	var stone := _detail_material("#b7bba5","stone")
	var pale := _detail_material("#c9c8af","stone")
	var dark := _detail_material("#889a8c","stone")
	var mats: Array[ShaderMaterial] = [stone,pale,dark]
	var post_height := float(_detail.wanli_bridge.post_height)
	var rail_height := float(_detail.wanli_bridge.rail_height)
	var half_width := bounds.size.x/WORLD_SCALE*0.5
	var offset := float(_detail.wanli_bridge.water_side_offset)/WORLD_SCALE
	var first_y := bounds.position.y
	var last_y := bounds.end.y
	for water: Rect2 in _water_bounds:
		if water.position.x < bounds.position.x and water.end.x >= bounds.position.x:
			if water.intersects(bounds.grow(24)):
				first_y = maxf(first_y,water.position.y+24)
				last_y = minf(last_y,water.end.y-24)
	var first_z := (first_y-bounds.get_center().y)/WORLD_SCALE
	var last_z := (last_y-bounds.get_center().y)/WORLD_SCALE
	var rail_length := last_z-first_z
	var count := ceili((last_y-first_y)/float(_detail.wanli_bridge.post_spacing))
	var posts: Array[Vector3] = []
	var caps: Array[Vector3] = []
	var feet: Array[Vector3] = []
	for side: float in [-1,1]:
		var x := side*(half_width+offset)
		for index: int in range(count+1):
			var z := lerpf(first_z,last_z,float(index)/count)
			posts.append(Vector3(x,(post_height-0.08)*0.5+0.03,z))
			caps.append(Vector3(x,post_height+0.02,z))
			feet.append(Vector3(x,0.06,z))
			_detail_add_water_solid(Rect2(bounds.get_center()+Vector2(x,z)*WORLD_SCALE-Vector2(10,10),Vector2(20,20)),"bridge_post")
		_box(root,Vector3(x,rail_height,(first_z+last_z)*0.5),Vector3(0.11,0.12,rail_length),pale)
		_box(root,Vector3(x,0.28,(first_z+last_z)*0.5),Vector3(0.095,0.075,rail_length),dark)
		_detail_add_water_solid(Rect2(Vector2(bounds.get_center().x+x*WORLD_SCALE-5,first_y),Vector2(10,last_y-first_y)),"continuous_bridge_rails")
		for end: float in [-1,1]:
			var z := first_z if end<0 else last_z
			_box(root,Vector3(x,0.19,z),Vector3(0.31,0.38,0.40),stone)
			_box(root,Vector3(x,0.44,z),Vector3(0.34,0.12,0.43),pale)
			_detail_add_water_solid(Rect2(bounds.get_center()+Vector2(x,z)*WORLD_SCALE-Vector2(14,18),Vector2(28,36)),"bridgehead_stone")
	_repeat_boxes(root,posts,Vector3(0.18,post_height-0.08,0.18),stone)
	_repeat_boxes(root,caps,Vector3(0.24,0.10,0.24),pale)
	_repeat_boxes(root,feet,Vector3(0.24,0.12,0.24),pale)
	_detail_bridge_posts = posts.size()
	var plaque := Vector3(-half_width-offset,1.14,last_z)
	_detail_sign(root,plaque,str(_detail.wanli_bridge.inscription),Vector2(0.48,0.24),21,dark,mats)
	_detail_add_water_solid(Rect2(bounds.get_center()+Vector2(plaque.x,plaque.z)*WORLD_SCALE-Vector2(20,3),Vector2(40,6)),"bridge_name_plaque")
	# Short shore-facing stone revetments are confined to the original river
	# rectangles. They do not introduce steps or raised paving at either end.
	for side: float in [-1,1]:
		for end: float in [-1,1]:
			var length := float(_detail.wanli_bridge.bank_length)
			var center := Vector2(bounds.get_center().x+side*(bounds.size.x*0.5+length*0.5+40),first_y-8 if end<0 else last_y+8)
			var bank := Rect2(center-Vector2(length*0.5,16),Vector2(length,32))
			_detail_add_water_solid(bank,"river_revetment")
			_box(root,Vector3((center.x-bounds.get_center().x)/WORLD_SCALE,0.12,(center.y-bounds.get_center().y)/WORLD_SCALE),Vector3(length/WORLD_SCALE,0.28,0.40),stone)
	_detail_register_group(root,bounds.grow(430),1.0,mats,"wanli_bridge_water_side")
	_detail_bridge_built = true


func _build_dense_ward(bounds: Rect2, label: String) -> void:
	var profile := _building_profile(bounds)
	var id := str(profile.get("id",""))
	if not _detail_houses.has(id):
		super._build_dense_ward(bounds,label)
		return
	var style: Dictionary = _detail_houses[id]
	var root := _lot_root(bounds,"DetailedFirstStreetHouse")
	var size := bounds.size/WORLD_SCALE
	var timber := _detail_material("#795f46","wood")
	var dark := _detail_material("#4f645b","flat")
	var wall := _detail_material("#ded5b9" if str(style.style)!="cloth_awning" else "#cecbb2","plaster")
	var tile := _detail_material("#647c73","roof",Vector2(3.5,1.5))
	var stone := _detail_material("#b1b7a4","stone")
	var mats: Array[ShaderMaterial] = [timber,dark,wall,tile,stone]
	_box(root,Vector3(0,0.08,0),Vector3(size.x,0.16,size.y),stone)
	var has_porch := str(style.style)=="cloth_awning"
	_box(root,Vector3(0,0.87,-0.23 if has_porch else -0.02),Vector3(size.x-0.07,1.65,size.y-(0.55 if has_porch else 0.09)),wall)
	var facade_z := size.y*0.5-(0.48 if has_porch else 0.025)
	for side: float in [-1,1]:
		_box(root,Vector3(side*(size.x*0.5-0.065),0.91,facade_z),Vector3(0.10,1.70,0.04),timber)
	for y: float in [0.28,1.62]:
		_box(root,Vector3(0,y,facade_z),Vector3(size.x-0.08,0.075,0.04),timber)
	var door_x := size.x*0.27
	_box(root,Vector3(door_x,0.81,facade_z+0.005),Vector3(0.53,1.43,0.025),timber)
	for index: int in range(4):
		_box(root,Vector3(door_x-0.22+index*0.145,0.80,facade_z+0.020),Vector3(0.012,1.36,0.010),dark)
	_box(root,Vector3(door_x-0.12,0.91,facade_z+0.017),Vector3(0.046,0.046,0.012),stone)
	var window_x := -size.x*0.22
	_box(root,Vector3(window_x,1.04,facade_z+0.006),Vector3(size.x*0.36,0.72,0.022),dark)
	for index: int in range(4):
		_box(root,Vector3(window_x-size.x*0.15+index*size.x*0.10,1.04,facade_z+0.017),Vector3(0.035,0.74,0.012),timber)
	for y: float in [0.73,1.05,1.38]:
		_box(root,Vector3(window_x,y,facade_z+0.017),Vector3(size.x*0.36,0.035,0.012),timber)
	_small_roof(root,Vector3(0,1.76,0),size.x-0.40,size.y-0.36,tile)
	_box(root,Vector3(0,1.79,size.y*0.5-0.07),Vector3(size.x-0.06,0.065,0.075),timber)
	if str(style.style)=="cloth_awning":
		var cloth := _detail_material("#b9a57f","flat")
		mats.append(cloth)
		var shade := _box(root,Vector3(-0.15,1.52,size.y*0.5-0.25),Vector3(size.x*0.72,0.055,0.43),cloth)
		shade.rotation_degrees.x = -10
		for x: float in [-0.65,0.35]:
			_box(root,Vector3(x,0.74,size.y*0.5-0.11),Vector3(0.045,1.47,0.045),timber)
		for index: int in range(3):
			_box(root,Vector3(-0.48+index*0.25,0.25,size.y*0.5-0.18),Vector3(0.23,0.14,0.23),cloth)
		_detail_sign(root,Vector3(-0.66,1.17,size.y*0.5-0.035),str(style.sign),Vector2(0.22,0.46),29,timber,mats)
	elif str(style.style)=="lattice_shop":
		_box(root,Vector3(window_x,0.60,facade_z-0.04),Vector3(size.x*0.43,0.12,0.14),timber)
		_detail_sign(root,Vector3(window_x,1.53,facade_z+0.005),str(style.sign),Vector2(0.44,0.20),25,timber,mats)
	else:
		_box(root,Vector3(0,1.64,size.y*0.5-0.10),Vector3(size.x*0.93,0.045,0.16),tile)
	# Roof gables receive white infill instead of exposing an open triangular
	# hole; every piece remains inside the pre-existing house footprint.
	for side: float in [-1,1]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for point: Vector3 in [Vector3(side*(size.x*0.5-0.055),1.77,-size.y*0.5+0.06),Vector3(side*(size.x*0.5-0.055),2.22,0),Vector3(side*(size.x*0.5-0.055),1.77,size.y*0.5-0.06)]:
			surface.set_normal(Vector3(side,0,0))
			surface.set_uv(Vector2(point.z,point.y))
			surface.add_vertex(point)
		var gable := MeshInstance3D.new()
		gable.mesh = surface.commit()
		gable.material_override = wall
		root.add_child(gable)
	_register_lot_roof(root,mats)
	_detail_built_houses.append(id)
	_detail_solids.append({"kind":"first_street_facade_awning_and_goods","id":id,"bounds":_row(bounds),"within_obstacle":true})
	_built_houses += 1


func _detail_sign(parent: Node3D, at: Vector3, value: String, size: Vector2, font_size: int, material: ShaderMaterial, _materials: Array[ShaderMaterial]) -> void:
	_box(parent,at,Vector3(size.x,size.y,0.025),material)
	var text := Label3D.new()
	text.text = value
	text.font = _font
	text.font_size = font_size
	text.pixel_size = 0.006
	text.modulate = Color("#e2cf9e")
	text.outline_size = 0
	text.position = at+Vector3(0,0,0.016)
	parent.add_child(text)


func _detail_material(color: String, kind: String, repeats: Vector2 = Vector2.ONE) -> ShaderMaterial:
	var material := super._fade_material(color,kind,repeats)
	if kind=="flat":
		# The inherited city helper deliberately grades its plaster textures.
		# These few new dark joints, windows, brass studs and cloth colours need
		# their authored values; no cached material elsewhere is changed.
		if _detail_flat_texture==null:
			var pixels := Image.create(2,2,false,Image.FORMAT_RGBA8)
			pixels.fill(Color.WHITE)
			_detail_flat_texture = ImageTexture.create_from_image(pixels)
		material.set_shader_parameter("surface_texture",_detail_flat_texture)
		material.set_shader_parameter("surface_color",Color(color))
	return material


func _repeat_boxes(parent: Node3D, positions: Array[Vector3], size: Vector3, material: Material) -> void:
	if positions.is_empty():
		return
	var box := BoxMesh.new()
	box.size = size
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.mesh = box
	data.instance_count = positions.size()
	for index: int in range(positions.size()):
		data.set_instance_transform(index,Transform3D(Basis.IDENTITY,positions[index]))
	var node := MultiMeshInstance3D.new()
	node.multimesh = data
	node.material_override = material
	parent.add_child(node)
	_detail_instances += positions.size()
	_detail_draw_groups += 1


func _detail_register_group(body: Node3D, bounds: Rect2, height: float, materials: Array[ShaderMaterial], kind: String) -> void:
	roof_rows.append({"node":body,"body":body,"materials":materials,"fade":0.0,"logical_bounds":bounds,"render_height":height})
	var row := {"body":body,"bounds":bounds,"height":height}
	_body_rows.append(row)
	_body_by_instance[body.get_instance_id()] = row
	_detail_groups.append({"kind":kind,"bounds":_row(bounds),"render_height":height,"material_count":materials.size()})


func _detail_add_water_solid(bounds: Rect2, kind: String) -> void:
	var contained := false
	for water: Rect2 in _water_bounds:
		if water.encloses(bounds):
			contained = true
			break
	solid_footprints.append(bounds)
	_detail_solids.append({"kind":kind,"bounds":_row(bounds),"within_obstacle":contained})


func _row(bounds: Rect2) -> Array:
	return [bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]


func audit() -> Dictionary:
	var result := super.audit()
	result["detail_geometry"] = {"layout_source":DETAIL_LAYOUT,"base_layout_source":layout_path,"focus_bounds":_detail.get("focus_bounds",[]),"south_gate_built":_detail_gate_built,"wanli_bridge_built":_detail_bridge_built,"bridge_posts":_detail_bridge_posts,"authored_house_count":_detail_houses.size(),"built_house_ids":_detail_built_houses.duplicate(),"raised_footprints":_detail_solids.duplicate(true),"occlusion_groups":_detail_groups.duplicate(true),"repeated_instances":_detail_instances,"repeated_draw_groups":_detail_draw_groups,"logical_walk_surface_height":0.0,"new_walk_obstacles":false,"camera_and_person_scale_changed":false}
	return result
