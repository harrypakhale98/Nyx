import SwiftUI

/// The sources Nyx on Apple Watch draws from, credited as their terms ask, in the same words as
/// About the data on the iPhone, shortened for the wrist.
struct WatchCredits: View {
    @Environment(\.nyx) private var palette
    private let lines: [LocalizedStringKey] = [
        "Weather data by Open-Meteo.com (CC BY 4.0), as averaged by Nyx.",
        "Usual clouds: contains modified Copernicus Climate Change Service information (ERA5, 2015–2024).",
        "Stars: Yale Bright Star Catalogue.",
        "Moon: NASA's Scientific Visualization Studio; LRO LROC and LOLA teams.",
        "Park data: National Park Service.",
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(lines[index]).font(.footnote)
                }
                Text("Nyx is not affiliated with or endorsed by the National Park Service, NASA or DarkSky International.")
                    .font(.caption2).foregroundStyle(palette.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .nyxTitle(String(localized: "Credits"))
    }
}

#Preview("Credits • red") {
    WatchPreviewHost(nightVision: true) { _, _ in NavigationStack { WatchCredits() } }
}
#Preview("Credits • AX5") {
    WatchPreviewHost(nightVision: false) { _, _ in NavigationStack { WatchCredits() } }.dynamicTypeSize(.accessibility5)
}
