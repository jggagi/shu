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
uniform vec2 lower_fade = vec2(40.0, 100.0);
uniform vec2 upper_fade = vec2(195.0, 270.0);
uniform vec2 noise_scale = vec2(1.7, 0.65);

void fragment() {
	vec2 p = UV * patch_size + patch_origin;
	vec2 scene_uv = p / vec2(1416.0, 526.0);
	vec2 shift = vec2(weather_time * drift_speed + phase_offset, phase_offset * 0.37);
	float cloud = smoothstep(0.2, 0.7, texture(mist_noise, scene_uv * noise_scale + shift).r);
	float height = smoothstep(lower_fade.x, lower_fade.y, p.y)
		* (1.0 - smoothstep(upper_fade.x, upper_fade.y, p.y));
	float window = window_mask(p);
	COLOR = vec4(mist_tint.rgb, cloud * height * density * window);
}
