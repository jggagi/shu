shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec4 stone_tint : source_color = vec4(0.47, 0.51, 0.44, 1.0);
uniform float strata_scale = 1.0;
uniform float moss_amount = 0.38;
varying vec3 rock_position;
varying vec3 rock_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
 vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
 return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1)), f.x), f.y);
}
void vertex() { rock_position = VERTEX; rock_normal = NORMAL; }
void fragment() {
 vec2 p = mix(vec2(rock_position.x + rock_position.z*0.61, rock_position.y), rock_position.xz, smoothstep(0.4,0.9,abs(rock_normal.y))) * strata_scale;
 float broad = noise(p*0.85);
 float fine = noise(p*16.0);
 float strata = p.y*11.0 + noise(p*vec2(0.6,1.7))*2.7 + p.x*0.22;
 float seam = pow(1.0-abs(sin(strata)), 12.0);
 float joint = pow(1.0-abs(sin(p.x*3.1 + noise(p*0.9)*5.0)), 20.0);
 float moss = smoothstep(0.57,0.84,noise(p*2.4+5.0)) * (0.25+max(rock_normal.y,0.0)*0.75);
 vec3 stone = stone_tint.rgb * (0.77+broad*0.38+fine*0.08);
 stone *= 1.0-seam*0.26-joint*0.18;
 stone = mix(stone, vec3(0.25,0.32,0.18), moss*moss_amount);
 float height = broad*0.5 + fine*0.035 - seam*0.10 - joint*0.04;
 vec3 q0=dFdx(VERTEX), q1=dFdy(VERTEX);
 vec3 sx=cross(NORMAL,q1), sy=cross(q0,NORMAL);
 float determinant=dot(q0,sx);
 vec3 gradient=(dFdx(height)*sx+dFdy(height)*sy)*sign(determinant)/max(abs(determinant),0.00001);
 NORMAL=normalize(NORMAL-gradient*0.11);
 ALBEDO=stone; ROUGHNESS=0.94;
}
