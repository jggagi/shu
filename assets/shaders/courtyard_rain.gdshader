shader_type canvas_item;
render_mode unshaded;
uniform sampler2D exposed_mask : filter_linear;
uniform float elapsed = 0.0;
uniform float rain_amount = 0.0;
uniform float opacity = 0.53;
float hash(float x) {return fract(sin(x*127.1)*43758.5453);}
void fragment() {
 vec2 p = UV * vec2(1280.0,720.0);
 float sx = p.x - p.y * 0.065;
 float column = floor(sx / 18.0);
 float center = 4.0 + hash(column + 5.0) * 10.0;
 float x = mod(sx,18.0);
 float y = mod(p.y-elapsed*255.0+hash(column)*155.0,155.0);
 float len = 12.0+hash(column+19.0)*8.0;
 float line = (1.0-smoothstep(0.35,1.15,abs(x-center))) * smoothstep(0.0,2.0,y) * (1.0-smoothstep(len-2.0,len,y));
 line *= 1.0-y/len;
 COLOR=vec4(0.82,0.89,0.92,max(line,0.0)*texture(exposed_mask,UV).r*rain_amount*opacity);
}
