uniform sampler2D liquidDepth;
uniform float cameraUnderwater;
uniform vec2 frameSize;
uniform vec4 waterMurkColor;
uniform vec3 realCloudShadowLightDir;
uniform float realCloudShadowDaylight;
uniform float realMoonLightStrength;
uniform float dayLightStrength;

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
	float n1 = gnoise(vec3(p + vec2(t, -t * 0.72), t * 0.15));
	float n2 = gnoise(vec3(p * 1.74 + vec2(-t * 0.47, t * 0.84), t * 0.21));
	float ridges = 1.0 - abs(n1 - n2);
	ridges *= 0.82 + 0.18 * n1;
	return smoothstep(0.40, 0.90, pow(clamp(ridges, 0.0, 1.0), 7.0));
}

float getCausticLight(vec3 worldPos, float murkiness) {
	if (murkiness <= 0.001) return 0.0;

	vec2 p = worldPos.xz * 0.58;
	float t = windWaveCounter * 0.115;
	// Ramp up only; getUnderwaterMurkiness already saturates fast so any high-end fade kills caustics in real ponds.
	float depthFade = smoothstep(0.005, 0.10, murkiness);
	float broad = causticFilament(p, t);
	float fine = causticFilament(p * 2.15 + vec2(11.7, -4.3), t * 1.18);
	float sparkle = pow(max(0.0, broad * 0.55 + fine * 0.45), 1.7);
	float daylightBoost = 0.16 + clamp(realCloudShadowDaylight, 0.0, 1.0) * 0.45;
	return sparkle * depthFade * daylightBoost;
}

vec3 applyUnderwaterEffects(vec3 color, float murkiness) {
	vec3 murkColor = waterMurkColor.rgb * 0.4;
	return mix(color.rgb, murkColor, murkiness);
}

vec3 applyUnderwaterEffectsAt(vec3 color, float murkiness, vec3 worldPos) {
	vec3 murkColor = waterMurkColor.rgb * 0.4;
	vec3 causticColor = mix(vec3(0.65, 0.88, 1.00), vec3(0.94, 0.98, 0.85), clamp(realCloudShadowDaylight, 0.0, 1.0) * 0.4);
	float waterShadow = smoothstep(0.18, 0.95, murkiness) * 0.18;
	vec3 shadedColor = mix(color.rgb, murkColor, murkiness) * (1.0 - waterShadow);
	// Boost caustic visibility on the seabed; the surface caustic uses its own tame factor in chunkliquid.
	return shadedColor + causticColor * getCausticLight(worldPos, murkiness) * 1.6;
}

vec3 applyMoonDirectLight(vec3 color, vec3 normal, float fogAmount) {
	float moon = clamp(realMoonLightStrength, 0.0, 1.0);
	if (moon <= 0.001) return color;

	float upness = clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
	float ndl = max(0.0, dot(normalize(normal), normalize(realCloudShadowLightDir)));
	float direct = pow(ndl, 0.85) * upness * moon * (1.0 - smoothstep(0.38, 0.92, fogAmount));
	vec3 moonTint = vec3(0.46, 0.55, 0.78);
	return color + (color * moonTint * 0.22 + vec3(0.006, 0.009, 0.017)) * direct;
}

// Analytic hemispherical ambient: zenith/horizon/ground tint by face normal + day-night blend; cheap IBL proxy.
vec3 vspHemiAmbient(vec3 normal, float dayStrength) {
	float d = clamp(dayStrength, 0.0, 1.0);

	vec3 zenithDay = vec3(0.45, 0.62, 0.95);
	vec3 zenithNight = vec3(0.06, 0.10, 0.20);
	vec3 horizonDay = vec3(0.82, 0.88, 0.98);
	vec3 horizonNight = vec3(0.16, 0.20, 0.34);
	vec3 horizonTwilight = vec3(0.96, 0.55, 0.28);

	float twilight = smoothstep(0.02, 0.30, d) * (1.0 - smoothstep(0.30, 0.75, d));

	vec3 zenith = mix(zenithNight, zenithDay, d);
	vec3 horizon = mix(horizonNight, horizonDay, d);
	horizon = mix(horizon, horizonTwilight, twilight * 0.65);

	float upness = clamp(normal.y, -1.0, 1.0);
	vec3 sky = mix(horizon, zenith, smoothstep(0.0, 0.7, upness));
	vec3 ground = horizon * vec3(0.50, 0.55, 0.42);
	return upness > 0.0 ? sky : mix(horizon, ground, -upness);
}

// Subtle multiplicative tint so engine ambient/sky-light remains dominant.
vec3 applyHemisphericalAmbient(vec3 color, vec3 normal, float dayStrength, float strength) {
	vec3 envColor = vspHemiAmbient(normal, dayStrength);
	return color * mix(vec3(1.0), envColor, strength);
}

// Amplify color saturation of nearby block-light sources so torches/lava/forges visibly tint surfaces.
vec3 applyEmissiveBounce(vec3 color, vec3 blockLight, float strength) {
	float intensity = max(max(blockLight.r, blockLight.g), blockLight.b);
	if (intensity < 0.05) return color;
	vec3 chroma = blockLight / max(intensity, 0.001);
	return color + color * (chroma - vec3(0.85)) * intensity * strength;
}

// Increase contrast between lit/unlit pixels to deepen crevices and corners (cheap fake-AO).
vec3 applyContactDarken(vec3 color, float strength) {
	float lumi = dot(color, vec3(0.299, 0.587, 0.114));
	float darken = 1.0 - smoothstep(0.0, 0.30, 1.0 - lumi) * strength;
	return color * darken;
}

float vspVolumetricJitter(vec2 p) {
	return fract(0.75487765 * p.x + 0.56984026 * p.y);
}

float vspVolumetricPhase(float cosTheta) {
	return 0.58 + 0.08 * cosTheta * cosTheta;
}

float calculateVspVolumetricScatter(vec3 viewPos, vec3 normal, float fogAmount) {
#if GODRAYS > 0 && SHADOWQUALITY > 0
	if (sunlightLevel < 0.002 || fogAmount > 0.96) {
		return 0.0;
	}
	if (shadowRayStart.w <= 0.0001 || shadowCoordsFar.w <= 0.0001 || shadowCoordsFar.z >= 0.999 ||
		shadowCoordsFar.x <= 0.02 || shadowCoordsFar.x >= 0.98 ||
		shadowCoordsFar.y <= 0.02 || shadowCoordsFar.y >= 0.98) {
		return 0.0;
	}

	const int maxSamples = 5;
	vec3 dV = (shadowCoordsFar.xyz - shadowRayStart.xyz) / float(maxSamples);
	float rayStepLength = length(dV);
	if (rayStepLength < 0.00001) {
		return 0.0;
	}

	float viewDistance = length(viewPos);
	if (viewDistance < 7.0) {
		return 0.0;
	}

	vec3 progress = shadowRayStart.xyz + dV * vspVolumetricJitter(gl_FragCoord.xy);
	float segmentDepth = clamp(viewDistance / 820.0 / float(maxSamples), 0.018, 0.26);
	float stepScatter = 1.0 - exp(-segmentDepth);
	float stepTransmittance = exp(-segmentDepth);
	float transmittance = 1.0;
	float scattered = 0.0;

	for (int i = 0; i < maxSamples; i++) {
		float inLight = texture(shadowMapFar, vec3(progress.xy, progress.z - 0.0009));
		scattered += inLight * stepScatter * transmittance;
		transmittance *= stepTransmittance;
		if (transmittance < 0.035) break;
		progress += dV;
	}

	float normalOut = clamp(scattered * 2.8, 0.0, 1.0);
	float shadowLightLen = max(length(shadowLightPos.xyz), 0.00001);
	float phase = vspVolumetricPhase(dot(dV / rayStepLength, shadowLightPos.xyz / shadowLightLen));
	float daylight = clamp(realCloudShadowDaylight + realMoonLightStrength * 0.55, 0.0, 1.0);
	float fogGate = 1.0 - smoothstep(0.58, 0.98, fogAmount);
	float shaped = clamp(normalOut * phase * daylight * fogGate, 0.0, 1.0);
	return min(0.58, pow(shaped, 0.82) * 0.52);
#endif
	return 0.0;
}

// Driven by VSEssentials.WeatherSystemClient.PrecIntensity via mod patch.
uniform float precIntensity;
vec4 applyWetSurface(vec4 texColor, vec3 normal, vec3 worldPos, float fogAmount, float glowLevel) {
	if (precIntensity < 0.01) return texColor;

	float upness = pow(clamp(normal.y, 0.0, 1.0), 1.4);
	float exposed = 1.0 - smoothstep(0.05, 0.40, glowLevel);

	vec3 hashIn = floor(worldPos * 0.18);
	float wetMask = fract(sin(dot(hashIn, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	wetMask = mix(0.55, 1.0, wetMask);

	float wet = clamp(precIntensity, 0.0, 1.0) * upness * exposed * wetMask;
	wet *= (1.0 - fogAmount);

	vec3 darken = mix(vec3(1.0), vec3(0.55, 0.58, 0.66), wet);
	vec3 wetCol = texColor.rgb * darken;
	float luma = dot(wetCol, vec3(0.299, 0.587, 0.114));
	wetCol = mix(vec3(luma), wetCol, mix(1.0, 1.18, wet));

	texColor.rgb = mix(texColor.rgb, wetCol, wet);
	return texColor;
}

float getProceduralCloudShadow(vec3 worldPos, vec3 normal, float fogAmount) {
	float upness = clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
	float daylight = smoothstep(0.04, 0.32, lightPosition.y);
	float fogFade = 1.0 - smoothstep(0.94, 0.995, fogAmount);
	if (upness <= 0.05 || daylight <= 0.01 || fogFade <= 0.01) return 1.0;
	
	vec2 drift = vec2(windWaveCounter * 0.004, -windWaveCounter * 0.002);
	vec2 p = worldPos.xz * 0.0035 + drift;
	float broad = gnoise(vec3(p, 0.0)) * 0.5 + 0.5;
	float detail = gnoise(vec3(p * 2.3 + vec2(17.0, -9.0), 0.0)) * 0.5 + 0.5;
	float cloud = smoothstep(0.46, 0.72, broad * 0.78 + detail * 0.22);
	float strength = cloud * upness * daylight * fogFade * (0.55 + shadowIntensity * 0.45);
	
	return 1.0 - strength * 0.32;
}

// Underwater/caustic cloud shadow; always procedural - engine cloud map drifted with the player.
float getCloudShadow(vec3 worldPos, vec3 normal, float fogAmount) {
	return getProceduralCloudShadow(worldPos, normal, fogAmount);
}
