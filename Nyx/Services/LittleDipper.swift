import Foundation

/// The Little Dipper count: how many of the asterism's seven stars the eye should find on a night,
/// the field astronomer's quick test of a sky. Always an estimate, worked out from the park's
/// Bortle estimate, the night's moonlight and air, never measured.
///
/// **The sky's own glow.** A Bortle class becomes a zenith brightness by the middle of its SQM range
/// (Bortle 2001, Sky & Telescope, as tabulated by Dark Skies Awareness; the table `SkyGrid.bortle`
/// reads the other way): 1 21.85, 2 21.68, 3 21.45, 4 21.05, 5 19.8, 6 18.9, 7 18.25. The table stops
/// at 18.0 for 8 and gives nothing for 9, so 8 is 17.5 and 9 is 16.5, an assumption at the bright end
/// of city-centre zenith readings (commonly 16 to 18). Each choice sits at or below its range's
/// middle, so the count never credits a sky darker than its estimate.
///
/// **The eye.** Brightness becomes a naked-eye limiting magnitude by the conversion Unihedron, maker
/// of the Sky Quality Meter, publishes: NELM = 7.93 − 5 log10(10^(4.316 − SQM/5) + 1). It is a typical
/// eye's figure and tops out near 6.6 at the darkest sites, about a magnitude below Bortle's own NELM
/// column (a seasoned observer with averted vision, which the park page's faintest-star note uses).
/// For counting stars a visitor can name, the plainer eye is the honest one.
///
/// **Moonlight** adds light to the sky rather than taking a fixed penalty, so a full Moon washes out a
/// pristine sky and barely touches a city's. `SkyConditions.moonlight` is the Krisciunas–Schaefer
/// brightening over true darkness on a magnitude scale where 1 is a full Moon at the zenith, 30 times
/// a 21.7 sky (`AstronomyEngine.fullMoonBrightening`); turned back into light, the Moon adds
/// 31^moonlight − 1 of those skies. Averaging in magnitudes, as the score does, credits the Moon-free
/// hours a little; the count describes true darkness as a whole, not its best hour.
///
/// **The stars' altitude.** The Little Dipper circles the pole, so it stands about as high as the
/// latitude. Light through more air dims by 0.25 magnitudes per airmass beyond the zenith's (a clear
/// site's visual extinction), plus 1.086 × the smoke forecast's aerosol optical depth per airmass.
/// The bowl swings 16° above and below Polaris through the night; the count uses Polaris's height.
///
/// **Clouds** do not dim stars, they hide them: at 75% or more cover (the score's cloud figure, which
/// caps the night in Poor) the count says clouds likely hide the asterism; below that it counts what
/// clear gaps would show.
///
/// **Where it is not up.** Below +10° latitude Polaris skims the horizon and the bowl sets: no reading
/// (American Samoa, places in the southern hemisphere). No southern substitute: the Southern Cross
/// has five naked-eye stars of very different reach, and a second scale would read as the same one.
/// A night without true darkness has no reading either: twilight, not the sky's glow, decides it.
nonisolated enum LittleDipper {
    struct Star: Sendable, Hashable {
        let name: String
        /// J2000 right ascension and declination, degrees.
        let ra: Double
        let dec: Double
        /// Visual (V) magnitude.
        let magnitude: Double
    }
    /// Handle to bowl. Positions J2000 (Hipparcos). V magnitudes as commonly listed (Hipparcos; the
    /// Yale Bright Star Catalogue gives Pherkad 3.05, Yildun 4.36, ε 4.23, ζ 4.32, Polaris 2.02, and
    /// Polaris and ε UMi vary by a few hundredths to a tenth). No difference moves a count by more
    /// than the estimate's own spread, so the values stay as given.
    static let stars: [Star] = [
        Star(name: "Polaris", ra: 37.95, dec: 89.264, magnitude: 1.98),
        Star(name: "Yildun", ra: 263.05, dec: 86.586, magnitude: 4.35),
        Star(name: "Epsilon Ursae Minoris", ra: 251.49, dec: 82.037, magnitude: 4.21),
        Star(name: "Zeta Ursae Minoris", ra: 236.02, dec: 77.794, magnitude: 4.29),
        Star(name: "Eta Ursae Minoris", ra: 244.38, dec: 75.755, magnitude: 4.95),
        Star(name: "Kochab", ra: 222.68, dec: 74.156, magnitude: 2.08),
        Star(name: "Pherkad", ra: 230.18, dec: 71.834, magnitude: 3.00),
    ]
    /// The asterism's lines, as indexes into `stars`: the handle, then the bowl closed on ζ.
    static let lines: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 6), (6, 5), (5, 3)]
    /// Southernmost latitude with a reading: Polaris 10° up.
    static let minimumLatitude = 10.0
    /// Cloud cover (percent) from which clouds likely hide the asterism.
    static let hidingCloud = 75.0
    /// Visual extinction per airmass at a clear site.
    static let extinction = 0.25

    struct Reading: Equatable, Sendable {
        /// The faintest magnitude the eye reaches at the asterism's height, after air and haze.
        let limit: Double
        /// How much fainter the asterism looks than it would at the zenith.
        let dimming: Double
        let cloudsHide: Bool
        func sees(_ star: Star) -> Bool { !cloudsHide && star.magnitude + dimming <= limit }
        var visible: Int { LittleDipper.stars.filter(sees).count }
        /// For VoiceOver, where the glyph is shown: "5 of 7 Little Dipper stars, an estimate".
        var label: String {
            cloudsHide ? String(localized: "Clouds likely hide the Little Dipper, an estimate")
                : String(localized: "\(visible) of 7 Little Dipper stars, an estimate")
        }
        /// One sentence beside the drawing in the score breakdown.
        var sentence: String {
            cloudsHide ? String(localized: "Clouds likely hide the Little Dipper. An estimate, not part of the score.")
                : String(localized: "To the eye, about \(visible) of the Little Dipper's 7 stars. An estimate, not part of the score.")
        }
    }

    /// Zenith sky brightness (mag/arcsec²) for a Bortle class; see the type's note.
    static func zenithBrightness(bortle: Int) -> Double {
        [21.85, 21.68, 21.45, 21.05, 19.8, 18.9, 18.25, 17.5, 16.5][min(8, max(0, bortle-1))]
    }
    /// A typical eye's limiting magnitude under a sky of `brightness` mag/arcsec² (Unihedron).
    static func nakedEyeLimit(brightness: Double) -> Double {
        7.93 - 5*log10(pow(10, 4.316 - brightness/5) + 1)
    }
    /// The sky with the Moon's light added: `moonlight` 0…1 on `AstronomyEngine`'s magnitude scale.
    static func brightness(bortle: Int, moonlight: Double) -> Double {
        let reference = 21.7, moon = min(1, max(0, moonlight.isFinite ? moonlight : 0))
        let sky = pow(10, -0.4*(zenithBrightness(bortle: bortle) - reference))
        let added = pow(1 + AstronomyEngine.fullMoonBrightening, moon) - 1
        return reference - 2.5*log10(sky + added)
    }
    /// Airmass at an altitude in degrees (Rozenberg 1966, finite at the horizon), as the moonlight uses.
    static func airmass(altitude: Double) -> Double {
        let c = sin(min(90, max(0, altitude))*Double.pi/180)
        return 1/(c + 0.025*exp(-11*c))
    }

    /// The count's reading for a place and night; nil where the asterism is not up (below +10°) or
    /// the night has no true darkness.
    static func reading(latitude: Double, bortle: Int, moonlight: Double, darkHours: Double, cloud: Double?, aerosol: Double?) -> Reading? {
        guard latitude.isFinite, latitude >= minimumLatitude, darkHours.isFinite, darkHours > 0 else { return nil }
        let air = airmass(altitude: latitude)
        let haze = aerosol.flatMap { $0.isFinite ? 1.086*max(0, $0)*air : nil } ?? 0
        let hidden = cloud.map { $0.isFinite && $0 >= hidingCloud } ?? false
        return Reading(limit: nakedEyeLimit(brightness: brightness(bortle: bortle, moonlight: moonlight)),
                       dimming: extinction*(air - 1) + haze, cloudsHide: hidden)
    }
    /// A night's reading, from the same moonlight, clouds and air its score counted.
    static func reading(_ night: Night) -> Reading? {
        let sky = night.sky
        return reading(latitude: night.park.latitude, bortle: night.park.bortleEstimate,
                       moonlight: sky.moonlight ?? sky.moon.illumination*(1 - sky.moonBelowFraction),
                       darkHours: sky.darkHours, cloud: night.score.cloudUsed, aerosol: night.aerosol)
    }

    /// The asterism's shape: a polar projection about the celestial pole (the stars lie within 18° of
    /// it, so distances barely distort), seen from the ground (right ascension runs anticlockwise),
    /// turned so the handle leads from Polaris on the left to the bowl on the right and tilted 25° up,
    /// as it is usually drawn. Points in a box `aspect` wide and 1 high, y down.
    static let shape: (points: [SIMD2<Double>], aspect: Double) = {
        let raw = stars.map { star -> SIMD2<Double> in
            let r = 90 - star.dec, a = star.ra*Double.pi/180
            return SIMD2(r*cos(a), r*sin(a))
        }
        let pole = raw[0], bowl = (raw[3] + raw[4] + raw[5] + raw[6])/4
        let turn = 25*Double.pi/180 - atan2(bowl.y - pole.y, bowl.x - pole.x)
        let turned = raw.map { p -> SIMD2<Double> in
            let d = p - pole
            // Flip y for the screen, which grows downward.
            return SIMD2(d.x*cos(turn) - d.y*sin(turn), -(d.x*sin(turn) + d.y*cos(turn)))
        }
        let xs = turned.map(\.x), ys = turned.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        let height = max(0.001, (ys.max() ?? 1) - minY)
        return (turned.map { SIMD2(($0.x - minX)/height, ($0.y - minY)/height) }, ((xs.max() ?? 1) - minX)/height)
    }()
}
