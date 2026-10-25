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
    /// The iPhone's Moon pictures for the nights the wrist shows (`WatchMoons`); the dial draws the
    /// vector Moon for any night without one.
    private(set) var moons: WatchMoons?
    var palette: PaletteChoice {
        didSet {
            guard palette != oldValue else { return }
            WatchSky.palette = palette
            publish()
        }
    }
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
    /// When the places were last sent unasked (`tellIPhone`), so two wakes a moment apart send them once.
    @ObservationIgnored private var lastTell: Date?

    init() {
        parks = ((try? ParkData.load()) ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        context = WatchSky.readContext()
        moons = WatchMoons.readStored()
        palette = WatchSky.palette
        pinned = WatchSky.pinnedPark
        adaptation = WatchSky.adaptationStart.map(AdaptationClock.init(start:))
        #if DEBUG
        WatchDebug.apply(to: self)
        #endif
        // Awaited by the receiver, so a background wake knows when the context is stored and the face reloaded.
        receiver.onContext = { [weak self] context in await self?.apply(context) }
        receiver.onMoons = { [weak self] moons in await self?.apply(moons) }
        receiver.onReachable = { [weak self] in await self?.tellIPhoneIfNeeded() }
        receiver.activate()
        // An update may change what the faces read (the bundled parks, the snapshot's shape) while
        // the stored context is unchanged, and an unchanged context is never applied again: write
        // the snapshot now. Nothing reloads unless it was rewritten.
        publish(force: false)
    }
    func apply(_ context: WatchContext) {
        // Each send arrives twice (application context, and a complication transfer while a Nyx
        // complication is on the face), activation hands the stored one over again at launch, and a
        // queued transfer may arrive late: only a newer context is applied (`WatchContext.isNewer`).
        let previous = self.context
        guard WatchContext.isNewer(context, than: previous) else { return }
        self.context = context
        WatchSky.save(context)
        // The faces read the context too, so they reload when what it says changed, not only when it was sent again.
        publish(force: previous?.sent(at: .distantPast) != context.sent(at: .distantPast))
    }
    /// A newer set of Moon pictures replaces the stored one whole, less any night already over, so
    /// the watch keeps one small file that never grows.
    func apply(_ moons: WatchMoons, now: Date = .now) {
        guard WatchMoons.isNewer(moons, than: self.moons) else { return }
        let kept = moons.pruned(before: now.addingTimeInterval(-2*86400))
        kept.store()
        self.moons = kept
    }
    /// Asks Nyx on iPhone, when it can be reached, to refresh and hand over the context again
    /// (`WatchRequest` on the iPhone). The answer comes at once; the context follows by the usual
    /// path. The watch itself still makes no network request.
    func askIPhone(at now: Date = .now) {
        guard ask?.current(at: now) != .asking else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { ask = IPhoneAsk(.unreachable, at: now); return }
        let session = WCSession.default
        guard session.isReachable else {
            ask = IPhoneAsk(session.iOSDeviceNeedsUnlockAfterRebootForReachability ? .locked : .unreachable, at: now)
            return
        }
        ask = IPhoneAsk(.asking, at: now)
        let places = WatchSky.wantedPlaces(pinned: pinned)
        session.sendMessage(IPhoneAsk.message(places: places), replyHandler: { @Sendable reply in
            let state = IPhoneAsk.state(reply: reply[IPhoneAsk.replyKey] as? String)
            Task { @MainActor in
                if state != .unreachable { WatchSky.told = (places, .now) }
                self.answered(state)
            }
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
    /// Red or not at `now`: At dusk follows the Sun at the park on Tonight.
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
    /// broken as everywhere, `NightPlanner.best`), else Tonight's answer on the iPhone, else its starting park.
    func featured(at now: Date) -> Park? {
        NightPlanner.best(WatchSky.candidates(in: parks, context: context, pinned: pinned, now: now).map { tonight($0, at: now) })?.park
    }
    /// Which rule Tonight follows (`WatchSky.choice`), for its caption.
    func rule(at now: Date) -> WatchSky.Rule? { WatchSky.choice(in: parks, context: context, pinned: pinned, now: now).rule }
    func pin(_ park: Park?) {
        guard park?.id != pinned else { return }
        pinned = park?.id
        WatchSky.pinnedPark = park?.id
        publish()
        tellIPhone()
    }
    /// A newly kept place has clouds only once the iPhone follows it: when it can be reached, it is
    /// told at once, quietly, as "Update from iPhone" would tell it. Otherwise it is told the next
    /// time Nyx opens or the iPhone comes within reach (`tellIPhoneIfNeeded`).
    private func tellIPhone(at now: Date = .now) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        let places = WatchSky.wantedPlaces(pinned: pinned)
        lastTell = now
        WCSession.default.sendMessage(IPhoneAsk.message(places: places), replyHandler: { @Sendable _ in
            Task { @MainActor in WatchSky.told = (places, .now) }
        }, errorHandler: { @Sendable _ in })
    }
    /// As Nyx opens and when the iPhone comes within reach: tells it the places this watch wants
    /// clouds for (the one kept on Tonight, those its faces are set to) when its last context follows
    /// others: a place kept while it was out of reach, a face set to a park it does not follow. Once
    /// per list (`WatchContext.shouldTell`), and never twice within a few seconds.
    func tellIPhoneIfNeeded(at now: Date = .now) {
        let told = WatchSky.told
        guard WatchContext.shouldTell(WatchSky.wantedPlaces(pinned: pinned), context: context, told: told?.places, toldAt: told?.at, now: now),
              lastTell.map({ abs(now.timeIntervalSince($0)) >= 30 }) ?? true else { return }
        tellIPhone(at: now)
    }
    func tonight(_ park: Park, at now: Date) -> Night { night(park, offset: 0, at: now) }
    func night(_ park: Park, offset: Int, at now: Date) -> Night {
        let evening = park.date(park.currentNight(at: now), addingDays: offset)
        if skies.count > 120 { skies.removeAll() }
        let sky = WatchTimeline.sky(park, evening: evening, cache: &skies)
        return WatchSky.night(park, evening: evening, forecast: context?.cloudForecasts[park.id], detail: context?.forecastDetails[park.id], now: now, sky: sky,
                              climate: context?.climate ?? .shared)
    }
    func week(_ park: Park, at now: Date) -> [Night] { (0..<7).map { night(park, offset: $0, at: now) } }
    /// Hand the complications what Tonight shows, then ask them and the Smart Stack to look again:
    /// always when `force` (the palette, the pin or the context's contents changed), else only when
    /// what they read was rewritten.
    func publish(force: Bool = true) {
        let written = WatchSky.publish(parks: WatchSky.candidates(in: parks, context: context, pinned: pinned, now: .now), context: context)
        guard force || written else { return }
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
    /// Runs with each set of Moon pictures the iPhone sends (`WatchMoons`).
    var onMoons: (@Sendable (WatchMoons) async -> Void)?
    /// Whether activation has finished (and handed over the context it found), and how many
    /// contexts (and Moon sets) were received but are not yet stored and published.
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
    /// Runs when the iPhone comes within reach, and when activation finds it in reach.
    var onReachable: (@Sendable () async -> Void)?
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        // Counted before activation reads as finished, so a background wake never sees a gap between the two.
        if state == .activated { receive(session.receivedApplicationContext) }
        self.state.withLock { $0.activated = true }
        if state == .activated, session.isReachable { reachable() }
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { reachable() }
    }
    private func reachable() {
        guard let onReachable else { return }
        Task { await onReachable() }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    /// Complication transfers carry the same context, sent when a Nyx complication is on the face.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receive(userInfo) }
    /// The iPhone's Moon pictures. Read here, before returning: WatchConnectivity removes the file then.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[WatchMoons.metadataKey] != nil, let data = try? Data(contentsOf: file.fileURL), let moons = WatchMoons(data: data),
              let onMoons else { return }
        state.withLock { $0.applying += 1 }
        Task {
            await onMoons(moons)
            self.state.withLock { $0.applying -= 1 }
        }
    }
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
