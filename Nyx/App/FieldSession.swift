import Accessibility
import SwiftUI
import UIKit
import WidgetKit

/// One stretch of time in field mode: the park, its night, the eye's dark-adaptation clock, and
/// what field mode changed on the phone (night vision, screen brightness, auto-lock), each put back
/// exactly as it was on the way out. Leaving the app restores the brightness for other apps.
/// It guards the battery through a long night: auto-lock returns after ten minutes without a touch
/// (the Live Activity carries the night on the Lock Screen), the compass rests while the phone is
/// hot, and Low Power Mode turned on mid-session stills the sky.
@MainActor @Observable final class FieldSession {
    let park: Park
    let night: FieldNight
    /// Read once on entry (field mode is one night); DEBUG captures set it again after a live refresh.
    /// The night's Live Activity keeps it too while field mode is open (`FieldActivities.held`).
    var score: DarknessScore
    /// When `score` was worked out (`FieldActivities.scoredAt`): its cloud forecast's time, so the
    /// Live Activity says how old it is ("as of Tue") for a session opened on an old forecast.
    var scoredAt: Date
    /// The park's closure when field mode opened, for the Live Activity it starts (later park alerts update it there).
    let closure: String?
    var adaptation: DarkAdaptation
    /// Set when the eye's clock started over on return, until acknowledged.
    var reset: DarkAdaptation.Reset?
    /// Haptic triggers: a light tick per milestone, a medium pulse when true darkness begins.
    var milestonesPassed=0
    var darknessBegan=0
    /// The night's Live Activity is running for this park.
    var following=false
    /// False for DEBUG screen routes: nothing on the phone is changed.
    @ObservationIgnored let changesPhone: Bool
    /// DEBUG only: shifts "now" so a screenshot can show a moment in the night.
    @ObservationIgnored private let offset: TimeInterval
    @ObservationIgnored private var prior: (nightVision: Bool, brightness: CGFloat?, idle: Bool)?
    /// Set by `end()`: a cover closed during its own presentation must not begin afterwards.
    @ObservationIgnored private var ended=false
    @ObservationIgnored private var observers: [NSObjectProtocol]=[]
    @ObservationIgnored private var ticker: Task<Void,Never>?
    @ObservationIgnored private var idleWatch: Task<Void,Never>?
    /// The last touch anywhere on the field screen.
    @ObservationIgnored private var lastTouch=Date.now
    /// Without a touch for this long, the screen may lock again.
    static let idleAfter: TimeInterval=600
    /// Below this the screen is never raised; above it, field mode lowers it here.
    static let brightness: CGFloat=0.12
    /// The floor under Increase Contrast or accessibility text sizes, where 12% is too dim to read.
    static let legibleBrightness: CGFloat=0.2
    /// "Keep my brightness" in field mode's options: the screen is left as the person set it.
    static let keepBrightnessKey="fieldKeepsBrightness"
    /// Whether field mode leaves the screen's brightness alone (remembered on this iPhone).
    var keepsBrightness=UserDefaults.standard.bool(forKey: FieldSession.keepBrightnessKey)
    /// Where field mode sets the screen: never brighter than it was, 12% at most, or 20% when the
    /// person needs more light to read (Increase Contrast, accessibility text sizes). Nil leaves it.
    static func dimmed(from prior: CGFloat?, legible: Bool, keep: Bool) -> CGFloat? {
        guard !keep else { return nil }
        let floor=legible ? legibleBrightness : brightness
        return min(prior ?? floor, floor)
    }
    /// Increase Contrast or an accessibility text size.
    private static var needsLegibleLight: Bool {
        UIAccessibility.isDarkerSystemColorsEnabled || UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
    }

    init(park: Park, model: PlanModel, changesPhone: Bool=true, offset: TimeInterval=0, adaptedFor: TimeInterval=0) {
        let tonight=model.night(park)
        self.park=park; self.score=tonight.score; scoredAt=FieldActivities.scoredAt(tonight)
        self.night=FieldNight(park: park, sky: tonight.sky); closure=model.closure(park)
        self.changesPhone=changesPhone; self.offset=offset
        adaptation=DarkAdaptation(start: Date.now.addingTimeInterval(offset-adaptedFor))
        following=FieldActivities.isFollowing(park)
    }
    var now: Date { Date.now.addingTimeInterval(offset) }
    /// A night moment on the wall clock, for system timers that count against the real time.
    func real(_ date: Date) -> Date { date.addingTimeInterval(-offset) }

    func begin() {
        guard changesPhone, prior == nil, !ended else { return }
        let defaults=SharedSettings.defaults
        // Opened from an alarm's "Open sky", which turned night vision on first: what it was before that.
        prior=(OpenSkyPrior.take() ?? defaults.bool(forKey: "nightVision"), screen?.brightness, UIApplication.shared.isIdleTimerDisabled)
        setNightVision(true)
        dim()
        UIApplication.shared.isIdleTimerDisabled=true
        lastTouch=Date.now
        defaults.set(park.id, forKey: FieldModeRequest.lastParkKey)
        let center=NotificationCenter.default
        observers=[
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.left() } },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.restoreBrightness() } },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.dim() } },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.returned() } },
            // A hot phone rests its compass until it cools; the sky view keeps the last direction.
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in MainActor.assumeIsolated { FieldSession.applyThermalState() } },
        ]
        FieldSession.applyThermalState()
        if UserDefaults.standard.object(forKey: "fieldLiveActivity") as? Bool ?? true { follow(true) }
        // Both loops hold the session only while they act, never across a sleep, so a session whose
        // window went away is released rather than kept alive by its own clock.
        ticker=Task { [weak self] in
            while !Task.isCancelled {
                guard let step=self?.upcoming() else { return }
                try? await Task.sleep(for: .seconds(step.wait))
                guard !Task.isCancelled, let self else { return }
                await self.pass(step.next)
            }
        }
        idleWatch=Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                self.checkIdle()
            }
        }
    }
    /// A touch on the field screen: the screen stays awake again.
    func touched(at now: Date = .now) {
        lastTouch=now
        if changesPhone, prior != nil, !UIApplication.shared.isIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled=true }
    }
    /// Auto-lock returns once the screen has gone untouched for `idleAfter`.
    static func autoLockReturns(lastTouch: Date, now: Date) -> Bool { now.timeIntervalSince(lastTouch)>=idleAfter }
    private func checkIdle(now: Date = .now) {
        guard changesPhone, let prior, Self.autoLockReturns(lastTouch: lastTouch, now: now), UIApplication.shared.isIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled=prior.idle
    }
    private static func applyThermalState() {
        FieldMotion.shared.rest(PowerState.serious(ProcessInfo.processInfo.thermalState))
    }
    func end() {
        ended=true
        // A kept "Open sky" value belongs to the session that tap opened, never to a later one.
        SharedSettings.defaults.removeObject(forKey: OpenSkyPrior.key)
        ticker?.cancel(); ticker=nil
        idleWatch?.cancel(); idleWatch=nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers=[]
        FieldMotion.shared.stop()
        // The night's activity, if it runs on, follows the forecast again.
        FieldActivities.release(parkID: park.id)
        guard let prior else { return }
        self.prior=nil
        // A Stargazing Focus that switched night vision on keeps it on.
        if !StargazingFocus.holdsNightVision() { setNightVision(prior.nightVision) }
        if let brightness=prior.brightness { screen?.brightness=brightness }
        UIApplication.shared.isIdleTimerDisabled=prior.idle
        Task { await FieldActivities.refresh(nightVision: SharedSettings.defaults.bool(forKey: "nightVision")) }
    }
    /// Start or stop the Lock Screen countdown; remembered as the default for next time.
    func follow(_ on: Bool) {
        if changesPhone { UserDefaults.standard.set(on, forKey: "fieldLiveActivity") }
        following=on && FieldActivities.enabled
        guard changesPhone else { return }
        Task {
            if on { await FieldActivities.start(night: night, score: score, scoredAt: scoredAt, nightVision: true, closure: closure, now: now) } else { await FieldActivities.stop() }
            following=FieldActivities.isFollowing(park)
        }
    }
    /// "My screen stayed dark."
    func keepAdaptation() {
        if let reset { adaptation.undo(reset) }
        reset=nil
    }

    private var screen: UIScreen? {
        let scenes=UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }
    private func dim() {
        guard let screen, let prior else { return }
        if let level=Self.dimmed(from: prior.brightness, legible: Self.needsLegibleLight, keep: keepsBrightness) { screen.brightness=level }
        else if let brightness=prior.brightness { screen.brightness=brightness }
    }
    /// "Keep my brightness": the screen goes back to the person's own level, and stays there each time.
    func keepBrightness(_ on: Bool) {
        keepsBrightness=on
        guard changesPhone else { return }
        UserDefaults.standard.set(on, forKey: Self.keepBrightnessKey)
        dim()
    }
    private func restoreBrightness() {
        if let brightness=prior?.brightness { screen?.brightness=brightness }
    }
    private func setNightVision(_ on: Bool) {
        SharedSettings.defaults.set(on, forKey: "nightVision")
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadControls(ofKind: "NightVisionControl")
    }
    private func left() { adaptation.leave(at: now) }
    private func returned() {
        if let reset=adaptation.returned(at: now) { self.reset=reset }
        Task { await FieldActivities.refresh(nightVision: true, now: now) }
    }
    /// The ticker sleeps until each milestone (five minutes at most, then looks again), then marks it.
    private func upcoming() -> (next: FieldNight.Milestone, wait: TimeInterval)? {
        guard let next=night.next(after: now) else { return nil }
        return (next, min(max(1, next.date.timeIntervalSince(now)), 300))
    }
    /// A milestone reached: a tick, a spoken line, a Live Activity update.
    private func pass(_ next: FieldNight.Milestone) async {
        guard now>=next.date else { return }
        // Milestones that passed while Nyx was away are not announced late.
        guard now.timeIntervalSince(next.date)<90 else { return }
        milestonesPassed+=1
        if next.kind == .darkness { darknessBegan+=1 }
        AccessibilityNotification.Announcement("\(next.title). \(next.detail)").post()
        if changesPhone { await FieldActivities.refresh(nightVision: true, now: now) }
    }
}

/// Field mode covers the whole screen from wherever it is opened: park detail, Tonight, a park
/// sheet over another sheet, Control Center, Siri or the Live Activity. Presented from the top of
/// the asking window's stack (`SceneCommands.topController`), like parks opened from reminders, so
/// nothing the person was doing is dismissed and another iPad window is never covered.
@MainActor enum FieldPresenter {
    /// Field mode is for a phone or iPad held up to the sky. On a Mac running the iPad app there is
    /// no sky to point at and no Lock Screen, so it is simply not offered.
    static var supported: Bool { !ProcessInfo.processInfo.isiOSAppOnMac }
    /// Field mode covers one window. A constellation under it holds a new star until it closes;
    /// another iPad window's is never held. Each open host is held weakly and counts only while it
    /// stands in a connected window, so a window closed with field mode open never leaves a stale flag.
    private static var hosts: [WeakHost]=[]
    private final class WeakHost { weak var host: FieldHostingController?; init(_ host: FieldHostingController) { self.host=host } }
    /// Posted when field mode opens or closes in any window.
    static let changed=Notification.Name("com.harrypakhale.nyx.fieldModeChanged")
    /// Whether field mode covers this scene's window (any window, before the scene is known).
    static func isOpen(in scene: UIWindowScene?) -> Bool {
        hosts.contains { box in
            guard let shown=box.host?.viewIfLoaded?.window?.windowScene else { return false }
            return scene == nil || shown === scene
        }
    }
    static func setOpen(_ open: Bool, host: FieldHostingController) {
        hosts.removeAll { $0.host == nil || $0.host === host }
        if open { hosts.append(WeakHost(host)) }
        NotificationCenter.default.post(name:changed,object:nil)
    }
    static func present(park: Park, model: PlanModel, from controller: UIViewController?) {
        // Field mode keeps the night's score for the whole session: opened from Control Center on a slow
        // launch, it waits for the offline caches (`ScoreGate`) rather than keeping a score they would change.
        if model.cachesPending {
            Task { [weak controller] in await model.cachesReady(); present(park: park, model: model, from: controller) }
            return
        }
        guard supported, var top=controller else { return }
        while let next=top.presentedViewController { top=next }
        if let open=top as? FieldHostingController {
            // Already in the field: a different park replaces it; the same park stays.
            guard open.parkID != park.id else { return }
            open.close { [weak top=open.presentingViewController] in present(park: park, model: model, from: top) }
            return
        }
        let session=FieldSession(park: park, model: model)
        let host=FieldHostingController(parkID: park.id)
        host.rootView=AnyView(FieldView(session: session) { [weak host] in host?.close() }.environment(model).nyxAccessibility())
        host.onClose={ session.end() }
        host.onTouch={ [weak session] in session?.touched() }
        host.modalPresentationStyle = .fullScreen
        host.modalTransitionStyle = .crossDissolve
        top.present(host, animated: true) { session.begin() }
    }
}
/// Field mode's window cover. The session ends (brightness, auto-lock and night vision put back)
/// whenever the cover goes for good: closed, taken down with what it was shown over, its iPad
/// window closed, or released. A sheet over field mode, the Lock Screen or leaving the app is not
/// an ending: the cover stays presented and the night carries on.
final class FieldHostingController: UIHostingController<AnyView> {
    let parkID: String
    var onClose: (()->Void)?
    var onTouch: (()->Void)?
    private var sceneObserver: NSObjectProtocol?
    init(parkID: String) { self.parkID=parkID; super.init(rootView: AnyView(EmptyView())) }
    isolated deinit {
        if let sceneObserver { NotificationCenter.default.removeObserver(sceneObserver) }
        if let onClose { onClose(); FieldPresenter.setOpen(false,host:self) }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        // Watches touches without taking any: every control works exactly as before.
        let watcher=TouchWatcher { [weak self] in self?.onTouch?() }
        view.addGestureRecognizer(watcher)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        FieldPresenter.setOpen(true,host:self)
        watchScene()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Something shown over field mode leaves it presented (and its presenter set): not an ending.
        if isBeingDismissed || presentingViewController == nil { finish() }
    }
    /// Closing an iPad window disconnects its scene without dismissing anything in it.
    private func watchScene() {
        guard sceneObserver == nil, let scene=view.window?.windowScene else { return }
        sceneObserver=NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: scene, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
    }
    /// The session ends once, however field mode ended.
    private func finish() {
        if let sceneObserver { NotificationCenter.default.removeObserver(sceneObserver); self.sceneObserver=nil }
        onClose?(); onClose=nil
        FieldPresenter.setOpen(false,host:self)
    }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    func close(then: (()->Void)?=nil) {
        onClose?(); onClose=nil
        dismiss(animated: true) { then?() }
    }
}
/// Sees each touch begin and then steps aside, so it never delays or cancels another gesture.
final class TouchWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) {
        self.action=action
        super.init(target: nil, action: nil)
        cancelsTouchesInView=false
        delaysTouchesBegan=false
        delaysTouchesEnded=false
        delegate=self
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        action()
        state = .failed
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
