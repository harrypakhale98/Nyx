import RealityKit
import SwiftUI

/// The immersive space's content. The window drives it: the park, the night and the moment come
/// from the shared model, so the window's ornament scrubs this sky.
struct SkySpace: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scene = SkyScene()
    var body: some View {
        RealityView { content in
            await scene.build(palette: palette)
            content.add(scene.root)
            // VoiceOver's activate on the Moon, a planet or the core does what a tap does.
            let model = model
            scene.activation = content.subscribe(to: AccessibilityEvents.Activate.self) { event in
                Self.toggle(event.entity.name, in: model)
            }
        } update: { _ in
            guard let plan = model.plan, let moment = model.skyMoment else { return }
            scene.update(plan: plan, moment: moment, palette: palette, typeSize: typeSize, selected: model.selectedBody)
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in Self.toggle(value.entity.name, in: model) })
        .onAppear { model.immersiveOpen = true }
        .onDisappear { model.immersiveOpen = false }
    }
    /// Shows or hides a body's name card. Only entities named `body:…` are bodies.
    private static func toggle(_ name: String, in model: VisionModel) {
        guard name.hasPrefix("body:") else { return }
        let id = String(name.dropFirst("body:".count))
        model.selectedBody = model.selectedBody == id ? nil : id
    }
    private var palette: VisionPalette { VisionPalette(nightVision: model.nightVision, highContrast: contrast == .increased, solid: reduceTransparency) }
    /// The labels' text size: the person's, or DEBUG's `-nyx-ax5`.
    private var typeSize: DynamicTypeSize { VisionDebug.isEnabled("ax5") ? .accessibility3 : dynamicTypeSize }
}
