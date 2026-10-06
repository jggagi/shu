shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/window_mask.gdshaderinc"

uniform sampler2D mist_noise : repeat_enable, filter_linear;
uniform float weather_time = 0.0;
uniform float density = 0.0;
uniform vec4 mist_tint : source_color = vec4(0.77, 0.84, 0.83, 1.0);
uniform float drift_speed = 0.011;
uniform float phase_offset = 0.0;
uniform vec2 patch_origin = vec2(265.0, 23.0);
uniform vec2 patch_size = vec2(875.0, 343.0);

void fragment() {
	vec2 p = UV * patch_size + patch_origin;
	vec2 scene_uv = p / vec2(1416.0, 526.0);
	vec2 shift = vec2(weather_time * drift_speed + phase_offset, phase_offset * 0.37);
	float cloud = smoothstep(0.2, 0.7, texture(mist_noise, scene_uv * vec2(2.0, 0.7) + shift).r);
	float height = smoothstep(30.0, 140.0, p.y) * (1.0 - smoothstep(320.0, 380.0, p.y));
	COLOR = vec4(mist_tint.rgb, cloud * height * density * window_mask(p));
}
