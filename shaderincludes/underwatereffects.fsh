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

float causticFilament(vec2 p, float t) {
	float n1 = gnoise(vec3(p + vec2(t, -t * 0.74), t * 0.17));
	float n2 = gnoise(vec3(p * 1.71 + vec2(-t * 0.53, t * 0.91), t * 0.23));
	float n3 = gnoise(vec3(p * 2.83 + vec2(t * 0.19, t * 0.41), t * 0.11));
	float ridges = 1.0 - abs(n1 - n2);
	ridges *= 1.0 - abs(n2 - n3) * 0.72;
	return smoothstep(0.48, 0.92, pow(clamp(ridges, 0.0, 1.0), 10.0));
}

float getCausticLight(vec3 worldPos, float murkiness) {
	if (murkiness <= 0.001) return 0.0;
	
	vec2 p = worldPos.xz * 0.32;
	float t = windWaveCounter * 0.16;
	float depthFade = smoothstep(0.02, 0.18, murkiness) * (1.0 - smoothstep(0.76, 1.0, murkiness));
	float broad = causticFilament(p, t);
	float fine = causticFilament(p * 2.35 + vec2(11.7, -4.3), t * 1.28);
	float sparkle = pow(max(0.0, broad * 0.58 + fine * 0.34), 1.9);
	float daylightBoost = 0.16 + clamp(realCloudShadowDaylight, 0.0, 1.0) * 0.16;
	return sparkle * depthFade * daylightBoost;
}

vec3 applyUnderwaterEffects(vec3 color, float murkiness) {
	vec3 murkColor = waterMurkColor.rgb * 0.4;
	return mix(color.rgb, murkColor, murkiness);
}

vec3 applyUnderwaterEffectsAt(vec3 color, float murkiness, vec3 worldPos) {
	vec3 murkColor = waterMurkColor.rgb * 0.4;
	vec3 causticColor = mix(vec3(0.45, 0.72, 0.86), vec3(0.76, 0.86, 0.78), clamp(realCloudShadowDaylight, 0.0, 1.0) * 0.28);
	float waterShadow = smoothstep(0.18, 0.95, murkiness) * 0.18;
	vec3 shadedColor = mix(color.rgb, murkColor, murkiness) * (1.0 - waterShadow);
	return shadedColor + causticColor * getCausticLight(worldPos, murkiness);
}

vec4 applyWetSurface(vec4 texColor, vec3 normal, vec3 worldPos, float fogAmount, float glowLevel) {
	float upness = max(0.0, normal.y);
	float wetness = clamp(dropletIntensity * upness * (1.0 - fogAmount) * (1.0 - min(1.0, glowLevel)), 0.0, 1.0);
	if (wetness <= 0.001) return texColor;
	
	float breakup = 0.68 + 0.32 * gnoise(vec3(worldPos.x * 0.22, worldPos.z * 0.22, windWaveCounter * 0.15));
	float fine = smoothstep(0.58, 0.92, gnoise(vec3(worldPos.x * 1.9, worldPos.z * 1.9, windWaveCounter * 0.28)));
	float daylight = clamp(realCloudShadowDaylight, 0.0, 1.0);
	float shine = pow(max(0.0, dot(normalize(normal), lightPosition)), 14.0) * shadowIntensity * (0.35 + daylight * 0.65);
	vec3 wetTint = mix(texColor.rgb * vec3(0.70, 0.76, 0.82), waterMurkColor.rgb * 0.38, 0.16);
	vec3 glint = mix(vec3(0.14, 0.17, 0.19), vec3(0.55, 0.65, 0.75), daylight);
	texColor.rgb = mix(texColor.rgb, wetTint, wetness * breakup * 0.34);
	texColor.rgb += glint * wetness * (shine * 0.55 + fine * 0.045);
	
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
