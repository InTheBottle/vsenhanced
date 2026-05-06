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

vec3 SoftHighlightRollOff(vec3 color) {
	float luma = Luma(color);
	float shoulder = 1.0 + max(luma - 0.82, 0.0) * 0.65;
	return min(color / shoulder, vec3(1.0));
}

vec3 ApplyDetailContrast(vec3 color) {
	vec3 center = texture(primaryScene, texCoord).rgb;
	vec3 blur =
		texture(primaryScene, clamp(texCoord + vec2(invFrameSize.x, 0), vec2(0.0), vec2(1.0))).rgb +
		texture(primaryScene, clamp(texCoord - vec2(invFrameSize.x, 0), vec2(0.0), vec2(1.0))).rgb +
		texture(primaryScene, clamp(texCoord + vec2(0, invFrameSize.y), vec2(0.0), vec2(1.0))).rgb +
		texture(primaryScene, clamp(texCoord - vec2(0, invFrameSize.y), vec2(0.0), vec2(1.0))).rgb;
	blur *= 0.25;
	
	float highlightGuard = 1.0 - smoothstep(0.72, 0.95, Luma(color));
	float darkGuard = smoothstep(0.04, 0.18, Luma(color));
	return clamp(color + (center - blur) * 0.08 * highlightGuard * darkGuard, vec3(0.0), vec3(1.0));
}

vec3 ApplyDirectionalGrade(vec3 color) {
	float night = 1.0 - smoothstep(0.08, 0.35, dayLight);
	float dusk = (1.0 - smoothstep(0.42, 0.85, dayLight)) * smoothstep(0.08, 0.38, dayLight);
	float shadowMask = 1.0 - smoothstep(0.18, 0.58, Luma(color));
	
	color = mix(color, color * vec3(0.78, 0.86, 1.08) + rgbaFog.rgb * 0.04, night * 0.35);
	color = mix(color, color * vec3(1.08, 0.96, 0.86), dusk * 0.18);
	color = mix(color, color * vec3(0.92, 0.96, 1.05), shadowMask * night * 0.12);
	
	return clamp(color, vec3(0.0), vec3(1.0));
}

vec4 ColorGrade(vec4 color) {
	// I don't know why, but this seems to make the scene look a lot better
	color.a = dot(color.rgb, vec3(0.299, 0.587, 0.114)); 
	
	vec3 hsl = rgb2hsl(color.rgb);

	float lightRange = maxlight - minlight;
	float satRange = maxsat - minsat;

	hsl.z = pow((clamp(hsl.z, minlight, maxlight) - minlight) / lightRange, 1/gammaLevel);
	hsl.y = pow((clamp(hsl.y, minsat, maxsat) - minsat) / satRange, 1);
	
	
	color.rgb = hsl2rgb(hsl);
	color.rgb = pow(color.rgb, vec3(1.0 / extraGamma));
	color.rgb *= brightnessLevel;

	// Sepia
	vec3 sepia = vec3(
		(color.r * 0.393) + (color.g * 0.769) + (color.b * 0.189),
		(color.r * 0.349) + (color.g * 0.686) + (color.b * 0.168),
		(color.r * 0.272) + (color.g * 0.534) + (color.b * 0.131)
	) * 0.85;
	
	color.rgb = mix(color.rgb, sepia, sepiaLevel);
	
	color.rgb = color.rgb * (contrastLevel+1) - contrastLevel;
	
	if (glitchEffectStrength > 0) {
		float g = gnoise(vec3(texCoord.x * 2000.0, texCoord.y * 2000.0, mod(windWaveCounter*30, 100)));
		color.rgb *= mix(1, clamp(0.7 + g / 2, 0.7, 1), glitchEffectStrength);
		
		vec3 rust = vec3(
			(color.r * 0.393) + (color.g * 0.769) + (color.b * 0.189),
			(color.r * 0.349) + (color.g * 0.686) + (color.b * 0.168),
			(color.r * 0.272) + (color.g * 0.534) + (color.b * 0.131)
		);
		
		float gdiff = min(color.g, 0.1);
		float bdiff = min(color.b, 0.1);
		rust.g -= gdiff;
		rust.b -= bdiff;
		rust.r += gdiff + bdiff;
		
		color.rgb = mix(color.rgb, rust, glitchEffectStrength);
		color.a += glitchEffectStrength/3;
	}
	

	
	
	// Limit brightness
	// This was commented out, why? Seems to only affect overly bright surfaces
	color.rgb = SoftHighlightRollOff(color.rgb);
	
	return color;	
}


void main(void)
{
	// FXAA precompiler constant is set by game engine
	#if FXAA == 1
		vec4 color = fxaaTexturePixel(primaryScene, texCoord, invFrameSize);
	#else
		vec4 color = texture(primaryScene, texCoord);
	#endif	
    
	color.a=1;
	float bloomSub = 0;
	#if BLOOM == 1
		vec4 bloomCol = texture(bloomParts, texCoord);
		float glowLevel = texture(glowParts, texCoord).r;
		
		float ambLevel = ambientBloomLevel / 2.0;
		
		color.rgb = (color.rgb + bloomCol.rgb * (ambLevel * 1.5)) / (1 + ambLevel);
		
		bloomSub = glowLevel * (bloomCol.r + bloomCol.b + bloomCol.g);
	#endif 

	#if SSAOLEVEL > 0
		#if SSAOLEVEL > 1
			float ssao = min(texture(ssaoScene, texCoord).r, texture(ssaoScene, texCoord - vec2(0, invFrameSize.y*1)).r);
		#else
			float ssao = texture(ssaoScene, texCoord).r;
		#endif		
		
		color.rgb *= min(1.0, ssao + bloomSub);
		
		/*if (texCoord.x < 0.5) {
		   color.rgb = mix(color.rgb, vec3(ssao), 1);
		}*/
	#endif
	
	
	#if GODRAYS > 0
		color.rgb += vec3(1.0, 0.88, 0.68) * clamp(godrayIntensity, 0.0, 0.35) * 0.035;
		color.rgb = SoftHighlightRollOff(color.rgb);
		color.a=1;
	#endif
	
	vec4 gradedColor = ColorGrade(color);
	
	outColor = mix(color, gradedColor, gradedColor.a);
	outColor.rgb = ApplyDetailContrast(outColor.rgb);
	outColor.rgb = ApplyDirectionalGrade(outColor.rgb);
	


	// Vignetting
	vec2 position = (gl_FragCoord.xy * invFrameSize.xy) - vec2(0.5);
	float grayvignette = 1 - smoothstep(1.1, 0.75 - 0.45, length(position));
	float edgeAmount = smoothstep(0.25, 0.75, length(position));
	float chromaStrength = clamp((damageVignetting + frostVignetting * 0.5 + glitchEffectStrength) * edgeAmount * 0.003, 0.0, 0.003);
	if (chromaStrength > 0.0) {
		vec2 chromaDir = normalize(position + vec2(0.0001)) * chromaStrength;
		outColor.r = texture(primaryScene, clamp(texCoord + chromaDir, vec2(0.0), vec2(1.0))).r;
		outColor.b = texture(primaryScene, clamp(texCoord - chromaDir, vec2(0.0), vec2(1.0))).b;
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
		
		vec3 vignetteColor = vec3(0.8 * damageVignetting/2, 0, 0);
		
		float centerness = pow(1 - abs(damageVignettingSide), 3);
		
		float side = clamp(centerness + pow(mix(texCoord.x, 1 - texCoord.x, (1 + damageVignettingSide) / 2), 1.5), 0, 1);
		
		outColor.rgb = mix(outColor.rgb, vignetteColor, max(0.0, str - g) * side);
	}
	
	//outColor.rgb = mix(outColor.rgb, vec3(0), grayvignette);
	
	int frameWidth = int(1.0 / invFrameSize.x + 0.5);
	outColor.rgb += NoiseFromPixelPosition(ivec2(gl_FragCoord.xy), 31, frameWidth).rgb * 0.05;
	outColor.rgb = clamp(outColor.rgb, vec3(0.0), vec3(1.0));
	outColor.a=1;
}
