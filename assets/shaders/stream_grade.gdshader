shader_type canvas_item;
render_mode unshaded;
uniform vec4 world_tint : source_color = vec4(1.0);
uniform vec4 sky_tint : source_color = vec4(1.0);
uniform float brightness = 1.0;
uniform float sky_strength = 0.0;
void fragment() {
	vec4 painted = texture(TEXTURE, UV);
	float sky = (1.0 - smoothstep(0.0, 0.40, UV.y)) * smoothstep(0.28, 0.48, UV.x);
	vec3 tint = mix(world_tint.rgb, sky_tint.rgb, sky * sky_strength);
	COLOR = vec4(painted.rgb * tint * brightness, painted.a);
}
