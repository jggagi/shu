extends Node
## Small, world-space finishing pieces. Original house batches, navigation and
## calibrated surface identities remain untouched; all additions are separate.

const HEROES := ["ward_city_22_16", "ward_city_22_19", "ward_city_23_16", "ward_city_23_15"]
const TREES := ["ward_city_22_15", "ward_city_23_19"]
const FOLIAGE := "res://assets/art/chengdu_concept_finish/foliage.png"
const LEAF_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;
uniform sampler2D foliage : source_color, filter_linear_mipmap, repeat_disable;
void fragment() {
    vec4 c=texture(foliage,UV);
    ALBEDO=c.rgb*COLOR.rgb;
    ALPHA=c.a;
    ALPHA_SCISSOR_THRESHOLD=0.5;
    ROUGHNESS=0.98;
}
"""
const FALLBACK := """shader_type spatial;
render_mode cull_disabled;
uniform vec4 surface_color : source_color = vec4(1.0);
uniform float fade = 0.0;
uniform vec2 player_uv = vec2(0.5);
void fragment() {
    vec2 delta=(SCREEN_UV-player_uv)*vec2(1280.0,720.0);
    float local=1.0-smoothstep(44.0,92.0,length(delta));
    float pattern=fract(sin(dot(floor(UV*vec2(680.0,300.0)),vec2(12.9898,78.233)))*43758.5453);
    if (pattern<local*fade*0.88) { discard; }
    ALBEDO=surface_color.rgb;
    ROUGHNESS=0.98;
    SPECULAR=0.0;
}
"""

var records: Array[Dictionary] = []
var _stage: Node
var _material_helper: Node
var _seen: Dictionary = {}
var _tools: Dictionary = {}
var _hidden_leaves: Array[Dictionary] = []
var _row_bindings: Array[Dictionary] = []
var _roots: Array[Node] = []
var _errors: Array[String] = []
var _bounds_errors: Array[Dictionary] = []
var _leaf_material: ShaderMaterial
var _fallback_shader: Shader
var _leaf_cards := 0
var _triangles := 0


func setup(stage: Node, material_helper: Node = null) -> void:
	if _stage!=null:
		return
	_stage=stage
	_material_helper=material_helper
	for body: Node in _stage.get("_art_roots").values():
		attach_house(body)


func attach_house(body: Node) -> void:
	if not is_instance_valid(body) or _seen.has(body.get_instance_id()):
		return
	var id := str(body.get_meta("art_street_id",""))
	if id not in HEROES and id not in TREES:
		return
	_seen[body.get_instance_id()]=true
	var parent := body.get_node_or_null("StreetFacingStructure") as Node3D
	if parent==null:
		_errors.append(id+": missing authored front")
		return
	var profile: Dictionary = _stage.get("_art_profiles")[id]
	var width := float(profile.bounds[3])/80.0
	var depth := float(profile.bounds[2])/80.0
	var row := _roof_row(body)
	var root := Node3D.new()
	root.name="ConceptFinish"
	_preserve(root)
	parent.add_child(root)
	_roots.append(root)
	_tools={}
	if id in HEROES:
		_eave(width,depth,float(profile.eave_height),bool(profile.get("ridge_along_front",false)))
		_stone_foot(width,depth)
		_lattice(width-0.18,depth-0.22,1.85 if id=="ward_city_22_16" else float(profile.eave_height),0.0)
		if id=="ward_city_22_16":
			_lattice(width-0.28,depth-0.42,float(profile.eave_height)-1.89,1.89,-0.08)
			# Keep these on the existing upper gallery, within its original lot.
			_jar(Vector3(-0.53,1.96,0.84),0.10,0.27)
			_basket(Vector3(0.49,1.96,0.82),0.105,0.22)
		else:
			_shop(width,depth,float(profile.eave_height),id=="ward_city_23_15")
		_flush(root,body,id,row,profile.bounds)
	if id in TREES:
		_tree(root,body,id,profile.bounds)


func _preserve(node: Node) -> void:
	node.set_meta("art_street_preserve",true)
	node.set_meta("painted_city_preserve",true)
	node.set_meta("concept_finish_detail",true)


func _tool(role: String) -> SurfaceTool:
	if not _tools.has(role):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[role]=tool
	return _tools[role]


func _triangle(role: String,a: Vector3,b: Vector3,c: Vector3,ua: Vector2 = Vector2.ZERO,ub: Vector2 = Vector2.RIGHT,uc: Vector2 = Vector2.ONE,color: Color = Color.WHITE) -> void:
	var normal := (b-a).cross(c-a).normalized()
	if normal.length_squared()<0.1:
		return
	var tool := _tool(role)
	for index: int in range(3):
		tool.set_normal(normal)
		tool.set_uv([ua,ub,uc][index])
		tool.set_color(color)
		tool.add_vertex([a,b,c][index])
	_triangles+=1


func _quad(role: String,a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color = Color.WHITE) -> void:
	_triangle(role,a,b,c,Vector2(0,1),Vector2(1,1),Vector2(1,0),color)
	_triangle(role,a,c,d,Vector2(0,1),Vector2(1,0),Vector2(0,0),color)


func _primitive(role: String,mesh: Mesh,at: Vector3,basis: Basis = Basis.IDENTITY) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices=arrays[Mesh.ARRAY_INDEX]
	var tool := _tool(role)
	var count := indices.size() if not indices.is_empty() else vertices.size()
	var normal_basis := basis.inverse().transposed()
	for item: int in range(count):
		var index := indices[item] if not indices.is_empty() else item
		tool.set_normal((normal_basis*normals[index]).normalized())
		tool.set_uv(uv[index])
		tool.set_color(Color.WHITE)
		tool.add_vertex(basis*vertices[index]+at)
	_triangles+=count/3


func _box(role: String,at: Vector3,size: Vector3) -> void:
	var box := BoxMesh.new()
	box.size=size
	_primitive(role,box,at)


func _cylinder(role: String,at: Vector3,radius: float,height: float,top: float = 1.0,basis: Basis = Basis.IDENTITY) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius=radius
	mesh.top_radius=radius*top
	mesh.height=height
	mesh.radial_segments=10
	mesh.rings=1
	_primitive(role,mesh,at,basis)


func _eave(width: float,depth: float,eave: float,along: bool) -> void:
	var span := depth-0.26 if along else width-0.22
	var count := maxi(5,int(round(span/0.24)))
	var outward := Vector3.LEFT if along else Vector3.BACK
	var across := Vector3.BACK if along else Vector3.RIGHT
	for index: int in range(count):
		var distance := lerpf(-span*0.5,span*0.5,(index+0.5)/count)
		var corner := 0.09*pow(absf(distance)/(span*0.5+0.1),6.0)
		var center := outward*((width if along else depth)*0.5-0.025)+across*distance+Vector3.UP*(eave+0.105+corner)
		_tile_end(center,outward,across)
		# Compact beam ends break the straight fascia without extending the lot.
		_box("wood",center-outward*0.065-Vector3.UP*0.13,Vector3(0.10,0.10,0.14) if not along else Vector3(0.14,0.10,0.10))


func _tile_end(center: Vector3,outward: Vector3,across: Vector3) -> void:
	for index: int in range(10):
		var a := TAU*index/10.0
		var b := TAU*(index+1)/10.0
		var outer_a := center+(across*cos(a)+Vector3.UP*sin(a))*0.052
		var outer_b := center+(across*cos(b)+Vector3.UP*sin(b))*0.052
		var inner_a := center+(across*cos(a)+Vector3.UP*sin(a))*0.034
		var inner_b := center+(across*cos(b)+Vector3.UP*sin(b))*0.034
		_quad("roof",outer_a,outer_b,inner_b,inner_a)
		_triangle("dark",center-outward*0.003,inner_a-outward*0.003,inner_b-outward*0.003)
		if index<5:
			_quad("roof",outer_a,outer_a-outward*0.12,outer_b-outward*0.12,outer_b)


func _stone_foot(width: float,depth: float) -> void:
	var count := int(ceil((width-0.18)/0.32))
	var step := (width-0.18)/count
	for index: int in range(count):
		_box("stone",Vector3(-width*0.5+0.09+step*(index+0.5),0.16,depth*0.5-0.065),Vector3(step-0.018,0.18+(index%2)*0.012,0.10))
	for side: float in [-1,1]:
		for index: int in range(5):
			_box("stone",Vector3(side*(width*0.5-0.065),0.16,lerpf(-depth*0.39,depth*0.39,(index+0.5)/5.0)),Vector3(0.10,0.18,depth*0.156-0.018))


func _lattice(width: float,depth: float,height: float,offset: float,z_offset: float = 0.0) -> void:
	for side: float in [-1,1]:
		for vertical: float in [-1,1]:
			_box("wood",Vector3(side*(width*0.5+0.014),offset+height*0.59+vertical*0.083,-depth*0.10+z_offset),Vector3(0.031,0.023,0.56))


func _shop(width: float,depth: float,eave: float,cloth: bool) -> void:
	var front := depth*0.5
	# Joinery on the existing counter face, not additional furniture on the road.
	for index: int in range(6):
		_box("wood",Vector3(-width*0.43+index*width*0.105,0.64,front-0.071),Vector3(width*0.101,0.63,0.018))
	if cloth:
		_box("cloth",Vector3(width*0.13,0.87,front-0.044),Vector3(0.19,0.43,0.012))
		_basket(Vector3(-width*0.34,1.055,front-0.20),0.09,0.16)
	else:
		# A short bamboo blind leaves the real serving opening visible below it.
		for index: int in range(10):
			_cylinder("cloth",Vector3(-width*0.15,eave-0.15-index*0.023,front-0.10),0.009,width*0.57,1.0,Basis(Vector3.FORWARD,PI*0.5))
		for x: float in [-width*0.37,width*0.07]:
			_box("wood",Vector3(x,eave-0.25,front-0.087),Vector3(0.010,0.26,0.010))
		# Recessed dark shelves give the already-authored cups a real shop behind.
		_box("dark",Vector3(-width*0.16,1.40,front-0.44),Vector3(width*0.57,0.57,0.025))
		_jar(Vector3(-width*0.34,1.055,front-0.22),0.077,0.18)
		_box("cloth",Vector3(width*0.12,0.93,front-0.044),Vector3(0.17,0.32,0.012))


func _jar(base: Vector3,radius: float,height: float) -> void:
	_cylinder("ceramic",base+Vector3.UP*(height*0.43),radius,height*0.78,0.87)
	_cylinder("ceramic",base+Vector3.UP*(height*0.86),radius*0.67,height*0.16,1.08)
	_cylinder("dark",base+Vector3.UP*(height*0.949),radius*0.52,0.006)


func _basket(base: Vector3,radius: float,height: float) -> void:
	_cylinder("wood",base+Vector3.UP*height*0.5,radius,height,1.06)
	_cylinder("dark",base+Vector3.UP*(height+0.003),radius*0.82,0.006)
	for side: float in [-1,1]:
		_box("wood",base+Vector3(side*radius*0.86,height+0.05,0),Vector3(0.018,0.11,0.018))
	_box("wood",base+Vector3.UP*(height+0.105),Vector3(radius*1.8,0.019,0.019))


func _flush(root: Node3D,body: Node,id: String,row: Dictionary,bounds: Array) -> void:
	for role: String in _tools:
		var mesh := MeshInstance3D.new()
		mesh.name="Detail_"+role
		mesh.mesh=(_tools[role] as SurfaceTool).commit()
		mesh.material_override=_material(role,row)
		_preserve(mesh)
		root.add_child(mesh)
		_check_bounds(mesh,body,id,bounds)
		records.append({"node":mesh,"role":role,"house_id":id,"roof_row":row})
	_tools={}


func _material(role: String,row: Dictionary) -> ShaderMaterial:
	var material: ShaderMaterial
	if is_instance_valid(_material_helper):
		material=_material_helper.call("create_detail_material",role,row) as ShaderMaterial
	if material==null:
		if _fallback_shader==null:
			_fallback_shader=Shader.new()
			_fallback_shader.code=FALLBACK
		material=ShaderMaterial.new()
		material.shader=_fallback_shader
		material.set_shader_parameter("surface_color",Color({"roof":"#718181","wood":"#86745b","stone":"#b6b19c","dark":"#353c33","cloth":"#bbaa7b","ceramic":"#a8b7a6"}.get(role,"#a7a48e")))
	if not row.is_empty():
		if not row.materials.has(material):
			(row.materials as Array).append(material)
		material.set_shader_parameter("fade",float(row.get("fade",0.0)))
		_row_bindings.append({"row":row,"material":material})
	return material


func _tree(root: Node3D,body: Node,id: String,bounds: Array) -> void:
	if not ResourceLoader.exists(FOLIAGE):
		_errors.append("foliage texture missing")
		return
	for node: MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		if str(node.get_meta("art_surface_role",""))=="leaf":
			_hidden_leaves.append({"node":node,"visible":node.visible})
			node.visible=false
	if _leaf_material==null:
		_leaf_material=ShaderMaterial.new()
		var shader := Shader.new()
		shader.code=LEAF_SHADER
		_leaf_material.shader=shader
		_leaf_material.set_shader_parameter("foliage",_keyed_foliage())
	_tools={}
	var positions := [Vector3(0,3.57,0.04),Vector3(-0.12,3.48,0.08),Vector3(0.12,3.62,0.02),Vector3(0.02,3.72,-0.12),Vector3(0.03,3.45,0.13),Vector3(-0.09,3.83,0.04),Vector3(-0.12,3.66,-0.08),Vector3(0.12,3.52,0.10)]
	for index: int in range(positions.size()):
		var width := 1.44 if index<6 else 1.40
		var height := 1.12 if index!=5 else 1.08
		var basis := Basis.from_euler(Vector3(-0.93-0.10*(index%3),(index%3)*PI/3.0,0.08*(index%2)))
		var tint := Color(1.0,0.99,0.90) if index%3==0 else Color(0.96,1.0,0.94)
		var at: Vector3 = positions[index]
		_quad("leaf",at+basis*Vector3(-width*.5,-height*.5,0),at+basis*Vector3(width*.5,-height*.5,0),at+basis*Vector3(width*.5,height*.5,0),at+basis*Vector3(-width*.5,height*.5,0),tint)
		_leaf_cards+=1
	var mesh := MeshInstance3D.new()
	mesh.name="ConceptLeafClusters"
	mesh.mesh=(_tools.leaf as SurfaceTool).commit()
	mesh.material_override=_leaf_material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preserve(mesh)
	root.add_child(mesh)
	_check_bounds(mesh,body,id,bounds,true)
	records.append({"node":mesh,"role":"leaf","house_id":id,"roof_row":{},"card_count":8})
	_tools={}


func _keyed_foliage() -> ImageTexture:
	# Key raw RGB before filtering. Keying after mipmaps mixes magenta into
	# thin leaves and creates pink confetti at normal gameplay distance.
	var image := (load(FOLIAGE) as Texture2D).get_image()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x,y)
			var chroma := minf(color.r-color.g,color.b-color.g)
			color.a=0.0 if chroma>0.02 else 1.0
			image.set_pixel(x,y,color)
	# Fill transparent RGB from neighbouring opaque leaves before deriving mips.
	image.fix_alpha_edges()
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _roof_row(body: Node) -> Dictionary:
	for row: Dictionary in _stage.get("roof_rows"):
		if row.get("body")==body:
			return row
	_errors.append(str(body.name)+": roof row missing")
	return {}


func _chain(node: Node3D,stop: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var parents: Array[Node3D] = []
	var ancestor: Node = node
	while ancestor!=null and ancestor!=stop:
		if ancestor is Node3D:
			parents.append(ancestor)
		ancestor=ancestor.get_parent()
	for index: int in range(parents.size()-1,-1,-1):
		result=result*parents[index].transform
	return result


func _check_bounds(mesh: MeshInstance3D,body: Node,id: String,bounds: Array,leaf: bool = false) -> void:
	var transform := _chain(mesh,_stage.get("world_root"))
	var expected := Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]),float(bounds[3])).grow(0.02)
	var minimum_y := INF
	for surface: int in range(mesh.mesh.get_surface_count()):
		for vertex: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var point := transform*vertex
			var logical: Vector2 = _stage.call("world_to_logical",point)
			minimum_y=minf(minimum_y,point.y)
			if not expected.has_point(logical):
				_bounds_errors.append({"house_id":id,"role":str(mesh.name),"logical":[logical.x,logical.y]})
				return
	if leaf and minimum_y<2.7:
		_bounds_errors.append({"house_id":id,"role":"leaf","minimum_y":minimum_y})


func audit() -> Dictionary:
	var roles: Dictionary = {}
	var houses: Dictionary = {}
	for record: Dictionary in records:
		roles[record.role]=int(roles.get(record.role,0))+1
		houses[record.house_id]=true
	return {"built_house_ids":houses.keys(),"hero_house_count":4,"tree_house_count":2,"mesh_count":records.size(),"role_meshes":roles,"leaf_cards":_leaf_cards,
		"triangles":_triangles,"hidden_original_leaf_batches":_hidden_leaves.size(),"roof_material_bindings":_row_bindings.size(),"bounds_errors":_bounds_errors.duplicate(),"errors":_errors.duplicate(),
		"world_space":true,"new_walk_obstacles":false,"original_batches_changed":false,"leaf_follows_roof_fade":false}


func _exit_tree() -> void:
	for leaf: Dictionary in _hidden_leaves:
		if is_instance_valid(leaf.node):
			leaf.node.visible=leaf.visible
	for binding: Dictionary in _row_bindings:
		if is_instance_valid(binding.row.get("body")):
			(binding.row.materials as Array).erase(binding.material)
	for root: Node in _roots:
		if is_instance_valid(root):
			root.queue_free()
