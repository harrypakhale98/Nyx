import Foundation
import simd

/// The geometry of standing under a park's sky, for the Vision Pro immersive space: where a body
/// at an altitude and azimuth sits around the viewer, how the whole celestial sphere turns for a
/// moment (so the stars are built once and only a rotation changes while the night is scrubbed),
/// how a scrub position maps to a time, and how bright twilight leaves the sky.
/// Shared with the iPhone app only so its tests can check it against `AstronomyEngine`.
///
/// World frame (RealityKit): x to the viewer's right, y up, −z ahead. Ahead is the `facing`
/// azimuth, not the real north: the immersive sky is not aligned to the room.
nonisolated enum SkyDome {
    private static let rad = Double.pi/180

    /// South ahead in the northern hemisphere, north in the southern: the Milky Way's core, the
    /// Moon and the planets cross that half of the sky, so the view opens on what moves.
    static func facing(for park: Park) -> Double { park.latitude < 0 ? 0 : 180 }

    /// Unit direction in the world frame for an altitude and azimuth (degrees, azimuth from north
    /// through east), with `facing` straight ahead.
    static func direction(altitude: Double, azimuth: Double, facing: Double) -> SIMD3<Double> {
        let alt = altitude*rad, d = (azimuth-facing)*rad
        return SIMD3(cos(alt)*sin(d), sin(alt), -cos(alt)*cos(d))
    }
    /// Altitude and azimuth (degrees) of a world direction: the inverse of `direction`.
    static func horizontal(of v: SIMD3<Double>, facing: Double) -> (altitude: Double, azimuth: Double) {
        let n = simd_normalize(v)
        let az = atan2(n.x, -n.z)/rad + facing
        return (asin(max(-1, min(1, n.y)))/rad, az - floor(az/360)*360)
    }
    /// Celestial unit vector: x toward RA 0 on the equator, z toward the north celestial pole.
    static func celestial(ra: Double, dec: Double) -> SIMD3<Double> {
        SIMD3(cos(dec)*cos(ra), cos(dec)*sin(ra), sin(dec))
    }
    /// Local mean sidereal time (radians), the same expression `AstronomyEngine` uses.
    static func localSiderealTime(_ date: Date, longitude: Double) -> Double {
        let jd = date.timeIntervalSince1970/86400 + 2440587.5
        let t = (jd-2451545)/36525
        let degrees = 280.46061837 + 360.98564736629*(jd-2451545) + 0.000387933*t*t - t*t*t/38710000 + longitude
        return (degrees - floor(degrees/360)*360)*rad
    }
    /// The rotation that carries celestial vectors into the world frame at a moment: turn the
    /// sphere by sidereal time, tip it by the park's latitude, then face `facing`. A proper
    /// rotation (determinant 1), so it can drive an entity's orientation.
    static func rotation(at date: Date, latitude: Double, longitude: Double, facing: Double) -> simd_double3x3 {
        let lst = localSiderealTime(date, longitude: longitude)
        let spin = simd_double3x3(rows: [SIMD3(cos(lst), sin(lst), 0), SIMD3(-sin(lst), cos(lst), 0), SIMD3(0, 0, 1)])
        let phi = latitude*rad
        // East, north, up from the turned celestial frame.
        let local = simd_double3x3(rows: [SIMD3(0, 1, 0), SIMD3(-sin(phi), 0, cos(phi)), SIMD3(cos(phi), 0, sin(phi))])
        let f = facing*rad
        let world = simd_double3x3(rows: [SIMD3(cos(f), -sin(f), 0), SIMD3(0, 0, 1), SIMD3(-sin(f), -cos(f), 0)])
        return world*local*spin
    }
    static func rotation(at date: Date, park: Park) -> simd_double3x3 {
        rotation(at: date, latitude: park.latitude, longitude: park.longitude, facing: facing(for: park))
    }
    /// Galactic to equatorial (J2000, radians), from the north galactic pole (RA 192.859°, Dec +27.128°).
    static func equatorial(galacticLongitude l: Double, latitude b: Double) -> (ra: Double, dec: Double) {
        let poleRA = 192.85948*rad, poleDec = 27.12825*rad, node = 122.93192*rad
        let dec = asin(max(-1, min(1, sin(b)*sin(poleDec) + cos(b)*cos(poleDec)*cos(node-l))))
        let ra = poleRA + atan2(cos(b)*sin(node-l), sin(b)*cos(poleDec) - cos(b)*sin(poleDec)*cos(node-l))
        return (ra - floor(ra/(2*Double.pi))*2*Double.pi, dec)
    }

    // MARK: Scrubbing a night

    /// The stretch a night's scrub covers: sunset to sunrise. Under the polar night, 4 pm to 8 am
    /// park time; under the midnight sun, the 10 pm–2 am window the rest of the app uses.
    static func span(for sky: SkyConditions) -> DateInterval {
        if let sunset = sky.sunset, let sunrise = sky.sunrise, sunrise > sunset { return DateInterval(start: sunset, end: sunrise) }
        if sky.state == .polarNight { return DateInterval(start: sky.evening.addingTimeInterval(4*3600), end: sky.evening.addingTimeInterval(20*3600)) }
        let window = sky.cloudWindow
        return DateInterval(start: window.start, end: max(window.start, window.end))
    }
    /// The moment at a scrub position (0 at the start of the span, 1 at its end; clamped).
    static func moment(_ fraction: Double, in span: DateInterval) -> Date {
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return span.start.addingTimeInterval(span.duration*f)
    }
    /// The scrub position of a moment: the inverse of `moment`.
    static func fraction(of date: Date, in span: DateInterval) -> Double {
        guard span.duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(span.start)/span.duration))
    }
    /// Where a night opens: the middle of true darkness, else the middle of the span.
    static func darkest(_ sky: SkyConditions) -> Date {
        if let a = sky.darkStart, let b = sky.darkEnd, b > a { return a.addingTimeInterval(b.timeIntervalSince(a)/2) }
        let s = span(for: sky)
        return s.start.addingTimeInterval(s.duration/2)
    }

    // MARK: Twilight

    /// How much of a class of stars twilight leaves visible (0…1), from the Sun's altitude in
    /// degrees. Bright stars appear around the end of civil twilight; the faintest catalogue stars
    /// near nautical; the Milky Way only as astronomical twilight ends.
    enum Layer: Sendable { case bright, middle, faint, milkyWay }
    static func visibility(_ layer: Layer, sunAltitude: Double) -> Double {
        let (from, to): (Double, Double) = switch layer {
        case .bright: (-3, -8)
        case .middle: (-6, -12)
        case .faint: (-9, -15)
        case .milkyWay: (-12, -18)
        }
        return smooth((from-sunAltitude)/(from-to))
    }
    /// The sky's colour away from the Sun (linear RGB, 0…1): deep blue at sunset, indigo through
    /// nautical twilight, black once the Sun is 18° down.
    static func skyColor(sunAltitude: Double) -> SIMD3<Double> {
        let stops: [(Double, SIMD3<Double>)] = [
            (5, SIMD3(0.32, 0.46, 0.72)), (0, SIMD3(0.20, 0.27, 0.48)), (-6, SIMD3(0.055, 0.07, 0.18)),
            (-12, SIMD3(0.012, 0.016, 0.05)), (-18, SIMD3(0, 0, 0.004)),
        ]
        guard sunAltitude < stops[0].0 else { return stops[0].1 }
        guard sunAltitude > stops[stops.count-1].0 else { return stops[stops.count-1].1 }
        for (upper, lower) in zip(stops, stops.dropFirst()) where sunAltitude > lower.0 {
            let t = (upper.0-sunAltitude)/(upper.0-lower.0)
            return upper.1 + (lower.1-upper.1)*t
        }
        return stops[stops.count-1].1
    }
    private static func smooth(_ x: Double) -> Double { let t = min(1, max(0, x)); return t*t*(3-2*t) }
}
