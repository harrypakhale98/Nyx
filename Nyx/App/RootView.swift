import SwiftUI
import SwiftData
import WidgetKit
import TipKit
import CoreSpotlight

struct RootView:View {
    @Environment(PlanModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.legibilityWeight) private var legibility
    @Query private var saved:[SavedPark]
    /// The person's own spots, handed to the model before anything resolves a saved `pin:` id.
    @Query private var spots:[SavedSpot]
    @Environment(\.modelContext) private var context
    @AppStorage("onboardingComplete") private var onboarded=false
    @AppStorage(NightLook.nightVisionKey,store:SharedSettings.defaults) private var nightVision=false
    @AppStorage(NightTint.key,store:SharedSettings.defaults) private var brighterRed=false
    /// Night vision At dusk (`NightVisionDusk`): followed while this window is active, never in the background.
    @AppStorage(NightVisionMode.atDuskKey,store:SharedSettings.defaults) private var atDusk=false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// This window's tab and keyboard commands (each iPad window has its own).
    @State private var commands=SceneCommands()
    /// This window's tab, restored with the window (each iPad window keeps its own).
    @SceneStorage("tab") private var savedTab=0
    @State private var intro=false
    /// Cold launch: the launch screen's starfield paints first, then the app settles in.
    /// Never blocks input; skipped under Reduce Motion and in screenshot scenarios.
    @State private var revealed=DebugScenario.screen != nil
    /// The launch reveal has (logically) landed: Tonight's first count plays after it, not under it.
    @State private var launchSettled=DebugScenario.screen != nil
    /// The park a link, reminder or Spotlight opened, with its night: one value, so a later link
    /// presented above it never changes the night on this sheet.
    @State private var launch:LaunchPark?
    /// First light's park, while the sky reveals itself over the app.
    @State private var firstLight:Park?
    /// DEBUG promo capture (`-nyx-promo-hold 2`): Tonight's first count waits that many seconds after
    /// launch, so a recording sees it from zero on a settled screen. Always false in Release.
    @State private var promoHold=DebugScenario.number("-nyx-promo-hold") != nil
    /// The Tonight tab icon is today's real moon phase, drawn just after the first frame (the tab
    /// bar is still fading in) and again whenever Nyx returns.
    @State private var moonIcon=Image(systemName:AppTab.tonight.symbol)
    /// The launch's own update of the saved parks has run: until then, becoming active (which
    /// also happens at launch) leaves it to that one rather than publishing twice.
    @State private var launchPublished=false
    /// The night-vision lamp's black cover (0 clear, 1 black), where it is heading, and its run.
    @State private var lampCover=0.0
    @State private var lampMotion=NightVisionLamp.Cover()
    @State private var lampTask:Task<Void,Never>?
    /// Where the lamp's dark grows from (the switch), while it grows; nil for an even fade.
    @State private var lampOrigin:CGPoint?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @Environment(\.dynamicTypeSize) private var typeSize
    /// This window's place among the windows a tapped reminder may open in (`NotificationRouter`).
    @State private var routerID=UUID()
    /// The tab bar recedes as a page scrolls down and returns on the way up, except where a bar that
    /// moves would cost someone their place: VoiceOver, Switch Control and accessibility text sizes.
    private var tabBarMinimize:TabBarMinimizeBehavior {
        voiceOver || switchControl || typeSize.isAccessibilitySize || DebugScenario.isEnabled("ax5") ? .never : .onScrollDown
    }

    private var palette:NyxPalette { NyxPalette(nightVision:nightVision || DebugScenario.state=="night-vision" || DebugScenario.isEnabled("night-vision"),highContrast:contrast == .increased || DebugScenario.isEnabled("contrast"),brighterRed:brighterRed || DebugScenario.isEnabled("brighter-red"),boldText:legibility == .bold || DebugScenario.isEnabled("bold")) }
    var body:some View {
        Group {
            if model.loadError { CalmState(symbol:"moon",title:"The park library could not open",message:"Close and reopen Nyx. Your saved nights remain on this iPhone.").background(Color.black) }
            else if let screen=DebugScenario.screen,AppTab(route:screen) == nil {
                NavigationStack { DebugScreen(screen:screen,palette:palette) }
            } else {
                ZStack {
                // Removed once revealed, so its sky stops animating and sensing tilt behind the tabs.
                if !revealed { NightBackground().transition(.opacity) }
                // Four tabs: where (Tonight, Parks), when (Plan: the month, or the nights you are free),
                // and remember (Journal). Learn lives in Settings › About the sky and beside the sky it explains.
                // Each tab's content is tinted starlight (back buttons, menus, links, the close and done
                // buttons); only the selected tab below is amber, as the place you are.
                TabView(selection:$commands.tab) {
                    Tab(value:AppTab.tonight) { NavigationStack { TonightView() }.modifier(TabChrome(tab:.tonight,tint:palette.ink)) } label:{ Label { Text(AppTab.tonight.title) } icon:{ moonIcon } }
                    // Parks becomes a list beside the park on a wide iPad; a stack in narrow windows and on iPhone.
                    Tab(AppTab.parks.title,systemImage:AppTab.parks.symbol,value:.parks) { ParksTab().modifier(TabChrome(tab:.parks,tint:palette.ink)) }
                    Tab(AppTab.plan.title,systemImage:AppTab.plan.symbol,value:.plan) { NavigationStack { PlanView() }.modifier(TabChrome(tab:.plan,tint:palette.ink)) }
                    Tab(AppTab.journal.title,systemImage:AppTab.journal.symbol,value:.journal) { NavigationStack { JournalView() }.modifier(TabChrome(tab:.journal,tint:palette.ink)) }
                        // A night from Plan's month or a park held over the Journal's tab item or sidebar
                        // row opens the Journal, which takes the drop (`acceptsJournalDrop`). The tab item itself
                        // takes none: SwiftUI's tab drop destination did not fire on iPadOS 26 or 27.
                        .springLoadingBehavior(.enabled)
                }
                // A tab bar on iPhone; on iPad a tab bar that opens into a sidebar.
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(tabBarMinimize)
                // Content fades under the bars on every release: iOS 27's automatic edge is hard (a grey band
                // under the park page's picker, rows at full brightness under the tab bar), iOS 26's soft.
                .scrollEdgeEffectStyle(.soft,for:.all)
                // A followed night under way: a strip above the tabs that opens field mode (iOS 26.1).
                .modifier(NightInProgressAccessory { id in withPlace(id) { FieldPresenter.present(park:$0,model:model,from:commands.topController) } })
                .tint(commands.sidebar ? palette.selectionTint : palette.accent)
                .tabViewSidebarHeader { Text(verbatim:"Nyx").font(.system(.title2,design:.serif)).foregroundStyle(palette.ink).accessibilityAddTraits(.isHeader) }
                .opacity(revealed ? 1 : 0).scaleEffect(revealed ? 1 : 0.97)
                // Tonight's first answer waits for the person: not behind onboarding (from the first
                // frame, before the sheet rises) or first light, and not until the launch reveal has
                // landed, so the count never runs under the tabs' own fade-in. Swiping the sheet away releases it too.
                .environment(\.nyxRevealHeld,(!onboarded && DebugScenario.screen == nil) || intro || firstLight != nil || promoHold || !launchSettled)
                }
            }
        }
        // The first save offers reminders; the first journal entry may ask for a rating.
        .background(MomentsWatcher())
        .environment(commands).focusedSceneValue(commands)
        .background(WindowSceneReader(commands:commands).frame(width:0,height:0).accessibilityHidden(true))
        .environment(\.nyx,palette).environment(\.nyxReduceMotion,DebugScenario.isEnabled("reduce-motion")).environment(\.skyHome,model.home)
        .foregroundStyle(palette.ink,palette.muted,palette.muted).tint(palette.ink).preferredColorScheme(.dark)
        // The DEBUG field routes draw field mode inside the root, so the root hides the status bar for them as
        // presented field mode does (the root's own preference would otherwise win over the field view's).
        .statusBarHidden(palette.nightVision || ["field","field-compass"].contains(DebugScenario.screen ?? ""))
        .modifier(DebugTypeSize())
        .debugWindows()
        // Field mode draws its own red; filtering it twice would darken it below legible contrast.
        .modifier(NightVisionFilter(enabled:palette.nightVision && !["field","field-compass","assistive","assistive-tonight","assistive-saved"].contains(DebugScenario.screen ?? ""),red:palette.red))
        // The lamp turns the palette under its cover, at once; every other path (Control Center, Siri, a
        // Focus, onboarding) crossfades on the shared spring, and Reduce Motion on its short dissolve:
        // a colour change with nothing moving, never a cut of the whole screen.
        .animation(lampCover>0 ? nil : NyxMotion.spring(reduced:systemReduceMotion || DebugScenario.isEnabled("reduce-motion")),value:palette.nightVision)
        .overlay { LampCover(cover:lampCover,origin:lampOrigin).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true) }
        .onChange(of:commands.lampRequest) { _,request in if let request { runLamp(request.on,announce:request.announce,origin:request.origin) } }
        // One soft tap at the turn, on every path (the lamp writes the setting under its cover), however
        // many switches are loaded: each visited tab's toolbar and onboarding have one.
        .sensoryFeedback(.impact(flexibility:.soft,intensity:0.7),trigger:nightVision)
        .sheet(isPresented:$intro,onDismiss:{ onboarded=true }) { OnboardingView { onboarded=true;intro=false }.nyxPresentation().environment(\.nyx,palette) }
        .sheet(item:$launch) { launch in ParkSheet(park:launch.park,initialDate:launch.night,whatsUp:launch.whatsUp,commands:commands) }
        .overlay { if let park=firstLight { FirstLightView(park:park,night:model.tonight(park),moment:DebugScenario.screen == nil ? .now : FirstLightDebug.moment(park:park,model:model)) { firstLight=nil }.environment(\.nyx,palette).modifier(DebugTypeSize()).modifier(NightVisionFilter(enabled:palette.nightVision,red:palette.red)) } }
        .onAppear { LaunchSignposts.firstFrame() }
        .onAppear { if DebugScenario.screen == nil, let tab=AppTab(rawValue:savedTab) { commands.tab=tab } }
        // A location found is a starting point chosen, from whichever screen asked (Tonight or Plan).
        .onChange(of:model.location.latitude != nil) { _,found in if found, DebugScenario.screen == nil { model.startChosen=true } }
        .onChange(of:commands.tab) { _,tab in savedTab=tab.rawValue }
        // Field mode can open from Tonight or Control Center before any park page has appeared; its dawn
        // "Keep this night" needs the journal's store.
        .onAppear { KeepThisNight.container=context.container }
        .task {
            // First: links, reminders and the saved-place update below resolve spots through the model.
            model.setSpots(spots)
            moonIcon=RootView.currentMoonIcon()
            model.savedSync.palette=palette
            NotificationRouter.shared.connect(routerID) { route in openReminder(route) }
            if let screen=DebugScenario.screen { commands.tab=AppTab(route:screen) ?? .tonight }
            DebugScreens.launch(model:model,context:context,commands:commands)
            if let hold=DebugScenario.number("-nyx-promo-hold") { Task { try? await Task.sleep(for:.seconds(hold)); promoHold=false } }
            intro = !onboarded && DebugScenario.screen == nil
            if systemReduceMotion || DebugScenario.isEnabled("reduce-motion") { revealed=true; launchSettled=true }
            else {
                withAnimation(NyxMotion.launch,completionCriteria:.logicallyComplete) { revealed=true } completion:{ launchSettled=true }
                // The dial starts its count as the tabs finish arriving (about nine tenths there), so the
                // launch and the score read as one motion rather than two in a row.
                Task { try? await Task.sleep(for:.seconds(NyxMotion.launchSettle)); launchSettled=true }
            }
            openRequestedField(); openRequestedPark()
            // Every park's week, worked out off the main thread once the first frame is up, so Parks opens ready.
            Task(priority:.utility) { await model.prepareNights(model.parks,count:7) }
            if let link=DebugScenario.link { try? await Task.sleep(for:.seconds(1)); handle(DeepLink(link)) }
            if DebugScenario.screen == nil { firstLight=await FirstLightWatcher.check(model:model) }
            if DebugScenario.screen == nil { LuminanceProof.shared.start(); try? await SpotlightIndexer.indexIfNeeded(model.parks);await model.savedSync.update(model,saved:saved,spots:spots) }
            launchPublished=true
        }
        .onChange(of:scenePhase) { _,phase in
            // Ask iOS for the next background refresh whenever Nyx leaves the screen.
            if phase == .background, DebugScenario.screen == nil {
                SavedSkySync.scheduleRefresh()
                // Journals opened from other apps are copied into Documents/Inbox; ones left behind
                // by an import cut short are cleared, keeping one still waiting to be imported and
                // one being imported right now.
                let waiting=[model.journalFile,model.importingJournal].compactMap { $0 }
                Task.detached(priority:.utility) { JournalInbox.sweep(keeping:waiting) }
            }
            if phase == .active {
            // The window used last opens a tapped reminder, never one closed since.
            NotificationRouter.shared.connect(routerID) { route in openReminder(route) }
            model.tick(); moonIcon=RootView.currentMoonIcon()
            if launchPublished { Task { await model.savedSync.update(model,saved:saved,spots:spots) } }
            if firstLight == nil { Task { if let park=await FirstLightWatcher.check(model:model) { firstLight=park } } }
            openRequestedField(); openRequestedPark()
            // The night's Live Activity catches up (or ends at dawn) whenever Nyx is opened.
            if DebugScenario.screen == nil { Task { await FieldActivities.refresh(nightVision:nightVision) } }
        } }
        .onDisappear { NotificationRouter.shared.disconnect(routerID) }
        .onReceive(NotificationCenter.default.publisher(for:FieldModeRequest.notification)) { _ in openRequestedField() }
        .onReceive(NotificationCenter.default.publisher(for:ParkOpenRequest.notification)) { _ in openRequestedPark() }
        // At dusk: looked at again whenever the choice, the switch, the starting point or the window's
        // state changes, then at each dusk and dawn while Nyx is open.
        .task(id:DuskWatch(atDusk:atDusk,on:nightVision,active:scenePhase == .active,place:NightVisionDusk.place(model).map { [$0.park.latitude,$0.park.longitude] })) { await followDusk() }
        .task {
            // Keep "tonight" honest on a screen left open through sunrise.
            while !Task.isCancelled { try? await Task.sleep(for:.seconds(300)); model.tick() }
        }
        .onChange(of:palette.nightVision) { _,_ in model.savedSync.palette=palette }
        .onChange(of:nightVision) { _,on in
            // Keep the Control Center toggle and widgets in step with the switch, wherever it was flipped
            // (in Nyx, Control Center, a Focus or field mode).
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadControls(ofKind:"NightVisionControl")
            // The watch hears the parks the widget has, never the empty list of a store that could not open.
            model.savedSync.pushWatch(model)
            // A followed night on the Lock Screen changes colour with the app.
            if DebugScenario.screen == nil { Task { await FieldActivities.refresh(nightVision:on) } }
        }
        // Widgets, a followed night and the watch draw their red from the same choice (`NightLook`, `WatchContext.brighterRed`).
        .onChange(of:brighterRed) { _,_ in
            WidgetCenter.shared.reloadAllTimelines()
            model.savedSync.pushWatch(model)
            if DebugScenario.screen == nil { Task { await FieldActivities.refresh(nightVision:nightVision) } }
        }
        // The saved parks and spots, the starting park and the reminder switches: the widgets' snapshot,
        // the watch and reminders follow each change, as in Assistive Access (`savedUpkeep`).
        .savedUpkeep(saved:saved,spots:spots)
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            withPlace(activity.userInfo?[CSSearchableItemActivityIdentifier] as? String) { open($0) }
        }
        // A park and night handed off from park detail on another iPhone or iPad.
        .onContinueUserActivity(ParkHandoff.type) { activity in
            guard let handoff=ParkHandoff(userInfo:activity.userInfo) else { return }
            withPlace(handoff.parkID) { park in
                // A night that has passed since it was handed off opens tonight instead.
                open(park,night:handoff.evening(in:park).flatMap { LaunchPark.night($0,tonight:model.tonight(park),whatsUp:false) })
            }
        }
        .onOpenURL { url in
            // A journal export opened from Files: the Journal tab offers to import it.
            if url.isFileURL, url.pathExtension.lowercased() == JournalArchive.fileExtension { commands.tab = .journal; model.journalFile=url; return }
            handle(DeepLink(url))
        }
        // Differentiate Without Color, Reduce Highlighting, Cross-Fade, reduced resources: read once, for every screen and sheet.
        .nyxAccessibility()
    }
    /// The toolbar switch's lamp: down to black over the rest of ~0.2 s, the palette turned under the
    /// cover with one soft tap and the state announced (unless VoiceOver was on the switch, which says
    /// its own value), then revealed on the shared spring. From a clear window the dark grows as a
    /// circle from the switch (`LampCover`), reaching every corner by the same moment the even fade
    /// would be black. A tap that lands mid-way starts again from wherever the cover is, toward the
    /// state now asked for, in the cover's present shape.
    private func runLamp(_ on:Bool,announce:Bool,origin:CGPoint?) {
        lampTask?.cancel()
        lampTask=Task { @MainActor in
            if on != nightVision {
                let now=Date.now, time=NightVisionLamp.dimTime(from:lampMotion.value(at:now))
                // The circle only from a clear window: a cover already partly down keeps its shape.
                if lampMotion.value(at:now)<=0.001 { lampOrigin=origin }
                lampMotion=NightVisionLamp.Cover(from:lampMotion.value(at:now),to:1,start:now,duration:time)
                withAnimation(.easeIn(duration:time)) { lampCover=1 }
                try? await Task.sleep(for:.seconds(time))
                guard !Task.isCancelled else { return }
                var quiet=Transaction(); quiet.disablesAnimations=true
                // Wholly black either way now; the reveal is the even fade.
                withTransaction(quiet) { nightVision=on; lampOrigin=nil }
                if announce { NightVisionLamp.announce(on) }
            }
            let start=Date.now
            lampMotion=NightVisionLamp.Cover(from:lampMotion.value(at:start),to:0,start:start,duration:NightVisionLamp.reveal)
            withAnimation(NyxMotion.spring) { lampCover=0 }
            try? await Task.sleep(for:.seconds(NightVisionLamp.reveal))
            guard !Task.isCancelled else { return }
            commands.lampTarget=nil; lampOrigin=nil
        }
    }
    /// What At dusk's watch depends on: a change to any of these looks at the Sun again.
    private struct DuskWatch:Equatable { let atDusk:Bool; let on:Bool; let active:Bool; let place:[Double]? }
    /// At dusk while this window is active: the switch is set now, then again at the next dusk or
    /// dawn (at most 15 minutes apart, so a changed clock or time zone catches up). The palette turns
    /// on the root's crossfade on the shared spring, with the soft tap, as Control Center's does;
    /// VoiceOver hears it, since nothing on screen was touched. Captures leave the switch alone.
    private func followDusk() async {
        guard atDusk, scenePhase == .active, DebugScenario.screen == nil else { return }
        while !Task.isCancelled {
            guard let result=NightVisionDusk.apply(model) else { return }
            // Writing the switch changes this task's id, which starts it again and cancels this one.
            if result.changed { NightVisionLamp.announce(result.plan.on) }
            let wait=min(900,max(1,(result.plan.next?.timeIntervalSinceNow ?? 900)+1))
            try? await Task.sleep(for:.seconds(wait))
        }
    }
    /// Widgets, Spotlight, Live Activities, calendar events Nyx drafted and In-App Events all land here.
    private func handle(_ link:DeepLink?) {
        switch link {
        case .park(let id): withPlace(id) { open($0) }
        case .parkNight(let id,let day): withPlace(id) { open($0,night:LaunchPark.night(day.evening(in:$0),tonight:model.tonight($0),whatsUp:false)) }
        case .tonight: commands.tab = .tonight
        case .field(let id): withPlace(id) { FieldPresenter.present(park:$0,model:model,from:commands.topController) }
        case .whatsUp(let id,let day): withPlace(id) { open($0,night:LaunchPark.night(day.evening(in:$0),tonight:model.tonight($0),whatsUp:true)) }
        case .calendar(let id,let year,let month):
            withPlace(id) { _ in commands.tab = .plan; commands.calendarRequest=CalendarRequest(parkID:id,year:year,month:month) }
        case nil: break
        }
    }
    /// Opens a park from a reminder, Spotlight, a widget or a link (at a given night, and at What's
    /// up, when the link names one). When another sheet is already up (a journal draft, a
    /// breakdown), the park is presented above it instead of waiting or dismissing it, so nothing
    /// the person was doing is lost.
    private func open(_ park:Park,night:(date:Date,whatsUp:Bool)?=nil) {
        // This window's own stack: a link or reminder never opens over another iPad window.
        guard let top=commands.topController, top.presentingViewController != nil else { launch=LaunchPark(park:park,night:night?.date,whatsUp:night?.whatsUp ?? false); return }
        let detail=ParkSheet(park:park,initialDate:night?.date,whatsUp:night?.whatsUp ?? false,commands:commands).environment(model).modelContainer(context.container)
        top.present(UIHostingController(rootView:detail),animated:true)
    }
    /// Opens field mode when Control Center, Siri or Shortcuts asked for it: the named place and no
    /// other (a place abroad on a cold launch once the catalogue is read); with none named, the last
    /// place used in the field, else the starting place.
    private func openRequestedField() {
        guard DebugScenario.screen == nil, let request=FieldModeRequest.take() else { return }
        let show:(Park)->Void={ FieldPresenter.present(park:$0,model:model,from:commands.topController) }
        if let id=request.parkID { withPlace(id,show); return }
        let last=SharedSettings.defaults.string(forKey:FieldModeRequest.lastParkKey)
        Task { if let park=await model.usualFieldPlace(lastUsed:last) { show(park) } }
    }
    /// A tapped reminder opens the night it announced (a shower reminder at What's up).
    private func openReminder(_ route:ReminderRoute) {
        withPlace(route.parkID) { park in open(park,night:route.day.flatMap { LaunchPark.night($0.evening(in:park),tonight:model.tonight(park),whatsUp:route.whatsUp) }) }
    }
    /// Opens the park Spotlight, Siri or a snippet's "Open in Nyx" asked for (`OpenParkIntent`),
    /// or the Tonight tab when the Tonight control was tapped before any park was saved.
    private func openRequestedPark() {
        guard DebugScenario.screen == nil, let request=ParkOpenRequest.take() else { return }
        guard let id=request.parkID else { commands.tab = .tonight; return }
        // A night the best-night card named opens as a widget's link to that night does.
        if let day=request.night.flatMap(TripDay.init(iso:)) { handle(.parkNight(park:id,day:day)) } else { withPlace(id) { open($0) } }
    }
    /// Every route from outside (links, widgets, reminders, Spotlight, Handoff, Siri) finds its place
    /// here: at once when it is known; a place abroad named on a cold launch, before the world catalogue
    /// is read, once it is (`PlanModel.place(named:)`). An id Nyx does not know opens nothing, never another place.
    private func withPlace(_ id:String?,_ act:@escaping (Park)->Void) {
        guard let id else { return }
        if let park=model.park(id) { act(park); return }
        guard model.awaitsCatalog(id) else { return }
        Task { if let park=await model.place(named:id) { act(park) } }
    }
    private static func currentMoonIcon()->Image {
        let moon=AstronomyEngine().moonPhase(at:.now)
        let renderer=ImageRenderer(content:MoonDisc(illumination:moon.illumination,waxing:moon.waxing,iconMode:true).frame(width:24,height:24))
        renderer.scale=3
        return renderer.uiImage.map{Image(uiImage:$0).renderingMode(.template)} ?? Image(systemName:"moon")
    }
}
/// What a link, reminder or Spotlight asked the main window to open: the park, the night, and
/// whether to scroll to What's up. Its identity is all three, so a different night is a new sheet.
struct LaunchPark: Identifiable, Equatable {
    let park:Park
    var night:Date?=nil
    var whatsUp=false
    var id:String { "\(park.id)|\(night?.timeIntervalSince1970 ?? 0)|\(whatsUp)" }
    /// The night a link, reminder or Handoff names, while it is still ahead: one already past opens
    /// tonight instead (at What's up, when that was asked for), as a restored park window does.
    nonisolated static func night(_ evening:Date,tonight:Date,whatsUp:Bool)->(date:Date,whatsUp:Bool)? {
        if evening>=tonight { return (evening,whatsUp) }
        return whatsUp ? (tonight,true) : nil
    }
}
/// A park opened from a reminder, Spotlight or a widget. It reads night vision and Increase
/// Contrast itself, so it matches the app (and follows a Control Center switch) wherever it is
/// presented, including above another sheet. It carries the window's commands as a layer of its
/// own (`SceneCommands.layer`), so ⌘R, ⌘← ⌘→ and ⌘⇧N reach the page on top and never the one under it.
private struct ParkSheet:View {
    let park:Park
    var initialDate:Date?=nil
    var whatsUp=false
    let commands:SceneCommands
    @State private var layer=SceneCommands.newLayer()
    @Environment(PlanModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.legibilityWeight) private var legibility
    @AppStorage(NightLook.nightVisionKey,store:SharedSettings.defaults) private var nightVision=false
    @AppStorage(NightTint.key,store:SharedSettings.defaults) private var brighterRed=false
    var body:some View {
        NavigationStack {
            ParkDetailView(park:park,initialDate:initialDate,focusWhatsUp:whatsUp).toolbar { ToolbarItem(placement:.cancellationAction) { Button(role:.close) { dismiss() } } }.environment(\.parkInSheet,true)
        }
        .environment(\.nyxTab,layer).environment(commands).environment(\.skyHome,model.home)
        .onAppear { commands.layer(layer,shown:true) }
        .onDisappear { commands.layer(layer,shown:false) }
        // The palette goes outside the presentation's style, which reads it to redden the whole sheet.
        .nyxPresentation().nyxAccessibility().environment(\.nyx,NyxPalette(nightVision:nightVision,highContrast:contrast == .increased,brighterRed:brighterRed,boldText:legibility == .bold))
    }
}
#Preview("Tab shell") { RootView().environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true) }
