import AppIntents

/// "Turn on night vision" by voice. The Control Center toggle's `NightVisionIntent` sets a value
/// the control passes in; a spoken shortcut cannot fix that value, so this one only ever turns night
/// vision on. Same setting, and the same reloads, so widgets, the control and a followed night's
/// Live Activity turn red together (the app's own screens follow the setting as they do for the control).
struct NightVisionOnIntent: AppIntent {
    static let title: LocalizedStringResource="Turn on night vision"
    static let description=IntentDescription("Turns on Nyx's red night-vision palette, for eyes adapted to the dark. Widgets and the Lock Screen follow.")
    init() {}
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        // The watch and a followed night follow, as with the control (the app's hook when it is running).
        if !(await NightVisionFollowers.set(true)) { await FieldActivities.refresh(nightVision:true) }
        return .result(dialog:"Night vision is on.")
    }
}
