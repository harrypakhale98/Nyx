import AppIntents
import WidgetKit

/// Shared by the app and the widget extension's Control Center control. Kept apart from the
/// Siri shortcuts so the extension never registers a second copy of them. A Live Activity intent:
/// the system performs it in Nyx's own process, launched in the background without opening Nyx,
/// so a followed night's Live Activity and the watch turn with the switch (`NightVisionFollowers`).
struct NightVisionIntent:SetValueIntent,LiveActivityIntent {
    static let title:LocalizedStringResource="Set night vision"
    @Parameter(title:"Enabled") var value:Bool
    init() {}
    init(value:Bool) { self.value=value }
    func perform() async throws -> some IntentResult {
        await NightVisionFollowers.set(value)
        return .result()
    }
}

/// What else turns with night vision when the switch is flipped away from Nyx's windows (Control
/// Center): set by the app once it has its model; nil in the widget extension, which reaches
/// neither the Live Activity nor the watch.
enum NightVisionFollowers {
    static var changed:(@MainActor (Bool) async -> Void)?
    /// Sets night vision, reloads the widgets and controls, and tells the followers. False when
    /// there were none to tell (the app's hook is not set).
    @discardableResult static func set(_ value:Bool) async -> Bool {
        SharedSettings.defaults.set(value,forKey:"nightVision")
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        guard let changed else { return false }
        await changed(value)
        return true
    }
}
