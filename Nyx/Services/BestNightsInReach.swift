import Foundation

/// Plan's first answer: "where, and on which night, this month?" Every place in reach, its best
/// night of the next 30, and the places ordered by that night, the best first. A closure in a park's
/// last update counts against its nights (`NightPlanner.better(_:_:closures:)`), as wherever a best
/// night is recommended; the scores shown never change. Nights past the forecast rest on each
/// place's usual clouds and say so (`Night.basisLabel`).
nonisolated struct BestNightsInReach: Sendable {
    struct Row: Sendable, Identifiable {
        let best: Night
        var park: Park { best.park }
        var id: String { best.park.id }
    }
    /// Each place's best night, the best first, at most `rowLimit`.
    let rows: [Row]
    /// How many places had nights to rank, and how many were in reach before a shortlist.
    let total: Int
    var inReach = 0
    /// Each ranked park's closure from its last park update, said beside its name.
    var closures: [String: String] = [:]
    /// The nights each place is judged over, from tonight (`NightPlanner.horizon`).
    static let nights = NightPlanner.horizon
    static let rowLimit = 10
    var best: Night? { rows.first?.best }
    /// `months`: each place's nights from tonight, in the order to keep on a tie.
    static func make(_ months: [[Night]], closures: [String: String] = [:], inReach: Int? = nil, limit: Int = rowLimit) -> BestNightsInReach {
        func better(_ a: Night, _ b: Night) -> Bool { NightPlanner.better(a, b, closures: closures) }
        let bests = months.compactMap { $0.min(by: better) }
        let ordered = bests.enumerated().sorted { a, b in
            if better(a.element, b.element) { return true }
            if better(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
        return BestNightsInReach(rows: ordered.prefix(max(0, limit)).map(Row.init), total: bests.count, inReach: inReach ?? bests.count, closures: closures)
    }
    /// What VoiceOver says for one row: the place, the night, the score and band, what the clouds
    /// rest on, and a closure.
    static func spoken(_ night: Night, closure: String?) -> String {
        var parts = [night.park.shortName, night.park.dayLabel(night.id), String(localized: "\(night.score.value), \(night.score.band.label)")]
        parts += night.basisLabels
        if let closure { parts.append(String(localized: "Closure: \(closure)")) }
        return parts.joined(separator: ". ")
    }
}
