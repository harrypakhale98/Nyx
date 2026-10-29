import SwiftUI

/// Where the Moon, the stars, their names and the park data come from, and who Nyx is not: the
/// iPhone's own lines (`Credits`), those something on the headset rests on, under the iPhone's
/// section names, so a licence is never shortened away here.
struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.visionPalette) private var palette
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Credits.Section.allCases, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            VisionEyebrow(verbatim: section.title)
                            ForEach(section.lines(for: .vision), id: \.self) { line in
                                Text(line).font(.body).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text(Credits.notAffiliated)
                        .font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                // The title's inset, as the privacy sheet's Form keeps.
                .padding(.horizontal, 24).padding(.vertical, 24)
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
        .modifier(NightVisionFilter(enabled: palette.nightVision, red: palette.base.red))
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
