shader_type canvas_item;
render_mode unshaded, blend_mix;

// A small painted sun, without lens flare, rays or a realtime light source.
uniform float sun_opacity = 0.0;
uniform float sun_radius = 23.0;
uniform vec4 sun_tint : source_color = vec4(1.0, 0.94, 0.71, 1.0);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 160.0;
	float distance = length(p);
	float angle = atan(p.y, p.x);
	float edge = sun_radius + sin(angle * 5.0) * 0.35 + cos(angle * 9.0) * 0.25;
	float disk = 1.0 - smoothstep(edge - 1.5, edge + 1.2, distance);
	float wash = exp(-distance * distance / (sun_radius * sun_radius * 3.0));
	float paper = 0.97 + 0.03 * sin(p.x * 1.9 + sin(p.y * 2.7));
	float border_fade = 1.0 - smoothstep(58.0, 76.0, distance);
	float alpha = (disk * 0.90 + (1.0 - disk) * wash * 0.12) * paper * border_fade * sun_opacity;
	COLOR = vec4(sun_tint.rgb, alpha);
}
