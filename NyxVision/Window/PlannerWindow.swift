import SwiftUI

/// The planner: every park with its score for the chosen night, and one park's
/// night in full. The ornament below steps nights and scrubs the night's clock, for the window and
/// for the immersive sky alike.
struct PlannerWindow: View {
    static let id = "planner"
    @Environment(VisionModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var showCredits = VisionDebug.isEnabled("vision-credits")
    @State private var showPrivacy = VisionDebug.isEnabled("vision-privacy")
    /// True while the sky is opening or closing, so a second tap cannot start a second transition.
    @State private var skyBusy = false
    var body: some View {
        @Bindable var model = model
        let palette = VisionPalette(nightVision: model.nightVision, highContrast: contrast == .increased, solid: reduceTransparency)
        NavigationSplitView {
            ParkList(query: query)
                .searchable(text: $query, prompt: Text("Search parks"))
                .navigationTitle(Text("Nyx"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showPrivacy = true } label: { Label("Your privacy", systemImage: "hand.raised") }
                            .help(Text("Your privacy"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showCredits = true } label: { Label("Credits", systemImage: "info.circle") }
                            .help(Text("Credits"))
                    }
                }
        } detail: {
            NightDetail()
                .toolbar {
                    // Always in reach, wherever the detail is scrolled: into the sky and back out.
                    ToolbarItem(placement: .topBarTrailing) { skyButton }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { openWindow(id: MoonVolume.id) } label: { Label("The Moon on your table", systemImage: "moon.circle") }
                            .help(Text("The Moon on your table"))
                            .accessibilityHint(Text("Opens this night's Moon as a globe you can place in the room"))
                            .disabled(model.plan == nil)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Toggle(isOn: $model.constellations) { Label("Constellations", systemImage: "point.3.connected.trianglepath.dotted") }
                            .toggleStyle(.button)
                            .help(Text("Constellations"))
                            .accessibilityHint(Text("Shows or hides the constellation figures in the sky"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Toggle(isOn: $model.nightVision) { Label("Night vision", systemImage: "eye") }
                            .toggleStyle(.button)
                            .accessibilityHint(Text("Turns the window and the sky a dim red that keeps your eyes adapted to the dark"))
                    }
                }
        }
        .sheet(isPresented: $showCredits) { CreditsView().environment(\.visionPalette, palette).modifier(DebugTypeSize()) }
        .sheet(isPresented: $showPrivacy) { YourPrivacyView().environment(model).environment(\.visionPalette, palette).modifier(DebugTypeSize()) }
        .ornament(visibility: model.parks.isEmpty ? .hidden : .visible, attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            NightControls().environment(\.visionPalette, palette)
        }
        .environment(\.visionPalette, palette)
        .modifier(NightVisionWindow(enabled: model.nightVision, palette: palette))
        .modifier(DebugTypeSize())
        .task {
            if let body = VisionDebug.body { model.selectedBody = body }
            if VisionDebug.isEnabled("vision-no-lines") { model.constellations = false }
            if VisionDebug.isEnabled("vision-moon") { openWindow(id: MoonVolume.id) }
            if VisionDebug.isEnabled("vision-widget-shots") { VisionWidgetShots.render() }
            if VisionDebug.isEnabled("vision-immersive") { await toggleSky() }
            // DEBUG: `-nyx-vision-skyonly` closes the window once the sky is open, for screenshots of the sky alone.
            if VisionDebug.isEnabled("vision-skyonly"), model.immersiveOpen { dismissWindow(id: Self.id) }
        }
        // Tonight moves on at the park's sunrise, however long the headset kept Nyx suspended.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await model.keepClock()
        }
        // The Moon volume offers a way back here only while every planner window is closed.
        .onAppear { model.plannerWindows += 1 }
        .onDisappear { model.plannerWindows = max(0, model.plannerWindows-1) }
        // While the window is in use: the parks' cloud forecast, asked for again only when six hours old.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await model.keepForecastsFresh()
        }
        // A park and night handed off from Nyx on iPhone or iPad: that park, that night, in this window.
        .onContinueUserActivity(ParkHandoff.type) { activity in
            if let handoff = ParkHandoff(userInfo: activity.userInfo) { model.open(handoff) }
        }
        .onChange(of: scenePhase) { _, phase in
            // The window holds every control for the sky. Closed, it would leave someone standing
            // in a sky they cannot change or leave except by the Digital Crown, so the sky closes
            // with it. Opening Nyx again brings the window back.
            guard phase == .background, model.immersiveOpen, !VisionDebug.isEnabled("vision-skyonly") else { return }
            Task { await dismissImmersiveSpace(); model.immersiveOpen = false }
        }
    }
    private var skyButton: some View {
        let open = model.immersiveOpen
        return Button { Task { await toggleSky() } } label: {
            Label(open ? "Leave the sky" : "Stand under this sky", systemImage: open ? "xmark" : "sparkles")
        }
        .buttonStyle(.borderedProminent).tint(model.nightVision ? .white.opacity(0.3) : Color(red: 1, green: 0.706, blue: 0.329).opacity(0.85))
        .disabled(skyBusy || model.plan == nil)
        .accessibilityHint(open ? Text("Returns to the room. The window stays where it is.")
                                : Text("Surrounds you with this park's computed sky at the time on the clock below the window"))
    }
    private func toggleSky() async {
        guard !skyBusy else { return }
        skyBusy = true
        defer { skyBusy = false }
        if model.immersiveOpen { await dismissImmersiveSpace(); model.immersiveOpen = false; return }
        if case .opened = await openImmersiveSpace(id: SkySpace.id) { model.immersiveOpen = true }
    }
}

/// Night vision on the window: every colour to a dim red over a near-black panel instead of grey glass.
private struct NightVisionWindow: ViewModifier {
    let enabled: Bool
    let palette: VisionPalette
    func body(content: Content) -> some View {
        content
            .saturation(enabled ? 0 : 1)
            .colorMultiply(enabled ? palette.red : .white)
            .background { if enabled { palette.nightPanel } }
            .animation(VisionMotion.spring, value: enabled)
    }
}
struct DebugTypeSize: ViewModifier {
    func body(content: Content) -> some View {
        if VisionDebug.isEnabled("ax5") { content.dynamicTypeSize(.accessibility3) } else { content }
    }
}

/// Every park in alphabetical order (a place you can reach matters more than a rank), each with
/// its score for the chosen night.
struct ParkList: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.visionPalette) private var palette
    let query: String
    var body: some View {
        @Bindable var model = model
        let parks = model.parks.filter { $0.matches(query) }
        List(selection: $model.selectedID) {
            Section {
                ForEach(parks) { park in
                    ParkRow(park: park, night: model.listNights[park.id]).tag(park.id)
                }
            } header: {
                Text(model.nightOffset == 0 ? String(localized: "Tonight") : nightName)
            }
        }
        .overlay {
            if model.parks.isEmpty { ParkDataUnavailable() }
            else if parks.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }
    private var nightName: String {
        guard let park = model.park else { return "" }
        return park.dayLabel(model.night(for: park))
    }
}
/// A park and its night: the score, and under it the band, or "Early look" / "Estimate" when the
/// night has no full cloud forecast (the iPhone's compact words).
struct ParkRow: View {
    @Environment(\.visionPalette) private var palette
    let park: Park
    let night: Night?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(park.shortName).font(.system(.body, design: .serif))
                Text(park.state).font(.caption).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 8)
            if let night {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(night.score.value, format: .number).font(.system(.title2, design: .serif)).monospacedDigit().foregroundStyle(palette.accent)
                    Text(night.compactBandLabel).font(.caption2).foregroundStyle(palette.muted)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(park.name))
        .accessibilityValue(night.map { Text("\($0.score.value) out of 100, \($0.bandWithBasis)") } ?? Text("Computing"))
    }
}

#if DEBUG
#Preview("Park rows: forecast, early look, usual clouds, computing") {
    let parks = Array(VisionModel(now: .now).parks.prefix(2))
    let now = Date.now
    func night(_ park: Park, days: Int, forecast: Bool) -> Night {
        let evening = park.date(park.currentNight(at: now), addingDays: days)
        return NightPlanner.night(park: park, sky: AstronomyEngine().conditions(for: park, on: evening),
                                  forecast: forecast ? VisionModel.fixture(parks: [park], cover: 20, issued: now)[park.id] : nil, detail: nil, now: now)
    }
    return List {
        ForEach(parks) { park in
            ParkRow(park: park, night: night(park, days: 0, forecast: true))
            ParkRow(park: park, night: night(park, days: 6, forecast: true))
            ParkRow(park: park, night: night(park, days: 20, forecast: false))
            ParkRow(park: park, night: nil)
        }
    }
}

#Preview("Planner") {
    PlannerWindow().environment(VisionModel(now: .now))
}

#Preview("Planner, park data unavailable") {
    PlannerWindow().environment(VisionModel(now: .now, parks: []))
}
#endif
