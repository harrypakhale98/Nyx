import Foundation
import Testing
@testable import Nyx

/// "Looking back": a night is noted only from a full forecast over true darkness while its clouds are
/// ahead, answered only by a forecast issued after it, compared only under the same rules, and kept
/// within its limits.
@MainActor struct HindsightTests {
    let engine = AstronomyEngine(), scoring = ScoreEngine()
    private func night(_ park: Park, _ iso: String, cloud: Double?, issued: Date?) throws -> Night {
        let day = try #require(TripDay(iso: iso))
        let sky = engine.conditions(for: park, on: day.evening(in: park))
        let score = scoring.score(sky: sky, bortle: park.bortleEstimate, cloud: cloud, basis: .forecast, aerosol: nil)
        return Night(park: park, sky: sky, score: score, cloudCover: cloud, forecastUpdated: issued)
    }
    @Test func aNightIsNotedOnlyFromAForecastBeforeItsClouds() throws {
        let jotr = try park("jotr")
        let forecast = try night(jotr, "2026-11-09", cloud: 5, issued: Date(timeIntervalSince1970: 1_794_000_000))
        let before = forecast.sky.cloudWindow.start.addingTimeInterval(-3600)
        let record = try #require(Hindsight.note(forecast, now: before))
        #expect(record.said == forecast.score.value && record.saidCloud == 5 && record.day == jotr.isoDay(forecast.id) && record.looked == nil)
        // Once the clouds have begun, what Nyx said is fixed.
        #expect(Hindsight.note(forecast, now: forecast.sky.cloudWindow.start.addingTimeInterval(60)) == nil)
        // No cloud figure: nothing to compare.
        #expect(Hindsight.note(try night(jotr, "2026-11-09", cloud: nil, issued: nil), now: before) == nil)
        // No true darkness (Gates of the Arctic in June): nothing to compare.
        let polar = try night(try park("gaar"), "2026-06-21", cloud: 5, issued: Date(timeIntervalSince1970: 1_781_000_000))
        #expect(Hindsight.note(polar, now: polar.sky.evening) == nil)
    }
    @Test func aNightIsAnsweredOnlyByAForecastIssuedAfterIt() throws {
        let jotr = try park("jotr")
        let said = try night(jotr, "2026-11-09", cloud: 5, issued: Date(timeIntervalSince1970: 1_794_000_000))
        let record = try #require(Hindsight.note(said, now: said.sky.cloudWindow.start.addingTimeInterval(-3600)))
        let end = said.sky.cloudWindow.end
        // Fetched too soon after the night's clouds ended: model runs arrive hours late, so not yet an answer.
        #expect(Hindsight.check(record, against: try night(jotr, "2026-11-09", cloud: 40, issued: end.addingTimeInterval(3*3600))) == nil)
        let looked = try night(jotr, "2026-11-09", cloud: 40, issued: end.addingTimeInterval(Hindsight.settle+60))
        let answered = try #require(Hindsight.check(record, against: looked))
        #expect(answered.looked?.score == looked.score.value && answered.looked?.cloud == 40)
        // The same rules the score itself uses for that cloud.
        #expect(answered.looked?.score == scoring.score(sky: looked.sky, bortle: jotr.bortleEstimate, cloud: 40, basis: .forecast, aerosol: nil).value)
        // Answered once; another night or other rules never answer it.
        #expect(Hindsight.check(answered, against: looked) == nil)
        #expect(Hindsight.check(record, against: try night(jotr, "2026-11-10", cloud: 40, issued: end.addingTimeInterval(90000))) == nil)
        let older = HindsightRecord(placeID: record.placeID, evening: record.evening, day: record.day, said: record.said, saidCloud: record.saidCloud,
                                    issued: record.issued, rules: ScoreEngine.rulesVersion-1, looked: nil)
        #expect(Hindsight.check(older, against: looked) == nil)
    }
    private func record(_ day: Int, said: Int = 80, seen: Int? = nil) -> HindsightRecord {
        let evening = Date(timeIntervalSince1970: 1_790_000_000 + Double(day)*86400)
        return HindsightRecord(placeID: "jotr", evening: evening, day: "day-\(day)", said: said, saidCloud: 5, issued: evening, rules: ScoreEngine.rulesVersion,
                               looked: seen.map { .init(score: $0, cloud: 10, issued: evening.addingTimeInterval(86400)) })
    }
    @Test func recordsKeepOnePerNightAndTheirLimit() {
        var records: [HindsightRecord] = []
        for day in 0..<70 { records = Hindsight.upsert(record(day), into: records) }
        #expect(records.count == Hindsight.limit && records.first?.day == "day-69")
        records = Hindsight.upsert(record(69, said: 50), into: records)
        #expect(records.count == Hindsight.limit && records.filter { $0.day == "day-69" }.map(\.said) == [50])
        // Unanswered nights are let go after a few days; answered ones stay.
        let now = record(10).evening.addingTimeInterval(Hindsight.patience+1)
        let kept = Hindsight.pruned([record(10), record(9, seen: 70)], now: now)
        #expect(kept.map(\.day) == ["day-9"])
    }
    @Test func aMovedAnswerLetsTheOldOneGo() {
        let first = record(5), moved = HindsightRecord(placeID: "deva", evening: first.evening, day: first.day, said: 70, saidCloud: 5, issued: first.evening, rules: ScoreEngine.rulesVersion, looked: nil)
        let records = Hindsight.upsert(moved, into: Hindsight.replacing(moved, in: [first, record(4, seen: 60)]))
        #expect(records.map(\.placeID) == ["deva", "jotr"] && records.last?.day == "day-4")
    }
    @Test func theTallyAndLastNight() throws {
        #expect(Hindsight.tally([record(1, seen: 80), record(2, seen: 60)]) == nil)
        let records = [record(1, seen: 80), record(2, seen: 60), record(3, seen: 75), record(4, seen: 91), record(5)]
        let tally = try #require(Hindsight.tally(records))
        #expect(tally.close == 2 && tally.of == 4)
        let now = record(4).evening.addingTimeInterval(12*3600)
        #expect(Hindsight.lastNight(records, now: now)?.day == "day-4")
        #expect(Hindsight.lastNight(records, now: now.addingTimeInterval(2*86400)) == nil)
    }
    @Test func theSentenceSaysBothNumbers() throws {
        let changed = try #require(Hindsight.sentence(record(1, said: 82, seen: 78), name: "Joshua Tree"))
        #expect(changed == String(localized: "Last night at Joshua Tree, Nyx said 82 with 5% cloud. Looking back, the weather models put the cloud at 10%: about 78."))
        let same = try #require(Hindsight.sentence(record(1, said: 82, seen: 82), name: "Joshua Tree"))
        #expect(same.contains("82") && same != changed)
        #expect(Hindsight.sentence(record(1), name: "Joshua Tree") == nil)
    }
}
