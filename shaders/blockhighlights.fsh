#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

in vec4 color;
in float glowLevel;
in vec4 rgbaFog;

uniform sampler2D particleTex;

#include fogandlight.fsh
#include oit.fsh

void main()
{
    OIT(color, glowLevel);
}

