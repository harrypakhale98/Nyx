import Foundation
import Synchronization

// The guarded transport and the cloud forecast client, shared by Nyx on iPhone and iPad (with the
// widgets, which read the cache) and by Nyx on Vision Pro. Park updates, forecast detail and the
// smoke forecast stay in DataServices.swift, which Vision Pro does not compile: its only requests
// are this file's cloud forecast and Haleakalā's summit cloud layers (`SummitLayerService`), both
// to api.open-meteo.com, behind one switch.

/// The cloud forecast's switch in Your privacy (on unless turned off), read by the transport
/// before any request to the forecast host.
nonisolated enum CloudForecastSwitch {
    static let key = "weatherEnabled"
    static func isOn(_ defaults: UserDefaults = .standard) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
}
/// Saved spots' cloud forecasts (G3): their own switch in Your privacy, on unless turned off, and
/// effective only while `CloudForecastSwitch` is on too. A saved spot is the one request that
/// carries a place the person chose rather than a public park, so it carries less: the spot's
/// coordinates rounded to 0.1° (about 11 km), clouds only, in a request of its own that never
/// mixes spots with the parks. Never the device's location, unless the person saved it as a spot.
/// Approved by the owner on 2026-10-11.
nonisolated enum SpotForecast {
    static let key = "spotForecastsEnabled"
    static func isOn(_ defaults: UserDefaults = .standard) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
    /// A point on the 0.1° grid, held as whole tenths of a degree so it is exact and compares exactly.
    nonisolated struct Point: Hashable, Sendable {
        let latitudeTenths: Int
        let longitudeTenths: Int
        /// The nearest grid point (halves away from zero); latitudes clamp to ±90°, longitudes wrap into −180…180°.
        /// Nil for a coordinate that is not a number.
        init?(latitude: Double, longitude: Double) {
            guard latitude.isFinite, longitude.isFinite else { return nil }
            latitudeTenths=min(900, max(-900, Int((latitude*10).rounded())))
            var lon=Int((longitude*10).rounded()) % 3600
            if lon > 1800 { lon -= 3600 } else if lon < -1800 { lon += 3600 }
            longitudeTenths=lon
        }
        var latitude: Double { Double(latitudeTenths)/10 }
        var longitude: Double { Double(longitudeTenths)/10 }
        /// "37.1", "-0.5", "180.0": always one decimal, written from the tenths, never from a float.
        static func text(_ tenths: Int) -> String { "\(tenths<0 ? "-" : "")\(abs(tenths)/10).\(abs(tenths)%10)" }
    }
    /// Each spot's grid point, and the distinct points in the order first seen: spots that round to
    /// the same point are asked about once.
    static func points(_ spots: [Park]) -> (points: [Point], byID: [String: Point]) {
        var points: [Point]=[], seen=Set<Point>(), byID: [String: Point]=[:]
        for spot in spots {
            guard let point=Point(latitude: spot.latitude, longitude: spot.longitude) else { continue }
            byID[spot.id]=point
            if seen.insert(point).inserted { points.append(point) }
        }
        return (points, byID)
    }
    /// The parks' cloud request with only rounded points in it: the same host, hours and fields,
    /// and nothing else (no name, no id, no zone).
    static func url(for points: [Point]) -> URL? {
        guard !points.isEmpty else { return nil }
        var parts=URLComponents()
        parts.scheme="https"; parts.host=WeatherService.host; parts.path="/v1/forecast"
        parts.queryItems=[URLQueryItem(name: "latitude", value: points.map { Point.text($0.latitudeTenths) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: points.map { Point.text($0.longitudeTenths) }.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "cloud_cover"), URLQueryItem(name: "forecast_days", value: "15"), URLQueryItem(name: "past_days", value: "1"),
            URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "GMT")]
        return parts.url
    }
    /// A place's forecast cache file: "weather-jotr" for a park, as always; "weather-pin-<uuid>" for a spot (no colon in a file name).
    static func cacheName(_ id: String) -> String { "weather-"+id.replacingOccurrences(of: ":", with: "-") }
}
/// World catalogue places' cloud forecasts (G4; owner's decision D3, 2026-10-11). A catalogue
/// place is never asked about alone: its forecast comes with every other catalogue place in the
/// same 10° × 10° tile of latitude and longitude, so a request names a region about the size of a
/// country, never the place being looked at, and never the device's position (only catalogue
/// coordinates, which are public and the same in every copy of Nyx, are ever sent). Tiles too sparse
/// to hide a place among others are asked about all together (`Regions`). A dense region is split into
/// requests of at most `maxPointsPerRequest`, by Wikidata number rather than by position, so each part
/// still spans the whole region. Same host, switch, hours and fields as the curated parks' request,
/// which stays as it was.
nonisolated enum CatalogForecast {
    static let tileDegrees = 10.0
    /// Owner's cap (D3): never more than 1,000 coordinates in one request.
    static let maxPointsPerRequest = 1_000
    /// At most this many catalogue points in one refresh: whole tiles, in the order their places were
    /// asked for, until the next tile would pass it (the first tile always goes). A very wide radius in
    /// a dense region then costs no more than about two requests' worth; places beyond it keep their
    /// cached forecast or their usual clouds, labelled as such.
    static let maxPointsPerRefresh = 2_000
    /// A 10° cell: rows from the south pole, columns from the antimeridian.
    nonisolated struct Tile: Hashable, Comparable, Sendable {
        let row: Int
        let column: Int
        init(row: Int, column: Int) { self.row = row; self.column = column }
        /// The tile holding a point; nil for a coordinate that is not a number. 90° N belongs to the
        /// last row and 180° E to the first column (the same meridian as 180° W).
        init?(latitude: Double, longitude: Double) {
            guard latitude.isFinite, longitude.isFinite else { return nil }
            let rows = Int(180/CatalogForecast.tileDegrees), columns = Int(360/CatalogForecast.tileDegrees)
            row = min(rows-1, max(0, Int(((latitude+90)/CatalogForecast.tileDegrees).rounded(.down))))
            var lon = (longitude+180).truncatingRemainder(dividingBy: 360)
            if lon < 0 { lon += 360 }
            column = min(columns-1, max(0, Int((lon/CatalogForecast.tileDegrees).rounded(.down))))
        }
        init?(_ place: Park) { self.init(latitude: place.latitude, longitude: place.longitude) }
        static func < (a: Tile, b: Tile) -> Bool { (a.row, a.column) < (b.row, b.column) }
        /// "-30,140": the tile's south-west corner in degrees, for tests and logs.
        var corner: String { "\(row*Int(CatalogForecast.tileDegrees)-90),\(column*Int(CatalogForecast.tileDegrees)-180)" }
    }
    /// The number of a `wd:Q…` id, for a stable order inside a tile; ids that are not one sort last.
    static func itemNumber(_ id: String) -> Int {
        guard id.hasPrefix(Place.catalogPrefix + "Q") else { return .max }
        return Int(id.dropFirst(Place.catalogPrefix.count + 1)) ?? .max
    }
    /// One tile's places as requests: every member, ordered by Wikidata number (then id), split into
    /// as few near-equal parts as keep each within `maxPointsPerRequest`. Deterministic for the same members.
    static func chunks(_ members: [Park], limit: Int = maxPointsPerRequest) -> [[Park]] {
        var seen = Set<String>()
        let ordered = members.filter { seen.insert($0.id).inserted }.sorted { (itemNumber($0.id), $0.id) < (itemNumber($1.id), $1.id) }
        guard !ordered.isEmpty, limit > 0 else { return [] }
        let parts = (ordered.count + limit - 1) / limit
        let base = ordered.count / parts, extra = ordered.count % parts
        var result: [[Park]] = [], start = 0
        for part in 0..<parts {
            let size = base + (part < extra ? 1 : 0)
            result.append(Array(ordered[start..<start+size]))
            start += size
        }
        return result
    }
    /// Below this many catalogue places a tile is too sparse to hide one among the others (a lone
    /// island park would be named by its own tile): every such tile is asked about together, as one
    /// region of the world's remote places (about 330 points today).
    static let minimumPoints = 8
    /// The fixed partition of the catalogue into what is requested together: each tile with at least
    /// `minimumPoints` places on its own, and every sparser tile in one shared region. It depends only
    /// on the bundled catalogue, never on the place viewed or where the person is.
    nonisolated struct Regions: Sendable {
        /// Each region's requests, whole and in order (`chunks`).
        let requests: [[[Park]]]
        /// The region of each tile that holds a catalogue place.
        let regionOfTile: [Tile: Int]
        static let empty = Regions([])
        init(_ catalog: [Park], minimum: Int = CatalogForecast.minimumPoints) {
            var byTile: [Tile: [Park]] = [:]
            for place in catalog where place.isCatalogPlace { if let tile = Tile(place) { byTile[tile, default: []].append(place) } }
            var requests: [[[Park]]] = [], regionOfTile: [Tile: Int] = [:], sparse: [Park] = [], sparseTiles: [Tile] = []
            for tile in byTile.keys.sorted() {
                let members = byTile[tile] ?? []
                if members.count >= minimum {
                    regionOfTile[tile] = requests.count
                    requests.append(CatalogForecast.chunks(members))
                } else { sparse += members; sparseTiles.append(tile) }
            }
            if !sparse.isEmpty {
                for tile in sparseTiles { regionOfTile[tile] = requests.count }
                requests.append(CatalogForecast.chunks(sparse))
            }
            self.requests = requests; self.regionOfTile = regionOfTile
        }
        /// The requests that cover `wanted`: for each catalogue place among them, in order, its whole
        /// region, each region once, within `budget` points (the first region always goes). Curated
        /// parks and saved spots among `wanted` are ignored: they have requests of their own.
        func plan(wanted: [Park], budget: Int = CatalogForecast.maxPointsPerRefresh) -> [[Park]] {
            var regions: [Int] = [], seen = Set<Int>()
            for place in wanted where place.isCatalogPlace {
                guard let tile = Tile(place), let region = regionOfTile[tile], seen.insert(region).inserted else { continue }
                regions.append(region)
            }
            var planned: [[Park]] = [], points = 0
            for region in regions {
                let count = requests[region].reduce(0) { $0 + $1.count }
                if !planned.isEmpty && points + count > budget { break }
                planned += requests[region]
                points += count
            }
            return planned
        }
    }
    /// The curated parks' request with these catalogue places' public coordinates: the same host,
    /// hours and fields, and nothing else (no name, id or zone).
    static func url(for places: [Park]) -> URL? {
        guard !places.isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = WeatherService.host; parts.path = "/v1/forecast"
        parts.queryItems = [URLQueryItem(name: "latitude", value: places.map { String($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: places.map { String($0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "cloud_cover"), URLQueryItem(name: "forecast_days", value: "15"), URLQueryItem(name: "past_days", value: "1"),
            URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "GMT")]
        return parts.url
    }
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
    /// The server's own `Retry-After`, in seconds from its answer, when it sent one.
    var retryAfter: TimeInterval?=nil
    /// The short reason in an error body (`{"error":true,"reason":"…"}`): Open-Meteo says there
    /// which of its limits was reached (`Backoff.Window`). Matched, never shown.
    var reason: String?=nil
    /// `Retry-After` as seconds or as an HTTP date; nil when absent or unreadable.
    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value=value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds=TimeInterval(value) { return seconds.isFinite && seconds>=0 ? seconds : nil }
        let format=DateFormatter()
        format.locale=Locale(identifier: "en_US_POSIX"); format.timeZone=TimeZone(identifier: "GMT")
        format.dateFormat="EEE, dd MMM yyyy HH:mm:ss zzz"
        return format.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
    /// The `reason` of a small JSON error body, if it has one.
    static func reason(in body: Data) -> String? {
        struct Body: Decodable { let reason: String? }
        guard body.count<=4096 else { return nil }
        return (try? JSONDecoder().decode(Body.self, from: body))?.reason.map { String($0.prefix(200)) }
    }
}
/// How long to leave a host alone after it refused a request. Without a hint: an hour after 429
/// (the NPS key is shared by every install, 1,000 requests an hour), fifteen minutes after a server
/// error, doubling with each refusal in a row. A `Retry-After` is honoured as given. Open-Meteo
/// names the limit it reached (per minute, hour or day, per network address, in fixed UTC windows,
/// verified in its server source on 2026-10-11), so Nyx waits for that window to reset. A little
/// jitter keeps devices refused together from returning together. A 3xx (a campground Wi-Fi
/// sign-in page), any other 4xx, being offline or a switch turned off never waits: the service
/// itself did not ask for less traffic. Nothing ever retries on its own; the next refresh asks.
nonisolated enum Backoff {
    static func delay(after error: any Error) -> TimeInterval? {
        guard let status=(error as? HTTPStatusError)?.status else { return nil }
        if status == 429 { return 3600 }
        return (500..<600).contains(status) ? 900 : nil
    }
    /// The longest Nyx ever waits on its own reckoning (a server's later reset is still honoured).
    static let longest: TimeInterval=24*3600
    /// The limit an Open-Meteo 429 names: its windows reset on the UTC minute, hour and day.
    enum Window: Equatable {
        case minute, hour, day, concurrent
        init?(_ reason: String?) {
            guard let reason=reason?.lowercased() else { return nil }
            if reason.contains("daily") { self = .day }
            else if reason.contains("hourly") { self = .hour }
            else if reason.contains("minutely") { self = .minute }
            else if reason.contains("concurrent") { self = .concurrent }
            else { return nil }
        }
        /// The next reset after `now` (UTC), for the windows that reset.
        func reset(after now: Date) -> Date {
            let length: TimeInterval = switch self { case .minute, .concurrent: 60; case .hour: 3600; case .day: 86400 }
            let t=now.timeIntervalSince1970
            return Date(timeIntervalSince1970: ((t/length).rounded(.down)+1)*length)
        }
        /// How far past the reset a device may return at most (`jitter` spreads them).
        var spread: TimeInterval { switch self { case .minute, .concurrent: 30; case .hour: 600; case .day: 1800 } }
    }
    /// The wait after the `strike`-th refusal in a row (1 for the first); `jitter` in 0..<1.
    static func wait(after error: any Error, strike: Int, now: Date, jitter: Double) -> TimeInterval? {
        guard let refusal=error as? HTTPStatusError, let base=delay(after: error) else { return nil }
        let doubling=pow(2, Double(min(max(strike, 1)-1, 10))), jitter=min(max(jitter, 0), 1)
        // The server's own time, never shortened, a few seconds more for the spread.
        if let after=refusal.retryAfter { return min(after, longest)+jitter*min(60, max(1, after*0.1)) }
        if refusal.status == 429, let window=Window(refusal.reason) {
            let reset=window.reset(after: now).timeIntervalSince(now)
            switch window {
            // Back at the next window, and a window later for every refusal in a row since.
            case .minute: return min(reset+60*(doubling-1), 3600)+jitter*window.spread
            case .hour: return min(reset+3600*(doubling-1), longest)+jitter*window.spread
            // The day's quota returns at midnight UTC, and not before.
            case .day: return reset+jitter*window.spread
            case .concurrent: return min(60*doubling, 3600)+jitter*window.spread
            }
        }
        // No hint: the base wait, doubling, a little shorter at random so returns spread out.
        let cap: TimeInterval=refusal.status == 429 ? longest : 6*3600
        return min(base*doubling, cap)*(1-0.2*jitter)
    }
    /// True when the request failed only because Low Data Mode keeps it off a constrained network.
    static func constrained(_ error: any Error) -> Bool {
        guard let error=error as? URLError else { return false }
        let reason=error.networkUnavailableReason ?? (error.userInfo[NSURLErrorNetworkUnavailableReasonKey] as? Int).flatMap(URLError.NetworkUnavailableReason.init(rawValue:))
        return reason == .constrained
    }
}
/// When each host may be asked again after refusing a request, and how many refusals in a row it
/// has made. Kept on disk, so a quota refusal survives a relaunch instead of every cold launch
/// asking again at once. Per host: the forecast, air-quality and park services refuse independently.
nonisolated final class HostBackoff: Sendable {
    nonisolated struct Hold: Codable, Sendable, Equatable {
        var until: Date
        var strikes: Int
    }
    private let state: Mutex<[String: Hold]>
    private let file: URL?
    private let random: @Sendable () -> Double
    /// `file` nil keeps the holds in memory only (tests, and services that do not persist).
    /// `random` (0..<1) spreads the waits; tests pin it.
    init(file: URL?, now: Date = .now, random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.file=file; self.random=random
        let data=file.flatMap { try? Data(contentsOf: $0) }
        // Earlier versions kept a date per host; it reads as a first refusal.
        let stored=data.flatMap { try? JSONDecoder().decode([String: Hold].self, from: $0) }
            ?? data.flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) }?.mapValues { Hold(until: $0, strikes: 1) } ?? [:]
        // A date further ahead than any backoff could set (a clock that moved) is not honoured;
        // one long past is no longer a streak.
        state=Mutex(stored.filter { $0.value.until<now.addingTimeInterval(Backoff.longest+2*3600) && $0.value.until>now.addingTimeInterval(-86400) })
    }
    static let shared=HostBackoff(file: CacheDirectory.url.appendingPathComponent("nyx-backoff.json"))
    func allows(_ host: String, now: Date = .now) -> Bool { state.withLock { now >= ($0[host]?.until ?? .distantPast) } }
    func retryAfter(_ host: String) -> Date? { state.withLock { $0[host]?.until } }
    func strikes(_ host: String) -> Int { state.withLock { $0[host]?.strikes ?? 0 } }
    /// Records a refusal; anything `Backoff` does not wait for is ignored. Refusals less than a day
    /// apart count as a streak, and each one in a streak waits longer (`Backoff.wait`).
    func record(_ error: any Error, host: String, now: Date = .now) {
        guard Backoff.delay(after: error) != nil else { return }
        let jitter=random()
        let snapshot=state.withLock { holds -> [String: Hold] in
            let previous=holds[host]
            let strikes=previous.map { now.timeIntervalSince($0.until)<86400 ? $0.strikes+1 : 1 } ?? 1
            let wait=Backoff.wait(after: error, strike: strikes, now: now, jitter: jitter) ?? 0
            holds[host]=Hold(until: max(previous?.until ?? .distantPast, now.addingTimeInterval(wait)), strikes: strikes)
            holds=holds.filter { $0.value.until>now.addingTimeInterval(-86400) }
            return holds
        }
        save(snapshot)
    }
    /// The host answered: its streak is over.
    func succeeded(_ host: String) {
        let snapshot=state.withLock { holds -> [String: Hold]? in holds.removeValue(forKey: host) == nil ? nil : holds }
        if let snapshot { save(snapshot) }
    }
    private func save(_ holds: [String: Hold]) {
        if let file, let data=try? JSONEncoder().encode(holds) { try? data.write(to: file, options: .atomic) }
    }
}
/// What Open-Meteo counts a request as. Its free service is limited in "calls", not requests, and
/// weighs each location of a request on its own: `max(1, v/10, v/10 × d/14)`, where `v` is the
/// number of weather variables times the number of models and `d` the days of data (forecast plus
/// past days). So every place in a request is at least one call, and a request for 63 parks is 63
/// calls. Read from Open-Meteo's server source (`ForecastApiResult.calculateQueryWeight`) on
/// 2026-10-11; see Research/open-meteo-usage.md.
nonisolated enum CallWeight {
    static func of(_ url: URL) -> Double {
        let items=URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        func list(_ name: String) -> [String] { value(name)?.split(separator: ",").map(String.init).filter { !$0.isEmpty } ?? [] }
        let locations=max(1, list("latitude").count)
        let variables=max(1, ["hourly", "daily", "current", "minutely_15"].reduce(0) { $0+list($1).count })
        let models=max(1, list("models").count)
        // Open-Meteo's defaults: seven days of forecast, five for air quality.
        let forecastDays=value("forecast_days").flatMap(Int.init) ?? (url.path.hasSuffix("air-quality") ? 5 : 7)
        let days=max(1, forecastDays+(value("past_days").flatMap(Int.init) ?? 0))
        let variableShare=Double(variables*models)/10
        return Double(locations)*max(1, variableShare, variableShare*Double(days)/14)
    }
}
/// This device's own ceiling on Open-Meteo calls, per host, in the same fixed UTC windows as the
/// service's limits (600 a minute, 5,000 an hour, 10,000 a day for each network address). Kept
/// well below them, because carriers and campground Wi-Fi put many devices behind one address.
/// Browsing the world (catalogue tiles) stops earlier than the parks' own forecast, so looking
/// around can never leave tonight's forecast without room.
nonisolated struct CallBudget: Sendable, Equatable {
    nonisolated struct Caps: Sendable, Equatable {
        let minute: Double
        let hour: Double
        let day: Double
    }
    /// The parks, saved spots, forecast detail and Haleakalā's summit layers.
    let essential: Caps
    /// World catalogue tiles.
    let browsing: Caps
    static let standard=CallBudget(essential: Caps(minute: 400, hour: 1_000, day: 3_000), browsing: Caps(minute: 300, hour: 700, day: 2_000))
}
/// Every Open-Meteo request this device made in the last day or so: when, to which host, and what
/// Open-Meteo counts it as (`CallWeight`). Kept in Application Support on this device and never
/// sent anywhere. It holds requests to the budget (`CallBudget`) and tells Your privacy how many
/// forecast requests went out today.
nonisolated final class CallLedger: Sendable {
    nonisolated struct Entry: Codable, Sendable, Equatable {
        let id: UUID
        let date: Date
        let host: String
        var calls: Double
    }
    private let state: Mutex<[Entry]>
    private let file: URL?
    /// `file` nil keeps the ledger in memory only (tests, and services that do not persist).
    init(file: URL?, now: Date = .now) {
        self.file=file
        let stored=file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        state=Mutex(stored.filter { $0.date>now.addingTimeInterval(-Self.kept) && $0.date<now.addingTimeInterval(3600) })
    }
    static let shared=CallLedger(file: CacheDirectory.url.appendingPathComponent("nyx-calls.json"))
    /// A little over a day: the UTC day and the local day both fit, whatever the time zone.
    static let kept: TimeInterval=50*3600
    /// The start of the UTC minute, hour or day holding `now`: the service's own windows.
    static func windowStart(_ now: Date, length: TimeInterval) -> Date {
        Date(timeIntervalSince1970: (now.timeIntervalSince1970/length).rounded(.down)*length)
    }
    /// Calls counted for `host` from `start` on.
    func used(_ host: String, since start: Date) -> Double {
        state.withLock { $0.reduce(0) { $1.host == host && $1.date >= start ? $0+$1.calls : $0 } }
    }
    /// Whether a request of `calls` fits every window. An empty window takes any one request, as
    /// the service does (it checks usage before a request, not its size), so no tile is ever out of reach.
    private static func fits(_ entries: [Entry], host: String, calls: Double, caps: CallBudget.Caps, now: Date) -> Bool {
        for (length, cap) in [(60.0, caps.minute), (3600.0, caps.hour), (86400.0, caps.day)] {
            let start=windowStart(now, length: length)
            let used=entries.reduce(0) { $1.host == host && $1.date >= start ? $0+$1.calls : $0 }
            if used>0 && used+calls>cap { return false }
        }
        return true
    }
    func allows(_ host: String, calls: Double, caps: CallBudget.Caps, now: Date = .now) -> Bool {
        state.withLock { Self.fits($0, host: host, calls: calls, caps: caps, now: now) }
    }
    /// Counts a request before it goes, so requests sent together cannot overrun the budget; nil
    /// (nothing counted) when it does not fit.
    func reserve(_ host: String, calls: Double, caps: CallBudget.Caps, now: Date = .now) -> UUID? {
        let id=UUID()
        let snapshot=state.withLock { entries -> [Entry]? in
            guard Self.fits(entries, host: host, calls: calls, caps: caps, now: now) else { return nil }
            entries=entries.filter { $0.date>now.addingTimeInterval(-Self.kept) }
            entries.append(Entry(id: id, date: now, host: host, calls: calls))
            return entries
        }
        guard let snapshot else { return nil }
        save(snapshot)
        return id
    }
    /// What the request finally counted as (a refused request is one call).
    func settle(_ id: UUID, calls: Double) {
        let snapshot=state.withLock { entries -> [Entry] in
            if let index=entries.firstIndex(where: { $0.id == id }) { entries[index].calls=calls }
            return entries
        }
        save(snapshot)
    }
    /// The request never reached the service (offline, a switch turned off, Low Data Mode).
    func cancel(_ id: UUID) {
        let snapshot=state.withLock { entries -> [Entry] in entries.removeAll { $0.id == id }; return entries }
        save(snapshot)
    }
    /// Requests to Open-Meteo's hosts since local midnight, and the calls they count as.
    func today(now: Date = .now, calendar: Calendar = .current) -> (requests: Int, calls: Double) {
        let start=calendar.startOfDay(for: now)
        return state.withLock { entries in
            let today=entries.filter { $0.date >= start && $0.host.hasSuffix("open-meteo.com") }
            return (today.count, today.reduce(0) { $0+$1.calls })
        }
    }
    private func save(_ entries: [Entry]) {
        if let file, let data=try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
    }
}
/// How long a forecast is used before it is asked for again, by what it is. Open-Meteo's models
/// update hourly (GFS and HRRR, behind the best-match forecast over the US), every three hours
/// (ICON), every six (ECMWF IFS) and every twelve (CAMS, the smoke forecast). In normal use clouds
/// are asked for once they are six hours old and forecast detail at twelve. Pulling to refresh asks
/// sooner, but never before the fastest model behind that forecast can have run again: an hour for
/// clouds, three hours for model comparison and layers, and never for smoke (CAMS runs twice a day).
nonisolated enum ForecastReuse {
    static let clouds: TimeInterval=6*3600
    static let cloudsForced: TimeInterval=3600
    static let detail: TimeInterval=12*3600
    static let detailForced: TimeInterval=3*3600
    static let airForced: TimeInterval=12*3600
    /// Due when older than `normal`, or with `force` older than `forced`; always when there is none.
    static func due(_ updated: Date?, now: Date, force: Bool, normal: TimeInterval, forced: TimeInterval) -> Bool {
        guard let updated else { return true }
        let age=now.timeIntervalSince(updated)
        return age>=normal || (force && age>=forced)
    }
}
/// One request to an Open-Meteo host, sent only while the host is not cooling down and the
/// request fits this device's budget; counted in the ledger, its refusal recorded. Never retried.
nonisolated enum ForecastRequest {
    /// Not sent: the service asked Nyx to wait, or this device's budget for now is spent.
    nonisolated struct HeldBack: Error {}
    static func get(_ url: URL, transport: any HTTPTransport, constrained: Bool, backoff: HostBackoff, ledger: CallLedger,
                    caps: CallBudget.Caps, clock: @Sendable () -> Date) async throws -> Data {
        guard let host=url.host else { throw URLError(.unsupportedURL) }
        let now=clock()
        guard backoff.allows(host, now: now), let ticket=ledger.reserve(host, calls: CallWeight.of(url), caps: caps, now: now) else { throw HeldBack() }
        do {
            let data=try await transport.get(url, headers: [:], constrained: constrained)
            backoff.succeeded(host)
            return data
        } catch {
            // Open-Meteo counts a request it answered with an error as one call; one that never reached it, as none.
            if error is HTTPStatusError { ledger.settle(ticket, calls: 1) } else { ledger.cancel(ticket) }
            backoff.record(error, host: host, now: clock())
            throw error
        }
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
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPStatusError(status: http.statusCode, retryAfter: HTTPStatusError.retryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: .now),
                                  reason: HTTPStatusError.reason(in: data))
        }
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
    /// Saved spots' clouds: cached, and with `network` refreshed in a request of their own
    /// (`SpotForecast`). Services without spots answer with nothing.
    func spotForecasts(for spots: [Park], network: Bool, force: Bool) async -> [String: Forecast]
    /// World catalogue places' clouds, by whole tiles (`CatalogForecast.Regions.plan`): every member of
    /// every request cached, and with `network` the requests that are due asked again. Services
    /// without a catalogue answer with nothing.
    func catalogForecasts(_ requests: [[Park]], network: Bool, force: Bool) async -> [String: Forecast]
    /// True when the parks' or spots' forecast was due but not asked for, because the service asked
    /// Nyx to wait or this device's budget was spent; false again once a request succeeds.
    func heldBack() async -> Bool
}
nonisolated extension WeatherProviding {
    func spotForecasts(for spots: [Park], network: Bool, force: Bool) async -> [String: Forecast] { [:] }
    func catalogForecasts(_ requests: [[Park]], network: Bool, force: Bool) async -> [String: Forecast] { [:] }
    func heldBack() async -> Bool { false }
    func forecast(for park: Park, network: Bool, force: Bool = false) async -> Forecast? {
        await forecasts(for: [park], network: network, force: force)[park.id]
    }
}
actor WeatherService: WeatherProviding {
    static let host="api.open-meteo.com"
    private let transport: any HTTPTransport
    private let persist: Bool
    private let backoff: HostBackoff
    private let ledger: CallLedger
    private let budget: CallBudget
    private let clock: @Sendable () -> Date
    private var memory: [String: Forecast] = [:]
    /// Parks whose cache file has been looked for, found or not, so no file is read twice.
    private var loaded=Set<String>()
    /// Requests already on their way, so Tonight, Parks and saved parks never fetch the same park twice at once.
    private var inFlight: [String: Task<[String: Forecast], Never>] = [:]
    /// How many callers are still waiting on each request in flight.
    private var waiters: [Task<[String: Forecast], Never>: Int] = [:]
    /// The saved spots' request under way, if any; later callers wait for it.
    private var spotFlight: Task<[String: Forecast], Never>?
    /// Catalogue tile requests under way, by their members; a caller asking for the same tile waits for it.
    private var catalogFlight: [String: Task<[String: Forecast], Never>] = [:]
    /// The parks' or spots' forecast was due and held back (`heldBack()`).
    private var held=false
    /// Where the spots' switch is read; tests use their own suite.
    private let suite: String?
    init(transport: any HTTPTransport = SafeHTTP(), persist: Bool = true, backoff: HostBackoff? = nil, suite: String? = nil,
         ledger: CallLedger? = nil, budget: CallBudget = .standard, clock: @escaping @Sendable () -> Date = { .now }) {
        self.transport=transport; self.persist=persist; self.clock=clock; self.suite=suite; self.budget=budget
        self.backoff=backoff ?? (persist ? .shared : HostBackoff(file: nil))
        self.ledger=ledger ?? (persist ? .shared : CallLedger(file: nil))
    }
    func hydrate(_ parks: [Park]) async -> [String: Forecast] {
        for park in parks { load(park.id) }
        return memory
    }
    func seed(_ cached: [String: Forecast], parks: [Park]) {
        for park in parks where loaded.insert(park.id).inserted && memory[park.id] == nil { memory[park.id]=cached[park.id] }
    }
    /// Async, as the protocol declares it, so it is this method (not the protocol's default) that answers.
    func heldBack() async -> Bool { held }
    private func load(_ id: String) {
        guard loaded.insert(id).inserted, memory[id] == nil, persist, let cached=CacheDirectory.read(Forecast.self, name: SpotForecast.cacheName(id)) else { return }
        memory[id]=cached
    }
    /// Cached forecasts for every park, refreshed in as few requests as possible: Open-Meteo
    /// accepts many coordinates at once, so all 63 parks cost two requests, not 63 (though
    /// Open-Meteo still counts each park as a call, `CallWeight`). The requests go one after the
    /// other, never side by side. A failed request keeps the last forecast; nothing is ever filled
    /// in as clear. Due at six hours, or at an hour when pulled to refresh (`ForecastReuse`).
    func forecasts(for parks: [Park], network: Bool, force: Bool = false) async -> [String: Forecast] {
        var result: [String: Forecast] = [:]
        var due: [Park] = []
        let now=clock()
        for park in parks {
            load(park.id)
            let cached=memory[park.id]
            if let cached { result[park.id]=cached }
            if network && ForecastReuse.due(cached?.updated, now: now, force: force, normal: ForecastReuse.clouds, forced: ForecastReuse.cloudsForced) { due.append(park) }
        }
        // The service asked Nyx to wait: the cached forecasts, and say so.
        if !due.isEmpty && !backoff.allows(Self.host, now: now) { held=true; due=[] }
        var waits: [Task<[String: Forecast], Never>] = due.compactMap { inFlight[$0.id] }
        let fresh=due.filter { inFlight[$0.id] == nil }
        if !fresh.isEmpty {
            let chunks=stride(from: 0, to: fresh.count, by: 50).map { Array(fresh[$0..<min(fresh.count, $0+50)]) }
            let task=Task { () -> [String: Forecast] in
                var fetched: [String: Forecast] = [:]
                for chunk in chunks {
                    guard !Task.isCancelled else { break }
                    guard let part=await self.fetch(chunk, caps: self.budget.essential) else { break }
                    // Kept by the request itself, not by whoever waits: a forecast that arrives after
                    // every caller stopped waiting still counts.
                    var kept: [String: Forecast] = [:]
                    for (park, forecast) in part { kept[park.id]=forecast }
                    self.keep(kept)
                    fetched.merge(kept) { _, new in new }
                }
                return fetched
            }
            for park in fresh { inFlight[park.id]=task }
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
    /// Saved spots' clouds (G3), kept and refreshed as the parks' are (`ForecastReuse`, the same
    /// cache, backoff, budget and guarded transport), but never in the parks' request: one request
    /// of their own (two past fifty distinct points) carrying only each spot's coordinates rounded
    /// to 0.1°, the same rounded point asked once. Asked only with `network` and the spots' switch
    /// on (`SpotForecast`); otherwise the cached forecasts, or none, and each night falls back to
    /// the usual clouds from the world grid, as for any place.
    func spotForecasts(for spots: [Park], network: Bool, force: Bool = false) async -> [String: Forecast] {
        func kept() -> [String: Forecast] {
            var result: [String: Forecast]=[:]
            for spot in spots { if let kept=memory[spot.id] { result[spot.id]=kept } }
            return result
        }
        for spot in spots { load(spot.id) }
        let defaults=suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        guard network && SpotForecast.isOn(defaults) else { return kept() }
        // Another request is on its way (perhaps for other spots): wait for it, then decide again
        // what is due. A cancelled caller stops waiting and returns what is kept.
        while let running=spotFlight {
            guard await SharedRequest.value(of: running) != nil else { return kept() }
        }
        let now=clock()
        var due=spots.filter { ForecastReuse.due(memory[$0.id]?.updated, now: now, force: force, normal: ForecastReuse.clouds, forced: ForecastReuse.cloudsForced) }
        if !due.isEmpty && !backoff.allows(Self.host, now: now) { held=true; due=[] }
        if !due.isEmpty {
            let task=Task {
                let fetched=await self.fetchSpots(due)
                // Kept by the request itself, so a forecast that arrives after its caller stopped waiting still counts.
                self.keep(fetched)
                self.spotFlight=nil
                return fetched
            }
            spotFlight=task
            _=await SharedRequest.value(of: task)
        }
        return kept()
    }
    /// World catalogue places' clouds (G4), by whole tiles: `requests` comes from
    /// `CatalogForecast.Regions.plan`, each one every catalogue place of a 10° tile (or of the sparse
    /// tiles together, or a part of a dense region), never a place alone. Cached and kept as the
    /// parks' are (`ForecastReuse`, the same cache files by id, backoff and guarded transport). A
    /// request is due when its freshest member is (they arrive together); due requests go one after
    /// another, within the browsing budget (`CallBudget.browsing`), and the first that fails or does
    /// not fit stops the rest, so scrolling the world can never send a burst. Returns every member's
    /// kept forecast; places left out keep their last forecast or their usual clouds, labelled.
    func catalogForecasts(_ requests: [[Park]], network: Bool, force: Bool = false) async -> [String: Forecast] {
        let now=clock()
        var due: [[Park]]=[]
        for request in requests {
            for place in request { load(place.id) }
            guard network, !request.isEmpty, request.count <= CatalogForecast.maxPointsPerRequest else { continue }
            let newest=request.compactMap { memory[$0.id]?.updated }.max()
            if ForecastReuse.due(newest, now: now, force: force, normal: ForecastReuse.clouds, forced: ForecastReuse.cloudsForced) { due.append(request) }
        }
        for request in due {
            guard backoff.allows(Self.host, now: clock()) else { break }
            let key=request.map(\.id).joined(separator: ",")
            let task: Task<[String: Forecast], Never>
            if let running=catalogFlight[key] { task=running } else {
                task=Task {
                    var fetched: [String: Forecast]=[:]
                    for (place, forecast) in await self.fetch(request, url: CatalogForecast.url(for: request), caps: self.budget.browsing) ?? [] { fetched[place.id]=forecast }
                    // Kept by the request itself, so a forecast that arrives after its caller stopped waiting still counts.
                    self.keep(fetched)
                    self.catalogFlight[key]=nil
                    return fetched
                }
                catalogFlight[key]=task
            }
            // A cancelled caller stops waiting; a request that brought nothing (offline, refused, over budget) ends the round.
            guard let fetched=await SharedRequest.value(of: task), !fetched.isEmpty else { break }
        }
        var result: [String: Forecast]=[:]
        for request in requests { for place in request { if let kept=memory[place.id] { result[place.id]=kept } } }
        return result
    }
    private func fetchSpots(_ spots: [Park]) async -> [String: Forecast] {
        let grid=SpotForecast.points(spots)
        var byPoint: [SpotForecast.Point: Forecast]=[:]
        for start in stride(from: 0, to: grid.points.count, by: 50) {
            let chunk=Array(grid.points[start..<min(grid.points.count, start+50)])
            guard let url=SpotForecast.url(for: chunk) else { continue }
            let data: Data
            do { data=try await ForecastRequest.get(url, transport: transport, constrained: true, backoff: backoff, ledger: ledger, caps: budget.essential, clock: clock) } catch {
                if error is ForecastRequest.HeldBack { held=true }
                break
            }
            held=false
            struct Response: Decodable { struct Hourly: Decodable { let time: [Double]; let cloud_cover: [Double?] }; let hourly: Hourly }
            // One coordinate returns an object; several return an array in request order.
            let decoded=(try? JSONDecoder().decode([Response].self, from: data)) ?? (try? JSONDecoder().decode(Response.self, from: data)).map { [$0] } ?? []
            guard decoded.count == chunk.count else { continue }
            let now=clock()
            for (point, response) in zip(chunk, decoded) where response.hourly.time.count == response.hourly.cloud_cover.count && !response.hourly.time.isEmpty {
                byPoint[point]=Forecast(updated: now, times: response.hourly.time, clouds: response.hourly.cloud_cover)
            }
        }
        return grid.byID.compactMapValues { byPoint[$0] }
    }
    private func keep(_ fetched: [String: Forecast]) {
        for (id, forecast) in fetched where memory[id].map({ $0.updated < forecast.updated }) ?? true {
            memory[id]=forecast
            if persist { CacheDirectory.write(forecast, name: SpotForecast.cacheName(id)) }
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
    /// `given`: the catalogue's request for exactly these places (`CatalogForecast.url`); the parks' otherwise.
    /// Nil when the request was not sent (`ForecastRequest.HeldBack`); empty when it failed or could not be read.
    private func fetch(_ parks: [Park], url given: URL? = nil, caps: CallBudget.Caps) async -> [(Park, Forecast)]? {
        guard !parks.isEmpty else { return [] }
        var parts=URLComponents()
        parts.scheme="https"; parts.host="api.open-meteo.com"; parts.path="/v1/forecast"
        // Hours start at 00:00 UTC; yesterday's hours keep an eastern park's night in progress covered.
        // Fifteen days ahead plus yesterday is sixteen days of hours (verified 2026-10-07), the
        // forecast's full useful range; one variable over sixteen days is one call a place.
        parts.queryItems=[URLQueryItem(name: "latitude", value: parks.map { String($0.forecastPoint.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: parks.map { String($0.forecastPoint.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "cloud_cover"), URLQueryItem(name: "forecast_days", value: "15"), URLQueryItem(name: "past_days", value: "1"),
            URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "GMT")]
        guard let url=given ?? parts.url else { return [] }
        struct Response: Decodable { struct Hourly: Decodable { let time: [Double]; let cloud_cover: [Double?] }; let hourly: Hourly }
        let data: Data
        let curated=given == nil
        do { data=try await ForecastRequest.get(url, transport: transport, constrained: true, backoff: backoff, ledger: ledger, caps: caps, clock: clock) } catch {
            if error is ForecastRequest.HeldBack {
                // Only the parks' own forecast says it is waiting; places abroad keep their labels.
                if curated { held=true }
                return nil
            }
            return []
        }
        if curated { held=false }
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
/// The cloud layers over a summit that sits above the trade-wind inversion (`Park.aboveInversion`,
/// Haleakalā alone), for Nyx on Vision Pro, which has no forecast detail service: the iPhone scores
/// that park from mid and high cloud (`NightPlanner.night`), and these two layers let Vision Pro
/// score it the same way. One small request, at most every twelve hours, carrying only the
/// summit's public viewing-spot coordinates: same host, same switch, same guarded transport and
/// backoff as the cloud forecast. Seven days ahead plus yesterday, as the iPhone's layer forecast,
/// so nights past its reach use the summit's usual clouds on both. Kept on disk beside the forecast;
/// a failed request keeps the last layers, and without any the score counts the usual clouds (never
/// the total cloud, which the low inversion cloud below the summit dominates).
/// The iPhone never asks for these: its layers come with forecast detail (DataServices.swift).
actor SummitLayerService {
    static let keys=["cloud_cover_mid","cloud_cover_high"]
    /// The iPhone's layer freshness (`ForecastDetailService.freshFor`): the layers are the summit's
    /// clouds, eased toward its usual clouds as they age, so they are asked for again at this age.
    static let freshFor: TimeInterval=12*3600
    private let transport: any HTTPTransport
    private let persist: Bool
    private let backoff: HostBackoff
    private let ledger: CallLedger
    private let budget: CallBudget
    private let clock: @Sendable () -> Date
    private var memory: [String: HourlySeries] = [:]
    /// Parks whose cache file has been looked for, found or not, so no file is read twice.
    private var loaded=Set<String>()
    /// A request already under way; later callers wait for it instead of asking again.
    private var running: Task<Void, Never>?
    init(transport: any HTTPTransport = SafeHTTP(), persist: Bool = true, backoff: HostBackoff? = nil, ledger: CallLedger? = nil,
         budget: CallBudget = .standard, clock: @escaping @Sendable () -> Date = { .now }) {
        self.transport=transport; self.persist=persist; self.clock=clock; self.budget=budget
        self.backoff=backoff ?? (persist ? .shared : HostBackoff(file: nil))
        self.ledger=ledger ?? (persist ? .shared : CallLedger(file: nil))
    }
    /// The cached layers for the summits among `parks`, and with `network` a refresh of those
    /// twelve hours old. Parks below the inversion are never asked about.
    func layers(for parks: [Park], network: Bool) async -> [String: HourlySeries] {
        let summits=parks.filter { $0.aboveInversion == true }
        for park in summits { load(park.id) }
        // Another request is on its way (perhaps for other summits): wait for it, then decide again
        // what is due. A cancelled caller stops waiting and returns what is kept; the request
        // finishes and stores itself.
        while network, let running {
            guard await SharedRequest.value(of: running) != nil else { return kept(summits) }
        }
        if network {
            let now=clock()
            let due=summits.filter { park in (memory[park.id].map { now.timeIntervalSince($0.updated) } ?? .infinity) >= Self.freshFor }
            if !due.isEmpty, backoff.allows(WeatherService.host, now: now) {
                let task=Task {
                    self.keep(await self.fetch(due))
                    self.running=nil
                }
                running=task
                _=await SharedRequest.value(of: task)
            }
        }
        return kept(summits)
    }
    private func kept(_ summits: [Park]) -> [String: HourlySeries] {
        var result: [String: HourlySeries] = [:]
        for park in summits { if let series=memory[park.id] { result[park.id]=series } }
        return result
    }
    private func load(_ id: String) {
        guard loaded.insert(id).inserted, memory[id] == nil, persist, let cached=CacheDirectory.read(HourlySeries.self, name: "summit-\(id)") else { return }
        memory[id]=cached
    }
    private func keep(_ fetched: [(String, HourlySeries)]) {
        for (id, series) in fetched where memory[id].map({ $0.updated < series.updated }) ?? true {
            memory[id]=series
            if persist { CacheDirectory.write(series, name: "summit-\(id)") }
        }
    }
    /// `hourly=cloud_cover_mid,cloud_cover_high&forecast_days=7&past_days=1&timeformat=unixtime&timezone=GMT`
    /// at each summit's `forecastPoint`.
    static func url(for parks: [Park]) -> URL? {
        guard !parks.isEmpty else { return nil }
        var parts=URLComponents()
        parts.scheme="https"; parts.host="api.open-meteo.com"; parts.path="/v1/forecast"
        parts.queryItems=[URLQueryItem(name: "latitude", value: parks.map { String($0.forecastPoint.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: parks.map { String($0.forecastPoint.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: keys.joined(separator: ",")), URLQueryItem(name: "forecast_days", value: "7"), URLQueryItem(name: "past_days", value: "1"),
            URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "GMT")]
        return parts.url
    }
    /// Empty when the request failed or its answer could not be read whole.
    private func fetch(_ parks: [Park]) async -> [(String, HourlySeries)] {
        guard let url=Self.url(for: parks) else { return [] }
        let data: Data
        // Low Data Mode is allowed, as for the cloud forecast: on Vision Pro these layers are the score's clouds.
        do { data=try await ForecastRequest.get(url, transport: transport, constrained: true, backoff: backoff, ledger: ledger, caps: budget.essential, clock: clock) } catch {
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
            for key in Self.keys {
                guard let series=response.hourly[key], series.count == times.count else { return nil }
                values[key]=series
            }
            return (park.id, HourlySeries(updated: now, times: times, values: values))
        }
    }
}
