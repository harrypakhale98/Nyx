import SwiftUI

/// Nyx's palette on Vision Pro: starlight text, moon-amber for the score, void black behind the
/// sky. Night vision turns everything a dim signal red, in the window and in the immersive sky.
struct VisionPalette: Equatable {
    var nightVision = false
    var highContrast = false
    /// Window colours. In night vision the window's red filter does the tinting, so ink stays
    /// white there (as on the iPhone): a red ink filtered again would turn a dim, unreadable red.
    var ink: Color { nightVision ? .white : Color(red: 0.961, green: 0.945, blue: 0.902) }
    var accent: Color { nightVision ? .white : Color(red: 1, green: 0.706, blue: 0.329) }
    /// Words in the immersive sky, which no window filter reaches: red already in night vision.
    var skyInk: Color { nightVision ? Color(red: 1, green: 0.30, blue: 0.24) : Color(red: 0.961, green: 0.945, blue: 0.902) }
    var muted: Color { ink.opacity(highContrast ? 0.95 : nightVision ? 0.9 : 0.72) }
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
        Text(text).font(.caption.weight(.semibold)).kerning(typeSize.isAccessibilitySize ? 0 : 2.4)
            .textCase(typeSize.isAccessibilitySize ? nil : .uppercase).foregroundStyle(palette.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The Moon from the iPhone's shader (`Moon.metal`): NASA's lunar map on a lit sphere with the
/// real phase, tilt, libration and earthshine. Night vision is the window's filter (or, in the
/// sky, the material's tint), so the disc itself is always drawn in natural colour.
struct VisionMoon: View {
    let geometry: MoonGeometry
    var label: String?
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
        let i = geometry.phaseAngle, a = geometry.brightLimb
        let earthshine = 0.09*(1-cos(i))/2
        return ShaderLibrary.nyxMoon(.float2(CGSize(width: side, height: side)), .float4(sin(i) * -sin(a), sin(i)*cos(a), cos(i), earthshine),
            .float4(cos(geometry.north), sin(geometry.north), geometry.librationLongitude, geometry.librationLatitude), .image(Image("MoonMap")))
    }
    static func describe(_ geometry: MoonGeometry) -> String {
        String(localized: "Moon, \(Int((geometry.illumination*100).rounded())) percent illuminated")
    }
}
