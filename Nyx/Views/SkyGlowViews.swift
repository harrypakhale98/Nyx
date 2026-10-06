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

/// The viewing spots, each with its sky glow beside the park's and its step-free access from nps.gov.
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
        }
    }
}
struct ViewingSpotRow: View {
    @Environment(\.nyx) private var palette
    let park: Park
    let spot: ViewingSpot
    private var access: SpotAccess? { AccessData.shared.access(park:park.id,spot:spot.name) }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(spot.name).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true)
            Text("\(spot.latitude.formatted(.number.precision(.fractionLength(3)))), \(spot.longitude.formatted(.number.precision(.fractionLength(3)))) · approximate").font(.caption.monospacedDigit()).foregroundStyle(palette.muted).textSelection(.enabled)
                // A 44-point target for the long-press "Copy coordinates" menu (iOS 26 audits the text's own height).
                .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
                .contextMenu { Button("Copy coordinates",systemImage:"doc.on.doc") { UIPasteboard.general.string="\(spot.latitude), \(spot.longitude)" } }
            Text(spot.localizedNote).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if let site=SkyGlow.shared.spot(spot.name,park:park.id) {
                let level=SkyGlow.shared.level(site.glow)
                let comparison=SkyGlow.shared.park(park.id).flatMap { SkyGlow.comparison(spot:site.glow,park:$0.glow) }
                VStack(alignment:.leading,spacing:4) {
                    Text("Sky glow here").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                    GlowLine(level:level,text:[SkyGlow.levelLabel(level),comparison].compactMap { $0 }.joined(separator:" · "),font:.footnote)
                }
                .padding(.top,2)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(String(localized:"Sky glow here: \([SkyGlow.levelLabel(level),comparison].compactMap { $0 }.joined(separator:". ")), level \(level) of 5."))
            }
            if let access, let summary=access.summary {
                Label { Text(summary).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:access.symbol).foregroundStyle(palette.accent).accessibilityHidden(true) }
                    .font(.footnote).foregroundStyle(palette.ink)
                DisclosureGroup { AccessSource(access:access).padding(.top,6) } label:{ Text("Access source").font(.footnote) }
                    .tint(palette.accent)
            }
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
            if let url=access.source { Link(destination:url) { Label("Open the park's page in Safari",systemImage:"safari").font(.footnote) }.foregroundStyle(palette.accent) }
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
    private static func page(host:String)->URL? {
        var components=URLComponents(); components.scheme="https"; components.host=host
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
                Link(destination:url) { Label("Share your observation with Globe at Night",systemImage:"safari") }.font(.body.weight(.medium)).foregroundStyle(palette.accent)
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
