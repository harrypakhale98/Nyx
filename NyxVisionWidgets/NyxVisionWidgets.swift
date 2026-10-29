import SwiftUI
import WidgetKit

/// Nyx's visionOS widget: tonight's Moon, pinned to a wall (recessed, like a window into the
/// night) or set on a surface (elevated), on glass. The large face adds the next seven nights'
/// Moons. Self-contained: it reads no saved parks and makes no requests.
@main struct NyxVisionWidgets: WidgetBundle {
    var body: some Widget { MoonWidget() }
}

struct MoonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "moon", provider: MoonProvider()) { entry in MoonWidgetView(entry: entry) }
            .configurationDisplayName(Text("Tonight's Moon"))
            .description(Text("The Moon's phase and the next new moon, when the darkest nights begin."))
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .supportedMountingStyles([.elevated, .recessed])
            .widgetTexture(.glass)
    }
}

struct MoonEntry: TimelineEntry {
    let date: Date
    let facts: MoonFacts
}

/// One entry every three hours for a day, so "next new moon" moves on soon after one passes; the
/// Moon is the one at each entry's moment, as on the iPhone and the watch (`MoonFacts`).
struct MoonProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoonEntry { MoonEntry(date: .now, facts: MoonFacts(at: .now)) }
    func getSnapshot(in context: Context, completion: @escaping (MoonEntry) -> Void) {
        completion(MoonEntry(date: .now, facts: MoonFacts(at: .now)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MoonEntry>) -> Void) {
        let now = Date.now
        // Every three hours, plus the next 6 AM, where the large face's week moves on a night (`MoonWeek`).
        let calendar = Calendar.current
        let sixAM = calendar.nextDate(after: now, matching: DateComponents(hour: 6, minute: 0), matchingPolicy: .nextTime)
        let dates = ((0..<8).map { now.addingTimeInterval(Double($0)*3*3600) } + [sixAM].compactMap { $0 }).sorted()
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

#Preview("Large", as: .systemLarge) {
    MoonWidget()
} timeline: {
    MoonEntry(date: .now, facts: MoonFacts(at: .now))
    MoonEntry(date: .now.addingTimeInterval(10*86400), facts: MoonFacts(at: .now.addingTimeInterval(10*86400)))
}
