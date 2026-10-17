import Foundation

// Park updates (NPS), forecast detail and the smoke forecast, for Nyx on iPhone and iPad and on
// Vision Pro (alerts and smoke only there). The guarded transport (`SafeHTTP`, `HostGuard`,
// `HostBackoff`), the offline cache folder and the cloud forecast (`WeatherService`) live in
// CloudForecastClient.swift; the launch's cache reads (`CachePreload`), iPhone only, in CachePreload.swift.

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
    /// "Smoke and haze" was switched off: drop every cached aerosol series, in memory and on disk,
    /// so nothing (the app, Siri, the widgets) counts the air-quality host's data any more.
    func forgetAir() async
    /// Smoke for world catalogue places, asked for by the same whole requests as their clouds
    /// (`CatalogForecast.Regions`), never one place alone; with `network` false, only what is kept.
    func catalogAir(_ requests: [[Park]], network: Bool, force: Bool) async -> [String: ForecastDetail]
}
nonisolated extension DetailProviding {
    /// A provider without catalogue smoke (a test double) has none to give.
    func catalogAir(_ requests: [[Park]], network: Bool, force: Bool) async -> [String: ForecastDetail] { [:] }
}
/// The forecast's context, beside the score's own clouds: three models' clouds, cloud layers,
/// cold, dew, wind, visibility, rain, weather and water vapour (seven days), and the aerosol and
/// dust forecast that warns of smoke.
/// Like clouds, every park shares each request, so a refresh is three more requests (two chunks
/// each for 63 parks), never one per park, and none of them hints at where someone is. Each part
/// keeps its own twelve-hour freshness (`ForecastReuse`); a failed request keeps the last good
/// part. Requests to one host go one after the other, never side by side, within this device's
/// budget (`CallBudget`). Detail never uses a Low Data Mode network: it is context, and the
/// score's clouds still arrive.
actor ForecastDetailService: DetailProviding {
    enum Kind: CaseIterable, Sendable {
        case models, layers, air
        var host: String { self == .air ? "air-quality-api.open-meteo.com" : "api.open-meteo.com" }
        /// How soon pulling to refresh may ask again: three hours for the forecast models (ICON
        /// runs every three), never sooner than twelve for smoke (CAMS runs twice a day).
        var forced: TimeInterval { self == .air ? ForecastReuse.airForced : ForecastReuse.detailForced }
    }
    /// Detail is context for the week ahead; twice a day keeps it current at a quarter of the calls.
    static let freshFor: TimeInterval=ForecastReuse.detail
    /// At most this many places in one catalogue smoke request. Three hourly series for eight days
    /// make a whole 1,000-place tile about 8 MB, too slow on a weak connection; so a tile goes in
    /// parts, each part of one tile's request, never two regions mixed.
    static let catalogAirChunk=250
    private let transport: any HTTPTransport
    private let persist: Bool
    private let backoff: HostBackoff
    private let ledger: CallLedger
    private let budget: CallBudget
    private let clock: @Sendable () -> Date
    /// Whether to ask for the context the park page reads beyond the score (`ForecastDetail.layerExtras`,
    /// `airExtras`); Vision Pro asks for smoke only, exactly as its privacy screen says.
    private let extras: Bool
    private var memory: [String: ForecastDetail] = [:]
    private var loaded=Set<String>()
    private var lowData=false
    /// The files on disk hold no aerosol series (`forgetAir` swept them this launch).
    private var airCleared=false
    /// Counts `forgetAir` calls. A refresh notes it when it begins; smoke that arrives after the
    /// switch went off (the request was already in flight) is dropped instead of stored.
    private var airGeneration=0
    /// A refresh already under way, with the parks it asked about for each kind; later callers wait
    /// for it instead of asking again.
    private var running: (task: Task<Void, Never>, attempted: [Kind: Set<String>])?
    /// Callers waiting for a refresh to end, the one that started it included (tests read it).
    private(set) var waiting=0
    /// The catalogue smoke request under way, if any; a later caller waits for it, then takes what is kept.
    private var catalogAirRunning: Task<Void, Never>?
    init(transport: any HTTPTransport = SafeHTTP(), persist: Bool = true, backoff: HostBackoff? = nil, ledger: CallLedger? = nil,
         budget: CallBudget = .standard, extras: Bool = true, clock: @escaping @Sendable () -> Date = { .now }) {
        self.transport=transport; self.persist=persist; self.clock=clock; self.budget=budget; self.extras=extras
        self.backoff=backoff ?? (persist ? .shared : HostBackoff(file: nil))
        self.ledger=ledger ?? (persist ? .shared : CallLedger(file: nil))
    }
    func hydrate(_ parks: [Park]) async -> [String: ForecastDetail] {
        for park in parks { load(park.id) }
        return memory
    }
    func seed(_ cached: [String: ForecastDetail], parks: [Park]) {
        for park in parks where loaded.insert(park.id).inserted && memory[park.id] == nil { memory[park.id]=cached[park.id] }
    }
    func pausedForLowData() -> Bool { lowData }
    func forgetAir() {
        airGeneration+=1
        for (id, detail) in memory where detail.air != nil {
            var kept=detail; kept.air=nil
            memory[id]=kept
            if persist { CacheDirectory.write(kept, name: "detail-\(id)") }
        }
        // Parks not read yet this launch: their files on disk, once until smoke is fetched again.
        guard persist, !airCleared else { return }
        airCleared=true
        let all=Set(((try? ParkData.load().map(\.id)) ?? [])+Self.keptCatalogueIDs())
        for id in all where memory[id] == nil {
            guard var cached=CacheDirectory.read(ForecastDetail.self, name: "detail-\(id)"), cached.air != nil else { continue }
            cached.air=nil
            CacheDirectory.write(cached, name: "detail-\(id)")
        }
    }
    /// World catalogue places with a detail file kept (their smoke), read from the cache folders' file names.
    private static func keptCatalogueIDs() -> [String] {
        let prefix="nyx-detail-", suffix=".json"
        return [CacheDirectory.url, CacheDirectory.legacyFolder].flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { $0.hasPrefix(prefix+Park.catalogPrefix) && $0.hasSuffix(suffix) }
                .map { String($0.dropFirst(prefix.count).dropLast(suffix.count)) }
        }
    }
    private func load(_ id: String) {
        guard loaded.insert(id).inserted, memory[id] == nil, persist, let cached=CacheDirectory.read(ForecastDetail.self, name: "detail-\(id)") else { return }
        memory[id]=cached
    }
    func details(for parks: [Park], weather: Bool, smoke: Bool, force: Bool = false) async -> [String: ForecastDetail] {
        for park in parks { load(park.id) }
        // Another request is on its way (perhaps for other parks): wait for it, then decide again
        // what is due, leaving out what it already asked for: a request that failed without a
        // backoff (a timeout, a refusal, an unreadable answer) is not sent again once per waiter. A
        // cancelled caller stops waiting and returns what is kept; the request finishes and stores itself.
        var attempted: [Kind: Set<String>] = [:]
        while let current=running {
            waiting+=1
            let finished=await SharedRequest.value(of: current.task) != nil
            waiting-=1
            guard finished else { return kept(parks) }
            attempted.merge(current.attempted) { $0.union($1) }
        }
        do {
            let now=clock()
            var jobs: [(Kind, [Park])] = []
            for kind in Kind.allCases where (kind == .air ? smoke : weather) && backoff.allows(kind.host, now: now) {
                let due=parks.filter { park in
                    attempted[kind]?.contains(park.id) != true
                        && ForecastReuse.due(Self.series(memory[park.id], kind)?.updated, now: now, force: force, normal: Self.freshFor, forced: kind.forced)
                }
                for start in stride(from: 0, to: due.count, by: 50) { jobs.append((kind, Array(due[start..<min(due.count, start+50)]))) }
            }
            if !jobs.isEmpty {
                let generation=airGeneration
                // One host's requests one after the other (Open-Meteo serves one at a time per
                // address and queues the rest); the two hosts side by side.
                let byHost=Dictionary(grouping: jobs) { $0.0.host }.values.map { Array($0) }
                let task=Task {
                    let results=await withTaskGroup(of: [(Kind, [(String, HourlySeries)]?)].self) { group in
                        for queue in byHost {
                            group.addTask {
                                var done: [(Kind, [(String, HourlySeries)]?)] = []
                                for (kind, chunk) in queue {
                                    guard !Task.isCancelled else { break }
                                    let fetched=await self.fetch(kind, chunk)
                                    done.append((kind, fetched))
                                    // A host that now asks Nyx to wait: the rest of its queue waits too.
                                    if fetched?.isEmpty == true && !self.backoff.allows(kind.host, now: self.clock()) { break }
                                }
                                return done
                            }
                        }
                        var all: [(Kind, [(String, HourlySeries)]?)] = []
                        for await result in group { all+=result }
                        return all
                    }
                    self.store(results, airGeneration: generation)
                    self.running=nil
                }
                var asked: [Kind: Set<String>] = [:]
                for (kind, chunk) in jobs { asked[kind, default: []].formUnion(chunk.map(\.id)) }
                running=(task, asked)
                waiting+=1
                _=await SharedRequest.value(of: task)
                waiting-=1
            }
        }
        return kept(parks)
    }
    /// Smoke at world catalogue places: each request of `CatalogForecast.Regions` whole (in parts of
    /// `catalogAirChunk`), with the same public coordinates as its clouds, to the air-quality host,
    /// within the browsing budget, so looking around the world never leaves the parks' smoke without
    /// room. A request is due as its places' clouds are: all of it, or none of it. Kept on disk.
    func catalogAir(_ requests: [[Park]], network: Bool, force: Bool = false) async -> [String: ForecastDetail] {
        let places=Array(requests.joined())
        for place in places { load(place.id) }
        if let current=catalogAirRunning {
            waiting+=1
            _=await SharedRequest.value(of: current)
            waiting-=1
            return kept(places)
        }
        let now=clock()
        guard network, backoff.allows(Kind.air.host, now: now) else { return kept(places) }
        let due=requests.filter { request in
            !request.isEmpty && request.count <= CatalogForecast.maxPointsPerRequest
                && ForecastReuse.due(request.compactMap { memory[$0.id]?.air?.updated }.max(), now: now, force: force, normal: Self.freshFor, forced: Kind.air.forced)
        }
        guard !due.isEmpty else { return kept(places) }
        let generation=airGeneration
        let task=Task {
            var results: [(Kind, [(String, HourlySeries)]?)] = []
            asking: for request in due {
                for part in CatalogForecast.chunks(request, limit: Self.catalogAirChunk) {
                    guard !Task.isCancelled else { break asking }
                    let fetched=await self.fetch(.air, part, caps: self.budget.browsing)
                    results.append((.air, fetched))
                    // The host asks Nyx to wait, or the browsing budget is spent: the rest waits too.
                    if fetched?.isEmpty == true && !self.backoff.allows(Kind.air.host, now: self.clock()) { break asking }
                }
            }
            self.store(results, airGeneration: generation, notesLowData: false)
            self.catalogAirRunning=nil
        }
        catalogAirRunning=task
        waiting+=1
        _=await SharedRequest.value(of: task)
        waiting-=1
        return kept(places)
    }
    private func kept(_ parks: [Park]) -> [String: ForecastDetail] {
        var result: [String: ForecastDetail] = [:]
        for park in parks { if let detail=memory[park.id] { result[park.id]=detail } }
        return result
    }
    /// A nil part was held back by Low Data Mode. Smoke asked for before the latest `forgetAir`
    /// is not stored: the switch went off while it was on its way.
    /// `notesLowData` false: the catalogue's smoke, which says nothing about the parks' detail being paused.
    private func store(_ results: [(Kind, [(String, HourlySeries)]?)], airGeneration generation: Int, notesLowData: Bool = true) {
        var changed=Set<String>()
        if notesLowData { lowData=results.contains { $0.1 == nil } }
        for (kind, fetched) in results {
            if kind == .air && generation != airGeneration { continue }
            for (id, series) in fetched ?? [] {
                var detail=memory[id] ?? ForecastDetail()
                switch kind { case .models: detail.models=series; case .layers: detail.layers=series; case .air: detail.air=series; airCleared=false }
                memory[id]=detail; changed.insert(id)
            }
        }
        if persist { for id in changed { if let detail=memory[id] { CacheDirectory.write(detail, name: "detail-\(id)") } } }
    }
    private static func series(_ detail: ForecastDetail?, _ kind: Kind) -> HourlySeries? {
        switch kind { case .models: detail?.models; case .layers: detail?.layers; case .air: detail?.air }
    }
    /// Nil when Low Data Mode held the request back; empty when it failed any other way.
    /// `caps`: the browsing budget for the catalogue's smoke; the essential one otherwise.
    private func fetch(_ kind: Kind, _ parks: [Park], caps: CallBudget.Caps? = nil) async -> [(String, HourlySeries)]? {
        guard !parks.isEmpty else { return [] }
        var parts=URLComponents()
        parts.scheme="https"
        var items=[URLQueryItem(name: "latitude", value: parks.map { String($0.forecastPoint.latitude) }.joined(separator: ",")),
                   URLQueryItem(name: "longitude", value: parks.map { String($0.forecastPoint.longitude) }.joined(separator: ","))]
        let keys: [String]
        var context: [String]=[]
        switch kind {
        case .models:
            parts.host="api.open-meteo.com"; parts.path="/v1/forecast"; keys=ForecastDetail.modelKeys
            items+=[URLQueryItem(name: "hourly", value: "cloud_cover"), URLQueryItem(name: "models", value: "gfs_seamless,ecmwf_ifs025,icon_seamless")]
        case .layers:
            parts.host="api.open-meteo.com"; parts.path="/v1/forecast"; keys=ForecastDetail.layerKeys; context=extras ? ForecastDetail.layerExtras : []
            items.append(URLQueryItem(name: "hourly", value: (keys+context).joined(separator: ",")))
        case .air:
            // CAMS global covers every park, Alaska and American Samoa included.
            parts.host="air-quality-api.open-meteo.com"; parts.path="/v1/air-quality"; keys=ForecastDetail.airKeys; context=extras ? ForecastDetail.airExtras : []
            items+=[URLQueryItem(name: "hourly", value: (keys+context).joined(separator: ",")), URLQueryItem(name: "domains", value: "cams_global")]
        }
        parts.queryItems=items+[URLQueryItem(name: "forecast_days", value: "7"), URLQueryItem(name: "past_days", value: "1"),
                                URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "GMT")]
        guard let url=parts.url else { return [] }
        let data: Data
        do { data=try await ForecastRequest.get(url, transport: transport, constrained: false, backoff: backoff, ledger: ledger, caps: caps ?? budget.essential, clock: clock) } catch {
            return Backoff.constrained(error) ? nil : []
        }
        return OpenMeteoAnswer.series(data, ids: parks.map(\.id), keys: keys, extras: context, now: clock())
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
    /// One request for all the parks' alerts, fresh for six hours, shared by every screen. `pages`
    /// caps the requests (one in a background refresh); a set it cannot complete is not kept.
    func alerts(for parks: [Park], key: String, network: Bool, force: Bool, pages: Int) async -> AlertsUpdate
    /// One park's night-sky programs, asked for only when its page is open, fresh for a day.
    func programs(for park: Park, key: String, network: Bool, force: Bool) async -> ProgramsCache?
    /// The cached alerts, read once from disk off the main actor at launch.
    func hydrate(_ parks: [Park]) async -> AlertsUpdate
    /// Alerts already read at launch (`CachePreload`).
    func seed(_ cached: ParkAlertsCache?) async
    /// Every park's campgrounds from one request (all 63 park codes), fresh for seven days.
    func campgrounds(for parks: [Park], key: String, network: Bool, force: Bool) async -> CampgroundsCache?
}
extension ParkProviding {
    nonisolated func alerts(for parks: [Park], key: String, network: Bool, force: Bool = false) async -> AlertsUpdate {
        await alerts(for: parks, key: key, network: network, force: force, pages: ParkStore.alertPages)
    }
    /// A provider without campgrounds (a test double) has none to show.
    nonisolated func campgrounds(for parks: [Park], key: String, network: Bool, force: Bool) async -> CampgroundsCache? { nil }
}
/// NOAA's Kp forecast (`AuroraOutlook`) from the Space Weather Prediction Center: one small global
/// file (about 7 KB), asked for whole, so the request names no place and nothing about anyone. Fresh
/// for three hours (NOAA reissues it several times a day); one request at a time; none while the
/// service is refusing (`HostBackoff`); none at all with "Aurora forecast" off in Your privacy
/// (`auroraEnabled`, enforced by `SafeHTTP` before any connection). The last good copy is kept on
/// disk and used for a day.
actor AuroraService {
    static let host="services.swpc.noaa.gov"
    static let path="/products/noaa-planetary-k-index-forecast.json"
    /// The switch in Your privacy, on iPhone, iPad and Vision Pro (`SafeHTTP.preferences`).
    static let key="auroraEnabled"
    static let freshFor: TimeInterval=3*3600
    /// Pulling to refresh asks again after an hour at the soonest.
    static let forcedAfter: TimeInterval=3600
    private let transport: any HTTPTransport
    private let persist: Bool
    private let backoff: HostBackoff
    private let clock: @Sendable () -> Date
    private var memory: AuroraOutlook?
    private var loaded=false
    private var running: Task<AuroraOutlook?, Never>?
    /// Bumped by `forget`: a request that was out when the switch went off is dropped on arrival,
    /// never kept or written to disk.
    private var generation=0
    /// When a request last went out: after one that failed or brought nothing readable, the next
    /// waits an hour, however often the screens refresh.
    private var attempted: Date?
    init(transport: any HTTPTransport = SafeHTTP(), persist: Bool = true, backoff: HostBackoff? = nil, clock: @escaping @Sendable () -> Date = { .now }) {
        self.transport=transport; self.persist=persist; self.clock=clock
        self.backoff=backoff ?? (persist ? .shared : HostBackoff(file: nil))
    }
    /// The last forecast on this device, read from disk once; nil when there is none or it is over a day old.
    func cached() -> AuroraOutlook? {
        if !loaded { loaded=true; if persist, memory == nil { memory=CacheDirectory.read(AuroraOutlook.self, name: "aurora") } }
        return memory.flatMap { $0.usable(now: clock()) ? $0 : nil }
    }
    /// The forecast, asking NOAA when the copy here is stale and `network` allows it. A failed or
    /// refused request keeps the last good copy.
    func outlook(network: Bool, force: Bool=false) async -> AuroraOutlook? {
        let current=cached()
        let age=current.map { clock().timeIntervalSince($0.updated) } ?? .infinity
        guard network, age>=Self.freshFor || (force && age>=Self.forcedAfter), backoff.allows(Self.host, now: clock()),
              attempted.map({ clock().timeIntervalSince($0)>=Self.forcedAfter }) ?? true else { return current }
        if let running { return await running.value ?? current }
        var parts=URLComponents(); parts.scheme="https"; parts.host=Self.host; parts.path=Self.path
        guard let url=parts.url else { return current }
        let transport=self.transport, clock=self.clock, backoff=self.backoff
        let task=Task<AuroraOutlook?, Never> {
            do {
                let data=try await transport.get(url, headers: [:], constrained: true)
                backoff.succeeded(Self.host)
                return AuroraOutlook.parse(data, now: clock())
            } catch {
                backoff.record(error, host: Self.host, now: clock())
                return nil
            }
        }
        running=task; attempted=clock()
        let asked=generation
        let fresh=await task.value
        running=nil
        // Switched off while the request was out: nothing that arrived is kept.
        guard asked == generation else { return nil }
        guard let fresh else { return current }
        memory=fresh
        if persist { CacheDirectory.write(fresh, name: "aurora") }
        return fresh
    }
    /// "Aurora forecast" was switched off: the copy here is dropped, in memory and on disk.
    func forget() {
        generation+=1
        running?.cancel(); running=nil
        memory=nil; loaded=true
        if persist { CacheDirectory.remove(name: "aurora") }
    }
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
    /// Callers waiting on `alertsTask`; when the last one is cancelled, so is the request.
    private var alertWaiters=0
    /// The last alerts request was refused (quota, a refused key, a server error).
    private var refused=false
    private var programCache: [String: ProgramsCache] = [:]
    private var programsLoaded=Set<String>()
    private var programTasks: [String: Task<Void, Never>] = [:]
    private var campgroundCache: CampgroundsCache?
    private var campgroundsLoaded=false
    private var campgroundsTask: Task<Void, Never>?
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
            if let code=park.nps { alerts[code]=old.alerts }
            oldest=min(oldest ?? old.updated, old.updated)
        }
        return oldest.map { ParkAlertsCache(updated: $0, alerts: alerts) }
    }
    /// Pages of 500 alerts asked for at most; 63 parks rarely need a second.
    static let alertPages=4
    func alerts(for parks: [Park], key: String, network: Bool, force: Bool, pages: Int) async -> AlertsUpdate {
        loadAlerts(parks)
        guard network, Self.usable(key) else { return AlertsUpdate(cache: alertCache, busy: false) }
        // Another screen's request is on its way: wait for it, then decide again. The task clears
        // itself before it finishes, so a waiter never sees a request that has already ended.
        // A cancelled caller stops waiting and returns what is cached.
        while let running=alertsTask {
            guard await wait(for: running) else { return AlertsUpdate(cache: alertCache, busy: busy) }
        }
        guard Self.stale(alertCache?.updated, maxAge: 6*3600, force: force, now: clock()) else { return AlertsUpdate(cache: alertCache, busy: false) }
        guard backoff.allows(Self.host, now: clock()) else { return AlertsUpdate(cache: alertCache, busy: true) }
        let codes=Array(Set(parks.compactMap(\.nps))).sorted(), ids=parks.map(\.id)
        let task=Task { () -> Bool in
            let ok=await self.fetchAlerts(codes: codes, parkIDs: ids, key: key, pages: pages)
            self.alertsTask=nil
            return ok
        }
        alertsTask=task
        _=await wait(for: task)
        return AlertsUpdate(cache: alertCache, busy: busy)
    }
    /// Waits for the alerts request; false when the caller was cancelled first. The request is
    /// cancelled too once nobody is waiting for it.
    private func wait(for task: Task<Bool, Never>) async -> Bool {
        alertWaiters+=1
        let finished=await SharedRequest.value(of: task) != nil
        alertWaiters-=1
        if !finished, alertWaiters == 0 { task.cancel() }
        return finished
    }
    func programs(for park: Park, key: String, network: Bool, force: Bool = false) async -> ProgramsCache? {
        if persist, programsLoaded.insert(park.id).inserted, programCache[park.id] == nil {
            programCache[park.id]=CacheDirectory.read(ProgramsCache.self, name: "programs-\(park.id)")
        }
        guard network, Self.usable(key) else { return programCache[park.id] }
        // A cancelled caller stops waiting and returns what is cached, as for alerts.
        while let running=programTasks[park.id] {
            guard await SharedRequest.value(of: running) != nil else { return programCache[park.id] }
        }
        guard Self.stale(programCache[park.id]?.updated, maxAge: 24*3600, force: force, now: clock()), backoff.allows(Self.host, now: clock()) else { return programCache[park.id] }
        let task=Task {
            await self.fetchPrograms(park, key: key)
            self.programTasks[park.id]=nil
        }
        programTasks[park.id]=task
        _=await SharedRequest.value(of: task)
        return programCache[park.id]
    }
    /// Campgrounds change with the seasons, not the hour: one request for all the parks (so it
    /// never says which park someone is looking at), kept seven days, and never on a Low Data Mode
    /// network (the full answer is about 2 MB).
    func campgrounds(for parks: [Park], key: String, network: Bool, force: Bool = false) async -> CampgroundsCache? {
        if !campgroundsLoaded {
            campgroundsLoaded=true
            if persist, campgroundCache == nil { campgroundCache=CacheDirectory.read(CampgroundsCache.self, name: "campgrounds") }
        }
        guard network, Self.usable(key) else { return campgroundCache }
        while let running=campgroundsTask {
            guard await SharedRequest.value(of: running) != nil else { return campgroundCache }
        }
        guard Self.stale(campgroundCache?.updated, maxAge: Self.campgroundsFresh, force: force, now: clock()), backoff.allows(Self.host, now: clock()) else { return campgroundCache }
        let codes=Array(Set(parks.compactMap(\.nps))).sorted()
        let task=Task {
            await self.fetchCampgrounds(codes: codes, key: key)
            self.campgroundsTask=nil
        }
        campgroundsTask=task
        _=await SharedRequest.value(of: task)
        return campgroundCache
    }
    static let campgroundsFresh: TimeInterval=7*86400
    /// Pages with `start`, as alerts do. A request that fails part-way keeps the last complete set.
    private func fetchCampgrounds(codes: [String], key: String) async {
        var all: [Campground] = [], read=0
        for _ in 0..<4 {
            guard let data=await data(url("campgrounds", [("parkCode", codes.joined(separator: ",")), ("limit", "500"), ("start", String(read))]), key: key, constrained: false),
                  let page=try? Campground.page(data) else { return }
            all+=page.campgrounds; read+=page.count
            guard let total=page.total, read<total, page.count>0 else { break }
        }
        var grouped=Dictionary(uniqueKeysWithValues: codes.map { ($0, [Campground]()) })
        for campground in all where grouped[campground.parkCode] != nil { grouped[campground.parkCode]?.append(campground) }
        let fresh=CampgroundsCache(updated: clock(), campgrounds: grouped)
        campgroundCache=fresh
        if persist { CacheDirectory.write(fresh, name: "campgrounds") }
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
        guard let data=await data(url, key: key, constrained: true) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    /// The body of a request that may wait for an unconstrained network: Low Data Mode holding it
    /// back is not a refusal and starts no backoff.
    private func data(_ url: URL?, key: String, constrained: Bool) async -> Data? {
        guard let url else { return nil }
        do {
            let data=try await transport.get(url, headers: ["X-Api-Key": key], constrained: constrained)
            refused=false
            backoff.succeeded(Self.host)
            return data
        } catch {
            if Backoff.constrained(error) { return nil }
            if error is HTTPStatusError { refused=true }
            backoff.record(error, host: Self.host, now: clock())
            return nil
        }
    }
    /// Pages with `start` while NPS reports more than one page holds (it allows up to 500 a page).
    /// A request that fails part-way keeps the last complete set.
    private func fetchAlerts(codes: [String], parkIDs: [String], key: String, pages: Int) async -> Bool {
        // Only an alert's id, title and parks are needed to show it; a missing description or category
        // reads as empty, and a record that still cannot be read costs only itself, never the page.
        struct Record: Decodable {
            let id: String, title: String, description: String, category: String, parkCode: String
            enum CodingKeys: String, CodingKey { case id, title, description, category, parkCode }
            init(from decoder: any Decoder) throws {
                let c=try decoder.container(keyedBy: CodingKeys.self)
                id=try c.decode(String.self, forKey: .id); title=try c.decode(String.self, forKey: .title)
                parkCode=try c.decode(String.self, forKey: .parkCode)
                description=(try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
                category=(try? c.decodeIfPresent(String.self, forKey: .category)) ?? ""
            }
        }
        struct Page: Decodable {
            let data: [Lenient<Record>]; let total: String?
            enum CodingKeys: String, CodingKey { case data, total }
            init(from decoder: any Decoder) throws {
                let c=try decoder.container(keyedBy: CodingKeys.self)
                data=try c.decode([Lenient<Record>].self, forKey: .data)
                total=try? c.decodeIfPresent(String.self, forKey: .total)
            }
        }
        var records: [Record] = [], read=0, complete=false
        for _ in 0..<max(1, min(pages, Self.alertPages)) {
            guard let page=await get(Page.self, url("alerts", [("parkCode", codes.joined(separator: ",")), ("limit", "500"), ("start", String(read))]), key: key) else { return false }
            // `start` counts every record on the page, read or not, so the next page follows on.
            read+=page.data.count
            records+=page.data.compactMap(\.value)
            guard let total=page.total.flatMap(Int.init), read<total, !page.data.isEmpty else { complete=true; break }
        }
        // Allowed fewer pages than there are (a background refresh): the last complete set stays.
        if !complete, pages<Self.alertPages { return false }
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
        // Ranger programs are the National Park Service's: a place it does not run has none to ask for.
        guard let code=park.nps else { return }
        let today=park.isoDay(clock())
        func page(_ number: Int) async -> Page? {
            // Events page with pageSize, which the server caps at 50 whatever is asked for.
            await get(Page.self, url("events", [("parkCode", code), ("dateStart", today), ("pageSize", String(Self.eventsPage)), ("pageNumber", String(number))]), key: key)
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
