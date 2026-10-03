import AppIntents
import WidgetKit

/// Shared by the app and the widget extension's Control Center control. Kept apart from the
/// Siri shortcuts so the extension never registers a second copy of them.
struct NightVisionIntent:SetValueIntent {
    static let title:LocalizedStringResource="Set night vision"
    @Parameter(title:"Enabled") var value:Bool
    init() {}
    init(value:Bool) { self.value=value }
    func perform() async throws -> some IntentResult {
        SharedSettings.defaults.set(value,forKey:"nightVision")
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}
