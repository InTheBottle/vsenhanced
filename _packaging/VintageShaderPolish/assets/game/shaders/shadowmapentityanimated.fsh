#version 330 core

in vec2 uv;

out vec4 outColor;

uniform sampler2D entityTex;

void main () {
	outColor = vec4(texture(entityTex, uv));
	if (outColor.a < 0.01) discard;
}