import SwiftUI
import SwiftData
import WidgetKit
import TipKit
import CoreSpotlight

struct RootView:View {
    @Environment(PlanModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorSchemeContrast) private var contrast
    @Query private var saved:[SavedPark]
    @Environment(\.modelContext) private var context
    @AppStorage("onboardingComplete") private var onboarded=false
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("notificationsEnabled") private var notificationsEnabled=false
    @State private var savedUpdating=false
    @State private var tab=0
    @State private var intro=false
    /// Cold launch: the launch screen's starfield paints first, then the app settles in.
    /// Never blocks input; skipped under Reduce Motion and in screenshot scenarios.
    @State private var revealed=DebugScenario.screen != nil
    @State private var launchParkID:String?
    /// The Tonight tab icon is today's real moon phase; refreshed whenever Nyx returns.
    @State private var moonIcon=RootView.currentMoonIcon()
    private var palette:NyxPalette { NyxPalette(nightVision:nightVision || DebugScenario.state=="night-vision",highContrast:contrast == .increased || DebugScenario.isEnabled("contrast")) }
    var body:some View {
        Group {
            if model.loadError { CalmState(symbol:"moon",title:"The park library could not open",message:"Close and reopen Nyx. Your saved nights remain on this iPhone.").background(Color.black) }
            else if let screen=DebugScenario.screen,screen != "tonight",screen != "parks",screen != "calendar",screen != "journal",screen != "learn" {
                NavigationStack { debugScreen(screen) }
            } else {
                ZStack {
                NightBackground().opacity(revealed ? 0 : 1)
                TabView(selection:$tab) {
                    Tab(value:0) { NavigationStack { TonightView() } } label:{ Label { Text("Tonight") } icon:{ moonIcon } }
                    Tab("Parks",systemImage:"mountain.2",value:1) { NavigationStack { ParksView() } }
                    Tab("Calendar",systemImage:"calendar",value:2) { NavigationStack { CalendarView() } }
                    Tab("Journal",systemImage:"book.closed",value:3) { NavigationStack { JournalView() } }
                    Tab("Learn",systemImage:"sparkles",value:4) { NavigationStack { LearnView() } }
                }
                .opacity(revealed ? 1 : 0).scaleEffect(revealed ? 1 : 0.97)
                }
            }
        }
        .environment(\.nyx,palette).environment(\.nyxReduceMotion,DebugScenario.isEnabled("reduce-motion"))
        .foregroundStyle(palette.ink,palette.muted,palette.muted).tint(palette.accent).preferredColorScheme(.dark).statusBarHidden(palette.nightVision)
        .modifier(DebugTypeSize())
        .modifier(NightVisionFilter(enabled:palette.nightVision))
        .animation(systemReduceMotion || DebugScenario.isEnabled("reduce-motion") ? nil : NyxMotion.spring,value:palette.nightVision)
        .sheet(isPresented:$intro,onDismiss:{ onboarded=true }) { OnboardingView { onboarded=true;intro=false }.environment(\.nyx,palette).nyxPresentation() }
        .sheet(item:Binding(get:{launchParkID.flatMap{model.park($0)}},set:{launchParkID=$0?.id})) { park in NavigationStack { ParkDetailView(park:park) }.nyxPresentation() }
        .task {
            NotificationRouter.shared.connect { parkID in launchParkID=parkID }
            if let screen=DebugScenario.screen { tab=["tonight":0,"parks":1,"calendar":2,"journal":3,"learn":4][screen] ?? 0 }
            #if DEBUG
            if DebugScenario.state=="populated" {
                context.insert(JournalEntry(date:.now,parkID:model.homeID,notes:"The Milky Way stretched above the ridge. A quiet hour under the stars."))
                context.insert(SavedPark(parkID:model.homeID))
                try? context.save()
            }
            #endif
            intro = !onboarded && DebugScenario.screen == nil
            if systemReduceMotion || DebugScenario.isEnabled("reduce-motion") { revealed=true }
            else { withAnimation(.spring(response:0.9,dampingFraction:0.9)) { revealed=true } }
            if DebugScenario.screen == nil { await SpotlightIndexer.index(model.parks);await updateSaved() }
        }
        .onChange(of:scenePhase) { _,phase in if phase == .active { model.tick(); moonIcon=RootView.currentMoonIcon(); Task { await updateSaved() } } }
        .task {
            // Keep "tonight" honest on a screen left open through sunrise.
            while !Task.isCancelled { try? await Task.sleep(for:.seconds(300)); model.tick() }
        }
        .onChange(of:nightVision) { _,_ in
            // Keep the Control Center toggle and widgets in step with the in-app switch.
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadControls(ofKind:"NightVisionControl")
        }
        .onChange(of:notificationsEnabled) { _,enabled in Task { if enabled { await updateSaved() } else { await NotificationScheduler().remove() } } }
        .onChange(of:saved.map(\.parkID)) { _,_ in Task { await updateSaved() } }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            launchParkID=activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        }
        .onOpenURL { url in
            guard url.scheme=="nyx" else { return }
            if url.host=="park" { launchParkID=url.lastPathComponent } else if url.host=="tonight" { tab=0 }
        }
    }
    @ViewBuilder private func debugScreen(_ screen:String)->some View {
        #if DEBUG
        switch screen {
        case "detail": if let park=model.home { ParkDetailView(park:park) }
        case "breakdown": if let park=model.home { ScoreBreakdownView(night:model.night(park)) }
        case "editor": JournalEditorView()
        case "entry": JournalDetailView(entry:JournalEntry(date:.now,parkID:model.homeID,notes:"The Milky Way stretched above the ridge. A quiet hour under the stars."))
        case "onboarding": OnboardingView {}
        case "settings": SettingsView()
        case "privacy": PrivacyView()
        case "data": AboutDataView()
        case "article": EssayView(essay:.darkness)
        case "ask": GuideView(mode:.planning)
        case "widgets": WidgetReviewView(entry:TonightEntry(date:.now,night:model.home.map{model.night($0)},nightVision:false))
        case "widgets-empty": WidgetReviewView(entry:TonightEntry(date:.now,night:nil,nightVision:false))
        case "skyarc": if let park=model.home { ScrollView { Panel { SkyArc(night:model.night(park)) }.padding(24) }.background(NightBackground()) }
        case "river": if let park=model.home { ScrollView { Panel { TimeRiver(nights:DebugScenario.state=="empty" ? [] : model.nights(park,from:model.tonight(park),count:30),selected:.constant(model.tonight(park))) }.padding(24) }.background(NightBackground()) }
        case "location-explainer": PermissionExplainer(symbol:"location",title:"Find a sky nearby",message:"Nyx compares distances on this iPhone. Your location is never sent to a service.",action:"Use my location") {}
        case "notification-explainer": PermissionExplainer(symbol:"bell",title:"A night worth making time for",message:"Local reminders use complete cloud forecasts. They are estimates, not confirmations of access.",action:"Enable reminders") {}
        case "loader": ConstellationLoader().background(NightBackground())
        case "share": if let park=model.home { ShareCard(night:model.night(park)).environment(\.nyxReduceMotion,true) }
        default: TonightView()
        }
        #else
        TonightView()
        #endif
    }
    private static func currentMoonIcon()->Image {
        let moon=AstronomyEngine().moonPhase(at:.now)
        let renderer=ImageRenderer(content:MoonDisc(illumination:moon.illumination,waxing:moon.waxing,iconMode:true).frame(width:24,height:24))
        renderer.scale=3
        return renderer.uiImage.map{Image(uiImage:$0).renderingMode(.template)} ?? Image(systemName:"moon")
    }
    private func updateSaved() async {
        guard DebugScenario.screen == nil, !savedUpdating else { return }
        let initialIDs=saved.map(\.parkID)
        savedUpdating=true
        defer {
            savedUpdating=false
            if saved.map(\.parkID) != initialIDs { Task { await updateSaved() } }
        }
        let parks=saved.compactMap{model.park($0.parkID)}
        await model.refresh(parks)
        let snapshot=SavedSkySnapshot(parks:parks,forecasts:model.forecasts)
        SharedSettings.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        if notificationsEnabled {
            let today=model.today
            let nights=await Task.detached(priority:.utility) { snapshot.nights(from:today,count:14) }.value
            guard notificationsEnabled else { return }
            let names=Dictionary(parks.map { ($0.id,$0.shortName) },uniquingKeysWith:{ first,_ in first })
            await NotificationScheduler().reschedule(nights:nights) { plan in
                // The on-device model may only choose between two vetted titles; it never writes forecasts.
                guard let name=names[plan.parkID], await OnDeviceGuide.reminderStyle(parkName:name) else { return nil }
                return String(localized:"A night to consider at \(name)")
            }
        }
    }
}
#Preview("Tab shell") { RootView().environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self],inMemory:true) }

private struct DebugTypeSize: ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if DebugScenario.isEnabled("ax5") { content.dynamicTypeSize(.accessibility5) } else { content }
    }
}
