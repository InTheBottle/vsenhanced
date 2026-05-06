#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

uniform sampler2D tex;
uniform float extraGodray = 0;
uniform float alphaTest = 0.001;

uniform float auroraCounter;

in vec2 uv;
in vec4 col;
in vec4 rgbaFog;
in vec4 vexPos;
in float xpos;
in float fogAmount;
in float glowLevel;
flat in int renderFlags;



#include fogandlight.fsh
#include noise3d.ash
#include oit.fsh

void main () {
	vec4 outColor = vec4(1);
	
	outColor = applyFogAndShadow(outColor, fogAmount);

	if (outColor.a < alphaTest) discard;
	
	float rndr = min(0.6, cnoise(vec3(vexPos.x/500.0, -vexPos.z/600.0, auroraCounter))*2.3 - 1);
	float rndg = cnoise(vec3(vexPos.x/600.0, vexPos.z/600.0, 1 - auroraCounter))/3;
	float rndb = cnoise(vec3(vexPos.x/600.0, vexPos.z/600.0, 1 - auroraCounter))/5;
	
	outColor = vec4(
		clamp(rndr, 0, 1), 
		clamp(0.5 + rndg - rndr, 0, 0.8),
		clamp(0.5 + rndb, 0, 1),
		max(0, 0.7 - uv.y * 0.7)/2
	);
	
	float advx = xpos * 10; // was uv.x

	outColor.a *= 
		1
		+ 0.7 * cnoise(vec3(advx/6 + (vexPos.x)/120.0, uv.y/2 + (vexPos.z)/120.0, auroraCounter))
		+ 0.5 * cnoise(vec3(advx/3 + (vexPos.x)/60.0, uv.y/1.5 + (vexPos.z)/60.0, auroraCounter))
		+ 0.2 * cnoise(vec3(advx/1.5 + (vexPos.x)/30.0, uv.y + (vexPos.z)/30.0, auroraCounter))
	;
	
	
	//outColor.a *= 0.7;
	
	outColor.a *= clamp(9*uv.y - 1, 0, 1);
	
	//outColor.a=1;
	
	
	outColor.a = clamp(outColor.a, 0, 1);

	outColor *= col;
	
	// Fade edges
	// http://fooplot.com/#W3sidHlwZSI6MCwiZXEiOiJtaW4oMSxtaW4oMTAqeCwoMS14KSoxMCkpIiwiY29sb3IiOiIjMDAwMDAwIn0seyJ0eXBlIjoxMDAwLCJ3aW5kb3ciOlsiMCIsIjEiLCIwIiwiMiJdLCJzaXplIjpbNjQ5LDM5OV19XQ--
	float a = min((xpos - 0.1) * 20, (1 - xpos) * 20);
	outColor.a *= min(1, a);
	
	OIT(clamp(outColor, vec4(0.0), vec4(1.0)), 0.0);
	outGlow = vec4(1, extraGodray, 0, min(1, outColor.a * 6));

}
