#version 330 core

uniform sampler2D inputTexture;
uniform sampler2D glowParts;
uniform sampler2D realCloudShadowMap;

uniform vec3 sunPos3dIn;
uniform vec3 realCloudShadowLightDir;
uniform vec3 realCloudShadowOffset;
uniform vec3 realCameraWorldPos;
uniform float realCloudShadowMapWidth;
uniform float realCloudShadowStrength;
uniform float realCloudShadowDaylight;
uniform mat4 invProjectionMatrix;
uniform mat4 invModelViewMatrix;

in vec2 texCoord;
in vec3 sunPosScreen;
in float iGlobalTime;
in float direction;
in vec3 frontColor;
in vec3 backColor;

out vec4 outColor;

vec3 safeNormalize(vec3 v, vec3 fallback) {
	float len2 = dot(v, v);
	return len2 > 1e-6 ? v * inversesqrt(len2) : fallback;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sampleSunMask(vec2 uv) {
	float mask = texture(glowParts, clamp(uv, vec2(0.001), vec2(0.999))).g;
	return smoothstep(0.018, 0.30, mask);
}

vec2 clampRayStep(vec2 s) {
	float len = length(s);
	return len > 0.006 ? s * (0.006 / len) : s;
}

float hgPhase(float cosTheta, float g) {
	float gg = g * g;
	float denom = max(1.0 + gg - 2.0 * g * cosTheta, 1e-4);
	return (1.0 - gg) / (4.0 * 3.14159265 * pow(denom, 1.5));
}

// Project worldPos along sunDir onto a representative cloud-shadow plane and
// sample the cloud density texture. Mirrors the cloud-shadow lookup used by
// chunk* shaders but uses a lightweight single-tap projection so each godray
// step costs one texture fetch.
// Returns transmittance: 1.0 = sun fully visible, 0.0 = fully blocked.
float sampleCloudTransmittance(vec3 worldPos, vec3 sunDir) {
	if (realCloudShadowStrength <= 0.01 || realCloudShadowMapWidth <= 1.0) return 1.0;
	if (sunDir.y < 0.05) return 0.0;

	const float cloudShadowPlane = 60.0;
	const float cloudTileSize = 50.0;
	float relY = worldPos.y - realCloudShadowOffset.y;
	if (relY > cloudShadowPlane) return 1.0;
	float t = (cloudShadowPlane - relY) / sunDir.y;

	vec2 hitXz = worldPos.xz + sunDir.xz * t;
	vec2 mapPos = (hitXz - realCloudShadowOffset.xz) / cloudTileSize + realCloudShadowMapWidth * 0.5;
	vec2 uv = mapPos / realCloudShadowMapWidth;
	if (uv.x <= 0.001 || uv.y <= 0.001 || uv.x >= 0.999 || uv.y >= 0.999) return 1.0;

	float d = texture(realCloudShadowMap, uv).r;
	float occlusion = clamp(smoothstep(0.18, 0.74, d) * realCloudShadowStrength, 0.0, 1.0);
	return clamp(1.0 - occlusion, 0.0, 1.0);
}

void main(void) {
	// Reconstruct view-space position and world-space view direction for this pixel.
	vec4 ndc = vec4(texCoord * 2.0 - 1.0, -1.0, 1.0);
	vec4 viewPos = invProjectionMatrix * ndc;
	if (abs(viewPos.w) < 1e-6) {
		outColor = vec4(0.0, 0.0, 0.0, 1.0);
		return;
	}
	viewPos.xyz /= viewPos.w;
	vec4 worldDir4 = invModelViewMatrix * vec4(viewPos.xyz, 0.0);
	vec3 viewDirWorld = safeNormalize(worldDir4.xyz, vec3(0.0, 0.0, -1.0));
	vec3 sunDirWorld = safeNormalize(realCloudShadowLightDir, vec3(0.0, 1.0, 0.0));

	vec3 sunDir3d = safeNormalize(sunPos3dIn, vec3(0.0, 1.0, 0.0));
	float dp = dot(sunDir3d, safeNormalize(viewPos.xyz, vec3(0.0, 0.0, -1.0)));
	vec3 useColor = mix(backColor, frontColor, dp * 0.5 + 0.5);

	vec2 nSunPos = (clamp(sunPosScreen.xy, -10.0, 10.0) + 1.0) * 0.5;

	// Forward-scattering phase: rays glow brightest looking near the sun.
	float cosTheta = clamp(dot(viewDirWorld, sunDirWorld), -1.0, 1.0);
	float phase = hgPhase(cosTheta, 0.74);
	phase = max(phase, 0.06);

	const int samples = 28;
	const float decay = 0.965;
	const float marchNear = 12.0;
	const float marchFar = 240.0;

	vec2 step1 = clampRayStep((nSunPos - texCoord) * 0.022 * direction);
	vec2 step2 = clampRayStep((nSunPos - texCoord) * 0.062 * direction);

	float jitter = hash12(gl_FragCoord.xy + iGlobalTime * 31.0);
	vec2 rayUv = texCoord + step1 * (jitter - 0.5);

	float screenWeight = 0.038;
	float screenAccum = 0.0;
	float volAccum = 0.0;
	float transmittance = 1.0;

	// Combined march. The screen-space accumulator (rays around objects) walks
	// from this pixel toward the sun and reads glowParts; the volumetric
	// accumulator (rays through clouds) walks along this pixel's view ray in
	// world space and samples the cloud-shadow map projected onto the cloud
	// plane along the sun direction.
	for (int i = 0; i < samples; i++) {
		float ti = float(i) / float(samples - 1);
		rayUv += mix(step1, step2, ti);

		float mask = sampleSunMask(rayUv);
		screenAccum += mask * screenWeight;

		float worldT = mix(marchNear, marchFar, ti) + (jitter - 0.5) * 8.0;
		vec3 worldP = realCameraWorldPos + viewDirWorld * worldT;
		float cloudT = sampleCloudTransmittance(worldP, sunDirWorld);
		float distFalloff = exp(-worldT * 0.0035);
		volAccum += cloudT * transmittance * distFalloff * 0.045;
		transmittance *= 0.984;

		screenWeight *= decay;
	}

	volAccum *= phase * clamp(realCloudShadowDaylight, 0.0, 1.0);

	// Modulate volumetric by overall sun visibility so it fades when the disc
	// is below the horizon or buried behind a mountain.
	float sunDiscMask = sampleSunMask(nSunPos);
	float volumetricGate = clamp(sunDiscMask * 1.2 + screenAccum * 1.5, 0.0, 1.0);
	volAccum *= volumetricGate;

	float exposure = clamp(screenAccum + volAccum * 0.55, 0.0, 0.36);
	if (!(exposure >= 0.0)) exposure = 0.0;
	vec3 rays = min(useColor * exposure, vec3(0.32));
	outColor = vec4(rays, 1.0);
}
