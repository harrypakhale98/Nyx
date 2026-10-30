#if canImport(WatchConnectivity) && os(iOS)
import Foundation
import WatchConnectivity

/// Hands Apple Watch what it cannot know on its own (saved parks, the starting park, night
/// vision, the last cloud forecasts) as WatchConnectivity application context: device to
/// device, never through a server. Does nothing when no watch is paired or Nyx is not on it.
nonisolated final class WatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchBridge()
    /// Guards every stored property below; WatchConnectivity calls back on its own queue.
    private let lock = NSLock()
    private var latest: WatchContext?
    private var lastSent: Data?
    /// Set when `latest` left out the models' ranges because no watch with Nyx was known yet:
    /// called on the main actor, instead of sending, once one is, to hand over a complete context.
    private var complete: (@MainActor @Sendable () -> Void)?
    /// What runs when the watch asks for its context ("Update from iPhone"): set by `SavedSkySync`
    /// once it has the model. A request heard before then waits in `requested`.
    private var onRequest: (@MainActor @Sendable () -> Void)?
    private var requested = false
    private var activating = false
    private override init() { super.init() }
    /// The places Apple Watch last asked the iPhone to follow (`WatchRequest.places`): the one kept
    /// on its Tonight and those its complications are set to. Kept across launches, so a background
    /// refresh carries their clouds too.
    static var requestedParkIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: WatchRequest.placesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: WatchRequest.placesKey) }
    }
    /// The number of the last context handed to WatchConnectivity (`WatchContext.sequence`), kept
    /// across launches so the next one is always higher.
    static var lastSequence: Int64? {
        get { (UserDefaults.standard.object(forKey: sequenceKey) as? NSNumber)?.int64Value }
        set { UserDefaults.standard.set(newValue.map { NSNumber(value: $0) }, forKey: sequenceKey) }
    }
    private static let sequenceKey = "watchContextSequence"
    /// False where no watch can ever pair (iPad), so nothing is worked out for one.
    static var isAvailable: Bool { WCSession.isSupported() }
    /// True only once the session is active with a paired watch that has Nyx on it. The models'
    /// ranges are worked out only then: on an iPhone with no watch (most of them) the night-vision
    /// switch and every publish cost nothing for one.
    var hasWatchApp: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    /// Called wherever the widget snapshot is written, and when night vision or the starting park
    /// changes (`SavedSkySync.pushWatch`). Cheap when there is no watch: once the session knows no
    /// watch with Nyx is paired, nothing is worked out, and `complete` hands over again when one is.
    /// `ranges` is nil when they were not worked out (`hasWatchApp` was false); `complete` then hands
    /// over again, with them, once a watch with Nyx turns out to be there. `tonightNight`: the
    /// place-local night Tonight's answer was picked for (`PlanModel.tonightPickNight`).
    func push(savedParkIDs: [String], homeParkID: String, tonightParkID: String? = nil, tonightNight: String? = nil, watchParkIDs: [String] = [], forecasts: [String: Forecast],
              details: [String: ForecastDetail], closures: [String: String], aboveInversion: Set<String>, ranges: [String: [String: ClosedRange<Int>]]?, places: [Place] = [],
              aurora: AuroraOutlook? = nil, dusk: [Double]? = nil, checkedParkIDs: Set<String>? = nil, complete: (@MainActor @Sendable () -> Void)? = nil) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        // No watch with Nyx paired: nothing is worked out for one, and `complete` hands over once there
        // is (`sessionWatchStateDidChange`). Still activating, it is made as before, ready to go at once.
        // A push with no `complete` of its own (its caller believed a watch was there) keeps the one
        // already armed, so a watch paired later is never left waiting for the next publish.
        if session.activationState == .activated, !(session.isPaired && session.isWatchAppInstalled) {
            lock.withLock { latest = nil; self.complete = complete ?? self.complete }
            return
        }
        let nightVision = SharedSettings.defaults.bool(forKey: NightLook.nightVisionKey), brighterRed = SharedSettings.defaults.bool(forKey: NightTint.key)
        let context = WatchContext.make(savedParkIDs: savedParkIDs, homeParkID: homeParkID, nightVision: nightVision, brighterRed: brighterRed, forecasts: forecasts,
                                        details: details, closures: closures, aboveInversion: aboveInversion, ranges: ranges ?? [:], places: places,
                                        tonightParkID: tonightParkID, tonightNight: tonightNight, watchParkIDs: watchParkIDs, aurora: aurora,
                                        spotForecastsOff: !SpotForecast.isOn(), dusk: dusk,
                                        alertsOff: !NetworkService.alerts.isOn(), smokeOff: !NetworkService.smoke.isOn(), checkedParkIDs: checkedParkIDs)
        lock.withLock { latest = context; self.complete = ranges == nil ? complete : nil }
        if session.activationState == .activated { send(session) } else { activate() }
    }
    /// Sets the delegate and activates the session, as Apple asks apps to at launch: a message from
    /// the watch that launched Nyx is delivered only to an active session. Cheap and once only.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState != .activated, lock.withLock({ () -> Bool in defer { activating = true }; return !activating }) else { return }
        session.delegate = self
        session.activate()
    }
    /// `handler` runs on the main actor each time the watch asks for its context; a request that
    /// came before anyone listened runs now.
    func listen(_ handler: @escaping @MainActor @Sendable () -> Void) {
        guard WCSession.isSupported() else { return }
        let pending = lock.withLock { () -> Bool in
            onRequest = handler
            defer { requested = false }
            return requested
        }
        if pending { Task { @MainActor in handler() } }
        activate()
    }
    private func send(_ session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }
        // A context made before a watch was known lacks the ranges: make it again, complete, rather than send it.
        if let complete: @MainActor @Sendable () -> Void = lock.withLock({ defer { self.complete = nil }; return self.complete }) {
            Task { @MainActor in complete() }
            return
        }
        let context: WatchContext? = lock.withLock { latest }
        guard let context else { return }
        // The same parks, forecasts, smoke, closures, ranges and switch as last time: nothing to say.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let comparable = try? encoder.encode(context.sent(at: .distantPast))
        guard comparable == nil || lock.withLock({ comparable != lastSent }) else { return }
        // Numbered as it goes, so the watch tells it from an older one whatever this iPhone's clock
        // says. Taken under the lock, so two sends never share a number; one that fails leaves a gap.
        let sequence = lock.withLock { () -> Int64 in
            let next = WatchContext.nextSequence(after: Self.lastSequence)
            Self.lastSequence = next
            return next
        }
        guard let data = context.numbered(sequence).data else { return }
        // Remembered only once delivered to WatchConnectivity, so a failed update is retried next time.
        do { try session.updateApplicationContext([WatchContext.key: data]) } catch { return }
        lock.withLock { lastSent = comparable }
        // A complication on the current face may wake the watch app to refresh now (budgeted by the system).
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo([WatchContext.key: data])
        }
    }
    /// The key list (`WatchMoons.key`) of the Moon pictures last handed to WatchConnectivity, kept
    /// across launches: a picture never changes once drawn, so the same keys mean the same set.
    static var moonsSent: String? {
        get { UserDefaults.standard.string(forKey: moonsKey) }
        set { UserDefaults.standard.set(newValue, forKey: moonsKey) }
    }
    private static let moonsKey = "watchMoonsSent"
    /// Where the outgoing set waits until delivered: one file at a time, removed once sent or replaced.
    private static var moonsFolder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("WatchMoons", isDirectory: true)
    }
    /// Whether the pictures named by `keys` still have to go to the watch: a watch with Nyx is there
    /// and they are not the set last handed over. Checked before any picture is read or shrunk.
    func needsMoons(_ keys: String) -> Bool {
        hasWatchApp && lock.withLock { Self.moonsSent != keys }
    }
    /// Hands the watch its Moon pictures (`WatchMoons`) as one small file. Only the newest set is
    /// ever on its way: one still queued is cancelled and its file removed, so nothing accumulates
    /// on either side; the watch replaces its one stored copy.
    func send(moons: WatchMoons, keys: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled, let data = moons.data, let folder = Self.moonsFolder else { return }
        lock.withLock {
            guard Self.moonsSent != keys else { return }
            for transfer in session.outstandingFileTransfers where transfer.file.metadata?[WatchMoons.metadataKey] != nil { transfer.cancel() }
            try? FileManager.default.removeItem(at: folder)
            let url = folder.appendingPathComponent("moons-\(UUID().uuidString).plist")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch { return }
            session.transferFile(url, metadata: [WatchMoons.metadataKey: WatchMoons.currentVersion])
            Self.moonsSent = keys
        }
    }
    /// A set delivered, or cancelled for a newer one: its file goes. One that failed with no newer one
    /// queued is forgotten, so the next hand-over sends it again.
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard fileTransfer.file.metadata?[WatchMoons.metadataKey] != nil else { return }
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        guard error != nil else { return }
        lock.withLock {
            if !session.outstandingFileTransfers.contains(where: { $0.file.metadata?[WatchMoons.metadataKey] != nil }) { Self.moonsSent = nil }
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        lock.withLock { activating = false }
        if state == .activated { send(session) }
    }
    /// "Update from iPhone" on the watch. Answered at once, before any work: whether this iPhone
    /// will ask for fresh clouds or, with forecasts switched off, only hand over what it has. The
    /// context itself follows by application context, as always, and is sent even if unchanged.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let forecastsOn = NetworkService.forecasts.isOn()
        guard let reply = WatchRequest.reply(to: message, forecastsOn: forecastsOn) else { replyHandler([:]); return }
        replyHandler([WatchRequest.replyKey: reply.rawValue])
        // A watch before 2.2 names no places: what an earlier request asked for stays followed.
        if let places = WatchRequest.places(in: message) { Self.requestedParkIDs = places }
        let handler = lock.withLock { () -> (@MainActor @Sendable () -> Void)? in
            // The watch asked: the next hand-over goes even when it says nothing new.
            lastSent = nil
            if onRequest == nil { requested = true }
            return onRequest
        }
        if let handler { Task { @MainActor in handler() } }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    /// Switching to another watch: activate again so the new one receives the context and its Moons.
    func sessionDidDeactivate(_ session: WCSession) {
        lock.withLock { Self.moonsSent = nil }
        session.activate()
    }
    func sessionWatchStateDidChange(_ session: WCSession) {
        // Nyx was just installed on the watch: send what was last prepared.
        guard session.isWatchAppInstalled else { return }
        lock.withLock { lastSent = nil; Self.moonsSent = nil }
        send(session)
    }
}

/// The one message Apple Watch sends: "Update from iPhone" (`["request": "context"]`), naming the
/// places it wants clouds for (`places`). The watch spells the same strings (`IPhoneAsk` in
/// NyxWatch); the iPhone answers at once with `Reply`.
nonisolated enum WatchRequest {
    static let key = "request"
    static let context = "context"
    static let replyKey = "reply"
    static let placesKey = "places"
    /// More than a watch could show at once; a longer list is cut, never refused. The watch asks for
    /// no more than this (`WatchContext.maxWatchPlaces`).
    static let maxPlaces = WatchContext.maxWatchPlaces
    /// The places a request names, each a valid place id (`PlaceIDText`), once, in order; nil from a
    /// watch before 2.2, which names none.
    static func places(in message: [String: Any]) -> [String]? {
        guard let raw = message[placesKey] as? [String] else { return nil }
        var seen = Set<String>()
        return Array(raw.compactMap(PlaceIDText.validated).filter { seen.insert($0).inserted }.prefix(maxPlaces))
    }
    enum Reply: String, Sendable {
        /// Asking Open-Meteo for the saved parks' clouds, then handing the context over.
        case refreshing
        /// Cloud forecasts are switched off on this iPhone: the context goes again as it is.
        case resending
    }
    /// Nil for anything other than a request for the context, which is answered with an empty reply.
    static func reply(to message: [String: Any], forecastsOn: Bool) -> Reply? {
        guard message[key] as? String == context else { return nil }
        return forecastsOn ? .refreshing : .resending
    }
}
#endif
