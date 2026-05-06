#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

in vec4 color;
in vec2 uv;
in vec4 rgbaFog;
in vec3 vexPos;
in float fogAmount;
in float glowLevel;
in float extraWeight;



uniform sampler2D particleTex;

#include fogandlight.fsh
#include underwatereffects.fsh
#include oit.fsh

void main()
{
	vec4 outColor;
	
	float murkiness=getUnderwaterMurkiness();
	if (murkiness > 0) {
		outColor = applyFogAndShadow(color, 0);
		outColor.rgb = applyUnderwaterEffects(outColor.rgb, murkiness);	
	} else {	
		outColor = applyFogAndShadow(color, fogAmount);
	}

	vec2 uvdist = vec2(
		max(max(0.0, 0.1 - uv.x), max(0.0, uv.x - 0.9)),
		max(max(0.0, 0.1 - uv.y), max(0.0, uv.y - 0.9))
	);
	
	outColor.a *= 1 - length(uvdist)*10;	

    OIT(clamp(outColor, vec4(0.0), vec4(1.0)), glowLevel);

}
