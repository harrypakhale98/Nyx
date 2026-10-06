import SwiftUI

/// Words in the sky: the compass on the horizon, a whisper under the galactic core, a name card
/// for a tapped body, and the plaque at your feet that says what this is and is not.
struct SkyLabel: View {
    enum Style { case compass, whisper, card, plaque }
    let title: String
    let detail: String?
    let style: Style
    let palette: VisionPalette
    var body: some View {
        switch style {
        case .compass:
            Text(title).font(.system(size: 30, weight: .light, design: .serif)).foregroundStyle(palette.skyInk.opacity(palette.highContrast ? 0.95 : 0.7))
        case .whisper:
            Text(title).font(.system(size: 13, weight: .regular, design: .serif)).italic().kerning(1.2)
                .foregroundStyle(palette.skyInk.opacity(palette.highContrast ? 0.9 : 0.55))
        case .card:
            VStack(spacing: 2) {
                Text(title).font(.system(size: 17, weight: .regular, design: .serif))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(palette.skyInk.opacity(palette.highContrast ? 0.95 : 0.72)) }
            }
            .foregroundStyle(palette.skyInk).padding(.horizontal, 14).padding(.vertical, 8)
            .background(palette.nightVision ? AnyShapeStyle(palette.nightPanel) : AnyShapeStyle(.black.opacity(0.35)), in: .capsule)
        case .plaque:
            VStack(spacing: 6) {
                Text(title).font(.system(size: 22, weight: .light, design: .serif)).foregroundStyle(palette.skyInk)
                if let detail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(palette.skyInk.opacity(palette.highContrast ? 0.95 : 0.72)).multilineTextAlignment(.center).frame(width: 260)
                }
            }
            .padding(16)
        }
    }
}
