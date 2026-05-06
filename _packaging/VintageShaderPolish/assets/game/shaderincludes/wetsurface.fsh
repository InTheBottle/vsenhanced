uniform float dropletIntensity = 0.0;

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
