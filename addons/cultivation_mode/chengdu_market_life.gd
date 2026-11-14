extends Node
## Market dressing only. Solid goods remain on the old blocked lots; four
## explicitly authored frontage vendors are nonblocking presentation actors.

const LAYOUT := "res://assets/data/chengdu-market-life-layout.json"
const VENDORS := "res://assets/art/chengdu_market_life/vendors.png"
const PLANTS := "res://assets/art/chengdu_market_life/plants.png"
const CARD_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;
uniform sampler2D sheet_cell : source_color, filter_linear_mipmap, repeat_disable;
uniform float fade=0.0;
uniform vec2 player_uv=vec2(0.5);
void fragment() {
    vec2 delta=(SCREEN_UV-player_uv)*vec2(1280.0,720.0);
    float local=1.0-smoothstep(44.0,92.0,length(delta));
    float pattern=fract(sin(dot(floor(UV*vec2(680.0,300.0)),vec2(12.9898,78.233)))*43758.5453);
    if (pattern<local*fade*0.88) { discard; }
    vec4 c=texture(sheet_cell,UV);
    ALBEDO=c.rgb*COLOR.rgb;
    ALPHA=c.a;
    ALPHA_SCISSOR_THRESHOLD=0.5;
    ROUGHNESS=0.98;
}
"""

var records: Array[Dictionary] = []
var _stage: Node
var _helper: Node
var _font: Font
var _entries: Dictionary = {}
var _vegetation: Dictionary = {}
var _seen: Dictionary = {}
var _roots: Array[Node] = []
var _bindings: Array[Dictionary] = []
var _errors: Array[String] = []
var _bounds_errors: Array[Dictionary] = []
var _textures: Dictionary = {}
var _texture_audit: Dictionary = {}
var _card_shader: Shader
var _tools: Dictionary = {}
var _colors: Dictionary = {}
var _stall_count := 0
var _vendor_count := 0
var _sign_count := 0
var _plant_count := 0
var _triangles := 0
var _checked_signs: Dictionary = {}
var _frontage_vendors: Array[Dictionary] = []


func setup(stage: Node, material_helper: Node, font: Font) -> void:
	if _stage!=null:
		return
	_stage=stage
	_helper=material_helper
	_font=font
	if not FileAccess.file_exists(LAYOUT):
		_errors.append("market layout missing")
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not data is Dictionary:
		_errors.append("market layout is not an object")
		return
	for entry: Dictionary in data.get("entries",[]):
		_entries[str(entry.house_id)]=entry
	for entry: Dictionary in data.get("vegetation",[]):
		_vegetation[str(entry.house_id)]=entry
	_card_shader=Shader.new()
	_card_shader.code=CARD_SHADER
	for body: Node in _stage.get("_art_roots").values():
		attach_house(body)


func attach_house(body: Node) -> void:
	if not is_instance_valid(body) or _seen.has(body.get_instance_id()):
		return
	var id := str(body.get_meta("art_street_id",""))
	if not _entries.has(id) and not _vegetation.has(id):
		return
	var parent := body.get_node_or_null("StreetFacingStructure") as Node3D
	if parent==null:
		_errors.append(id+": authored front missing")
		return
	_seen[body.get_instance_id()]=true
	var profile: Dictionary = _stage.get("_art_profiles")[id]
	var row := _row(body)
	var root := Node3D.new()
	root.name="MarketLife"
	_preserve(root)
	root.set_meta("market_life_root",true)
	parent.add_child(root)
	_roots.append(root)
	_tools={}
	_colors={}
	var entry: Dictionary = _entries.get(id,_vegetation.get(id,{}))
	var width := float(profile.bounds[3])/80.0
	var depth := float(profile.bounds[2])/80.0
	if _entries.has(id):
		_stall(entry,width,depth,float(profile.eave_height))
		_flush(root,body,id,row,profile.bounds)
		_vendor(root,body,id,row,entry,profile)
		_sign(root,body,id,row,entry,width,depth,float(profile.eave_height),profile.bounds)
		_stall_count+=1
	for plant: Dictionary in entry.get("plants",[]):
		_plant(root,body,id,row,plant,profile.bounds)
	_flush(root,body,id,row,profile.bounds)


func _preserve(node: Node) -> void:
	node.set_meta("art_street_preserve",true)
	node.set_meta("painted_city_preserve",true)
	node.set_meta("market_life_detail",true)


func _row(body: Node) -> Dictionary:
	for row: Dictionary in _stage.get("roof_rows"):
		if row.get("body")==body:
			return row
	_errors.append(str(body.name)+": roof row missing")
	return {}


func _tool(role: String) -> SurfaceTool:
	if not _tools.has(role):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[role]=tool
	return _tools[role]


func _quad(role: String,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	var tool := _tool(role)
	var normal := (b-a).cross(c-a).normalized()
	for index: int in [0,1,2,0,2,3]:
		tool.set_normal(normal)
		tool.set_uv([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)][index])
		tool.set_color(Color.WHITE)
		tool.add_vertex([a,b,c,d][index])
	_triangles+=2


func _primitive(role: String,mesh: Mesh,at: Vector3,basis: Basis=Basis.IDENTITY) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices=arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else vertices.size()
	var tool := _tool(role)
	for item: int in range(count):
		var index := indices[item] if not indices.is_empty() else item
		tool.set_normal((basis*normals[index]).normalized())
		tool.set_uv(uv[index])
		tool.set_color(Color.WHITE)
		tool.add_vertex(basis*vertices[index]+at)
	_triangles+=count/3


func _box(role: String,at: Vector3,size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size=size
	_primitive(role,mesh,at)


func _cylinder(role: String,at: Vector3,radius: float,height: float,top: float=1.0,basis: Basis=Basis.IDENTITY) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius=radius
	mesh.top_radius=radius*top
	mesh.height=height
	mesh.radial_segments=8
	mesh.rings=1
	_primitive(role,mesh,at,basis)


func _fruit(role: String,at: Vector3,radius: float,color: Color) -> void:
	_colors[role]=color
	var mesh := SphereMesh.new()
	mesh.radius=radius
	mesh.height=radius*1.8
	mesh.radial_segments=8
	mesh.rings=4
	_primitive(role,mesh,at)


func _jar(at: Vector3,radius: float,height: float) -> void:
	_cylinder("ceramic",at+Vector3.UP*height*.44,radius,height*.82,.78)
	_cylinder("ceramic",at+Vector3.UP*height*.90,radius*.62,height*.16,1.12)
	_cylinder("dark",at+Vector3.UP*(height+.003),radius*.48,.006)


func _basket(at: Vector3,radius: float,height: float) -> void:
	_cylinder("wood",at+Vector3.UP*height*.5,radius,height,1.08)
	_cylinder("dark",at+Vector3.UP*(height+.003),radius*.83,.006)


func _stall(entry: Dictionary,width: float,depth: float,eave: float) -> void:
	var front := depth*.5
	var courtyard := str(entry.get("mode","open_shop"))=="courtyard_wall_counter"
	var surface := 1.055 if not courtyard else 1.035
	var z := front-.14 if not courtyard else .86
	if courtyard:
		_box("wood",Vector3(-.28,surface-.045,z),Vector3(width*.62,.07,.20))
	# A small dark frame gives six different signs a common readable support.
	var top := minf(eave-.23,1.76) if not courtyard else 1.65
	for side: float in [-1,1]:
		_box("wood",Vector3(side*width*.40,(top+.21)*.5,front-.065),Vector3(.035,top-.21,.035))
	_box("wood",Vector3(0,top,front-.065),Vector3(width*.82,.045,.045))
	var kind := str(entry.get("kind","tea"))
	match kind:
		"tea", "snack":
			_jar(Vector3(.10,surface,z-.025),.085,.20)
			for index: int in range(3):
				_cylinder("ceramic",Vector3(-.58+index*.15,surface+.045,z),.047,.08,1.06)
				_cylinder("dark",Vector3(-.58+index*.15,surface+.087,z),.034,.004)
			_basket(Vector3(-.23,surface,z-.04),.12,.065)
			for index: int in range(4):
				_fruit("snack",Vector3(-.29+(index%2)*.095,surface+.105,z-.08+int(index/2)*.075),.039,Color("#d5bd83"))
		"fruitveg", "fruit":
			for index: int in range(2):
				_box("wood",Vector3(-.51+index*.39,surface+.025,z),Vector3(.34,.05,.23))
			for index: int in range(12):
				var role := "fruit_yellow" if index<6 else "fruit_green"
				_fruit(role,Vector3(-.63+(index%6)*.12,surface+.09,z-.045+int(index/6)*.11),.051,Color("#b9a947") if index<6 else Color("#71834b"))
		"cloth":
			for index: int in range(3):
				var role := "cloth_"+str(index)
				_colors[role]=[Color("#a4afa4"),Color("#b49a79"),Color("#899eaa")][index]
				_box(role,Vector3(-.52+index*.30,surface+.065+index*.018,z),Vector3(.26,.12,.23))
		"pottery":
			for index: int in range(5):
				_jar(Vector3(-.62+index*.17,surface,z-.035),.055+(index%2)*.022,.15+(index%3)*.06)
		"herbs":
			for index: int in range(3):
				var at := Vector3(-.63+index*.29,surface,z-.025)
				_basket(at,.105,.075)
				for leaf: int in range(4):
					var x := at.x-.065+leaf*.04
					_quad("herb",Vector3(x,surface+.08,z-.08),Vector3(x+.05,surface+.09,z+.02),Vector3(x+.04,surface+.20,z+.01),Vector3(x-.015,surface+.18,z-.06))
			_colors.herb=Color("#738056")
		"bamboo":
			for index: int in range(7):
				_cylinder("bamboo",Vector3(-.52+index*.045,surface+.23,z-.02),.016,.44,1.0,Basis(Vector3.FORWARD,.16))
			_colors.bamboo=Color("#a8a26c")
			_basket(Vector3(.02,surface,z-.015),.11,.15)
			_basket(Vector3(.25,surface,z-.015),.095,.12)


func _material(role: String,row: Dictionary) -> ShaderMaterial:
	var base := role if role in ["wood","stone","dark","cloth","ceramic","roof"] else "ceramic"
	var material := _helper.call("create_detail_material",base,row) as ShaderMaterial
	if material==null:
		_errors.append("market material factory unavailable: "+role)
		return null
	if _colors.has(role):
		material.set_shader_parameter("textured",false)
		material.set_shader_parameter("surface_color",_colors[role])
	_bindings.append({"row":row,"material":material})
	return material


func _flush(root: Node3D,body: Node,id: String,row: Dictionary,bounds: Array) -> void:
	for role: String in _tools:
		var node := MeshInstance3D.new()
		node.name="Market_"+role
		node.mesh=(_tools[role] as SurfaceTool).commit()
		node.material_override=_material(role,row)
		_preserve(node)
		root.add_child(node)
		_check(node,id,bounds)
		records.append({"node":node,"role":role,"kind":"goods","house_id":id,"roof_row":row})
	_tools={}


func _card_material(texture: Texture2D,row: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader=_card_shader
	material.set_shader_parameter("sheet_cell",texture)
	material.set_shader_parameter("fade",float(row.get("fade",0.0)))
	(row.materials as Array).append(material)
	_bindings.append({"row":row,"material":material})
	return material


func _card(root: Node3D,id: String,row: Dictionary,kind: String,texture: Texture2D,at: Vector3,size: Vector2,bounds: Array,fixed_world: bool=false,frontage: Dictionary={}) -> void:
	_tools={}
	var basis := _chain(root,_stage.get("world_root")).basis.inverse() if fixed_world else Basis.IDENTITY
	_quad("card",at+basis*Vector3(-size.x*.5,0,0),at+basis*Vector3(size.x*.5,0,0),at+basis*Vector3(size.x*.5,size.y,0),at+basis*Vector3(-size.x*.5,size.y,0))
	var node := MeshInstance3D.new()
	node.name="Market_"+kind
	node.mesh=(_tools.card as SurfaceTool).commit()
	node.material_override=_card_material(texture,row)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preserve(node)
	root.add_child(node)
	if kind=="vendor" and not frontage.is_empty():
		_check_frontage(node,root,id,frontage)
	else:
		_check(node,id,bounds)
	records.append({"node":node,"role":kind,"kind":kind,"house_id":id,"roof_row":row,"fixed_world_orientation":fixed_world,"frontage_envelope":frontage.duplicate(true)})
	_tools={}


func _vendor(root: Node3D,body: Node,id: String,row: Dictionary,entry: Dictionary,profile: Dictionary) -> void:
	var texture := _cell("vendors",int(entry.get("vendor_cell",0)))
	if texture==null:
		return
	var p: Array = entry.get("vendor_position",[-.32,.20,.79])
	var at := Vector3(float(p[0]),float(p[1]),float(p[2]))
	var frontage: Dictionary = entry.get("vendor_frontage_envelope",{})
	var outside := not frontage.is_empty() and bool(frontage.get("nonblocking",false))
	var height := 1.35
	if outside:
		height=float(entry.get("vendor_height",1.70))
	elif str(entry.get("mode",""))!="courtyard_wall_counter":
		height=minf(height,float(profile.eave_height)-.18-at.y)
	var width := .55
	if outside:
		var foot := at
		at.y-=float(_texture_audit["vendors"+str(int(entry.get("vendor_cell",0)))].shoe_uv_from_bottom)*height
		var chain := _chain(root,_stage.get("world_root"))
		var world_foot := chain*foot
		var logical: Vector2 = _stage.call("world_to_logical",world_foot)
		var clearance := float(frontage.get("anchor_radius_logical",18.0))
		var walkable := _walkable_anchor(logical,clearance)
		var proof := {"house_id":id,"logical_anchor":[logical.x,logical.y],"shoe_world_y":world_foot.y,"anchor_clearance_logical":clearance,"original_navigation_walkable":walkable,"nonblocking":true,"height_meters":height,"width_meters":width,"card_base_local_y":at.y}
		_frontage_vendors.append(proof)
		if not walkable:
			_bounds_errors.append({"house_id":id,"contract":"nonblocking_vendor_frontage","error":"original navigation rejects merchant foot clearance","logical":[logical.x,logical.y]})
		if str(entry.get("mode",""))!="open_shop" or width>float(frontage.get("maximum_billboard_width_meters",0.0)):
			_errors.append(id+": invalid explicit frontage vendor contract")
	_card(root,id,row,"vendor",texture,at,Vector2(width,height),profile.bounds,true,frontage if outside else {})
	_vendor_count+=1


func _sign(root: Node3D,body: Node,id: String,row: Dictionary,entry: Dictionary,width: float,depth: float,eave: float,bounds: Array) -> void:
	var text := str(entry.get("sign",""))
	if _font==null or text.is_empty():
		_errors.append(id+": sign or font missing")
		return
	for index: int in range(text.length()):
		var code := text.unicode_at(index)
		if not _font.has_char(code):
			_errors.append(id+": font missing character "+str(code))
	var courtyard := str(entry.get("mode",""))=="courtyard_wall_counter"
	var hanging := str(entry.get("sign_style","board"))=="hang"
	var basis := _chain(root,_stage.get("world_root")).basis.inverse()
	var normal := basis*Vector3.BACK
	# A south-facing blade sits just outside the real side wall, while its
	# full projection stays inside the original blocked lot.
	var at := Vector3(signf(normal.x)*(width*.5-.045),1.55 if courtyard else minf(eave-.22,1.76),.58)
	_tools={}
	var board := BoxMesh.new()
	board.size=Vector3(.32,.56,.04) if hanging else Vector3(.70,.27,.04)
	_primitive("wood",board,at,basis)
	_flush(root,body,id,row,bounds)
	var node := Label3D.new()
	node.name="MarketSign_"+text
	node.font=_font
	node.text=text.substr(0,1)+"\n"+text.substr(1) if hanging else text
	node.font_size=64
	node.pixel_size=.0034
	node.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	node.billboard=BaseMaterial3D.BILLBOARD_DISABLED
	node.no_depth_test=false
	node.fixed_size=false
	node.shaded=false
	node.outline_size=2
	node.modulate=Color("#e0cda1")
	node.outline_modulate=Color("#302d28")
	node.position=at+normal*.024+Vector3.UP*.018
	node.basis=basis
	_preserve(node)
	root.add_child(node)
	records.append({"node":node,"role":"sign","kind":"sign","house_id":id,"roof_row":row,"text":text,"bounds":bounds})
	_sign_count+=1


func _plant(root: Node3D,body: Node,id: String,row: Dictionary,entry: Dictionary,bounds: Array) -> void:
	var texture := _cell("plants",int(entry.get("cell",0)))
	if texture==null:
		return
	var p: Array = entry.get("position",[.62,.20,1.01])
	var s: Array = entry.get("size",[.28,.32])
	var at := Vector3(float(p[0]),float(p[1]),float(p[2]))
	var size := Vector2(float(s[0]),float(s[1]))
	var potted := id in ["ward_city_22_15","ward_city_23_19"]
	if potted:
		_cylinder("ceramic",at+Vector3.UP*.065,.105,.13,1.13)
		_cylinder("dark",at+Vector3.UP*.133,.093,.006)
		_flush(root,body,id,row,bounds)
		at.y+=.10
	_card(root,id,row,"plant",texture,at,size,bounds,true)
	_plant_count+=1


func _cell(sheet: String,index: int) -> Texture2D:
	var key := sheet+str(index)
	if _textures.has(key):
		return _textures[key]
	var path := VENDORS if sheet=="vendors" else PLANTS
	if index<0 or index>3 or not ResourceLoader.exists(path):
		_errors.append("market sheet/cell unavailable: "+key)
		return null
	var source := (load(path) as Texture2D).get_image()
	source.clear_mipmaps()
	var side := source.get_width()/2
	var image := source.get_region(Rect2i((index%2)*side,int(index/2)*side,side,side))
	image.convert(Image.FORMAT_RGBA8)
	var opaque := Rect2i()
	var first := true
	var last_opaque_y := -1
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x,y)
			color.a=0.0 if minf(color.r-color.g,color.b-color.g)>.02 else 1.0
			image.set_pixel(x,y,color)
			if color.a>.5:
				last_opaque_y=maxi(last_opaque_y,y)
				if first:
					opaque=Rect2i(x,y,1,1)
					first=false
				else:
					opaque=opaque.expand(Vector2i(x,y))
	if first:
		_errors.append("market cell has no foreground: "+key)
		return null
	var crop := opaque.grow(8).intersection(Rect2i(0,0,side,side))
	var padded := Image.create(crop.size.x+16,crop.size.y+16,false,Image.FORMAT_RGBA8)
	padded.fill(Color(0,0,0,0))
	padded.blit_rect(image,crop,Vector2i(8,8))
	padded.fix_alpha_edges()
	padded.generate_mipmaps()
	var texture := ImageTexture.create_from_image(padded)
	_textures[key]=texture
	var shoe_uv_from_bottom := float(padded.get_height()-1-(last_opaque_y-crop.position.y+8))/float(padded.get_height())
	_texture_audit[key]={"sheet":sheet,"cell":index,"source_rect":[(index%2)*side,int(index/2)*side,side,side],"foreground_bounds":[opaque.position.x,opaque.position.y,opaque.size.x,opaque.size.y],"runtime_size":[padded.get_width(),padded.get_height()],"padding":8,"rgba_before_mips":true,"shoe_uv_from_bottom":shoe_uv_from_bottom}
	return texture


func _chain(node: Node3D,stop: Node) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var parents: Array[Node3D] = []
	var ancestor: Node = node
	while ancestor!=null and ancestor!=stop:
		if ancestor is Node3D:
			parents.append(ancestor)
		ancestor=ancestor.get_parent()
	for index: int in range(parents.size()-1,-1,-1):
		transform=transform*parents[index].transform
	return transform


func _check(node: GeometryInstance3D,id: String,bounds: Array) -> void:
	var transform := _chain(node,_stage.get("world_root"))
	var expected := Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]),float(bounds[3])).grow(.02)
	var vertices := PackedVector3Array()
	if node is MeshInstance3D:
		for surface: int in range(node.mesh.get_surface_count()):
			vertices.append_array(node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	else:
		var box := node.get_aabb()
		for corner: int in range(8):
			vertices.append(box.get_endpoint(corner))
	for vertex: Vector3 in vertices:
		var point: Vector2 = _stage.call("world_to_logical",transform*vertex)
		if not expected.has_point(point):
			_bounds_errors.append({"house_id":id,"node":str(node.name),"logical":[point.x,point.y]})
			return


func _walkable_anchor(point: Vector2,clearance: float) -> bool:
	var definition: Dictionary = _stage.get("_definition")
	var floor_row: Array = definition.get("floor",[])
	if floor_row.size()!=4 or clearance<18.0:
		return false
	var floor_rect := Rect2(float(floor_row[0]),float(floor_row[1]),float(floor_row[2]),float(floor_row[3])).grow(-clearance)
	if not floor_rect.has_point(point):
		return false
	for box: Array in definition.get("obstacles",[]):
		if Rect2(float(box[0]),float(box[1]),float(box[2]),float(box[3])).grow(clearance).has_point(point):
			return false
	return true


func _check_frontage(node: MeshInstance3D,root: Node3D,id: String,contract: Dictionary) -> void:
	var rect: Array = contract.get("local_xz_rect",[])
	var vertical: Array = contract.get("vertical_range_meters",[])
	if rect.size()!=4 or vertical.size()!=2 or not bool(contract.get("nonblocking",false)):
		_errors.append(id+": missing explicit frontage envelope")
		return
	var expected := Rect2(float(rect[0]),float(rect[1]),float(rect[2]),float(rect[3])).grow(.0001)
	var transform := _chain(node,root)
	for surface: int in range(node.mesh.get_surface_count()):
		for vertex: Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var point := transform*vertex
			if not expected.has_point(Vector2(point.x,point.z)) or point.y<float(vertical[0]) or point.y>float(vertical[1]):
				_bounds_errors.append({"house_id":id,"contract":"nonblocking_vendor_frontage","error":"merchant card leaves explicit frontage envelope","local":[point.x,point.y,point.z]})
				return


func sync() -> void:
	for record: Dictionary in records:
		if record.kind!="sign" or not is_instance_valid(record.node):
			continue
		var label := record.node as Label3D
		var opacity := 1.0-float(record.roof_row.get("fade",0.0))*.88
		label.modulate.a=opacity
		label.outline_modulate.a=opacity
		if label.is_inside_tree() and not _checked_signs.has(label.get_instance_id()) and label.get_aabb().size.length_squared()>0.0:
			_check(label,str(record.house_id),record.bounds)
			_checked_signs[label.get_instance_id()]=true


func audit() -> Dictionary:
	var meshes := 0
	var houses: Dictionary = {}
	for record: Dictionary in records:
		houses[str(record.house_id)]=true
		if record.node is MeshInstance3D:
			meshes+=1
	return {"layout_source":LAYOUT,"built_house_ids":houses.keys(),"stall_count":_stall_count,"vendor_count":_vendor_count,"sign_count":_sign_count,"plant_count":_plant_count,"frontage_vendor_count":_frontage_vendors.size(),"frontage_vendors":_frontage_vendors.duplicate(true),
		"node_count":records.size(),"mesh_count":meshes,"label_count":_sign_count,"checked_sign_bounds":_checked_signs.size(),"triangles":_triangles,"roof_material_bindings":_bindings.size(),"textures":_texture_audit.duplicate(true),"bounds_errors":_bounds_errors.duplicate(),"errors":_errors.duplicate(),
		"world_space":true,"billboard":false,"original_batches_changed":false,"new_walk_obstacles":false,"new_ground_planes":false}


func _exit_tree() -> void:
	for binding: Dictionary in _bindings:
		if is_instance_valid(binding.row.get("body")):
			(binding.row.materials as Array).erase(binding.material)
	for root: Node in _roots:
		if is_instance_valid(root):
			root.queue_free()
