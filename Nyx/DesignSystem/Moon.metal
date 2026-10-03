#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// The Moon as a lit sphere, one pixel at a time.
/// - size: the drawing's size in points.
/// - light: (x, y, z, earthshine). The Sun's direction in screen space (x right, y up, z toward
///   the viewer), and how bright the night side glows with light reflected from Earth.
/// - frame: (cos, sin) of the angle from screen-up to the Moon's north pole, then the optical
///   libration in longitude and latitude (radians).
/// - map: NASA's equirectangular lunar colour map, longitude 0 at the centre.
/// Reflectance is Lommel–Seeliger, so the full Moon is evenly bright to its edge, as it is.
[[ stitchable ]] half4 nyxMoon(float2 position, half4 color, float2 size, float4 light, float4 frame, texture2d<half> map) {
    float radius = min(size.x, size.y) * 0.5;
    float2 p = (position - size * 0.5) / radius;
    p.y = -p.y;                                     // y up
    float r2 = dot(p, p);
    float edge = 1.5 / radius;                      // about one and a half pixels of soft limb
    float coverage = 1.0 - smoothstep(1.0 - edge, 1.0 + edge, sqrt(r2));
    if (coverage <= 0.0) { return half4(0.0); }
    float3 n = float3(p, sqrt(max(0.0, 1.0 - r2)));

    // Lighting happens in screen space.
    float3 sun = normalize(light.xyz);
    float mu0 = dot(n, sun);                        // cosine of incidence
    float mu = max(n.z, 0.02);                      // cosine of emission
    float lit = mu0 > 0.0 ? 2.0 * mu0 / (mu0 + mu) : 0.0;
    lit *= smoothstep(-0.015, 0.05, mu0);           // the terminator is soft but narrow

    // Texture lookup happens in the Moon's own frame: rotate so lunar north is up,
    // then apply libration so the side tipped toward us shows.
    float c = frame.x, s = frame.y;
    float3 m = float3(n.x * c + n.y * s, -n.x * s + n.y * c, n.z);
    float bl = frame.w, ll = frame.z;
    float3 m2 = float3(m.x, m.y * cos(bl) + m.z * sin(bl), -m.y * sin(bl) + m.z * cos(bl));
    float3 m3 = float3(m2.x * cos(ll) + m2.z * sin(ll), m2.y, -m2.x * sin(ll) + m2.z * cos(ll));
    float longitude = atan2(m3.x, m3.z);
    float latitude = asin(clamp(m2.y, -1.0, 1.0));
    constexpr sampler linearRepeat(filter::linear, address::repeat);
    float2 uv = float2(longitude / (2.0 * M_PI_F) + 0.5, 0.5 - latitude / M_PI_F);
    half3 albedo = map.sample(linearRepeat, uv).rgb;

    // A gentle lift: the map is a calibrated mosaic, darker than the Moon looks to the eye at night.
    half3 day = albedo * half(1.35 * lit);
    half3 earthshine = albedo * half(light.w) * half3(0.75, 0.85, 1.0);
    half3 rgb = min(day + earthshine, half3(1.0));
    return half4(rgb * half(coverage), half(coverage));
}
