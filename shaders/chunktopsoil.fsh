#version 330 core

uniform sampler2D terrainTex;
uniform sampler2D terrainTexLinear;

uniform float alphaTest = 0.01;
uniform vec2 blockTextureSize;

in vec4 rgba;
in vec4 rgbaFog;
in float fogAmount;
in vec2 uv;
in vec2 uv2;
in float glowLevel;
in vec3 blockLight;
in vec4 worldPos;
in vec3 vspWorldPos;
in vec3 vertexPosition;

flat in int renderFlags;
in vec3 normal;
in vec4 gnormal;



layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outGlow;
#if SSAOLEVEL > 0
in vec4 fragPosition;
layout(location = 2) out vec4 outGNormal;
layout(location = 3) out vec4 outGPosition;
#endif

#include vertexflagbits.ash
#include fogandlight.fsh
#include colormap.fsh
#include noise3d.ash
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
	vec4 brownSoilColor = texture(terrainTex, uv) * rgba;
	
      	if (normal.y >= 0) {
      		 // Top (normal.y == 1) or Sides (normal.y == 0)
      		vec4 grassColor = getColorMapped(terrainTexLinear, texture(terrainTex, uv2 + vec2(blockTextureSize.x * normal.y, 0))) * rgba;
      		outColor = brownSoilColor * (1 - grassColor.a) + grassColor * grassColor.a;
      	} else {
      		 // Bottom
      		outColor = applyFog(brownSoilColor, fogAmount);
	}
	
	if (psychedelicStrength > Epsilon) outColor = applyPsychedelicEffect(outColor, vertexPosition*2, 0);
	if (glitchStrength > Epsilon) outColor = applyRustEffect(outColor, normal, vertexPosition, 1);
	outColor = vspApplyWetSurface(outColor, normal, vspWorldPos, fogAmount, glowLevel);
	

	#if SHADOWQUALITY > 0
	float intensity = 0.34 + (1 - shadowIntensity)/8.0; // this was 0.45, which makes shadow acne visible on blocks
	#else
	float intensity = 0.45;
	#endif
	
	
	
	float murkiness=getUnderwaterMurkiness();
	outColor = applyFogAndShadowWithNormal(outColor, clamp(fogAmount - 50*murkiness, 0, 1), normal, 1, intensity, worldPos.xyz);
	outColor.rgb = vspApplyUnderwaterEffectsAt(outColor.rgb, murkiness, vspWorldPos);
	outColor.rgb = applyMoonDirectLight(outColor.rgb, normal, fogAmount);
	outColor.rgb = applyHemisphericalAmbient(outColor.rgb, normal, dayLightStrength, 0.18);
	outColor.rgb = applyEmissiveBounce(outColor.rgb, blockLight, 0.55);
	outColor.rgb = applyContactDarken(outColor.rgb, 0.20);
	float vspCloudShadow = vspGetCloudShadow(vspWorldPos, normal, fogAmount);
	float vspLitGuard = smoothstep(0.015, 0.09, dot(outColor.rgb, vec3(0.299, 0.587, 0.114)));
	float vspShadowFactor = mix(1.0, vspCloudShadow, vspLitGuard);
	if (!(vspShadowFactor >= 0.0)) vspShadowFactor = 1.0;
	outColor.rgb *= clamp(vspShadowFactor, 0.5, 1.0);
	
	outColor.a = rgbaFog.a;

	float aTest = outColor.a;
	aTest += max(0.0, 1 - rgba.a) * min(1, outColor.a * 10);
#if NORMALVIEW == 0	
	 // Fade to sky color
         // Also, when looking through tinted glass you can clearly see the edges where we fade to sky color; using the outColor.a < 0.005 discard seems to completely fix that
	if (aTest < alphaTest || outColor.a < 0.005) discard;
#endif


	float glow = 0;

#if SHINYEFFECT > 0
	if ((renderFlags & ReflectiveBitMask) > 0) {
		vec3 worldVec = normalize(worldPos.xyz);
	
		float angle = 2 * dot(normalize(normal), worldVec);
		angle += gnoise(vec3(uv.x*500, uv.y*500, worldVec.z/10)) / 7.5;		
		outColor.rgb *= max(vec3(1), vec3(1) + 3*blockLight * gnoise(vec3(worldVec.x/10 + angle, worldVec.y/10 + angle, worldVec.z/10 + angle)));
	}
	
	glow = pow(max(0.0, dot(normal, lightPosition)), 6) * 0.1 * shadowIntensity * (1 - fogAmount);
#endif	

	

#if SSAOLEVEL > 0
	outGPosition = vec4(fragPosition.xyz, fogAmount * 2 + glowLevel);
	outGNormal = gnormal;
#endif

#if NORMALVIEW > 0
	outColor = vec4((normal.x + 1) / 2, (normal.y + 1)/2, (normal.z+1)/2, 1);
#endif

	float vspScatter = calculateVspVolumetricScatter(worldPos.xyz, normal, fogAmount);
    outGlow = vec4(glowLevel + glow, vspScatter, 0, outColor.a);
}
