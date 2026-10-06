import Foundation

/// What the iPhone tells Apple Watch, and nothing more: the saved parks, the starting park, the
/// night-vision switch and the last cloud forecasts. The watch never touches the network; it
/// computes the Sun, the Moon and the score itself from these and the bundled parks.
/// Sent as one property-list value (JSON data) through WatchConnectivity, device to device.
nonisolated struct WatchContext: Codable, Sendable, Equatable {
    static let key = "nyx.watch.context"
    /// Bumped when the shape changes; an older or newer context is ignored, never misread.
    static let currentVersion = 1
    /// WatchConnectivity rejects large contexts; forecasts that would pass this are left out
    /// (those parks show moon and darkness only, labelled as such).
    static let byteBudget = 48_000
    let version: Int
    let sent: Date
    let savedParkIDs: [String]
    let homeParkID: String
    let nightVision: Bool
    let forecasts: [String: CompactForecast]

    init(sent: Date, savedParkIDs: [String], homeParkID: String, nightVision: Bool, forecasts: [String: CompactForecast]) {
        self.version = Self.currentVersion
        self.sent = sent; self.savedParkIDs = savedParkIDs; self.homeParkID = homeParkID
        self.nightVision = nightVision; self.forecasts = forecasts
    }
    /// The context for these saved parks, trimmed to the hours the watch can show (last night
    /// through a week ahead) and to the byte budget, saved parks first in their order.
    static func make(savedParkIDs: [String], homeParkID: String, nightVision: Bool, forecasts: [String: Forecast], now: Date = .now) -> WatchContext {
        var compact: [String: CompactForecast] = [:]
        let ids = savedParkIDs + (savedParkIDs.contains(homeParkID) ? [] : [homeParkID])
        // Park IDs and the envelope are small; each forecast is measured on its own.
        var used = 2_000 + ids.reduce(0) { $0 + $1.utf8.count + 4 }
        for id in ids {
            guard let forecast = forecasts[id], let trimmed = CompactForecast(forecast, from: now.addingTimeInterval(-24*3600), to: now.addingTimeInterval(9*86400)),
                  let size = (try? JSONEncoder().encode(trimmed))?.count else { continue }
            guard used + size + id.utf8.count + 4 <= byteBudget else { break }
            used += size + id.utf8.count + 4
            compact[id] = trimmed
        }
        return WatchContext(sent: now, savedParkIDs: savedParkIDs, homeParkID: homeParkID, nightVision: nightVision, forecasts: compact)
    }
    var data: Data? { try? JSONEncoder().encode(self) }
    var dictionary: [String: Any] { data.map { [Self.key: $0] } ?? [:] }
    init?(dictionary: [String: Any]) {
        guard let data = dictionary[Self.key] as? Data else { return nil }
        self.init(data: data)
    }
    init?(data: Data) {
        guard let decoded = try? JSONDecoder().decode(WatchContext.self, from: data), decoded.version == Self.currentVersion else { return nil }
        self = decoded
    }
    /// The forecasts in the shape the score engine and the widgets already read.
    var cloudForecasts: [String: Forecast] { forecasts.compactMapValues(\.forecast) }
}

/// An hourly cloud series as a start time and values: the times of a clean hourly series are
/// implied, which keeps the context small. A series with gaps is never compacted (it would
/// invent times), so that park shows no clouds rather than wrong ones.
nonisolated struct CompactForecast: Codable, Sendable, Equatable {
    let updated: Date
    let start: Double
    let clouds: [Double?]
    init?(_ forecast: Forecast, from: Date, to: Date) {
        let times = forecast.times
        guard !times.isEmpty, times.count == forecast.clouds.count, times.allSatisfy(\.isFinite),
              zip(times, times.dropFirst()).allSatisfy({ abs($1-$0-3600) < 0.1 }) else { return nil }
        let keep = times.indices.filter { times[$0]+3600 > from.timeIntervalSince1970 && times[$0] < to.timeIntervalSince1970 }
        guard let first = keep.first, let last = keep.last else { return nil }
        updated = forecast.updated
        start = times[first]
        clouds = Array(forecast.clouds[first...last])
    }
    var forecast: Forecast? {
        guard !clouds.isEmpty, start.isFinite else { return nil }
        return Forecast(updated: updated, times: clouds.indices.map { start + Double($0)*3600 }, clouds: clouds)
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
