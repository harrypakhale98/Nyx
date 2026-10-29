import Foundation

/// The darkest few of a park's next thirty nights, best first, each with how many nights
/// after tonight it falls, so a planner can step straight to it. Ranked by `NightPlanner.better`
/// over `NightPlanner.bestNights`, so each night is scored exactly as everywhere else: the cloud
/// forecast where it reaches, eased toward the park's usual clouds days ahead, the usual clouds
/// alone beyond. Pure: the forecasts and "now" come in. Shown in the Vision Pro planner.
nonisolated struct NightsAhead: Sendable {
    nonisolated struct Pick: Sendable, Identifiable {
        let night: Night
        /// Nights after tonight (park-local): 0 is tonight.
        let offset: Int
        var id: Date { night.id }
    }
    let park: Park
    let picks: [Pick]
    /// True when no night searched has any true darkness (an Alaskan summer): the ranking still
    /// holds, but none of the nights is truly dark. Every night counts, not only the picks: a dark
    /// night under cloud can rank below clear twilit ones, as Siri's best night says it.
    let noDarkness: Bool

    /// Tonight and the nights after it to `NightPlanner.horizon`, the iPhone's best-night reach.
    init(park: Park, planner: NightPlanner, now: Date, count: Int = NightPlanner.horizon, limit: Int = 3) {
        let tonight = park.currentNight(at: now)
        self.park = park
        let ranked = planner.bestNights([park], from: now, count: count, now: now, limit: .max)
        picks = ranked.prefix(max(0, limit)).map { Pick(night: $0, offset: Self.offset(of: $0.id, after: tonight, in: park)) }
        noDarkness = !ranked.isEmpty && ranked.allSatisfy { $0.sky.darkHours <= 0 }
    }
    /// Whole park-local nights from `tonight` to `evening`, never negative.
    static func offset(of evening: Date, after tonight: Date, in park: Park) -> Int {
        max(0, park.calendar.dateComponents([.day], from: park.evening(tonight), to: park.evening(evening)).day ?? 0)
    }
    /// The first pick whose clouds rest on less than a full forecast, the one whose caption explains the rest.
    var firstEstimate: Pick? { picks.first { !$0.night.score.hasForecast } }
}
