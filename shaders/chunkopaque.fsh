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

#if SHADOWQUALITY > 0
uniform mat4 toShadowMapSpaceMatrixFar;
#endif

float vspNoise(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 vspApplyUnderwaterEffectsAt(vec3 color, float murkiness, vec3 worldPos) {
	return applyUnderwaterEffectsAt(color, murkiness, worldPos);
}

vec4 vspApplyWetSurface(vec4 texColor, vec3 normal, vec3 worldPos, float fogAmount, float glowLevel) {
	return applyWetSurface(texColor, normal, worldPos, fogAmount, glowLevel);
}

float vspCloudDensity(vec2 mapPos) {
	vec2 uv = mapPos / realCloudShadowMapWidth;
	if (uv.x <= 0.001 || uv.y <= 0.001 || uv.x >= 0.999 || uv.y >= 0.999) return 0.0;
	vec2 texel = vec2(1.0 / realCloudShadowMapWidth);
	float density = texture(realCloudShadowMap, uv).r * 0.7;
	density += texture(realCloudShadowMap, uv + texel * vec2( 0.75,  0.0)).r * 0.075;
	density += texture(realCloudShadowMap, uv + texel * vec2(-0.75,  0.0)).r * 0.075;
	density += texture(realCloudShadowMap, uv + texel * vec2( 0.0,  0.75)).r * 0.075;
	density += texture(realCloudShadowMap, uv + texel * vec2( 0.0, -0.75)).r * 0.075;
	return density;
}

vec2 vspIntersectCloudLayer(float originY, float dirY) {
	if (abs(dirY) < 0.0001) return vec2(-1.0);
	vec2 t = (vec2(-62.5, 512.5) - originY) / dirY;
	float nearT = min(t.x, t.y);
	float farT = max(t.x, t.y);
	if (farT < 0.0) return vec2(-1.0);
	return vec2(max(nearT, 0.0), farT - max(nearT, 0.0));
}

float vspCloudVolume(float originY, float dirY, vec2 bounds, float maxT) {
	vec2 t = (bounds - originY) / dirY;
	float nearT = min(t.x, t.y);
	float farT = max(t.x, t.y);
	return max(0.0, min(farT, maxT) - max(nearT, 0.0));
}

float vspTraceCloudShadow(vec3 worldPos, vec3 sunDir) {
	vec2 layer = vspIntersectCloudLayer(worldPos.y - realCloudShadowOffset.y, sunDir.y);
	if (layer.x < 0.0 || layer.y <= 0.0) return 0.0;
	
	const float cloudTileSize = 50.0;
	vec3 origin = worldPos + sunDir * layer.x;
	origin.y -= realCloudShadowOffset.y;
	origin.xz -= realCloudShadowOffset.xz;
	origin /= cloudTileSize;
	origin.xz += realCloudShadowMapWidth * 0.5;
	
	float farT = min(layer.y / cloudTileSize, realCloudShadowMapWidth);
	ivec2 cell = ivec2(floor(origin.xz));
	vec2 positiveStep = step(vec2(0.0), sunDir.xz);
	ivec2 stepDir = ivec2(positiveStep * 2.0 - 1.0);
	vec2 invDir = 1.0 / max(abs(sunDir.xz), vec2(0.0001));
	vec2 nextCell = vec2(cell) + positiveStep;
	vec2 tMax = (nextCell - origin.xz) * invDir * sign(sunDir.xz);
	vec2 tDelta = invDir;
	float t = 0.0;
	float shadow = 0.0;
	
	for (int i = 0; i < 96; i++) {
		if (cell.x < 0 || cell.y < 0 || cell.x >= int(realCloudShadowMapWidth) || cell.y >= int(realCloudShadowMapWidth)) break;
		float nextT = min(min(tMax.x, tMax.y), farT);
		vec4 map = clamp(texelFetch(realCloudShadowMap, cell, 0), vec4(0.0), vec4(1.0));
		float core = smoothstep(0.28, 0.72, map.r);
		if (core > 0.001) {
			vec2 bounds = vec2(min(map.b, map.a), max(map.b, map.a));
			float segment = vspCloudVolume(origin.y + sunDir.y * t, sunDir.y, bounds, max(nextT - t, 0.0));
			float hit = core * clamp(segment * map.r * 2.6, 0.0, 1.0);
			shadow = clamp(shadow + (1.0 - shadow) * hit, 0.0, 0.92);
			if (!(shadow >= 0.0)) return 0.0;
			if (shadow > 0.90) break;
		}
		if (nextT >= farT) break;
		if (tMax.x < tMax.y) {
			cell.x += stepDir.x;
			t = tMax.x;
			tMax.x += tDelta.x;
		} else {
			cell.y += stepDir.y;
			t = tMax.y;
			tMax.y += tDelta.y;
		}
	}
	
	if (!(shadow >= 0.0)) return 0.0;
	return clamp(shadow, 0.0, 1.0);
}

float vspGetCloudShadow(vec3 worldPos, vec3 normal, float fogAmount) {
	float upness = clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
	float daylight = realCloudShadowDaylight * smoothstep(0.02, 0.22, realCloudShadowLightDir.y);
	float fogFade = 1.0 - smoothstep(0.55, 0.95, fogAmount);
	if (upness <= 0.05 || daylight <= 0.01 || fogFade <= 0.01) return 1.0;
	float cloud = 0.0;
	if (realCloudShadowStrength > 0.01 && realCloudShadowMapWidth > 1.0) {
		cloud = vspTraceCloudShadow(worldPos, normalize(realCloudShadowLightDir)) * realCloudShadowStrength;
	} else {
		vec2 p = worldPos.xz * 0.0028 + vec2(windWaveCounter * 0.004, -windWaveCounter * 0.002);
		cloud = smoothstep(0.42, 0.72, vspNoise(floor(p * 24.0) / 24.0));
	}
	if (!(cloud >= 0.0)) cloud = 0.0;
	cloud = clamp(cloud, 0.0, 1.0);
	float strength = clamp(cloud * upness * daylight * fogFade, 0.0, 1.0);
	float shadow = 1.0 - strength * 0.28;
	if (!(shadow >= 0.0)) return 1.0;
	return clamp(shadow, 0.72, 1.0);
}

void main() 
{
	vec4 texColor = getColorMapped(terrainTexLinear, texture(terrainTex, uv)) * rgba;
	
	if (psychedelicStrength > Epsilon) texColor = applyPsychedelicEffect(texColor, vertexPosition*2, 0);
	if (glitchStrength > Epsilon) texColor = applyRustEffect(texColor, normal, vertexPosition, 1);
	texColor = vspApplyWetSurface(texColor, normal, vspWorldPos, fogAmount, glowLevel);
	
	float b = getBrightnessFromShadowMap();
	
	float murkiness=getUnderwaterMurkiness();
	outColor = applyFogAndShadowFromBrightness(texColor, clamp(fogAmount - 50*murkiness, 0, 1), min(b, nb), worldPos.xyz); 
	
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
	float vspCloudShadow = vspGetCloudShadow(vspWorldPos, normal, fogAmount);
	float vspLitGuard = smoothstep(0.015, 0.09, dot(outColor.rgb, vec3(0.299, 0.587, 0.114)));
	outColor.rgb *= mix(1.0, vspCloudShadow, vspLitGuard);


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
	
	outGlow = vec4(glowLevel + glow, godrayLevel, 0, min(1, fogAmount + outColor.a));
	
//	outColor=vec4(1);
}
