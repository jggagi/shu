extends RefCounted
## Static surfaces for the earth plane, chipped flagstones and riverbank stone.
## World XZ supplies deterministic colour variation. Stone UVs supply only a
## broad worn centre; mesh/instance COLOR and the authored bevel remain intact.
## Bank moisture uses the same world position and the existing water height.
## No displacement, normal change, animation, transparency or replacement light.

const COMMON_SHADER: String = """shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float detail_strength : hint_range(0.0, 1.0) = 1.0;
varying vec2 surface_world_xz;
varying float surface_world_y;

float surface_hash(vec2 p) {
    p = fract(p * vec2(0.1031, 0.11369));
    p += dot(p, p.yx + 33.33);
    return fract((p.x + p.y) * p.x);
}

float surface_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    vec2 ease = f * f * (3.0 - 2.0 * f);
    float a = surface_hash(cell);
    float b = surface_hash(cell + vec2(1.0, 0.0));
    float c = surface_hash(cell + vec2(0.0, 1.0));
    float d = surface_hash(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, ease.x), mix(c, d, ease.x), ease.y);
}

float grain_visibility(vec2 p, float frequency) {
    // Filter only the small procedural grains as their world scale falls below
    // a pixel. This is local material antialiasing, not a screen-space effect.
    vec2 footprint = fwidth(p) * frequency;
    return 1.0 - smoothstep(0.55, 1.25, max(footprint.x, footprint.y));
}

void vertex() {
    surface_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    surface_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
"""

const EARTH_FRAGMENT: String = """
void fragment() {
    vec2 p = surface_world_xz;
    float broad = surface_noise(p * 0.22 + vec2(11.3, 7.8));
    float middle = surface_noise(p * 1.35 + vec2(19.6, 3.4));
    float grain = (surface_noise(p * 31.0 + vec2(4.2, 12.7)) - 0.5)
        * grain_visibility(p, 31.0);
    // Broad mineral variation and rare cooler, slightly damp soil. Neither
    // term traces a path, a tile boundary or the edge of a scene object.
    float damp = smoothstep(0.63, 0.87, broad);
    vec3 cool_soil = base_color.rgb * vec3(0.94, 0.985, 1.025);
    vec3 soil = mix(base_color.rgb, cool_soil, damp * 0.60);
    float tone = 0.975 + (broad - 0.5) * 0.11
        + (middle - 0.5) * 0.035 + grain * 0.012;
    ALBEDO = mix(base_color.rgb, soil * tone, detail_strength) * COLOR.rgb;
    ROUGHNESS = 0.97;
    METALLIC = 0.0;
    SPECULAR = 0.0;
}
"""

const FLAGSTONE_FRAGMENT: String = """
void fragment() {
    vec2 p = surface_world_xz;
    float broad = surface_noise(p * 0.47 + vec2(8.7, 23.1));
    float mineral = surface_noise(p * 3.6 + vec2(37.4, 5.2));
    float grain = (surface_noise(p * 35.0 + vec2(2.8, 17.3)) - 0.5)
        * grain_visibility(p, 35.0);
    // The existing 0..1 UV domain is local to each chipped stone. A broad,
    // low-contrast centre wears a little paler; there is no perimeter stripe.
    // Existing bevel normals and COLOR already give the edge its own weight.
    vec2 local = (UV - vec2(0.5)) * vec2(1.0, 1.10);
    float wear = 1.0 - smoothstep(0.10, 0.66, length(local));
    wear *= 0.72 + mineral * 0.28;
    float tone = 0.950 + (broad - 0.5) * 0.070
        + (mineral - 0.5) * 0.030 + grain * 0.010 + wear * 0.035;
    vec3 stone = base_color.rgb * tone;
    ALBEDO = mix(base_color.rgb, stone, detail_strength) * COLOR.rgb;
    ROUGHNESS = 0.95 - wear * 0.025 * detail_strength;
    METALLIC = 0.0;
    SPECULAR = 0.0;
}
"""

const BANK_FRAGMENT: String = """
uniform float water_level = -0.28;

void fragment() {
    vec2 p = surface_world_xz;
    float broad = surface_noise(p * 0.33 + vec2(16.2, 4.5));
    float mineral = surface_noise(vec2(p.x * 0.80 + p.y * 0.17,
        surface_world_y * 1.70 + p.y * 0.11) + vec2(5.8, 12.4));
    // Moisture fades into the stone over a shallow height range. A softly
    // varied upper edge avoids a ruled waterline or a repeated block outline.
    float damp_top = -0.12 + (broad - 0.5) * 0.035;
    float wet = 1.0 - smoothstep(water_level - 0.015, damp_top, surface_world_y);
    wet *= 0.82 + mineral * 0.18;
    float tone = 0.995 + (broad - 0.5) * 0.035
        + (mineral - 0.5) * 0.012 - wet * 0.13;
    vec3 cool = mix(vec3(1.0), vec3(0.985, 1.0, 1.01), wet * 0.30);
    // Include mineral variation in the 15% maximum darkening, rather than
    // allowing several individually subtle terms to build a black border.
    vec3 stone = clamp(base_color.rgb * cool * tone,
        base_color.rgb * 0.85, base_color.rgb * 1.025);
    ALBEDO = mix(base_color.rgb, stone, detail_strength) * COLOR.rgb;
    ROUGHNESS = 0.96;
    METALLIC = 0.0;
    SPECULAR = 0.0;
}
"""


func make_earth_material() -> ShaderMaterial:
	# Current plane used #aaa991; this small shift removes its green cast while
	# retaining the scene's light value and warm grey-brown street shoulder.
	return _make_material(EARTH_FRAGMENT, Color("#aaa18c"), "earth")


func make_flagstone_material() -> ShaderMaterial:
	# Preserve the current stone albedo and all per-mesh/per-instance colours.
	return _make_material(FLAGSTONE_FRAGMENT, Color("#b9b9a6"), "flagstone")


func make_bank_material() -> ShaderMaterial:
	return _make_material(BANK_FRAGMENT, Color("#9eaa9b"), "bank")


func _make_material(fragment: String, color: Color, kind: String) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = COMMON_SHADER + fragment
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", color)
	material.set_meta("surface_kind", kind)
	return material
