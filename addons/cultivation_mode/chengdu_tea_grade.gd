extends Node
## A bounded colour pass on existing materials. No new floor or vertex changes.

const LAYOUT := "res://assets/data/chengdu-tea-polish-layout.json"
const DECLARATIONS := """
uniform vec4 tea_grade_zone;
uniform float tea_grade_feather = 2.0;
uniform vec3 tea_grade_gain = vec3(1.0);
uniform float tea_grade_eave = 0.0;
uniform float tea_grade_eave_strength = 0.0;
uniform float tea_grade_ground = 0.0;
float tea_grade_mask(vec3 p) {
    vec2 outside=max(max(tea_grade_zone.xy-p.xz,p.xz-tea_grade_zone.zw),vec2(0.0));
    return 1.0-smoothstep(0.0,max(tea_grade_feather,0.01),length(outside));
}
vec3 tea_grade_colour(vec3 c,vec3 p) {
    float mask=tea_grade_mask(p);
    vec3 target=c*tea_grade_gain;
    float eave=exp(-pow((p.y-tea_grade_eave+0.13)/0.32,2.0));
    target*=1.0-eave*tea_grade_eave_strength;
    float luma=dot(target,vec3(0.2126,0.7152,0.0722));
    target=mix(target,vec3(luma),tea_grade_ground*0.06);
    return mix(c,target,mask);
}
"""

var _stage: Node
var _config: Dictionary = {}
var _targets: Array[String] = ["ward_city_22_19", "ward_city_22_16"]
var _seen: Dictionary = {}
var _bindings: Array[Dictionary] = []
var _errors: Array[String] = []
var _ground_count := 0
var _surface_count := 0


func setup(stage: Node) -> void:
	_stage=stage
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if data is Dictionary:
		_config=data.get("grade",{})
	for body: Node in _stage.get("_art_roots").values():
		attach_house(body)
	attach_ground()


func _grade(material: ShaderMaterial, role: String, point_name: String, anchor: String, eave: float=0.0) -> void:
	if material==null or material.shader==null or _seen.has(material.get_instance_id()):
		return
	var old:=material.shader
	var code:=old.code
	if code.count(anchor)!=1 or code.count("void fragment() {")!=1:
		_errors.append("Unrecognised colour fragment: "+role)
		return
	var shader:=Shader.new()
	shader.code=code.replace("void fragment() {",DECLARATIONS+"\nvoid fragment() {").replace(anchor,anchor+"\n    ALBEDO=tea_grade_colour(ALBEDO,"+point_name+");")
	# This audit includes the complete vertex function, not just its VERTEX writes.
	var vertex_before:=_vertex(code)
	var vertex_after:=_vertex(shader.code)
	if vertex_before!=vertex_after:
		_errors.append("Colour pass changed a vertex function")
		return
	material.shader=shader
	_seen[material.get_instance_id()]=true
	var bounds: Array=_config.get("bounds",[7380,7100,1120,700])
	var a: Vector3=_stage.call("logical_to_world",Vector2(float(bounds[0]),float(bounds[1])))
	var b: Vector3=_stage.call("logical_to_world",Vector2(float(bounds[0])+float(bounds[2]),float(bounds[1])+float(bounds[3])))
	material.set_shader_parameter("tea_grade_zone",Vector4(a.x,a.z,b.x,b.z))
	material.set_shader_parameter("tea_grade_feather",float(_config.get("feather_logical",160.0))/80.0)
	var gains: Array=_config.get(role+"_gain",{"ground":[0.82,0.84,0.87],"plaster":[1.04,1.0,0.91],"roof":[0.92,0.97,1.02],"wood":[0.96,0.90,0.82]}.get(role,[1.0,1.0,1.0]))
	material.set_shader_parameter("tea_grade_gain",Vector3(float(gains[0]),float(gains[1]),float(gains[2])))
	material.set_shader_parameter("tea_grade_eave",eave)
	material.set_shader_parameter("tea_grade_eave_strength",float(_config.get("eave_strength",0.20)) if role in ["plaster","wood"] else 0.0)
	material.set_shader_parameter("tea_grade_ground",1.0 if role=="ground" else 0.0)
	_bindings.append({"material":material,"shader":shader,"old_shader":old,"role":role,"vertex_unchanged":vertex_before==vertex_after})
	if role=="ground":
		_ground_count+=1
	else:
		_surface_count+=1


func _vertex(code: String) -> String:
	var at:=code.find("void vertex()")
	if at<0:
		return ""
	var start:=code.find("{",at)
	var depth:=0
	for index: int in range(start,code.length()):
		if code[index]=="{":
			depth+=1
		elif code[index]=="}":
			depth-=1
			if depth==0:
				return code.substr(at,index-at+1)
	return code.substr(at)


func attach_house(body: Node) -> void:
	var id:=str(body.get_meta("art_street_id",""))
	if id not in _targets:
		return
	var eave:=float(_stage.get("_art_profiles")[id].eave_height)
	for node: Node in body.find_children("*","MeshInstance3D",true,false):
		var role:=str(node.get_meta("tea_polish_role",node.get_meta("art_surface_role","")))
		var material: Variant=node.get("material_override")
		if material is ShaderMaterial and material.shader.code.contains("varying vec3 finish_position;"):
			_grade(material,role,"finish_position","ALBEDO=color;",eave)
		var overlay: Variant=node.get("material_overlay")
		if role=="roof" and overlay is ShaderMaterial:
			_grade(overlay,"roof","original_world_position","ALBEDO=concept_finish(selected.rgb);",eave)


func attach_ground() -> void:
	var helper: Node=_stage.get("_art_street_art")
	if is_instance_valid(helper):
		for row: Dictionary in helper.get("records"):
			var material:=row.material as ShaderMaterial
			if material!=null and bool(material.get_shader_parameter("fragment_reference_priority")):
				_grade(material,"ground","original_world_position","ALBEDO=concept_finish(selected.rgb);")
	var opaque: Node=_stage.get("_crafted_surfaces")
	if is_instance_valid(opaque):
		for row: Dictionary in opaque.get("records"):
			if str(row.kind)=="paving":
				_grade(row.material as ShaderMaterial,"ground","stage_position","ALBEDO=mix(original,paving,region);")


func audit() -> Dictionary:
	return {"layout_source":LAYOUT,"selected_houses":_targets.duplicate(),"graded_surface_materials":_surface_count,"graded_ground_materials":_ground_count,"fragment_only":true,"new_samplers":0,"new_floor":false,"errors":_errors.duplicate(),"grade":_config.duplicate(true)}


func _exit_tree() -> void:
	for row: Dictionary in _bindings:
		if row.material.shader==row.shader:
			row.material.shader=row.old_shader
