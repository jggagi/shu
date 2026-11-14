extends "res://addons/cultivation_mode/chengdu_market_life.gd"
## A single illustrated crown, one tea seller and two bounded facade groups.
## Reuses the existing mesh/material utilities without changing their sources.

const POLISH_LAYOUT := "res://assets/data/chengdu-tea-polish-layout.json"
const CROWN_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, specular_disabled;
uniform sampler2D illustration : source_color, filter_linear_mipmap, repeat_disable;
void fragment() {
    vec4 c=texture(illustration,UV);
    ALBEDO=c.rgb;
    ALPHA=c.a;
    ALPHA_SCISSOR_THRESHOLD=0.5;
    ROUGHNESS=1.0;
}
"""
const CONTACT_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, specular_disabled;
uniform float fade=0.0;
uniform vec2 player_uv=vec2(0.5);
void fragment() {
    float edge=1.0-smoothstep(0.15,1.0,length(UV*2.0-1.0));
    ALBEDO=vec3(0.17,0.14,0.10);
    ALPHA=edge*0.20*(1.0-fade*0.88);
    ROUGHNESS=1.0;
}
"""
const FIXED_RIGHT := Vector3(1,0,0)
const FIXED_UP := Vector3(0,0.6156614753,-0.7880107536)

var _polish: Dictionary = {}
var _hidden_originals: Array[Dictionary] = []
var _sprite_info: Dictionary = {}
var _polish_houses: Dictionary = {}
var _tree_count := 0
var _merchant_count := 0
var _tea_count := 0
var _gallery_count := 0
var _crown_min_y := INF
var _merchant_proof: Dictionary = {}


func setup(stage: Node, material_helper: Node, font: Font) -> void:
	if _stage!=null:
		return
	_stage=stage
	_helper=material_helper
	_font=font
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(POLISH_LAYOUT))
	if not data is Dictionary:
		_errors.append("tea polish layout missing or invalid")
		return
	_polish=data
	_card_shader=Shader.new()
	_card_shader.code=CARD_SHADER
	for body: Node in _stage.get("_art_roots").values():
		attach_house(body)


func attach_house(body: Node) -> void:
	if not is_instance_valid(body) or _seen.has(body.get_instance_id()):
		return
	var id := str(body.get_meta("art_street_id",""))
	if id not in _polish.get("targets",{}).values():
		return
	var front := body.get_node_or_null("StreetFacingStructure") as Node3D
	if front==null:
		_errors.append(id+": authored facade missing")
		return
	_seen[body.get_instance_id()]=true
	_polish_houses[id]=true
	var profile: Dictionary = _stage.get("_art_profiles")[id]
	var row := _row(body)
	var root := Node3D.new()
	root.name="TeaPolish"
	_preserve(root)
	root.set_meta("tea_polish_root",true)
	front.add_child(root)
	_roots.append(root)
	_tools={}
	_colors={}
	if id==str(_polish.targets.tea_shop):
		_tea_group()
		_flush(root,body,id,row,profile.bounds)
		_tea_count+=1
		_seller(root,body,id,row)
	if id==str(_polish.targets.gallery_house):
		_gallery_group(profile)
		_flush(root,body,id,row,profile.bounds)
		_gallery_count+=1
	if id==str(_polish.targets.tree):
		_crown(root,body,id,profile.bounds)


func _preserve(node: Node) -> void:
	node.set_meta("art_street_preserve",true)
	node.set_meta("painted_city_preserve",true)
	node.set_meta("tea_polish_detail",true)


func _base_role(role: String) -> String:
	return role.get_slice("_",0)


func _material(role: String,row: Dictionary) -> ShaderMaterial:
	var material := _helper.call("create_detail_material",_base_role(role),row) as ShaderMaterial
	if material==null:
		_errors.append("tea material factory unavailable: "+role)
		return null
	if _colors.has(role):
		material.set_shader_parameter("surface_color",_colors[role])
		if _base_role(role) in ["dark","cloth","ceramic"]:
			material.set_shader_parameter("textured",false)
	_bindings.append({"row":row,"material":material})
	return material


func _flush(root: Node3D,body: Node,id: String,row: Dictionary,bounds: Array) -> void:
	for role: String in _tools:
		var mesh := MeshInstance3D.new()
		mesh.name="TeaDetail_"+role
		mesh.mesh=(_tools[role] as SurfaceTool).commit()
		mesh.material_override=_material(role,row)
		_preserve(mesh)
		mesh.set_meta("tea_polish_role",_base_role(role))
		root.add_child(mesh)
		_check(mesh,id,bounds)
		records.append({"node":mesh,"role":_base_role(role),"kind":"solid","house_id":id,"roof_row":row})
	_tools={}


func _tea_group() -> void:
	var data: Dictionary = _polish.tea_composition
	var a: Dictionary = data.awning
	var w := float(a.width)*.5
	_colors.cloth_canopy=Color("#9b9c78")
	_quad("cloth_canopy",Vector3(-w,float(a.front_y),float(a.front_z)),Vector3(w,float(a.front_y),float(a.front_z)),Vector3(w,float(a.back_y),float(a.back_z)),Vector3(-w,float(a.back_y),float(a.back_z)))
	for x: float in [-w,w]:
		_box("wood",Vector3(x,(float(a.front_y)+.23)*.5,float(a.front_z)-.025),Vector3(.035,float(a.front_y)-.23,.035))
	_box("wood",Vector3(0,float(a.front_y),float(a.front_z)-.018),Vector3(w*2,.045,.045))
	var counter: Dictionary = data.counter
	var top := float(counter.y)
	var z := float(counter.z)
	_box("wood",Vector3(-.27,top+.01,z),Vector3(1.12,.045,.24))
	_colors.cloth_runner=Color("#bdb493")
	_box("cloth_runner",Vector3(-.28,top+.036,z),Vector3(.54,.014,.21))
	_jar(Vector3(-.45,top+.045,z),.07,.18)
	for x: float in [-.15,.02,.19]:
		_cylinder("ceramic",Vector3(x,top+.075,z),.035,.065,1.1)
		_cylinder("dark",Vector3(x,top+.109,z),.024,.004)
	var south: Dictionary = data.south_display
	var sx := float(south.x)
	var sz := float(south.z)
	var sy := float(south.ledge_y)
	_box("wood",Vector3(sx,sy,sz),Vector3(float(south.depth),.055,float(south.width)))
	for index: int in range(3):
		_cylinder("ceramic",Vector3(sx,sy+.066,sz-.16+index*.15),.023,.07,1.1)
		_cylinder("dark",Vector3(sx,sy+.104,sz-.16+index*.15),.017,.004)
	# Slender vessels and the rolled screen occupy the existing side window,
	# rather than inventing an opening or pushing a table into the street.
	_jar(Vector3(sx,sy+.035,sz+.30),.024,.12)
	_cylinder("cloth_canopy",Vector3(sx,float(south.blind_y),sz),.025,float(south.width)*.85,1.0,Basis(Vector3.RIGHT,PI*.5))
	for z_side: float in [sz-.38,sz+.38]:
		_box("wood",Vector3(sx,float(south.blind_y)-.09,z_side),Vector3(.025,.20,.025))


func _gallery_group(profile: Dictionary) -> void:
	var width := float(profile.bounds[3])/80.0
	var depth := float(profile.bounds[2])/80.0
	var south := -1.0
	_colors.wood_shutter=Color("#93967a")
	_colors.dark_recess=Color("#413f35")
	for level: int in range(2):
		var x := south*(width*.5-(.047 if level==0 else .098))
		var center := Vector3(x,1.85*.59 if level==0 else 1.89+(float(profile.eave_height)-1.89)*.59,-(depth-.22)*.10 if level==0 else -.08-(depth-.42)*.10)
		for side: float in [-1,1]:
			_box("dark_recess",center+Vector3(0,0,side*.315),Vector3(.018,.55,.035))
			_box("wood_shutter",center+Vector3(-.008,0,side*.39),Vector3(.025,.43,.105))
			for slat: int in range(4):
				_box("wood",center+Vector3(-.026,-.15+slat*.10,side*.39),Vector3(.012,.018,.09))
		_box("wood",center-Vector3.UP*.29,Vector3(.038,.06,.69))
	for value: float in _polish.gallery.get("beam_y",[.30,1.88,3.08]):
		var upper := value>2.0
		_box("wood",Vector3(south*(.905 if upper else .95),value,-.08 if upper else 0),Vector3(.026,.045,depth-(.52 if upper else .25)))


func _hide(node: Node) -> void:
	_hidden_originals.append({"node":node,"visible":node.visible})
	node.visible=false


func _sprite(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	if not ResourceLoader.exists(path):
		_errors.append("tea illustration missing: "+path)
		return null
	var image := (load(path) as Texture2D).get_image()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	var crown := path==str(_polish.tree.image)
	var edge_candidates: Array[int] = []
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var c := image.get_pixel(x,y)
			c.a=0.0 if minf(c.r-c.g,c.b-c.g)>.02 else 1.0
			image.set_pixel(x,y,c)
			if crown and c.a>.5 and c.r-c.g>.12 and c.r+c.b-2.0*c.g>.08:
				edge_candidates.append(y*image.get_width()+x)
	var despilled := _crown_edge_despill(image,edge_candidates) if crown else 0
	var used := image.get_used_rect()
	if used.size.x==0 or used.size.y==0:
		_errors.append("tea illustration has no keyed foreground")
		return null
	var crop := used.grow(8).intersection(Rect2i(0,0,image.get_width(),image.get_height()))
	var padded := Image.create(crop.size.x+16,crop.size.y+16,false,Image.FORMAT_RGBA8)
	padded.fill(Color(0,0,0,0))
	padded.blit_rect(image,crop,Vector2i(8,8))
	padded.fix_alpha_edges()
	padded.generate_mipmaps()
	var texture := ImageTexture.create_from_image(padded)
	_textures[path]=texture
	_sprite_info[path]={"foreground_size":[used.size.x,used.size.y],"runtime_size":[padded.get_width(),padded.get_height()],"shoe_uv_from_bottom":float(padded.get_height()-(used.end.y-crop.position.y+8))/float(padded.get_height()),"key_before_mips":true,"padding":8,"crown_edge_despill_pixels":despilled,"despill_radius_source_pixels":3 if crown else 0}
	return texture


func _crown_edge_despill(image: Image,candidates: Array[int]) -> int:
	# One pass from the pre-despill RGBA copy. Only opaque magenta-contaminated
	# edge pixels change RGB; alpha and the illustration's yellow interior stay.
	var original := image.get_data()
	var output := original.duplicate()
	var width := image.get_width()
	var height := image.get_height()
	var changed := 0
	for pixel: int in candidates:
		var x := pixel%width
		var y := int(pixel/width)
		var edge := false
		for dy: int in range(-3,4):
			for dx: int in range(-3,4):
				var nx := x+dx
				var ny := y+dy
				if nx>=0 and nx<width and ny>=0 and ny<height and original[(ny*width+nx)*4+3]==0:
					edge=true
					break
			if edge:
				break
		if not edge:
			continue
		var at := pixel*4
		output[at]=mini(int(original[at]),maxi(0,2*int(original[at+1])-int(original[at+2])))
		output[at+2]=mini(int(original[at+2]),int(original[at+1]))
		changed+=1
	image.set_data(width,height,false,Image.FORMAT_RGBA8,output)
	return changed


func _uv_triangle(tool: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,ua: Vector2,ub: Vector2,uc: Vector2) -> void:
	var normal := (b-a).cross(c-a).normalized()
	for index: int in range(3):
		tool.set_normal(normal)
		tool.set_uv([ua,ub,uc][index])
		tool.set_color(Color.WHITE)
		tool.add_vertex([a,b,c][index])
	_triangles+=1


func _crown(root: Node3D,body: Node,id: String,bounds: Array) -> void:
	var data: Dictionary = _polish.tree
	var texture := _sprite(str(data.image))
	if texture==null:
		return
	var old := body.find_children("ConceptLeafClusters","MeshInstance3D",true,false)
	if old.size()!=1:
		_errors.append("selected original tree has no unique concept crown")
		return
	_hide(old[0])
	var info: Dictionary = _sprite_info[str(data.image)]
	var dims := Vector2(float(info.runtime_size[0]),float(info.runtime_size[1]))
	var fit := minf(float(data.world_size[0])/dims.x,float(data.world_size[1])/dims.y)
	dims*=fit
	var p: Array = data.center
	var center := Vector3(float(p[0]),float(p[1]),float(p[2]))
	var basis := _chain(root,_stage.get("world_root")).basis.inverse()
	var count := int(data.get("segments",10))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z: int in range(count):
		for x: int in range(count):
			var uv := [Vector2(float(x)/count,float(z)/count),Vector2(float(x+1)/count,float(z)/count),Vector2(float(x+1)/count,float(z+1)/count),Vector2(float(x)/count,float(z+1)/count)]
			var points: Array[Vector3] = []
			for cell: Vector2 in uv:
				var nx := cell.x*2.0-1.0
				var nz := cell.y*2.0-1.0
				var arch := float(data.arch_height)*(1.0-nx*nx)*(1.0-nz*nz)-float(data.bend_height)*nz
				points.append(center+basis*Vector3(nx*dims.x*.5,arch,nz*dims.y*.5))
			_uv_triangle(tool,points[0],points[2],points[1],uv[0],uv[2],uv[1])
			_uv_triangle(tool,points[0],points[3],points[2],uv[0],uv[3],uv[2])
	var mesh := MeshInstance3D.new()
	mesh.name="TeaNaturalCrown"
	mesh.mesh=tool.commit()
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code=CROWN_SHADER
	material.shader=shader
	material.set_shader_parameter("illustration",texture)
	mesh.material_override=material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_preserve(mesh)
	mesh.set_meta("tea_polish_role","crown")
	root.add_child(mesh)
	_check(mesh,id,bounds)
	var chain := _chain(mesh,_stage.get("world_root"))
	for vertex: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		_crown_min_y=minf(_crown_min_y,(chain*vertex).y)
	if _crown_min_y<float(data.minimum_clearance):
		_bounds_errors.append({"house_id":id,"error":"crown clearance","minimum_y":_crown_min_y})
	records.append({"node":mesh,"role":"crown","kind":"crown","house_id":id,"roof_row":{}})
	_tree_count+=1


func _seller(root: Node3D,body: Node,id: String,row: Dictionary) -> void:
	var data: Dictionary = _polish.merchant
	var texture := _sprite(str(data.image))
	if texture==null:
		return
	var old := body.find_children("Market_vendor","MeshInstance3D",true,false)
	if old.size()!=1:
		_errors.append("tea merchant has no unique original market card")
		return
	_hide(old[0])
	var info: Dictionary = _sprite_info[str(data.image)]
	var dims := Vector2(float(info.runtime_size[0]),float(info.runtime_size[1]))
	var fg := Vector2(float(info.foreground_size[0]),float(info.foreground_size[1]))
	var scale := minf(float(data.visible_height)/fg.y,float(data.max_width)/fg.x)
	var width := dims.x*scale
	var height := dims.y*scale
	var anchor := Vector2(float(data.logical_anchor[0]),float(data.logical_anchor[1]))
	var foot: Vector3 = _stage.call("logical_to_world",anchor)
	foot.y=float(data.shoe_y)
	var chain := _chain(root,_stage.get("world_root"))
	var inv := chain.affine_inverse()
	var base := foot-FIXED_UP*(float(info.shoe_uv_from_bottom)*height)
	var points := [inv*(base-FIXED_RIGHT*width*.5),inv*(base+FIXED_RIGHT*width*.5),inv*(base+FIXED_RIGHT*width*.5+FIXED_UP*height),inv*(base-FIXED_RIGHT*width*.5+FIXED_UP*height)]
	_tools={}
	_quad("seller",points[0],points[1],points[2],points[3])
	var mesh := MeshInstance3D.new()
	mesh.name="TeaChibiSeller"
	mesh.mesh=(_tools.seller as SurfaceTool).commit()
	mesh.material_override=_card_material(texture,row)
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preserve(mesh)
	mesh.set_meta("tea_polish_role","actor")
	root.add_child(mesh)
	var contract := {"nonblocking":true,"local_xz_rect":data.local_xz_rect,"vertical_range_meters":data.vertical_range}
	_check_frontage(mesh,root,id,contract)
	var walkable := _walkable_anchor(anchor,float(data.anchor_clearance))
	if not walkable:
		_bounds_errors.append({"house_id":id,"error":"tea seller original anchor is not walkable with clearance"})
	_merchant_proof={"logical_anchor":[anchor.x,anchor.y],"shoe_world_y":foot.y,"original_navigation_walkable":walkable,"anchor_clearance":float(data.anchor_clearance),"visible_size":[fg.x*scale,fg.y*scale],"quad_size":[width,height],"preserves_foreground_aspect":true,"fixed_world_right":[FIXED_RIGHT.x,FIXED_RIGHT.y,FIXED_RIGHT.z],"fixed_world_up":[FIXED_UP.x,FIXED_UP.y,FIXED_UP.z]}
	records.append({"node":mesh,"role":"actor","kind":"merchant","house_id":id,"roof_row":row,"frontage_envelope":contract})
	_tools={}
	_contact(root,id,row,foot,inv)
	_merchant_count+=1


func _contact(root: Node3D,id: String,row: Dictionary,foot: Vector3,inverse: Transform3D) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(foot.x,.032,foot.z)
	for index: int in range(24):
		var a := TAU*index/24.0
		var b := TAU*(index+1)/24.0
		_uv_triangle(tool,inverse*center,inverse*(center+Vector3(cos(b)*.23,0,sin(b)*.12)),inverse*(center+Vector3(cos(a)*.23,0,sin(a)*.12)),Vector2(.5,.5),Vector2(.5+.5*cos(b),.5+.5*sin(b)),Vector2(.5+.5*cos(a),.5+.5*sin(a)))
	var mesh := MeshInstance3D.new()
	mesh.name="TeaSellerContact"
	mesh.mesh=tool.commit()
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code=CONTACT_SHADER
	material.shader=shader
	mesh.material_override=material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preserve(mesh)
	mesh.set_meta("tea_polish_role","actor_contact")
	root.add_child(mesh)
	(row.materials as Array).append(material)
	_bindings.append({"row":row,"material":material})
	records.append({"node":mesh,"role":"actor_contact","kind":"contact","house_id":id,"roof_row":row})


func sync() -> void:
	pass


func set_polish_enabled(enabled: bool) -> void:
	for root: Node in _roots:
		if is_instance_valid(root):
			root.visible=enabled
	for hidden: Dictionary in _hidden_originals:
		if is_instance_valid(hidden.node):
			hidden.node.visible=false if enabled else hidden.visible


func audit() -> Dictionary:
	return {"layout_source":POLISH_LAYOUT,"built_house_ids":_polish_houses.keys(),"tree_count":_tree_count,"merchant_count":_merchant_count,"tea_shop_count":_tea_count,"gallery_count":_gallery_count,
		"mesh_count":records.size(),"triangle_count":_triangles,"hidden_originals":_hidden_originals.size(),"roof_material_bindings":_bindings.size(),"crown_minimum_y":_crown_min_y if _tree_count>0 else 0.0,
		"merchant":_merchant_proof.duplicate(true),"sprite_info":_sprite_info.duplicate(true),"errors":_errors.duplicate(),"bounds_errors":_bounds_errors.duplicate(),"original_batches_changed":false,"new_walk_obstacles":false,"contact_world_y":.032,"coherent_crown_images":_tree_count}


func _exit_tree() -> void:
	for hidden: Dictionary in _hidden_originals:
		if is_instance_valid(hidden.node):
			hidden.node.visible=hidden.visible
	super._exit_tree()
