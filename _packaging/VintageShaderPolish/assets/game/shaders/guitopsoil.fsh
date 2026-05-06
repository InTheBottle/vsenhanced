#version 330 core

in vec4 rgba; // Without biome tint
in vec4 rgba2; // With biome tint
in vec2 uv;
in vec2 uv2;
in vec4 color;
in float glowLevel;

out vec4 outColor;

uniform sampler2D terrainTex;
uniform float blockTextureSize;

uniform float noTexture;
uniform float alphaTest;

void main () {
	
	vec4 brownSoilColor = texture(terrainTex, uv) * rgba;
	vec4 grassColor;
	
	if (rgba.a < 0.01) {
		// Bottom
		outColor = brownSoilColor;
	} else {
		if (rgba2.a > 0.01) {
			// Top
			grassColor = texture(terrainTex, uv2) * rgba2;
		} else {
			// Side + Overlay
			grassColor = texture(terrainTex, uv2 + vec2(blockTextureSize, 0)) * vec4(rgba2.rgb, 1);
		}
		
		outColor = brownSoilColor * (1 - grassColor.a) + grassColor * grassColor.a;
	}
	outColor.a = 1;
}