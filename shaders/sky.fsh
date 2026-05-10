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

// Rayleigh + Mie analytic atmosphere. Coefficients tuned visually, not physical.
vec3 atmosphereScatter(vec3 viewDir, vec3 sunDir, float sunStrength) {
	const vec3 betaR = vec3(0.058, 0.135, 0.331);
	const vec3 betaM = vec3(0.055);

	float cosTheta = dot(viewDir, sunDir);
	float cos2 = cosTheta * cosTheta;

	float phaseR = (3.0 / (16.0 * 3.141593)) * (1.0 + cos2);
	float gM = 0.78;
	float gM2 = gM * gM;
	float phaseM = (3.0 / (8.0 * 3.141593)) *
		((1.0 - gM2) * (1.0 + cos2)) /
		((2.0 + gM2) * pow(max(0.0001, 1.0 + gM2 - 2.0 * gM * cosTheta), 1.5));

	// Kasten airmass approximation.
	float cosV = max(-0.05, viewDir.y);
	float cosS = max(-0.05, sunDir.y);
	float opticalV = 1.0 / (cosV + 0.15 * pow(max(0.0001, 1.6386 - cosV), -1.253));
	float opticalS = 1.0 / (cosS + 0.15 * pow(max(0.0001, 1.6386 - cosS), -1.253));

	vec3 sunTransmit = exp(-(betaR + betaM) * opticalS);

	vec3 viewExt = max((betaR + betaM) * opticalV, vec3(0.0001));
	vec3 scatter = (betaR * phaseR + betaM * phaseM) * sunTransmit;
	scatter *= (vec3(1.0) - exp(-viewExt)) / viewExt;

	// Lift to compensate for single-scattering's overly dark off-sun horizon.
	float horizonBoost = 1.0 + 0.85 * (1.0 - smoothstep(-0.04, 0.40, viewDir.y));

	return scatter * 18.0 * sunStrength * horizonBoost;
}

void main()
{
	outColor = vec4(1);
	outGlow = vec4(1);
	float sealevelOffsetFactor = 0.25;
	vec4 engineColor = vec4(1);
	vec4 engineGlow = vec4(1);
	getSkyColorAt(vertexPosition, sunPosition, sealevelOffsetFactor, clamp(dayLight, 0, 1), horizonFog, engineColor, engineGlow);

	vec3 viewDir = normalize(vertexPosition);
	vec3 sunDir = normalize(sunPosition);
	float dayClamped = clamp(dayLight, 0.0, 1.0);
	float sunStrength = smoothstep(-0.05, 0.18, sunDir.y) * dayClamped;

	vec3 atmos = atmosphereScatter(viewDir, sunDir, sunStrength);
	// Reinhard tonemap.
	atmos = atmos / (atmos + vec3(1.0));

	// Blend our analytic atmosphere only where it's clean; engine palette elsewhere.
	float blend = smoothstep(0.20, 0.70, dayClamped) *
		(1.0 - clamp(horizonFog, 0.0, 0.85)) *
		smoothstep(-0.05, 0.12, viewDir.y);
	vec3 skyRgb = mix(engineColor.rgb, atmos, blend * 0.45);

	outColor = vec4(skyRgb, engineColor.a);
	outGlow = engineGlow;

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
