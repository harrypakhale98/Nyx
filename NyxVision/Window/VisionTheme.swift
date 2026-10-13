import SwiftUI

/// Nyx's palette on Vision Pro: starlight text, moon-amber for the score, void black behind the
/// sky. Night vision turns everything a dim signal red, in the window and in the immersive sky.
/// Derived from the iPhone's `NyxPalette` and `NightTint` (one copy of every colour, NyxPalette.swift),
/// so Vision Pro can never drift from the red the contrast tests measure.
struct VisionPalette: Equatable {
    var nightVision = false
    var highContrast = false
    /// Reduce Transparency: panels behind words become nearly opaque.
    var solid = false
    /// The iPhone's palette with the same switches. Vision Pro has no "Brighter red" of its own and
    /// no channel to the iPhone's setting, so its red follows Increase Contrast, as the iPhone's does.
    var base: NyxPalette { NyxPalette(nightVision: nightVision, highContrast: highContrast) }
    /// Window colours. In night vision the window's red filter does the tinting, so ink stays
    /// white there (as on the iPhone): a red ink filtered again would turn a dim, unreadable red.
    var ink: Color { base.ink }
    var accent: Color { base.accent }
    /// Words in the immersive sky, which no window filter reaches. In night vision always the
    /// brighter red (`NightTint.brighter`), at full strength (`skyOpacity`): over the dark sky, with
    /// no Increase Contrast to ask for it, the standard red reads at only 4.3:1 for protan eyes,
    /// and the brighter one at 5.1:1 (at 0.78 opacity it too would fall to 4.2:1).
    var skyInk: Color { nightVision ? NightTint.brighter.color : NyxPalette.starlight }
    /// A sky label's opacity: as given in starlight, full under Increase Contrast or in night vision.
    func skyOpacity(_ opacity: Double) -> Double { highContrast || nightVision ? 1 : opacity }
    /// Night vision's red multiplier (`NyxPalette.red`, `NightTint`): the deepest red that keeps
    /// text at 6.2:1 on black, or under Increase Contrast the brighter one that keeps it above
    /// 4.5:1 for protan and deutan eyes too.
    var red: Color { base.red.color }
    /// Secondary text. On glass it is the system's vibrant secondary style, which keeps its
    /// contrast over whatever the room shows through; night vision and Increase Contrast use a
    /// near-solid ink instead.
    var muted: AnyShapeStyle {
        highContrast || nightVision ? AnyShapeStyle(ink.opacity(highContrast ? 0.95 : 0.9)) : AnyShapeStyle(.secondary)
    }
    var line: Color { ink.opacity(highContrast ? 0.6 : 0.2) }
    /// Behind the window's content in night vision, where grey glass would read as a bright panel:
    /// the iPhone's night panel.
    var nightPanel: Color { NyxPalette(nightVision: true, highContrast: highContrast).panel }
    /// Behind words under Reduce Transparency, in place of glass: a near-opaque deep indigo.
    var solidPanel: Color { NyxPalette.indigo }
    /// The iPhone's night-vision filter applied to a colour in the sky (`NightTint.filtered`, one
    /// copy): desaturated, then multiplied by this palette's red, so the sky leaks no more green
    /// or blue than the iPhone's screen does.
    func sky(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        nightVision ? base.red.filtered(rgb) : rgb
    }
}
private struct VisionPaletteKey: EnvironmentKey { static let defaultValue = VisionPalette() }
extension EnvironmentValues {
    var visionPalette: VisionPalette { get { self[VisionPaletteKey.self] } set { self[VisionPaletteKey.self] = newValue } }
}
enum VisionMotion {
    /// The app's one spring: the iPhone's own (`NyxMotion.spring`).
    static let spring = NyxMotion.spring
}

/// Small spaced capitals over a section, as on the iPhone; set solid in Japanese (`Lettering`).
struct VisionEyebrow: View {
    @Environment(\.visionPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: LocalizedStringKey
    var body: some View {
        let spaced = Lettering.spaced && !typeSize.isAccessibilitySize
        Text(text).font(.footnote.weight(.semibold)).kerning(spaced ? 1.6 : 0)
            .textCase(spaced ? .uppercase : nil).foregroundStyle(palette.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The Moon from the iPhone's shader (`Moon.metal`): NASA's lunar map on a lit sphere with the
/// real phase, tilt, libration and earthshine. Night vision is the window's filter (or, in the
/// sky, the material's tint), so the disc itself is always drawn in natural colour.
///
/// The iPhone's two sizes of map (`MoonShading`): from 120 pt, as the night panel's Moon is, it
/// draws on `MoonAtlas`, the 4096×2048 colour map with LOLA's relief casting crater shadows along
/// the terminator (fading toward the limb and toward full Moon, in the shader). Smaller Moons, and
/// the immersive sky's disc (`atlas: false`, 256 pixels, where the relief would not show), keep
/// `MoonMap`: the atlas decodes to about 48 MB, the small map to about 2 MB.
struct VisionMoon: View {
    let geometry: MoonGeometry
    var label: String?
    /// False keeps the small map at any size (the immersive sky's 256-pixel disc).
    var atlas = true
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Rectangle().fill(.black).frame(width: side, height: side)
                .colorEffect(shader(side: side))
                .position(x: proxy.size.width/2, y: proxy.size.height/2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? VisionMoon.describe(geometry))
        .accessibilityIgnoresInvertColors()
    }
    private func shader(side: Double) -> Shader {
        let sun = MoonShading.sunDirection(geometry)
        let earthshine = 0.09*(1-cos(geometry.phaseAngle))/2
        let size = Shader.Argument.float2(CGSize(width: side, height: side))
        let lighting = Shader.Argument.float4(sun.x, sun.y, sun.z, earthshine)
        let frame = Shader.Argument.float4(cos(geometry.north), sin(geometry.north), geometry.librationLongitude, geometry.librationLatitude)
        if atlas && MoonShading.usesAtlas(side: side) {
            return ShaderLibrary.nyxMoonRelief(size, lighting, frame, .float(MoonShading.reliefStrength), .image(Image("MoonAtlas")))
        }
        return ShaderLibrary.nyxMoon(size, lighting, frame, .image(Image("MoonMap")))
    }
    static func describe(_ geometry: MoonGeometry) -> String {
        String(localized: "Moon, \(Int((geometry.illumination*100).rounded())) percent lit")
    }
}

#Preview("Eyebrow and Moon") {
    VStack(alignment: .leading, spacing: 24) {
        VisionEyebrow(text: "What's up tonight")
        VisionEyebrow(text: "What's up tonight").environment(\.visionPalette, VisionPalette(highContrast: true))
        HStack(spacing: 24) {
            ForEach([0.0, 1.6, 2.6], id: \.self) { angle in
                VisionMoon(geometry: MoonGeometry(phaseAngle: angle, brightLimb: 1.2, north: 0.3, librationLongitude: 0, librationLatitude: 0)).frame(width: 140, height: 140)
            }
        }
    }
    .padding(40).glassBackgroundEffect()
}

/// The night panel's size (190 pt) on the atlas with relief, beside a 110 pt Moon on the small map.
#Preview("Moon with relief, and a small Moon") {
    HStack(alignment: .bottom, spacing: 32) {
        ForEach([1.45, 1.75], id: \.self) { angle in
            VisionMoon(geometry: MoonGeometry(phaseAngle: angle, brightLimb: 4.5, north: 0.2, librationLongitude: 0.05, librationLatitude: -0.04)).frame(width: 190, height: 190)
        }
        VisionMoon(geometry: MoonGeometry(phaseAngle: 1.6, brightLimb: 4.5, north: 0.2, librationLongitude: 0, librationLatitude: 0)).frame(width: 110, height: 110)
    }
    .padding(40).background(.black)
}
