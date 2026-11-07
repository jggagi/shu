shader_type spatial;
render_mode diffuse_burley;
varying vec3 road_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() { road_position=VERTEX; }
void fragment() {
 vec2 p=road_position.xz;
 float broad=noise(p*0.74)*0.70+noise(p*1.6+8.0)*0.30;
 float center=-5.8*(1.0-smoothstep(-7.5,-4.4,p.y));
 float edge=smoothstep(3.6,6.9,abs(p.x-center)+noise(p*1.3)*0.7);
 float dirt=noise(p*5.5);
 float grain=noise(p*34.0);
 // Compacted earth has a quiet average value. Low-frequency variation is
 // deliberately narrow; the board must not look cloudy or marble-veined.
 vec3 dry=vec3(0.512,0.455,0.340)+(broad-0.5)*vec3(0.038,0.035,0.028);
 // Broad worn bands read as compacted traffic rather than repeated scratches.
 float track=exp(-pow((p.x-center-0.84-noise(p*0.35)*0.16)*3.1,2.0));
 track+=exp(-pow((p.x-center+0.82-noise(p*0.35+3.0)*0.19)*3.0,2.0));
 dry=mix(dry,vec3(0.48,0.425,0.335),track*0.14);
 dry*=0.965+dirt*0.065+grain*0.025;
 float grit=smoothstep(0.76,0.94,noise(p*14.0));
 dry=mix(dry,vec3(0.54,0.515,0.42),grit*0.17);
 vec3 shoulder=mix(vec3(0.37,0.40,0.29),vec3(0.29,0.35,0.235),noise(p*2.7));
 vec3 color=mix(dry,shoulder,edge*0.72);
 float height=broad*0.012+dirt*0.004+grain*0.0008;
 vec3 q0=dFdx(VERTEX),q1=dFdy(VERTEX),sx=cross(NORMAL,q1),sy=cross(q0,NORMAL);
 float det=dot(q0,sx);
 vec3 gradient=(dFdx(height)*sx+dFdy(height)*sy)*sign(det)/max(abs(det),0.00001);
 NORMAL=normalize(NORMAL-gradient*0.55);
 ALBEDO=color; ROUGHNESS=0.98;
}
