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
nonisolated struct Night: Identifiable, Sendable {
    var id: Date { sky.evening }
    let park: Park
    let sky: SkyConditions
    let score: DarknessScore
    let cloudCover: Double?
    let forecastUpdated: Date?
}
