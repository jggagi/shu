shader_type canvas_item;
render_mode unshaded;

uniform float weather_time = 0.0;
uniform float wind_strength = 0.0;
uniform float cloud_strength = 0.0;
uniform float rain_strength = 0.0;
uniform bool shadow_pass = false;
void vertex() {
	float anchored = pow(1.0 - UV.y, 2.0);
	float sway = sin(weather_time * 1.2 + UV.y * 3.5) + 0.35 * sin(weather_time * 2.1 + UV.x * 4.0);
	VERTEX.x += sway * anchored * wind_strength * 5.5;
}
void fragment() {
	vec4 base = COLOR; // Godot fragment COLOR already includes TEXTURE and modulation.
	if (shadow_pass) {
		COLOR = vec4(0.18, 0.22, 0.17, base.a * 0.12 * cloud_strength);
	} else {
	base.rgb *= 1.0 - cloud_strength * 0.06 - rain_strength * 0.05;
	COLOR = base;
	}
}
