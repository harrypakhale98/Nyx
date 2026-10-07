import SwiftUI

/// Pages Settings opens in Safari (or Mail, or the App Store) when the person taps them. Nyx never
/// requests them itself, so they are not network hosts of Nyx's (`Scripts/verify_release.py`
/// checks this list together with `BrowserLink`).
enum SupportLink {
    static let privacyPolicy=page(host:"harrypakhale98.github.io",path:"/Nyx/privacy.html")
    static let support=page(host:"harrypakhale98.github.io",path:"/Nyx/support.html")
    /// The attribution Open-Meteo's CC BY 4.0 licence asks for links here.
    static let openMeteo=page(host:"open-meteo.com")
    static let email:URL?={ var components=URLComponents(); components.scheme="mailto"; components.path="harry.pakhale98@gmail.com"; components.queryItems=[URLQueryItem(name:"subject",value:"Nyx")]; return components.url }()
    /// The App Store's "Write a Review" page for Nyx, once the app has an App Store ID.
    static var review:URL? { AppStoreLink.appID.flatMap { page(host:"apps.apple.com",path:"/app/id\($0)",query:[URLQueryItem(name:"action",value:"write-review")]) } }
    private static func page(host:String,path:String="",query:[URLQueryItem]?=nil)->URL? {
        var components=URLComponents(); components.scheme="https"; components.host=host; components.path=path; components.queryItems=query
        return components.url
    }
}
/// Nyx's App Store ID, the number App Store Connect assigns when the app record is created. It is
/// filled in at launch; until then the "Rate Nyx" row is not shown.
enum AppStoreLink {
    static let appID:String?=nil
}
/// Settings › Support › Credits: every source Nyx draws on, in the words each asks to be credited with.
/// About the data explains how each one is used.
struct CreditsView: View {
    @Environment(\.nyx) private var palette
    var body: some View {
        Form {
            Section { Text("Nyx is built on public science. Each source is credited here in the words it asks for.").font(.subheadline) }
                .listRowBackground(palette.panel)
            Section("Weather and air") {
                if let url=SupportLink.openMeteo {
                    Link(destination:url) { ExternalRow(title:"Weather data by Open-Meteo.com") }
                        .accessibilityHint("Opens open-meteo.com in Safari.")
                }
                credit("Cloud forecasts and the three forecast models: Open-Meteo, CC BY 4.0.")
                credit("Smoke and haze: CAMS, the Copernicus Atmosphere Monitoring Service, via Open-Meteo, CC BY 4.0.")
                credit("Usual clouds: contains modified Copernicus Climate Change Service information (2015–2024). ERA5, Hersbach et al. 2020, CC BY 4.0.")
            }.listRowBackground(palette.panel)
            Section("Sky and light") {
                credit("The Moon: NASA's Scientific Visualization Studio, CGI Moon Kit, with the LRO LROC (Hapke Normalized WAC Mosaic) and LOLA teams.")
                credit("Night lights from space: NASA Black Marble (VNP46A4, Román et al. 2018), public domain.")
                credit("Stars: the Yale Bright Star Catalogue (Hoffleit and Warren), via NASA HEASARC.")
                credit("Star names: the IAU Working Group on Star Names (WGSN).")
                credit("Lunar eclipses: NASA eclipse predictions by Fred Espenak (NASA/GSFC).")
                credit("Meteor showers: the International Meteor Organization (IMO) calendar.")
            }.listRowBackground(palette.panel)
            Section("Parks and places") {
                credit("Parks, alerts and ranger programs: the National Park Service.")
                credit("Starting places and the map of the United States: U.S. Census Bureau Gazetteer Files, population estimates and cartographic boundaries, public domain.")
            }.listRowBackground(palette.panel)
            Section {
                credit("Nyx is not affiliated with or endorsed by the National Park Service, NASA or DarkSky International.")
                NavigationLink("About the data") { AboutDataView() }
            }.listRowBackground(palette.panel)
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
            if let symbol { Image(systemName:symbol).foregroundStyle(palette.accent).frame(width:24).accessibilityHidden(true) }
            Text(title).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            Spacer(minLength:8)
            Image(systemName:"arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
        }.frame(minHeight:44).contentShape(Rectangle())
    }
}
extension View {
    /// A form over the night sky: the system's grouped background hidden, rows on Nyx's solid panel
    /// (each section sets `listRowBackground(palette.panel)`), the sky veiled so text stays calm.
    func nightForm()->some View { scrollContentBackground(.hidden).background(NightBackground(veil:0.55)) }
}
#Preview("Credits") { NavigationStack { CreditsView() }.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Credits AX5") { NavigationStack { CreditsView() }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
