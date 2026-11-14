shader_type canvas_item;
render_mode unshaded;
uniform float elapsed = 0.0;
uniform bool environment_enabled = true;
uniform bool foliage_only = false;

vec2 painted_wind(vec2 uv) {
	float gust = sin(elapsed*0.38);
	// Feathered canopy, fixed trunk. Only a few source pixels at the leaf tips.
	vec2 q = (uv-vec2(0.095,0.58))/vec2(0.125,0.29);
	float leaves = (1.0-smoothstep(0.45,1.0,dot(q,q)))*smoothstep(0.025,0.065,uv.x);
	leaves *= 1.0-smoothstep(0.83,0.94,uv.y);
	float tips = 0.65+0.35*sin(uv.y*9.0);
	vec2 offset = vec2(gust*0.0015*tips,sin(elapsed*0.31)*0.0004)*leaves;
	// The cloth's upper attachment stays pinned; its loose diagonal hem breathes.
	vec2 px = uv*vec2(1536.0,864.0);
	float upper = 320.0-0.46*px.x;
	float lower = 385.0-0.52*px.x;
	float cloth = smoothstep(4.0,18.0,px.y-upper)*(1.0-smoothstep(-4.0,6.0,px.y-lower));
	cloth *= smoothstep(240.0,275.0,px.x)*(1.0-smoothstep(475.0,500.0,px.x));
	offset.y += gust*0.0009*cloth;
	return offset;
}

void fragment() {
	vec2 uv = UV;
	// Interior river flow preserves every bank, boat, post and plank edge.
	float right_water = smoothstep(0.815,0.855,uv.x)*smoothstep(0.31,0.40,uv.y);
	float bottom_water = smoothstep(0.88,0.96,uv.y)*smoothstep(0.33,0.39,uv.x);
	float mask = max(right_water,bottom_water);
	vec2 wave = vec2(sin(uv.y*116.0+elapsed*0.65)*0.00045,sin(uv.x*79.0-elapsed*0.32)*0.00022);
	vec2 wind = environment_enabled ? painted_wind(uv) : vec2(0.0);
	vec4 c = texture(TEXTURE,uv+wave*mask+wind);
	if (foliage_only) {
		float luma = dot(c.rgb,vec3(0.299,0.587,0.114));
		c.a *= 1.0-smoothstep(0.43,0.65,luma);
	}
	COLOR = c;
}
