import Accessibility
import SwiftUI
import UIKit
import WidgetKit

/// One stretch of time in field mode: the park, its night, the eye's dark-adaptation clock, and
/// what field mode changed on the phone (night vision, screen brightness, auto-lock), each put back
/// exactly as it was on the way out. Leaving the app restores the brightness for other apps.
@MainActor @Observable final class FieldSession {
    let park: Park
    let night: FieldNight
    /// Read once on entry (field mode is one night); DEBUG captures set it again after a live refresh.
    var score: DarknessScore
    var adaptation: DarkAdaptation
    /// Set when the eye's clock started over on return, until acknowledged.
    var reset: DarkAdaptation.Reset?
    /// Haptic triggers: a light tick per milestone, a soft success when true darkness begins.
    var milestonesPassed=0
    var darknessBegan=0
    /// The night's Live Activity is running for this park.
    var following=false
    /// False for DEBUG screen routes: nothing on the phone is changed.
    @ObservationIgnored let changesPhone: Bool
    /// DEBUG only: shifts "now" so a screenshot can show a moment in the night.
    @ObservationIgnored private let offset: TimeInterval
    @ObservationIgnored private var prior: (nightVision: Bool, brightness: CGFloat?, idle: Bool)?
    @ObservationIgnored private var observers: [NSObjectProtocol]=[]
    @ObservationIgnored private var ticker: Task<Void,Never>?
    /// Below this the screen is never raised; above it, field mode lowers it here.
    static let brightness: CGFloat=0.12

    init(park: Park, model: PlanModel, changesPhone: Bool=true, offset: TimeInterval=0, adaptedFor: TimeInterval=0) {
        let tonight=model.night(park)
        self.park=park; self.score=tonight.score; self.night=FieldNight(park: park, sky: tonight.sky)
        self.changesPhone=changesPhone; self.offset=offset
        adaptation=DarkAdaptation(start: Date.now.addingTimeInterval(offset-adaptedFor))
        following=FieldActivities.isFollowing(park)
    }
    var now: Date { Date.now.addingTimeInterval(offset) }
    /// A night moment on the wall clock, for system timers that count against the real time.
    func real(_ date: Date) -> Date { date.addingTimeInterval(-offset) }

    func begin() {
        guard changesPhone, prior == nil else { return }
        let defaults=SharedSettings.defaults
        prior=(defaults.bool(forKey: "nightVision"), screen?.brightness, UIApplication.shared.isIdleTimerDisabled)
        setNightVision(true)
        dim()
        UIApplication.shared.isIdleTimerDisabled=true
        defaults.set(park.id, forKey: FieldModeRequest.lastParkKey)
        let center=NotificationCenter.default
        observers=[
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.left() } },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.restoreBrightness() } },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.dim() } },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.returned() } },
        ]
        if UserDefaults.standard.object(forKey: "fieldLiveActivity") as? Bool ?? true { follow(true) }
        ticker=Task { [weak self] in await self?.run() }
    }
    func end() {
        ticker?.cancel(); ticker=nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers=[]
        FieldMotion.shared.stop()
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
            if on { await FieldActivities.start(night: night, score: score, nightVision: true, now: now) } else { await FieldActivities.stop() }
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
        screen.brightness=min(prior.brightness ?? Self.brightness, Self.brightness)
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
    /// Sleeps until each milestone, then marks it: a tick, a spoken line, a Live Activity update.
    private func run() async {
        while !Task.isCancelled {
            guard let next=night.next(after: now) else { return }
            let wait=min(max(1, next.date.timeIntervalSince(now)), 300)
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, now>=next.date else { continue }
            // Milestones that passed while Nyx was away are not announced late.
            guard now.timeIntervalSince(next.date)<90 else { continue }
            milestonesPassed+=1
            if next.kind == .darkness { darknessBegan+=1 }
            AccessibilityNotification.Announcement("\(next.title). \(next.detail)").post()
            if changesPhone { await FieldActivities.refresh(nightVision: true, now: now) }
        }
    }
}

/// Field mode covers the whole screen from wherever it is opened: park detail, Tonight, a park
/// sheet over another sheet, Control Center, Siri or the Live Activity. Presented from the top of
/// UIKit's stack, like parks opened from reminders, so nothing the person was doing is dismissed.
@MainActor enum FieldPresenter {
    static func present(park: Park, model: PlanModel) {
        let root=UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        guard var top=root else { return }
        while let next=top.presentedViewController { top=next }
        if let open=top as? FieldHostingController {
            // Already in the field: a different park replaces it; the same park stays.
            guard open.parkID != park.id else { return }
            open.close { present(park: park, model: model) }
            return
        }
        let session=FieldSession(park: park, model: model)
        let host=FieldHostingController(parkID: park.id)
        host.rootView=AnyView(FieldView(session: session) { [weak host] in host?.close() }.environment(model).nyxAccessibility())
        host.onClose={ session.end() }
        host.modalPresentationStyle = .fullScreen
        host.modalTransitionStyle = .crossDissolve
        top.present(host, animated: true) { session.begin() }
    }
}
final class FieldHostingController: UIHostingController<AnyView> {
    let parkID: String
    var onClose: (()->Void)?
    init(parkID: String) { self.parkID=parkID; super.init(rootView: AnyView(EmptyView())) }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    func close(then: (()->Void)?=nil) {
        onClose?(); onClose=nil
        dismiss(animated: true) { then?() }
    }
}
