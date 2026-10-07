import Foundation

/// The last hourly cloud forecast for one park. Its own file, apart from the network services,
/// so the widgets and the watch (which never touches the network) can read it.
nonisolated struct Forecast: Codable, Sendable {
    let updated: Date
    let times: [Double]
    let clouds: [Double?]
    /// Overlap-weighted hourly mean; a partial forecast is never treated as full. A forecast is
    /// never dropped for its age: `CloudBasis.forecastWeight` fades it toward the park's usual
    /// clouds by how far ahead of the night it was made, so an old forecast can only count less.
    func mean(from start: Date?, to end: Date?) -> Double? {
        guard let start, let end else { return nil }
        return HourlyWindow.mean(times:times,values:clouds,from:start,to:end,valid:0...100)
    }
    /// The hourly values whose half hour either side overlaps `start`…`end`, with their timestamps.
    func hours(from start: Date, to end: Date) -> [(time: Date, cloud: Double)] {
        zip(times,clouds).compactMap { t,c in
            guard let c, c.isFinite, (0...100).contains(c), t+1800>start.timeIntervalSince1970, t-1800<end.timeIntervalSince1970 else { return nil }
            return (Date(timeIntervalSince1970:t),c)
        }
    }
}
