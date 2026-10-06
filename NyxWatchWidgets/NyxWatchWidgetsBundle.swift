import AppIntents
import SwiftUI
import WidgetKit

@main struct NyxWatchWidgetsBundle: WidgetBundle {
    var body: some Widget { TonightComplication(); DuskWidget() }
}

/// Complications and Smart Stack: tonight's score at the park the watch follows, the Moon, and the
/// next moment of the night. Built on the watch from the snapshot the watch app wrote.
struct TonightComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NyxTonight", provider: TonightComplicationProvider()) { entry in WatchComplicationView(entry: entry) }
            .configurationDisplayName("Tonight's sky")
            .description("The darkness score, the Moon and the next moment of the night.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}
struct TonightComplicationProvider: TimelineProvider {
    private var nightVision: Bool { WatchSky.nightVision(WatchSky.palette, context: WatchSky.readContext()) }
    func placeholder(in context: Context) -> WatchSkyEntry { WatchSkyEntry(date: .now, night: nil, next: nil, nightVision: true) }
    func getSnapshot(in context: Context, completion: @escaping (WatchSkyEntry) -> Void) {
        var snapshot = SharedSettings.read()
        // The face gallery shows a real sky (Joshua Tree tonight, moon and darkness only), not an empty state.
        if context.isPreview, snapshot?.parks.isEmpty ?? true, let sample = try? ParkData.load().first(where: { $0.id == "jotr" }) {
            snapshot = SavedSkySnapshot(parks: [sample], forecasts: [:])
        }
        var cache: [String: SkyConditions] = [:]
        completion(WatchTimeline.entry(at: .now, snapshot: snapshot, nightVision: nightVision, cache: &cache))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchSkyEntry>) -> Void) {
        let now = Date.now
        let entries = WatchTimeline.entries(from: now, snapshot: SharedSettings.read(), nightVision: nightVision)
        completion(Timeline(entries: entries, policy: .after(entries.last?.date ?? now.addingTimeInterval(3600))))
    }
}

/// A park and night worth stepping outside for. The watch's Smart Stack offers it from 45 minutes
/// before sunset until true darkness ends, on Good nights or better, and only then.
struct DuskNight: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Dark night"
    static let description = IntentDescription("A dark night at a park Nyx follows.")
    @Parameter(title: "Park") var park: String?
    @Parameter(title: "Evening") var evening: Date?
    init() {}
    init(park: String, evening: Date) { self.park = park; self.evening = evening }
}
struct DuskEntry: RelevanceEntry {
    let entry: WatchSkyEntry
}
struct DuskProvider: RelevanceEntriesProvider {
    func relevance() async -> WidgetRelevance<DuskNight> {
        guard let snapshot = SharedSettings.read() else { return WidgetRelevance([]) }
        let now = Date.now
        var attributes: [WidgetRelevanceAttribute<DuskNight>] = []
        for park in snapshot.parks {
            for offset in 0..<7 {
                let evening = park.date(park.currentNight(at: now), addingDays: offset)
                let night = WatchSky.night(park, evening: evening, forecast: snapshot.forecasts[park.id], now: now)
                guard night.score.value >= 60, let window = WatchTimeline.duskWindow(sky: night.sky), window.end > now else { continue }
                attributes.append(WidgetRelevanceAttribute(configuration: DuskNight(park: park.id, evening: evening), context: .date(interval: window, kind: .informational)))
            }
        }
        return WidgetRelevance(attributes)
    }
    func entry(configuration: DuskNight, context: Context) async throws -> DuskEntry {
        let now = Date.now
        let snapshot = SharedSettings.read()
        let parks = snapshot?.parks ?? []
        guard let id = configuration.park, let evening = configuration.evening, let park = parks.first(where: { $0.id == id }) ?? (try? ParkData.load())?.first(where: { $0.id == id }) else {
            return DuskEntry(entry: WatchSkyEntry(date: now, night: nil, next: nil, nightVision: nightVision))
        }
        let night = WatchSky.night(park, evening: evening, forecast: snapshot?.forecasts[park.id], now: now)
        return DuskEntry(entry: WatchSkyEntry(date: now, night: night, next: NightMilestone.next(after: now, in: night.sky), nightVision: nightVision))
    }
    func placeholder(context: Context) -> DuskEntry { DuskEntry(entry: WatchSkyEntry(date: .now, night: nil, next: nil, nightVision: true)) }
    private var nightVision: Bool { WatchSky.nightVision(WatchSky.palette, context: WatchSky.readContext()) }
}
struct DuskWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: "NyxDusk", provider: DuskProvider()) { entry in
            WatchComplicationView(previewFamily: .accessoryRectangular, entry: entry.entry)
        }
        .configurationDisplayName("Dark night ahead")
        .description("Appears in the Smart Stack at dusk on Good nights or better.")
    }
}
