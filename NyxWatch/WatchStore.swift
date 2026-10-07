import Foundation
import Observation
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
        receiver.onContext = { [weak self] context in Task { @MainActor in self?.apply(context) } }
        receiver.activate()
    }
    func apply(_ context: WatchContext) {
        // An older context arriving late (a queued transfer) never replaces a newer one.
        if let current = self.context, current.sent > context.sent { return }
        self.context = context
        WatchSky.save(context)
        publish()
    }
    func park(_ id: String?) -> Park? { id.flatMap { id in parks.first { $0.id == id } } }
    /// Red or not at `now`: Automatic follows the Sun at the park on Tonight.
    func nightVision(at now: Date) -> Bool { WatchSky.nightVision(palette, context: context, park: featured(at: now), at: now) }
    /// The Control Center control writes the palette from another process: read it again on return.
    func reloadSettings() {
        let stored = WatchSky.palette
        if stored != palette { palette = stored }
        if let clock = adaptation, clock.isStale(at: .now) { stopAdaptation() }
    }
    func startAdaptation(at now: Date = .now) {
        let clock = AdaptationClock(start: now)
        adaptation = clock
        WatchSky.adaptationStart = now
        AdaptationReminders.schedule(clock, now: now)
    }
    func stopAdaptation() {
        adaptation = nil
        WatchSky.adaptationStart = nil
        AdaptationReminders.cancel()
    }
    var savedParks: [Park] { (context?.savedParkIDs ?? []).compactMap(park) }
    /// The park on Tonight: the one kept on the watch, else the darkest saved park tonight, else the iPhone's starting park.
    func featured(at now: Date) -> Park? {
        WatchSky.candidates(in: parks, context: context, pinned: pinned).max { tonight($0, at: now).score.value < tonight($1, at: now).score.value }
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
        return WatchSky.night(park, evening: evening, forecast: context?.cloudForecasts[park.id], now: now, sky: sky)
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
    /// For a WatchConnectivity background wake: wait (briefly) for whatever the iPhone queued.
    func receivePending() async {
        receiver.activate()
        for _ in 0..<20 where WCSession.default.hasContentPending { try? await Task.sleep(for: .milliseconds(500)) }
    }
    #if DEBUG
    func debugSet(context: WatchContext?, pinned: String?) {
        self.context = context
        self.pinned = pinned
    }
    func debugSet(adaptation: AdaptationClock?) { self.adaptation = adaptation }
    #endif
}

/// Listens for the iPhone's context. WatchConnectivity calls back on its own queue, so this
/// object holds no state beyond the callback and forwards everything to the main actor.
nonisolated final class WatchReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    var onContext: (@Sendable (WatchContext) -> Void)?
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState != .activated else { return }
        session.delegate = self
        session.activate()
    }
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        receive(session.receivedApplicationContext)
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    /// Complication transfers carry the same context, sent when a Nyx complication is on the face.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receive(userInfo) }
    private func receive(_ dictionary: [String: Any]) {
        guard let context = WatchContext(dictionary: dictionary) else { return }
        onContext?(context)
    }
}
