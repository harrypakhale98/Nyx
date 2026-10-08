import SwiftUI
import WidgetKit

/// One moment on the wrist: the night Tonight would show, and what happens next.
nonisolated struct WatchSkyEntry: TimelineEntry, Sendable {
    let date: Date
    let night: Night?
    let next: NightMilestone?
    let nightVision: Bool
    /// Smart Stack ranking, kept as plain values so the entry stays Sendable.
    var rank: (score: Float, duration: TimeInterval)?
    var relevance: TimelineEntryRelevance? { rank.map { TimelineEntryRelevance(score: $0.score, duration: $0.duration) } }
}

/// The wearer's colour choice as the complications read it: Automatic is decided per entry, by
/// the Sun at that entry's park and moment, so a face turns red at civil dusk.
nonisolated struct WristLook: Sendable {
    let choice: PaletteChoice
    let phone: Bool?
    static var current: WristLook { WristLook(choice: WatchSky.palette, phone: WatchSky.readContext()?.nightVision) }
    /// Placeholders and the face gallery: red, as at a dark site.
    static let red = WristLook(choice: .red, phone: nil)
    func nightVision(park: Park?, at date: Date) -> Bool { choice.nightVision(phone: phone, park: park, at: date) }
}

/// Colours every Nyx complication shares. In full colour they follow the palette; in the tinted
/// (accented) and vibrant face modes there are no opacity levels, because the system maps
/// luminance itself and stacked opacities turn to mud: everything is one ink, and only the score
/// and its gauge join the accent group.
struct WristInk {
    let nightVision: Bool
    let mode: WidgetRenderingMode
    var layered: Bool { mode == .fullColor }
    var ink: Color { nightVision ? Color(red: NightRed.red, green: NightRed.green, blue: NightRed.blue) : Color(red: 0.961, green: 0.945, blue: 0.902) }
    var accent: Color { nightVision || !layered ? ink : Color(red: 1, green: 0.706, blue: 0.329) }
    var muted: Color { layered ? ink.opacity(nightVision ? NightRed.levels[1] : 0.72) : ink }
}

/// Builds complication timelines on the watch from the snapshot the watch app wrote: the same
/// parks, forecasts and engine as Tonight, so the face and the app never disagree.
nonisolated enum WatchTimeline {
    /// Joshua Tree tonight, with its usual clouds: the gallery's sky and the redacted placeholder's shape.
    static var sample: SavedSkySnapshot? {
        (try? ParkData.load().first(where: { $0.id == "jotr" })).map { SavedSkySnapshot(parks: [$0], forecasts: [:]) }
    }
    static func sky(_ park: Park, evening: Date, cache: inout [String: SkyConditions]) -> SkyConditions {
        let key = "\(park.id)-\(Int(evening.timeIntervalSince1970))"
        let sky = cache[key] ?? AstronomyEngine().conditions(for: park, on: evening)
        cache[key] = sky
        return sky
    }
    /// The park Tonight would show at `date`: the darkest of the snapshot's parks, ties broken as
    /// on the iPhone (`NightPlanner.best`).
    static func best(at date: Date, snapshot: SavedSkySnapshot?, cache: inout [String: SkyConditions]) -> Night? {
        var nights: [Night] = []
        for park in snapshot?.parks ?? [] {
            let evening = park.currentNight(at: date)
            nights.append(WatchSky.night(park, evening: evening, forecast: snapshot?.forecasts[park.id], detail: snapshot?.details?[park.id], now: date,
                                         sky: sky(park, evening: evening, cache: &cache)))
        }
        return NightPlanner.best(nights)
    }
    static func entry(at date: Date, snapshot: SavedSkySnapshot?, look: WristLook, cache: inout [String: SkyConditions]) -> WatchSkyEntry {
        let best = best(at: date, snapshot: snapshot, cache: &cache)
        let next = best.flatMap { NightMilestone.next(after: date, in: $0.sky) }
        return WatchSkyEntry(date: date, night: best, next: next, nightVision: look.nightVision(park: best?.park, at: date), rank: best.map { rank(for: $0, at: date) })
    }
    /// Moments a complication must redraw at besides the hour: Automatic changing colour at the
    /// snapshot's parks over the next day.
    static func paletteMoments(from now: Date, snapshot: SavedSkySnapshot?, look: WristLook) -> [Date] {
        guard look.choice == .automatic else { return [] }
        return (snapshot?.parks ?? []).flatMap { WristSky.paletteChanges(at: $0, from: now, to: now.addingTimeInterval(86400)) }
    }
    /// Entries now, at every milestone of the next day (so "next" turns over on time), and hourly
    /// (so tonight turns over at the park's sunrise). Countdown text updates itself in between.
    static func entries(from now: Date, snapshot: SavedSkySnapshot?, look: WristLook) -> [WatchSkyEntry] {
        var cache: [String: SkyConditions] = [:]
        let first = entry(at: now, snapshot: snapshot, look: look, cache: &cache)
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
        var moments = Set((0..<24).map { hour.addingTimeInterval(Double($0)*3600) })
        moments.formUnion(paletteMoments(from: now, snapshot: snapshot, look: look))
        for park in snapshot?.parks ?? [] {
            for offset in 0..<2 {
                let evening = park.date(park.currentNight(at: now), addingDays: offset)
                let key = "\(park.id)-\(Int(evening.timeIntervalSince1970))"
                let sky = cache[key] ?? AstronomyEngine().conditions(for: park, on: evening)
                cache[key] = sky
                for milestone in NightMilestone.list(for: sky) where milestone.date > now && milestone.date < now.addingTimeInterval(86400) {
                    moments.insert(milestone.date)
                }
                if let start = duskWindow(sky: sky)?.start, start > now, start < now.addingTimeInterval(86400) { moments.insert(start) }
            }
        }
        return [first] + moments.sorted().map { entry(at: $0, snapshot: snapshot, look: look, cache: &cache) }
    }
    /// From 45 minutes before sunset to the end of true darkness: when a stargazer wants Nyx on the wrist.
    static func duskWindow(sky: SkyConditions) -> DateInterval? {
        guard let begin = sky.sunset ?? sky.darkStart else { return nil }
        let start = begin.addingTimeInterval(-45*60)
        let end = sky.darkEnd ?? sky.sunrise ?? begin.addingTimeInterval(3*3600)
        return end > start ? DateInterval(start: start, end: end) : nil
    }
    /// Smart Stack ranking: relevant around dusk on a night the iPhone would surface too
    /// (`NightPlanner.worthSurfacing`: Good with a forecast, Excellent without), more so the darker the night.
    static func rank(for night: Night, at date: Date) -> (score: Float, duration: TimeInterval) {
        guard NightPlanner.worthSurfacing(night), let window = duskWindow(sky: night.sky), window.contains(date) else { return (0, 0) }
        return (Float(night.score.value)/100, window.end.timeIntervalSince(date))
    }
}

/// "True darkness in 1 hr, 10 min". In a complication (`now` nil) the time updates itself; in the
/// app it is written for `now` and refreshed by the screen's minute timeline, which keeps
/// self-updating time text out of the app's paged views (it looped layout there on watchOS 27).
func countdownText(_ milestone: NightMilestone, now: Date? = nil) -> Text {
    let reference = now.map { Text(verbatim: inDuration(until: milestone.date, from: $0)) }
        ?? Text(.currentDate, format: .reference(to: milestone.date, allowedFields: [.hour, .minute]))
    return switch milestone.kind {
    case .sunset: Text("Sunset \(reference)")
    case .darkStart: Text("True darkness \(reference)")
    case .moonrise: Text("Moon rises \(reference)")
    case .moonset: Text("Moon sets \(reference)")
    case .darkEnd: Text("Dawn twilight \(reference)")
    case .sunrise: Text("Sunrise \(reference)")
    }
}

/// "in 42 min", rounded up to the minute so it never reads "in 0 min" before the moment.
func inDuration(until date: Date, from now: Date) -> String {
    let minutes = max(1, Int((date.timeIntervalSince(now)/60).rounded(.up)))
    let span = Duration.seconds(minutes*60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    return String(localized: "in \(span)")
}

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) private var systemFamily
    var previewFamily: WidgetFamily?
    let entry: WatchSkyEntry
    /// Next moment as a clock time instead of a self-updating countdown, for cards built once.
    var clockTimes = false
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    private var colors: WristInk { WristInk(nightVision: entry.nightVision, mode: renderingMode) }
    private var ink: Color { colors.ink }
    private var accent: Color { colors.accent }
    private var muted: Color { colors.muted }
    var body: some View {
        Group {
            if let night = entry.night {
                switch family {
                case .accessoryCircular: circular(night)
                case .accessoryCorner: corner(night)
                case .accessoryInline: inline(night)
                default: rectangular(night)
                }
            } else { empty }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.night.map(summary) ?? String(localized: "Nyx. Choose a park in Nyx on Apple Watch."))
        .containerBackground(for: .widget) { Color.black }
        // A tap opens this park on this night, not whatever Tonight would show.
        .widgetURL(entry.night.flatMap { WatchLink(park: $0.park, evening: $0.sky.evening).url })
    }
    private func circular(_ night: Night) -> some View {
        // The system's open ring echoes the app's celestial gauge; the Moon sits in its opening.
        Gauge(value: Double(night.score.value), in: 0...100) {
            // Coloured explicitly: the label otherwise renders white, the one bright thing on a red face.
            MoonSymbol(night: night).foregroundStyle(muted)
        } currentValueLabel: {
            Text(night.score.value, format: .number).font(.system(.title3, design: .serif)).widgetAccentable()
        }
        .gaugeStyle(.accessoryCircular).tint(accent).foregroundStyle(ink).widgetAccentable()
    }
    private func corner(_ night: Night) -> some View {
        // The numeral once, in the corner; the curved gauge alone carries the fill, without end labels.
        Text(night.score.value, format: .number).font(.system(.title2, design: .serif)).foregroundStyle(accent).widgetAccentable()
            .widgetLabel {
                Gauge(value: Double(night.score.value), in: 0...100) { Text(night.score.band.label) }.tint(accent).widgetAccentable()
            }
    }
    private func inline(_ night: Night) -> some View {
        // Inline is one short line: the next moment's clock time reads at a glance and never goes stale.
        Group {
            if let next = entry.next { Text("\(night.score.value) · \(next.shortTitle) at \(night.park.time(next.date))") }
            else { Text("\(night.score.value) \(night.score.band.label) · \(night.park.wristName)") }
        }.foregroundStyle(ink)
    }
    /// Park, score and band, then the next moment; at large text sizes the moment line drops first.
    private func rectangular(_ night: Night) -> some View {
        ViewThatFits(in: .vertical) {
            rectangular(night, showsNext: true)
            rectangular(night, showsNext: false)
        }
        .foregroundStyle(ink).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func rectangular(_ night: Night, showsNext: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                MoonSymbol(night: night).font(.caption2).foregroundStyle(muted)
                Text(night.park.wristName).font(.system(.headline, design: .serif)).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(night.score.value, format: .number).font(.system(.title2, design: .serif).weight(.light)).foregroundStyle(accent).widgetAccentable()
                Text(night.bandWithBasis)
                    .font(.caption2).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            if showsNext, let next = entry.next {
                Group {
                    if clockTimes { Text("\(next.title) at \(night.park.time(next.date))") } else { countdownText(next) }
                }.font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var empty: some View {
        Group {
            switch family {
            case .accessoryCircular: ZStack { AccessoryWidgetBackground(); Image(systemName: "moon.stars") }
            case .accessoryCorner: Image(systemName: "moon.stars").widgetLabel("Nyx")
            case .accessoryInline: Text("Nyx · choose a park")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Nyx", systemImage: "moon.stars").font(.headline)
                    Text("Open Nyx to choose a park.").font(.caption2).foregroundStyle(muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.foregroundStyle(ink)
    }
    private func summary(_ night: Night) -> String {
        var text = String(localized: "\(night.park.wristName), \(night.score.value) out of 100, \(night.score.band.label).")
        if let caption = night.basisCaption() { text += " " + caption }
        if let next = entry.next { text += " " + String(localized: "\(next.title) at \(night.park.time(next.date)).") }
        return text
    }
}
