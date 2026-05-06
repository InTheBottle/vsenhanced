#version 330 core

uniform sampler2D colorTex;
uniform sampler2D glowTex;
uniform float extraBloom;
uniform float ambientBloomLevel;

in vec2 texcoord;

out vec4 outColor;

void main(void)
{
	vec4 color = texture(colorTex, texcoord);
	float glowLevel = texture(glowTex, texcoord).r * color.a;
	float luma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	float softHighlight = smoothstep(0.62, 1.15, luma);
	float bloomIntensity = extraBloom + 3*glowLevel + ambientBloomLevel * (0.18 + 0.82 * softHighlight);
	
	outColor = color * bloomIntensity;
	//outColor = color * 2;  - night vision 
}
