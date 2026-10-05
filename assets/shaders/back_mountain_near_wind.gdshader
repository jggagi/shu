shader_type canvas_item;
render_mode blend_mix;

uniform vec4 pine_uv_rect = vec4(0.0, 0.0, 0.39, 0.64);
uniform vec4 grass_uv_rect = vec4(0.16, 0.715, 0.98, 0.805);
uniform float wind_time = 0.0;
uniform float wind_strength : hint_range(0.0, 0.2) = 0.0;
varying vec4 art_modulation;

void vertex() {
    art_modulation = COLOR;
}

bool inside_rect(vec2 uv, vec4 rect) {
	return uv.x >= rect.x && uv.x <= rect.z && uv.y >= rect.y && uv.y <= rect.w;
}

void fragment() {
	vec2 sample_uv = UV;
	if (inside_rect(UV, pine_uv_rect)) {
		float height_mask = 1.0 - smoothstep(pine_uv_rect.y, pine_uv_rect.w, UV.y);
		sample_uv.x += sin(UV.y * 22.0 + wind_time * 2.1) * 0.014 * wind_strength * height_mask;
	}
	if (inside_rect(UV, grass_uv_rect)) {
		float skyline_mask = 1.0 - smoothstep(grass_uv_rect.y, grass_uv_rect.w, UV.y);
		sample_uv.x += sin(UV.x * 32.0 + wind_time * 2.7) * 0.009 * wind_strength * skyline_mask;
	}
	COLOR = texture(TEXTURE, clamp(sample_uv, vec2(0.0), vec2(1.0))) * art_modulation;
}

// Restrict native light to the foreground stone/ground band; trees stay painted.
void light() {
    float platform = smoothstep(0.62, 0.71, UV.y)
        * (1.0 - smoothstep(0.84, 0.93, UV.y));
    LIGHT = vec4(LIGHT_COLOR.rgb * COLOR.rgb * LIGHT_ENERGY * platform, LIGHT_COLOR.a);
}
