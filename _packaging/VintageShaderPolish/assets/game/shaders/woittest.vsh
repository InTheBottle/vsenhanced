#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPosition;
layout(location = 1) in vec4 colorIn;

uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;

out vec4 v_color;
//out float depth;

void main () {
	v_color = colorIn;
	gl_Position = projectionMatrix * modelViewMatrix * vec4(vertexPosition, 1.0);
	
	//depth = -(modelViewMatrix * vec4(vertexPosition, 1.0)).z;
}