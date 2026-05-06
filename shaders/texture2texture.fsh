#version 330 core

in vec2 uv;

out vec4 outColor;

uniform sampler2D tex2d;
uniform float texu;
uniform float texv;
uniform float texw;
uniform float texh;
uniform float alphaTest;


void main () {
	outColor = texture(tex2d, vec2(texu + uv.x * texw, texv + uv.y * texh));	
	if (outColor.a <= alphaTest) discard;
}