shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/window_mask.gdshaderinc"
#include "res://assets/shaders/actor_breath.gdshaderinc"
#include "res://assets/shaders/incense_prop.gdshaderinc"

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
uniform bool desk_clean_incense = false;
uniform bool incense_sprite = false;
uniform float actor_breath_strength = 0.0;
uniform float actor_breath_phase = 0.0;
uniform bool actor_breath_is_mentor = false;
uniform float wetness = 0.0;
uniform float daylight_strength = 0.0;
uniform vec4 daylight_rect = vec4(270.0, 315.0, 970.0, 360.0);
uniform vec2 daylight_center = vec2(620.0, 337.0);
uniform vec2 daylight_radius = vec2(350.0, 20.0);
uniform vec4 daylight_color : source_color = vec4(1.0, 0.94, 0.81, 1.0);
uniform float lamp_strength = 0.0;
uniform bool lamp_core_enabled = false;
uniform vec2 lamp_center = vec2(1368.0, 403.0);
uniform vec2 lamp_core_half_size = vec2(24.0, 58.0);
uniform vec2 lamp_spill_center = vec2(1368.0, 428.0);
uniform vec2 lamp_spill_radius = vec2(235.0, 108.0);
uniform vec4 lamp_warm_color : source_color = vec4(1.0, 0.73, 0.40, 1.0);
uniform float lamp_core_gain = 0.7;
uniform float lamp_spill_gain = 0.6;
uniform float tassel_sway_px = 0.0;
uniform bool tassel_motion_enabled = false;
varying vec2 scene_uv;
varying vec4 vertex_modulation;

// Long teal tassel on the central blind in tingyu-clean-v3.png (1672 x 941):
// a padded 581..630 x 178..269 source-pixel patch, leaving room for the displaced fringe.
const vec4 TASSEL_SOURCE_RECT_UV = vec4(0.3474880, 0.1891605, 0.3767943, 0.2858661);
const float TASSEL_FRINGE_START_UV = 0.2337940; // y = 220 px, below the knot and wrap
const float TASSEL_FRINGE_FULL_UV = 0.2763018; // y = 260 px, near the lower fringe

void vertex() {
	scene_uv = (VERTEX + layer_origin) / scene_size;
	vertex_modulation = COLOR;
}

void fragment() {
	vec4 base = COLOR; // Godot fragment COLOR already includes TEXTURE and modulation.
	if (desk_clean_incense) {
		vec2 source = UV / TEXTURE_PIXEL_SIZE;
		if (source.x >= 1150.0 && source.x <= 1350.0 && source.y >= 315.0 && source.y <= 510.0) {
			// Adjacent bare tabletop at the same source row restores this small
			// footprint; above the tabletop the original strip is transparent.
			base = texture(TEXTURE, vec2(1370.0 * TEXTURE_PIXEL_SIZE.x, UV.y)) * vertex_modulation;
		}
	}
	if (incense_sprite) {
		vec2 source = vec2(1150.0, 315.0) + UV * vec2(200.0, 195.0);
		base = texture(TEXTURE, source * TEXTURE_PIXEL_SIZE) * vertex_modulation;
		base.a *= incense_silhouette(source);
	}
	if (actor_breath_strength > 0.0) {
		vec2 actor_uv = actor_breath_warp_uv(UV, TEXTURE_PIXEL_SIZE, actor_breath_strength, actor_breath_phase, actor_breath_is_mentor);
		base = texture(TEXTURE, actor_uv) * vertex_modulation;
	}
	if (tassel_motion_enabled) {
		vec2 patch_softness = TEXTURE_PIXEL_SIZE * vec2(4.0, 3.0);
		float patch_x = smoothstep(TASSEL_SOURCE_RECT_UV.x, TASSEL_SOURCE_RECT_UV.x + patch_softness.x, UV.x)
			* (1.0 - smoothstep(TASSEL_SOURCE_RECT_UV.z - patch_softness.x, TASSEL_SOURCE_RECT_UV.z, UV.x));
		float patch_y = smoothstep(TASSEL_SOURCE_RECT_UV.y, TASSEL_SOURCE_RECT_UV.y + patch_softness.y, UV.y)
			* (1.0 - smoothstep(TASSEL_SOURCE_RECT_UV.w - patch_softness.y, TASSEL_SOURCE_RECT_UV.w, UV.y));
		float tassel_patch = patch_x * patch_y;
		if (tassel_patch > 0.0) {
			float fringe_weight = smoothstep(TASSEL_FRINGE_START_UV, TASSEL_FRINGE_FULL_UV, UV.y);
			vec2 warped_uv = UV - vec2(tassel_sway_px * TEXTURE_PIXEL_SIZE.x * fringe_weight, 0.0);
			vec4 warped = texture(TEXTURE, warped_uv) * vertex_modulation;
			base = mix(base, warped, tassel_patch);
		}
	}
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

	float wood_mask = soft_rect(p, daylight_rect);
	vec2 sun_delta = (p - daylight_center) / max(daylight_radius, vec2(0.001));
	float sun_patch = (1.0 - smoothstep(0.30, 1.0, length(sun_delta))) * wood_mask;
	float sun_mix = clamp(daylight_strength * sun_patch * 0.72, 0.0, 0.62);
	vec3 sunlit = graded * daylight_color.rgb * vec3(1.10, 1.05, 0.94);
	graded = mix(graded, sunlit, sun_mix);

	float damp_mask = soft_rect(p, vec4(270.0, 315.0, 970.0, 360.0));
	float damp_mix = clamp(wetness * damp_mask, 0.0, 1.0);
	graded = mix(graded, graded * vec3(0.91, 0.94, 0.97), damp_mix * 0.72);
	float damp_glint = soft_rect(p, vec4(275.0, 315.0, 965.0, 321.0)) * damp_mix;
	graded += vec3(0.018, 0.022, 0.026) * damp_glint;

	if (lamp_strength > 0.0) {
		float source_luminance = clamp(dot(base.rgb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
		if (lamp_core_enabled) {
			vec2 core_delta = abs(p - lamp_center) - lamp_core_half_size;
			float core_distance = length(max(core_delta, vec2(0.0))) + min(max(core_delta.x, core_delta.y), 0.0);
			float core_mask = 1.0 - smoothstep(-2.0, 5.0, core_distance);
			float paper_gate = smoothstep(0.32, 0.72, source_luminance);
			float core_mix = clamp(lamp_strength * lamp_core_gain * core_mask * paper_gate, 0.0, 1.0);
			vec3 warm_paper = lamp_warm_color.rgb * source_luminance;
			graded = mix(graded, warm_paper, core_mix);
		}
		vec2 spill_delta = (p - lamp_spill_center) / max(lamp_spill_radius, vec2(0.001));
		float spill_radius = length(spill_delta);
		float spill_mask = 1.0 - smoothstep(0.15, 1.0, spill_radius);
		float spill_mix = clamp(lamp_strength * lamp_spill_gain * spill_mask, 0.0, 1.0);
		float surface_warmth = spill_mix * source_luminance;
		graded *= vec3(1.0 + 0.16 * surface_warmth, 1.0 + 0.065 * surface_warmth, 1.0 - 0.07 * surface_warmth);
		graded += vec3(0.025, 0.014, 0.005) * surface_warmth;
	}
	COLOR = vec4(graded, base.a);
}
