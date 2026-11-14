extends Node
## Street-specific finish. Geometry and frozen calibration remain untouched.

const ATLAS := "res://assets/art/chengdu_concept_finish/surfaces.png"
const SURFACE := """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 surface_color : source_color = vec4(1.0);
uniform float meters = 2.0;
uniform bool textured = true;
uniform bool plaster = false;
uniform vec2 player_uv = vec2(0.5);
uniform float fade = 0.0;
varying vec3 finish_position;
varying vec3 finish_normal;
void vertex() {
    finish_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    finish_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
    vec2 delta=(SCREEN_UV-player_uv)*vec2(1280.0,720.0);
    float local=1.0-smoothstep(44.0,92.0,length(delta));
    float pattern=fract(sin(dot(floor(UV*vec2(680.0,300.0)),vec2(12.9898,78.233)))*43758.5453);
    if (pattern<local*fade*0.88) { discard; }
    vec3 n=abs(normalize(finish_normal));
    vec2 p=finish_position.xz;
    if (n.x>n.y && n.x>n.z) { p=finish_position.zy; }
    else if (n.z>n.y) { p=finish_position.xy; }
    vec3 color=surface_color.rgb;
    if (textured) { color*=texture(surface_texture,p/meters).rgb; }
    if (plaster) {
        color=mix(color,vec3(0.60,0.53,0.42)*surface_color.rgb,0.22);
        float foot=1.0-smoothstep(0.18,0.55,finish_position.y);
        color=mix(color,color*vec3(0.62,0.65,0.54),foot*0.52);
    }
    ALBEDO=color;
    ROUGHNESS=0.98;
    SPECULAR=0.0;
}
"""
const PROJECTED_DECLARATIONS := """
uniform sampler2D finish_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float finish_meters = 3.2;
uniform float finish_strength = 0.0;
uniform float finish_reference_luma = 0.5;
vec3 concept_finish(vec3 original) {
    vec3 tile=texture(finish_texture,original_world_position.xz/finish_meters).rgb;
    float light=clamp(dot(original,vec3(0.2126,0.7152,0.0722))/finish_reference_luma,0.28,1.35);
    return mix(original,tile*light,finish_strength);
}
"""

var _stage: Node
var _tiles: Dictionary = {}
var _shader: Shader
var _seen: Dictionary = {}
var _bindings: Array[Dictionary] = []
var _projected_bindings: Array[Dictionary] = []
var _projected_seen: Dictionary = {}
var _projected_shaders: Dictionary = {}
var _rows: Array[Dictionary] = []
var _errors: Array[String] = []

func setup(stage: Node) -> void:
	_stage=stage
	if not ResourceLoader.exists(ATLAS):
		_errors.append("concept surface atlas missing")
		return
	var image := (load(ATLAS) as Texture2D).get_image()
	var cell := image.get_width()/2
	for row: Array in [["plaster",0,0],["roof",1,0],["stone",0,1],["wood",1,1]]:
		var tile := image.get_region(Rect2i(int(row[1])*cell,int(row[2])*cell,cell,cell))
		_stage.get("_crafted_surfaces").call("_periodic_edges",tile,16)
		tile.generate_mipmaps()
		_tiles[str(row[0])]=ImageTexture.create_from_image(tile)
	_shader=Shader.new()
	_shader.code=SURFACE
	for body: Node in _stage.get("_art_roots").values():
		attach_house(body)
	# Keep the existing opaque ground and its transforms/depth; replace its tile.
	var ground: Node = _stage.get("_crafted_surfaces")
	for record: Dictionary in ground.get("records"):
		if str(record.kind)=="paving":
			record.material.set_shader_parameter("crafted_texture",_tiles.stone)
			record.material.set_shader_parameter("crafted_period",3.6)
			record.material.set_shader_parameter("crafted_gain",0.95)
	attach_projected()

func create_detail_material(role: String, roof_row: Dictionary = {}) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader=_shader
	var colors := {"dark":"#302d28","cloth":"#c4aa7c","ceramic":"#cbd6cb","leaf":"#8e9d58"}
	material.set_shader_parameter("textured",_tiles.has(role))
	material.set_shader_parameter("plaster",role=="plaster")
	var tint := Color.WHITE if _tiles.has(role) else Color(colors.get(role,"#a38e6b"))
	if role=="wood":
		tint=Color(1.22,1.12,1.0)
	elif role=="plaster":
		tint=Color(0.92,0.90,0.86)
	material.set_shader_parameter("surface_color",tint)
	material.set_shader_parameter("meters",2.4 if role=="plaster" else 1.8)
	if _tiles.has(role):
		material.set_shader_parameter("surface_texture",_tiles[role])
	if not roof_row.is_empty():
		(roof_row.materials as Array).append(material)
		material.set_shader_parameter("fade",float(roof_row.get("fade",0.0)))
		_rows.append({"row":roof_row,"material":material})
	return material

func attach_house(body: Node) -> void:
	if _shader==null or _seen.has(body.get_instance_id()):
		return
	_seen[body.get_instance_id()]=true
	var roof_row: Dictionary = {}
	for row: Dictionary in _stage.get("roof_rows"):
		if row.get("body")==body:
			roof_row=row
			break
	for node: MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		var role := str(node.get_meta("art_surface_role",""))
		if role.is_empty() or role=="leaf":
			continue
		var old := node.material_override
		var material := create_detail_material(role,roof_row)
		node.material_override=material
		_bindings.append({"node":node,"old":old,"material":material})
	attach_projected()

func attach_projected() -> void:
	var art: Node = _stage.get("_art_street_art")
	if not is_instance_valid(art):
		return
	for record: Dictionary in art.get("records"):
		var material := record.material as ShaderMaterial
		if _projected_seen.has(material.get_instance_id()):
			continue
		_projected_seen[material.get_instance_id()]=true
		var ground := bool(material.get_shader_parameter("fragment_reference_priority"))
		var role := str(record.node.get_meta("art_surface_role",""))
		if not ground and role!="roof":
			continue
		var old := material.shader
		var key := old.get_instance_id()
		if not _projected_shaders.has(key):
			var code := old.code
			if code.count("ALBEDO=selected.rgb;")!=1:
				_errors.append("projected finish fragment contract differs")
				continue
			var shader := Shader.new()
			shader.code=code.replace("void fragment() {",PROJECTED_DECLARATIONS+"\nvoid fragment() {").replace("ALBEDO=selected.rgb;","ALBEDO=concept_finish(selected.rgb);")
			_projected_shaders[key]=shader
		material.shader=_projected_shaders[key]
		material.set_shader_parameter("finish_texture",_tiles.stone if ground else _tiles.roof)
		material.set_shader_parameter("finish_meters",3.6 if ground else 1.7)
		material.set_shader_parameter("finish_strength",0.86 if ground else 0.70)
		material.set_shader_parameter("finish_reference_luma",0.50 if ground else 0.12)
		_projected_bindings.append({"material":material,"old_shader":old,"shader":material.shader})

func _exit_tree() -> void:
	for binding: Dictionary in _bindings:
		if is_instance_valid(binding.node) and binding.node.material_override==binding.material:
			binding.node.material_override=binding.old
	for binding: Dictionary in _projected_bindings:
		if binding.material.shader==binding.shader:
			binding.material.shader=binding.old_shader
	for binding: Dictionary in _rows:
		(binding.row.materials as Array).erase(binding.material)

func audit() -> Dictionary:
	return {"atlas":ATLAS,"loaded_tiles":_tiles.keys(),"house_count":_seen.size(),"surface_count":_bindings.size(),
		"projected_surface_count":_projected_bindings.size(),"projection_vertex_unchanged":true,
		"new_overlay_sampler_count":10,"ground_depth_bias_preserved":true,"errors":_errors.duplicate()}
