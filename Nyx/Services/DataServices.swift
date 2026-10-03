import Foundation

nonisolated protocol HTTPTransport: Sendable {
    func get(_ url: URL) async throws -> Data
}
/// A redirect is never followed. Runtime requests can reach exactly two hosts.
nonisolated final class HostGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
nonisolated struct SafeHTTP: HTTPTransport {
    static let hosts: Set<String> = ["developer.nps.gov", "api.open-meteo.com"]
    func get(_ url: URL) async throws -> Data {
        guard url.scheme == "https", let host = url.host, Self.hosts.contains(host) else { throw URLError(.unsupportedURL) }
        let preference = host == "developer.nps.gov" ? "npsEnabled" : "weatherEnabled"
        guard UserDefaults.standard.object(forKey: preference) as? Bool != false else { throw URLError(.cancelled) }
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
nonisolated enum CacheDirectory {
    static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    }
    static func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("nyx-\(name).json")) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func write<T: Encodable>(_ value: T, name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url.appendingPathComponent("nyx-\(name).json"), options: .atomic)
    }
}
nonisolated struct Forecast: Codable, Sendable {
    let updated: Date
    let times: [Double]
    let clouds: [Double?]
    /// Overlap-weighted hourly mean; a partial forecast is never treated as full.
    func mean(from start: Date?, to end: Date?, now: Date = .now) -> Double? {
        guard let start, let end, end>start, now.timeIntervalSince(updated)<36*3600 else { return nil }
        guard times.count==clouds.count, times.allSatisfy(\.isFinite),
              zip(times,times.dropFirst()).allSatisfy({ abs($1-$0-3600)<0.1 }) else { return nil }
        var weight = 0.0, sum = 0.0
        for (i,t) in times.enumerated() where i<clouds.count {
            let overlap = min(end.timeIntervalSince1970,t+3600)-max(start.timeIntervalSince1970,t)
            if overlap>0, let cloud=clouds[i], cloud.isFinite, (0...100).contains(cloud) { sum+=cloud*overlap; weight+=overlap }
        }
        guard weight >= end.timeIntervalSince(start)-1 else { return nil }
        return sum/weight
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
            if network && (force || cached.map { Date.now.timeIntervalSince($0.updated)>=6*3600 } ?? true) { due.append(park) }
        }
        for start in stride(from: 0, to: due.count, by: 50) {
            let chunk = Array(due[start..<min(due.count, start+50)])
            for (park, forecast) in await fetch(chunk) {
                memory[park.id]=forecast; result[park.id]=forecast
                if persist { CacheDirectory.write(forecast,name:"weather-\(park.id)") }
            }
        }
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
nonisolated struct ParkEnrichment: Codable, Sendable {
    let updated: Date
    let alerts: [ParkAlert]
    let programs: [RangerProgram]
    let description: String?
}
nonisolated protocol ParkProviding: Sendable {
    func enrichment(for park: Park, key: String, network: Bool, force: Bool) async -> ParkEnrichment?
}
actor ParkStore: ParkProviding {
    private let transport: any HTTPTransport
    private let persist:Bool
    private var memory: [String:ParkEnrichment]=[:]
    init(transport: any HTTPTransport = SafeHTTP(),persist:Bool=true) { self.transport=transport;self.persist=persist }
    func enrichment(for park: Park, key: String, network: Bool, force: Bool = false) async -> ParkEnrichment? {
        let cached=memory[park.id] ?? (persist ? CacheDirectory.read(ParkEnrichment.self,name:"park-\(park.id)") : nil)
        guard network, !key.isEmpty, !key.contains("$(") else { return cached }
        if !force, let cached, Date.now.timeIntervalSince(cached.updated)<6*3600 { return cached }
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
        struct ParkResponse: Decodable { struct Info: Decodable { let description:String }; let data:[Info] }
        // Alerts are the safety signal: they are saved as soon as they arrive. A slow or failing
        // events or park request keeps the last known programs and description instead of
        // discarding fresh closures. A failed alerts request never wipes known closures.
        guard let alerts=try? JSONDecoder().decode(AlertResponse.self,from:await transport.get(url("alerts"))).data else { return cached }
        let today=park.isoDay(.now)
        var programs=(cached?.programs ?? []).filter { $0.date >= today }
        if let firstPage=try? JSONDecoder().decode(EventResponse.self,from:await transport.get(url("events"))) {
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
            }
        }
        let info=try? JSONDecoder().decode(ParkResponse.self,from:await transport.get(url("parks"))).data
        let result=ParkEnrichment(updated:.now,alerts:alerts,programs:programs,description:info?.first?.description ?? cached?.description)
        memory[park.id]=result; if persist { CacheDirectory.write(result,name:"park-\(park.id)") }; return result
    }
    private static func plain(_ html:String)->String {
        html.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)
            .replacingOccurrences(of:"&nbsp;",with:" ").replacingOccurrences(of:"&amp;",with:"&")
    }
}
