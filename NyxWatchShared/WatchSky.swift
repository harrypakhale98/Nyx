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
        get { PaletteChoice(rawValue: defaults.string(forKey: paletteKey) ?? "") ?? .red }
        set { defaults.set(newValue.rawValue, forKey: paletteKey) }
    }
    /// A park kept on Tonight from the watch; nil follows the iPhone.
    static var pinnedPark: String? {
        get { defaults.string(forKey: parkKey).flatMap { $0.isEmpty ? nil : $0 } }
        set { defaults.set(newValue ?? "", forKey: parkKey) }
    }
    /// The parks Tonight and the complications weigh, in order: a park kept on the watch; else the
    /// parks saved on iPhone; else the iPhone's starting park. Empty until one of those exists.
    static func candidates(in parks: [Park], context: WatchContext?, pinned: String?) -> [Park] {
        let byID = Dictionary(parks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let pinned, let park = byID[pinned] { return [park] }
        let saved = (context?.savedParkIDs ?? []).compactMap { byID[$0] }
        if !saved.isEmpty { return saved }
        return context.flatMap { byID[$0.homeParkID] }.map { [$0] } ?? []
    }
    /// One night at one park, scored on the watch from the bundled park, the astronomy engine and,
    /// when the iPhone sent one, the cached cloud forecast. A missing forecast is never treated as clear.
    static func night(_ park: Park, evening: Date, forecast: Forecast?, now: Date, sky cached: SkyConditions? = nil) -> Night {
        let sky = cached ?? AstronomyEngine().conditions(for: park, on: evening)
        let clouds = forecast?.mean(from: sky.cloudWindow.start, to: sky.cloudWindow.end, now: now)
        return Night(park: park, sky: sky, score: ScoreEngine().score(sky: sky, bortle: park.bortleEstimate, cloudCover: clouds),
                     cloudCover: clouds, forecastUpdated: clouds == nil ? nil : forecast?.updated)
    }
    /// Write what the complications read: the candidate parks and their forecasts.
    static func publish(parks: [Park], context: WatchContext?) {
        let ids = Set(parks.map(\.id))
        SharedSettings.write(SavedSkySnapshot(parks: parks, forecasts: (context?.cloudForecasts ?? [:]).filter { ids.contains($0.key) }))
    }
    static func nightVision(_ choice: PaletteChoice, context: WatchContext?) -> Bool {
        switch choice {
        case .red: true
        case .standard: false
        // Before the first sync, red: at a dark site that is the safe default.
        case .phone: context?.nightVision ?? true
        }
    }
    /// Why a score has no clouds in it, in one short honest line.
    static func forecastNote(_ night: Night, context: WatchContext?, short: Bool = false) -> String? {
        guard !night.score.hasForecast else { return nil }
        if short { return String(localized: "Moon and darkness only") }
        return context == nil ? String(localized: "Moon and darkness only. Open Nyx on iPhone for clouds.")
            : String(localized: "Moon and darkness only. No cloud forecast for this night.")
    }
}

nonisolated enum PaletteChoice: String, CaseIterable, Identifiable, Sendable {
    case red, phone, standard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .red: String(localized: "Red light")
        case .phone: String(localized: "Match iPhone")
        case .standard: String(localized: "Starlight")
        }
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
