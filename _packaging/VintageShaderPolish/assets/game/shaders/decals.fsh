#version 330 core

in vec2 decalUv;
in vec2 blockUv;
in vec2 decalUvSize;
in vec4 color;
in vec2 decalUvStart;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outGlow;

uniform sampler2D decalTexture;
uniform sampler2D blockTexture;

void main()
{
	vec2 uv = vec2(decalUvStart.x + mod(decalUv.x, decalUvSize.x), decalUvStart.y + mod(decalUv.y, decalUvSize.y));
	
	outColor = color * texture(decalTexture, uv);
	
	
	float blockAlpha = texture(blockTexture, blockUv).a;
	if (outColor.a < 0.01 || blockAlpha < 0.01) discard;

	outGlow = vec4(0, 0, 0, outColor.a);
}
