// World-stable cloud shadows: noise sampled at (worldXZ, time), no player term.

float vspCloudHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vspCloudOctave(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n00 = vspCloudHash(i);
    float n10 = vspCloudHash(i + vec2(1.0, 0.0));
    float n01 = vspCloudHash(i + vec2(0.0, 1.0));
    float n11 = vspCloudHash(i + vec2(1.0, 1.0));
    return mix(mix(n00, n10, f.x), mix(n01, n11, f.x), f.y);
}

float vspCloudFBM(vec2 p) {
    float n  = 0.50 * vspCloudOctave(p);
    n       += 0.27 * vspCloudOctave(p * 2.07 + vec2(13.7,  7.3));
    n       += 0.15 * vspCloudOctave(p * 4.21 + vec2(31.1, 19.9));
    n       += 0.08 * vspCloudOctave(p * 8.13 + vec2(53.7, 41.1));
    return n;
}

float vspGetCloudShadow(vec3 worldPos, vec3 normal, float fogAmount) {
    float upness = clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
    float daylight = realCloudShadowDaylight * smoothstep(0.02, 0.22, realCloudShadowLightDir.y);
    // Moonlit nights: full-strength drifting cloud shadows read as noise on dim
    // terrain. realMoonLightStrength is >0 only at night, so days are untouched.
    daylight *= 1.0 - 0.70 * smoothstep(0.05, 0.30, realMoonLightStrength);
    // Fade out earlier in fog so the fog band stays clean and converges to the
    // engine fog color instead of carrying drifting shadow mottle.
    float fogFade = 1.0 - smoothstep(0.30, 0.80, fogAmount);
    if (upness <= 0.05 || daylight <= 0.01 || fogFade <= 0.01) return 1.0;

    vec3 sd = normalize(realCloudShadowLightDir);
    if (sd.y < 0.05) return 1.0;

    const float cloudAltitude = 220.0;
    float dy = max(cloudAltitude - worldPos.y, 0.0);
    float t  = dy / max(sd.y, 0.05);
    vec2 projXZ = worldPos.xz + sd.xz * t;

    vec2 p = projXZ * 0.0030 + vec2(windWaveCounter * 0.012, -windWaveCounter * 0.008);
    float density = vspCloudFBM(p);
    float cloud = smoothstep(0.45, 0.78, density);

    float strength = clamp(cloud * upness * daylight * fogFade, 0.0, 1.0);
    float shadow = 1.0 - strength * 0.50;
    return clamp(shadow, 0.50, 1.0);
}
