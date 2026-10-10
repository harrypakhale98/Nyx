import Foundation
import Testing
@testable import Nyx

/// The forecast models' range the iPhone hands Apple Watch (`WatchContext.ranges`): the same
/// range the iPhone's dial shows, read on the wrist only beside a score it still holds.
struct WatchModelRangeTests {
    func park(_ id: String) throws -> Park { try #require(try ParkData.load().first { $0.id == id }) }
    private let t0 = 1_791_158_400.0 // 2026-10-05 00:00 UTC

    @MainActor @Test func theWatchShowsTheRangeTheIPhoneShows() throws {
        let jotr = try park("jotr"), now = Date.now
        // The disagreeing-models fixture: a different spread each night, so some nights have a range.
        let fixture = try #require(DebugForecasts(state: "disagree", parks: [jotr], now: now))
        let model = PlanModel()
        model.forecasts = fixture.forecasts; model.details = fixture.details
        let ranges = SavedSkySync.modelRanges(model, ids: ["jotr", "jotr"])
        #expect(!(ranges["jotr"] ?? [:]).isEmpty)
        let sent = WatchContext.make(savedParkIDs: ["jotr"], homeParkID: "jotr", nightVision: false, forecasts: fixture.forecasts,
                                     details: fixture.details, ranges: ranges, now: now)
        let wrist = try #require(WatchContext(dictionary: sent.dictionary))
        #expect(wrist == sent && !wrist.ranges.isEmpty)
        var shownOnBoth = 0
        for offset in 0..<7 {
            let night = model.night(jotr, on: jotr.date(model.tonight(jotr), addingDays: offset))
            let phone = CelestialGauge.modelRange(model.outlook(night), basis: night.basis)
            // The watch scores the night itself from what was sent, then looks up the range.
            let watch = NightPlanner.night(park: jotr, sky: night.sky, forecast: wrist.cloudForecasts["jotr"], detail: wrist.forecastDetails["jotr"], now: now)
            #expect(watch.score.value == night.score.value, "night \(offset)")
            #expect(wrist.modelRange(for: watch) == phone, "night \(offset)")
            if let phone {
                #expect(phone.contains(watch.score.value))
                shownOnBoth += 1
            }
        }
        #expect(shownOnBoth > 0)
    }

    @Test func rangesDecodeLenientlyAndNeverLeaveTheScoreOut() throws {
        let jotr = try park("jotr"), now = Date(timeIntervalSince1970: t0 + 30*3600)
        let hours = (0..<17*24).map { t0 + Double($0)*3600 }
        let forecast = Forecast(updated: now.addingTimeInterval(-3600), times: hours, clouds: hours.map { _ in 20 })
        let night = NightPlanner.night(park: jotr, sky: AstronomyEngine().conditions(for: jotr, on: jotr.currentNight(at: now)), forecast: forecast, detail: nil, now: now)
        try #require(night.basis == .forecast)
        let day = WatchContext.day(night.id, in: jotr), score = night.score.value
        func context(_ pair: [Int]) -> WatchContext {
            WatchContext(sent: now, savedParkIDs: ["jotr"], homeParkID: "jotr", nightVision: false, forecasts: [:], ranges: ["jotr": [day: pair]])
        }
        #expect(day.count == 10 && day.hasPrefix("2026-10-0"))
        let low = max(0, score-6), high = min(100, score+6)
        #expect(context([low, high]).modelRange(for: night) == low...high)
        // A range that leaves the wrist's score out, a spread of 4 or less, or a malformed pair: none.
        #expect(context([min(100, score+1), min(100, score+9)]).modelRange(for: night) == nil)
        #expect(context([max(0, score-2), min(100, score+2)]).modelRange(for: night) == nil)
        #expect(context([low, score, high]).modelRange(for: night) == nil)
        #expect(context([high, low]).modelRange(for: night) == nil)
        // Without a full forecast the iPhone shows no range, and neither does the watch.
        let usual = NightPlanner.night(park: jotr, sky: night.sky, forecast: nil, detail: nil, now: now)
        #expect(context([0, 100]).modelRange(for: usual) == nil)
        // A park whose clouds did not travel sends no range: it would mean nothing on the wrist.
        let made = WatchContext.make(savedParkIDs: ["jotr", "deva"], homeParkID: "jotr", nightVision: false, forecasts: ["jotr": forecast],
                                     ranges: ["jotr": [day: low...high], "deva": [day: 10...40]], now: now)
        #expect(made.ranges == ["jotr": [day: [low, high]]])
        // A 1.2 iPhone's context has no ranges; a malformed field costs only the ranges.
        let data = try #require(made.data)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["ranges"] = nil
        let old = try #require(WatchContext(data: try JSONSerialization.data(withJSONObject: object)))
        #expect(old.ranges.isEmpty && old.cloudForecasts["jotr"] != nil)
        object["ranges"] = "junk"
        let junk = try #require(WatchContext(data: try JSONSerialization.data(withJSONObject: object)))
        #expect(junk.ranges.isEmpty && junk.forecasts == made.forecasts)
    }
}
