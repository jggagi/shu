extends "res://addons/cultivation_mode/chengdu_finished_street_stage.gd"
## Only these eighteen lots move. Session and the map use matching authored data.

const COMPACT_LAYOUT="res://assets/data/chengdu-compact-street-layout.json"
const PAVING_SHADER="""shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled, depth_draw_never;
uniform sampler2D paving : source_color, filter_linear_mipmap, repeat_enable;
uniform float period=1.65;
uniform vec2 span;
uniform float feather=.45;
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
 vec2 edge=min(UV,vec2(1.0)-UV)*span;
 ALPHA=smoothstep(0.0,feather,min(edge.x,edge.y));
 ROUGHNESS=1.0;
 SPECULAR=0.0;
}
void light(){if(LIGHT_IS_DIRECTIONAL){DIFFUSE_LIGHT+=direct_linear*ATTENUATION;}}
"""
var _compact_config: Dictionary


func _init() -> void:
	super()
	layout_path=COMPACT_LAYOUT
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(COMPACT_LAYOUT))
	_compact_config=data.compact_street
	# Instance-local profiles also drive painted foundations and shop furniture.
	for row: Dictionary in _compact_config.houses:
		_art_profiles[row.id]["bounds"]=row.after.duplicate()


func setup(walker: Control, font: Font, definition: Dictionary) -> void:
	super.setup(walker,font,definition)
	# Old concept floor paintings were calibrated to the old street positions.
	# Cover that local area with the existing paving, below the grounded feet.
	var config: Dictionary=_compact_config.paving
	var bounds:=_rect(config.bounds)
	var material:=ShaderMaterial.new()
	# Transparent paintings do not write depth. Draw this after old floor
	# projections (-2), but before houses and plants (0), at every camera point.
	material.render_priority=-1
	var shader:=Shader.new()
	shader.code=PAVING_SHADER
	material.shader=shader
	material.set_shader_parameter("paving",load(str(config.texture)))
	material.set_shader_parameter("period",float(config.period))
	material.set_shader_parameter("span",bounds.size/WORLD_SCALE)
	material.set_shader_parameter("feather",float(config.feather))
	var mesh:=MeshInstance3D.new()
	mesh.name="CompactStreetPaving"
	var plane:=PlaneMesh.new()
	plane.size=bounds.size/WORLD_SCALE
	mesh.mesh=plane
	mesh.material_override=material
	mesh.position=logical_to_world(bounds.get_center())+Vector3.UP*float(config.height)
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(mesh)


func audit() -> Dictionary:
	var result:=super.audit()
	result["compact_street"]={"moved_lots":_compact_config.houses.size(),
		"main_width_before":580,"main_width_after":360,"internal_lane_width":60,
		"layout":COMPACT_LAYOUT,"session_obstacles":_definition.obstacles.size()}
	return result
