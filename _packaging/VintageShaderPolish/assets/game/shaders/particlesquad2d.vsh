#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout (location = 0) in vec3 vertexPosition;		// Per vertex
layout (location = 1) in vec2 uvIn;					// Per vertex
layout (location = 2) in vec4 baseColor;			// Per vertex

layout (location = 3) in vec4 inColor;				// Per instance
layout (location = 4) in vec3 particlePosition; 	// Per instance
layout (location = 5) in float scale;					// Per instance
layout (location = 6) in float inGlow;				// Per instance

uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;

out vec4 color;
out vec2 uv;
out float glowLevel;

void main()
{
	color = baseColor * inColor;
	uv = uvIn;
	glowLevel = inGlow;
	
	vec3 pos = vec3(vertexPosition.x * scale, vertexPosition.y * scale, vertexPosition.z);
	
	vec4 cameraPos = modelViewMatrix * vec4(pos + particlePosition, 1.0);
	gl_Position = projectionMatrix * cameraPos;
}