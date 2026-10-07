import SwiftUI

/// What every tab's first screen carries in its leading toolbar: night vision, one tap away in the
/// dark, and Settings. Screen actions (add, share, sort) stay on the trailing side.
struct TabRootToolbar: ViewModifier {
    @State private var settings=false
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
/// The night-vision switch as a toolbar toggle: the screen turns red on the shared spring (`RootView`
/// animates the palette) with one soft tap. VoiceOver hears a toggle with its state; Voice Control
/// answers to "Night vision" or "Red light".
struct NightVisionToggle: View {
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    var body: some View {
        Toggle(isOn:$nightVision) {
            Label("Night vision",systemImage:nightVision ? "moon.circle.fill" : "moon.circle")
        }
        .toggleStyle(.button).labelStyle(.iconOnly)
        .accessibilityLabel("Night vision")
        .accessibilityInputLabels([Text("Night vision"),Text("Red light"),Text("Red screen")])
        .help("Night vision")
        .sensoryFeedback(.impact(flexibility:.soft,intensity:0.7),trigger:nightVision)
    }
}
#Preview("Tab root toolbar") {
    NavigationStack { Color.black.navigationTitle("Tonight").navigationBarTitleDisplayMode(.inline).tabRootToolbar() }
        .environment(PlanModel()).preferredColorScheme(.dark)
}
