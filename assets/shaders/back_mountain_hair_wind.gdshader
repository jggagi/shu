shader_type canvas_item;
render_mode blend_mix;

uniform vec4 hair_uv_rect = vec4(0.1, 0.015, 0.78, 0.62);
uniform float wind_time = 0.0;
uniform float wind_strength = 0.0;
uniform float tile_origin = 0.0;
varying vec4 art_modulation;

void vertex() {
    art_modulation = COLOR;
}
void fragment() {
    // Atlas UV covers one half of the source sheet; warp within that tile only.
    vec2 local_uv = vec2((UV.x - tile_origin) * 2.0, UV.y);
    vec2 sample_uv = UV;
    float hair_mask = smoothstep(hair_uv_rect.x, hair_uv_rect.x + 0.06, local_uv.x)
        * (1.0 - smoothstep(hair_uv_rect.z - 0.06, hair_uv_rect.z, local_uv.x))
        * (1.0 - smoothstep(hair_uv_rect.w - 0.10, hair_uv_rect.w, local_uv.y));
    // Ponytail/ribbon side moves, face and seated body remain anchored.
    hair_mask *= 1.0 - smoothstep(0.39, 0.58, local_uv.x);
    sample_uv.x += sin(local_uv.y * 18.0 + wind_time * 2.4) * 0.008 * wind_strength * hair_mask;
    sample_uv.x = clamp(sample_uv.x, tile_origin + TEXTURE_PIXEL_SIZE.x, tile_origin + 0.5 - TEXTURE_PIXEL_SIZE.x);
    COLOR = texture(TEXTURE, sample_uv) * art_modulation;
}
