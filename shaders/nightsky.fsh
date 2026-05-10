#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

in vec3 texCoords;
in float worldPosY;
in float nightVisionStrengthv;

uniform vec4 rgbaFog;
uniform samplerCube ctex;
uniform int ditherSeed;
uniform int horizontalResolution;
uniform float dayLight;
uniform float horizonFog;
uniform float playerToSealevelOffset;
uniform float fogDensityIn;
uniform float fogMinIn;


out vec4 outColor;
#if SSAOLEVEL > 0
layout(location = 2) out vec4 outGNormal;
layout(location = 3) out vec4 outGPosition;
#endif


#include dither.fsh
#include fogandlight.fsh
#include underwatereffects.fsh

void main () {
	vec4 skyCol = texture (ctex, texCoords) + NoiseFromPixelPosition(ivec2(gl_FragCoord.xy), 37, horizontalResolution) * 0.10;
	skyCol -= 0.03f;
	skyCol.rgb *= 2;

	vec3 skyDir = normalize(texCoords);
	float horizonExtinction = 1.0 - smoothstep(-0.04, 0.32, skyDir.y + playerToSealevelOffset * 0.0004);
	// Wider mask threshold so faint stars register; brighter starMask
	// boost so identified star pixels pop without lifting the dark sky.
	float starMask = smoothstep(0.14, 0.55, max(max(skyCol.r, skyCol.g), skyCol.b));
	float twinkle = NoiseFromPixelPosition(ivec2(gl_FragCoord.xy), 41, horizontalResolution).x;
	skyCol.rgb *= 1.0 - horizonExtinction * (0.35 + 0.2 * horizonFog);
	// Strong star multiplier: starMask gates this so only star pixels get
	// brightened; (0.75 + twinkle*0.45) gives twinkling 75%-120% extra.
	skyCol.rgb += skyCol.rgb * starMask * (0.75 + twinkle * 0.45) * (1.0 - horizonExtinction);
	float nightFactor = 1.0 - smoothstep(0.06, 0.32, dayLight);
	skyCol.rgb += vec3(0.018, 0.025, 0.052) * nightFactor * (1.0 - horizonExtinction * 0.55);
	skyCol.a = max(0.0, 1 - 2*(dayLight - 0.05));
	
	outColor = skyCol;
	outColor.rgb += vec3(0.1, 0.5, 0.1) * nightVisionStrengthv;

	float murkiness=getSkyMurkiness();
	outColor.rgb = applyUnderwaterEffects(outColor.rgb, murkiness);

#if SSAOLEVEL > 0
	outGPosition = vec4(0);
	outGNormal = vec4(0);
#endif

}
