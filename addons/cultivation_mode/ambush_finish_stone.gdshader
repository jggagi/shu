shader_type spatial;
render_mode diffuse_burley, cull_disabled;

// Large weathering forms first; the last octave is deliberately very shallow.
// Coordinates follow the source mesh, so rotating the tactical camera is stable.
uniform vec4 stone_tint : source_color = vec4(0.47, 0.51, 0.46, 1.0);
uniform float weather_scale = 1.0;
uniform float moss_amount = 0.26;
uniform bool use_source_albedo = false;
uniform sampler2D source_albedo : source_color, filter_linear_mipmap;
varying vec3 stone_position;
varying vec3 stone_normal;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() { stone_position=VERTEX; stone_normal=NORMAL; }
void fragment() {
 vec3 p=stone_position*weather_scale;
 float top=smoothstep(0.12,0.85,stone_normal.y);
 vec2 face=mix(vec2(p.x+p.z*0.68,p.y),p.xz,top);
 float broad=noise(face*1.9+vec2(5.3,2.7));
 float worn=noise(face*6.3);
 // Broken diagonal bedding and one irregular crossing joint avoid striping.
 float warp=noise(face*2.7)*0.16;
 float seam=1.0-smoothstep(0.006,0.024,abs(sin((face.y+face.x*0.17+warp)*10.0)));
 seam*=smoothstep(0.32,0.65,noise(face*3.7+2.0));
 float joint=1.0-smoothstep(0.008,0.027,abs(face.x-face.y*0.31-0.14-noise(face*1.7)*0.35));
 float fissure=max(seam*0.72,joint);
 float damp=smoothstep(0.42,0.76,noise(face*3.1+7.8))*(0.25+top*0.75);
 vec3 source=use_source_albedo ? texture(source_albedo,UV).rgb : vec3(1.0);
 vec3 rock=stone_tint.rgb*source*(0.87+broad*0.25+worn*0.045);
 rock=mix(rock,rock*vec3(0.58,0.62,0.57),fissure*0.72);
 rock=mix(rock,vec3(0.25,0.31,0.20),damp*moss_amount);
 // Low contrast weathering on planes; the silhouette remains source geometry.
 float height=broad*0.018+worn*0.002-fissure*0.009;
 vec3 q0=dFdx(VERTEX),q1=dFdy(VERTEX),sx=cross(NORMAL,q1),sy=cross(q0,NORMAL);
 float det=dot(q0,sx);
 vec3 gradient=(dFdx(height)*sx+dFdy(height)*sy)*sign(det)/max(abs(det),0.00001);
 NORMAL=normalize(NORMAL-gradient*0.36);
 ALBEDO=rock; ROUGHNESS=mix(0.97,0.90,damp*moss_amount);
}
