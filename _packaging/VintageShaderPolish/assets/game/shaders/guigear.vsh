#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPositionIn;
layout(location = 1) in vec2 uvIn;

uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;


out vec2 uv;
out vec2 pos;

void main(void)
{
	gl_Position = projectionMatrix * modelViewMatrix * vec4(vertexPositionIn, 1.0);
	
	uv = uvIn;
	pos = (modelViewMatrix * vec4(vertexPositionIn, 1.0)).xy;
}