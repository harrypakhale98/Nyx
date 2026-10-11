import AppIntents
import SwiftUI
import WidgetKit

/// Control Center (and the Action button): start dark adaptation without finding the eye button.
/// Opens Nyx straight onto the red clock; a clock already running is shown, not restarted.
struct AdaptationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AdaptationRequest.controlKind) {
            ControlWidgetButton(action: StartAdaptationIntent()) { Label("Dark adaptation", systemImage: "eye") }
        }
        .displayName("Start dark adaptation")
        .description("Opens Nyx in red and starts a 30-minute dark-adaptation clock.")
    }
}

/// The dark-adaptation clock on the face: the ring the app draws, filling over 30 minutes, with the
/// time counting up on its own between entries. Red while the clock runs, whatever the face wears:
/// it is there for eyes that are adapting. Idle, it follows the wearer's colours like every Nyx
/// complication. A tap opens Nyx.
struct AdaptationComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AdaptationRequest.complicationKind, provider: AdaptationProvider()) { entry in AdaptationComplicationView(entry: entry) }
            .configurationDisplayName("Dark adaptation")
            .description("The 30-minute dark-adaptation clock, in red while it runs.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

/// The clock at one moment: running from `start`, or not running.
nonisolated struct AdaptationEntry: TimelineEntry, Sendable {
    let date: Date
    /// When the running clock started; nil when none is running.
    let start: Date?
    let nightVision: Bool
    var clock: AdaptationClock? { start.map(AdaptationClock.init(start:)) }
    var adapted: Bool { clock?.isAdapted(at: date) ?? false }
    /// The 30 minutes the ring and the counting time run across.
    var interval: ClosedRange<Date>? { start.map { $0...$0.addingTimeInterval(Double(AdaptationClock.minutes*60)) } }
}

nonisolated enum AdaptationTimeline {
    /// Running: now and every whole minute to 30 (so the spoken minutes stay true; the ring and the
    /// time move on their own), then idle when the clock is forgotten. Idle: now and wherever
    /// Automatic changes colour at the followed park over the next day.
    static func entries(from now: Date, start: Date?, look: WristLook, park: Park?) -> [AdaptationEntry] {
        func idle(_ date: Date) -> AdaptationEntry { AdaptationEntry(date: date, start: nil, nightVision: look.nightVision(park: park, at: date)) }
        guard let clock = AdaptationRequest.running(at: now, start: start) else {
            let changes = look.choice == .automatic ? park.map { WristSky.paletteChanges(at: $0, from: now, to: now.addingTimeInterval(86400)) } ?? [] : []
            return ([now] + changes).map(idle)
        }
        let minutes = (1...AdaptationClock.minutes).map { clock.start.addingTimeInterval(Double($0*60)) }.filter { $0 > now }
        return ([now] + minutes).map { AdaptationEntry(date: $0, start: clock.start, nightVision: true) }
            + [idle(clock.start.addingTimeInterval(AdaptationClock.forgetAfter))]
    }
}

struct AdaptationProvider: TimelineProvider {
    /// The gallery and the redacted placeholder: a clock 12 minutes in, red, as at a dark site.
    func placeholder(in context: Context) -> AdaptationEntry {
        AdaptationEntry(date: .now, start: .now.addingTimeInterval(-12*60), nightVision: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (AdaptationEntry) -> Void) {
        if context.isPreview, AdaptationRequest.running(at: .now) == nil { completion(placeholder(in: context)); return }
        completion(Self.entries(from: .now).first ?? placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AdaptationEntry>) -> Void) {
        let now = Date.now
        let entries = Self.entries(from: now)
        // The app and the intent reload this whenever the clock starts or stops.
        completion(Timeline(entries: entries, policy: .after(max(entries.last?.date ?? now, now.addingTimeInterval(3600)))))
    }
    static func entries(from now: Date) -> [AdaptationEntry] {
        var cache: [String: SkyConditions] = [:]
        let park = WristTimeline.park(at: now, snapshot: SharedSettings.read(), cache: &cache)
        return AdaptationTimeline.entries(from: now, start: WatchSky.adaptationStart, look: .current, park: park)
    }
}

struct AdaptationComplicationView: View {
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    var previewFamily: WidgetFamily?
    let entry: AdaptationEntry
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    private var colors: WristInk { WristInk(nightVision: entry.nightVision, mode: renderingMode) }
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            default: rectangular
            }
        }
        .foregroundStyle(colors.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dark adaptation")
        .accessibilityValue(spokenValue)
        .containerBackground(for: .widget) { Color.black }
    }
    /// The app's ring in miniature: "30 minutes" before it starts, the time while it runs, "30 adapted" after.
    private var circular: some View {
        ZStack {
            if let interval = entry.interval, !entry.adapted {
                ProgressView(timerInterval: interval, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular).tint(colors.accent).widgetAccentable()
                Text(timerInterval: interval, countsDown: false, showsHours: false)
                    .font(.system(.footnote, design: .serif).weight(.medium)).monospacedDigit()
                    .multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 7)
            } else {
                ProgressView(value: entry.adapted ? 1 : 0).progressViewStyle(.circular).tint(colors.accent).widgetAccentable()
                VStack(spacing: -1) {
                    Text(AdaptationClock.minutes, format: .number).font(.system(.body, design: .serif).weight(.medium)).monospacedDigit()
                        .foregroundStyle(entry.adapted ? colors.accent : colors.ink)
                    Group { if entry.adapted { Text("adapted") } else { Text("minutes") } }
                        .font(.system(.caption2, design: .serif)).foregroundStyle(colors.muted).lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 7)
            }
        }
    }
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: entry.start == nil ? "eye" : "eye.fill").font(.caption2).foregroundStyle(colors.muted)
                Text("Dark adaptation").font(.system(.headline, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
            }
            if let interval = entry.interval, !entry.adapted {
                Text("\(Text(timerInterval: interval, countsDown: false, showsHours: false)) of 30 min")
                    .font(.system(.body, design: .serif)).monospacedDigit().foregroundStyle(colors.accent).widgetAccentable().lineLimit(1)
                ProgressView(timerInterval: interval, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear).tint(colors.accent).widgetAccentable()
            } else if let start = entry.start {
                Text("Adapted").font(.system(.body, design: .serif)).foregroundStyle(colors.accent).widgetAccentable().lineLimit(1)
                Text("Started at \(start.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(colors.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Text("Not started").font(.system(.body, design: .serif)).foregroundStyle(colors.muted).lineLimit(1)
                Text("Eyes adapt in about 30 minutes.").font(.caption2).foregroundStyle(colors.muted).lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    /// The same words as the app's ring for VoiceOver, true to the minute (an entry every minute).
    private var spokenValue: String {
        guard let clock = entry.clock else { return String(localized: "Not started") }
        if entry.adapted { return String(localized: "Adapted, 30 minutes") }
        return String(localized: "\(clock.elapsedMinutes(at: entry.date)) of about 30 minutes")
    }
}

#Preview("Adaptation • circular", as: .accessoryCircular) { AdaptationComplication() } timeline: {
    AdaptationEntry(date: .now, start: nil, nightVision: false)
    AdaptationEntry(date: .now, start: nil, nightVision: true)
    AdaptationEntry(date: .now, start: .now.addingTimeInterval(-12*60), nightVision: true)
    AdaptationEntry(date: .now, start: .now.addingTimeInterval(-40*60), nightVision: true)
}
#Preview("Adaptation • rectangular", as: .accessoryRectangular) { AdaptationComplication() } timeline: {
    AdaptationEntry(date: .now, start: nil, nightVision: false)
    AdaptationEntry(date: .now, start: nil, nightVision: true)
    AdaptationEntry(date: .now, start: .now.addingTimeInterval(-12*60), nightVision: true)
    AdaptationEntry(date: .now, start: .now.addingTimeInterval(-40*60), nightVision: true)
}
