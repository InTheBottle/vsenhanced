#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPositionIn;
layout(location = 1) in vec4 vertexColor;
layout(location = 2) in int renderFlags;

uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;

out vec4 color;

#include vertexflagbits.ash
#include shadowcoords.vsh
#include fogandlight.vsh

void main(void)
{
	vec4 cameraPos = modelViewMatrix * vec4(vertexPositionIn, 1.0);
	color = applyLight(vec3(1), vec4(1), renderFlags, cameraPos) * vertexColor;
	gl_Position = projectionMatrix * cameraPos;
}