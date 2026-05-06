#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 vertexPositionIn;
layout(location = 1) in vec2 uvIn;
layout(location = 2) in vec4 colorIn;
layout(location = 3) in float xposIn;

uniform vec4 color;

uniform vec4 rgbaTint;
uniform vec3 rgbaAmbientIn;
uniform vec4 rgbaLightIn;
uniform vec4 rgbaBlockIn;
uniform vec4 rgbaFogIn;

uniform float fogMinIn;
uniform float fogDensityIn;

uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;


uniform float auroraCounter;

out vec2 uv;
out vec4 col;
out vec4 rgbaFog;
out float fogAmount;
out vec4 vexPos;
out float xpos;

flat out int renderFlags;

#if SHADOWQUALITY > 0
out vec4 shadowCoordsFar;
#endif
#if SHADOWQUALITY > 1
out vec4 shadowCoordsNear;
#endif

#include vertexflagbits.ash
#include fogandlight.vsh
#include noise3d.ash

void main(void)
{
	vexPos = vec4(vertexPositionIn, 1.0);
	
	vexPos.x += 100*cnoise(vec3((vexPos.x)/100.0, (vexPos.z)/500.0, auroraCounter/3));
	vexPos.z += 100*cnoise(vec3((vexPos.x)/120.0, (vexPos.z)/300.0, auroraCounter/3));

	vec4 camPos = modelViewMatrix * vexPos;
	
	uv = uvIn;
	xpos = xposIn;
	col = color;
	rgbaFog = rgbaFogIn;	
	
	gl_Position = projectionMatrix * camPos;
		
	fogAmount = getFogLevel(vec4(vertexPositionIn, 1), fogMinIn, fogDensityIn);
}