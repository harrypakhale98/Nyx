import AppIntents
import Foundation
import WidgetKit

/// "Start field mode at Joshua Tree" from Siri, Shortcuts or Spotlight. Opens the app on the field
/// screen for tonight at that park.
struct StartFieldModeIntent: AppIntent {
    static let title: LocalizedStringResource="Start field mode"
    static let description=IntentDescription("Opens a dark, red field screen for tonight at a national park: when true darkness begins, the Moon, the Milky Way core and where to look.")
    static let supportedModes: IntentModes = .foreground
    @Parameter(title:"Park") var park: ParkEntity
    static var parameterSummary: some ParameterSummary { Summary("Start field mode at \(\.$park)") }
    init() {}
    init(park: ParkEntity) { self.park=park }
    func perform() async throws -> some IntentResult {
        FieldModeRequest.post(parkID:park.id)
        return .result()
    }
}

/// The "Open sky" button on a "core is up" alarm: night vision on, then field mode for that park,
/// so the eyes go from the dark room to a red screen and never to a bright Lock Screen.
struct OpenSkyIntent: LiveActivityIntent {
    static let title: LocalizedStringResource="Open the sky"
    static let description=IntentDescription("Opens Nyx's red field screen for tonight, with night vision on.")
    static let isDiscoverable=false
    static let supportedModes: IntentModes = .foreground
    @Parameter(title:"Park") var parkID: String
    init() {}
    init(parkID: String) { self.parkID=parkID }
    func perform() async throws -> some IntentResult {
        SharedSettings.defaults.set(true,forKey:"nightVision")
        FieldModeRequest.post(parkID:parkID)
        return .result()
    }
}

/// A "Stargazing" Focus: while it is on, Nyx turns night vision on and offers field mode on
/// Tonight. When the Focus ends, night vision returns to what it was, unless the person changed
/// it in the meantime.
///
/// The system calls `perform()` when the Focus starts, changes and ends, and also when Nyx
/// launches. With no Focus on, it passes the parameters' defaults (`current` does not throw: it
/// hands back a default instance, seen on the iOS 27 simulator). So the defaults are "off", and
/// "off" means "no Stargazing Focus": the person switches on what the Focus should do.
struct StargazingFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource="Stargazing"
    static let description=IntentDescription("Turns on Nyx's red night-vision palette and offers field mode while this Focus is on.")
    @Parameter(title:"Night vision",default:false) var nightVision: Bool
    @Parameter(title:"Offer field mode",default:false) var offerField: Bool
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title:"Stargazing",subtitle:nightVision ? "Night vision on" : offerField ? "Field mode offered" : "Nothing changes yet")
    }
    func perform() async throws -> some IntentResult {
        StargazingFocus.apply(nightVision:nightVision,offerField:offerField)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}

/// What the Stargazing Focus changed, kept in shared defaults so it can be undone exactly.
nonisolated enum StargazingFocus {
    static let activeKey="stargazingFocus"
    static let offerKey="stargazingFocusOffersField"
    static let holdKey="stargazingFocusNightVision"
    static let priorKey="stargazingFocusPriorNightVision"
    /// Both off is the system saying no Stargazing Focus is on (its defaults), so whatever was
    /// changed is put back. Night vision's prior value is kept from the moment the Focus first
    /// turned it on, and restored when the Focus stops holding it.
    static func apply(nightVision: Bool, offerField: Bool, defaults: UserDefaults = SharedSettings.defaults) {
        let active=nightVision || offerField
        if nightVision && !defaults.bool(forKey:holdKey) {
            defaults.set(defaults.bool(forKey:"nightVision"),forKey:priorKey)
            defaults.set(true,forKey:"nightVision")
        } else if !nightVision && defaults.bool(forKey:holdKey) {
            // Put it back only if it is still as the Focus left it (on); a person who turned it off meanwhile keeps it off.
            if defaults.bool(forKey:"nightVision"), defaults.object(forKey:priorKey) != nil { defaults.set(defaults.bool(forKey:priorKey),forKey:"nightVision") }
            defaults.removeObject(forKey:priorKey)
        }
        defaults.set(nightVision,forKey:holdKey)
        defaults.set(active,forKey:activeKey)
        defaults.set(offerField,forKey:offerKey)
        if !active { for key in [activeKey,offerKey,holdKey,priorKey] { defaults.removeObject(forKey:key) } }
    }
    /// True while the Focus is on and asked Nyx to offer field mode.
    static func offersField(_ defaults: UserDefaults = SharedSettings.defaults) -> Bool { defaults.bool(forKey:activeKey) && defaults.bool(forKey:offerKey) }
    /// True while the Focus holds night vision on, so leaving field mode keeps it.
    static func holdsNightVision(_ defaults: UserDefaults = SharedSettings.defaults) -> Bool { defaults.bool(forKey:holdKey) }
}
