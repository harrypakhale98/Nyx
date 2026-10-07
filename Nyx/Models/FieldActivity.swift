import ActivityKit
import AlarmKit
import Foundation

/// The Live Activity for a night in the field, shared by the app (which starts and updates it)
/// and the widget extension (which draws it). Everything is computed on the phone when it starts,
/// so it needs no push server: the night's milestones travel in the attributes, the countdown is a
/// system timer, and the line from dusk to dawn fills by itself.
nonisolated struct FieldActivityAttributes: ActivityAttributes {
    struct Milestone: Codable, Hashable, Sendable {
        let title: String
        let date: Date
        let symbol: String
    }
    struct ContentState: Codable, Hashable, Sendable {
        /// The next milestone when the app last looked; the countdown runs to it.
        var next: Milestone?
        /// Draw in red: night vision was on.
        var nightVision: Bool
        /// Set once the night is over.
        var finished: Bool=false
    }
    let parkID: String
    let parkName: String
    let score: Int
    let band: String
    /// Sunset (or the start of the night window) and sunrise: the ends of the line.
    let dusk: Date
    let dawn: Date
    let darkStart: Date?
    let darkEnd: Date?
    /// At most eight, earliest first, so the whole activity stays far below ActivityKit's 4 KB.
    let milestones: [Milestone]
    /// The park's IANA zone: the Lock Screen shows park time, as field mode does, wherever the
    /// phone's clock is set. Optional so an activity started by an earlier build still decodes.
    var timeZoneID: String? = nil
    var timeZone: TimeZone { timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current }
    /// The one milestone every face names, so title, symbol and countdown never disagree: the
    /// state's next milestone, or once that moment has passed with no update (stale), the one after
    /// it. Nil when the night is over or only sunrise is left.
    func shown(_ state: ContentState, isStale: Bool) -> Milestone? {
        guard !state.finished, let next=state.next else { return nil }
        return isStale ? after(next).first : next
    }

    /// The milestones after the one the state points at, for when the state has gone stale.
    func after(_ milestone: Milestone?) -> [Milestone] {
        guard let milestone else { return milestones }
        return milestones.filter { $0.date>milestone.date }
    }
    /// Where a moment falls along the night, 0 at dusk and 1 at dawn.
    func fraction(_ date: Date) -> Double {
        let span=dawn.timeIntervalSince(dusk)
        return span>0 ? min(1, max(0, date.timeIntervalSince(dusk)/span)) : 0
    }
}

/// What a field-mode alarm carries, so the alarm's own Live Activity can name the park.
nonisolated struct FieldAlarmMetadata: AlarmMetadata {
    let parkName: String
    let kind: String
}
