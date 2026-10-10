import SwiftUI
import WidgetKit

/// Screenshot routes for the watch, DEBUG only (Release always starts on Tonight):
/// `-nyx-watch-screen tonight | milestones | week | dark | parks | chooser | credits | complications`
/// `-nyx-watch-state synced | unsynced | polar | samoa | closure | expired | models`, `-nyx-watch-palette automatic | red | phone | standard`,
/// `-nyx-watch-night 0…6` (Tonight turned to that night with the Crown), `-nyx-watch-adaptation <minutes>`
/// (the adaptation clock started that long ago), `-nyx-watch-info` (the dark-adaptation info sheet), `-nyx-watch-aod` (Always-On, which the simulator cannot show),
/// `-nyx-watch-face` (with `complications`: the full-colour renders alone, unlabelled, for the store frame).
/// States change who is followed, never a score: every night is computed by the real engine.
enum WatchDebug {
    static var screen: String? {
        #if DEBUG
        return argument("-nyx-watch-screen")
        #else
        return nil
        #endif
    }
    static var initialPage: Int { ["milestones": 1, "week": 2][screen ?? ""] ?? 0 }
    static var initialNight: Int {
        #if DEBUG
        return argument("-nyx-watch-night").flatMap(Int.init).map { min(6, max(0, $0)) } ?? 0
        #else
        return 0
        #endif
    }
    /// `-nyx-watch-info` (with `-nyx-watch-screen dark`): the dark-adaptation info sheet open.
    static var showsInfo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-nyx-watch-info")
        #else
        return false
        #endif
    }
    /// Screens that are Tonight itself (a page, or the dark-adaptation cover over it).
    static let homeScreens: Set<String> = ["tonight", "milestones", "week", "dark"]
    /// `-nyx-watch-ax`: the largest accessibility text size (the watch simulator cannot set it);
    /// `-nyx-watch-xxxl`: the largest size short of the accessibility sizes.
    struct TypeSize: ViewModifier {
        func body(content: Content) -> some View {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-nyx-watch-ax") { content.dynamicTypeSize(.accessibility5) }
            else if ProcessInfo.processInfo.arguments.contains("-nyx-watch-xxxl") { content.dynamicTypeSize(.xxxLarge) }
            else { content }
            #else
            content
            #endif
        }
    }
    /// `-nyx-watch-aod`: the wrist-down rendering, for review.
    struct AlwaysOn: ViewModifier {
        func body(content: Content) -> some View {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-nyx-watch-aod") { content.environment(\.isLuminanceReduced, true) } else { content }
            #else
            content
            #endif
        }
    }
    /// `-nyx-watch-scroll bottom`: scroll views open at their end, to review what sits below the fold.
    struct ScrollEnd: ViewModifier {
        func body(content: Content) -> some View {
            #if DEBUG
            content.defaultScrollAnchor(argument("-nyx-watch-scroll") == "bottom" ? .bottom : nil)
            #else
            content
            #endif
        }
    }
    #if DEBUG
    private static func argument(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), index+1 < args.count else { return nil }
        return args[index+1]
    }
    static func apply(to store: WatchStore) {
        if let palette = argument("-nyx-watch-palette").flatMap(PaletteChoice.init(rawValue:)) { store.palette = palette }
        // Fixture contexts carry no usable forecast: a fixture never invents clouds.
        let synced = WatchContext(sent: .now, savedParkIDs: ["jotr", "deva", "grba", "bibe"], homeParkID: "jotr", nightVision: true, forecasts: [:])
        switch argument("-nyx-watch-state") {
        case "unsynced": store.debugSet(context: nil, pinned: nil)
        case "synced": store.debugSet(context: synced, pinned: nil)
        case "polar": store.debugSet(context: synced, pinned: "dena")
        case "samoa": store.debugSet(context: synced, pinned: "npsa")
        case "closure":
            // A fixture closure, for reviewing the line beside the score; it never touches a score.
            let closed = WatchContext(sent: .now, savedParkIDs: synced.savedParkIDs, homeParkID: "jotr", nightVision: true, forecasts: [:],
                                      closures: ["jotr": "Keys View Road closed for repairs through November"])
            store.debugSet(context: closed, pinned: nil)
        case "models":
            // The forecast models' range, for review: the iPhone's own "disagree" forecast fixture
            // (`DebugForecasts`, a different spread each night), its ranges worked out by the
            // iPhone's rule (`NightOutlook.of`, `dialRange`) and handed over through
            // `WatchContext.make`, as a paired iPhone would. The only watch fixture with clouds,
            // because a range needs a forecast; it changes what the wrist is told, never the engine.
            guard let context = modelsContext(savedParkIDs: synced.savedParkIDs, store: store) else { break }
            store.debugSet(context: context, pinned: "jotr")
        case "expired":
            // A forecast the iPhone sent three days ago: too old to score, so the watch says so.
            let old = Date.now.addingTimeInterval(-3*86400)
            let hours = (0..<48).map { old.timeIntervalSince1970.rounded(.down) + Double($0)*3600 }
            let forecast = Forecast(updated: old, times: hours, clouds: hours.map { _ in nil })
            let compact = CompactForecast(forecast, from: old.addingTimeInterval(-3600), to: .now).map { ["jotr": $0] } ?? [:]
            store.debugSet(context: WatchContext(sent: old, savedParkIDs: ["jotr"], homeParkID: "jotr", nightVision: true, forecasts: compact), pinned: nil)
        default: break
        }
        if let minutes = argument("-nyx-watch-adaptation").flatMap(Double.init) {
            store.debugSet(adaptation: AdaptationClock(start: .now.addingTimeInterval(-minutes*60)))
        }
    }
    /// The context a paired iPhone would hand over for the "disagree" forecast fixture, ranges and
    /// all (the `models` state, and the previews of every place the range shows).
    static func modelsContext(savedParkIDs: [String], store: WatchStore, now: Date = .now) -> WatchContext? {
        let parks = savedParkIDs.compactMap { store.park($0) }
        guard let fixture = DebugForecasts(state: "disagree", parks: parks, now: now) else { return nil }
        var ranges: [String: [String: ClosedRange<Int>]] = [:]
        for park in parks {
            guard let detail = fixture.details[park.id] else { continue }
            for offset in 0..<7 {
                let evening = park.date(park.currentNight(at: now), addingDays: offset)
                let night = WatchSky.night(park, evening: evening, forecast: fixture.forecasts[park.id], detail: detail, now: now)
                if let range = NightOutlook.of(night, detail: detail, now: now, scoring: ScoreEngine())?.dialRange(basis: night.basis) {
                    ranges[park.id, default: [:]][WatchContext.day(night.id, in: park)] = range
                }
            }
        }
        return WatchContext.make(savedParkIDs: savedParkIDs, homeParkID: savedParkIDs.first ?? "jotr", nightVision: true, forecasts: fixture.forecasts,
                                 details: fixture.details, ranges: ranges, now: now)
    }
    @MainActor @ViewBuilder static func view(_ screen: String) -> some View {
        switch screen {
        case "parks": ParksList()
        case "chooser": ParkChooser()
        case "credits": WatchCredits()
        case "complications": DebugFeatured { ComplicationReview(park: $0) }
        default: EmptyView()
        }
    }
    #endif
}

#if DEBUG
private struct DebugFeatured<Content: View>: View {
    @Environment(WatchStore.self) private var store
    @ViewBuilder let content: (Park) -> Content
    var body: some View {
        if let park = store.featured(at: .now) ?? store.park("jotr") { content(park) }
    }
}
/// Every complication family of every kind, drawn from the live engine for review, in full colour
/// and then tinted (accented); the face itself is checked on device.
private struct ComplicationReview: View {
    @Environment(WatchStore.self) private var store
    let park: Park
    var body: some View {
        let night = store.tonight(park, at: .now)
        let red = store.nightVision(at: .now)
        let entry = WatchSkyEntry(date: .now, night: night, next: NightMilestone.next(after: .now, in: night.sky), nightVision: red)
        let moon = MoonEntry(date: .now, park: park, moon: MoonNow(at: .now, park: park), nightVision: red)
        let dark = NextDarkEntry(date: .now, park: park, moment: DarkMoment.next(at: park, now: .now), nightVision: red)
        // Countdowns are drawn for this moment: a live `.currentDate` reference inside an app scroll view
        // never finished its first layout on the watchOS 27 simulator (the widget extension counts down live).
        if ProcessInfo.processInfo.arguments.contains("-nyx-watch-face") {
            // `-nyx-watch-face`: the full-colour renders alone, unlabelled, circular ones clipped to
            // their circles as on a face, for the store's complications frame.
            VStack(spacing: 6) {
                HStack(spacing: 16) {
                    WatchComplicationView(previewFamily: .accessoryCircular, entry: entry).frame(width: 50, height: 50).clipShape(Circle())
                    NextDarkComplicationView(previewFamily: .accessoryCircular, entry: dark, now: .now).frame(width: 50, height: 50).clipShape(Circle())
                }
                WatchComplicationView(previewFamily: .accessoryRectangular, entry: entry, clockTimes: true).frame(height: 56)
                NextDarkComplicationView(previewFamily: .accessoryRectangular, entry: dark, now: .now).frame(height: 56)
                WatchComplicationView(previewFamily: .accessoryInline, entry: entry).frame(height: 20)
            }
            .environment(\.widgetRenderingMode, .fullColor)
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .toolbar(.hidden, for: .navigationBar)
        } else {
            review(entry: entry, moon: moon, dark: dark, red: red)
        }
    }
    @ViewBuilder private func review(entry: WatchSkyEntry, moon: MoonEntry, dark: NextDarkEntry, red: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ProcessInfo.processInfo.arguments.contains("-nyx-watch-tinted") ? [WidgetRenderingMode.accented] : [.fullColor, .accented], id: \.description) { mode in
                    Group {
                        Text(mode == .fullColor ? "Full color" : "Tinted").font(.caption2).foregroundStyle(.gray)
                        HStack(spacing: 8) {
                            WatchComplicationView(previewFamily: .accessoryCircular, entry: entry).frame(width: 50, height: 50)
                            MoonComplicationView(previewFamily: .accessoryCircular, entry: moon).frame(width: 50, height: 50)
                            NextDarkComplicationView(previewFamily: .accessoryCircular, entry: dark, now: .now).frame(width: 50, height: 50)
                        }
                        HStack(spacing: 8) {
                            WatchComplicationView(previewFamily: .accessoryCorner, entry: entry).frame(width: 50, height: 50)
                            MoonComplicationView(previewFamily: .accessoryCorner, entry: moon).frame(width: 50, height: 50)
                            NextDarkComplicationView(previewFamily: .accessoryCorner, entry: dark, now: .now).frame(width: 50, height: 50)
                        }
                        WatchComplicationView(previewFamily: .accessoryRectangular, entry: entry, clockTimes: true).frame(height: 60)
                        MoonComplicationView(previewFamily: .accessoryRectangular, entry: moon).frame(height: 60)
                        NextDarkComplicationView(previewFamily: .accessoryRectangular, entry: dark, now: .now).frame(height: 60)
                        WatchComplicationView(previewFamily: .accessoryInline, entry: entry).frame(height: 20)
                        MoonComplicationView(previewFamily: .accessoryInline, entry: moon).frame(height: 20)
                        NextDarkComplicationView(previewFamily: .accessoryInline, entry: dark, now: .now).frame(height: 20)
                    }
                    .environment(\.widgetRenderingMode, mode)
                }
                WatchComplicationView(previewFamily: .accessoryRectangular, entry: WatchSkyEntry(date: .now, night: nil, next: nil, nightVision: red)).frame(height: 50)
            }
        }
        .navigationTitle("Complications")
    }
}
#endif
