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
                Text("Lower classes mean less artificial light. Conditions vary across the park.").font(.caption).foregroundStyle(palette.muted)
            }
            if let site {
                let level=SkyGlow.shared.level(site.glow)
                VStack(alignment:.leading,spacing:6) {
                    Text("Night lights from space").font(.subheadline.weight(.medium)).foregroundStyle(palette.ink)
                    GlowLine(level:level,text:SkyGlow.levelLabel(level))
                }
                .padding(.top,4)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(String(localized:"Night lights from space: \(SkyGlow.levelLabel(level)), level \(level) of 5."))
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
            return String(localized:"About as dark as this park's other spots")
        }
        return parkCentre.flatMap { SkyGlow.comparison(spot:glow,park:$0) }
    }
    /// The note a spot carries without the shared caveat, which the panel says once.
    static func lead(_ spot:ViewingSpot)->String? {
        let note=spot.localizedNote
        let caveat=String(localized:"Approximate coordinates. Check current access, opening hours and closures with a ranger. This is not a navigation guide.")
        let lead=note.hasSuffix(caveat) ? String(note.dropLast(caveat.count)).trimmingCharacters(in:.whitespaces) : note
        return lead.isEmpty ? nil : lead
    }
    /// Apple Maps, opened at the person's tap with driving directions to the spot. Nyx sends nothing;
    /// Maps takes it from there.
    static func directions(_ spot:ViewingSpot)->URL? {
        var components=URLComponents()
        components.scheme="maps"
        components.queryItems=[URLQueryItem(name:"daddr",value:"\(spot.latitude),\(spot.longitude)"),URLQueryItem(name:"dirflg",value:"d")]
        return components.url
    }
}
struct ViewingSpotRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: Park
    let spot: ViewingSpot
    @State private var copied=false
    private var access: SpotAccess? { AccessData.shared.access(park:park.id,spot:spot.name) }
    private var coordinates: String { "\(spot.latitude.formatted(.number.precision(.fractionLength(4)))), \(spot.longitude.formatted(.number.precision(.fractionLength(4))))" }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text(spot.name).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
            if let lead=SpotGlow.lead(spot) { Text(lead).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            if let site=SkyGlow.shared.spot(spot.name,park:park.id) {
                let level=SkyGlow.shared.level(site.glow)
                let others=(SkyGlow.shared.park(park.id)?.spots ?? []).filter { $0.name != spot.name }.map(\.glow)
                let words=SpotGlow.comparison(site.glow,others:others,parkCentre:SkyGlow.shared.park(park.id)?.glow) ?? String(localized:"Sky glow here")
                GlowLine(level:level,text:words,font:.footnote)
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel(String(localized:"Sky glow here: \(words). Level \(level) of 5 on the national parks' scale."))
            }
            if let access, let summary=access.summary {
                Label { Text(summary).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:access.symbol).foregroundStyle(palette.accent).accessibilityHidden(true) }
                    .font(.footnote).foregroundStyle(palette.ink)
            }
            ViewThatFits(in:.horizontal) {
                HStack(spacing:10) { actions }
                VStack(alignment:.leading,spacing:6) { actions }
            }
            if copied { Text("Copied \(coordinates)").font(.caption.monospacedDigit()).foregroundStyle(palette.muted).transition(.opacity) }
            if let access, access.summary != nil {
                DisclosureGroup { AccessSource(access:access).padding(.top,6) } label:{ Text("Access source").font(.footnote).frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }
                    .tint(palette.accent)
            }
        }
        .sensoryFeedback(.success,trigger:copied) { _,new in new }
    }
    @ViewBuilder private var actions: some View {
        Button {
            UIPasteboard.general.string="\(spot.latitude), \(spot.longitude)"
            copied=true
            Task { try? await Task.sleep(for:.seconds(3)); copied=false }
        } label:{ Label("Copy coordinates",systemImage:"doc.on.doc").font(.footnote.weight(.medium)).frame(minHeight:44) }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(palette.accent)
            .accessibilityHint(String(localized:"Copies \(coordinates), approximate."))
        if let url=SpotGlow.directions(spot) {
            Button { openURL(url) } label:{ Label("Directions in Maps",systemImage:"arrow.triangle.turn.up.right.diamond").font(.footnote.weight(.medium)).frame(minHeight:44) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(palette.accent)
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
            if let evidence=access.evidence { Text("“\(evidence)”").font(.system(.footnote,design:.serif)).italic().foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
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
        ("light.recessed","Shield outdoor lights so they shine down, never up."),
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
                HStack { Text("Read “\(Essay.darkness.title)”").fixedSize(horizontal:false,vertical:true); Spacer(); Image(systemName:"chevron.right").font(.footnote).accessibilityHidden(true) }.frame(minHeight:44).contentShape(Rectangle())
            }.font(.subheadline).foregroundStyle(palette.accent)
        }
    }
}

/// Pages Nyx opens in Safari when the person taps a `Link`. The app never requests them itself,
/// so they are not network hosts of Nyx's (`Scripts/verify_release.py` checks this list).
enum BrowserLink {
    static let globeAtNight=page(host:"globeatnight.org")
    /// The park's current conditions and alerts on nps.gov, for when Nyx's own alerts are unavailable.
    static func parkConditions(_ park:Park)->URL? { page(host:"www.nps.gov",path:"/\(park.apiCode)/planyourvisit/conditions.htm") }
    private static func page(host:String,path:String="")->URL? {
        var components=URLComponents(); components.scheme="https"; components.host=host; components.path=path
        return components.url
    }
}
/// Globe at Night: a citizen-science count of the stars people see, used to track light pollution.
/// Nyx only opens the site in Safari; nothing is prefilled and nothing is sent by the app.
struct GlobeAtNightLink: View {
    @Environment(\.nyx) private var palette
    var body: some View {
        if let url=BrowserLink.globeAtNight {
            VStack(alignment:.leading,spacing:8) {
                Link(destination:url) { Label("Share your observation with Globe at Night",systemImage:"safari").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }.font(.body.weight(.medium)).foregroundStyle(palette.accent)
                Text("A citizen-science project that maps light pollution from what people see. It opens in Safari; Nyx sends nothing, so you enter your night there yourself.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}

#Preview("Light pollution · Death Valley") { if let p=try? ParkData.load().first(where:{$0.id=="deva"}) { Panel { LightPollution(park:p) }.padding().background(.black).preferredColorScheme(.dark) } }
#Preview("Spots · Sequoia") { if let p=try? ParkData.load().first(where:{$0.id=="sequ"}) { ScrollView { Panel { ViewingSpots(park:p) }.padding() }.background(.black).preferredColorScheme(.dark) } }
#Preview("Spots · AX5") { if let p=try? ParkData.load().first(where:{$0.id=="grca"}) { ScrollView { Panel { ViewingSpots(park:p) }.padding() }.background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) } }
#Preview("Protect · Night vision") { if let p=try? ParkData.load().first(where:{$0.id=="grte"}) { NavigationStack { Panel { ProtectThisSky(park:p) }.padding() }.environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).background(.black).preferredColorScheme(.dark) } }
#Preview("Globe at Night") { GlobeAtNightLink().padding().background(.black).preferredColorScheme(.dark) }
