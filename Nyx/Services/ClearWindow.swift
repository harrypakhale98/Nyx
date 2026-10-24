import Foundation

/// The best stretch of one forecast night: clear (hourly cloud under 30%), in true darkness, with
/// the Moon down where it matters, and when the Milky Way's core is 10° up within it. Found from
/// the hourly forecast already on the phone, or handed to the watch; only forecast nights have one.
nonisolated struct ClearWindow: Sendable, Equatable {
    let interval: DateInterval
    /// True when the Moon (at least 5% lit) is below the horizon throughout; a new Moon is not named.
    let moonDown: Bool
    /// Where the core is 10° up inside the window, when for at least half an hour.
    let core: DateInterval?
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
        let lit = sky.moon.illumination >= 0.05
        let moonOK = { (date: Date) in !lit || engine.lunarAltitude(at: date, park: park) < -0.833 }
        var moonDown = lit
        var base = almanac.longest(in: dark) { clear($0) && moonOK($0) }
        if (base?.duration ?? 0) < minimum { base = almanac.longest(in: dark, where: clear); moonDown = false }
        guard let base, base.duration >= minimum else { return nil }
        let coreUp = { (date: Date) in engine.horizontal(date: date, park: park, ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec).altitude >= SkyAlmanac.coreMinimumAltitude }
        let core = almanac.longest(in: base, where: coreUp).flatMap { $0.duration >= minimum ? $0 : nil }
        return ClearWindow(interval: base, moonDown: moonDown, core: core)
    }
    /// A night's best window from the hourly forecast it was scored on: mid and high cloud only at a
    /// summit above the inversion, else the clouds. One rule for the iPhone and the watch, which
    /// holds the same forecast the iPhone handed over. Nil without a full forecast.
    static func find(_ night: Night, forecast: Forecast?, layers: HourlySeries?) -> ClearWindow? {
        guard night.score.hasForecast else { return nil }
        let window = night.sky.cloudWindow
        var hours: [(time: Date, cloud: Double)] = []
        if night.upperCloudOnly, let layers, let mid = layers.values["cloud_cover_mid"], let high = layers.values["cloud_cover_high"], mid.count == layers.times.count, high.count == layers.times.count {
            hours = layers.times.indices.compactMap { i in
                guard let m = mid[i], let h = high[i], layers.times[i]+1800 > window.start.timeIntervalSince1970, layers.times[i]-1800 < window.end.timeIntervalSince1970 else { return nil }
                return (Date(timeIntervalSince1970: layers.times[i]), 100*(1-(1-m/100)*(1-h/100)))
            }
        } else if let forecast { hours = forecast.hours(from: window.start, to: window.end) }
        return find(park: night.park, sky: night.sky, hours: hours)
    }
}
