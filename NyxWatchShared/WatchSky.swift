import Foundation
import SwiftUI

/// Everything the watch app and its complications agree on: which park the wrist follows,
/// which palette it wears, and how a night is scored. Shared through the watch's own App Group;
/// nothing here touches the network.
nonisolated enum WatchSky {
    static let contextFile = "watch-context.json"
    static let paletteKey = "watchPalette"
    static let parkKey = "watchPark"
    static var defaults: UserDefaults { SharedSettings.defaults }
    private static var contextURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedSettings.group)?.appendingPathComponent(contextFile)
    }
    /// The last context the iPhone sent; it survives relaunches so the watch works away from the phone.
    static func readContext() -> WatchContext? {
        guard let url = contextURL, let data = try? Data(contentsOf: url) else { return nil }
        return WatchContext(data: data)
    }
    static func save(_ context: WatchContext) {
        guard let url = contextURL, let data = context.data else { return }
        try? data.write(to: url, options: .atomic)
    }
    static var palette: PaletteChoice {
        get { PaletteChoice(rawValue: defaults.string(forKey: paletteKey) ?? "") ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: paletteKey) }
    }
    static let adaptationKey = "watchAdaptationStart"
    /// The Control Center control's kind, reloaded whenever the palette changes.
    static let redLightKind = "NyxRedLight"
    /// When the dark-adaptation clock was started, if it is running.
    static var adaptationStart: Date? {
        get { defaults.object(forKey: adaptationKey) as? Date }
        set { defaults.set(newValue, forKey: adaptationKey) }
    }
    /// A park kept on Tonight from the watch; nil follows the iPhone.
    static var pinnedPark: String? {
        get { defaults.string(forKey: parkKey).flatMap { $0.isEmpty ? nil : $0 } }
        set { defaults.set(newValue ?? "", forKey: parkKey) }
    }
    /// The parks Tonight and the complications weigh, in order: a park kept on the watch; else the
    /// parks saved on iPhone; else the iPhone's starting park. Empty until one of those exists.
    /// Saved spots and world catalogue places arrive whole in the context (`WatchContext.places`); a
    /// bundled park keeps its id.
    static func candidates(in parks: [Park], context: WatchContext?, pinned: String?) -> [Park] {
        let byID = Dictionary((parks + (context?.places ?? [])).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let pinned, let park = byID[pinned] { return [park] }
        let saved = (context?.savedParkIDs ?? []).compactMap { byID[$0] }
        if !saved.isEmpty { return saved }
        return context.flatMap { byID[$0.homeParkID] }.map { [$0] } ?? []
    }
    /// A place by id on the wrist: a bundled park, else a saved spot or catalogue place the iPhone
    /// sent whole (`WatchContext.places`). Nil for an id neither knows.
    static func place(_ id: String, in parks: [Park], context: WatchContext?) -> Park? {
        parks.first { $0.id == id } ?? context?.places.first { $0.id == id }
    }
    /// One night at one park, scored on the watch from the bundled park, the astronomy engine and,
    /// when the iPhone sent them, the cached cloud forecast and the smoke and summit layers, by the
    /// iPhone's own rule (`NightPlanner.night`): without a forecast, the park's usual clouds for the month.
    /// `climate` carries the usual clouds the iPhone sent for spots and world places (`WatchContext.climate`,
    /// `SavedSkySnapshot.climate`); the bundled climate alone knows only the 63 parks.
    static func night(_ park: Park, evening: Date, forecast: Forecast?, detail: ForecastDetail?, now: Date, sky cached: SkyConditions? = nil,
                      climate: CloudClimate = .shared) -> Night {
        NightPlanner.night(park: park, sky: cached ?? AstronomyEngine().conditions(for: park, on: evening), forecast: forecast, detail: detail, now: now, climate: climate)
    }
    /// Write what the complications read: the candidate parks, their forecasts, smoke and layers,
    /// and the usual clouds the iPhone sent for spots and world places.
    static func publish(parks: [Park], context: WatchContext?) {
        SharedSettings.write(snapshot(parks: parks, context: context))
    }
    /// The candidate parks with what the iPhone sent for them, as the complications read it.
    static func snapshot(parks: [Park], context: WatchContext?) -> SavedSkySnapshot {
        let ids = Set(parks.map(\.id))
        let usual = (context?.usualClouds ?? [:]).filter { ids.contains($0.key) }
        return SavedSkySnapshot(parks: parks, forecasts: (context?.cloudForecasts ?? [:]).filter { ids.contains($0.key) },
                                details: (context?.forecastDetails ?? [:]).filter { ids.contains($0.key) },
                                closures: (context?.closures ?? [:]).filter { ids.contains($0.key) }, usualClouds: usual.isEmpty ? nil : usual)
    }
    /// Red or not, for the park Tonight follows at that moment (Automatic reads its Sun).
    static func nightVision(_ choice: PaletteChoice, context: WatchContext?, park: Park?, at now: Date) -> Bool {
        choice.nightVision(phone: context?.nightVision, park: park, at: now)
    }
    /// What a score's clouds rest on when there is no full forecast, in one short honest line.
    static func forecastNote(_ night: Night, context: WatchContext?, short: Bool = false) -> String? {
        guard let label = night.basisLabel else { return nil }
        if short { return label }
        if context == nil, night.basis == .usual { return String(localized: "No cloud forecast yet. Open Nyx on iPhone for clouds.") }
        return night.basisCaption()
    }
}

/// A complication's or the Smart Stack card's tap: the park and night it shows, opened in the
/// watch app. The iPhone's park link with the park-local evening added
/// (`nyx://park/<id>?date=YYYY-MM-DD`, the date as the iPhone's What's up link writes it). A
/// widget's URL goes straight to its own app, so no URL scheme is registered on the watch.
nonisolated struct WatchLink: Hashable, Sendable {
    let parkID: String
    /// The evening's park-local calendar day; nil opens tonight.
    let day: DateComponents?
    init(park: Park, evening: Date?) {
        parkID = park.id
        day = evening.map { park.calendar.dateComponents([.year, .month, .day], from: $0) }
    }
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "nyx", url.host()?.lowercased() == "park",
              let raw = url.pathComponents.first(where: { $0 != "/" }), let id = Self.placeID(raw) else { return nil }
        parkID = id
        let date = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "date" }?.value
        let parts = date?.split(separator: "-").compactMap { Int($0) } ?? []
        day = parts.count == 3 ? DateComponents(year: parts[0], month: parts[1], day: parts[2]) : nil
    }
    /// A place id in its stored form, as the iPhone's links read it (`DeepLink.placeID`): a park's
    /// letters (any case), a Wikidata item (`wd:Q123456`) or a saved spot (`pin:` and a UUID, lowercase).
    static func placeID(_ raw: String) -> String? {
        let raw = raw.contains("%") ? (raw.removingPercentEncoding ?? raw) : raw
        let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 1 {
            guard (2...8).contains(raw.count), raw.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
            return raw.lowercased()
        }
        let rest = parts[1]
        switch parts[0].lowercased() {
        case "wd":
            let digits = rest.dropFirst()
            guard rest.first?.lowercased() == "q", (1...12).contains(digits.count), digits.first != "0",
                  digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return "wd:Q\(digits)"
        case "pin":
            guard rest.count == 36, let uuid = UUID(uuidString: String(rest)) else { return nil }
            return "pin:\(uuid.uuidString.lowercased())"
        default: return nil
        }
    }
    var url: URL? {
        var components = URLComponents()
        components.scheme = "nyx"
        components.host = "park"
        components.path = "/" + parkID
        if let day, let year = day.year, let month = day.month, let date = day.day {
            components.queryItems = [URLQueryItem(name: "date", value: String(format: "%04d-%02d-%02d", year, month, date))]
        }
        return components.url
    }
    /// Nights after tonight at `park` (0…`limit`); a night already past, or none given, is tonight.
    func offset(in park: Park, now: Date, limit: Int) -> Int {
        guard let day, let evening = park.calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else { return 0 }
        let days = park.calendar.dateComponents([.day], from: park.currentNight(at: now), to: evening).day ?? 0
        return min(limit, max(0, days))
    }
}

extension Park {
    /// The name as it fits a wrist: "American Samoa", not "National Park of American Samoa".
    nonisolated var wristName: String { shortName.replacingOccurrences(of: "National Park of ", with: "") }
}

extension NyxPalette {
    /// The quietest text level on the watch (past milestones); still ≥ 4.5:1 on black in red.
    var faint: Color { ink.opacity(nightVision ? NightRed.levels[2] : 0.62) }
}
