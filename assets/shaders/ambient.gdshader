shader_type canvas_item;
render_mode unshaded;

uniform sampler2D cloud_noise : repeat_enable, filter_linear;
uniform vec2 layer_origin = vec2(0.0);
uniform vec2 scene_size = vec2(1416.0, 526.0);
uniform float weather_time = 0.0;
uniform float cloud_strength = 0.0;
uniform float rain_strength = 0.0;
varying vec2 scene_uv;

void vertex() {
	scene_uv = (VERTEX + layer_origin) / scene_size;
}
void fragment() {
	vec4 base = COLOR; // Godot fragment COLOR already includes TEXTURE and modulation.
	vec2 drift = vec2(weather_time * 0.013, weather_time * 0.004);
	float cloud = smoothstep(0.25, 0.75, texture(cloud_noise, scene_uv * vec2(1.6, 0.8) + drift).r);
	float light = 1.0 - cloud_strength * (0.035 + cloud * 0.095) - rain_strength * 0.035;
	vec3 cool = mix(vec3(1.0), vec3(0.92, 0.97, 1.015), rain_strength * 0.6);
	COLOR = vec4(base.rgb * light * cool, base.a);
}
