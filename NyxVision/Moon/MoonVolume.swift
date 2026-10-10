import RealityKit
import SwiftUI
import UIKit
import simd

/// "The Moon on your table": a volume holding the chosen night's Moon as a globe, NASA's lunar
/// map (the 4096×2048 LROC colour mosaic, with surface relief from LOLA elevation as a normal map)
/// lit by a single sunlight at the true phase angle, turned as it appears from the chosen
/// park at the Moon's best moment that night (bright limb, axis and libration from
/// `AstronomyEngine.moonGeometry`). It works without leaving the room, which suits a short,
/// seated look. A drag turns the globe; let go and it turns back to the face we always see.
struct MoonVolume: View {
    static let id = "moon"
    @Environment(VisionModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var globe = MoonGlobe()
    /// Nights after tonight, park-local. The volume keeps its own night, so scrubbing the Moon
    /// does not move the planner.
    @State private var nights = 0
    @State private var view: MoonView?
    var body: some View {
        let stepper = $nights
        RealityView { content in
            await globe.build()
            content.add(globe.root)
            // VoiceOver's swipe up and down on the Moon step through the nights, as the ornament does.
            globe.subscriptions = [
                content.subscribe(to: AccessibilityEvents.Increment.self) { _ in stepper.wrappedValue = min(MoonView.lastNight, stepper.wrappedValue+1) },
                content.subscribe(to: AccessibilityEvents.Decrement.self) { _ in stepper.wrappedValue = max(0, stepper.wrappedValue-1) },
            ]
        } update: { _ in
            if let view { globe.show(view, nightVision: model.nightVision, reduceMotion: reduceMotion) }
        }
        .gesture(DragGesture(minimumDistance: 4).targetedToAnyEntity()
            .onChanged { value in globe.turn(by: Float(value.translation.width)) }
            .onEnded { _ in globe.settle(reduceMotion: reduceMotion) })
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            MoonControls(view: view, nights: $nights, offersPlanner: !model.plannerOpen)
                .environment(\.visionPalette, VisionPalette(nightVision: model.nightVision, highContrast: contrast == .increased, solid: reduceTransparency))
                .modifier(DebugTypeSize())
        }
        // Keyed by the night itself, so the Moon moves on when tonight does (`VisionModel.tick`),
        // and by whether it is tonight, which a stepped-to night becomes when tonight reaches it.
        .task(id: "\(model.selectedID ?? "")-\(evening.map { Int($0.timeIntervalSince1970) } ?? 0)-\(nights == 0)") {
            guard let park = model.park, let night = evening else { return }
            let tonight = nights == 0
            let computed = await Task.detached(priority: .userInitiated) { MoonView(park: park, night: night, isTonight: tonight) }.value
            guard !Task.isCancelled else { return }
            view = computed
        }
        .onAppear { if let n = VisionDebug.moonNights { nights = n } }
        // When tonight turns over, a later night keeps its date, as the planner's does (`VisionModel.tick`).
        .onChange(of: model.now) { before, after in
            guard nights > 0, let park = model.park else { return }
            let turned = park.calendar.dateComponents([.day], from: park.currentNight(at: before), to: park.currentNight(at: after)).day ?? 0
            if turned > 0 { nights = max(0, nights-turned) }
        }
        // Left on the table for days, the volume still shows tonight's Moon when looked at again.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await model.keepClock()
        }
    }
    /// The night on show: tonight at the planner's park, or a later one.
    private var evening: Date? { model.park.map { $0.date($0.currentNight(at: model.now), addingDays: nights) } }
}

/// One night's Moon as the volume shows it, computed off the main thread.
nonisolated struct MoonView: Sendable, Equatable {
    /// A lunar month of nights from tonight.
    static let lastNight = 29
    let park: Park
    let night: Date
    let isTonight: Bool
    let moment: Date
    let geometry: MoonGeometry
    let phaseName: String
    init(park: Park, night: Date, isTonight: Bool) {
        let engine = AstronomyEngine()
        self.park = park
        self.night = night
        self.isTonight = isTonight
        moment = engine.moonViewTime(for: engine.conditions(for: park, on: night), park: park)
        geometry = engine.moonGeometry(for: park, at: moment)
        phaseName = engine.moonPhase(at: moment).name
    }
    var percent: Int { Int((geometry.illumination*100).rounded()) }
    /// "Moon, waxing crescent, 23 percent lit".
    var spoken: String { String(localized: "Moon, \(phaseName.lowercased()), \(percent) percent lit") }
    static func == (a: MoonView, b: MoonView) -> Bool { a.park.id == b.park.id && a.moment == b.moment }

    /// The Sun's direction as seen from the Moon, in the volume's frame (x right, y up, z toward
    /// the viewer): the same vector the Moon shader lights the disc with.
    var sunDirection: SIMD3<Float> {
        let i = geometry.phaseAngle, a = geometry.brightLimb
        return simd_normalize(SIMD3<Float>(Float(sin(i) * -sin(a)), Float(sin(i)*cos(a)), Float(cos(i))))
    }
    /// The globe's orientation: the inverse of the shader's screen-to-Moon turn (lunar north
    /// from screen up, then libration in latitude and longitude), so the map's face matches the
    /// window's disc exactly.
    var orientation: simd_quatf {
        let c = cos(geometry.north), s = sin(geometry.north)
        let cb = cos(geometry.librationLatitude), sb = sin(geometry.librationLatitude)
        let cl = cos(geometry.librationLongitude), sl = sin(geometry.librationLongitude)
        let n = simd_double3x3(rows: [SIMD3(c, s, 0), SIMD3(-s, c, 0), SIMD3(0, 0, 1)])
        let b = simd_double3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, cb, sb), SIMD3(0, -sb, cb)])
        let l = simd_double3x3(rows: [SIMD3(cl, 0, sl), SIMD3(0, 1, 0), SIMD3(-sl, 0, cl)])
        let screenToMoon = l*b*n
        let m = screenToMoon.transpose
        return simd_quatf(simd_float3x3(columns: (SIMD3<Float>(m.columns.0), SIMD3<Float>(m.columns.1), SIMD3<Float>(m.columns.2))))
    }
}

/// The globe, its sunlight, and the turn a drag gives it.
@MainActor final class MoonGlobe {
    let root = Entity()
    let sphere = ModelEntity()
    private let sun = DirectionalLight()
    private var material: PhysicallyBasedMaterial?
    /// LOLA's relief as a normal map, worn except near full Moon (`MoonShading.globeShowsRelief`).
    private var relief: TextureResource?
    private var shown: MoonView?
    private var shownNightVision = false
    private var spin: Float = 0
    /// VoiceOver's increment and decrement, kept alive with the globe.
    var subscriptions: [EventSubscription] = []
    static let radius: Float = 0.14

    func build() async {
        let textures = await MoonGlobeTextures.load()
        relief = textures.relief
        if let texture = textures.colour {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = .init(floatLiteral: 1)
            material.metallic = .init(floatLiteral: 0)
            material.emissiveColor = .init(color: .white, texture: .init(texture))
            material.emissiveIntensity = 0
            self.material = material
        }
        if let mesh = try? Self.globeMesh() { sphere.model = ModelComponent(mesh: mesh, materials: material.map { [$0] } ?? []) }
        // Sunlight only: the room's light would fill in the night side and erase the phase.
        sphere.components.set(EnvironmentLightingConfigurationComponent(environmentLightingWeight: 0))
        sphere.components.set(CollisionComponent(shapes: [.generateSphere(radius: Self.radius)]))
        sphere.components.set(InputTargetComponent())
        sphere.components.set(HoverEffectComponent())
        root.addChild(sphere)
        root.addChild(sun)
    }

    func show(_ view: MoonView, nightVision: Bool, reduceMotion: Bool) {
        if shown != view || shownNightVision != nightVision {
            let first = shown == nil
            shown = view
            shownNightVision = nightVision
            // Natural sunlight; the night side keeps a trace of earthshine, strongest around new
            // moon, as on the window's disc. Night vision's red is the surface's tint below.
            let red = UIColor(red: 1, green: 0.27, blue: 0.23, alpha: 1)
            sun.light = DirectionalLightComponent(color: UIColor(red: 1, green: 0.98, blue: 0.95, alpha: 1), intensity: 15000)
            if var material {
                // Night vision also tints the surface itself, as the window's filter tints its
                // disc: the faint fill the system still gives the night side turns red with it,
                // rather than staying grey beside a red day side.
                material.baseColor = .init(tint: nightVision ? red : .white, texture: material.baseColor.texture)
                material.emissiveColor = .init(color: nightVision ? red : UIColor(red: 0.75, green: 0.85, blue: 1, alpha: 1), texture: material.emissiveColor.texture)
                material.emissiveIntensity = nightVision ? 0 : Float(0.03*(1-cos(view.geometry.phaseAngle))/2)
                // Crater rims and shadows along the terminator; near full Moon the surface goes
                // flat, as the real one does and as the window's disc fades its relief.
                material.normal = .init(texture: MoonShading.globeShowsRelief(view.geometry) ? relief.map { .init($0) } : nil)
                sphere.model?.materials = [material]
                self.material = material
            }
            // A directional light shines along its −z: point +z at the Sun.
            let light = Transform(rotation: simd_quatf(from: [0, 0, 1], to: view.sunDirection))
            let face = Transform(rotation: simd_quatf(angle: spin, axis: [0, 1, 0])*view.orientation)
            if first || reduceMotion {
                sun.transform = light
                sphere.transform = face
            } else {
                sun.move(to: light, relativeTo: root, duration: 0.6, timingFunction: .easeInOut)
                sphere.move(to: face, relativeTo: root, duration: 0.6, timingFunction: .easeInOut)
            }
            var access = AccessibilityComponent()
            access.isAccessibilityElement = true
            access.label = LocalizedStringResource(stringLiteral: view.spoken)
            access.value = LocalizedStringResource(stringLiteral: MoonControls.caption(view))
            access.systemActions = [.increment, .decrement]
            sphere.components.set(access)
        }
    }
    /// A drag turns the globe about the vertical, slowly: a third of a degree a point.
    func turn(by points: Float) {
        guard let shown else { return }
        spin = points*0.006
        sphere.transform.rotation = simd_quatf(angle: spin, axis: [0, 1, 0])*shown.orientation
    }
    /// Let go, and the Moon turns back to the face it always shows us (at once under Reduce Motion).
    func settle(reduceMotion: Bool) {
        spin = 0
        guard let shown else { return }
        let face = Transform(rotation: shown.orientation)
        if reduceMotion { sphere.transform = face } else { sphere.move(to: face, relativeTo: root, duration: 1.4, timingFunction: .easeInOut) }
    }

    /// A globe whose texture coordinates follow the Moon shader's map lookup (`MoonGlobeGrid`):
    /// longitude 0 (the mean near side) toward +z, east toward +x, north up. Tangents point east
    /// and bitangents north, the normal map's red and green axes. 192 × 96 cells keep the limb
    /// round at arm's length (a cell is 4.6 mm on the 14 cm radius).
    static func globeMesh() throws -> MeshResource {
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], tangents: [SIMD3<Float>] = [], bitangents: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        let columns = 192, rows = 96
        for i in 0...columns {
            for j in 0...rows {
                let vertex = MoonGlobeGrid.vertex(column: i, row: j, columns: columns, rows: rows)
                positions.append(vertex.normal*radius)
                normals.append(vertex.normal)
                tangents.append(vertex.tangent)
                bitangents.append(vertex.bitangent)
                uvs.append(vertex.uv)
            }
        }
        for i in 0..<columns {
            for j in 0..<rows {
                let a = UInt32(i*(rows+1)+j), b = a+UInt32(rows+1)
                // Counterclockwise seen from outside.
                indices += [a, b, b+1, a, b+1, a+1]
            }
        }
        var descriptor = MeshDescriptor(name: "moon")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.tangents = MeshBuffers.Tangents(tangents)
        descriptor.bitangents = MeshBuffers.Tangents(bitangents)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

/// The globe's two textures, read from the app bundle when the volume opens and held only by the
/// globe's material, so they go when the volume closes. Built by `Scripts/build_moon_globe.swift`
/// and stored already GPU-compressed (ASTC in KTX, with their mipmaps), so they load as they are,
/// with nothing decoded or cached on the way: `MoonGlobeColour.ktx` (4096×2048 LROC colour, ASTC
/// 6×6, about 5 MB) and `MoonGlobeNormal.ktx` (2048×1024 LOLA normals, ASTC 4×4, about 2.8 MB),
/// against some 53 MB as plain RGBA. If either is missing the globe keeps `MoonMap` and a smooth
/// surface rather than failing.
struct MoonGlobeTextures {
    var colour: TextureResource?
    var relief: TextureResource?
    static func load() async -> MoonGlobeTextures {
        var textures = MoonGlobeTextures()
        if let url = Bundle.main.url(forResource: "MoonGlobeColour", withExtension: "ktx") {
            textures.colour = try? await TextureResource(contentsOf: url, options: .init(semantic: .color))
        }
        if textures.colour == nil, let image = UIImage(named: "MoonMap")?.cgImage {
            textures.colour = try? await TextureResource(image: image, options: .init(semantic: .color))
        }
        if let url = Bundle.main.url(forResource: "MoonGlobeNormal", withExtension: "ktx") {
            textures.relief = try? await TextureResource(contentsOf: url, options: .init(semantic: .normal))
        }
        return textures
    }
}

/// The ornament under the Moon: step or slide through a lunar month of nights.
struct MoonControls: View {
    @Environment(\.visionPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openWindow) private var openWindow
    let view: MoonView?
    @Binding var nights: Int
    /// The planner is closed: the volume is the only Nyx window left, so it offers the way back.
    var offersPlanner = false
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button { nights -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(nights == 0)
                    .accessibilityLabel(Text("Previous night"))
                VStack(spacing: 2) {
                    Text(title).font(.system(.headline, design: .serif))
                    if let view { Text("\(view.phaseName) · \(view.percent)% lit").font(.callout).foregroundStyle(palette.muted) }
                }
                .frame(minWidth: 200)
                .accessibilityElement(children: .combine)
                Button { nights += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(nights >= MoonView.lastNight)
                    .accessibilityLabel(Text("Next night"))
            }
            .buttonBorderShape(.circle)
            Slider(value: Binding(get: { Double(nights) }, set: { nights = Int($0.rounded()) }), in: 0...Double(MoonView.lastNight), step: 1) {
                Text("Night")
            }
            .frame(minWidth: 320)
            .accessibilityValue(Text(title))
            if let view {
                Text(Self.caption(view)).font(.footnote).foregroundStyle(palette.muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420)
            }
            if nights > 0 || offersPlanner {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    if nights > 0 { Button("Back to tonight") { nights = 0 } }
                    if offersPlanner {
                        Button { openWindow(id: PlannerWindow.id) } label: { Label("Open planner", systemImage: "list.bullet") }
                            .accessibilityHint(Text("Opens the window with every park and the night's controls"))
                    }
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 18)
        .frame(maxWidth: typeSize.isAccessibilitySize ? 640 : 480)
        .glassBackgroundEffect(displayMode: palette.nightVision || palette.solid ? .never : .always)
        .background {
            if palette.nightVision { RoundedRectangle(cornerRadius: 32).fill(palette.nightPanel) }
            else if palette.solid { RoundedRectangle(cornerRadius: 32).fill(Color(red: 0.07, green: 0.08, blue: 0.14)) }
        }
        .saturation(palette.nightVision ? 0 : 1)
        .colorMultiply(palette.nightVision ? palette.red : .white)
    }
    private var title: String {
        guard let view else { return nights == 0 ? String(localized: "Tonight") : "" }
        return view.isTonight ? String(localized: "Tonight") : view.park.dayLabel(view.night)
    }
    /// "As seen from Joshua Tree at 10:42 PM. Drag it to turn it."
    static func caption(_ view: MoonView) -> String {
        String(localized: "As seen from \(view.park.shortName) at \(view.park.time(view.moment)), its highest that night. Drag to turn it; it turns back to the face we always see.")
    }
}

#Preview("Moon controls") {
    let model = VisionModel(now: .now)
    return MoonControls(view: model.park.map { MoonView(park: $0, night: $0.currentNight(at: .now), isTonight: true) }, nights: .constant(0))
}

#Preview("Moon controls, a later night, night vision") {
    let model = VisionModel(now: .now)
    return MoonControls(view: model.park.map { MoonView(park: $0, night: $0.date($0.currentNight(at: .now), addingDays: 9), isTonight: false) }, nights: .constant(9))
        .environment(\.visionPalette, VisionPalette(nightVision: true))
}

#Preview("Moon controls, planner closed") {
    let model = VisionModel(now: .now)
    return MoonControls(view: model.park.map { MoonView(park: $0, night: $0.date($0.currentNight(at: .now), addingDays: 3), isTonight: false) }, nights: .constant(3), offersPlanner: true)
}

#Preview("Moon controls, accessibility size") {
    let model = VisionModel(now: .now)
    return MoonControls(view: model.park.map { MoonView(park: $0, night: $0.currentNight(at: .now), isTonight: true) }, nights: .constant(0))
        .dynamicTypeSize(.accessibility3)
}

#Preview("Moon volume", windowStyle: .volumetric) {
    MoonVolume().environment(VisionModel(now: .now))
}
