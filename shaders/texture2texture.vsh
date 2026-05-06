#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 pos;
layout(location = 1) in vec2 uvIn;

uniform float xs;
uniform float ys;
uniform float width;
uniform float height;

out vec2 uv;

void main(void)
{
	uv = uvIn;	
	
	vec2 posTL = (pos.xy  + 1) / 2;
	
	posTL.x = xs + posTL.x * width;
	posTL.y = ys + posTL.y * height;
	vec2 posOut = posTL * 2 - 1;
	
	gl_Position = vec4(posOut.x, posOut.y, 0, 1);
}