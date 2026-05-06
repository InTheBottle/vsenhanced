#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

in vec4 rgbaCloud;
in vec4 rgbaFog;
in vec3 plightrgb;
in float fogAmountf;
in float nightVisionStrengthv;

in vec3 vertexPos;
flat in int flagsf;
in float thinCloudModef;

uniform float fogDensityIn;
uniform float fogMinIn;
uniform vec3 sunPosition;


#include noise3d.ash
#include dither.fsh
#include fogandlight.fsh
#include skycolor.fsh
#include underwatereffects.fsh
#include oit.fsh

float halfsmooth(float x, float t){
    return x > t ? (x - t / 2.0) : (x * x * x * (1.0 - x * 0.5 / t) / t / t);
}

vec3 applyCloudLighting(vec3 baseColor, vec3 skyGlowColor, float skyGlowAlpha, vec3 cloudPos, float alpha, float fogAmount, float thinCloudMode) {
	vec3 skyDir = normalize(cloudPos);
	vec3 sunDir = normalize(sunPosition);
	float sunFacing = max(0.0, dot(skyDir, sunDir));
	float density = smoothstep(0.18, 0.95, alpha) * (1.0 - thinCloudMode * 0.55);
	float edge = 1.0 - smoothstep(0.28, 0.86, alpha);
	float highness = clamp(skyDir.y * 0.5 + 0.5, 0.0, 1.0);
	float breakup = 0.92 + 0.08 * gnoise(vec3(cloudPos.xz * 0.006, windWaveCounter * 0.03));
	
	float rim = pow(sunFacing, 5.2) * edge * skyGlowAlpha * (1.0 - fogAmount);
	float forwardScatter = pow(sunFacing, 1.55) * skyGlowAlpha * (0.34 + 0.86 * edge) * (1.0 - fogAmount);
	float throughLight = pow(sunFacing, 9.0) * skyGlowAlpha * smoothstep(0.12, 0.82, alpha) * (1.0 - smoothstep(0.92, 1.0, alpha)) * (1.0 - fogAmount);
	float silverLining = pow(sunFacing, 14.0) * edge * (0.45 + 0.55 * skyGlowAlpha) * (1.0 - fogAmount);
	float bodyShadow = density * (0.08 + 0.10 * (1.0 - highness)) * (1.0 - rim * 0.55) * (1.0 - throughLight * 0.35) * (1.0 - fogAmount);
	float underside = density * smoothstep(0.2, 0.85, 1.0 - highness) * (1.0 - fogAmount);
	
	vec3 warmLight = mix(vec3(1.0, 0.94, 0.82), skyGlowColor * vec3(1.10, 0.96, 0.82), clamp(skyGlowAlpha + 0.35, 0.0, 1.0));
	vec3 coolFill = mix(rgbaFog.rgb, vec3(0.72, 0.80, 0.92), 0.35);
	
	baseColor *= 1.0 - bodyShadow * breakup;
	baseColor = mix(baseColor, baseColor * coolFill, underside * 0.12);
	baseColor += warmLight * (rim * 0.55 + forwardScatter * 0.24 + throughLight * 0.32 + silverLining * 0.18) * breakup;
	
	return baseColor;
}

float getCloudRaySource(vec3 cloudPos, float alpha, float skyGlowAlpha, float fogAmount, float thinCloudMode) {
	vec3 skyDir = normalize(cloudPos);
	vec3 sunDir = normalize(sunPosition);
	float sunFacing = max(0.0, dot(skyDir, sunDir));
	float thinFade = 1.0 - thinCloudMode * 0.65;
	float edge = smoothstep(0.025, 0.26, alpha) * (1.0 - smoothstep(0.48, 0.95, alpha));
	float bodyGlow = smoothstep(0.10, 0.58, alpha) * (1.0 - smoothstep(0.78, 1.0, alpha));
	float breakup = 0.86 + 0.14 * gnoise(vec3(cloudPos.xz * 0.01, windWaveCounter * 0.025));
	float forward = pow(sunFacing, 3.4);
	float halo = pow(sunFacing, 10.0) * (1.0 - smoothstep(0.82, 1.0, alpha));
	float veil = pow(sunFacing, 1.8) * smoothstep(0.08, 0.55, alpha) * (1.0 - smoothstep(0.90, 1.0, alpha));
	return clamp((edge * 0.66 + bodyGlow * 0.26 + halo * 0.34 + veil * 0.20) * forward * skyGlowAlpha * (1.0 - fogAmount) * thinFade * breakup, 0.0, 0.82);
}

void main()
{
	float sealevelOffsetFactor = 0.25;
	float dayLight = 1;
	float horizonFog = 0;
	// Due to earth curvature the clouds are actually lower, so we do +100 to not have them dismissed during sunglow coloring
	vec4 skyGlow = getSkyGlowAt(vec3(vertexPos.x, vertexPos.y+100, vertexPos.z), sunPosition, sealevelOffsetFactor, clamp(dayLight, 0, 1), horizonFog, 0.7);
	
	vec4 col = rgbaCloud;
	
	col.a = (col.a)/(col.a +0.5)*1.5;
	
	col.rgb *= mix(vec3(1), 1.2 * skyGlow.rgb, skyGlow.a);
	col.rgb *= max(1, 0.9 + skyGlow.a/10);
	col.rgb = applyCloudLighting(col.rgb, skyGlow.rgb, skyGlow.a, vertexPos, col.a, fogAmountf, thinCloudModef);
	
	float baseBloom = max(0.0, 0.25 - fogAmountf/2);
	#if BLOOM == 1
		col.rgb *= 1 - baseBloom;
	#endif
	
	if (psychedelicStrength > Epsilon) col = applyPsychedelicEffect(col, vertexPos.xyz, 1);
	
	col.rgb = mix(col.rgb, rgbaFog.rgb, fogAmountf) + plightrgb;

	col.rgb += vec3(0.1, 0.5, 0.1) * nightVisionStrengthv;

	

	// Seems to give a ~8 FPS boost on an intel hd 620 when looking at the sky at 128 view distance
	if (col.a < 0.005) discard;
	
	float ldepth = texture(liquidDepth, gl_FragCoord.xy/frameSize.xy).r;
	if (ldepth < gl_FragCoord.z) {
		float murkiness = max(0.0, getSkyMurkiness() - 14*fogDensityIn);
		col.rgb = applyUnderwaterEffects(col.rgb, murkiness);
	}

    // fake depth for better blending
    float faux = halfsmooth((gl_FragCoord.z * 2.0 - 1.0) / gl_FragCoord.w, 500.0);

    OIT(col, 0.0, faux);

	float cloudRay = 0.0;
    outGlow = vec4(max(0, skyGlow.a/10 + baseBloom), cloudRay, 0, min(1, col.a*5 - (flagsf >= 5 ? thinCloudModef : 0)));

}
