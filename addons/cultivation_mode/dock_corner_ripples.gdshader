shader_type canvas_item;
render_mode unshaded;
uniform float elapsed = 0.0;
uniform vec2 stern = vec2(1005.0,415.0);
uniform vec2 bow = vec2(735.0,611.0);
uniform float splash_started = -99.0;
uniform vec2 splash_point = vec2(1040.0,480.0);
uniform vec2 splash_from = vec2(778.0,325.0);
uniform float action_age = -99.0;
uniform float release_time = 0.82;

float ring(vec2 point,vec2 center,float offset) {
	float phase = fract(elapsed/5.8+offset);
	vec2 q = point-center;
	q.y *= 2.8;
	float radius = mix(7.0,29.0,phase);
	float distance_to_ring = (length(q)-radius)/1.8;
	float lifetime = sin(phase*3.14159265);
	return exp(-distance_to_ring*distance_to_ring)*lifetime*lifetime;
}
void fragment() {
	vec2 point = UV*vec2(1280.0,720.0);
	float water = ring(point,stern,0.0)+ring(point,stern,0.5);
	water += ring(point,bow,0.24)+ring(point,bow,0.74);
	// Broad, low-contrast rings fade in and out with no sudden birth or wrap.
	float age = action_age-release_time;
	float splash = 0.0;
	float pebble = 0.0;
	if (splash_started>=0.0 && age>=0.0 && age<0.65) {
		float flight = age/0.65;
		vec2 stone = mix(splash_from,splash_point,flight)-vec2(0.0,58.0*sin(flight*3.14159265));
		pebble = (1.0-smoothstep(1.0,2.1,distance(point,stone)))*0.85;
	}
	if (splash_started>=0.0 && age>=0.65 && age<5.0) {
		float impact_age = age-0.65;
		if (impact_age<0.30) {
			for (int drop=0;drop<3;drop++) {
				float t = impact_age/0.30;
				vec2 offset = vec2(float(drop-1)*9.0*t,-sin(t*3.14159265)*(7.0+float(drop)*2.0));
				splash += (1.0-smoothstep(0.6,1.6,distance(point,splash_point+offset)))*(1.0-t)*0.55;
			}
		}
		for (int i=0;i<3;i++) {
			float t = (age-0.65-float(i)*0.24)/4.0;
			if (t>=0.0 && t<1.0) {
				vec2 q = point-splash_point;
				q.y *= 2.8;
				float d = (length(q)-mix(2.0,59.0,t))/1.9;
				splash += exp(-d*d)*smoothstep(0.0,0.08,t)*(1.0-smoothstep(0.40,1.0,t))*0.25;
			}
		}
	}
	float alpha = clamp(water*0.14+splash,0.0,0.38);
	vec3 color = vec3(0.73,0.77,0.67);
	if (pebble>alpha) {
		alpha = pebble;
		color = vec3(0.29,0.25,0.18);
	}
	COLOR = vec4(color,alpha);
}
