#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) in vec3 xyz;
layout(location = 1) in vec2 uvIn;
layout(location = 2) in vec4 rgbaLightIn;
layout(location = 3) in int renderFlags;
layout(location = 4) in vec2 flowVector;
layout(location = 5) in int colormapData;
layout(location = 6) in int waterFlagsIn;

uniform vec3 origin;
uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;
uniform float viewDistance;

#include vertexflagbits.ash
#include vertexwarp.vsh


void main(void)
{
	vec4 worldPos = vec4(xyz + origin, 1.0);
	
	float div = ((waterFlagsIn & LiquidWeakWaveBitMask) > 0) ? 90 : 5;
	
	float oceanity = ((waterFlagsIn >> 2) & 0xff) / 255.0;
	div *= max(0.2, 1 - oceanity);

	if ((waterFlagsIn & 1) == 1) {
		worldPos = applyLiquidWarping((waterFlagsIn & LiquidIsLavaBitMask) == 0, worldPos, div);
	}
		
	vec4 cameraPos = modelViewMatrix * worldPos;
	
	gl_Position = projectionMatrix * cameraPos;
	
	// Distance fade out
	float a = length(worldPos.xz) / viewDistance;
	gl_Position.w -= max(0.0, (a-0.75)*5);
}