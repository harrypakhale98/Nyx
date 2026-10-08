import SwiftUI
import WidgetKit

/// The Moon widget: tonight's Moon, how much is lit, whether it is up, and its next rise or set at
/// a park. Computed from the date alone (no forecast), so it is never stale. Shared by the widget
/// extension and the app's DEBUG review screen.
struct MoonEntry: TimelineEntry {
    let date: Date
    let moon: MoonNow
    /// The park whose rise and set times are shown; nil shows the phase alone.
    let park: Park?
    /// The park's night at `date`, for the app's picture of that night's Moon.
    let night: Date?
    let nightVision: Bool
    init(date: Date, park: Park?, nightVision: Bool) {
        self.date=date; self.park=park; self.nightVision=nightVision
        moon=MoonNow(at: date, park: park)
        night=park.map { $0.currentNight(at: date) }
    }
}
struct MoonWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.displayScale) private var displayScale
    var previewFamily: WidgetFamily?=nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    let entry: MoonEntry
    private var tinted: Bool { renderingMode != .fullColor }
    private var nightVision: Bool { entry.nightVision && !tinted }
    private var ink: Color { tinted ? .white : nightVision ? Color(red:1,green:0.27,blue:0.23) : Color(red:0.961,green:0.945,blue:0.902) }
    private var muted: Color { ink.opacity(tinted ? 0.62 : nightVision ? 0.9 : 0.7) }
    private var southern: Bool { (entry.park?.latitude ?? 1)<0 }
    var body: some View {
        content.foregroundStyle(ink)
            .accessibilityElement(children: .ignore).accessibilityLabel(summary)
            .containerBackground(for: .widget) { WidgetSky(seed: "moon", ink: ink) }
            .widgetURL(URL(string: entry.park.map { "nyx://park/\($0.id)" } ?? "nyx://tonight"))
    }
    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Label { Text(verbatim: "\(entry.moon.phase.name) · \(entry.moon.percent)%") } icon: { symbol }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    symbol.font(.title3).widgetAccentable()
                    Text(verbatim: "\(entry.moon.percent)%").font(.caption2.weight(.medium)).monospacedDigit()
                }
            }.dynamicTypeSize(.small ... .xxxLarge)
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text("THE MOON").font(.caption2.weight(.medium)).tracking(0.8).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                }
                disc.frame(width: 58, height: 58).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 2)
                Text(entry.moon.phase.name).font(.system(.subheadline, design: .serif)).lineLimit(1).minimumScaleFactor(0.75)
                Text(litLine).font(.caption2).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)
                if let event=eventLine { Text(event).font(.caption2).lineLimit(1).minimumScaleFactor(0.75) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(.small ... .xLarge)
        }
    }
    /// The phase as a symbol, turned for the southern sky.
    private var symbol: some View {
        Image(systemName: entry.moon.phase.symbolName).scaleEffect(x: southern ? -1 : 1, y: southern ? -1 : 1)
    }
    /// The app's picture of that night's Moon (or the nearest night it drew), else the vector Moon.
    @ViewBuilder private var disc: some View {
        if let park=entry.park, let night=entry.night, let url=SharedSettings.moonImage(park: park.id, night: night), let image=UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().widgetAccentedRenderingMode(.accentedDesaturated).scaledToFit()
                .accessibilityIgnoresInvertColors().modifier(NightVisionFilter(enabled: nightVision))
        } else {
            MoonDisc(illumination: entry.moon.phase.illumination, waxing: entry.moon.phase.waxing, southern: southern)
                .environment(\.nyx, NyxPalette(nightVision: nightVision, highContrast: false))
                .accessibilityIgnoresInvertColors().modifier(NightVisionFilter(enabled: nightVision))
        }
    }
    private var litLine: String {
        switch entry.moon.isUp {
        case true?: String(localized: "\(entry.moon.percent)% lit · up now")
        case false?: String(localized: "\(entry.moon.percent)% lit · down now")
        case nil: String(localized: "\(entry.moon.percent)% lit")
        }
    }
    /// "Rises 8:12 PM · Joshua Tree", in park time.
    private var eventLine: String? {
        guard let park=entry.park, let next=entry.moon.next else { return nil }
        let time=park.time(next.date)
        return next.rises ? String(localized: "Rises \(time) · \(park.shortName)") : String(localized: "Sets \(time) · \(park.shortName)")
    }
    var summary: String {
        var text=String(localized: "\(entry.moon.phase.name), \(entry.moon.percent) percent lit.")
        if let up=entry.moon.isUp { text+=" "+(up ? String(localized: "The Moon is up.") : String(localized: "The Moon is down.")) }
        if let park=entry.park, let next=entry.moon.next {
            text+=" "+(next.rises ? String(localized: "Moonrise at \(park.time(next.date)) at \(park.shortName).") : String(localized: "Moonset at \(park.time(next.date)) at \(park.shortName)."))
        }
        return text
    }
}
#Preview("Moon widget") {
    let park=(try? ParkData.load())?.first { $0.id == "jotr" }
    HStack(spacing: 20) {
        MoonWidgetView(previewFamily: .systemSmall, entry: MoonEntry(date: .now, park: park, nightVision: false)).frame(width: 158, height: 158).background(.black)
        MoonWidgetView(previewFamily: .accessoryCircular, entry: MoonEntry(date: .now, park: park, nightVision: false)).frame(width: 68, height: 68)
    }.padding().background(Color(white: 0.2))
}
