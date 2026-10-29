import Foundation

/// What the iPhone tells Apple Watch, and nothing more: the saved parks, the starting park, the
/// night-vision switch, the last cloud forecasts, the smoke and summit cloud-layer forecasts the
/// score uses, the parks' closures, and the forecast models' range where the iPhone's dial shows one. The watch never touches the network; it computes the Sun,
/// the Moon and the score itself from these and the bundled parks.
/// Sent as one property-list value (JSON data) through WatchConnectivity, device to device.
nonisolated struct WatchContext: Codable, Sendable, Equatable {
    static let key = "nyx.watch.context"
    /// Bumped when the shape changes. Watch apps update on their own schedule, so a watch reads any
    /// context from `minimumVersion` on: fields added later are optional and unknown ones ignored.
    /// (Details and closures were added that way: a 1.2 watch reads a context without them, and an
    /// older watch ignores them. So were the models' ranges, in 1.3, Tonight's answer, the
    /// watch's own places and the places left out, in 2.2, and the night of Tonight's answer and
    /// the saved spots' cloud switch, after 2.4.)
    static let currentVersion = 1
    static let minimumVersion = 1
    /// WatchConnectivity rejects large contexts; forecasts that would pass this are left out
    /// (those parks are scored with their usual clouds, labelled as such).
    static let byteBudget = 48_000
    let version: Int
    let sent: Date
    /// The iPhone's count of hand-overs, stamped as each is sent (`nextSequence`) and never lower
    /// than the last, even when the iPhone's clock is set back: the watch applies only a higher one
    /// (`isNewer`). Nil from an iPhone before 2.3, and before a context is sent; an older watch ignores it.
    let sequence: Int64?
    let savedParkIDs: [String]
    let homeParkID: String
    let nightVision: Bool
    /// The iPhone's "Brighter red" (Settings › In the dark): the wrist's red follows it, so protan
    /// eyes keep the red they chose on the phone. False from an iPhone before 2.0 (17).
    let brighterRed: Bool
    let forecasts: [String: CompactForecast]
    /// The parts of the forecast detail that change a score: the aerosol forecast (smoke caps) and,
    /// for a summit above the inversion, mid and high cloud. Empty when none was sent.
    let details: [String: CompactDetail]
    /// Each park's closure as Nyx words it beside the score, from the last park update.
    let closures: [String: String]
    /// The forecast models' range of scores the iPhone's dial shows for a park's night
    /// (`NightOutlook.dialRange`): park id → park-local day ("2026-10-10", `day(_:in:)`) →
    /// [lowest, highest]. Two small numbers a night, and only for the nights that have one: the
    /// watch cannot work it out itself, since the three models' clouds stay on the iPhone.
    let ranges: [String: [String: [Int]]]
    /// Saved spots and world catalogue places (`wd:` ids) among the saved parks and the
    /// starting park, whole: the watch bundles only the curated parks, never a place the person saved
    /// or the world catalogue. Empty from an iPhone without either; a watch from before 2.0 ignores it
    /// and simply leaves those places out, as any id it does not know.
    let places: [Place]
    /// The usual clouds of each place in `places`, month by month, from the iPhone's world grid
    /// (`CloudClimate.carriedMonths`): the watch bundles no grid, and without them it would score a
    /// spot or world place with no usual clouds where the forecast does not reach. Empty from an
    /// iPhone before 2.0 (15); an older watch ignores it.
    let usualClouds: [String: CloudClimate.Months]
    /// The place Tonight on the iPhone last answered with (the darkest within its reach), when it
    /// had one: the wrist falls back to it when nothing is kept on the watch or saved. Nil from an
    /// iPhone before 2.2; an older watch ignores it.
    let tonightParkID: String?
    /// The place-local night (`Park.isoDay`, "2026-10-16") Tonight's answer was picked for: the
    /// wrist follows it only while that night is still tonight there (`stillPicks`), as the
    /// iPhone does (`PlanModel.tonightPick`). Nil from an iPhone before it was sent; the night the
    /// context was sent in then stands in.
    let tonightNight: String?
    /// "Clouds at your saved spots" is off on the iPhone: it fetches no clouds for saved spots, so
    /// asking it to refresh one would not help (`CloudSource.spotsOff`). False from an older iPhone.
    let spotForecastsOff: Bool
    /// The places this watch asked the iPhone to follow (the one kept on Tonight and those its
    /// complications are set to), which the iPhone now carries clouds for. Empty from an older iPhone.
    let watchParkIDs: [String]
    /// Followed places whose clouds, smoke and summit layers did not fit the byte budget: the wrist
    /// scores them with their usual clouds and says why (`CloudSource.dropped`). A place travels whole
    /// or not at all (`make`), so one listed here has nothing of its forecast on the wrist, and one
    /// not listed scores with all the iPhone's score counts.
    let droppedParkIDs: [String]
    /// The iPhone's `bundledData`: the watch app updates on its own schedule, so when its own
    /// differs, its scores can differ from the iPhone's and it says so (`dataDiffers`). Nil from an
    /// iPhone before 2.3; an older watch ignores it.
    let dataVersion: String?
    /// NOAA's Kp forecast as the iPhone holds it, from the last twelve hours on (about 30 small
    /// periods), so the wrist names aurora in What's up exactly as the iPhone does
    /// (`AuroraForecast.item`). Nil with "Aurora forecast" off or none fetched, and from an iPhone
    /// before 2.4; an older watch ignores it.
    let aurora: AuroraOutlook?
    /// Where the iPhone's night vision At dusk looks for the Sun when Near me has not found you
    /// (`NightVisionDusk.place`): the chosen town or starting park, never the device's location, which
    /// stays on the iPhone. As [latitude, longitude] to a tenth of a degree (about 11 km; dusk moves
    /// about 24 seconds over that), so the wrist's At dusk turns at the phone's minute. Nil from an
    /// iPhone before it was sent; the wrist then follows the park on Tonight. An older watch ignores it.
    let dusk: [Double]?
    /// The forecasts in the shape the score engine and the widgets already read, expanded once when
    /// the context is made or received, never per score. Not sent: rebuilt from `forecasts`.
    let cloudForecasts: [String: Forecast]
    /// The smoke and summit layers in the shape `NightPlanner.night` reads, expanded once. Not sent.
    let forecastDetails: [String: ForecastDetail]
    /// The climate the watch scores with: the bundled one plus `usualClouds`. Not sent.
    let climate: CloudClimate
    /// Only what travels; the expanded forecasts above are rebuilt on arrival.
    enum CodingKeys: String, CodingKey {
        case version, sent, sequence, savedParkIDs, homeParkID, nightVision, brighterRed, forecasts, details, closures, ranges, places, usualClouds, tonightParkID, watchParkIDs, droppedParkIDs, dataVersion, aurora
        case tonightNight, spotForecastsOff, dusk
    }
    /// What was sent; the expanded forecasts follow from it.
    static func == (a: WatchContext, b: WatchContext) -> Bool {
        a.version == b.version && a.sent == b.sent && a.sequence == b.sequence && a.savedParkIDs == b.savedParkIDs && a.homeParkID == b.homeParkID
            && a.nightVision == b.nightVision && a.brighterRed == b.brighterRed && a.forecasts == b.forecasts && a.details == b.details && a.closures == b.closures
            && a.ranges == b.ranges && a.places == b.places && a.usualClouds == b.usualClouds
            && a.tonightParkID == b.tonightParkID && a.watchParkIDs == b.watchParkIDs && a.droppedParkIDs == b.droppedParkIDs && a.dataVersion == b.dataVersion
            && a.aurora == b.aurora && a.tonightNight == b.tonightNight && a.spotForecastsOff == b.spotForecastsOff && a.dusk == b.dusk
    }

    init(sent: Date, savedParkIDs: [String], homeParkID: String, nightVision: Bool, brighterRed: Bool = false, forecasts: [String: CompactForecast],
         details: [String: CompactDetail] = [:], closures: [String: String] = [:], ranges: [String: [String: [Int]]] = [:], places: [Place] = [],
         usualClouds: [String: CloudClimate.Months] = [:], tonightParkID: String? = nil, watchParkIDs: [String] = [], droppedParkIDs: [String] = [],
         dataVersion: String? = WatchContext.bundledData, sequence: Int64? = nil, aurora: AuroraOutlook? = nil, tonightNight: String? = nil, spotForecastsOff: Bool = false,
         dusk: [Double]? = nil) {
        self.version = Self.currentVersion
        self.dusk = dusk.flatMap(Self.duskPoint)
        self.tonightNight = tonightParkID == nil ? nil : tonightNight; self.spotForecastsOff = spotForecastsOff
        self.aurora = aurora
        self.sequence = sequence
        self.dataVersion = dataVersion
        self.sent = sent; self.savedParkIDs = savedParkIDs; self.homeParkID = homeParkID
        self.nightVision = nightVision; self.brighterRed = brighterRed; self.forecasts = forecasts; self.details = details; self.closures = closures; self.ranges = ranges
        self.places = places; self.usualClouds = usualClouds
        self.tonightParkID = tonightParkID; self.watchParkIDs = watchParkIDs; self.droppedParkIDs = droppedParkIDs
        cloudForecasts = forecasts.compactMapValues(\.forecast); forecastDetails = details.compactMapValues(\.detail)
        climate = CloudClimate.shared.carrying(usualClouds)
    }
    /// How far past its issue a forecast is carried: the ten days it counts for, and a day for the
    /// last night it reaches.
    static let forecastReach: TimeInterval = 11*86400
    /// The context for these saved parks, trimmed to the hours the watch can show (last night
    /// through the forecast's last useful night) and to the byte budget. The followed places are the
    /// saved ones in their order, then the starting park, the iPhone's Tonight answer and the places
    /// the watch asked for (`followed(saved:home:tonight:watch:)`).
    /// A spot or world place travels first, its usual clouds (from `climate`, the iPhone's grid) right behind it.
    /// The followed places' closures come next, before any forecast: a closure is safety, and it is
    /// the forecasts that give way when room runs short. Then every followed place's clouds with its
    /// smoke and summit layers, as one, in order, so the starting park and Tonight's answer are never
    /// left out for a place after them; then the models' ranges (which mean nothing without clouds); the
    /// other parks' closures (a complication can be set to any park) fill what room is left. A place
    /// whose forecast did not fit is named in `droppedParkIDs`, and once one place's does not fit, no
    /// place after it gets any. Never clouds without their smoke: the wrist would show a clear score
    /// where the iPhone's is held down by smoke, as if it were the iPhone's.
    static func make(savedParkIDs: [String], homeParkID: String, nightVision: Bool, brighterRed: Bool = false, forecasts: [String: Forecast],
                     details: [String: ForecastDetail] = [:], closures: [String: String] = [:], aboveInversion: Set<String> = [],
                     ranges: [String: [String: ClosedRange<Int>]] = [:], places: [Place] = [], climate: CloudClimate = .shared,
                     tonightParkID: String? = nil, tonightNight: String? = nil, watchParkIDs: [String] = [], aurora: AuroraOutlook? = nil,
                     spotForecastsOff: Bool = false, dusk: [Double]? = nil, now: Date = .now) -> WatchContext {
        var compact: [String: CompactForecast] = [:], compactDetails: [String: CompactDetail] = [:], sentClosures: [String: String] = [:]
        var sentRanges: [String: [String: [Int]]] = [:]
        let ids = followed(saved: savedParkIDs, home: homeParkID, tonight: tonightParkID, watch: watchParkIDs)
        let from = now.addingTimeInterval(-24*3600)
        // Park IDs and the envelope are small; each forecast is measured on its own.
        var used = 2_000 + (ids+watchParkIDs).reduce(0) { $0 + $1.utf8.count + 4 } + (tonightParkID?.utf8.count ?? 0) + (tonightNight?.utf8.count ?? 0)
        // A value that cannot be encoded never fits.
        func size(_ value: some Encodable, _ id: String) -> Int { ((try? JSONEncoder().encode(value))?.count ?? byteBudget) + id.utf8.count + 4 }
        func fits(_ value: some Encodable, _ id: String) -> Bool { room(size(value, id)) }
        func room(_ size: Int) -> Bool {
            guard used + size <= byteBudget else { return false }
            used += size
            return true
        }
        // A spot or catalogue place first: without its record the watch cannot show it at all, while a
        // forecast left out only costs clouds. Only places that are followed (or the start), in order, once.
        // Its usual clouds (about 150 bytes) travel with it or not at all: without them its nights past the
        // forecast would count no clouds, and the wrist would show a clearer score than the iPhone's.
        var sentPlaces: [Place] = [], placed = Set<String>(), sentUsual: [String: CloudClimate.Months] = [:]
        for place in places where ids.contains(place.id) && placed.insert(place.id).inserted {
            let months = climate.months(for: place)
            guard room(size(place, place.id) + (months.map { size($0, place.id) } ?? 0)) else { break }
            sentPlaces.append(place)
            sentUsual[place.id] = months
        }
        let followed = Set(ids)
        // Each closure the room allows; a long one left out never keeps a shorter one off the wrist.
        func pack(_ closures: [(key: String, value: String)]) {
            for (id, closure) in closures where fits(closure, id) { sentClosures[id] = closure }
        }
        pack(closures.filter { followed.contains($0.key) }.sorted { (ids.firstIndex(of: $0.key) ?? 0) < (ids.firstIndex(of: $1.key) ?? 0) })
        // Kept to the hours that still count: a forecast weighs nothing ten days after it was made
        // (`CloudBasis.forecastWeight`), plus a day so a night that begins before then has all its
        // hours, as on the iPhone. Measured from the forecast, not the clock, so both score alike.
        func reach(_ forecast: Forecast) -> Date { forecast.updated.addingTimeInterval(Self.forecastReach) }
        // A place's clouds, smoke and summit layers travel together or not at all, so the wrist scores
        // as the iPhone does or says why it cannot. Smoke or layers without clouds travel too: the
        // iPhone counts them over the usual clouds, and a summit's layers are its clouds.
        var dropped: [String] = [], full = false
        for id in ids {
            let forecast = forecasts[id]
            let trimmed = forecast.flatMap { CompactForecast($0, from: from, to: reach($0)) }
            let small = details[id].flatMap {
                CompactDetail($0, upper: aboveInversion.contains(id), from: from, to: forecast.map(reach) ?? now.addingTimeInterval(Self.forecastReach))
            }
            guard trimmed != nil || small != nil else { continue }
            guard !full, room((trimmed.map { size($0, id) } ?? 0) + (small.map { size($0, id) } ?? 0)) else { full = true; dropped.append(id); continue }
            compact[id] = trimmed; compactDetails[id] = small
        }
        for id in ids where compact[id] != nil {
            guard let nights = ranges[id]?.filter({ (0...100).contains($0.value.lowerBound) && $0.value.upperBound <= 100 }), !nights.isEmpty else { continue }
            let pairs = nights.mapValues { [$0.lowerBound, $0.upperBound] }
            if fits(pairs, id) { sentRanges[id] = pairs }
        }
        // The aurora forecast, about 1.5 KB, after every followed place's clouds (a score outranks a
        // possible aurora): only the periods still ahead or within the last day, the forecast's own
        // useful age (`AuroraOutlook.maximumAge`), so a polar night that began yesterday evening and
        // runs to noon is still covered from its start, as on the iPhone.
        let sentAurora = aurora.flatMap { outlook -> AuroraOutlook? in
            let kept = AuroraOutlook(updated: outlook.updated, periods: outlook.periods.filter { $0.end > now.addingTimeInterval(-AuroraOutlook.maximumAge) })
            return kept.periods.isEmpty || !fits(kept, "aurora") ? nil : kept
        }
        pack(closures.filter { !followed.contains($0.key) }.sorted { $0.key < $1.key })
        return WatchContext(sent: now, savedParkIDs: savedParkIDs, homeParkID: homeParkID, nightVision: nightVision, brighterRed: brighterRed, forecasts: compact,
                            details: compactDetails, closures: sentClosures, ranges: sentRanges, places: sentPlaces, usualClouds: sentUsual,
                            tonightParkID: tonightParkID, watchParkIDs: watchParkIDs, droppedParkIDs: ids.filter(dropped.contains), aurora: sentAurora,
                            tonightNight: tonightNight, spotForecastsOff: spotForecastsOff, dusk: dusk)
    }
    /// The places the watch is handed, in the order their clouds are packed, once each: the saved
    /// places, the starting park, the iPhone's Tonight answer, then the places the watch asked for.
    static func followed(saved: [String], home: String, tonight: String?, watch: [String]) -> [String] {
        var seen = Set<String>()
        return (saved + [home] + (tonight.map { [$0] } ?? []) + watch).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    /// Every place this context follows: what the iPhone sends clouds for when it can.
    var followedParkIDs: [String] { Self.followed(saved: savedParkIDs, home: homeParkID, tonight: tonightParkID, watch: watchParkIDs) }
    /// Whether Tonight's answer on the iPhone is `place` and still answers at `now`: only while the
    /// night it was picked for is still tonight there, as on the iPhone (`PlanModel.tonightPick`), so a
    /// watch left away from the iPhone for days never shows last week's pick as tonight's.
    func stillPicks(_ place: Park, at now: Date) -> Bool {
        guard place.id == tonightParkID else { return false }
        return place.isoDay(place.currentNight(at: now)) == (tonightNight ?? place.isoDay(place.currentNight(at: sent)))
    }
    /// Whether the watch should tell the iPhone, unasked, which places it wants clouds for
    /// (`wanted`: the one kept on Tonight, then those its faces are set to): when `context` follows
    /// another list (a place kept while the iPhone was out of reach, a face set to a park it does not
    /// follow), unless that same list was told within `retell`, so a place the iPhone cannot follow
    /// (a spot it no longer has) is not asked for at every wake. Lists are compared as sets: faces
    /// reordered ask nothing new. The iPhone's answer does not say which places it cannot follow, so
    /// such a place is asked for again only after `retell`.
    static func shouldTell(_ wanted: [String], context: WatchContext?, told: [String]?, toldAt: Date?, now: Date) -> Bool {
        let wanted = Set(wanted.prefix(maxWatchPlaces))
        guard wanted != Set(context?.watchParkIDs ?? []) else { return false }
        guard let told, let toldAt, Set(told.prefix(maxWatchPlaces)) == wanted else { return true }
        return now.timeIntervalSince(toldAt) >= retell || toldAt > now
    }
    /// The most places a watch asks the iPhone to follow (`WatchRequest.maxPlaces`): more than a
    /// watch could show at once. The watch asks for no more (`WatchSky.wantedPlaces`), so the lists compare.
    static let maxWatchPlaces = 8
    /// The places a watch asks for, once each and at most `maxWatchPlaces`: the one kept on Tonight,
    /// then those its faces are set to (`WatchSky.wantedPlaces`). The iPhone cuts a longer list
    /// (`WatchRequest.places`), so asking for more would only ask again and again.
    static func wanted(pinned: String?, faces: [String]) -> [String] {
        var seen = Set<String>()
        return Array(((pinned.map { [$0] } ?? []) + faces).filter { seen.insert($0).inserted }.prefix(maxWatchPlaces))
    }
    static let retell: TimeInterval = 12*3600
    var data: Data? { try? JSONEncoder().encode(self) }
    var dictionary: [String: Any] { data.map { [Self.key: $0] } ?? [:] }
    init?(dictionary: [String: Any]) {
        guard let data = dictionary[Self.key] as? Data else { return nil }
        self.init(data: data)
    }
    init?(data: Data) {
        guard let decoded = try? JSONDecoder().decode(WatchContext.self, from: data), decoded.version >= Self.minimumVersion else { return nil }
        self = decoded
    }
    /// The same context stamped at another moment, with no sequence, for comparing what it says rather than when.
    func sent(at date: Date) -> WatchContext { stamped(sent: date, sequence: nil) }
    /// The same context as the hand-over numbered `sequence`.
    func numbered(_ sequence: Int64) -> WatchContext { stamped(sent: sent, sequence: sequence) }
    private func stamped(sent date: Date, sequence: Int64?) -> WatchContext {
        WatchContext(sent: date, savedParkIDs: savedParkIDs, homeParkID: homeParkID, nightVision: nightVision, brighterRed: brighterRed, forecasts: forecasts, details: details,
                     closures: closures, ranges: ranges, places: places, usualClouds: usualClouds, tonightParkID: tonightParkID, watchParkIDs: watchParkIDs,
                     droppedParkIDs: droppedParkIDs, dataVersion: dataVersion, sequence: sequence, aurora: aurora, tonightNight: tonightNight, spotForecastsOff: spotForecastsOff,
                     dusk: dusk)
    }
    /// The number for the next hand-over: one past the last, or the clock in milliseconds when that
    /// is higher. A clock set back never lowers it, and a reinstall that forgot the last number still
    /// starts above every number sent before (unless the clock was also set back past them).
    static func nextSequence(after last: Int64?, now: Date = .now) -> Int64 {
        let clock = Int64((now.timeIntervalSince1970*1000).rounded(.down))
        return max((last ?? 0) &+ 1, clock)
    }
    /// Whether the watch should apply `context` over `previous`, the one it holds. Each send can
    /// arrive twice (application context, and a complication transfer), activation hands the stored
    /// one over again, and a queued transfer may arrive late: only a newer one counts. Newer by the
    /// iPhone's sequence when both carry one, so an iPhone clock set back never holds a new context
    /// out; else by when it was sent, as before.
    static func isNewer(_ context: WatchContext, than previous: WatchContext?) -> Bool {
        guard let previous else { return true }
        if let next = context.sequence, let last = previous.sequence { return next > last }
        return context.sent > previous.sent
    }
    /// The bundled data and rules every score rests on, as a short fingerprint: each park's id,
    /// coordinates, time zone, Bortle estimate and summit flag, each park's usual clouds month by
    /// month, and `ScoreEngine.rulesVersion`, in a fixed text form, hashed with 64-bit FNV-1a, in hex.
    /// Descriptions, sources, viewing spots and the measured sky glow (which only breaks ties) are
    /// left out, so an edit to words never reads as different scores. Read once; nil when a file is missing.
    static let bundledData: String? = bundledData(in: .main)
    static func bundledData(in bundle: Bundle) -> String? {
        guard let parks = try? ParkData.load(bundle: bundle), let climate = CloudClimate.load(bundle) else { return nil }
        return fingerprint(parks: parks, climate: climate.parks)
    }
    static func fingerprint(parks: [Park], climate: [String: CloudClimate.Months], rules: Int = ScoreEngine.rulesVersion) -> String {
        func values(_ months: [Int?]) -> String { months.map { $0.map(String.init) ?? "-" }.joined(separator: ",") }
        var text = "rules \(rules)\n"
        for park in parks.sorted(by: { $0.id < $1.id }) {
            text += "\(park.id)|\(park.latitude)|\(park.longitude)|\(park.timeZoneID)|\(park.bortleEstimate)|\(park.aboveInversion == true)\n"
        }
        for (id, months) in climate.sorted(by: { $0.key < $1.key }) { text += "\(id)|\(values(months.cloud))|\(values(months.clear))\n" }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return String(hash, radix: 16)
    }
    /// True when the iPhone's bundled data differs from this device's: the watch then asks to be
    /// updated, since the same night could score differently on each.
    var dataDiffers: Bool {
        guard let dataVersion, let mine = Self.bundledData else { return false }
        return dataVersion != mine
    }
    /// When the iPhone runs a Nyx whose parks, usual clouds or scoring rules differ from this
    /// watch's, the same night could score differently on each: said plainly, on the watch, without
    /// guessing which of the two is older.
    var dataNote: String? { dataDiffers ? Self.versionsNote : nil }
    /// `dusk` as a place for the Sun, or nil.
    var duskPlace: Park? { dusk.map { WristSky.place(latitude: $0[0], longitude: $0[1]) } }
    /// A latitude and longitude to a tenth of a degree, or nil unless it is a real place.
    static func duskPoint(_ point: [Double]) -> [Double]? {
        guard point.count == 2, point.allSatisfy(\.isFinite), abs(point[0]) <= 90, abs(point[1]) <= 180 else { return nil }
        return point.map { ($0*10).rounded()/10 }
    }
    /// The same words on the faces (`FaceNote.versionsDiffer`), spoken.
    static var versionsNote: String { String(localized: "iPhone and Apple Watch have different versions of Nyx. Update both for matching scores.") }
    /// The models' range to show beside the wrist's own score for this night, or nil. Shown only
    /// as the iPhone shows it (a full forecast, a spread of more than 4 points) and only while it
    /// still holds the score the watch worked out: a range that left the score out would
    /// contradict the number above it, so it is dropped rather than stretched.
    func modelRange(for night: Night) -> ClosedRange<Int>? {
        guard night.basis == .forecast, let pair = ranges[night.park.id]?[night.park.isoDay(night.id)], pair.count == 2 else { return nil }
        let low = pair[0], high = pair[1], score = night.score.value
        guard 0 <= low, low <= score, score <= high, high <= 100, high-low > 4 else { return nil }
        return low...high
    }
}

nonisolated extension WatchContext {
    /// Lenient: only the version, the time sent and the starting park are required; a forecast
    /// that no longer decodes leaves that park without clouds instead of dropping the context.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        sent = try container.decode(Date.self, forKey: .sent)
        // Absent before 2.3: compared by `sent`, as before.
        sequence = (try? container.decodeIfPresent(Int64.self, forKey: .sequence)) ?? nil
        homeParkID = try container.decode(String.self, forKey: .homeParkID)
        savedParkIDs = (try? container.decodeIfPresent([String].self, forKey: .savedParkIDs)) ?? []
        nightVision = (try? container.decodeIfPresent(Bool.self, forKey: .nightVision)) ?? false
        // Absent before 2.0 (17): the standard red, as before.
        brighterRed = (try? container.decodeIfPresent(Bool.self, forKey: .brighterRed)) ?? false
        forecasts = ((try? container.decodeIfPresent([String: Lenient<CompactForecast>].self, forKey: .forecasts)) ?? [:]).compactMapValues(\.value)
        details = ((try? container.decodeIfPresent([String: Lenient<CompactDetail>].self, forKey: .details)) ?? [:]).compactMapValues(\.value)
        closures = (try? container.decodeIfPresent([String: String].self, forKey: .closures)) ?? [:]
        // Absent from a 1.2 iPhone's context; a malformed one costs only the ranges.
        ranges = (try? container.decodeIfPresent([String: [String: [Int]]].self, forKey: .ranges)) ?? [:]
        // Absent before 2.0; a spot that no longer decodes is left out, never the context.
        places = ((try? container.decodeIfPresent([Lenient<Place>].self, forKey: .places)) ?? []).compactMap(\.value)
        // Absent before 2.0 (15); one place's months that no longer decode cost only that place's usual clouds.
        usualClouds = ((try? container.decodeIfPresent([String: Lenient<CloudClimate.Months>].self, forKey: .usualClouds)) ?? [:]).compactMapValues(\.value)
        // Absent before 2.2: no Tonight answer, nothing asked for by the watch, nothing known to be left out.
        tonightParkID = (try? container.decodeIfPresent(String.self, forKey: .tonightParkID)) ?? nil
        // Absent from an iPhone up to 2.4: the night the context was sent in stands in (`stillPicks`); spots' clouds read as on.
        tonightNight = tonightParkID == nil ? nil : (try? container.decodeIfPresent(String.self, forKey: .tonightNight)) ?? nil
        spotForecastsOff = (try? container.decodeIfPresent(Bool.self, forKey: .spotForecastsOff)) ?? false
        watchParkIDs = (try? container.decodeIfPresent([String].self, forKey: .watchParkIDs)) ?? []
        // Absent before 2.4 or with the forecast off; a malformed one costs only the aurora item.
        aurora = (try? container.decodeIfPresent(AuroraOutlook.self, forKey: .aurora)) ?? nil
        droppedParkIDs = (try? container.decodeIfPresent([String].self, forKey: .droppedParkIDs)) ?? []
        // Absent before 2.3: nothing to compare, so nothing is said.
        dataVersion = (try? container.decodeIfPresent(String.self, forKey: .dataVersion)) ?? nil
        // Absent from an older iPhone, or with no starting point: the wrist follows the park on Tonight.
        dusk = ((try? container.decodeIfPresent([Double].self, forKey: .dusk)) ?? nil).flatMap(Self.duskPoint)
        cloudForecasts = forecasts.compactMapValues(\.forecast); forecastDetails = details.compactMapValues(\.detail)
        climate = CloudClimate.shared.carrying(usualClouds)
    }
}

/// An hourly cloud series as a start time and values: the times of a clean hourly series are
/// implied, which keeps the context small. A series with gaps is never compacted (it would
/// invent times), so that park shows no clouds rather than wrong ones.
nonisolated struct CompactForecast: Codable, Sendable, Equatable {
    let updated: Date
    let start: Double
    let clouds: [Double?]
    init?(_ forecast: Forecast, from: Date, to: Date) {
        guard let kept = CompactSeries.trim(times: forecast.times, from: from, to: to), forecast.times.count == forecast.clouds.count else { return nil }
        updated = forecast.updated
        start = forecast.times[kept.lowerBound]
        clouds = Array(forecast.clouds[kept])
    }
    var forecast: Forecast? {
        guard !clouds.isEmpty, start.isFinite else { return nil }
        return Forecast(updated: updated, times: clouds.indices.map { start + Double($0)*3600 }, clouds: clouds)
    }
}

/// One `HourlySeries` compacted the same way (start hour and values), keeping only the named
/// variables.
nonisolated struct CompactSeries: Codable, Sendable, Equatable {
    let updated: Date
    let start: Double
    let values: [String: [Double?]]
    init?(_ series: HourlySeries, keys: [String], from: Date, to: Date) {
        guard let kept = Self.trim(times: series.times, from: from, to: to) else { return nil }
        var values: [String: [Double?]] = [:]
        for key in keys {
            guard let all = series.values[key], all.count == series.times.count else { return nil }
            values[key] = Array(all[kept])
        }
        updated = series.updated
        start = series.times[kept.lowerBound]
        self.values = values
    }
    var series: HourlySeries? {
        guard let count = values.values.first?.count, count > 0, start.isFinite, values.values.allSatisfy({ $0.count == count }) else { return nil }
        return HourlySeries(updated: updated, times: (0..<count).map { start + Double($0)*3600 }, values: values)
    }
    /// The indices of a clean hourly series that touch `from`…`to`; nil for a series with gaps.
    static func trim(times: [Double], from: Date, to: Date) -> ClosedRange<Int>? {
        guard !times.isEmpty, times.allSatisfy(\.isFinite), zip(times, times.dropFirst()).allSatisfy({ abs($1-$0-3600) < 0.1 }) else { return nil }
        let keep = times.indices.filter { times[$0]+3600 > from.timeIntervalSince1970 && times[$0] < to.timeIntervalSince1970 }
        guard let first = keep.first, let last = keep.last else { return nil }
        return first...last
    }
}

/// What of a park's forecast detail the score uses, for the watch: the aerosol forecast and, at a
/// summit above the inversion, mid and high cloud. Model spread, cold, dew and wind stay on the iPhone.
nonisolated struct CompactDetail: Codable, Sendable, Equatable {
    var air: CompactSeries?
    var layers: CompactSeries?
    init?(_ detail: ForecastDetail, upper: Bool, from: Date, to: Date) {
        air = detail.air.flatMap { CompactSeries($0, keys: ["aerosol_optical_depth"], from: from, to: to) }
        layers = upper ? detail.layers.flatMap { CompactSeries($0, keys: ["cloud_cover_mid", "cloud_cover_high"], from: from, to: to) } : nil
        if air == nil && layers == nil { return nil }
    }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        air = try? container.decodeIfPresent(CompactSeries.self, forKey: .air)
        layers = try? container.decodeIfPresent(CompactSeries.self, forKey: .layers)
    }
    var detail: ForecastDetail? {
        let air = air?.series, layers = layers?.series
        guard air != nil || layers != nil else { return nil }
        return ForecastDetail(layers: layers, air: air)
    }
}

/// The moments of one night that change what you can see, in order. Moon events count as on the
/// iPhone's field night (`FieldNight`): only for a Moon that matters (`MoonPhase.negligible` is not)
/// and inside the night (`SkyAlmanac.nightWindow`, sunset to sunrise or the midnight sun's cloud window).
nonisolated struct NightMilestone: Sendable, Equatable, Identifiable {
    enum Kind: Int, Sendable, CaseIterable { case sunset, darkStart, moonrise, moonset, darkEnd, sunrise }
    let kind: Kind
    let date: Date
    var id: Int { kind.rawValue }
    var title: String {
        switch kind {
        case .sunset: String(localized: "Sunset")
        case .darkStart: String(localized: "True darkness")
        case .moonrise: String(localized: "Moonrise")
        case .moonset: String(localized: "Moonset")
        case .darkEnd: String(localized: "Dawn twilight")
        case .sunrise: String(localized: "Sunrise")
        }
    }
    /// One word, for the inline complication: "Dark at 7:51 PM".
    var shortTitle: String {
        switch kind {
        case .sunset: String(localized: "Sunset")
        case .darkStart: String(localized: "Dark")
        case .moonrise: String(localized: "Moonrise")
        case .moonset: String(localized: "Moonset")
        case .darkEnd: String(localized: "Dawn")
        case .sunrise: String(localized: "Sunrise")
        }
    }
    static func list(for sky: SkyConditions) -> [NightMilestone] {
        // Within a minute of the window's edges, as the iPhone's list bounds it.
        let window = SkyAlmanac.nightWindow(sky), from = window.start.addingTimeInterval(-60), to = window.end.addingTimeInterval(60)
        var all: [NightMilestone] = []
        func add(_ kind: Kind, _ date: Date?) { if let date { all.append(NightMilestone(kind: kind, date: date)) } }
        add(.sunset, sky.sunset); add(.darkStart, sky.darkStart); add(.darkEnd, sky.darkEnd); add(.sunrise, sky.sunrise)
        // A dark window that runs to the night's edge (polar night) has no real crossing there.
        all.removeAll { ($0.kind == .darkStart && $0.date <= sky.evening) || ($0.kind == .darkEnd && $0.date >= sky.end) }
        for (kind, date) in [(Kind.moonrise, sky.moonrise), (.moonset, sky.moonset)] where !sky.moon.negligible {
            if let date, date >= from, date <= to { all.append(NightMilestone(kind: kind, date: date)) }
        }
        return all.sorted { $0.date == $1.date ? $0.kind.rawValue < $1.kind.rawValue : $0.date < $1.date }
    }
    static func next(after now: Date, in sky: SkyConditions) -> NightMilestone? {
        list(for: sky).first { $0.date > now }
    }
}
extension SkyConditions {
    /// Where the night stands at a moment, for the one-word status beside a countdown.
    nonisolated enum Phase: Sendable, Equatable { case day, twilight, dark }
    nonisolated func phase(at now: Date) -> Phase {
        if let darkStart, let darkEnd, now >= darkStart, now < darkEnd { return .dark }
        if let sunset, now >= sunset, now < (sunrise ?? end) { return .twilight }
        if sunset == nil, state == .polarNight || state == .noAstronomicalDarkness, now >= evening, now < end { return .twilight }
        return .day
    }
}

/// Night-vision red as it reaches the eye: the app multiplies white by the standard red
/// (`NightTint.standard`). The watch's red text levels live here, so each can be measured in tests.
nonisolated enum NightRed {
    /// Text opacities the watch uses on black in red: primary, then muted and faint, which are one
    /// level in red (`NyxPalette.mutedOpacity`, `faintOpacity`).
    static let levels = [1.0, NyxPalette.mutedOpacity(nightVision: true, highContrast: false)]
    /// WCAG 2 contrast of red at an opacity, composited over black.
    static func contrastOnBlack(opacity: Double) -> Double { ColorVision.typical.contrast(NightTint.standard.rgb*opacity, .zero) }
}
