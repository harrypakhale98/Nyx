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
    /// The hours whose clouds matter. True darkness when there is any; otherwise sunset
    /// to sunrise, or local 22:00–02:00 under the midnight sun, so an Alaska summer night
    /// still reports its forecast instead of looking like it has none.
    var cloudWindow: (start: Date, end: Date) {
        if let darkStart, let darkEnd, darkEnd > darkStart { return (darkStart, darkEnd) }
        if let sunset, let sunrise, sunrise > sunset { return (sunset, sunrise) }
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
nonisolated struct DarknessScore: Sendable {
    let value: Int
    let moonPoints: Double
    let cloudPoints: Double?
    let bortlePoints: Double
    let lengthPoints: Double
    var band: ScoreBand { .band(value) }
    var hasForecast: Bool { cloudPoints != nil }
}
extension SkyConditions {
    /// The spec's wording for tonight; any other night is named as that night.
    nonisolated static func noDarknessMessage(tonight: Bool) -> String {
        tonight ? String(localized: "No true darkness tonight at this latitude.") : String(localized: "No true darkness on this night at this latitude.")
    }
}
nonisolated struct Night: Identifiable, Sendable {
    var id: Date { sky.evening }
    let park: Park
    let sky: SkyConditions
    let score: DarknessScore
    let cloudCover: Double?
    let forecastUpdated: Date?
}
