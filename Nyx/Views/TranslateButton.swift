import SwiftUI
import Translation

/// "Translate" under the Park Service's own words (alerts, ranger programs), which arrive in
/// English. Shown only when Nyx is running in another language. A tap opens the system's
/// translation sheet (iOS 17.4) with that text: translated on this device by iOS. Nyx sends
/// nothing; on first use iOS may download its own language pack, as it does for dictation.
struct TranslateButton: View {
    @Environment(\.nyx) private var palette
    let text: String
    @State private var presented=false
    /// The app's own language, not the region's: an English app in Mexico needs no button.
    static var offered: Bool {
        if DebugScenario.isEnabled("translate") { return true }
        return !(Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("en")
    }
    var body: some View {
        if Self.offered, !text.isEmpty {
            Button { presented=true } label:{
                Label("Translate",systemImage:"translate").font(.subheadline)
                    .frame(minHeight:44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(palette.accent)
            .accessibilityHint("Shows a translation from iOS, made on this device.")
            .translationPresentation(isPresented:$presented,text:text)
        }
    }
}
#Preview("Translate") {
    TranslateButton(text:"Keys View Road is closed nightly from 9 PM to 6 AM.").padding().background(.black).preferredColorScheme(.dark)
}
