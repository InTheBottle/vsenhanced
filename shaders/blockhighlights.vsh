#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPositionIn;
layout(location = 1) in vec4 vertexColor;


uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;

out vec4 color;
out vec4 rgbaFog;

#include vertexflagbits.ash
#include shadowcoords.vsh
#include fogandlight.vsh

void main(void)
{
	vec4 cameraPos = modelViewMatrix * vec4(vertexPositionIn, 1.0);
	
	color = vertexColor;
	gl_Position = projectionMatrix * cameraPos;
	
	// We are cheap. We pretend the highlights are closer to the camera to enforce it
	// always being drawn on top
	gl_Position.w += 0.0004;
	
	rgbaFog = vec4(0);
	glowLevel = 0;
}