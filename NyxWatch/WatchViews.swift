import SwiftUI
import WatchKit

/// Red at night: at a dark site the wrist is the screen, and red light keeps the eyes adapted.
/// Automatic (the default) wears Nyx's standard colours by day and turns red at civil dusk.
struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    /// When Nyx last became active: between two minute marks, "now" is never earlier than this.
    @State private var woke = Date.now
    /// A park and night opened from a complication or the Smart Stack, above Tonight.
    @State private var path: [WatchLink] = []
    var body: some View {
        // The app's one clock, read once a minute: Automatic turns red at civil dusk with the app
        // open, and every page below reads the same minute (`\.watchNow`).
        TimelineView(.everyMinute) { timeline in
            let now = max(timeline.date, woke).addingTimeInterval(WatchDebug.clockShift)
            content(now: now).environment(\.watchNow, now)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.reloadSettings()
            woke = .now
        }
    }
    private func content(now: Date) -> some View {
        let palette = NyxPalette(nightVision: store.nightVision(at: now), highContrast: contrast == .increased)
        return NavigationStack(path: $path) {
            Group {
                #if DEBUG
                if let screen = WatchDebug.screen, !WatchDebug.homeScreens.contains(screen) { WatchDebug.view(screen) }
                else { home }
                #else
                home
                #endif
            }
            .navigationDestination(for: WatchLink.self) { link in
                if let park = store.park(link.parkID) { ParkNightView(park: park, startNight: link.offset(in: park, now: .now, limit: 6)) }
            }
        }
        .onOpenURL { open($0) }
        .environment(\.nyx, palette)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .modifier(WatchDebug.TypeSize())
        // Scroll bars and Tonight's page dots are system chrome the red filter cannot reach: they
        // would be the one white thing on the screen, so under red light they go.
        .scrollIndicators(palette.nightVision ? .never : .automatic)
        // The complication review draws in the widgets' own colours, so it is not filtered twice.
        // Under Increase Contrast the brighter red, as on the iPhone (`NyxPalette.red`).
        .modifier(NightVisionFilter(enabled: palette.nightVision && WatchDebug.screen != "complications", red: palette.red))
        .modifier(AlwaysOnDim(nightVision: palette.nightVision))
        .background(Color.black)
        .modifier(WatchDebug.AlwaysOn())
        .modifier(WatchDebug.ScrollEnd())
    }
    /// A complication's park and night (`WatchLink`): pushed above Tonight, or Tonight itself when
    /// it is tonight at the park Tonight already shows.
    private func open(_ url: URL) {
        guard let link = WatchLink(url), let park = store.park(link.parkID) else { return }
        let now = Date.now
        if link.offset(in: park, now: now, limit: 6) == 0, store.featured(at: now)?.id == park.id { path = []; return }
        path = [link]
    }
    @ViewBuilder private var home: some View {
        HomeNight()
    }
}

/// Tonight's park on the root's minute, or the chooser when there is none.
private struct HomeNight: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.watchNow) private var now
    var body: some View {
        if let park = store.featured(at: now) { ParkNightView(park: park, isHome: true) }
        else { ParkChooser() }
    }
}
extension EnvironmentValues {
    /// The minute every watch page is drawn for, from `WatchRootView`'s single timeline.
    @Entry var watchNow: Date = .now
}

/// Wrist down, Starlight's cream and amber step down with the screen; red is already the dimmest light.
private struct AlwaysOnDim: ViewModifier {
    @Environment(\.isLuminanceReduced) private var dimmed
    let nightVision: Bool
    func body(content: Content) -> some View { content.opacity(dimmed && !nightVision ? 0.8 : 1) }
}
/// Text that matters only with the wrist raised (hints, notes, footers) fades further in Always-On,
/// so the score, the countdown and the adaptation minutes are what a lowered wrist shows.
private struct NonEssential: ViewModifier {
    @Environment(\.isLuminanceReduced) private var dimmed
    func body(content: Content) -> some View { content.opacity(dimmed ? 0.55 : 1) }
}
extension View {
    func nonEssential() -> some View { modifier(NonEssential()) }
}

/// One park's night in three pages the Digital Crown moves through: the score and what comes
/// next, tonight's milestones, and the week.
struct ParkNightView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.nyx) private var palette
    let park: Park
    var isHome = false
    /// Nights after tonight the dial opens on (a complication's later night), turned with the Crown.
    var startNight = WatchDebug.initialNight
    @State private var page = WatchDebug.initialPage
    @State private var darkMode = WatchDebug.screen == "dark"
    @Environment(\.watchNow) private var now
    var body: some View {
        Group {
            let week = store.week(park, at: now)
            let night = week.first ?? store.tonight(park, at: now)
            TabView(selection: $page) {
                // (The DEBUG Always-On override is repeated per page: pages take the scene's value.)
                TonightFace(night: night, week: week, now: now, context: store.context, startNight: startNight).modifier(WatchDebug.AlwaysOn()).tag(0)
                MilestonesPage(night: night, now: now, context: store.context).modifier(WatchDebug.AlwaysOn()).tag(1)
                WeekPage(park: park, nights: week, now: now, isHome: isHome).modifier(WatchDebug.AlwaysOn()).tag(2)
            }
            .tabViewStyle(.verticalPage)
            // A wrist tap as a moment of the night passes, while its countdown is on screen.
            .modifier(MilestoneTap(park: park, next: NightMilestone.next(after: now, in: night.sky), active: page < 2 && !darkMode))
        }
        .nyxTitle(park.wristName)
        .toolbar {
            if isHome {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ParksList() } label: { Label("Parks", systemImage: "list.bullet") }.tint(palette.toolbarTint)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Double Tap opens it: a hand holding binoculars can still start adapting.
                Button { darkMode = true } label: { Label("Dark adaptation", systemImage: "eye") }.tint(palette.toolbarTint)
                    .handGestureShortcut(.primaryAction, isEnabled: !darkMode)
            }
        }
        .fullScreenCover(isPresented: $darkMode) { DarkAdaptationView(park: park) }
    }
}

/// One wrist tap when a moment of the night passes (sunset, true darkness, moonrise…) while the
/// screen counting down to it is up. Never for a change of park.
struct MilestoneTap: ViewModifier {
    let park: Park
    let next: NightMilestone?
    let active: Bool
    private struct Key: Equatable { let park: String; let next: NightMilestone? }
    func body(content: Content) -> some View {
        content.sensoryFeedback(.start, trigger: Key(park: park.id, next: next)) { old, new in
            active && old.park == new.park && old.next != nil && old.next != new.next
        }
    }
}

/// One glance: the gauge first, then what happens next. At the standard text sizes (the watch's
/// default and below) the face is fixed and the gauge takes what the words leave. At accessibility sizes it scrolls, the gauge
/// keeps its size and the words flow below it. At the large sizes in between, every line stays
/// whole and the face scrolls only where the words would leave the gauge too small to read
/// (`WatchTonightLayout`), as on the 40 mm watch in Spanish. Tap the dial, then turn the
/// Digital Crown to step through the week: the score and the Moon change night by night, with a
/// detent tap for each. VoiceOver adjusts the same nights by swiping up or down on the dial.
struct TonightFace: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let night: Night
    let week: [Night]
    let now: Date
    let context: WatchContext?
    @State private var offset: Int
    /// The dial takes the Crown only after a tap; otherwise the Crown pages, as everywhere on the watch.
    /// Opened on a later night, it holds the Crown already, so the night shown stays until let go.
    @State private var engaged: Bool
    @FocusState private var scrubbing: Bool
    /// The face's height and the tallest the words under the dial can be this week with every
    /// line whole, at the large text sizes; the layout held while the dial has the Crown.
    @State private var room = 0.0
    @State private var wordsHeight = 0.0
    @State private var held: WatchTonightLayout?
    init(night: Night, week: [Night], now: Date, context: WatchContext?, startNight: Int = WatchDebug.initialNight) {
        self.night = night
        self.week = week
        self.now = now
        self.context = context
        _offset = State(initialValue: startNight)
        _engaged = State(initialValue: startNight > 0)
    }
    private var shown: Night { week.indices.contains(offset) ? week[offset] : night }
    /// The park's closure from the iPhone's last park update, worded as on the iPhone.
    private var closure: String? { context?.closures[night.park.id] }
    private var looking: Bool { engaged || offset != 0 }
    /// The forecast models' range for the night on the dial, as the iPhone shows it.
    private var models: ClosedRange<Int>? { context?.modelRange(for: shown) }
    /// Up to this size the face is fixed as designed: the watch's default text size.
    private var standardSizes: DynamicTypeSize { WatchTonightLayout.largestStandard(screenHeight: WKInterfaceDevice.current().screenBounds.height) }
    private var measured: WatchTonightLayout {
        WatchTonightLayout.choose(room: room, words: wordsHeight, standardSize: typeSize <= standardSizes, accessibilitySize: typeSize.isAccessibilitySize)
    }
    var body: some View {
        if typeSize.isAccessibilitySize {
            scrolling
        } else if typeSize <= standardSizes {
            fixed(wraps: false)
        } else {
            Group {
                switch held ?? measured {
                case .fixed: fixed(wraps: true)
                case .scrolling: scrolling
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: Double.self) { $0.size.height } action: { room = $0 }
            .background {
                // The words as the fixed face would set them, measured unseen at the face's width:
                // tonight's, and each night's the Crown can turn to, so the choice never depends on
                // which layout or night is showing, and tapping the dial never changes the layout
                // (which would take the Crown away from it).
                ZStack {
                    VStack(spacing: WatchTonightLayout.spacing) { words(wraps: true, looking: false, shown: night) }
                    ForEach(week.indices, id: \.self) { index in
                        VStack(spacing: WatchTonightLayout.spacing) { words(wraps: true, looking: true, shown: week[index], isTonight: index == 0) }
                    }
                }
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: Double.self) { $0.size.height } action: { wordsHeight = $0 }
                .hidden()
                .accessibilityHidden(true)
            }
            .onChange(of: engaged) { _, on in held = on ? measured : nil }
        }
    }
    private var scrolling: some View {
        ScrollView {
            VStack(spacing: 6) {
                // Smaller at the large sizes, so the words under it start on the first screen.
                let side = typeSize.isAccessibilitySize ? 112 : WatchTonightLayout.scrollingDial
                gauge.frame(width: side, height: side)
                // At accessibility sizes the band word leaves the dial for this line.
                if typeSize.isAccessibilitySize { Text(shown.score.band.label).font(.system(.headline, design: .serif)) }
                if looking { NightGlance(night: shown, isTonight: offset == 0, models: models) } else { NextMoment(night: night, now: now, models: models, wraps: true) }
                if let closure { ClosureLine(text: closure) }
                ForEach(cloudLines(shown, context: context, now: now), id: \.self) {
                    Text($0).font(.caption2).foregroundStyle(palette.faint).multilineTextAlignment(.center).nonEssential()
                }
            }.frame(maxWidth: .infinity)
        }
    }
    /// `wraps`: every line whole, wrapped rather than shrunk or cut (the large sizes).
    private func fixed(wraps: Bool) -> some View {
        VStack(spacing: WatchTonightLayout.spacing) {
            // The gauge takes what the words leave: larger on Ultra, never crowding them on 42 mm.
            gauge.frame(maxWidth: 150, minHeight: 0)
            words(wraps: wraps, looking: looking, shown: shown, isTonight: offset == 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    /// What sits under the dial: the next moment of tonight, or the night the Crown turned to.
    @ViewBuilder private func words(wraps: Bool, looking: Bool, shown: Night, isTonight: Bool = true) -> some View {
        let lines: Int? = wraps ? nil : 1
        if looking {
            NightGlance(night: shown, isTonight: isTonight, models: context?.modelRange(for: shown)).layoutPriority(1)
        } else {
            // "No cloud forecast" or the models' range rides on the clock-time line, so neither costs the gauge anything.
            NextMoment(night: night, now: now, cloudsUnknown: night.basis == .usual, models: context?.modelRange(for: shown), wraps: wraps).layoutPriority(1)
            if NightMilestone.next(after: now, in: night.sky) == nil, let note = WatchSky.forecastNote(night, context: context, short: true) {
                Text(note).font(.caption2).foregroundStyle(palette.faint).lineLimit(lines).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: wraps).layoutPriority(1).nonEssential()
            }
        }
        // A closure stands beside the score on every surface; here it costs the gauge one line
        // (at the large sizes, the lines it needs).
        if let closure { ClosureLine(text: closure, lines: lines).layoutPriority(1) }
    }
    private var gauge: some View {
        WatchGauge(night: shown, nightLabel: offset == 0 ? nil : shown.park.dayLabel(shown.id), models: models)
            .contentShape(Circle())
            .focusable(engaged)
            .focused($scrubbing)
            .focusEffectDisabled()
            .digitalCrownRotation(detent: $offset, from: 0, through: max(0, week.count-1), by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onTapGesture {
                // Focus once the dial has become focusable, on the next turn of the run loop.
                if engaged { engaged = false } else { engaged = true; Task { scrubbing = true } }
            }
            // Back to tonight when the Crown is let go of: a second tap, or another page.
            .onChange(of: scrubbing) { _, focused in
                if !focused { engaged = false }
            }
            .onChange(of: engaged) { _, on in
                if !on { scrubbing = false; withAnimation(reduceMotion ? nil : NyxMotion.spring) { offset = 0 } }
            }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: offset = min(max(0, week.count-1), offset+1)
                case .decrement: offset = max(0, offset-1)
                @unknown default: break
                }
            }
            .onAppear { if engaged { Task { scrubbing = true } } }
    }
}

/// A park's closure, in the accent with a warning mark, as the iPhone shows it beside the score.
struct ClosureLine: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: String
    var lines: Int? = nil
    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
            .font(.caption2).foregroundStyle(palette.accent)
            .lineLimit(typeSize.isAccessibilitySize ? nil : lines).minimumScaleFactor(0.8)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Closure alert: \(text)"))
    }
}

/// A night chosen with the Crown: which night, its true darkness in park time and, where the
/// iPhone shows one, the forecast models' range of scores.
struct NightGlance: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    let night: Night
    let isTonight: Bool
    var models: ClosedRange<Int>? = nil
    var body: some View {
        VStack(spacing: 0) {
            let day = isTonight ? Text("Tonight") : Text(night.park.dayLabel(night.id))
            let eyebrow = Font.caption2.weight(.semibold)
            if let models, typeSize.isAccessibilitySize {
                // In the scrolling accessibility layout a line costs the dial nothing: the range has its own.
                day.font(eyebrow).textCase(.uppercase).tracking(1).foregroundStyle(palette.accent)
                Text("Models \(models.lowerBound)–\(models.upperBound)").font(.caption2).foregroundStyle(palette.muted).accessibilityHidden(true)
            } else if let models {
                // The models' range rides on the day's line where it fits whole ("SAT, OCT 10 · MODELS
                // 73–89", letterspaced, then without the letterspacing, then "models" in lower case);
                // where it does not, the day stands alone and the hairline on the dial's rim carries
                // the range, so a ranged night never costs the dial a line (or its band word). Never
                // shrunk or cut: a cut range would show a wrong number. The dial speaks it, so
                // VoiceOver hears only the day here.
                let range = Text("Models \(models.lowerBound)–\(models.upperBound)")
                ViewThatFits(in: .horizontal) {
                    Text("\(day.foregroundStyle(palette.accent)) · \(range.foregroundStyle(palette.muted))")
                        .font(eyebrow).textCase(.uppercase).tracking(1)
                    Text("\(day.foregroundStyle(palette.accent)) · \(range.foregroundStyle(palette.muted))")
                        .font(eyebrow).textCase(.uppercase)
                    // Narrower still: the range in lower case and regular weight, the iPhone river's "models 73–89".
                    let upper = (isTonight ? String(localized: "Tonight") : night.park.dayLabel(night.id)).uppercased(with: locale)
                    Text("\(Text(verbatim: upper).font(eyebrow).foregroundStyle(palette.accent)) · \(Text("models \(models.lowerBound)–\(models.upperBound)").font(.caption2).foregroundStyle(palette.muted))")
                    day.font(eyebrow).textCase(.uppercase).tracking(1).foregroundStyle(palette.accent)
                }
                .lineLimit(1).accessibilityLabel(day)
            } else {
                day.font(eyebrow).textCase(.uppercase).tracking(1).foregroundStyle(palette.accent)
            }
            if let start = night.sky.darkStart, let end = night.sky.darkEnd, night.sky.darkHours > 0 {
                Text("Dark \(night.park.time(start)) to \(night.park.time(end))").font(.system(.subheadline, design: .serif))
            } else {
                Text(SkyConditions.noDarknessMessage(tonight: isTonight)).font(.footnote)
            }
            if isTonight { Text("Turn the Crown to look ahead").font(.caption2).foregroundStyle(palette.muted).nonEssential() }
            // An early look is named as the iPhone names it, never "no forecast" (`Night.basisLabel`).
            else if let basis = night.basisLabel { Text(basis).font(.caption2).foregroundStyle(palette.muted).nonEssential() }
        }
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// Where the clouds came from and how old they are, after any line saying the score has none.
func cloudLines(_ night: Night, context: WatchContext?, now: Date) -> [String] {
    let source = CloudSource.of(context: context, park: night.park, now: now)
    // A forecast the iPhone could refresh says so plainly, never "no forecast for this night".
    let refreshable = source.isStale || source == .missing(followed: false)
    var lines: [String] = []
    if let note = WatchSky.forecastNote(night, context: context, short: refreshable) { lines.append(note) }
    if let line = source.line(for: night.park) { lines.append(line) }
    return lines
}

/// The next moment of the night and how long until it, rewritten by the screen's minute timeline.
struct NextMoment: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let night: Night
    let now: Date
    var cloudsUnknown = false
    /// Tonight's forecast models' range, when the iPhone shows one (never with `cloudsUnknown`).
    var models: ClosedRange<Int>? = nil
    /// Every line whole, wrapped rather than shrunk or cut off (always at accessibility sizes).
    var wraps = false
    var body: some View {
        let limit = typeSize.isAccessibilitySize || wraps ? nil : 1 as Int?
        Group {
            if let next = NightMilestone.next(after: now, in: night.sky) {
                VStack(spacing: 0) {
                    // At the site the first question is "is it dark yet": answer it before the countdown.
                    if let state = nowLine {
                        Text(state).font(.caption2.weight(.semibold)).textCase(.uppercase).tracking(1).foregroundStyle(palette.accent)
                            .lineLimit(limit).minimumScaleFactor(0.8)
                    }
                    countdownText(next, now: now).font(.system(.subheadline, design: .serif)).foregroundStyle(palette.ink)
                        .lineLimit(limit).minimumScaleFactor(0.7)
                    Group {
                        let at = Text("at \(night.park.time(next.date))")
                        if cloudsUnknown { Text("at \(night.park.time(next.date)) · no cloud forecast").minimumScaleFactor(0.8) }
                        else if let models {
                            // The range shares the line only whole, never shrunk or cut (a cut "models
                            // 59–8…" would show a wrong number): where it does not fit, the time stands
                            // alone and the hairline on the dial's rim carries the range. At accessibility
                            // sizes the line wraps instead. The dial speaks the range; VoiceOver hears
                            // only the time here.
                            let full = Text("at \(night.park.time(next.date)) · models \(models.lowerBound)–\(models.upperBound)")
                            if typeSize.isAccessibilitySize { full.accessibilityLabel(at) }
                            else { ViewThatFits(in: .horizontal) { full; at.minimumScaleFactor(0.8) }.accessibilityLabel(at) }
                        } else { at.minimumScaleFactor(0.8) }
                    }
                    .font(.caption2).foregroundStyle(palette.muted).lineLimit(limit).nonEssential()
                }
            } else if night.sky.darkHours == 0 {
                Text(SkyConditions.noDarknessMessage(tonight: true)).font(.footnote)
            }
        }
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
    private var nowLine: String? {
        switch night.sky.phase(at: now) {
        case .dark: String(localized: "Truly dark now")
        case .twilight: String(localized: "Twilight now")
        case .day: nil
        }
    }
}

struct MilestonesPage: View {
    @Environment(\.nyx) private var palette
    let night: Night
    let now: Date
    let context: WatchContext?
    var body: some View {
        let list = NightMilestone.list(for: night.sky)
        let next = NightMilestone.next(after: now, in: night.sky)
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                WatchEyebrow(text: "Tonight")
                ForEach(list) { milestone in
                    let past = milestone.date <= now
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        // Passed moments are small filled dots, the next one ringed, later ones hollow.
                        ZStack {
                            if milestone == next { Circle().stroke(palette.accent, lineWidth: 1.2).frame(width: 11, height: 11) }
                            Circle().fill(past ? palette.faint : Color.clear).frame(width: 4, height: 4)
                            if !past && milestone != next { Circle().stroke(palette.muted, lineWidth: 1).frame(width: 7, height: 7) }
                        }
                        .frame(width: 12).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center]+4 }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(night.park.time(milestone.date)).font(.system(.body, design: .serif)).monospacedDigit()
                            Text(milestone.title).font(.footnote)
                            if milestone == next {
                                Text(inDuration(until: milestone.date, from: now)).font(.caption2).foregroundStyle(palette.accent)
                            }
                        }
                    }
                    .foregroundStyle(past ? palette.faint : palette.ink)
                    .modifier(PastDim(past: past))
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(past ? String(localized: "Passed") : milestone == next ? String(localized: "Next") : "")
                }
                if list.isEmpty { Text("No sunset, darkness or moonrise tonight.").font(.footnote) }
                Rectangle().fill(palette.line).frame(height: 0.5).padding(.vertical, 2).accessibilityHidden(true)
                Text("\(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded()))% lit").font(.footnote)
                ForEach(cloudLines(night, context: context, now: now), id: \.self) {
                    Text($0).font(.caption2).foregroundStyle(palette.muted).nonEssential()
                }
                // No score stands on this page, so the line says what the range is of: under "Clouds
                // from …" a bare "Forecast models: 59–89" read as cloud cover.
                if let models = context?.modelRange(for: night) {
                    Text("Forecast models put tonight's score between \(models.lowerBound) and \(models.upperBound).").font(.caption2).foregroundStyle(palette.muted).nonEssential()
                }
                if night.sky.darkHours > 0 {
                    Text("\(Duration.seconds(night.sky.darkHours*3600).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) of true darkness").font(.footnote)
                    Text(moonLine).font(.caption2).foregroundStyle(palette.muted).nonEssential()
                } else {
                    Text(SkyConditions.noDarknessMessage(tonight: true)).font(.footnote)
                }
                if night.park.timeZone.secondsFromGMT(for: now) != TimeZone.current.secondsFromGMT(for: now) {
                    Text("Times in \(night.park.timeZoneName)").font(.caption2).foregroundStyle(palette.muted).nonEssential()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var moonLine: String {
        let below = Int((night.sky.moonBelowFraction*100).rounded())
        switch below {
        case 100: return String(localized: "The Moon is down all through true darkness.")
        case 0: return String(localized: "The Moon is up all through true darkness.")
        default: return String(localized: "The Moon is down for \(below)% of true darkness.")
        }
    }
}
/// Passed milestones are not news: they fade in Always-On.
private struct PastDim: ViewModifier {
    let past: Bool
    func body(content: Content) -> some View { if past { content.nonEssential() } else { content } }
}

struct WeekPage: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.isLuminanceReduced) private var dimmed
    let park: Park
    let nights: [Night]
    let now: Date
    let isHome: Bool
    var body: some View {
        let best = NightPlanner.best(nights)
        // Nights that tie the best are all ringed; the best by the iPhone's tie-breaks is named, the rest counted.
        let tied = nights.filter { $0.score.value == best?.score.value }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchEyebrow(text: "Next 7 nights")
                if typeSize.isAccessibilitySize {
                    ForEach(nights) { night in
                        HStack { Text(park.dayLabel(night.id)); Spacer(); Text(night.score.value, format: .number).foregroundStyle(palette.accent) }
                            .font(.footnote).accessibilityElement(children: .ignore).accessibilityLabel(label(night))
                    }
                } else {
                    HStack(spacing: 0) { ForEach(nights) { night in column(night, best: tied.contains { $0.id == night.id }) } }
                }
                if let best {
                    VStack(alignment: .leading, spacing: 0) {
                        if tied.count > 1 { Text("Darkest: \(park.dayLabel(best.id)) and \(tied.count-1) more").font(.footnote) }
                        else { Text("Darkest: \(park.dayLabel(best.id))").font(.footnote) }
                        Text("\(best.score.value) · \(best.score.band.label)").font(.system(.body, design: .serif)).foregroundStyle(palette.accent)
                    }
                    .fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
                }
                Group {
                    if nights.contains(where: { !$0.score.hasForecast }) {
                        Text("Hollow nights have no full cloud forecast yet.")
                    }
                    if let line = CloudSource.of(context: store.context, park: park, now: now).line(for: park) { Text(line) }
                }
                .font(.caption2).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true).nonEssential()
                if !isHome || store.pinned == park.id {
                    let kept = store.pinned == park.id
                    Button { store.pin(kept ? nil : park) } label: {
                        Label(kept ? "Follow iPhone again" : "Show on Tonight", systemImage: kept ? "pin.slash" : "pin")
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func column(_ night: Night, best: Bool) -> some View {
        VStack(spacing: 3) {
            Text(park.weekdayInitial(night.id)).font(.caption2.weight(best ? .bold : .regular)).foregroundStyle(best ? palette.ink : palette.muted)
            ZStack {
                if best { Circle().stroke(palette.accent.opacity(0.8), lineWidth: 1).frame(width: 20, height: 20) }
                let d = 4 + 11*Double(night.score.value)/100
                // Wrist down the fills drop to one quiet level; only the sizes still rank the nights.
                if night.score.hasForecast { Circle().fill(palette.accent.opacity(dimmed ? 0.5 : 0.5+Double(night.score.value)/200)).frame(width: d, height: d) }
                else { Circle().stroke(palette.accent, lineWidth: 1).frame(width: d, height: d) }
            }.frame(height: 22)
            Text(night.score.value, format: .number).font(.caption2.monospacedDigit()).foregroundStyle(palette.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(night) + (best ? ". " + String(localized: "Darkest of the week") : ""))
    }
    private func label(_ night: Night) -> String {
        let base = String(localized: "\(park.dayLabel(night.id)), \(night.score.value), \(night.score.band.label)")
        return night.basisLabel.map { base + ", " + $0 } ?? base
    }
}

struct WatchEyebrow: View {
    @Environment(\.nyx) private var palette
    let text: LocalizedStringKey
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).textCase(.uppercase).tracking(1.2).foregroundStyle(palette.muted).accessibilityAddTraits(.isHeader)
    }
}

/// Every park, saved ones first with tonight's score; the palette choice and the credits live here too.
struct ParksList: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.nyx) private var palette
    @Environment(\.watchNow) private var now
    var body: some View {
        @Bindable var store = store
        Group {
            List {
                if let pinned = store.park(store.pinned) {
                    Section {
                        Button { store.pin(nil) } label: { Label("Follow iPhone again", systemImage: "pin.slash") }
                    } footer: { Text("Tonight shows \(pinned.wristName).") }
                }
                if !store.savedParks.isEmpty {
                    Section("Saved on iPhone") { ForEach(store.savedParks) { row($0, now: now, scored: true) } }
                }
                Section("All parks") { ForEach(store.parks) { row($0, now: now, scored: false) } }
                Section {
                    Picker("Colors", selection: $store.palette) { ForEach(PaletteChoice.allCases) { Text($0.title).tag($0) } }
                } footer: { Text("Automatic turns red from dusk to dawn at the park on Tonight. Red light keeps your eyes adapted to the dark.") }
                Section {
                    NavigationLink { WatchCredits() } label: { Label("Credits", systemImage: "text.book.closed") }
                } footer: { Text("Nyx on Apple Watch makes no network requests. Clouds come from Nyx on your iPhone.") }
            }
        }
        .nyxTitle(String(localized: "Parks"))
    }
    private func row(_ park: Park, now: Date, scored: Bool) -> some View {
        NavigationLink { ParkNightView(park: park) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(park.wristName).font(.system(.body, design: .serif)).lineLimit(2)
                    Text(park.state.replacingOccurrences(of: ",", with: " · ")).font(.caption2).foregroundStyle(palette.muted)
                }
                Spacer(minLength: 2)
                if store.pinned == park.id { Image(systemName: "pin.fill").font(.caption2).accessibilityLabel("On Tonight") }
                if scored {
                    let night = store.tonight(park, at: now)
                    Text(night.score.value, format: .number).font(.system(.title3, design: .serif)).foregroundStyle(palette.accent)
                        .accessibilityLabel("\(night.score.value) out of 100, \(night.score.band.label)")
                }
            }
        }
    }
}

/// Before the iPhone has sent anything: pick a park, and Nyx scores it with its usual clouds.
struct ParkChooser: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.nyx) private var palette
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a park").font(.system(.title3, design: .serif))
                    Text("Nyx on iPhone sends your saved parks and cloud forecasts. Until then, scores use each park's usual clouds.").font(.caption2).foregroundStyle(palette.muted)
                }.listRowBackground(Color.clear)
            }
            Section("Dark Sky parks") { ForEach(store.parks.filter(\.darkSkyDesignated)) { row($0) } }
            Section("Other parks") { ForEach(store.parks.filter { !$0.darkSkyDesignated }) { row($0) } }
        }
        .nyxTitle("Nyx")
    }
    private func row(_ park: Park) -> some View {
        Button { store.pin(park) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(park.wristName).font(.system(.body, design: .serif))
                Text(park.state.replacingOccurrences(of: ",", with: " · ")).font(.caption2).foregroundStyle(palette.muted)
            }
        }
    }
}

extension NyxPalette {
    /// Toolbar buttons fill with the tint on watchOS. A bright fill would be the brightest thing on
    /// the screen at night, so they sit dark: nebula violet, or near-black under red light.
    var toolbarTint: Color { nightVision ? Color(white: 0.2) : Color(red: 0.165, green: 0.106, blue: 0.306) }
}
extension View {
    /// The system title is a dim grey that falls below 4.5:1 once turned red; draw it in ink instead.
    func nyxTitle(_ title: String) -> some View { modifier(NyxTitle(title: title)) }
}
private struct NyxTitle: ViewModifier {
    @Environment(\.nyx) private var palette
    let title: String
    func body(content: Content) -> some View {
        // Long names ("Black Canyon of the Gunnison") shrink before they truncate. One line even at
        // accessibility sizes: a second line would run into the system clock above it.
        content.navigationTitle { Text(title).foregroundStyle(palette.ink).lineLimit(1).minimumScaleFactor(0.6) }
            .toolbarForegroundStyle(palette.ink, for: .navigationBar)
    }
}

#Preview("Tonight • Automatic by day") {
    WatchPreviewHost(nightVision: false) { park, store in TonightFace(night: store.tonight(park, at: .now), week: store.week(park, at: .now), now: .now, context: nil) }
}
#Preview("Tonight • red • AX5") {
    WatchPreviewHost(nightVision: true) { park, store in TonightFace(night: store.tonight(park, at: .now), week: store.week(park, at: .now), now: .now, context: nil) }
        .dynamicTypeSize(.accessibility5)
}
#Preview("Tonight • xxxLarge") {
    // Fixed where the dial keeps its minimum under whole lines, scrolling where it cannot (`WatchTonightLayout`).
    WatchPreviewHost(nightVision: false) { park, store in TonightFace(night: store.tonight(park, at: .now), week: store.week(park, at: .now), now: .now, context: nil) }
        .dynamicTypeSize(.xxxLarge)
}
#Preview("Night glance • Friday") {
    WatchPreviewHost(nightVision: true) { park, store in NightGlance(night: store.week(park, at: .now)[3], isTonight: false) }
}
#Preview("Night glance • models' range") {
    // A range around the night's own score, as `WatchContext.modelRange` would hand it over.
    WatchPreviewHost(nightVision: false) { park, store in
        let night = store.week(park, at: .now)[1]
        NightGlance(night: night, isTonight: false, models: max(0, night.score.value-12)...min(100, night.score.value+4))
    }
}
#if DEBUG
#Preview("Tonight • models' range") {
    ModelsPreview(nightVision: false) { week, context in TonightFace(night: week[0], week: week, now: .now, context: context) }
}
#Preview("Crown night • models' range • red") {
    ModelsPreview(nightVision: true) { week, context in TonightFace(night: week[0], week: week, now: .now, context: context, startNight: 1) }
}
#Preview("Crown night • models' range • xxxLarge") {
    ModelsPreview(nightVision: false) { week, context in TonightFace(night: week[0], week: week, now: .now, context: context, startNight: 6) }
        .dynamicTypeSize(.xxxLarge)
}
#Preview("Next moment • models' range") {
    ModelsPreview(nightVision: false) { week, context in NextMoment(night: week[0], now: .now, models: context.modelRange(for: week[0])) }
}
#Preview("Next moment • models' range • xxxLarge") {
    ModelsPreview(nightVision: false) { week, context in NextMoment(night: week[0], now: .now, models: context.modelRange(for: week[0])) }
        .dynamicTypeSize(.xxxLarge)
}
#Preview("Milestones • models' range") {
    ModelsPreview(nightVision: false) { week, context in MilestonesPage(night: week[0], now: .now, context: context) }
}
/// Previews of the models' range: Joshua Tree's week from the "disagree" forecast fixture, handed
/// over as a paired iPhone would (`WatchDebug.modelsContext`).
private struct ModelsPreview<Content: View>: View {
    let nightVision: Bool
    @ViewBuilder let content: ([Night], WatchContext) -> Content
    var body: some View {
        WatchPreviewHost(nightVision: nightVision) { park, store in
            if let context = WatchDebug.modelsContext(savedParkIDs: [park.id], store: store) {
                let week = (0..<7).map {
                    WatchSky.night(park, evening: park.date(park.currentNight(at: .now), addingDays: $0), forecast: context.cloudForecasts[park.id],
                                   detail: context.forecastDetails[park.id], now: .now)
                }
                content(week, context)
            }
        }
    }
}
#endif
#Preview("Milestones • Always-On") {
    WatchPreviewHost(nightVision: false) { park, store in MilestonesPage(night: store.tonight(park, at: .now), now: .now, context: nil) }
        .environment(\.isLuminanceReduced, true)
}
#Preview("Parks") {
    WatchPreviewHost(nightVision: false) { _, _ in NavigationStack { ParksList() } }
}

/// Previews: Joshua Tree from the real engine, in either palette.
struct WatchPreviewHost<Content: View>: View {
    @State private var store = WatchStore()
    let nightVision: Bool
    @ViewBuilder let content: (Park, WatchStore) -> Content
    var body: some View {
        if let park = store.park("jotr") {
            let palette = NyxPalette(nightVision: nightVision, highContrast: false)
            content(park, store).environment(store).environment(\.nyx, palette)
                .foregroundStyle(palette.ink).tint(palette.accent).modifier(NightVisionFilter(enabled: nightVision)).background(Color.black)
        }
    }
}
