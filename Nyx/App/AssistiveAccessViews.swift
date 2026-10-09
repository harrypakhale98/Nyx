import SwiftUI
import SwiftData
import WidgetKit

/// Nyx in Assistive Access: one answer, in large type, with nothing to learn. Three choices:
/// "Tonight" (the darkest park within reach of the chosen starting point), "Saved parks" and the
/// "Red light" switch, which is the same night vision as the full app's.
/// Each park is one card: its name, one word for the night ("Excellent night"), the Moon as it
/// will look, when true darkness begins, and a closure if the park reported one. No river,
/// calendar, journal or Ask Nyx. The same `PlanModel` and journal store as the full app; system
/// controls take Assistive Access's own large style by themselves.
struct AssistiveAccessRoot: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    var body: some View {
        // High contrast throughout: amber and starlight at full strength, and the brighter red.
        let palette=NyxPalette(nightVision:nightVision,highContrast:true)
        NavigationStack { AssistiveHome() }
            .environment(\.nyx,palette)
            .preferredColorScheme(.dark)
            .background(AssistiveSavedSync())
            .modifier(NightVisionFilter(enabled:nightVision,red:palette.red))
            .animation(reduceMotion ? nil : NyxMotion.spring,value:nightVision)
            .task { model.savedSync.palette=palette }
            .onChange(of:nightVision) { _,on in
                // The same follow-through as the full app (`RootView`): widgets, the Control Center
                // control, the watch and a followed night's Live Activity change colour with the switch.
                model.savedSync.palette=NyxPalette(nightVision:on,highContrast:true)
                WidgetCenter.shared.reloadAllTimelines()
                ControlCenter.shared.reloadControls(ofKind:"NightVisionControl")
                model.savedSync.pushWatch(model)
                if DebugScenario.screen == nil { Task { await FieldActivities.refresh(nightVision:on) } }
            }
    }
}
/// The main window's saved-park upkeep, for this scene: the full app's `RootView` does not run in
/// Assistive Access, so "Remind me" would otherwise save a park and switch reminders on without
/// anything being scheduled. The widget's snapshot, the watch and reminders follow the saved parks
/// through the same `SavedSkySync`, which keeps the last snapshot's parks when the store could not open.
private struct AssistiveSavedSync: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Query private var saved: [SavedPark]
    @AppStorage("notificationsEnabled") private var reminders=false
    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .task { await update() }
            .onChange(of: saved.map(\.parkID)) { _, _ in Task { await update() } }
            .onChange(of: reminders) { _, enabled in Task { if enabled { await update() } else { await NotificationScheduler().remove() } } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.tick(); Task { await update() } }
                if phase == .background, DebugScenario.screen == nil { SavedSkySync.scheduleRefresh() }
            }
    }
    private func update() async { await model.savedSync.update(model, parkIDs: saved.map(\.parkID)) }
}
/// The three choices: the guidance's limit for a home screen.
struct AssistiveHome: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    var body: some View {
        List {
            NavigationLink { AssistiveTonight() } label:{ Label("Tonight",systemImage:"moon.stars") }
            NavigationLink { AssistiveSaved() } label:{ Label("Saved parks",systemImage:"star") }
            // Night vision, shared with the full app, widgets, the Live Activity and the watch. Reads
            // the palette, so what the switch says is what the screen shows.
            Toggle(isOn:Binding(get:{ palette.nightVision },set:{ nightVision=$0 })) { Label("Red light",systemImage:"flashlight.on.circle") }
                // A track that stays distinct from the white thumb once the screen is red.
                .tint(palette.controlTint)
        }
        .navigationTitle("Nyx")
        .task { if let park=AssistiveTonight.best(model) { await model.refresh([park]) } }
    }
}

/// The one park for tonight.
struct AssistiveTonight: View {
    @Environment(PlanModel.self) private var model
    /// The darkest park within the radius of the starting point (the first run's choice, or the
    /// example park until one is chosen).
    static func best(_ model: PlanModel) -> Park? { model.ranked(model.nearby(latitude: nil, longitude: nil)).first }
    var body: some View {
        ScrollView {
            if let park=Self.best(model) {
                AssistiveParkCard(park: park, reminder: true).padding(20)
            } else {
                Text("No national park is close enough tonight. Ask someone to choose a starting point in Nyx.").font(.title2).padding(20)
            }
        }
        .navigationTitle("Tonight")
        .assistiveAccessNavigationIcon(systemImage: "moon.stars")
    }
}

/// The same card for each saved park.
struct AssistiveSaved: View {
    @Environment(PlanModel.self) private var model
    @Query(sort: \SavedPark.savedAt) private var saved: [SavedPark]
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                let parks=saved.compactMap { model.park($0.parkID) }
                if parks.isEmpty {
                    Text("No saved parks yet. Parks you save in Nyx appear here.").font(.title2).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(parks) { park in AssistiveParkCard(park: park, reminder: false) }
            }.padding(20)
        }
        .navigationTitle("Saved parks")
        .assistiveAccessNavigationIcon(systemImage: "star")
        .task { await model.refresh(saved.compactMap { model.park($0.parkID) }) }
    }
}

/// One park, one night, said simply.
struct AssistiveParkCard: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.modelContext) private var context
    @Query private var saved: [SavedPark]
    @AppStorage("notificationsEnabled") private var reminders=false
    @State private var explains=false
    let park: Park
    /// Offers "Remind me" (Tonight's park), which saves the park and turns on reminders.
    var reminder: Bool
    private var night: Night { model.night(park) }
    private var isSaved: Bool { saved.contains { $0.parkID == park.id } }
    var body: some View {
        let night=night
        VStack(alignment: .leading, spacing: 18) {
            Text(park.shortName).font(.system(.largeTitle, design: .serif).weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(Self.word(night)).font(.title.weight(.semibold)).foregroundStyle(palette.accent).fixedSize(horizontal: false, vertical: true)
            MoonView(geometry: AstronomyEngine().moon(for: night).geometry).frame(maxWidth: 200).frame(maxWidth: .infinity)
            Text(Self.darkLine(night)).font(.title2).fixedSize(horizontal: false, vertical: true)
            if let closure=model.closure(park) {
                Label { Text("Closed: \(closure)").fixedSize(horizontal: false, vertical: true) } icon:{ Image(systemName: "exclamationmark.triangle.fill") }
                    .font(.title3.weight(.semibold)).foregroundStyle(palette.accent)
            }
            // Not offered when saved parks could not be opened: the park would not stay saved.
            if reminder && !model.journalUnavailable {
                if !(isSaved && reminders) {
                    Button { remind() } label:{ Label("Remind me", systemImage: "bell").frame(maxWidth: .infinity, minHeight: 56) }
                        .buttonStyle(.borderedProminent).foregroundStyle(Color.black)
                        .accessibilityHint("Nyx will tell you when a night here looks very dark.")
                } else {
                    Label("Nyx will remind you about dark nights here.", systemImage: "bell.fill").font(.title3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $explains) { RemindersExplainer { granted in reminders=granted }.nyxPresentation() }
    }
    /// "Excellent night", or "Excellent night, clouds not known yet" without a cloud forecast.
    static func word(_ night: Night) -> String {
        let word=String(localized: "\(night.score.band.label) night")
        return night.score.hasForecast ? word : word+", "+String(localized: "clouds not known yet")
    }
    /// "Dark from 8:40 PM", or the plain words for a night without true darkness.
    static func darkLine(_ night: Night) -> String {
        guard let start=night.sky.darkStart, night.sky.darkHours>0 else { return SkyConditions.noDarknessMessage(tonight: true) }
        return String(localized: "Dark from \(night.park.time(start))")
    }
    private func remind() {
        if !isSaved { context.insert(SavedPark(parkID: park.id)); try? context.save() }
        if !reminders { explains=true }
    }
}

#Preview("Assistive Access", traits: .assistiveAccess) { AssistiveAccessRoot().environment(PlanModel()).modelContainer(for: [SavedPark.self, JournalEntry.self], inMemory: true) }
#Preview("Tonight card") { let m=PlanModel(); if let p=m.home { ScrollView { AssistiveParkCard(park: p, reminder: true).padding() }.environment(m).modelContainer(for: [SavedPark.self, JournalEntry.self], inMemory: true).background(.black).preferredColorScheme(.dark) } }
