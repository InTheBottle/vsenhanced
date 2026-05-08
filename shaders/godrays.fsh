#version 330 core

// Engine-bound; kept and referenced so the linker doesn't prune them.
uniform sampler2D inputTexture;
uniform sampler2D glowParts;

uniform sampler2D sceneDepthTex;
#if SHADOWQUALITY > 0
uniform sampler2DShadow shadowMapFar;
uniform mat4 toShadowMapSpaceMatrixFar;
uniform float shadowRangeFar;
#endif
#if SHADOWQUALITY > 1
uniform sampler2DShadow shadowMapNear;
uniform mat4 toShadowMapSpaceMatrixNear;
uniform float shadowRangeNear;
#endif

uniform mat4 invProjectionMatrix;
uniform mat4 invModelViewMatrix;

uniform vec3 realCloudShadowLightDir;
uniform float realCloudShadowDaylight;
uniform float realMoonLightStrength;
uniform float dayLightStrength;
// trueSunPos.y < 0 means sun below horizon (real night).
uniform vec3 trueSunPos;

uniform vec2 invFrameSizeIn;
uniform float iGlobalTimeIn;

in vec2 texCoord;
out vec4 outColor;

const int NUM_STEPS = 56;
const float ATM_SIGMA = 0.020;

float phaseHG(float cosTheta, float g) {
    float gSq = g * g;
    return (1.0 - gSq) / pow(max(0.0001, 1.0 + gSq - 2.0 * g * cosTheta), 1.5) / 12.566371;
}

vec3 reconstructWorldRay(vec2 uv) {
    vec4 viewPos = invProjectionMatrix * vec4(uv * 2.0 - 1.0, -1.0, 1.0);
    viewPos.xyz /= viewPos.w;
    return normalize((invModelViewMatrix * vec4(viewPos.xyz, 0.0)).xyz);
}

vec3 reconstructWorldPoint(vec2 uv, float depth) {
    vec4 viewPos = invProjectionMatrix * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    viewPos.xyz /= viewPos.w;
    return (invModelViewMatrix * vec4(viewPos.xyz, 1.0)).xyz;
}

// Engine matrices already produce [0,1] UV+depth, no *0.5+0.5 needed.
float sampleSunVisibility(vec3 worldPos) {
#if SHADOWQUALITY > 1
    vec4 cn = toShadowMapSpaceMatrixNear * vec4(worldPos, 1.0);
    if (cn.x > 0.04 && cn.x < 0.96 && cn.y > 0.04 && cn.y < 0.96 && cn.z < 0.999) {
        return texture(shadowMapNear, vec3(cn.xy, cn.z - 0.0005));
    }
#endif
#if SHADOWQUALITY > 0
    vec4 cf = toShadowMapSpaceMatrixFar * vec4(worldPos, 1.0);
    if (cf.x > 0.04 && cf.x < 0.96 && cf.y > 0.04 && cf.y < 0.96 && cf.z < 0.999) {
        return texture(shadowMapFar, vec3(cf.xy, cf.z - 0.0009));
    }
#endif
    return 1.0;
}

// Interleaved gradient noise (Jimenez 2014) -- blue-noise-like, not grainy.
float ign(vec2 frag) {
    return fract(52.9829189 * fract(0.06711056 * frag.x + 0.00583715 * frag.y));
}

void main(void) {
    if (trueSunPos.y < 0.02) {
        vec3 a = texture(inputTexture, texCoord).rgb;
        vec3 b = texture(glowParts, texCoord).rgb;
        outColor = vec4(a * b * 1e-9, 1.0);
        return;
    }

    vec3 viewDir = reconstructWorldRay(texCoord);

    float depth = texture(sceneDepthTex, texCoord).r;
    // Skip shadow sampling for sky pixels: view-aligned-with-sun rays produce bogus self-shadow tests.
    bool isSky = depth >= 0.9999;
#if SHADOWQUALITY > 0
    float marchRange = shadowRangeFar;
#else
    float marchRange = 120.0;
#endif
    float maxDist;
    if (isSky) {
        maxDist = marchRange * 1.10;
    } else {
        vec3 worldEnd = reconstructWorldPoint(texCoord, depth);
        maxDist = length(worldEnd);
    }
    maxDist = min(maxDist, marchRange * 1.40);

    float horizonRamp = smoothstep(0.02, 0.15, trueSunPos.y);
    float lightRamp = smoothstep(0.10, 0.45, dayLightStrength);
    float dayGate = horizonRamp * lightRamp;

    if (maxDist < 0.5) {
        vec3 keep = texture(inputTexture, texCoord).rgb * texture(glowParts, texCoord).rgb;
        outColor = vec4(keep * 1e-8, 1.0);
        return;
    }

    float stepLen = maxDist / float(NUM_STEPS);
    float jitter = ign(gl_FragCoord.xy);

    vec3 sunDir = normalize(realCloudShadowLightDir);
    float cosTheta = dot(viewDir, sunDir);

    float phase = mix(phaseHG(cosTheta, 0.78), phaseHG(cosTheta, 0.30), 0.15);

    float sunElev = smoothstep(-0.04, 0.20, sunDir.y);
    vec3 sunCol = mix(vec3(1.20, 0.85, 0.55), vec3(1.05, 1.00, 0.95), sunElev);
    float strength = clamp(realCloudShadowDaylight + realMoonLightStrength * 0.18, 0.0, 1.4);

    vec3 inscatter = vec3(0.0);
    float transmittance = 1.0;
    for (int i = 0; i < NUM_STEPS; i++) {
        float t = (float(i) + jitter) * stepLen;
        if (t >= maxDist) break;

        vec3 sp = viewDir * t;
        float vis = isSky ? 1.0 : sampleSunVisibility(sp);

        inscatter += sunCol * phase * vis * ATM_SIGMA * stepLen * transmittance;
        transmittance *= exp(-ATM_SIGMA * stepLen);
        if (transmittance < 0.05) break;
    }

    inscatter *= strength * dayGate;

    // Keep samplers referenced.
    vec3 keep = texture(inputTexture, texCoord).rgb * texture(glowParts, texCoord).rgb;
    inscatter += keep * 1e-8;

    outColor = vec4(inscatter / (inscatter + vec3(1.0)), 1.0);
}
