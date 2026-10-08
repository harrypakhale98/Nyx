import Foundation
import Synchronization

// The guarded transport and the cloud forecast client, shared by Nyx on iPhone and iPad (with the
// widgets, which read the cache) and by Nyx on Vision Pro. Park updates, forecast detail and the
// smoke forecast stay in DataServices.swift, which Vision Pro does not compile: its only request
// is this file's cloud forecast, to api.open-meteo.com, behind its own switch.

/// The cloud forecast's switch in Your privacy (on unless turned off), read by the transport
/// before any request to the forecast host.
nonisolated enum CloudForecastSwitch {
    static let key = "weatherEnabled"
    static func isOn(_ defaults: UserDefaults = .standard) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
}
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
/// approval) the aerosol forecast that warns of smoke. Nyx on Vision Pro reaches only the
/// forecast host (`SafeHTTP.preferences`).
nonisolated final class HostGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
nonisolated struct SafeHTTP: HTTPTransport {
    /// Each host and the preference that must not be off before it is contacted. On Vision Pro
    /// (approved 2026-10-07) only the cloud forecast: the other two hosts are not even compiled
    /// into that app, so no code path there can name them (`Scripts/verify_release.py` checks).
    #if os(visionOS)
    static let preferences: [String: String] = ["api.open-meteo.com": CloudForecastSwitch.key]
    #else
    static let preferences: [String: String] = ["developer.nps.gov": "npsEnabled", "api.open-meteo.com": CloudForecastSwitch.key,
                                                 "air-quality-api.open-meteo.com": "smokeEnabled"]
    #endif
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
    /// Why a request may not be made, decided before any connection: `.unsupportedURL` for anything
    /// but HTTPS to the listed hosts, `.cancelled` when that host's switch is off; nil when allowed.
    static func refusal(_ url: URL, defaults: UserDefaults) -> URLError.Code? {
        guard url.scheme == "https", let host=url.host, let preference=preferences[host] else { return .unsupportedURL }
        return defaults.object(forKey: preference) as? Bool == false ? .cancelled : nil
    }
    func get(_ url: URL, headers: [String: String], constrained: Bool) async throws -> Data {
        let defaults=suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        // Checked before any connection is made: a switch turned off means no request at all.
        if let refusal=Self.refusal(url, defaults: defaults) { throw URLError(refusal) }
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
/// Waiting on a request that several callers share (`WeatherService`, `ParkStore`). A cancelled
/// caller stops waiting at once and gets nil, without cancelling the request for the others; the
/// service decides whether anyone is still waiting.
nonisolated enum SharedRequest {
    static func value<T: Sendable>(of task: Task<T, Never>) async -> T? {
        let waiter=Waiter<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.set(continuation)
                Task { waiter.resume(await task.value) }
                // Cancelled before the continuation was set: the handler below found nothing to resume.
                if Task.isCancelled { waiter.resume(nil) }
            }
        } onCancel: {
            waiter.resume(nil)
        }
    }
    /// Resumes its continuation once, with the value or with nil, whichever comes first.
    private final class Waiter<T: Sendable>: Sendable {
        private let state=Mutex<CheckedContinuation<T?, Never>?>(nil)
        func set(_ continuation: CheckedContinuation<T?, Never>) { state.withLock { $0=continuation } }
        func resume(_ value: T?) { state.withLock { $0.take() }?.resume(returning: value) }
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
    /// How many callers are still waiting on each request in flight.
    private var waiters: [Task<[String: Forecast], Never>: Int] = [:]
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
                // Kept by the request itself, not by whoever waits: a forecast that arrives after
                // every caller stopped waiting still counts.
                self.keep(fetched)
                return fetched
            }
            for park in chunk { inFlight[park.id]=task }
            waits.append(task)
        }
        var seen=Set<Task<[String: Forecast], Never>>()
        let shared=waits.filter { seen.insert($0).inserted }
        for task in shared { waiters[task, default: 0]+=1 }
        for task in shared {
            // A cancelled caller (a background refresh out of time) stops waiting at once and
            // returns what is cached; the request goes on for anyone else still waiting.
            let fetched=await SharedRequest.value(of: task)
            leave(task, finished: fetched != nil)
            for id in (fetched ?? [:]).keys where due.contains(where: { $0.id == id }) { result[id]=memory[id] }
        }
        return result
    }
    private func keep(_ fetched: [String: Forecast]) {
        for (id, forecast) in fetched where memory[id].map({ $0.updated < forecast.updated }) ?? true {
            memory[id]=forecast
            if persist { CacheDirectory.write(forecast, name: "weather-\(id)") }
        }
    }
    /// One caller has stopped waiting. A finished request leaves `inFlight`; one nobody waits for
    /// any more is cancelled, so a background refresh out of time leaves nothing running.
    private func leave(_ task: Task<[String: Forecast], Never>, finished: Bool) {
        let remaining=(waiters[task] ?? 1)-1
        waiters[task]=remaining>0 ? remaining : nil
        guard finished || remaining == 0 else { return }
        if !finished { task.cancel() }
        inFlight=inFlight.filter { $0.value != task }
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
