#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

uniform sampler2D terrainTex;

in vec4 rgba;
in vec4 rgbaFog;
in float fogAmount;
in vec2 uv;
in float glowLevel;
in vec4 worldPos;
in vec3 vspWorldPos;
in vec3 blockLight;
in vec3 vertexPos;

in float normalShadeIntensity;
flat in int renderFlags;
flat in vec3 normal;

#include vertexflagbits.ash
#include fogandlight.fsh
#include noise3d.ash
#include colormap.fsh
#include underwatereffects.fsh
#include oit.fsh

#if SHADOWQUALITY > 0
uniform mat4 toShadowMapSpaceMatrixFar;
#endif

float vspNoise(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 vspApplyUnderwaterEffectsAt(vec3 color, float murkiness, vec3 worldPos) {
	vec3 shaded = applyUnderwaterEffects(color, murkiness);
	float caustic = smoothstep(0.72, 0.98, vspNoise(worldPos.xz * 0.55 + windWaveCounter * 0.08));
	return shaded + mix(vec3(0.72, 0.88, 1.0), waterMurkColor.rgb, 0.35) * caustic * murkiness * 0.12;
}

vec4 vspApplyWetSurface(vec4 texColor, vec3 normal, vec3 worldPos, float fogAmount, float glowLevel) {
	float wetness = clamp(dropletIntensity * max(0.0, normal.y) * (1.0 - fogAmount) * (1.0 - min(1.0, glowLevel)), 0.0, 1.0);
	if (wetness <= 0.001) return texColor;
	float breakup = 0.75 + 0.25 * vspNoise(worldPos.xz * 0.22 + windWaveCounter * 0.03);
	float shine = pow(max(0.0, dot(normalize(normal), lightPosition)), 12.0) * shadowIntensity;
	texColor.rgb *= 1.0 - wetness * breakup * 0.12;
	texColor.rgb += vec3(shine) * wetness * 0.12;
	return texColor;
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
		vec4 map = texelFetch(realCloudShadowMap, cell, 0);
		float core = smoothstep(0.22, 0.68, map.r);
		if (core > 0.0) {
			float segment = vspCloudVolume(origin.y + sunDir.y * t, sunDir.y, map.ba, nextT - t);
			float hit = core * clamp(segment * map.r * 4.0, 0.0, 1.0);
			shadow += (1.0 - shadow) * hit;
			if (shadow > 0.98) break;
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
	
	return shadow;
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
	float strength = cloud * upness * daylight * fogFade;
	return clamp(1.0 - strength * 0.34, 0.62, 1.0);
}

void main() 
{
	// When looking through tinted glass you can clearly see the edges where we fade to sky color
	// Using this discard seems to completely fix that
	if (rgba.a < 0.005) discard;

	vec4 texColor = rgba * getColorMapped(terrainTex, texture(terrainTex, uv));

	if (psychedelicStrength > Epsilon) texColor = applyPsychedelicEffect(texColor, vertexPos.xyz, 0);
	texColor = vspApplyWetSurface(texColor, normal, vspWorldPos, fogAmount, glowLevel);

	float murkiness=getUnderwaterMurkiness();
	if (murkiness > 0) {
		texColor = applyFogAndShadowWithNormal(texColor, 0, normal, normalShadeIntensity, 0.45, worldPos.xyz);
		texColor.rgb = vspApplyUnderwaterEffectsAt(texColor.rgb, murkiness, vspWorldPos);	
	} else {	
		texColor = applyFogAndShadowWithNormal(texColor, fogAmount, normal, normalShadeIntensity, 0.45, worldPos.xyz);
	}	
	
	texColor.rgb *= vspGetCloudShadow(vspWorldPos, normal, fogAmount);
	

#if SHINYEFFECT > 0
	float glow=0;
	texColor = mix(applyReflectiveEffect(texColor, glow, renderFlags, uv, normal, worldPos, worldPos, blockLight), texColor, min(1, 2 * fogAmount));
#endif	

    OIT(texColor, glowLevel);

}
