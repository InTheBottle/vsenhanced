#version 330 core
#extension GL_ARB_explicit_attrib_location: enable


uniform vec4 color;
uniform float glowLevel = 1.0;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outGlow;


void main() {
	outColor = color;
	outGlow = vec4(glowLevel, 0, 0, outColor.a);
}