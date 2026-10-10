import Foundation
import simd

/// The Moon shader's rules (`Moon.metal`), shared by the iPhone's `MoonView`, the Vision Pro
/// window's `VisionMoon` and the Vision Pro Moon volume's globe, so every large Moon in Nyx draws
/// on the same map with the same relief.
nonisolated enum MoonShading {
    /// From this size (points) a Moon draws on `MoonAtlas`, the 4096×2048 colour map with LOLA's
    /// relief; below it, on the 1024×512 `MoonMap`.
    static let atlasSide = 120.0
    /// The terrain's slopes, exaggerated 2.5 times: at 280 pt one texel of relief is about a point,
    /// and real slopes at that scale only show at the very edge of the terminator. The globe's
    /// normal map is baked with the same factor (`Scripts/build_moon_globe.swift`).
    static let reliefStrength = 2.5
    static func usesAtlas(side: Double) -> Bool { side >= atlasSide }
    /// The Sun's direction in screen space (x right, y up, z toward the viewer).
    static func sunDirection(_ geometry: MoonGeometry) -> SIMD3<Double> {
        let i = geometry.phaseAngle, a = geometry.brightLimb
        return SIMD3(sin(i) * -sin(a), sin(i)*cos(a), cos(i))
    }
    /// Within this phase angle of full the globe drops its relief, as the shader's relief fades
    /// out between 35° and 20° from opposition (the shadows hide behind the terrain that casts
    /// them). A material's normal map cannot fade, so the globe switches at the middle, 27.5°.
    static let globeReliefPhaseAngle = 27.5*Double.pi/180
    static func globeShowsRelief(_ geometry: MoonGeometry) -> Bool { geometry.phaseAngle >= globeReliefPhaseAngle }
}

/// The Moon volume's globe as a grid of longitude and latitude, mapped so its texture lookup is
/// exactly the Moon shader's: longitude 0 (the mean near side) toward +z, east toward +x, north
/// up (+y). The shader samples (longitude/2π + 0.5, 0.5 − latitude/π) from the image's top-left;
/// RealityKit's texture coordinates run up from the image's bottom, so the grid's v is
/// latitude/π + 0.5, the same texel.
nonisolated enum MoonGlobeGrid {
    struct Vertex: Equatable {
        /// On the unit sphere; the mesh scales it by the globe's radius.
        let normal: SIMD3<Float>
        /// Toward lunar east (+u): the normal map's red axis.
        let tangent: SIMD3<Float>
        /// Toward lunar north (+v): the normal map's green axis.
        let bitangent: SIMD3<Float>
        let uv: SIMD2<Float>
    }
    static func vertex(column i: Int, row j: Int, columns: Int, rows: Int) -> Vertex {
        let lon = (Double(i)/Double(columns)-0.5)*2*Double.pi
        let lat = (Double(j)/Double(rows)-0.5)*Double.pi
        let n = SIMD3(cos(lat)*sin(lon), sin(lat), cos(lat)*cos(lon))
        let east = SIMD3(cos(lon), 0, -sin(lon))
        let north = SIMD3(-sin(lat)*sin(lon), cos(lat), -sin(lat)*cos(lon))
        return Vertex(normal: SIMD3<Float>(n), tangent: SIMD3<Float>(east), bitangent: SIMD3<Float>(north),
                      uv: SIMD2(Float(i)/Float(columns), Float(j)/Float(rows)))
    }
    /// The shader's lookup for a direction in the Moon's frame, from the image's top-left
    /// (`Moon.metal`: longitude = atan2(x, z), latitude = asin(y)).
    static func shaderUV(_ m: SIMD3<Double>) -> SIMD2<Double> {
        let longitude = atan2(m.x, m.z), latitude = asin(max(-1, min(1, m.y)))
        return SIMD2(longitude/(2*Double.pi)+0.5, 0.5-latitude/Double.pi)
    }
}
