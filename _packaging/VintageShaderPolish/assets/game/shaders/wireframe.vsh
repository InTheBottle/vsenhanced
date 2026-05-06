#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPositionIn;
layout(location = 1) in vec4 vertexColor;
layout(location = 2) in int renderFlags;

uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;
uniform vec4 colorIn;
uniform vec3 origin;
uniform float extraGlow;

out vec4 color;

#include vertexflagbits.ash
#include shadowcoords.vsh
#include fogandlight.vsh
#include vertexwarp.vsh

void main(void)
{
	vec4 worldPos = applyVertexWarping(renderFlags, vec4(vertexPositionIn + origin, 1.0));
	worldPos = applyGlobalWarping(worldPos);

	vec4 cameraPos = modelViewMatrix * worldPos;
	
	color = max(vertexColor, vec4(0.001, 0.001, 0.001, 0));
	
	
	glowLevel = extraGlow;
	color = applyLightWithoutPointLight(color, color,  0);
	color.a = vertexColor.a;
	gl_Position = projectionMatrix * cameraPos;
	color *= colorIn;
	
	// Pretend the vertices are closer to the camera to enforce it always being drawn on top
	gl_Position.w += 0.0014 + (renderFlags >> 8) * 0.00025;
}