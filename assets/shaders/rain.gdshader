shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/window_mask.gdshaderinc"
uniform vec2 patch_origin = vec2(269.0, 20.0);
uniform vec2 patch_size = vec2(706.0, 360.0);
uniform float weather_time = 0.0;
uniform float rain_strength = 0.0;
uniform float columns = 44.0;
uniform float fall_speed = 270.0;
uniform float row_height = 180.0;
uniform float opacity = 0.42;
float hash(float p) { return fract(sin(p * 127.1) * 43758.5453); }
void fragment() {
	vec2 p = UV * patch_size;
	float cell_width = patch_size.x / columns;
	float slanted_x = p.x - p.y * 0.06;
	float column = floor(slanted_x / cell_width);
	float x = mod(slanted_x, cell_width);
	float center = cell_width * (0.25 + hash(column + 5.0) * 0.5);
	float y = mod(p.y - weather_time * fall_speed + hash(column) * row_height, row_height);
	float length = 11.0 + hash(column + 19.0) * 7.0;
	float line = (1.0 - smoothstep(0.35, 1.15, abs(x - center))) * smoothstep(0.0, 2.0, y) * (1.0 - smoothstep(length - 2.0, length, y));
	line *= 1.0 - y / length;
	float outside = window_mask(p + patch_origin);
	COLOR = vec4(0.79, 0.87, 0.89, max(line, 0.0) * outside * rain_strength * opacity);
}
