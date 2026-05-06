#version 330 core

uniform sampler2D scene;

in vec2 texCoord;

out vec4 outColor;


void main(void)
{
	outColor = texture(scene, texCoord);
	outColor.a = 1;
}