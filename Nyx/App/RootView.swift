import SwiftUI

/// Placeholder shell. Replaced by the tab shell in Phase 1.
struct RootView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("Nyx")
                .font(.system(size: 56, weight: .light, design: .serif))
                .tracking(8)
                .foregroundStyle(Color(red: 0.961, green: 0.945, blue: 0.902))
        }
    }
}

#Preview {
    RootView()
}
