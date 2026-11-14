extends Node
## A local shadow receiver for painted stone; the original sun remains authoritative.
## Compatibility renders its shadowed sun in a separate sRGB additive pass.
## Split the sRGB colour endpoints, then linearise only the additive delta.

const LAYOUT := "res://assets/data/chengdu-afternoon-light-layout.json"
const RECEIVER := """
uniform vec4 afternoon_zone;
uniform float afternoon_feather = 1.6;
uniform vec3 afternoon_sunlit = vec3(1.025,1.012,0.985);
uniform vec3 afternoon_shade = vec3(0.72,0.78,0.87);
uniform float afternoon_shadow_strength = 1.0;
varying vec3 afternoon_direct_linear;
float afternoon_mask(vec3 p) {
    vec2 outside=max(max(afternoon_zone.xy-p.xz,p.xz-afternoon_zone.zw),vec2(0.0));
    return 1.0-smoothstep(0.0,max(afternoon_feather,0.01),length(outside));
}
vec3 afternoon_to_linear(vec3 c) {
    return mix(pow((c+vec3(0.055))/1.055,vec3(2.4)),c/12.92,lessThanEqual(c,vec3(0.04045)));
}
"""
const GROUND_END := """
    float afternoon_amount=afternoon_mask(original_world_position);
    vec3 afternoon_lit=ALBEDO*mix(vec3(1.0),afternoon_sunlit,afternoon_amount);
    vec3 afternoon_dark=afternoon_lit*mix(vec3(1.0),afternoon_shade,afternoon_amount);
    EMISSION=afternoon_dark;
    ALBEDO=vec3(1.0);
    afternoon_direct_linear=afternoon_to_linear(max(afternoon_lit-afternoon_dark,vec3(0.0)));
    ROUGHNESS=1.0;
    SPECULAR=0.0;
"""
const GROUND_LIGHT := """
void light() {
    if (LIGHT_IS_DIRECTIONAL) {
        DIFFUSE_LIGHT+=afternoon_direct_linear*mix(1.0,ATTENUATION,afternoon_shadow_strength);
    }
}
"""
const MODEL_LIGHT := """
void light() {
    DIFFUSE_LIGHT+=max(dot(NORMAL,LIGHT),0.0)*ATTENUATION*LIGHT_COLOR/PI*afternoon_direct_tint;
}
"""

var _stage: Node
var _config: Dictionary = {}
var _seen: Dictionary = {}
var _bindings: Array[Dictionary] = []
var _errors: Array[String] = []
var _counts: Dictionary = {"art_ground":0,"gate_ground":0,"model":0}
var _enabled := true


func setup(stage: Node) -> void:
	_stage=stage
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not data is Dictionary:
		_errors.append("Missing afternoon light layout")
		return
	_config=data
	var painted: Node=_stage.get("_art_street_art")
	for row: Dictionary in painted.get("records"):
		var material:=row.material as ShaderMaterial
		if material!=null and bool(material.get_shader_parameter("fragment_reference_priority")):
			_receiver(material,"art_ground")
	var gate: Node=_stage.get("_painted_gate")
	if is_instance_valid(gate):
		for row: Dictionary in gate.get("_installed"):
			if painted.call("_is_ground_plane",row.node):
				_receiver(row.material as ShaderMaterial,"gate_ground")
	for body: Node in _stage.get("_art_roots").values():
		attach_house(body)


func _uniforms(material: ShaderMaterial) -> Dictionary:
	var result: Dictionary={}
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		var key:=str(uniform.name)
		result[key]=material.get_shader_parameter(key)
	return result


func _restore(material: ShaderMaterial,shader: Shader,parameters: Dictionary) -> void:
	material.shader=shader
	for key: String in parameters:
		material.set_shader_parameter(key,parameters[key])


func _bind(material: ShaderMaterial,code: String,kind: String) -> void:
	var original:=material.shader
	var vertex_same:=_vertex(original.code)==_vertex(code)
	if not vertex_same:
		_errors.append("Afternoon light changed a vertex function: "+kind)
		return
	var parameters:=_uniforms(material)
	var shader:=Shader.new()
	shader.code=code
	_restore(material,shader,parameters)
	var bounds: Array=_config.bounds
	var a: Vector3=_stage.call("logical_to_world",Vector2(float(bounds[0]),float(bounds[1])))
	var b: Vector3=_stage.call("logical_to_world",Vector2(float(bounds[0])+float(bounds[2]),float(bounds[1])+float(bounds[3])))
	if kind=="model":
		material.set_shader_parameter("afternoon_fill",float(_config.model_fill))
		material.set_shader_parameter("afternoon_direct_tint",_v3(_config.model_direct_tint))
	else:
		material.set_shader_parameter("afternoon_zone",Vector4(a.x,a.z,b.x,b.z))
		material.set_shader_parameter("afternoon_feather",float(_config.feather_logical)/80.0)
		material.set_shader_parameter("afternoon_sunlit",_v3(_config.sunlit_gain))
		material.set_shader_parameter("afternoon_shade",_v3(_config.shadow_gain))
	_bindings.append({"material":material,"shader":shader,"original":original,"parameters":parameters,"active_parameters":_uniforms(material),"kind":kind,"vertex_unchanged":vertex_same})
	_seen[material.get_instance_id()]=true
	_counts[kind]=int(_counts[kind])+1
	if not _enabled:
		_restore(material,original,parameters)


func _receiver(material: ShaderMaterial,kind: String) -> void:
	if material==null or material.shader==null or _seen.has(material.get_instance_id()):
		return
	var code:=material.shader.code
	if code.count("void fragment() {")!=1 or code.contains("void light()") or not code.contains("depth_draw_never"):
		_errors.append("Unrecognised painted ground shader: "+kind)
		return
	# Keep the complete original fragment, ALPHA, source matching and vertex lift.
	code=code.replace("unshaded, ","").replace("shadows_disabled, ","")
	code=code.replace("render_mode ","render_mode ambient_light_disabled, specular_disabled, ")
	code=code.replace("void fragment() {",RECEIVER+"\nvoid fragment() {")
	var end:=code.rfind("}")
	code=code.substr(0,end)+GROUND_END+code.substr(end)+GROUND_LIGHT
	_bind(material,code,kind)


func attach_house(body: Node) -> void:
	if _config.is_empty():
		return
	var kit:=body.get_node_or_null("StreetFacingStructure/BlenderAuthoredKit")
	if kit==null:
		return
	for node: Node in kit.find_children("*","MeshInstance3D",true,false):
		var material: Variant=node.get("material_override")
		if not material is ShaderMaterial or material.shader==null or _seen.has(material.get_instance_id()):
			continue
		var code: String=material.shader.code
		# Only imported atlas materials, excluding the retained old courtyard beams.
		if not code.contains("uniform sampler2D painted_atlas"):
			continue
		code=code.replace("void fragment() {","uniform vec3 afternoon_direct_tint = vec3(1.0);\nuniform float afternoon_fill = 0.82;\nvoid fragment() {")
		code=code.replace("    SPECULAR=0.0;","    SPECULAR=0.0;\n    AO=afternoon_fill;\n    AO_LIGHT_AFFECT=0.0;")
		_bind(material,code+MODEL_LIGHT,"model")


func set_enabled(enabled: bool) -> void:
	if enabled==_enabled:
		return
	_enabled=enabled
	for row: Dictionary in _bindings:
		var material:=row.material as ShaderMaterial
		# Save current fade/player UV too; toggling must not restore stale state.
		var values:=_uniforms(material)
		if not enabled:
			row.active_parameters=values
		else:
			var active: Dictionary=row.active_parameters.duplicate()
			active.merge(values,true)
			values=active
		_restore(material,row.shader if enabled else row.original,values)


func set_receiver_shadows_enabled(enabled: bool) -> void:
	# QA only: keep the sun in its original GLES shadowed additive pass.
	# Disabling the light's shadow flag would change pass/gamma behaviour too.
	for row: Dictionary in _bindings:
		if row.kind!="model" and row.material.shader==row.shader:
			row.material.set_shader_parameter("afternoon_shadow_strength",1.0 if enabled else 0.0)


func _v3(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))


func _vertex(code: String) -> String:
	var at:=code.find("void vertex()")
	if at<0:
		return ""
	var start:=code.find("{",at)
	var depth:=0
	for i: int in range(start,code.length()):
		if code[i]=="{":
			depth+=1
		elif code[i]=="}":
			depth-=1
			if depth==0:
				return code.substr(at,i-at+1)
	return code.substr(at)


func audit() -> Dictionary:
	return {"layout_source":LAYOUT,"counts":_counts.duplicate(),"errors":_errors.duplicate(),"enabled":_enabled,"new_floor":false,"new_lights":0,"new_material_samplers":0,"all_vertices_unchanged":_bindings.all(func(row: Dictionary) -> bool: return row.vertex_unchanged),"config":_config.duplicate(true),"contract":"Compatibility, linear tonemap, one shadowed directional sun; sRGB additive delta receiver"}


func _exit_tree() -> void:
	for row: Dictionary in _bindings:
		if row.material.shader==row.shader:
			_restore(row.material,row.original,_uniforms(row.material))
