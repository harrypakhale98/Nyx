import Foundation

/// Where a place sits in Earth's magnetic field, for the aurora note. A centred (tilted) dipole:
/// guidance, not a field model. Aurora follows geomagnetic latitude, not geographic latitude, so one
/// rule serves both hemispheres. Good across North America; it reads Europe about 3–5° too high and
/// Australasia about 4–5° too low (Hobart comes out near −50°), so a corrected-latitude grid replaces
/// it before places abroad join the catalogue (G4).
nonisolated enum Geomagnetic {
    /// The north geomagnetic (dipole) pole for epoch 2025.0, from the IGRF-14 dipole coefficients
    /// (g10, g11, h11): about 80.8° N, 72.8° W. Approximate. The dipole pole moves slowly (about
    /// 80.65° N, 72.7° W in 2020, so a few hundredths of a degree a year); the faster-moving magnetic
    /// dip pole is a different point and is not used here.
    static let poleLatitude = 80.8
    static let poleLongitude = -72.8

    /// Geomagnetic latitude in degrees, −90…90: φm = asin(sin φ sin φp + cos φ cos φp cos(λ − λp)).
    static func latitude(latitude: Double, longitude: Double) -> Double {
        let rad = Double.pi/180
        let s = sin(latitude*rad)*sin(poleLatitude*rad) + cos(latitude*rad)*cos(poleLatitude*rad)*cos((longitude-poleLongitude)*rad)
        return asin(max(-1, min(1, s)))/rad
    }
    static func latitude(of place: Place) -> Double { latitude(latitude: place.latitude, longitude: place.longitude) }

    /// How often aurora reaches a sky, by |φm|. The bounds follow the usual table of the auroral
    /// oval's equatorward view line by Kp index (Kp 3 near 60°, Kp 5 near 56°, Kp 7 near 52°):
    /// `often` sees aurora at quiet to unsettled levels, `active` needs active nights or minor
    /// storms, `storms` only strong ones. Below 52° aurora is too rare for a standing note.
    enum AuroraReach: Int, Comparable, Sendable {
        case none, storms, active, often
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        init(geomagneticLatitude degrees: Double) {
            switch abs(degrees) {
            case 60...: self = .often
            case 56..<60: self = .active
            case 52..<56: self = .storms
            default: self = .none
            }
        }
    }
    static func auroraReach(_ place: Place) -> AuroraReach { AuroraReach(geomagneticLatitude: latitude(of: place)) }
}
