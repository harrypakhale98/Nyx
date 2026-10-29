import Foundation

/// The best stretch of one forecast night: clear (hourly cloud under 30%), in true darkness, with
/// the Moon down where it matters, and when the Milky Way's core is 10° up within it. Found from
/// the hourly forecast already on the phone, or handed to the watch; only forecast nights have one.
nonisolated struct ClearWindow: Sendable, Equatable {
    let interval: DateInterval
    /// True when a Moon that matters (`MoonPhase.negligible` is not) is below the horizon throughout;
    /// a new Moon is not named.
    let moonDown: Bool
    /// Where the core is 10° up inside the window, when for at least half an hour.
    let core: DateInterval?
    /// True when no clear stretch is free of the Moon and a Moon over half lit is up for at least half
    /// of this one: clear, but washed with moonlight, so never named or drawn as the night's best.
    var moonlit = false
    /// The stretch a dial draws brightest (the iPhone's and the watch's `NightTrack`): none under a bright Moon.
    var brightest: DateInterval? { moonlit ? nil : interval }
    /// Above this the Moon washes a clear window out (`moonlit`).
    static let brightMoon = 0.5
    /// Hourly cloud under this is "clear".
    static let clearBelow = 30.0
    /// Shorter stretches are not worth naming.
    static let minimum: TimeInterval = 1800

    /// `hours` are hourly cloud values (each describing the half hour either side of its time).
    static func find(park: Park, sky: SkyConditions, hours: [(time: Date, cloud: Double)],
                     engine: AstronomyEngine = AstronomyEngine(), almanac: SkyAlmanac = SkyAlmanac()) -> ClearWindow? {
        guard let start = sky.darkStart, let end = sky.darkEnd, end.timeIntervalSince(start) >= minimum, !hours.isEmpty else { return nil }
        let dark = DateInterval(start: start, end: end)
        func cloud(_ date: Date) -> Double? {
            hours.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
                .flatMap { abs($0.time.timeIntervalSince(date)) <= 1800 ? $0.cloud : nil }
        }
        let clear = { (date: Date) in (cloud(date) ?? 100) < clearBelow }
        let moonOK = { (date: Date) in engine.moonHidden(at: date, park: park, phase: sky.moon) }
        var moonDown = !sky.moon.negligible
        var base = almanac.longest(in: dark) { clear($0) && moonOK($0) }
        if (base?.duration ?? 0) < minimum { base = almanac.longest(in: dark, where: clear); moonDown = false }
        guard let base, base.duration >= minimum else { return nil }
        let coreUp = { (date: Date) in engine.horizontal(date: date, park: park, ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec).altitude >= SkyAlmanac.coreMinimumAltitude }
        let core = almanac.longest(in: base, where: coreUp).flatMap { $0.duration >= minimum ? $0 : nil }
        let moonUp = almanac.longest(in: base) { engine.lunarAltitude(at: $0, park: park) >= -0.833 }
        let washed = !moonDown && sky.moon.illumination > brightMoon && (moonUp?.duration ?? 0) >= base.duration/2
        return ClearWindow(interval: base, moonDown: moonDown, core: core, moonlit: washed)
    }
    /// A night's best window from the hourly forecast it was scored on: mid and high cloud only at a
    /// summit above the inversion, else the clouds. One rule for the iPhone and the watch, which
    /// holds the same forecast the iPhone handed over. Nil without a full forecast.
    static func find(_ night: Night, forecast: Forecast?, layers: HourlySeries?) -> ClearWindow? {
        guard night.score.hasForecast else { return nil }
        let window = night.sky.cloudWindow
        // The summit's layers combined as the score combines them (`HourlySeries.upperCloud`), invalid hours left out.
        let clouds = night.upperCloudOnly ? layers?.upperCloud ?? forecast : forecast
        return find(park: night.park, sky: night.sky, hours: clouds?.hours(from: window.start, to: window.end) ?? [])
    }
}
