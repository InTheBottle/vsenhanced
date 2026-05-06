#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

uniform sampler2D depthSampler;

in vec3 vertexPosition;

out vec4 outColor;

float LinearizeDepth(vec2 uv)
{
  float n = 0.3; // camera z near
  float f = 1500.0; // camera z far
  float z = texture(depthSampler, uv).x;
  return z; //(2.0 * n) / (f + n - z * (f - n));	
}
	
void main() 
{ 
	vec2 uv = vertexPosition.xy;
	
	// Don't ask me why this is nieeded, i guess our quad is weird
	uv.x = uv.x / 2 + 0.5;
	uv.y = uv.y / 2 + 0.5;
	
	float d;
	d = LinearizeDepth(uv);
	outColor = vec4(d, d, d, 1.0);
}