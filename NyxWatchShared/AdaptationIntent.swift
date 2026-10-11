import AppIntents
import Foundation
import WidgetKit

/// "Start dark adaptation" from Control Center, the Action button, Siri or Shortcuts. Shared by the
/// watch app and its widget extension (which hosts the control), like the iPhone's field-mode
/// control: it runs in the app, which opens straight onto the red clock (`AdaptationRequest`).
/// It is the clock the eye button and Double Tap start: the same stored start
/// (`WatchSky.adaptationStart`) and, once the app takes the request (`WatchStore.startAdaptation`),
/// the same wrist taps at 25 and 30 minutes. A clock already running is kept, never restarted.
struct StartAdaptationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start dark adaptation"
    static let description = IntentDescription("Opens Nyx in red and starts a 30-minute dark-adaptation clock, with wrist taps at 25 and 30 minutes.")
    static let supportedModes: IntentModes = .foreground
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let running = AdaptationRequest.running(at: now)
        let start = running?.start ?? now
        // Stored before anything opens, so the clock and the complication hold even if no screen does.
        if running == nil { WatchSky.adaptationStart = start }
        AdaptationRequest.post(start: start, now: now)
        WidgetCenter.shared.reloadTimelines(ofKind: AdaptationRequest.complicationKind)
        return .result(dialog: IntentDialog(stringLiteral: AdaptationRequest.dialog(running: running, now: now)))
    }
}

/// A request to show the dark-adaptation clock, handed from an intent to the watch app's root view.
/// Stored as well as posted, because a cold launch may run the intent before any view is listening
/// (the iPhone's `FieldModeRequest` pattern).
nonisolated enum AdaptationRequest {
    static let key = "watchAdaptationRequest"
    static let notification = Notification.Name("NyxWatchAdaptationRequest")
    /// The running-clock complication, reloaded whenever the clock starts or stops.
    static let complicationKind = "NyxAdaptation"
    /// The Control Center control.
    static let controlKind = "NyxAdaptationControl"
    /// The clock that is running at `now`, if any: one left from an earlier night is not.
    static func running(at now: Date, start: Date? = WatchSky.adaptationStart) -> AdaptationClock? {
        start.map(AdaptationClock.init(start:)).flatMap { $0.isStale(at: now) ? nil : $0 }
    }
    static func post(start: Date, now: Date = .now, defaults: UserDefaults = WatchSky.defaults, notify: Bool = true) {
        defaults.set(["start": start.timeIntervalSince1970, "at": now.timeIntervalSince1970], forKey: key)
        if notify { NotificationCenter.default.post(name: notification, object: nil) }
    }
    /// The pending request's clock start, once, if it was made within the last minute.
    static func take(now: Date = .now, defaults: UserDefaults = WatchSky.defaults) -> Date? {
        guard let request = defaults.dictionary(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        guard let at = request["at"] as? Double, abs(now.timeIntervalSince1970 - at) < 60, let start = request["start"] as? Double else { return nil }
        return Date(timeIntervalSince1970: start)
    }
    /// What Siri says: a new clock, or the one already running, in its own minutes.
    static func dialog(running: AdaptationClock?, now: Date) -> String {
        guard let running else { return String(localized: "Dark adaptation started. Keep the screen red for about 30 minutes.") }
        if running.isAdapted(at: now) { return String(localized: "Your eyes should be adapted. Keep the screen red.") }
        return String(localized: "Dark adaptation is already running: \(running.elapsedMinutes(at: now)) of about 30 minutes.")
    }
}
