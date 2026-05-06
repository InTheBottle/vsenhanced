#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 quadCoord;  // Per vertex
layout(location = 1) in vec2 uvIn;			// Per vertex

layout(location = 2) in vec3 pointA;
layout(location = 3) in vec3 pointB;

uniform float lineWidth;
uniform mat4 projection;
uniform mat4 view;
uniform vec3 origin;

void main() {
	vec3 dir = pointB - pointA;
	vec3 q = quadCoord * vec3(lineWidth, 1, lineWidth) - vec3(lineWidth/2, 0, lineWidth/2);
	float up = q.y;
	gl_Position = projection * view * vec4(pointA + origin + vec3(1, dir.y, 1) * q + vec3(dir.x*up, 0, dir.z*up), 1);
}