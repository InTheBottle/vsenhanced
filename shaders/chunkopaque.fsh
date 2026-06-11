#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

uniform sampler2D terrainTex;
uniform sampler2D terrainTexLinear;

in vec4 rgba;
in vec4 rgbaFog;
in float fogAmount;
in vec2 uv;
in float glowLevel;
flat in int renderFlags;
in vec3 normal;
in vec4 worldPos;
in vec3 vspWorldPos;
in vec3 vertexPosition;
in vec3 blockLight;
in vec4 gnormal;
in vec4 camPos;
in float lod0Fade;
in float nb;

uniform float alphaTest;
uniform float fogDensityIn;
uniform float fogMinIn;
uniform float horizonFog;
uniform vec3 sunPosition;
uniform float dayLight;
uniform int haxyFade;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outGlow;
#if SSAOLEVEL > 0
layout(location = 2) out vec4 outGNormal;
layout(location = 3) out vec4 outGPosition;
#endif

#include vertexflagbits.ash
#include fogandlight.fsh
#include dither.fsh
#include skycolor.fsh
#include colormap.fsh
#include underwatereffects.fsh
#include cloudshadow.fsh

#if SHADOWQUALITY > 0
uniform mat4 toShadowMapSpaceMatrixFar;
#endif

vec3 vspApplyUnderwaterEffectsAt(vec3 color, float murkiness, vec3 worldPos) {
	return applyUnderwaterEffectsAt(color, murkiness, worldPos);
}

vec4 vspApplyWetSurface(vec4 texColor, vec3 normal, vec3 worldPos, float fogAmount, float glowLevel) {
	return applyWetSurface(texColor, normal, worldPos, fogAmount, glowLevel);
}

void main() 
{
	vec4 texColor = getColorMapped(terrainTexLinear, texture(terrainTex, uv)) * rgba;
	
	if (psychedelicStrength > Epsilon) texColor = applyPsychedelicEffect(texColor, vertexPosition*2, 0);
	if (glitchStrength > Epsilon) texColor = applyRustEffect(texColor, normal, vertexPosition, 1);
	texColor = vspApplyWetSurface(texColor, normal, vspWorldPos, fogAmount, glowLevel);
	
	float b = getBrightnessFromShadowMap();

	float murkiness=getUnderwaterMurkiness();

	// VSP surface lighting runs on the shadowed color BEFORE fog so that fully
	// fogged terrain converges to exactly the engine fog color. That keeps the
	// terrain/sky horizon seamless at every time of day.
	vec4 litColor = applyShadowFromBrightness(texColor, min(b, nb));
	litColor.rgb = applyMoonDirectLight(litColor.rgb, normal, fogAmount);
	litColor.rgb = applyHemisphericalAmbient(litColor.rgb, normal, dayLightStrength, 0.18);
	litColor.rgb = applyEmissiveBounce(litColor.rgb, blockLight, 0.55);
	litColor.rgb = applyContactDarken(litColor.rgb, 0.20);
	float vspCloudShadow = vspGetCloudShadow(vspWorldPos, normal, fogAmount);
	float vspLitGuard = smoothstep(0.015, 0.09, dot(litColor.rgb, vec3(0.299, 0.587, 0.114)));
	float vspShadowFactor = mix(1.0, vspCloudShadow, vspLitGuard);
	if (!(vspShadowFactor >= 0.0)) vspShadowFactor = 1.0;
	litColor.rgb *= clamp(vspShadowFactor, 0.5, 1.0);

	float effectiveFog = clamp(fogAmount - 50*murkiness, 0.0, 1.0);
	outColor = applyFog(litColor, effectiveFog);
	outColor = applySpheresFog(outColor, effectiveFog, worldPos.xyz);

	float glow = 0;
	float godrayLevel = 0;

	if (haxyFade > 0) {           // test the uniform first, for higher performance
	    if (rgba.a < 0.999) {
			vec4 skyColor = vec4(1);
			vec4 skyGlow = vec4(1);
			float sealevelOffsetFactor = 0.25;
		
			getSkyColorAt(worldPos.xyz, sunPosition, sealevelOffsetFactor, clamp(dayLight, 0, 1), horizonFog, skyColor, skyGlow);
			godrayLevel = skyGlow.g;
			outColor.rgb = mix(skyColor.rgb, outColor.rgb, max(1-dayLight, max(0.0, rgba.a)));
	    }
	}

	outColor.rgb = vspApplyUnderwaterEffectsAt(outColor.rgb, murkiness, vspWorldPos);


#if NORMALVIEW == 0	
	// Fade to sky color
	// Also, when looking through tinted glass you can clearly see the edges where we fade to sky color; using the rgba.a < 0.005 discard seems to completely fix that
	float aTest = outColor.a + max(0.0, 1 - rgba.a) * min(1, outColor.a * 10) - lod0Fade;
	
	if ((renderFlags & WindModeBitMask) == WindModeWeakLowAlphaTest) aTest *= 4;
	
	if (aTest < alphaTest || rgba.a < 0.005) discard;
#endif


#if SHINYEFFECT > 0
	if ((renderFlags & ReflectiveBitMask) != 0) {
		outColor = mix(applyReflectiveEffect(outColor, glow, renderFlags, uv, normal, worldPos, camPos, blockLight), outColor, clamp(2 * fogAmount + 2*(1-b), 0, 1));
	}
	glow += pow(max(0.0, dot(normal, lightPosition)), 6) * 0.125 * shadowIntensity * (1 - fogAmount - murkiness);
#endif




#if SSAOLEVEL > 0
	outGPosition = vec4(camPos.xyz, fogAmount * 2 + glowLevel + murkiness);
	outGNormal = gnormal;
#endif

#if NORMALVIEW > 0
	outColor = vec4((normal.x + 1) / 2, (normal.y + 1)/2, (normal.z+1)/2, 1);
#endif

	float vspScatter = calculateVspVolumetricScatter(worldPos.xyz, normal, fogAmount);
	outGlow = vec4(glowLevel + glow, max(godrayLevel, vspScatter), 0, min(1, fogAmount + outColor.a));
	
//	outColor=vec4(1);
}
