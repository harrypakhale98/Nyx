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
    /// (`CloudSource.lifetime`): still scored (eased toward usual clouds, or as it stands where the
    /// place has none), but worth refreshing.
    var cloudsOld = false
    /// The face is set to a saved spot or world place the iPhone no longer sends: it says so, rather
    /// than showing another place.
    var unsaved = false
    /// The iPhone runs a Nyx whose parks, usual clouds or scoring rules differ from this watch's
    /// (`WatchContext.dataDiffers`): the score may differ from the iPhone's, and the face says so.
    var dataDiffers = false
    /// What the face says about the data beneath the score, in order (`FaceNote`).
    var notes: [FaceNote] { FaceNote.notes(cloudsOld: cloudsOld, dataDiffers: dataDiffers) }
    var relevance: TimelineEntryRelevance? { rank.map { TimelineEntryRelevance(score: $0.score, duration: $0.duration) } }
}

/// The wearer's colour choice as the complications read it: At dusk is decided per entry, by the Sun
/// at the iPhone's At-dusk place (`WatchContext.duskPlace`) or, before one is sent, at that entry's
/// park, so a face turns red at civil dusk with the app and the phone.
nonisolated struct WristLook: Sendable {
    let choice: PaletteChoice
    let phone: Bool?
    var dusk: Park? = nil
    static var current: WristLook {
        let context = WatchSky.readContext()
        return WristLook(choice: WatchSky.palette, phone: context?.nightVision, dusk: context?.duskPlace)
    }
    /// Placeholders and the face gallery: red, as at a dark site.
    static let red = WristLook(choice: .red, phone: nil)
    func nightVision(park: Park?, at date: Date) -> Bool { choice.nightVision(phone: phone, park: park, dusk: dusk, at: date) }
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
    /// A closure's warning glyph: the app's warm red in full colour (`NyxPalette.cautionColor`), so
    /// amber stays the score's; ink in night vision and wherever the face is tinted.
    var caution: Color { nightVision || !layered ? ink : NyxPalette.cautionColor }
    var mutedOpacity: Double { NyxPalette.mutedOpacity(nightVision: nightVision, highContrast: highContrast) }
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
    /// on the iPhone (`NightPlanner.best`). For a timeline: each park's night is scored once
    /// (`scored`, by park and evening) and reused at every entry, since the snapshot holds still.
    /// Only whether a night lies beyond the forecast depends on the moment
    /// (`NightPlanner.beyondForecast`), so that is worked out again. The watch's details carry no
    /// models' spread (`CompactDetail`), the one other input read against the moment.
    static func best(at date: Date, snapshot: SavedSkySnapshot?, cache: inout [String: SkyConditions], scored: inout [String: Night]) -> Night? {
        var nights: [Night] = []
        for park in snapshot?.parks ?? [] {
            let evening = park.currentNight(at: date), forecast = snapshot?.forecasts[park.id], detail = snapshot?.details?[park.id]
            let key = "\(park.id)-\(Int(evening.timeIntervalSince1970))"
            if var night = scored[key] {
                night.beyondForecast = NightPlanner.beyondForecast(night, forecast: forecast, detail: detail, now: date)
                nights.append(night)
                continue
            }
            let night = WatchSky.night(park, evening: evening, forecast: forecast, detail: detail, now: date, sky: sky(park, evening: evening, cache: &cache),
                                       climate: snapshot?.climate ?? .shared)
            scored[key] = night
            nights.append(night)
        }
        return NightPlanner.best(nights)
    }
    static func entry(at date: Date, snapshot: SavedSkySnapshot?, look: WristLook, dataDiffers: Bool = false, cache: inout [String: SkyConditions]) -> WatchSkyEntry {
        var scored: [String: Night] = [:]
        return entry(at: date, snapshot: snapshot, look: look, dataDiffers: dataDiffers, cache: &cache, scored: &scored)
    }
    static func entry(at date: Date, snapshot: SavedSkySnapshot?, look: WristLook, dataDiffers: Bool = false, cache: inout [String: SkyConditions],
                      scored: inout [String: Night]) -> WatchSkyEntry {
        let best = best(at: date, snapshot: snapshot, cache: &cache, scored: &scored)
        let next = best.flatMap { NightMilestone.next(after: date, in: $0.sky) }
        return WatchSkyEntry(date: date, night: best, next: next, nightVision: look.nightVision(park: best?.park, at: date), rank: best.map { rank(for: $0, at: date) },
                             closure: best.flatMap { snapshot?.closures[$0.park.id] },
                             cloudsOld: best.map { cloudsOld($0.park, forecast: snapshot?.forecasts[$0.park.id], detail: snapshot?.details?[$0.park.id], at: date) } ?? false,
                             dataDiffers: dataDiffers)
    }
    /// The face's "No recent forecast", when the watch app's line says it (`CloudSource.faceOld`).
    static func cloudsOld(_ park: Park, forecast: Forecast?, detail: ForecastDetail?, at date: Date) -> Bool {
        CloudSource.faceOld(park, forecast: forecast?.updated, layers: detail?.layers?.updated, at: date)
    }
    /// When the clouds the park's score counts were issued, as the watch app reads it (`CloudSource.issued`).
    static func issued(_ park: Park, forecast: Forecast?, detail: ForecastDetail?) -> Date? {
        CloudSource.issued(park, forecast: forecast?.updated, layers: detail?.layers?.updated)
    }
    static func issued(_ park: Park, snapshot: SavedSkySnapshot?) -> Date? {
        issued(park, forecast: snapshot?.forecasts[park.id], detail: snapshot?.details?[park.id])
    }
    /// When each snapshot park's clouds turn old within the next day, so the face says so on time.
    static func ageMoments(from now: Date, snapshot: SavedSkySnapshot?) -> [Date] {
        (snapshot?.parks.compactMap { issued($0, snapshot: snapshot)?.addingTimeInterval(CloudSource.lifetime) } ?? []).filter { $0 > now && $0 < now.addingTimeInterval(86400) }
    }
    /// Moments a complication must redraw at besides the hour: Automatic changing colour at the
    /// snapshot's parks over the next day.
    static func paletteMoments(from now: Date, snapshot: SavedSkySnapshot?, look: WristLook) -> [Date] {
        guard look.choice == .automatic else { return [] }
        return (look.dusk.map { [$0] } ?? snapshot?.parks ?? []).flatMap { WristSky.paletteChanges(at: $0, from: now, to: now.addingTimeInterval(WristSky.dayAhead)) }
    }
    /// The moments over the next day at which the park a face follows may change: every hour, and a
    /// second past each park's sunrise, when its night turns over (`Park.nightTurnovers`). Every
    /// timeline here starts from these and picks the park again at each entry, so faces never mix parks.
    static func followMoments(from now: Date, snapshot: SavedSkySnapshot?) -> Set<Date> {
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
        var moments = Set((0..<24).map { hour.addingTimeInterval(Double($0)*3600) })
        for park in snapshot?.parks ?? [] { moments.formUnion(park.nightTurnovers(from: now, to: now.addingTimeInterval(86400))) }
        return moments
    }
    /// A timeline asked for again after its last entry, and never sooner than an hour from now
    /// (a face with nothing to follow yet has only `now`, and must not be asked for again at once).
    static func timeline<Entry: TimelineEntry>(_ entries: [Entry], now: Date) -> Timeline<Entry> {
        Timeline(entries: entries, policy: .after(max(entries.last?.date ?? now, now.addingTimeInterval(3600))))
    }
    /// The same, ending at `until` when it comes first: what the face follows changes then
    /// (`WatchSky.faces`), so the timeline is made again there rather than running on, even when
    /// the hour's floor would otherwise ask later.
    static func timeline<Entry: TimelineEntry>(_ entries: [Entry], now: Date, until end: Date?) -> Timeline<Entry> {
        guard let end, end > now else { return timeline(entries, now: now) }
        let after = max(entries.last?.date ?? now, now.addingTimeInterval(3600))
        return Timeline(entries: entries.filter { $0.date < end }, policy: .after(min(after, end)))
    }
    /// Entries now, at every milestone of the next day (so "next" turns over on time), whenever the
    /// followed park may change (`followMoments`), and hourly. Countdown text updates itself in between.
    static func entries(from now: Date, snapshot: SavedSkySnapshot?, look: WristLook, dataDiffers: Bool = false) -> [WatchSkyEntry] {
        var cache: [String: SkyConditions] = [:], scored: [String: Night] = [:]
        let first = entry(at: now, snapshot: snapshot, look: look, dataDiffers: dataDiffers, cache: &cache, scored: &scored)
        var moments = followMoments(from: now, snapshot: snapshot)
        moments.formUnion(paletteMoments(from: now, snapshot: snapshot, look: look))
        moments.formUnion(ageMoments(from: now, snapshot: snapshot))
        for park in snapshot?.parks ?? [] {
            for offset in 0..<2 {
                let sky = Self.sky(park, evening: park.date(park.currentNight(at: now), addingDays: offset), cache: &cache)
                for milestone in NightMilestone.list(for: sky) where milestone.date > now && milestone.date < now.addingTimeInterval(86400) {
                    moments.insert(milestone.date)
                }
                if let start = duskWindow(sky: sky)?.start, start > now, start < now.addingTimeInterval(86400) { moments.insert(start) }
            }
        }
        return [first] + moments.sorted().map { entry(at: $0, snapshot: snapshot, look: look, dataDiffers: dataDiffers, cache: &cache, scored: &scored) }
    }
    /// From 45 minutes before sunset to the end of true darkness: when a stargazer wants Nyx on the wrist.
    /// Deliberately not `NightPlanner.duskWindow` (the iPhone's: 90 minutes before sunset to an hour
    /// into true darkness). Both share `NightPlanner.worthSurfacing`, so they agree on which nights;
    /// only the hours differ, because the iPhone is for setting out and the wrist stays useful at the
    /// park all night.
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
/// A complication's line has room for about twenty characters once the duration is on it, so
/// there the two long names give way to the short ones the inline complication already uses
/// ("Dark in 1 hr, 10 min", "Dawn in 5 min"); the app keeps the full words. The moments are named as
/// the iPhone's field mode and Live Activity name them (`FieldNight`): Sunset, True darkness,
/// Moonrise, Moonset, Dawn twilight, Sunrise.
func countdownText(_ milestone: NightMilestone, now: Date? = nil) -> Text {
    let reference = now.map { Text(verbatim: inDuration(until: milestone.date, from: $0)) }
        ?? Text(.currentDate, format: .reference(to: milestone.date, allowedFields: [.hour, .minute]))
    let compact = now == nil
    return switch milestone.kind {
    case .sunset: Text("Sunset \(reference)")
    case .darkStart: compact ? Text("Dark \(reference)") : Text("True darkness \(reference)")
    case .moonrise: Text("Moonrise \(reference)")
    case .moonset: Text("Moonset \(reference)")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    private var colors: WristInk { WristInk(nightVision: entry.nightVision, mode: renderingMode, contrast: contrast) }
    private var ink: Color { colors.ink }
    private var accent: Color { colors.accent }
    private var caution: Color { colors.caution }
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
            // A closure takes the Moon's place, in the warning's red: it stands beside the score on every surface.
            if entry.closure != nil { Image(systemName: ClosureLine.symbol).foregroundStyle(caution) } else { MoonSymbol(night: night).foregroundStyle(muted) }
        } currentValueLabel: {
            // Two digits inside a fixed ring: shrink rather than spill over the arc, as on the iPhone's Lock Screen.
            Text(night.score.value, format: .number).scoreNumeral(.title3, accent: accent).minimumScaleFactor(0.6).widgetAccentable()
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(night.score.value)))
        }
        .gaugeStyle(.accessoryCircular).tint(accent).foregroundStyle(ink).widgetAccentable()
    }
    private func corner(_ night: Night) -> some View {
        // The numeral once, in the corner; the curved gauge alone carries the fill, without end labels.
        Text(night.score.value, format: .number).scoreNumeral(.title2, accent: accent).widgetAccentable()
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(night.score.value)))
            .widgetLabel {
                // A closure takes the curved label from the gauge: the numeral stays, the warning is read first.
                if entry.closure != nil {
                    Text("\(Text(Image(systemName: ClosureLine.symbol)).foregroundStyle(caution)) \(Text("Closure alert"))").foregroundStyle(ink).widgetAccentable()
                } else {
                    Gauge(value: Double(night.score.value), in: 0...100) { Text(night.score.band.label) }.tint(accent).widgetAccentable()
                }
            }
    }
    private func inline(_ night: Night) -> some View {
        // Inline is one short line: the next moment's clock time reads at a glance and never goes stale.
        // A closure outranks it.
        Group {
            if entry.closure != nil { Text("\(Image(systemName: ClosureLine.symbol)) \(ClosureLine.inline(score: night.score.value))") }
            // The park's clock, with its zone where it is not this watch's (`wristTime`).
            else if let next = entry.next { Text("\(night.score.value) · \(next.shortTitle) at \(night.park.wristTime(next.date))") }
            else { Text("\(night.score.value) \(night.score.band.label) · \(night.park.shortName)") }
        }.foregroundStyle(ink)
    }
    /// How much of a closure the rectangular complication has room for.
    private enum ClosureFit { case whole(String), alert, mark }
    /// Park, score and band, then the next moment; at large text sizes the moment line drops first.
    /// A closure comes before the moment and is never cut: its own words wrapped whole, else
    /// "Closure alert", else the warning mark beside the numeral (the spoken label always has it all).
    /// A note on the data beneath the score ("Nyx versions differ", "No recent forecast") says so in a
    /// line of its own, which gives way after the next moment and before the closure is shortened;
    /// with two, the second goes first.
    private func rectangular(_ night: Night) -> some View {
        let notes = entry.notes, first = Array(notes.prefix(1))
        return Group {
            if let closure = entry.closure {
                ViewThatFits(in: .vertical) {
                    rectangular(night, closure: .whole(closure), notes: notes, showsNext: true)
                    rectangular(night, closure: .whole(closure), notes: notes, showsNext: false)
                    rectangular(night, closure: .whole(closure), notes: first, showsNext: false)
                    rectangular(night, closure: .whole(closure), notes: [], showsNext: false)
                    rectangular(night, closure: .alert, notes: first, showsNext: false)
                    rectangular(night, closure: .alert, notes: [], showsNext: false)
                    rectangular(night, closure: .mark, notes: [], showsNext: false)
                }
            } else {
                ViewThatFits(in: .vertical) {
                    rectangular(night, closure: nil, notes: notes, showsNext: true)
                    rectangular(night, closure: nil, notes: notes, showsNext: false)
                    rectangular(night, closure: nil, notes: first, showsNext: false)
                    rectangular(night, closure: nil, notes: [], showsNext: false)
                }
            }
        }
        .foregroundStyle(ink).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func rectangular(_ night: Night, closure: ClosureFit?, notes: [FaceNote], showsNext: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                MoonSymbol(night: night).font(.caption2).foregroundStyle(muted)
                Text(night.park.shortName).font(.system(.headline, design: .serif)).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(night.score.value, format: .number).scoreNumeral(.title2, accent: accent).widgetAccentable()
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(night.score.value)))
                if case .mark = closure { Image(systemName: ClosureLine.symbol).font(.caption2).foregroundStyle(caution).widgetAccentable() }
                // Whole or the one word: a basis or smoke note cut mid-word would say less than the
                // word under the score (VoiceOver hears it all in the summary).
                ViewThatFits(in: .horizontal) {
                    Text(night.bandWithBasis).lineLimit(1)
                    Text(night.bandWithBasis).lineLimit(1).minimumScaleFactor(0.8)
                    Text(night.compactBandLabel).lineLimit(1).minimumScaleFactor(0.8)
                }.font(.caption2).foregroundStyle(muted)
            }
            // Measured at full height, so a closure that would need cutting gives way to a shorter form instead.
            switch closure {
            case .whole(let text): closureLine(Text(text))
            case .alert: closureLine(Text("Closure alert"))
            case .mark, nil: EmptyView()
            }
            ForEach(notes, id: \.self) { note in
                Label { Text(note.short) } icon: { Image(systemName: note.symbol) }
                    .font(.caption2).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            if showsNext, let next = entry.next {
                Group {
                    if clockTimes { Text("\(next.title) at \(night.park.wristTime(next.date))") } else { countdownText(next) }
                }.font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func closureLine(_ text: Text) -> some View {
        Label { text.foregroundStyle(ink) } icon: { Image(systemName: ClosureLine.symbol).foregroundStyle(caution) }
            .font(.caption2.weight(.medium)).widgetAccentable()
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
        var text = String(localized: "\(night.park.shortName), \(night.score.value) out of 100, \(night.score.band.label).")
        // The closure is spoken in every family, right after the score it stands beside.
        if let closure = entry.closure { text += " " + ClosureLine.spoken(closure) }
        if let caption = night.basisCaption() { text += " " + caption }
        if let smoke = night.smokeSentence() { text += " " + smoke }
        // In every family, though only the rectangular one has room to show them.
        for note in entry.notes { text += " " + note.spoken }
        if let next = entry.next {
            text += " " + String(localized: "\(next.title) at \(night.park.time(next.date)).")
            // The time is the park's: where its clock is not this watch's, say whose.
            if let zone = night.park.spokenZone(at: next.date) { text += " " + zone }
        }
        return text
    }
}

#Preview("Tonight • old forecast, rectangular") { OldForecastPreview() }
#Preview("Tonight • old forecast and closure") { OldForecastPreview(closure: "Keys View Road and the Geology Tour Road closed for repairs through November") }
#Preview("Tonight • old forecast • xxxLarge") { OldForecastPreview(closure: "Keys View Road closed at night").dynamicTypeSize(.xxxLarge) }
#Preview("Tonight • versions differ") { OldForecastPreview(old: false, differs: true) }
#Preview("Tonight • versions differ, old forecast and closure") { OldForecastPreview(closure: "Keys View Road closed at night", differs: true) }
/// The rectangular face with a forecast 36 hours old (or an iPhone on another version of Nyx), in
/// full colour and tinted, from the real engine.
private struct OldForecastPreview: View {
    var closure: String? = nil
    var old = true
    var differs = false
    private var entry: WatchSkyEntry {
        var cache: [String: SkyConditions] = [:]
        let entry = WatchTimeline.entry(at: .now, snapshot: WatchTimeline.sample, look: .red, cache: &cache)
        return WatchSkyEntry(date: entry.date, night: entry.night, next: entry.next, nightVision: false, closure: closure, cloudsOld: old, dataDiffers: differs)
    }
    var body: some View {
        VStack(spacing: 8) {
            WatchComplicationView(previewFamily: .accessoryRectangular, entry: entry).frame(height: 60)
            WatchComplicationView(previewFamily: .accessoryRectangular, entry: entry).frame(height: 60).environment(\.widgetRenderingMode, .accented)
        }
        .padding(.horizontal, 6)
    }
}
