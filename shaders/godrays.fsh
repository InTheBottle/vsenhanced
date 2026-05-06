#version 330 core

uniform sampler2D inputTexture;
uniform sampler2D glowParts;
uniform vec3 sunPos3dIn;
uniform mat4 invProjectionMatrix;
uniform mat4 invModelViewMatrix;

in vec2 texCoord;
in vec3 sunPosScreen;
in float iGlobalTime;
in float direction;
in vec3 frontColor;
in vec3 backColor;

out vec4 outColor;

vec3 safeNormalize(vec3 value, vec3 fallback) {
	float len2 = dot(value, value);
	return len2 > 0.000001 ? value * inversesqrt(len2) : fallback;
}

float sampleGodrayMask(vec2 uv) {
	float mask = texture(glowParts, clamp(uv, vec2(0.001), vec2(0.999))).g;
	return smoothstep(0.018, 0.30, mask);
}

vec2 clampRayStep(vec2 stepUv) {
	float len = length(stepUv);
	return len > 0.006 ? stepUv * (0.006 / len) : stepUv;
}

float rayJitter(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec4 applyVolumetricLighting(vec3 color, vec2 uv, vec2 nSunPos) {
	const int samples = 34;
	const float decay = 0.966;
	vec2 shortStep = clampRayStep((nSunPos - uv) * 0.018 * direction);
	vec2 longStep = clampRayStep((nSunPos - uv) * 0.058 * direction);
	float weight = 0.052;
	float exposure = sampleGodrayMask(uv) * 0.035;

	vec2 rayUv = uv + shortStep * (rayJitter(gl_FragCoord.xy + iGlobalTime) - 0.5);
	for (int i = 0; i < samples; i++) {
		float t = float(i) / float(samples - 1);
		rayUv += mix(shortStep, longStep, t);
		exposure += sampleGodrayMask(rayUv) * weight;
		weight *= decay;
	}

	exposure = clamp(exposure, 0.0, 0.24);
	vec3 rays = min(color * exposure, vec3(0.24));
	return vec4(rays, 1.0);
}

void main(void) {
	vec4 proCoord = invProjectionMatrix * vec4(texCoord * 2.0 - 1.0, -1.0, 1.0);
	if (abs(proCoord.w) < 0.000001) {
		outColor = vec4(0.0, 0.0, 0.0, 1.0);
		return;
	}

	proCoord.xyz /= proCoord.w;
	proCoord.w = 0.0;
	proCoord = invModelViewMatrix * proCoord;

	float dp = dot(safeNormalize(sunPos3dIn, vec3(0.0, 1.0, 0.0)), safeNormalize(proCoord.xyz, vec3(0.0, 0.0, -1.0)));
	vec3 useColor = mix(backColor, frontColor, dp * 0.5 + 0.5);
	vec2 nSunPos = (clamp(sunPosScreen.xy, -10.0, 10.0) + 1.0) * 0.5;
	outColor = applyVolumetricLighting(useColor, texCoord, nSunPos);
}
