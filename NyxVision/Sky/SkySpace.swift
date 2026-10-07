import RealityKit
import SwiftUI

/// The immersive space's content. The window drives it: the park, the night and the moment come
/// from the shared model, so the window's ornament scrubs this sky. A drag across the sky turns
/// the night too, and the room darkens as the sky surrounds. Where the forecast reaches the hour,
/// its clouds dim the stars and drift overhead.
struct SkySpace: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scene = SkyScene()
    /// The clock where the current drag began; nil between drags.
    @State private var dragStart: Double?
    /// How far the Digital Crown has opened the sky (0…1); nil until the system says.
    @State private var immersion: Double?
    var body: some View {
        RealityView { content in
            await scene.build(palette: palette)
            content.add(scene.root)
            // VoiceOver's activate on the Moon, a planet, a named star or the core does what a tap does.
            let model = model
            scene.activation = content.subscribe(to: AccessibilityEvents.Activate.self) { event in
                Self.toggle(event.entity.name, in: model)
            }
            // VoiceOver's swipe up and down on the sky move the clock half an hour.
            scene.adjustments = [
                content.subscribe(to: AccessibilityEvents.Increment.self) { _ in Self.step(1800, in: model) },
                content.subscribe(to: AccessibilityEvents.Decrement.self) { _ in Self.step(-1800, in: model) },
            ]
        } update: { _ in
            guard let plan = model.plan, let moment = model.skyMoment else { return }
            scene.update(plan: plan, moment: moment, cloud: plan.cloud(at: moment.date), palette: palette, typeSize: typeSize, selected: model.selectedBody,
                         constellations: model.constellations, reduceMotion: reduceMotion)
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in Self.toggle(value.entity.name, in: model) })
        .simultaneousGesture(turnGesture)
        // The room fades as the sky opens: dark at first, as dark as the system allows once the
        // sky fills most of the view. Reduce Transparency keeps more of the room in sight.
        .preferredSurroundingsEffect(Self.surroundings(immersion: immersion, reduceTransparency: reduceTransparency))
        .onImmersionChange { _, new in immersion = new.amount }
        .onAppear { model.immersiveOpen = true }
        .onDisappear { model.immersiveOpen = false; model.cancelSweep() }
    }

    /// Grab the sky and turn it: a horizontal drag moves the clock as far as the stars would
    /// turn in that time, never faster than `VisionModel.comfortableTurn`. Under Reduce Motion
    /// the sky waits for the hand to let go and then moves once, without a sweep.
    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 12).targetedToAnyEntity()
            .onChanged { value in
                guard let plan = model.plan else { return }
                let facing = SkyDome.facing(for: plan.park)
                let from = scene.azimuth(ofScenePoint: value.convert(value.startLocation3D, from: .local, to: .scene), facing: facing)
                let to = scene.azimuth(ofScenePoint: value.convert(value.location3D, from: .local, to: .scene), facing: facing)
                if dragStart == nil { dragStart = model.fraction; model.cancelSweep() }
                guard let start = dragStart, !reduceMotion else { return }
                model.turn(toward: SkyDome.dragTarget(from: start, degrees: Self.wrapped(to-from), southern: plan.park.latitude < 0, span: plan.span))
            }
            .onEnded { value in
                defer { dragStart = nil }
                guard reduceMotion, let plan = model.plan, let start = dragStart else { return }
                let facing = SkyDome.facing(for: plan.park)
                let from = scene.azimuth(ofScenePoint: value.convert(value.startLocation3D, from: .local, to: .scene), facing: facing)
                let to = scene.azimuth(ofScenePoint: value.convert(value.location3D, from: .local, to: .scene), facing: facing)
                model.move(to: SkyDome.dragTarget(from: start, degrees: Self.wrapped(to-from), southern: plan.park.latitude < 0, span: plan.span), reduceMotion: true)
            }
    }
    /// An angle difference in −180…180°.
    static func wrapped(_ degrees: Double) -> Double { (degrees+540).truncatingRemainder(dividingBy: 360)-180 }
    static func surroundings(immersion: Double?, reduceTransparency: Bool) -> SurroundingsEffect {
        if reduceTransparency { return .dark }
        return (immersion ?? 1) < 0.5 ? .dark : .ultraDark
    }

    /// Shows or hides a body's name card. Only entities named `body:…` are bodies; a tap on the
    /// empty sky puts a showing card away.
    private static func toggle(_ name: String, in model: VisionModel) {
        if name == "sky.grab" { model.selectedBody = nil; return }
        guard name.hasPrefix("body:") else { return }
        let id = String(name.dropFirst("body:".count))
        model.selectedBody = model.selectedBody == id ? nil : id
    }
    private static func step(_ seconds: Double, in model: VisionModel) {
        guard let plan = model.plan, plan.span.duration > 0 else { return }
        model.move(to: model.fraction+seconds/plan.span.duration, reduceMotion: true)
    }
    private var palette: VisionPalette { VisionPalette(nightVision: model.nightVision, highContrast: contrast == .increased, solid: reduceTransparency) }
    /// The labels' text size: the person's, or DEBUG's `-nyx-ax5`.
    private var typeSize: DynamicTypeSize { VisionDebug.isEnabled("ax5") ? .accessibility3 : dynamicTypeSize }
}
