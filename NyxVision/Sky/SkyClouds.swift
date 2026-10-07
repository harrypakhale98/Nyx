import CoreGraphics
import Foundation
import simd

/// The immersive sky's forecast clouds: a soft deck whose share of the sky is the forecast's cover
/// at that hour (`SkyDome.cloud`). Only the amount is the forecast's; the shapes are noise, and
/// the window and the plaque say so. Drawn once per tenth of cover and kept, so scrubbing a night
/// only swaps a texture.
nonisolated enum SkyClouds {
    /// Azimuth (360°) by altitude, from `bottom` to the zenith (row 0).
    static let width = 768, height = 192
    static let bottom = -2.0
    /// The deck sits just behind the skyline (22 and 25 m), so ridges stand in front of it, and in
    /// front of the Moon (28 m), the stars (30 m) and the Milky Way (34 m), which it can cover.
    static let radius: Float = 26
    /// The thickest cloud never quite hides everything behind it: a deck seen from below is uneven.
    static let peak = 0.82

    static func altitude(row y: Int) -> Double { 90-(Double(y)+0.5)/Double(height)*(90-bottom) }

    /// The deck seen from the ground: a layer, so clouds overhead look larger and those near the
    /// horizon crowd together, as real ones do. The distance along the layer is softened (r^0.65):
    /// a true flat plane left one blob overhead and streaks at the horizon. Noise of about 0…1 per
    /// pixel, seamless at 360° because the azimuth wraps on the plane.
    static let field: [Float] = {
        var values = [Float](repeating: 0, count: width*height)
        values.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let base = buffer
            DispatchQueue.concurrentPerform(iterations: height) { y in
                // Below about 4° the plane is too far to sample; the horizon blend takes over there.
                let a = max(4, altitude(row: y))*Double.pi/180
                let r = 2.2*pow(cos(a)/sin(a), 0.65)
                for x in 0..<width {
                    let azimuth = (Double(x)+0.5)/Double(width)*2*Double.pi
                    let px = Float(r*sin(azimuth)), py = Float(r*cos(azimuth))
                    base[y*width+x] = SkyTextures.fbm(px+31.7, py+11.3, octaves: 5, period: 64)
                }
            }
        }
        return values
    }()
    /// The field's values above 8°, sorted, with each one's share of the sky (rows nearer the
    /// zenith cover less of it), for `threshold`.
    private static let distribution: [(value: Float, weight: Double)] = {
        var samples: [(Float, Double)] = []
        for y in 0..<height {
            let a = altitude(row: y)
            guard a >= 8 else { continue }
            let w = cos(a*Double.pi/180)
            for x in stride(from: 0, to: width, by: 2) { samples.append((field[y*width+x], w)) }
        }
        let total = samples.reduce(0) { $0+$1.1 }
        return samples.sorted { $0.0 < $1.0 }.map { ($0.0, $0.1/max(total, 1e-9)) }
    }()
    /// The noise level above which `cover` of the sky lies.
    static func threshold(cover: Double) -> Float {
        var below = 0.0
        for sample in distribution {
            below += sample.weight
            if below >= 1-cover { return sample.value }
        }
        return distribution.last?.value ?? 1
    }
    /// One tenth of cover (3…10) as an image: white, its alpha the cloud. Near the horizon the
    /// eye looks through many miles of deck, so the gaps close: there the alpha is the chance
    /// that three clouds in a row all miss, 1 − (1 − cover)³.
    static func image(tenths: Int) -> CGImage? {
        let cover = min(1, max(0, Double(tenths)/10))
        let t = threshold(cover: cover), soft: Float = 0.05
        let through = 1-pow(1-cover, 3)
        return SkyTextures.image(width: width, height: height) { x, y in
            let n = field[y*width+x], a = altitude(row: y)
            let edge = SkyTextures.smooth(Double((n-t+soft)/(2*soft)))
            // Thicker toward a cloud's heart, so a deck reads as clouds rather than a stencil.
            let body = edge*(0.55+0.45*SkyTextures.smooth(Double((n-t)/0.12)))
            let w = SkyTextures.smooth((a-3)/14)
            let alpha = peak*(w*(cover >= 1 ? 1 : body)+(1-w)*through)
            // Premultiplied white: encoded, its colour equals its alpha, so it un-premultiplies to white.
            return (SIMD3(repeating: SkyTextures.linear(alpha)), alpha)
        }
    }
    /// The deck's colour (linear): clouds hide the stars and airglow above them and are lit from
    /// below by whatever lights the land, almost nothing at a dark park and a dull orange over a
    /// bright one. In twilight and moonlight they take the sky's own light.
    static func color(_ light: SkyTextures.Light) -> SIMD3<Double> {
        SkyTextures.skyColor(altitude: 35, fromSun: 120, light)*0.75+SIMD3(0.010, 0.0065, 0.0035)*pow(light.skyGlow, 1.5)
    }
}
