extends "res://addons/cultivation_mode/chengdu_finished_street.gd"
## The same UV artwork now meets the actual horizontal lot, not a tilted card.
const GROUND_CONFIG="res://assets/data/chengdu-grounded-street-layout.json"
const APRON="""shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled, depth_draw_never;
uniform sampler2D paving : source_color, filter_linear_mipmap, repeat_enable;
uniform float period=1.65;
varying vec3 world_position;
varying vec3 direct_linear;
vec3 linear_delta(vec3 c){return mix(pow((c+vec3(.055))/1.055,vec3(2.4)),c/12.92,lessThanEqual(c,vec3(.04045)));}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec3 lit=texture(paving,world_position.xz/period).rgb*vec3(1.06,1.03,.97);
 vec3 shade=lit*vec3(.72,.78,.87);
 EMISSION=shade;
 ALBEDO=vec3(1.0);
 direct_linear=linear_delta(max(lit-shade,vec3(0.0)));
 float edge=1.0-smoothstep(.12,1.0,1.0-UV.y);
 float ends=smoothstep(0.0,.08,UV.x)*(1.0-smoothstep(.92,1.0,UV.x));
 ALPHA=edge*ends*.80;
 ROUGHNESS=1.0;
 SPECULAR=0.0;
}
void light(){if(LIGHT_IS_DIRECTIONAL){DIFFUSE_LIGHT+=direct_linear*ATTENUATION;}}
"""
var _ground_config: Dictionary
var _apron_material: ShaderMaterial
var _aprons:=0
var _grounded_vertices:=0
var _corner_max_error:=0.0
var _actual_contact_vertices:=0


func setup(stage: Node) -> void:
	_ground_config=JSON.parse_string(FileAccess.get_file_as_string(GROUND_CONFIG))
	_apron_material=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code=APRON
	_apron_material.shader=shader
	_apron_material.set_shader_parameter("paving",load(str(_ground_config.paving_texture)))
	_apron_material.set_shader_parameter("period",float(_ground_config.paving_period))
	super.setup(stage)


func _profile(context: Dictionary) -> Dictionary:
	var layers: Dictionary=_stage.get("_illustrated_street").get("_layers")
	for key: String in layers:
		var size: Array=layers[key].size
		if Vector2(size[0],size[1]).is_equal_approx(context.size):
			return _config.profiles[key]
	_errors.append("Grounding profile size missing")
	return {}


func _foundation_point(pixel: Vector2, context: Dictionary, contact: PackedVector2Array) -> Vector3:
	var local_foot: Vector3=context.inverse*context.foot
	var hx:=local_foot.x
	var hz:=local_foot.z
	var point: Vector3
	# Measured image V follows SW -> SE -> NE of the original rectangle.
	# These are shared physical corners, independent of the moving camera.
	if pixel.x<=contact[1].x:
		var t: float=(pixel.x-contact[0].x)/(contact[1].x-contact[0].x)
		point=Vector3(lerpf(-hx,hx,t),0,hz)
	else:
		var t: float=(pixel.x-contact[1].x)/(contact[2].x-contact[1].x)
		point=Vector3(hx,0,lerpf(hz,-hz,t))
	point=context.inverse.affine_inverse()*point
	point.y=float(_ground_config.ground_y)
	return point


func _grounded_point(pixel: Vector2, context: Dictionary, roof: PackedVector2Array, base: PackedVector2Array, contact: PackedVector2Array) -> Vector3:
	var roof_y:=_line_y(roof,pixel.x)
	var base_y:=_line_y(base,pixel.x)
	var floor_y:=_line_y(contact,pixel.x)
	var amount:=clampf((pixel.y-roof_y)/maxf(floor_y-roof_y,1.0),0,1)
	var original_floor:=_world(Vector2(pixel.x,floor_y),context)
	var target:=_foundation_point(pixel,context,contact)
	var world:=_world(pixel,context)+(target-original_floor)*amount
	var depth:=.12*(pixel.y/roof_y) if pixel.y<=roof_y else .12*(1.0-clampf((pixel.y-roof_y)/(base_y-roof_y),0,1))
	return world+_basis.z*depth


func _paint_mesh(polygon: PackedVector2Array, context: Dictionary, roof: PackedVector2Array, base: PackedVector2Array) -> MeshInstance3D:
	if polygon[0].is_equal_approx(Vector2.ZERO):
		return super._paint_mesh(polygon,context,roof,base)
	var profile:=_profile(context)
	var contact:=_points(profile.contact)
	var bounds:=Rect2(polygon[0],Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds=bounds.expand(point)
	var step:=int(_ground_config.mesh_step_pixels)
	var pieces: Array[PackedVector2Array]=[polygon]
	if polygon[0].is_equal_approx(base[0]):
		# Make the contact V a real mesh edge. A grid alone would interpolate
		# over its bend and could leave the painted edge a few cm above floor.
		var full_contact:=contact.duplicate()
		full_contact.insert(0,Vector2(0,_line_y(contact,0)))
		full_contact.append(Vector2(context.size.x,_line_y(contact,context.size.x)))
		var upper:=PackedVector2Array([Vector2.ZERO,Vector2(context.size.x,0)])
		var lower:=PackedVector2Array([Vector2(0,context.size.y),context.size])
		pieces.clear()
		for mask: PackedVector2Array in [_band(upper,full_contact),_band(full_contact,lower)]:
			pieces.append_array(Geometry2D.intersect_polygons(polygon,mask))
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: int in range(floori(bounds.position.x/step)*step,ceili(bounds.end.x),step):
		for y: int in range(floori(bounds.position.y/step)*step,ceili(bounds.end.y),step):
			var cell:=PackedVector2Array([Vector2(x,y),Vector2(x+step,y),Vector2(x+step,y+step),Vector2(x,y+step)])
			for piece: PackedVector2Array in pieces:
				for clipped: PackedVector2Array in Geometry2D.intersect_polygons(piece,cell):
					var indices:=Geometry2D.triangulate_polygon(clipped)
					for index: int in indices:
						var pixel:=clipped[index]
						var world:=_grounded_point(pixel,context,roof,base,contact)
						surface.set_normal(_basis.z)
						surface.set_uv(pixel/context.size)
						surface.add_vertex(context.inverse*world)
						_grounded_vertices+=1
						for corner: Vector2 in contact:
							if pixel.distance_to(corner)<.001:
								_actual_contact_vertices+=1
								_corner_max_error=maxf(_corner_max_error,absf(world.y-float(_ground_config.ground_y)))
	for pixel: Vector2 in contact:
		var world:=_grounded_point(pixel,context,roof,base,contact)
		_corner_max_error=maxf(_corner_max_error,absf(world.y-float(_ground_config.ground_y)))
	var mesh:=MeshInstance3D.new()
	mesh.mesh=surface.commit()
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


func _on_ground(pixel: Vector2, context: Dictionary) -> Vector3:
	return _foundation_point(pixel,context,_points(_profile(context).contact))


func _gutter(_parent: Node3D, _a: Vector3, _b: Vector3, _front: Vector3) -> void:
	# The previous extra parallel seam exaggerated the cutout border.
	pass


func _contact_strip(parent: Node3D, a: Vector3, b: Vector3) -> void:
	# Face outward from SW->SE and SE->NE; both original frontages stay free.
	var direction: Vector3=(b-a).normalized()
	var outward:=Vector3(-direction.z,0,direction.x)
	var width:=float(_ground_config.apron_width)
	var shift:=Vector3.UP*.003
	var apron:=_quad([a+shift,b+shift,b+shift+outward*width,a+shift+outward*width])
	apron.name="FeatheredFoundationPaving"
	apron.material_override=_apron_material
	parent.add_child(apron)
	_aprons+=1
	# A thin soft contact belongs directly under the physical stone footing.
	var side:=outward*.045
	var seam:=_quad([a-side+shift*2,b-side+shift*2,b+side+shift*2,a+side+shift*2])
	seam.name="FootingContact"
	var shader:=Shader.new()
	shader.code=CONTACT.replace("*0.22","*0.14")
	var material:=ShaderMaterial.new()
	material.shader=shader
	seam.material_override=material
	parent.add_child(seam)
	_contacts+=1


func audit() -> Dictionary:
	var result:=super.audit()
	result["grounding"]={"layout_source":GROUND_CONFIG,"ground_y":_ground_config.get("ground_y",0),"contact_corner_max_height_error":_corner_max_error,"actual_contact_mesh_vertices":_actual_contact_vertices,"warped_vertices":_grounded_vertices,"apron_segments":_aprons,"original_floor_art_unchanged":true,"world_camera_unchanged":true,"old_parallel_gutters_removed":true}
	return result
