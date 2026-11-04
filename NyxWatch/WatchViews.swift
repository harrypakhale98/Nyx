import SwiftUI
import WatchKit

/// Red at night: at a dark site the wrist is the screen, and red light keeps the eyes adapted.
/// At dusk (the default) wears Nyx's standard colours by day and turns red at civil dusk.
struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.legibilityWeight) private var legibility
    @Environment(\.scenePhase) private var scenePhase
    /// When Nyx last became active: between two minute marks, "now" is never earlier than this.
    @State private var woke = Date.now
    /// Every page above Tonight, as values (`WatchRoute`), so a complication's tap can return to
    /// Tonight or replace what is open.
    @State private var path: [WatchRoute] = []
    var body: some View {
        // The app's one clock, read once a minute: At dusk turns red at civil dusk with the app
        // open, and every page below reads the same minute (`\.watchNow`).
        TimelineView(.everyMinute) { timeline in
            let now = max(timeline.date, woke).addingTimeInterval(WatchDebug.clockShift)
            content(now: now).environment(\.watchNow, now)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.reloadSettings()
            store.tellIPhoneIfNeeded()
            woke = .now
        }
    }
    private func content(now: Date) -> some View {
        // The iPhone's brighter red and Bold Text reach the wrist as they do every iPhone screen.
        let palette = NyxPalette(nightVision: store.nightVision(at: now), highContrast: contrast == .increased,
                                 brighterRed: store.context?.brighterRed ?? false, boldText: legibility == .bold)
        return NavigationStack(path: $path) {
            Group {
                #if DEBUG
                if let screen = WatchDebug.screen, !WatchDebug.homeScreens.contains(screen) { WatchDebug.view(screen) }
                else { home }
                #else
                home
                #endif
            }
            .watchRoutes()
        }
        .onOpenURL { open($0) }
        .environment(\.nyx, palette)
        // Starlight for titles, links and pickers: amber is the score's and light's alone.
        .foregroundStyle(palette.ink)
        .tint(palette.ink)
        .modifier(WatchDebug.TypeSize())
        // Scroll bars and Tonight's page dots are system chrome the red filter cannot reach: they
        // would be the one white thing on the screen, so under red light they go, and while the red
        // cover is up: a presentation's bar follows this setting, whatever the palette beneath it.
        .scrollIndicators(palette.nightVision || store.adaptationCover != nil ? .never : .automatic)
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
        path = [.night(link)]
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
/// The pages the watch's navigation stack opens: Parks, Credits, and a park's night (a row, a
/// complication's or the Smart Stack's tap).
enum WatchRoute: Hashable {
    case parks, credits
    case night(WatchLink)
}
private struct WatchRoutes: ViewModifier {
    @Environment(WatchStore.self) private var store
    func body(content: Content) -> some View {
        content.navigationDestination(for: WatchRoute.self) { route in
            switch route {
            case .parks: ParksList()
            case .credits: WatchCredits()
            case .night(let link):
                if let park = store.park(link.parkID) { ParkNightView(park: park, startNight: link.offset(in: park, now: .now, limit: 6)) }
                else { GoneNight() }
            }
        }
    }
}
/// A place's page whose place the iPhone stopped sending while it was open (a saved spot removed,
/// or a place that was only Tonight's answer):
/// one calm line, and back to where it came from rather than a blank page.
private struct GoneNight: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nyx) private var palette
    var body: some View {
        Text("Nyx on iPhone no longer sends this place.").font(.footnote).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).padding()
            // Long enough to read the line, then back.
            .task {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { dismiss() }
            }
    }
}
extension View {
    /// Where `WatchRoute` values lead, once at the root of the stack.
    func watchRoutes() -> some View { modifier(WatchRoutes()) }
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

/// One park's night in four pages the Digital Crown moves through: the score and what comes
/// next, tonight's milestones, what's up tonight, and the week.
struct ParkNightView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.nyx) private var palette
    let park: Park
    var isHome = false
    /// Nights after tonight the dial opens on (a complication's later night), turned with the Crown.
    var startNight = WatchDebug.initialNight
    @State private var page = WatchDebug.initialPage
    @Environment(\.watchNow) private var now
    /// The red dark-adaptation screen is up (opened at the root, `AdaptationRequests`).
    private var darkMode: Bool { store.adaptationCover != nil }
    var body: some View {
        Group {
            let week = store.week(park, at: now)
            let night = week.first ?? store.tonight(park, at: now)
            TabView(selection: $page) {
                // (The DEBUG Always-On override is repeated per page: pages take the scene's value.)
                TonightFace(night: night, week: week, now: now, context: store.context, moons: store.moons, startNight: startNight).modifier(WatchDebug.AlwaysOn()).tag(0)
                MilestonesPage(night: night, now: now, context: store.context).modifier(WatchDebug.AlwaysOn()).tag(1)
                // Tonight's pages together: the moments of the night, then what is up in it.
                WhatsUpPage(night: night).modifier(WatchDebug.AlwaysOn()).tag(2)
                WeekPage(park: park, nights: week, now: now, isHome: isHome).modifier(WatchDebug.AlwaysOn()).tag(3)
            }
            .tabViewStyle(.verticalPage)
            // A wrist tap as a moment of the night passes, while its countdown is on screen.
            .modifier(MilestoneTap(park: park, next: NightMilestone.next(after: now, in: night.sky), active: page < 2 && !darkMode))
        }
        .nyxTitle(park.shortName, shorter: park.wristName)
        .toolbar {
            if isHome {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: WatchRoute.parks) { Label("Parks", systemImage: "list.bullet") }.tint(palette.toolbarTint)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Double Tap opens it: a hand holding binoculars can still start adapting.
                // Opened by the root's one presenter, so a request from Siri or the control finds it up.
                Button { store.openAdaptation(park: park) } label: { Label("Dark adaptation", systemImage: "eye") }.tint(palette.toolbarTint)
                    .handGestureShortcut(.primaryAction, isEnabled: !darkMode)
            }
        }
    }
}

/// One wrist tap when a moment of the night passes (sunset, true darkness, moonrise…) while the
/// screen counting down to it is up. Never for a change of park.
struct MilestoneTap: ViewModifier {
    let park: Park?
    let next: NightMilestone?
    let active: Bool
    private struct Key: Equatable { let park: String; let next: NightMilestone? }
    func body(content: Content) -> some View {
        content.sensoryFeedback(.start, trigger: Key(park: park?.id ?? "", next: next)) { old, new in
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
    /// The iPhone's Moon pictures, so the dial's Moon is the one the iPhone shows for each night.
    let moons: WatchMoons?
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
    init(night: Night, week: [Night], now: Date, context: WatchContext?, moons: WatchMoons? = nil, startNight: Int = WatchDebug.initialNight) {
        self.night = night
        self.week = week
        self.now = now
        self.context = context
        self.moons = moons
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
    /// Why no closure under the score may be known (`WatchContext.alertsNote`): park alerts off,
    /// busy, refused or not yet checked.
    private var alertsNote: String? { context?.alertsNote(night.park) }
    /// The clock-time line under tonight's countdown says only the time, so a note can take its place
    /// (`NextMoment`): no forecast words or models' range already hold it.
    private var timeLineFree: Bool {
        NightMilestone.next(after: now, in: night.sky) != nil && night.basis != .usual && context?.modelRange(for: night) == nil
    }
    /// Fixed as designed, one line each, without measuring: at the standard sizes, unless a closure
    /// is shown, whose words are never cut, or a note says closures may not be known where it would
    /// cost the dial a line (`WatchTonightLayout.designed`).
    private var designed: Bool {
        WatchTonightLayout.designed(standardSize: typeSize <= standardSizes, closure: closure != nil, note: alertsNote != nil, timeLineFree: timeLineFree)
    }
    private var measured: WatchTonightLayout {
        WatchTonightLayout.choose(room: room, words: wordsHeight, standardSize: designed, accessibilitySize: typeSize.isAccessibilitySize)
    }
    var body: some View {
        if typeSize.isAccessibilitySize {
            scrolling
        } else if designed {
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
                // Smaller at the large sizes, so the words under it start on the first screen; never wider
                // than 60% of the screen, so a 40 mm watch keeps its countdown in view as an Ultra does.
                let side = typeSize.isAccessibilitySize ? min(112, WKInterfaceDevice.current().screenBounds.width*0.6) : WatchTonightLayout.scrollingDial
                gauge.frame(width: side, height: side)
                // At accessibility sizes the band word leaves the dial for this line.
                // VoiceOver hears it once, in the dial's value.
                if typeSize.isAccessibilitySize { Text(shown.score.band.label).bandWord(.headline, ink: palette.ink).accessibilityHidden(true) }
                // Directly under the score, as on iPhone and Vision Pro: the one line never to be missed,
                // and then, if the Park Service refuses requests, that it is an earlier update's.
                if let closure {
                    WristClosureLine(text: closure)
                    if let note = context?.alertsNote(night.park) { AlertsNote(text: note) }
                } else if let note = alertsNote {
                    // Where a closure would stand, that closures may not be known: the short line, the
                    // whole sentence for VoiceOver (and on screen at the end).
                    AlertsNote(text: String(localized: "Check park alerts before you go."), spoken: note)
                }
                if looking { NightGlance(night: shown, isTonight: offset == 0, models: models) } else { NextMoment(night: night, now: now, models: models, wraps: true) }
                if let smoke = shown.smokeCaveat { SmokeLine(text: smoke, spoken: smoke) }
                // A later night's glance already names what its clouds rest on.
                ForEach(cloudLines(shown, context: context, now: now, labelShown: looking && offset != 0), id: \.self) {
                    Text($0).font(.caption2).foregroundStyle(palette.faint).multilineTextAlignment(.center).nonEssential()
                }
                // Why no closure under the score may be known, in the iPhone's words (with a closure, under
                // it); VoiceOver heard it with the short line under the score.
                if closure == nil, let note = alertsNote { AlertsNote(text: note).accessibilityHidden(true) }
                AskIPhoneRow(source: WatchSky.cloudSource(night.park, context: context, now: now))
            }.frame(maxWidth: .infinity)
        }
        // Still while the dial holds the Crown, so the scroll view never takes the Crown from it.
        .scrollDisabled(engaged)
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
        // A closure stands directly under the score on every surface, whole, so the road or trail it
        // names is never cut off: it wraps, and the face scrolls where it would leave the gauge too small.
        if let closure {
            WristClosureLine(text: closure).layoutPriority(1)
            // A closure kept from an earlier update while the Park Service refuses requests says so under it.
            if let note = context?.alertsNote(night.park) { AlertsNote(text: note).layoutPriority(1) }
        }
        if looking {
            NightGlance(night: shown, isTonight: isTonight, models: context?.modelRange(for: shown), wraps: wraps).layoutPriority(1)
        } else {
            // "No cloud forecast" or the models' range rides on the clock-time line where it fits whole,
            // else takes the time's place, so neither costs the gauge a line (the track has no rim mark for either).
            NextMoment(night: night, now: now, cloudsUnknown: night.basis == .usual, models: context?.modelRange(for: shown),
                       alertsNote: wraps || closure != nil ? nil : alertsNote, wraps: wraps).layoutPriority(1)
            if NightMilestone.next(after: now, in: night.sky) == nil, let note = WatchSky.forecastNote(night, context: context, short: true) {
                Text(note).font(.caption2).foregroundStyle(palette.faint).lineLimit(lines).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: wraps).layoutPriority(1).nonEssential()
            }
        }
        // Haze or smoke beside the score, as on the iPhone and Vision Pro (`Night.smokeCaveat`): the short
        // words where a line is all there is, the whole sentence for VoiceOver and at the large sizes.
        if let smoke = shown.smokeCaveat, let label = shown.smokeCaveatLabel {
            SmokeLine(text: wraps ? smoke : label, spoken: smoke, lines: wraps ? nil : 1).layoutPriority(1)
        }
        // No closure under the score is not "nothing closed" while closures may not be known: one short
        // line, measured with the rest, with the iPhone's whole sentence for VoiceOver (the scrolling face shows it).
        // The designed face has no line to spare: there the note takes the clock time's place under tonight's
        // countdown (`NextMoment`), and a night turned to with the Crown, which has no such line, leaves it to
        // tonight and the week.
        if wraps, closure == nil, let note = alertsNote {
            AlertsNote(text: String(localized: "Check park alerts before you go."), spoken: note).layoutPriority(1)
        }
    }
    private var gauge: some View {
        // The best window by the iPhone's own rule, from the hourly clouds it handed over.
        let window = ClearWindow.find(shown, forecast: context?.cloudForecasts[shown.park.id], layers: context?.forecastDetails[shown.park.id]?.layers)?.brightest
        return WatchGauge(night: shown, nightLabel: offset == 0 ? nil : shown.park.dayLabel(shown.id), models: models, moon: moons?.image(park: shown.park.id, night: shown.id),
                          window: window, now: now)
            .contentShape(Circle())
            .focusable(engaged)
            .focused($scrubbing)
            .focusEffectDisabled()
            .digitalCrownRotation(detent: $offset, from: 0, through: max(0, week.count-1), by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onTapGesture { engaged.toggle() }
            // Back to tonight when the Crown is let go of: a second tap, or another page.
            .onChange(of: scrubbing) { _, focused in
                if !focused { engaged = false }
            }
            .onChange(of: engaged) { _, on in
                if !on { scrubbing = false; withAnimation(reduceMotion ? nil : NyxMotion.spring) { offset = 0 } }
            }
            // Focus once the dial has become focusable, after the update that makes it so; a request
            // the focus system drops is made again, for up to a second. Opened on a later night,
            // the dial holds the Crown from the start.
            .task(id: engaged) {
                guard engaged else { return }
                for _ in 0..<20 where !scrubbing {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    scrubbing = true
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                }
            }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: offset = min(max(0, week.count-1), offset+1)
                case .decrement: offset = max(0, offset-1)
                @unknown default: break
                }
            }
    }
}

/// A park's closure, the warning mark in `caution` and the words in ink, as the iPhone shows it
/// beside the score: whole, wrapped, never shrunk or cut.
struct WristClosureLine: View {
    @Environment(\.nyx) private var palette
    let text: String
    /// Centred under the dial; leading on a page set flush left (the week).
    var alignment: TextAlignment = .center
    var body: some View {
        Label { Text(text).foregroundStyle(palette.ink) } icon: { Image(systemName: ClosureLine.symbol).foregroundStyle(palette.caution) }
            .font(.caption2)
            .multilineTextAlignment(alignment).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ClosureLine.spoken(text))
    }
}

/// Why a national park's closures are not known on the wrist (`WatchContext.alertsNote`): without it
/// an empty closure line would read as "nothing closed", and a closure kept from an earlier update as current.
struct AlertsNote: View {
    @Environment(\.nyx) private var palette
    let text: String
    var alignment: TextAlignment = .center
    /// What VoiceOver reads, when the line shown is the short form of it.
    var spoken: String? = nil
    var body: some View {
        Text(text).font(.caption2).foregroundStyle(palette.muted)
            .multilineTextAlignment(alignment).fixedSize(horizontal: false, vertical: true).nonEssential()
            .accessibilityLabel(spoken ?? text)
    }
}

/// Haze or smoke thick enough to wash out the Milky Way, in ink with the iPhone's smoke mark.
struct SmokeLine: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: String
    let spoken: String
    var lines: Int? = nil
    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "smoke") }
            .font(.caption2).foregroundStyle(palette.ink)
            .lineLimit(typeSize.isAccessibilitySize ? nil : lines).minimumScaleFactor(0.8)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
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
    /// False on the fixed face, which is one line each: the lines shrink a little rather than wrap
    /// and take the dial's room (a 40 mm watch's "Dark 8:31 PM to 6:42 AM CDT" left it 35 pt).
    var wraps = true
    /// The serif subheadline's size, for the smaller steps of the dark window (sizes ViewThatFits can measure, which a shrink is not).
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 15
    /// The caption's size, for the Crown hint's smaller steps.
    @ScaledMetric(relativeTo: .caption2) private var caption: CGFloat = 14
    var body: some View {
        VStack(spacing: 0) {
            let day = isTonight ? Text("Tonight") : Text(night.park.dayLabel(night.id))
            let eyebrow = Font.caption2.weight(.semibold)
            if let models, typeSize.isAccessibilitySize {
                // In the scrolling accessibility layout a line costs the dial nothing: the range has its own.
                // Set solid there, as every eyebrow is at accessibility sizes.
                day.font(eyebrow).foregroundStyle(palette.ink)
                Text("Models \(models.lowerBound)–\(models.upperBound)").font(.caption2).foregroundStyle(palette.muted).accessibilityHidden(true)
            } else if let models {
                // The models' range rides on the day's line where it fits whole ("SAT, OCT 10 · MODELS
                // 73–89", letterspaced, then without the letterspacing, then "models" in lower case);
                // where it does not, it takes a line of its own under the day: the night's track has no
                // rim mark for it. Never shrunk or cut: a cut range would show a wrong number. The
                // dial speaks it, so VoiceOver hears only the day here.
                let range = Text("Models \(models.lowerBound)–\(models.upperBound)")
                ViewThatFits(in: .horizontal) {
                    Text("\(day.foregroundStyle(palette.ink)) · \(range.foregroundStyle(palette.muted))")
                        .font(eyebrow).textCase(Lettering.spaced ? .uppercase : nil).tracking(Lettering.spaced ? 1 : 0).accessibilityLabel(day)
                    Text("\(day.foregroundStyle(palette.ink)) · \(range.foregroundStyle(palette.muted))")
                        .font(eyebrow).textCase(Lettering.spaced ? .uppercase : nil).accessibilityLabel(day)
                    // Narrower still: the range in lower case and regular weight, the iPhone river's "models 73–89".
                    let upper = (isTonight ? String(localized: "Tonight") : night.park.dayLabel(night.id)).uppercased(with: locale)
                    Text("\(Text(verbatim: upper).font(eyebrow).foregroundStyle(palette.ink)) · \(Text("models \(models.lowerBound)–\(models.upperBound)").font(.caption2).foregroundStyle(palette.muted))")
                        .accessibilityLabel(day)
                    VStack(spacing: 0) {
                        day.font(eyebrow).textCase(Lettering.spaced ? .uppercase : nil).tracking(Lettering.spaced ? 1 : 0).foregroundStyle(palette.ink)
                        range.font(.caption2).foregroundStyle(palette.muted).accessibilityHidden(true)
                    }
                }
                .lineLimit(1)
            } else {
                let spaced = Lettering.spaced && !typeSize.isAccessibilitySize
                day.font(eyebrow).textCase(spaced ? .uppercase : nil).tracking(spaced ? 1 : 0).foregroundStyle(palette.ink)
            }
            if let start = night.sky.darkStart, let end = night.sky.darkEnd, night.sky.darkHours > 0 {
                // Park time: the zone rides on the last time where the park's clock is not the watch's.
                let full = Text("Dark \(night.park.time(start)) to \(night.park.zonedTime(end))")
                if wraps { full.font(.system(.subheadline, design: .serif)) }
                else {
                    // One line on the fixed face: the sentence where it fits, else "Dark 18:12–4:41", set a
                    // little smaller where that keeps one line, and wrapped at the smallest step only where even
                    // that does not fit (at full size, a long zoned es-MX range left a 40 mm dial about 65 pt).
                    // Never shrunk until cut: a cut time is a wrong time.
                    let range = Text(verbatim: "\(String(localized: "Dark")) \(night.park.time(start))–\(night.park.zonedTime(end))")
                    ViewThatFits(in: .horizontal) {
                        full.lineLimit(1)
                        range.lineLimit(1).accessibilityLabel(full)
                        range.font(.system(size: size*0.85, design: .serif)).lineLimit(1).accessibilityLabel(full)
                        range.font(.system(size: size*0.75, design: .serif)).lineLimit(1).accessibilityLabel(full)
                        range.font(.system(size: size*0.75, design: .serif)).lineLimit(2).accessibilityLabel(full)
                    }
                    .font(.system(.subheadline, design: .serif))
                }
            } else if wraps {
                Text(SkyConditions.noDarknessMessage(tonight: isTonight)).font(.footnote)
            } else {
                // One line on the fixed face: the sentence where it fits, else its first words, never cut.
                let message = SkyConditions.noDarknessMessage(tonight: isTonight)
                ViewThatFits(in: .horizontal) {
                    Text(message)
                    Text("No true darkness").minimumScaleFactor(0.8).accessibilityLabel(message)
                }
                .font(.footnote).lineLimit(1)
            }
            if isTonight {
                let hint = Text("Turn the Crown to look ahead")
                Group {
                    if wraps { hint }
                    else {
                        // One line on the fixed face, set a little smaller where that keeps it whole, and
                        // only then wrapped, never cut ("Dreh die Digital Crown, um vorauszus…" on 40 mm).
                        ViewThatFits(in: .horizontal) {
                            hint.lineLimit(1)
                            hint.font(.system(size: caption*0.85)).lineLimit(1)
                            hint.font(.system(size: caption*0.75)).lineLimit(1)
                            hint.font(.system(size: caption*0.85))
                        }
                    }
                }
                .font(.caption2).foregroundStyle(palette.muted).nonEssential()
            }
            // An early look is named as the iPhone names it, never "no forecast", and a night that counts
            // no clouds says so (`Night.standaloneBasisLabel`).
            // On the fixed face, one line where it fits: else "Usual clouds" for a night scored on them, and
            // only then wrapped, never cut ("Pronóstico de nubes no disp…").
            else if let basis = night.standaloneBasisLabel {
                Group {
                    if wraps { Text(basis) }
                    else {
                        let usual = night.basis == .usual && night.score.cloudPoints != nil
                        ViewThatFits(in: .horizontal) {
                            Text(basis).lineLimit(1)
                            Text(usual ? String(localized: "Usual clouds") : basis).lineLimit(1).accessibilityLabel(basis)
                            Text(basis).lineLimit(2)
                        }
                    }
                }
                .font(.caption2).foregroundStyle(palette.muted).nonEssential()
            }
        }
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// Where the clouds came from and how old they are, after any line saying the score has none.
/// `labelShown`: the night's basis label is already on screen (`NightGlance`), so its short note,
/// the same words, is not said again, and the long note does not open with them.
func cloudLines(_ night: Night, context: WatchContext?, now: Date, labelShown: Bool = false) -> [String] {
    let source = WatchSky.cloudSource(night.park, context: context, now: now)
    // A forecast the iPhone could refresh says so plainly, never "no forecast for this night".
    var lines: [String] = []
    if !(labelShown && source.explainsItself), let note = WatchSky.forecastNote(night, context: context, short: source.explainsItself, labelShown: labelShown) { lines.append(note) }
    if let line = source.line(for: night.park) { lines.append(line) }
    if let line = context?.dataNote { lines.append(line) }
    return lines
}

/// "Dawn twilight in 5 hr, 4 min", whole: the full name where it fits on one line, then the
/// complications' short name ("Dawn in 5 hr, 4 min"), then narrow units ("Dawn in 5h 4m"), set
/// down to 70% where that keeps one line (as the shrink it replaces meant to: a shrinking line was
/// cut instead), and only then wrapped, onto a third line where two do not hold it (German or French
/// at the largest standard size): the duration is never cut ("en 5 h y 4…" read as five hours four). `wraps`: the whole line, wrapped (the large sizes). VoiceOver hears
/// the full words whichever shows. The callers set it in the serif subheadline.
struct Countdown: View {
    let next: NightMilestone
    let now: Date
    var wraps = false
    /// The serif subheadline's size, for the smaller steps (sizes ViewThatFits can measure, which a shrink is not).
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 15
    var body: some View {
        let full = countdownText(next, now: now)
        if wraps { full }
        else {
            let narrow = countdownText(next, now: now, short: true, width: .narrow)
            ViewThatFits(in: .horizontal) {
                full.lineLimit(1)
                countdownText(next, now: now, short: true).lineLimit(1).accessibilityLabel(full)
                narrow.lineLimit(1).accessibilityLabel(full)
                narrow.font(.system(size: size*0.85, design: .serif)).lineLimit(1).accessibilityLabel(full)
                narrow.font(.system(size: size*0.7, design: .serif)).lineLimit(1).accessibilityLabel(full)
                narrow.lineLimit(3).accessibilityLabel(full)
            }
        }
    }
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
    /// Why closures may not be known (`WatchContext.alertsNote`), for the designed face: it takes the
    /// clock time's place.
    var alertsNote: String? = nil
    /// Every line whole, wrapped rather than shrunk or cut off (always at accessibility sizes).
    var wraps = false
    var body: some View {
        let limit = typeSize.isAccessibilitySize || wraps ? nil : 1 as Int?
        Group {
            if let next = NightMilestone.next(after: now, in: night.sky) {
                VStack(spacing: 0) {
                    // At the site the first question is "is it dark yet": answer it before the countdown.
                    // Where the Sun never sinks far enough (Denali in June), the answer is that it will
                    // not be, said whether or not a moment is still to come: the sentence where it has
                    // the room, else its first words on the one line the state would take.
                    if night.sky.darkHours == 0 {
                        let message = SkyConditions.noDarknessMessage(tonight: true)
                        if limit == nil { Text(message).font(.caption2).foregroundStyle(palette.ink) }
                        else {
                            ViewThatFits(in: .horizontal) {
                                Text(message).font(.caption2)
                                eyebrow(String(localized: "No true darkness")).accessibilityLabel(message)
                                // Without the letterspacing, for the longer languages ("KEINE ECHTE DUNKELH…" on 40 mm).
                                eyebrow(String(localized: "No true darkness"), spaced: false).accessibilityLabel(message)
                            }
                            .foregroundStyle(palette.ink).lineLimit(1)
                        }
                    } else if let state = nowLine {
                        eyebrow(state).lineLimit(limit)
                    }
                    Countdown(next: next, now: now, wraps: limit == nil).font(.system(.subheadline, design: .serif)).foregroundStyle(palette.ink)
                    Group {
                        // Park time, with its zone where the park's clock is not the watch's ("at 4:52 AM MST").
                        let time = night.park.zonedTime(next.date)
                        let at = Text("at \(time)")
                        if cloudsUnknown, let basis = night.basisLabel {
                            // Whole or not at all, as the models' range below (it was cut to "no cloud
                            // forec…" on 40 mm). Where the two do not share the line, the words take the
                            // time's place: the night's track has no rim mark for them, a line of their own
                            // left a 40 mm dial too small to read, and the countdown above already says
                            // when (the Milestones page gives the clock time). VoiceOver hears it all.
                            // The iPhone's two words for it (`Night.basisLabel`): not yet beyond the forecast's
                            // reach, unavailable within it; "Usual clouds" where neither fits. A night that counts
                            // no clouds says so alone (`Night.standaloneBasisLabel`), wrapped rather than cut.
                            let full = night.beyondForecast ? Text("at \(time) · no cloud forecast yet") : Text("at \(time) · cloud forecast unavailable")
                            if typeSize.isAccessibilitySize || wraps { full }
                            else {
                                let alone = night.standaloneBasisLabel ?? basis
                                ViewThatFits(in: .horizontal) {
                                    full
                                    Text(alone).accessibilityLabel(full)
                                    if night.score.cloudPoints != nil { Text("Usual clouds").minimumScaleFactor(0.8).accessibilityLabel(full) }
                                    else { Text(alone).lineLimit(2).accessibilityLabel(full) }
                                }
                            }
                        }
                        else if let models {
                            // The range shares the line only whole, never shrunk or cut (a cut "models
                            // 59–8…" would show a wrong number): where it does not fit, it takes the time's
                            // place, as the words above do. Where the face wraps (the large sizes) the line
                            // wraps instead. VoiceOver hears the whole line, whichever shows.
                            let full = Text("at \(time) · models \(models.lowerBound)–\(models.upperBound)")
                            if typeSize.isAccessibilitySize || wraps { full }
                            else {
                                ViewThatFits(in: .horizontal) {
                                    full
                                    Text("Models \(models.lowerBound)–\(models.upperBound)").accessibilityLabel(full)
                                }
                            }
                        } else if let alertsNote, !(typeSize.isAccessibilitySize || wraps) {
                            // Closures may not be known: said in the clock time's place, as the forecast's words
                            // are, so the note costs the dial no line (the Milestones page gives the time).
                            // The shorter words where the line would not hold it; VoiceOver hears the time and the whole note.
                            ViewThatFits(in: .horizontal) {
                                Text("Check park alerts before you go.")
                                Text("Closures not checked.").minimumScaleFactor(0.8)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Phrase.sentences([String(localized: "at \(time)"), alertsNote]))
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
    /// The state over the countdown, set as an eyebrow (solid at accessibility sizes, or where `spaced` is false).
    private func eyebrow(_ text: String, spaced: Bool = true) -> some View {
        let spaced = spaced && Lettering.spaced && !typeSize.isAccessibilitySize
        return Text(text).font(.caption2.weight(.semibold)).textCase(spaced ? .uppercase : nil).tracking(spaced ? 1 : 0).foregroundStyle(palette.ink)
            .minimumScaleFactor(0.8)
    }
    /// "Truly dark now" only with the Moon out of the way, as the next-dark complication says it
    /// (`DarkMoment`); under the Moon, the iPhone's words for true darkness with the Moon up.
    private var nowLine: String? {
        switch night.sky.phase(at: now) {
        case .dark: AstronomyEngine().moonHidden(at: now, park: night.park, phase: night.sky.moon) ? String(localized: "Truly dark now") : String(localized: "Dark, Moon up")
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
                            if milestone == next { Circle().stroke(palette.ink, lineWidth: 1.2*palette.stroke).frame(width: 11, height: 11) }
                            Circle().fill(past ? palette.faint : Color.clear).frame(width: 4, height: 4)
                            if !past && milestone != next { Circle().stroke(palette.muted, lineWidth: palette.stroke).frame(width: 7, height: 7) }
                        }
                        .frame(width: 12).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center]+4 }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(night.park.time(milestone.date)).font(.system(.body, design: .serif)).monospacedDigit()
                            Text(milestone.title).font(.footnote)
                            if milestone == next {
                                Text(inDuration(until: milestone.date, from: now)).font(.caption2).foregroundStyle(palette.ink)
                            }
                        }
                    }
                    .foregroundStyle(past ? palette.faint : palette.ink)
                    .modifier(PastDim(past: past))
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(past ? String(localized: "Passed") : milestone == next ? String(localized: "Next") : "")
                }
                if list.isEmpty { Text("No sunset, darkness or moonrise tonight.").font(.footnote) }
                Rectangle().fill(palette.line).frame(height: 0.5*palette.stroke).padding(.vertical, 2).accessibilityHidden(true)
                Text("\(night.sky.moon.name), \(Percent.text(night.sky.moon.percentLit)) lit").font(.footnote)
                ForEach(cloudLines(night, context: context, now: now), id: \.self) {
                    Text($0).font(.caption2).foregroundStyle(palette.muted).nonEssential()
                }
                if let note = context?.alertsNote(night.park) { AlertsNote(text: note, alignment: .leading) }
                AskIPhoneRow(source: WatchSky.cloudSource(night.park, context: context, now: now))
                // No score stands on this page, so the line says what the range is of: under "Clouds
                // from …" a bare "Forecast models: 59–89" read as cloud cover.
                if let models = context?.modelRange(for: night) {
                    Text("Forecast models put tonight's score between \(models.lowerBound) and \(models.upperBound).").font(.caption2).foregroundStyle(palette.muted).nonEssential()
                }
                if night.sky.darkHours > 0 {
                    Text("\(Duration.seconds(night.sky.darkHours*3600).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) of true darkness").font(.footnote)
                    // The iPhone's rule for the Moon in true darkness; how much is lit is the line above.
                    if let moon = night.sky.moonSentence(park: night.park, withLit: false) {
                        Text(moon).font(.caption2).foregroundStyle(palette.muted).nonEssential()
                    }
                } else {
                    Text(SkyConditions.noDarknessMessage(tonight: true)).font(.footnote)
                }
                if night.park.keepsOtherTime(at: now) {
                    Text("Times in \(night.park.timeZoneName)").font(.caption2).foregroundStyle(palette.muted).nonEssential()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    let park: Park
    let nights: [Night]
    let now: Date
    let isHome: Bool
    var body: some View {
        // The best by the iPhone's tie-breaks is named in the words of every surface (`WeekBest`), and
        // ringed unless every night scores the same ("Best this week: every night").
        let best = NightPlanner.best(nights), ringed = WeekBest.ringed(nights)
        // Sized as the iPhone sizes a week: a night that counts no clouds never sets the range (`NightMark.range`).
        let (low, high) = NightMark.range(nights)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchEyebrow(text: "Next 7 nights")
                if typeSize.isAccessibilitySize {
                    // Rows of words, no dots: what a hollow dot would say ("Early look", "Usual clouds")
                    // is written under the night it belongs to, so the legend below is not needed.
                    ForEach(nights) { night in
                        VStack(alignment: .leading, spacing: 0) {
                            // Clear of the scroll indicator at the trailing edge.
                            HStack { Text(park.dayLabel(night.id)); Spacer(); Text(night.score.value, format: .number).foregroundStyle(palette.accent) }.padding(.trailing, 8)
                            if let basis = night.standaloneBasisLabel { Text(basis).font(.caption2).foregroundStyle(palette.muted) }
                        }
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore).accessibilityLabel(label(night))
                    }
                } else {
                    HStack(spacing: 0) { ForEach(nights) { night in column(night, best: night.id == ringed?.id, low: low, high: high) } }
                }
                if let best, let line = WeekBest.label(nights, scored: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // "Best this week: Sat", "…: tonight" or "…: every night", as the iPhone's Parks
                        // rows and medium widget say it, with the score as a numeral under it.
                        Text(line).font(.footnote)
                        // The score in the accent, its band word in ink as the dial sets it, and what
                        // the score rests on in a line of its own.
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(best.score.value, format: .number).scoreNumeral(.body, accent: palette.accent)
                            Text(best.score.band.label).bandWord(.subheadline, ink: palette.ink)
                        }
                        if let note = best.basisNote { Text(note).font(.caption2).foregroundStyle(palette.muted) }
                    }
                    .fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
                }
                // The park's closure from the iPhone's last park update, under the week's score, as on every surface.
                if let closure = store.context?.closures[park.id] { WristClosureLine(text: closure, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading) }
                // Then why none may be known (park alerts off on iPhone, or no park update covering the
                // park), or that the closure is an earlier update's while the Park Service refuses requests.
                if let note = store.context?.alertsNote(park) { AlertsNote(text: note, alignment: .leading) }
                Group {
                    // Why Tonight shows this place, where nothing on screen says so: nothing is saved on iPhone.
                    if isHome, let line = WatchSky.caption(store.rule(at: now)) { Text(line) }
                    if !typeSize.isAccessibilitySize, let legend { Text(legend) }
                    if let line = WatchSky.cloudSource(park, context: store.context, now: now).line(for: park) { Text(line) }
                    if let line = store.context?.dataNote { Text(line) }
                }
                .font(.caption2).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true).nonEssential()
                AskIPhoneRow(source: WatchSky.cloudSource(park, context: store.context, now: now))
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
    /// What the marks mean, in the iPhone's week legend: the fills where a night has no full forecast,
    /// the stars under Differentiate Without Color.
    private var legend: String? {
        // The ring is named only where one is drawn.
        let ring = WeekBest.ringed(nights) != nil
        // A night that counts no clouds is drawn hollow too, and named where the week has one.
        let marks = switch (ring, nights.contains { $0.basis == .usual && $0.score.cloudPoints == nil }) {
        case (true, false): String(localized: "Solid: forecast. Half-filled: an early look. Hollow: usual clouds. The ring marks the week's best night.")
        case (false, false): String(localized: "Solid: forecast. Half-filled: an early look. Hollow: usual clouds.")
        case (true, true): String(localized: "Solid: forecast. Half-filled: an early look. Hollow: usual clouds, or the Moon and darkness only. The ring marks the week's best night.")
        case (false, true): String(localized: "Solid: forecast. Half-filled: an early look. Hollow: usual clouds, or the Moon and darkness only.")
        }
        if nights.contains(where: { $0.basis.fill != .full }) { return differentiate ? Sentences.join([NightMark.legend, marks]) : marks }
        guard differentiate else { return nil }
        return ring ? String(localized: "\(NightMark.legend) The ring marks the week's best night.") : NightMark.legend
    }
    private func column(_ night: Night, best: Bool, low: Int, high: Int) -> some View {
        VStack(spacing: 3) {
            Text(park.weekdayInitial(night.id)).font(.caption2.weight(best ? .bold : .regular)).foregroundStyle(best ? palette.ink : palette.muted)
            ZStack {
                if best { Circle().stroke(palette.accent.opacity(0.8), lineWidth: palette.stroke).frame(width: 20, height: 20) }
                // The iPhone's sizes across the week's own range, 7.5 pt at most so the 10 pt ring stays clear of it.
                let d = 2*NightMark.drawnRadius(NightMark.radius(score: night.score.value, low: low, high: high, largest: 7.5), fill: night.basis.fill, lineWidth: 1, stroke: palette.stroke)
                // Wrist down the fills drop to one quiet level; only the sizes still rank the nights.
                NightDot(fill: night.basis.fill, color: palette.accent, fillOpacity: palette.markOpacity(score: dimmed ? 0 : night.score.value), lineWidth: palette.stroke,
                         mark: NightMark.mark(night, differentiate: differentiate)).frame(width: d, height: d)
            }.frame(height: 22)
            Text(night.score.value, format: .number).font(.caption2.monospacedDigit()).foregroundStyle(palette.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(night) + (best ? ". " + String(localized: "Best this week") : ""))
    }
    private func label(_ night: Night) -> String {
        let base = String(localized: "\(park.dayLabel(night.id)), \(night.score.value), \(night.score.band.label)")
        return ([base]+[night.standaloneBasisLabel, night.smokeLabel].compactMap { $0 }).joined(separator: ", ")
    }
}

struct WatchEyebrow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: LocalizedStringKey
    var body: some View {
        // Set solid at accessibility sizes, as on iPhone and Vision Pro.
        let spaced = Lettering.spaced && !typeSize.isAccessibilitySize
        // Clear of the page dots the system sets at the trailing edge of a vertical page; a long heading wraps.
        Text(text).font(.caption2.weight(.medium)).textCase(spaced ? .uppercase : nil).tracking(spaced ? 1.2 : 0).foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true).padding(.trailing, 10).accessibilityAddTraits(.isHeader)
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
                    } footer: { Text("Tonight shows \(pinned.shortName).") }
                }
                if !store.savedParks.isEmpty {
                    Section("Saved on iPhone") { ForEach(store.savedParks) { row($0, now: now, scored: true) } }
                }
                // The watch bundles the 63 US national parks only; saved spots and places abroad come from iPhone, above.
                Section("US national parks") { ForEach(store.parks) { row($0, now: now, scored: false) } }
                Section {
                    Picker("Night vision", selection: $store.palette) { ForEach(PaletteChoice.allCases) { Text($0.title).tag($0) } }
                } footer: { Text("At dusk is red from dusk to dawn at your iPhone's starting point. Night vision keeps your eyes adapted to the dark.") }
                Section {
                    NavigationLink(value: WatchRoute.credits) { Label("Credits", systemImage: "text.book.closed") }
                } footer: { Text("Nyx on Apple Watch makes no network requests. Clouds come from Nyx on your iPhone.") }
            }
        }
        .nyxTitle(String(localized: "Parks"))
    }
    private func row(_ park: Park, now: Date, scored: Bool) -> some View {
        let night = scored ? store.tonight(park, at: now) : nil, closure = scored ? store.context?.closures[park.id] : nil
        return NavigationLink(value: WatchRoute.night(WatchLink(park: park, evening: nil))) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(park.shortName).font(.system(.body, design: .serif)).lineLimit(2)
                    Text(park.statesLine).font(.caption2).foregroundStyle(palette.muted)
                }
                Spacer(minLength: 2)
                if store.pinned == park.id { Image(systemName: "pin.fill").font(.caption2).accessibilityLabel("On Tonight") }
                if let night {
                    // A known closure's mark beside the score, as on the iPhone's rows; its words are on the park's page.
                    if closure != nil { Image(systemName: ClosureLine.symbol).font(.caption2).foregroundStyle(palette.caution) }
                    Text(night.score.value, format: .number).scoreNumeral(.title3, accent: palette.accent)
                }
            }
            // A scored row says what the iPhone's and Vision Pro's rows say (`Night.spokenRow`), the closure in full.
            .modifier(SpokenRow(label: night?.spokenRow(closure: closure, withBasis: true), pinned: store.pinned == park.id))
        }
    }
}
/// A scored row's VoiceOver words in place of its parts': the row label every device says, then
/// "On Tonight" when the row's place is pinned there.
private struct SpokenRow: ViewModifier {
    let label: String?
    let pinned: Bool
    func body(content: Content) -> some View {
        if let label {
            content.accessibilityElement(children: .ignore).accessibilityLabel(Text(verbatim: label)).accessibilityValue(pinned ? Text("On Tonight") : Text(verbatim: ""))
        } else {
            content
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
                    Text("Choose a place").font(.system(.title3, design: .serif))
                    Text("Nyx on iPhone sends your saved places and cloud forecasts. Until then, scores use each place's usual clouds.").font(.caption2).foregroundStyle(palette.muted)
                }.listRowBackground(Color.clear)
                // Nothing has come from the iPhone yet: ask for it here rather than wait.
                if store.context == nil { AskIPhoneRow(source: .unsynced).listRowBackground(Color.clear) }
            }
            // The 63 US national parks the watch bundles, Dark Sky designated ones first (marked), as one honest list.
            Section("US national parks") { ForEach(store.parks.filter(\.darkSkyDesignated) + store.parks.filter { !$0.darkSkyDesignated }) { row($0) } }
        }
        .nyxTitle("Nyx")
    }
    private func row(_ park: Park) -> some View {
        // Until the iPhone names Tonight's places: a pick here gives way to them (`WatchStore.apply`).
        Button { store.pin(park, provisional: true) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(park.shortName).font(.system(.body, design: .serif))
                    Text(park.statesLine).font(.caption2).foregroundStyle(palette.muted)
                }
                Spacer(minLength: 2)
                if park.darkSkyDesignated { Image(systemName: "moon.stars").font(.caption2).foregroundStyle(palette.ink).accessibilityLabel("Dark Sky designated") }
            }
        }
    }
}

extension NyxPalette {
    /// Toolbar buttons fill with the tint on watchOS. A bright fill would be the brightest thing on
    /// the screen at night, so they sit dark: nebula violet, or near-black under red light.
    var toolbarTint: Color { nightVision ? Color(white: 0.2) : NyxPalette.nebula }
}
extension View {
    /// The system title is a dim grey that falls below 4.5:1 once turned red; draw it in ink instead.
    /// `shorter`: the name as said on a small wrist (`Park.wristName`), where the whole one does not fit.
    func nyxTitle(_ title: String, shorter: String? = nil) -> some View { modifier(NyxTitle(title: title, shorter: shorter ?? title)) }
}
private struct NyxTitle: ViewModifier {
    @Environment(\.nyx) private var palette
    let title: String
    let shorter: String
    func body(content: Content) -> some View {
        // The whole name where it fits, else the shorter one, which shrinks before it truncates: at
        // 60% the 40 mm title still cut "Great Smoky…" and "American Sa…". One line even at
        // accessibility sizes: a second line would run into the system clock above it. VoiceOver
        // always hears the whole name.
        content.navigationTitle {
            ViewThatFits(in: .horizontal) {
                Text(title)
                Text(shorter).accessibilityLabel(title)
                Text(shorter).minimumScaleFactor(0.6).accessibilityLabel(title)
            }
            .foregroundStyle(palette.ink).lineLimit(1)
        }
        .toolbarForegroundStyle(palette.ink, for: .navigationBar)
    }
}
extension Park {
    /// The name the watch's title gives a bundled park whose short name is too long for a 40 mm
    /// title even at 60% (`NyxTitle`): the form rangers and visitors say. Every other place, and
    /// every larger watch the whole name fits, keeps `shortName`.
    var wristName: String? { localShortName == nil ? Self.wristNames[id] : nil }
    private static let wristNames: [String: String] = [
        "blca": "Black Canyon", "grsm": "Great Smokies", "gumo": "Guadalupe", "thro": "T. Roosevelt",
        "gaar": "Gates", "wrst": "Wrangell", "havo": "Volcanoes", "grsa": "Sand Dunes", "cave": "Carlsbad",
        "npsa": "Am. Samoa", "cuva": "Cuyahoga", "neri": "New River", "romo": "Rocky Mtn", "lavo": "Lassen",
        "chis": "Channel Isl.", "noca": "N. Cascades", "pefo": "Petrified", "maca": "Mammoth",
    ]
}

#Preview("Tonight • At dusk by day") {
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
                                   detail: context.forecastDetails[park.id], now: .now, climate: context.climate)
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
#Preview("Week • AX5") {
    // Rows of words: each night's basis written under it, and no legend for dots that are not drawn.
    WatchPreviewHost(nightVision: false) { park, store in WeekPage(park: park, nights: store.week(park, at: .now), now: .now, isHome: true) }
        .dynamicTypeSize(.accessibility5)
}
#Preview("Parks") {
    WatchPreviewHost(nightVision: false) { _, _ in NavigationStack { ParksList().watchRoutes() } }
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
                .foregroundStyle(palette.ink).tint(palette.ink).modifier(NightVisionFilter(enabled: nightVision)).background(Color.black)
        }
    }
}
