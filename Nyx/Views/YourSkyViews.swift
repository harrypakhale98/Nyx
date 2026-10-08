import SwiftUI

extension ConstellationLayout {
    /// The layout as a sky map: your stars, and one figure per season, oldest first.
    func content(parks: [Park]) -> SkyMapContent {
        let names=Dictionary(parks.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
        let stars=stars.map { star in
            let park=names[star.night.parkID]
            let date=park?.dateLabel(star.night.date) ?? star.night.date.formatted(date:.long,time:.omitted)
            return SkyMapContent.Star(id:star.id.uuidString,point:star.point,brightness:star.brightness,
                                      label:String(localized:"\(park?.shortName ?? ""), \(date). Observed Bortle \(star.night.observedBortle)."))
        }
        return SkyMapContent(stars:stars,figures:seasons.map { season in lines.filter { $0.season==season }.map { ($0.from,$0.to) } })
    }
    var summary: String {
        guard !stars.isEmpty else { return String(localized:"Your constellation. A map of the 63 national parks drawn as faint stars. Your first night will be your first star.") }
        let parks=Set(stars.map(\.night.parkID)).count
        return String(localized:"Your constellation: \(stars.count) nights at \(parks) parks across \(seasons.count) seasons, each a star at its park on a map of the United States.")
    }
}
/// The journal's header: your constellation, and the skies you have seen.
struct YourSkyPanel: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    let nights: [LoggedNight]
    let open: (UUID)->Void
    var body: some View {
        let layout=ConstellationLayout(nights:nights,parks:model.parks)
        Panel { VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.center) {
                Eyebrow(text:"Your constellation")
                Spacer(minLength:8)
                if !nights.isEmpty { ConstellationShareButton(layout:layout,year:Calendar.current.component(.year,from:.now)) }
            }
            SkyMapView(content:layout.content(parks:model.parks),summary:layout.summary) { id in
                if let night=nights.first(where:{ $0.id.uuidString==id }) { open(night.id) }
            }
            if nights.isEmpty {
                Text("Your first night will be your first star").font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true)
                Text("Each night you record shines at its park on this map of the sky. Nights in the same season join into a figure of their own. Every entry stays on this iPhone.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            } else {
                Text("Brighter stars mark darker skies. Each season's nights join into a figure. Tap a star to open its night.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                Divider().overlay(palette.line)
                SkiesSeenSection(seen:SkiesSeen(nights:nights,parks:model.parks))
            }
        } }
    }
}
/// "7 of 63 national park skies", and where you saw your darkest sky in each. A count, not a game.
struct SkiesSeenSection: View {
    @Environment(\.nyx) private var palette
    let seen: SkiesSeen
    @State private var expanded=DebugScenario.state=="skies"
    var body: some View {
        DisclosureGroup(isExpanded:$expanded) {
            VStack(alignment:.leading,spacing:12) {
                ForEach(seen.parks) { place in
                    ViewThatFits(in:.horizontal) {
                        HStack(alignment:.firstTextBaseline) { Text(place.name).font(.subheadline); Spacer(minLength:8); detail(place) }
                        VStack(alignment:.leading,spacing:2) { Text(place.name).font(.subheadline); detail(place) }
                    }
                    .accessibilityElement(children:.combine)
                }
                Text("Bortle as you observed it: the darkest of your nights there.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }.padding(.top,10)
        } label:{
            Label { Text(seen.line).font(.system(.body,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:"sparkles").foregroundStyle(palette.accent).accessibilityHidden(true) }
                .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
        }.tint(palette.muted)
    }
    private func detail(_ place:SkiesSeen.Place)->some View {
        Text(place.nights==1 ? String(localized:"Bortle \(place.darkestBortle) · one night") : String(localized:"Bortle \(place.darkestBortle) · \(place.nights) nights"))
            .font(.caption.monospacedDigit()).foregroundStyle(palette.muted)
    }
}
/// The constellation as fixed-size artwork for sharing: "My sky, 2026".
struct ConstellationCard: View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    let layout: ConstellationLayout
    let title: String
    var body: some View {
        let parks=Set(layout.stars.map(\.night.parkID)).count
        ZStack {
            Color.black
            Starfield(seed:"my-sky",twinkle:0)
            VStack(alignment:.leading,spacing:18) {
                Text("NYX").font(.caption).tracking(7).foregroundStyle(palette.muted)
                Text(title).font(.system(size:40,weight:.light,design:.serif)).foregroundStyle(palette.ink)
                SkyMapCanvas(content:layout.content(parks:model.parks),parks:model.parks).frame(width:500,height:300)
                Text(String(localized:"\(layout.stars.count) nights under the stars at \(parks) national parks"))
                    .font(.system(.title3,design:.serif)).foregroundStyle(palette.ink)
                Text("Each star is a night at its park. Brighter stars, darker skies.").font(.caption).foregroundStyle(palette.muted)
            }.padding(40)
        }.frame(width:580,height:560)
            .environment(\.colorScheme,.dark).dynamicTypeSize(.large)
            .accessibilityElement(children:.ignore).accessibilityLabel(layout.summary)
    }
}
struct ConstellationShareButton: View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let layout: ConstellationLayout
    let year: Int
    @State private var image: Image?
    private var title: String {
        let years=Set(layout.stars.map { Calendar.current.component(.year,from:$0.night.date) })
        guard let low=years.min(), let high=years.max(), low != high else { return String(localized:"My sky, \(String(years.first ?? year))") }
        return String(localized:"My sky, \(String(low))–\(String(high))")
    }
    var body: some View {
        Group {
            if let image { ShareLink(item:image,preview:SharePreview(title,image:image)) { Label("Share",systemImage:"square.and.arrow.up").labelStyle(.iconOnly).frame(minWidth:44,minHeight:44) }.accessibilityLabel("Share your constellation") }
            else { ProgressView().frame(minWidth:44,minHeight:44).accessibilityLabel("Preparing your constellation to share") }
        }
        .task(id:"\(layout.stars.count)-\(palette.nightVision)") {
            let card=ConstellationCard(layout:layout,title:title).environment(\.nyx,palette).environment(model)
            let renderer=ImageRenderer(content:card.modifier(NightVisionFilter(enabled:palette.nightVision)))
            renderer.scale=max(2,displayScale)
            image=renderer.uiImage.map { Image(uiImage:$0) }
        }
    }
}

// MARK: Year under the stars

struct YearRecapView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    let nights: [LoggedNight]
    @State private var year: Int
    @State private var reflection: String?
    @State private var reflecting=false
    /// The year, as large as the page allows, growing with Dynamic Type up to a point.
    @ScaledMetric(relativeTo:.largeTitle) private var yearSize=84.0
    init(nights: [LoggedNight], year: Int? = nil) {
        self.nights=nights
        let years=nights.map { Calendar.current.component(.year,from:$0.date) }
        _year=State(initialValue:year ?? years.max() ?? Calendar.current.component(.year,from:.now))
    }
    private var years: [Int] { Array(Set(nights.map { Calendar.current.component(.year,from:$0.date) })).sorted(by:>) }
    var body: some View {
        let recap=YearRecap(year:year,nights:nights,parks:model.parks)
        let yearNights=nights.filter { Calendar.current.component(.year,from:$0.date)==year }
        let layout=ConstellationLayout(nights:yearNights,parks:model.parks)
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Eyebrow(text:"Year under the stars")
            HStack(alignment:.firstTextBaseline) {
                Text(String(year)).font(.system(size:min(yearSize,120),weight:.light,design:.serif)).foregroundStyle(palette.accent).kerning(2)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer(minLength:8)
                if years.count>1 {
                    Menu { Picker("Year",selection:$year) { ForEach(years,id:\.self) { Text(String($0)).tag($0) } } } label:{ Label("Year",systemImage:"calendar").frame(minHeight:44) }
                        .accessibilityLabel("Choose a year").accessibilityValue(String(year))
                }
            }
            stats(recap)
            if let darkest=recap.darkest, let park=model.park(darkest.parkID) {
                Panel { HStack(alignment:.center,spacing:18) {
                    MoonView(geometry:AstronomyEngine().moon(for:model.night(park,on:darkest.date)).geometry).frame(width:56,height:56)
                    VStack(alignment:.leading,spacing:4) {
                        Eyebrow(text:"Your darkest sky")
                        Text(darkest.parkName).font(.system(.title2,design:.serif)).fixedSize(horizontal:false,vertical:true)
                        Text("\(darkest.dateLabel) · Bortle \(darkest.bortle), as you saw it").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                    }
                }.accessibilityElement(children:.combine) }
            }
            Panel { VStack(alignment:.leading,spacing:14) {
                Text("The Moon's phases you met").font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true)
                MoonPhaseRow(met:recap.phases)
                Text(String(localized:"\(recap.phases.count) of 8 · the phases you met are lit")).font(.subheadline).foregroundStyle(palette.muted)
            } }
            if let event=recap.event {
                Label { Text(event).fixedSize(horizontal:false,vertical:true) } icon:{ SkyGlyph(.meteors,color:palette.accent).frame(width:16,height:16) }.font(.subheadline)
            }
            if !layout.stars.isEmpty { Panel { VStack(alignment:.leading,spacing:12) { Eyebrow(text:"This year's constellation"); SkyMapView(content:layout.content(parks:model.parks),summary:layout.summary) } } }
            VStack(alignment:.leading,spacing:10) {
                Eyebrow(text:"In a few words")
                if reflecting { ConstellationLoader().frame(maxWidth:.infinity) }
                else {
                    Text(reflection ?? recap.template).font(.system(.body,design:.serif)).lineSpacing(6).fixedSize(horizontal:false,vertical:true)
                    Text(reflection == nil ? String(localized:"From your journal, on this iPhone.") : String(localized:"Written on this iPhone from your journal. The figures above are the facts.")).font(.caption).foregroundStyle(palette.muted)
                }
            }
            if recap.nights>0 { RecapShareButton(recap:recap,layout:layout) }
        }.padding(24).readableColumn() }
        .defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top)
        .background(NightBackground()).navigationTitle("Year under the stars").navigationBarTitleDisplayMode(.inline)
        .task(id:year) {
            let yearNights=nights.filter { Calendar.current.component(.year,from:$0.date)==year }
            reflection=nil
            guard recap.nights>0, OnDeviceGuide.available, DebugScenario.screen == nil else { return }
            reflecting=true
            reflection=await OnDeviceGuide.yearReflection(facts:recap.facts,notes:yearNights.map(\.notes).filter { !$0.isEmpty })
            reflecting=false
        }
    }
    @ViewBuilder private func stats(_ recap:YearRecap)->some View {
        let tiles=[(recap.nights,String(localized:"Nights out")),(recap.parkNames.count,String(localized:"Parks")),(recap.newParkNames.count,String(localized:"New to you"))]
        ViewThatFits(in:.horizontal) {
            HStack(spacing:12) { ForEach(tiles,id:\.1) { tile($0.0,$0.1) } }
            VStack(spacing:12) { ForEach(tiles,id:\.1) { tile($0.0,$0.1) } }
        }
    }
    private func tile(_ value:Int,_ label:String)->some View {
        VStack(spacing:4) {
            Text("\(value)").font(.system(.largeTitle,design:.serif,weight:.light)).foregroundStyle(palette.ink).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity).padding(.vertical,16).background(RoundedRectangle(cornerRadius:18).fill(palette.panel)).overlay(RoundedRectangle(cornerRadius:18).stroke(palette.line,lineWidth:0.5))
            .accessibilityElement(children:.combine)
    }
}
/// The eight phases in a row: lit where you were out under that phase, a faint outline where not.
struct MoonPhaseRow: View {
    @Environment(\.nyx) private var palette
    let met: Set<Int>
    var body: some View {
        HStack(spacing:0) {
            ForEach(0..<8,id:\.self) { index in
                let fraction=YearRecap.phaseFraction(index), moon=MoonPhase(fraction:fraction)
                VStack(spacing:6) {
                    ZStack {
                        Circle().stroke(palette.line,lineWidth:0.6)
                        MoonDisc(illumination:moon.illumination,waxing:moon.waxing).opacity(met.contains(index) ? 1 : 0.18)
                    }.frame(maxWidth:30,maxHeight:30)
                    // A new moon met is as dark as one missed; the amber mark says which you saw.
                    Circle().fill(palette.accent).frame(width:4,height:4).opacity(met.contains(index) ? 1 : 0)
                }.frame(maxWidth:.infinity)
            }
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(String(localized:"Phases met: \((0..<8).filter(met.contains).map { MoonPhase(fraction:YearRecap.phaseFraction($0)).name }.joined(separator:", "))"))
        .accessibilityIgnoresInvertColors()
    }
}
struct RecapCard: View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    let recap: YearRecap
    let layout: ConstellationLayout
    var body: some View {
        ZStack {
            Color.black
            Starfield(seed:"recap-\(recap.year)",twinkle:0)
            VStack(alignment:.leading,spacing:16) {
                Text("Nyx · Year under the stars").textCase(.uppercase).font(.caption).tracking(4).foregroundStyle(palette.muted)
                Text(String(recap.year)).font(.system(size:80,weight:.light,design:.serif)).foregroundStyle(palette.accent)
                HStack(spacing:28) {
                    figure(recap.nights,String(localized:"nights out"))
                    figure(recap.parkNames.count,String(localized:"parks"))
                    figure(recap.phases.count,String(localized:"Moon phases"))
                }
                SkyMapCanvas(content:layout.content(parks:model.parks),parks:model.parks).frame(width:500,height:300)
                if let darkest=recap.darkest { Text("Darkest sky: \(darkest.parkName), Bortle \(darkest.bortle)").font(.system(.title3,design:.serif)).foregroundStyle(palette.ink) }
            }.padding(40)
        }.frame(width:580,height:720)
            .environment(\.colorScheme,.dark).dynamicTypeSize(.large)
            .accessibilityElement(children:.ignore).accessibilityLabel(recap.template)
    }
    private func figure(_ value:Int,_ label:String)->some View {
        VStack(alignment:.leading,spacing:2) { Text("\(value)").font(.system(size:34,weight:.light,design:.serif)).foregroundStyle(palette.ink); Text(label).font(.caption).foregroundStyle(palette.muted) }
    }
}
struct RecapShareButton: View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let recap: YearRecap
    let layout: ConstellationLayout
    @State private var image: Image?
    var body: some View {
        Group {
            if let image { ShareLink(item:image,preview:SharePreview(String(localized:"My year under the stars, \(String(recap.year))"),image:image)) { Label("Share your year",systemImage:"square.and.arrow.up") } }
            else { ProgressView().accessibilityLabel("Preparing your year to share") }
        }.buttonStyle(.bordered)
        .task(id:"\(recap.year)-\(recap.nights)-\(palette.nightVision)") {
            let card=RecapCard(recap:recap,layout:layout).environment(\.nyx,palette).environment(model)
            let renderer=ImageRenderer(content:card.modifier(NightVisionFilter(enabled:palette.nightVision)))
            renderer.scale=max(2,displayScale)
            image=renderer.uiImage.map { Image(uiImage:$0) }
        }
    }
}

#if DEBUG
/// Illustrative nights for the `constellation` and `recap` scenarios: a lived-in year across the West.
enum DebugJournal {
    static func nights(now: Date = .now) -> [LoggedNight] {
        let year=Calendar.current.component(.year,from:now)
        func at(_ month:Int,_ day:Int,_ yearOffset:Int=0)->Date { Calendar.current.date(from:DateComponents(year:year+yearOffset,month:month,day:day,hour:22)) ?? now }
        let rows:[(Date,String,Int,Int)]=[ // date, park, observed Bortle, score
            (at(11,14,-1),"jotr",3,72),(at(1,24),"deva",2,81),(at(2,18),"jotr",3,77),(at(2,20),"deva",2,88),
            (at(5,16),"brca",2,84),(at(5,18),"grba",1,90),(at(7,22),"grba",1,94),(at(7,24),"arch",2,86),(at(8,12),"grba",1,92),
            (at(8,15),"cany",2,89),(at(9,19),"grca",2,80),(at(9,20),"brca",2,85),
        ]
        return rows.enumerated().map { i,row in LoggedNight(id:UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",i)) ?? UUID(),date:row.0,parkID:row.1,observedBortle:row.2,score:row.3,notes:i==6 ? String(localized:"The Milky Way cast a faint shadow on the trail.") : "") }
    }
}
#endif
