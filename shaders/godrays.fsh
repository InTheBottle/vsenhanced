#version 330 core

uniform sampler2D glowParts;
uniform sampler2D inputTexture;
uniform vec3 sunPos3dIn;
uniform mat4 invProjectionMatrix;
uniform mat4 invModelViewMatrix;

in vec2 texCoord;
in vec3 frontColor;
in vec3 backColor;

out vec4 outColor;

vec3 safeNormalize(vec3 value, vec3 fallback) {
	float len2 = dot(value, value);
	return len2 > 0.000001 ? value * inversesqrt(len2) : fallback;
}

vec3 getViewDirection(vec2 uv) {
	vec4 viewPos = invProjectionMatrix * vec4(uv * 2.0 - 1.0, -1.0, 1.0);
	if (abs(viewPos.w) > 0.000001) {
		viewPos.xyz /= viewPos.w;
	}
	return safeNormalize((invModelViewMatrix * vec4(viewPos.xyz, 0.0)).xyz, vec3(0.0, 0.0, -1.0));
}

float phaseFunction(float cosTheta) {
	float forward = clamp(cosTheta * 0.5 + 0.5, 0.0, 1.0);
	float broad = 0.42 + 0.18 * cosTheta * cosTheta;
	float forwardLobe = pow(forward, 2.2) * 0.55;
	return broad + forwardLobe;
}

float sampleScatter(vec2 uv) {
	return max(texture(glowParts, clamp(uv, vec2(0.001), vec2(0.999))).g, 0.0);
}

float resolveScatter(vec2 uv) {
	vec2 px = 1.0 / vec2(textureSize(glowParts, 0));
	float scatter = sampleScatter(uv) * 0.36;
	scatter += sampleScatter(uv + vec2( px.x,  0.0)) * 0.13;
	scatter += sampleScatter(uv + vec2(-px.x,  0.0)) * 0.13;
	scatter += sampleScatter(uv + vec2( 0.0,  px.y)) * 0.13;
	scatter += sampleScatter(uv + vec2( 0.0, -px.y)) * 0.13;
	scatter += sampleScatter(uv + vec2( px.x,  px.y)) * 0.03;
	scatter += sampleScatter(uv + vec2(-px.x,  px.y)) * 0.03;
	scatter += sampleScatter(uv + vec2( px.x, -px.y)) * 0.03;
	scatter += sampleScatter(uv + vec2(-px.x, -px.y)) * 0.03;
	return scatter;
}

void main(void) {
	vec3 viewDir = getViewDirection(texCoord);
	vec3 lightDir = safeNormalize(sunPos3dIn, vec3(0.0, 1.0, 0.0));
	float cosTheta = clamp(dot(viewDir, lightDir), -1.0, 1.0);
	float phase = phaseFunction(cosTheta);

	float scatter = resolveScatter(texCoord);
	scatter = smoothstep(0.025, 0.20, scatter);
	scatter = pow(clamp(scatter, 0.0, 1.0), 1.18);

	vec3 rayColor = mix(backColor, frontColor, cosTheta * 0.5 + 0.5);
	vec3 rays = rayColor * scatter * phase * 0.58;
	rays += texture(inputTexture, texCoord).rgb * 0.000001;
	outColor = vec4(min(rays, vec3(0.26)), 1.0);
}
