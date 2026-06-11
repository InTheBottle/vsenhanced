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
#include cloudshadow.fsh
#include oit.fsh


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
	// When looking through tinted glass you can clearly see the edges where we fade to sky color
	// Using this discard seems to completely fix that
	if (rgba.a < 0.005) discard;

	vec4 texColor = rgba * getColorMapped(terrainTex, texture(terrainTex, uv));

	if (psychedelicStrength > Epsilon) texColor = applyPsychedelicEffect(texColor, vertexPos.xyz, 0);
	texColor = vspApplyWetSurface(texColor, normal, vspWorldPos, fogAmount, glowLevel);

	float murkiness=getUnderwaterMurkiness();

	// VSP surface lighting runs on the shadowed color BEFORE fog so that fully
	// fogged geometry converges to exactly the engine fog color. That keeps the
	// terrain/sky horizon seamless at every time of day.
	texColor = applyShadowWithNormal(texColor, normal, normalShadeIntensity, 0.45);

	float vspCloudShadow = vspGetCloudShadow(vspWorldPos, normal, fogAmount);
	float vspLitGuard = smoothstep(0.015, 0.09, dot(texColor.rgb, vec3(0.299, 0.587, 0.114)));
	texColor.rgb = applyMoonDirectLight(texColor.rgb, normal, fogAmount);
	texColor.rgb = applyHemisphericalAmbient(texColor.rgb, normal, dayLightStrength, 0.18);
	texColor.rgb = applyEmissiveBounce(texColor.rgb, blockLight, 0.55);
	texColor.rgb = applyContactDarken(texColor.rgb, 0.20);
	// Subsurface translucency: leaves/grass glow warm when sun is behind the surface (wrap lighting model).
	{
		vec3 sssLightDir = normalize(realCloudShadowLightDir);
		float wrap = max(0.0, dot(-sssLightDir, normalize(normal)) + 0.4) / 1.4;
		float sss = pow(wrap, 2.4) * clamp(realCloudShadowDaylight, 0.0, 1.0) * (1.0 - fogAmount);
		vec3 sssTint = vec3(0.85, 1.05, 0.55);
		texColor.rgb += texColor.rgb * sssTint * sss * 0.35;
	}
	float vspShadowFactor = mix(1.0, vspCloudShadow, vspLitGuard);
	if (!(vspShadowFactor >= 0.0)) vspShadowFactor = 1.0;
	texColor.rgb *= clamp(vspShadowFactor, 0.5, 1.0);

	if (murkiness > 0) {
		texColor = applySpheresFog(texColor, 0.0, worldPos.xyz);
		texColor.rgb = vspApplyUnderwaterEffectsAt(texColor.rgb, murkiness, vspWorldPos);
	} else {
		texColor = applyFog(texColor, fogAmount);
		texColor = applySpheresFog(texColor, fogAmount, worldPos.xyz);
	}


#if SHINYEFFECT > 0
	float glow=0;
	texColor = mix(applyReflectiveEffect(texColor, glow, renderFlags, uv, normal, worldPos, worldPos, blockLight), texColor, min(1, 2 * fogAmount));
#endif

    OIT(texColor, glowLevel);
	outGlow.y = max(outGlow.y, calculateVspVolumetricScatter(worldPos.xyz, normal, fogAmount));

}
