import Foundation
import Synchronization

nonisolated protocol HTTPTransport: Sendable {
    func get(_ url: URL) async throws -> Data
    /// With request headers (the NPS key travels as `X-Api-Key`, never in the URL) and whether the
    /// request may use a constrained network (Low Data Mode). Transports that ignore both may rely
    /// on the default, which calls `get(_:)`.
    func get(_ url: URL, headers: [String: String], constrained: Bool) async throws -> Data
}
nonisolated extension HTTPTransport {
    func get(_ url: URL, headers: [String: String], constrained: Bool) async throws -> Data { try await get(url) }
}
/// The server answered, but not with success: 429 when the shared quota is spent, 403 for a
/// refused key, 5xx when it is struggling, 3xx when a captive portal answered instead. Only 429
/// and 5xx make the services wait before asking again (`Backoff`).
nonisolated struct HTTPStatusError: Error, Sendable {
    let status: Int
}
/// How long to leave a host alone after it refused a request: an hour after 429 (the NPS key is
/// shared by every install, 1,000 requests an hour), fifteen minutes after a server error. A 3xx
/// (a campground Wi-Fi sign-in page), any other 4xx, being offline or a switch turned off never
/// waits: the service itself did not ask for less traffic.
nonisolated enum Backoff {
    static func delay(after error: any Error) -> TimeInterval? {
        guard let status=(error as? HTTPStatusError)?.status else { return nil }
        if status == 429 { return 3600 }
        return (500..<600).contains(status) ? 900 : nil
    }
    /// True when the request failed only because Low Data Mode keeps it off a constrained network.
    static func constrained(_ error: any Error) -> Bool {
        guard let error=error as? URLError else { return false }
        let reason=error.networkUnavailableReason ?? (error.userInfo[NSURLErrorNetworkUnavailableReasonKey] as? Int).flatMap(URLError.NetworkUnavailableReason.init(rawValue:))
        return reason == .constrained
    }
}
/// When each host may be asked again after refusing a request. Kept on disk, so a quota refusal
/// survives a relaunch instead of every cold launch asking again at once. Per host: the forecast,
/// air-quality and park services refuse independently.
nonisolated final class HostBackoff: Sendable {
    private let state: Mutex<[String: Date]>
    private let file: URL?
    /// `file` nil keeps the dates in memory only (tests, and services that do not persist).
    init(file: URL?, now: Date = .now) {
        self.file=file
        let stored=file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        // A date further ahead than any backoff could set (a clock that moved) is not honoured.
        state=Mutex(stored.filter { $0.value>now && $0.value<now.addingTimeInterval(2*3600) })
    }
    static let shared=HostBackoff(file: CacheDirectory.url.appendingPathComponent("nyx-backoff.json"))
    func allows(_ host: String, now: Date = .now) -> Bool { state.withLock { now >= ($0[host] ?? .distantPast) } }
    func retryAfter(_ host: String) -> Date? { state.withLock { $0[host] } }
    /// Records a refusal; anything `Backoff` does not wait for is ignored.
    func record(_ error: any Error, host: String, now: Date = .now) {
        guard let delay=Backoff.delay(after: error) else { return }
        let snapshot=state.withLock { dates -> [String: Date] in
            dates[host]=max(dates[host] ?? .distantPast, now.addingTimeInterval(delay))
            dates=dates.filter { $0.value>now }
            return dates
        }
        if let file, let data=try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
    }
}
/// A redirect is never followed. Runtime requests can reach exactly three hosts, each behind its
/// own switch in Your privacy: park updates, forecasts, and (since 2026-10-05, with the owner's
/// approval) the aerosol forecast that warns of smoke.
nonisolated final class HostGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
nonisolated struct SafeHTTP: HTTPTransport {
    /// Each host and the preference that must not be off before it is contacted.
    static let preferences: [String: String] = ["developer.nps.gov": "npsEnabled", "api.open-meteo.com": "weatherEnabled",
                                                 "air-quality-api.open-meteo.com": "smokeEnabled"]
    static var hosts: Set<String> { Set(preferences.keys) }
    /// Where the switches live; tests use their own suite.
    let suite: String?
    /// One ephemeral session per transport, reused for every request: no cookies, no cache, and
    /// one TLS handshake per host instead of one per request.
    private let session: URLSession
    init(suite: String? = nil) {
        self.suite=suite
        let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=20
        configuration.timeoutIntervalForResource=30
        configuration.httpCookieStorage=nil
        configuration.urlCache=nil
        session=URLSession(configuration: configuration, delegate: HostGuard(), delegateQueue: nil)
    }
    func get(_ url: URL) async throws -> Data { try await get(url, headers: [:], constrained: true) }
    func get(_ url: URL, headers: [String: String], constrained: Bool) async throws -> Data {
        guard url.scheme == "https", let host=url.host, let preference=Self.preferences[host] else { throw URLError(.unsupportedURL) }
        let defaults=suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        guard defaults.object(forKey: preference) as? Bool != false else { throw URLError(.cancelled) }
        var request=URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.allowsConstrainedNetworkAccess=constrained
        let (data,response)=try await session.data(for: request)
        guard let http=response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw HTTPStatusError(status: http.statusCode) }
        return data
    }
}
/// The last forecasts and park updates. Application Support, not Caches: iOS empties Caches when
/// storage runs low, and these files are what keep clouds and closures available offline. They are
/// excluded from backup because they can always be fetched again.
nonisolated enum CacheDirectory {
    static let url: URL = {
        let manager=FileManager.default
        guard var folder=manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Offline", isDirectory: true),
              (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return legacy }
        var values=URLResourceValues()
        values.isExcludedFromBackup=true
        try? folder.setResourceValues(values)
        return folder
    }()
    /// Where earlier versions kept these files; still read until the next successful update.
    private static var legacy: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    }
    /// A file that is missing costs one existence check, not two failed reads.
    static func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        let file="nyx-\(name).json", manager=FileManager.default
        let current=url.appendingPathComponent(file), old=legacy.appendingPathComponent(file)
        let source=manager.fileExists(atPath: current.path) ? current : manager.fileExists(atPath: old.path) ? old : nil
        guard let source, let data=try? Data(contentsOf: source) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func write<T: Encodable>(_ value: T, name: String) {
        guard let data=try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url.appendingPathComponent("nyx-\(name).json"), options: .atomic)
    }
    static func remove(name: String) {
        for folder in [url, legacy] { try? FileManager.default.removeItem(at: folder.appendingPathComponent("nyx-\(name).json")) }
    }
}
extension Park {
    /// Where the forecast is asked for: the park's first named viewing spot (where people actually
    /// stand under the sky, often far higher or lower than the park's centre point), else the park's
    /// own coordinates. Open-Meteo corrects for the terrain height at the point it is given.
    nonisolated var forecastPoint: (latitude: Double, longitude: Double) {
        viewingSpots.first.map { ($0.latitude, $0.longitude) } ?? (latitude, longitude)
    }
}
nonisolated protocol WeatherProviding: Sendable {
    func forecasts(for parks: [Park], network: Bool, force: Bool) async -> [String: Forecast]
    /// The cached forecasts, read once from disk off the main actor at launch.
    func hydrate(_ parks: [Park]) async -> [String: Forecast]
    /// Forecasts already read at launch (`CachePreload`), so no file is read again.
    func seed(_ cached: [String: Forecast], parks: [Park]) async
}
nonisolated extension WeatherProviding {
    func forecast(for park: Park, network: Bool, force: Bool = false) async -> Forecast? {
        await forecasts(for: [park], network: network, force: force)[park.id]
    }
}
actor WeatherService: WeatherProviding {
    static let host="api.open-meteo.com"
    private let transport: any HTTPTransport
    private let persist: Bool
    private let backoff: HostBackoff
    private let clock: @Sendable () -> Date
    private var memory: [String: Forecast] = [:]
    /// Parks whose cache file has been looked for, found or not, so no file is read twice.
    private var loaded=Set<String>()
    /// Requests already on their way, so Tonight, Parks and saved parks never fetch the same park twice at once.
    private var inFlight: [String: Task<[String: Forecast], Never>] = [:]
    init(transport: any HTTPTransport = SafeHTTP(), persist: Bool = true, backoff: HostBackoff? = nil, clock: @escaping @Sendable () -> Date = { .now }) {
        self.transport=transport; self.persist=persist; self.clock=clock
        self.backoff=backoff ?? (persist ? .shared : HostBackoff(file: nil))
    }
    func hydrate(_ parks: [Park]) async -> [String: Forecast] {
        for park in parks { load(park.id) }
        return memory
    }
    func seed(_ cached: [String: Forecast], parks: [Park]) {
        for park in parks where loaded.insert(park.id).inserted && memory[park.id] == nil { memory[park.id]=cached[park.id] }
    }
    private func load(_ id: String) {
        guard loaded.insert(id).inserted, memory[id] == nil, persist, let cached=CacheDirectory.read(Forecast.self, name: "weather-\(id)") else { return }
        memory[id]=cached
    }
    /// Cached forecasts for every park, refreshed in as few requests as possible: Open-Meteo
    /// accepts many coordinates at once, so all 63 parks cost one request, not 63.
    /// A failed request keeps the last forecast; nothing is ever filled in as clear.
    func forecasts(for parks: [Park], network: Bool, force: Bool = false) async -> [String: Forecast] {
        var result: [String: Forecast] = [:]
        var due: [Park] = []
        let now=clock()
        let allowed=backoff.allows(Self.host, now: now)
        for park in parks {
            load(park.id)
            let cached=memory[park.id]
            if let cached { result[park.id]=cached }
            // A forced refresh still waits ten minutes between requests for the same park.
            let age=cached.map { now.timeIntervalSince($0.updated) } ?? .infinity
            if network && allowed && (age>=6*3600 || (force && age>=600)) { due.append(park) }
        }
        var waits: [Task<[String: Forecast], Never>] = due.compactMap { inFlight[$0.id] }
        let fresh=due.filter { inFlight[$0.id] == nil }
        for start in stride(from: 0, to: fresh.count, by: 50) {
            let chunk=Array(fresh[start..<min(fresh.count, start+50)])
            let task=Task { () -> [String: Forecast] in
                var fetched: [String: Forecast] = [:]
                for (park, forecast) in await self.fetch(chunk) { fetched[park.id]=forecast }
                return fetched
            }
            for park in chunk { inFlight[park.id]=task }
            waits.append(task)
        }
        var seen=Set<Task<[String: Forecast], Never>>()
        for task in waits where seen.insert(task).inserted {
            for (id, forecast) in await task.value {
                if memory[id].map({ $0.updated < forecast.updated }) ?? true {
                    memory[id]=forecast
                    if persist, let park=due.first(where: { $0.id == id }) { CacheDirectory.write(forecast, name: "weather-\(park.id)") }
                }
                if due.contains(where: { $0.id == id }) { result[id]=memory[id] }
            }
        }
        for park in fresh where inFlight[park.id] != nil { inFlight[park.id]=nil }
        return result
    }
    private func fetch(_ parks: [Park]) async -> [(Park, Forecast)] {
        guard !parks.isEmpty else { return [] }
        var parts=URLComponents()
        parts.scheme="https"; parts.host="api.open-meteo.com"; parts.path="/v1/forecast"
        // Hours start at 00:00 UTC; yesterday's hours keep an eastern park's night in progress covered.
        // Fifteen days ahead plus yesterday is sixteen days of hours (verified 2026-10-07), the
        // forecast's full useful range, at a lower call weight than sixteen plus one.
        parts.queryItems=[URLQueryItem(name: "latitude", value: parks.map { String($0.forecastPoint.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: parks.map { String($0.forecastPoint.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "cloud_cover"), URLQueryItem(name: "forecast_days", value: "15"), URLQueryItem(name: "past_days", value: "1"),
            URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "GMT")]
        guard let url=parts.url else { return [] }
        struct Response: Decodable { struct Hourly: Decodable { let time: [Double]; let cloud_cover: [Double?] }; let hourly: Hourly }
        let data: Data
        do { data=try await transport.get(url, headers: [:], constrained: true) } catch {
            backoff.record(error, host: Self.host, now: clock())
            return []
        }
        // One coordinate returns an object; several return an array in request order.
        let decoded=(try? JSONDecoder().decode([Response].self, from: data)) ?? (try? JSONDecoder().decode(Response.self, from: data)).map { [$0] } ?? []
        guard decoded.count == parks.count else { return [] }
        let now=clock()
        return zip(parks, decoded).compactMap { park, response in
            guard response.hourly.time.count == response.hourly.cloud_cover.count, !response.hourly.time.isEmpty else { return nil }
            return (park, Forecast(updated: now, times: response.hourly.time, clouds: response.hourly.cloud_cover))
        }
    }
}
nonisolated protocol DetailProviding: Sendable {
    /// `weather` and `smoke` are the two switches in Your privacy: forecast detail comes from
    /// the forecast host, aerosols from the air-quality host.
    func details(for parks: [Park], weather: Bool, smoke: Bool, force: Bool) async -> [String: ForecastDetail]
    /// The cached detail, read once from disk off the main actor at launch.
    func hydrate(_ parks: [Park]) async -> [String: ForecastDetail]
    /// Detail already read at launch (`CachePreload`).
    func seed(_ cached: [String: ForecastDetail], parks: [Park]) async
    /// True when the last detail request was held back by Low Data Mode.
    func pausedForLowData() async -> Bool
}
/// The forecast's context, beside the score's own clouds: three models' clouds, cloud layers,
/// cold, dew, wind and visibility (seven days), and the aerosol forecast that warns of smoke.
/// Like clouds, every park shares each request, so a refresh is three more requests (two chunks
/// each for 63 parks), never one per park, and none of them hints at where someone is. Each part
/// keeps its own twelve-hour freshness; a failed request keeps the last good part. Detail never
/// uses a Low Data Mode network: it is context, and the score's clouds still arrive.
actor ForecastDetailService: DetailProviding {
    enum Kind: CaseIterable, Sendable {
        case models, layers, air
        var host: String { self == .air ? "air-quality-api.open-meteo.com" : "api.open-meteo.com" }
    }
    /// Detail is context for the week ahead; twice a day keeps it current at a quarter of the calls.
    static let freshFor: TimeInterval=12*3600
    private let transport: any HTTPTransport
    private let persist: Bool
    private let backoff: HostBackoff
    private let clock: @Sendable () -> Date
    private var memory: [String: ForecastDetail] = [:]
    private var loaded=Set<String>()
    private var lowData=false
    /// A refresh already under way; later callers wait for it instead of asking again.
    private var running: Task<Void, Never>?
    init(transport: any HTTPTransport = SafeHTTP(), persist: Bool = true, backoff: HostBackoff? = nil, clock: @escaping @Sendable () -> Date = { .now }) {
        self.transport=transport; self.persist=persist; self.clock=clock
        self.backoff=backoff ?? (persist ? .shared : HostBackoff(file: nil))
    }
    func hydrate(_ parks: [Park]) async -> [String: ForecastDetail] {
        for park in parks { load(park.id) }
        return memory
    }
    func seed(_ cached: [String: ForecastDetail], parks: [Park]) {
        for park in parks where loaded.insert(park.id).inserted && memory[park.id] == nil { memory[park.id]=cached[park.id] }
    }
    func pausedForLowData() -> Bool { lowData }
    private func load(_ id: String) {
        guard loaded.insert(id).inserted, memory[id] == nil, persist, let cached=CacheDirectory.read(ForecastDetail.self, name: "detail-\(id)") else { return }
        memory[id]=cached
    }
    func details(for parks: [Park], weather: Bool, smoke: Bool, force: Bool = false) async -> [String: ForecastDetail] {
        for park in parks { load(park.id) }
        if let running { await running.value }
        else {
            let now=clock()
            var jobs: [(Kind, [Park])] = []
            for kind in Kind.allCases where (kind == .air ? smoke : weather) && backoff.allows(kind.host, now: now) {
                let due=parks.filter { park in
                    let age=Self.series(memory[park.id], kind).map { now.timeIntervalSince($0.updated) } ?? .infinity
                    return age>=Self.freshFor || (force && age>=600)
                }
                for start in stride(from: 0, to: due.count, by: 50) { jobs.append((kind, Array(due[start..<min(due.count, start+50)]))) }
            }
            if !jobs.isEmpty {
                let task=Task {
                    let results=await withTaskGroup(of: (Kind, [(String, HourlySeries)]?).self) { group in
                        for (kind, chunk) in jobs { group.addTask { (kind, await self.fetch(kind, chunk)) } }
                        var all: [(Kind, [(String, HourlySeries)]?)] = []
                        for await result in group { all.append(result) }
                        return all
                    }
                    self.store(results)
                    self.running=nil
                }
                running=task
                await task.value
            }
        }
        var result: [String: ForecastDetail] = [:]
        for park in parks { if let detail=memory[park.id] { result[park.id]=detail } }
        return result
    }
    /// A nil part was held back by Low Data Mode.
    private func store(_ results: [(Kind, [(String, HourlySeries)]?)]) {
        var changed=Set<String>()
        lowData=results.contains { $0.1 == nil }
        for (kind, fetched) in results {
            for (id, series) in fetched ?? [] {
                var detail=memory[id] ?? ForecastDetail()
                switch kind { case .models: detail.models=series; case .layers: detail.layers=series; case .air: detail.air=series }
                memory[id]=detail; changed.insert(id)
            }
        }
        if persist { for id in changed { if let detail=memory[id] { CacheDirectory.write(detail, name: "detail-\(id)") } } }
    }
    private static func series(_ detail: ForecastDetail?, _ kind: Kind) -> HourlySeries? {
        switch kind { case .models: detail?.models; case .layers: detail?.layers; case .air: detail?.air }
    }
    /// Nil when Low Data Mode held the request back; empty when it failed any other way.
    private func fetch(_ kind: Kind, _ parks: [Park]) async -> [(String, HourlySeries)]? {
        guard !parks.isEmpty else { return [] }
        var parts=URLComponents()
        parts.scheme="https"
        var items=[URLQueryItem(name: "latitude", value: parks.map { String($0.forecastPoint.latitude) }.joined(separator: ",")),
                   URLQueryItem(name: "longitude", value: parks.map { String($0.forecastPoint.longitude) }.joined(separator: ","))]
        let keys: [String]
        switch kind {
        case .models:
            parts.host="api.open-meteo.com"; parts.path="/v1/forecast"; keys=ForecastDetail.modelKeys
            items+=[URLQueryItem(name: "hourly", value: "cloud_cover"), URLQueryItem(name: "models", value: "gfs_seamless,ecmwf_ifs025,icon_seamless")]
        case .layers:
            parts.host="api.open-meteo.com"; parts.path="/v1/forecast"; keys=ForecastDetail.layerKeys
            items.append(URLQueryItem(name: "hourly", value: keys.joined(separator: ",")))
        case .air:
            // CAMS global covers every park, Alaska and American Samoa included.
            parts.host="air-quality-api.open-meteo.com"; parts.path="/v1/air-quality"; keys=ForecastDetail.airKeys
            items+=[URLQueryItem(name: "hourly", value: keys.joined(separator: ",")), URLQueryItem(name: "domains", value: "cams_global")]
        }
        parts.queryItems=items+[URLQueryItem(name: "forecast_days", value: "7"), URLQueryItem(name: "past_days", value: "1"),
                                URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "GMT")]
        guard let url=parts.url else { return [] }
        let data: Data
        do { data=try await transport.get(url, headers: [:], constrained: false) } catch {
            if Backoff.constrained(error) { return nil }
            backoff.record(error, host: kind.host, now: clock())
            return []
        }
        struct Response: Decodable { let hourly: [String: [Double?]] }
        // One coordinate returns an object; several return an array in request order.
        let decoded=(try? JSONDecoder().decode([Response].self, from: data)) ?? (try? JSONDecoder().decode(Response.self, from: data)).map { [$0] } ?? []
        guard decoded.count == parks.count else { return [] }
        let now=clock()
        return zip(parks, decoded).compactMap { park, response in
            guard let times=response.hourly["time"].map({ $0.compactMap { $0 } }), !times.isEmpty, times.count == response.hourly["time"]?.count else { return nil }
            var values: [String: [Double?]] = [:]
            for key in keys {
                guard let series=response.hourly[key], series.count == times.count else { return nil }
                values[key]=series
            }
            return (park.id, HourlySeries(updated: now, times: times, values: values))
        }
    }
}
nonisolated struct ParkEnrichment: Codable, Sendable {
    let updated: Date
    let alerts: [ParkAlert]
    let programs: [RangerProgram]
    let description: String?
    /// When programs were last fetched successfully; nil if they never were. Optional so
    /// caches written before this field still decode.
    var programsUpdated: Date?=nil
}
/// Every park's alerts from one request, keyed by NPS park code. A code present with no alerts
/// was checked and had none; a code missing was not in the request.
nonisolated struct ParkAlertsCache: Codable, Sendable, Equatable {
    let updated: Date
    let alerts: [String: [ParkAlert]]
}
/// One park's upcoming night-sky ranger programs.
nonisolated struct ProgramsCache: Codable, Sendable, Equatable {
    let updated: Date
    let programs: [RangerProgram]
}
/// The alerts every screen shares, and whether NPS is refusing requests right now (the shared
/// key's quota is spent, or the service is struggling), so the app can say so calmly.
nonisolated struct AlertsUpdate: Sendable, Equatable {
    let cache: ParkAlertsCache?
    let busy: Bool
}
nonisolated protocol ParkProviding: Sendable {
    /// One request for all the parks' alerts, fresh for six hours, shared by every screen.
    func alerts(for parks: [Park], key: String, network: Bool, force: Bool) async -> AlertsUpdate
    /// One park's night-sky programs, asked for only when its page is open, fresh for a day.
    func programs(for park: Park, key: String, network: Bool, force: Bool) async -> ProgramsCache?
    /// The cached alerts, read once from disk off the main actor at launch.
    func hydrate(_ parks: [Park]) async -> AlertsUpdate
    /// Alerts already read at launch (`CachePreload`).
    func seed(_ cached: ParkAlertsCache?) async
}
/// Every install shares one NPS key and its hourly quota (1,000 requests), so requests are spent
/// carefully. Alerts for all 63 parks arrive in one request every six hours, whichever screen asks
/// first, so a request never reveals which parks are near someone. Ranger programs are asked for
/// only when a park's page opens, and kept a day (they are scheduled weeks ahead). Even a forced
/// refresh waits ten minutes since the last success; one request at a time however many screens
/// ask; and none at all for a while after the server refuses one (`HostBackoff`, kept on disk).
actor ParkStore: ParkProviding {
    static let host="developer.nps.gov"
    private let transport: any HTTPTransport
    private let persist: Bool
    private let backoff: HostBackoff
    private let clock: @Sendable () -> Date
    private var alertCache: ParkAlertsCache?
    private var alertsLoaded=false
    private var alertsTask: Task<Bool, Never>?
    /// The last alerts request was refused (quota, a refused key, a server error).
    private var refused=false
    private var programCache: [String: ProgramsCache] = [:]
    private var programsLoaded=Set<String>()
    private var programTasks: [String: Task<Void, Never>] = [:]
    init(transport: any HTTPTransport = SafeHTTP(), persist: Bool = true, backoff: HostBackoff? = nil, clock: @escaping @Sendable () -> Date = { .now }) {
        self.transport=transport; self.persist=persist; self.clock=clock
        self.backoff=backoff ?? (persist ? .shared : HostBackoff(file: nil))
    }
    private var busy: Bool { refused || !backoff.allows(Self.host, now: clock()) }
    func hydrate(_ parks: [Park]) async -> AlertsUpdate {
        loadAlerts(parks)
        return AlertsUpdate(cache: alertCache, busy: busy)
    }
    /// The shared file, or (once, after an update from a version that kept one file per park)
    /// the last per-park alerts, so closures known offline are never forgotten by an upgrade.
    private func loadAlerts(_ parks: [Park]) {
        guard !alertsLoaded else { return }
        alertsLoaded=true
        guard persist, alertCache == nil else { return }
        alertCache=Self.stored(parks)
    }
    func seed(_ cached: ParkAlertsCache?) {
        guard !alertsLoaded else { return }
        alertsLoaded=true
        if alertCache == nil { alertCache=cached }
    }
    /// The alerts on disk: the shared file, or the per-park files of earlier versions.
    nonisolated static func stored(_ parks: [Park]) -> ParkAlertsCache? {
        if let shared=CacheDirectory.read(ParkAlertsCache.self, name: "alerts") { return shared }
        var alerts: [String: [ParkAlert]] = [:], oldest: Date?
        for park in parks {
            guard let old=CacheDirectory.read(ParkEnrichment.self, name: "park-\(park.id)") else { continue }
            alerts[park.apiCode]=old.alerts
            oldest=min(oldest ?? old.updated, old.updated)
        }
        return oldest.map { ParkAlertsCache(updated: $0, alerts: alerts) }
    }
    func alerts(for parks: [Park], key: String, network: Bool, force: Bool = false) async -> AlertsUpdate {
        loadAlerts(parks)
        guard network, Self.usable(key) else { return AlertsUpdate(cache: alertCache, busy: false) }
        // Another screen's request is on its way: wait for it, then decide again. The task clears
        // itself before it finishes, so a waiter never sees a request that has already ended.
        while let running=alertsTask { _=await running.value }
        guard Self.stale(alertCache?.updated, maxAge: 6*3600, force: force, now: clock()) else { return AlertsUpdate(cache: alertCache, busy: false) }
        guard backoff.allows(Self.host, now: clock()) else { return AlertsUpdate(cache: alertCache, busy: true) }
        let codes=Array(Set(parks.map(\.apiCode))).sorted(), ids=parks.map(\.id)
        let task=Task { () -> Bool in
            let ok=await self.fetchAlerts(codes: codes, parkIDs: ids, key: key)
            self.alertsTask=nil
            return ok
        }
        alertsTask=task
        _=await task.value
        return AlertsUpdate(cache: alertCache, busy: busy)
    }
    func programs(for park: Park, key: String, network: Bool, force: Bool = false) async -> ProgramsCache? {
        if persist, programsLoaded.insert(park.id).inserted, programCache[park.id] == nil {
            programCache[park.id]=CacheDirectory.read(ProgramsCache.self, name: "programs-\(park.id)")
        }
        guard network, Self.usable(key) else { return programCache[park.id] }
        while let running=programTasks[park.id] { await running.value }
        guard Self.stale(programCache[park.id]?.updated, maxAge: 24*3600, force: force, now: clock()), backoff.allows(Self.host, now: clock()) else { return programCache[park.id] }
        let task=Task {
            await self.fetchPrograms(park, key: key)
            self.programTasks[park.id]=nil
        }
        programTasks[park.id]=task
        await task.value
        return programCache[park.id]
    }
    /// A part is due once it is older than `maxAge`; even a forced refresh waits ten minutes
    /// since that part's last success.
    static func stale(_ updated: Date?, maxAge: TimeInterval, force: Bool, now: Date) -> Bool {
        guard let updated else { return true }
        let age=now.timeIntervalSince(updated)
        return age>=maxAge || (force && age>=600)
    }
    static func usable(_ key: String) -> Bool { !key.isEmpty && !key.contains("$(") }
    private func url(_ path: String, _ query: [(String, String)]) -> URL? {
        var c=URLComponents(); c.scheme="https"; c.host="developer.nps.gov"; c.path="/api/v1/\(path)"
        c.queryItems=query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return c.url
    }
    private func get<T: Decodable>(_ type: T.Type, _ url: URL?, key: String) async -> T? {
        guard let url else { return nil }
        do {
            let data=try await transport.get(url, headers: ["X-Api-Key": key], constrained: true)
            refused=false
            return try JSONDecoder().decode(type, from: data)
        } catch {
            if error is HTTPStatusError { refused=true }
            backoff.record(error, host: Self.host, now: clock())
            return nil
        }
    }
    /// Pages with `start` while NPS reports more than one page holds (it allows up to 500 a page).
    /// A request that fails part-way keeps the last complete set.
    private func fetchAlerts(codes: [String], parkIDs: [String], key: String) async -> Bool {
        struct Record: Decodable { let id: String; let title: String; let description: String; let category: String; let parkCode: String }
        struct Page: Decodable { let data: [Record]; let total: String? }
        var records: [Record] = []
        for _ in 0..<4 {
            guard let page=await get(Page.self, url("alerts", [("parkCode", codes.joined(separator: ",")), ("limit", "500"), ("start", String(records.count))]), key: key) else { return false }
            records+=page.data
            guard let total=page.total.flatMap(Int.init), records.count<total, !page.data.isEmpty else { break }
        }
        var alerts=Dictionary(uniqueKeysWithValues: codes.map { ($0, [ParkAlert]()) })
        for record in records {
            // One alert can name several parks ("acad,ever"); each gets it.
            for code in record.parkCode.lowercased().split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where alerts[code] != nil {
                alerts[code]?.append(ParkAlert(id: record.id, title: record.title, description: Self.plain(record.description), category: record.category))
            }
        }
        let fresh=ParkAlertsCache(updated: clock(), alerts: alerts)
        alertCache=fresh
        if persist {
            CacheDirectory.write(fresh, name: "alerts")
            // The per-park files of earlier versions are now superseded.
            for id in parkIDs { CacheDirectory.remove(name: "park-\(id)") }
        }
        return true
    }
    private func fetchPrograms(_ park: Park, key: String) async {
        struct Time: Decodable { let timestart: String?; let timeend: String? }
        struct Event: Decodable { let id: String; let title: String; let datestart: String; let description: String; let tags: [String]?; let dates: [String]?; let times: [Time]?; let location: String? }
        struct Page: Decodable { let data: [Event]; let total: String? }
        let today=park.isoDay(clock())
        func page(_ number: Int) async -> Page? {
            // Events page with pageSize, which the server caps at 50 whatever is asked for.
            await get(Page.self, url("events", [("parkCode", park.apiCode), ("dateStart", today), ("pageSize", String(Self.eventsPage)), ("pageNumber", String(number))]), key: key)
        }
        guard let first=await page(1) else { return }
        var events=first.data
        let pages=min(10, Int(ceil((Double(first.total ?? "0") ?? 0)/Double(Self.eventsPage))))
        if pages>1 {
            for number in 2...pages {
                guard let more=await page(number) else { return }
                events+=more.data
            }
        }
        let programs=events.filter { Self.isNightSky(title: $0.title, tags: $0.tags ?? []) }.flatMap { event in
            (event.dates ?? [event.datestart]).filter { $0 >= today }.map { day in RangerProgram(id: event.id+day, title: event.title, date: day, description: Self.plain(event.description),
                time: event.times?.first.flatMap { RangerProgram.timeRange(start: $0.timestart, end: $0.timeend) }, location: RangerProgram.place(event.location)) }
        }.sorted { $0.date<$1.date }
        let fresh=ProgramsCache(updated: clock(), programs: programs)
        programCache[park.id]=fresh
        if persist { CacheDirectory.write(fresh, name: "programs-\(park.id)") }
    }
    static let eventsPage=50
    /// A ranger program about the night sky, from its title and tags. "astronom" covers astronomy
    /// and astronomical; a telescope talk with no tags is still a night-sky program.
    static func isNightSky(title: String, tags: [String]) -> Bool {
        let text=(title+" "+tags.joined(separator: " ")).lowercased()
        return ["astronom","stargaz","night sky","night-sky","star party","star parties","telescope","milky way","dark sky","dark-sky","constellation","meteor"].contains(where: text.contains)
    }
    static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
    }
}
/// The offline caches (forecasts, forecast detail and park alerts for 63 parks, about 190 small
/// files), read on background threads from the first moment of launch, while the store opens and
/// the parks load on the main thread. The model takes them just before the first frame, so the
/// first screen shows exactly what it always did, and the services are seeded so no file is read twice.
nonisolated final class CachePreload: @unchecked Sendable {
    nonisolated struct Contents: Sendable {
        var forecasts: [String: Forecast]=[:]
        var details: [String: ForecastDetail]=[:]
        var alerts: ParkAlertsCache?
    }
    private let group=DispatchGroup()
    private let lock=NSLock()
    /// Written on the reading threads under `lock`, read only after `group` has finished.
    private var contents=Contents()
    static func start() -> CachePreload {
        let preload=CachePreload()
        preload.group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            preload.read()
            preload.group.leave()
        }
        return preload
    }
    private func read() {
        guard let parks=try? ParkData.load() else { return }
        DispatchQueue.concurrentPerform(iterations: parks.count) { index in
            let id=parks[index].id
            let forecast=CacheDirectory.read(Forecast.self, name: "weather-\(id)"), detail=CacheDirectory.read(ForecastDetail.self, name: "detail-\(id)")
            lock.withLock { contents.forecasts[id]=forecast; contents.details[id]=detail }
        }
        let alerts=ParkStore.stored(parks)
        lock.withLock { contents.alerts=alerts }
    }
    /// Waits for the reads to finish (they began at launch, so usually they already have).
    func wait() -> Contents {
        group.wait()
        return lock.withLock { contents }
    }
}
