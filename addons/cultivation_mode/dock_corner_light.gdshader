shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D willow_source : source_color, repeat_disable, filter_linear;
uniform float elapsed = 0.0;
uniform vec3 grade_tint = vec3(1.025,1.008,0.995);
uniform float saturation = 1.0;
uniform vec2 light_center = vec2(0.46,0.34);
uniform vec2 light_radius = vec2(0.38,0.44);
uniform vec3 light_color = vec3(1.0,0.77,0.43);
uniform float light_strength = 0.17;
uniform float awning_strength = 0.065;
uniform float leaf_strength = 0.24;
uniform float mist_strength = 0.0;
uniform float lamp_strength = 0.0;
uniform vec2 tea_lamp = vec2(391.0,169.0);
uniform vec2 boat_lamp = vec2(794.0,514.0);
uniform vec2 tea_pool = vec2(370.0,283.0);
uniform vec2 boat_pool = vec2(801.0,551.0);
uniform vec2 lamp_reflection = vec2(794.0,619.0);

float soft_ellipse(vec2 point, vec2 center, vec2 radius) {
	vec2 q = (point-center)/radius;
	return exp(-dot(q,q)*1.7);
}
float leaf(vec2 uv) {
	vec3 c = texture(willow_source, uv).rgb;
	return 1.0-smoothstep(0.38,0.61,dot(c,vec3(0.299,0.587,0.114)));
}
void fragment() {
	vec3 original = texture(screen_texture, SCREEN_UV).rgb;
	vec2 p = UV;
	// Broad warm light preserves the painting's fine local value differences.
	float sunlight = soft_ellipse(p,light_center,light_radius);
	float awning = soft_ellipse(p,vec2(0.245,0.19),vec2(0.18,0.14));
	vec3 lit = original;
	if (saturation != 1.0) {
		lit = mix(vec3(dot(lit,vec3(0.299,0.587,0.114))),lit,saturation);
	}
	lit *= grade_tint;
	lit += (vec3(1.0)-lit)*light_color*(sunlight*light_strength+awning*awning_strength);
	// Deeper cool shade beneath the existing painted tea awning.
	float eave = soft_ellipse(p,vec2(0.187,0.318),vec2(0.09,0.08))*0.055;
	lit *= vec3(1.0-eave,1.0-eave*0.8,1.0-eave*0.5);
	// Project the actual painted willow leaves onto a small authored stone patch.
	// The feathered receiving patch is fully on land; it never crosses the wall.
	vec2 patch = (p-vec2(0.115,0.425))/vec2(0.225,0.225);
	float edge = smoothstep(0.0,0.16,patch.x)*(1.0-smoothstep(0.78,1.0,patch.x));
	edge *= smoothstep(0.0,0.16,patch.y)*(1.0-smoothstep(0.78,1.0,patch.y));
	vec2 source_uv = vec2(0.012+patch.x*0.20,0.36+patch.y*0.49);
	source_uv.x += sin(elapsed*0.38+patch.y*2.4)*0.004;
	source_uv.y += sin(elapsed*0.31)*0.0018;
	vec2 feather = vec2(2.5/1536.0,2.5/864.0);
	float leaves = leaf(source_uv)*0.4;
	leaves += (leaf(source_uv+vec2(feather.x,0.0))+leaf(source_uv-vec2(feather.x,0.0)))*0.15;
	leaves += (leaf(source_uv+vec2(0.0,feather.y))+leaf(source_uv-vec2(0.0,feather.y)))*0.15;
	float shade = clamp(leaves*edge*leaf_strength,0.0,leaf_strength);
	lit *= vec3(1.0-shade,1.0-shade*0.84,1.0-shade*0.62);
	// Morning haze stays over distant water, away from walkable foreground.
	if (mist_strength > 0.0) {
		float mist = soft_ellipse(p,vec2(0.91,0.24),vec2(0.33,0.32));
		lit = mix(lit,vec3(0.80,0.88,0.86),mist*mist_strength);
	}
	if (lamp_strength > 0.0) {
		vec2 point = p*vec2(1280.0,720.0);
		float flame = 0.97+sin(elapsed*1.4)*0.02+sin(elapsed*2.6+0.7)*0.01;
		float wall = soft_ellipse(point,tea_lamp+vec2(0.0,25.0),vec2(57.0,69.0));
		float stone = soft_ellipse(point,tea_pool,vec2(107.0,69.0));
		float deck = soft_ellipse(point,boat_pool,vec2(46.0,31.0));
		float bounce = max(max(wall*0.80,stone*0.68),deck*0.78)*lamp_strength*flame;
		vec3 warm = original*vec3(1.14,0.86,0.52);
		lit = mix(lit,warm,bounce);
		// Tight glow reveals a source; the larger pools keep painted texture.
		float halo = soft_ellipse(point,tea_lamp,vec2(22.0,29.0));
		halo += soft_ellipse(point,boat_lamp,vec2(17.0,22.0));
		lit += vec3(1.0,0.48,0.12)*halo*lamp_strength*flame*0.15;
		// Bounded broken streaks begin below the hull, entirely on open water.
		vec2 r = point-lamp_reflection;
		float band = smoothstep(0.45,0.88,sin(r.y*0.62+sin(r.x*0.12+elapsed*0.7)*0.8));
		float scatter = 0.72+0.28*sin(r.y*0.19+elapsed*0.45);
		float water = soft_ellipse(point,lamp_reflection,vec2(23.0+max(r.y,0.0)*0.13,43.0));
		water *= smoothstep(-28.0,-17.0,r.y)*(1.0-smoothstep(56.0,67.0,r.y));
		lit += vec3(1.0,0.55,0.19)*water*band*scatter*lamp_strength*flame*0.20;
	}
	COLOR = vec4(clamp(lit,vec3(0.0),vec3(1.0)),1.0);
}
