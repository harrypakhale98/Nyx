import Foundation
import Testing
@testable import Nyx

/// Plan's best nights in reach: each place's best night of the next 30, the places ordered by it, a
/// closure counted against a park as wherever a best night is recommended.
@MainActor struct BestNightsTests {
    let parks: [Park]
    init() throws { parks = try ParkData.load() }
    private func months(_ ids: [String], from start: Date, count: Int = NightPlanner.horizon) -> [[Night]] {
        let engine = AstronomyEngine(), scoring = ScoreEngine()
        return ids.compactMap { id in parks.first { $0.id == id } }.map { park in
            (0..<count).map { day in
                let sky = engine.conditions(for: park, on: park.evening(park.date(start, addingDays: day)))
                return Night(park: park, sky: sky, score: scoring.score(sky: sky, bortle: park.bortleEstimate, cloudCover: nil), cloudCover: nil, forecastUpdated: nil)
            }
        }
    }
    @Test func placesAreOrderedByTheirBestNight() throws {
        let start = Date(timeIntervalSince1970: 1_792_500_000)
        let input = months(["cuva", "jotr", "grba", "deva", "grca", "bibe", "indu", "acad", "romo", "yell", "zion", "arch"], from: start)
        let ranking = BestNightsInReach.make(input)
        #expect(ranking.rows.count == BestNightsInReach.rowLimit && ranking.total == 12)
        // One row per place, each the place's own best night of the month.
        #expect(Set(ranking.rows.map(\.id)).count == ranking.rows.count)
        for row in ranking.rows {
            let month = try #require(input.first { $0.first?.park.id == row.id })
            #expect(!month.contains { NightPlanner.better($0, row.best) })
        }
        for (a, b) in zip(ranking.rows, ranking.rows.dropFirst()) { #expect(!NightPlanner.better(b.best, a.best)) }
        // The best night overall leads, and nothing in any month beats it.
        let best = try #require(ranking.best)
        #expect(!input.joined().contains { NightPlanner.better($0, best) })
    }
    @Test func aClosureCountsAgainstItsPark() throws {
        let start = Date(timeIntervalSince1970: 1_792_500_000)
        let input = months(["deva", "grba"], from: start)
        let open = BestNightsInReach.make(input)
        let leader = try #require(open.best?.park.id)
        let closed = BestNightsInReach.make(input, closures: [leader: "Main road closed"])
        // Ten points down: the other park leads unless the closed one is still ten points darker.
        let other = try #require(open.rows.first { $0.id != leader })
        let first = try #require(open.best)
        if first.rankScore - NightPlanner.closurePenalty < other.best.rankScore { #expect(closed.best?.park.id == other.id) }
        else { #expect(closed.best?.park.id == leader) }
        #expect(closed.closures[leader] == "Main road closed")
        // The scores themselves never change.
        #expect(closed.rows.first { $0.id == leader }?.best.score.value == first.score.value)
    }
    @Test func nothingInReachRanksNothing() {
        let none = BestNightsInReach.make([])
        #expect(none.rows.isEmpty && none.total == 0 && none.best == nil)
        #expect(BestNightsInReach.make([[]]).rows.isEmpty)
    }
    @Test func aRowIsSpokenWithWhatItRestsOn() throws {
        let start = Date(timeIntervalSince1970: 1_792_500_000)
        let night = try #require(months(["jotr"], from: start, count: 1).first?.first)
        let spoken = BestNightsInReach.spoken(night, closure: "Keys View Road closed")
        #expect(spoken.hasPrefix(night.park.shortName))
        #expect(spoken.contains(String(localized: "\(night.score.value), \(night.score.band.label)")))
        // No cloud figure: the usual-clouds label is said, so an estimate never sounds like a forecast.
        for label in night.basisLabels { #expect(spoken.contains(label)) }
        #expect(spoken.contains(String(localized: "Closure: Keys View Road closed")))
    }
}
