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
            // Every device's list (`Credits`), the iPhone's lines; Open-Meteo's credit links to its site, as its licence asks.
            ForEach(Credits.Section.allCases,id:\.self) { section in
                Section(section.title) {
                    if section == .weather, let url=SupportLink.openMeteo {
                        Link(destination:url) { ExternalRow(title:"Weather data by Open-Meteo.com") }
                            .accessibilityHint("Opens open-meteo.com in Safari.")
                    }
                    ForEach(section.lines(for:.phone),id:\.self) { credit($0) }
                }.openRows(palette)
            }
            Section {
                credit(Credits.notAffiliated)
                NavigationLink("About the data") { AboutDataView() }
            }.openRows(palette)
        }
        .nightForm().navigationTitle("Credits").navigationBarTitleDisplayMode(.inline)
    }
    private func credit(_ text:String)->some View { Text(text).font(.subheadline).fixedSize(horizontal:false,vertical:true).textSelection(.enabled) }
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
