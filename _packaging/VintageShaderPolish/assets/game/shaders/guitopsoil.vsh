#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPositionIn;
layout(location = 1) in vec2 uvIn;
layout(location = 2) in vec4 colorIn;

uniform vec4 rgbaIn;
uniform int extraGlow;
uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;
uniform int applyColor;

out vec2 uv;
out vec2 uv2;
out vec4 rgba; // Without biome tint
out vec4 rgba2; // With biome tint


void main(void)
{
	uv = uvIn;
    uv2 = uvIn;
    rgba = vec4(1);
    rgba2 = vec4(1);
	float glowLevel = extraGlow / 128.0;
	
	vec4 color = rgbaIn * (1 + glowLevel);
	if (applyColor == 1) color *= colorIn;
	
	gl_Position = projectionMatrix * modelViewMatrix * vec4(vertexPositionIn, 1.0);
}