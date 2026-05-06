#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPositionIn;
layout(location = 1) in vec2 uvIn;
layout(location = 2) in vec4 colorIn;
layout(location = 3) in int flags;
layout(location = 4) in float damageEffectIn;
layout(location = 5) in int jointId;

uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;
uniform int addRenderFlags;

// UBO:Animation,0,4800
layout (std140) uniform Animation
{
    mat4 values[MAXANIMATEDELEMENTS];	// MAXANIMATEDELEMENTS constant is defined during game engine shader loading. 
} ElementTransforms;

out vec2 uv;

void main(void)
{
	vec4 cameraPos = modelViewMatrix * ElementTransforms.values[jointId] * vec4(vertexPositionIn, 1.0);
	uv = uvIn;
	gl_Position = projectionMatrix * cameraPos;
}