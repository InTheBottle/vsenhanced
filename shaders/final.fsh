#version 330 core

uniform sampler2D primaryScene;
uniform sampler2D glowParts;  // The second color buffer (outGlow var)
uniform sampler2D bloomParts; // The blurred find bright texture
uniform sampler2D godrayParts;
uniform sampler2D ssaoScene;

uniform float gammaLevel;
uniform float brightnessLevel;
uniform float contrastLevel;
uniform float sepiaLevel;
uniform float ambientBloomLevel;
uniform float damageVignetting;
uniform float damageVignettingSide;
uniform float frostVignetting;
uniform float extraGamma = 1.0;
uniform float windWaveCounter;
uniform float glitchEffectStrength;
uniform float dayLight = 1.0;
uniform vec4 rgbaFog = vec4(0.55, 0.62, 0.72, 1.0);

// Smoothed exposure modulator from CPU-side eye adaptation. ~0.7 squints
// in bright outdoors, ~1.3 dilates in dark caves; default of 1.0 means
// "no modulation" if the uniform isn't bound.
uniform float vspExposure = 1.0;

uniform float minlight = 0.0;
uniform float maxlight = 1;
uniform float minsat = 0;
uniform float maxsat = 1;


in vec2 invFrameSize;
in vec2 texCoord;
flat in float godrayIntensity;

layout(location = 0) out vec4 outColor;

#include fxaa.fsh
#include dither.fsh
#include colorutil.ash
#include noise3d.ash

float SmoothStep(float x) { return x * x * (3.0f - 2.0f * x); }

float Luma(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

const mat3 AGX_INSET = mat3(
	0.842479, 0.042328, 0.042376,
	0.078434, 0.878469, 0.078434,
	0.079224, 0.079166, 0.879143
);
const mat3 AGX_OUTSET = mat3(
	 1.196879, -0.052897, -0.052972,
	-0.098021,  1.151903, -0.098043,
	-0.099030, -0.098961,  1.151074
);
const float AGX_MIN_EV = -9.75;
const float AGX_MAX_EV =  2.75;
const float AGX_EV_INV = 0.08; // 1.0 / (max - min)

vec3 ApplyAgX(vec3 color) {

	color *= 1.55;

	color = AGX_INSET * color;
	color = clamp(log2(max(color, vec3(0.00005))), vec3(AGX_MIN_EV), vec3(AGX_MAX_EV));
	color = (color - vec3(AGX_MIN_EV)) * AGX_EV_INV;
	color = clamp(color, 0.0003, 1.0);
	color = AGX_OUTSET * color;

	color = (((((15.41 * color - 40.22) * color + 32.1) * color - 6.868) * color + 0.29) * color + 0.286) * color - 0.001;

	color = pow(max(color, vec3(0.0)), vec3(2.2));

	return color;
}

float autoExposure() {
	return vspExposure;
}

vec3 ApplyOutputDither(vec3 color, float skyMask) {
	int frameWidth = int(1.0 / invFrameSize.x + 0.5);
	vec3 noise = NoiseFromPixelPosition(ivec2(gl_FragCoord.xy), 31, frameWidth).rgb;
	float luma = Luma(color);
	float darkBoost = 1.0 - smoothstep(0.0, 0.22, luma);
	float midBand = smoothstep(0.04, 0.55, luma) * (1.0 - smoothstep(0.86, 1.0, luma));
	float gradientMask = max(midBand, darkBoost * 2.2);
	float strength = mix(0.65, 1.0, skyMask) * gradientMask / 255.0;
	return color + noise * strength;
}

vec3 SampleBloom(float strength) {
	vec3 b0 = texture(bloomParts, texCoord).rgb;
	vec2 r = invFrameSize * 6.0;
	vec3 b1 = texture(bloomParts, clamp(texCoord + vec2( r.x,  0.0), vec2(0.0), vec2(1.0))).rgb;
	vec3 b2 = texture(bloomParts, clamp(texCoord + vec2(-r.x,  0.0), vec2(0.0), vec2(1.0))).rgb;
	vec3 b3 = texture(bloomParts, clamp(texCoord + vec2( 0.0,  r.y), vec2(0.0), vec2(1.0))).rgb;
	vec3 b4 = texture(bloomParts, clamp(texCoord + vec2( 0.0, -r.y), vec2(0.0), vec2(1.0))).rgb;

	vec3 bloom = b0 * 0.45 + (b1 + b2 + b3 + b4) * 0.1375;

	// Gate by bloom luma: dark bloom pixels (atlas leakage, dim sources)
	// are zeroed so the scene's blacks aren't lifted.
	float bloomLuma = dot(bloom, vec3(0.2126, 0.7152, 0.0722));
	float gate = smoothstep(0.04, 0.28, bloomLuma);

	// Soft gamma on bloom emphasises hot sources over weak ones.
	bloom = pow(bloom, vec3(0.85));
	return bloom * gate * strength;
}

vec3 ApplyDirectionalGrade(vec3 color) {
	float night = 1.0 - smoothstep(0.08, 0.35, dayLight);
	float dusk = (1.0 - smoothstep(0.42, 0.85, dayLight)) * smoothstep(0.08, 0.38, dayLight);
	float shadowMask = 1.0 - smoothstep(0.18, 0.58, Luma(color));

	color = mix(color, color * vec3(0.92, 0.98, 1.09) + rgbaFog.rgb * 0.065, night * 0.42);
	color = mix(color, color * vec3(1.08, 0.96, 0.86), dusk * 0.18);
	color = mix(color, color * vec3(0.98, 1.02, 1.10) + vec3(0.010, 0.014, 0.026), shadowMask * night * 0.28);

	float nightGain = mix(1.0, 1.22, night);
	vec3 nightFloor = vec3(0.016, 0.020, 0.034) * night;
	color = color * nightGain + nightFloor;

	return clamp(color, vec3(0.0), vec3(1.0));
}

vec3 ColorGradePreAgX(vec3 color) {
	color = pow(color, vec3(1.0 / extraGamma));
	color = pow(max(color, vec3(0.0)), vec3(2.4 / max(gammaLevel, 0.05)));
	color *= brightnessLevel;

	vec3 sepiaScale = vec3(1.0 + sepiaLevel * 0.1, 1.0, 1.0 - sepiaLevel * 0.1);
	color *= sepiaScale;

	const float invGrey = 1.0 / 0.18;
	vec3 cPow = vec3(1.25 + contrastLevel * 0.16667);
	color = pow(max(color * invGrey, vec3(0.0001)), cPow);
	color *= 0.18 * (0.75 + contrastLevel * 0.2);

	if (glitchEffectStrength > 0.0) {
		float g = gnoise(vec3(texCoord.xy * 2000.0, mod(windWaveCounter * 30.0, 100.0)));
		color *= mix(1.0, clamp(0.7 + g * 0.5, 0.7, 1.0), glitchEffectStrength);
		vec3 glitchScale = vec3(
			1.0 + glitchEffectStrength * 0.75,
			1.0 + glitchEffectStrength * 0.10,
			1.0 - glitchEffectStrength * 0.20
		);
		color *= glitchScale;
	}

	return color;
}


void main(void)
{
	#if FXAA == 1
		vec3 color = fxaaTexturePixel(primaryScene, texCoord, invFrameSize).rgb;
	#else
		vec3 color = texture(primaryScene, texCoord).rgb;
	#endif

	// Bloom: gated soft-halo blend (see SampleBloom). Glow contributes to
	// SSAO bypass so emissive surfaces don't get occluded.
	float bloomSub = 0.0;
	#if BLOOM == 1
		vec3 bloomRaw = texture(bloomParts, texCoord).rgb;
		float glowLevel = texture(glowParts, texCoord).r;
		float bloomStrength = clamp(ambientBloomLevel * 0.45, 0.0, 0.85);
		color += SampleBloom(bloomStrength);
		bloomSub = glowLevel * dot(bloomRaw, vec3(0.2126, 0.7152, 0.0722));

		float bloomNight = 1.0 - smoothstep(0.08, 0.35, dayLight);
		if (bloomNight > 0.001) {
			float bloomLuma = dot(bloomRaw, vec3(0.2126, 0.7152, 0.0722));
			float gate = smoothstep(0.05, 0.30, bloomLuma);
			color += bloomRaw * vec3(1.10, 0.92, 0.68) * gate * bloomNight * 0.50;
		}
	#endif

	#if SSAOLEVEL > 0
		float ssao = texture(ssaoScene, texCoord).r;
		#if SSAOLEVEL > 1
			ssao = min(ssao, texture(ssaoScene, texCoord - vec2(0.0, invFrameSize.y)).r);
		#endif
		color *= min(1.0, ssao + bloomSub);
	#endif

	#if GODRAYS > 0
		// Direct add: godrayParts holds 0-1 ray intensity; pow(1.2) here
		// would attenuate them since pow(0.3, 1.2) < 0.3. Mild ceiling
		// keeps the sun disc from blowing out completely.
		vec3 godrays = min(texture(godrayParts, texCoord).rgb, vec3(0.85));
		color += godrays * 0.65;
	#endif

	// Sky-band mask for dither weighting (computed from clamped scene).
	vec3 sceneRef = clamp(color, vec3(0.0), vec3(1.0));
	float skyBandMask = smoothstep(0.46, 0.82, sceneRef.b)
		* smoothstep(sceneRef.r + 0.03, sceneRef.b + 0.20, sceneRef.b)
		* smoothstep(sceneRef.g * 0.82, sceneRef.b + 0.18, sceneRef.b);

	// Eye adaptation: small modulator around 1.0 (squint to dilate).
	color *= autoExposure();

	// Display-space grade in linear (before AgX), so user sliders behave
	// as the engine intended.
	color = ColorGradePreAgX(color);

	// AgX tonemap, calibrated for the engine's actual range.
	color = ApplyAgX(color);

	// Optional warm/cool tint for night and dusk (display space).
	color = ApplyDirectionalGrade(color);

	outColor = vec4(color, 1.0);


	// Vignetting
	vec2 position = (gl_FragCoord.xy * invFrameSize.xy) - vec2(0.5);
	float grayvignette = 1 - smoothstep(1.1, 0.75 - 0.45, length(position));
	float edgeAmount = smoothstep(0.25, 0.75, length(position));
	float chromaStrength = clamp((frostVignetting * 0.5 + glitchEffectStrength) * edgeAmount * 0.003, 0.0, 0.003);
	if (chromaStrength > 0.0) {
		vec2 chromaDir = normalize(position + vec2(0.0001)) * chromaStrength;
		// Clamp the raw HDR samples so they don't bypass the tonemap.
		outColor.r = clamp(texture(primaryScene, clamp(texCoord + chromaDir, vec2(0.0), vec2(1.0))).r, 0.0, 1.0);
		outColor.b = clamp(texture(primaryScene, clamp(texCoord - chromaDir, vec2(0.0), vec2(1.0))).b, 0.0, 1.0);
	}
	
	
		
	if (frostVignetting > 0) {
		float str = -0.05 + 1.05*clamp(1 - smoothstep(1.1 - frostVignetting / 4, 0.75 - 0.45, length(position)), 0, 1) - grayvignette;
		float g = 0;
		
		float wx = gnoise(vec3(gl_FragCoord.x / 20.0, str, gl_FragCoord.x / 11.0 + gl_FragCoord.y / 10.0));
		float wy = gnoise(vec3(gl_FragCoord.x / 20.0, str, gl_FragCoord.x / 10.0 - gl_FragCoord.y / 9.0));
		
		g = 2*gnoise(vec3(wx / 3.0, wy / 3.0, 0.2)) + 0.8;
		g *= gnoise(vec3(gl_FragCoord.x / 20.0, gl_FragCoord.y / 20.0, 1.5)) + 0.2;
		g -= gnoise(vec3(wx * 2.0, wy * 2.0, 1))/5;
		g -= str*2;
		g *= frostVignetting;
		
		float v = 0.9 + gnoise(vec3(wx, -wy, 0)) / 15.0;
		vec3 vignetteColor = vec3(v, v, 0.95);
		
		outColor.rgb = mix(outColor.rgb, vignetteColor, max(0.0, str - g) + 0.5*str);
	}
	
	
	
	if (damageVignetting > 0) {
		float str = clamp(1 - smoothstep(1.1 - damageVignetting / 4, 0.75 - 0.45, length(position)), 0, 1) - grayvignette;
		float g = 0;
		
		g = gnoise(vec3(gl_FragCoord.x / 20.0, gl_FragCoord.y / 20.0, 0)) + 0.5;
		g += gnoise(vec3(gl_FragCoord.x / 5.0, gl_FragCoord.y / 5.0, 0))/5;
		g -= str*2;
		
		g*=damageVignetting;
		
		float centerness = pow(1 - abs(damageVignettingSide), 3);
		float side = clamp(centerness + pow(mix(texCoord.x, 1 - texCoord.x, (1 + damageVignettingSide) / 2), 1.5), 0, 1);
		float damageMask = max(0.0, str - g) * side;
		vec3 bloodTint = vec3(0.52, 0.035, 0.02) * (0.65 + damageVignetting * 0.35);
		outColor.rgb = mix(outColor.rgb, outColor.rgb * vec3(0.42, 0.12, 0.10) + bloodTint, damageMask);
	}
	
	//outColor.rgb = mix(outColor.rgb, vec3(0), grayvignette);
	
	outColor.rgb = ApplyOutputDither(outColor.rgb, skyBandMask);
	outColor.rgb = clamp(outColor.rgb, vec3(0.0), vec3(1.0));
	outColor.a=1;
}
