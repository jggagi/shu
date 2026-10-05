shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 shadow_color : source_color = vec4(0.40, 0.36, 0.32, 1.0);
uniform float opacity : hint_range(0.0, 0.5) = 0.12;
uniform float softness : hint_range(0.2, 2.0) = 1.0;
uniform float irregularity : hint_range(0.0, 0.3) = 0.08;
uniform float lobe_offset : hint_range(0.0, 0.5) = 0.18;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float edge_wobble = sin(UV.x * 17.0 + UV.y * 8.0) * irregularity;
	float broad = length(vec2(p.x * 0.94, p.y * (1.0 + edge_wobble)));
	float core = exp(-broad * broad * 2.7 / softness);
	float left_lobe = exp(-length(vec2(p.x + lobe_offset, p.y * 1.35)) * 3.3 / softness);
	float right_lobe = exp(-length(vec2(p.x - lobe_offset, p.y * 1.45)) * 3.1 / softness);
	float fade = clamp(core * 0.58 + left_lobe * 0.22 + right_lobe * 0.20, 0.0, 1.0);
	float edge = (1.0 - smoothstep(0.58, 1.0, abs(p.x)))
		* (1.0 - smoothstep(0.45, 1.0, abs(p.y)));
	float alpha = fade * edge * opacity * shadow_color.a;
	COLOR = vec4(shadow_color.rgb, alpha);
}
