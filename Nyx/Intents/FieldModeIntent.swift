import AppIntents
import Foundation

/// Opens field mode from Control Center. Shared by the app and the widget extension (which hosts
/// the control); it always runs in the app, which reads the request and opens the field screen
/// for the last park used in the field, or the starting park.
struct OpenFieldModeIntent: AppIntent {
    static let title: LocalizedStringResource="Open field mode"
    static let description=IntentDescription("Opens Nyx's field screen for the night: a dark, red countdown through its milestones.")
    static let supportedModes: IntentModes = .foreground
    init() {}
    func perform() async throws -> some IntentResult {
        FieldModeRequest.post(parkID:nil)
        return .result()
    }
}

/// A request to open field mode, handed from an intent to the app's root view. Stored as well as
/// posted, because a cold launch may run the intent before any view is listening.
nonisolated enum FieldModeRequest {
    static let key="fieldModeRequest"
    /// The park last used in the field, for Control Center and the Live Activity.
    static let lastParkKey="lastFieldPark"
    static let notification=Notification.Name("NyxFieldModeRequest")
    static func post(parkID: String?, now: Date = .now, defaults: UserDefaults = SharedSettings.defaults, notify: Bool = true) {
        defaults.set(["park": parkID ?? "", "at": now.timeIntervalSince1970], forKey: key)
        if notify { NotificationCenter.default.post(name: notification, object: nil) }
    }
    /// The pending request, once, if it was made within the last minute. `parkID` is nil for "the usual park".
    struct Pending: Equatable { let parkID: String? }
    static func take(now: Date = .now, defaults: UserDefaults = SharedSettings.defaults) -> Pending? {
        guard let request=defaults.dictionary(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        guard let at=request["at"] as? Double, abs(now.timeIntervalSince1970-at)<60 else { return nil }
        let park=request["park"] as? String
        return Pending(parkID: park?.isEmpty == false ? park : nil)
    }
}
