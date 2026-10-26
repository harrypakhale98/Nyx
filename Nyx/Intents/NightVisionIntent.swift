import AppIntents
import WidgetKit

/// Shared by the app and the widget extension's Control Center control. Kept apart from the
/// Siri shortcuts so the extension never registers a second copy of them. A Live Activity intent:
/// the system performs it in Nyx's own process, launched in the background without opening Nyx,
/// so a followed night's Live Activity and the watch turn with the switch (`NightVisionFollowers`).
struct NightVisionIntent:SetValueIntent,LiveActivityIntent {
    static let title:LocalizedStringResource="Set night vision"
    @Parameter(title:"Night vision") var value:Bool
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
        // A turn by hand: under At dusk it holds until the next dusk or dawn.
        NightVisionMode.turnedByHand()
        SharedSettings.defaults.set(value,forKey:"nightVision")
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        guard let changed else { return false }
        await changed(value)
        return true
    }
}

/// Night vision's choice on iPhone and iPad: Off, On, or At dusk (red from civil dusk to civil dawn
/// at the starting point, `NightVisionDusk`). "nightVision" stays the state every surface reads
/// (widgets, Control Center, the Live Activity, the watch's Match iPhone); At dusk is one key beside
/// it, so Off and On are simply that switch and nothing downstream changes. Here, not in the app,
/// because Control Center's intent is compiled into the widget extension too.
nonisolated enum NightVisionMode: String, CaseIterable, Identifiable, Sendable {
    case off, on, dusk
    static let atDuskKey="nightVisionAtDusk"
    /// When the switch was last turned by hand under At dusk (seconds since 1970): the turn holds
    /// until the first dusk or dawn after it, then At dusk takes over again.
    static let heldKey="nightVisionHeldAt"
    var id:String { rawValue }
    var title:LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .on: "On"
        case .dusk: "At dusk"
        }
    }
    static func current(_ defaults:UserDefaults=SharedSettings.defaults)->NightVisionMode {
        defaults.bool(forKey:atDuskKey) ? .dusk : defaults.bool(forKey:"nightVision") ? .on : .off
    }
    static func heldAt(_ defaults:UserDefaults=SharedSettings.defaults)->Date? {
        (defaults.object(forKey:heldKey) as? Double).map(Date.init(timeIntervalSince1970:))
    }
    /// The toolbar switch, Control Center, Siri, Assistive Access: under At dusk the turn is noted, so
    /// the next look at the Sun keeps it rather than undoing it. Off and On need nothing.
    static func turnedByHand(_ defaults:UserDefaults=SharedSettings.defaults,now:Date = .now) {
        if defaults.bool(forKey:atDuskKey) { defaults.set(now.timeIntervalSince1970,forKey:heldKey) }
    }
}
