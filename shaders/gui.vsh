#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPositionIn;
layout(location = 1) in vec2 uvIn;
layout(location = 2) in vec4 colorIn;
// Bits 0-7: Glow level
// Bits 8-10: Z-Offset
// Bit 11: Wind waving yes/no
// Bit 12: Water waving yes/no
// Bit 13: low contrast mode
// Bit 14-26: x/y/z normals, 12 bits total. Each axis with 1 sign bit and 3 value bits
layout(location = 3) in int renderFlagsIn;
layout(location = 4) in float damageEffectIn;
layout(location = 5) in int jointId;

uniform vec4 rgbaIn;
uniform vec4 rgbaGlowIn;
uniform int extraGlow;
uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 modelMatrix;
uniform int applyModelMat;
uniform int applyColor;
uniform int applyAnimation;

// UBO:Animation,0,4800
layout (std140) uniform Animation
{
    mat4 values[MAXANIMATEDELEMENTS];	// MAXANIMATEDELEMENTS constant is defined during game engine shader loading.
} ElementTransforms;




out vec2 uv;
out vec2 uvOverlay;
out vec4 color;
out vec4 rgbaGlow;
out vec2 clipPos;
out float damageEffectV;

flat out vec3 normal;
out float normalShadeIntensity;

#include vertexflagbits.ash
#include fogandlight.vsh

void main(void)
{
	damageEffectV = damageEffectIn;
	uv = uvIn;
	
	int glow = min(255, extraGlow + (renderFlagsIn & GlowLevelBitMask));
	
	glowLevel = glow / 255.0;
	rgbaGlow = rgbaGlowIn;
	
	color = rgbaIn;
	
	if (applyColor == 1) color *= colorIn;
	
	if (applyAnimation > 0) {
		mat4 animModelMat = modelViewMatrix * ElementTransforms.values[jointId];
		gl_Position = projectionMatrix * animModelMat * vec4(vertexPositionIn, 1.0);
	} else {
		gl_Position = projectionMatrix * modelViewMatrix * vec4(vertexPositionIn, 1.0);
	}
	
	clipPos = gl_Position.xy;
	
	normal = unpackNormal(renderFlagsIn);
	if (applyModelMat > 0) {
		normal = (modelMatrix * vec4(normal, 0)).xyz;
		normal = normalize(normal);
	}
	
	normalShadeIntensity = 1;
}