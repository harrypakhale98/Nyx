import SwiftUI
import WidgetKit

@main
struct NyxWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TonightWidget()
    }
}

/// Placeholder widget. The real "Tonight's sky" widget is built in Phase 6a.
struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TonightWidget", provider: TonightProvider()) { _ in
            Text("Nyx")
                .font(.system(.title, design: .serif))
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Tonight's sky")
        .description("The darkest sky among your saved parks tonight.")
        .supportedFamilies([.systemSmall])
    }
}

struct TonightEntry: TimelineEntry {
    let date: Date
}

struct TonightProvider: TimelineProvider {
    func placeholder(in context: Context) -> TonightEntry { TonightEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (TonightEntry) -> Void) {
        completion(TonightEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TonightEntry>) -> Void) {
        completion(Timeline(entries: [TonightEntry(date: .now)], policy: .never))
    }
}
