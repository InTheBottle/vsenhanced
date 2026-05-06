#version 330 core

uniform sampler2D inputTexture;
uniform sampler2D glowParts;
uniform sampler2D realCloudShadowMap;
uniform float realCloudShadowMapWidth;
uniform vec3 realCloudShadowOffset;
uniform float realCloudShadowStrength;
uniform vec3 realCloudShadowLightDir;
uniform float realCloudShadowDaylight;
uniform float realMoonLightStrength;
uniform vec3 sunPos3dIn;
uniform mat4 invProjectionMatrix;
uniform mat4 invModelViewMatrix;


in vec2 texCoord;
in vec3 sunPosScreen;
in float iGlobalTime;
in float intensity;
in float direction;

out vec4 outColor;

const float cloudTileSize = 50.0;
const vec2 cloudLayerBounds = vec2(-62.5, 512.5);

vec3 getSunRayColor() {
	float sunHeight = clamp(realCloudShadowLightDir.y, 0.0, 1.0);
	float horizonWarmth = 1.0 - smoothstep(0.28, 0.68, sunHeight);
	vec3 lowSun = vec3(1.0, 0.68, 0.42);
	vec3 highSun = vec3(1.0, 0.92, 0.74);
	vec3 sunColor = mix(highSun, lowSun, horizonWarmth);
	vec3 moonColor = vec3(0.58, 0.66, 0.88);
	float moonBlend = smoothstep(-1.0, -0.15, -direction);
	return mix(sunColor, moonColor, moonBlend * 0.72);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 getCameraWorldPosition() {
	return (invModelViewMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

vec3 getWorldRay(vec2 uv) {
	vec4 viewPos = invProjectionMatrix * vec4(uv * 2.0 - 1.0, -1.0, 1.0);
	if (abs(viewPos.w) > 0.000001) {
		viewPos.xyz /= viewPos.w;
	}
	viewPos.w = 0.0;
	return normalize((invModelViewMatrix * viewPos).xyz);
}

vec2 intersectCloudLayer(float originY, float dirY) {
	if (abs(dirY) < 0.0001) return vec2(-1.0);
	vec2 t = (cloudLayerBounds - originY) / dirY;
	float nearT = min(t.x, t.y);
	float farT = max(t.x, t.y);
	if (farT < 0.0) return vec2(-1.0);
	return vec2(max(nearT, 0.0), farT - max(nearT, 0.0));
}

float sampleCloudVolume(vec3 worldPos) {
	if (realCloudShadowMapWidth <= 1.0) return 0.0;

	vec3 local = worldPos;
	local.y -= realCloudShadowOffset.y;
	local.xz -= realCloudShadowOffset.xz;
	local /= cloudTileSize;
	vec2 mapPos = local.xz + realCloudShadowMapWidth * 0.5;
	vec2 mapUv = mapPos / realCloudShadowMapWidth;
	if (mapUv.x <= 0.001 || mapUv.y <= 0.001 || mapUv.x >= 0.999 || mapUv.y >= 0.999) return 0.0;

	vec4 map = clamp(texture(realCloudShadowMap, mapUv), vec4(0.0), vec4(1.0));
	float density = smoothstep(0.14, 0.70, map.r);
	vec2 bounds = vec2(min(map.b, map.a), max(map.b, map.a));
	float vertical = smoothstep(bounds.x - 0.12, bounds.x + 0.22, local.y) *
		(1.0 - smoothstep(bounds.y - 0.22, bounds.y + 0.12, local.y));
	return clamp(density * vertical, 0.0, 1.0);
}

float traceLightVisibility(vec3 worldPos, vec3 lightDir) {
	float occlusion = 0.0;
	float jitter = hash12(gl_FragCoord.xy + worldPos.xz * 0.013);

	for (int i = 0; i < 7; i++) {
		float fi = float(i) + jitter;
		vec3 samplePos = worldPos + lightDir * (fi * 58.0 + 18.0);
		float density = sampleCloudVolume(samplePos);
		occlusion += (1.0 - occlusion) * density * 0.34;
		if (occlusion > 0.92) break;
	}
	
	return clamp(1.0 - occlusion, 0.0, 1.0);
}

float visibilityEdge(vec3 worldPos, vec3 lightDir, vec3 sideDir) {
	float center = traceLightVisibility(worldPos, lightDir);
	float sideA = traceLightVisibility(worldPos + sideDir * 42.0, lightDir);
	float sideB = traceLightVisibility(worldPos - sideDir * 42.0, lightDir);
	float gradient = abs(center - sideA) + abs(center - sideB);
	return clamp(center * 0.30 + gradient * 1.75 + center * (1.0 - center) * 1.15, 0.0, 1.0);
}

vec4 applyGodRays(in vec2 uv) {
	float celestial = clamp(realCloudShadowDaylight + realMoonLightStrength * 0.70, 0.0, 1.0);
	float rayStrength = smoothstep(0.025, 0.38, intensity) * celestial;
	if (rayStrength <= 0.002 || realCloudShadowMapWidth <= 1.0 || realCloudShadowStrength <= 0.01) {
		return vec4(0.0);
	}

	vec3 cameraWorld = getCameraWorldPosition();
	vec3 viewDir = getWorldRay(uv);
	vec3 lightDir = normalize(realCloudShadowLightDir);
	vec2 layer = intersectCloudLayer(cameraWorld.y - realCloudShadowOffset.y, viewDir.y);
	if (layer.x < 0.0 || layer.y <= 0.0) {
		return vec4(0.0);
	}

	float startT = max(20.0, layer.x - 280.0);
	float endT = min(layer.x + layer.y + 160.0, 1450.0);
	if (endT <= startT) return vec4(0.0);

	vec3 sideDir = cross(viewDir, vec3(0.0, 1.0, 0.0));
	if (dot(sideDir, sideDir) < 0.001) {
		sideDir = vec3(1.0, 0.0, 0.0);
	} else {
		sideDir = normalize(sideDir);
	}

	const int viewSamples = 12;
	float jitter = hash12(gl_FragCoord.xy + iGlobalTime);
	float stepLen = (endT - startT) / float(viewSamples);
	float phase = 0.66 + 0.34 * pow(max(0.0, dot(viewDir, lightDir)), 2.0);
	float transmittance = 1.0;
	float scatter = 0.0;
	
	for (int i = 0; i < viewSamples; i++) {
		float fi = float(i) + jitter;
		float t = startT + fi * stepLen;
		vec3 samplePos = cameraWorld + viewDir * t;
		float cloudDensity = sampleCloudVolume(samplePos);
		float airFade = smoothstep(startT, startT + stepLen * 2.0, t) * (1.0 - smoothstep(endT - stepLen, endT, t));
		float edgeLight = visibilityEdge(samplePos, lightDir, sideDir);
		float cloudEdge = cloudDensity * (1.0 - smoothstep(0.68, 1.0, cloudDensity));
		float airShaft = edgeLight * (0.16 + cloudEdge * 0.95);
		float contribution = airShaft * airFade * transmittance;
		scatter += contribution;
		transmittance *= exp(-cloudDensity * 0.18);
		if (transmittance < 0.08) break;
	}

	scatter = clamp(scatter / float(viewSamples) * rayStrength * phase * realCloudShadowStrength * 2.45, 0.0, 0.42);
	vec3 rayColor = getSunRayColor();
	vec3 color = rayColor * scatter;
	color *= 1.0 - smoothstep(0.22, 0.42, dot(color, vec3(0.299, 0.587, 0.114))) * 0.30;
	color = min(color, vec3(0.30));
	return vec4(color, 1.0);
}


void main(void) {
	outColor = applyGodRays(texCoord);
	
	outColor.a=1;
}
