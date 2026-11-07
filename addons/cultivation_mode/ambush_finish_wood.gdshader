shader_type spatial;
render_mode diffuse_burley;
uniform vec4 wood_tint : source_color = vec4(0.49,0.41,0.28,1.0);
varying vec3 wood_position;
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){wood_position=VERTEX;}
void fragment(){
 vec3 p=wood_position;
 float grain=noise(vec2((p.x+p.z*0.7)*120.0,p.y*3.0));
 float broad=noise(vec2((p.x+p.z)*23.0,p.y*1.9));
 ALBEDO=wood_tint.rgb*(0.83+broad*0.22+grain*0.10);
 ROUGHNESS=0.97;
}
