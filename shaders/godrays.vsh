#version 330 core

uniform vec2 invFrameSizeIn;
uniform vec3 sunPosScreenIn;
uniform vec3 sunPos3dIn;
uniform vec3 playerViewVector;
uniform float iGlobalTimeIn;
uniform float directionIn;
uniform int dusk;

out vec2 texCoord;
out vec3 sunPosScreen;
out float iGlobalTime;
out float intensity;
out float direction;

void main(void)
{
	// https://randallr.wordpress.com/2014/06/14/rendering-a-screen-covering-triangle-in-opengl
	float x = -1.0 + float((gl_VertexID & 1) << 2);
    float y = -1.0 + float((gl_VertexID & 2) << 1);
    gl_Position = vec4(x, y, 0, 1);
    texCoord = vec2((x+1.0) * 0.5, (y + 1.0) * 0.5);
	
	sunPosScreen = sunPosScreenIn;
	iGlobalTime = iGlobalTimeIn;
	
	direction = directionIn;
	
	// https://www.toolfk.com/online-plotter-frame/#W3sidHlwZSI6MCwiZXEiOiJtYXgoMSwxLjc1KigxLTYqYWJzKHgtMC4yMikpKSIsImNvbG9yIjoiIzAwMDAwMCJ9LHsidHlwZSI6MTAwMCwid2luZG93IjpbIi0xIiwiMSIsIjAiLCIyIl19XQ--
	float dawnMul = max(1.0, (1.0 - dusk) * 2.0 * (1.0 - 6.0 * abs(sunPos3dIn.y - 0.1)));
	float daylightFade = smoothstep(-0.04, 0.16, sunPos3dIn.y) * (1.0 - smoothstep(0.92, 1.0, sunPos3dIn.y));
	float moonDisc = 1.0 - smoothstep(-0.85, -0.05, directionIn);
	float moonHeight = clamp(-sunPos3dIn.y, 0.0, 1.0);
	float moonFade = moonDisc * smoothstep(0.03, 0.28, moonHeight) * (1.0 - smoothstep(0.86, 1.0, moonHeight));
	
	intensity = clamp(max(0.42 * dawnMul * daylightFade, 0.18 * moonFade), 0.0, 0.58);
}
