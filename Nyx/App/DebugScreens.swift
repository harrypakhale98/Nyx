import SwiftUI
import SwiftData

/// DEBUG direct-screen routes and capture fixtures, out of the app shell. `RootView` shows
/// `DebugScreen` for a route that is not a tab, runs `DebugScreens.launch` in its first task and
/// wraps its root in `debugWindows()`. In Release `DebugScenario.screen` is always nil, the launch
/// hook does nothing and the modifier hands the root back unchanged.
struct DebugScreen: View {
    let screen: String
    /// The root's palette: the Assistive Access routes take its night vision.
    let palette: NyxPalette
    @Environment(PlanModel.self) private var model
    var body: some View {
        #if DEBUG

        switch screen {
        // Keyed by the place: a catalogue place named by `-nyx-park` arrives once the catalogue is read
        // (the first park stands in until then), and its page must be its own, asking for its own tile.
        // `-nyx-night 2026-11-02`: the page opens on that night, with the real clock and forecast.
        case "detail": if let park=model.home { ParkDetailView(park:park,initialDate:DebugScenario.text("-nyx-night").flatMap(TripDay.init(iso:)).map { $0.evening(in:park) }).id(park.id) }
        // Saved spot captures: the save sheet (`-nyx-state coordinates` for typed coordinates) and a saved spot's page.
        case "save-spot": NavigationStack { SaveSpotView(source: DebugScenario.state == "coordinates" ? .coordinates : .here) }
        case "spot":
            let spot=Place(spotID:"pin:00000000-0000-4000-8000-0000000000aa",name:"Pullout off Pinto Basin Road",latitude:33.92,longitude:-115.93,
                           timeZoneID:"America/Los_Angeles",countryCode:"US",region:"California")
            ParkDetailView(park:spot).onAppear { model.setSpots(places:[spot]) }
        case "breakdown": if let park=model.home { ScoreBreakdownView(night:model.night(park)).task { await model.refreshForecasts(watching:[park]) } }
        case "editor": JournalEditorView()
        case "entry": JournalDetailView(entry:JournalEntry(date:.now,parkID:model.homeID,notes:"The Milky Way stretched above the ridge. A quiet hour under the stars."))
        case "onboarding": OnboardingView {}
        case "settings": SettingsView()
        case "credits": CreditsView()
        // Learn is no longer a tab: its index as Settings › About the sky pushes it.
        case "learn": LearnView()
        case "places": StartingPointPicker(nearMe:nil) { _ in }
        case "privacy": PrivacyView()
        // Your privacy → Advanced on its own, opened (`-nyx-advanced`).
        case "nps-key": Form { Section { NPSKeyField() } header:{ Text("Advanced") } }.readableForm().navigationTitle("Your privacy").navigationBarTitleDisplayMode(.inline)
        case "data": AboutDataView()
        // "The next six months" for the starting park (`-nyx-park` for another), for audits and captures.
        case "long-view": if let park=model.home { NavigationStack { LongViewPage(park:park) } }
        // "With the lights out" alone, as Tonight shows it from Las Vegas (to Death Valley), for audits and captures.
        case "lights-out": if let dark=model.park("deva") {
            NavigationStack { ScrollView { Panel { LightsOutFigure(target:LightsOut.Target(place:dark,meters:dark.distanceMeters(latitude:36.17,longitude:-115.14),homeClass:8,homeKnown:true,
                                                                                          best:NightPlanner.best(model.nights(dark,from:model.tonight(dark),count:NightPlanner.horizon))),origin:"Las Vegas") }.padding(24) }
                .background(NightBackground(park:dark,night:model.tonight(dark))).navigationTitle(dark.shortName).navigationBarTitleDisplayMode(.inline) }
        }
        // The Sky glow panel (what city light takes, light pollution, Protect this sky) and viewing spots for one park:
        // `-nyx-park deva | grca | sequ`; `-nyx-glow-compare city` opens the illustration on the city's sky (here and on the park page).
        case "light": if let park=model.home { NavigationStack { ScrollView { VStack(spacing:26) { SkyGlowPanel(park:park,comparison:DebugScenario.text("-nyx-glow-compare") == "city" ? .city : .here); Panel { ViewingSpots(park:park) } }.padding(24) }.defaultScrollAnchor(DebugScenario.number("-nyx-scroll").map { UnitPoint(x:0.5,y:$0) } ?? .top).background(NightBackground(park:park,night:model.tonight(park))).navigationTitle(park.shortName).navigationBarTitleDisplayMode(.inline) } }
        case "article": EssayView(essay:Essay(rawValue:DebugScenario.state ?? "") ?? .darkness)
        // Where to stay for one park (`-nyx-park`; `-nyx-state live` loads campgrounds), and From home
        // tonight for the starting point (`-nyx-place "Chicago, IL"`, `-nyx-date`).
        case "stay": if let park=model.home { ScrollView { WhereToStayPanel(park:park).padding(24) }.background(NightBackground(park:park,night:model.tonight(park))).navigationTitle(park.shortName).navigationBarTitleDisplayMode(.inline) }
        case "from-home": if let origin=HomeSky.origin(location:nil,place:model.homePlace,park:model.home) { ScrollView { FromHomePanel(origin:origin,now:model.today).padding(24) }.background(NightBackground()).navigationTitle("Tonight").navigationBarTitleDisplayMode(.inline) }
        case "ask": GuideView(mode:.planning)
        case "widgets": WidgetReviewView(entry:DebugPlatform.widgetEntry(model,large:false)).task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        case "widgets-large": WidgetReviewView(entry:DebugPlatform.widgetEntry(model,large:true),large:true).task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        case "snippet": DebugSnippetView().task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        // About the data with the clearly labelled DEBUG luminance fixture (no real MetricKit report in the simulator).
        case "metric": if DebugScenario.state=="privacy" { PrivacyView().defaultScrollAnchor(.bottom) } else { AboutDataView() }
        case "widgets-xl": WidgetReviewView(entry:DebugPlatform.widgetEntry(model,large:true),extraLarge:true).task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        // 1.1 platform features: inline, the Moon, a closure line, a widget set to one park; iPad's portrait extra-large.
        case "widgets-new": WidgetReviewView(entry:DebugPlatform.widgetEntry(model,large:true),newer:true,moon:MoonEntry(date:.now,park:model.home,nightVision:false)).task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        case "widgets-xl-portrait": WidgetReviewView(entry:DebugPlatform.widgetEntry(model,large:true),portrait:true).task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        case "widgets-step": WidgetReviewView(entry:DebugPlatform.widgetEntry(model,large:true),stepped:true).task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        case "widgets-step-large": WidgetReviewView(entry:DebugPlatform.widgetEntry(model,large:true),steppedLarge:true).task { await model.refreshForecasts(watching:model.home.map { [$0] } ?? []) }
        case "widgets-empty": WidgetReviewView(entry:TonightEntry(date:.now,night:nil,nightVision:false))
        case "skyarc": if let park=model.home { ScrollView { Panel { SkyArc(night:model.night(park),core:model.whatsUp(model.night(park)).core) }.padding(24) }.background(NightBackground(park:park,night:model.tonight(park))) }
        case "whatsup": if let park=model.home { ScrollView { Panel { WhatsUpPanel(whatsUp:model.whatsUp(model.night(park)),notes:model.skyNotes(model.night(park))) }.padding(24) }.background(NightBackground(park:park,night:model.tonight(park))) }
        case "gauge": DebugGaugeSweep()
        case "river": if let park=model.home { let nights=DebugScenario.state=="empty" ? [] : model.nights(park,from:model.tonight(park),count:30); ScrollView { Panel { DebugRiverHost(nights:nights,start:model.tonight(park),outlooks:model.outlooks(nights),markers:model.markers(nights)) }.padding(24) }.background(NightBackground()).task { await model.refreshForecasts(watching:[park]) } }
        case "location-explainer": PermissionExplainer(symbol:"location",title:"Find dark places near you",message:"Nyx compares distances on this iPhone. Your location is never sent to a service.",action:"Use my location") {}
        case "notification-explainer": PermissionExplainer(symbol:"bell",title:"A reminder before a very dark night",message:"Local reminders use complete cloud forecasts. They are estimates, not confirmations of access.",action:"Enable reminders") {}
        case "loader": ConstellationLoader().frame(maxWidth:.infinity,maxHeight:.infinity).background(NightBackground())
        case "field","field-compass": if let park=model.home { DebugField(park:park,model:model,compass:screen=="field-compass") }
        case "live-activity": if let park=model.home { FieldActivityReview(night:model.night(park)) }
        case "alarm-explainer": PermissionExplainer(symbol:"alarm",title:"An alarm for the sky",message:"Nyx can set an alarm on this iPhone for a moment in the night, like the Milky Way's core rising, so you can rest until the sky is ready. Alarms ring through Silent and Focus. Nothing leaves this phone.",action:"Allow alarms") {}
        case "share": if let park=model.home { ShareCardReview(park:park,daysAhead:Int(DebugScenario.number("-nyx-share-night") ?? 0)) }
        case "listen": if let park=model.home { ScrollView { Panel { NightListenView(night:model.night(park),expanded:true) }.padding(24) }.background(NightBackground(park:park,night:model.tonight(park))).navigationTitle(park.shortName).navigationBarTitleDisplayMode(.inline) }
        case "accessibility": SoundAndTouchView()
        // The Assistive Access scene's root, for captures (the simulator cannot switch Assistive Access on),
        // with that scene's own palette and red (the brighter one); the root's filter skips these routes.
        case "assistive": AssistiveHome().modifier(AssistiveReview(nightVision:palette.nightVision))
        case "assistive-tonight": AssistiveTonight().modifier(AssistiveReview(nightVision:palette.nightVision))
        case "assistive-saved": AssistiveSaved().modifier(AssistiveReview(nightVision:palette.nightVision))
        // Settings → Support → Diagnostics, with two illustrative reports (`-nyx-state empty` for none).
        case "diagnostics": DiagnosticsView(records:DebugScenario.state=="empty" ? [] : [DiagnosticRecord(id:"a",kind:.crash,received:.now-86_400,json:"{}"),DiagnosticRecord(id:"b",kind:.hang,received:.now-3*86_400,json:"{}")])
        // Delight: `trip` (`-nyx-state weekends`), `constellation` (`-nyx-state empty`), `recap`, `icons`, `first-light`.
        case "trip": TripPlannerView().navigationTitle("Nights I can go").navigationBarTitleDisplayMode(.inline)
        case "constellation": ScrollView { YourSkyPanel(nights:DebugScenario.state=="empty" ? [] : DebugJournal.nights(now:model.today)) { _ in }.padding(24) }.background(NightBackground()).navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
        case "recap": YearRecapView(nights:DebugJournal.nights(now:model.today))
        case "icons": AppIconPicker()
        case "first-light": if let park=model.home { FirstLightView(park:park,night:model.tonight(park),moment:FirstLightDebug.moment(park:park,model:model)) {} }
        // Store art (In-App Event media): the park's computed sky for the night alone, edge to edge,
        // a little brighter than behind text. Same stars, Milky Way, planets and radiant as every screen.
        case "sky": if let park=model.home { RealSky(park:park,night:model.tonight(park),twinkle:pow(Double(model.night(park).score.value)/100,2),strength:0.9).background(Color.black).ignoresSafeArea().toolbarVisibility(.hidden,for:.navigationBar) }
        default: TonightView()
        }
        #else
        TonightView()
        #endif
    }
}
@MainActor enum DebugScreens {
    /// Once the root's first task runs: the fixtures a capture asked for.
    static func launch(model:PlanModel,context:ModelContext,commands:SceneCommands) {
        #if DEBUG
        DebugFollowing.install(model)
        DebugHeaderExport.runIfRequested(model)
        DebugPromoExport.runIfRequested(model)
        // `-nyx-journal-revisit`: leave the Journal after 5 s and come back a second later, so a
        // capture can show that the figures do not draw themselves again.
        if DebugScenario.isEnabled("journal-revisit") {
            Task { try? await Task.sleep(for:.seconds(5)); commands.tab = .tonight; try? await Task.sleep(for:.seconds(1)); commands.tab = .journal }
        }
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
            // `-nyx-star-new 4`: one more night recorded that many seconds in, as a save from the editor
            // would, so the real arrival path (watcher, constellation, spring) can be captured mid-flight.
            if let delay=DebugScenario.number("-nyx-star-new") {
                Task { try? await Task.sleep(for:.seconds(delay)); context.insert(JournalEntry(date:.now-10*day,parkID:"arch",observedBortle:2,notes:"")); try? context.save() }
            }
        }
        #endif
    }
}
extension View {
    /// iPad window captures (`-nyx-narrow`, `-nyx-window`, `-nyx-open-window`); the view itself in Release.
    @ViewBuilder func debugWindows()->some View {
        #if DEBUG
        modifier(DebugWindow()).modifier(DebugOpenParkWindow())
        #else
        self
        #endif
    }
}

/// The moment first light shows in DEBUG scenarios: two hours into true darkness tonight.
enum FirstLightDebug {
    @MainActor static func moment(park:Park,model:PlanModel)->Date {
        let sky=model.night(park).sky
        return (sky.darkStart ?? sky.evening.addingTimeInterval(10*3600)).addingTimeInterval(2*3600)
    }
}
/// DEBUG captures: `-nyx-ax5` and `-nyx-bold`, on the root and on the full-screen sky (a cover does not inherit them).
struct DebugTypeSize: ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        #if DEBUG
        // `-nyx-bold` stands in for Bold Text, which the simulator cannot switch from the command line.
        let sized=DebugScenario.isEnabled("ax5") ? AnyView(content.dynamicTypeSize(.accessibility5)) : AnyView(content)
        if DebugScenario.isEnabled("bold") { sized.environment(\.legibilityWeight,.bold) } else { sized }
        #else
        // Release: both switches are always off, so the app's root is never type-erased.
        content
        #endif
    }
}
#if DEBUG
/// iPad screenshot scenarios: `-nyx-narrow` draws the app in a 390-point compact column, as in a
/// narrow window beside another app. (Landscape: `ScreenshotTests` turns the simulator.)
private struct DebugWindow: ViewModifier {
    /// The simulated window's origin on screen, for the stand-in fold (`debugWindowOrigin`).
    @State private var origin:CGPoint?
    @ViewBuilder func body(content:Content)->some View {
        if DebugScenario.isEnabled("narrow") {
            content.environment(\.horizontalSizeClass,.compact).frame(maxWidth:390).frame(maxWidth:.infinity).background(Color(white:0.12).ignoresSafeArea())
        } else if let window=DebugScenario.window {
            // iPhone Duo's inner display on an iPad simulator: regular both ways, at the display's size.
            content.environment(\.horizontalSizeClass,.regular).environment(\.verticalSizeClass,.regular)
                .environment(\.debugWindowOrigin,origin).frame(width:window.width,height:window.height).clipped()
                .onGeometryChange(for:CGPoint.self) { $0.frame(in:.global).origin } action:{ origin=$0 }
                .frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(white:0.12).ignoresSafeArea())
        } else { content }
    }
}
/// DEBUG captures: `-nyx-open-window deva` opens that park in a window of its own once the app is
/// up, as "Open in New Window" would.
private struct DebugOpenParkWindow: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    func body(content:Content)->some View {
        content.task {
            guard multipleWindows, let id=DebugScenario.text("-nyx-open-window") else { return }
            try? await Task.sleep(for:.seconds(2))
            openWindow(value:ParkWindow(parkID:id))
        }
    }
}
/// The `assistive*` capture routes: the Assistive Access scene's palette (high contrast) and its own
/// night-vision filter with that palette's brighter red, as `AssistiveAccessRoot` applies them.
private struct AssistiveReview: ViewModifier {
    let nightVision: Bool
    func body(content:Content)->some View {
        let palette=NyxPalette(nightVision:nightVision,highContrast:true)
        return content.environment(\.nyx,palette).modifier(NightVisionFilter(enabled:nightVision,red:palette.red))
    }
}
#endif
