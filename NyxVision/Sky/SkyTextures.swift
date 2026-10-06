import CoreGraphics
import Foundation
import simd

/// The immersive sky's pictures, drawn on device (no image files): how stars look by colour and
/// brightness, soft glows, the sky's colour for any Sun and Moon, and an illustrative skyline.
/// The Milky Way and the star atlas themselves are drawn on the GPU (SkyShaders.metal) once per
/// launch; the sky's colour only when the Sun or Moon has moved enough to change it.
nonisolated enum SkyTextures {
    // MARK: Stars

    /// The atlas: one column per B−V colour, one row per half magnitude of brightness.
    static let starColumns = 16, starRows = 12, starCell = 128
    static func column(forColorIndex bv: Double) -> Int {
        min(starColumns-1, max(0, Int((bv+0.4)/2.4*Double(starColumns))))
    }
    /// Row 0 holds Sirius (−1.5 to −1.0); row 11 everything from magnitude 4.0 to the catalogue's 4.5 limit.
    static func row(forMagnitude m: Double) -> Int { min(starRows-1, max(0, Int(((m+1.5)/0.5).rounded(.down)))) }
    static func magnitude(row: Int) -> Double { -1.25+0.5*Double(row) }

    /// How one brightness row is drawn, in degrees on the sky. A perceptual curve, not linear flux:
    /// each magnitude brightens the peak by 10^(0.24) rather than 10^(0.4), so the brightest star is
    /// about 20 times the faintest instead of 250, which a display can show without crushing the
    /// faint end. Once the peak saturates, a star grows instead: a glare halo, and for the brightest
    /// dozen (brighter than magnitude 1) a faint wide glow, the way bright stars look to the eye.
    struct StarLook: Equatable {
        var peak: Double, core: Double, halo: Double, haloWidth: Double, glow: Double, glowWidth: Double, saturation: Double
        /// Half the quad's width: three widths of the widest part that is drawn.
        var radius: Double { 3*max(core, halo > 0.01 ? haloWidth : 0, glow > 0 ? glowWidth*1.2 : 0, 0.05) }
    }
    static func look(row: Int) -> StarLook {
        let m = magnitude(row: row)
        let flux = 0.34*pow(10, -0.4*0.6*(m-4.25))
        let excess = max(0, flux-1)
        return StarLook(peak: min(1, flux), core: 0.036*(1+0.3*log2(1+excess)),
                        halo: excess > 0 ? 0.1*min(1, excess)+0.035*excess : 0, haloWidth: 0.1+0.05*excess,
                        glow: m < 1 ? 0.012+0.03*min(4, excess) : 0, glowWidth: 0.55+0.05*excess,
                        // Faint stars look white to the eye (rods see no colour); bright ones show it.
                        saturation: 0.4+0.6*smooth((4-m)/4.5))
    }
    /// The quad's full width in degrees for a star of this magnitude.
    static func starSize(magnitude m: Double) -> Double { 2*look(row: row(forMagnitude: m)).radius }

    /// A star's colour from its B−V index: Ballesteros' temperature, then a blackbody's colour
    /// (Helland's fit), normalised so its brightest channel is 1. Linear RGB. Antares reads orange,
    /// Rigel blue-white, the Sun's twins a warm white.
    static func starColor(bv: Double) -> SIMD3<Double> {
        let temperature = 4600*(1/(0.92*bv+1.7)+1/(0.92*bv+0.62))
        let c = blackbody(temperature)
        return c/max(c.x, c.y, c.z)
    }
    static func blackbody(_ kelvin: Double) -> SIMD3<Double> {
        let k = max(10, min(400, kelvin/100))
        let r = k <= 66 ? 255 : 329.698727446*pow(k-60, -0.1332047592)
        let g = k <= 66 ? 99.4708025861*log(k)-161.1195681661 : 288.1221695283*pow(k-60, -0.0755148492)
        let b = k >= 66 ? 255 : k <= 19 ? 0 : 138.5177312231*log(k-10)-305.0447927307
        return SIMD3(linear(r/255), linear(g/255), linear(b/255))
    }

    /// The atlas's parameters for `nyxStarAtlas` (SkyShaders.metal): eight numbers per row
    /// (peak, core, halo, halo width, glow, glow width, saturation, radius) and three per column.
    static func atlasLooks() -> [Float] {
        (0..<starRows).flatMap { row -> [Float] in
            let k = look(row: row)
            return [k.peak, k.core, k.halo, k.haloWidth, k.glow, k.glowWidth, k.saturation, k.radius].map(Float.init)
        }
    }
    static func atlasColors() -> [Float] {
        (0..<starColumns).flatMap { column -> [Float] in
            let c = starColor(bv: -0.4+(Double(column)+0.5)*2.4/Double(starColumns))
            return [Float(c.x), Float(c.y), Float(c.z)]
        }
    }

    /// A soft round glow (planets, the Moon's halo).
    static func glow(size: Int = 128, color: SIMD3<Double>, core: Double = 0.18) -> CGImage? {
        image(width: size, height: size) { x, y in
            let dx = (Double(x)+0.5)/Double(size)-0.5, dy = (Double(y)+0.5)/Double(size)-0.5
            let r = sqrt(dx*dx+dy*dy)*2
            let intensity = (exp(-pow(r/core, 2)) + 0.25*exp(-pow(r/0.5, 2)))*smooth((1-r)/0.3)
            // Opaque: added as light, and a faint alpha would be un-premultiplied into a bright pixel.
            return (color*min(1, intensity), 1)
        }
    }
    /// Moonlight scattered in the air around the Moon: bright close in, a long faint skirt.
    static func aureole(size: Int = 256) -> CGImage? {
        image(width: size, height: size, dither: true) { x, y in
            let dx = (Double(x)+0.5)/Double(size)-0.5, dy = (Double(y)+0.5)/Double(size)-0.5
            let r = sqrt(dx*dx+dy*dy)*2
            let intensity = (0.85/(1+pow(r/0.05, 2)) + 0.15*exp(-pow(r/0.45, 2)))*smooth((1-r)/0.35)
            return (SIMD3(repeating: intensity), 1)
        }
    }

    // MARK: The Milky Way

    /// The Milky Way's texture (drawn by `nyxMilkyWay` in SkyShaders.metal), equirectangular in
    /// galactic coordinates: u is longitude from the anticentre (u = 0.5 is the core, so the seam
    /// falls where the band is faintest and every noise wraps exactly at 360°), v is latitude from
    /// −30° (the image's bottom row) to +30°, fading to nothing over its outer 12°. 0.088° per pixel
    /// along the band, 0.078° across it.
    static let milkyWayWidth = 4096, milkyWayHeight = 768, milkyWayLatitude = 30.0

    // MARK: The sky's colour

    /// What lights the sky at a moment: the Sun's altitude, the park's own sky glow (0 for
    /// Bortle 1, 1 for Bortle 9) and the Moon's glare (0 below the horizon, 1 for a full Moon high).
    struct Light: Equatable { var sunAltitude: Double, skyGlow: Double, moonGlare: Double }

    /// How much a Moon lights the sky: its brightness falls much faster than its lit fraction
    /// (a quarter Moon is about a tenth of a full one), and a Moon low in thick air lights less.
    static func moonGlare(illumination: Double, altitude: Double) -> Double {
        pow(max(0, min(1, illumination)), 2.3)*smooth((altitude+1)/6)*(0.55+0.45*smooth(altitude/35))
    }

    /// The dome, an equirectangular image: u is the angle from the Sun's azimuth (0 at the Sun,
    /// ±180° behind), v is altitude from −10° (bottom) to 90°. Symmetric about the Sun, so only
    /// half is computed.
    static func dome(_ light: Light, width: Int = 128, height: Int = 256, color: (SIMD3<Double>) -> SIMD3<Double>) -> CGImage? {
        let half = width/2
        var cache = [SIMD3<Double>](repeating: .zero, count: half*height)
        for y in 0..<height {
            let altitude = 90-(Double(y)+0.5)/Double(height)*100
            for x in 0..<half {
                let angle = 180-(Double(x)+0.5)/Double(width)*360
                cache[y*half+x] = color(skyColor(altitude: altitude, fromSun: angle, light))
            }
        }
        let colors = cache
        return image(width: width, height: height) { x, y in
            let column = x < half ? x : width-1-x
            return (colors[y*half+column], 1)
        }
    }

    /// The sky's colour in one direction (linear RGB), from the Sun's real altitude:
    /// - night: near black, with airglow (faint green-brown, brightest some degrees up, the van
    ///   Rhijn effect, dimmed again by thick air at the horizon) and the park's own sky glow;
    /// - twilight: a deep-blue zenith over a glow toward the Sun that reddens and sinks as the Sun
    ///   goes down, and while the Sun is just below the horizon the Earth's shadow rising opposite
    ///   it, under the pink Belt of Venus;
    /// - moonlight: the same blue as daylight (it is sunlight), far dimmer, brighter low down.
    /// Also paints the disc behind the Moon, so its night side hides stars without darkening a twilight sky.
    static func skyColor(altitude: Double, fromSun angle: Double, _ light: Light) -> SIMD3<Double> {
        let h = max(0, altitude), s = light.sunAltitude, a = abs(angle)
        let rad = Double.pi/180
        let fromHorizon = 1-h/90

        var rgb = zenith(sunAltitude: s)*(0.6+0.9*pow(fromHorizon, 3))

        // Airglow and the park's sky glow, always there, only visible once twilight has gone.
        let cosine = cos(h*rad)
        let vanRhijn = 1/sqrt(max(0.02, 1-0.9723*cosine*cosine))
        let airmass = 1/(sin(h*rad)+0.15*pow(h+3.885, -1.253))
        let thickAir = exp(-0.04*(airmass-1))
        rgb += SIMD3(0.0002, 0.00032, 0.00018)*pow(vanRhijn-1, 1.6)*thickAir
        rgb += (SIMD3(0.007, 0.0055, 0.004)*exp(-h/8) + SIMD3(0.0003, 0.0003, 0.0004))*light.skyGlow

        // The glow toward the Sun.
        let sunward = glowStrength(sunAltitude: s)
        if sunward > 0 {
            let soft = sqrt(a*a+64)-8   // no cusp straight above the Sun
            let spread = exp(-soft/45)*(0.3+0.7*exp(-a*a/700))
            let deep = smooth((-s-2)/10)   // the glow reddens and flattens as the Sun sinks
            let low = SIMD3(1.0, 0.34-0.12*deep, 0.07-0.03*deep)*1.4*exp(-h/(6-2*deep))
            let mid = SIMD3(1.0, 0.68, 0.32)*0.5*exp(-h/(12-4*deep))
            let high = SIMD3(0.55, 0.65, 0.85)*0.25*exp(-h/28)*(1-deep)
            rgb += (low+mid+high)*sunward*spread*1.8
        }

        // The Earth's shadow and the Belt of Venus, opposite the Sun just after sunset.
        let belt = smooth((s+7)/4)*smooth((3-s)/2)
        if belt > 0 {
            let opposite = exp(-(180-a)/55)
            let top = max(0.5, 1.5-s)
            let shade = 1-0.35*belt*opposite*(1-smooth((h-top)/2.5))
            rgb *= shade
            let pink: Double = 0.36*zenith(sunAltitude: s).z*belt*opposite*exp(-pow((h-top-5)/4.5, 2))
            rgb += SIMD3<Double>(1.0, 0.6, 0.68)*pink
        }

        // Moonlight: blue, brighter toward the horizon.
        rgb += SIMD3(0.0045, 0.0085, 0.024)*light.moonGlare*(0.7+0.6*fromHorizon*fromHorizon)
        return rgb
    }
    /// The sky straight up for a Sun altitude (degrees): blue by day, deep blue at sunset, indigo
    /// through nautical twilight, the night floor once the Sun is 18° down.
    static func zenith(sunAltitude s: Double) -> SIMD3<Double> {
        let stops: [(Double, SIMD3<Double>)] = [
            (5, SIMD3(0.16, 0.28, 0.6)), (2, SIMD3(0.1, 0.18, 0.42)), (0, SIMD3(0.06, 0.11, 0.28)), (-3, SIMD3(0.028, 0.05, 0.15)),
            (-6, SIMD3(0.009, 0.015, 0.055)), (-9, SIMD3(0.003, 0.0045, 0.016)), (-12, SIMD3(0.0012, 0.0016, 0.0045)),
            (-15, SIMD3(0.0008, 0.001, 0.0022)), (-18, nightZenith),
        ]
        return interpolate(stops, s)
    }
    static let nightZenith = SIMD3(0.0007, 0.0009, 0.0016)
    static func glowStrength(sunAltitude s: Double) -> Double {
        let stops: [(Double, SIMD3<Double>)] = [(5, SIMD3(repeating: 1.1)), (0, SIMD3(repeating: 0.9)), (-3, SIMD3(repeating: 0.55)), (-6, SIMD3(repeating: 0.22)),
                                                (-9, SIMD3(repeating: 0.07)), (-12, SIMD3(repeating: 0.02)), (-15, SIMD3(repeating: 0.005)), (-18, .zero)]
        return interpolate(stops, s).x
    }
    private static func interpolate(_ stops: [(Double, SIMD3<Double>)], _ s: Double) -> SIMD3<Double> {
        guard s < stops[0].0 else { return stops[0].1 }
        guard s > stops[stops.count-1].0 else { return stops[stops.count-1].1 }
        for (upper, lower) in zip(stops, stops.dropFirst()) where s > lower.0 {
            let t = (upper.0-s)/(upper.0-lower.0)
            return upper.1+(lower.1-upper.1)*t
        }
        return stops[stops.count-1].1
    }

    // MARK: The skyline

    /// An illustrative skyline for a park, the height of the land in degrees every half degree of
    /// azimuth (721 values, the last equal to the first). Seeded by the park, so each place keeps
    /// its own; not surveyed terrain, and the plaque says so. `far` is the higher, hazier range.
    static func skyline(seed: String, far: Bool) -> [Double] {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in (seed+(far ? "-far" : "-near")).utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        let offset = Float(hash % 997)
        var heights: [Double] = []
        for i in 0...720 {
            let x = Float(i)/720
            let n = smooth((Double(fbm(x*7, offset+0.5, octaves: 6, period: 7))-0.28)/0.44)
            heights.append(far ? 0.4+3.6*pow(n, 1.3) : 0.15+1.6*pow(n, 1.8))
        }
        return heights
    }

    /// A hard-edged white disc for alpha testing.
    static func disc(size: Int = 64) -> CGImage? {
        image(width: size, height: size) { x, y in
            let dx = (Double(x)+0.5)/Double(size)-0.5, dy = (Double(y)+0.5)/Double(size)-0.5
            let inside = sqrt(dx*dx+dy*dy) < 0.49 ? 1.0 : 0
            return (SIMD3(repeating: inside), inside)
        }
    }

    // MARK: Drawing

    static func smooth(_ x: Double) -> Double { let t = min(1, max(0, x)); return t*t*(3-2*t) }
    static func linear(_ s: Double) -> Double { s <= 0.04045 ? s/12.92 : pow((s+0.055)/1.055, 2.4) }

    /// Gradient noise in about 0…1, deterministic, wrapping every `period` cells in x, so the same
    /// Milky Way appears every launch and nothing seams at 360°.
    static func noise(_ x: Float, _ y: Float, period: Int) -> Float {
        let fx = x.rounded(.down), fy = y.rounded(.down)
        let i = Int(fx), j = Int(fy), tx = x-fx, ty = y-fy
        let i0 = ((i % period)+period) % period, i1 = (i0+1) % period
        func gradient(_ i: Int, _ j: Int, _ dx: Float, _ dy: Float) -> Float {
            var h = UInt32(truncatingIfNeeded: i &* 374_761_393 &+ j &* 668_265_263)
            h = (h ^ (h >> 13)) &* 1_274_126_177
            let g = gradients[Int((h ^ (h >> 16)) & 63)]
            return g.x*dx+g.y*dy
        }
        let u = tx*tx*tx*(tx*(tx*6-15)+10), v = ty*ty*ty*(ty*(ty*6-15)+10)
        let a = gradient(i0, j, tx, ty), b = gradient(i1, j, tx-1, ty)
        let c = gradient(i0, j+1, tx, ty-1), d = gradient(i1, j+1, tx-1, ty-1)
        let top = a+(b-a)*u, bottom = c+(d-c)*u
        return 0.5+0.75*(top+(bottom-top)*v)
    }
    private static let gradients: [SIMD2<Float>] = (0..<64).map { SIMD2(cos(Float($0)*Float.pi/32), sin(Float($0)*Float.pi/32)) }
    /// Fractal noise: octaves of `noise`, each twice as fine and half as strong, normalised to about 0…1.
    static func fbm(_ x: Float, _ y: Float, octaves: Int, period: Int) -> Float {
        var sum: Float = 0, amplitude: Float = 1, total: Float = 0, scale: Float = 1, p = period
        for octave in 0..<octaves {
            sum += amplitude*noise(x*scale, y*scale+Float(octave)*17.3, period: p)
            total += amplitude
            amplitude *= 0.5; scale *= 2; p *= 2
        }
        return max(0, min(1, sum/total))
    }

    /// sRGB-encodes, optionally with half a step of ordered dither so a smooth dark gradient seen
    /// at about its own resolution (the Moon's aureole) does not band. Not for the dome, whose
    /// texels are degrees wide and would show the pattern.
    private static func encode(_ linear: Double, _ x: Int, _ y: Int, dither: Bool) -> UInt8 {
        let c = min(1, max(0, linear))
        let s = c <= 0.0031308 ? 12.92*c : 1.055*pow(c, 1/2.4)-0.055
        guard dither else { return UInt8((s*255).rounded()) }
        let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5][(y & 3)*4+(x & 3)]
        return UInt8(max(0, min(255, (s*255+(Double(bayer)+0.5)/16-0.5).rounded())))
    }
    /// An sRGB image from a per-pixel function returning premultiplied linear colour and alpha
    /// (0…1). Rows are drawn in parallel; the function must be safe to call from any thread.
    static func image(width: Int, height: Int, dither: Bool = false, pixel: @Sendable (Int, Int) -> (SIMD3<Double>, Double)) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width*height*4)
        bytes.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let base = buffer
            let bands = min(height, 32)
            DispatchQueue.concurrentPerform(iterations: bands) { band in
                for y in stride(from: band, to: height, by: bands) {
                    for x in 0..<width {
                        let (rgb, alpha) = pixel(x, y)
                        let i = (y*width+x)*4
                        base[i] = encode(rgb.x, x, y, dither: dither); base[i+1] = encode(rgb.y, x, y, dither: dither); base[i+2] = encode(rgb.z, x, y, dither: dither)
                        base[i+3] = UInt8((min(1, max(0, alpha))*255).rounded())
                    }
                }
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent)
    }
}
