// Excellent dither method by Krishty
// http://old.zfx.info/DisplayThread.php?TID=24491
vec4 NoiseFromPixelPosition(ivec2 PixelsPosition, int ditherSeed, int horizontalResolution) {

    int PixelsIndex = horizontalResolution * PixelsPosition.y + PixelsPosition.x;
    int PixelsArea = PixelsPosition.x * PixelsPosition.y;

    ivec4 vPixelsIndex = ditherSeed + PixelsIndex * ivec4(41, 29, 53, 43);
    ivec4 vPixelsArea = ditherSeed + PixelsArea * ivec4(23, 59, 47, 37);

    return (vec4((vPixelsIndex ^ vPixelsArea) % 661) / 330.5 - 1.0) / 128;
}
