import Foundation
import Testing
@testable import Nyx

/// A place reaches Apple Watch whole or is named as left out: never clouds without the smoke or
/// summit layers the iPhone's score counts. What the wrist says about a score's clouds matches the
/// clouds that score rests on, and a face says when the iPhone runs a Nyx with other data.
struct WatchWholePlaceTests {
    /// 2026-10-07 12:00 UTC.
    let now = Date(timeIntervalSince1970: 1_791_158_400 + 30*3600)
    private func hours(_ count: Int) -> [Double] {
        let first = (floor(now.timeIntervalSince1970/3600)-24)*3600
        return (0..<count).map { first+Double($0)*3600 }
    }
    /// Sixteen days of hourly clouds, different at every place.
    func forecast(_ seed: Int, updated: Date? = nil) -> Forecast {
        let times = hours(17*24)
        return Forecast(updated: updated ?? now.addingTimeInterval(-3600), times: times, clouds: times.indices.map { Double(($0*(seed%5+2)+seed*7) % 40) })
    }
    /// A week of thick smoke (it holds every score down) and, for a summit, its cloud layers.
    func detail(_ seed: Int, layers: Bool = true, updated: Date? = nil) -> ForecastDetail {
        let times = hours(8*24), issued = updated ?? now.addingTimeInterval(-3600)
        func values(_ step: Int, _ scale: Double = 1) -> [Double?] { times.indices.map { Double(($0*step+seed*11) % 101)*scale } }
        let air = HourlySeries(updated: issued, times: times, values: ["aerosol_optical_depth": times.indices.map { 0.6+Double(($0+seed) % 5)*0.1 }])
        let upper = HourlySeries(updated: issued, times: times, values: ["cloud_cover_low": values(3), "cloud_cover_mid": values(7, 0.3), "cloud_cover_high": values(11, 0.3)])
        return ForecastDetail(layers: layers ? upper : nil, air: air)
    }
    private func nights(_ park: Park, count: Int = 5) -> [SkyConditions] {
        let engine = AstronomyEngine(), tonight = park.currentNight(at: now)
        return (0..<count).map { engine.conditions(for: park, on: park.date(tonight, addingDays: $0)) }
    }

    /// Every park saved, each with clouds and smoke, far past the budget: each followed place either
    /// scores on the wrist exactly as on the iPhone (smoke included) or is named as left out and says
    /// so; the places that travel are the first ones, each whole.
    @Test func everyPlaceHasItsSmokeOnTheWristOrIsNamedAsLeftOut() throws {
        let ids = TestData.parks.map(\.id)
        let forecasts = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, forecast($0+1)) })
        let details = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, detail($0+1)) })
        let sent = WatchContext.make(savedParkIDs: ids, homeParkID: "jotr", nightVision: false, forecasts: forecasts, details: details,
                                     aboveInversion: ["hale"], now: now)
        #expect((sent.data?.count ?? .max) <= WatchContext.byteBudget)
        let context = try #require(sent.data.flatMap { WatchContext(data: $0) })
        let whole = ids.filter { context.forecasts[$0] != nil }
        // Not trivial: some places travel, some are left out.
        #expect(!whole.isEmpty && whole.count < ids.count && whole == Array(ids.prefix(whole.count)))
        var smoky = 0
        for id in ids {
            let place = try park(id)
            guard !context.droppedParkIDs.contains(id) else {
                #expect(context.forecasts[id] == nil && context.details[id] == nil, "\(id)")
                #expect(CloudSource.of(context: context, park: place, now: now) == .dropped, "\(id)")
                continue
            }
            #expect(context.details[id]?.air != nil, "\(id) travels without its smoke")
            for sky in nights(place) {
                let phone = NightPlanner.night(park: place, sky: sky, forecast: forecasts[id], detail: details[id], now: now)
                let wrist = NightPlanner.night(park: place, sky: sky, forecast: context.cloudForecasts[id], detail: context.forecastDetails[id], now: now,
                                               climate: context.climate)
                #expect(wrist.score.value == phone.score.value && wrist.score.band == phone.score.band, "\(id) \(sky.evening)")
                #expect(wrist.aerosol == phone.aerosol && wrist.bandWithBasis == phone.bandWithBasis, "\(id) \(sky.evening)")
                if phone.aerosol != nil, phone.score.limit != nil { smoky += 1 }
            }
        }
        #expect(smoky > 0)
        #expect(context.droppedParkIDs == ids.filter { context.forecasts[$0] == nil })
    }

    /// Smoke or summit layers with no cloud forecast still travel: the iPhone counts them over the
    /// usual clouds, and a summit's layers are its clouds.
    @Test func smokeAndLayersTravelWithoutClouds() throws {
        let sent = WatchContext.make(savedParkIDs: ["jotr", "hale"], homeParkID: "jotr", nightVision: false, forecasts: [:],
                                     details: ["jotr": detail(1), "hale": detail(2)], aboveInversion: ["hale"], now: now)
        let context = try #require(sent.data.flatMap { WatchContext(data: $0) })
        for id in ["jotr", "hale"] {
            let place = try park(id)
            for sky in nights(place, count: 3) {
                let phone = NightPlanner.night(park: place, sky: sky, forecast: nil, detail: id == "jotr" ? detail(1) : detail(2), now: now)
                let wrist = NightPlanner.night(park: place, sky: sky, forecast: nil, detail: context.forecastDetails[id], now: now, climate: context.climate)
                #expect(wrist.score.value == phone.score.value && wrist.aerosol == phone.aerosol && wrist.upperCloudOnly == phone.upperCloudOnly, "\(id)")
            }
        }
        #expect(context.droppedParkIDs.isEmpty)
    }

    /// Haleakalā scores from its mid and high layers alone. With a total-cloud forecast but no layers
    /// (none fetched yet, or an older iPhone that left them out for room) its score says "Cloud
    /// forecast unavailable", and the source line agrees instead of naming the total's time.
    @Test func theSummitsSourceLineFollowsItsLayers() throws {
        let hale = try park("hale"), total = forecast(3)
        let bare = WatchContext(sent: now, savedParkIDs: ["hale"], homeParkID: "hale", nightVision: false,
                                forecasts: ["hale": try #require(CompactForecast(total, from: now.addingTimeInterval(-86400), to: now.addingTimeInterval(11*86400)))])
        let tonight = try #require(nights(hale, count: 1).first)
        let night = NightPlanner.night(park: hale, sky: tonight, forecast: bare.cloudForecasts["hale"], detail: bare.forecastDetails["hale"], now: now, climate: bare.climate)
        #expect(night.basis == .usual && night.basisLabel == "Cloud forecast unavailable")
        let source = CloudSource.of(context: bare, park: hale, now: now)
        #expect(source == .missing(followed: true) && source.isStale)
        #expect(source.line(for: hale)?.hasPrefix("Clouds from") == false)
        // With its layers (issued apart from the total), the line names the layers' time and the score uses them.
        let layered = now.addingTimeInterval(-5*3600)
        let sent = WatchContext.make(savedParkIDs: ["hale"], homeParkID: "hale", nightVision: false, forecasts: ["hale": total],
                                     details: ["hale": detail(3, updated: layered)], aboveInversion: ["hale"], now: now)
        let context = try #require(sent.data.flatMap { WatchContext(data: $0) })
        #expect(CloudSource.of(context: context, park: hale, now: now) == .fresh(layered))
        let wrist = NightPlanner.night(park: hale, sky: tonight, forecast: context.cloudForecasts["hale"], detail: context.forecastDetails["hale"], now: now, climate: context.climate)
        #expect(wrist.upperCloudOnly && wrist.forecastUpdated == layered)
        // A park below the inversion keeps its clouds' own time.
        #expect(CloudSource.issued(try park("jotr"), forecast: total.updated, layers: layered) == total.updated)
    }

    /// A face says when the iPhone's Nyx has other data: a short line where there is room, and the
    /// whole sentence in every face's spoken label, beside an old forecast's.
    @Test func facesSayWhenVersionsDiffer() throws {
        let other = WatchContext(sent: now, savedParkIDs: [], homeParkID: "jotr", nightVision: false, forecasts: [:], dataVersion: "0")
        let same = WatchContext(sent: now, savedParkIDs: [], homeParkID: "jotr", nightVision: false, forecasts: [:])
        #expect(WatchContext.bundledData != nil && other.dataDiffers && !same.dataDiffers)
        let notes = FaceNote.notes(cloudsOld: true, dataDiffers: other.dataDiffers)
        #expect(notes == [.versionsDiffer, .oldForecast])
        #expect(notes.map(\.spoken) == [try #require(other.dataNote), "No recent forecast. Open Nyx on iPhone to refresh."])
        #expect(notes.map(\.short) == ["Nyx versions differ", "No recent forecast"])
        #expect(FaceNote.notes(cloudsOld: false, dataDiffers: same.dataDiffers).isEmpty)
    }
}
