shader_type canvas_item;
render_mode unshaded, blend_mix;

// Only presentation: source frames, geometry and playback timing stay intact.
uniform float saturation = 0.80;
uniform float ink_contrast = 0.88;
uniform vec3 mountain_wash : source_color = vec3(0.64, 0.70, 0.66);
uniform vec3 stone_bounce : source_color = vec3(0.43, 0.48, 0.39);
uniform float foot_y = 542.0;
uniform float paper_strength = 0.85;
varying vec4 world_modulate;
varying vec2 frame_pixel;
varying vec2 paper_point;

float paper_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float paper_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(paper_hash(cell), paper_hash(cell + vec2(1.0, 0.0)), f.x),
        mix(paper_hash(cell + vec2(0.0, 1.0)), paper_hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
    world_modulate = COLOR;
    frame_pixel = VERTEX;
    // Paper stays on the painted canvas; atlas page changes never reseed it.
    paper_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    vec4 source = texture(TEXTURE, UV);
    // Subpixel edge softness only; premultiplied filtering avoids white matte fringes.
    vec2 px = TEXTURE_PIXEL_SIZE * 0.65;
    vec4 left = texture(TEXTURE, UV - vec2(px.x, 0.0));
    vec4 right = texture(TEXTURE, UV + vec2(px.x, 0.0));
    vec4 up = texture(TEXTURE, UV - vec2(0.0, px.y));
    vec4 down = texture(TEXTURE, UV + vec2(0.0, px.y));
    float coverage = source.a * 0.76 + (left.a + right.a + up.a + down.a) * 0.06;
    vec3 pigment = (source.rgb * source.a * 0.76 +
        (left.rgb * left.a + right.rgb * right.a + up.rgb * up.a + down.rgb * down.a) * 0.06) / max(coverage, 0.0001);
    float value = dot(pigment, vec3(0.299, 0.587, 0.114));
    float skin = smoothstep(0.08, 0.22, pigment.r - pigment.b) * smoothstep(0.28, 0.75, value);
    pigment = mix(vec3(value), pigment, mix(saturation, 0.96, skin));
    pigment = (pigment - vec3(0.48)) * mix(ink_contrast, 0.97, skin) + vec3(0.48);
    // A light mountain wash brings clean video colours into the painted palette.
    pigment = mix(pigment, mountain_wash, mix(0.075, 0.02, skin));
    pigment *= mix(vec3(0.95, 0.98, 0.96), vec3(1.0, 0.98, 0.96), skin);
    // Reflected stone colour belongs near the lower robe and shoes, not the face.
    float lower = smoothstep(foot_y - 150.0, foot_y - 10.0, frame_pixel.y);
    pigment = mix(pigment, stone_bounce, lower * (1.0 - value) * 0.13);
    // Pigment variation belongs on broad paint areas, not faces or narrow ink detail.
    float left_value = dot(left.rgb, vec3(0.299, 0.587, 0.114));
    float right_value = dot(right.rgb, vec3(0.299, 0.587, 0.114));
    float up_value = dot(up.rgb, vec3(0.299, 0.587, 0.114));
    float down_value = dot(down.rgb, vec3(0.299, 0.587, 0.114));
    float detail = max(abs(left_value - right_value), abs(up_value - down_value));
    float edge_keep = smoothstep(0.018, 0.09, detail);
    float solid = min(min(left.a, right.a), min(up.a, down.a));
    float paint_area = (1.0 - skin) * (1.0 - edge_keep) * smoothstep(0.09, 0.28, value) * smoothstep(0.94, 0.995, solid);
    float grain = paper_noise(paper_point * 0.50);
    float fibres = paper_noise(paper_point * vec2(0.075, 0.46) + vec2(17.0, 9.0));
    float wash = paper_noise(paper_point * vec2(0.045, 0.11) + vec2(4.0, 23.0));
    float absorption = (grain - 0.5) * 0.045 + (fibres - 0.5) * 0.030 + (wash - 0.5) * 0.055;
    pigment *= 1.0 + absorption * paper_strength * paint_area;
    // Alpha, geometry, world grading and all source timing remain unchanged.
    COLOR = vec4(clamp(pigment, vec3(0.0), vec3(1.0)) * world_modulate.rgb, coverage * world_modulate.a);
}
