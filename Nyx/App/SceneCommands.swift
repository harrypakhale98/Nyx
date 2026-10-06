import SwiftUI

/// One window's keyboard and menu-bar commands (iPad, or an iPhone with a keyboard). Each window
/// owns one, so ⌘2 in one window never moves another; the menu bar reaches the focused window's
/// through `focusedSceneValue`.
@MainActor @Observable final class SceneCommands {
    /// The tabs in order, for ⌘1–⌘5.
    static let tabs:[LocalizedStringKey]=["Tonight","Parks","Calendar","Journal","Learn"]
    var tab=0
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

private struct TabKey: EnvironmentKey { static let defaultValue:Int?=nil }
extension EnvironmentValues {
    /// The tab a view lives in, so a command meant for the Calendar never moves a park on Tonight.
    var nyxTab: Int? { get { self[TabKey.self] } set { self[TabKey.self]=newValue } }
}

/// The menu bar and the ⌘-hold overlay on iPad: the five tabs, Find a Park, and the night keys.
struct NyxCommands: Commands {
    @FocusedValue(SceneCommands.self) private var scene
    var body: some Commands {
        CommandGroup(before:.sidebar) {
            ForEach(Array(SceneCommands.tabs.enumerated()),id:\.offset) { index,title in
                Button(title) { scene?.tab=index }
                    .keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:.command)
                    .disabled(scene == nil)
            }
            Divider()
        }
        // ⌘← and ⌘→, as Calendar steps its days: plain arrows belong to scroll views and keyboard focus.
        CommandMenu("Nights") {
            Button("Find a Park") { scene?.findPark() }.keyboardShortcut("f",modifiers:.command).disabled(scene == nil)
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
