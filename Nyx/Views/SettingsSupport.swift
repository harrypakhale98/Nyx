import SwiftUI

/// Pages Settings opens in Safari (or Mail, or the App Store) when the person taps them. Nyx never
/// requests them itself, so they are not network hosts of Nyx's.
enum SupportLink {
    static let privacyPolicy=BrowserLink.page(host:"get-nyx.com",path:"/privacy")
    static let support=BrowserLink.page(host:"get-nyx.com",path:"/support")
    /// The attribution Open-Meteo's CC BY 4.0 licence asks for links here (one constant, shared with About the data).
    static let openMeteo=BrowserLink.openMeteo
    static let email:URL?={ var components=URLComponents(); components.scheme="mailto"; components.path="harry.pakhale98@gmail.com"; components.queryItems=[URLQueryItem(name:"subject",value:"Nyx")]; return components.url }()
    /// The App Store's "Write a Review" page for Nyx, once the app has an App Store ID.
    /// The product page, shared beside a card (the recipient opens it in the App Store; Nyx requests nothing).
    static var storePage:URL? { AppStoreLink.appID.flatMap { BrowserLink.page(host:"apps.apple.com",path:"/app/id\($0)") } }
    static var review:URL? { AppStoreLink.appID.flatMap { BrowserLink.page(host:"apps.apple.com",path:"/app/id\($0)",query:[URLQueryItem(name:"action",value:"write-review")]) } }
}
/// Nyx's App Store ID (live since October 7, 2026): the "Rate Nyx" row and share cards link to it.
enum AppStoreLink {
    static let appID:String?="6818817800"
}
/// Settings › Support › Credits: every source Nyx draws on, in the words each asks to be credited with.
/// About the data explains how each one is used.
struct CreditsView: View {
    @Environment(\.nyx) private var palette
    var body: some View {
        Form {
            Section { Text("Nyx is built on public science. Each source is credited here in the words it asks for.").font(.subheadline) }
                .openRows(palette)
            Section("Weather and air") {
                if let url=SupportLink.openMeteo {
                    Link(destination:url) { ExternalRow(title:"Weather data by Open-Meteo.com") }
                        .accessibilityHint("Opens open-meteo.com in Safari.")
                }
                credit("Cloud forecasts and the three forecast models: Open-Meteo, CC BY 4.0.")
                credit("Smoke and haze: contains modified Copernicus Atmosphere Monitoring Service information (2026), via Open-Meteo.")
                credit("Usual clouds: contains modified Copernicus Climate Change Service information (2026): ERA5, 2015 to 2024, Hersbach et al. 2020, CC BY 4.0.")
                credit("Usual night temperatures: contains modified Copernicus Climate Change Service information (2026): ERA5, 2015 to 2024, CC BY 4.0.")
            }.openRows(palette)
            Section("Sky and light") {
                credit("The Moon: NASA's Scientific Visualization Studio, CGI Moon Kit, with the LRO LROC (Hapke Normalized WAC Mosaic) and LOLA teams.")
                credit("Night lights from space: NASA Black Marble (VNP46A4, Román et al. 2018), public domain.")
                credit("Stars: the Yale Bright Star Catalogue (Hoffleit and Warren), via NASA HEASARC.")
                credit("Star names: the IAU Working Group on Star Names (WGSN).")
                credit("Lunar eclipses: NASA eclipse predictions by Fred Espenak (NASA/GSFC).")
                credit("Meteor showers: the International Meteor Organization (IMO) calendar.")
                credit("Aurora latitude: computed from the International Geomagnetic Reference Field (IGRF-14, IAGA; coefficients from NOAA NCEI, U.S. Government work).")
                credit("Aurora forecast: the planetary K-index forecast of NOAA's Space Weather Prediction Center, U.S. Government work.")
                credit("Deep-sky positions and magnitudes: Wikidata (CC0), the SIMBAD database (CDS, Strasbourg) and the Harris globular cluster catalogue.")
                credit("Moon names and positions: the IAU Gazetteer of Planetary Nomenclature, USGS (public domain).")
            }.openRows(palette)
            Section("Parks and places") {
                credit("Parks, alerts and ranger programs: the National Park Service.")
                credit("Measured night skies: the National Park Service Night Skies Program, public domain.")
                credit("Night and seasonal access: National Park Service, nps.gov, public domain.")
                credit("Busy and quiet months: National Park Service Visitor Use Statistics, 2021 to 2025 monthly averages, CC0.")
                credit("Starting points in the United States and its outline: U.S. Census Bureau Gazetteer Files, population estimates and cartographic boundaries, public domain.")
                credit("Starting points outside the United States: GeoNames (geonames.org), CC BY 4.0.")
                credit("World parks and dark-sky places: Wikidata, CC0.")
                credit("World map: Natural Earth, public domain.")
                credit("Terrain horizons: USGS 3D Elevation Program (public domain); produced using Copernicus WorldDEM-30 and WorldDEM-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30 and WorldDEM-90.")
            }.openRows(palette)
            Section {
                credit("Nyx is not affiliated with or endorsed by the National Park Service, NASA or DarkSky International.")
                NavigationLink("About the data") { AboutDataView() }
            }.openRows(palette)
        }
        .nightForm().navigationTitle("Credits").navigationBarTitleDisplayMode(.inline)
    }
    private func credit(_ text:LocalizedStringKey)->some View { Text(text).font(.subheadline).fixedSize(horizontal:false,vertical:true).textSelection(.enabled) }
}
/// A row that leaves Nyx: its title, and a small arrow that says so.
struct ExternalRow: View {
    @Environment(\.nyx) private var palette
    let title:LocalizedStringKey
    var symbol:String?=nil
    var body: some View {
        HStack(spacing:12) {
            if let symbol { Image(systemName:symbol).foregroundStyle(palette.ink).frame(width:24).accessibilityHidden(true) }
            Text(title).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            Spacer(minLength:8)
            Image(systemName:"arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
        }.frame(minHeight:44).contentShape(Rectangle())
    }
}
extension View {
    /// A form over the night sky: the system's grouped background hidden, rows on Nyx's solid panel
    /// (each section sets `listRowBackground(palette.panel)`), the sky veiled so text stays calm.
    func nightForm()->some View { scrollContentBackground(.hidden).background(NightBackground(veil:0.65)) }
    /// Rows open to the night: clear where the indigo card was, a starlight hairline between them.
    func openRows(_ palette:NyxPalette)->some View { listRowBackground(Color.clear).listRowSeparatorTint(palette.line) }
}
#Preview("Credits") { NavigationStack { CreditsView() }.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Credits AX5") { NavigationStack { CreditsView() }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
