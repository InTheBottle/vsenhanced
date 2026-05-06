#version 330 core
// code will change the version to 430 if USESSBO > 0
#extension GL_ARB_explicit_attrib_location: enable

 #if USESSBO > 0
layout(location = 0) in vec4 rgbaLightIn;
layout(location = 1) in vec2 blockUvIn;
layout(location = 2) in vec2 decalUvSizeIn;
layout(location = 3) in vec2 decalUvStartIn;
 #else
layout(location = 0) in vec3 vertexPos;
layout(location = 1) in vec2 decalUvIn;
// rgb = block light, a=sun light level
layout(location = 2) in vec4 rgbaLightIn;
layout(location = 3) in int renderFlagsIn;
layout(location = 4) in vec2 blockUvIn;
layout(location = 5) in vec2 decalUvSizeIn;
layout(location = 6) in vec2 decalUvStartIn; // Argh >.<
 #endif

uniform vec4 rgbaFogIn;
uniform vec3 rgbaAmbientIn;
uniform float fogDensityIn;
uniform float fogMinIn;
uniform vec3 origin;
uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;

out vec2 decalUv;
out vec2 blockUv;
out vec2 decalUvSize;
out vec2 decalUvStart;
out vec4 color;

#include vertexflagbits.ash
#include shadowcoords.vsh
#include fogandlight.vsh
#include vertexwarp.vsh

 #if USESSBO > 0
layout(binding = 3, std430) readonly buffer faceDataBuf  { FaceData faces[]; };
 #endif


void main () {
 #if USESSBO > 0
	FaceData vdata = faces[gl_VertexID / 4];
	int vIndex = gl_VertexID & 0x03;
	int renderFlagsIn = vdata.flags[vIndex];
	vec3 vertexPos = vdata.xyz + ((vIndex + 1) & 2) * vdata.xyzA + (vIndex & 2) * vdata.xyzB;
 #endif
	vec4 worldpos = vec4(vertexPos + origin, 1.0);
	
	worldpos = applyVertexWarping(renderFlagsIn, worldpos);
	worldpos = applyGlobalWarping(worldpos);
	
	vec4 cameraPos = modelViewMatrix * worldpos;

	gl_Position = projectionMatrix * cameraPos;
	
	
	color = applyLight(rgbaAmbientIn, rgbaLightIn, renderFlagsIn, cameraPos);
	color = applyFog(worldpos, color, rgbaFogIn, fogMinIn, fogDensityIn);
	color.a = 1;
	
	// We pretend the decal is closer to the camera to enforce it
	// always being drawn on top
	//gl_Position.w += 0.0012; - not enough for leaves :o
	int zOffset = 1 + ((renderFlagsIn & ZOffsetBitMask) >> 8);
	gl_Position.w += zOffset * 0.00025 / max(0.1, gl_Position.z * 0.05);

 #if USESSBO > 0
	decalUv = UnpackUv(vdata, vIndex, 0, 0);
 #else
	decalUv = decalUvIn;
 #endif
	blockUv = blockUvIn;
	decalUvSize = decalUvSizeIn;
	decalUvStart = decalUvStartIn;
}