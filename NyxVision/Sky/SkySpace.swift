import RealityKit
import SwiftUI

/// The immersive space's content. The window drives it: the park, the night and the moment come
/// from the shared model, so the window's ornament scrubs this sky.
struct SkySpace: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var scene = SkyScene()
    var body: some View {
        RealityView { content in
            await scene.build(palette: palette)
            content.add(scene.root)
        } update: { _ in
            guard let plan = model.plan, let moment = model.skyMoment else { return }
            scene.update(plan: plan, moment: moment, palette: palette, selected: model.selectedBody)
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            let id = value.entity.name.replacingOccurrences(of: "body:", with: "")
            model.selectedBody = model.selectedBody == id ? nil : id
        })
        .onAppear { model.immersiveOpen = true }
        .onDisappear { model.immersiveOpen = false }
    }
    private var palette: VisionPalette { VisionPalette(nightVision: model.nightVision, highContrast: contrast == .increased, solid: reduceTransparency) }
}
