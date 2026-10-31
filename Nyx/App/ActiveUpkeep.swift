import SwiftUI
import SwiftData

/// What Nyx does each time it comes forward, whichever window that is (a main window, or a park's own
/// window in front of it on iPad): "tonight" checked against the clock, the saved parks published again
/// (the widgets, the watch, and reminders rescheduled for the next nights) and the night's Live Activity
/// caught up. Once per coming forward: a second window already active (two side by side) adds nothing.
/// While Nyx is on screen, one of its active windows also keeps "tonight" honest through sunrise and
/// follows night vision At dusk (`ActiveWindows.keeper`), so a park's window restored alone does both.
struct ActiveUpkeep: ViewModifier {
    @Environment(PlanModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NightLook.nightVisionKey,store:SharedSettings.defaults) private var nightVision=false
    /// Night vision At dusk (`NightVisionDusk`): followed while Nyx is active, never in the background.
    @AppStorage(NightVisionMode.atDuskKey,store:SharedSettings.defaults) private var atDusk=false
    @State private var id=UUID()
    let saved: [SavedPark]
    let spots: [SavedSpot]
    /// Whether the saved parks may be published from here yet: a main window's launch publishes them
    /// itself, after Spotlight's index, and becoming active at launch leaves it to that one.
    var publish=true
    /// This window keeps Nyx's time while it is on screen: the first of the windows active now.
    private var keeps: Bool { ActiveWindows.shared.keeper == id }
    func body(content: Content) -> some View {
        content
            .onChange(of:scenePhase,initial:true) { _,phase in
                guard ActiveWindows.shared.update(id,active:phase == .active) else { return }
                model.tick()
                if publish { Task { await model.savedSync.update(model,saved:saved,spots:spots) } }
                if DebugScenario.screen == nil { Task { await FieldActivities.refresh(nightVision:nightVision) } }
            }
            .onDisappear { _=ActiveWindows.shared.update(id,active:false) }
            .task(id:keeps) {
                // Keep "tonight" honest on a screen left open through sunrise.
                guard keeps else { return }
                while !Task.isCancelled { try? await Task.sleep(for:.seconds(300)); if !Task.isCancelled { model.tick() } }
            }
            // At dusk: looked at again whenever the choice, the switch, the starting point or the keeping
            // window changes, then at each dusk and dawn while Nyx is open.
            .task(id:DuskWatch(atDusk:atDusk,on:nightVision,keeps:keeps,place:NightVisionDusk.place(model).map { [$0.park.latitude,$0.park.longitude] })) { await followDusk() }
    }
    /// What At dusk's watch depends on: a change to any of these looks at the Sun again.
    private struct DuskWatch: Equatable { let atDusk: Bool; let on: Bool; let keeps: Bool; let place: [Double]? }
    /// At dusk while Nyx is active: the switch is set now, then again at the next dusk or dawn (at most
    /// 15 minutes apart, so a changed clock or time zone catches up). The palette turns on the window's
    /// crossfade on the shared spring, with the soft tap, as Control Center's does; VoiceOver hears it,
    /// since nothing on screen was touched. Captures leave the switch alone.
    private func followDusk() async {
        guard atDusk, keeps, DebugScenario.screen == nil else { return }
        while !Task.isCancelled {
            guard let result=NightVisionDusk.apply(model) else { return }
            // Writing the switch changes this task's id, which starts it again and cancels this one.
            if result.changed { NightVisionLamp.announce(result.plan.on) }
            let wait=min(900,max(1,(result.plan.next?.timeIntervalSinceNow ?? 900)+1))
            try? await Task.sleep(for:.seconds(wait))
        }
    }
}
extension View {
    /// `ActiveUpkeep`, for a window of either kind.
    func activeUpkeep(saved: [SavedPark], spots: [SavedSpot], publish: Bool=true) -> some View {
        modifier(ActiveUpkeep(saved:saved,spots:spots,publish:publish))
    }
}

/// The windows active right now, in the order they became so. Nyx has come forward when the first of
/// them becomes active; the first still active keeps its time (`keeper`).
@Observable final class ActiveWindows {
    static let shared=ActiveWindows()
    private(set) var active: [UUID]=[]
    /// Records a window's phase; true when it is the only window active, having just become so.
    func update(_ id: UUID, active now: Bool) -> Bool {
        guard now else { active.removeAll { $0 == id }; return false }
        guard !active.contains(id) else { return false }
        active.append(id)
        return active.count == 1
    }
    /// The window that ticks "tonight" and follows At dusk: one at a time, handed on when it leaves.
    var keeper: UUID? { active.first }
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
    /// Nyx's own mark on each window's session ("main" or "park"), which the system keeps with the
    /// session across a relaunch (`WindowSceneReader` sets it once the window has a scene).
    nonisolated static let kindKey="nyx.window"
    static func mark(_ session: UISceneSession, main: Bool) {
        let kind=main ? "main" : "park"
        guard session.userInfo?[kindKey] as? String != kind else { return }
        var info=session.userInfo ?? [:]
        info[kindKey]=kind
        session.userInfo=info
    }
    /// Whether a session is a main window's: by Nyx's mark; a session from before the mark by the window
    /// group SwiftUI names in it (a park's own windows are "park").
    nonisolated static func isMain(_ info: [String: Any]?) -> Bool {
        if let kind=info?[kindKey] as? String { return kind == "main" }
        return (info?["com.apple.SwiftUI.sceneID"] as? String).map { $0 != "park" } ?? false
    }
    static func bringForward() {
        let scene=entries.reversed().compactMap { $0.commands?.windowScene }.first { $0.activationState != .unattached }
        // Not connected: the main window's own session, restored with the app, rather than a new window beside it.
        let session=scene?.session ?? UIApplication.shared.openSessions.first { isMain($0.userInfo) }
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
