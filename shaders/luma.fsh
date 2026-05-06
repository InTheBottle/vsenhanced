#version 330 core

uniform sampler2D scene;

in vec2 texCoord;

out vec4 outColor;

float luma(vec3 color) {
  return dot(color, vec3(0.299, 0.587, 0.114));
}

void main(void)
{
	vec4 color = texture(scene, texCoord);
	color.a = luma(color.rgb);
	outColor = color;
}