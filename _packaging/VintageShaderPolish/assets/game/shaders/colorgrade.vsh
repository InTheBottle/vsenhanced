#version 330 core

layout(location=0) in vec2 position;

uniform vec2 invFrameSizeIn;

out vec2 texCoord;
out vec2 invFrameSize;

void main(void)
{
    gl_Position = vec4(position, 0, 1);
    texCoord = (position+1.0) / 2.0;
	invFrameSize = invFrameSizeIn;
}