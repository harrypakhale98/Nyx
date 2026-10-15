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
        ("Constellation figures", "Drawn for Nyx between catalog stars."),
        ("Cloud forecasts", "Weather data by Open-Meteo.com (CC BY 4.0), as averaged by Nyx."),
        ("Usual clouds", "Contains modified Copernicus Climate Change Service information (2026): ERA5, 2015 to 2024. Licensed under CC BY 4.0. Neither the European Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains."),
        ("Usual night temperatures", "Contains modified Copernicus Climate Change Service information (2026): ERA5, 2015 to 2024. Licensed under CC BY 4.0."),
        ("Smoke and haze", "Contains modified Copernicus Atmosphere Monitoring Service information (2026), via Open-Meteo. Neither the European Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains."),
        ("Park data", "National Park Service."),
        ("Aurora forecast", "The planetary K-index forecast of NOAA's Space Weather Prediction Center, U.S. Government work."),
        ("Aurora latitude", "Computed from the International Geomagnetic Reference Field (IGRF-14, IAGA; coefficients from NOAA NCEI)."),
        ("Terrain", "USGS 3D Elevation Program (public domain); produced using Copernicus WorldDEM-30 and WorldDEM-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30 and WorldDEM-90."),
        ("Deep sky", "Wikidata (CC0), the SIMBAD database (CDS, Strasbourg) and the Harris globular cluster catalogue."),
        ("Moon names", "IAU Gazetteer of Planetary Nomenclature, USGS (public domain)."),
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
                    Text("Nyx is not affiliated with or endorsed by the National Park Service, NASA or DarkSky International.")
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
        .colorMultiply(palette.nightVision ? palette.red : .white)
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
