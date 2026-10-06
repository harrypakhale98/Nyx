import SwiftUI

/// The planner: every park with its moon-and-darkness score for the chosen night, and one park's
/// night in full. The ornament below steps nights and scrubs the night's clock, for the window and
/// for the immersive sky alike.
struct PlannerWindow: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var query = ""
    var body: some View {
        @Bindable var model = model
        let palette = VisionPalette(nightVision: model.nightVision, highContrast: contrast == .increased, solid: reduceTransparency)
        NavigationSplitView {
            ParkList(query: query)
                .searchable(text: $query, prompt: Text("Search parks"))
                .navigationTitle(Text("Nyx"))
        } detail: {
            NightDetail(toggleSky: toggleSky)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Toggle(isOn: $model.nightVision) { Label("Night vision", systemImage: "eye") }
                            .toggleStyle(.button)
                            .accessibilityHint(Text("Turns the window and the sky a dim red that keeps your eyes adapted to the dark"))
                    }
                }
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            NightControls().environment(\.visionPalette, palette)
        }
        .environment(\.visionPalette, palette)
        .modifier(NightVisionWindow(enabled: model.nightVision, palette: palette))
        .modifier(DebugTypeSize())
        .task {
            if let body = VisionDebug.body { model.selectedBody = body }
            if VisionDebug.isEnabled("vision-immersive") { await toggleSky() }
            // DEBUG: `-nyx-vision-skyonly` closes the window once the sky is open, for screenshots of the sky alone.
            if VisionDebug.isEnabled("vision-skyonly"), model.immersiveOpen { dismissWindow(id: "planner") }
        }
    }
    private func toggleSky() async {
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
            .colorMultiply(enabled ? Color(red: 1, green: 0.27, blue: 0.23) : .white)
            .background { if enabled { palette.nightPanel } }
            .animation(VisionMotion.spring, value: enabled)
    }
}
private struct DebugTypeSize: ViewModifier {
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
                    ParkRow(park: park, score: model.listScores[park.id]).tag(park.id)
                }
            } header: {
                Text(model.nightOffset == 0 ? "Tonight · moon and darkness" : "\(nightName) · moon and darkness")
            }
        }
        .overlay {
            if parks.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }
    private var nightName: String {
        guard let park = model.park else { return "" }
        return park.dayLabel(model.night(for: park))
    }
}
struct ParkRow: View {
    @Environment(\.visionPalette) private var palette
    let park: Park
    let score: DarknessScore?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(park.shortName).font(.system(.body, design: .serif))
                Text(park.state).font(.caption).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 8)
            if let score {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(score.value, format: .number).font(.system(.title2, design: .serif)).monospacedDigit().foregroundStyle(palette.accent)
                    Text(score.band.label).font(.caption2).foregroundStyle(palette.muted)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(park.name))
        .accessibilityValue(score.map { Text("\($0.value) out of 100, \($0.band.label), moon and darkness only") } ?? Text("Computing"))
    }
}
