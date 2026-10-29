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
    /// Set to a place no longer saved (`TonightProvider.unsaved`): its name, or "" when the setting
    /// kept none. The widget says so rather than showing the Moon from nowhere in particular.
    let unsaved: String?
    init(date: Date, park: Park?, nightVision: Bool, unsaved: String?=nil) {
        self.date=date; self.park=park; self.nightVision=nightVision; self.unsaved=unsaved
        moon=MoonNow(at: date, park: park)
        night=park.map { $0.currentNight(at: date) }
    }
    /// The system's redacted placeholder: the Moon at Joshua Tree from the bundled parks, never the
    /// App Group's snapshot (0.8 MB, decoded synchronously, for a shape drawn redacted).
    static func placeholder(at date: Date = .now) -> MoonEntry {
        MoonEntry(date: date, park: (try? ParkData.load())?.first { $0.id == Park.defaultID }, nightVision: false)
    }
}
struct MoonWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var previewFamily: WidgetFamily?=nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    let entry: MoonEntry
    private var tinted: Bool { renderingMode != .fullColor }
    /// The app's night look: its red (brighter by choice or under Increase Contrast) and contrast.
    private var look: NightLook { NightLook(contrast: contrast, nightVision: entry.nightVision && !tinted) }
    private var nightVision: Bool { look.nightVision }
    private var ink: Color { tinted ? .white : look.ink }
    private var muted: Color { tinted ? ink.opacity(0.62) : look.muted }
    /// The Moon's words, shared with the watch's Moon complication (`MoonRectangleText`).
    private var text: MoonRectangleText { MoonRectangleText(moon: entry.moon, park: entry.park) }
    /// How much is lit, in the reader's own percent style ("42 %" where that is the custom).
    private var percent: String { Percent.text(entry.moon.phase.percentLit) }
    private var southern: Bool { (entry.park?.latitude ?? 1)<0 }
    var body: some View {
        Group {
            if let name=entry.unsaved { UnsavedPlaceFace(name: name, family: family, muted: muted) }
            else { content.accessibilityElement(children: .ignore).accessibilityLabel(summary) }
        }
        .foregroundStyle(ink)
        .containerBackground(for: .widget) { WidgetSky(seed: "moon", ink: ink) }
        .widgetURL(URL(string: entry.park.map { "nyx://park/\($0.id)" } ?? "nyx://tonight"))
    }
    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Label { Text(verbatim: "\(entry.moon.phase.name) · \(percent)") } icon: { symbol }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    symbol.font(.title3).widgetAccentable()
                    Text(verbatim: percent).font(.caption2.weight(.medium)).monospacedDigit().contentTransition(reduceMotion ? .opacity : .numericText())
                }
            }.dynamicTypeSize(.small ... .xxxLarge)
        case .accessoryRectangular:
            // Three lines on the Lock Screen: the phase as the heading, how much is lit, then the
            // next rise or set in park time (the park's name dropped before the time is cut).
            let text=self.text
            VStack(alignment: .leading, spacing: 1) {
                Label { Text(text.phase).lineLimit(1).minimumScaleFactor(0.8) } icon: { symbol.widgetAccentable() }
                    .font(.headline)
                Text(text.lit).font(.caption).lineLimit(1)
                if let event=text.event, let short=text.shortEvent {
                    ViewThatFits(in: .horizontal) {
                        Text(event).lineLimit(1)
                        Text(short).lineLimit(1).minimumScaleFactor(0.8)
                    }.font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(.small ... .xxxLarge)
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text("The Moon").textCase(Lettering.spaced ? .uppercase : nil).font(.caption2.weight(.medium)).tracking(Lettering.spaced ? 0.8 : 0).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                }
                disc.frame(width: 58, height: 58).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 2)
                Text(entry.moon.phase.name).font(.system(.subheadline, design: .serif)).lineLimit(1).minimumScaleFactor(0.75)
                Text(text.litNow).font(.caption2).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8).contentTransition(reduceMotion ? .opacity : .numericText())
                if let event=text.event { Text(event).font(.caption2).lineLimit(1).minimumScaleFactor(0.75) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(.small ... .xLarge)
        }
    }
    /// The phase as a symbol, turned for the southern sky.
    private var symbol: some View {
        Image(systemName: entry.moon.phase.symbolName(southern: southern))
    }
    /// The app's picture of that night's Moon, else the vector Moon.
    @ViewBuilder private var disc: some View {
        if let park=entry.park, let night=entry.night, let url=SharedSettings.moonImage(park: park.id, night: night), let image=UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().widgetAccentedRenderingMode(.accentedDesaturated).scaledToFit()
                .accessibilityIgnoresInvertColors().modifier(NightVisionFilter(enabled: nightVision, red: look.red))
        } else {
            MoonDisc(illumination: entry.moon.phase.illumination, waxing: entry.moon.phase.waxing, southern: southern)
                .environment(\.nyx, look.palette)
                .accessibilityIgnoresInvertColors().modifier(NightVisionFilter(enabled: nightVision, red: look.red))
        }
    }
    /// "Waxing crescent, 23 percent lit. The Moon is up. Moonset at 11:40 PM, Joshua Tree."
    var summary: String { text.spoken }
}
#Preview("Moon widget") {
    let park=(try? ParkData.load())?.first { $0.id == "jotr" }
    HStack(spacing: 20) {
        MoonWidgetView(previewFamily: .systemSmall, entry: MoonEntry(date: .now, park: park, nightVision: false)).frame(width: 158, height: 158).background(.black)
        MoonWidgetView(previewFamily: .accessoryCircular, entry: MoonEntry(date: .now, park: park, nightVision: false)).frame(width: 68, height: 68)
    }.padding().background(Color(white: 0.2))
}
#Preview("Moon widget, Lock Screen rectangle") {
    let library=(try? ParkData.load()) ?? []
    VStack(alignment: .leading, spacing: 16) {
        // A park's next rise or set; a longer name that may give way to the time alone; far north; no park.
        ForEach(["jotr", "grsa", "gaar"], id: \.self) { id in
            MoonWidgetView(previewFamily: .accessoryRectangular, entry: MoonEntry(date: .now, park: library.first { $0.id == id }, nightVision: false)).frame(width: 160, height: 72)
        }
        MoonWidgetView(previewFamily: .accessoryRectangular, entry: MoonEntry(date: .now, park: nil, nightVision: false)).frame(width: 160, height: 72)
    }.foregroundStyle(.white).padding().background(Color(white: 0.2))
}
#Preview("Moon widget, place no longer saved") {
    HStack(spacing: 20) {
        MoonWidgetView(previewFamily: .systemSmall, entry: MoonEntry(date: .now, park: nil, nightVision: false, unsaved: "Eifel")).frame(width: 158, height: 158).background(.black)
        MoonWidgetView(previewFamily: .accessoryRectangular, entry: MoonEntry(date: .now, park: nil, nightVision: false, unsaved: "Eifel")).frame(width: 160, height: 72)
    }.foregroundStyle(.white).padding().background(Color(white: 0.2))
}
