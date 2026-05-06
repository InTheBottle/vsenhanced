#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPositionIn;
layout(location = 1) in vec2 uvIn;
layout(location = 2) in vec4 colorIn;
layout(location = 3) in int flags;
#if defined(GLOWSUB)
layout(location = 4) in float glowSub;
#endif

uniform vec4 rgbaTint;
uniform vec3 rgbaAmbientIn;
uniform vec4 rgbaLightIn;
uniform vec4 rgbaGlowIn;
uniform vec4 rgbaFogIn;
uniform int extraGlow;
uniform float fogMinIn;
uniform float fogDensityIn;

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat4 modelMatrix;

uniform int dontWarpVertices;
uniform int fadeFromSpheresFog;
uniform int addRenderFlags;
uniform float extraZOffset;

out vec2 uv;
out vec4 color;
out vec4 rgbaFog;
out vec4 rgbaGlow;
out float fogAmount;
out vec4 camPos;
out vec4 worldPos;
flat out int renderFlags;

out vec3 normal;
#if SSAOLEVEL > 0
out vec4 gnormal;
#endif


#include vertexflagbits.ash
#include shadowcoords.vsh
#include fogandlight.vsh
#include vertexwarp.vsh

void main(void)
{
	worldPos = modelMatrix * vec4(vertexPositionIn, 1.0);
	
	if (dontWarpVertices == 0) {
		worldPos = applyVertexWarping(flags | addRenderFlags, worldPos);
		worldPos = applyGlobalWarping(worldPos);
	}
	if (dontWarpVertices == 2) {
		int windMode = ((flags | addRenderFlags) >> WindModePosition) & 0xF;
		vec4 newPos = applyVertexWarping(flags | addRenderFlags, worldPos);
		worldPos = mix(worldPos, newPos, 0.25); // Hardcoded intensity downscale of 4x
		worldPos = applyGlobalWarping(worldPos);
	}
	
	camPos = viewMatrix * worldPos;
	
	uv = uvIn;
	
	float gs = 0.0;
#if defined(GLOWSUB)
	gs = glowSub;
#endif

	int glow = clamp(extraGlow + (flags & GlowLevelBitMask) - int(gs * 255), 0, 255);
	
	renderFlags = glow | (flags & ~GlowLevelBitMask);
	rgbaGlow.rgb = rgbaGlowIn.rgb * max(vec3(0), (1 - vec3(3*gs)));
	rgbaGlow.a = rgbaGlowIn.a;
	
	color = rgbaTint * applyLight(rgbaAmbientIn, rgbaLightIn, renderFlags, camPos) * colorIn;
#if defined(GLOWSUB)
	color.rgb *= 1 - 0.5 * gs;
	color.rgb = mix(color.rgb, rgbaGlow.rgb, max(0, glowLevel - gs) / 2);
#endif	
	

	if (fadeFromSpheresFog > 0) {
		color.a *= clamp(1 - getSpheresFogAmount(vertexPositionIn * 10), 0, 1);
	}

	// Distance fade out
	color.a *= clamp(20 * (1.10 - length(worldPos.xz) / viewDistance) - 5, -1, 1);

	rgbaFog = rgbaFogIn;
	gl_Position = projectionMatrix * camPos;
	calcShadowMapCoords(viewMatrix, worldPos);
	
	fogAmount = getFogLevel(worldPos, fogMinIn, fogDensityIn);
	
	gl_Position.w += extraZOffset;
	
	normal = unpackNormal(flags);
	normal = normalize((modelMatrix * vec4(normal.x, normal.y, normal.z, 0)).xyz);
	
	#if SSAOLEVEL > 0
		gnormal = viewMatrix * vec4(normal, 0);
	#endif
}