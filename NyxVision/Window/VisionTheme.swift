import SwiftUI

/// Nyx's palette on Vision Pro: starlight text, moon-amber for the score, void black behind the
/// sky. Night vision turns everything a dim signal red, in the window and in the immersive sky.
struct VisionPalette: Equatable {
    var nightVision = false
    var highContrast = false
    /// Reduce Transparency: panels behind words become nearly opaque.
    var solid = false
    /// Window colours. In night vision the window's red filter does the tinting, so ink stays
    /// white there (as on the iPhone): a red ink filtered again would turn a dim, unreadable red.
    var ink: Color { nightVision ? .white : Color(red: 0.961, green: 0.945, blue: 0.902) }
    var accent: Color { nightVision ? .white : Color(red: 1, green: 0.706, blue: 0.329) }
    /// Words in the immersive sky, which no window filter reaches: red already in night vision,
    /// the brighter red under Increase Contrast.
    var skyInk: Color { nightVision ? (highContrast ? red : Color(red: 1, green: 0.30, blue: 0.24)) : Color(red: 0.961, green: 0.945, blue: 0.902) }
    /// Night vision's red multiplier, as on the iPhone (`NyxPalette.red`, `NightTint`): the deepest
    /// red that keeps text at 6.2:1 on black, or under Increase Contrast the brighter one that
    /// keeps it above 4.5:1 for protan and deutan eyes too. The same two values, repeated here
    /// because the visionOS target does not compile the iPhone's design system.
    var red: Color { highContrast ? Color(red: 1, green: 0.36, blue: 0.31) : Color(red: 1, green: 0.27, blue: 0.23) }
    /// Secondary text. On glass it is the system's vibrant secondary style, which keeps its
    /// contrast over whatever the room shows through; night vision and Increase Contrast use a
    /// near-solid ink instead.
    var muted: AnyShapeStyle {
        highContrast || nightVision ? AnyShapeStyle(ink.opacity(highContrast ? 0.95 : 0.9)) : AnyShapeStyle(.secondary)
    }
    var line: Color { ink.opacity(highContrast ? 0.6 : 0.2) }
    /// Behind the window's content in night vision, where grey glass would read as a bright panel.
    var nightPanel: Color { Color(red: 0.07, green: 0.008, blue: 0.005) }
    /// The same red mapping as the iPhone's night-vision filter, for linear colours in the sky.
    func sky(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        guard nightVision else { return rgb }
        let luminance = 0.2126*rgb.x + 0.7152*rgb.y + 0.0722*rgb.z
        return SIMD3(luminance, 0.2*luminance, 0.16*luminance)*1.2
    }
}
private struct VisionPaletteKey: EnvironmentKey { static let defaultValue = VisionPalette() }
extension EnvironmentValues {
    var visionPalette: VisionPalette { get { self[VisionPaletteKey.self] } set { self[VisionPaletteKey.self] = newValue } }
}
enum VisionMotion {
    /// The app's one spring (the iPhone's `NyxMotion.spring`).
    static let spring = Animation.spring(response: 0.65, dampingFraction: 0.82)
}

/// Small spaced capitals over a section, as on the iPhone.
struct VisionEyebrow: View {
    @Environment(\.visionPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: LocalizedStringKey
    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).kerning(typeSize.isAccessibilitySize ? 0 : 1.6)
            .textCase(typeSize.isAccessibilitySize ? nil : .uppercase).foregroundStyle(palette.muted)
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
