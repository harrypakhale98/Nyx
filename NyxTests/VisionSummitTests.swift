import Foundation
import Testing
@testable import Nyx

/// Haleakalā on Vision Pro: the summit's mid and high cloud (`SummitLayerService`, shared in
/// CloudForecastClient.swift) so the headset scores the park above the inversion as the iPhone does.
struct VisionSummitTests {
    let parks: [Park]
    init() throws { parks = try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    func evening(_ park: Park, _ iso: String) throws -> Date {
        let day = try #require(TripDay(iso: iso))
        return day.evening(in: park)
    }
    /// Hourly times from three hours before `start`, for `count` hours.
    func hours(from start: Date, count: Int = 40) -> [Double] {
        let first = floor(start.timeIntervalSince1970/3600)*3600-3*3600
        return (0..<count).map { first+Double($0)*3600 }
    }
    /// Low cloud thick below the summit, thin and changing cloud above it.
    func low(_ i: Int) -> Double { 90 }
    func mid(_ i: Int) -> Double { Double(5+(i%4)*5) }
    func high(_ i: Int) -> Double { Double(10+(i%3)*10) }
    func column(_ times: [Double], _ value: (Int) -> Double) -> [Double?] { times.indices.map { value($0) } }
    /// Open-Meteo's answer for one coordinate.
    func body(_ times: [Double]) -> String {
        func list(_ values: [Double]) -> String { "[" + values.map { String($0) }.joined(separator: ",") + "]" }
        return "{\"hourly\":{\"time\":\(list(times)),\"cloud_cover_mid\":\(list(times.indices.map(mid))),\"cloud_cover_high\":\(list(times.indices.map(high)))}}"
    }

    /// All 63 parks in, one request out: Haleakalā's viewing spot, two cloud layers, seven days
    /// plus yesterday, to the forecast host only. Not asked again for twelve hours.
    @Test func oneSmallRequestForTheSummitOnly() async throws {
        let hale = try park("hale")
        #expect(parks.filter { $0.aboveInversion == true }.map(\.id) == ["hale"])
        let clock = SummitClock()
        let http = StubHTTP(["/v1/forecast": body(hours(from: clock.now))])
        let service = SummitLayerService(transport: http, persist: false, clock: { clock.now })
        let layers = await service.layers(for: parks, network: true)
        #expect(Array(layers.keys) == ["hale"])
        #expect(layers["hale"]?.values.keys.sorted() == ["cloud_cover_high", "cloud_cover_mid"])
        var urls = await http.urls
        #expect(urls.count == 1)
        let url = try #require(urls.first)
        let point = hale.forecastPoint
        #expect(url.absoluteString == "https://api.open-meteo.com/v1/forecast?latitude=\(point.latitude)&longitude=\(point.longitude)&hourly=cloud_cover_mid,cloud_cover_high&forecast_days=7&past_days=1&timeformat=unixtime&timezone=GMT")
        #expect(url.host == "api.open-meteo.com" && SafeHTTP.preferences[url.host ?? ""] == CloudForecastSwitch.key)
        #expect(SummitLayerService.url(for: [hale]) == url)
        // Nothing else rides along: no low cloud, models, weather or air.
        for word in ["cloud_cover_low", "models", "temperature", "aerosol", "pm2_5", "air-quality"] { #expect(!url.absoluteString.contains(word)) }
        // Fresh for twelve hours however often the window asks; then asked once more.
        _ = await service.layers(for: parks, network: true)
        clock.now = clock.now.addingTimeInterval(11*3600)
        _ = await service.layers(for: parks, network: true)
        urls = await http.urls
        #expect(urls.count == 1)
        clock.now = clock.now.addingTimeInterval(3600)
        _ = await service.layers(for: parks, network: true)
        urls = await http.urls
        #expect(urls.count == 2)
    }
    /// Parks below the inversion never cause a request; with the switch off (`network` false)
    /// nothing is asked; a failure keeps nothing invented; a refusal on the forecast host holds the
    /// summit request back too.
    @Test func quietUnlessNeeded() async throws {
        let http = StubHTTP(["/v1/forecast": body(hours(from: .now))])
        let service = SummitLayerService(transport: http, persist: false)
        #expect(await service.layers(for: parks.filter { $0.id != "hale" }, network: true).isEmpty)
        #expect(await service.layers(for: parks, network: false).isEmpty)
        #expect(await http.urls.isEmpty)
        await http.setFailure()
        #expect(await service.layers(for: parks, network: true).isEmpty)
        #expect(await http.urls.count == 1)
        // The cloud forecast is refused (429): the shared backoff keeps the summit request home.
        let backoff = HostBackoff(file: nil), refused = StubHTTP([:])
        await refused.setStatus(429)
        _ = await WeatherService(transport: refused, persist: false, backoff: backoff).forecasts(for: parks, network: true, force: true)
        let summit = StubHTTP(["/v1/forecast": body(hours(from: .now))])
        #expect(await SummitLayerService(transport: summit, persist: false, backoff: backoff).layers(for: parks, network: true).isEmpty)
        #expect(await summit.urls.isEmpty)
    }
    /// The layers Vision Pro fetches score Haleakalā exactly as the iPhone's full forecast detail
    /// does (same mid and high cloud, other layers and models ignored for the summit), and differently
    /// from total cloud, which counts the low cloud below the summit.
    @Test func visionScoresTheSummitAsTheIPhone() async throws {
        let hale = try park("hale")
        let night = try evening(hale, "2026-12-09")
        let sky = AstronomyEngine().conditions(for: hale, on: night)
        let window = sky.cloudWindow
        let issued = window.start.addingTimeInterval(-6*3600)
        let times = hours(from: window.start)
        let total = Forecast(updated: issued, times: times, clouds: times.map { _ in 92 })
        // Vision Pro: the service's own decoding of Open-Meteo's answer.
        let clock = SummitClock()
        clock.now = issued
        let http = StubHTTP(["/v1/forecast": body(times)])
        let layers = await SummitLayerService(transport: http, persist: false, clock: { clock.now }).layers(for: [hale], network: true)
        let fetched = try #require(layers["hale"])
        let vision = NightPlanner.night(park: hale, sky: sky, forecast: total, detail: ForecastDetail(layers: fetched), now: issued)
        // The iPhone: forecast detail with every layer, the weather beside it and three models.
        let all: [String: [Double?]] = ["cloud_cover_low": column(times, low), "cloud_cover_mid": column(times, mid), "cloud_cover_high": column(times, high),
                                        "temperature_2m": column(times) { _ in 2 }, "dew_point_2m": column(times) { _ in -4 },
                                        "wind_gusts_10m": column(times) { _ in 30 }, "visibility": column(times) { _ in 40_000 }]
        var spread: [String: [Double?]] = [:]
        for (index, key) in ForecastDetail.modelKeys.enumerated() { spread[key] = column(times) { _ in Double(70+index*10) } }
        let models = HourlySeries(updated: issued, times: times, values: spread)
        let iPhone = NightPlanner.night(park: hale, sky: sky, forecast: total, detail: ForecastDetail(models: models, layers: HourlySeries(updated: issued, times: times, values: all)), now: issued)
        #expect(vision.upperCloudOnly && iPhone.upperCloudOnly)
        #expect(vision.score.value == iPhone.score.value && vision.basis == iPhone.basis && vision.score.limit == iPhone.score.limit)
        #expect(vision.cloudCover == iPhone.cloudCover && vision.forecastUpdated == iPhone.forecastUpdated)
        let before = NightPlanner.night(park: hale, sky: sky, forecast: total, detail: nil, now: issued)
        #expect(!before.upperCloudOnly && before.cloudCover == 92 && before.score.value <= vision.score.value)
        let upper = try #require(vision.cloudCover)
        #expect(upper < 50)
        // Layers far older than the forecast are set aside on both, never mixed with fresh total cloud.
        let newer = Forecast(updated: issued.addingTimeInterval(2*86400), times: times, clouds: total.clouds)
        let stale = NightPlanner.night(park: hale, sky: sky, forecast: newer, detail: ForecastDetail(layers: fetched), now: issued)
        #expect(!stale.upperCloudOnly && stale.cloudCover == 92)
    }
    /// The immersive sky over the summit draws the layers as the score combines them.
    @Test func upperCloudCombinesLikeTheScore() throws {
        let times = hours(from: Date(timeIntervalSince1970: 1_790_000_000), count: 3)
        let layers = HourlySeries(updated: .now, times: times, values: ["cloud_cover_mid": [10, nil, 0], "cloud_cover_high": [10, 50, 100]])
        let upper = try #require(layers.upperCloud)
        #expect(upper.times == times && upper.updated == layers.updated)
        #expect(abs((upper.clouds[0] ?? 0)-19) < 1e-9 && upper.clouds[1] == nil && upper.clouds[2] == 100)
        #expect(HourlySeries(updated: .now, times: times, values: ["cloud_cover_mid": [10, 10, 10]]).upperCloud == nil)
    }
}

/// A settable clock for freshness tests.
private final class SummitClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
}
