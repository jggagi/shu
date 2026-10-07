shader_type canvas_item;
render_mode unshaded;
uniform sampler2D foliage_mask : filter_linear;
uniform sampler2D distance_mask : filter_linear;
uniform float elapsed = 0.0;
uniform float gust = 0.0;
uniform float sway_pixels = 4.5;
uniform float brightness = 1.0;
uniform vec4 world_tint : source_color = vec4(1.0);
uniform vec4 sky_tint : source_color = vec4(1.0);
uniform float sky_strength = 0.0;
uniform float far_contrast = 1.0;
uniform float mist_strength = 0.0;
void fragment() {
 float leaf = texture(foliage_mask, UV).r;
 float wave = sin(elapsed * 2.4 + UV.x * 11.0 + UV.y * 7.0);
 vec2 warp = vec2(wave, sin(elapsed * 1.8 + UV.x * 10.0) * 0.25) * gust * sway_pixels / vec2(1280.0,720.0) * leaf;
 vec4 base = texture(TEXTURE, UV - warp);
 vec3 grade = base.rgb * world_tint.rgb * brightness;
 float far = texture(distance_mask, UV).r;
 vec3 distant = vec3(0.5) + (grade - vec3(0.5)) * far_contrast;
 distant = mix(distant, sky_tint.rgb * brightness, sky_strength * 0.3);
 // A still atmospheric wash is part of weather; no additional cloud animation system.
 distant = mix(distant, vec3(0.77,0.82,0.80) * brightness, clamp(mist_strength * 0.12,0.0,0.32));
 COLOR = vec4(mix(grade,distant,far),base.a);
}
