import Foundation

nonisolated protocol HTTPTransport: Sendable {
    func get(_ url: URL) async throws -> Data
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
    var suite: String? = nil
    func get(_ url: URL) async throws -> Data {
        guard url.scheme == "https", let host = url.host, let preference = Self.preferences[host] else { throw URLError(.unsupportedURL) }
        let defaults = suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        guard defaults.object(forKey: preference) as? Bool != false else { throw URLError(.cancelled) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: HostGuard(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data,response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
}
/// The last forecasts and park updates. Application Support, not Caches: iOS empties Caches when
/// storage runs low, and these files are what keep clouds and closures available offline. They are
/// excluded from backup because they can always be fetched again.
nonisolated enum CacheDirectory {
    static let url: URL = {
        let manager = FileManager.default
        guard var folder = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Offline", isDirectory: true),
              (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return legacy }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return folder
    }()
    /// Where earlier versions kept these files; still read until the next successful update.
    private static var legacy: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    }
    static func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        let file = "nyx-\(name).json"
        guard let data = (try? Data(contentsOf: url.appendingPathComponent(file))) ?? (try? Data(contentsOf: legacy.appendingPathComponent(file))) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func write<T: Encodable>(_ value: T, name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url.appendingPathComponent("nyx-\(name).json"), options: .atomic)
    }
}
nonisolated protocol WeatherProviding: Sendable {
    func forecasts(for parks: [Park], network: Bool, force: Bool) async -> [String: Forecast]
}
extension WeatherProviding {
    func forecast(for park: Park, network: Bool, force: Bool = false) async -> Forecast? {
        await forecasts(for: [park], network: network, force: force)[park.id]
    }
}
actor WeatherService: WeatherProviding {
    private let transport: any HTTPTransport
    private let persist:Bool
    private var memory: [String: Forecast] = [:]
    /// Requests already on their way, so Tonight, Parks and saved parks never fetch the same park twice at once.
    private var inFlight: [String: Task<[String: Forecast], Never>] = [:]
    init(transport: any HTTPTransport = SafeHTTP(),persist:Bool=true) { self.transport=transport;self.persist=persist }
    /// Cached forecasts for every park, refreshed in as few requests as possible: Open-Meteo
    /// accepts many coordinates at once, so all 63 parks cost one request, not 63.
    /// A failed request keeps the last forecast; nothing is ever filled in as clear.
    func forecasts(for parks: [Park], network: Bool, force: Bool = false) async -> [String: Forecast] {
        var result: [String: Forecast] = [:]
        var due: [Park] = []
        for park in parks {
            let cached = memory[park.id] ?? (persist ? CacheDirectory.read(Forecast.self, name: "weather-\(park.id)") : nil)
            if let cached { memory[park.id]=cached; result[park.id]=cached }
            // A forced refresh still waits ten minutes between requests for the same park.
            let age=cached.map { Date.now.timeIntervalSince($0.updated) } ?? .infinity
            if network && (age>=6*3600 || (force && age>=600)) { due.append(park) }
        }
        var waits: [Task<[String: Forecast], Never>] = due.compactMap { inFlight[$0.id] }
        let fresh = due.filter { inFlight[$0.id] == nil }
        for start in stride(from: 0, to: fresh.count, by: 50) {
            let chunk = Array(fresh[start..<min(fresh.count, start+50)])
            let task = Task { () -> [String: Forecast] in
                var fetched: [String: Forecast] = [:]
                for (park, forecast) in await self.fetch(chunk) { fetched[park.id]=forecast }
                return fetched
            }
            for park in chunk { inFlight[park.id]=task }
            waits.append(task)
        }
        var seen = Set<Task<[String: Forecast], Never>>()
        for task in waits where seen.insert(task).inserted {
            for (id, forecast) in await task.value {
                if memory[id].map({ $0.updated < forecast.updated }) ?? true {
                    memory[id]=forecast
                    if persist, let park=due.first(where: { $0.id == id }) { CacheDirectory.write(forecast,name:"weather-\(park.id)") }
                }
                if due.contains(where: { $0.id == id }) { result[id]=memory[id] }
            }
        }
        for park in fresh where inFlight[park.id] != nil { inFlight[park.id]=nil }
        return result
    }
    private func fetch(_ parks: [Park]) async -> [(Park, Forecast)] {
        guard !parks.isEmpty else { return [] }
        var parts = URLComponents()
        parts.scheme="https"; parts.host="api.open-meteo.com"; parts.path="/v1/forecast"
        // Hours start at 00:00 UTC; yesterday's hours keep an eastern park's night in progress covered.
        parts.queryItems=[URLQueryItem(name:"latitude",value:parks.map { String($0.latitude) }.joined(separator:",")),
            URLQueryItem(name:"longitude",value:parks.map { String($0.longitude) }.joined(separator:",")),
            URLQueryItem(name:"hourly",value:"cloud_cover"),URLQueryItem(name:"forecast_days",value:"16"),URLQueryItem(name:"past_days",value:"1"),
            URLQueryItem(name:"timeformat",value:"unixtime"),URLQueryItem(name:"timezone",value:"GMT")]
        guard let url=parts.url else { return [] }
        struct Response: Decodable { struct Hourly: Decodable { let time: [Double]; let cloud_cover: [Double?] }; let hourly: Hourly }
        guard let data=try? await transport.get(url) else { return [] }
        // One coordinate returns an object; several return an array in request order.
        let decoded=(try? JSONDecoder().decode([Response].self, from: data)) ?? (try? JSONDecoder().decode(Response.self, from: data)).map { [$0] } ?? []
        guard decoded.count == parks.count else { return [] }
        let now=Date.now
        return zip(parks, decoded).compactMap { park, response in
            guard response.hourly.time.count == response.hourly.cloud_cover.count, !response.hourly.time.isEmpty else { return nil }
            return (park, Forecast(updated:now,times:response.hourly.time,clouds:response.hourly.cloud_cover))
        }
    }
}
nonisolated protocol DetailProviding: Sendable {
    /// `weather` and `smoke` are the two switches in Your privacy: forecast detail comes from
    /// the forecast host, aerosols from the air-quality host.
    func details(for parks: [Park], weather: Bool, smoke: Bool, force: Bool) async -> [String: ForecastDetail]
}
/// The forecast's context, beside the score's own clouds: three models' clouds, cloud layers,
/// cold, dew, wind and visibility (seven days), and the aerosol forecast that warns of smoke.
/// Like clouds, every park shares each request, so a refresh is three more requests (two chunks
/// each for 63 parks), never one per park, and none of them hints at where someone is. Each part
/// keeps its own six-hour freshness; a failed request keeps the last good part.
actor ForecastDetailService: DetailProviding {
    enum Kind: CaseIterable, Sendable { case models, layers, air }
    private let transport: any HTTPTransport
    private let persist: Bool
    private var memory: [String: ForecastDetail] = [:]
    /// A refresh already under way; later callers wait for it instead of asking again.
    private var running: Task<Void, Never>?
    init(transport: any HTTPTransport = SafeHTTP(), persist: Bool = true) { self.transport=transport; self.persist=persist }
    func details(for parks: [Park], weather: Bool, smoke: Bool, force: Bool = false) async -> [String: ForecastDetail] {
        for park in parks where memory[park.id] == nil {
            if persist, let cached=CacheDirectory.read(ForecastDetail.self, name: "detail-\(park.id)") { memory[park.id]=cached }
        }
        if let running { await running.value }
        else {
            let now=Date.now
            var jobs: [(Kind, [Park])] = []
            for kind in Kind.allCases where kind == .air ? smoke : weather {
                let due=parks.filter { park in
                    let age=Self.series(memory[park.id], kind).map { now.timeIntervalSince($0.updated) } ?? .infinity
                    return age>=6*3600 || (force && age>=600)
                }
                for start in stride(from: 0, to: due.count, by: 50) { jobs.append((kind, Array(due[start..<min(due.count, start+50)]))) }
            }
            if !jobs.isEmpty {
                let task=Task {
                    let results=await withTaskGroup(of: (Kind, [(String, HourlySeries)]).self) { group in
                        for (kind, chunk) in jobs { group.addTask { (kind, await self.fetch(kind, chunk)) } }
                        var all: [(Kind, [(String, HourlySeries)])] = []
                        for await result in group { all.append(result) }
                        return all
                    }
                    self.store(results)
                }
                running=task
                await task.value
                running=nil
            }
        }
        var result: [String: ForecastDetail] = [:]
        for park in parks { if let detail=memory[park.id] { result[park.id]=detail } }
        return result
    }
    private func store(_ results: [(Kind, [(String, HourlySeries)])]) {
        var changed=Set<String>()
        for (kind, fetched) in results {
            for (id, series) in fetched {
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
    private func fetch(_ kind: Kind, _ parks: [Park]) async -> [(String, HourlySeries)] {
        guard !parks.isEmpty else { return [] }
        var parts=URLComponents()
        parts.scheme="https"
        var items=[URLQueryItem(name: "latitude", value: parks.map { String($0.latitude) }.joined(separator: ",")),
                   URLQueryItem(name: "longitude", value: parks.map { String($0.longitude) }.joined(separator: ","))]
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
        guard let url=parts.url, let data=try? await transport.get(url) else { return [] }
        struct Response: Decodable { let hourly: [String: [Double?]] }
        // One coordinate returns an object; several return an array in request order.
        let decoded=(try? JSONDecoder().decode([Response].self, from: data)) ?? (try? JSONDecoder().decode(Response.self, from: data)).map { [$0] } ?? []
        guard decoded.count == parks.count else { return [] }
        let now=Date.now
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
nonisolated protocol ParkProviding: Sendable {
    /// `programs` adds the ranger events request; alerts alone are enough wherever programs are not shown.
    func enrichment(for park: Park, key: String, network: Bool, force: Bool, programs: Bool) async -> ParkEnrichment?
}
/// Every install shares one NPS key and its hourly quota, so requests are spent carefully: alerts
/// only unless programs are on screen, no repeat request for the same park within ten minutes (even
/// when forced), and one request at a time per park however many screens ask.
actor ParkStore: ParkProviding {
    private let transport: any HTTPTransport
    private let persist:Bool
    private var memory: [String:ParkEnrichment]=[:]
    private var inFlight: [String:Task<ParkEnrichment?,Never>]=[:]
    init(transport: any HTTPTransport = SafeHTTP(),persist:Bool=true) { self.transport=transport;self.persist=persist }
    func enrichment(for park: Park, key: String, network: Bool, force: Bool = false, programs: Bool = true) async -> ParkEnrichment? {
        let cached=memory[park.id] ?? (persist ? CacheDirectory.read(ParkEnrichment.self,name:"park-\(park.id)") : nil)
        guard network, !key.isEmpty, !key.contains("$(") else { return cached }
        if let cached {
            let now=Date.now
            if now.timeIntervalSince(cached.updated)<600 { return cached }
            // Fresh only when everything asked for is: a failed events request retries next time.
            let oldest=programs ? min(cached.updated,cached.programsUpdated ?? .distantPast) : cached.updated
            if !force, now.timeIntervalSince(oldest)<6*3600 { return cached }
        }
        if let running=inFlight[park.id] { return await running.value }
        let task=Task { await self.fetch(park,key:key,cached:cached,programs:programs) }
        inFlight[park.id]=task
        let result=await task.value
        inFlight[park.id]=nil
        return result
    }
    private func fetch(_ park: Park, key: String, cached: ParkEnrichment?, programs wanted: Bool) async -> ParkEnrichment? {
        func url(_ path: String, page:Int=1) throws -> URL {
            var c=URLComponents(); c.scheme="https"; c.host="developer.nps.gov"; c.path="/api/v1/\(path)"
            c.queryItems=[URLQueryItem(name:"parkCode",value:park.apiCode),URLQueryItem(name:"api_key",value:key),URLQueryItem(name:"limit",value:"100")]
            if path=="events" { c.queryItems?.append(contentsOf:[URLQueryItem(name:"dateStart",value:park.isoDay(.now)),URLQueryItem(name:"pageSize",value:"100"),URLQueryItem(name:"pageNumber",value:String(page))]) }
            guard let url=c.url else { throw URLError(.badURL) }; return url
        }
        struct AlertResponse: Decodable { let data: [ParkAlert] }
        struct EventResponse: Decodable {
            struct Event: Decodable { let id:String; let title:String; let datestart:String; let description:String; let tags:[String]?; let dates:[String]? }
            let data:[Event]; let total:String?
        }
        // Alerts are the safety signal: they are saved as soon as they arrive. A slow or failing
        // events request keeps the last known programs instead of discarding fresh closures.
        // A failed alerts request never wipes known closures.
        guard let alerts=try? JSONDecoder().decode(AlertResponse.self,from:await transport.get(url("alerts"))).data else { return cached }
        let today=park.isoDay(.now)
        var programs=(cached?.programs ?? []).filter { $0.date >= today }
        var programsUpdated=cached?.programsUpdated
        if wanted, let firstPage=try? JSONDecoder().decode(EventResponse.self,from:await transport.get(url("events"))) {
            var events:[EventResponse.Event]?=firstPage.data
            let pages=min(10,Int(ceil((Double(firstPage.total ?? "0") ?? 0)/100)))
            if pages>1 {
                for page in 2...pages {
                    guard let more=try? JSONDecoder().decode(EventResponse.self,from:await transport.get(url("events",page:page))).data else { events=nil;break }
                    events?.append(contentsOf:more)
                }
            }
            if let events {
                programs=events.filter {
                    let text=($0.title+" "+($0.tags ?? []).joined(separator:" ")).lowercased()
                    return ["astronomy","stargaz","night sky","night-sky","star party"].contains(where:text.contains)
                }.flatMap { event in
                    (event.dates ?? [event.datestart]).filter { $0 >= today }.map { day in RangerProgram(id:event.id+day,title:event.title,date:day,description:Self.plain(event.description)) }
                }.sorted { $0.date<$1.date }
                programsUpdated = .now
            }
        }
        // The park description is bundled in parks.json; it is never fetched.
        let result=ParkEnrichment(updated:.now,alerts:alerts,programs:programs,description:cached?.description,programsUpdated:programsUpdated)
        memory[park.id]=result; if persist { CacheDirectory.write(result,name:"park-\(park.id)") }; return result
    }
    private static func plain(_ html:String)->String {
        html.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)
            .replacingOccurrences(of:"&nbsp;",with:" ").replacingOccurrences(of:"&amp;",with:"&")
    }
}
