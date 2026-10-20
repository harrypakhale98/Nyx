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
    /// Called with each place's whole detail as the service keeps a request's answer, as it lands
    /// (`StoreObserver`), whether or not anyone still waits for that request.
    func observe(_ handler: @escaping @Sendable ([String: ForecastDetail]) async -> Void)
}
nonisolated extension DetailProviding {
    /// A provider without catalogue smoke (a test double) has none to give.
    func catalogAir(_ requests: [[Park]], network: Bool, force: Bool) async -> [String: ForecastDetail] { [:] }
    /// A provider that never fetches (a test double) has nothing to hand on.
    func observe(_ handler: @escaping @Sendable ([String: ForecastDetail]) async -> Void) {}
}
/// The forecast's context, beside the score's own clouds: three models' clouds, cloud layers,
/// cold, dew, wind, visibility, rain, weather and water vapour (seven days), and the aerosol and
/// dust forecast that warns of smoke.
/// Like clouds, every park shares each request, so a refresh is three more requests (two chunks
/// each for 63 parks), never one per park, and none of them hints at where someone is. Each part
/// keeps its own twelve-hour freshness (`ForecastReuse`); a failed request keeps the last good
/// part, and one the service answered with nothing usable waits before it is sent again
/// (`ForecastReuse.retryable`). Requests to one host go one after the other, never side by side,
/// within this device's budget (`CallBudget`); each answer is kept as it lands. Detail never uses a
/// Low Data Mode network: it is context, and the score's clouds still arrive.
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
    /// The catalogue smoke request under way, if any, with the places it asked about; a later caller
    /// waits for it, then decides again what is due.
    private var catalogAirRunning: (task: Task<Void, Never>, attempted: Set<String>)?
    /// Catalogue smoke parts this device's own budget held back, sent once its minute has passed
    /// (`followUp`), by their first places; a refresh meanwhile leaves them to it.
    private var catalogAirFollowUp: (task: Task<Void, Never>, parts: Set<String>)?
    /// When each place was last sent and answered with nothing usable for it, by kind
    /// (`ForecastReuse.retryable`); cleared by a usable answer.
    private var tried: [Kind: [String: Date]] = [:]
    private let observer=StoreObserver<[String: ForecastDetail]>()
    /// Waits out the browsing budget's minute before held-back catalogue smoke goes; tests pass their own.
    private let pause: @Sendable (TimeInterval) async -> Void
    nonisolated func observe(_ handler: @escaping @Sendable ([String: ForecastDetail]) async -> Void) { observer.set(handler) }
    init(transport: any HTTPTransport = SafeHTTP(), persist: Bool = true, backoff: HostBackoff? = nil, ledger: CallLedger? = nil,
         budget: CallBudget = .standard, extras: Bool = true, clock: @escaping @Sendable () -> Date = { .now },
         pause: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.transport=transport; self.persist=persist; self.clock=clock; self.budget=budget; self.extras=extras; self.pause=pause
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
                        && ForecastReuse.retryable(tried[kind]?[park.id], now: now, force: force)
                }
                for start in stride(from: 0, to: due.count, by: 50) { jobs.append((kind, Array(due[start..<min(due.count, start+50)]))) }
            }
            if !jobs.isEmpty {
                let generation=airGeneration
                // One host's requests one after the other (Open-Meteo serves one at a time per
                // address and queues the rest); the two hosts side by side. Each answer is kept as it
                // arrives, so smoke never waits for the forecast host's longer queue.
                let byHost=Dictionary(grouping: jobs) { $0.0.host }.values.map { Array($0) }
                let task=Task {
                    let lowData=await withTaskGroup(of: Bool.self) { group in
                        for queue in byHost {
                            group.addTask {
                                var paused=false
                                for (kind, chunk) in queue {
                                    guard !Task.isCancelled else { break }
                                    let fetched=await self.fetch(kind, chunk)
                                    if fetched == nil { paused=true }
                                    await self.store([(kind, fetched)], airGeneration: generation)
                                    // A host that now asks Nyx to wait: the rest of its queue waits too.
                                    if fetched?.isEmpty == true && !self.backoff.allows(kind.host, now: self.clock()) { break }
                                }
                                return paused
                            }
                        }
                        var any=false
                        for await paused in group { any = any || paused }
                        return any
                    }
                    self.lowData=lowData
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
    /// Smoke at world catalogue places: each request of `CatalogForecast.Regions` in its fixed parts of
    /// `catalogAirChunk` (`airParts`), with the same public coordinates as its clouds, to the
    /// air-quality host, within the browsing budget, so looking around the world never leaves the parks'
    /// smoke without room. Each part is due on its own, as its places' smoke ages; a part is always
    /// asked whole, never one place alone. A part the budget holds back goes once its minute has
    /// passed (`followUp`), else on the next refresh. Kept on disk.
    func catalogAir(_ requests: [[Park]], network: Bool, force: Bool = false) async -> [String: ForecastDetail] {
        let places=Array(requests.joined())
        for place in places { load(place.id) }
        guard network else { return kept(places) }
        // Another catalogue request is on its way (perhaps for another region): wait for it, then
        // decide again what is due, leaving out the places it already asked about. A cancelled
        // caller stops waiting and returns what is kept; the request finishes and stores itself.
        var attempted=Set<String>()
        while let current=catalogAirRunning {
            waiting+=1
            let finished=await SharedRequest.value(of: current.task) != nil
            waiting-=1
            guard finished else { return kept(places) }
            attempted.formUnion(current.attempted)
        }
        let now=clock()
        guard backoff.allows(Kind.air.host, now: now) else { return kept(places) }
        let followed=catalogAirFollowUp?.parts ?? []
        let due=Self.airParts(requests).filter { part in
            guard let first=part.first?.id, !attempted.contains(first), !followed.contains(first) else { return false }
            return airDue(part, now: now, force: force)
        }
        guard !due.isEmpty else { return kept(places) }
        let generation=airGeneration
        let task=Task {
            let held=await self.sendAir(due, generation: generation)
            self.followUp(held, generation: generation)
            self.catalogAirRunning=nil
        }
        catalogAirRunning=(task, Set(due.joined().map(\.id)))
        waiting+=1
        _=await SharedRequest.value(of: task)
        waiting-=1
        return kept(places)
    }
    /// Each catalogue request in its parts of at most `catalogAirChunk` places (`CatalogForecast.chunks`):
    /// fixed for the same catalogue, so a part asked alone is always the same part.
    static func airParts(_ requests: [[Park]]) -> [[Park]] {
        requests.filter { !$0.isEmpty && $0.count <= CatalogForecast.maxPointsPerRequest }.flatMap { CatalogForecast.chunks($0, limit: catalogAirChunk) }
    }
    /// A part's places arrive together, so it is due as its freshest smoke is, unless it was just
    /// answered with nothing usable (`ForecastReuse.retryable`).
    private func airDue(_ part: [Park], now: Date, force: Bool) -> Bool {
        ForecastReuse.due(part.compactMap { memory[$0.id]?.air?.updated }.max(), now: now, force: force, normal: Self.freshFor, forced: Kind.air.forced)
            && ForecastReuse.retryable(part.compactMap { tried[.air]?[$0.id] }.max(), now: now, force: force)
    }
    /// Sends catalogue smoke parts one after the other, keeping each answer as it lands. Returns the
    /// parts this device's browsing budget held back; a service that asks Nyx to wait stops the rest.
    private func sendAir(_ parts: [[Park]], generation: Int) async -> [[Park]] {
        for (index, part) in parts.enumerated() {
            guard !Task.isCancelled, generation == airGeneration, backoff.allows(Kind.air.host, now: clock()) else { break }
            // Over this minute's, hour's or day's budget: this part and the rest wait.
            guard fits(part, at: clock()) else { return Array(parts[index...]) }
            let fetched=await fetch(.air, part, caps: budget.browsing)
            store([(.air, fetched)], airGeneration: generation)
        }
        return []
    }
    /// Whether a catalogue smoke part fits the browsing budget at `date`.
    private func fits(_ part: [Park], at date: Date) -> Bool {
        guard let url=request(.air, part)?.url else { return false }
        return ledger.allows(Kind.air.host, calls: CallWeight.of(url), caps: budget.browsing, now: date)
    }
    /// Parts the browsing budget held back go once its minute has passed (a few seconds on, so devices
    /// held together do not return together), round by round while each round sends some; never
    /// while the hour's or the day's budget is what holds them: the next refresh asks then.
    private func followUp(_ held: [[Park]], generation: Int) {
        guard !held.isEmpty, catalogAirFollowUp == nil, generation == airGeneration else { return }
        let task=Task {
            var left=held
            while let next=left.first, generation == self.airGeneration {
                let now=self.clock()
                let minute=CallLedger.windowStart(now, length: 60).addingTimeInterval(60)
                guard self.fits(next, at: minute) else { break }
                await self.pause(minute.timeIntervalSince(now)+Double.random(in: 1..<10))
                guard !Task.isCancelled else { break }
                // A part kept meanwhile (a refresh got there first) is no longer due.
                let still=left.filter { self.airDue($0, now: self.clock(), force: false) }
                let again=await self.sendAir(still, generation: generation)
                guard again.count<still.count else { break }
                left=again
            }
            self.catalogAirFollowUp=nil
        }
        catalogAirFollowUp=(task, Set(held.compactMap(\.first?.id)))
    }
    /// Lets the catalogue smoke held back by the budget finish (tests).
    func followUpFinished() async { await catalogAirFollowUp?.task.value }
    private func kept(_ parks: [Park]) -> [String: ForecastDetail] {
        var result: [String: ForecastDetail] = [:]
        for park in parks { if let detail=memory[park.id] { result[park.id]=detail } }
        return result
    }
    /// Keeps what arrived, on disk too, and hands it on (`observe`). A nil part was held back by Low
    /// Data Mode. Smoke asked for before the latest `forgetAir` is not stored: the switch went off
    /// while it was on its way.
    private func store(_ results: [(Kind, [(String, HourlySeries)]?)], airGeneration generation: Int) {
        var changed=Set<String>()
        for (kind, fetched) in results {
            if kind == .air && generation != airGeneration { continue }
            for (id, series) in fetched ?? [] {
                var detail=memory[id] ?? ForecastDetail()
                switch kind { case .models: detail.models=series; case .layers: detail.layers=series; case .air: detail.air=series; airCleared=false }
                memory[id]=detail; changed.insert(id)
            }
        }
        if persist { for id in changed { if let detail=memory[id] { CacheDirectory.write(detail, name: "detail-\(id)") } } }
        var landed: [String: ForecastDetail]=[:]
        for id in changed { landed[id]=memory[id] }
        if !landed.isEmpty { observer.send(landed) }
    }
    private static func series(_ detail: ForecastDetail?, _ kind: Kind) -> HourlySeries? {
        switch kind { case .models: detail?.models; case .layers: detail?.layers; case .air: detail?.air }
    }
    /// One kind's request for these places: its URL, the series a place's answer must hold
    /// (`ForecastDetail.layerRequired`, `airRequired`; the models all three), and the context kept
    /// when it comes whole.
    private func request(_ kind: Kind, _ parks: [Park]) -> (url: URL, required: [String], context: [String])? {
        var parts=URLComponents()
        parts.scheme="https"
        var items=[URLQueryItem(name: "latitude", value: parks.map { String($0.forecastPoint.latitude) }.joined(separator: ",")),
                   URLQueryItem(name: "longitude", value: parks.map { String($0.forecastPoint.longitude) }.joined(separator: ","))]
        let asked: [String], required: [String]
        switch kind {
        case .models:
            parts.host="api.open-meteo.com"; parts.path="/v1/forecast"; asked=ForecastDetail.modelKeys; required=asked
            items+=[URLQueryItem(name: "hourly", value: "cloud_cover"), URLQueryItem(name: "models", value: "gfs_seamless,ecmwf_ifs025,icon_seamless")]
        case .layers:
            parts.host="api.open-meteo.com"; parts.path="/v1/forecast"; asked=ForecastDetail.layerKeys+(extras ? ForecastDetail.layerExtras : []); required=ForecastDetail.layerRequired
            items.append(URLQueryItem(name: "hourly", value: asked.joined(separator: ",")))
        case .air:
            // CAMS global covers every park, Alaska and American Samoa included.
            parts.host="air-quality-api.open-meteo.com"; parts.path="/v1/air-quality"; asked=ForecastDetail.airKeys+(extras ? ForecastDetail.airExtras : []); required=ForecastDetail.airRequired
            items+=[URLQueryItem(name: "hourly", value: asked.joined(separator: ",")), URLQueryItem(name: "domains", value: "cams_global")]
        }
        parts.queryItems=items+[URLQueryItem(name: "forecast_days", value: "7"), URLQueryItem(name: "past_days", value: "1"),
                                URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "timezone", value: "GMT")]
        return parts.url.map { ($0, required, asked.filter { !required.contains($0) }) }
    }
    /// Nil when Low Data Mode held the request back; empty when it failed any other way.
    /// `caps`: the browsing budget for the catalogue's smoke; the essential one otherwise.
    /// A place the service answered for without what the score needs (or refused) is noted in
    /// `tried`, so it is not asked again on every refresh.
    private func fetch(_ kind: Kind, _ parks: [Park], caps: CallBudget.Caps? = nil) async -> [(String, HourlySeries)]? {
        guard !parks.isEmpty, let request=request(kind, parks) else { return [] }
        let data: Data
        do { data=try await ForecastRequest.get(request.url, transport: transport, constrained: false, backoff: backoff, ledger: ledger, caps: caps ?? budget.essential, clock: clock) } catch {
            if error is HTTPStatusError { note(kind, parks.map(\.id), kept: []) }
            return Backoff.constrained(error) ? nil : []
        }
        let series=OpenMeteoAnswer.series(data, ids: parks.map(\.id), keys: request.required, extras: request.context, now: clock())
        note(kind, parks.map(\.id), kept: series.map(\.0))
        return series
    }
    /// Places answered without a usable series are tried again later (`ForecastReuse.retryable`); the rest are clear.
    private func note(_ kind: Kind, _ ids: [String], kept: [String]) {
        let now=clock(), usable=Set(kept)
        for id in ids { tried[kind, default: [:]][id]=usable.contains(id) ? nil : now }
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
    /// Called with a park's id and its programs whenever a programs request is kept, as it lands
    /// (`StoreObserver`), whether or not its page still waits for it.
    func observePrograms(_ handler: @escaping @Sendable ((String, ProgramsCache)) async -> Void)
}
extension ParkProviding {
    /// A provider that never fetches (a test double) has nothing to hand on.
    nonisolated func observePrograms(_ handler: @escaping @Sendable ((String, ProgramsCache)) async -> Void) {}
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
    /// The last alerts request was refused (the quota spent, a refused key, a server error); a
    /// failure anywhere else (programs, campgrounds, a Wi-Fi sign-in page) says nothing about alerts.
    private var refused=false
    private var programCache: [String: ProgramsCache] = [:]
    private var programsLoaded=Set<String>()
    private var programTasks: [String: Task<Void, Never>] = [:]
    /// When each park's programs request was last answered without programs (refused, or unreadable),
    /// so opening its page again does not ask on every visit (`retryable`).
    private var programsTried: [String: Date] = [:]
    private let programsObserver=StoreObserver<(String, ProgramsCache)>()
    nonisolated func observePrograms(_ handler: @escaping @Sendable ((String, ProgramsCache)) async -> Void) { programsObserver.set(handler) }
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
        // Another screen's request is on its way: wait for it and take what it brought, never sending
        // it again: one that failed without a backoff (a timeout) is not repeated once per waiter.
        // The task clears itself before it finishes, so a waiter never sees a request that has
        // already ended. A cancelled caller stops waiting and returns what is cached.
        if let running=alertsTask {
            _=await wait(for: running)
            return AlertsUpdate(cache: alertCache, busy: busy)
        }
        guard Self.stale(alertCache?.updated, maxAge: 6*3600, force: force, now: clock()) else { return AlertsUpdate(cache: alertCache, busy: busy) }
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
        // A request for this park on its way: its answer, never a second request. A cancelled caller
        // stops waiting and returns what is cached, as for alerts.
        if let running=programTasks[park.id] {
            _=await SharedRequest.value(of: running)
            return programCache[park.id]
        }
        let now=clock()
        guard Self.stale(programCache[park.id]?.updated, maxAge: 24*3600, force: force, now: now), Self.retryable(programsTried[park.id], force: force, now: now),
              backoff.allows(Self.host, now: now) else { return programCache[park.id] }
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
        if let running=campgroundsTask {
            _=await SharedRequest.value(of: running)
            return campgroundCache
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
            guard let data=await data(url("campgrounds", [("parkCode", codes.joined(separator: ",")), ("limit", "500"), ("start", String(read))]), key: key, constrained: false).data,
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
    /// After a request NPS answered with nothing usable, the same request waits an hour, or ten
    /// minutes when pulled to refresh.
    static func retryable(_ tried: Date?, force: Bool, now: Date) -> Bool { stale(tried, maxAge: 3600, force: force, now: now) }
    static func usable(_ key: String) -> Bool { !key.isEmpty && !key.contains("$(") }
    private func url(_ path: String, _ query: [(String, String)]) -> URL? {
        var c=URLComponents(); c.scheme="https"; c.host="developer.nps.gov"; c.path="/api/v1/\(path)"
        c.queryItems=query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return c.url
    }
    /// The decoded body, or nil; `answered` when NPS answered (an unreadable body or a refusal)
    /// rather than the request failing on its way; `refusal` its error status, if any.
    private func get<T: Decodable>(_ type: T.Type, _ url: URL?, key: String) async -> (value: T?, answered: Bool, refusal: HTTPStatusError?) {
        let reply=await data(url, key: key, constrained: true)
        guard let data=reply.data else { return (nil, reply.refusal != nil, reply.refusal) }
        return (try? JSONDecoder().decode(type, from: data), true, nil)
    }
    /// The body of a request that may wait for an unconstrained network: Low Data Mode holding it
    /// back is not a refusal and starts no backoff. `refusal`: the error status NPS answered with.
    private func data(_ url: URL?, key: String, constrained: Bool) async -> (data: Data?, refusal: HTTPStatusError?) {
        guard let url else { return (nil, nil) }
        do {
            let data=try await transport.get(url, headers: ["X-Api-Key": key], constrained: constrained)
            backoff.succeeded(Self.host)
            return (data, nil)
        } catch {
            if Backoff.constrained(error) { return (nil, nil) }
            backoff.record(error, host: Self.host, now: clock())
            return (nil, error as? HTTPStatusError)
        }
    }
    /// An answer that means NPS is refusing alerts: the shared key's quota spent (429), the key
    /// refused (401, 403), or the service struggling (5xx). A redirect (a Wi-Fi sign-in page) or
    /// another 4xx is not.
    static func refuses(_ status: Int) -> Bool { status == 429 || status == 401 || status == 403 || (500..<600).contains(status) }
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
            let reply=await get(Page.self, url("alerts", [("parkCode", codes.joined(separator: ",")), ("limit", "500"), ("start", String(read))]), key: key)
            if let status=reply.refusal?.status, Self.refuses(status) { refused=true } else if reply.value != nil { refused=false }
            guard let page=reply.value else { return false }
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
        // Only an event's id and title are needed to list it; anything else missing or of another
        // type reads as absent, and an event that still cannot be read costs only itself.
        struct Event: Decodable {
            let id: String, title: String, datestart: String?, description: String, tags: [String]?, dates: [String]?, times: [Time]?, location: String?
            enum CodingKeys: String, CodingKey { case id, title, datestart, description, tags, dates, times, location }
            init(from decoder: any Decoder) throws {
                let c=try decoder.container(keyedBy: CodingKeys.self)
                id=try c.decode(String.self, forKey: .id); title=try c.decode(String.self, forKey: .title)
                datestart=try? c.decodeIfPresent(String.self, forKey: .datestart)
                description=(try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
                tags=try? c.decodeIfPresent([String].self, forKey: .tags); dates=try? c.decodeIfPresent([String].self, forKey: .dates)
                times=try? c.decodeIfPresent([Time].self, forKey: .times); location=try? c.decodeIfPresent(String.self, forKey: .location)
            }
        }
        struct Page: Decodable {
            let data: [Lenient<Event>]; let total: String?
            enum CodingKeys: String, CodingKey { case data, total }
            init(from decoder: any Decoder) throws {
                let c=try decoder.container(keyedBy: CodingKeys.self)
                data=try c.decode([Lenient<Event>].self, forKey: .data)
                total=try? c.decodeIfPresent(String.self, forKey: .total)
            }
        }
        // Ranger programs are the National Park Service's: a place it does not run has none to ask for.
        guard let code=park.nps else { return }
        let today=park.isoDay(clock())
        func page(_ number: Int) async -> Page? {
            // Events page with pageSize, which the server caps at 50 whatever is asked for.
            let reply=await get(Page.self, url("events", [("parkCode", code), ("dateStart", today), ("pageSize", String(Self.eventsPage)), ("pageNumber", String(number))]), key: key)
            // Answered, but not with programs: not asked again on every visit to the page.
            if reply.value == nil, reply.answered { programsTried[park.id]=clock() }
            return reply.value
        }
        guard let first=await page(1) else { return }
        var events=first.data.compactMap(\.value)
        let pages=Self.eventPages(total: first.total)
        if pages>1 {
            for number in 2...pages {
                guard let more=await page(number) else { return }
                events+=more.data.compactMap(\.value)
            }
        }
        let programs=events.filter { Self.isNightSky(title: $0.title, tags: $0.tags ?? []) }.flatMap { event in
            (event.dates ?? event.datestart.map { [$0] } ?? []).filter { $0 >= today }.map { day in RangerProgram(id: event.id+day, title: event.title, date: day, description: Self.plain(event.description),
                time: event.times?.first.flatMap { RangerProgram.timeRange(start: $0.timestart, end: $0.timeend) }, location: RangerProgram.place(event.location)) }
        }.sorted { $0.date<$1.date }
        let fresh=ProgramsCache(updated: clock(), programs: programs)
        programCache[park.id]=fresh; programsTried[park.id]=nil
        if persist { CacheDirectory.write(fresh, name: "programs-\(park.id)") }
        programsObserver.send((park.id, fresh))
    }
    /// How many pages of events to read for NPS's `total`, at most ten: a total that is not a whole
    /// number of events (missing, negative, "NaN") reads as one page, never a crash.
    static func eventPages(total: String?) -> Int {
        let count=min(max(total.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0, 0), 10*eventsPage)
        return (count+eventsPage-1)/eventsPage
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
