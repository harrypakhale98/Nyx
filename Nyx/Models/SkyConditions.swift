import Foundation

nonisolated enum DarknessState: String, Codable, Sendable {
    case normal, noAstronomicalDarkness, polarDay, polarNight
}
nonisolated struct MoonPhase: Codable, Sendable {
    let fraction: Double
    var illumination: Double { (1-cos(fraction * 2 * .pi))/2 }
    var waxing: Bool { fraction < 0.5 }
    /// Within about a day of new: the phase `name` calls "New moon", decided here once.
    var isNew: Bool { fraction < 0.03 || fraction >= 0.97 }
    var name: String {
        if isNew { return String(localized: "New moon") }
        return switch fraction {
        case ..<0.22: String(localized: "Waxing crescent")
        case ..<0.28: String(localized: "First quarter")
        case ..<0.47: String(localized: "Waxing gibbous")
        case ..<0.53: String(localized: "Full moon")
        case ..<0.72: String(localized: "Waning gibbous")
        case ..<0.78: String(localized: "Last quarter")
        default: String(localized: "Waning crescent")
        }
    }
    /// How much of the disc is lit, as a whole percent: the one number every surface shows.
    var percentLit: Int { Int((illumination*100).rounded()) }
    /// Too thin to matter (under 5% lit), judged on the number shown, so "5% lit" is never called negligible
    /// and "4% lit" always is. The one threshold for "is the Moon in the way?" (`AstronomyEngine.moonHidden`).
    var negligible: Bool { percentLit < 5 }
    /// "23% lit", the percent written as the reader's locale writes it.
    var litText: String { String(localized: "\(Percent.text(percentLit)) lit") }
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
    /// The Moon-free share of true darkness as a whole percent, rounded once for every device, so
    /// "all through" (100) and "up all through" (0) mean the same on the iPhone, the watch and Vision Pro.
    var moonDownPercent: Int { Int((moonBelowFraction*100).rounded()) }
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
    /// Where the Moon is during true darkness, decided once for every surface (`MoonInDarkness`).
    /// "All" and "none" by `moonDownPercent`, so the iPhone, the watch and Vision Pro round alike.
    var moonInDarkness: MoonInDarkness {
        guard darkHours > 0 else { return .noDarkness }
        if moonDownPercent == 100 { return .allFree }
        if moon.negligible { return .negligible }
        if moonDownPercent == 0 { return .allUp }
        if let darkStart, let darkEnd {
            let dark = DateInterval(start: darkStart, end: max(darkStart, darkEnd))
            // A Moon that both sets and rises inside true darkness is neither: say how much is Moon-free.
            let sets = moonset.flatMap { dark.contains($0) ? $0 : nil }, rises = moonrise.flatMap { dark.contains($0) ? $0 : nil }
            if let sets, rises == nil { return .setsAt(sets) }
            if let rises, sets == nil { return .risesAt(rises) }
        }
        return .partial(percentFree: moonDownPercent)
    }
}
/// The Moon during a night's true darkness, in the order it is decided: none to speak of, then a
/// Moon that sets or rises inside it, then how much of it is Moon-free. One rule, two lengths of
/// words (`sentence`, `short`), so no surface says the Moon matters where another says it does not.
nonisolated enum MoonInDarkness: Sendable, Equatable {
    case noDarkness, allFree, negligible, allUp
    case setsAt(Date)
    case risesAt(Date)
    case partial(percentFree: Int)
    /// One sentence for under a dial: "Moon up until 11:40 PM, 23% lit." `withLit: false` leaves out
    /// how much is lit, for a surface that shows the phase and percent on the line above (the watch,
    /// Vision Pro). Nil without true darkness: the heroes already say "No true darkness tonight at
    /// this latitude."
    func sentence(park: Park, moon: MoonPhase, withLit: Bool = true) -> String? {
        let lit = Percent.text(moon.percentLit)
        switch self {
        case .noDarkness: return nil
        case .allFree: return Sentences.end(String(localized: "Moon-free through all of true darkness"))
        case .negligible: return withLit ? String(localized: "Moon too thin to matter, \(lit) lit.") : String(localized: "Moon too thin to matter.")
        case .allUp: return withLit ? String(localized: "Moon up all through true darkness, \(lit) lit.") : Sentences.end(String(localized: "Moon up all through true darkness"))
        case .setsAt(let set): return withLit ? String(localized: "Moon up until \(park.time(set)), \(lit) lit.") : String(localized: "Moon up until \(park.time(set)).")
        case .risesAt(let rise): return withLit ? String(localized: "Moon rises at \(park.time(rise)), \(lit) lit.") : String(localized: "Moon rises at \(park.time(rise)).")
        case .partial(let free): return Sentences.end(String(localized: "Moon-free for \(free)% of true darkness"))
        }
    }
    /// The same at a glance, a few words with no full stop: "Moon down at 11:40 PM".
    func short(park: Park) -> String {
        switch self {
        case .noDarkness: String(localized: "No true darkness")
        case .negligible: String(localized: "Almost no moonlight")
        case .allFree: String(localized: "Moon down")
        case .allUp: String(localized: "Dark, Moon up")
        case .setsAt(let set): String(localized: "Moon down at \(park.time(set))")
        case .risesAt(let rise): String(localized: "Dark until \(park.time(rise))")
        case .partial(let free): String(localized: "Moon-free for \(free)% of true darkness")
        }
    }
}
extension SkyConditions {
    /// `moonInDarkness` in one sentence (`MoonInDarkness.sentence`).
    nonisolated func moonSentence(park: Park, withLit: Bool = true) -> String? { moonInDarkness.sentence(park: park, moon: moon, withLit: withLit) }
    /// `moonInDarkness` at a glance (`MoonInDarkness.short`).
    nonisolated func moonShort(park: Park) -> String { moonInDarkness.short(park: park) }
    /// "Sets 8:53 PM · Rises 4:42 AM" in time order, from noon to sunrise (a rise late the next
    /// morning is not this night's news), or "Up all night" / "Below the horizon all night", on every
    /// device. Without a rise or set the Moon stays put, so its altitude midway through the night
    /// decides (the share of darkness it spends down says nothing on a night with no true darkness).
    nonisolated func moonTimes(park: Park) -> String {
        let morning = sunrise ?? end
        var events: [(Date, String)] = []
        if let rise = moonrise, rise < morning { events.append((rise, String(localized: "Rises \(park.time(rise))"))) }
        if let set = moonset, set < morning { events.append((set, String(localized: "Sets \(park.time(set))"))) }
        if events.isEmpty {
            let start = sunset ?? evening, middle = start.addingTimeInterval(morning.timeIntervalSince(start)/2)
            // The upper limb on a refracted horizon, as the engine times rises and sets.
            let below = AstronomyEngine().lunarAltitude(at: middle, park: park) < -0.833
            return below ? String(localized: "Below the horizon all night") : String(localized: "Up all night")
        }
        return events.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: " · ")
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
    /// The lowest score in the band: the one set of cutoffs every surface reads ("Excellent or better"
    /// is `score >= ScoreBand.excellent.minimum`), never a number written again elsewhere.
    var minimum: Int {
        switch self { case .pristine: 90; case .excellent: 75; case .good: 60; case .fair: 40; case .poor: 0 }
    }
    static func band(_ score: Int) -> Self {
        allCases.first { score >= $0.minimum } ?? .poor
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
    case moonlight(Int)
    case clouds(Int)
    case skyGlow(Int)
    case smoke(Int)
    var cap: Int { switch self { case .darkness(let c), .moonlight(let c), .clouds(let c), .skyGlow(let c), .smoke(let c): c } }
    /// "Clouds limit tonight to 55."
    func sentence(tonight: Bool) -> String {
        switch self {
        case .darkness(let c): tonight ? String(localized: "Short hours of true darkness limit tonight to \(c).") : String(localized: "Short hours of true darkness limit this night to \(c).")
        case .moonlight(let c): tonight ? String(localized: "Moonlight limits tonight to \(c).") : String(localized: "Moonlight limits this night to \(c).")
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
    /// The four parts added, unrounded: what the night would score if nothing held it down (ties
    /// between equal scores are broken on it, `NightPlanner.better`).
    var rawPartsSum: Double { moonPoints+(cloudPoints ?? 0)+bortlePoints+lengthPoints }
    /// The four parts added, rounded once: the score before any cap.
    var partsSum: Int { Int(rawPartsSum.rounded()) }
    /// The parts as whole points that always add up to `partsSum` (largest remainder), so the numbers
    /// a reader adds on a breakdown make the total beside them; rounding each part alone could show
    /// 40 + 25 + 15 + 15 beside a sum of 94.
    var displayedParts: (moon: Int, cloud: Int?, glow: Int, length: Int) {
        let raw = [moonPoints, cloudPoints ?? 0, bortlePoints, lengthPoints].map { max(0, $0) }
        var whole = raw.map { Int($0.rounded(.down)) }
        let short = max(0, min(raw.count, partsSum-whole.reduce(0, +)))
        // The largest fractions take the missing points; on a tie, the earlier part (moon, clouds, Bortle, duration).
        let fraction = raw.map { $0-$0.rounded(.down) }
        let order = raw.indices.sorted { fraction[$0] != fraction[$1] ? fraction[$0] > fraction[$1] : $0 < $1 }
        // A part never shows more than its own maximum ("53 of 53" with no cloud figure, never 54).
        let scale = cloudPoints == nil ? 1/0.75 : 1
        let maximum = [40*scale, cloudPoints == nil ? 0 : 25, 20*scale, 15*scale].map { Int($0.rounded()) }
        for index in order.filter({ whole[$0] < maximum[$0] }).prefix(short) { whole[index] += 1 }
        return (whole[0], cloudPoints == nil ? nil : whole[1], whole[2], whole[3])
    }
    /// True when a cloud forecast counts in full. An early look or the usual clouds is not a forecast.
    var hasForecast: Bool { basis == .forecast }
    /// The weakest link in words, when its cap holds the score below the sum of its parts ("Clouds
    /// limit tonight to 55."), on every device; nil when nothing does. The iPhone, which shows the
    /// four parts, adds their sum.
    func limitSentence(tonight: Bool) -> String? {
        guard let limit, limit.cap < partsSum else { return nil }
        return limit.sentence(tonight: tonight)
    }
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
    /// The same month's share of mostly clear nights, percent, and whether it is the world grid's
    /// estimate: from the climate the night was scored with, for `typicalClouds`.
    var usualClear: Double? = nil
    var usualEstimated = false
    /// A summit above the inversion, scored from mid and high cloud only (`Park.aboveInversion`).
    var upperCloudOnly = false
    /// How far apart three forecast models' cloud averages are, in percentage points, within
    /// their seven-day horizon. Breaks ties between equal scores; never changes one.
    var modelSpread: Double? = nil
    /// The aerosol optical depth the score counted (the smoke forecast's average over the cloud
    /// window), so the smoke caveat and the score never describe different air.
    var aerosol: Double? = nil
    /// For a night scored on the usual clouds: true when it simply lies beyond what a cloud forecast
    /// reaches ("No cloud forecast yet"), false when a forecast should reach it but could not be read
    /// ("Cloud forecast unavailable"). Set by `NightPlanner.night` (`beyondForecast`), so every surface
    /// says the same; a night the app keeps has it worked out again as the forecast ages (`PlanModel.night`).
    var beyondForecast = true
    var basis: CloudBasis { score.basis }
}

/// A whole percentage as the reader's locale writes it ("23%"; "23 %" in French and German), for
/// copy such as "\(Percent.text(23)) lit" whose catalog entry is then "%@ lit".
nonisolated enum Percent {
    static func text(_ whole: Int) -> String { whole.formatted(.percent) }
}
