import SwiftUI

/// What every tab's first screen carries in its leading toolbar: night vision, one tap away in the
/// dark, and Settings. Screen actions (add, share, sort) stay on the trailing side.
struct TabRootToolbar: ViewModifier {
    @State private var settings=false
    @Environment(SceneCommands.self) private var commands:SceneCommands?
    func body(content:Content)->some View {
        content
            .toolbar {
                ToolbarItemGroup(placement:.topBarLeading) {
                    NightVisionToggle()
                    Button { settings=true } label:{ Image(systemName:"gearshape") }
                        .accessibilityLabel("Settings").accessibilityInputLabels([Text("Settings"),Text("Preferences")])
                }
            }
            .sheet(isPresented:$settings) { SettingsSheet() }
            .onChange(of:commands?.closeSettings) { settings=false }
    }
}
extension View {
    /// Night vision and Settings in a tab's root toolbar (`TabRootToolbar`).
    func tabRootToolbar()->some View { modifier(TabRootToolbar()) }
}
/// Settings in its own sheet, so it opens the same way from every tab, on iPhone and iPad.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SettingsView().toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }.nyxPresentation()
    }
}
/// The night-vision switch as a toolbar toggle: a lamp, not a theme. The window dips to black, the
/// red comes up under the cover and is revealed (`NightVisionLamp`, run by `RootView`), with one
/// soft tap at the turn. Under Reduce Motion or Prefer Cross-Fade Transitions it writes the setting
/// at once and the palette crossfades. VoiceOver hears a toggle with its state, said once: the
/// switch's own value when VoiceOver is on it, "Night vision on" or "off" only when it was turned
/// from elsewhere (Voice Control with VoiceOver running). Voice Control answers to "Night vision",
/// "Red light" or "Flashlight".
struct NightVisionToggle: View {
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @Environment(SceneCommands.self) private var commands:SceneCommands?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @Environment(\.nyxAccess) private var access
    private var shown:Bool { commands?.lampTarget ?? nightVision }
    var body: some View {
        Toggle(isOn:Binding(get:{ shown },set:{ turn($0) })) {
            Label("Night vision",systemImage:shown ? "flashlight.on.circle.fill" : "flashlight.off.circle")
        }
        .toggleStyle(.button).labelStyle(.iconOnly)
        .accessibilityLabel("Night vision")
        // "Flashlight" too: it is the glyph on screen.
        .accessibilityInputLabels([Text("Night vision"),Text("Red light"),Text("Red screen"),Text("Flashlight")])
        .help("Night vision")
        // The soft tap at the turn comes once, from `RootView`: every tab's toolbar has its own switch.
    }
    private func turn(_ on:Bool) {
        // Read at the tap, before the lamp's cover could move VoiceOver anywhere.
        let announce = !NightVisionLamp.voiceOverOnSwitch()
        if let commands, !(systemReduceMotion || forcedReduceMotion || access.crossFade) { commands.requestNightVision(on,announce:announce); return }
        nightVision=on
        if announce { NightVisionLamp.announce(on) }
    }
}
/// The lamp's timing, shared by the toolbar switch and `RootView`: ~0.2 s down to black, the turn,
/// then the reveal on the shared spring (~0.45 s to the eye). A second tap mid-way reverses from
/// wherever the cover is, so no frame is ever brighter than the one before on the way into the red.
enum NightVisionLamp {
    /// One tap on the switch: the state asked for, and whether to say it (`voiceOverOnSwitch`).
    struct Request: Equatable { let id:Int; let on:Bool; var announce=true }
    static let dim=0.2
    static let reveal=0.45
    /// Where the cover is between frames, as far as the lamp needs to know: a straight line from one
    /// value to another over a duration. The drawn curve is eased; this only sets how long is left.
    struct Cover: Equatable {
        var from=0.0, to=0.0
        var start=Date.distantPast
        var duration=0.0
        func value(at now:Date)->Double {
            guard duration>0 else { return to }
            let done=min(1,max(0,now.timeIntervalSince(start)/duration))
            return from+(to-from)*done
        }
    }
    /// Seconds left to reach full cover from a cover already partly down (0 to 1).
    static func dimTime(from cover:Double)->Double { dim*(1-min(max(cover,0),1)) }
    /// Whether VoiceOver is on the switch itself, which then speaks its own new value: an
    /// announcement as well would say the state twice. The toolbar's switch is hosted by UIKit,
    /// so the element VoiceOver is on is read there, by the switch's label.
    @MainActor static func voiceOverOnSwitch()->Bool {
        guard UIAccessibility.isVoiceOverRunning,
              let element=UIAccessibility.focusedElement(using:UIAccessibility.AssistiveTechnologyIdentifier.notificationVoiceOver) as? NSObject else { return false }
        return element.accessibilityLabel == String(localized:"Night vision")
    }
    /// Said after the setting is written, politely, after anything VoiceOver is already saying.
    @MainActor static func announce(_ on:Bool) {
        NightListener.announce(on ? String(localized:"Night vision on") : String(localized:"Night vision off"),priority:.default)
    }
}
#Preview("Tab root toolbar") {
    NavigationStack { Color.black.navigationTitle("Tonight").navigationBarTitleDisplayMode(.inline).tabRootToolbar() }
        .environment(PlanModel()).preferredColorScheme(.dark)
}
