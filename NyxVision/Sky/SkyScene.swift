import RealityKit
import SwiftUI
import simd
import UIKit

/// "Stand under the sky": the celestial sphere around the viewer for one park, night and moment.
///
/// The stars (903 Yale Bright Star Catalogue stars, three meshes by brightness) and the Milky Way
/// are built once in celestial coordinates; a moment only turns that sphere (`SkyDome.rotation`),
/// so scrubbing a night is a single transform change. The Moon, the planets and the labels move
/// against the stars and are placed each moment; the sky's colour is redrawn only when the Sun or
/// the Moon has moved enough to change it. Nothing here touches the network.
@MainActor final class SkyScene {
    /// Floor origin of the immersive space.
    let root = Entity()
    private let eye = Entity()
    private let celestial = Entity()
    private let dome = ModelEntity()
    private let ground = ModelEntity()
    private var stars: [(entity: ModelEntity, layer: SkyDome.Layer)] = []
    private let milkyWay = ModelEntity()
    private let moon = ModelEntity()
    private let moonHalo = ModelEntity()
    /// Moonlight scattered by the air around the Moon, tens of degrees across.
    private let moonAureole = ModelEntity()
    /// A disc in the sky's own colour just behind the Moon: the night side hides the stars behind
    /// it, as the real one does, without punching a black hole in a twilight sky.
    private let moonShadow = ModelEntity()
    private var discTexture: TextureResource?
    private var moonTexture: TextureResource?
    private let sun = ModelEntity()
    private var planets: [String: ModelEntity] = [:]
    /// The galactic core's glow: a generous tap target with no feedback of its own (its label,
    /// closer to the eye, carries the hover effect and the accessibility element).
    private let coreTarget = Entity()
    private let coreLabel = Entity()
    private let card = Entity()
    private var compass: [Entity] = []
    private let plaque = Entity()
    /// An illustrative skyline in two ranges, the farther one paler with distance.
    private let farRidge = ModelEntity(), nearRidge = ModelEntity()
    private var additive: UnlitMaterial?
    private var starTexture: TextureResource?
    private var milkyWayTexture: TextureResource?
    private var glowTexture: TextureResource?
    private var aureoleTexture: TextureResource?
    /// Named stars and constellation figures (`SkyLore`). Each named star is a target over its
    /// catalogue star, nearly invisible until looked at, with the hover effect and name card planets have.
    private(set) var lore = SkyLore.empty
    private var catalogueStars: [CatalogueStar] = []
    private var namedStars: [String: ModelEntity] = [:]
    private var starAccess: [String: String] = [:]
    /// The stick figures: one mesh of thin ribbons in celestial coordinates, turning with the stars.
    private let figures = ModelEntity()
    private var lineTexture: TextureResource?
    private var linesOn = false, linesFade = 0.0, linesLevel = 0.0, linesColor = SIMD3<Double>(1, 1, 1)
    private var linesTask: Task<Void, Never>?
    /// A shell of input targets 40 m out, behind every star and label: what a drag on the empty
    /// sky lands on (`SkySpace` turns the night with it). It has no hover effect and draws nothing.
    let grab = Entity()

    // Distances in metres: far enough that both eyes see the sky at infinity, inside any far plane.
    static let starRadius: Float = 30, milkyWayRadius: Float = 34, domeRadius: Float = 48, bodyRadius: Float = 28, labelRadius: Float = 10
    /// The skyline stands in front of the stars and the Moon, so a rising Moon clears the ridge.
    static let nearRidgeRadius: Float = 22, farRidgeRadius: Float = 25
    static let eyeHeight: Float = 1.55
    /// The Moon is drawn 3 times its true 0.52° so its phase can be seen; its place is true.
    static let moonScale = 3.0

    // What was last applied, so each moment only redoes what changed.
    private var palette: VisionPalette?
    private var domeLight: SkyTextures.Light?
    private var sunAzimuth = Double.nan
    private var moonKey = ""
    private var domePark = ""
    private var ridgePark = ""
    private var labelKeys: [ObjectIdentifier: String] = [:]
    /// VoiceOver's activate on a body, kept alive with the scene.
    var activation: EventSubscription?
    /// VoiceOver's increment and decrement on the sky, kept alive with the scene.
    var adjustments: [EventSubscription] = []

    init() {
        root.name = "sky"
        eye.position = [0, Self.eyeHeight, 0]
        // DEBUG only: `-nyx-vision-look yaw,pitch` turns the whole scene so a screenshot can show
        // the sky above or beside the window. Never in Release.
        if let look = VisionDebug.look { eye.orientation = simd_quatf(angle: look.pitch*Float.pi/180, axis: [1, 0, 0])*simd_quatf(angle: -look.yaw*Float.pi/180, axis: [0, 1, 0]) }
        root.addChild(eye)
        eye.addChild(ground)
        for child in [dome, celestial, farRidge, nearRidge, moonAureole, moonHalo, moonShadow, moon, sun, coreTarget, coreLabel, card, plaque] as [Entity] { eye.addChild(child) }
    }

    /// Builds the meshes and textures. Async because the additive program compiles off the main thread.
    func build(palette: VisionPalette) async {
        var descriptor = UnlitMaterial.Program.Descriptor()
        descriptor.blendMode = .add
        // Exact colours: tone mapping would bleach bright stars to white and break night vision's red.
        descriptor.applyPostProcessToneMap = false
        var material = UnlitMaterial(program: await UnlitMaterial.Program(descriptor: descriptor))
        material.writesDepth = false
        material.faceCulling = .none
        additive = material

        // The static pictures, drawn once on the GPU: the Milky Way and the star atlas.
        if let image = Self.milkyWayImage() { milkyWayTexture = try? await TextureResource(image: image, options: .init(semantic: .color)) }
        if let image = Self.starAtlasImage() { starTexture = try? await TextureResource(image: image, options: .init(semantic: .color)) }
        if let image = SkyTextures.glow(color: SIMD3(1, 1, 1)) { glowTexture = try? await TextureResource(image: image, options: .init(semantic: .color)) }
        if let image = SkyTextures.aureole() { aureoleTexture = try? await TextureResource(image: image, options: .init(semantic: .color)) }
        if let image = SkyTextures.disc() { discTexture = try? await TextureResource(image: image, options: .init(semantic: .color)) }

        let catalogue = Self.catalogue()
        catalogueStars = catalogue
        for layer in [SkyDome.Layer.faint, .middle, .bright] {
            let members = catalogue.filter { star in
                switch layer { case .bright: star.mag < 2.2; case .middle: star.mag >= 2.2 && star.mag < 3.6; default: star.mag >= 3.6 }
            }
            let entity = ModelEntity()
            if let mesh = try? Self.starMesh(members) { entity.model = ModelComponent(mesh: mesh, materials: []) }
            celestial.addChild(entity)
            stars.append((entity, layer))
        }
        if let mesh = try? Self.milkyWayMesh() { milkyWay.model = ModelComponent(mesh: mesh, materials: []) }
        celestial.addChild(milkyWay)

        if let mesh = try? Self.domeMesh() { dome.model = ModelComponent(mesh: mesh, materials: []) }
        dome.components.set(AccessibilityComponent())

        // The ground: a dark disc to the horizon, hiding everything below it.
        ground.model = ModelComponent(mesh: .generateCylinder(height: 0.01, radius: 70), materials: [])
        ground.position = [0, -Self.eyeHeight-0.01, 0]

        let quad = Self.quad()
        for entity in [moon, moonHalo, moonAureole, moonShadow, sun] { entity.model = ModelComponent(mesh: quad, materials: []) }
        moon.name = "body:moon"
        Self.makeTappable(moon, radius: 1.2)
        for planet in SkyAlmanac.Planet.allCases {
            let entity = ModelEntity(mesh: quad, materials: [])
            entity.name = "body:"+planet.rawValue
            Self.makeTappable(entity, radius: 3)
            eye.addChild(entity)
            planets[planet.rawValue] = entity
        }
        coreTarget.name = "body:core"
        coreTarget.components.set(CollisionComponent(shapes: [.generateSphere(radius: 1.6)]))
        coreTarget.components.set(InputTargetComponent())
        for _ in 0..<4 { let label = Entity(); eye.addChild(label); compass.append(label) }
        buildLore(catalogue)
        buildGrab()
        apply(palette: palette)
    }

    /// Named stars' targets and the constellation figures' mesh.
    private func buildLore(_ catalogue: [CatalogueStar]) {
        lore = SkyLore.load(catalogue: catalogue)
        if let image = SkyTextures.image(width: 32, height: 4, pixel: { x, _ in
            // Across the ribbon: bright in the middle, soft to nothing at both edges, so a thin
            // line far away stays smooth instead of stepping.
            let u = abs((Double(x)+0.5)/16-1)
            return (SIMD3(repeating: SkyTextures.smooth(1-u)), 1)
        }) { lineTexture = try? TextureResource(image: image, options: .init(semantic: .color)) }
        if let mesh = try? Self.figureMesh(lore.lines, catalogue: catalogue) { figures.model = ModelComponent(mesh: mesh, materials: []) }
        figures.isEnabled = false
        celestial.addChild(figures)
        let quad = Self.quad()
        for star in lore.stars {
            let entity = ModelEntity(mesh: quad, materials: [])
            entity.name = "body:"+star.id
            // A target 0.7° across: close pairs such as Alnitak and Alnilam (1.4° apart) stay separate.
            Self.makeTappable(entity, radius: 0.5)
            eye.addChild(entity)
            namedStars[star.id] = entity
        }
    }
    /// About 145 overlapping panels, every 15° of azimuth and altitude from 15° below the
    /// horizon to 75° up, and a cap over the zenith.
    private func buildGrab() {
        grab.name = "sky.grab"
        let r: Float = 40, step = 15.0*Double.pi/180
        var shapes: [ShapeResource] = []
        for altitude in stride(from: -7.5, through: 67.5, by: 15) {
            for azimuth in stride(from: 0.0, to: 360, by: 15) {
                let position = Self.point(altitude, azimuth, 0, r)
                let width = Float(Double(r)*cos(altitude*Double.pi/180)*step*1.3)+0.5, height = Float(Double(r)*step*1.3)
                shapes.append(ShapeResource.generateBox(size: [width, height, 0.5]).offsetBy(rotation: Self.facingViewer(position), translation: position))
            }
        }
        let cap = r*Float(cos(75*Double.pi/180))*2.4
        shapes.append(ShapeResource.generateBox(size: [cap, 0.5, cap]).offsetBy(translation: [0, r*Float(sin(75*Double.pi/180)), 0]))
        grab.components.set(CollisionComponent(shapes: shapes))
        grab.components.set(InputTargetComponent())
        eye.addChild(grab)
    }
    /// The compass bearing (degrees from north) of a point in the scene, as seen from the eye:
    /// how a drag across the sky is measured.
    func azimuth(ofScenePoint point: SIMD3<Float>, facing: Double) -> Double {
        let local = eye.convert(position: point, from: nil)
        return SkyDome.horizontal(of: SIMD3<Double>(local), facing: facing).azimuth
    }

    // MARK: Each moment

    func update(plan: NightPlan, moment: SkyMoment, palette: VisionPalette, typeSize: DynamicTypeSize, selected: String?, constellations: Bool = true, reduceMotion: Bool = false) {
        apply(palette: palette)
        let park = plan.park, facing = SkyDome.facing(for: park)
        let m = moment.rotation
        let rotation = simd_float3x3(columns: (SIMD3<Float>(m.columns.0), SIMD3<Float>(m.columns.1), SIMD3<Float>(m.columns.2)))
        celestial.orientation = simd_quatf(rotation)

        // How dark the sky is: twilight, then moonlight and the park's own sky glow.
        let light = SkyTextures.Light(sunAltitude: moment.sunAltitude, skyGlow: Double(park.bortleEstimate-1)/8,
                                      moonGlare: SkyTextures.moonGlare(illumination: moment.moonIllumination, altitude: moment.moon.altitude))
        let glare = light.moonGlare
        // What the park's own light pollution leaves of the faint sky (Bortle 1 all of it, 5 about a third).
        let dark = pow(max(0.03, 1-0.12*Double(park.bortleEstimate-1)), 1.5)
        let boost = palette.highContrast ? 1.25 : 1.0
        for (entity, layer) in stars {
            var level = SkyDome.visibility(layer, sunAltitude: moment.sunAltitude)
            switch layer {
            case .faint: level *= (1-0.8*Self.smooth(glare/0.45))*(0.35+0.65*dark)
            case .middle: level *= 1-0.4*Self.smooth(glare/0.7)
            default: level *= 1-0.1*glare
            }
            tint(entity, texture: starTexture, level: level*boost, color: Self.ink(palette))
        }
        // The Milky Way: true darkness only, washed out by moonlight in proportion to its glare (a
        // quarter Moon high takes about half of it, a full Moon nearly all) and by the park's glow.
        let washed = 1-0.97*Self.smooth(glare/0.4)
        let milkyWayLight = 0.4*SkyDome.visibility(.milkyWay, sunAltitude: moment.sunAltitude)*washed*dark*boost
        tint(milkyWay, texture: milkyWayTexture, level: Self.srgb(milkyWayLight), color: Self.ink(palette))

        // The skyline, seeded by the park (built before its colour is set below).
        if ridgePark != park.id {
            ridgePark = park.id
            for (entity, far) in [(farRidge, true), (nearRidge, false)] {
                let heights = SkyTextures.skyline(seed: park.id, far: far)
                if let mesh = try? Self.ridgeMesh(heights, facing: facing, radius: far ? Self.farRidgeRadius : Self.nearRidgeRadius) {
                    let materials = entity.model?.materials ?? []
                    entity.model = ModelComponent(mesh: mesh, materials: materials)
                }
            }
        }
        // The dome and the skyline's colour, redrawn only when the light has changed visibly.
        let changed = domeLight.map { abs($0.sunAltitude-light.sunAltitude) > 0.3 || abs($0.moonGlare-light.moonGlare) > 0.01 } ?? true
        if changed || abs(moment.sunAzimuth-sunAzimuth) > 2 || self.palette != palette || domePark != park.id {
            domePark = park.id; domeLight = light; sunAzimuth = moment.sunAzimuth
            let paint = palette.sky
            if let image = SkyTextures.dome(light, color: paint), let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
                dome.model?.materials = [Self.plain(texture)]
            }
            // The mesh's u = 0.5 meridian points at the Sun.
            dome.orientation = simd_quatf(angle: Float(-(moment.sunAzimuth-facing)*Double.pi/180), axis: [0, 1, 0])
            // Land is darker than any sky above it; the far range takes a little of the horizon's
            // colour, as distant hills do in haze.
            let horizon = SkyTextures.skyColor(altitude: 1.5, fromSun: 100, light)
            solid(nearRidge, paint(Self.land))
            solid(farRidge, paint(Self.land+(horizon-Self.land)*0.32))
        }
        var domeAccess = AccessibilityComponent()
        domeAccess.isAccessibilityElement = true
        // VoiceOver's swipe up and down move the clock half an hour, as a drag across the sky does.
        domeAccess.systemActions = [.increment, .decrement]
        domeAccess.label = LocalizedStringResource(stringLiteral: String(localized: "Sky over \(park.shortName) at \(park.time(moment.date))"))
        domeAccess.value = LocalizedStringResource(stringLiteral: Self.summary(moment))
        dome.components.set(domeAccess)

        placeMoon(plan: plan, moment: moment, facing: facing, palette: palette, light: light)
        placePlanets(moment: moment, facing: facing, palette: palette)
        // The Sun itself only under the midnight sun.
        if moment.sunAltitude > -1 {
            sun.isEnabled = true
            billboard(sun, altitude: moment.sunAltitude, azimuth: moment.sunAzimuth, facing: facing, radius: Self.bodyRadius, degrees: 3)
            tint(sun, texture: glowTexture, level: 1, color: palette.sky(SIMD3(1, 0.93, 0.8)))
        } else { sun.isEnabled = false }

        let coreShown = moment.core.altitude > 0 && SkyDome.visibility(.milkyWay, sunAltitude: moment.sunAltitude) > 0.3
        // Moonlight can leave nothing of the band to point at: the label then says so instead of
        // naming a patch of empty, moonlit sky.
        let coreWashed = Self.coreWashedOut(moonUp: moment.moon.up, washed: washed)
        let coreTitle = coreWashed ? String(localized: "Milky Way core, washed out by the Moon") : moment.core.name
        coreTarget.isEnabled = coreShown
        coreLabel.isEnabled = coreShown
        if coreShown {
            coreTarget.position = Self.point(moment.core.altitude, moment.core.azimuth, facing, Self.bodyRadius)
            let face = label(coreLabel, SkyLabel(title: coreTitle, detail: nil, style: .whisper, palette: palette, typeSize: typeSize),
                             key: "core\(palette.nightVision)\(coreWashed)", altitude: moment.core.altitude-2.4, azimuth: moment.core.azimuth, facing: facing)
            if let face {
                // The visible words are what the eye lands on: they light up under a look and answer a tap.
                if face.name != "body:core" {
                    face.name = "body:core"
                    face.components.set(CollisionComponent(shapes: [.generateBox(size: [1, 1, 0.02])]))
                    face.components.set(InputTargetComponent())
                    face.components.set(HoverEffectComponent())
                }
                face.components.set(Self.access(coreTitle, moment.core.place))
            }
        }
        placeStars(moment: moment, facing: facing, palette: palette)
        placeLines(moment: moment, palette: palette, glare: glare, on: constellations, reduceMotion: reduceMotion)
        placeCompass(facing: facing, palette: palette, typeSize: typeSize)
        placeCard(selected: selected, moment: moment, plan: plan, facing: facing, palette: palette, typeSize: typeSize, coreWashed: coreWashed)
        let night = park.dayLabel(plan.sky.evening)
        let plaqueText = String(localized: "Computed for \(park.shortName), \(night). Not a live view; clouds not shown, and the skyline is illustrative. Ahead is \(Compass.name(facing)), not your room's real north.")
        // Scaled by its distance from the eye, so it reads at the size it would at one metre.
        let plaquePosition: SIMD3<Float> = [0, -0.95, -1.9]
        label(plaque, SkyLabel(title: park.shortName, detail: plaqueText, style: .plaque, palette: palette, typeSize: typeSize),
              key: "plaque\(park.id)\(night)\(palette.nightVision)", position: plaquePosition, scale: simd_length(plaquePosition))
        plaque.components.set(Self.access(park.shortName, plaqueText, activatable: false))
    }

    private func placeMoon(plan: NightPlan, moment: SkyMoment, facing: Double, palette: VisionPalette, light: SkyTextures.Light) {
        let up = moment.moon.altitude > -1
        moon.isEnabled = up; moonHalo.isEnabled = up; moonShadow.isEnabled = up; moonAureole.isEnabled = up
        guard up else { return }
        let size = 0.52*Self.moonScale
        billboard(moon, altitude: moment.moon.altitude, azimuth: moment.moon.azimuth, facing: facing, radius: Self.bodyRadius, degrees: size)
        billboard(moonHalo, altitude: moment.moon.altitude, azimuth: moment.moon.azimuth, facing: facing, radius: Self.bodyRadius+0.5, degrees: size*7)
        billboard(moonAureole, altitude: moment.moon.altitude, azimuth: moment.moon.azimuth, facing: facing, radius: Self.bodyRadius+0.8, degrees: 56)
        billboard(moonShadow, altitude: moment.moon.altitude, azimuth: moment.moon.azimuth, facing: facing, radius: Self.bodyRadius+0.2, degrees: size*0.985)
        if let discTexture {
            let fromSun = abs((moment.moon.azimuth-moment.sunAzimuth+540).truncatingRemainder(dividingBy: 360)-180)
            let c = palette.sky(SkyTextures.skyColor(altitude: moment.moon.altitude, fromSun: fromSun, light))
            var material = Self.plain(discTexture)
            // The dome's texture is sRGB-encoded; a tint is given in sRGB too, so encode to match.
            let e = SIMD3(Self.srgb(c.x), Self.srgb(c.y), Self.srgb(c.z))
            material.color = .init(tint: UIColor(red: e.x, green: e.y, blue: e.z, alpha: 1), texture: .init(discTexture))
            material.opacityThreshold = 0.5
            moonShadow.model?.materials = [material]
        }
        // The halo and the wide aureole grow with the Moon's glare, so a crescent wears a faint
        // ring and a full Moon lights a broad patch of sky around itself.
        let moonColor = palette.sky(SIMD3(0.85, 0.88, 0.95))
        let low = max(0, min(1, moment.moon.altitude/5+0.5))
        tint(moonHalo, texture: glowTexture, level: (0.12+0.4*sqrt(light.moonGlare))*moment.moonIllumination.squareRoot()*low, color: moonColor)
        tint(moonAureole, texture: aureoleTexture, level: Self.srgb(0.1*light.moonGlare), color: palette.sky(SIMD3(0.75, 0.83, 1)))
        // The disc is re-rendered when its look changes by more than a couple of degrees of tilt.
        let geometry = AstronomyEngine().moonGeometry(for: plan.park, at: moment.date)
        // Added light over the disc behind it: the lit limb and earthshine, nothing outside the limb.
        let key = "\(plan.park.id)-\(Int(geometry.brightLimb*90/Double.pi))-\(Int(geometry.phaseAngle*180/Double.pi))"
        if key != moonKey, let image = Self.moonImage(geometry), let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            moonKey = key
            moonTexture = texture
        }
        tint(moon, texture: moonTexture, level: 1, color: Self.ink(palette))
        let percent = Int((moment.moonIllumination*100).rounded())
        moon.components.set(Self.access(String(localized: "Moon, \(percent) percent lit"), moment.moon.place))
    }

    private func placePlanets(moment: SkyMoment, facing: Double, palette: VisionPalette) {
        let visible = Set(moment.visiblePlanets.map(\.id))
        for body in moment.planets {
            guard let entity = planets[body.id] else { continue }
            entity.isEnabled = visible.contains(body.id)
            guard entity.isEnabled else { continue }
            let size = max(0.5, 0.72-0.08*body.magnitude)
            billboard(entity, altitude: body.altitude, azimuth: body.azimuth, facing: facing, radius: Self.bodyRadius, degrees: size)
            // As bright as the brightest stars or a little more, never a beacon.
            let level = max(0.9, min(1.8, 1.4-0.2*body.magnitude))*SkyDome.visibility(.bright, sunAltitude: moment.sunAltitude)
            tint(entity, texture: glowTexture, level: level, color: palette.sky(Self.planetColor(body.id)))
            entity.components.set(Self.access(body.name, "\(body.place), \(WhatsUp.brightness(body.magnitude))"))
        }
    }

    private func placeCompass(facing: Double, palette: VisionPalette, typeSize: DynamicTypeSize) {
        let points: [(String, Double)] = [(String(localized: "N"), 0), (String(localized: "E"), 90), (String(localized: "S"), 180), (String(localized: "W"), 270)]
        for (entity, point) in zip(compass, points) {
            // On the dark land just under the skyline, where a planetarium writes them.
            label(entity, SkyLabel(title: point.0, detail: nil, style: .compass, palette: palette, typeSize: typeSize), key: "\(point.0)\(palette.nightVision)\(palette.highContrast)",
                  altitude: -2.4, azimuth: point.1, facing: facing, radius: 12)
            // Nothing happens on activate, so VoiceOver offers no action.
            entity.components.set(Self.access(Compass.name(point.1).capitalized, String(localized: "Compass point on the horizon"), activatable: false))
        }
    }

    /// Where a catalogue star is at a moment: altitude and azimuth, degrees.
    private func horizontal(row: Int, moment: SkyMoment, facing: Double) -> (altitude: Double, azimuth: Double)? {
        guard catalogueStars.indices.contains(row) else { return nil }
        let star = catalogueStars[row]
        return SkyDome.horizontal(of: moment.rotation*SkyDome.celestial(ra: star.ra, dec: star.dec), facing: facing)
    }
    /// Named stars' targets, over their stars, while they are up and the sky is dark enough to show them.
    private func placeStars(moment: SkyMoment, facing: Double, palette: VisionPalette) {
        for star in lore.stars {
            guard let entity = namedStars[star.id], let place = horizontal(row: star.row, moment: moment, facing: facing) else { continue }
            let seen = SkyDome.visibility(star.magnitude < 2.2 ? .bright : .middle, sunAltitude: moment.sunAltitude) > 0.3
            guard place.altitude > 1, seen else { entity.isEnabled = false; continue }
            billboard(entity, altitude: place.altitude, azimuth: place.azimuth, facing: facing, radius: Self.bodyRadius+0.6, degrees: 1.4)
            // A breath of glow, too faint to notice until a look brightens it: the hover effect's canvas.
            tint(entity, texture: glowTexture, level: 0.02, color: Self.ink(palette))
            // "Vega", "high in the west, in Lyra". Rebuilt only when the words change.
            let value = String(localized: "\(SkyLore.direction(altitude: place.altitude, azimuth: place.azimuth)), in \(star.constellation)")
            if starAccess[star.id] != value {
                starAccess[star.id] = value
                entity.components.set(Self.access(star.name, value))
            }
        }
    }
    /// The figures: faint, cool lines that fade in over 0.6 s (at once under Reduce Motion) and
    /// follow twilight as the middle stars do, a little dimmer under a bright Moon.
    private func placeLines(moment: SkyMoment, palette: VisionPalette, glare: Double, on: Bool, reduceMotion: Bool) {
        linesLevel = 0.3*SkyDome.visibility(.middle, sunAltitude: moment.sunAltitude)*(1-0.4*Self.smooth(glare/0.7))*(palette.highContrast ? 1.5 : 1)
        linesColor = palette.sky(SIMD3(0.62, 0.72, 1))
        if on != linesOn {
            linesOn = on
            linesTask?.cancel()
            if reduceMotion {
                linesFade = on ? 1 : 0
            } else {
                let start = linesFade, goal: Double = on ? 1 : 0, began = Date.now
                linesTask = Task { [weak self] in
                    while !Task.isCancelled {
                        let t = min(1, Date.now.timeIntervalSince(began)/0.6)
                        guard let self else { return }
                        self.linesFade = start+(goal-start)*Self.smooth(t)
                        self.paintLines()
                        if t >= 1 { return }
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
            }
        }
        paintLines()
    }
    private func paintLines() {
        tint(figures, texture: lineTexture, level: linesLevel*linesFade, color: linesColor)
    }
    /// True when moonlight has washed the band out enough that a label on the core would name nothing visible.
    nonisolated static func coreWashedOut(moonUp: Bool, washed: Double) -> Bool { moonUp && washed < 0.3 }

    private func placeCard(selected: String?, moment: SkyMoment, plan: NightPlan, facing: Double, palette: VisionPalette, typeSize: DynamicTypeSize, coreWashed: Bool) {
        if let selected, let star = lore.stars.first(where: { $0.id == selected }) {
            guard let place = horizontal(row: star.row, moment: moment, facing: facing), namedStars[star.id]?.isEnabled == true else { card.isEnabled = false; return }
            card.isEnabled = true
            let detail = "\(String(localized: "\(Int(place.altitude.rounded()))° up in the \(Compass.name(place.azimuth))")) · \(star.constellation) · \(SkyLore.brightness(star.magnitude))"
            label(card, SkyLabel(title: star.name, detail: detail, style: .card, palette: palette, typeSize: typeSize), key: "card\(star.id)\(detail)\(palette.nightVision)",
                  altitude: place.altitude-(typeSize.isAccessibilitySize ? 3.4 : 2.4), azimuth: place.azimuth, facing: facing)
            card.components.set(Self.access(star.name, detail, activatable: false))
            return
        }
        let bodies = [moment.moon, moment.core] + moment.planets
        guard let selected, let body = bodies.first(where: { $0.id == selected }), body.up else { card.isEnabled = false; return }
        card.isEnabled = true
        var detail = body.place
        if body.kind == .planet { detail += " · " + WhatsUp.brightness(body.magnitude) }
        if body.kind == .moon { detail += " · " + String(localized: "\(Int((moment.moonIllumination*100).rounded()))% lit") }
        if body.kind == .core { detail += " · " + (coreWashed ? String(localized: "washed out by moonlight") : String(localized: "the bright center of our galaxy")) }
        label(card, SkyLabel(title: body.name, detail: detail, style: .card, palette: palette, typeSize: typeSize), key: "card\(body.id)\(detail)\(palette.nightVision)",
              altitude: body.altitude-(body.kind == .moon ? 3.4 : 2.8), azimuth: body.azimuth, facing: facing)
        card.components.set(Self.access(body.name, detail, activatable: false))
    }

    // MARK: Palette

    private func apply(palette: VisionPalette) {
        guard palette != self.palette else { return }
        self.palette = palette
        domeLight = nil
        moonKey = ""
        labelKeys = [:]
        // The textures keep their natural colours; night vision is the materials' red tint.
        var groundMaterial = UnlitMaterial(applyPostProcessToneMap: false)
        let ground = palette.sky(Self.land*0.8)
        groundMaterial.color = .init(tint: UIColor(red: Self.srgb(ground.x), green: Self.srgb(ground.y), blue: Self.srgb(ground.z), alpha: 1))
        self.ground.model?.materials = [groundMaterial]
    }
    /// The land's colour, linear: far darker than the darkest sky, so the skyline always reads.
    static let land = SIMD3(0.0011, 0.0011, 0.0014)
    /// An opaque, unlit colour (linear RGB).
    private func solid(_ entity: ModelEntity, _ color: SIMD3<Double>) {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: UIColor(red: Self.srgb(color.x), green: Self.srgb(color.y), blue: Self.srgb(color.z), alpha: 1))
        material.faceCulling = .none
        entity.model?.materials = [material]
    }
    /// Sets an additive material whose brightness is its tint (additive light ignores opacity).
    private func tint(_ entity: ModelEntity, texture: TextureResource?, level: Double, color: SIMD3<Double> = SIMD3(1, 1, 1)) {
        guard var material = additive, let texture else { return }
        let c = color*max(0, min(1.5, level))
        material.color = .init(tint: UIColor(red: c.x, green: c.y, blue: c.z, alpha: 1), texture: .init(texture))
        entity.model?.materials = [material]
        entity.isEnabled = level > 0.003
    }

    // MARK: Placement

    static func point(_ altitude: Double, _ azimuth: Double, _ facing: Double, _ radius: Float) -> SIMD3<Float> {
        SIMD3<Float>(SkyDome.direction(altitude: altitude, azimuth: azimuth, facing: facing))*radius
    }
    /// Places a quad facing the viewer, upright toward the zenith, `degrees` across.
    private func billboard(_ entity: Entity, altitude: Double, azimuth: Double, facing: Double, radius: Float, degrees: Double) {
        let position = Self.point(altitude, azimuth, facing, radius)
        entity.position = position
        entity.orientation = Self.facingViewer(position)
        let side = Float(2*Double(radius)*tan(degrees/2*Double.pi/180))
        entity.scale = [side, side, side]
    }
    /// The rotation whose +z points back at the viewer and whose +y leans toward the zenith.
    static func facingViewer(_ position: SIMD3<Float>) -> simd_quatf {
        let z = simd_normalize(-position)
        var up = SIMD3<Float>(0, 1, 0) - simd_dot(SIMD3<Float>(0, 1, 0), z)*z
        if simd_length(up) < 1e-4 { up = [0, 0, -1] }
        up = simd_normalize(up)
        let x = simd_cross(up, z)
        return simd_quatf(simd_float3x3(columns: (x, up, z)))
    }
    /// A SwiftUI label in the sky, scaled with distance so it reads at the size it would at one metre.
    @discardableResult
    private func label(_ entity: Entity, _ view: SkyLabel, key: String, altitude: Double, azimuth: Double, facing: Double, radius: Float = SkyScene.labelRadius) -> ModelEntity? {
        let position = Self.point(altitude, azimuth, facing, radius)
        return label(entity, view, key: key, position: position, scale: radius)
    }
    /// Labels are SwiftUI views rendered once into a texture on a quad (re-rendered only when their
    /// words or the person's text size change): view attachments far out in an immersive sky
    /// appeared late or not at all. Returns the quad that shows the words.
    @discardableResult
    private func label(_ entity: Entity, _ view: SkyLabel, key: String, position: SIMD3<Float>, scale: Float) -> ModelEntity? {
        entity.position = position
        entity.orientation = Self.facingViewer(position)
        entity.scale = [scale, scale, scale]
        let id = ObjectIdentifier(entity), key = "\(key)|\(view.typeSize)|\(view.palette.highContrast)|\(view.palette.solid)"
        guard labelKeys[id] != key else { return entity.children.first as? ModelEntity }
        let renderer = ImageRenderer(content: view.environment(\.dynamicTypeSize, view.typeSize))
        renderer.scale = 3
        guard let image = renderer.cgImage, let texture = try? TextureResource(image: image, options: .init(semantic: .color)) else { return entity.children.first as? ModelEntity }
        labelKeys[id] = key
        let face = entity.children.first as? ModelEntity ?? {
            let quad = ModelEntity(mesh: Self.quad(), materials: [])
            entity.addChild(quad)
            return quad
        }()
        var material = Self.plain(texture)
        material.blending = .transparent(opacity: 1.0)
        // A label must not hide the additive sky behind its transparent margins.
        material.writesDepth = false
        face.model?.materials = [material]
        // About 0.9 mm per point at one metre, the size system text has at that distance.
        let metresPerPoint: Float = 0.00088
        face.scale = [Float(image.width)/3*metresPerPoint, Float(image.height)/3*metresPerPoint, 1]
        return face
    }

    // MARK: Meshes

    nonisolated struct CatalogueStar: Sendable { let ra: Double; let dec: Double; let mag: Double; let bv: Double }
    nonisolated static func catalogue(bundle: Bundle = .main) -> [CatalogueStar] {
        guard let url = bundle.url(forResource: "stars", withExtension: "json"), let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([[Double]].self, from: data) else { return [] }
        return rows.compactMap { $0.count == 4 ? CatalogueStar(ra: $0[0]*Double.pi/180, dec: $0[1]*Double.pi/180, mag: $0[2], bv: $0[3]) : nil }
    }
    /// One quad per star in celestial coordinates, facing the centre, sized by magnitude, with
    /// texture coordinates picking its colour from the star strip. One mesh, one draw.
    static func starMesh(_ stars: [CatalogueStar]) throws -> MeshResource {
        var positions: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        for star in stars {
            let c = SkyDome.celestial(ra: star.ra, dec: star.dec)
            let centre = SIMD3<Float>(c)*starRadius
            let reference: SIMD3<Double> = abs(c.z) > 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)
            let t1 = SIMD3<Float>(simd_normalize(simd_cross(c, reference))), t2 = SIMD3<Float>(simd_normalize(simd_cross(c, simd_cross(c, reference))))
            // Each star's quad is as wide as its atlas cell draws it: wider for brighter stars.
            let degrees = SkyTextures.starSize(magnitude: star.mag)
            let half = starRadius*Float(tan(degrees/2*Double.pi/180))
            let base = UInt32(positions.count)
            positions += [centre-(t1+t2)*half, centre+(t1-t2)*half, centre+(t1+t2)*half, centre+(t2-t1)*half]
            let column = Float(SkyTextures.column(forColorIndex: star.bv)), n = Float(SkyTextures.starColumns)
            let row = Float(SkyTextures.row(forMagnitude: star.mag)), rows = Float(SkyTextures.starRows)
            let u0 = column/n, u1 = (column+1)/n
            // The atlas's row 0 is its top, where v = 1.
            let v0 = 1-(row+1)/rows, v1 = 1-row/rows
            uvs += [[u0, v0], [u1, v0], [u1, v1], [u0, v1]]
            indices += [base, base+1, base+2, base, base+2, base+3]
        }
        var descriptor = MeshDescriptor(name: "stars")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
    /// The constellation figures: each line a thin ribbon along the great circle between two
    /// catalogue stars, stopping short of both so the stars stand clear of their lines, as on a
    /// planetarium dome. Celestial coordinates, just inside the stars.
    static func figureMesh(_ lines: [(Int, Int)], catalogue: [CatalogueStar]) throws -> MeshResource? {
        let radius = starRadius-0.5, halfWidth = Double(radius)*tan(0.055*Double.pi/180)
        var positions: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        for (a, b) in lines where catalogue.indices.contains(a) && catalogue.indices.contains(b) {
            let p = SkyDome.celestial(ra: catalogue[a].ra, dec: catalogue[a].dec), q = SkyDome.celestial(ra: catalogue[b].ra, dec: catalogue[b].dec)
            let angle = acos(max(-1, min(1, simd_dot(p, q))))
            // The gap at each end: half the star's drawn size and a little more.
            let gapA = (SkyTextures.starSize(magnitude: catalogue[a].mag)/2+0.45)*Double.pi/180
            let gapB = (SkyTextures.starSize(magnitude: catalogue[b].mag)/2+0.45)*Double.pi/180
            guard angle > gapA+gapB+0.002 else { continue }
            let steps = max(1, Int((angle*180/Double.pi/2).rounded(.up)))
            let axis = simd_normalize(simd_cross(p, q))
            let side = SIMD3<Float>(axis*halfWidth)
            for i in 0...steps {
                // p turned toward q by t about their common axis (Rodrigues; axis ⟂ p).
                let t = gapA+(angle-gapA-gapB)*Double(i)/Double(steps)
                let centre = SIMD3<Float>(p*cos(t)+simd_cross(axis, p)*sin(t))*radius
                positions += [centre-side, centre+side]
                let v = Float(i)/Float(steps)
                uvs += [[0, v], [1, v]]
                if i > 0 {
                    let base = UInt32(positions.count-4)
                    indices += [base, base+1, base+3, base, base+3, base+2]
                }
            }
        }
        guard !indices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: "figures")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
    /// The band between galactic latitudes −30° and +30°, all the way round: wide enough that the
    /// bulge's glow has faded to nothing well inside it.
    static func milkyWayMesh() throws -> MeshResource {
        var positions: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        let columns = 240, rows = 30, latitude = SkyTextures.milkyWayLatitude
        for i in 0...columns {
            for j in 0...rows {
                let l = (Double(i)/Double(columns)+0.5)*2*Double.pi, b = (-latitude+2*latitude*Double(j)/Double(rows))*Double.pi/180
                let e = SkyDome.equatorial(galacticLongitude: l, latitude: b)
                positions.append(SIMD3<Float>(SkyDome.celestial(ra: e.ra, dec: e.dec))*milkyWayRadius)
                // Mesh and texture both start at the anticentre (l = 180°), so the seam is where the band is faintest.
                uvs.append([Float(i)/Float(columns), Float(j)/Float(rows)])
            }
        }
        for i in 0..<columns {
            for j in 0..<rows {
                let a = UInt32(i*(rows+1)+j), b = a+UInt32(rows+1)
                indices += [a, b, b+1, a, b+1, a+1]
            }
        }
        var descriptor = MeshDescriptor(name: "milkyWay")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
    /// The inside of a sphere from 10° below the horizon to the zenith; u = 0.5 points ahead (−z).
    /// Rows every 2°, so the twilight's low bands are not bent by long triangles.
    static func domeMesh() throws -> MeshResource {
        var positions: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        let columns = 72, rows = 50
        for i in 0...columns {
            for j in 0...rows {
                let u = Double(i)/Double(columns), altitude = 90-100*Double(j)/Double(rows)
                let angle = (u-0.5)*360
                positions.append(SIMD3<Float>(SkyDome.direction(altitude: altitude, azimuth: angle, facing: 0))*domeRadius)
                uvs.append([Float(u), Float(1-Double(j)/Double(rows))])
            }
        }
        for i in 0..<columns {
            for j in 0..<rows {
                let a = UInt32(i*(rows+1)+j), b = a+UInt32(rows+1)
                indices += [a, b, b+1, a, b+1, a+1]
            }
        }
        var descriptor = MeshDescriptor(name: "dome")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
    /// The skyline: a wall from 12° below the horizon up to the land's height, every half degree
    /// of azimuth all the way round, `radius` metres out.
    static func ridgeMesh(_ heights: [Double], facing: Double, radius: Float) throws -> MeshResource {
        var positions: [SIMD3<Float>] = [], indices: [UInt32] = []
        let count = heights.count-1
        for i in 0...count {
            let azimuth = Double(i)*360/Double(count)
            positions.append(SIMD3<Float>(SkyDome.direction(altitude: -12, azimuth: azimuth, facing: facing))*radius)
            positions.append(SIMD3<Float>(SkyDome.direction(altitude: heights[i], azimuth: azimuth, facing: facing))*radius)
        }
        for i in 0..<count {
            let a = UInt32(2*i), b = a+2
            indices += [a, b, b+1, a, b+1, a+1]
        }
        var descriptor = MeshDescriptor(name: "ridge")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
    /// A unit square in the xy plane facing +z, texture upright (v = 1 at the top).
    static func quad() -> MeshResource {
        var descriptor = MeshDescriptor(name: "quad")
        descriptor.positions = MeshBuffers.Positions([[-0.5, -0.5, 0], [0.5, -0.5, 0], [0.5, 0.5, 0], [-0.5, 0.5, 0]])
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates([[0, 0], [1, 0], [1, 1], [0, 1]])
        descriptor.primitives = .triangles([0, 1, 2, 0, 2, 3])
        return (try? MeshResource.generate(from: [descriptor])) ?? .generatePlane(width: 1, height: 1)
    }

    // MARK: Helpers

    /// An unlit, untone-mapped textured material, visible from both sides.
    static func plain(_ texture: TextureResource) -> UnlitMaterial {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        material.faceCulling = .none
        return material
    }

    private static func makeTappable(_ entity: Entity, radius: Float) {
        // The quad is scaled to the body's size; the target is sized in that unit, generous to the eye.
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
        entity.components.set(InputTargetComponent())
        entity.components.set(HoverEffectComponent())
    }
    /// An accessibility element. `activatable` bodies answer VoiceOver's activate as a tap does
    /// (`SkySpace` handles `AccessibilityEvents.Activate`): the name card shows or hides.
    static func access(_ label: String, _ value: String, activatable: Bool = true) -> AccessibilityComponent {
        var component = AccessibilityComponent()
        component.isAccessibilityElement = true
        component.label = LocalizedStringResource(stringLiteral: label)
        component.value = LocalizedStringResource(stringLiteral: value)
        if activatable { component.systemActions = [.activate] }
        return component
    }
    static func smooth(_ x: Double) -> Double { SkyTextures.smooth(x) }
    static func srgb(_ linear: Double) -> Double {
        let c = min(1, max(0, linear))
        return c <= 0.0031308 ? 12.92*c : 1.055*pow(c, 1/2.4)-0.055
    }
    /// The tint over grey sky textures: white, or night vision's red.
    static func ink(_ palette: VisionPalette) -> SIMD3<Double> { palette.nightVision ? SIMD3(1, 0.2, 0.16) : SIMD3(1, 1, 1) }
    static func planetColor(_ id: String) -> SIMD3<Double> {
        switch id {
        case "mars": SIMD3(1, 0.62, 0.45)
        case "saturn": SIMD3(1, 0.9, 0.7)
        case "jupiter": SIMD3(1, 0.95, 0.86)
        case "mercury": SIMD3(1, 0.92, 0.82)
        default: SIMD3(1, 1, 0.94)
        }
    }
    static func summary(_ moment: SkyMoment) -> String {
        var parts = [moment.twilight]
        parts.append(moment.moon.up ? String(localized: "Moon \(moment.moon.place), \(Int((moment.moonIllumination*100).rounded()))% lit") : String(localized: "Moon below the horizon"))
        parts += moment.visiblePlanets.map { "\($0.name) \($0.place)" }
        if moment.core.up && moment.sunAltitude < -15 { parts.append("\(moment.core.name) \(moment.core.place)") }
        return parts.joined(separator: ". ")
    }
    /// The Milky Way, drawn once by `nyxMilkyWay` (SkyShaders.metal): about 50 ms on the GPU.
    static func milkyWayImage() -> CGImage? {
        let width = SkyTextures.milkyWayWidth, height = SkyTextures.milkyWayHeight
        let view = Rectangle().fill(.black).frame(width: CGFloat(width), height: CGFloat(height))
            .colorEffect(ShaderLibrary.nyxMilkyWay(.float2(CGSize(width: width, height: height)), .float(SkyTextures.milkyWayLatitude)))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }
    /// The star atlas, drawn once by `nyxStarAtlas` from `SkyTextures.look` and the B−V colours.
    static func starAtlasImage() -> CGImage? {
        let cell = SkyTextures.starCell
        let view = Rectangle().fill(.black).frame(width: CGFloat(cell*SkyTextures.starColumns), height: CGFloat(cell*SkyTextures.starRows))
            .colorEffect(ShaderLibrary.nyxStarAtlas(.float2(CGSize(width: cell, height: cell)), .floatArray(SkyTextures.atlasLooks()), .floatArray(SkyTextures.atlasColors())))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }
    /// The Moon disc for a moment, rendered from the same shader as the window and the iPhone.
    static func moonImage(_ geometry: MoonGeometry) -> CGImage? {
        if VisionDebug.isEnabled("vision-uvtest") {
            let renderer = ImageRenderer(content: Text("R↑").font(.system(size: 120, weight: .bold)).foregroundStyle(.white).frame(width: 256, height: 256).background(.blue))
            return renderer.cgImage
        }
        let renderer = ImageRenderer(content: VisionMoon(geometry: geometry).frame(width: 256, height: 256))
        renderer.scale = 1
        return renderer.cgImage
    }
}
