import SwiftUI
import SwiftData

/// A park in a window of its own (iPad, and the iPad app on a Mac): "Open in New Window" from a
/// park's row or page, or ⌘⇧N on the park in view. The system keeps the value with the window, so
/// Joshua Tree beside Death Valley comes back after a relaunch. Only the park id and the night travel.
nonisolated struct ParkWindow: Codable, Hashable, Sendable {
    let parkID: String
    /// The night the window opened on (the park-local evening); nil for tonight.
    var night: Date?=nil
}
/// One park's window: its page, in the app's palette and night vision, with its own keyboard
/// commands (⌘← ⌘→ move its night; the tab keys belong to the main window). The night chosen
/// here is kept for the window, so a restored window opens where it was left.
struct ParkWindowRoot: View {
    @Binding var value: ParkWindow?
    @Environment(PlanModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.legibilityWeight) private var legibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @AppStorage(NightTint.key,store:SharedSettings.defaults) private var brighterRed=false
    /// The night last chosen in this window, as seconds since 1970 (0: none yet).
    @SceneStorage("windowNight") private var chosenNight=0.0
    @State private var commands=SceneCommands(parkWindow:true)
    var body: some View {
        // The same palette as the main window, brighter red included (`RootView`).
        let palette=NyxPalette(nightVision:nightVision,highContrast:contrast == .increased,brighterRed:brighterRed,boldText:legibility == .bold)
        NavigationStack {
            if let value, let park=model.park(value.parkID) {
                ParkDetailView(park:park,initialDate:ParkWindowRoot.night(stored:chosenNight,opened:value.night,tonight:model.tonight(park)),nightChanged:{ night in chosenNight=night.timeIntervalSince1970 })
                    .id(park.id)
            } else {
                CalmState(symbol:"mountain.2",title:"This park is not in Nyx",message:"Close this window and choose a park from the list.")
                    .frame(maxHeight:.infinity).background(NightBackground())
            }
        }
        .environment(\.nyxTab,0)
        .environment(commands).focusedSceneValue(commands)
        .background(WindowSceneReader(commands:commands).frame(width:0,height:0).accessibilityHidden(true))
        .environment(\.nyx,palette).environment(\.skyHome,model.home)
        .foregroundStyle(palette.ink,palette.muted,palette.muted).tint(palette.accent).preferredColorScheme(.dark).statusBarHidden(palette.nightVision)
        .modifier(NightVisionFilter(enabled:palette.nightVision,red:palette.red))
        .animation(reduceMotion ? nil : NyxMotion.spring,value:palette.nightVision)
        .nyxAccessibility()
    }
    /// The night a window opens on: the one last chosen in it, else the one it was opened with.
    /// A night before the park's current one (a window left open past sunrise, or restored days
    /// later) gives way to tonight. `tonight` is the park's current night (`Park.currentNight(at:)`).
    nonisolated static func night(stored:Double,opened:Date?,tonight:Date)->Date? {
        let candidate=stored>0 ? Date(timeIntervalSince1970:stored) : opened
        guard let candidate, candidate>=tonight else { return nil }
        return candidate
    }
}
/// "Open in New Window", wherever the system offers more than one window and this is not already
/// a park's own window. Nothing on iPhone.
struct OpenParkWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    let park: Park
    var night: Date?=nil
    var body: some View {
        if multipleWindows, commands?.parkWindow != true {
            Button("Open in New Window",systemImage:"macwindow.badge.plus") { openWindow(value:ParkWindow(parkID:park.id,night:night)) }
                .accessibilityInputLabels([Text("Open in New Window"),Text("New window")])
        }
    }
}
/// DEBUG captures: `-nyx-open-window deva` opens that park in a window of its own once the app is
/// up, as "Open in New Window" would. Nothing in Release.
struct DebugOpenParkWindow: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    func body(content:Content)->some View {
        content.task {
            #if DEBUG
            let args=ProcessInfo.processInfo.arguments
            guard multipleWindows, let index=args.firstIndex(of:"-nyx-open-window"), index+1<args.count else { return }
            try? await Task.sleep(for:.seconds(2))
            openWindow(value:ParkWindow(parkID:args[index+1]))
            #endif
        }
    }
}
/// The park on screen in a window's current tab, for ⌘⇧N. A park's page reports itself while it is
/// visible; another tab's page never answers for this one.
struct ReportsVisiblePark: ViewModifier {
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(\.nyxTab) private var tab
    let parkID: String
    func body(content:Content)->some View {
        content
            .onAppear { commands?.show(park:parkID,tab:tab) }
            .onDisappear { commands?.hide(park:parkID,tab:tab) }
    }
}
