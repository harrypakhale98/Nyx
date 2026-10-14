import Foundation
import Testing
@testable import Nyx

/// The same night is picked, and scored, the same way on every surface: the best night with a
/// closure, and the usual clouds handed to the widgets and the watch.
@MainActor @Suite struct SameNightTests {
    let parks: [Park] = (try? ParkData.load()) ?? []
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    let now = Date(timeIntervalSince1970: 1_792_180_800) // 2026-10-16 20:00 UTC

    /// A closed park's slightly darker night is not the best night in the trip planner, Siri's
    /// ranking or the week's ring; a much darker one still is, everywhere alike.
    @Test func bestNightAgreesForAClosedPark() throws {
        let jotr = try park("jotr"), deva = try park("deva")
        let days = [TripDay(year: 2026, month: 10, day: 16), TripDay(year: 2026, month: 10, day: 17)]
        func night(_ park: Park, _ day: Int, _ score: Int) -> Night {
            let sky = AstronomyEngine().conditions(for: park, on: park.date(park.currentNight(at: now), addingDays: day))
            return Night(park: park, sky: sky, score: DarknessScore(value: score, moonPoints: 30, cloudPoints: 24, bortlePoints: 16, lengthPoints: 10), cloudCover: 5, forecastUpdated: now)
        }
        func picks(jotr scores: [Int], closures: [String: String]) -> (trip: Night?, siri: Night?, week: Night?) {
            let grid = days.indices.map { [night(jotr, $0, scores[$0]), night(deva, $0, [84, 80][$0])] }
            let trip = TripPlanner.plan(days: days, grid: grid, closures: closures, maxHopMeters: .infinity).best?.night
            let siri = NightPlanner.ranked(grid.flatMap { $0 }, closures: closures).first
            let week = WeekAcrossParks.make([grid.map { $0[0] }, grid.map { $0[1] }], closures: closures)
            let ringed = week.best.map { week.rows[$0.row].nights[$0.night] }
            return (trip, siri, ringed)
        }
        func same(_ a: Night?, _ b: Night?) -> Bool { a?.park.id == b?.park.id && a?.id == b?.id }
        let closed = ["jotr": "Park road closed"]
        // Open: Joshua Tree's 90 is the best night everywhere.
        let open = picks(jotr: [90, 88], closures: [:])
        #expect(open.trip?.park.id == "jotr" && open.trip?.score.value == 90 && same(open.trip, open.siri) && same(open.trip, open.week))
        // Closed: 90 counts as 80, below Death Valley's 84, on every surface.
        let shut = picks(jotr: [90, 88], closures: closed)
        #expect(shut.trip?.park.id == "deva" && shut.trip?.score.value == 84 && same(shut.trip, shut.siri) && same(shut.trip, shut.week))
        // Far darker even when closed: still the best, everywhere.
        let dark = picks(jotr: [99, 88], closures: closed)
        #expect(dark.trip?.park.id == "jotr" && same(dark.trip, dark.siri) && same(dark.trip, dark.week))
        #expect(TripPlanner.closurePenalty == NightPlanner.closurePenalty)
        // Siri's own search takes the closures the same way.
        let planner = NightPlanner(forecasts: [:])
        let all = planner.bestNights([jotr, deva], from: now, count: 3, now: now, limit: .max)
        let answer = try #require(BestNightSearch.answer(parks: [jotr, deva], planner: planner, from: now, nights: 3, now: now, closures: ["\(all[0].park.id)": "Closed"]))
        #expect(same(answer.best, NightPlanner.ranked(all, closures: ["\(all[0].park.id)": "Closed"]).first))
    }

    /// A world place's usual clouds, carried to the widgets and the watch as whole percents, score
    /// its nights exactly as the iPhone's grid does: the grid holds whole percents itself.
    @Test func carriedUsualCloudsScoreAsOnTheIPhone() throws {
        let place = try #require(ParkLibrary.catalog().first { CloudClimate.shared.months(for: $0) != nil })
        let months = try #require(CloudClimate.shared.carriedMonths(for: [place])[place.id])
        // Off the phone: the bundled per-park file and the carried months, no grid.
        let carried = (CloudClimate.load() ?? CloudClimate(parks: [:])).carrying([place.id: months])
        for day in [0, 40, 120, 250] {
            let sky = AstronomyEngine().conditions(for: place, on: place.date(place.currentNight(at: now), addingDays: day))
            let phone = NightPlanner.night(park: place, sky: sky, forecast: nil, detail: nil, now: now)
            let wrist = NightPlanner.night(park: place, sky: sky, forecast: nil, detail: nil, now: now, climate: carried)
            #expect(phone.usualCloud != nil && phone.usualCloud == wrist.usualCloud && phone.score.value == wrist.score.value, "day \(day)")
            if let usual = phone.usualCloud { #expect(usual == usual.rounded()) }
        }
    }
}
