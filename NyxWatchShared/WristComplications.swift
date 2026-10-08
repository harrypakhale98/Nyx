import SwiftUI
import WidgetKit

// Two more ways to tell darkness at a glance: the Moon right now (no forecast, never stale) and
// the next stretch of truly dark sky. Both follow the park Tonight follows and the wearer's colours.

/// The Moon from the followed park at one moment.
nonisolated struct MoonEntry: TimelineEntry, Sendable {
    let date: Date
    let park: Park?
    let moon: MoonNow
    let nightVision: Bool
}

/// The next truly dark sky at the followed park at one moment.
nonisolated struct NextDarkEntry: TimelineEntry, Sendable {
    let date: Date
    let park: Park?
    let moment: DarkMoment
    let nightVision: Bool
}

nonisolated enum WristTimeline {
    /// The followed park at `date`: the darkest of the snapshot's parks tonight, as on Tonight.
    static func park(at date: Date, snapshot: SavedSkySnapshot?, cache: inout [String: SkyConditions]) -> Park? {
        WatchTimeline.best(at: date, snapshot: snapshot, cache: &cache)?.park ?? snapshot?.parks.first
    }
    /// Now, every hour for a day, at each rise and set, and where Automatic changes colour.
    static func moonEntries(from now: Date, snapshot: SavedSkySnapshot?, look: WristLook) -> [MoonEntry] {
        var cache: [String: SkyConditions] = [:]
        let followed = park(at: now, snapshot: snapshot, cache: &cache)
        let events = followed.map { park in MoonNow.events(at: park, around: now) { WatchTimeline.sky(park, evening: $0, cache: &cache) } } ?? []
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
        var moments = Set((0..<24).map { hour.addingTimeInterval(Double($0)*3600) })
        moments.formUnion(events.map(\.date).filter { $0 > now && $0 < now.addingTimeInterval(86400) })
        moments.formUnion(WatchTimeline.paletteMoments(from: now, snapshot: followed.map { SavedSkySnapshot(parks: [$0], forecasts: [:]) }, look: look))
        return ([now] + moments.sorted()).map { date in
            MoonEntry(date: date, park: followed, moon: MoonNow(at: date, park: followed, events: events), nightVision: look.nightVision(park: followed, at: date))
        }
    }
    /// Now, at each moment the answer changes (true darkness, moonrise, moonset, dawn) over the
    /// next day, hourly, and where Automatic changes colour.
    static func nextDarkEntries(from now: Date, snapshot: SavedSkySnapshot?, look: WristLook) -> [NextDarkEntry] {
        var cache: [String: SkyConditions] = [:]
        guard let followed = park(at: now, snapshot: snapshot, cache: &cache) else {
            return [NextDarkEntry(date: now, park: nil, moment: .none, nightVision: look.nightVision(park: nil, at: now))]
        }
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
        var moments = Set((0..<24).map { hour.addingTimeInterval(Double($0)*3600) })
        for offset in 0..<2 {
            let sky = WatchTimeline.sky(followed, evening: followed.date(followed.currentNight(at: now), addingDays: offset), cache: &cache)
            for date in [sky.darkStart, sky.darkEnd, sky.moonrise, sky.moonset].compactMap({ $0 }) where date > now && date < now.addingTimeInterval(86400) {
                moments.insert(date.addingTimeInterval(1))
            }
        }
        moments.formUnion(WatchTimeline.paletteMoments(from: now, snapshot: SavedSkySnapshot(parks: [followed], forecasts: [:]), look: look))
        return ([now] + moments.sorted()).map { date in
            NextDarkEntry(date: date, park: followed, moment: DarkMoment.next(at: followed, now: date) { WatchTimeline.sky(followed, evening: $0, cache: &cache) },
                          nightVision: look.nightVision(park: followed, at: date))
        }
    }
}

/// The Moon's phase as a symbol, turned for the southern sky (American Samoa sees it upside down).
struct MoonPhaseGlyph: View {
    let phase: MoonPhase
    let southern: Bool
    var body: some View {
        Image(systemName: phase.symbolName).scaleEffect(x: southern ? -1 : 1, y: southern ? -1 : 1)
    }
}

struct MoonComplicationView: View {
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    var previewFamily: WidgetFamily?
    let entry: MoonEntry
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    private var colors: WristInk { WristInk(nightVision: entry.nightVision, mode: renderingMode) }
    private var glyph: MoonPhaseGlyph { MoonPhaseGlyph(phase: entry.moon.phase, southern: (entry.park?.latitude ?? 0) < 0) }
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        glyph.font(.title3).widgetAccentable()
                        Text("\(entry.moon.percent)%").font(.system(.caption2, design: .serif).weight(.medium)).foregroundStyle(colors.muted)
                    }
                }
            case .accessoryCorner:
                glyph.font(.title2).foregroundStyle(colors.accent).widgetAccentable()
                    .widgetLabel { Text(cornerLine) }
            case .accessoryInline:
                Text("\(Image(systemName: entry.moon.phase.symbolName)) \(cornerLine)")
            default:
                HStack(spacing: 8) {
                    glyph.font(.title).foregroundStyle(colors.accent).widgetAccentable()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.moon.phase.name).font(.system(.headline, design: .serif)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(litLine).font(.caption2).foregroundStyle(colors.muted).lineLimit(1).minimumScaleFactor(0.8)
                        if let event = eventLine { Text(event).font(.caption2).lineLimit(1).minimumScaleFactor(0.8) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(colors.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityIgnoresInvertColors()
        .containerBackground(for: .widget) { Color.black }
        // A tap opens tonight at the park whose Moon this is.
        .widgetURL(entry.park.flatMap { WatchLink(park: $0, evening: $0.currentNight(at: entry.date)).url })
    }
    /// "34% lit · up now", or the phase's light alone before a park is chosen.
    private var litLine: String {
        switch entry.moon.isUp {
        case true?: String(localized: "\(entry.moon.percent)% lit · up now")
        case false?: String(localized: "\(entry.moon.percent)% lit · down now")
        case nil: String(localized: "\(entry.moon.percent)% lit")
        }
    }
    /// "Sets 11:40 PM · Joshua Tree" in park time.
    private var eventLine: String? {
        guard let park = entry.park, let next = entry.moon.next else { return nil }
        let time = park.time(next.date)
        return next.rises ? String(localized: "Rises \(time) · \(park.wristName)") : String(localized: "Sets \(time) · \(park.wristName)")
    }
    private var cornerLine: String {
        guard let park = entry.park, let next = entry.moon.next else { return String(localized: "\(entry.moon.percent)% lit") }
        let time = park.time(next.date)
        return next.rises ? String(localized: "\(entry.moon.percent)% · rises \(time)") : String(localized: "\(entry.moon.percent)% · sets \(time)")
    }
    private var summary: String {
        var text = String(localized: "\(entry.moon.phase.name), \(entry.moon.percent) percent lit.")
        if let up = entry.moon.isUp { text += " " + (up ? String(localized: "The Moon is up.") : String(localized: "The Moon is down.")) }
        if let park = entry.park, let next = entry.moon.next {
            text += " " + (next.rises ? String(localized: "Moonrise at \(park.time(next.date)) at \(park.wristName).") : String(localized: "Moonset at \(park.time(next.date)) at \(park.wristName)."))
        }
        return text
    }
}

struct NextDarkComplicationView: View {
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    var previewFamily: WidgetFamily?
    let entry: NextDarkEntry
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    private var colors: WristInk { WristInk(nightVision: entry.nightVision, mode: renderingMode) }
    private var target: Date? { entry.moment.target(at: entry.date) }
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: symbol).font(.caption).widgetAccentable()
                        // The clock time, not a countdown: it fits the circle and never goes stale.
                        if let target, let park = entry.park {
                            Text(Self.shortTime(target, in: park))
                                .font(.system(.footnote, design: .serif).weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        } else {
                            Text(verbatim: "—").font(.footnote)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            case .accessoryCorner:
                Image(systemName: symbol).font(.title3).foregroundStyle(colors.accent).widgetAccentable()
                    .widgetLabel { headline }
            case .accessoryInline:
                Text(inline)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: symbol).font(.caption2).foregroundStyle(colors.muted)
                        Text(entry.park?.wristName ?? "Nyx").font(.system(.headline, design: .serif)).lineLimit(1)
                    }
                    headline.font(.system(.body, design: .serif)).foregroundStyle(colors.accent).widgetAccentable().lineLimit(1).minimumScaleFactor(0.7)
                    Text(detail).font(.caption2).foregroundStyle(colors.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(colors.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .containerBackground(for: .widget) { Color.black }
        // A tap opens the night the countdown points into.
        .widgetURL(entry.park.flatMap { WatchLink(park: $0, evening: $0.currentNight(at: target ?? entry.date)).url })
    }
    /// "7:48", park time, without AM/PM: the circle has room for the digits only.
    static func shortTime(_ date: Date, in park: Park) -> String {
        var format = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()
        format.timeZone = park.timeZone
        return date.formatted(format)
    }
    private var symbol: String {
        switch entry.moment {
        case .darkNow: "moon.stars.fill"
        case .begins(_, true): "moonset.fill"
        case .begins: "moon.stars"
        case .moonlit: "moon.haze"
        case .none: "sun.horizon"
        }
    }
    /// A self-updating relative time, "in 1 hr, 10 min".
    private func reference(_ date: Date) -> Text { Text(.currentDate, format: .reference(to: date, allowedFields: [.hour, .minute])) }
    @ViewBuilder private var headline: some View {
        switch entry.moment {
        case .darkNow: Text("Truly dark now")
        case .begins(let date, true): Text("Moon down \(reference(date))")
        case .begins(let date, false): Text("True darkness \(reference(date))")
        case .moonlit(let from, _) where from > entry.date: Text("True darkness \(reference(from))")
        case .moonlit: Text("Moonlit darkness now")
        case .none: Text("No true darkness")
        }
    }
    private var detail: String {
        guard let park = entry.park else { return String(localized: "Choose a park in Nyx on Apple Watch.") }
        switch entry.moment {
        case .darkNow(let until, true): return String(localized: "Until moonrise at \(park.time(until))")
        case .darkNow(let until, false): return String(localized: "Until dawn twilight at \(park.time(until))")
        case .begins(let date, true): return String(localized: "Moonset at \(park.time(date))")
        case .begins(let date, false): return String(localized: "At \(park.time(date))")
        case .moonlit: return String(localized: "The Moon is up all through true darkness.")
        case .none: return String(localized: "The Sun stays too high at this latitude.")
        }
    }
    /// Clock times, never a countdown: inline text cannot update itself.
    private var inline: String {
        guard let park = entry.park else { return String(localized: "Nyx · choose a park") }
        switch entry.moment {
        case .darkNow(let until, _): return String(localized: "Dark until \(park.time(until))")
        case .begins(let date, true): return String(localized: "Moon down at \(park.time(date))")
        case .begins(let date, false): return String(localized: "Dark at \(park.time(date))")
        case .moonlit(_, let to): return String(localized: "Moonlit until \(park.time(to))")
        case .none: return String(localized: "No true darkness")
        }
    }
    private var summary: String {
        guard let park = entry.park else { return String(localized: "Nyx. Choose a park in Nyx on Apple Watch.") }
        switch entry.moment {
        case .darkNow(let until, _): return String(localized: "\(park.wristName). Truly dark now, until \(park.time(until)).")
        case .begins(let date, true): return String(localized: "\(park.wristName). The Moon sets at \(park.time(date)); truly dark from then.")
        case .begins(let date, false): return String(localized: "\(park.wristName). True darkness at \(park.time(date)).")
        case .moonlit(let from, let to): return String(localized: "\(park.wristName). True darkness from \(park.time(from)) to \(park.time(to)), with the Moon up all through it.")
        case .none: return String(localized: "\(park.wristName). No true darkness tonight at this latitude.")
        }
    }
}
