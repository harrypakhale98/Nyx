#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The immersive sky's static textures, drawn once on the GPU through `ImageRenderer` (milliseconds,
// where the same model on the CPU took seconds in a debug build). Outputs are sRGB-encoded, as
// `ImageRenderer` writes them straight into an 8-bit sRGB image, and opaque: these textures are
// added as light, and a faint pixel with a faint alpha is un-premultiplied on upload into a bright
// one (that drew a hard edge where the alpha rounded to zero).

namespace nyxsky {

float3 encode(float3 c) {
    c = clamp(c, 0.0, 1.0);
    return select(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, 12.92 * c, c <= 0.0031308);
}
float smooth01(float x) { float t = clamp(x, 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
/// A longitude difference folded into −180…180.
float wrapDegrees(float d) { return d > 180.0 ? d - 360.0 : (d < -180.0 ? d + 360.0 : d); }

float gradient(int i, int j, float dx, float dy) {
    uint h = uint(i) * 374761393u + uint(j) * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h ^= h >> 16;
    float angle = float(h & 63u) * M_PI_F / 32.0;
    return cos(angle) * dx + sin(angle) * dy;
}
/// Gradient noise in about 0…1, wrapping every `period` cells in x, so nothing seams at 360°.
float noise(float x, float y, int period) {
    float fx = floor(x), fy = floor(y);
    int i = int(fx), j = int(fy);
    float tx = x - fx, ty = y - fy;
    int i0 = ((i % period) + period) % period, i1 = (i0 + 1) % period;
    float u = tx * tx * tx * (tx * (tx * 6.0 - 15.0) + 10.0), v = ty * ty * ty * (ty * (ty * 6.0 - 15.0) + 10.0);
    float a = gradient(i0, j, tx, ty), b = gradient(i1, j, tx - 1.0, ty);
    float c = gradient(i0, j + 1, tx, ty - 1.0), d = gradient(i1, j + 1, tx - 1.0, ty - 1.0);
    float top = mix(a, b, u), bottom = mix(c, d, u);
    return 0.5 + 0.75 * mix(top, bottom, v);
}
/// Octaves of `noise`, each twice as fine and half as strong, normalised to about 0…1.
float fbm(float x, float y, int octaves, int period) {
    float sum = 0.0, amplitude = 1.0, total = 0.0, scale = 1.0;
    int p = period;
    for (int o = 0; o < octaves; o++) {
        sum += amplitude * noise(x * scale, y * scale + float(o) * 17.3, p);
        total += amplitude;
        amplitude *= 0.5; scale *= 2.0; p *= 2;
    }
    return clamp(sum / total, 0.0, 1.0);
}
float bump(float l, float centre, float width) { float d = wrapDegrees(l - centre) / width; return exp(-d * d); }
float blob(float l, float b, float l0, float b0, float sl, float sb) {
    float dl = wrapDegrees(l - l0) / sl, db = (b - b0) / sb;
    float q = dl * dl + db * db;
    return q > 9.0 ? 0.0 : exp(-q);
}
/// Where the Great Rift's dark lane runs (galactic latitude, degrees) along the longitude.
float riftCentre(float l) {
    const float keys[12][2] = {{96, 1.0}, {85, 1.4}, {70, 0.6}, {55, 0.2}, {40, 0.6}, {30, 1.3}, {20, 1.7}, {10, 2.3}, {3, 2.2}, {-5, 3.0}, {-15, 4.0}, {-26, 5.0}};
    for (int k = 0; k < 11; k++) {
        if (l <= keys[k][0] && l >= keys[k + 1][0]) {
            float t = (keys[k][0] - l) / (keys[k][0] - keys[k + 1][0]);
            return mix(keys[k][1], keys[k + 1][1], t);
        }
    }
    return 1.0;
}

}  // namespace nyxsky

/// The Milky Way in galactic coordinates (linear light, sRGB-encoded on output). x is longitude
/// from the anticentre (the core at the middle), y latitude from +b (top) to −b (bottom).
/// A model, not a photograph: a thin disc widening toward the core, the boxy bulge just south of
/// the plane, the named star clouds, clumping from domain-warped noise, a fine grain of unresolved
/// stars, and dust: the Great Rift from Cygnus to Ophiuchus, lanes across the bulge, the Pipe and
/// ρ Ophiuchi clouds, both Coalsacks, fainter filaments along the plane. Warm toward the core,
/// cooler in the arms; dust reddens the edges of lanes.
[[ stitchable ]] half4 nyxMilkyWay(float2 position, half4 color, float2 size, float latitude) {
    using namespace nyxsky;
    float x = position.x / size.x;
    float l = x * 360.0 - 180.0;
    float b = latitude - position.y / size.y * 2.0 * latitude;

    float inner = bump(l, 0, 55);
    float disc = 0.04 + 0.32 * inner + 0.13 * bump(l, 75, 14) + 0.13 * bump(l, -68, 22) + 0.05 * bump(l, 128, 25) + 0.03 * bump(l, -110, 30);
    float width = 1.6 + 2.2 * bump(l, 0, 35);
    float warmth = min(1.0, 1.15 * bump(l, 0, 26));

    // Light.
    float thin = 0.8 * disc * exp(-b * b / (2.0 * width * width));
    float thick = 0.07 * disc * exp(-b * b / (2.0 * 6.5 * 6.5));
    float bulge = 0.22 * blob(l, b, 0.5, -2.5, 7, 5.5) + 0.1 * blob(l, b, 0, -2, 12, 9) + 0.035 * blob(l, b, 0, -2, 22, 16);
    float clouds = 0.8 * blob(l, b, 2.5, -4.6, 4.0, 2.8)       // Large Sagittarius Star Cloud
        + 0.6 * blob(l, b, 12.1, -0.8, 1.3, 0.9)               // Small Sagittarius Star Cloud, M24
        + 0.55 * blob(l, b, 27.5, -2.3, 3.0, 2.2)              // Scutum Star Cloud
        + 0.1 * blob(l, b, 36, -2.5, 6, 3)                     // Aquila
        + 0.3 * blob(l, b, 76, 0.6, 8.5, 3.0) + 0.14 * blob(l, b, 64, -1.2, 5, 2.2)  // Cygnus Star Cloud
        + 0.2 * blob(l, b, -32, -0.6, 8, 2.4)                  // Norma
        + 0.16 * blob(l, b, -50, -0.4, 7, 2.4)                 // Centaurus
        + 0.32 * blob(l, b, -73, -0.8, 5, 2.3)                 // Carina
        + 0.12 * blob(l, b, -8, 2.5, 5, 3)                     // toward Antares
        + 0.08 * blob(l, b, 118, -1, 10, 3);                   // Cassiopeia
    // Clumping: star clouds a few degrees long and half as tall, lightly warped so they read as
    // clouds, not cells.
    float wx = fbm(x * 30.0, b / 4.0 + 7.1, 2, 30), wy = fbm(x * 30.0 + 3.7, b / 4.0 + 19.3, 2, 30);
    float clump = 0.65 * fbm(x * 100.0 + 1.4 * (wx - 0.5), b / 2.4 + 1.4 * (wy - 0.5), 3, 100)
        + 0.35 * fbm(x * 400.0 + 2.0 * (wx - 0.5), b / 0.9 + 2.0 * (wy - 0.5), 3, 400);
    float clumping = 0.2 + 2.1 * clump * clump;
    // A fine grain of unresolved stars, a few tenths of a degree across.
    float grain = fbm(x * 1800.0, b / 0.2 + 3.3, 2, 1800);
    float light = (thin + thick + clouds) * clumping + bulge * (0.6 + 0.8 * clump);
    light *= 0.62 + 0.9 * grain * grain;

    // Dust: ridged noise drawn out along the plane, thresholded so only some of it forms lanes.
    float ridge = 1.0 - abs(2.0 * fbm(x * 180.0 + 0.8 * (wy - 0.5), b / 1.2 + 40.0, 4, 180) - 1.0);
    float lanes = smoothstep(0.5, 0.92, ridge);
    float patches = fbm(x * 45.0, b / 2.0 + 60.0, 3, 45);
    float ends = smooth01((88.0 - l) / 8.0) * smooth01((l + 24.0) / 8.0);
    float tau = 0.0;
    if (l > -26.0 && l < 98.0) {
        float riftWidth = 1.1 + 1.4 * bump(l, 35, 16) + 0.5 * bump(l, 75, 10);
        float d = (b + 2.4 * (patches - 0.5) - riftCentre(l)) / (riftWidth * (0.6 + 0.8 * fbm(x * 20.0, 77.0, 2, 20)));
        float islands = fbm(x * 220.0, b / 1.1 + 90.0, 3, 220);
        tau += 1.5 * ends * exp(-d * d * d * d) * (0.05 + 1.7 * patches * patches) * (0.25 + 1.2 * smoothstep(0.35, 0.75, islands)) + 0.5 * ends * exp(-d * d) * lanes;
    }
    tau += 1.5 * blob(l, b, 1, 2.0, 8, 1.1) * (0.45 + 0.8 * patches + 0.5 * lanes);  // the lane across the top of the bulge
    tau += 0.8 * blob(l, b, 7.5, -0.4, 5.0, 0.6) * (0.5 + patches);              // between M24 and the Large Cloud
    // The Pipe Nebula's stem and bowl, and the ρ Ophiuchi clouds above Antares.
    float t = clamp((1.2 - l) / 5.4, 0.0, 1.0);
    float sl = wrapDegrees(l - (1.2 - 5.4 * t)), sb = b - (3.6 + 3.6 * t);
    tau += 0.9 * exp(-(sl * sl + sb * sb) / 0.6) + 0.8 * blob(l, b, -4.4, 7.4, 1.6, 1.4);
    tau += 1.0 * blob(l, b, -6.5, 16.5, 3.2, 2.4) * (0.5 + patches);
    tau += 1.3 * blob(l, b, -58.8, -0.6, 2.4, 2.2);                 // the Coalsack
    // Fainter filaments everywhere along the plane, strongest in the inner galaxy.
    tau += 0.8 * lanes * exp(-b * b / (2.0 * 3.0 * 3.0)) * (0.3 + 0.7 * inner);
    light *= exp(-tau);
    light *= smooth01((latitude - abs(b)) / 12.0);

    // Colour.
    float3 warm = float3(1.0, 0.82, 0.6), cool = float3(0.72, 0.82, 1.0), neutral = float3(0.9, 0.9, 0.94);
    float warmShare = min(1.0, warmth * 0.75 + bulge / (bulge + thin + thick + clouds + 0.001) * 0.6);
    float3 tint = mix(neutral, cool, (1.0 - warmth) * 0.8);
    tint = mix(tint, warm, warmShare);
    tint *= mix(float3(1.0), float3(1.0, 0.84, 0.66), min(1.0, tau) * 0.45);
    // A soft shoulder keeps the core luminous without clipping.
    // A gentle contrast curve keeps the faint wings faint, then a soft shoulder keeps the core
    // luminous without clipping.
    float3 rgb = tint * (1.0 - exp(-1.25 * pow(light, 1.2)));
    float3 encoded = encode(rgb);
    return half4(half3(encoded), 1.0h);
}

/// The star atlas: one column per B−V colour, one row per brightness (`SkyTextures.look`).
/// - looks: per row, (peak, core, halo, haloWidth, glow, glowWidth, saturation, radius), degrees.
/// - colors: per column, linear RGB.
/// Each cell: a core burning toward white, the glare and glow in the star's colour, fading to
/// nothing before the cell's edge so mipmaps never bleed one star into the next.
[[ stitchable ]] half4 nyxStarAtlas(float2 position, half4 color, float2 cells, device const float *looks, int lookCount, device const float *colors, int colorCount) {
    using namespace nyxsky;
    float cell = cells.x;
    int column = int(position.x / cell), row = int(position.y / cell);
    if (row * 8 + 7 >= lookCount || column * 3 + 2 >= colorCount) { return half4(0.0h); }
    float2 p = (fmod(position, cell) / cell) * 2.0 - 1.0;
    float rn = length(p);
    if (rn >= 1.0) { return half4(0.0h); }
    device const float *k = looks + row * 8;
    float r = rn * k[7];
    float3 starColor = float3(colors[column * 3], colors[column * 3 + 1], colors[column * 3 + 2]);
    float3 hue = mix(float3(1.0), starColor, k[6]);
    float core = k[0] * exp(-r * r / (2.0 * k[1] * k[1]));
    float glare = k[2] * exp(-r * r / (2.0 * k[3] * k[3])) + k[4] / pow(1.0 + pow(r / k[5] * 3.0, 2.0), 1.5);
    float3 white = mix(float3(1.0), hue, 0.6);
    float3 rgb = min((white * core + hue * glare) * smooth01((1.0 - rn) / 0.18), float3(1.0));
    float3 encoded = encode(rgb);
    return half4(half3(encoded), 1.0h);
}
