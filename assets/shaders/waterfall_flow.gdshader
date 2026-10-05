shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float flow_time = 0.0;
uniform float flow_alpha : hint_range(0.0, 0.5) = 0.16;
uniform vec4 flow_tint : source_color = vec4(0.89, 0.93, 0.91, 1.0);

void fragment() {
	float y = UV.y;
	float center = 0.49 + sin(y * 7.2 + 0.4) * 0.075 + sin(y * 17.0) * 0.018;
	float ribbon = abs(UV.x - center);
	float edge = 0.17 + sin(y * 10.0 - flow_time * 1.25) * 0.025;
	float core = 1.0 - smoothstep(edge * 0.42, edge, ribbon);
	float fade_top = smoothstep(0.0, 0.12, y);
	float fade_bottom = 1.0 - smoothstep(0.72, 1.0, y);
	float current = 0.68 + 0.32 * sin(y * 38.0 - flow_time * 3.2 + UV.x * 9.0);
	float alpha = core * fade_top * fade_bottom * current * flow_alpha;
	COLOR = vec4(flow_tint.rgb * COLOR.rgb, alpha * COLOR.a);
}
