#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

in vec4 color;
in float glowLevel;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outGlow;

void main () {
	outColor = color;
    outGlow = vec4(glowLevel, 0, 0, color.a);
}