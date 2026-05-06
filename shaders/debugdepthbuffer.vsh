#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPositionIn;

uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;

out vec3 vertexPosition;

void main(void)
{
	vertexPosition = vertexPositionIn;
	
	gl_Position = projectionMatrix * modelViewMatrix * vec4(vertexPositionIn, 1.0);
}