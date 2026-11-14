extends Node
## Local mesh/UV composition over immutable painted artwork. No gameplay owner.

const CONFIG="res://assets/data/chengdu-layered-street-layout.json"
const PAINT="""shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;
uniform sampler2D illustration : source_color, filter_linear_mipmap, repeat_disable;
uniform float fade=0.0;
uniform float reveal=0.98;
uniform vec2 player_uv=vec2(0.5);
void fragment(){
 vec4 art=texture(illustration,UV);
 if(art.a<0.12){discard;}
 float local=1.0-smoothstep(42.0,92.0,length((SCREEN_UV-player_uv)*vec2(1280.0,720.0)));
 ALBEDO=art.rgb;
 ALPHA=art.a*(1.0-local*fade*reveal);
 ROUGHNESS=1.0;
}
"""
const CONTACT="""shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled, depth_draw_never;
void fragment(){
 float soft=pow(max(0.0,1.0-abs(UV.y*2.0-1.0)),1.7);
 float ends=smoothstep(0.0,0.12,UV.x)*(1.0-smoothstep(0.88,1.0,UV.x));
 ALBEDO=vec3(0.13,0.115,0.085);
 ALPHA=soft*ends*0.22;
}
"""
const STEAM="""shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled, depth_draw_never;
uniform float elapsed=0.0;
void fragment(){
 float rise=1.0-UV.y;
 float wind=sin(elapsed*0.9+rise*5.0)*0.055;
 float center=0.5+sin(rise*9.0-elapsed*1.2)*0.12+wind*rise;
 float thin=exp(-pow((UV.x-center)/(0.055+rise*0.10),2.0));
 float wisp=0.58+0.42*sin(rise*16.0-elapsed*1.4);
 ALBEDO=vec3(0.90,0.86,0.74);
 ALPHA=thin*wisp*smoothstep(0.0,0.1,rise)*(1.0-smoothstep(0.45,1.0,rise))*0.32;
}
"""
const GUTTER="""shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled, depth_draw_never;
void fragment(){
 float edge=abs(UV.y*2.0-1.0);
 float groove=1.0-smoothstep(0.10,0.27,edge);
 float joint=1.0-smoothstep(0.0,0.035,min(fract(UV.x*9.0),1.0-fract(UV.x*9.0)));
 ALBEDO=mix(vec3(0.40,0.38,0.31),vec3(0.19,0.20,0.17),groove*0.70+joint*0.15);
 ALPHA=(1.0-smoothstep(0.76,1.0,edge))*smoothstep(0.0,0.06,UV.x)*(1.0-smoothstep(0.94,1.0,UV.x))*0.32;
}
"""
const CLOTH="""shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;
uniform float elapsed=0.0;
void vertex(){
 float gust=sin(elapsed*0.9)*0.65+sin(elapsed*1.7)*0.35;
 VERTEX.x+=pow(UV.y,2.0)*gust*0.022;
 VERTEX.z+=pow(UV.y,2.0)*sin(elapsed*0.9+UV.y*2.0)*0.009;
}
void fragment(){
 float hem=step(0.07,UV.x)*step(UV.x,0.93)*step(0.07,UV.y)*step(UV.y,0.93);
 float weave=sin(UV.x*160.0)*sin(UV.y*210.0)*0.009;
 ALBEDO=mix(vec3(0.31,0.20,0.11),vec3(0.69,0.46,0.24),hem)+weave;
 ROUGHNESS=1.0;
}
"""

var _stage: Node
var _config: Dictionary
var _basis:=Basis.from_euler(Vector3(deg_to_rad(-52.0),deg_to_rad(45.0),0))
var _paint_shader: Shader
var _records: Array[Dictionary]=[]
var _motion: Array[ShaderMaterial]=[]
var _motion_labels: Array[Dictionary]=[]
var _roots: Array[Node3D]=[]
var _seen: Dictionary={}
var _enabled:=true
var _elapsed:=0.0
var _errors: Array[String]=[]
var _contacts:=0
var _gutters:=0


func setup(stage: Node) -> void:
	_stage=stage
	_config=JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	_paint_shader=Shader.new()
	_paint_shader.code=PAINT
	attach_houses()


func attach_houses() -> void:
	var illustrated: Node=_stage.get("_illustrated_street")
	for binding: Dictionary in illustrated.get("_bindings"):
		var id:=str(binding.house_id)
		if not _config.houses.has(id) or _seen.has(id):
			continue
		var body: Node3D=_stage.get("_art_roots")[id]
		var original:=body.get_node("IllustratedStreetLayer").get_child(0) as MeshInstance3D
		var art: Dictionary=illustrated.get("_layers")[binding.layer]
		var size:=Vector2(art.size[0],art.size[1])
		var anchor:=Vector2(art.anchor_px[0],art.anchor_px[1])
		var context: Dictionary={"foot":binding.anchor_world,"size":size,"anchor":anchor,"ppm":size.x/float(binding.width_meters),"inverse":body.transform.affine_inverse()}
		var root:=Node3D.new()
		root.name="LayeredStreetComposition"
		body.add_child(root)
		_roots.append(root)
		var profile: Dictionary=_config.profiles[binding.layer]
		var roof:=_points(profile.roof)
		var base:=_points(profile.base)
		var upper:=PackedVector2Array([Vector2.ZERO,Vector2(size.x,0)])
		var lower:=PackedVector2Array([Vector2(0,size.y),size])
		var sections: Array[PackedVector2Array]=[_band(upper,roof),_band(roof,base),_band(base,lower)]
		var mats: Array[ShaderMaterial]=[]
		for i: int in range(sections.size()):
			var material:=ShaderMaterial.new()
			material.shader=_paint_shader
			material.set_shader_parameter("illustration",original.material_override.get_shader_parameter("illustration"))
			material.set_shader_parameter("reveal",[0.84,0.98,0.65][i])
			material.set_shader_parameter("fade",float(binding.row.fade))
			material.set_shader_parameter("player_uv",Vector2(.5,.5))
			var mesh:=_paint_mesh(sections[i],context,roof,base)
			mesh.name=["RoofOrCanopy","Facade","ThresholdAndProps"][i]
			mesh.material_override=material
			root.add_child(mesh)
			(binding.row.materials as Array).append(material)
			mats.append(material)
		var ground:=Node3D.new()
		ground.name="FoundationContact"
		_stage.get("world_root").add_child(ground)
		_roots.append(ground)
		var contact:=_points(profile.contact)
		for i: int in range(contact.size()-1):
			var a:=_on_ground(contact[i],context)
			var b:=_on_ground(contact[i+1],context)
			_contact_strip(ground,a,b)
			if binding.layer in ["tea_shop","corner_shop"]:
				_gutter(ground,a,b,Vector3(context.foot.x,0.041,context.foot.z))
		if _config.motion.has(binding.layer):
			_add_motion(root,context,_config.motion[binding.layer])
		_records.append({"id":id,"original":original,"original_visible":original.visible,"root":root,"ground":ground,"materials":mats,"row":binding.row,"body":body})
		_seen[id]=true
		original.visible=not _enabled
		root.visible=_enabled
		ground.visible=_enabled and body.visible


func _points(values: Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for p: Array in values:
		result.append(Vector2(p[0],p[1]))
	return result


func _band(top: PackedVector2Array, bottom: PackedVector2Array) -> PackedVector2Array:
	var result:=top.duplicate()
	var back:=bottom.duplicate()
	back.reverse()
	result.append_array(back)
	return result


func _world(pixel: Vector2, context: Dictionary) -> Vector3:
	return context.foot+_basis.x*((pixel.x-context.anchor.x)/context.ppm)+_basis.y*((context.anchor.y-pixel.y)/context.ppm)


func _line_y(line: PackedVector2Array, x: float) -> float:
	for i: int in range(line.size()-1):
		if x<=line[i+1].x:
			return lerpf(line[i].y,line[i+1].y,inverse_lerp(line[i].x,line[i+1].x,x))
	return line[-1].y


func _paint_mesh(polygon: PackedVector2Array, context: Dictionary, roof: PackedVector2Array, base: PackedVector2Array) -> MeshInstance3D:
	# Shared seam vertices have identical depth in adjacent sections. The shallow
	# relief gives translation parallax without exposing blank cutout seams.
	var indices:=Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty():
		_errors.append("Untriangulable painted section")
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in indices:
		var pixel:=polygon[index]
		var y:=_line_y(roof,pixel.x)
		var b:=_line_y(base,pixel.x)
		var depth:=0.12*(pixel.y/y) if pixel.y<=y else 0.12*(1.0-clampf((pixel.y-y)/(b-y),0,1))
		var world:=_world(pixel,context)+_basis.z*depth
		surface.set_uv(pixel/context.size)
		surface.set_normal(_basis.z)
		surface.add_vertex(context.inverse*world)
	var mesh:=MeshInstance3D.new()
	mesh.mesh=surface.commit()
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


func _on_ground(pixel: Vector2, context: Dictionary) -> Vector3:
	var point:=_world(pixel,context)
	# Follow the painted foundation's projection down onto the real ground.
	return point+_basis.z*((0.041-point.y)/_basis.z.y)


func _contact_strip(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var cross: Vector3=(b-a).normalized().cross(Vector3.UP)*0.11
	var mesh:=_quad([a-cross,b-cross,b+cross,a+cross])
	mesh.name="SoftFoundationContact"
	var material:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code=CONTACT
	material.shader=shader
	mesh.material_override=material
	parent.add_child(mesh)
	_contacts+=1


func _gutter(parent: Node3D, a: Vector3, b: Vector3, front: Vector3) -> void:
	var perpendicular: Vector3=(b-a).normalized().cross(Vector3.UP)
	# Choose the street side of the measured painted foundation, then keep
	# these shallow markings visual only; the old navigable route is retained.
	if perpendicular.dot((a+b)*.5-front)<0:
		perpendicular=-perpendicular
	var shift:=perpendicular*.16+Vector3.UP*.003
	var width:=perpendicular*.085
	var mesh:=_quad([a+shift-width,b+shift-width,b+shift+width,a+shift+width])
	mesh.name="WornDrainageSeam"
	var material:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code=GUTTER
	material.shader=shader
	mesh.material_override=material
	parent.add_child(mesh)
	_gutters+=1


func _quad(corners: Array[Vector3]) -> MeshInstance3D:
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in [0,1,2,0,2,3]:
		surface.set_uv([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)][index])
		surface.set_normal(_basis.z)
		surface.add_vertex(corners[index])
	var mesh:=MeshInstance3D.new()
	mesh.mesh=surface.commit()
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


func _add_motion(root: Node3D, context: Dictionary, config: Dictionary) -> void:
	if config.has("steam_pixel"):
		var source:=_world(Vector2(config.steam_pixel[0],config.steam_pixel[1]),context)+_basis.z*.06
		var steam:=_quad([context.inverse*(source-_basis.x*.075),context.inverse*(source+_basis.x*.075),context.inverse*(source+_basis.x*.075+_basis.y*.48),context.inverse*(source-_basis.x*.075+_basis.y*.48)])
		steam.name="TeaSteam"
		steam.material_override=_motion_material(STEAM)
		root.add_child(steam)
	var origin:=_world(Vector2(config.banner_pixel[0],config.banner_pixel[1]),context)+_basis.z*.18
	var cloth:=MeshInstance3D.new()
	cloth.name="ClothPennant"
	var plane:=PlaneMesh.new()
	plane.orientation=PlaneMesh.FACE_Z
	plane.size=Vector2(.19,.38)
	plane.subdivide_width=3
	plane.subdivide_depth=10
	cloth.mesh=plane
	cloth.transform=context.inverse*Transform3D(_basis,origin-_basis.y*.19)
	cloth.material_override=_motion_material(CLOTH)
	cloth.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cloth)
	var sign:=Label3D.new()
	sign.text=str(config.banner_text)
	sign.font=load("res://assets/fonts/ShuChengduScaleSerif.ttf")
	sign.font_size=40
	sign.pixel_size=.0032
	sign.outline_size=0
	sign.modulate=Color("#382d20")
	sign.transform=context.inverse*Transform3D(_basis,origin-_basis.y*.19+_basis.z*.008)
	root.add_child(sign)
	_motion_labels.append({"node":sign,"origin":sign.position,"right":context.inverse.basis*_basis.x})


func _motion_material(code: String) -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code=code
	material.shader=shader
	_motion.append(material)
	return material


func sync(elapsed: float) -> void:
	_elapsed=elapsed
	for material: ShaderMaterial in _motion:
		material.set_shader_parameter("elapsed",elapsed)
	var gust:=sin(elapsed*.9)*.65+sin(elapsed*1.7)*.35
	for row: Dictionary in _motion_labels:
		row.node.position=row.origin+row.right*(.25*gust*.022)
	for row: Dictionary in _records:
		row.ground.visible=_enabled and row.body.visible


func set_enabled(enabled: bool) -> void:
	_enabled=enabled
	for row: Dictionary in _records:
		row.original.visible=bool(row.original_visible) and not enabled
		row.root.visible=enabled
		row.ground.visible=enabled and row.body.visible


func audit() -> Dictionary:
	return {"layout_source":CONFIG,"split_house_count":_seen.size(),"mesh_sections":_seen.size()*3,"max_relief_meters":.12,"contact_strips":_contacts,"drainage_seams":_gutters,"motion_materials":_motion.size(),"motion_clock":"existing stage ambient_elapsed; freezes when host is inactive","elapsed":_elapsed,"new_obstacles":0,"new_state":false,"enabled":_enabled,"errors":_errors.duplicate()}


func _exit_tree() -> void:
	for row: Dictionary in _records:
		if is_instance_valid(row.original):
			row.original.visible=row.original_visible
		for material: ShaderMaterial in row.materials:
			(row.row.materials as Array).erase(material)
	for root: Node3D in _roots:
		if is_instance_valid(root):
			root.queue_free()
