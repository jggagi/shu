shader_type spatial;
render_mode diffuse_burley;
varying vec3 road_position;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
float fbm(vec2 p) { return noise(p)*0.58+noise(p*2.17+4.0)*0.28+noise(p*4.41)*0.14; }
void vertex() { road_position=VERTEX; }
void fragment() {
 vec2 p=road_position.xz;
 float broad=fbm(p*0.9), grain=noise(p*63.0), grit=noise(p*19.0);
 float center=-5.8*(1.0-smoothstep(-7.5,-4.4,p.y));
 float edge=smoothstep(4.1,7.5,abs(p.x-center)+fbm(p*1.6)*0.9);
 float tracks=exp(-pow((p.x-center-0.9)*2.1,2.0))+exp(-pow((p.x-center+0.9)*2.1,2.0));
 vec3 dry=mix(vec3(0.42,0.37,0.27),vec3(0.60,0.54,0.40),broad);
 dry*=0.94+grit*0.07+grain*0.055;
 dry=mix(dry,vec3(0.40,0.35,0.26),tracks*0.09);
 float moss=edge*smoothstep(0.28,0.77,fbm(p*2.8));
 vec3 shoulder=mix(vec3(0.34,0.39,0.25),vec3(0.24,0.33,0.17),moss);
 vec3 color=mix(dry,shoulder,edge*0.78);
 float pores=smoothstep(0.83,0.95,grain)*0.06;
 color-=pores;
 float height=broad*0.12+grit*0.012+grain*0.003;
 vec3 q0=dFdx(VERTEX),q1=dFdy(VERTEX),sx=cross(NORMAL,q1),sy=cross(q0,NORMAL);
 float determinant=dot(q0,sx);
 vec3 gradient=(dFdx(height)*sx+dFdy(height)*sy)*sign(determinant)/max(abs(determinant),0.00001);
 NORMAL=normalize(NORMAL-gradient*0.12);
 ALBEDO=color; ROUGHNESS=0.98;
}
