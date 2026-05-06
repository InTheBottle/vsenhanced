#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

in vec4 color;
in vec2 uv;
in float glowLevel;



uniform sampler2D particleTex;
uniform int oitPass;
uniform int withTexture;
uniform int heldItemMode;

#include oit.fsh

void main()
{
	vec4 outColor;

	if (heldItemMode > 0) {
		// Ensure held item always being in the front
		gl_FragDepth = gl_FragCoord.z / 20;
	} else {
		gl_FragDepth = gl_FragCoord.z;
	}
	
	if (withTexture > 0) {
		outColor = color * texture(particleTex, uv);
	} else {
		outColor = color;
	}
	
	if (outColor.a < 0.002) discard;
	
	

	if (oitPass > 0) {
		// Dunno why but with this modifier the torch particles look more similar when held versus placed
		outColor.a*=1;

        OIT(outColor, glowLevel);

	} else {
		OITreveal = outColor;
	}
}
