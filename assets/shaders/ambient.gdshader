shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/window_mask.gdshaderinc"

uniform sampler2D cloud_noise : repeat_enable, filter_linear;
uniform vec2 layer_origin = vec2(0.0);
uniform vec2 scene_size = vec2(1416.0, 526.0);
uniform float weather_time = 0.0;
uniform float brightness = 1.0;
uniform vec4 world_tint : source_color = vec4(1.0);
uniform vec4 sky_tint : source_color = vec4(1.0);
uniform float sky_strength = 0.0;
uniform float far_contrast = 1.0;
uniform float cloud_strength = 0.0;
uniform float rain_strength = 0.0;
uniform bool sheltered = false;
varying vec2 scene_uv;

void vertex() {
	scene_uv = (VERTEX + layer_origin) / scene_size;
}

void fragment() {
	vec4 base = COLOR; // Godot fragment COLOR already includes TEXTURE and modulation.
	vec2 p = scene_uv * scene_size;
	float outdoor_mask = sheltered ? 0.0 : window_mask(p);
	float grade_mix = sheltered ? 0.35 : 1.0;
	float brightness_mix = sheltered ? 0.30 : 1.0;
	vec3 tint = mix(vec3(1.0), world_tint.rgb, grade_mix);
	float adjusted_brightness = sheltered
		? max(0.80, mix(1.0, brightness, brightness_mix))
		: brightness;
	vec3 graded = base.rgb * tint * adjusted_brightness;
	vec3 far_scene = vec3(0.5) + (graded - vec3(0.5)) * far_contrast;
	vec3 outdoor = mix(far_scene, sky_tint.rgb, sky_strength * 0.50);
	graded = mix(graded, outdoor, outdoor_mask);

	vec2 drift = vec2(weather_time * 0.013, weather_time * 0.004);
	float cloud = smoothstep(0.25, 0.75, texture(cloud_noise, scene_uv * vec2(1.6, 0.8) + drift).r);
	float weather_mix = sheltered ? 0.0 : 1.0;
	float light = 1.0 - cloud_strength * (0.035 + cloud * 0.095) - rain_strength * 0.035;
	vec3 cool = mix(vec3(1.0), vec3(0.92, 0.97, 1.015), rain_strength * 0.6);
	graded *= mix(1.0, light, weather_mix) * mix(vec3(1.0), cool, weather_mix);
	COLOR = vec4(graded, base.a);
}
