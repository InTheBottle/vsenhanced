#version 330 core
// code will change the version to 430 if USESSBO > 0
#extension GL_ARB_explicit_attrib_location: enable

 #if USESSBO > 0
// rgb = block light, a=sun light level
layout(location = 0) in vec4 rgbaLightIn;
 #else
layout(location = 0) in vec3 xyz;
layout(location = 1) in vec2 uvIn;
layout(location = 2) in vec4 rgbaLightIn;
layout(location = 3) in int renderFlagsIn;
 #endif

uniform vec3 origin;
uniform mat4 mvpMatrix;
uniform float subpixelPaddingX;
uniform float subpixelPaddingY;

out vec2 uv;

#include vertexflagbits.ash
#include vertexwarp.vsh

 #if USESSBO > 0
layout(binding = 3, std430) readonly buffer faceDataBuf  { FaceData faces[]; };
 #endif


void main(void)
{
 #if USESSBO > 0
	FaceData vdata = faces[gl_VertexID / 4];
	int vIndex = gl_VertexID & 0x03;
	vec3 xyz = vdata.xyz + ((vIndex + 1) & 2) * vdata.xyzA + (vIndex & 2) * vdata.xyzB;
 #endif

	vec4 worldPos = vec4(xyz + origin, 1.0);
 #if USESSBO > 0
	worldPos = applyVertexWarping(vdata.flags[vIndex], worldPos);
 #else
	worldPos = applyVertexWarping(renderFlagsIn, worldPos);
 #endif
	worldPos = applyGlobalWarping(worldPos);
	
	gl_Position = mvpMatrix * worldPos;
	
 #if USESSBO > 0
	uv = UnpackUv(vdata, vIndex, subpixelPaddingX, subpixelPaddingY);
 #else
        uv = uvIn;
 #endif
	
	// We could use this to fix peter panninng on tall grass, but needs an extra render pass or extra vertex data for grass
	//gl_Position.w += 1 * 0.00025 / max(0.1, gl_Position.z * 0.05);
}