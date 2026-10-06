import CoreGraphics
import Foundation

/// The immersive sky's pictures, drawn on device at launch (no image files): a strip of star
/// glows by colour, the Milky Way's band, a soft glow, and the twilight dome.
nonisolated enum SkyTextures {
    /// B−V colour buckets in the star strip, blue-white (−0.4) to deep orange (2.0).
    static let starColumns = 16
    static func column(forColorIndex bv: Double) -> Int {
        min(starColumns-1, max(0, Int((bv+0.4)/2.4*Double(starColumns))))
    }
    /// A star's colour from its B−V index (Ballesteros' temperature, a gentle tint over
    /// starlight), as the iPhone's real sky draws it.
    static func starColor(bv: Double) -> SIMD3<Double> {
        let temperature = 4600*(1/(0.92*bv+1.7)+1/(0.92*bv+0.62))
        let warmth = max(-1, min(1, (6500-temperature)/3500))
        let tint = warmth > 0 ? SIMD3(1, 1-0.22*warmth, 1-0.5*warmth) : SIMD3(1+0.3*warmth, 1+0.12*warmth, 1)
        let starlight = SIMD3(0.961, 0.945, 0.902)
        return tint*0.7 + starlight*0.3
    }

    /// One row of glowing points, one cell per colour: a tight core and a faint halo, fading to
    /// nothing well inside the cell so mipmaps never bleed one colour into the next.
    static func starStrip(cell: Int = 64, color: (SIMD3<Double>) -> SIMD3<Double>) -> CGImage? {
        image(width: cell*starColumns, height: cell) { x, y in
            let column = x/cell
            let bv = -0.4 + (Double(column)+0.5)*2.4/Double(starColumns)
            let dx = (Double(x % cell)+0.5)/Double(cell)-0.5, dy = (Double(y)+0.5)/Double(cell)-0.5
            let r = sqrt(dx*dx+dy*dy)*2
            let intensity = glowProfile(r)
            return (color(starColor(bv: bv))*intensity, intensity)
        }
    }
    static func glowProfile(_ r: Double) -> Double {
        let core = exp(-pow(r/0.2, 2)), halo = 0.18*exp(-pow(r/0.5, 2))
        return (core+halo)*smooth((1-r)/0.25)
    }
    /// A soft round glow (planets, the Moon's halo).
    static func glow(size: Int = 128, color: SIMD3<Double>, core: Double = 0.18) -> CGImage? {
        image(width: size, height: size) { x, y in
            let dx = (Double(x)+0.5)/Double(size)-0.5, dy = (Double(y)+0.5)/Double(size)-0.5
            let r = sqrt(dx*dx+dy*dy)*2
            let intensity = (exp(-pow(r/core, 2)) + 0.25*exp(-pow(r/0.5, 2)))*smooth((1-r)/0.3)
            return (color*min(1, intensity), min(1, intensity))
        }
    }

    /// The Milky Way along the galactic plane: u is galactic longitude from the anticentre
    /// (u = 0.5 is the core, so the texture's seam falls where the band is faintest), v is
    /// galactic latitude from −20° (v = 0, the image's bottom row) to +20°. A smooth model, not a photograph: brightest and
    /// widest toward the core in Sagittarius, star clouds in Cygnus and Carina, the Great Rift's
    /// dust lane from Cygnus to Sagittarius, and a gentle mottling.
    static func milkyWay(width: Int = 2048, height: Int = 256, color: (SIMD3<Double>) -> SIMD3<Double>) -> CGImage? {
        image(width: width, height: height) { x, y in
            let l = ((Double(x)+0.5)/Double(width)*360+180).truncatingRemainder(dividingBy: 360), b = 20-(Double(y)+0.5)/Double(height)*40
            let intensity = milkyWayIntensity(l: l, b: b)
            let toCore = pow((1+cos(l*Double.pi/180))/2, 3)
            let tint = SIMD3(0.74, 0.8, 1.0)*(1-toCore) + SIMD3(1.0, 0.9, 0.74)*toCore
            return (color(tint)*intensity, intensity)
        }
    }
    static func milkyWayIntensity(l: Double, b: Double) -> Double {
        let rad = Double.pi/180
        func bump(_ centre: Double, _ width: Double) -> Double {
            let d = (l-centre+540).truncatingRemainder(dividingBy: 360)-180
            return exp(-pow(d/width, 2))
        }
        let toCore = pow((1+cos(l*rad))/2, 3)
        // Star clouds: Sagittarius and Scutum by the core, Cygnus, Carina, and the fainter winter arm.
        let base = 0.12 + 0.8*toCore + 0.32*bump(78, 13) + 0.25*bump(287, 11) + 0.18*bump(27, 6) + 0.1*bump(330, 18) + 0.06*bump(150, 40)
        let sigma = 2.4 + 5.6*pow((1+cos(l*rad))/2, 5)
        var value = base*exp(-b*b/(2*sigma*sigma))
        // The bulge stands a little south of the plane toward Sagittarius.
        value += 0.35*toCore*bump(4, 9)*exp(-pow((b+4)/4.5, 2))
        // Fades to nothing before the mesh's edge at ±20°.
        value *= smooth((20-abs(b))/6)
        // Mottling at three scales, then the dust: the Great Rift from Cygnus to Sagittarius and
        // softer lanes along the plane, strongest toward the core. Noise wraps every 360°.
        let mottle = 0.55*noise(l/6, b/2.2, period: 60) + 0.3*noise(l/2, b/0.9+17, period: 180) + 0.15*noise(l/0.8, b/0.45+41, period: 450)
        value *= 0.68 + 0.5*mottle
        let rift = (bump(45, 30)+0.7*bump(8, 10))*exp(-pow((b-1.4)/1.7, 2))*(0.75+0.25*noise(l/1.5, b/0.8+5, period: 240))
        let lanes = smooth((noise(l/1.5+90, b/0.8, period: 240)-0.4)/0.45)*exp(-pow(b/2.5, 2))*(0.3+0.7*toCore)
        value *= (1 - 0.7*min(1, rift))*(1 - 0.3*lanes)
        return max(0, min(1, pow(max(0, value), 1.25)))
    }

    /// The twilight dome, an equirectangular strip: u is the angle from the Sun's azimuth
    /// (0 at the Sun, ±180° behind), v is altitude from −10° to 90°. Brighter toward the horizon
    /// and toward the Sun while it is less than 18° down.
    /// At night the horizon still glows faintly (airglow, and the park's own sky glow from its
    /// Bortle class), so the dark ground stands out against it as it does under a real sky.
    static func dome(sunAltitude: Double, skyGlow: Double, moonlight: Double, width: Int = 96, height: Int = 48, color: (SIMD3<Double>) -> SIMD3<Double>) -> CGImage? {
        image(width: width, height: height) { x, y in
            let angle = abs((Double(x)+0.5)/Double(width)*360-180)
            let altitude = 90-(Double(y)+0.5)/Double(height)*100
            return (color(skyColor(altitude: altitude, fromSun: angle, sunAltitude: sunAltitude, skyGlow: skyGlow, moonlight: moonlight)), 1)
        }
    }
    /// The dome's colour in one direction (linear RGB): the twilight base, brighter toward the
    /// horizon and the Sun, plus airglow, the park's sky glow and moonlight. Also paints the disc
    /// behind the Moon, so the Moon's night side hides stars without darkening a twilight sky.
    static func skyColor(altitude: Double, fromSun angle: Double, sunAltitude: Double, skyGlow: Double, moonlight: Double) -> SIMD3<Double> {
        let base = SkyDome.skyColor(sunAltitude: sunAltitude), glow = SkyDome.skyColor(sunAltitude: sunAltitude+5)
        let glowing = sunAltitude > -18 ? 1-max(0, -sunAltitude-6)/12 : 0
        let horizon = pow(1-max(0, altitude)/90, 3)
        var rgb = base*(0.55+0.45*horizon)
        rgb += glow*0.9*glowing*exp(-angle/40)*pow(1-max(0, altitude)/90, 6)
        let low = exp(-max(0, altitude)/9)
        rgb += (SIMD3(0.016, 0.019, 0.026) + SIMD3(0.03, 0.022, 0.012)*skyGlow)*low
        // A bright Moon lifts the whole sky toward a pale blue-grey.
        rgb += SIMD3(0.018, 0.026, 0.045)*moonlight*(0.6+0.4*horizon)
        return rgb
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

    private static func smooth(_ x: Double) -> Double { let t = min(1, max(0, x)); return t*t*(3-2*t) }
    /// Smooth value noise in 0…1, deterministic, so the same Milky Way appears every launch.
    static func noise(_ x: Double, _ y: Double, period: Int = .max) -> Double {
        func hash(_ i: Int, _ j: Int) -> Double {
            var h = UInt64(bitPattern: Int64(i &* 374_761_393 &+ j &* 668_265_263))
            h = (h ^ (h >> 13)) &* 1_274_126_177
            return Double((h ^ (h >> 16)) & 0xFFFF)/65535
        }
        func wrap(_ i: Int) -> Int { period == .max ? i : ((i % period)+period) % period }
        let i = Int(floor(x)), j = Int(floor(y)), fx = x-floor(x), fy = y-floor(y)
        let u = fx*fx*(3-2*fx), v = fy*fy*(3-2*fy)
        let top = hash(wrap(i), j)*(1-u)+hash(wrap(i+1), j)*u, bottom = hash(wrap(i), j+1)*(1-u)+hash(wrap(i+1), j+1)*u
        return top*(1-v)+bottom*v
    }
    /// An sRGB image from a per-pixel function returning premultiplied colour and alpha (0…1).
    static func image(width: Int, height: Int, pixel: (Int, Int) -> (SIMD3<Double>, Double)) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width*height*4)
        func encode(_ linear: Double) -> UInt8 {
            let c = min(1, max(0, linear))
            let s = c <= 0.0031308 ? 12.92*c : 1.055*pow(c, 1/2.4)-0.055
            return UInt8((s*255).rounded())
        }
        for y in 0..<height {
            for x in 0..<width {
                let (rgb, alpha) = pixel(x, y)
                let i = (y*width+x)*4
                bytes[i] = encode(rgb.x); bytes[i+1] = encode(rgb.y); bytes[i+2] = encode(rgb.z)
                bytes[i+3] = UInt8((min(1, max(0, alpha))*255).rounded())
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent)
    }
}
