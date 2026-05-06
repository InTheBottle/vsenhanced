#version 330 core

uniform vec2 invFrameSizeIn;
uniform vec3 sunPosScreenIn;
uniform vec3 sunPos3dIn;
uniform vec3 playerViewVector;
uniform float iGlobalTimeIn;
uniform float directionIn;
uniform int dusk;
uniform float moonLightStrength;
uniform float sunLightStrength;
uniform float dayLightStrength;
uniform float shadowIntensity;
uniform float flatFogDensity;
uniform float playerWaterDepth;
uniform vec4 fogColor;

out vec2 texCoord;
out vec3 sunPosScreen;
out float iGlobalTime;
out float direction;
out vec3 frontColor;
out vec3 backColor;

const float NumDayColors = 5.0;
const vec3 DayColors[5] = vec3[5](
	vec3(1.0, 0.24, 0.05),
	vec3(1.0, 0.58, 0.22),
	vec3(0.92, 0.84, 0.70),
	vec3(0.68, 0.82, 1.0),
	vec3(0.46, 0.64, 1.0)
);

void main(void)
{
	float x = -1.0 + float((gl_VertexID & 1) << 2);
	float y = -1.0 + float((gl_VertexID & 2) << 1);
	gl_Position = vec4(x, y, 0, 1);
	texCoord = vec2((x + 1.0) * 0.5, (y + 1.0) * 0.5);

	// When the sun is below the horizon, anchor the rays on the moon instead.
	// VS doesn't expose a separate moon screen position to this pass, but the
	// moon is roughly antipodal to the sun on the celestial sphere, so the
	// negation of sunPos3d/sunPosScreen is a serviceable approximation.
	bool isNight = sunPos3dIn.y < 0.0;
	vec3 lightPos3d = isNight ? -sunPos3dIn : sunPos3dIn;
	vec3 lightPosScreenLocal = isNight ? -sunPosScreenIn : sunPosScreenIn;

	sunPosScreen = lightPosScreenLocal;
	iGlobalTime = iGlobalTimeIn;
	direction = dot(lightPos3d, playerViewVector) >= 0.0 ? 1.0 : -1.0;

	vec3 moonColor = vec3(0.32, 0.46, 0.78) * moonLightStrength * 1.30;
	float height = pow(clamp(lightPos3d.y * 1.55, 0.0, 1.0), 2.35);
	float actualScale = height * NumDayColors;
	float cmpH = min(floor(actualScale), NumDayColors - 1.0);
	float cmpH1 = min(floor(actualScale) + 1.0, NumDayColors - 1.0);
	vec3 sunlight = mix(DayColors[int(cmpH)], DayColors[int(cmpH1)], fract(actualScale));
	float rayIntensity = clamp(pow(max(shadowIntensity, 0.18), 1.65), 0.10, 1.0) * 1.25;
	vec3 sunColor = sunlight * rayIntensity * max(sunLightStrength, dayLightStrength * 0.35);
	vec3 sunBackColor = mix(vec3(0.95, 0.12, 0.20), vec3(0.42, 0.62, 1.0), clamp(height * 5.0, 0.0, 1.0)) * rayIntensity;

	vec3 outFront = moonColor;
	vec3 outBack = moonColor * 0.72;
	if (sunLightStrength > 0.15) {
		outFront = sunColor;
		outBack = sunBackColor;
	} else if (sunLightStrength > 0.05) {
		float mixStrength = (sunLightStrength - 0.05) / 0.10;
		outFront = mix(moonColor, sunColor, mixStrength);
		outBack = mix(moonColor * 0.72, sunBackColor, mixStrength);
	}

	float depthMult = clamp(playerWaterDepth * 5.0, 0.0, 1.0);
	outFront = mix(outFront, fogColor.xyz, depthMult);
	outBack = mix(outBack, fogColor.xyz, depthMult);

	float fogDensity = clamp((0.032 - flatFogDensity) * 45.0, 0.0, 1.0);
	frontColor = outFront * fogDensity;
	backColor = outBack * fogDensity;
}
