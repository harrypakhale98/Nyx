import SwiftUI

/// Red first: at a dark site the wrist is the screen, and red light keeps the eyes adapted.
struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        let palette = NyxPalette(nightVision: store.nightVision, highContrast: contrast == .increased)
        NavigationStack {
            #if DEBUG
            if let screen = WatchDebug.screen, !WatchDebug.homeScreens.contains(screen) { WatchDebug.view(screen) }
            else { home }
            #else
            home
            #endif
        }
        .environment(\.nyx, palette)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .modifier(WatchDebug.TypeSize())
        // The complication review draws in the widgets' own colours, so it is not filtered twice.
        .modifier(NightVisionFilter(enabled: palette.nightVision && WatchDebug.screen != "complications"))
        .background(Color.black)
    }
    @ViewBuilder private var home: some View {
        TimelineView(.everyMinute) { timeline in
            if let park = store.featured(at: timeline.date) { ParkNightView(park: park, isHome: true) }
            else { ParkChooser() }
        }
    }
}

/// One park's night in three pages the Digital Crown moves through: the score and what comes
/// next, tonight's milestones, and the week.
struct ParkNightView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.nyx) private var palette
    let park: Park
    var isHome = false
    @State private var page = WatchDebug.initialPage
    @State private var darkMode = WatchDebug.screen == "dark"
    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            let night = store.tonight(park, at: now)
            TabView(selection: $page) {
                TonightFace(night: night, now: now, context: store.context).tag(0)
                MilestonesPage(night: night, now: now, context: store.context).tag(1)
                WeekPage(park: park, nights: store.week(park, at: now), isHome: isHome).tag(2)
            }
            .tabViewStyle(.verticalPage)
        }
        .nyxTitle(park.wristName)
        .toolbar {
            if isHome {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ParksList() } label: { Label("Parks", systemImage: "list.bullet") }.tint(palette.toolbarTint)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { darkMode = true } label: { Label("Dark adaptation", systemImage: "eye") }.tint(palette.toolbarTint)
            }
        }
        .fullScreenCover(isPresented: $darkMode) { DarkAdaptationView(park: park) }
    }
}

/// One glance: the gauge first, then what happens next. Scrolls only at accessibility sizes,
/// where the gauge keeps its size and the words flow below it.
struct TonightFace: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let night: Night
    let now: Date
    let context: WatchContext?
    var body: some View {
        if typeSize.isAccessibilitySize {
            ScrollView {
                VStack(spacing: 6) {
                    WatchGauge(night: night).frame(width: 112, height: 112)
                    Text(night.score.band.label).font(.system(.headline, design: .serif))
                    NextMoment(night: night, now: now)
                    if let note = WatchSky.forecastNote(night, context: context) { Text(note).font(.caption2).foregroundStyle(palette.faint).multilineTextAlignment(.center) }
                }.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 3) {
                // The gauge takes what the words leave: larger on Ultra, never crowding them on 42 mm.
                WatchGauge(night: night).frame(maxWidth: 150, minHeight: 0)
                // Clouds unknown rides on the clock-time line, so the "now" line costs the gauge nothing.
                NextMoment(night: night, now: now, cloudsUnknown: !night.score.hasForecast).layoutPriority(1)
                if NightMilestone.next(after: now, in: night.sky) == nil, let note = WatchSky.forecastNote(night, context: context, short: true) {
                    Text(note).font(.caption2).foregroundStyle(palette.faint).lineLimit(1).minimumScaleFactor(0.8).layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    var body: some View {
        Group {
            if let next = NightMilestone.next(after: now, in: night.sky) {
                VStack(spacing: 0) {
                    // At the site the first question is "is it dark yet": answer it before the countdown.
                    if let state = nowLine {
                        Text(state).font(.caption2.weight(.semibold)).textCase(.uppercase).tracking(1).foregroundStyle(palette.accent)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    countdownText(next, now: now).font(.system(.subheadline, design: .serif)).foregroundStyle(palette.ink)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.7)
                    Group {
                        if cloudsUnknown { Text("at \(night.park.time(next.date)) · clouds unknown") } else { Text("at \(night.park.time(next.date))") }
                    }
                    .font(.caption2).foregroundStyle(palette.muted).lineLimit(1).minimumScaleFactor(0.8)
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
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(past ? String(localized: "Passed") : milestone == next ? String(localized: "Next") : "")
                }
                if list.isEmpty { Text("No sunset, darkness or moonrise tonight.").font(.footnote) }
                Rectangle().fill(palette.line).frame(height: 0.5).padding(.vertical, 2).accessibilityHidden(true)
                Text("\(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded()))% lit").font(.footnote)
                if let note = WatchSky.forecastNote(night, context: context) { Text(note).font(.caption2).foregroundStyle(palette.muted) }
                if night.sky.darkHours > 0 {
                    Text("\(Duration.seconds(night.sky.darkHours*3600).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) of true darkness").font(.footnote)
                    Text(moonLine).font(.caption2).foregroundStyle(palette.muted)
                } else {
                    Text(SkyConditions.noDarknessMessage(tonight: true)).font(.footnote)
                }
                if night.park.timeZone.secondsFromGMT(for: now) != TimeZone.current.secondsFromGMT(for: now) {
                    Text("Times in \(night.park.timeZoneName)").font(.caption2).foregroundStyle(palette.muted)
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

struct WeekPage: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: Park
    let nights: [Night]
    let isHome: Bool
    var body: some View {
        let best = nights.max { $0.score.value < $1.score.value }
        // Nights that tie the best are all ringed; the first is named, the rest counted.
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
                if nights.contains(where: { !$0.score.hasForecast }) {
                    Text("Hollow nights are moon and darkness only.").font(.caption2).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                }
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
                if night.score.hasForecast { Circle().fill(palette.accent.opacity(0.5+Double(night.score.value)/200)).frame(width: d, height: d) }
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
        return night.score.hasForecast ? base : base + ", " + String(localized: "moon and darkness only")
    }
}

struct WatchEyebrow: View {
    @Environment(\.nyx) private var palette
    let text: LocalizedStringKey
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).textCase(.uppercase).tracking(1.2).foregroundStyle(palette.muted).accessibilityAddTraits(.isHeader)
    }
}

/// Every park, saved ones first with tonight's score; the palette choice lives here too.
struct ParksList: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.nyx) private var palette
    var body: some View {
        @Bindable var store = store
        TimelineView(.everyMinute) { timeline in
            List {
                if let pinned = store.park(store.pinned) {
                    Section {
                        Button { store.pin(nil) } label: { Label("Follow iPhone again", systemImage: "pin.slash") }
                    } footer: { Text("Tonight shows \(pinned.wristName).") }
                }
                if !store.savedParks.isEmpty {
                    Section("Saved on iPhone") { ForEach(store.savedParks) { row($0, now: timeline.date, scored: true) } }
                }
                Section("All parks") { ForEach(store.parks) { row($0, now: timeline.date, scored: false) } }
                Section {
                    Picker("Colors", selection: $store.palette) { ForEach(PaletteChoice.allCases) { Text($0.title).tag($0) } }
                } footer: { Text("Red light keeps your eyes adapted to the dark.") }
                Section {} footer: { Text("Nyx on Apple Watch makes no network requests. Clouds come from Nyx on your iPhone.") }
            }
        }
        .nyxTitle(String(localized: "Parks"))
    }
    private func row(_ park: Park, now: Date, scored: Bool) -> some View {
        NavigationLink { ParkNightView(park: park) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(park.wristName).font(.system(.body, design: .serif)).lineLimit(2)
                    Text(park.state).font(.caption2).foregroundStyle(palette.muted)
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

/// Before the iPhone has sent anything: pick a park, and Nyx works from the Moon and darkness alone.
struct ParkChooser: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.nyx) private var palette
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a park").font(.system(.title3, design: .serif))
                    Text("Nyx on iPhone sends your saved parks and clouds. Until then, the score is moon and darkness only.").font(.caption2).foregroundStyle(palette.muted)
                }.listRowBackground(Color.clear)
            }
            Section("Dark-sky parks") { ForEach(store.parks.filter(\.darkSkyDesignated)) { row($0) } }
            Section("Other parks") { ForEach(store.parks.filter { !$0.darkSkyDesignated }) { row($0) } }
        }
        .nyxTitle("Nyx")
    }
    private func row(_ park: Park) -> some View {
        Button { store.pin(park) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(park.wristName).font(.system(.body, design: .serif))
                Text(park.state).font(.caption2).foregroundStyle(palette.muted)
            }
        }
    }
}

/// Field mode on the wrist: red only, black everywhere, one large countdown to the next moment.
struct DarkAdaptationView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 40
    let park: Park
    @Environment(\.dismiss) private var dismiss
    private let palette = NyxPalette(nightVision: true, highContrast: false)
    var body: some View {
        // Its own stack, filtered as a whole: the system's close button would otherwise be the one
        // white thing on the screen. A dark, red-glyphed Done replaces it.
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Label("Done", systemImage: "xmark") }.tint(palette.toolbarTint)
                    }
                }
        }
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .environment(\.nyx, palette)
        .modifier(NightVisionFilter(enabled: true))
        .background(Color.black)
    }
    private var content: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            let night = store.tonight(park, at: now)
            let list = NightMilestone.list(for: night.sky)
            ScrollView {
                VStack(spacing: 6) {
                    if let next = list.first(where: { $0.date > now }) {
                        Text(next.title).font(.system(.headline, design: .serif))
                        Group {
                            // Wrist down, the seconds would only drain the battery: minutes are enough.
                            if dimmed { Text(inDuration(until: next.date, from: now)) }
                            else { Text(timerInterval: now...max(now, next.date), countsDown: true) }
                        }
                        .font(.system(size: timerSize, weight: .light, design: .serif)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(palette.accent)
                        Text("at \(park.time(next.date))").font(.footnote).foregroundStyle(palette.muted)
                        if let after = list.first(where: { $0.date > next.date }) {
                            Text("Next: \(after.title), \(park.time(after.date))").font(.caption2).foregroundStyle(palette.muted)
                        }
                    } else {
                        Text("Nothing more tonight").font(.system(.headline, design: .serif))
                    }
                    Text("Red light only. Eyes take 20 to 30 minutes to adapt to the dark; a bright screen resets them.")
                        .font(.caption2).foregroundStyle(palette.faint).padding(.top, 6)
                }
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
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
        // Long names ("Black Canyon of the Gunnison") shrink before they truncate.
        content.navigationTitle { Text(title).foregroundStyle(palette.ink).lineLimit(1).minimumScaleFactor(0.6) }
            .toolbarForegroundStyle(palette.ink, for: .navigationBar)
    }
}
