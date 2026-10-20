import SwiftUI

/// The sources Nyx on Apple Watch draws from, credited as their terms ask, in the same words as
/// About the data on the iPhone, shortened for the wrist.
struct WatchCredits: View {
    @Environment(\.nyx) private var palette
    /// Every source something on the wrist rests on: the score, What's up and the terrain under the core.
    private let lines: [LocalizedStringKey] = [
        "Weather data by Open-Meteo.com (CC BY 4.0), as averaged by Nyx.",
        "Smoke and haze: contains modified Copernicus Atmosphere Monitoring Service information (2026), via Open-Meteo.",
        "Usual clouds: contains modified Copernicus Climate Change Service information (2026): ERA5, 2015 to 2024.",
        "Stars: Yale Bright Star Catalogue.",
        "Moon: NASA's Scientific Visualization Studio; LRO LROC and LOLA teams.",
        "Night lights from space: NASA Black Marble (VNP46A4, Román et al. 2018), public domain.",
        "Deep-sky positions and magnitudes: Wikidata (CC0), the SIMBAD database (CDS, Strasbourg) and the Harris globular cluster catalogue.",
        "Meteor showers: the International Meteor Organization (IMO) calendar.",
        "Lunar eclipses: NASA eclipse predictions by Fred Espenak (NASA/GSFC).",
        "Aurora forecast: the planetary K-index forecast of NOAA's Space Weather Prediction Center, U.S. Government work.",
        "Aurora latitude: computed from the International Geomagnetic Reference Field (IGRF-14, IAGA; coefficients from NOAA NCEI, U.S. Government work).",
        "Park data: National Park Service.",
        "Terrain horizons: USGS 3D Elevation Program (public domain); produced using Copernicus WorldDEM-30 and WorldDEM-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30 and WorldDEM-90.",
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
