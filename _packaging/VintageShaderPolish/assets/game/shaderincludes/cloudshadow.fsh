uniform sampler2D realCloudShadowMap;
uniform float realCloudShadowMapWidth;
uniform vec3 realCloudShadowOffset;
uniform float realCloudShadowStrength;

float getProceduralCloudShadow(vec3 worldPos, vec3 normal, float fogAmount) {
	float upness = clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
	float daylight = smoothstep(0.04, 0.32, lightPosition.y);
	float fogFade = 1.0 - smoothstep(0.45, 0.9, fogAmount);
	if (upness <= 0.05 || daylight <= 0.01 || fogFade <= 0.01) return 1.0;
	
	vec2 drift = vec2(windWaveCounter * 0.004, -windWaveCounter * 0.002);
	vec2 p = worldPos.xz * 0.0035 + drift;
	float broad = gnoise(vec3(p, 0.0)) * 0.5 + 0.5;
	float detail = gnoise(vec3(p * 2.3 + vec2(17.0, -9.0), 0.0)) * 0.5 + 0.5;
	float cloud = smoothstep(0.46, 0.72, broad * 0.78 + detail * 0.22);
	float strength = cloud * upness * daylight * fogFade * (0.55 + shadowIntensity * 0.45);
	
	return 1.0 - strength * 0.32;
}

float sampleRealCloudDensity(vec2 mapPos) {
	vec2 uv = mapPos / realCloudShadowMapWidth;
	if (uv.x <= 0.001 || uv.y <= 0.001 || uv.x >= 0.999 || uv.y >= 0.999) return 0.0;
	
	vec2 texel = vec2(1.0 / realCloudShadowMapWidth);
	float density = texture(realCloudShadowMap, uv).r * 0.42;
	density += texture(realCloudShadowMap, uv + texel * vec2( 1.5,  0.0)).r * 0.145;
	density += texture(realCloudShadowMap, uv + texel * vec2(-1.5,  0.0)).r * 0.145;
	density += texture(realCloudShadowMap, uv + texel * vec2( 0.0,  1.5)).r * 0.145;
	density += texture(realCloudShadowMap, uv + texel * vec2( 0.0, -1.5)).r * 0.145;
	return density;
}

float getCloudShadow(vec3 worldPos, vec3 normal, float fogAmount) {
	float upness = clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
	float daylight = smoothstep(0.04, 0.32, lightPosition.y);
	float fogFade = 1.0 - smoothstep(0.45, 0.9, fogAmount);
	if (upness <= 0.05 || daylight <= 0.01 || fogFade <= 0.01) return 1.0;
	
	if (realCloudShadowStrength <= 0.01 || realCloudShadowMapWidth <= 1.0) {
		return getProceduralCloudShadow(worldPos, normal, fogAmount);
	}
	
	float cloudTileSize = 50.0;
	float rayHeight = max(realCloudShadowOffset.y - worldPos.y, 0.0);
	vec2 projected = worldPos.xz + lightPosition.xz * (rayHeight / max(lightPosition.y, 0.08));
	vec2 mapPos = (projected - realCloudShadowOffset.xz) / cloudTileSize + realCloudShadowMapWidth * 0.5;
	float cloud = smoothstep(0.01, 0.32, sampleRealCloudDensity(mapPos));
	float strength = cloud * upness * daylight * fogFade * (0.55 + shadowIntensity * 0.45) * realCloudShadowStrength;
	
	return 1.0 - strength * 0.38;
}
