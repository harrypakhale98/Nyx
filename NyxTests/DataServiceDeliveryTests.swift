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
    /// nil answers as Open-Meteo would again (`OpenMeteoEcho`).
    func set(_ path: String, _ reply: Reply?) { replies[path]=reply }
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

/// Answers NPS's events by page number, and counts the requests.
final class PagedEvents: HTTPTransport {
    private let pages: Mutex<[Int: PathHTTP.Reply]>
    private let count=Mutex(0)
    init(_ pages: [Int: PathHTTP.Reply]) { self.pages=Mutex(pages) }
    func set(_ number: Int, _ reply: PathHTTP.Reply) { pages.withLock { $0[number]=reply } }
    var asked: Int { count.withLock { $0 } }
    func get(_ url: URL) async throws -> Data {
        count.withLock { $0+=1 }
        let number=URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pageNumber" }?.value.flatMap { Int($0) } ?? 1
        switch pages.withLock({ $0[number] }) {
        case .body(let text): return Data(text.utf8)
        case .status(let code): throw HTTPStatusError(status: code)
        case .failure(let code): throw URLError(code)
        case nil: throw URLError(.badServerResponse)
        }
    }
}

/// Holds the first request until `release()` and then refuses it with `first`; later requests get
/// empty alerts at once. Records the NPS key each request carried.
actor KeyedGateHTTP: HTTPTransport {
    private(set) var keys: [String]=[]
    private var held: CheckedContinuation<Void, Never>?
    private var gate=true
    private let first: Int
    init(first status: Int) { first=status }
    func get(_ url: URL) async throws -> Data { try await get(url, headers: [:], constrained: true) }
    func get(_ url: URL, headers: [String: String], constrained: Bool) async throws -> Data {
        keys.append(headers["X-Api-Key"] ?? "")
        if gate {
            gate=false
            await withCheckedContinuation { held=$0 }
            throw HTTPStatusError(status: first)
        }
        return Data("{\"data\":[]}".utf8)
    }
    func release() { held?.resume(); held=nil }
}

/// Holds the first request until `release()` and then fails it as a cancelled request does
/// (`URLError.cancelled`); later requests get empty alerts at once. Counts the requests.
actor CancelledFirstHTTP: HTTPTransport {
    private(set) var asked=0
    private var held: CheckedContinuation<Void, Never>?
    func get(_ url: URL) async throws -> Data {
        asked+=1
        if asked == 1 {
            await withCheckedContinuation { held=$0 }
            throw URLError(.cancelled)
        }
        return Data("{\"data\":[]}".utf8)
    }
    func release() { held?.resume(); held=nil }
}

/// Holds the alerts request made with the key "old" until `release()`, and answers it as a refusal
/// of that key; answers any other key at once. Records the key each programs request carried.
actor KeySwapParks: ParkProviding {
    static let stale=ParkAlertsCache(updated: Date(timeIntervalSince1970: 1_000_000), alerts: [:])
    static let fresh=ParkAlertsCache(updated: Date(timeIntervalSince1970: 2_000_000), alerts: [:])
    private(set) var alertKeys: [String]=[]
    private(set) var programKeys: [String]=[]
    private var held: CheckedContinuation<Void, Never>?
    func alerts(for parks: [Park], key: String, network: Bool, force: Bool, pages: Int) async -> AlertsUpdate {
        alertKeys.append(key)
        guard key == "old" else { return AlertsUpdate(cache: Self.fresh, busy: false) }
        await withCheckedContinuation { held=$0 }
        return AlertsUpdate(cache: Self.stale, busy: true, keyRefused: true)
    }
    func programs(for park: Park, key: String, network: Bool, force: Bool) async -> ProgramsCache? {
        programKeys.append(key)
        return ProgramsCache(updated: Self.fresh.updated, programs: [])
    }
    func hydrate(_ parks: [Park]) async -> AlertsUpdate { AlertsUpdate(cache: nil, busy: false) }
    func seed(_ cached: ParkAlertsCache?) async {}
    func release() { held?.resume(); held=nil }
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

    /// Smoke switched off lets go of parts held back for the next minute, so switched on again
    /// nothing waits for a follow-up that will never send.
    @Test func smokeSwitchedOffLetsGoOfHeldParts() async throws {
        let sparse=try #require(CatalogForecast.Regions(try TestData.catalog()).requests.last)
        let clock=BudgetClock(Self.monday), http=PathHTTP([:])
        let service=ForecastDetailService(transport: http, persist: false, clock: { clock.now }, pause: { _ in try? await Task.sleep(for: .seconds(3600)) })
        _=await service.catalogAir(sparse, network: true)
        #expect(await http.urls.count == 1)
        await service.forgetAir()
        let done=Deliveries<Bool>()
        Task { await service.followUpFinished(); done.add(true) }
        #expect(await done.wait { !$0.isEmpty })
    }

    // MARK: Forecast detail

    /// A busy or struggling service (429, 5xx) is waited out by the host's backoff alone: once it
    /// has passed, the places are asked again, not an hour later. A refusal of the request itself waits.
    @Test func aStrugglingServiceIsNotAnUnusableAnswer() async throws {
        let summit=try #require(TestData.parks.first { $0.aboveInversion == true })
        let clock=BudgetClock(Self.monday)
        let http=PathHTTP(["/v1/air-quality": .status(503)])
        let service=ForecastDetailService(transport: http, persist: false, backoff: HostBackoff(file: nil, random: { 0 }), clock: { clock.now })
        _=await service.details(for: [summit], weather: false, smoke: true, force: false)
        #expect(await http.count("/v1/air-quality") == 1)
        await http.set("/v1/air-quality", nil)
        clock.advance(901)
        let later=await service.details(for: [summit], weather: false, smoke: true, force: false)
        #expect(await http.count("/v1/air-quality") == 2)
        #expect(later[summit.id]?.air != nil)

        let refused=PathHTTP(["/v1/air-quality": .status(400)])
        let other=ForecastDetailService(transport: refused, persist: false, backoff: HostBackoff(file: nil, random: { 0 }), clock: { clock.now })
        _=await other.details(for: [summit], weather: false, smoke: true, force: false)
        clock.advance(901)
        _=await other.details(for: [summit], weather: false, smoke: true, force: false)
        #expect(await refused.count("/v1/air-quality") == 1)
    }

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
    /// Events NPS writes in a way Nyx cannot read at all are not "no programs": nothing is kept,
    /// and the page is not asked for again at once. A null among an event's dates costs only itself.
    @Test func unreadableEventsAreNotNoPrograms() async throws {
        let jotr=try park("jotr")
        let now=Date(timeIntervalSince1970: 1_792_094_400)
        let http=PathHTTP(["/api/v1/events": .body("{\"total\":\"2\",\"data\":[{\"eventId\":\"a\",\"name\":\"Astronomy night\"},{\"eventId\":\"b\",\"name\":\"Star party\"}]}")])
        let store=ParkStore(transport: http, persist: false, clock: { now })
        #expect(await store.programs(for: jotr, key: "k", network: true, force: true) == nil)
        #expect(await store.programs(for: jotr, key: "k", network: true, force: true) == nil)
        #expect(await http.count("/api/v1/events") == 1)

        await http.set("/api/v1/events", .body("{\"total\":\"1\",\"data\":[{\"id\":\"a\",\"title\":\"Evening program\",\"dates\":[null,\"2099-10-16\"],"
            + "\"tags\":[null,\"Astronomy\"],\"times\":[null,{\"timestart\":\"8:00 PM\",\"timeend\":\"9:00 PM\"}]}]}"))
        let fresh=ParkStore(transport: http, persist: false, clock: { now })
        #expect(await fresh.programs(for: jotr, key: "k", network: true, force: true)?.programs.map(\.date) == ["2099-10-16"])
    }
    /// A Wi-Fi sign-in page, or a later page failing for now, blocks nothing: the next visit asks
    /// again. A later page NPS answers with nothing usable keeps the pages before it.
    @Test func programsAreAskedAgainAfterPassingFailures() async throws {
        let jotr=try park("jotr")
        let now=Date(timeIntervalSince1970: 1_792_094_400)
        let portal=PathHTTP(["/api/v1/events": .status(302)])
        let store=ParkStore(transport: portal, persist: false, clock: { now })
        _=await store.programs(for: jotr, key: "k", network: true, force: false)
        _=await store.programs(for: jotr, key: "k", network: true, force: false)
        #expect(await portal.count("/api/v1/events") == 2)

        let first="{\"total\":\"60\",\"data\":[{\"id\":\"a\",\"title\":\"Astronomy night\",\"datestart\":\"2099-10-16\"}]}"
        let paged=PagedEvents([1: .body(first), 2: .status(302)])
        let later=ParkStore(transport: paged, persist: false, clock: { now })
        #expect(await later.programs(for: jotr, key: "k", network: true, force: false) == nil)
        #expect(paged.asked == 2)
        paged.set(2, .body("not json"))
        #expect(await later.programs(for: jotr, key: "k", network: true, force: false)?.programs.map(\.title) == ["Astronomy night"])
        #expect(paged.asked == 4)
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
        // A Wi-Fi sign-in page (once the refused key's day has passed) is not a refusal, and does not end one either.
        await http.set("/api/v1/alerts", .status(302))
        clock.advance(NPSKeyPause.length)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: true).busy)
        await http.set("/api/v1/alerts", .body("{\"data\":[]}"))
        clock.advance(601)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: true).busy == false)
    }
    /// The shared key's quota spent holds the host for an hour or more; a key of the person's own
    /// (saved or removed) has its own quota, so the hold is lifted and alerts are asked for at once,
    /// even within ten minutes of the last success.
    @Test func aNewKeyLiftsTheHold() async throws {
        let jotr=try park("jotr")
        let clock=BudgetClock(Self.monday)
        let http=PathHTTP(["/api/v1/alerts": .body("{\"data\":[]}")])
        let store=ParkStore(transport: http, persist: false, clock: { clock.now })
        #expect(await store.alerts(for: [jotr], key: "shared", network: true, force: true).busy == false)
        clock.advance(601)
        await http.set("/api/v1/alerts", .status(429))
        #expect(await store.alerts(for: [jotr], key: "shared", network: true, force: true).busy)
        await http.set("/api/v1/alerts", .body("{\"data\":[]}"))
        clock.advance(601)
        #expect(await store.alerts(for: [jotr], key: "shared", network: true, force: true).busy)
        #expect(await http.urls.count == 2)
        await store.keyChanged(to: "mine")
        let mine=await store.alerts(for: [jotr], key: "mine", network: true, force: true)
        #expect(!mine.busy && !mine.keyRefused && mine.cache?.updated == clock.now)
        #expect(await http.urls.count == 3)
        // Within ten minutes of that success: a forced refresh waits, a key removed does not.
        clock.advance(60)
        _=await store.alerts(for: [jotr], key: "mine", network: true, force: true)
        #expect(await http.urls.count == 3)
        await store.keyChanged(to: "shared")
        _=await store.alerts(for: [jotr], key: "shared", network: true, force: false)
        #expect(await http.urls.count == 4)
    }
    /// A key saved while a request with the old one is out: a caller with the new key that is
    /// cancelled returns at once and sends nothing; a caller still holding the old key sends
    /// nothing; exactly one request follows, with the new key; and the old key's 429 sets no wait.
    @Test(.timeLimit(.minutes(1))) func aKeyChangeMidRequestSendsTheNewKeyOnce() async throws {
        let jotr=try park("jotr")
        let http=KeyedGateHTTP(first: 429)
        let store=ParkStore(transport: http, persist: false)
        let old=Task { await store.alerts(for: [jotr], key: "old", network: true, force: true) }
        while await http.keys.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        await store.keyChanged(to: "new")
        let live=Task { await store.alerts(for: [jotr], key: "new", network: true, force: true) }
        let cancelled=Task { await store.alerts(for: [jotr], key: "new", network: true, force: true) }
        cancelled.cancel()
        _=await cancelled.value
        #expect(await http.keys == ["old"])
        let late=Task { await store.alerts(for: [jotr], key: "old", network: true, force: true) }
        await http.release()
        let fresh=await live.value
        _=await (old.value, late.value)
        _=await store.alerts(for: [jotr], key: "old", network: true, force: true)
        #expect(await http.keys == ["old", "new"])
        #expect(!fresh.busy && fresh.cache?.alerts["jotr"] == [])
    }
    /// A key NPS does not accept (401, 403) is told apart from a busy service, until alerts succeed.
    @Test func aRefusedKeyIsToldApart() async throws {
        let jotr=try park("jotr")
        let clock=BudgetClock(Self.monday)
        let http=PathHTTP(["/api/v1/alerts": .status(403)])
        let store=ParkStore(transport: http, persist: false, clock: { clock.now })
        let refused=await store.alerts(for: [jotr], key: "mine", network: true, force: true)
        #expect(refused.busy && refused.keyRefused)
        #expect(await store.hydrate([jotr]).keyRefused)
        await http.set("/api/v1/alerts", .status(429))
        clock.advance(NPSKeyPause.length)
        let quota=await store.alerts(for: [jotr], key: "mine", network: true, force: true)
        #expect(quota.busy && !quota.keyRefused)
        await http.set("/api/v1/alerts", .status(401))
        await store.keyChanged(to: "other")
        #expect(await store.alerts(for: [jotr], key: "other", network: true, force: true).keyRefused)
        await http.set("/api/v1/alerts", .body("{\"data\":[]}"))
        await store.keyChanged(to: "fixed")
        let accepted=await store.alerts(for: [jotr], key: "fixed", network: true, force: true)
        #expect(!accepted.busy && !accepted.keyRefused)
    }
    /// A refused key is not sent again for a day, even when pulled to refresh; a key saved or removed
    /// goes at once.
    @Test func aRefusedKeyWaitsADay() async throws {
        let jotr=try park("jotr")
        let clock=BudgetClock(Self.monday)
        let http=PathHTTP(["/api/v1/alerts": .status(403)])
        let store=ParkStore(transport: http, persist: false, clock: { clock.now })
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: false).keyRefused)
        clock.advance(3601)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: true).keyRefused)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: false).keyRefused)
        #expect(await http.count("/api/v1/alerts") == 1)
        clock.advance(NPSKeyPause.length-3602)
        _=await store.alerts(for: [jotr], key: "k", network: true, force: true)
        #expect(await http.count("/api/v1/alerts") == 1)
        clock.advance(1)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: false).keyRefused)
        #expect(await http.count("/api/v1/alerts") == 2)
        await store.keyChanged(to: "other")
        _=await store.alerts(for: [jotr], key: "other", network: true, force: false)
        #expect(await http.count("/api/v1/alerts") == 3)
    }
    /// The day's pause outlives the app: a store made later (a relaunch) reads it, and holds alerts,
    /// programs and campgrounds for that key, still saying the key was refused. It is kept as a date
    /// and a hash, never the key. A key saved or removed ends it, file and all.
    @Test func aRefusedKeysPauseOutlivesARelaunch() async throws {
        let jotr=try park("jotr")
        let clock=BudgetClock(Self.monday)
        let file=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-nps-pause-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let key="refusedKey0123456789abcdefghijklmnopqrstu"
        let http=PathHTTP(["/api/v1/alerts": .status(403), "/api/v1/events": .body("{\"data\":[]}"), "/api/v1/campgrounds": .body("{\"data\":[]}")])
        let first=ParkStore(transport: http, persist: false, pauseFile: file, clock: { clock.now })
        #expect(await first.alerts(for: [jotr], key: key, network: true, force: true).keyRefused)
        let stamp=try String(contentsOf: file, encoding: .utf8)
        #expect(!stamp.contains(key) && stamp.contains(NPSKeyPause.digest(key)) && NPSKeyPause.digest(key).count == 16)
        clock.advance(3600)
        let relaunched=ParkStore(transport: http, persist: false, pauseFile: file, clock: { clock.now })
        let held=await relaunched.alerts(for: [jotr], key: key, network: true, force: true)
        #expect(held.busy && held.keyRefused)
        #expect(await relaunched.programs(for: jotr, key: key, network: true, force: true) == nil)
        #expect(await relaunched.campgrounds(for: [jotr], key: key, network: true, force: true) == nil)
        #expect(await http.urls.count == 1)
        // Another key is not held by it.
        #expect(await relaunched.programs(for: jotr, key: "another", network: true, force: true) != nil)
        #expect(await http.urls.count == 2)
        // A day after the refusal, the next launch asks again (and is refused again).
        clock.advance(NPSKeyPause.length-3600)
        let nextDay=ParkStore(transport: http, persist: false, pauseFile: file, clock: { clock.now })
        _=await nextDay.alerts(for: [jotr], key: key, network: true, force: false)
        #expect(await http.count("/api/v1/alerts") == 2)
        await nextDay.keyChanged(to: "other")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let cleared=ParkStore(transport: http, persist: false, pauseFile: file, clock: { clock.now })
        _=await cleared.alerts(for: [jotr], key: key, network: true, force: false)
        #expect(await http.count("/api/v1/alerts") == 3)
    }
    /// Campgrounds NPS refused, or answered unreadably, are not asked for on every park page: again an
    /// hour later. An odd field costs only itself, and one record that cannot be read costs only
    /// itself, never the other campgrounds.
    @Test func campgroundsWaitAfterARefusalAndKeepReadableRecords() async throws {
        let jotr=try park("jotr")
        let clock=BudgetClock(Self.monday)
        let http=PathHTTP(["/api/v1/campgrounds": .status(403)])
        let store=ParkStore(transport: http, persist: false, clock: { clock.now })
        #expect(await store.campgrounds(for: [jotr], key: "k", network: true, force: false) == nil)
        #expect(await store.campgrounds(for: [jotr], key: "k", network: true, force: false) == nil)
        #expect(await http.count("/api/v1/campgrounds") == 1)
        clock.advance(3601)
        await http.set("/api/v1/campgrounds", .body("not json"))
        #expect(await store.campgrounds(for: [jotr], key: "k", network: true, force: false) == nil)
        #expect(await store.campgrounds(for: [jotr], key: "k", network: true, force: false) == nil)
        #expect(await http.count("/api/v1/campgrounds") == 2)
        clock.advance(3601)
        // A count as a number is read; a field of the wrong type costs only that field; something that is
        // not a record costs only itself.
        await http.set("/api/v1/campgrounds", .body("{\"total\":\"3\",\"data\":[{\"name\":\"Jumbo Rocks\",\"parkCode\":\"jotr\",\"campsites\":{\"totalSites\":124},\"url\":7},\"not a record\",{\"name\":\"Indian Cove\",\"parkCode\":\"jotr\",\"accessibility\":[]}]}"))
        let kept=await store.campgrounds(for: [jotr], key: "k", network: true, force: false)
        #expect(kept?.campgrounds["jotr"]?.map(\.name).sorted() == ["Indian Cove", "Jumbo Rocks"])
        #expect(kept?.campgrounds["jotr"]?.first { $0.name == "Jumbo Rocks" }?.totalSites == 124)
        #expect(await http.count("/api/v1/campgrounds") == 3)
    }
    /// A caller still holding a key the person has since replaced asks NPS for nothing: no programs,
    /// no campgrounds.
    @Test func aReplacedKeyAsksForNothingMore() async throws {
        let jotr=try park("jotr")
        let http=PathHTTP(["/api/v1/events": .body("{\"data\":[]}"), "/api/v1/campgrounds": .body("{\"data\":[]}")])
        let store=ParkStore(transport: http, persist: false)
        await store.keyChanged(to: "new")
        #expect(await store.programs(for: jotr, key: "old", network: true, force: true) == nil)
        #expect(await store.campgrounds(for: [jotr], key: "old", network: true, force: true) == nil)
        #expect(await http.urls.isEmpty)
        _=await store.programs(for: jotr, key: "new", network: true, force: true)
        #expect(await http.urls.count == 1)
    }
    /// A caller that joins an alerts request just cancelled (its only waiter left) asks again itself,
    /// rather than taking the cancelled request's failure and the old cache.
    @Test(.timeLimit(.minutes(1))) func aCallerJoiningACancelledRequestAsksAgain() async throws {
        let jotr=try park("jotr")
        let http=CancelledFirstHTTP()
        let store=ParkStore(transport: http, persist: false)
        let first=Task { await store.alerts(for: [jotr], key: "k", network: true, force: true) }
        while await http.asked == 0 { try await Task.sleep(for: .milliseconds(5)) }
        first.cancel()
        #expect(await first.value.cache == nil)
        // Joins the cancelled request while its answer is still held.
        let second=Task { await store.alerts(for: [jotr], key: "k", network: true, force: true) }
        try await Task.sleep(for: .milliseconds(100))
        await http.release()
        let answer=await second.value
        #expect(answer.cache?.alerts["jotr"] == [] && !answer.busy)
        #expect(await http.asked == 2)
    }
    /// Where alerts are shown, a refused key is named rather than called busy: the person's own key,
    /// or the shared one, with the cue to check the Park Service's site.
    @Test func aRefusedKeyIsNamedWhereAlertsAreShown() throws {
        let jotr=try park("jotr")
        let busy=MissingInput.unchecked(busy: true)
        let own=ScoreInputs(alertsBusy: true, alertsRefusal: .own).accessNote(jotr)
        let shared=ScoreInputs(alertsBusy: true, alertsRefusal: .shared).accessNote(jotr)
        #expect(own == MissingInput.refusal(.own, cached: false) && own != busy)
        #expect(shared == MissingInput.refusal(.shared, cached: false) && shared != busy && shared?.contains("nps.gov") == true)
        #expect(MissingInput.refusal(.own, cached: true) != own)
        #expect(ScoreInputs(alertsBusy: true).accessNote(jotr) == busy)
        #expect(MissingInput.unchecked(busy: false, refused: .own) == MissingInput.unchecked(busy: false))
    }
    /// Alerts an earlier update left, while the Park Service refuses requests: the refused key (or
    /// that alerts are busy) is said after what they list, closure or not, so an old update never
    /// passes for a current one.
    @Test func cachedAlertsSayWhenTheyCannotBeUpdated() throws {
        let jotr=try park("jotr")
        let cache=ParkAlertsCache(updated: .now, alerts: ["jotr": []])
        let summary=AlertRanking.summary([], park: jotr)
        #expect(ScoreInputs(alerts: cache).accessNote(jotr) == summary)
        let refused=ScoreInputs(alerts: cache, alertsBusy: true, alertsRefusal: .shared).accessNote(jotr)
        #expect(refused == Sentences.join([summary, MissingInput.refusal(.shared, cached: true)]))
        #expect(MissingInput.refusal(.shared, cached: true) != MissingInput.refusal(.shared, cached: false))
        #expect(ScoreInputs(alerts: cache, alertsBusy: true).accessNote(jotr) == Sentences.join([summary, MissingInput.unchecked(busy: true)]))
        // A closure stands beside the score on its own: the note says only that it cannot be updated.
        let closed=ParkAlertsCache(updated: .now, alerts: ["jotr": [ParkAlert(id: "c", title: "Keys View Road closed", description: "", category: "Park Closure")]])
        #expect(ScoreInputs(alerts: closed).accessNote(jotr) == nil)
        #expect(ScoreInputs(alerts: closed, alertsBusy: true, alertsRefusal: .own).accessNote(jotr) == MissingInput.refusal(.own, cached: true))
    }
    /// A key saved or removed while a park page's alerts request is out: the old key's answer is not
    /// applied (nor its refusal named), and the page's programs are asked for with the new key.
    @MainActor @Test(.timeLimit(.minutes(1))) func aPageOpenAcrossAKeyChangeAsksWithTheNewKey() async throws {
        let jotr=try park("jotr")
        let store=KeySwapParks()
        let model=PlanModel(weather: WeatherService(transport: StubHTTP([:]), persist: false), parkStore: store,
                            detail: ForecastDetailService(transport: StubHTTP([:]), persist: false), defaults: isolatedDefaults())
        var own: String?="old"
        model.ownNPSKey={ own }
        let page=Task { await model.refreshParkUpdates([jotr], programs: true) }
        while await store.alertKeys.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        own="new"
        await model.npsKeyChanged()
        await store.release()
        await page.value
        #expect(model.alertsUpdated == KeySwapParks.fresh.updated)
        #expect(model.alertsRefusal == nil && !model.npsKeyRefused && !model.alertsBusy)
        #expect(await store.programKeys == ["new"])
        #expect(model.programsAsked.contains(jotr.id))
    }
    /// Fresh alerts are not called busy because another request (programs) made the Park Service's host wait.
    @Test func anotherRequestsRefusalLeavesFreshAlertsCalm() async throws {
        let jotr=try park("jotr")
        let http=PathHTTP(["/api/v1/alerts": .body("{\"data\":[]}"), "/api/v1/events": .status(503)])
        let store=ParkStore(transport: http, persist: false)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: true).busy == false)
        _=await store.programs(for: jotr, key: "k", network: true, force: true)
        #expect(await store.alerts(for: [jotr], key: "k", network: true, force: false).busy == false)
    }
    /// A full refresh that finds a background one (one page) on its way, which stops before the set
    /// is whole, asks for the rest itself rather than keep the old alerts.
    @Test func aFullRefreshFollowsABackgroundOneThatStoppedShort() async throws {
        let jotr=try park("jotr")
        let body="{\"total\":\"600\",\"data\":[{\"id\":\"a\",\"title\":\"Road Closed\",\"parkCode\":\"jotr\"}]}"
        let http=PathHTTP(["/api/v1/alerts": .body(body)], delay: .milliseconds(100))
        let store=ParkStore(transport: http, persist: false)
        let background=Task { await store.alerts(for: [jotr], key: "k", network: true, force: true, pages: 1) }
        while await http.count("/api/v1/alerts") == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        let full=await store.alerts(for: [jotr], key: "k", network: true, force: true)
        #expect(await background.value.cache == nil)
        #expect(full.cache?.alerts["jotr"]?.isEmpty == false)
        #expect(await http.count("/api/v1/alerts") == 1+ParkStore.alertPages)
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

    /// Detail handed on chunk by chunk, as a refresh's requests land, is one change.
    @MainActor @Test func chunksThatLandTogetherAreOneChange() async throws {
        let model=PlanModel(weather: WeatherService(transport: PathHTTP([:]), persist: false), parkStore: ParkStore(transport: PathHTTP([:]), persist: false),
                            detail: ForecastDetailService(transport: PathHTTP([:]), persist: false), defaults: isolatedDefaults())
        await model.cachesReady()
        let before=model.dataRevision
        let series=HourlySeries(updated: .now, times: [1790000000], values: ["aerosol_optical_depth": [0.1]])
        for start in stride(from: 0, to: model.parks.count, by: 10) {
            model.receiveDetails(Dictionary(uniqueKeysWithValues: model.parks[start..<min(start+10, model.parks.count)].map { ($0.id, ForecastDetail(air: series)) }))
        }
        let clock=ContinuousClock(), end=clock.now.advanced(by: .seconds(5))
        while model.details.count<model.parks.count && clock.now<end { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(model.details.count == model.parks.count)
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

    /// Only a reopening that has already happened is not a closure: one still to come, delayed,
    /// partial or uncertain is, and so is anything with something still shut.
    @Test func reopeningsAreNotClosures() {
        func kind(_ title: String, _ category: String) -> AlertKind { ParkAlert(id: "x", title: title, description: "", category: category).kind }
        #expect(kind("Road Reopened After Closure", "Information") == .notice)
        #expect(kind("Road Reopened After Closure", "Park Closure") == .notice)
        #expect(kind("Tioga Road Has Reopened", "Park Closure") == .notice)
        #expect(kind("Kolob Canyons Road Now Open", "Information") == .notice)
        #expect(kind("Kolob Canyons Road Now Open", "Park Closure") == .closure)
        #expect(kind("Road Is Open to High-Clearance Vehicles", "Park Closure") == .closure)
        #expect(kind("Going-to-the-Sun Road Has Reopened", "Park Closure") == .notice)
        for title in ["Tioga Road Reopens May 30", "Going-to-the-Sun Road Expected to Reopen June 15", "Generals Highway Reopening Delayed",
                      "Partial Reopening of Kolob Canyons Road", "Road Has Been Closed Due to Snow; Will Reopen When Safe",
                      "Road Reopens Friday After Weeklong Closure", "Scenic Drive Reopens Following Winter Closure",
                      "Road Reopened to Vehicles Until October 31", "Road Is Open Only to High-Clearance Vehicles"] {
            #expect(kind(title, "Park Closure") == .closure, "\(title)")
        }
        #expect(kind("Road Has Been Closed Due to Snow; Will Reopen When Safe", "Information") == .closure)
        #expect(kind("Road Reopens Friday After Weeklong Closure", "Information") == .closure)
        #expect(kind("Trail Reopened After Being Closed for Repairs", "Information") == .notice)
        #expect(kind("Lower Road Reopens; Upper Road Remains Closed", "Park Closure") == .closure)
        #expect(kind("Road Reopened, Trail Closed", "Information") == .closure)
        #expect(kind("Road Closure", "Information") == .closure)
        // Open in part, something else still shut, in any closure word.
        for title in ["Park Is Open; Upper Road Impassable After Storm", "Lehman Caves Tours Are Open; Wheeler Peak Scenic Drive Closure in Effect",
                      "Kolob Canyons Road Now Open; Lee Pass Trailhead Washed Out", "Visitor Center Reopened; Road Closure Continues"] {
            #expect(kind(title, "Information") == .closure, "\(title)")
            #expect(kind(title, "Park Closure") == .closure, "\(title)")
        }
        // Reopened only to some, or only so far.
        #expect(kind("Road Reopened to Hikers and Bikers", "Park Closure") == .closure)
        #expect(kind("Rim Drive Reopened to Mile 8", "Park Closure") == .closure)
    }
}
