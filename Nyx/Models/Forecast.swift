import Foundation

/// The last hourly cloud forecast for one park. Its own file, apart from the network services,
/// so the widgets and the watch (which never touches the network) can read it.
nonisolated struct Forecast: Codable, Sendable {
    let updated: Date
    let times: [Double]
    let clouds: [Double?]
    /// How long a forecast stays recent: after this every surface asks for a fresh one and stops
    /// describing what it says (model spread, layers, smoke), and a reminder no longer rests on it.
    /// The score itself never drops it; it fades by lead time (`CloudBasis.forecastWeight`).
    static let recentFor: TimeInterval = 36*3600
    /// Overlap-weighted hourly mean; a partial forecast is never treated as full. A forecast is
    /// never dropped for its age: `CloudBasis.forecastWeight` fades it toward the park's usual
    /// clouds by how far ahead of the night it was made, so an old forecast can only count less.
    func mean(from start: Date?, to end: Date?) -> Double? {
        guard let start, let end else { return nil }
        return HourlyWindow.mean(times:times,values:clouds,from:start,to:end,valid:0...100)
    }
    /// Whether `fresh` should replace `kept`: only a forecast made later. A slower refresh that
    /// finishes after a newer one never puts its older forecast back. Given `now`, a kept forecast
    /// stamped well after it (saved while the device clock ran ahead) gives way too, or no forecast
    /// could replace it until the clock caught up.
    static func replaces(_ fresh: Forecast?, _ kept: Forecast?, now: Date? = nil) -> Bool {
        guard let fresh else { return false }
        return newer(fresh.updated, than: kept?.updated, now: now)
    }
    /// How far after the present a forecast's stamp may lie before it is taken as a clock that ran ahead.
    static let futureSlack: TimeInterval = 3600
    /// A stamp well after `now` (`futureSlack`): kept while the device clock ran ahead, so its age says
    /// nothing. Every cache treats it as due and not recent, whatever it holds (clouds, detail, smoke,
    /// summit layers, aurora, park alerts, programs, campgrounds).
    static func ahead(_ updated: Date, of now: Date) -> Bool { updated > now.addingTimeInterval(futureSlack) }
    /// Whether something made at `fresh` replaces what was made at `kept` (the rule of `replaces`, for
    /// any cache): only a later one, or, given `now`, one made in the present over one stamped `ahead`.
    static func newer(_ fresh: Date, than kept: Date?, now: Date? = nil) -> Bool {
        guard let kept else { return true }
        return fresh > kept || now.map { ahead(kept, of: $0) && !ahead(fresh, of: $0) } == true
    }
    /// The hourly values whose half hour either side overlaps `start`…`end`, with their timestamps.
    func hours(from start: Date, to end: Date) -> [(time: Date, cloud: Double)] {
        zip(times,clouds).compactMap { t,c in
            guard let c, c.isFinite, (0...100).contains(c), t+1800>start.timeIntervalSince1970, t-1800<end.timeIntervalSince1970 else { return nil }
            return (Date(timeIntervalSince1970:t),c)
        }
    }
}
