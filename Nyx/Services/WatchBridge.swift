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
    /// changes (`SavedSkySync.pushWatch`). Cheap when there is no watch. `ranges` is nil when they
    /// were not worked out (`hasWatchApp` was false); `complete` then hands over again, with them,
    /// once a watch with Nyx turns out to be there.
    func push(savedParkIDs: [String], homeParkID: String, forecasts: [String: Forecast], details: [String: ForecastDetail],
              closures: [String: String], aboveInversion: Set<String>, ranges: [String: [String: ClosedRange<Int>]]?,
              complete: (@MainActor @Sendable () -> Void)? = nil) {
        guard WCSession.isSupported() else { return }
        let nightVision = SharedSettings.defaults.bool(forKey: "nightVision")
        let context = WatchContext.make(savedParkIDs: savedParkIDs, homeParkID: homeParkID, nightVision: nightVision, forecasts: forecasts,
                                        details: details, closures: closures, aboveInversion: aboveInversion, ranges: ranges ?? [:])
        let session = WCSession.default
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
        guard let context, let data = context.data else { return }
        // The same parks, forecasts, smoke, closures, ranges and switch as last time: nothing to say.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let comparable = try? encoder.encode(context.sent(at: .distantPast))
        guard comparable == nil || lock.withLock({ comparable != lastSent }) else { return }
        // Remembered only once delivered to WatchConnectivity, so a failed update is retried next time.
        do { try session.updateApplicationContext([WatchContext.key: data]) } catch { return }
        lock.withLock { lastSent = comparable }
        // A complication on the current face may wake the watch app to refresh now (budgeted by the system).
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo([WatchContext.key: data])
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
        let forecastsOn = UserDefaults.standard.object(forKey: "weatherEnabled") as? Bool ?? true
        guard let reply = WatchRequest.reply(to: message, forecastsOn: forecastsOn) else { replyHandler([:]); return }
        replyHandler([WatchRequest.replyKey: reply.rawValue])
        let handler = lock.withLock { () -> (@MainActor @Sendable () -> Void)? in
            // The watch asked: the next hand-over goes even when it says nothing new.
            lastSent = nil
            if onRequest == nil { requested = true }
            return onRequest
        }
        if let handler { Task { @MainActor in handler() } }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    /// Switching to another watch: activate again so the new one receives the context.
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) {
        // Nyx was just installed on the watch: send what was last prepared.
        guard session.isWatchAppInstalled else { return }
        lock.withLock { lastSent = nil }
        send(session)
    }
}

/// The one message Apple Watch sends: "Update from iPhone" (`["request": "context"]`). The watch
/// spells the same strings (`IPhoneAsk` in NyxWatch); the iPhone answers at once with `Reply`.
nonisolated enum WatchRequest {
    static let key = "request"
    static let context = "context"
    static let replyKey = "reply"
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
