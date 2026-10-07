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
    @AppStorage("showerReminders") private var showerReminders=true
    /// This window's tab and keyboard commands (each iPad window has its own).
    @State private var commands=SceneCommands()
    @State private var intro=false
    /// Cold launch: the launch screen's starfield paints first, then the app settles in.
    /// Never blocks input; skipped under Reduce Motion and in screenshot scenarios.
    @State private var revealed=DebugScenario.screen != nil
    @State private var launchParkID:String?
    /// A link's night at the park, and whether to open it at What's up.
    @State private var launchNight:(date:Date,whatsUp:Bool)?
    /// First light's park, while the sky reveals itself over the app.
    @State private var firstLight:Park?
    /// The Tonight tab icon is today's real moon phase, drawn just after the first frame (the tab
    /// bar is still fading in) and again whenever Nyx returns.
    @State private var moonIcon=Image(systemName:"moon")

    private var palette:NyxPalette { NyxPalette(nightVision:nightVision || DebugScenario.state=="night-vision" || DebugScenario.isEnabled("night-vision"),highContrast:contrast == .increased || DebugScenario.isEnabled("contrast")) }
    var body:some View {
        Group {
            if model.loadError { CalmState(symbol:"moon",title:"The park library could not open",message:"Close and reopen Nyx. Your saved nights remain on this iPhone.").background(Color.black) }
            else if let screen=DebugScenario.screen,screen != "tonight",screen != "parks",screen != "calendar",screen != "journal",screen != "learn" {
                NavigationStack { debugScreen(screen) }
            } else {
                ZStack {
                // Removed once revealed, so its sky stops animating and sensing tilt behind the tabs.
                if !revealed { NightBackground().transition(.opacity) }
                TabView(selection:$commands.tab) {
                    Tab(value:0) { NavigationStack { TonightView() }.environment(\.nyxTab,0).modifier(TabChrome(tint:palette.accent)) } label:{ Label { Text("Tonight") } icon:{ moonIcon } }
                    // Parks becomes a list beside the park on a wide iPad; a stack in narrow windows and on iPhone.
                    Tab("Parks",systemImage:"mountain.2",value:1) { ParksTab().environment(\.nyxTab,1).modifier(TabChrome(tint:palette.accent)) }
                    Tab("Calendar",systemImage:"calendar",value:2) { NavigationStack { CalendarView() }.environment(\.nyxTab,2).modifier(TabChrome(tint:palette.accent)) }
                    Tab("Journal",systemImage:"book.closed",value:3) { NavigationStack { JournalView() }.environment(\.nyxTab,3).modifier(TabChrome(tint:palette.accent)) }
                    Tab("Learn",systemImage:"sparkles",value:4) { NavigationStack { LearnView() }.environment(\.nyxTab,4).modifier(TabChrome(tint:palette.accent)) }
                }
                // A tab bar on iPhone; on iPad a tab bar that opens into a sidebar.
                .tabViewStyle(.sidebarAdaptable)
                .tint(commands.sidebar ? palette.controlTint : palette.accent)
                .tabViewSidebarHeader { Text(verbatim:"Nyx").font(.system(.title2,design:.serif)).foregroundStyle(palette.ink).accessibilityAddTraits(.isHeader) }
                .opacity(revealed ? 1 : 0).scaleEffect(revealed ? 1 : 0.97)
                }
            }
        }
        .environment(commands).focusedSceneValue(commands)
        .background(WindowSceneReader(commands:commands).frame(width:0,height:0).accessibilityHidden(true))
        .environment(\.nyx,palette).environment(\.nyxReduceMotion,DebugScenario.isEnabled("reduce-motion")).environment(\.skyHome,model.home)
        .foregroundStyle(palette.ink,palette.muted,palette.muted).tint(palette.accent).preferredColorScheme(.dark).statusBarHidden(palette.nightVision)
        .modifier(DebugTypeSize())
        .modifier(DebugWindow())
        // Field mode draws its own red; filtering it twice would darken it below legible contrast.
        .modifier(NightVisionFilter(enabled:palette.nightVision && !["field","field-compass"].contains(DebugScenario.screen ?? "")))
        .animation(systemReduceMotion || DebugScenario.isEnabled("reduce-motion") ? nil : NyxMotion.spring,value:palette.nightVision)
        .sheet(isPresented:$intro,onDismiss:{ onboarded=true }) { OnboardingView { onboarded=true;intro=false }.environment(\.nyx,palette).nyxPresentation() }
        .sheet(item:Binding(get:{launchParkID.flatMap{model.park($0)}},set:{launchParkID=$0?.id})) { park in ParkSheet(park:park,initialDate:launchNight?.date,whatsUp:launchNight?.whatsUp ?? false) }
        .overlay { if let park=firstLight { FirstLightView(park:park,night:model.tonight(park),moment:DebugScenario.screen == nil ? .now : FirstLightDebug.moment(park:park,model:model)) { firstLight=nil }.environment(\.nyx,palette).modifier(DebugTypeSize()).modifier(NightVisionFilter(enabled:palette.nightVision)) } }
        .onAppear { LaunchSignposts.firstFrame() }
        .task {
            moonIcon=RootView.currentMoonIcon()
            model.savedSync.palette=palette
            NotificationRouter.shared.connect { route in openReminder(route) }
            if let screen=DebugScenario.screen { commands.tab=["tonight":0,"parks":1,"calendar":2,"journal":3,"learn":4][screen] ?? 0 }
            #if DEBUG
            if DebugScenario.state=="populated" {
                // Illustrative sessions so store captures show a lived-in journal, written in the capture's language
                // (sample text only; DEBUG never adds catalog keys).
                let es=Bundle.main.preferredLocalizations.first=="es"
                let day:TimeInterval=86_400
                context.insert(JournalEntry(date:.now,parkID:model.homeID,notes:es ? "La Vía Láctea se extendía sobre la cresta. Una hora tranquila bajo las estrellas." : "The Milky Way stretched above the ridge. A quiet hour under the stars."))
                context.insert(JournalEntry(date:.now-24*day,parkID:"grba",observedBortle:1,notes:es ? "Sin Luna. Había tantas estrellas que costaba encontrar las constelaciones." : "No moon. The sky was so full of stars the constellations were hard to find."))
                context.insert(JournalEntry(date:.now-52*day,parkID:"brca",observedBortle:2,notes:es ? "Programa de astronomía con guardaparques. Saturno en un telescopio, con anillos y todo." : "Ranger astronomy program. Saturn through a telescope, rings and all."))
                context.insert(JournalEntry(date:.now-81*day,parkID:"deva",observedBortle:2,notes:es ? "Viento tibio desde las dunas. El núcleo galáctico colgaba bajo en el sur." : "Warm wind off the dunes. The galactic core hung low in the south."))
                context.insert(SavedPark(parkID:model.homeID))
                try? context.save()
            }
            #endif
            intro = !onboarded && DebugScenario.screen == nil
            if systemReduceMotion || DebugScenario.isEnabled("reduce-motion") { revealed=true }
            else { withAnimation(.spring(response:0.9,dampingFraction:0.9)) { revealed=true } }
            openRequestedField(); openRequestedPark()
            if let link=DebugScenario.link { try? await Task.sleep(for:.seconds(1)); handle(DeepLink(link)) }
            if DebugScenario.screen == nil { firstLight=await FirstLightWatcher.check(model:model) }
            if DebugScenario.screen == nil { LuminanceProof.shared.start(); try? await SpotlightIndexer.index(model.parks);await updateSaved() }
        }
        .onChange(of:scenePhase) { _,phase in
            // Ask iOS for the next background refresh whenever Nyx leaves the screen.
            if phase == .background, DebugScenario.screen == nil { SavedSkySync.scheduleRefresh() }
            if phase == .active {
            model.tick(); moonIcon=RootView.currentMoonIcon(); Task { await updateSaved() }
            if firstLight == nil { Task { if let park=await FirstLightWatcher.check(model:model) { firstLight=park } } }
            openRequestedField(); openRequestedPark()
            // The night's Live Activity catches up (or ends at dawn) whenever Nyx is opened.
            if DebugScenario.screen == nil { Task { await FieldActivities.refresh(nightVision:nightVision) } }
        } }
        .onReceive(NotificationCenter.default.publisher(for:FieldModeRequest.notification)) { _ in openRequestedField() }
        .onReceive(NotificationCenter.default.publisher(for:ParkOpenRequest.notification)) { _ in openRequestedPark() }
        .task {
            // Keep "tonight" honest on a screen left open through sunrise.
            while !Task.isCancelled { try? await Task.sleep(for:.seconds(300)); model.tick() }
        }
        .onChange(of:palette.nightVision) { _,_ in model.savedSync.palette=palette }
        .onChange(of:nightVision) { _,_ in
            // Keep the Control Center toggle and widgets in step with the in-app switch.
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadControls(ofKind:"NightVisionControl")
            WatchBridge.shared.push(savedParkIDs:saved.map(\.parkID),homeParkID:model.homeID,forecasts:model.forecasts)
        }
        .onChange(of:notificationsEnabled) { _,enabled in Task { if enabled { await updateSaved() } else { await NotificationScheduler().remove() } } }
        .onChange(of:saved.map(\.parkID)) { _,_ in Task { await updateSaved() } }
        .onChange(of:showerReminders) { _,_ in Task { await updateSaved() } }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            open(activity.userInfo?[CSSearchableItemActivityIdentifier] as? String)
        }
        .onOpenURL { url in
            // A journal export opened from Files: the Journal tab offers to import it.
            if url.isFileURL, url.pathExtension.lowercased() == JournalArchive.fileExtension { commands.tab=3; model.journalFile=url; return }
            handle(DeepLink(url))
        }
        // Differentiate Without Color, Reduce Highlighting, Cross-Fade, reduced resources: read once, for every screen and sheet.
        .nyxAccessibility()
    }
    /// Widgets, Spotlight, Live Activities, calendar events Nyx drafted and In-App Events all land here.
    private func handle(_ link:DeepLink?) {
        switch link {
        case .park(let id): launchNight=nil; open(id)
        case .tonight: commands.tab=0
        case .field(let id): if let park=model.park(id) { FieldPresenter.present(park:park,model:model,from:commands.topController) }
        case .whatsUp(let id,let day):
            guard let park=model.park(id) else { return }
            open(id,night:(day.evening(in:park),true))
        case .calendar(let id,let year,let month):
            guard model.park(id) != nil else { return }
            commands.tab=2; model.calendarRequest=CalendarRequest(parkID:id,year:year,month:month)
        case nil: break
        }
    }
    @ViewBuilder private func debugScreen(_ screen:String)->some View {
        #if DEBUG
        switch screen {
        case "detail": if let park=model.home { ParkDetailView(park:park) }
        case "breakdown": if let park=model.home { ScoreBreakdownView(night:model.night(park)).task { await model.refreshForecasts(watching:[park]) } }
        case "editor": JournalEditorView()
        case "entry": JournalDetailView(entry:JournalEntry(date:.now,parkID:model.homeID,notes:"The Milky Way stretched above the ridge. A quiet hour under the stars."))
        case "onboarding": OnboardingView {}
        case "settings": SettingsView()
        case "privacy": PrivacyView()
        // Your privacy → Advanced on its own, opened (`-nyx-advanced`).
        case "nps-key": Form { Section { NPSKeyField() } header:{ Text("Advanced") } }.readableForm().navigationTitle("Your privacy").navigationBarTitleDisplayMode(.inline)
        case "data": AboutDataView()
        // Light pollution, viewing spots (sky glow, step-free) and Protect this sky for one park: `-nyx-park deva | grca | sequ`.
        case "light": if let park=model.home { NavigationStack { ScrollView { VStack(spacing:26) { Panel { LightPollution(park:park) }; Panel { ViewingSpots(park:park) }; Panel { ProtectThisSky(park:park) } }.padding(24) }.background(NightBackground(park:park,night:model.tonight(park))).navigationTitle(park.shortName).navigationBarTitleDisplayMode(.inline) } }
        case "article": EssayView(essay:Essay(rawValue:DebugScenario.state ?? "") ?? .darkness)
        case "ask": GuideView(mode:.planning)
        case "widgets": WidgetReviewView(entry:DebugPlatform.widgetEntry(model,large:false)).task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        case "widgets-large": WidgetReviewView(entry:DebugPlatform.widgetEntry(model,large:true),large:true).task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        case "snippet": DebugSnippetView().task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        // About the data with the clearly labelled DEBUG luminance fixture (no real MetricKit report in the simulator).
        case "metric": if DebugScenario.state=="privacy" { PrivacyView().defaultScrollAnchor(.bottom) } else { AboutDataView() }
        case "widgets-xl": WidgetReviewView(entry:DebugPlatform.widgetEntry(model,large:true),extraLarge:true).task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        case "widgets-empty": WidgetReviewView(entry:TonightEntry(date:.now,night:nil,nightVision:false))
        case "skyarc": if let park=model.home { ScrollView { Panel { SkyArc(night:model.night(park),core:model.whatsUp(model.night(park)).core) }.padding(24) }.background(NightBackground(park:park,night:model.tonight(park))) }
        case "whatsup": if let park=model.home { ScrollView { Panel { WhatsUpPanel(whatsUp:model.whatsUp(model.night(park))) }.padding(24) }.background(NightBackground(park:park,night:model.tonight(park))) }
        case "river": if let park=model.home { let nights=DebugScenario.state=="empty" ? [] : model.nights(park,from:model.tonight(park),count:30); ScrollView { Panel { TimeRiver(nights:nights,selected:.constant(model.tonight(park)),outlooks:model.outlooks(nights),markers:model.markers(nights)) }.padding(24) }.background(NightBackground()).task { await model.refreshForecasts(watching:[park]) } }
        case "location-explainer": PermissionExplainer(symbol:"location",title:"Find a sky nearby",message:"Nyx compares distances on this iPhone. Your location is never sent to a service.",action:"Use my location") {}
        case "notification-explainer": PermissionExplainer(symbol:"bell",title:"A night worth making time for",message:"Local reminders use complete cloud forecasts. They are estimates, not confirmations of access.",action:"Enable reminders") {}
        case "loader": ConstellationLoader().background(NightBackground())
        case "field","field-compass": if let park=model.home { DebugField(park:park,model:model,compass:screen=="field-compass") }
        case "live-activity": if let park=model.home { FieldActivityReview(night:model.night(park)) }
        case "alarm-explainer": PermissionExplainer(symbol:"alarm",title:"An alarm for the sky",message:"Nyx can set an alarm on this iPhone for a moment in the night, like the Milky Way's core rising, so you can rest until the sky is ready. Alarms ring through Silent and Focus. Nothing leaves this phone.",action:"Allow alarms") {}
        case "share": if let park=model.home { ShareCard(night:model.night(park)).environment(\.nyxReduceMotion,true) }
        case "listen": if let park=model.home { ScrollView { Panel { NightListenView(night:model.night(park),expanded:true) }.padding(24) }.background(NightBackground(park:park,night:model.tonight(park))).navigationTitle(park.shortName).navigationBarTitleDisplayMode(.inline) }
        case "accessibility": SoundAndTouchView()
        // Settings → Support → Diagnostics, with two illustrative reports (`-nyx-state empty` for none).
        case "diagnostics": DiagnosticsView(records:DebugScenario.state=="empty" ? [] : [DiagnosticRecord(id:"a",kind:.crash,received:.now-86_400,json:"{}"),DiagnosticRecord(id:"b",kind:.hang,received:.now-3*86_400,json:"{}")])
        // Delight: `trip` (`-nyx-state weekends`), `constellation` (`-nyx-state empty`), `recap`, `icons`, `first-light`.
        case "trip": TripPlannerView()
        case "constellation": ScrollView { YourSkyPanel(nights:DebugScenario.state=="empty" ? [] : DebugJournal.nights(now:model.today)) { _ in }.padding(24) }.background(NightBackground()).navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
        case "recap": YearRecapView(nights:DebugJournal.nights(now:model.today))
        case "icons": AppIconPicker()
        case "first-light": if let park=model.home { FirstLightView(park:park,night:model.tonight(park),moment:FirstLightDebug.moment(park:park,model:model),leavesOnItsOwn:false) {} }
        // Store art (In-App Event media): the park's computed sky for the night alone, edge to edge,
        // a little brighter than behind text. Same stars, Milky Way, planets and radiant as every screen.
        case "sky": if let park=model.home { RealSky(park:park,night:model.tonight(park),twinkle:pow(Double(model.night(park).score.value)/100,2),strength:0.9).background(Color.black).ignoresSafeArea().toolbarVisibility(.hidden,for:.navigationBar) }
        default: TonightView()
        }
        #else
        TonightView()
        #endif
    }
    /// Opens a park from a reminder, Spotlight, a widget or a link (at a given night, and at What's
    /// up, when the link names one). When another sheet is already up (a journal draft, a
    /// breakdown), the park is presented above it instead of waiting or dismissing it, so nothing
    /// the person was doing is lost.
    private func open(_ parkID:String?,night:(date:Date,whatsUp:Bool)?=nil) {
        guard let parkID,let park=model.park(parkID) else { return }
        launchNight=night
        // This window's own stack: a link or reminder never opens over another iPad window.
        guard let top=commands.topController, top.presentingViewController != nil else { launchParkID=parkID; return }
        let detail=ParkSheet(park:park,initialDate:night?.date,whatsUp:night?.whatsUp ?? false).environment(model).modelContainer(context.container)
        top.present(UIHostingController(rootView:detail),animated:true)
    }
    /// Opens field mode when Control Center, Siri or Shortcuts asked for it: the named park, else
    /// the last park used in the field, else the starting park.
    private func openRequestedField() {
        guard DebugScenario.screen == nil, let request=FieldModeRequest.take() else { return }
        let id=request.parkID ?? SharedSettings.defaults.string(forKey:FieldModeRequest.lastParkKey) ?? model.homeID
        guard let park=model.park(id) ?? model.home else { return }
        FieldPresenter.present(park:park,model:model,from:commands.topController)
    }
    /// A tapped reminder opens the night it announced (a shower reminder at What's up).
    private func openReminder(_ route:ReminderRoute) {
        guard let park=model.park(route.parkID) else { return }
        open(route.parkID,night:route.day.map { ($0.evening(in:park),route.whatsUp) })
    }
    /// Opens the park Spotlight, Siri or a snippet's "Open in Nyx" asked for (`OpenParkIntent`).
    private func openRequestedPark() {
        guard DebugScenario.screen == nil else { return }
        open(ParkOpenRequest.take())
    }
    private static func currentMoonIcon()->Image {
        let moon=AstronomyEngine().moonPhase(at:.now)
        let renderer=ImageRenderer(content:MoonDisc(illumination:moon.illumination,waxing:moon.waxing,iconMode:true).frame(width:24,height:24))
        renderer.scale=3
        return renderer.uiImage.map{Image(uiImage:$0).renderingMode(.template)} ?? Image(systemName:"moon")
    }
    /// The widget, the watch, Siri's park list and reminders follow the saved parks; the work is
    /// the model's (`SavedSkySync`), once per process however many windows are open.
    private func updateSaved() async {
        await model.savedSync.update(model,parkIDs:saved.map(\.parkID))
    }
}
/// A park opened from a reminder, Spotlight or a widget. It reads night vision and Increase
/// Contrast itself, so it matches the app (and follows a Control Center switch) wherever it is
/// presented, including above another sheet.
private struct ParkSheet:View {
    let park:Park
    var initialDate:Date?=nil
    var whatsUp=false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    var body:some View {
        NavigationStack {
            ParkDetailView(park:park,initialDate:initialDate,focusWhatsUp:whatsUp).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() } } }
        }
        .environment(\.nyx,NyxPalette(nightVision:nightVision,highContrast:contrast == .increased)).nyxPresentation().nyxAccessibility()
    }
}
#Preview("Tab shell") { RootView().environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self],inMemory:true) }

/// The moment first light shows in DEBUG scenarios: two hours into true darkness tonight.
enum FirstLightDebug {
    @MainActor static func moment(park:Park,model:PlanModel)->Date {
        let sky=model.night(park).sky
        return (sky.darkStart ?? sky.evening.addingTimeInterval(10*3600)).addingTimeInterval(2*3600)
    }
}
/// iPad screenshot scenarios: `-nyx-narrow` draws the app in a 390-point compact column, as in a
/// narrow window beside another app. (Landscape: `ScreenshotTests` turns the simulator.)
private struct DebugWindow: ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if DebugScenario.isEnabled("narrow") {
            content.environment(\.horizontalSizeClass,.compact).frame(maxWidth:390).frame(maxWidth:.infinity).background(Color(white:0.12).ignoresSafeArea())
        } else { content }
    }
}
private struct DebugTypeSize: ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        // `-nyx-bold` stands in for Bold Text, which the simulator cannot switch from the command line.
        let sized=DebugScenario.isEnabled("ax5") ? AnyView(content.dynamicTypeSize(.accessibility5)) : AnyView(content)
        if DebugScenario.isEnabled("bold") { sized.environment(\.legibilityWeight,.bold) } else { sized }
    }
}
