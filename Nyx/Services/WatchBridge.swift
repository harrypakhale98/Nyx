#if canImport(WatchConnectivity) && os(iOS)
import Foundation
import WatchConnectivity

/// Hands Apple Watch what it cannot know on its own (saved parks, the starting park, night
/// vision, the last cloud forecasts) as WatchConnectivity application context: device to
/// device, never through a server. Does nothing when no watch is paired or Nyx is not on it.
nonisolated final class WatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchBridge()
    /// Guards `latest` and `lastSent`; WatchConnectivity calls back on its own queue.
    private let lock = NSLock()
    private var latest: WatchContext?
    private var lastSent: Data?
    private override init() { super.init() }
    /// False where no watch can ever pair (iPad), so nothing is worked out for one.
    static var isAvailable: Bool { WCSession.isSupported() }

    /// Called wherever the widget snapshot is written, and when night vision or the starting park
    /// changes (`SavedSkySync.pushWatch`). Cheap when there is no watch.
    func push(savedParkIDs: [String], homeParkID: String, forecasts: [String: Forecast], details: [String: ForecastDetail],
              closures: [String: String], aboveInversion: Set<String>, ranges: [String: [String: ClosedRange<Int>]]) {
        guard WCSession.isSupported() else { return }
        let nightVision = SharedSettings.defaults.bool(forKey: "nightVision")
        let context = WatchContext.make(savedParkIDs: savedParkIDs, homeParkID: homeParkID, nightVision: nightVision, forecasts: forecasts,
                                        details: details, closures: closures, aboveInversion: aboveInversion, ranges: ranges)
        let session = WCSession.default
        lock.withLock { latest = context }
        if session.activationState == .activated { send(session) }
        else { session.delegate = self; session.activate() }
    }
    private func send(_ session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }
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
        if state == .activated { send(session) }
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
#endif
