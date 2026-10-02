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
    func forecast(for park: Park, network: Bool, force: Bool) async -> Forecast?
}
actor WeatherService: WeatherProviding {
    private let transport: any HTTPTransport
    private let persist:Bool
    private var memory: [String: Forecast] = [:]
    init(transport: any HTTPTransport = SafeHTTP(),persist:Bool=true) { self.transport=transport;self.persist=persist }
    func forecast(for park: Park, network: Bool, force: Bool = false) async -> Forecast? {
        let cached = memory[park.id] ?? (persist ? CacheDirectory.read(Forecast.self, name: "weather-\(park.id)") : nil)
        if !network || (!force && cached.map { Date.now.timeIntervalSince($0.updated)<6*3600 } == true) { return cached }
        var parts = URLComponents()
        parts.scheme="https"; parts.host="api.open-meteo.com"; parts.path="/v1/forecast"
        parts.queryItems=[URLQueryItem(name:"latitude",value:String(park.latitude)),URLQueryItem(name:"longitude",value:String(park.longitude)),
            URLQueryItem(name:"hourly",value:"cloud_cover"),URLQueryItem(name:"forecast_days",value:"16"),URLQueryItem(name:"timeformat",value:"unixtime"),URLQueryItem(name:"timezone",value:"GMT")]
        guard let url=parts.url else { return cached }
        struct Response: Decodable { struct Hourly: Decodable { let time: [Double]; let cloud_cover: [Double?] }; let hourly: Hourly }
        do {
            let result = try JSONDecoder().decode(Response.self, from: await transport.get(url))
            guard result.hourly.time.count == result.hourly.cloud_cover.count else { return cached }
            let forecast=Forecast(updated:.now,times:result.hourly.time,clouds:result.hourly.cloud_cover)
            memory[park.id]=forecast; if persist { CacheDirectory.write(forecast,name:"weather-\(park.id)") }
            return forecast
        } catch { return cached }
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
        do {
            // All three must succeed before the cache is replaced: a failure never
            // wipes previously known closures or claims that the park is open.
            let alerts=try JSONDecoder().decode(AlertResponse.self,from:await transport.get(url("alerts"))).data
            let firstPage=try JSONDecoder().decode(EventResponse.self,from:await transport.get(url("events")))
            var events=firstPage.data
            let pages=min(10,Int(ceil((Double(firstPage.total ?? "0") ?? 0)/100)))
            if pages>1 { for page in 2...pages { events += try JSONDecoder().decode(EventResponse.self,from:await transport.get(url("events",page:page))).data } }
            let info=try JSONDecoder().decode(ParkResponse.self,from:await transport.get(url("parks"))).data
            let programs=events.filter {
                let text=($0.title+" "+($0.tags ?? []).joined(separator:" ")).lowercased()
                return ["astronomy","stargaz","night sky","night-sky","star party"].contains(where:text.contains)
            }.flatMap { event in
                (event.dates ?? [event.datestart]).filter { $0 >= park.isoDay(.now) }.map { day in RangerProgram(id:event.id+day,title:event.title,date:day,description:Self.plain(event.description)) }
            }.sorted { $0.date<$1.date }
            let result=ParkEnrichment(updated:.now,alerts:alerts,programs:programs,description:info.first?.description)
            memory[park.id]=result; if persist { CacheDirectory.write(result,name:"park-\(park.id)") }; return result
        } catch { return cached }
    }
    private static func plain(_ html:String)->String {
        html.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)
            .replacingOccurrences(of:"&nbsp;",with:" ").replacingOccurrences(of:"&amp;",with:"&")
    }
}
