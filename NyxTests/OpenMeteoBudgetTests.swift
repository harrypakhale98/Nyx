import Foundation
import Synchronization
import Testing
@testable import Nyx

extension OpenMeteoEcho: HTTPTransport {}

/// Answers any Open-Meteo request with a well-formed body for every place it names and every
/// variable (per model) it asks for, or refuses with a chosen error. Records what it was sent; with
/// `hold`, keeps the first request waiting until `release()`, so a test can act while it is in flight.
actor OpenMeteoEcho {
    private(set) var urls: [URL]=[]
    private var refusal: (any Error)?
    private var held: CheckedContinuation<Void, Never>?
    private var holding: Bool
    private(set) var waiting=false
    init(hold: Bool = false) { holding=hold }
    func refuse(_ error: (any Error)?) { refusal=error }
    func release() { held?.resume(); held=nil; waiting=false }
    func get(_ url: URL) async throws -> Data {
        urls.append(url)
        if holding {
            holding=false
            await withCheckedContinuation { held=$0; waiting=true }
        }
        if let refusal { throw refusal }
        return Self.body(for: url)
    }
    static func list(_ url: URL, _ name: String) -> [String] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value ?? "").split(separator: ",").map(String.init)
    }
    static func body(for url: URL) -> Data {
        let count=max(1, list(url, "latitude").count), models=list(url, "models")
        let keys=list(url, "hourly").flatMap { name in models.isEmpty ? [name] : models.map { "\(name)_\($0)" } }
        let one="{\"hourly\":{\"time\":[1790000000,1790003600],"+keys.map { "\"\($0)\":[10,20]" }.joined(separator: ",")+"}}"
        return Data((count == 1 ? one : "["+Array(repeating: one, count: count).joined(separator: ",")+"]").utf8)
    }
}
/// A clock the test moves by hand.
final class BudgetClock: Sendable {
    private let state: Mutex<Date>
    init(_ start: Date) { state=Mutex(start) }
    var now: Date { state.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { state.withLock { $0=$0.addingTimeInterval(seconds) } }
}

/// Nyx as a light, polite Open-Meteo client: what a request counts as, how long a forecast is reused,
/// how a refusal is waited out (across launches), and what a whole day costs one device.
struct OpenMeteoBudgetTests {
    static let host=WeatherService.host, air="air-quality-api.open-meteo.com"
    /// Monday 12 October 2026, 00:00 UTC: the start of one of the service's days.
    static let midnight=Date(timeIntervalSince1970: 1_791_763_200)
    func parks() throws -> [Park] { try ParkData.load() }
    func url(_ query: String, host: String = "api.open-meteo.com", path: String = "/v1/forecast") throws -> URL {
        try #require(URL(string: "https://\(host)\(path)?\(query)"))
    }
    func temporaryFile(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("nyx-\(name)-\(UUID().uuidString).json")
    }

    // MARK: What a request counts as

    /// Open-Meteo's own examples (pricing page): two weeks of 15 variables is 1.5 calls, four weeks
    /// 3.0; every place in a request counts on its own and is never less than one call.
    @Test func weightFollowsOpenMeteo() throws {
        let fifteen=(1...15).map { "v\($0)" }.joined(separator: ",")
        #expect(CallWeight.of(try url("latitude=1&longitude=1&hourly=\(fifteen)&forecast_days=14")) == 1.5)
        #expect(CallWeight.of(try url("latitude=1&longitude=1&hourly=\(fifteen)&forecast_days=28")) == 3.0)
        #expect(CallWeight.of(try url("latitude=1,2&longitude=1,2&hourly=\(fifteen)&forecast_days=14")) == 3.0)
        // Models multiply the variables: 5 variables in 5 models are 25.
        let five=(1...5).map { "v\($0)" }.joined(separator: ",")
        #expect(CallWeight.of(try url("latitude=1&longitude=1&hourly=\(five)&models=a,b,c,d,e&forecast_days=14")) == 2.5)
        // Nyx's own requests sit at the floor: one call a place.
        let parks=try parks()
        let clouds=try #require(CatalogForecast.url(for: Array(parks.prefix(50))))
        #expect(CallWeight.of(clouds) == 50)
        let point=try #require(SpotForecast.Point(latitude: 34, longitude: -116))
        let spots=try #require(SpotForecast.url(for: [point]))
        #expect(CallWeight.of(spots) == 1)
        let summit=try #require(SummitLayerService.url(for: Array(parks.prefix(1))))
        #expect(CallWeight.of(summit) == 1)
        #expect(CallWeight.of(try url("latitude=1,2,3&longitude=1,2,3&hourly=cloud_cover&models=gfs_seamless,ecmwf_ifs025,icon_seamless&forecast_days=7&past_days=1")) == 3)
        #expect(CallWeight.of(try url("latitude=1&longitude=1&hourly=aerosol_optical_depth,pm2_5&domains=cams_global&forecast_days=7&past_days=1", host: Self.air, path: "/v1/air-quality")) == 1)
    }

    // MARK: Refusals

    /// A 429 with no hint: nothing is asked for an hour, not even by pulling to refresh, and a
    /// relaunch (a new client reading the same file) waits too. Then the host is asked again.
    @Test func rateLimitWithoutRetryAfterWaitsAcrossLaunches() async throws {
        let file=temporaryFile("backoff"), parks=Array(try parks().prefix(3))
        defer { try? FileManager.default.removeItem(at: file) }
        let clock=BudgetClock(Self.midnight.addingTimeInterval(10*3600)), http=OpenMeteoEcho()
        await http.refuse(HTTPStatusError(status: 429))
        let first=WeatherService(transport: http, persist: false, backoff: HostBackoff(file: file, random: { 0 }), clock: { clock.now })
        #expect(await first.forecasts(for: parks, network: true, force: true).isEmpty)
        #expect(await first.heldBack() == false)
        _=await first.forecasts(for: parks, network: true, force: true)
        #expect(await http.urls.count == 1)
        #expect(await first.heldBack())
        // Relaunched half an hour later: the refusal is remembered.
        await http.refuse(nil)
        clock.advance(1800)
        let relaunched=WeatherService(transport: http, persist: false, backoff: HostBackoff(file: file, now: clock.now), clock: { clock.now })
        _=await relaunched.forecasts(for: parks, network: true, force: true)
        #expect(await http.urls.count == 1)
        #expect(HostBackoff(file: file, now: clock.now).retryAfter(Self.host) == Self.midnight.addingTimeInterval(11*3600))
        // An hour after the refusal it is asked again, and the streak is over.
        clock.advance(1801)
        let later=HostBackoff(file: file, now: clock.now)
        let afterwards=WeatherService(transport: http, persist: false, backoff: later, clock: { clock.now })
        #expect(await afterwards.forecasts(for: parks, network: true, force: true).count == parks.count)
        #expect(await http.urls.count == 2)
        #expect(later.strikes(Self.host) == 0 && HostBackoff(file: file, now: clock.now).retryAfter(Self.host) == nil)
    }
    /// The server's Retry-After is honoured as given (seconds or an HTTP date), never shortened.
    @Test func retryAfterIsHonoured() async throws {
        let now=Self.midnight
        #expect(HTTPStatusError.retryAfter("120", now: now) == 120)
        #expect(HTTPStatusError.retryAfter("Mon, 12 Oct 2026 00:05:00 GMT", now: now) == 300)
        #expect(HTTPStatusError.retryAfter("soon", now: now) == nil && HTTPStatusError.retryAfter(nil, now: now) == nil)
        let clock=BudgetClock(now), http=OpenMeteoEcho(), parks=Array(try parks().prefix(2))
        await http.refuse(HTTPStatusError(status: 429, retryAfter: 120))
        let service=WeatherService(transport: http, persist: false, backoff: HostBackoff(file: nil, random: { 0 }), clock: { clock.now })
        _=await service.forecasts(for: parks, network: true, force: true)
        await http.refuse(nil)
        clock.advance(119)
        _=await service.forecasts(for: parks, network: true, force: true)
        #expect(await http.urls.count == 1)
        clock.advance(2)
        #expect(await service.forecasts(for: parks, network: true, force: true).count == 2)
        #expect(await http.urls.count == 2)
    }
    /// Open-Meteo says which limit it reached, and its windows reset on the UTC minute, hour and
    /// day: Nyx comes back after that reset (a little later at random), never before.
    @Test func openMeteoNamesTheWindowToWaitFor() throws {
        let body=Data("{\"error\":true,\"reason\":\"Hourly API request limit exceeded. Please try again in the next hour.\"}".utf8)
        let reason=try #require(HTTPStatusError.reason(in: body))
        #expect(Backoff.Window(reason) == .hour)
        #expect(Backoff.Window("Daily API request limit exceeded. Please try again tomorrow.") == .day)
        #expect(Backoff.Window("Minutely API request limit exceeded. Please try again in one minute.") == .minute)
        #expect(Backoff.Window("Too many concurrent requests") == .concurrent)
        #expect(Backoff.Window("Parameter 'latitude' is out of range") == nil)
        let tenTwenty=Self.midnight.addingTimeInterval(10*3600+20*60)
        func wait(_ text: String, strike: Int = 1, at now: Date? = nil, jitter: Double = 0) -> TimeInterval? {
            Backoff.wait(after: HTTPStatusError(status: 429, reason: text), strike: strike, now: now ?? tenTwenty, jitter: jitter)
        }
        // Typed, so the comparison is between two times (an integer literal would compare unequal).
        let fortyMinutes: TimeInterval=40*60, hour: TimeInterval=3600
        #expect(wait("Hourly API request limit exceeded.") == fortyMinutes)
        #expect(wait("Hourly API request limit exceeded.", strike: 2) == fortyMinutes+hour)
        #expect(wait("Hourly API request limit exceeded.", jitter: 0.5) == fortyMinutes+300)
        #expect(wait("Daily API request limit exceeded.") == 13*hour+fortyMinutes)
        #expect(wait("Minutely API request limit exceeded.", at: tenTwenty.addingTimeInterval(30)) == 30)
        // A 503 without a hint waits fifteen minutes, then doubles; jitter only ever shortens it, by a fifth at most.
        #expect(Backoff.wait(after: HTTPStatusError(status: 503), strike: 1, now: tenTwenty, jitter: 0) == 900)
        #expect(Backoff.wait(after: HTTPStatusError(status: 503), strike: 3, now: tenTwenty, jitter: 0) == hour)
        let spread=try #require(Backoff.wait(after: HTTPStatusError(status: 503), strike: 1, now: tenTwenty, jitter: 0.99))
        #expect(spread >= 720 && spread <= 900)
        // Redirects, other errors and being offline never wait.
        #expect(Backoff.wait(after: HTTPStatusError(status: 302), strike: 1, now: tenTwenty, jitter: 0) == nil)
        #expect(Backoff.wait(after: URLError(.notConnectedToInternet), strike: 1, now: tenTwenty, jitter: 0) == nil)
    }
    /// Server errors in a row wait longer each time (15, 30, 60 minutes); a success ends the streak.
    @Test func serverErrorsBackOffExponentially() async throws {
        let clock=BudgetClock(Self.midnight), http=OpenMeteoEcho(), parks=Array(try parks().prefix(2))
        let backoff=HostBackoff(file: nil, random: { 0 })
        let service=WeatherService(transport: http, persist: false, backoff: backoff, clock: { clock.now })
        await http.refuse(HTTPStatusError(status: 503))
        var asked=0
        for wait in [900.0, 1800, 3600] {
            _=await service.forecasts(for: parks, network: true, force: true)
            asked+=1
            #expect(await http.urls.count == asked)
            #expect(backoff.retryAfter(Self.host) == clock.now.addingTimeInterval(wait))
            // Pulling to refresh while it waits sends nothing.
            clock.advance(wait-1)
            _=await service.forecasts(for: parks, network: true, force: true)
            #expect(await http.urls.count == asked)
            clock.advance(1)
        }
        #expect(backoff.strikes(Self.host) == 3)
        await http.refuse(nil)
        #expect(await service.forecasts(for: parks, network: true, force: true).count == 2)
        #expect(backoff.strikes(Self.host) == 0 && backoff.allows(Self.host, now: clock.now))
    }
    /// Forecast detail and the summit's layers wait out a refusal on their own hosts, as clouds do,
    /// and the smoke host's refusal never holds back the forecast host.
    @Test func detailWaitsPerHost() async throws {
        let clock=BudgetClock(Self.midnight), http=OpenMeteoEcho(), one=Array(try parks().prefix(1))
        let backoff=HostBackoff(file: nil, random: { 0 })
        await http.refuse(HTTPStatusError(status: 429, reason: "Daily API request limit exceeded."))
        let detail=ForecastDetailService(transport: http, persist: false, backoff: backoff, clock: { clock.now })
        _=await detail.details(for: one, weather: true, smoke: true)
        // One request to each host, then the first refusal on each stops that host's queue.
        #expect(await http.urls.count == 2)
        #expect(!backoff.allows(Self.host, now: clock.now) && !backoff.allows(Self.air, now: clock.now))
        clock.advance(23*3600)
        _=await detail.details(for: one, weather: true, smoke: true, force: true)
        let summit=SummitLayerService(transport: http, persist: false, backoff: backoff, clock: { clock.now })
        let hale=try #require(try parks().first { $0.aboveInversion == true })
        _=await summit.layers(for: [hale], network: true)
        #expect(await http.urls.count == 2)
        // After midnight UTC (and its spread) everything may ask again.
        clock.advance(3600+1800)
        await http.refuse(nil)
        #expect(await summit.layers(for: [hale], network: true)[hale.id] != nil)
        #expect(await detail.details(for: one, weather: true, smoke: true)[one[0].id]?.air != nil)
    }

    // MARK: Reuse

    /// However often Nyx is opened or pulled, a forecast is not asked for again before its time:
    /// clouds at six hours (an hour when pulled), model comparison and layers at twelve (three when
    /// pulled), smoke at twelve whatever happens.
    @Test func forecastsAreReusedWithinTheirWindow() async throws {
        let clock=BudgetClock(Self.midnight), http=OpenMeteoEcho(), parks=try parks()
        let weather=WeatherService(transport: http, persist: false, clock: { clock.now })
        let detail=ForecastDetailService(transport: http, persist: false, clock: { clock.now })
        func sent() async -> Int { await http.urls.count }
        _=await weather.forecasts(for: parks, network: true)
        #expect(await sent() == 2)
        for _ in 0..<20 { clock.advance(60); _=await weather.forecasts(for: parks, network: true) }
        #expect(await sent() == 2)
        clock.advance(30*60)
        for _ in 0..<5 { _=await weather.forecasts(for: parks, network: true, force: true) }
        #expect(await sent() == 2)
        clock.advance(11*60)
        _=await weather.forecasts(for: parks, network: true, force: true)
        #expect(await sent() == 4)
        // Opened again five hours on: still fresh.
        clock.advance(5*3600)
        _=await weather.forecasts(for: parks, network: true)
        #expect(await sent() == 4)
        clock.advance(3600)
        _=await weather.forecasts(for: parks, network: true)
        #expect(await sent() == 6)
        // Detail: models, layers and smoke, two requests each for 63 parks.
        _=await detail.details(for: parks, weather: true, smoke: true)
        #expect(await sent() == 12)
        clock.advance(3600)
        _=await detail.details(for: parks, weather: true, smoke: true, force: true)
        #expect(await sent() == 12)
        clock.advance(2*3600+60)
        _=await detail.details(for: parks, weather: true, smoke: true, force: true)
        let models=await http.urls.dropFirst(12).filter { $0.host == Self.host }.count, smoke=await http.urls.dropFirst(12).filter { $0.host == Self.air }.count
        #expect(models == 4 && smoke == 0)
        clock.advance(9*3600)
        _=await detail.details(for: parks, weather: true, smoke: true, force: true)
        #expect(await http.urls.dropFirst(16).filter { $0.host == Self.air }.count == 2)
    }
    /// Callers asking for the same thing at once share one request: two screens, one forecast.
    @Test func identicalRequestsShareOneFlight() async throws {
        let parks=try parks(), held=OpenMeteoEcho(hold: true)
        let weather=WeatherService(transport: held, persist: false)
        let first=Task { await weather.forecasts(for: parks, network: true) }
        var tries=0
        while !(await held.waiting), tries<500 { tries+=1; try await Task.sleep(for: .milliseconds(5)) }
        let second=Task { await weather.forecasts(for: parks, network: true, force: true) }
        try await Task.sleep(for: .milliseconds(50))
        await held.release()
        let firstCount=await first.value.count, secondCount=await second.value.count
        #expect(firstCount == parks.count && secondCount == parks.count)
        #expect(await held.urls.count == 2)
        // A catalogue tile asked for twice at once goes once.
        let catalog=try TestData.catalog(), regions=CatalogForecast.Regions(catalog)
        let tile=try #require(regions.requests.first?.first)
        let gate=OpenMeteoEcho(hold: true), places=WeatherService(transport: gate, persist: false)
        let a=Task { await places.catalogForecasts([tile], network: true) }
        tries=0
        while !(await gate.waiting), tries<500 { tries+=1; try await Task.sleep(for: .milliseconds(5)) }
        let b=Task { await places.catalogForecasts([tile], network: true) }
        try await Task.sleep(for: .milliseconds(50))
        await gate.release()
        let aCount=await a.value.count, bCount=await b.value.count
        #expect(aCount == tile.count && bCount == tile.count)
        #expect(await gate.urls.count == 1)
        // Forecast detail: one refresh in flight, later callers wait for it.
        let detailGate=OpenMeteoEcho(hold: true), detail=ForecastDetailService(transport: detailGate, persist: false)
        let c=Task { await detail.details(for: parks, weather: true, smoke: true) }
        tries=0
        while !(await detailGate.waiting), tries<500 { tries+=1; try await Task.sleep(for: .milliseconds(5)) }
        let d=Task { await detail.details(for: parks, weather: true, smoke: true, force: true) }
        try await Task.sleep(for: .milliseconds(50))
        await detailGate.release()
        _=await (c.value, d.value)
        #expect(await detailGate.urls.count == 6)
    }

    // MARK: The budget

    /// Scrolling the whole world list, a region a second for two minutes and then for an hour, never
    /// spends more than the browsing budget in any minute or hour, and tonight's parks still get
    /// their forecast at once.
    @Test func scrollingTheWorldCannotBurst() async throws {
        let catalog=try TestData.catalog(), regions=CatalogForecast.Regions(catalog)
        let clock=BudgetClock(Self.midnight.addingTimeInterval(9*3600)), http=OpenMeteoEcho(), ledger=CallLedger(file: nil)
        let service=WeatherService(transport: http, persist: false, ledger: ledger, clock: { clock.now })
        let caps=CallBudget.standard.browsing
        let largest=Double(regions.requests.flatMap { $0 }.map(\.count).max() ?? 0)
        #expect(largest <= 400)
        var index=0
        // Just under an hour, so the parks below ask within the hour the world has spent.
        for _ in 0..<3590 {
            let region=regions.requests[index % regions.requests.count]
            index+=1
            _=await service.catalogForecasts(region, network: true)
            let minute=ledger.used(Self.host, since: CallLedger.windowStart(clock.now, length: 60))
            let hour=ledger.used(Self.host, since: CallLedger.windowStart(clock.now, length: 3600))
            #expect(minute <= max(caps.minute, largest))
            #expect(hour <= max(caps.hour, largest))
            clock.advance(1)
        }
        // The hour was spent on the world; the parks still have room.
        let before=await http.urls.count
        #expect(await service.forecasts(for: try parks(), network: true).count == 63)
        #expect(await http.urls.count == before+2)
    }
    /// One day for two people, against the budgets this file justifies (Research/open-meteo-usage.md):
    /// a typical US day (Tonight three times, a park page twice, a pull to refresh, Background App
    /// Refresh every six hours) stays under 700 calls to the forecast host and 130 to the smoke host;
    /// a heavy day browsing Europe's parks on the list and the map stays under the device's daily
    /// ceiling of 3,000, with the world never more than 2,000.
    @Test func aSimulatedDayStaysWithinBudget() async throws {
        let parks=try parks(), catalog=try TestData.catalog(), regions=CatalogForecast.Regions(catalog)
        // Typical.
        do {
            let clock=BudgetClock(Self.midnight), http=OpenMeteoEcho(), ledger=CallLedger(file: nil)
            let weather=WeatherService(transport: http, persist: false, ledger: ledger, clock: { clock.now })
            let detail=ForecastDetailService(transport: http, persist: false, ledger: ledger, clock: { clock.now })
            func refresh(page: Bool = false, force: Bool = false) async {
                _=await weather.forecasts(for: parks, network: true, force: force)
                if page { _=await detail.details(for: parks, weather: true, smoke: true, force: force) }
            }
            // (hour, park page, pulled)
            let day: [(Double, Bool, Bool)]=[(0, false, false), (2, false, false), (6, false, false), (8, true, false), (12, false, false),
                                              (14, false, false), (15, true, true), (15.03, true, true), (18, false, false), (21, false, false)]
            for (hour, page, pulled) in day {
                clock.advance(Self.midnight.addingTimeInterval(hour*3600).timeIntervalSince(clock.now))
                await refresh(page: page, force: pulled)
            }
            let forecastCalls=ledger.used(Self.host, since: Self.midnight), smokeCalls=ledger.used(Self.air, since: Self.midnight)
            #expect(forecastCalls <= 700 && smokeCalls <= 130)
            #expect(forecastCalls == Double(63*5+126*2) && smokeCalls == 63)
        }
        // Heavy: Europe's regions on the list and the map, four visits, pulls, the parks too.
        do {
            let clock=BudgetClock(Self.midnight), http=OpenMeteoEcho(), ledger=CallLedger(file: nil)
            let weather=WeatherService(transport: http, persist: false, ledger: ledger, clock: { clock.now })
            let detail=ForecastDetailService(transport: http, persist: false, ledger: ledger, clock: { clock.now })
            let europe=regions.requests.filter { region in region.joined().contains { (35...71).contains($0.latitude) && (-11...40).contains($0.longitude) } }
            #expect(europe.count >= 5)
            var browsed=0.0
            for hour in [0.0, 6, 9, 12, 13, 18, 19, 23] {
                clock.advance(Self.midnight.addingTimeInterval(hour*3600).timeIntervalSince(clock.now))
                _=await weather.forecasts(for: parks, network: true)
                _=await detail.details(for: parks, weather: true, smoke: true)
                // A visit: every European region scrolled past, each settled for ten seconds, then twice again pulled.
                for pass in 0..<3 {
                    for region in europe {
                        let before=ledger.used(Self.host, since: Self.midnight)
                        _=await weather.catalogForecasts(region, network: true, force: pass>0)
                        browsed+=ledger.used(Self.host, since: Self.midnight)-before
                        clock.advance(10)
                    }
                    _=await weather.forecasts(for: parks, network: true, force: true)
                }
            }
            let forecastCalls=ledger.used(Self.host, since: Self.midnight)
            #expect(forecastCalls <= CallBudget.standard.essential.day)
            #expect(browsed <= CallBudget.standard.browsing.day)
        }
    }

    // MARK: The ledger and what the person sees

    /// The ledger survives a relaunch, counts a refusal as one call and a request that never left as
    /// none, and says what today cost.
    @Test func theLedgerCountsTodayAcrossLaunches() throws {
        let file=temporaryFile("calls")
        defer { try? FileManager.default.removeItem(at: file) }
        var calendar=Calendar(identifier: .gregorian)
        calendar.timeZone=try #require(TimeZone(identifier: "America/Los_Angeles"))
        // 07:00 UTC is midnight in Los Angeles.
        let morning=Self.midnight.addingTimeInterval(9*3600)
        let ledger=CallLedger(file: file, now: morning)
        let caps=CallBudget.standard.essential
        let sent=try #require(ledger.reserve(Self.host, calls: 63, caps: caps, now: morning))
        _=sent
        let refused=try #require(ledger.reserve(Self.host, calls: 63, caps: caps, now: morning))
        ledger.settle(refused, calls: 1)
        let offline=try #require(ledger.reserve(Self.air, calls: 63, caps: caps, now: morning))
        ledger.cancel(offline)
        // Yesterday evening in Los Angeles is not today.
        _=ledger.reserve(Self.host, calls: 10, caps: caps, now: Self.midnight.addingTimeInterval(6*3600))
        let relaunched=CallLedger(file: file, now: morning)
        let today=relaunched.today(now: morning, calendar: calendar)
        #expect(today.requests == 2 && today.calls == 64)
        // The minute is full for anything but an empty window.
        #expect(relaunched.allows(Self.host, calls: 300, caps: caps, now: morning))
        #expect(!relaunched.allows(Self.host, calls: 400, caps: caps, now: morning))
        #expect(relaunched.allows(Self.host, calls: 400, caps: caps, now: morning.addingTimeInterval(60)))
        #expect(relaunched.allows(Self.air, calls: 900, caps: caps, now: morning))
    }
    /// A refresh says what it found: new forecasts, one too recent to ask about again, requests
    /// paused while the service asks Nyx to wait, or saved data.
    @Test func refreshOutcomeSaysWhatHappened() {
        let now=Self.midnight.addingTimeInterval(20*3600)
        #expect(RefreshOutcome.of(forecastsOn: true, fetched: true, current: false, newest: now, heldBack: true, now: now) == .updated)
        let recent=now.addingTimeInterval(-20*60), old=now.addingTimeInterval(-5*3600)
        #expect(RefreshOutcome.of(forecastsOn: true, fetched: false, current: false, newest: recent, now: now) == .current(recent))
        #expect(RefreshOutcome.of(forecastsOn: true, fetched: false, current: false, newest: old, heldBack: true, now: now) == .paused(old))
        #expect(RefreshOutcome.of(forecastsOn: true, fetched: false, current: false, newest: nil, heldBack: true, now: now) == .paused(nil))
        #expect(RefreshOutcome.of(forecastsOn: true, fetched: false, current: false, newest: old, now: now) == .unreachable)
        #expect(RefreshOutcome.of(forecastsOn: false, fetched: false, current: false, newest: old, heldBack: true, now: now) == .forecastsOff)
        // Lines say the time in this device's own format, as of the real clock.
        #expect(RefreshOutcome.current(recent).line.hasSuffix(RefreshOutcome.when(recent)))
        #expect(RefreshOutcome.paused(old).line.hasSuffix(RefreshOutcome.when(old)))
        var utc=Calendar(identifier: .gregorian)
        utc.timeZone=TimeZone(identifier: "UTC") ?? .current
        #expect(RefreshOutcome.when(recent, now: now, calendar: utc) == recent.formatted(date: .omitted, time: .shortened))
        #expect(RefreshOutcome.paused(nil).line == String(localized: "Forecast requests are paused for a while. Showing saved data."))
    }
}
