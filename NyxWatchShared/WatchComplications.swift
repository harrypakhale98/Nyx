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
    /// The shown park's closure from the iPhone's last park update, worded as on the iPhone.
    var closure: String? = nil
    /// The shown park's clouds come from a forecast at least 36 hours old at this entry
    /// (`CloudSource.lifetime`): still scored, eased toward usual clouds, but worth refreshing.
    var cloudsOld = false
    /// The face is set to a saved spot or world place the iPhone no longer sends: it says so, rather
    /// than showing another place.
    var unsaved = false
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
/// luminance itself and stacked opacities turn to mud: everything is one ink, and only the score,
/// its gauge and a park's closure join the accent group. Increase Contrast lifts the quieter text
/// as the app's palette does (`NyxPalette.muted`): 0.9 instead of 0.72, and red at full strength.
/// The red itself is the app's (`NightLook`): the brighter one under Increase Contrast or when
/// chosen on iPhone (`WatchSky.brighterRed`), as on every other surface.
struct WristInk {
    let mode: WidgetRenderingMode
    let look: NightLook
    init(nightVision: Bool, mode: WidgetRenderingMode, contrast: ColorSchemeContrast = .standard, brighterRed: Bool = WatchSky.brighterRed) {
        self.mode = mode
        look = NightLook(nightVision: nightVision, brighterRed: brighterRed, highContrast: contrast == .increased)
    }
    var nightVision: Bool { look.nightVision }
    var highContrast: Bool { look.highContrast }
    var layered: Bool { mode == .fullColor }
    var ink: Color { look.ink }
    var accent: Color { nightVision || !layered ? ink : look.accent }
    var mutedOpacity: Double { nightVision ? (highContrast ? NightRed.levels[0] : NightRed.levels[1]) : (highContrast ? 0.9 : 0.72) }
    var muted: Color { layered ? ink.opacity(mutedOpacity) : ink }
}

/// Builds complication timelines on the watch from the snapshot the watch app wrote: the same
/// parks, forecasts and engine as Tonight, so the face and the app never disagree.
nonisolated enum WatchTimeline {
    /// Joshua Tree tonight, with its usual clouds: the gallery's sky and the redacted placeholder's shape.
    static var sample: SavedSkySnapshot? {
        (try? ParkData.load().first(where: { $0.id == Park.defaultID })).map { SavedSkySnapshot(parks: [$0], forecasts: [:]) }
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
        let climate = snapshot?.climate ?? .shared
        for park in snapshot?.parks ?? [] {
            let evening = park.currentNight(at: date)
            nights.append(WatchSky.night(park, evening: evening, forecast: snapshot?.forecasts[park.id], detail: snapshot?.details?[park.id], now: date,
                                         sky: sky(park, evening: evening, cache: &cache), climate: climate))
        }
        return NightPlanner.best(nights)
    }
    static func entry(at date: Date, snapshot: SavedSkySnapshot?, look: WristLook, cache: inout [String: SkyConditions]) -> WatchSkyEntry {
        let best = best(at: date, snapshot: snapshot, cache: &cache)
        let next = best.flatMap { NightMilestone.next(after: date, in: $0.sky) }
        return WatchSkyEntry(date: date, night: best, next: next, nightVision: look.nightVision(park: best?.park, at: date), rank: best.map { rank(for: $0, at: date) },
                             closure: best.flatMap { snapshot?.closures[$0.park.id] },
                             cloudsOld: isOld(best.flatMap { snapshot?.forecasts[$0.park.id]?.updated }, at: date))
    }
    /// A forecast fetched at `updated` is old at `date` once the watch app would say so ("No recent forecast").
    static func isOld(_ updated: Date?, at date: Date) -> Bool { updated.map { date.timeIntervalSince($0) >= CloudSource.lifetime } ?? false }
    /// When each snapshot forecast turns old within the next day, so the face says so on time.
    static func ageMoments(from now: Date, snapshot: SavedSkySnapshot?) -> [Date] {
        (snapshot?.forecasts.values.map { $0.updated.addingTimeInterval(CloudSource.lifetime) } ?? []).filter { $0 > now && $0 < now.addingTimeInterval(86400) }
    }
    /// Moments a complication must redraw at besides the hour: Automatic changing colour at the
    /// snapshot's parks over the next day.
    static func paletteMoments(from now: Date, snapshot: SavedSkySnapshot?, look: WristLook) -> [Date] {
        guard look.choice == .automatic else { return [] }
        return (snapshot?.parks ?? []).flatMap { WristSky.paletteChanges(at: $0, from: now, to: now.addingTimeInterval(86400)) }
    }
    /// Entries now, at every milestone of the next day (so "next" turns over on time), a second
    /// past each park's sunrise (so tonight turns over then, `Park.nightTurnovers`), and hourly.
    /// Countdown text updates itself in between.
    static func entries(from now: Date, snapshot: SavedSkySnapshot?, look: WristLook) -> [WatchSkyEntry] {
        var cache: [String: SkyConditions] = [:]
        let first = entry(at: now, snapshot: snapshot, look: look, cache: &cache)
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
        var moments = Set((0..<24).map { hour.addingTimeInterval(Double($0)*3600) })
        moments.formUnion(paletteMoments(from: now, snapshot: snapshot, look: look))
        moments.formUnion(ageMoments(from: now, snapshot: snapshot))
        for park in snapshot?.parks ?? [] {
            moments.formUnion(park.nightTurnovers(from: now, to: now.addingTimeInterval(86400)))
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
    /// Deliberately not `NightPlanner.duskWindow` (the iPhone's: 90 minutes before sunset to an hour
    /// into true darkness). Both share `NightPlanner.worthSurfacing`, so they agree on which nights;
    /// only the hours differ, because the iPhone is for setting out and the wrist stays useful at the
    /// park all night (DECISIONS.md, team review 2026-10-08, score consistency).
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

/// A park's closure on the wrist, in the iPhone's words: the line every surface must show beside
/// the score. Pure, so it can move wherever a test target can reach it.
nonisolated enum WristClosure {
    static let symbol = "exclamationmark.triangle.fill"
    /// Spoken after the score, as on the iPhone and the watch's Tonight: "Closure alert: …".
    static func spoken(_ closure: String) -> String { String(localized: "Closure alert: \(closure)") }
    /// The inline complication's line, "94 · Closure alert": one short line has no room for the
    /// closure's own words, which the rectangular complication, the spoken label and a tap give.
    static func inline(score: Int) -> String { String(localized: "\(score) · \(String(localized: "Closure alert"))") }
}

/// "True darkness in 1 hr, 10 min". In a complication (`now` nil) the time updates itself; in the
/// app it is written for `now` and refreshed by the screen's minute timeline, which keeps
/// self-updating time text out of the app's paged views (it looped layout there on watchOS 27).
/// A complication's line has room for about twenty characters once the duration is on it, so
/// there the two long names give way to the short ones the inline complication already uses
/// ("Dark in 1 hr, 10 min", "Dawn in 5 min"); the app keeps the full words.
func countdownText(_ milestone: NightMilestone, now: Date? = nil) -> Text {
    let reference = now.map { Text(verbatim: inDuration(until: milestone.date, from: $0)) }
        ?? Text(.currentDate, format: .reference(to: milestone.date, allowedFields: [.hour, .minute]))
    let compact = now == nil
    return switch milestone.kind {
    case .sunset: Text("Sunset \(reference)")
    case .darkStart: compact ? Text("Dark \(reference)") : Text("True darkness \(reference)")
    case .moonrise: Text("Moon rises \(reference)")
    case .moonset: Text("Moon sets \(reference)")
    case .darkEnd: compact ? Text("Dawn \(reference)") : Text("Dawn twilight \(reference)")
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
    @Environment(\.colorSchemeContrast) private var contrast
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    private var colors: WristInk { WristInk(nightVision: entry.nightVision, mode: renderingMode, contrast: contrast) }
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
            } else if entry.unsaved { unsaved } else { empty }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.night.map(summary) ?? (entry.unsaved ? String(localized: "This place is no longer saved in Nyx.")+" "+String(localized: "Edit the complication to choose another place.")
                                                          : String(localized: "Nyx. Choose a place in Nyx on Apple Watch.")))
        .containerBackground(for: .widget) { Color.black }
        // A tap opens this park on this night, not whatever Tonight would show.
        .widgetURL(entry.night.flatMap { WatchLink(park: $0.park, evening: $0.sky.evening).url })
    }
    private func circular(_ night: Night) -> some View {
        // The system's open ring echoes the app's celestial gauge; the Moon sits in its opening.
        Gauge(value: Double(night.score.value), in: 0...100) {
            // Coloured explicitly: the label otherwise renders white, the one bright thing on a red face.
            // A closure takes the Moon's place, in the accent: it stands beside the score on every surface.
            if entry.closure != nil { Image(systemName: WristClosure.symbol).foregroundStyle(accent) } else { MoonSymbol(night: night).foregroundStyle(muted) }
        } currentValueLabel: {
            Text(night.score.value, format: .number).font(.system(.title3, design: .serif)).widgetAccentable()
        }
        .gaugeStyle(.accessoryCircular).tint(accent).foregroundStyle(ink).widgetAccentable()
    }
    private func corner(_ night: Night) -> some View {
        // The numeral once, in the corner; the curved gauge alone carries the fill, without end labels.
        Text(night.score.value, format: .number).font(.system(.title2, design: .serif)).foregroundStyle(accent).widgetAccentable()
            .widgetLabel {
                // A closure takes the curved label from the gauge: the numeral stays, the warning is read first.
                if entry.closure != nil {
                    Text("\(Image(systemName: WristClosure.symbol)) \(Text("Closure alert"))").foregroundStyle(accent).widgetAccentable()
                } else {
                    Gauge(value: Double(night.score.value), in: 0...100) { Text(night.score.band.label) }.tint(accent).widgetAccentable()
                }
            }
    }
    private func inline(_ night: Night) -> some View {
        // Inline is one short line: the next moment's clock time reads at a glance and never goes stale.
        // A closure outranks it.
        Group {
            if entry.closure != nil { Text("\(Image(systemName: WristClosure.symbol)) \(WristClosure.inline(score: night.score.value))") }
            else if let next = entry.next { Text("\(night.score.value) · \(next.shortTitle) at \(night.park.time(next.date))") }
            else { Text("\(night.score.value) \(night.score.band.label) · \(night.park.wristName)") }
        }.foregroundStyle(ink)
    }
    /// How much of a closure the rectangular complication has room for.
    private enum ClosureFit { case whole(String), alert, mark }
    /// Park, score and band, then the next moment; at large text sizes the moment line drops first.
    /// A closure comes before the moment and is never cut: its own words wrapped whole, else
    /// "Closure alert", else the warning mark beside the numeral (the spoken label always has it all).
    /// An old forecast says so in a line of its own ("No recent forecast"), which gives way after
    /// the next moment and before the closure is shortened.
    private func rectangular(_ night: Night) -> some View {
        let old = entry.cloudsOld
        return Group {
            if let closure = entry.closure {
                ViewThatFits(in: .vertical) {
                    rectangular(night, closure: .whole(closure), old: old, showsNext: true)
                    rectangular(night, closure: .whole(closure), old: old, showsNext: false)
                    rectangular(night, closure: .whole(closure), old: false, showsNext: false)
                    rectangular(night, closure: .alert, old: old, showsNext: false)
                    rectangular(night, closure: .alert, old: false, showsNext: false)
                    rectangular(night, closure: .mark, old: false, showsNext: false)
                }
            } else {
                ViewThatFits(in: .vertical) {
                    rectangular(night, closure: nil, old: old, showsNext: true)
                    rectangular(night, closure: nil, old: old, showsNext: false)
                    rectangular(night, closure: nil, old: false, showsNext: false)
                }
            }
        }
        .foregroundStyle(ink).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func rectangular(_ night: Night, closure: ClosureFit?, old: Bool, showsNext: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                MoonSymbol(night: night).font(.caption2).foregroundStyle(muted)
                Text(night.park.wristName).font(.system(.headline, design: .serif)).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(night.score.value, format: .number).font(.system(.title2, design: .serif).weight(.light)).foregroundStyle(accent).widgetAccentable()
                if case .mark = closure { Image(systemName: WristClosure.symbol).font(.caption2).foregroundStyle(accent).widgetAccentable() }
                Text(night.bandWithBasis)
                    .font(.caption2).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            // Measured at full height, so a closure that would need cutting gives way to a shorter form instead.
            switch closure {
            case .whole(let text): closureLine(Text(text))
            case .alert: closureLine(Text("Closure alert"))
            case .mark, nil: EmptyView()
            }
            if old {
                Label { Text("No recent forecast") } icon: { Image(systemName: "clock.arrow.circlepath") }
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
    private func closureLine(_ text: Text) -> some View {
        Label { text } icon: { Image(systemName: WristClosure.symbol) }
            .font(.caption2.weight(.medium)).foregroundStyle(accent).widgetAccentable()
            .fixedSize(horizontal: false, vertical: true)
    }
    private var empty: some View {
        Group {
            switch family {
            case .accessoryCircular: ZStack { AccessoryWidgetBackground(); Image(systemName: "moon.stars") }
            case .accessoryCorner: Image(systemName: "moon.stars").widgetLabel("Nyx")
            case .accessoryInline: Text("Nyx · choose a place")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Nyx", systemImage: "moon.stars").font(.headline)
                    Text("Open Nyx to choose a place.").font(.caption2).foregroundStyle(muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.foregroundStyle(ink)
    }
    /// Set to a place no longer saved: the mark of a place taken off the map, and the two words that say why.
    private var unsaved: some View {
        Group {
            switch family {
            case .accessoryCircular: ZStack { AccessoryWidgetBackground(); Image(systemName: "mappin.slash") }
            case .accessoryCorner: Image(systemName: "mappin.slash").widgetLabel("No longer saved")
            case .accessoryInline: Text("\(Image(systemName: "mappin.slash")) \(Text("No longer saved"))")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("No longer saved", systemImage: "mappin.slash").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    Text("Edit the complication to choose another place.").font(.caption2).foregroundStyle(muted).lineLimit(2).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.foregroundStyle(ink)
    }
    private func summary(_ night: Night) -> String {
        var text = String(localized: "\(night.park.wristName), \(night.score.value) out of 100, \(night.score.band.label).")
        // The closure is spoken in every family, right after the score it stands beside.
        if let closure = entry.closure { text += " " + WristClosure.spoken(closure) }
        if let caption = night.basisCaption() { text += " " + caption }
        // In every family, though only the rectangular one has room to show it.
        if entry.cloudsOld { text += " " + String(localized: "No recent forecast. Open Nyx on iPhone to refresh.") }
        if let next = entry.next { text += " " + String(localized: "\(next.title) at \(night.park.time(next.date)).") }
        return text
    }
}

#Preview("Tonight • old forecast, rectangular") { OldForecastPreview() }
#Preview("Tonight • old forecast and closure") { OldForecastPreview(closure: "Keys View Road and the Geology Tour Road closed for repairs through November") }
#Preview("Tonight • old forecast • xxxLarge") { OldForecastPreview(closure: "Keys View Road closed at night").dynamicTypeSize(.xxxLarge) }
/// The rectangular face with a forecast 36 hours old, in full colour and tinted, from the real engine.
private struct OldForecastPreview: View {
    var closure: String? = nil
    private var entry: WatchSkyEntry {
        var cache: [String: SkyConditions] = [:]
        let entry = WatchTimeline.entry(at: .now, snapshot: WatchTimeline.sample, look: .red, cache: &cache)
        return WatchSkyEntry(date: entry.date, night: entry.night, next: entry.next, nightVision: false, closure: closure, cloudsOld: true)
    }
    var body: some View {
        VStack(spacing: 8) {
            WatchComplicationView(previewFamily: .accessoryRectangular, entry: entry).frame(height: 60)
            WatchComplicationView(previewFamily: .accessoryRectangular, entry: entry).frame(height: 60).environment(\.widgetRenderingMode, .accented)
        }
        .padding(.horizontal, 6)
    }
}
