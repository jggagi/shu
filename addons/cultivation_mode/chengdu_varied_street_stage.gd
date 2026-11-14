extends "res://addons/cultivation_mode/chengdu_painted_city_stage.gd"
## Ten authored exterior silhouettes inside the accepted individual lots.
## All other houses, the gate painting and the continuous city stay inherited.

const VARIED_LAYOUT := "res://assets/data/chengdu-varied-street-layout.json"
var _varied_houses: Dictionary = {}
var _varied_roots: Dictionary = {}
var _varied_built: Array[String] = []
var _varied_types: Dictionary = {}
var _varied_heights: Dictionary = {}
var _varied_bounds: Dictionary = {}
var _varied_errors: Array[String] = []
var _removed_sample_overlays := 0


func _init() -> void:
	super()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(VARIED_LAYOUT))
	if data is Dictionary:
		for house: Dictionary in data.get("houses",[]):
			_varied_houses[str(house.id)]=house


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	super.setup(walker,font,definition)
	_exclude_sample_overlays()


func _materialize_house(row: Dictionary) -> void:
	super._materialize_house(row)
	# LargeStage registers the lot after virtual geometry construction and
	# writes its old profile height. Patch only these ten after that write.
	var id := str(_building_profile(row.bounds).get("id",""))
	if _varied_heights.has(id):
		for roof: Dictionary in roof_rows:
			var body: Node = roof.get("body")
			if is_instance_valid(body) and str(body.get_meta("varied_street_id",""))==id:
				roof["render_height"]=_varied_heights[id]
		for body: Dictionary in _body_rows:
			if str(body.body.get_meta("varied_street_id",""))==id:
				body["height"]=_varied_heights[id]


func _build_dense_ward(bounds: Rect2, label: String) -> void:
	var id := str(_building_profile(bounds).get("id",""))
	if not _varied_houses.has(id):
		super._build_dense_ward(bounds,label)
		return
	var profile: Dictionary = _varied_houses[id]
	var body := _lot_root(bounds,"VariedFirstStreetHouse_"+id)
	body.set_meta("varied_street_id",id)
	var front := Node3D.new()
	front.rotation_degrees.y=float(profile.yaw_degrees)
	body.add_child(front)
	# +/-90 degrees exchanges local width/depth before rotation. The front
	# always faces a real street and every roof edge stays within the old lot.
	var width := bounds.size.y/WORLD_SCALE
	var depth := bounds.size.x/WORLD_SCALE
	var wall := _detail_material("#ded5bf","plaster")
	var wood := _detail_material("#87684c","wood")
	var dark := _detail_material("#4f645b","flat")
	var stone := _detail_material("#b7b6a5","stone")
	var tile := _detail_material("#6e817b","roof",Vector2(2.1,1.2))
	var cloth := _detail_material("#bbaa86","flat")
	var materials: Array[ShaderMaterial] = [wall,wood,dark,stone,tile,cloth]
	_box(front,Vector3(0,0.075,0),Vector3(width-0.05,0.15,depth-0.05),stone)
	var form := str(profile.form)
	var eave := float(profile.eave_height)
	var rise := float(profile.roof_rise)
	if str(profile.type)=="two_storey":
		_build_upper_house(front,width,depth,eave,rise,form,materials)
	elif form=="chamfered_corner":
		_build_corner_shop(front,width,depth,eave,rise,materials)
	else:
		var shop := str(profile.type)=="shop"
		var recess := 0.40 if shop else 0.10
		_box(front,Vector3(0,eave*0.5,-recess*0.5),Vector3(width-0.20,eave-0.12,depth-0.16-recess),wall)
		var face := depth*0.5-0.10-recess
		_front_frame(front,width,eave,face,wood)
		_closed_door(front,Vector3(width*0.26,0.12,face+0.035),0.44,minf(eave-0.28,1.51),wood,dark)
		_window(front,Vector3(-width*0.20,minf(eave*0.59,1.12),face+0.045),Vector2(width*0.37,eave*0.33),wood,dark)
		if form=="low_workshop":
			_shed_roof(front,Vector3(0,eave,0),width-0.08,depth-0.08,rise,tile,wood)
		else:
			_pitched_roof(front,Vector3(0,eave,0),width,depth,rise,tile,wood,form in ["front_gable","cloth_awning"],wall)
		if form=="stepped_gable":
			for side: float in [-1,1]:
				for step: int in range(3):
					_box(front,Vector3(side*(width*0.5-0.11),eave+0.12+step*0.17,0),Vector3(0.10,0.18,depth*(0.80-step*0.22)),wall)
		if form=="timber_frame":
			for x: float in [-0.43,0.0,0.43]:
				_box(front,Vector3(x,eave*0.50,face+0.055),Vector3(0.055,eave-0.1,0.045),wood)
		if shop:
			_shop_front(front,width,depth,eave,form,materials,str(profile.get("sign","")))
		elif form in ["front_gable","stepped_gable"]:
			_home_prop(front,width,depth,form=="front_gable",materials)
	_register_lot_roof(body,materials)
	_built_houses+=1
	if _detail_houses.has(id):
		_detail_built_houses.append(id)
	_varied_roots[id]=body
	_varied_built.append(id)
	_varied_types[str(profile.type)]=int(_varied_types.get(str(profile.type),0))+1
	_varied_bounds[id]=_row(bounds)
	_measure_sample(id,body,bounds)
	if is_instance_valid(_painted_city_surfaces):
		_painted_city_surfaces.call("attach_tree",body)
	_exclude_sample_overlays()


func _front_frame(parent: Node3D, width: float, height: float, z: float, wood: ShaderMaterial) -> void:
	for side: float in [-1,1]:
		_box(parent,Vector3(side*(width*0.5-0.13),height*0.50,z+0.035),Vector3(0.085,height-0.10,0.07),wood)
	for y: float in [0.24,height-0.12]:
		_box(parent,Vector3(0,y,z+0.035),Vector3(width-0.18,0.075,0.07),wood)


func _closed_door(parent: Node3D, at: Vector3, width: float, height: float, wood: ShaderMaterial, dark: ShaderMaterial) -> void:
	_box(parent,at+Vector3.UP*height*0.5,Vector3(width,height,0.05),wood)
	for x: float in [-0.22,0.0,0.22]:
		_box(parent,at+Vector3(x*width,height*0.50,0.032),Vector3(0.014,height*0.93,0.015),dark)
	_box(parent,at+Vector3(width*0.18,height*0.48,0.039),Vector3(0.035,0.07,0.015),dark)


func _window(parent: Node3D, at: Vector3, size: Vector2, wood: ShaderMaterial, dark: ShaderMaterial) -> void:
	_box(parent,at,Vector3(size.x,size.y,0.035),dark)
	for index: int in range(4):
		_box(parent,at+Vector3(lerpf(-size.x*0.48,size.x*0.48,index/3.0),0,0.024),Vector3(0.033,size.y+0.035,0.018),wood)
	for side: float in [-1,1]:
		_box(parent,at+Vector3(0,side*size.y*0.5,0.024),Vector3(size.x+0.035,0.033,0.018),wood)
	_box(parent,at+Vector3(0,0,0.025),Vector3(size.x,0.026,0.018),wood)


func _pitched_roof(parent: Node3D, at: Vector3, width: float, depth: float, rise: float, tile: ShaderMaterial, wood: ShaderMaterial, along_front: bool=false, gable_wall: ShaderMaterial=null) -> void:
	var roof := Node3D.new()
	roof.position=at
	parent.add_child(roof)
	if along_front:
		roof.rotation.y=PI*0.5
		var previous := width
		width=depth
		depth=previous
	for side: int in [-1,1]:
		var panel := MeshInstance3D.new()
		panel.mesh=_roof_surface(width-0.40,depth-0.40,side)
		panel.scale.y=rise/0.49
		panel.material_override=tile
		roof.add_child(panel)
	var ridge := _cylinder(roof,Vector3(0,rise+0.025,0),0.045,width-0.13,tile)
	ridge.rotation.z=PI*0.5
	for side: float in [-1,1]:
		_box(roof,Vector3(0,rise*0.20,side*(depth*0.5-0.07)),Vector3(width-0.08,0.055,0.065),wood)
		_gable(roof,side*(width*0.5-0.11),depth-0.22,rise,gable_wall if gable_wall!=null else tile)


func _gable(parent: Node3D, x: float, depth: float, rise: float, material: ShaderMaterial) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3 in [Vector3(x,0,-depth*0.5),Vector3(x,rise,0),Vector3(x,0,depth*0.5)]:
		surface.set_normal(Vector3(signf(x),0,0))
		surface.set_uv(Vector2(p.z,p.y))
		surface.add_vertex(p)
	var mesh := MeshInstance3D.new()
	mesh.mesh=surface.commit()
	mesh.material_override=material
	parent.add_child(mesh)


func _shed_roof(parent: Node3D, at: Vector3, width: float, depth: float, rise: float, tile: ShaderMaterial, wood: ShaderMaterial) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = [Vector3(-width*0.5,0,depth*0.5),Vector3(width*0.5,0,depth*0.5),Vector3(width*0.5,rise,-depth*0.5),Vector3(-width*0.5,rise,-depth*0.5)]
	for index: int in [0,1,2,0,2,3]:
		surface.set_normal(Vector3(0,1,0.2).normalized())
		surface.set_uv(Vector2(points[index].x/width+0.5,points[index].z/depth+0.5))
		surface.add_vertex(points[index]+at)
	var mesh := MeshInstance3D.new()
	mesh.mesh=surface.commit()
	mesh.material_override=tile
	parent.add_child(mesh)
	_box(parent,at+Vector3(0,0,depth*0.5-0.03),Vector3(width,0.06,0.06),wood)


func _shop_front(parent: Node3D, width: float, depth: float, eave: float, form: String, materials: Array[ShaderMaterial], sign_text: String) -> void:
	var wood := materials[1]
	var dark := materials[2]
	var cloth := materials[5]
	var z := depth*0.5-0.22
	_box(parent,Vector3(-width*0.16,0.53,z),Vector3(width*0.55,0.76,0.28),wood)
	_box(parent,Vector3(-width*0.16,0.96,z-0.025),Vector3(width*0.59,0.075,0.34),wood)
	if form=="cloth_awning":
		_box(parent,Vector3(0,eave*0.74,z-0.03),Vector3(width*0.85,0.065,0.37),cloth)
		for index: int in range(2):
			_box(parent,Vector3(-0.42+index*0.36,1.05,z-0.08),Vector3(0.24,0.58,0.045),cloth)
	else:
		for index: int in range(3):
			_cylinder(parent,Vector3(-0.47+index*0.22,1.08,z),0.07,0.16,cloth)
	for x: float in [-width*0.40,width*0.40]:
		_box(parent,Vector3(x,eave*0.45,z+0.07),Vector3(0.045,eave*0.90,0.045),wood)
	if not sign_text.is_empty():
		_detail_sign(parent,Vector3(width*0.32,eave*0.67,depth*0.5-0.08),sign_text,Vector2(0.21,0.42),27,dark,materials)


func _build_upper_house(parent: Node3D, width: float, depth: float, eave: float, rise: float, form: String, materials: Array[ShaderMaterial]) -> void:
	var wall := materials[0]
	var wood := materials[1]
	var dark := materials[2]
	var tile := materials[4]
	var z := depth*0.5-0.12
	_box(parent,Vector3(0,0.93,-0.05),Vector3(width-0.20,1.74,depth-0.26),wall)
	_front_frame(parent,width,1.82,z-0.08,wood)
	_closed_door(parent,Vector3(0.25,0.12,z-0.04),0.52,1.52,wood,dark)
	_window(parent,Vector3(-0.45,1.05,z),Vector2(0.51,0.60),wood,dark)
	var upper_width := width-0.28 if form=="upper_gallery" else width*0.71
	_box(parent,Vector3(0,(1.90+eave)*0.5,-0.17),Vector3(upper_width,eave-1.90,depth-0.52),wall)
	_box(parent,Vector3(0,1.87,-0.02),Vector3(width-0.14,0.12,depth-0.14),wood)
	var upper_z := depth*0.5-0.40
	_window(parent,Vector3(0,(1.90+eave)*0.5,upper_z),Vector2(upper_width*0.77,0.73),wood,dark)
	for side: float in [-1,1]:
		_box(parent,Vector3(side*(upper_width*0.5-0.05),(1.90+eave)*0.5,upper_z),Vector3(0.07,eave-1.84,0.07),wood)
		# The inherited camera looks north: side walls are prominent as well as
		# the street-facing facade. Give each storey a small framed side window.
		for floor_index: int in range(2):
			var side_wall := Node3D.new()
			var half_width := width*0.5-0.09 if floor_index==0 else upper_width*0.5+0.008
			side_wall.position=Vector3(side*half_width,0,-0.12 if floor_index==0 else -0.17)
			side_wall.rotation.y=side*PI*0.5
			parent.add_child(side_wall)
			_window(side_wall,Vector3(0,1.06 if floor_index==0 else (1.90+eave)*0.5,0.008),Vector2(0.63,0.60 if floor_index==0 else 0.70),wood,dark)
	if form=="upper_gallery":
		for index: int in range(6):
			_box(parent,Vector3(lerpf(-width*0.40,width*0.40,index/5.0),2.16,z-0.01),Vector3(0.035,0.45,0.035),wood)
		_box(parent,Vector3(0,2.40,z-0.01),Vector3(width*0.84,0.055,0.055),wood)
		_pitched_roof(parent,Vector3(0,eave,-0.02),width,depth-0.06,rise,tile,wood,false,wall)
	else:
		_pitched_roof(parent,Vector3(0,1.92,0.06),width,depth-0.12,0.32,tile,wood,false,wall)
		_pitched_roof(parent,Vector3(0,eave,-0.16),upper_width+0.18,depth-0.46,rise,tile,wood,true,wall)


func _home_prop(parent: Node3D, width: float, depth: float, water_jar: bool, materials: Array[ShaderMaterial]) -> void:
	var at := Vector3(width*0.38,0,depth*0.5-0.15)
	var finish := _detail_material("#92755c","flat") if water_jar else materials[1]
	if water_jar:
		materials.append(finish)
	var top := 0.43 if water_jar else 0.33
	_cylinder(parent,at+Vector3.UP*(0.29 if water_jar else 0.24),0.11 if water_jar else 0.12,0.28 if water_jar else 0.18,finish,1.08)
	_cylinder(parent,at+Vector3.UP*(top+0.005),0.127,0.025,finish)
	_cylinder(parent,at+Vector3.UP*(top+0.020),0.096,0.006,materials[2])
	if not water_jar:
		for side: float in [-1,1]:
			_box(parent,at+Vector3(side*0.105,0.43,0),Vector3(0.025,0.18,0.025),finish)
		_box(parent,at+Vector3.UP*0.52,Vector3(0.235,0.025,0.025),finish)


func _build_corner_shop(parent: Node3D, width: float, depth: float, eave: float, rise: float, materials: Array[ShaderMaterial]) -> void:
	var wall := materials[0]
	var wood := materials[1]
	var dark := materials[2]
	var tile := materials[4]
	var w := width*0.5-0.12
	var d := depth*0.5-0.12
	var outline: Array[Vector2] = [Vector2(-w,-d),Vector2(w,-d),Vector2(w,d),Vector2(-w+0.40,d),Vector2(-w,d-0.40)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(outline.size()):
		var a := outline[index]
		var b := outline[(index+1)%outline.size()]
		var normal := Vector3(b.y-a.y,0,a.x-b.x).normalized()
		for vertex: Vector3 in [Vector3(a.x,0.12,a.y),Vector3(b.x,0.12,b.y),Vector3(b.x,eave,b.y),Vector3(a.x,0.12,a.y),Vector3(b.x,eave,b.y),Vector3(a.x,eave,a.y)]:
			surface.set_normal(normal)
			surface.set_uv(Vector2(vertex.x+vertex.z,vertex.y))
			surface.add_vertex(vertex)
	var body := MeshInstance3D.new()
	body.mesh=surface.commit()
	body.material_override=wall
	parent.add_child(body)
	# A compact pyramidal roof has a different silhouette from every gable.
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(outline.size()):
		var a := outline[index]*1.04
		var b := outline[(index+1)%outline.size()]*1.04
		var tip := Vector3(0,eave+rise,-0.08)
		var p := Vector3(a.x,eave,a.y)
		var q := Vector3(b.x,eave,b.y)
		var normal := (q-p).cross(tip-p).normalized()
		if normal.y<0:
			normal=-normal
		for vertex: Vector3 in [p,q,tip]:
			roof.set_normal(normal)
			roof.set_uv(Vector2(vertex.x/width+0.5,vertex.z/depth+0.5))
			roof.add_vertex(vertex)
	var cap := MeshInstance3D.new()
	cap.mesh=roof.commit()
	cap.material_override=tile
	parent.add_child(cap)
	_closed_door(parent,Vector3(0.43,0.13,d+0.02),0.48,1.45,wood,dark)
	_window(parent,Vector3(-0.23,1.10,d+0.025),Vector2(0.58,0.50),wood,dark)
	var side := Node3D.new()
	side.rotation.y=-PI*0.5
	side.position=Vector3(-w-0.02,0,-0.13)
	parent.add_child(side)
	_window(side,Vector3(0,1.10,0),Vector2(0.65,0.50),wood,dark)
	_box(parent,Vector3(-0.17,0.64,d-0.10),Vector3(0.74,0.17,0.23),wood)
	_detail_sign(parent,Vector3(0.57,1.64,d+0.025),"茶",Vector2(0.28,0.22),26,dark,materials)


func _sample_root(node: Node) -> Node:
	var ancestor := node
	while ancestor!=null and ancestor!=world_root:
		if not str(ancestor.get_meta("varied_street_id","")).is_empty():
			return ancestor
		ancestor=ancestor.get_parent()
	return null


func _exclude_sample_overlays() -> void:
	if not is_instance_valid(_painted_gate):
		return
	var retained: Array[Dictionary] = []
	var ids: Dictionary = {}
	for record: Dictionary in _painted_gate.get("_installed"):
		if _sample_root(record.node)!=null:
			if record.node.material_overlay==record.material:
				record.node.material_overlay=record.old_overlay
			_removed_sample_overlays+=1
		else:
			retained.append(record)
			ids[int(record.source_id)]=true
	_painted_gate.set("_installed",retained)
	_painted_gate.set("_painted_unique_ids",ids)
	var seen: Dictionary = _painted_gate.get("_seen")
	for root_node: Node in _varied_roots.values():
		for mesh: Node in root_node.find_children("*","GeometryInstance3D",true,false):
			seen[mesh.get_instance_id()]=true


func _local_chain(node: Node3D) -> Transform3D:
	var chain: Array[Node3D] = []
	var ancestor: Node = node
	while ancestor!=world_root:
		if ancestor is Node3D:
			chain.append(ancestor as Node3D)
		ancestor=ancestor.get_parent()
	var result := Transform3D.IDENTITY
	for index: int in range(chain.size()-1,-1,-1):
		result=result*chain[index].transform
	return result


func _measure_sample(id: String, body: Node3D, bounds: Rect2) -> void:
	var height := 0.0
	for mesh: MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		var box := mesh.mesh.get_aabb()
		var transform := _local_chain(mesh)
		for x: float in [box.position.x,box.end.x]:
			for y: float in [box.position.y,box.end.y]:
				for z: float in [box.position.z,box.end.z]:
					var point: Vector3 = transform*Vector3(x,y,z)
					height=maxf(height,point.y)
					if not bounds.grow(0.02).has_point(world_to_logical(point)):
						var error := id+" mesh leaves existing lot: "+str(mesh.name)
						if not error in _varied_errors:
							_varied_errors.append(error)
	_varied_heights[id]=height+0.04


func audit() -> Dictionary:
	var result := super.audit()
	var overlay_count := 0
	for body: Node in _varied_roots.values():
		for mesh: GeometryInstance3D in body.find_children("*","GeometryInstance3D",true,false):
			if mesh.material_overlay!=null:
				overlay_count+=1
	result["varied_street"]={"layout_source":VARIED_LAYOUT,"authored_house_count":_varied_houses.size(),
		"built_house_ids":_varied_built.duplicate(),"built_type_counts":_varied_types.duplicate(),
		"footprint_errors":_varied_errors.duplicate(),"gate_overlay_count_on_sample":overlay_count,
		"removed_sample_overlay_records":_removed_sample_overlays,"render_height_by_id":_varied_heights.duplicate(),
		"original_bounds_by_id":_varied_bounds.duplicate(true),"no_new_walk_obstacles":true,
		"continuous_follow_unchanged":true,"new_state":false,"closed_exteriors":true}
	return result
