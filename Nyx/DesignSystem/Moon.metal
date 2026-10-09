#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// The atlas's bands (`Scripts/build_moon_atlas.swift`): colour in the top two thirds (4096×2048),
/// local relief in the bottom-left (2048×1024). One texel of the relief is 2π/2048 radians of arc.
constant float atlasWidth = 4096.0, atlasHeight = 3072.0;
constant float colourBand = 2048.0 / 3072.0;
/// Metres per grey level of the relief, as printed by the build script, over the Moon's radius
/// (1,737.4 km) and two texels of arc: turns a central difference of grey levels into a slope.
constant float reliefSlopePerLevel = 34.62 / (1737400.0 * 2.0 * (2.0 * M_PI_F / 2048.0));

/// The Moon as a lit sphere, one pixel at a time.
/// - size: the drawing's size in points.
/// - light: (x, y, z, earthshine). The Sun's direction in screen space (x right, y up, z toward
///   the viewer), and how bright the night side glows with light reflected from Earth.
/// - frame: (cos, sin) of the angle from screen-up to the Moon's north pole, then the optical
///   libration in longitude and latitude (radians).
/// - map: NASA's equirectangular lunar colour map, longitude 0 at the centre; or the atlas.
/// - relief: 0 for a smooth sphere; above 0 (atlas only), how strongly the terrain's slopes tilt
///   the incoming sunlight, 1 being real slopes.
/// Reflectance is Lommel–Seeliger, so the full Moon is evenly bright to its edge, as it is.
static half4 moonShade(float2 position, float2 size, float4 light, float4 frame, texture2d<half> map, bool atlas, float relief) {
    float radius = min(size.x, size.y) * 0.5;
    float2 p = (position - size * 0.5) / radius;
    p.y = -p.y;                                     // y up
    float r2 = dot(p, p);
    float edge = 1.5 / radius;                      // about one and a half pixels of soft limb
    float coverage = 1.0 - smoothstep(1.0 - edge, 1.0 + edge, sqrt(r2));
    if (coverage <= 0.0) { return half4(0.0); }
    float3 n = float3(p, sqrt(max(0.0, 1.0 - r2)));

    // Texture lookup happens in the Moon's own frame: rotate so lunar north is up,
    // then apply libration so the side tipped toward us shows.
    float c = frame.x, s = frame.y;
    float3 m = float3(n.x * c + n.y * s, -n.x * s + n.y * c, n.z);
    float bl = frame.w, ll = frame.z;
    float cb = cos(bl), sb = sin(bl), cl = cos(ll), sl = sin(ll);
    float3 m2 = float3(m.x, m.y * cb + m.z * sb, -m.y * sb + m.z * cb);
    float3 m3 = float3(m2.x * cl + m2.z * sl, m2.y, -m2.x * sl + m2.z * cl);
    float longitude = atan2(m3.x, m3.z);
    float latitude = asin(clamp(m2.y, -1.0, 1.0));
    constexpr sampler linearRepeat(filter::linear, address::repeat);
    float2 uv = float2(longitude / (2.0 * M_PI_F) + 0.5, 0.5 - latitude / M_PI_F);
    if (atlas) { uv.y = min(uv.y * colourBand, colourBand - 0.5 / atlasHeight); }   // never bleeds into the relief
    half3 albedo = map.sample(linearRepeat, uv).rgb;

    // Lighting happens in screen space.
    float3 sun = normalize(light.xyz);
    float mu0 = dot(n, sun);                        // cosine of incidence
    float mu = max(n.z, 0.02);                      // cosine of emission, always on the smooth sphere

    // Relief: the terrain's slope tilts the normal for the incidence term only, and only where the
    // Sun is low (near the terminator), where real shadows and lit rims are what the eye sees.
    float weight = relief * (1.0 - smoothstep(0.12, 0.32, abs(mu0)));
    if (atlas && weight > 0.0) {
        float u = fract(uv.x);
        float2 du = float2(1.0 / atlasWidth, 0.0), dv = float2(0.0, 1.0 / atlasHeight);
        float2 h = float2(clamp(u * 0.5, 0.5 / atlasWidth, 0.5 - 0.5 / atlasWidth),
                          clamp(colourBand + (0.5 - latitude / M_PI_F) * (1.0 - colourBand), colourBand + 0.5 / atlasHeight, 1.0 - 0.5 / atlasHeight));
        float east = float(map.sample(linearRepeat, h + du).r - map.sample(linearRepeat, h - du).r) * 255.0;
        float north = float(map.sample(linearRepeat, h - dv).r - map.sample(linearRepeat, h + dv).r) * 255.0;
        float gEast = east * reliefSlopePerLevel / max(cos(latitude), 0.15);
        float gNorth = north * reliefSlopePerLevel;
        // East and north on the sphere, in the Moon's frame, then back to screen space.
        float cp = cos(latitude), sp = sin(latitude), cL = cos(longitude), sL = sin(longitude);
        float3 e3 = float3(cL, 0.0, -sL), n3 = float3(-sp * sL, cp, -sp * cL);
        float3 tilt3 = gEast * e3 + gNorth * n3;
        float3 t2 = float3(tilt3.x * cl - tilt3.z * sl, tilt3.y, tilt3.x * sl + tilt3.z * cl);
        float3 t1 = float3(t2.x, t2.y * cb - t2.z * sb, t2.y * sb + t2.z * cb);
        float3 tilt = float3(t1.x * c - t1.y * s, t1.x * s + t1.y * c, t1.z);
        float3 bumped = normalize(n - weight * tilt);
        mu0 = dot(bumped, sun);
    }
    float lit = mu0 > 0.0 ? 2.0 * mu0 / (mu0 + mu) : 0.0;
    lit *= smoothstep(-0.015, 0.05, mu0);           // the terminator is soft but narrow

    // A gentle lift: the map is a calibrated mosaic, darker than the Moon looks to the eye at night.
    half3 day = albedo * half(1.35 * lit);
    half3 earthshine = albedo * half(light.w) * half3(0.75, 0.85, 1.0);
    half3 rgb = min(day + earthshine, half3(1.0));
    return half4(rgb * half(coverage), half(coverage));
}

/// The Moon on the small colour map (1024×512): every Moon under 120 pt, and the Vision Pro window.
[[ stitchable ]] half4 nyxMoon(float2 position, half4 color, float2 size, float4 light, float4 frame, texture2d<half> map) {
    return moonShade(position, size, light, frame, map, false, 0.0);
}

/// The large Moon on the atlas (`MoonAtlas`): the 4096×2048 colour map, and with `relief` above 0
/// crater shadows and lit rims along the terminator from LOLA's elevation.
[[ stitchable ]] half4 nyxMoonRelief(float2 position, half4 color, float2 size, float4 light, float4 frame, float relief, texture2d<half> map) {
    return moonShade(position, size, light, frame, map, true, relief);
}
