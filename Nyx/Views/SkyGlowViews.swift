import SwiftUI

/// Five short bars, lit up to a glow level (1 darkest … 5 brightest). The words beside it carry
/// the meaning, so the bars are hidden from VoiceOver and never the only signal.
struct GlowMeter: View {
    @Environment(\.nyx) private var palette
    @ScaledMetric(relativeTo:.caption) private var bar=12.0
    let level: Int
    var body: some View {
        HStack(spacing:3) {
            ForEach(1...5,id:\.self) { step in
                Capsule().fill(step<=level ? palette.accent : palette.line).frame(width:min(bar,22),height:max(3,min(bar,22)/3))
            }
        }.accessibilityHidden(true)
    }
}

/// The meter beside its words; at accessibility sizes the words take the full width below it.
private struct GlowLine: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    let level: Int
    let text: String
    var font: Font = .subheadline
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment:.leading,spacing:8) { GlowMeter(level:level); words }
        } else {
            HStack(alignment:.firstTextBaseline,spacing:10) { GlowMeter(level:level).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center]+4 }; words }
        }
    }
    private var words: some View { Text(text).font(font).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
}
/// Light pollution on park detail: the Bortle estimate the score uses, then what NASA's night lights
/// add as context (where the park sits among parks, and which way its light domes lie).
struct LightPollution: View {
    @Environment(\.nyx) private var palette
    let park: Park
    private var site: SkyGlow.Site? { SkyGlow.shared.park(park.id) }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            VStack(alignment:.leading,spacing:6) {
                LabeledContent("Bortle estimate",value:String(localized:"Class \(park.bortleEstimate) of 9"))
                    .accessibilityElement(children:.ignore).speechLabel(String(localized:"Bortle estimate, class \(park.bortleEstimate) of 9"))
                // A saved spot's class is the satellite grid's (or an assumed suburban sky), and says which;
                // a world catalogue place's is the grid's at its one point.
                if park.isSavedSpot { Text(park.sourceNote).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                else if !park.curated { Text("Estimated from satellite data, not measured here. Conditions vary across the area.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                else { Text("Lower classes mean less artificial light. Conditions vary across the park.").font(.caption).foregroundStyle(palette.muted) }
            }
            if park.curated, !park.isSavedSpot { MeasuredSkyRows(park:park).padding(.top,4) }
            if let site {
                let level=SkyGlow.shared.level(site.glow)
                VStack(alignment:.leading,spacing:6) {
                    Text("Night lights from space").font(.subheadline.weight(.medium)).foregroundStyle(palette.ink)
                    GlowLine(level:level,text:SkyGlow.levelLabel(level))
                }
                .padding(.top,4)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(String(localized:"Night lights from space: \(SkyGlow.levelLabel(level)), level \(level) of 5.")).accessibilityAddTraits(.isStaticText)
                let lines=SkyGlow.domeLines(site.domes)
                if !lines.isEmpty {
                    VStack(alignment:.leading,spacing:4) {
                        ForEach(lines,id:\.self) { line in Text(line).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
                        if level==1 { Text("Very little artificial light reaches this park; these glows are faint.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                    }
                    .accessibilityElement(children:.combine)
                }
                Text("From NASA satellite night lights: a comparison between parks, not a measurement of sky brightness. The score uses the estimate.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}

/// What the Park Service measured on the ground: up to three sites, darkest latest reading first,
/// each with its year and the observers' Bortle class when they gave one, then what the number means
/// and how old it is. Nothing for a park the Park Service has not measured.
struct MeasuredSkyRows: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: Park
    var body: some View {
        let sites=MeasuredSky.shared.sites(park.id)
        if !sites.isEmpty, let years=MeasuredSky.shared.years(park.id) {
            VStack(alignment:.leading,spacing:8) {
                Text("Measured by the Park Service").font(.subheadline.weight(.medium)).foregroundStyle(palette.ink).accessibilityAddTraits(.isHeader)
                ForEach(sites.prefix(3),id:\.name) { site in
                    if let night=site.latest { row(site.name,night) }
                }
                let which=sites.count>3 ? String(localized:"The three darkest of \(sites.count) sites measured, \(MeasuredSky.span(years)).") : String(localized:"Measured \(MeasuredSky.span(years)).")
                Text(Sentences.join([which,String(localized:"Sky brightness overhead, in magnitudes per square arcsecond: higher is darker, and the darkest natural skies read about 22. Sky glow may have grown since; the score uses the estimate.")]))
                    .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    /// Name and year beside the reading; at accessibility sizes the reading moves under the name,
    /// so a long name keeps the width.
    private func row(_ name:String,_ night:MeasuredSky.Night)->some View {
        let year=night.year.map { MeasuredSky.span($0...$0) } ?? ""
        let detail=night.bortle.map { String(localized:"\(year) · observers judged Bortle \($0)") } ?? year
        let reading=Text(MeasuredSky.reading(night.sqm)).font(.subheadline.monospacedDigit()).foregroundStyle(palette.ink)
        let label=VStack(alignment:.leading,spacing:2) {
            Text(name).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            if typeSize.isAccessibilitySize { reading }
            Text(detail).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
        return Group {
            if typeSize.isAccessibilitySize { label.frame(maxWidth:.infinity,alignment:.leading) }
            else { LabeledContent { reading } label: { label } }
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(night.bortle.map { String(localized:"\(name): \(MeasuredSky.reading(night.sqm)) magnitudes per square arcsecond in \(year); observers judged Bortle \($0).") }
                            ?? String(localized:"\(name): \(MeasuredSky.reading(night.sqm)) magnitudes per square arcsecond in \(year)."))
    }
}

/// The viewing spots: each with its name, its sky glow beside the park's other spots, step-free
/// access from nps.gov, and two plain actions (copy the coordinates, or hand them to Maps for
/// directions). The one caveat about approximate coordinates stands once, at the foot.
struct ViewingSpots: View {
    @Environment(\.nyx) private var palette
    let park: Park
    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            Eyebrow(text:"Places to settle in")
            if park.viewingSpots.isEmpty { Text("Ask a ranger for a permitted viewing area with an open horizon. Nyx has no verified viewing spot for this park yet.").foregroundStyle(palette.muted) }
            ForEach(park.viewingSpots,id:\.name) { spot in
                ViewingSpotRow(park:park,spot:spot)
                if spot != park.viewingSpots.last { Divider().overlay(palette.line) }
            }
            if !park.viewingSpots.isEmpty {
                Text("Coordinates are approximate, from nps.gov. This is not a navigation guide: check current access, hours and closures with the park.")
                    .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}
/// How a spot's sky glow compares with the park's other spots, or with the park's centre where it
/// has none: only when the difference is worth saying. Never a ranking against all parks.
nonisolated enum SpotGlow {
    static func comparison(_ glow:Double,others:[Double],parkCentre:Double?)->String? {
        let others=others.filter { $0>0 }
        if !others.isEmpty {
            let mean=others.reduce(0,+)/Double(others.count)
            if glow>mean*1.25 { return others.count==1 ? String(localized:"Brighter than this park's other spot") : String(localized:"Brighter than this park's other spots") }
            if glow<mean/1.25 { return others.count==1 ? String(localized:"Darker than this park's other spot") : String(localized:"Darker than this park's other spots") }
            return nil
        }
        return parkCentre.flatMap { SkyGlow.comparison(spot:glow,park:$0) }
    }
    /// True for a note in the Park Service's English, not one of Nyx's own catalog sentences.
    static func fromParkService(_ lead:String)->Bool {
        lead != String(localized:"The North Unit keeps Central Time, one hour ahead of the times Nyx shows for this park.")
    }
    /// The note a spot carries without the shared caveat, which the panel says once.
    static func lead(_ spot:ViewingSpot)->String? {
        let note=spot.localizedNote
        let caveat=String(localized:"Approximate coordinates. Check current access, opening hours and closures with a ranger. This is not a navigation guide.")
        let lead=note.hasSuffix(caveat) ? String(note.dropLast(caveat.count)).trimmingCharacters(in:.whitespaces) : note
        return lead.isEmpty ? nil : lead
    }
}
struct ViewingSpotRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: Park
    let spot: ViewingSpot
    private var access: SpotAccess? { AccessData.shared.access(park:park.id,spot:spot.name) }
    private var coordinates: String { "\(spot.latitude.formatted(.number.precision(.fractionLength(4)))), \(spot.longitude.formatted(.number.precision(.fractionLength(4))))" }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text(spot.name).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
            if let lead=SpotGlow.lead(spot) {
                Text(lead).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                // The notes come from nps.gov in English (the one note Nyx writes itself is in the catalog).
                if SpotGlow.fromParkService(lead) { TranslateButton(text:lead) }
            }
            if let site=SkyGlow.shared.spot(spot.name,park:park.id) {
                let level=SkyGlow.shared.level(site.glow)
                let others=(SkyGlow.shared.park(park.id)?.spots ?? []).filter { $0.name != spot.name }.map(\.glow)
                let words=SpotGlow.comparison(site.glow,others:others,parkCentre:SkyGlow.shared.park(park.id)?.glow) ?? String(localized:"Sky glow here")
                GlowLine(level:level,text:words,font:.footnote)
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel(String(localized:"Sky glow here: \(words). Level \(level) of 5 on the national parks' scale.")).accessibilityAddTraits(.isStaticText)
            }
            if let measured=MeasuredSky.shared.site(near:spot.latitude,spot.longitude,park:park.id), let night=measured.latest, let year=night.year {
                Label { Text("Park Service measured \(MeasuredSky.reading(night.sqm)) here in \(MeasuredSky.span(year...year))").fixedSize(horizontal:false,vertical:true) }
                    icon:{ Image(systemName:"camera.aperture").foregroundStyle(palette.accent).accessibilityHidden(true) }
                    .font(.footnote).foregroundStyle(palette.ink)
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel(String(localized:"Park Service measured the sky here in \(MeasuredSky.span(year...year)): \(MeasuredSky.reading(night.sqm)) magnitudes per square arcsecond, higher is darker."))
            }
            if let access, let summary=access.summary {
                Label { Text(summary).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:access.symbol).foregroundStyle(palette.accent).accessibilityHidden(true) }
                    .font(.footnote).foregroundStyle(palette.ink)
            }
            CoordinateActions(latitude:spot.latitude,longitude:spot.longitude,shown:coordinates,copyHint:String(localized:"Copies \(coordinates), approximate."),spacing:10)
            if let access, access.summary != nil {
                DisclosureGroup { AccessSource(access:access).padding(.top,6) } label:{ Text("Access source").font(.footnote).frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }
                    .tint(palette.accent)
            }
        }
    }
}
/// A place's two plain actions: copy its coordinates, or hand them to Maps for directions (side by
/// side, or stacked when they do not fit), with "Copied …" beneath for three seconds after the last
/// copy. A park's viewing spots and your own spot's panel share it.
struct CoordinateActions: View {
    @Environment(\.nyx) private var palette
    @Environment(\.openURL) private var openURL
    let latitude: Double
    let longitude: Double
    /// The coordinates as "Copied …" shows them.
    let shown: String
    let copyHint: String
    /// The spacing of the page's own column, between the actions and "Copied …".
    var spacing=10.0
    /// Each copy restarts the three seconds, so a second tap is never cut short by the first one's timer.
    @State private var copies=0
    @State private var copied=false
    var body: some View {
        VStack(alignment:.leading,spacing:spacing) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:10) { actions }
                VStack(alignment:.leading,spacing:6) { actions }
            }
            if copied { Text("Copied \(shown)").font(.caption.monospacedDigit()).foregroundStyle(palette.muted).transition(.opacity) }
        }
        // A copy is a light tick: the success thump is the journal's alone.
        .sensoryFeedback(.selection,trigger:copies)
        .task(id:copies) {
            guard copies>0 else { return }
            try? await Task.sleep(for:.seconds(3))
            guard !Task.isCancelled else { return }
            copied=false
        }
    }
    @ViewBuilder private var actions: some View {
        Button {
            PrivatePasteboard.copy("\(latitude), \(longitude)")
            copied=true; copies+=1
        } label:{ Label("Copy coordinates",systemImage:"doc.on.doc").font(.footnote.weight(.medium)).frame(minHeight:44) }
            .buttonStyle(.borderless).foregroundStyle(palette.accent)
            .accessibilityHint(copyHint)
        if let url=MapsHandOff.directions(latitude:latitude,longitude:longitude) {
            Button { openURL(url) } label:{ Label("Directions in Maps",systemImage:"arrow.triangle.turn.up.right.diamond").font(.footnote.weight(.medium)).frame(minHeight:44) }
                .buttonStyle(.borderless).foregroundStyle(palette.accent)
                .accessibilityHint("Opens Apple Maps with driving directions. Nyx sends nothing.")
        }
    }
}
/// The official sentence an access flag rests on, with a link to the nps.gov page (opened in Safari, never fetched by Nyx).
private struct AccessSource: View {
    @Environment(\.nyx) private var palette
    let access: SpotAccess
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            if let evidence=access.evidence { Text("\"\(evidence)\"").font(.system(.footnote,design:.serif)).italic().foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
            if let note=access.note { Text(note).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            if let url=access.source { Link(destination:url) { Label("Open the park's page in Safari",systemImage:"safari").font(.footnote).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }.foregroundStyle(palette.accent) }
            Text("National Park Service, retrieved October 5, 2026. Conditions change; check with the park.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
    }
}

/// What a park's dark sky is up against, and what anyone can do about it. Calm, practical, short.
struct ProtectThisSky: View {
    @Environment(\.nyx) private var palette
    let park: Park
    private let habits:[(symbol:String,text:LocalizedStringKey)]=[
        // An outline lamp shining down: the filled recessed light read as a solid blob at this size.
        ("lamp.ceiling","Shield outdoor lights so they shine down, never up."),
        ("lightbulb.min","Choose warm bulbs, 3000 K or lower."),
        ("sensor","Use motion sensors, and switch lights off when no one needs them."),
    ]
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Eyebrow(text:"Protect this sky")
            if park.darkSkyDesignated {
                Label { Text("An International Dark Sky Park, certified by DarkSky International.").fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:"checkmark.seal").foregroundStyle(palette.accent).accessibilityHidden(true) }
                    .font(.system(.body,design:.serif))
            }
            if let rank=SkyGlow.shared.trendRank(park.id) {
                VStack(alignment:.leading,spacing:6) {
                    Text(SkyGlow.trendSentence(rank)).font(.system(.body,design:.serif)).fixedSize(horizontal:false,vertical:true)
                    Text("NASA satellite night lights within \(Measurement(value:150,unit:UnitLength.kilometers).formatted(.measurement(width:.wide,usage:.road))), compared across parks. The sensor misses much of the blue light of white LEDs, and older and newer data were processed differently, so Nyx shows only the comparison.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }.accessibilityElement(children:.combine)
            }
            VStack(alignment:.leading,spacing:10) {
                Text("At home, anyone can help").font(.subheadline.weight(.medium))
                ForEach(habits,id:\.symbol) { habit in
                    Label { Text(habit.text).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:habit.symbol).foregroundStyle(palette.accent).accessibilityHidden(true) }
                        .font(.subheadline).foregroundStyle(palette.ink)
                }
            }
            NavigationLink { EssayView(essay:.darkness) } label:{
                HStack { Text("Read \"\(Essay.darkness.title)\"").fixedSize(horizontal:false,vertical:true); Spacer(); Image(systemName:"chevron.forward").font(.footnote).accessibilityHidden(true) }.frame(minHeight:44).contentShape(Rectangle())
            }.font(.subheadline).foregroundStyle(palette.accent)
        }
    }
}

/// Pages Nyx opens in Safari when the person taps a `Link`. The app never requests them itself,
/// so they are not network hosts of Nyx's.
enum BrowserLink {
    static let globeAtNight=page(host:"globeatnight.org")
    /// The credit Open-Meteo's licence asks for, and the licence itself (About the data).
    static let openMeteo=page(host:"open-meteo.com")
    static let creativeCommonsBY=page(host:"creativecommons.org",path:"/licenses/by/4.0/")
    /// The park's current conditions and alerts on nps.gov, for when Nyx's own alerts are unavailable.
    static func parkConditions(_ park:Park)->URL? { park.nps.flatMap { page(host:"www.nps.gov",path:"/\($0)/planyourvisit/conditions.htm") } }
    /// An https page; every page Nyx links to is built here (Settings' and Where to stay's too).
    static func page(host:String,path:String="",query:[URLQueryItem]?=nil)->URL? {
        var components=URLComponents(); components.scheme="https"; components.host=host; components.path=path; components.queryItems=query
        return components.url
    }
}
/// The credit Open-Meteo's licence asks for beside its forecast ("Weather data by Open-Meteo.com",
/// linked), with when the forecast was issued. Opens open-meteo.com in Safari; Nyx requests nothing.
struct OpenMeteoCredit: View {
    @Environment(\.nyx) private var palette
    /// The forecast's issue time, park-local and already formatted.
    let updated: String
    var body: some View {
        let issued=String(localized:"Updated \(updated)")
        if let url=BrowserLink.openMeteo {
            Link(destination:url) {
                VStack(alignment:.leading,spacing:2) {
                    HStack(alignment:.firstTextBaseline,spacing:4) {
                        Text("Weather data by Open-Meteo.com").foregroundStyle(palette.accent).fixedSize(horizontal:false,vertical:true)
                        Image(systemName:"arrow.up.right").imageScale(.small).foregroundStyle(palette.accent).accessibilityHidden(true)
                    }
                    Text(issued).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
                .font(.caption).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
            }
            .accessibilityElement(children:.combine)
            .accessibilityHint("Opens open-meteo.com in Safari.")
        } else {
            Text(issued).font(.caption).foregroundStyle(palette.muted)
        }
    }
}
/// Globe at Night: citizen-science observations of the stars people see, used to track light pollution.
/// Nyx only opens the site in Safari; nothing is prefilled and nothing is sent by the app.
struct GlobeAtNightLink: View {
    @Environment(\.nyx) private var palette
    var body: some View {
        if let url=BrowserLink.globeAtNight {
            VStack(alignment:.leading,spacing:8) {
                Link(destination:url) { Label("Share your observation with Globe at Night",systemImage:"safari").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }.font(.body.weight(.medium)).foregroundStyle(palette.accent)
                Text("A citizen-science project. Observations like yours let scientists estimate that the night sky grew brighter by 7 to 10 percent a year from 2011 to 2022. It opens in Safari; Nyx sends nothing.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}

#Preview("Light pollution · Death Valley") { if let p=try? ParkData.load().first(where:{$0.id=="deva"}) { Panel { LightPollution(park:p) }.padding().background(.black).preferredColorScheme(.dark) } }
#Preview("Spots · Sequoia") { if let p=try? ParkData.load().first(where:{$0.id=="sequ"}) { ScrollView { Panel { ViewingSpots(park:p) }.padding() }.background(.black).preferredColorScheme(.dark) } }
#Preview("Spots · AX5") { if let p=try? ParkData.load().first(where:{$0.id=="grca"}) { ScrollView { Panel { ViewingSpots(park:p) }.padding() }.background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) } }
#Preview("Protect · Night vision") { if let p=try? ParkData.load().first(where:{$0.id=="grte"}) { NavigationStack { Panel { ProtectThisSky(park:p) }.padding() }.environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).background(.black).preferredColorScheme(.dark) } }
#Preview("Globe at Night") { GlobeAtNightLink().padding().background(.black).preferredColorScheme(.dark) }
#Preview("Measured skies · Death Valley (many sites)") { if let p=try? ParkData.load().first(where:{$0.id=="deva"}) { Panel { MeasuredSkyRows(park:p) }.padding().background(.black).preferredColorScheme(.dark) } }
#Preview("Measured skies · Wind Cave (two sites, no Bortle)") { if let p=try? ParkData.load().first(where:{$0.id=="wica"}) { Panel { MeasuredSkyRows(park:p) }.padding().background(.black).preferredColorScheme(.dark) } }
#Preview("Measured skies · Congaree (none)") { if let p=try? ParkData.load().first(where:{$0.id=="cong"}) { Panel { LightPollution(park:p) }.padding().background(.black).preferredColorScheme(.dark) } }
#Preview("Measured skies · AX5") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { ScrollView { Panel { MeasuredSkyRows(park:p) }.padding() }.background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) } }
#Preview("Measured skies · night vision") { if let p=try? ParkData.load().first(where:{$0.id=="glac"}) { Panel { MeasuredSkyRows(park:p) }.padding().background(.black).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark) } }
#Preview("Viewing spot · measured here") { if let p=try? ParkData.load().first(where:{$0.id=="glac"}), let s=p.viewingSpots.first { Panel { ViewingSpotRow(park:p,spot:s) }.padding().background(.black).preferredColorScheme(.dark) } }
