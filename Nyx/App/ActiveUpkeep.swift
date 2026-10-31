import SwiftUI
import SwiftData

/// What Nyx does each time it comes forward, whichever window that is (a main window, or a park's own
/// window in front of it on iPad): "tonight" checked against the clock, the saved parks published again
/// (the widgets, the watch, and reminders rescheduled for the next nights) and the night's Live Activity
/// caught up. Once per coming forward: a second window already active (two side by side) adds nothing.
struct ActiveUpkeep: ViewModifier {
    @Environment(PlanModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NightLook.nightVisionKey,store:SharedSettings.defaults) private var nightVision=false
    @State private var id=UUID()
    let saved: [SavedPark]
    let spots: [SavedSpot]
    /// Whether the saved parks may be published from here yet: a main window's launch publishes them
    /// itself, after Spotlight's index, and becoming active at launch leaves it to that one.
    var publish=true
    func body(content: Content) -> some View {
        content
            .onChange(of:scenePhase,initial:true) { _,phase in
                guard ActiveWindows.shared.update(id,active:phase == .active) else { return }
                model.tick()
                if publish { Task { await model.savedSync.update(model,saved:saved,spots:spots) } }
                if DebugScenario.screen == nil { Task { await FieldActivities.refresh(nightVision:nightVision) } }
            }
            .onDisappear { _=ActiveWindows.shared.update(id,active:false) }
    }
}
extension View {
    /// `ActiveUpkeep`, for a window of either kind.
    func activeUpkeep(saved: [SavedPark], spots: [SavedSpot], publish: Bool=true) -> some View {
        modifier(ActiveUpkeep(saved:saved,spots:spots,publish:publish))
    }
}

/// The windows active right now. Nyx has come forward when the first of them becomes active.
struct ActiveWindows {
    @MainActor static var shared=ActiveWindows()
    private var active: Set<UUID>=[]
    /// Records a window's phase; true when it is the only window active, having just become so.
    mutating func update(_ id: UUID, active now: Bool) -> Bool {
        guard now else { active.remove(id); return false }
        guard !active.contains(id) else { return false }
        active.insert(id)
        return active.count == 1
    }
}

/// The main windows (with the tabs), the one active last at the end. A park's own window brings that
/// one forward ("Show Main Window"); with none left open, a new one opens.
@MainActor enum MainWindows {
    private final class Entry { weak var commands: SceneCommands?; init(_ commands: SceneCommands) { self.commands=commands } }
    private static var entries: [Entry]=[]
    /// Whether a main window is open (connected, in front or not); after a relaunch the system may
    /// restore a park's window alone and leave the main one unconnected until it is asked for.
    static var connected: Bool { entries.contains { ($0.commands?.windowScene).map { $0.activationState != .unattached } ?? false } }
    static func activated(_ commands: SceneCommands) {
        entries.removeAll { $0.commands == nil || $0.commands === commands }
        entries.append(Entry(commands))
    }
    static func bringForward() {
        let scene=entries.reversed().compactMap { $0.commands?.windowScene }.first { $0.activationState != .unattached }
        // Not connected: the main window's own session, restored with the app, rather than a new window
        // beside it. Each scene's session names its window group; a park's own windows are "park".
        let session=scene?.session ?? UIApplication.shared.openSessions.first { ($0.userInfo?["com.apple.SwiftUI.sceneID"] as? String).map { $0 != "park" } ?? false }
        let request=session.map { UISceneSessionActivationRequest(session:$0) } ?? UISceneSessionActivationRequest(role:.windowApplication)
        UIApplication.shared.activateSceneSession(for:request,errorHandler:nil)
    }
}

/// A park's own window in front with no main window open to answer (one closed, or not yet connected after
/// a relaunch that restored this window alone): a park asked for by Siri, Shortcuts or a control, field mode
/// from Control Center, or a tapped reminder brings a main window forward, which takes the request on arriving.
struct BringsMainWindowForRequests: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .onChange(of:scenePhase,initial:true) { _,_ in check() }
            .onReceive(NotificationCenter.default.publisher(for:ParkOpenRequest.notification)) { _ in check() }
            .onReceive(NotificationCenter.default.publisher(for:FieldModeRequest.notification)) { _ in check() }
            .onReceive(NotificationCenter.default.publisher(for:NotificationRouter.waiting)) { _ in check() }
    }
    private func check() {
        guard scenePhase == .active, !MainWindows.connected, Self.waiting else { return }
        MainWindows.bringForward()
    }
    /// Something only a main window opens is waiting (DEBUG: a `-nyx-link` too).
    private static var waiting: Bool {
        let defaults=SharedSettings.defaults, now=Date.now
        return PendingPark.waits(key:ParkOpenRequest.key,now:now,defaults:defaults) || PendingPark.waits(key:FieldModeRequest.key,now:now,defaults:defaults)
            || NotificationRouter.shared.waits || DebugScenario.link != nil
    }
}
