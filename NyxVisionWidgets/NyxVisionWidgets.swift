import SwiftUI
import WidgetKit

/// Nyx's visionOS widget: tonight's Moon, pinned to a wall (recessed, like a window into the
/// night) or set on a surface (elevated), on glass. Self-contained: it reads no saved parks and
/// makes no requests.
@main struct NyxVisionWidgets: WidgetBundle {
    var body: some Widget { MoonWidget() }
}

struct MoonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "moon", provider: MoonProvider()) { entry in MoonWidgetView(entry: entry) }
            .configurationDisplayName(Text("Tonight's Moon"))
            .description(Text("The Moon's phase and the next new moon, when the darkest nights begin."))
            .supportedFamilies([.systemSmall, .systemMedium])
            .supportedMountingStyles([.elevated, .recessed])
            .widgetTexture(.glass)
    }
}

struct MoonEntry: TimelineEntry {
    let date: Date
    let facts: MoonFacts
}

/// One entry every three hours for a day: the lit fraction changes by about a percent in that time.
struct MoonProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoonEntry { MoonEntry(date: .now, facts: MoonFacts(at: .now)) }
    func getSnapshot(in context: Context, completion: @escaping (MoonEntry) -> Void) {
        completion(MoonEntry(date: .now, facts: MoonFacts(at: .now)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MoonEntry>) -> Void) {
        let now = Date.now
        let dates = (0..<8).map { now.addingTimeInterval(Double($0)*3*3600) }
        completion(Timeline(entries: dates.map { MoonEntry(date: $0, facts: MoonFacts(at: $0)) }, policy: .after(now.addingTimeInterval(24*3600))))
    }
}

struct MoonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.levelOfDetail) private var levelOfDetail
    let entry: MoonEntry
    var body: some View {
        MoonWidgetFace(facts: entry.facts, family: family, simplified: levelOfDetail == .simplified)
            .containerBackground(for: .widget) { MoonWidgetFace.background }
    }
}

#Preview("Small", as: .systemSmall) {
    MoonWidget()
} timeline: {
    MoonEntry(date: .now, facts: MoonFacts(at: .now))
    MoonEntry(date: .now.addingTimeInterval(7*86400), facts: MoonFacts(at: .now.addingTimeInterval(7*86400)))
}

#Preview("Medium", as: .systemMedium) {
    MoonWidget()
} timeline: {
    MoonEntry(date: .now, facts: MoonFacts(at: .now))
}
