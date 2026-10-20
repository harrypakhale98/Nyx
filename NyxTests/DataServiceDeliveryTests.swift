import Foundation
import Synchronization
import Testing
@testable import Nyx

extension PathHTTP: HTTPTransport {}

/// Answers by path: a body, an HTTP status, or a URL error; records every request. Requests to the
/// forecast host can be held until `release()`, so a test can watch the other host's answer land first.
actor PathHTTP {
    enum Reply: Sendable { case body(String), status(Int), failure(URLError.Code) }
    private(set) var urls: [URL]=[]
    private var replies: [String: Reply]
    private var gated: Bool
    private var held: [CheckedContinuation<Void, Never>]=[]
    private let delay: Duration?
    init(_ replies: [String: Reply], gateForecastHost: Bool = false, delay: Duration? = nil) {
        self.replies=replies; gated=gateForecastHost; self.delay=delay
    }
    func set(_ path: String, _ reply: Reply) { replies[path]=reply }
    func release() { gated=false; for waiter in held { waiter.resume() }; held=[] }
    func get(_ url: URL) async throws -> Data {
        urls.append(url)
        if gated && url.host == WeatherService.host { await withCheckedContinuation { held.append($0) } }
        if let delay { try? await Task.sleep(for: delay) }
        switch replies[url.path] {
        case .body(let text): return Data(text.utf8)
        case .status(let code): throw HTTPStatusError(status: code)
        case .failure(let code): throw URLError(code)
        case nil: return OpenMeteoEcho.body(for: url)
        }
    }
    func count(_ path: String) -> Int { urls.filter { $0.path == path }.count }
}

/// Collects what a service hands on (`observe`), so a test can wait for a delivery.
final class Deliveries<Value: Sendable>: Sendable {
    private let state=Mutex<[Value]>([])
    func add(_ value: Value) { state.withLock { $0.append(value) } }
    var all: [Value] { state.withLock { $0 } }
    /// Waits (briefly) until `condition` holds for what has arrived.
    func wait(timeout: Duration = .seconds(5), until condition: ([Value]) -> Bool) async -> Bool {
        let clock=ContinuousClock(), end=clock.now.advanced(by: timeout)
        while clock.now<end {
            if condition(all) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition(all)
    }
}

/// Requests outlive the screens that asked, and every answer reaches the screens as it lands; the
/// shared NPS key and Open-Meteo's calls are spent once per need, never once per refresh.
struct DataServiceDeliveryTests {
    static let airHost="air-quality-api.open-meteo.com"
    static let monday=Date(timeIntervalSince1970: 1_791_763_200+10*3600)

    // MARK: Catalogue smoke

    /// The world's sparse tiles share one region of a few hundred places, sent in two parts. The
    /// second does not fit this minute's browsing budget: it goes once the minute has passed.
    @Test func aHeldBackPartOfARegionGoesOnceItsMinutePasses() async throws {
        let regions=CatalogForecast.Regions(try TestData.catalog())
        let sparse=try #require(regions.requests.last)
        let parts=ForecastDetailService.airParts(sparse)
        #expect(parts.count == 2 && parts.joined().count>Int(CallBudget.standard.browsing.minute))
        let clock=BudgetClock(Self.monday), http=PathHTTP([:])
        let service=ForecastDetailService(transport: http, persist: false, clock: { clock.now }, pause: { clock.advance($0) })
        let first=await service.catalogAir(sparse, network: true)
        #expect(Set(first.keys) == Set(parts[0].map(\.id)))
        await service.followUpFinished()
        #expect(await http.urls.count == 2)
        let all=await service.catalogAir(sparse, network: false)
        #expect(Set(all.keys) == Set(sparse.joined().map(\.id)))
    }
    /// Each part is due on its own: when the follow-up cannot send it (the minute has not passed), the
    /// next refresh asks for the part still without smoke, and only that part.
    @Test func eachPartIsDueOnItsOwn() async throws {
        let sparse=try #require(CatalogForecast.Regions(try TestData.catalog()).requests.last)
        let parts=ForecastDetailService.airParts(sparse)
        let clock=BudgetClock(Self.monday), http=PathHTTP([:])
        let service=ForecastDetailService(transport: http, persist: false, clock: { clock.now }, pause: { _ in })
        _=await service.catalogAir(sparse, network: true)
        await service.followUpFinished()
        #expect(await http.urls.count == 1)
        clock.advance(61)
        let later=await service.catalogAir(sparse, network: true)
        let urls=await http.urls
        #expect(urls.count == 2)
        #expect(OpenMeteoEcho.list(urls[1], "latitude").count == parts[1].count)
        #expect(Set(later.keys) == Set(sparse.joined().map(\.id)))
        // All fresh now: nothing more.
        clock.advance(61)
        _=await service.catalogAir(sparse, network: true)
        #expect(await http.urls.count == 2)
    }
    /// A caller that finds another region's smoke on its way waits for it, then asks for its own.
    @Test func aWaitingRegionStillAsksForItsOwnSmoke() async throws {
        let small=CatalogForecast.Regions(try TestData.catalog()).requests.filter { $0.joined().count <= 100 }
        #expect(small.count>=2)
        let one=small[0], two=small[1]
        let http=PathHTTP([:], delay: .milliseconds(50))
        let service=ForecastDetailService(transport: http, persist: false)
        async let a=service.catalogAir(one, network: true)
        async let b=service.catalogAir(two, network: true)
        let (first, second)=await (a, b)
        #expect(Set(first.keys) == Set(one.joined().map(\.id)))
        #expect(Set(second.keys) == Set(two.joined().map(\.id)))
        #expect(await http.urls.count == 2)
    }

    // MARK: Forecast detail

    /// Smoke is kept, and handed on, as soon as it lands: never held back by the forecast host's
    /// longer queue of requests.
    @Test func smokeLandsBeforeTheForecastHostFinishes() async throws {
        let parks=Array(TestData.parks.prefix(3))
        let http=PathHTTP([:], gateForecastHost: true)
        let service=ForecastDetailService(transport: http, persist: false)
        let landed=Deliveries<[String: ForecastDetail]>()
        service.observe { landed.add($0) }
        let refresh=Task { await service.details(for: parks, weather: true, smoke: true, force: true) }
        #expect(await landed.wait { $0.contains { $0[parks[0].id]?.air != nil } })
        #expect(landed.all.allSatisfy { $0.values.allSatisfy { $0.layers == nil && $0.models == nil } })
        await http.release()
        let done=await refresh.value
        #expect(done[parks[0].id]?.air != nil && done[parks[0].id]?.layers != nil && done[parks[0].id]?.models != nil)
    }
    /// What a request keeps after its screen went away reaches the planner anyway.
    @MainActor @Test func detailReachesThePlannerWithoutAnotherRefresh() async throws {
        let parks=Array(TestData.parks.prefix(2))
        let http=PathHTTP([:])
        let service=ForecastDetailService(transport: http, persist: false)
        let model=PlanModel(weather: WeatherService(transport: http, persist: false), parkStore: ParkStore(transport: http, persist: false),
                            detail: service, defaults: isolatedDefaults())
        await model.cachesReady()
        // Asked by someone else (a refresh that was then cancelled): the model was never handed the answer.
        _=await service.details(for: parks, weather: false, smoke: true, force: true)
        let clock=ContinuousClock(), end=clock.now.advanced(by: .seconds(5))
        while model.details[parks[0].id]?.air == nil && clock.now<end { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.details[parks[0].id]?.air != nil)
    }
    /// Deliveries land out of order: each part keeps the newer of the two.
    @Test func olderDetailNeverReplacesNewer() {
        let old=HourlySeries(updated: Self.monday, times: [1], values: ["aerosol_optical_depth": [0.1]])
        let new=HourlySeries(updated: Self.monday.addingTimeInterval(60), times: [1], values: ["aerosol_optical_depth": [0.5]])
        let layers=HourlySeries(updated: Self.monday, times: [1], values: ["cloud_cover_mid": [10]])
        let kept=ForecastDetail(layers: layers, air: new)
        #expect(kept.newer(ForecastDetail(air: old)) == kept)
        #expect(ForecastDetail(air: old).newer(ForecastDetail(layers: layers, air: new)) == kept)
    }
    /// If Open-Meteo renamed a context field, the score's part still arrives; if it renamed what the
    /// score needs, the places are not asked again on every refresh (an hour, or ten minutes forced).
    @Test func aRenamedFieldNeitherDropsTheScoreNorRepeatsTheRequest() async throws {
        let summit=try #require(TestData.parks.first { $0.aboveInversion == true })
        let clock=BudgetClock(Self.monday)
        let http=PathHTTP(["/v1/forecast": .body("{\"hourly\":{\"time\":[1790000000],\"cloud_cover_mid\":[10],\"cloud_cover_high\":[5],\"visibility_renamed\":[1]}}"),
                           "/v1/air-quality": .body("{\"hourly\":{\"time\":[1790000000],\"aod_renamed\":[0.2],\"pm2_5\":[3]}}")])
        let service=ForecastDetailService(transport: http, persist: false, clock: { clock.now })
        let first=await service.details(for: [summit], weather: true, smoke: true, force: false)
        #expect(first[summit.id]?.layers?.values["cloud_cover_mid"] == [10])
        #expect(first[summit.id]?.air == nil)
        let sent=await http.urls.count
        // Models (renamed too: no answer holds all three) and smoke are not asked again at once…
        _=await service.details(for: [summit], weather: true, smoke: true, force: false)
        _=await service.details(for: [summit], weather: true, smoke: true, force: true)
        #expect(await http.urls.count == sent)
        // …but ten minutes on a pull asks, and an hour on any refresh.
        clock.advance(601)
        _=await service.details(for: [summit], weather: true, smoke: true, force: true)
        #expect(await http.urls.count == sent+2)
        clock.advance(3600)
        _=await service.details(for: [summit], weather: true, smoke: true, force: false)
        #expect(await http.urls.count == sent+4)
    }

    // MARK: Park updates

    /// Events NPS writes with a missing description, date or id cost only themselves; an answer
    /// that cannot be read is not asked for again on every visit to the page.
    @Test func rangerProgramsReadLeniently() async throws {
        let jotr=try park("jotr")
        let now=Date(timeIntervalSince1970: 1_792_094_400), tomorrow="2026-10-16"
        let clock=BudgetClock(now)
        let events="{\"total\":\"nan\",\"data\":[{\"id\":\"a\",\"title\":\"Astronomy night\",\"datestart\":\"\(tomorrow)\",\"description\":null},"
            + "{\"id\":null,\"title\":\"Star party\",\"datestart\":\"\(tomorrow)\"},{\"id\":\"c\",\"title\":\"Telescope talk\",\"datestart\":null,\"dates\":[\"\(tomorrow)\"],\"tags\":null}]}"
        let http=PathHTTP(["/api/v1/events": .body(events)])
        let store=ParkStore(transport: http, persist: false, clock: { clock.now })
        let programs=await store.programs(for: jotr, key: "k", network: true, force: true)
        #expect(Set(programs?.programs.map(\.title) ?? []) == ["Astronomy night", "Telescope talk"])
        #expect(programs?.programs.first?.description == "")

        await http.set("/api/v1/events", .body("not json"))
        let broken=ParkStore(transport: http, persist: false, clock: { clock.now })
        #expect(await broken.programs(for: jotr, key: "k", network: true, force: true) == nil)
        #expect(await broken.programs(for: jotr, key: "k", network: true, force: true) == nil)
        #expect(await http.count("/api/v1/events") == 2)
        clock.advance(3601)
        _=await broken.programs(for: jotr, key: "k", network: true, force: false)
        #expect(await http.count("/api/v1/events") == 3)
    }
    /// NPS's event count is a string: anything that is not a whole number reads as one page.
    @Test func eventPagesNeverTrap() {
        #expect(ParkStore.eventPages(total: nil) == 0)
        #expect(ParkStore.eventPages(total: "nan") == 0)
        #expect(ParkStore.eventPages(total: "inf") == 0)
        #expect(ParkStore.eventPages(total: "-5") == 0)
        #expect(ParkStore.eventPages(total: "1e300") == 0)
        #expect(ParkStore.eventPages(total: "50") == 1)
        #expect(ParkStore.eventPages(total: "51") == 2)
        #expect(ParkStore.eventPages(total: "9223372036854775807") == 10)
    }
    /// Only the alerts request's own refusal says park alerts are busy, and it keeps saying so until alerts succeed.
    @Test func onlyAnAlertsRefusalIsBusy() async throws {
        let jotr=try park("jotr")
        let clock=BudgetClock(Self.monday)
        let http=PathHTTP(["/api/v1/alerts": .body("{\"data\":[]}"), "/api/v1/events": .status(403), "/api/v1/campgrounds": .status(404)])
        let store=ParkStore(transport: http, persist: false, clock: { clock.now })
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: true).busy == false)
        _=await store.programs(for: jotr, key: "k", network: true, force: true)
        _=await store.campgrounds(for: [jotr], key: "k", network: true, force: true)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: false).busy == false)
        // The alerts request itself refused (a refused key): busy, on every later answer too.
        clock.advance(601)
        await http.set("/api/v1/alerts", .status(403))
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: true).busy)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: false).busy)
        // A Wi-Fi sign-in page is not a refusal, and does not end one either.
        await http.set("/api/v1/alerts", .status(302))
        clock.advance(601)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: true).busy)
        await http.set("/api/v1/alerts", .body("{\"data\":[]}"))
        clock.advance(601)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: true).busy == false)
    }
    /// A request that fails without a backoff (a timeout) is not sent again by each caller that waited for it.
    @Test func waitersDoNotRepeatAFailedRequest() async throws {
        let jotr=try park("jotr")
        let http=PathHTTP(["/api/v1/alerts": .failure(.timedOut), "/api/v1/events": .failure(.timedOut), "/api/v1/campgrounds": .failure(.timedOut)], delay: .milliseconds(100))
        let store=ParkStore(transport: http, persist: false)
        async let a=store.alerts(for: [jotr], key: "k", network: true, force: true)
        async let b=store.alerts(for: [jotr], key: "k", network: true, force: true)
        async let c=store.programs(for: jotr, key: "k", network: true, force: true)
        async let d=store.programs(for: jotr, key: "k", network: true, force: true)
        async let e=store.campgrounds(for: [jotr], key: "k", network: true, force: true)
        async let f=store.campgrounds(for: [jotr], key: "k", network: true, force: true)
        _=await (a, b, c, d, e, f)
        #expect(await http.count("/api/v1/alerts") == 1)
        #expect(await http.count("/api/v1/events") == 1)
        #expect(await http.count("/api/v1/campgrounds") == 1)
    }
    /// Programs show on a park's page even when the alerts could not be fetched, and nothing claims
    /// the alerts were checked; programs fetched for a page that has closed still arrive.
    @MainActor @Test func programsShowWithoutAlerts() async throws {
        let jotr=try park("jotr")
        let now=Date(timeIntervalSince1970: 1_792_094_400)
        let http=PathHTTP(["/api/v1/alerts": .body("unreadable"),
                           "/api/v1/events": .body("{\"total\":\"1\",\"data\":[{\"id\":\"a\",\"title\":\"Astronomy night\",\"datestart\":\"2099-10-16\",\"description\":\"\"}]}")])
        let store=ParkStore(transport: http, persist: false, clock: { now })
        let model=PlanModel(weather: WeatherService(transport: http, persist: false), parkStore: store,
                            detail: ForecastDetailService(transport: http, persist: false), defaults: isolatedDefaults())
        await model.cachesReady()
        #expect(await store.alerts(for: model.parks, key: "k", network: true, force: true).cache == nil)
        _=await store.programs(for: jotr, key: "k", network: true, force: true)
        let clock=ContinuousClock(), end=clock.now.advanced(by: .seconds(5))
        while model.rangerPrograms(jotr) == nil && clock.now<end { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.rangerPrograms(jotr)?.programs.map(\.title) == ["Astronomy night"])
        #expect(model.rangerPrograms(jotr)?.updated != nil)
        #expect(model.enrichments[jotr.id] == nil)
    }
    /// A whole refresh's forecasts are one change, not one per park.
    @MainActor @Test func aRefreshIsOneChange() throws {
        let model=PlanModel(weather: WeatherService(transport: PathHTTP([:]), persist: false), parkStore: ParkStore(transport: PathHTTP([:]), persist: false),
                            detail: ForecastDetailService(transport: PathHTTP([:]), persist: false), defaults: isolatedDefaults())
        let before=model.dataRevision
        let forecast=Forecast(updated: .now, times: [1790000000], clouds: [10])
        model.takeForecasts(Dictionary(uniqueKeysWithValues: model.parks.map { ($0.id, forecast) }))
        #expect(model.dataRevision == before+1)
        model.takeForecasts(Dictionary(uniqueKeysWithValues: model.parks.map { ($0.id, forecast) }))
        #expect(model.dataRevision == before+1)
    }

    // MARK: Ordered files

    /// A snapshot taken earlier never overwrites one taken later, whichever is written last.
    @Test func olderSnapshotsNeverOverwriteNewer() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-ordered-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let writer=OrderedWriter(file: file)
        let first=writer.ticket(), second=writer.ticket()
        writer.write(["second"], ticket: second)
        writer.write(["first"], ticket: first)
        #expect(try JSONDecoder().decode([String].self, from: Data(contentsOf: file)) == ["second"])
    }

    // MARK: Alert meaning

    /// A reopening is not a closure, unless something is still shut.
    @Test func reopeningsAreNotClosures() {
        func kind(_ title: String, _ category: String) -> AlertKind { ParkAlert(id: "x", title: title, description: "", category: category).kind }
        #expect(kind("Road Reopened After Closure", "Information") == .notice)
        #expect(kind("Road Reopened After Closure", "Park Closure") == .notice)
        #expect(kind("Scenic Drive Reopens Following Winter Closure", "Information") == .notice)
        #expect(kind("Trail Reopened After Being Closed for Repairs", "Information") == .notice)
        #expect(kind("Lower Road Reopens; Upper Road Remains Closed", "Park Closure") == .closure)
        #expect(kind("Road Reopened, Trail Closed", "Information") == .closure)
        #expect(kind("Road Closure", "Information") == .closure)
    }
}
