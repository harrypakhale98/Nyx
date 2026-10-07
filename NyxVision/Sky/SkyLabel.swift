import SwiftUI
import UIKit

/// Words in the sky: the compass on the horizon, a whisper under the galactic core, a name card
/// for a tapped body, and the plaque at your feet that says what this is and is not.
///
/// Labels are rendered into textures (`ImageRenderer`), which never sees the person's text size,
/// so `typeSize` is passed in and every size is scaled the way the system scales its text styles.
/// Weights are medium and up, as visionOS asks: thin strokes shimmer over a moving, dark sky.
struct SkyLabel: View {
    enum Style { case compass, whisper, card, plaque }
    let title: String
    let detail: String?
    let style: Style
    let palette: VisionPalette
    var typeSize: DynamicTypeSize = .large
    var body: some View {
        switch style {
        case .compass:
            Text(title).font(font(32, .title1, weight: .semibold)).foregroundStyle(palette.skyInk.opacity(palette.highContrast ? 1 : 0.78))
        case .whisper:
            Text(title).font(font(18, .body, weight: .medium)).italic().kerning(1)
                .foregroundStyle(palette.skyInk.opacity(palette.highContrast ? 1 : 0.82))
                .padding(.horizontal, 12).padding(.vertical, 6)
        case .card:
            VStack(spacing: 3) {
                Text(title).font(font(22, .title2, weight: .semibold))
                if let detail { Text(detail).font(font(16, .callout, weight: .medium, serif: false)).foregroundStyle(palette.skyInk.opacity(palette.highContrast ? 1 : 0.88)) }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(palette.skyInk).padding(.horizontal, 18).padding(.vertical, 10)
            .background(palette.nightVision ? AnyShapeStyle(palette.nightPanel) : AnyShapeStyle(.black.opacity(palette.solid || palette.highContrast ? 0.88 : 0.55)), in: .capsule)
        case .plaque:
            VStack(spacing: 8) {
                Text(title).font(font(28, .title1, weight: .medium)).foregroundStyle(palette.skyInk)
                if let detail {
                    Text(detail).font(font(17, .body, weight: .medium, serif: false)).foregroundStyle(palette.skyInk.opacity(palette.highContrast ? 1 : 0.88))
                        .multilineTextAlignment(.center).frame(width: 380*scale(.body)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
    }
    private func font(_ size: CGFloat, _ style: UIFont.TextStyle, weight: Font.Weight, serif: Bool = true) -> Font {
        .system(size: size*scale(style), weight: palette.highContrast ? weight.bolder : weight, design: serif ? .serif : .default)
    }
    /// How the system would scale a text style at the person's size, against its size at Large.
    private func scale(_ style: UIFont.TextStyle) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: style)
        let base = metrics.scaledValue(for: 100, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        let scaled = metrics.scaledValue(for: 100, compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize)))
        return base > 0 ? scaled/base : 1
    }
}

private extension Font.Weight {
    /// One step heavier, for Increase Contrast.
    var bolder: Font.Weight { self == .medium ? .semibold : self == .semibold ? .bold : self }
}

#Preview("Sky labels") {
    let palette = VisionPalette()
    VStack(spacing: 30) {
        HStack(spacing: 40) {
            SkyLabel(title: "N", detail: nil, style: .compass, palette: palette)
            SkyLabel(title: "E", detail: nil, style: .compass, palette: VisionPalette(highContrast: true))
        }
        SkyLabel(title: "Milky Way core", detail: nil, style: .whisper, palette: palette)
        SkyLabel(title: "Jupiter", detail: "41° up in the southeast · very bright", style: .card, palette: palette)
        SkyLabel(title: "Moon", detail: "12° up in the west · 23% lit", style: .card, palette: VisionPalette(solid: true))
        SkyLabel(title: "Joshua Tree", detail: "Computed for Joshua Tree, Fri, Jul 17. Not a live view; clouds not shown, and the skyline is illustrative. Ahead is south, not your room's real north.", style: .plaque, palette: palette)
    }
    .padding(40).background(.black)
}

#Preview("Sky labels, night vision") {
    let palette = VisionPalette(nightVision: true)
    VStack(spacing: 30) {
        SkyLabel(title: "S", detail: nil, style: .compass, palette: palette)
        SkyLabel(title: "Milky Way core", detail: nil, style: .whisper, palette: palette)
        SkyLabel(title: "Saturn", detail: "28° up in the south · bright", style: .card, palette: palette)
    }
    .padding(40).background(.black)
}

#Preview("Sky labels, accessibility size") {
    let palette = VisionPalette()
    VStack(spacing: 30) {
        SkyLabel(title: "W", detail: nil, style: .compass, palette: palette, typeSize: .accessibility3)
        SkyLabel(title: "Mars", detail: "9° up in the east · bright", style: .card, palette: palette, typeSize: .accessibility3)
        SkyLabel(title: "Denali", detail: "Computed for Denali, Sun, Jun 21. Not a live view; clouds not shown, and the skyline is illustrative.", style: .plaque, palette: palette, typeSize: .accessibility3)
    }
    .padding(40).background(.black)
}
