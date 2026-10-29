import Foundation
import Testing
@testable import Nyx

/// The same night is picked, and scored, the same way on every surface: the best night with a
/// closure, and the usual clouds handed to the widgets and the watch.
@MainActor @Suite struct SameNightTests {
    let parks: [Park] = (try? ParkData.load()) ?? []
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

    /// Joshua Tree 90 with a closure against Death Valley 84, open: whatever claims the darkest says
    /// Joshua Tree 90 with its closure beside it; whatever recommends the best says Death Valley.
    @Test func darkestIsTheSkyBestCountsTheClosure() throws {
        let jotr = try park("jotr"), deva = try park("deva")
        func night(_ park: Park, _ score: Int) -> Night {
            let sky = AstronomyEngine().conditions(for: park, on: park.currentNight(at: now))
            return Night(park: park, sky: sky, score: DarknessScore(value: score, moonPoints: 30, cloudPoints: 24, bortlePoints: 16, lengthPoints: 10), cloudCover: 5, forecastUpdated: now)
        }
        let closed = night(jotr, 90), open = night(deva, 84), closures = ["jotr": "Park Boulevard closed"]
        // Darkest: Tonight's ranking, the map's list and summary, the week's rows.
        #expect(NightPlanner.ranked([open, closed]).first?.park.id == "jotr")
        let map = TonightMap(nights: [open, closed], closures: closures)
        #expect(map.darkest.first?.id == "jotr" && map.darkest.first?.score == 90 && map.darkest.first?.closure == "Park Boulevard closed")
        #expect(map.summary.contains("Park Boulevard closed"))
        let week = WeekAcrossParks.make([[open], [closed]], closures: closures)
        #expect(week.rows.first?.park.id == "jotr" && week.closures["jotr"] == "Park Boulevard closed")
        #expect(WeekAcrossParks.spoken(closed, isBest: false, closure: week.closures["jotr"]).contains("Park Boulevard closed"))
        // Best: the week's ring, the trip planner, Siri's ranking.
        #expect(week.best.map { week.rows[$0.row].nights[$0.night].park.id } == "deva")
        let day = TripDay(closed.id, calendar: jotr.calendar)
        let trip = TripPlanner.plan(days: [day], grid: [[closed, open]], closures: closures, maxHopMeters: .infinity)
        #expect(trip.best?.night.park.id == "deva" && trip.best?.night.score.value == 84)
        #expect(NightPlanner.ranked([closed, open], closures: closures).first?.park.id == "deva")
    }

    /// A world place's usual clouds, carried to the widgets and the watch as whole percents, score
    /// its nights exactly as the iPhone's grid does: the grid holds whole percents itself, and both
    /// ease them between months the same way.
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
        }
    }

    /// The iPhone names the data it scores with; a watch whose bundled data differs says so, and an
    /// older iPhone's context, which names none, says nothing.
    @Test func watchKnowsWhenItsDataDiffers() throws {
        let mine = try #require(WatchContext.bundledData)
        #expect(!mine.isEmpty && mine == WatchContext.bundledData(in: .main))
        let same = WatchContext(sent: now, savedParkIDs: [], homeParkID: "jotr", nightVision: false, forecasts: [:])
        #expect(same.dataVersion == mine && !same.dataDiffers && same.dataNote == nil)
        let data = try #require(same.data)
        let decoded = try #require(WatchContext(data: data))
        #expect(decoded.dataVersion == mine && decoded == same)
        let other = WatchContext(sent: now, savedParkIDs: [], homeParkID: "jotr", nightVision: false, forecasts: [:], dataVersion: "0")
        #expect(other.dataDiffers && other.dataNote == "iPhone and Apple Watch have different versions of Nyx. Update both for matching scores.")
        // An iPhone before the fingerprint: nothing to compare.
        let old = try #require(WatchContext(data: Data(#"{"version":1,"sent":0,"homeParkID":"jotr"}"#.utf8)))
        #expect(old.dataVersion == nil && !old.dataDiffers)
    }

    /// The fingerprint follows what scores rest on, never the words: a new description or viewing
    /// spot leaves it alone; a moved park, a new Bortle estimate, other usual clouds or new scoring
    /// rules change it.
    @Test func dataFingerprintFollowsOnlyScoreInputs() throws {
        let climate = try #require(CloudClimate.load()).parks
        let base = WatchContext.fingerprint(parks: parks, climate: climate)
        #expect(base == WatchContext.bundledData)
        func edited(_ change: (inout [String: Any]) -> Void) throws -> [Park] {
            var list = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(parks)) as? [[String: Any]])
            change(&list[0])
            return try JSONDecoder().decode([Park].self, from: JSONSerialization.data(withJSONObject: list))
        }
        #expect(WatchContext.fingerprint(parks: try edited { $0["description"] = "Other words." ; $0["sourceNote"] = "Another note." }, climate: climate) == base)
        #expect(WatchContext.fingerprint(parks: try edited { $0["viewingSpots"] = [Any]() }, climate: climate) == base)
        #expect(WatchContext.fingerprint(parks: try edited { $0["bortleEstimate"] = 9 }, climate: climate) != base)
        #expect(WatchContext.fingerprint(parks: try edited { $0["latitude"] = 10.5 }, climate: climate) != base)
        var cloudier = climate
        let id = try #require(climate.keys.sorted().first), months = try #require(climate[id])
        cloudier[id] = CloudClimate.Months(cloud: months.cloud.map { $0.map { $0+1 } }, clear: months.clear)
        #expect(WatchContext.fingerprint(parks: parks, climate: cloudier) != base)
        #expect(WatchContext.fingerprint(parks: parks, climate: climate, rules: ScoreEngine.rulesVersion+1) != base)
    }

    /// Tonight's pick travels to the widgets and the watch only while the night it was picked for is
    /// still tonight there; a pick kept from an earlier night is never handed on as tonight's.
    @Test func tonightsPickExpiresWithItsNight() throws {
        let suite = "nyx-pick-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlanModel(defaults: defaults)
        model.tonightPickID = "jotr"
        let jotr = try park("jotr")
        #expect(model.tonightPick == "jotr" && model.tonightPickNight == jotr.isoDay(jotr.currentNight(at: model.present)))
        #expect(defaults.string(forKey: "tonightPickNight") == model.tonightPickNight)
        // Days later: the same pick, kept on disk, is no longer tonight's.
        defaults.set("2020-01-01", forKey: "tonightPickNight")
        let later = PlanModel(defaults: defaults)
        #expect(later.tonightPickID == "jotr" && later.tonightPick == nil)
        // A pick saved before its night was kept: not handed on until Tonight answers again.
        defaults.removeObject(forKey: "tonightPickNight")
        #expect(PlanModel(defaults: defaults).tonightPick == nil)
    }
}
