import SwiftUI

/// Nyx for Apple Vision Pro: plan in a calm window, then stand under the sky you planned for.
/// Everything is computed on device from bundled data; this app makes no network requests.
@main struct NyxVisionApp: App {
    @State private var model = VisionModel()
    @State private var style: any ImmersionStyle = .progressive(0.35...1, initialAmount: 1)
    var body: some Scene {
        WindowGroup(id: "planner") {
            PlannerWindow().environment(model)
        }
        .defaultSize(width: 1180, height: 760)
        ImmersiveSpace(id: SkySpace.id) {
            SkySpace().environment(model)
        }
        .immersionStyle(selection: $style, in: .progressive(0.35...1, initialAmount: 1))
    }
}
extension SkySpace { static let id = "sky" }
