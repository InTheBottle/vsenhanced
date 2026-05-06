#if SHADOWQUALITY > 0
uniform float shadowRangeFar;
uniform mat4 toShadowMapSpaceMatrixFar;
out vec4 shadowCoordsFar;
#if GODRAYS > 0
uniform vec4 cameraWorldPosition;
out vec4 shadowRayStart;
out vec4 shadowLightPos;
out float sunlightLevel;
#endif
#endif
#if SHADOWQUALITY > 1
uniform float shadowRangeNear;
uniform mat4 toShadowMapSpaceMatrixNear;
out vec4 shadowCoordsNear;
#endif


const float transitionDistance = 10.0;


void calcShadowMapCoords(mat4 modelviewMat, vec4 worldPos) {
	float nearSub = 0;
#if SHADOWQUALITY > 0
	float len = length(worldPos);
#endif

#if SHADOWQUALITY > 1
	// Near map
	shadowCoordsNear = toShadowMapSpaceMatrixNear * worldPos;
		
	float distanceNear = clamp(
		max(max(0.0, 0.03 - shadowCoordsNear.x) * 100, max(0.0, shadowCoordsNear.x - 0.97) * 100) +
		max(max(0.0, 0.03 - shadowCoordsNear.y) * 100, max(0.0, shadowCoordsNear.y - 0.97) * 100) +
		max(0.0, shadowCoordsNear.z - 0.98) * 100 +
		max(0.0, len / shadowRangeNear - 0.15) 
	, 0.0, 1.0);
	
	nearSub = shadowCoordsNear.w = clamp(1.0 - distanceNear, 0.0, 1.0);
	if (shadowCoordsNear.z >= 0.999) shadowCoordsNear.w = 0.0;     // so no need to test both in fogandlight.fsh

#endif

#if SHADOWQUALITY > 0
	// Far map
	shadowCoordsFar = toShadowMapSpaceMatrixFar * worldPos;
	
	float distanceFar = clamp(
		max(max(0.0, 0.03 - shadowCoordsFar.x) * 10, max(0.0, shadowCoordsFar.x - 0.97) * 10) +
		max(max(0.0, 0.03 - shadowCoordsFar.y) * 10, max(0.0, shadowCoordsFar.y - 0.97) * 10) +
		max(0.0, shadowCoordsFar.z - 0.98) * 10 +
		max(0.0, len / shadowRangeFar - 0.15) 
	, 0.0, 1.0);

	distanceFar = distanceFar * 2 - 0.5;
	
	shadowCoordsFar.w = max(0.0, clamp(1.0 - distanceFar, 0.0, 1.0) - nearSub);
	if (shadowCoordsFar.z >= 0.999) shadowCoordsFar.w = 0.0;     // so no need to test both in fogandlight.fsh


#endif
}

void prepareVolumetricLightingFlat(vec3 lightPosition) {
#if SHADOWQUALITY > 0 && GODRAYS > 0
	shadowRayStart = toShadowMapSpaceMatrixFar * cameraWorldPosition;
	shadowLightPos = toShadowMapSpaceMatrixFar * vec4(lightPosition, 0.0);
	sunlightLevel = 1.0;
#endif
}

void prepareVolumetricLighting(vec3 lightPosition, vec4 lightColor) {
#if SHADOWQUALITY > 0 && GODRAYS > 0
	shadowRayStart = toShadowMapSpaceMatrixFar * cameraWorldPosition;
	shadowLightPos = toShadowMapSpaceMatrixFar * vec4(lightPosition, 0.0);
	sunlightLevel = lightColor.a;
#endif
}
