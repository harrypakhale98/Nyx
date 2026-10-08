import SwiftUI

/// One window's keyboard and menu-bar commands (iPad, or an iPhone with a keyboard). Each window
/// owns one, so ⌘2 in one window never moves another; the menu bar reaches the focused window's
/// through `focusedSceneValue`.
@MainActor @Observable final class SceneCommands {
    /// The tabs in order, for ⌘1–⌘4.
    static let tabs:[LocalizedStringKey]=["Tonight","Parks","Plan","Journal"]
    /// A screenshot route's tab: `calendar` and `plan` are both Plan; `parks-map` is Parks showing its map. Nil for routes that are not tabs.
    nonisolated static func tabIndex(_ route:String)->Int? { ["tonight":0,"parks":1,"parks-map":1,"calendar":2,"plan":2,"journal":3][route] }
    var tab=0
    /// A park's own window (`ParkWindow`): one page, no tabs, so the tab keys and Find a Park rest.
    let parkWindow:Bool
    init(parkWindow:Bool=false) { self.parkWindow=parkWindow }
    /// The park whose page is on screen in each tab, for ⌘⇧N (`ReportsVisiblePark`).
    private(set) var visibleParks:[Int:String]=[:]
    /// The park on screen in this window's current tab, if any.
    var visiblePark:String? { visibleParks[parkWindow ? 0 : tab] }
    func show(park id:String,tab:Int?) { if let tab { visibleParks[tab]=id } }
    func hide(park id:String,tab:Int?) { if let tab, visibleParks[tab]==id { visibleParks[tab]=nil } }
    /// A park's month asked of this window's Plan tab (a `nyx://calendar` link, "Show in Calendar",
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
    /// Bumped by ⌘F: the Parks list focuses its search field.
    private(set) var searchRequest=0
    /// ⌘← and ⌘→: the night view showing on the current tab moves one night.
    private(set) var step:NightStep?
    /// A ⌘F not yet answered: the Parks list may not exist until its tab first opens.
    private var searchPending=false
    func findPark() { tab=1; searchPending=true; searchRequest+=1 }
    /// True once per ⌘F, for the list that focuses its field.
    func takeSearch()->Bool { guard searchPending else { return false }; searchPending=false; return true }
    func stepNight(_ delta:Int) { step=NightStep(id:(step?.id ?? 0)+1,delta:delta,tab:tab) }
}
nonisolated struct NightStep: Equatable { let id:Int; let delta:Int; let tab:Int }
/// Hands a window's scene to its `SceneCommands` once the view is in that window.
struct WindowSceneReader: UIViewRepresentable {
    let commands:SceneCommands
    func makeUIView(context:Context)->Probe { let view=Probe(); view.commands=commands; view.isUserInteractionEnabled=false; return view }
    func updateUIView(_ view:Probe,context:Context) { view.commands=commands; view.report() }
    final class Probe: UIView {
        weak var commands:SceneCommands?
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        func report() { if let scene=window?.windowScene { commands?.windowScene=scene } }
    }
}

private struct TabKey: EnvironmentKey { static let defaultValue:Int?=nil }
extension EnvironmentValues {
    /// The tab a view lives in, so a command meant for the Calendar never moves a park on Tonight.
    var nyxTab: Int? { get { self[TabKey.self] } set { self[TabKey.self]=newValue } }
}

/// The menu bar and the ⌘-hold overlay on iPad: the four tabs, Find a Park, and the night keys.
struct NyxCommands: Commands {
    @FocusedValue(SceneCommands.self) private var scene
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    /// The tab keys and Find a Park need a window with tabs.
    private var tabless:Bool { scene == nil || scene?.parkWindow == true }
    var body: some Commands {
        // The park on screen, beside the one you are reading: ⌘⇧N, as "Open in New Window" on its row.
        CommandGroup(after:.newItem) {
            Button("Open Park in New Window") { if let id=scene?.visiblePark { openWindow(value:ParkWindow(parkID:id)) } }
                .keyboardShortcut("n",modifiers:[.command,.shift])
                .disabled(!multipleWindows || tabless || scene?.visiblePark == nil)
        }
        CommandGroup(before:.sidebar) {
            ForEach(Array(SceneCommands.tabs.enumerated()),id:\.offset) { index,title in
                Button(title) { scene?.tab=index }
                    .keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:.command)
                    .disabled(tabless)
            }
            Divider()
        }
        // ⌘← and ⌘→, as Calendar steps its days: plain arrows belong to scroll views and keyboard focus.
        CommandMenu("Nights") {
            Button("Find a Park") { scene?.findPark() }.keyboardShortcut("f",modifiers:.command).disabled(tabless)
            Divider()
            Button("Previous Night") { scene?.stepNight(-1) }.keyboardShortcut(.leftArrow,modifiers:.command).disabled(scene == nil)
            Button("Next Night") { scene?.stepNight(1) }.keyboardShortcut(.rightArrow,modifiers:.command).disabled(scene == nil)
        }
    }
}

/// ⌘← and ⌘→ for a view that shows one night: it moves only when it is on screen, on the window's
/// current tab, and `enabled`; elsewhere the keys do nothing.
struct NightKeys: ViewModifier {
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(\.nyxTab) private var tab
    var enabled=true
    let step:(Int)->Void
    @State private var visible=false
    func body(content:Content)->some View {
        content
            .onAppear { visible=true }
            .onDisappear { visible=false }
            .onChange(of:commands?.step) { _,request in
                guard let request, enabled, visible, let tab, request.tab==tab else { return }
                step(request.delta)
            }
    }
}
extension View {
    func nightKeys(enabled:Bool=true,step:@escaping (Int)->Void)->some View { modifier(NightKeys(enabled:enabled,step:step)) }
}

/// Each tab's content keeps the amber tint; the tab chrome around it learns whether it is a sidebar.
/// The sidebar marks its selected row with white text on the tint, which amber cannot carry
/// (about 1.8:1), so there the chrome takes the deeper control tint (about 5:1).
struct TabChrome: ViewModifier {
    @Environment(\.tabBarPlacement) private var placement
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    let tint: Color
    func body(content:Content)->some View {
        content.tint(tint).onChange(of:placement == .sidebar,initial:true) { _,sidebar in
            if commands?.sidebar != sidebar { commands?.sidebar=sidebar }
        }
    }
}
