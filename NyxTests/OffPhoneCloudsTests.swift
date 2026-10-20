import Foundation
import Testing
@testable import Nyx

/// Off the phone (widgets, Apple Watch, watch Siri), a saved spot or world place is scored with the
/// usual clouds the iPhone hands over from its world grid, so its nights read the same numbers as in
/// the app; both hand-overs stay readable by older and newer readers alike. A widget set to a place
/// that is no longer saved says so instead of showing another place.
@MainActor @Suite struct OffPhoneCloudsTests {
    private let now = Date(timeIntervalSince1970: 1_791_158_400) // 2026-10-05 00:00 UTC
    /// The extensions' climate: the bundled per-park file, no grid tiles.
    private func offPhone() throws -> CloudClimate { try #require(CloudClimate.load()) }
    /// A world place the grid covers in every month.
    private func abroad() throws -> Park {
        try #require(try CatalogData.load().first { place in
            CloudClimate.shared.months(for: place).map { $0.cloud.allSatisfy { $0 != nil } && $0.clear.allSatisfy { $0 != nil } } ?? false
        })
    }
    /// An hourly forecast issued at `now`, `days` days long, at a steady cover.
    private func forecast(days: Int, cover: Double) -> Forecast {
        let start = now.timeIntervalSince1970
        return Forecast(updated: now, times: (0..<(days*24)).map { start+Double($0)*3600 }, clouds: Array(repeating: cover, count: days*24))
    }
    private func same(_ a: Night, _ b: Night, _ label: String) {
        #expect(a.score.value == b.score.value, "\(label)")
        #expect(a.usualCloud == b.usualCloud && a.basis == b.basis, "\(label)")
    }

    @Test func aWorldPlaceScoresTheSameOnTheWidgetAsOnThePhone() throws {
        let place = try abroad()
        let phone = NightPlanner(forecasts: [place.id: forecast(days: 7, cover: 40)])
        // What the app writes for the widgets, through the bytes the widget reads.
        let written = SavedSkySnapshot(parks: [place], forecasts: [place.id: forecast(days: 7, cover: 40)], usualClouds: CloudClimate.shared.carriedMonths(for: [place]))
        let read = try JSONDecoder().decode(SavedSkySnapshot.self, from: try JSONEncoder().encode(written))
        #expect(read.usualClouds?[place.id] != nil)
        let widget = NightPlanner(forecasts: read.forecasts, climate: try offPhone().carrying(read.usualClouds))
        let without = NightPlanner(forecasts: read.forecasts, climate: try offPhone())
        var differed = false
        // Inside the forecast, the early look, and well beyond the forecast (no clouds forecast at all).
        for offset in [0, 2, 5, 9, 12, 20, 40] {
            let evening = place.date(place.currentNight(at: now), addingDays: offset)
            let mine = phone.night(place, on: evening, now: now)
            same(widget.night(place, on: evening, now: now), mine, "night +\(offset)")
            if offset >= 12 { #expect(mine.basis == .usual && mine.usualCloud != nil, "night +\(offset)") }
            // Before 2.0 (15) the extensions had no usual clouds for such a place.
            if without.night(place, on: evening, now: now).score.value != mine.score.value { differed = true }
        }
        #expect(differed)
    }

    @Test func aWorldPlaceScoresTheSameOnTheWatchAsOnThePhone() throws {
        let place = try abroad()
        let sent = WatchContext.make(savedParkIDs: [place.id, "jotr"], homeParkID: "jotr", nightVision: false, forecasts: [place.id: forecast(days: 16, cover: 25)],
                                     places: [place], now: now)
        let data = try #require(sent.data)
        #expect(data.count <= WatchContext.byteBudget)
        let received = try #require(WatchContext(data: data))
        #expect(received.usualClouds[place.id] == CloudClimate.shared.months(for: place) && received.usualClouds["jotr"] == nil)
        let phone = NightPlanner(forecasts: [place.id: forecast(days: 16, cover: 25)])
        let wrist = try offPhone().carrying(received.usualClouds)
        for offset in [0, 4, 8, 15, 17, 30] {
            let evening = place.date(place.currentNight(at: now), addingDays: offset)
            let mine = phone.night(place, on: evening, now: now)
            let theirs = NightPlanner.night(park: place, sky: AstronomyEngine().conditions(for: place, on: evening), forecast: received.cloudForecasts[place.id],
                                            detail: nil, now: now, climate: wrist)
            same(theirs, mine, "night +\(offset)")
        }
        // The watch's own scoring climate already carries them.
        #expect(received.climate.carried[place.id] != nil)
    }

    @Test func theSixtyThreeParksCarryNothingAndEveryPlaceWaitsForItsMonths() throws {
        let jotr = try #require(try ParkData.load().first { $0.id == "jotr" })
        #expect(CloudClimate.shared.months(for: jotr) == nil)
        // Off the phone nothing can be worked out: no grid.
        #expect(try offPhone().months(for: try abroad()) == nil)
        // The per-park file still wins over anything carried under a park's id.
        let wrong = CloudClimate.Months(cloud: Array(repeating: 99, count: 12), clear: Array(repeating: 1, count: 12))
        let evening = jotr.currentNight(at: now)
        #expect(CloudClimate.shared.carrying([jotr.id: wrong]).typical(jotr, on: evening) == CloudClimate.shared.typical(jotr, on: evening))
    }

    @Test func bothHandOversStayReadableEitherWay() throws {
        let place = try abroad()
        // A snapshot from before 2.0 (15): no usual clouds, still decodes, scores as before.
        let old = try JSONEncoder().encode(SavedSkySnapshot(parks: [place], forecasts: [:]))
        let object = try #require(try JSONSerialization.jsonObject(with: old) as? [String: Any])
        #expect(object["usualClouds"] == nil)
        #expect(try JSONDecoder().decode(SavedSkySnapshot.self, from: old).usualClouds == nil)
        // One place's months that no longer decode cost only that place's.
        let good = try #require(CloudClimate.shared.months(for: place))
        var mixed = object
        mixed["usualClouds"] = [place.id: ["cloud": good.cloud.map { $0 ?? 0 }, "clear": good.clear.map { $0 ?? 0 }], "pin:x": ["cloud": "cloudy"]]
        let decoded = try JSONDecoder().decode(SavedSkySnapshot.self, from: try JSONSerialization.data(withJSONObject: mixed))
        #expect(decoded.parks.map(\.id) == [place.id] && decoded.usualClouds?.keys.sorted() == [place.id])
        // A context from an iPhone before 2.0 (15) decodes, its places intact, with no usual clouds.
        let context = WatchContext.make(savedParkIDs: [place.id], homeParkID: "jotr", nightVision: false, forecasts: [:], places: [place], now: now)
        let bytes = try #require(context.data)
        let sentObject = try JSONSerialization.jsonObject(with: bytes)
        var sent = try #require(sentObject as? [String: Any])
        #expect(sent["usualClouds"] != nil)
        sent["usualClouds"] = nil
        let older = try #require(WatchContext(data: try JSONSerialization.data(withJSONObject: sent)))
        #expect(older.places.map(\.id) == [place.id] && older.usualClouds.isEmpty)
    }

    @Test func manyFollowedPlacesStayWithinTheWatchBudget() throws {
        let places = Array(try CatalogData.load().lazy.filter { CloudClimate.shared.months(for: $0) != nil }.prefix(60))
        let forecasts = Dictionary(uniqueKeysWithValues: places.map { ($0.id, forecast(days: 16, cover: 30)) })
        let context = WatchContext.make(savedParkIDs: places.map(\.id), homeParkID: "jotr", nightVision: false, forecasts: forecasts, places: places, now: now)
        #expect((context.data?.count ?? .max) <= WatchContext.byteBudget)
        // Each place that travels brings its usual clouds with it, the last one too.
        #expect(!context.places.isEmpty && context.places.allSatisfy { context.usualClouds[$0.id] != nil })
    }

    @Test func aWidgetSetToAPlaceNoLongerSavedSaysSo() throws {
        let jotr = try #require(try ParkData.load().first { $0.id == "jotr" })
        var builder = TonightTimeline(snapshot: SavedSkySnapshot(parks: [jotr], forecasts: [:]), large: true, unsaved: "Eifel")
        let entry = builder.entry(at: now)
        #expect(entry.night == nil && entry.unsaved == "Eifel" && entry.savedCount == 0)
        #expect(builder.duskWindows(from: now, nights: 14).isEmpty)
        #expect(TonightWidgetView.unsavedSummary("Eifel").hasPrefix("Eifel is no longer saved in Nyx."))
        #expect(TonightWidgetView.unsavedTitle("") == "This place is no longer saved in Nyx.")
        #expect(TonightControlValue.unsaved.score == nil && TonightControlValue.unsaved.parkID == nil)
    }
}
