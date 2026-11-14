shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D fabric : source_color;
uniform bool has_fabric = false;
uniform sampler2D fabric_normal : hint_normal;
uniform bool has_normal = false;
uniform vec4 cloth_color : source_color = vec4(0.32,0.45,0.51,1.0);
void fragment() {
 vec3 original = COLOR.rgb * (has_fabric ? texture(fabric,UV).rgb : vec3(1.0));
 float value = dot(original,vec3(0.2126,0.7152,0.0722));
 ALBEDO = cloth_color.rgb * clamp(0.28+value*1.65,0.35,1.25);
 if (has_normal) { NORMAL_MAP = texture(fabric_normal,UV).rgb; }
 ROUGHNESS = 0.92;
 SPECULAR = 0.12;
}
