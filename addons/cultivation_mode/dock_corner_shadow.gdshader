shader_type canvas_item;
render_mode unshaded;
uniform sampler2D ground_mask : repeat_disable, filter_linear;
uniform vec2 origin;
uniform vec2 extent;
uniform vec4 segments[16];
uniform float radii[16];
uniform int count = 0;
uniform float softness = 2.0;
uniform float opacity = 0.28;
void fragment() {
	vec2 point = origin+UV*extent;
	float coverage = 0.0;
	for (int i=0;i<16;i++) {
		if (i>=count) { break; }
		vec2 a = segments[i].xy;
		vec2 ab = segments[i].zw-a;
		float t = clamp(dot(point-a,ab)/max(dot(ab,ab),0.001),0.0,1.0);
		float d = distance(point,a+ab*t);
		coverage = max(coverage,1.0-smoothstep(max(radii[i]-softness,0.0),radii[i]+softness,d));
	}
	float land = texture(ground_mask,point/vec2(1280.0,720.0)).r;
	COLOR = vec4(0.17,0.20,0.19,coverage*land*opacity);
}
