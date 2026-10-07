import Foundation

nonisolated enum DarknessState: String, Codable, Sendable {
    case normal, noAstronomicalDarkness, polarDay, polarNight
}
nonisolated struct MoonPhase: Codable, Sendable {
    let fraction: Double
    var illumination: Double { (1-cos(fraction * 2 * .pi))/2 }
    var waxing: Bool { fraction < 0.5 }
    var name: String {
        switch fraction {
        case ..<0.03, 0.97...: String(localized: "New moon")
        case ..<0.22: String(localized: "Waxing crescent")
        case ..<0.28: String(localized: "First quarter")
        case ..<0.47: String(localized: "Waxing gibbous")
        case ..<0.53: String(localized: "Full moon")
        case ..<0.72: String(localized: "Waning gibbous")
        case ..<0.78: String(localized: "Last quarter")
        default: String(localized: "Waning crescent")
        }
    }
}
nonisolated struct SkyConditions: Sendable {
    let evening: Date
    let end: Date
    let sunset: Date?
    let sunrise: Date?
    let civilDusk: Date?
    let nauticalDusk: Date?
    let darkStart: Date?
    let darkEnd: Date?
    let state: DarknessState
    let moon: MoonPhase
    let moonrise: Date?
    let moonset: Date?
    let moonBelowFraction: Double
    let darkHours: Double
    /// Moonlight over true darkness, 0 (no Moon) to 1 (a full Moon high in the sky all through it):
    /// Krisciunas–Schaefer brightness by phase and altitude, averaged in magnitudes of sky
    /// brightening (`AstronomyEngine.moonlight`). Nil for a hand-built sky, which then falls back
    /// to illumination times the share of darkness with the Moon up.
    var moonlight: Double? = nil
    /// Under the midnight sun, when the Sun is lowest (solar midnight); nil on other nights.
    var lowestSun: Date? = nil
    /// The hours whose clouds matter. True darkness when there is any; otherwise sunset
    /// to sunrise, or under the midnight sun the four hours around the Sun's lowest point
    /// (local 22:00–02:00 if that is unknown), so an Alaska summer night still reports its
    /// forecast instead of looking like it has none.
    var cloudWindow: (start: Date, end: Date) {
        if let darkStart, let darkEnd, darkEnd > darkStart { return (darkStart, darkEnd) }
        if let sunset, let sunrise, sunrise > sunset { return (sunset, sunrise) }
        if let lowestSun { return (lowestSun.addingTimeInterval(-2*3600), lowestSun.addingTimeInterval(2*3600)) }
        return (evening.addingTimeInterval(10*3600), evening.addingTimeInterval(14*3600))
    }
}
nonisolated enum ScoreBand: String, Codable, CaseIterable, Sendable {
    case pristine, excellent, good, fair, poor
    var label: String {
        switch self {
        case .pristine: String(localized: "Pristine")
        case .excellent: String(localized: "Excellent")
        case .good: String(localized: "Good")
        case .fair: String(localized: "Fair")
        case .poor: String(localized: "Poor")
        }
    }
    static func band(_ score: Int) -> Self {
        switch score { case 90...: .pristine; case 75...: .excellent; case 60...: .good; case 40...: .fair; default: .poor }
    }
}
/// What a night's cloud figure rests on. One rule everywhere (`CloudBasis.forecastWeight`): a
/// forecast counts in full up to about three days ahead, then fades toward the park's usual
/// clouds for the month (ERA5, `CloudClimate`) and is gone ten days out. A forecast is never
/// dropped for its age; it fades instead, so going offline can never make a night look clearer.
nonisolated enum CloudBasis: Sendable, Equatable {
    /// A cloud forecast at (nearly) full weight.
    case forecast
    /// An early look: `weight` is the forecast's share of the clouds counted, `leadDays` how far
    /// ahead of the night the forecast was made.
    case blended(weight: Double, leadDays: Double)
    /// No forecast reaches this night: the park's usual clouds for the month.
    case usual
    /// The forecast's share of the clouds counted for a night `leadDays` after it was made:
    /// 1 up to three days ahead, falling to 0 at ten (cloud forecasts are little better than the
    /// usual weather beyond about a week).
    static func forecastWeight(leadDays: Double) -> Double {
        guard leadDays.isFinite else { return 0 }
        return min(1, max(0, (10-leadDays)/7))
    }
    /// From a weight: a full forecast from 0.95, an early look above 0, the usual clouds at 0.
    static func from(weight: Double, leadDays: Double) -> Self {
        weight >= 0.95 ? .forecast : weight > 0 ? .blended(weight: weight, leadDays: leadDays) : .usual
    }
    var isEarlyLook: Bool { if case .blended = self { true } else { false } }
    /// How a night's mark is drawn: filled with a forecast, half-filled for an early look, hollow without.
    var fill: NightFill { switch self { case .forecast: .full; case .blended: .half; case .usual: .hollow } }
}
nonisolated enum NightFill: Sendable, Hashable { case full, half, hollow }

/// The weakest link that holds a night's score down, when one does. The score adds its four
/// parts, then takes the lowest of that sum and these caps.
nonisolated enum ScoreLimit: Sendable, Equatable {
    case darkness(Int)
    case clouds(Int)
    case skyGlow(Int)
    case smoke(Int)
    var cap: Int { switch self { case .darkness(let c), .clouds(let c), .skyGlow(let c), .smoke(let c): c } }
    /// "Clouds limit tonight to 55."
    func sentence(tonight: Bool) -> String {
        switch self {
        case .darkness(let c): tonight ? String(localized: "Short hours of true darkness limit tonight to \(c).") : String(localized: "Short hours of true darkness limit this night to \(c).")
        case .clouds(let c): tonight ? String(localized: "Clouds limit tonight to \(c).") : String(localized: "Clouds limit this night to \(c).")
        case .skyGlow(let c): tonight ? String(localized: "Sky glow limits tonight to \(c).") : String(localized: "Sky glow limits this night to \(c).")
        case .smoke(let c): tonight ? String(localized: "Smoke or haze limits tonight to \(c).") : String(localized: "Smoke or haze limits this night to \(c).")
        }
    }
}
nonisolated struct DarknessScore: Sendable {
    let value: Int
    let moonPoints: Double
    /// Nil only when no cloud figure exists at all (no forecast and no usual clouds for the park).
    let cloudPoints: Double?
    let bortlePoints: Double
    let lengthPoints: Double
    /// What the cloud points rest on.
    var basis: CloudBasis
    /// The cloud cover the score counted, percent: the forecast, the usual clouds, or a blend.
    var cloudUsed: Double?
    /// The cap that holds the score below the sum of its parts, if any.
    var limit: ScoreLimit?
    init(value: Int, moonPoints: Double, cloudPoints: Double?, bortlePoints: Double, lengthPoints: Double,
         basis: CloudBasis? = nil, cloudUsed: Double? = nil, limit: ScoreLimit? = nil) {
        self.value=value; self.moonPoints=moonPoints; self.cloudPoints=cloudPoints; self.bortlePoints=bortlePoints; self.lengthPoints=lengthPoints
        self.basis=basis ?? (cloudPoints == nil ? .usual : .forecast); self.cloudUsed=cloudUsed; self.limit=limit
    }
    var band: ScoreBand { .band(value) }
    /// True when a cloud forecast counts in full. An early look or the usual clouds is not a forecast.
    var hasForecast: Bool { basis == .forecast }
}
extension SkyConditions {
    /// The spec's wording for tonight; any other night is named as that night.
    nonisolated static func noDarknessMessage(tonight: Bool) -> String {
        tonight ? String(localized: "No true darkness tonight at this latitude.") : String(localized: "No true darkness on this night at this latitude.")
    }
}
/// One park's night. Built from a sky and a forecast only by `NightPlanner.night(park:sky:forecast:detail:now:)`.
nonisolated struct Night: Identifiable, Sendable {
    var id: Date { sky.evening }
    let park: Park
    let sky: SkyConditions
    let score: DarknessScore
    /// The cloud forecast's average over the night's cloud window, when a forecast counts at all.
    let cloudCover: Double?
    let forecastUpdated: Date?
    /// The park's usual cloud for the month (ERA5), percent, when known.
    var usualCloud: Double? = nil
    /// A summit above the inversion, scored from mid and high cloud only (`Park.aboveInversion`).
    var upperCloudOnly = false
    /// How far apart three forecast models' cloud averages are, in percentage points, within
    /// their seven-day horizon. Breaks ties between equal scores; never changes one.
    var modelSpread: Double? = nil
    var basis: CloudBasis { score.basis }
}
