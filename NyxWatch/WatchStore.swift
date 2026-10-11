import Foundation
import Observation
import Synchronization
import UserNotifications
import WatchConnectivity
import WidgetKit

/// The watch's state: bundled parks, the last context from the iPhone, and the wearer's choices.
/// Every night is computed here, on the wrist, from the same engine the iPhone uses.
@Observable final class WatchStore {
    let parks: [Park]
    private(set) var context: WatchContext?
    var palette: PaletteChoice { didSet { WatchSky.palette = palette; publish() } }
    private(set) var pinned: String?
    /// The dark-adaptation clock, if one is running; it survives relaunches for one night.
    private(set) var adaptation: AdaptationClock?
    /// The reminders' permission as the last start found it, so a clock started from Siri or the
    /// control (while the first-time question may still be up) reaches the open screen.
    private(set) var reminderStatus: UNAuthorizationStatus?
    /// "Update from iPhone": the last request and its answer, shown beside an old forecast.
    private(set) var ask: IPhoneAsk?
    @ObservationIgnored private var skies: [String: SkyConditions] = [:]
    @ObservationIgnored private let receiver = WatchReceiver()

    init() {
        parks = ((try? ParkData.load()) ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        context = WatchSky.readContext()
        palette = WatchSky.palette
        pinned = WatchSky.pinnedPark
        adaptation = WatchSky.adaptationStart.map(AdaptationClock.init(start:))
        #if DEBUG
        WatchDebug.apply(to: self)
        #endif
        // Awaited by the receiver, so a background wake knows when the context is stored and the face reloaded.
        receiver.onContext = { [weak self] context in await self?.apply(context) }
        receiver.activate()
    }
    func apply(_ context: WatchContext) {
        // An older context arriving late (a queued transfer) never replaces a newer one.
        if let current = self.context, current.sent > context.sent { return }
        self.context = context
        WatchSky.save(context)
        publish()
    }
    /// Asks Nyx on iPhone, when it can be reached, to refresh and hand over the context again
    /// (`WatchRequest` on the iPhone). The answer comes at once; the context follows by the usual
    /// path. The watch itself still makes no network request.
    func askIPhone(at now: Date = .now) {
        guard ask?.state != .asking else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { ask = IPhoneAsk(.unreachable, at: now); return }
        let session = WCSession.default
        guard session.isReachable else {
            ask = IPhoneAsk(session.iOSDeviceNeedsUnlockAfterRebootForReachability ? .locked : .unreachable, at: now)
            return
        }
        ask = IPhoneAsk(.asking, at: now)
        session.sendMessage(IPhoneAsk.message, replyHandler: { @Sendable reply in
            let state = IPhoneAsk.state(reply: reply[IPhoneAsk.replyKey] as? String)
            Task { @MainActor in self.answered(state) }
        }, errorHandler: { @Sendable _ in
            Task { @MainActor in self.answered(.unreachable) }
        })
    }
    private func answered(_ state: IPhoneAsk.State) {
        guard ask?.state == .asking else { return }
        ask = IPhoneAsk(state, at: .now)
    }
    /// A bundled park, or a place the iPhone sent (a saved spot or a followed world catalogue place).
    func park(_ id: String?) -> Park? { id.flatMap { WatchSky.place($0, in: parks, context: context) } }
    /// Red or not at `now`: Automatic follows the Sun at the park on Tonight.
    func nightVision(at now: Date) -> Bool { WatchSky.nightVision(palette, context: context, park: featured(at: now), at: now) }
    /// The Control Center control writes the palette from another process: read it again on return.
    func reloadSettings() {
        let stored = WatchSky.palette
        if stored != palette { palette = stored }
        if let clock = adaptation, clock.isStale(at: .now) { stopAdaptation() }
    }
    /// Starts the clock at once, then schedules the reminders (asking for permission the first
    /// time) and returns the answer, so the screen knows whether to tap the wrist itself.
    @discardableResult func startAdaptation(at now: Date = .now) async -> UNAuthorizationStatus {
        let clock = AdaptationClock(start: now)
        adaptation = clock
        WatchSky.adaptationStart = now
        let status = await AdaptationReminders.schedule(clock, now: now)
        reminderStatus = status
        return status
    }
    func stopAdaptation() {
        adaptation = nil
        WatchSky.adaptationStart = nil
        AdaptationReminders.cancel()
    }
    var savedParks: [Park] { (context?.savedParkIDs ?? []).compactMap(park) }
    /// The park on Tonight: the one kept on the watch, else the darkest saved park tonight (ties
    /// broken as everywhere, `NightPlanner.best`), else the iPhone's starting park.
    func featured(at now: Date) -> Park? {
        NightPlanner.best(WatchSky.candidates(in: parks, context: context, pinned: pinned).map { tonight($0, at: now) })?.park
    }
    func pin(_ park: Park?) {
        pinned = park?.id
        WatchSky.pinnedPark = park?.id
        publish()
    }
    func tonight(_ park: Park, at now: Date) -> Night { night(park, offset: 0, at: now) }
    func night(_ park: Park, offset: Int, at now: Date) -> Night {
        let evening = park.date(park.currentNight(at: now), addingDays: offset)
        let key = "\(park.id)-\(Int(evening.timeIntervalSince1970))"
        let sky = skies[key] ?? AstronomyEngine().conditions(for: park, on: evening)
        if skies.count > 120 { skies.removeAll() }
        skies[key] = sky
        return WatchSky.night(park, evening: evening, forecast: context?.cloudForecasts[park.id], detail: context?.forecastDetails[park.id], now: now, sky: sky)
    }
    func week(_ park: Park, at now: Date) -> [Night] { (0..<7).map { night(park, offset: $0, at: now) } }
    /// Hand the complications what Tonight shows, then ask them and the Smart Stack to look again.
    func publish() {
        WatchSky.publish(parks: WatchSky.candidates(in: parks, context: context, pinned: pinned), context: context)
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.invalidateRelevance(ofKind: "NyxDusk")
        WidgetCenter.shared.invalidateConfigurationRecommendations()
        ControlCenter.shared.reloadControls(ofKind: WatchSky.redLightKind)
    }
    /// For a WatchConnectivity background wake: wait (briefly, ten seconds at most) until the session
    /// is up, nothing more is queued, and every context it handed over is stored and published, so
    /// the system never ends the wake before the complications have been asked to reload.
    func receivePending() async {
        guard WCSession.isSupported() else { return }
        receiver.activate()
        for _ in 0..<20 {
            guard receiver.isSettling || WCSession.default.hasContentPending else { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
    #if DEBUG
    func debugSet(context: WatchContext?, pinned: String?) {
        self.context = context
        self.pinned = pinned
    }
    func debugSet(adaptation: AdaptationClock?) { self.adaptation = adaptation }
    func debugSet(ask: IPhoneAsk?) { self.ask = ask }
    #endif
}

/// Listens for the iPhone's context. WatchConnectivity calls back on its own queue, so this
/// object holds only the callback and a count of what is still on its way to the main actor.
nonisolated final class WatchReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    var onContext: (@Sendable (WatchContext) async -> Void)?
    /// Whether activation has finished (and handed over the context it found), and how many
    /// contexts were received but are not yet stored and published.
    private let state = Mutex((activated: false, applying: 0))
    /// True until activation has finished and every received context has been applied.
    var isSettling: Bool { state.withLock { !$0.activated || $0.applying > 0 } }
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        // Already activated means this receiver's delegate call has come or is on its way; it alone marks activation finished.
        guard session.activationState != .activated else { return }
        session.delegate = self
        session.activate()
    }
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        // Counted before activation reads as finished, so a background wake never sees a gap between the two.
        if state == .activated { receive(session.receivedApplicationContext) }
        self.state.withLock { $0.activated = true }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    /// Complication transfers carry the same context, sent when a Nyx complication is on the face.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receive(userInfo) }
    /// Counted here, synchronously on WatchConnectivity's queue, so `hasContentPending` turning
    /// false never runs ahead of the context it delivered.
    private func receive(_ dictionary: [String: Any]) {
        guard let context = WatchContext(dictionary: dictionary), let onContext else { return }
        state.withLock { $0.applying += 1 }
        Task {
            await onContext(context)
            self.state.withLock { $0.applying -= 1 }
        }
    }
}
