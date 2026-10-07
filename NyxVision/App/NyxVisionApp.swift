import SwiftUI

/// Nyx for Apple Vision Pro: plan in a calm window, then stand under the sky you planned for, or
/// set the night's Moon on the table. Everything is computed on device from bundled data; the one
/// request is the parks' cloud forecast, behind its switch in Your privacy (`VisionModel+Forecasts`).
@main struct NyxVisionApp: App {
    @State private var model = VisionModel()
    /// The sky opens most of the way: the room stays at the edges, so nobody is dropped into
    /// darkness, and the Digital Crown opens the rest. DEBUG sky captures open it fully.
    static let opening = VisionDebug.isEnabled("vision-immersive") && !VisionDebug.isEnabled("vision-partial") ? 1.0 : 0.6
    @State private var style: any ImmersionStyle = .progressive(0.35...1, initialAmount: opening)
    var body: some Scene {
        WindowGroup(id: "planner") {
            PlannerWindow().environment(model)
        }
        .defaultSize(width: 1180, height: 760)
        WindowGroup(id: MoonVolume.id) {
            MoonVolume().environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.42, height: 0.42, depth: 0.42, in: .meters)
        ImmersiveSpace(id: SkySpace.id) {
            SkySpace().environment(model)
        }
        .immersionStyle(selection: $style, in: .progressive(0.35...1, initialAmount: Self.opening))
    }
}
extension SkySpace { static let id = "sky" }
