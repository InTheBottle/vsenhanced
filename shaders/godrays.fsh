#version 330 core

uniform sampler2D inputTexture;
uniform sampler2D glowParts;
uniform sampler2D realCloudShadowMap;
uniform float realCloudShadowMapWidth;
uniform vec3 realCloudShadowOffset;
uniform float realCloudShadowStrength;
uniform vec3 realCloudShadowLightDir;


in vec2 texCoord;
in vec3 sunPosScreen;
in float iGlobalTime;
in float intensity;
in float direction;

out vec4 outColor;


// Falloff over distance
const float decay = 0.9985; 

vec3 getSunRayColor(vec2 nSunPos) {
	float sunHeight = clamp(nSunPos.y, 0.0, 1.0);
	float horizonWarmth = 1.0 - smoothstep(0.28, 0.68, sunHeight);
	vec3 lowSun = vec3(1.0, 0.68, 0.42);
	vec3 highSun = vec3(1.0, 0.92, 0.74);
	vec3 sunColor = mix(highSun, lowSun, horizonWarmth);
	vec3 moonColor = vec3(0.58, 0.66, 0.88);
	float moonBlend = smoothstep(-1.0, -0.15, -direction);
	return mix(sunColor, moonColor, moonBlend * 0.72);
}

float sampleCloudBreakup(vec2 uv, vec2 nSunPos, float stepIndex) {
	if (realCloudShadowStrength <= 0.01 || realCloudShadowMapWidth <= 1.0) {
		return 1.0;
	}

	vec2 ray = uv - nSunPos;
	vec2 wind = realCloudShadowOffset.xz / max(realCloudShadowMapWidth * 50.0, 1.0);
	vec2 lightDrift = normalize(realCloudShadowLightDir.xz + vec2(0.0001)) * 0.035;
	vec2 mapUv = fract(vec2(0.5) + wind + ray * vec2(0.72, 0.58) + lightDrift + stepIndex * lightDrift * 0.012);
	vec2 texel = vec2(1.0 / realCloudShadowMapWidth);

	float density = texture(realCloudShadowMap, mapUv).r * 0.60;
	density += texture(realCloudShadowMap, mapUv + texel * vec2( 1.35,  0.0)).r * 0.14;
	density += texture(realCloudShadowMap, mapUv + texel * vec2( 0.0, -1.35)).r * 0.14;

	float clearGap = 1.0 - smoothstep(0.12, 0.62, density);
	float silverEdge = smoothstep(0.08, 0.34, density) * (1.0 - smoothstep(0.48, 0.92, density));
	float blocker = smoothstep(0.58, 0.95, density);
	return clamp(0.72 + clearGap * 0.50 + silverEdge * 0.52 - blocker * 0.22, 0.34, 1.56);
}

float sampleRayMask(vec2 uv, vec2 nSunPos, float stepIndex, float rayStrength) {
	vec4 glowData = texture(glowParts, uv);
	float cloudEdgeSource = smoothstep(0.04, 0.42, glowData.a) * (1.0 - smoothstep(0.76, 1.0, glowData.a));
	float glowSample = glowData.g * 1.45 + cloudEdgeSource * rayStrength * 0.72;
	float mask = smoothstep(0.018, 0.42, glowSample);
	vec2 toSun = nSunPos - uv;
	float radial = 1.0 - smoothstep(0.05, 0.92, length(toSun));
	float breakup = sampleCloudBreakup(uv, nSunPos, stepIndex);
	float atmosphericBeam = radial * rayStrength * (0.16 + 0.34 * breakup);
	return max(mask, atmosphericBeam) * breakup;
}


vec2 clampDeltas(vec2 dtuv) {
	// When looking 90 degrees away from the sun, dTuv gets very large and causes significant frame drops.
	// I presume this is because the graphics card local texture cache is no longer effective due to the large uv coord jumps
	if (length(dtuv) > 0.005) {
		dtuv = normalize(dtuv) * 0.005;
	}
	
	return dtuv;
}

vec4 applyGodRays(in vec2 uv, in vec2 nSunPos) {
	// Sample weight. Decays as we radiate outwards.
	float radialDistance = length(uv - nSunPos);
	float screenFade = smoothstep(1.15, 0.12, radialDistance);
	float horizonFade = smoothstep(0.02, 0.18, nSunPos.y) * (1.0 - smoothstep(0.96, 1.0, nSunPos.y));
	float cloudVeil = sampleCloudBreakup(mix(uv, nSunPos, 0.35), nSunPos, 0.0);
	float rayStrength = smoothstep(0.05, 0.68, intensity) * horizonFade * (0.82 + cloudVeil * 0.28);
	if (rayStrength * screenFade <= 0.002) {
		return vec4(0.0);
	}
	
	float weight = rayStrength * screenFade / 30.0;
	
	int samples = int(mix(36.0, 84.0, rayStrength));
	
	// Short deltas near the sun
	vec2 sdTuv = clampDeltas((nSunPos - uv) * max(rayStrength, 0.08) / 220 * direction);
	
	// Large deltas far away from the sun where precision matters less and where is more important that the ray travels as far as possible
	vec2 ldTuv = clampDeltas((nSunPos - uv) * max(rayStrength, 0.08) / 84 * direction);
	
	vec2 dTuv = sdTuv;
	
	
	vec3 rayColor = getSunRayColor(nSunPos);
	float glow = sampleRayMask(uv, nSunPos, 0.0, rayStrength);
	vec4 col = vec4(texture(inputTexture, uv).rgb * glow * rayColor * 0.42, glow * 0.34);
    
    for (float i=0.0; i < samples; i++) {
		uv.x = clamp(uv.x + dTuv.x, 0, 1);
		uv.y = clamp(uv.y + dTuv.y, 0, 1);
        float mask = sampleRayMask(uv, nSunPos, i, rayStrength);
        vec3 sampleColor = texture(inputTexture, uv).rgb;
		float airSparkle = 0.92 + 0.08 * sin(i * 2.37 + iGlobalTime * 0.7);
		float mist = smoothstep(0.08, 0.75, i / max(float(samples), 1.0));
        col.rgb += mix(rayColor, sampleColor * rayColor, 0.14 + mist * 0.08) * mask * weight * airSparkle * 1.34;
        col.a += mask * weight * 1.30;
        weight *= decay;
		
		dTuv = mix(sdTuv, ldTuv, i/samples);
    }
	
	// Seems to greatly reduce the sun turning into one massive white blob
	float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb *= 1.0 - smoothstep(0.58, 1.16, luma) * 0.24;
	col.rgb = min(col.rgb, vec3(0.72));
	
	col.a = min(1.0, col.a);
	
    return col;
}


void main(void) {
	vec2 nSunPos = (clamp(sunPosScreen.xy, -10, 10) + 1) / 2;	
	outColor = applyGodRays(texCoord, nSunPos);	
	
	outColor.a=1;
}
