#version 330 core

in vec4 v_color;

out vec4 outAccu;
out vec4 outReveal;


void drawPixel(vec4 color) {
    float alpha = color.a;

	float weight = max(0.01, min(3000, 0.03 / (0.00001 + pow(gl_FragCoord.z/200, 4))));

    // RGBA32F texture (accumulation)
    outAccu = vec4(color.rgb * alpha, alpha) * weight;

    // R32F texture (revealage)
    // Make sure to use the red channel (and GL_RED target in your texture)
    outReveal.r = alpha;
}

void main()
{
	drawPixel(v_color);
}