import Foundation
import Testing
@testable import Nyx

/// One place and night, one answer: the iPhone, the widgets' snapshot and Apple Watch score from
/// the same forecasts, and the hand-overs carry them for every place each surface follows.
@MainActor struct SameSkyTests {
    /// 2026-10-06 06:00 UTC.
    let now = Date(timeIntervalSince1970: 1_791_158_400 + 30*3600)
    private func hours(_ count: Int, around reference: Date? = nil) -> [Double] {
        let first = (floor((reference ?? now).timeIntervalSince1970/3600)-24)*3600
        return (0..<count).map { first+Double($0)*3600 }
    }
    /// Sixteen days of hourly clouds that differ from place to place and hour to hour.
    func forecast(_ seed: Int, at reference: Date? = nil) -> Forecast {
        let times = hours(17*24, around: reference)
        return Forecast(updated: (reference ?? now).addingTimeInterval(-3600), times: times, clouds: times.indices.map { Double(($0*(seed%7+3)+seed*13) % 101) })
    }
    /// A week of forecast detail: the three models, the cloud layers and smoke.
    func detail(_ seed: Int, at reference: Date? = nil, updated: Date? = nil) -> ForecastDetail {
        let times = hours(8*24, around: reference), issued = updated ?? (reference ?? now).addingTimeInterval(-3600)
        func values(_ step: Int, _ scale: Double = 1) -> [Double?] { times.indices.map { Double(($0*step+seed*11) % 101)*scale } }
        let models = HourlySeries(updated: issued, times: times, values: Dictionary(uniqueKeysWithValues: ForecastDetail.modelKeys.enumerated().map { ($1, values(5+$0)) }))
        let layers = HourlySeries(updated: issued, times: times, values: ["cloud_cover_low": values(3), "cloud_cover_mid": values(7), "cloud_cover_high": values(11)])
        let air = HourlySeries(updated: issued, times: times, values: ["aerosol_optical_depth": values(9, 0.008), "pm2_5": values(4)])
        return ForecastDetail(models: models, layers: layers, air: air)
    }
    private func nights(_ park: Park, count: Int = 7) -> [SkyConditions] {
        let engine = AstronomyEngine(), tonight = park.currentNight(at: now)
        return (0..<count).map { engine.conditions(for: park, on: park.date(tonight, addingDays: $0)) }
    }

    /// Saved parks (one a summit above the inversion), the starting park and Tonight's answer: each
    /// night the watch works out from the context matches the iPhone's on every count the face shows.
    @Test func theWatchScoresEveryFollowedNightAsTheIPhoneDoes() throws {
        let saved = ["jotr", "deva", "hale"], home = "chis", pick = "grba"
        let ids = saved+[home, pick]
        let forecasts = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, forecast($0+1)) })
        let details = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, detail($0+1)) })
        let sent = WatchContext.make(savedParkIDs: saved, homeParkID: home, nightVision: false, forecasts: forecasts, details: details,
                                     aboveInversion: ["hale"], tonightParkID: pick, now: now)
        let data = try #require(sent.data)
        let context = try #require(WatchContext(data: data))
        #expect(context.followedParkIDs == ids && context.droppedParkIDs.isEmpty && context.tonightParkID == pick)
        var smoky = 0, forecast = 0
        for id in ids {
            let place = try park(id)
            for sky in nights(place) {
                let phone = NightPlanner.night(park: place, sky: sky, forecast: forecasts[id], detail: details[id], now: now)
                let wrist = NightPlanner.night(park: place, sky: sky, forecast: context.cloudForecasts[id], detail: context.forecastDetails[id], now: now,
                                               climate: context.climate)
                #expect(wrist.score.value == phone.score.value, "\(id) \(sky.evening)")
                #expect(wrist.score.band == phone.score.band && wrist.basis == phone.basis, "\(id) \(sky.evening)")
                #expect(wrist.cloudCover == phone.cloudCover && wrist.aerosol == phone.aerosol, "\(id) \(sky.evening)")
                if phone.aerosol != nil { smoky += 1 }
                if phone.basis == .forecast { forecast += 1 }
            }
        }
        // Not a trivial match: smoke and full forecasts both reach some of the nights compared.
        #expect(smoky > 0 && forecast > 0)
    }

    /// Sixty saved parks with full forecasts and detail: the context stays within budget, no place
    /// lacks clouds while a later one has them, and the starting park and Tonight's answer either
    /// travel or are named as left out, so the watch can say why.
    @Test func manySavedPlacesNeverLeaveAGapInTheClouds() throws {
        let home = "chis", pick = "grsa"
        let saved = Array(TestData.parks.map(\.id).filter { $0 != home && $0 != pick }.prefix(60))
        let ids = saved+[home, pick]
        let forecasts = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, forecast($0+1)) })
        let details = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, detail($0+1)) })
        let context = WatchContext.make(savedParkIDs: saved, homeParkID: home, nightVision: false, forecasts: forecasts, details: details,
                                        aboveInversion: ["hale"], tonightParkID: pick, now: now)
        #expect(context.followedParkIDs == ids)
        #expect((context.data?.count ?? .max) <= WatchContext.byteBudget)
        let carried = ids.map { context.forecasts[$0] != nil }
        let gap = try #require(carried.firstIndex(of: false))
        #expect(gap > 0 && !carried[gap...].contains(true))
        for id in ids where context.forecasts[id] == nil { #expect(context.droppedParkIDs.contains(id)) }
        for id in [home, pick] { #expect(context.forecasts[id] != nil || context.droppedParkIDs.contains(id)) }
        // The wrist says plainly why, and does not offer a refresh that could not help.
        let data = try #require(context.data)
        let received = try #require(WatchContext(data: data))
        let start = try park(home), source = CloudSource.of(context: received, park: start, now: now)
        #expect(source == .dropped && !source.isStale && source.line(for: start) == "Too many saved places to send this whole forecast.")
        // An iPhone from before these fields: its context still decodes, with nothing left out or answered.
        let object = try JSONSerialization.jsonObject(with: data)
        var json = try #require(object as? [String: Any])
        for key in ["tonightParkID", "watchParkIDs", "droppedParkIDs"] { json.removeValue(forKey: key) }
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let older = try #require(WatchContext(data: stripped))
        #expect(older.tonightParkID == nil && older.watchParkIDs.isEmpty && older.droppedParkIDs.isEmpty && older.forecasts == context.forecasts)
        let answer = try park(pick)
        #expect(CloudSource.of(context: older, park: answer, now: now) == .missing(followed: false))
    }

    /// A change to a followed place's smoke alone (a park's page fetching its detail) is a change
    /// worth handing over; the same data again, or a change at a place nobody follows, is not.
    @Test func followedDataChangesOnADetailOnlyChange() {
        let ids = SavedSkySync.followedIDs(saved: ["jotr", "deva"], home: "chis", tonight: "deva", watch: ["grba", "jotr"], widgets: ["yell", "chis"])
        #expect(ids == ["jotr", "deva", "chis", "grba", "yell"])
        let forecasts = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, forecast($0+1)) })
        var details = ["jotr": detail(1)]
        let before = FollowedData(ids: ids, forecasts: forecasts, details: details, closures: [:])
        #expect(FollowedData(ids: ids, forecasts: forecasts, details: details, closures: [:]) == before)
        details["deva"] = ForecastDetail(air: detail(2).air)
        #expect(FollowedData(ids: ids, forecasts: forecasts, details: details, closures: [:]) != before)
        let smoke = FollowedData(ids: ids, forecasts: forecasts, details: details, closures: [:])
        details["deva"] = ForecastDetail(air: detail(2, updated: now).air)
        #expect(FollowedData(ids: ids, forecasts: forecasts, details: details, closures: [:]) != smoke)
        // A closure, and a new place followed, are changes too; a park nobody follows is not.
        #expect(FollowedData(ids: ids, forecasts: forecasts, details: details, closures: ["yell": "Road closed"]) != FollowedData(ids: ids, forecasts: forecasts, details: details, closures: [:]))
        #expect(FollowedData(ids: ids+["arch"], forecasts: forecasts, details: details, closures: [:]) != FollowedData(ids: ids, forecasts: forecasts, details: details, closures: [:]))
        details["zion"] = detail(9)
        #expect(FollowedData(ids: ids, forecasts: forecasts, details: details, closures: [:]) == FollowedData(ids: ids, forecasts: forecasts, details: details.filter { $0.key != "zion" }, closures: [:]))
    }

    /// The widgets' snapshot scores every followed place as the app does, a widget set to a park
    /// that is not saved included: same score, band, basis and limit, tonight and the week ahead.
    @Test func theSnapshotScoresEveryFollowedPlaceAsTheAppDoes() throws {
        let model = PlanModel(weather: WeatherService(transport: StubHTTP([:]), persist: false), parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                              detail: ForecastDetailService(transport: StubHTTP([:]), persist: false), defaults: isolatedDefaults())
        let saved = ["jotr", "deva", "hale"], reference = Date.now
        let ids = SavedSkySync.followedIDs(saved: saved, home: "chis", tonight: "grba", watch: [], widgets: ["yell"])
        model.forecasts = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, forecast($0+1, at: reference)) })
        model.details = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, detail($0+1, at: reference)) })
        let parks = try saved.map(park), followed = try ids.map(park)
        let written = SavedSkySync.snapshot(parks: parks, followed: followed, forecasts: model.forecasts, details: model.details, closures: [:])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let snapshot = try JSONDecoder().decode(SavedSkySnapshot.self, from: try encoder.encode(written))
        // "Darkest saved place" still weighs only the saved places; the others ride along for widgets set to them.
        #expect(snapshot.parks.map(\.id) == saved && Set(snapshot.forecasts.keys) == Set(ids) && Set((snapshot.details ?? [:]).keys) == Set(ids))
        let planner = snapshot.planner
        for place in followed {
            for offset in 0..<7 {
                let app = model.night(place, on: place.date(model.tonight(place), addingDays: offset))
                let widget = planner.night(place, sky: app.sky, now: model.present)
                #expect(widget.score.value == app.score.value && widget.score.band == app.score.band, "\(place.id) +\(offset)")
                #expect(widget.basis == app.basis && widget.score.limit == app.score.limit, "\(place.id) +\(offset)")
            }
        }
    }
}
