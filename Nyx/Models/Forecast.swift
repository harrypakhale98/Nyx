import Foundation

/// The last hourly cloud forecast for one park. Its own file, apart from the network services,
/// so the widgets and the watch (which never touches the network) can read it.
nonisolated struct Forecast: Codable, Sendable {
    let updated: Date
    let times: [Double]
    let clouds: [Double?]
    /// Overlap-weighted hourly mean; a partial forecast is never treated as full.
    func mean(from start: Date?, to end: Date?, now: Date = .now) -> Double? {
        guard let start, let end, now.timeIntervalSince(updated)<36*3600 else { return nil }
        return HourlyWindow.mean(times:times,values:clouds,from:start,to:end,valid:0...100)
    }
}
