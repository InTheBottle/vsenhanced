uniform sampler2D liquidDepth;
uniform float cameraUnderwater;
uniform vec2 frameSize;
uniform vec4 waterMurkColor;
uniform float dropletIntensity = 0.0;
uniform sampler2D realCloudShadowMap;
uniform float realCloudShadowMapWidth;
uniform vec3 realCloudShadowOffset;
uniform float realCloudShadowStrength;
uniform vec3 realCloudShadowLightDir;
uniform float realCloudShadowDaylight;

float getSkyMurkiness() {
	if (cameraUnderwater > 0.7) {
		return 0.0;
	}
	
	// Smoother ocean edge
	float ldepth1 = linearDepth(texture(liquidDepth, gl_FragCoord.xy/frameSize.xy).r);
	float ldepth2 = linearDepth(texture(liquidDepth, (gl_FragCoord.xy + vec2(0,3))/frameSize.xy).r);
	float ldepth3 = linearDepth(texture(liquidDepth, (gl_FragCoord.xy + vec2(0,6))/frameSize.xy).r);
	
	return 1-(ldepth1+ldepth2+ldepth3)/3.0;
}

float getUnderwaterMurkiness() {
	if (cameraUnderwater > 0.7) {
		return 0.0;
	}

	// We render the liquid depth z-buffer at 1/4th the resolution. This seems to cause black lines near the shore line
	// when there is strong fog. Probably because of the harsh transition of fog level above vs below water
	// Seems to be fixable by either doing full resolution render or doing a second sample. Pretty sure 2 texture reads on a tiny texture is way faster
	// so lets do that.
	float ldepth = linearDepth(
		max(
			texture(liquidDepth, gl_FragCoord.xy/frameSize.xy).r,
			texture(liquidDepth, (gl_FragCoord.xy + vec2(0,3))/frameSize.xy).r
		)
	);
	
	float fdepth = linearDepth(gl_FragCoord.z);
	return clamp(max(0.0, fdepth - ldepth)*350.0, 0.0, 1.0);
}

float getCausticLight(vec3 worldPos, float murkiness) {
	if (murkiness <= 0.001) return 0.0;
	
	vec2 p = worldPos.xz * 0.14;
	float t = windWaveCounter * 0.16;
	float depthFade = smoothstep(0.01, 0.14, murkiness) * (1.0 - smoothstep(0.78, 1.0, murkiness));
	float c1 = gnoise(vec3(p.x + t, p.y - t * 0.7, worldPos.y * 0.015));
	float c2 = gnoise(vec3(p.x * 1.7 - t * 0.5, p.y * 1.4 + t, worldPos.y * 0.02 + t * 0.3));
	float caustic = smoothstep(0.62, 1.02, c1 + c2 + 0.55);
	return caustic * depthFade * 0.24;
}

vec3 applyUnderwaterEffects(vec3 color, float murkiness) {
	vec3 murkColor = waterMurkColor.rgb * 0.4;
	return mix(color.rgb, murkColor, murkiness);
}

vec3 applyUnderwaterEffectsAt(vec3 color, float murkiness, vec3 worldPos) {
	vec3 murkColor = waterMurkColor.rgb * 0.4;
	vec3 causticColor = mix(vec3(0.75, 0.9, 1.0), waterMurkColor.rgb, 0.35);
	float waterShadow = smoothstep(0.18, 0.95, murkiness) * 0.18;
	vec3 shadedColor = mix(color.rgb, murkColor, murkiness) * (1.0 - waterShadow);
	return shadedColor + causticColor * getCausticLight(worldPos, murkiness);
}

vec4 applyWetSurface(vec4 texColor, vec3 normal, vec3 worldPos, float fogAmount, float glowLevel) {
	float upness = max(0.0, normal.y);
	float wetness = clamp(dropletIntensity * upness * (1.0 - fogAmount) * (1.0 - min(1.0, glowLevel)), 0.0, 1.0);
	if (wetness <= 0.001) return texColor;
	
	float breakup = 0.75 + 0.25 * gnoise(vec3(worldPos.x * 0.22, worldPos.z * 0.22, windWaveCounter * 0.15));
	float shine = pow(max(0.0, dot(normalize(normal), lightPosition)), 12.0) * shadowIntensity;
	texColor.rgb *= 1.0 - wetness * breakup * 0.12;
	texColor.rgb += vec3(shine) * wetness * 0.12;
	
	return texColor;
}

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
