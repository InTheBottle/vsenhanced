#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

in vec3 vertexPosition;
in vec4 rgbaFog;
in float nightVisionStrengthv;

uniform float fogDensityIn;
uniform float fogMinIn;
uniform float dayLight;
uniform float horizonFog;
uniform vec3 playerPos;
uniform vec3 sunPosition;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outGlow;
#if SSAOLEVEL > 0
layout(location = 2) out vec4 outGNormal;
layout(location = 3) out vec4 outGPosition;
#endif

#include dither.fsh
#include fogandlight.fsh
#include skycolor.fsh
#include underwatereffects.fsh

vec3 ApplySkyGradientDither(vec3 color) {
	vec3 p = vec3(gl_FragCoord.xy, 73.0);
	vec3 noise = fract(sin(vec3(
		dot(p, vec3(12.9898, 78.233, 37.719)),
		dot(p, vec3(39.3468, 11.135, 83.155)),
		dot(p, vec3(73.156, 52.235, 9.151))
	)) * 43758.5453) - vec3(0.5);
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	float gradientMask = smoothstep(0.04, 0.48, luma) * (1.0 - smoothstep(0.88, 1.0, luma));
	return color + noise * gradientMask * (0.85 / 255.0);
}

void main()
{
	outColor = vec4(1);
	outGlow = vec4(1);
	float sealevelOffsetFactor = 0.25;
	getSkyColorAt(vertexPosition, sunPosition, sealevelOffsetFactor, clamp(dayLight, 0, 1), horizonFog, outColor, outGlow);
	
	if (psychedelicStrength > Epsilon) outColor = applyPsychedelicEffect(outColor, vertexPosition.xyz/2, 0);
	
	float murkiness = max(0.0, getSkyMurkiness() - 14*fogDensityIn);
	outColor.rgb = applyUnderwaterEffects(outColor.rgb, murkiness);
	outColor.rgb = ApplySkyGradientDither(outColor.rgb);
	
	outColor.rgb += vec3(0.1, 0.5, 0.1) * nightVisionStrengthv;
	outGlow.y *= clamp((dayLight - 0.05) * 2 - 50*murkiness, 0, 1);
	
#if SSAOLEVEL > 0
	outGPosition = vec4(0);
	outGNormal = vec4(0);
#endif

}
