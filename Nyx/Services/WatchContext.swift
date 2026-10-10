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
    /// older watch ignores them. So were the models' ranges, in 1.3.)
    static let currentVersion = 1
    static let minimumVersion = 1
    /// WatchConnectivity rejects large contexts; forecasts that would pass this are left out
    /// (those parks are scored with their usual clouds, labelled as such).
    static let byteBudget = 48_000
    let version: Int
    let sent: Date
    let savedParkIDs: [String]
    let homeParkID: String
    let nightVision: Bool
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
    /// The forecasts in the shape the score engine and the widgets already read, expanded once when
    /// the context is made or received, never per score. Not sent: rebuilt from `forecasts`.
    let cloudForecasts: [String: Forecast]
    /// The smoke and summit layers in the shape `NightPlanner.night` reads, expanded once. Not sent.
    let forecastDetails: [String: ForecastDetail]
    /// Only what travels; the expanded forecasts above are rebuilt on arrival.
    enum CodingKeys: String, CodingKey { case version, sent, savedParkIDs, homeParkID, nightVision, forecasts, details, closures, ranges }
    /// What was sent; the expanded forecasts follow from it.
    static func == (a: WatchContext, b: WatchContext) -> Bool {
        a.version == b.version && a.sent == b.sent && a.savedParkIDs == b.savedParkIDs && a.homeParkID == b.homeParkID
            && a.nightVision == b.nightVision && a.forecasts == b.forecasts && a.details == b.details && a.closures == b.closures
            && a.ranges == b.ranges
    }

    init(sent: Date, savedParkIDs: [String], homeParkID: String, nightVision: Bool, forecasts: [String: CompactForecast],
         details: [String: CompactDetail] = [:], closures: [String: String] = [:], ranges: [String: [String: [Int]]] = [:]) {
        self.version = Self.currentVersion
        self.sent = sent; self.savedParkIDs = savedParkIDs; self.homeParkID = homeParkID
        self.nightVision = nightVision; self.forecasts = forecasts; self.details = details; self.closures = closures; self.ranges = ranges
        cloudForecasts = forecasts.compactMapValues(\.forecast); forecastDetails = details.compactMapValues(\.detail)
    }
    /// The context for these saved parks, trimmed to the hours the watch can show (last night
    /// through a week ahead) and to the byte budget, saved parks first in their order. Each park's
    /// clouds go first, then its smoke and summit layers and its models' ranges (which mean
    /// nothing without its clouds); closures, which are short, come last (the followed parks' first).
    static func make(savedParkIDs: [String], homeParkID: String, nightVision: Bool, forecasts: [String: Forecast],
                     details: [String: ForecastDetail] = [:], closures: [String: String] = [:], aboveInversion: Set<String> = [],
                     ranges: [String: [String: ClosedRange<Int>]] = [:], now: Date = .now) -> WatchContext {
        var compact: [String: CompactForecast] = [:], compactDetails: [String: CompactDetail] = [:], sentClosures: [String: String] = [:]
        var sentRanges: [String: [String: [Int]]] = [:]
        let ids = savedParkIDs + (savedParkIDs.contains(homeParkID) ? [] : [homeParkID])
        let from = now.addingTimeInterval(-24*3600), to = now.addingTimeInterval(9*86400)
        // Park IDs and the envelope are small; each forecast is measured on its own.
        var used = 2_000 + ids.reduce(0) { $0 + $1.utf8.count + 4 }
        func fits(_ value: some Encodable, _ id: String) -> Bool {
            guard let size = (try? JSONEncoder().encode(value))?.count, used + size + id.utf8.count + 4 <= byteBudget else { return false }
            used += size + id.utf8.count + 4
            return true
        }
        for id in ids {
            guard let forecast = forecasts[id], let trimmed = CompactForecast(forecast, from: from, to: to) else { continue }
            guard fits(trimmed, id) else { break }
            compact[id] = trimmed
            // Its smoke and summit layers right behind its clouds, so the wrist scores it as the
            // iPhone does; they are left out only once the budget is spent.
            if let detail = details[id], let small = CompactDetail(detail, upper: aboveInversion.contains(id), from: from, to: to), fits(small, id) {
                compactDetails[id] = small
            }
            if let nights = ranges[id]?.filter({ (0...100).contains($0.value.lowerBound) && $0.value.upperBound <= 100 }), !nights.isEmpty {
                let pairs = nights.mapValues { [$0.lowerBound, $0.upperBound] }
                if fits(pairs, id) { sentRanges[id] = pairs }
            }
        }
        let followed = Set(ids)
        for (id, closure) in closures.sorted(by: { (followed.contains($0.key) ? 0 : 1, $0.key) < (followed.contains($1.key) ? 0 : 1, $1.key) }) {
            guard fits(closure, id) else { break }
            sentClosures[id] = closure
        }
        return WatchContext(sent: now, savedParkIDs: savedParkIDs, homeParkID: homeParkID, nightVision: nightVision, forecasts: compact,
                            details: compactDetails, closures: sentClosures, ranges: sentRanges)
    }
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
    /// The same context stamped at another moment, for comparing what it says rather than when.
    func sent(at date: Date) -> WatchContext {
        WatchContext(sent: date, savedParkIDs: savedParkIDs, homeParkID: homeParkID, nightVision: nightVision, forecasts: forecasts, details: details,
                     closures: closures, ranges: ranges)
    }
    /// A night's key in `ranges`: its park-local calendar day, as `WatchLink` writes a date.
    static func day(_ evening: Date, in park: Park) -> String {
        let parts = park.calendar.dateComponents([.year, .month, .day], from: evening)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    /// The models' range to show beside the wrist's own score for this night, or nil. Shown only
    /// as the iPhone shows it (a full forecast, a spread of more than 4 points) and only while it
    /// still holds the score the watch worked out: a range that left the score out would
    /// contradict the number above it, so it is dropped rather than stretched.
    func modelRange(for night: Night) -> ClosedRange<Int>? {
        guard night.basis == .forecast, let pair = ranges[night.park.id]?[Self.day(night.id, in: night.park)], pair.count == 2 else { return nil }
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
        homeParkID = try container.decode(String.self, forKey: .homeParkID)
        savedParkIDs = (try? container.decodeIfPresent([String].self, forKey: .savedParkIDs)) ?? []
        nightVision = (try? container.decodeIfPresent(Bool.self, forKey: .nightVision)) ?? false
        forecasts = ((try? container.decodeIfPresent([String: Lenient<CompactForecast>].self, forKey: .forecasts)) ?? [:]).compactMapValues(\.value)
        details = ((try? container.decodeIfPresent([String: Lenient<CompactDetail>].self, forKey: .details)) ?? [:]).compactMapValues(\.value)
        closures = (try? container.decodeIfPresent([String: String].self, forKey: .closures)) ?? [:]
        // Absent from a 1.2 iPhone's context; a malformed one costs only the ranges.
        ranges = (try? container.decodeIfPresent([String: [String: [Int]]].self, forKey: .ranges)) ?? [:]
        cloudForecasts = forecasts.compactMapValues(\.forecast); forecastDetails = details.compactMapValues(\.detail)
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

/// The moments of one night that change what you can see, in order. Moon events count only
/// between sunset and sunrise (or across the whole night where the Sun never sets or rises).
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
        let from = sky.sunset ?? sky.evening, to = sky.sunrise ?? sky.end
        var all: [NightMilestone] = []
        func add(_ kind: Kind, _ date: Date?) { if let date { all.append(NightMilestone(kind: kind, date: date)) } }
        add(.sunset, sky.sunset); add(.darkStart, sky.darkStart); add(.darkEnd, sky.darkEnd); add(.sunrise, sky.sunrise)
        // A dark window that runs to the night's edge (polar night) has no real crossing there.
        all.removeAll { ($0.kind == .darkStart && $0.date <= sky.evening) || ($0.kind == .darkEnd && $0.date >= sky.end) }
        for (kind, date) in [(Kind.moonrise, sky.moonrise), (.moonset, sky.moonset)] {
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

/// Night-vision red as it reaches the eye: the app multiplies white by this colour. Kept here,
/// in one place, so the contrast of every red text level can be measured in tests.
nonisolated enum NightRed {
    static let red = 1.0, green = 0.27, blue = 0.23
    /// Text opacities the watch uses on black in red: primary, secondary, tertiary.
    static let levels = [1.0, 0.96, 0.86]
    /// WCAG 2 contrast of red at an opacity, composited over black.
    static func contrastOnBlack(opacity: Double) -> Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value/12.92 : pow((value+0.055)/1.055, 2.4) }
        let luminance = 0.2126*linear(red*opacity) + 0.7152*linear(green*opacity) + 0.0722*linear(blue*opacity)
        return (luminance+0.05)/0.05
    }
}
