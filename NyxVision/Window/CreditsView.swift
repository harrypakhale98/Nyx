import SwiftUI

/// Where the Moon, the stars, their names and the park data come from, and who Nyx is not.
/// The same sources as the iPhone's About the data, shortened; the Vision Pro app is reviewed
/// and shipped as its own build, so it carries its own credits.
struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.visionPalette) private var palette
    static let lines: [(title: LocalizedStringKey, text: LocalizedStringKey)] = [
        ("Moon map", "NASA's Scientific Visualization Studio; LRO LROC and LOLA teams."),
        ("Stars", "Yale Bright Star Catalogue (HEASARC)."),
        ("Star names", "IAU Working Group on Star Names."),
        ("Constellation figures", "Drawn for Nyx between catalogue stars."),
        ("Usual clouds", "Contains modified Copernicus Climate Change Service information (ERA5, 2015–2024)."),
        ("Park data", "National Park Service."),
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(Self.lines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 4) {
                            VisionEyebrow(text: line.title)
                            Text(line.text).font(.body).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("Nyx is not affiliated with or endorsed by NPS, NASA or DarkSky International.")
                        .font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 40).padding(.vertical, 24)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(Text("Credits"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        // A sheet is its own presentation: it takes night vision's red here, as the window does.
        .saturation(palette.nightVision ? 0 : 1)
        .colorMultiply(palette.nightVision ? Color(red: 1, green: 0.27, blue: 0.23) : .white)
        .background { if palette.nightVision { palette.nightPanel } }
    }
}

#Preview("Credits") {
    CreditsView()
}

#Preview("Credits, accessibility size") {
    CreditsView().dynamicTypeSize(.accessibility3)
}

#Preview("Credits, night vision") {
    CreditsView().environment(\.visionPalette, VisionPalette(nightVision: true))
}
