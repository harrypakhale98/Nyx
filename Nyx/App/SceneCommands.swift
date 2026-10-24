import SwiftUI

/// One window's keyboard and menu-bar commands (iPad, or an iPhone with a keyboard). Each window
/// owns one, so ⌘2 in one window never moves another; the menu bar reaches the focused window's
/// through `focusedSceneValue`.
@MainActor @Observable final class SceneCommands {
    /// The tabs in order, for ⌘1–⌘4.
    static let tabs:[LocalizedStringKey]=["Tonight","Parks","Plan","Journal"]
    /// A screenshot route's tab: `calendar` and `plan` are both Plan; `parks-map` is Parks showing its map. Nil for routes that are not tabs.
    nonisolated static func tabIndex(_ route:String)->Int? { ["tonight":0,"going":0,"parks":1,"parks-map":1,"calendar":2,"plan":2,"best":2,"journal":3][route] }
    var tab=0
    /// A park's own window (`ParkWindow`): one page, no tabs, so the tab keys and Find a Park rest.
    let parkWindow:Bool
    init(parkWindow:Bool=false) { self.parkWindow=parkWindow }
    /// The park whose page is on screen in each tab, for ⌘⇧N (`ReportsVisiblePark`).
    private(set) var visibleParks:[Int:String]=[:]
    /// The park on screen in this window's current tab, if any.
    var visiblePark:String? { visibleParks[current] }
    /// Park pages presented over this window (from a link or a reminder), the top one last. Each is
    /// a layer with a tab number of its own (`newLayer`), so while one is up the keys reach its page
    /// and never the tab's page under it.
    private(set) var layers:[Int]=[]
    func layer(_ id:Int,shown:Bool) {
        var next=layers.filter { $0 != id }
        if shown { next.append(id) }
        if next != layers { layers=next }
    }
    /// A layer's number: past every tab's, and never the same twice.
    static func newLayer()->Int { nextLayer+=1; return nextLayer }
    private static var nextLayer=100
    func show(park id:String,tab:Int?) { if let tab { visibleParks[tab]=id } }
    func hide(park id:String,tab:Int?) { if let tab, visibleParks[tab]==id { visibleParks[tab]=nil } }
    /// A park's month asked of this window's Plan tab (a `nyx://calendar` link, "Show in Plan",
    /// a park dropped on Plan). Per window, so a request in one iPad window never moves another's Plan.
    var calendarRequest:CalendarRequest?
    /// Bumped to close this window's Settings sheet, so a link from Learn shows where it leads.
    var closeSettings=0
    /// This window's scene, so a park or field mode opened from a link, a reminder or a menu is
    /// presented in the window that asked, never in whichever window happens to be key.
    @ObservationIgnored weak var windowScene:UIWindowScene?
    /// The top of this window's presentation stack (else the key window's, before the scene is known).
    var topController:UIViewController? { Self.top(in:windowScene) }
    /// The top of a scene's presentation stack; without a scene, the key window's.
    static func top(in scene:UIWindowScene?)->UIViewController? {
        let windows=scene?.windows ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard var top=(windows.first(where:\.isKeyWindow) ?? windows.first)?.rootViewController else { return nil }
        while let next=top.presentedViewController { top=next }
        return top
    }
    /// Whether the tabs stand in an iPad sidebar, where the selected row is white text on the tint.
    var sidebar=false
    /// Night vision asked of this window's toolbar switch: `RootView` dims the window to black,
    /// turns the palette under the cover and reveals it (`NightVisionLamp`). Each tap is a new request.
    private(set) var lampRequest:NightVisionLamp.Request?
    /// The state the switch shows while the lamp runs, so it answers the tap at once; nil at rest.
    var lampTarget:Bool?
    /// `origin`: where the switch is in the window, which the lamp's dark grows from; nil dims evenly.
    func requestNightVision(_ on:Bool,announce:Bool=true,origin:CGPoint?=nil) {
        lampTarget=on
        lampRequest=NightVisionLamp.Request(id:(lampRequest?.id ?? 0)+1,on:on,announce:announce,origin:origin)
    }
    /// Bumped by ⌘F: the Parks list focuses its search field.
    private(set) var searchRequest=0
    /// ⌘← and ⌘→: the night view showing on the current tab moves one night.
    private(set) var step:NightStep?
    /// A ⌘F not yet answered: the Parks list may not exist until its tab first opens.
    private var searchPending=false
    func findPark() { tab=1; searchPending=true; searchRequest+=1 }
    /// True once per ⌘F, for the list that focuses its field.
    func takeSearch()->Bool { guard searchPending else { return false }; searchPending=false; return true }
    func stepNight(_ delta:Int) { step=NightStep(id:(step?.id ?? 0)+1,delta:delta,tab:current) }
    /// The tab whose screens the keys reach: a park's window has one page, kept as tab 0; a park
    /// presented over the window is its own layer.
    private var current:Int { parkWindow ? 0 : layers.last ?? tab }
    /// The night views on screen in each tab that ⌘← ⌘→ would move (`NightKeys`), so the menu
    /// enables the keys only where a night is there to move.
    private(set) var nightViews:[Int:Set<UUID>]=[:]
    func nights(_ id:UUID,tab:Int?,on:Bool) {
        guard let tab, (nightViews[tab]?.contains(id) ?? false) != on else { return }
        if on { nightViews[tab,default:[]].insert(id) } else { nightViews[tab]?.remove(id) }
    }
    /// ⌘R: the screens on each tab with pull-to-refresh, in the order they came on screen
    /// (`RefreshKey`). The newest answers: a pushed park's page, else the list or Tonight under it.
    private(set) var refreshers:[Int:[Refresher]]=[:]
    nonisolated struct Refresher: Equatable { let id:UUID; let speaks:Bool }
    func refreshes(_ refresher:Refresher,tab:Int?,on:Bool) {
        guard let tab else { return }
        var list=refreshers[tab] ?? []
        list.removeAll { $0.id==refresher.id }
        if on { list.append(refresher) }
        if list != (refreshers[tab] ?? []) { refreshers[tab]=list }
    }
    /// A ⌘R under way, so a second press waits for the first rather than asking twice.
    var refreshing=false
    private(set) var refreshRequest:RefreshRequest?
    func refresh() {
        let list=refreshers[current] ?? []
        guard let last=list.last, !refreshing else { return }
        // Tonight says its own result as it refreshes; the others are said by `RefreshKey`.
        refreshRequest=RefreshRequest(id:(refreshRequest?.id ?? 0)+1,target:last.id,quiet:list.contains(where:\.speaks))
    }
    /// ⌘N and ⌘,: asked of the tab on screen, whose root toolbar presents them as its own buttons do.
    private(set) var sheetRequest:SheetRequest?
    func ask(_ kind:SheetRequest.Kind) { sheetRequest=SheetRequest(id:(sheetRequest?.id ?? 0)+1,kind:kind,tab:tab) }
    /// What the menu bar may offer for this window, as a value, so the menu redraws when it changes.
    func menu(journalOpen:Bool)->NyxMenu {
        let tabs = !parkWindow
        return NyxMenu(tabs:tabs,nights:!(nightViews[current] ?? []).isEmpty,refresh:!(refreshers[current] ?? []).isEmpty && !refreshing,
                       record:tabs && journalOpen,park:visiblePark)
    }
}
nonisolated struct NightStep: Equatable { let id:Int; let delta:Int; let tab:Int }
nonisolated struct RefreshRequest: Equatable { let id:Int; let target:UUID; let quiet:Bool }
nonisolated struct SheetRequest: Equatable {
    enum Kind: Equatable { case settings, record }
    let id:Int; let kind:Kind; let tab:Int
}
/// The focused window's menu state, published as a value by `WindowSceneReader`. A focused value
/// that changes is what redraws the menu bar; a `disabled` read from the observed `SceneCommands`
/// in the menu's body did not refresh reliably, so ⌘← ⌘→ had stayed enabled everywhere.
nonisolated struct NyxMenu: Equatable {
    /// A window with tabs (not a park's own window): the tab keys, Find a Park, Settings.
    var tabs=false
    /// A night view on screen on the current tab: ⌘← ⌘→.
    var nights=false
    /// A screen with pull-to-refresh on the current tab, not already refreshing from ⌘R.
    var refresh=false
    /// The journal can take a new night.
    var record=false
    /// The park whose page is on screen in the current tab: ⌘⇧N.
    var park:String?=nil
}
private struct NyxMenuKey: FocusedValueKey { typealias Value=NyxMenu }
extension FocusedValues {
    var nyxMenu: NyxMenu? { get { self[NyxMenuKey.self] } set { self[NyxMenuKey.self]=newValue } }
}
/// Hands a window's scene to its `SceneCommands` once the view is in that window, and publishes
/// the window's menu state (`NyxMenu`) for the menu bar. One per window, beside the root.
struct WindowSceneReader: View {
    let commands:SceneCommands
    @Environment(PlanModel.self) private var model: PlanModel?
    var body: some View {
        Probe(commands:commands).focusedSceneValue(\.nyxMenu,commands.menu(journalOpen:!(model?.journalUnavailable ?? true)))
    }
    private struct Probe: UIViewRepresentable {
        let commands:SceneCommands
        func makeUIView(context:Context)->ProbeView { let view=ProbeView(); view.commands=commands; view.isUserInteractionEnabled=false; return view }
        func updateUIView(_ view:ProbeView,context:Context) { view.commands=commands; view.report() }
    }
    final class ProbeView: UIView {
        weak var commands:SceneCommands?
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        func report() { if let scene=window?.windowScene { commands?.windowScene=scene } }
    }
}

private struct TabKey: EnvironmentKey { static let defaultValue:Int?=nil }
private struct RefreshZoneKey: EnvironmentKey { static let defaultValue:TimeZone?=nil }
extension EnvironmentValues {
    /// The tab a view lives in, so a command meant for the Calendar never moves a park on Tonight.
    var nyxTab: Int? { get { self[TabKey.self] } set { self[TabKey.self]=newValue } }
    /// The time zone ⌘R's note says a forecast's time in, where the screen shows a place's own
    /// time (Tonight); nil for this device's.
    var refreshTimeZone: TimeZone? { get { self[RefreshZoneKey.self] } set { self[RefreshZoneKey.self]=newValue } }
}

/// The menu bar and the ⌘-hold overlay on iPad: the four tabs, Find a Park, the night keys,
/// Refresh, Record a Night and Settings. Each is enabled only where the focused window has it.
struct NyxCommands: Commands {
    @FocusedValue(SceneCommands.self) private var scene
    @FocusedValue(\.nyxMenu) private var menu
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    /// The tab keys, Find a Park and Settings need a window with tabs.
    private var tabless:Bool { scene == nil || scene?.parkWindow == true }
    var body: some Commands {
        // Settings is in the app, not the Settings app: the same sheet as the gear in each tab's toolbar.
        CommandGroup(replacing:.appSettings) {
            Button("Settings…") { scene?.ask(.settings) }.keyboardShortcut(",",modifiers:.command).disabled(tabless)
        }
        // A new journal entry is the app's new item: the editor the Journal's "Record a night" opens.
        CommandGroup(before:.newItem) {
            Button("Record a Night") { scene?.ask(.record) }.keyboardShortcut("n",modifiers:.command).disabled(scene == nil || menu?.record != true)
        }
        // The park on screen, beside the one you are reading: ⌘⇧N, as "Open in New Window" on its row.
        CommandGroup(after:.newItem) {
            Button("Open Park in New Window") { if let id=scene?.visiblePark { openWindow(value:ParkWindow(parkID:id)) } }
                .keyboardShortcut("n",modifiers:[.command,.shift])
                .disabled(!multipleWindows || tabless || menu?.park == nil)
        }
        CommandGroup(before:.sidebar) {
            ForEach(Array(SceneCommands.tabs.enumerated()),id:\.offset) { index,title in
                Button(title) { scene?.tab=index }
                    .keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:.command)
                    .disabled(tabless)
            }
            Divider()
            // The screen's own pull-to-refresh; Plan and Journal have none, so it rests there.
            Button("Refresh") { scene?.refresh() }.keyboardShortcut("r",modifiers:.command).disabled(scene == nil || menu?.refresh != true)
            Divider()
        }
        // ⌘← and ⌘→, as Calendar steps its days: plain arrows belong to scroll views and keyboard focus.
        CommandMenu("Nights") {
            Button("Find a Park") { scene?.findPark() }.keyboardShortcut("f",modifiers:.command).disabled(tabless)
            Divider()
            Button("Previous Night") { scene?.stepNight(-1) }.keyboardShortcut(.leftArrow,modifiers:.command).disabled(scene == nil || menu?.nights != true)
            Button("Next Night") { scene?.stepNight(1) }.keyboardShortcut(.rightArrow,modifiers:.command).disabled(scene == nil || menu?.nights != true)
        }
    }
}

/// ⌘← and ⌘→ for a view that shows one night: it moves only when it is on screen, on the window's
/// current tab, and `enabled`; elsewhere the keys do nothing, and the menu shows them disabled.
/// A night view with pull-to-refresh answers ⌘R too (`RefreshKey`).
struct NightKeys: ViewModifier {
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(\.nyxTab) private var tab
    var enabled=true
    let step:(Int)->Void
    @State private var visible=false
    @State private var id=UUID()
    func body(content:Content)->some View {
        content
            // Reported as it happens, not through `onChange`: a page popped off a stack is gone before a change could run.
            .onAppear { visible=true; commands?.nights(id,tab:tab,on:enabled) }
            .onDisappear { visible=false; commands?.nights(id,tab:tab,on:false) }
            .onChange(of:enabled) { _,on in if visible { commands?.nights(id,tab:tab,on:on) } }
            .onChange(of:commands?.step) { _,request in
                guard let request, enabled, visible, let tab, request.tab==tab else { return }
                step(request.delta)
            }
            .modifier(RefreshKey())
    }
}
extension View {
    func nightKeys(enabled:Bool=true,step:@escaping (Int)->Void)->some View { modifier(NightKeys(enabled:enabled,step:step)) }
}

/// ⌘R for a screen with pull-to-refresh: the same action (`EnvironmentValues.refresh`, set by the
/// screen's `refreshable` around it), or `action` where the refresh lives inside a child view.
/// A key has no spinner to pull, so a small note says what happened, as Tonight says it: updated,
/// or saved data and why. Tonight's own refresh already speaks it (`speaks`), so here it is only shown.
struct RefreshKey: ViewModifier {
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(PlanModel.self) private var model: PlanModel?
    @Environment(\.refresh) private var pull
    @Environment(\.nyxTab) private var tab
    @Environment(\.refreshTimeZone) private var timeZone
    let speaks:Bool
    let action:(@MainActor ()async->Void)?
    @State private var id=UUID()
    @State private var note:RefreshNote.Phase?
    init(speaks:Bool=false,action:(@MainActor ()async->Void)?=nil) { self.speaks=speaks; self.action=action }
    private var refresher:SceneCommands.Refresher { .init(id:id,speaks:speaks) }
    func body(content:Content)->some View {
        content
            .overlay(alignment:.top) { if let note { RefreshNote(phase:note).transition(.opacity) } }
            .onAppear { commands?.refreshes(refresher,tab:tab,on:action != nil || pull != nil) }
            .onDisappear { commands?.refreshes(refresher,tab:tab,on:false); note=nil }
            .onChange(of:commands?.refreshRequest) { _,request in
                guard let request, request.target==id else { return }
                Task { await run(quiet:request.quiet) }
            }
    }
    private func run(quiet:Bool) async {
        guard let commands, !commands.refreshing else { return }
        let perform:@MainActor ()async->Void
        if let action { perform=action } else if let pull { perform={ await pull() } } else { return }
        commands.refreshing=true
        withAnimation(NyxMotion.fade) { note = .working }
        let before=model?.forecasts.mapValues(\.updated) ?? [:]
        await perform()
        commands.refreshing=false
        guard let model else { withAnimation(NyxMotion.fade) { note=nil }; return }
        let line=RefreshOutcome.of(model,before:before).line(in:timeZone ?? .current)
        // Heard, politely, after anything VoiceOver is already saying; seen for a few seconds.
        if !quiet { NightListener.announce(line,priority:.low) }
        withAnimation(NyxMotion.fade) { note = .said(line) }
        try? await Task.sleep(for:.seconds(3))
        if note == .said(line) { withAnimation(NyxMotion.fade) { note=nil } }
    }
}
/// What a refresh found, in Tonight's words: new forecasts (or ones minutes old), a forecast too
/// recent to ask about again (`ForecastReuse`), requests paused for a while, or saved data and why.
nonisolated enum RefreshOutcome: Equatable {
    case updated, forecastsOff, unreachable
    /// Not asked again: the newest forecast, from this time, is as new as the models allow.
    case current(Date)
    /// Paused: the service asked Nyx to wait, or this iPhone's request budget is spent. The newest forecast kept, if any.
    case paused(Date?)
    static func of(forecastsOn:Bool,fetched:Bool,current:Bool,newest:Date?=nil,heldBack:Bool=false,now:Date = .now)->RefreshOutcome {
        guard forecastsOn else { return .forecastsOff }
        if fetched || current { return .updated }
        if let newest, now.timeIntervalSince(newest)<ForecastReuse.cloudsForced { return .current(newest) }
        if heldBack { return .paused(newest) }
        return .unreachable
    }
    /// From the model after a refresh; `before` is when each forecast was issued before it began.
    @MainActor static func of(_ model:PlanModel,before:[String:Date],now:Date = .now)->RefreshOutcome {
        let fetched=model.forecasts.contains { id,forecast in before[id] != forecast.updated }
        let current=model.forecasts.values.contains { now.timeIntervalSince($0.updated)<600 }
        // The parks' own forecast: it is the one every refresh asks for.
        let newest=model.parks.compactMap { model.forecasts[$0.id]?.updated }.max()
        return of(forecastsOn:model.weatherEnabled,fetched:fetched,current:current,newest:newest,heldBack:model.forecastsHeldBack,now:now)
    }
    var line:String { line(in:.current) }
    /// The line with a forecast's time in `timeZone`: the place's own time where the screen shows
    /// it that way (Tonight's "Forecast as of" caption), so what is heard matches what is read.
    func line(in timeZone:TimeZone)->String {
        var calendar=Calendar.current
        calendar.timeZone=timeZone
        switch self {
        case .updated: return String(localized:"Updated")
        case .forecastsOff: return String(localized:"Cloud forecasts are off in Your privacy. Showing saved data.")
        case .unreachable: return String(localized:"Could not reach the forecast. Showing saved data.")
        case .current(let issued): return String(localized:"Up to date. Forecast from \(Self.when(issued,calendar:calendar))")
        case .paused(let issued?): return String(localized:"Forecast requests are paused for a while. Showing the forecast from \(Self.when(issued,calendar:calendar))")
        case .paused(nil): return String(localized:"Forecast requests are paused for a while. Showing saved data.")
        }
    }
    /// "9:41 PM" today, "Fri 9:41 PM" on an earlier day, in this device's own format and the
    /// calendar's time zone (this device's, unless a place's is asked for).
    static func when(_ date:Date,now:Date = .now,calendar:Calendar = .current)->String {
        var time=Date.FormatStyle(date:.omitted,time:.shortened), day=Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
        time.timeZone=calendar.timeZone; day.timeZone=calendar.timeZone
        return calendar.isDate(date,inSameDayAs:now) ? date.formatted(time) : date.formatted(day)
    }
}
/// ⌘R's note at the top of the page: the system spinner while it works, then one line. Solid
/// panel, not glass, so the line keeps its contrast over a bright stretch of sky. VoiceOver hears
/// the line as an announcement, so the note itself stays out of the way.
private struct RefreshNote: View {
    enum Phase: Equatable { case working, said(String) }
    @Environment(\.nyx) private var palette
    let phase:Phase
    var body: some View {
        Group {
            switch phase {
            case .working: ProgressView()
            case .said(let line): Text(line).font(.footnote).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            }
        }
        .foregroundStyle(palette.ink).tint(palette.ink)
        .padding(.horizontal,16).padding(.vertical,10).frame(minHeight:36)
        .background(RoundedRectangle(cornerRadius:18).fill(palette.panel)).overlay(RoundedRectangle(cornerRadius:18).stroke(palette.line,lineWidth:0.5))
        .frame(maxWidth:460).padding(.horizontal,24).padding(.top,8)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
#Preview("Refresh note") {
    VStack(spacing:24) {
        RefreshNote(phase:.working)
        RefreshNote(phase:.said(RefreshOutcome.updated.line))
        RefreshNote(phase:.said(RefreshOutcome.unreachable.line))
        RefreshNote(phase:.said(RefreshOutcome.forecastsOff.line)).dynamicTypeSize(.accessibility5)
    }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.black).preferredColorScheme(.dark)
}

/// Each tab's content keeps the amber tint; the tab chrome around it learns whether it is a sidebar.
/// The sidebar marks its selected row with white text on the tint, which amber cannot carry
/// (about 1.8:1), so there the chrome takes the deeper control tint (about 5:1).
/// Every tab's content waits behind the launch's score gate (`ScoreGate`) unless that tab is one
/// the gate lists as carrying no score from the caches, so a tab added later waits by default.
struct TabChrome: ViewModifier {
    @Environment(\.tabBarPlacement) private var placement
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    let tab: Int
    let tint: Color
    func body(content:Content)->some View {
        content.scoreGate(ScoreGate.gates(tab:tab)).environment(\.nyxTab,tab).tint(tint).onChange(of:placement == .sidebar,initial:true) { _,sidebar in
            if commands?.sidebar != sidebar { commands?.sidebar=sidebar }
        }
    }
}
