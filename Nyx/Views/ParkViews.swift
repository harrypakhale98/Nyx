import SwiftUI
import SwiftData
import TipKit

struct ParkRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let night: Night
    var closure: String?=nil
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            // Long names wrap beside the score; only accessibility sizes stack them.
            if typeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:14) { names; number }.frame(maxWidth:.infinity,alignment:.leading)
            } else {
                HStack(alignment:.center,spacing:16) { names.layoutPriority(1); Spacer(minLength:8); number }
            }
            if let closure { Label(closure,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(palette.accent).fixedSize(horizontal:false,vertical:true) }
        }.padding(.vertical,14)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(night.park.shortName), \(night.park.state). Darkness score \(night.score.value), \(night.score.band.label). \(night.score.hasForecast ? String(localized:"Cloud forecast included.") : String(localized:"Moon and darkness only.")) \(closure.map { String(localized:"Closure alert: \($0)") } ?? "")")
    }
    private var names: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(night.park.shortName).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            Text("\(night.park.state)\(night.park.darkSkyDesignated ? " · "+String(localized:"Dark-Sky designated") : "")").font(.caption).foregroundStyle(palette.muted)
        }
    }
    private var number: some View {
        VStack(alignment:.trailing,spacing:2) { Text("\(night.score.value)").font(.system(.largeTitle,design:.serif)).foregroundStyle(palette.accent); Text(night.score.hasForecast ? night.score.band.label : String(localized:"Estimate")).font(.caption2).foregroundStyle(palette.muted) }
    }
}
struct ParksView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Query(sort:\SavedPark.savedAt) private var saved: [SavedPark]
    @State private var search=""
    @State private var darkOnly=false
    @State private var savedOnly=false
    @AppStorage("parksByScore") private var byScore=false
    @Namespace private var zoom
    private var filtered:[Park] {
        let matching=model.parks.filter { p in (!darkOnly || p.darkSkyDesignated) && (!savedOnly || saved.contains{$0.parkID==p.id}) && (search.isEmpty || p.matches(search)) }
        return byScore ? model.ranked(matching) : matching
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Eyebrow(text:byScore ? LocalizedStringKey("Darkest tonight first") : LocalizedStringKey("63 places to look up"))
                Text("Find your dark sky").font(.system(.largeTitle,design:.serif)).foregroundStyle(palette.ink)
                Text("Scores without a cloud forecast are marked as estimates.").font(.subheadline).foregroundStyle(palette.muted)
                if DebugScenario.state=="loading" { ForEach(0..<5,id:\.self) { _ in SkeletonRow() } }
                else if filtered.isEmpty || DebugScenario.state=="empty" { CalmState(symbol:"sparkle.magnifyingglass",title:"No parks in this sky",message:"Try another name or widen your filters.") }
                else {
                    if !saved.isEmpty && !savedOnly && search.isEmpty && !darkOnly {
                        Eyebrow(text:"Saved for later")
                        ForEach(model.parks.filter{p in saved.contains{$0.parkID==p.id}}) { p in link(p) }
                        Eyebrow(text:"All national parks")
                    }
                    LazyVStack(spacing:0) { ForEach(filtered.filter { p in !( !saved.isEmpty && !savedOnly && search.isEmpty && !darkOnly && saved.contains{$0.parkID==p.id}) }) { p in link(p); Divider().overlay(palette.line) } }
                }
            }.padding(24)
        }.background(NightBackground()).navigationTitle("Parks").navigationBarTitleDisplayMode(.inline)
            .searchable(text:$search,prompt:"Park or state")
            // One request brings cloud forecasts for all 63 parks, so every score can include clouds.
            .task { await model.refresh(model.parks,parkUpdates:false) }
            .refreshable { await model.refresh(model.parks,force:true,parkUpdates:false) }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Menu {
                Picker("Sort",selection:$byScore) { Label("Name",systemImage:"textformat").tag(false); Label("Darkest tonight",systemImage:"moon.stars").tag(true) }
                Section { Toggle("Dark-Sky designated only",isOn:$darkOnly); Toggle("Saved parks only",isOn:$savedOnly) }
            } label:{ Image(systemName:"line.3.horizontal.decrease") }.accessibilityLabel("Sort and filter parks") } }
            .navigationDestination(for:Park.self) { park in ParkDetailView(park:park).navigationTransition(.zoom(sourceID:park.id,in:zoom)) }
    }
    private func link(_ park:Park)->some View {
        NavigationLink(value:park) { ParkRow(night:model.night(park),closure:model.closure(park)) }.buttonStyle(.plain).matchedTransitionSource(id:park.id,in:zoom)
    }
}
struct ParkDetailView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var saved:[SavedPark]
    let park:Park
    var initialDate:Date?=nil
    @State private var selected:Date?
    @State private var breakdown=false
    @State private var persistenceError=false
    private var night:Night { model.night(park,on:selected ?? initialDate ?? model.tonight(park)) }
    private var isSaved:Bool { saved.contains{$0.parkID==park.id} }
    /// The river covers tonight and the next 29 nights, or starts at a night chosen outside that span.
    private var riverStart:Date {
        let tonight=model.tonight(park)
        guard let initialDate else { return tonight }
        let chosen=park.evening(initialDate)
        return chosen>=tonight && chosen<park.date(tonight,addingDays:30) ? tonight : chosen
    }
    var body: some View {
        ScrollView {
            VStack(spacing:26) {
                VStack(spacing:12) {
                    Eyebrow(text:"A night beneath the stars")
                    Text(park.shortName).font(.system(.largeTitle,design:.serif)).multilineTextAlignment(.center)
                    Text(park.dayLabel(night.id)).font(.subheadline).foregroundStyle(palette.muted)
                    // The dial opens at the bottom; let the lines below tuck into that space.
                    CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast)
                        .padding(.bottom,typeSize.isAccessibilitySize ? 0 : -28)
                        .scrollTransition { [motionReduced = reduceMotion] view,phase in view.scaleEffect(motionReduced || phase.isIdentity ? 1 : 0.95).opacity(motionReduced || phase.isIdentity ? 1 : 0.8) }
                    if night.sky.state == .polarNight { Text("The Sun stays below the horizon today.").font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(.center) }
                    if night.sky.darkHours==0 { Text("No true darkness tonight at this latitude.").font(.body).foregroundStyle(palette.accent).multilineTextAlignment(.center) }
                    if !night.score.hasForecast { Text(night.id.timeIntervalSince(.now)>16*86400 ? String(localized:"Moon and darkness only — forecast not yet available.") : String(localized:"Cloud forecast unavailable. Moon and darkness only.")).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center) }
                    Button("Why this score") { breakdown=true }.font(.subheadline).buttonStyle(.bordered).popoverTip(DebugScenario.screen == nil ? ScoreTip() : nil)
                }
                Panel { TimeRiver(nights:model.nights(park,from:riverStart,count:30),selected:Binding(get:{selected ?? initialDate ?? model.tonight(park)},set:{selected=$0}),startsTonight:riverStart==model.tonight(park)) }
                Panel { VStack(alignment:.leading,spacing:8) { Label("Before you go",systemImage:"exclamationmark.shield").font(.subheadline.weight(.medium)); Text(model.alertSummary(park)).font(.subheadline).foregroundStyle(palette.muted);
                    if let data=model.enrichments[park.id],!data.alerts.isEmpty {
                        DisclosureGroup("All park alerts (\(data.alerts.count))") {
                            ForEach(data.alerts) { alert in VStack(alignment:.leading,spacing:8) { Text(alert.title).font(.headline);Text(alert.description).font(.subheadline).foregroundStyle(palette.muted) }.padding(.vertical,8) }
                        }
                    }
                     if let data=model.enrichments[park.id] { Text("Park update: \(park.timestamp(data.updated))").font(.caption).foregroundStyle(palette.muted) } } }
                Panel { SkyArc(night:night) }
                Panel {
                    VStack(alignment:.leading,spacing:18) {
                        Eyebrow(text:"Moonlight")
                        HStack(alignment:.center,spacing:24) {
                            MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:park.latitude<0).frame(width:70,height:70)
                            VStack(alignment:.leading,spacing:6) { Text(night.sky.moon.name).font(.system(.title3,design:.serif));Text("\(Int((night.sky.moon.illumination*100).rounded()))% illuminated").font(.subheadline).foregroundStyle(palette.muted) }
                        }
                        LabeledContent("Moonrise",value:park.time(night.sky.moonrise))
                        LabeledContent("Moonset",value:park.time(night.sky.moonset))
                        Text("Below the horizon for \(Int((night.sky.moonBelowFraction*100).rounded()))% of true darkness.").font(.caption).foregroundStyle(palette.muted)
                    }
                }
                Panel { VStack(alignment:.leading,spacing:16) {
                    Eyebrow(text:"What the sky may hold")
                    LabeledContent("Cloud cover",value:night.cloudCover.map{String(localized:"\(Int($0.rounded()))% average")} ?? String(localized:"Unavailable"))
                    if let updated=night.forecastUpdated { Text("Open-Meteo · updated \(park.timestamp(updated))").font(.caption).foregroundStyle(palette.muted) }
                    LabeledContent("Bortle estimate",value:String(localized:"Class \(park.bortleEstimate) of 9"))
                    Text("Lower classes mean less artificial light. Conditions vary across the park.").font(.caption).foregroundStyle(palette.muted)
                    Divider().overlay(palette.line)
                    Text(AstronomyEngine().milkyWayGuidance(for:park,on:night.id)).font(.subheadline).foregroundStyle(palette.muted)
                } }
                Panel { VStack(alignment:.leading,spacing:18) {
                    Eyebrow(text:"Places to settle in")
                    if park.viewingSpots.isEmpty { Text("Ask a ranger for a permitted viewing area with an open horizon. Nyx has no verified viewing spot for this park yet.").foregroundStyle(palette.muted) }
                    ForEach(park.viewingSpots,id:\.name) { spot in
                        VStack(alignment:.leading,spacing:6) { Text(spot.name).font(.system(.title3,design:.serif)); Text("\(spot.latitude.formatted(.number.precision(.fractionLength(3)))), \(spot.longitude.formatted(.number.precision(.fractionLength(3)))) · approximate").font(.caption).foregroundStyle(palette.muted); Text(spot.note).font(.caption).foregroundStyle(palette.muted) }
                    }
                } }
                Panel { VStack(alignment:.leading,spacing:14) {
                    Eyebrow(text:"Ranger night-sky programs")
                    if let data=model.enrichments[park.id] {
                        let programs=data.programs.filter{$0.date>=park.isoDay(model.today)}
                        if programs.isEmpty && data.programsUpdated == nil { Text("Programs could not be checked in the last update. Ask at the visitor center for current night-sky programs.").foregroundStyle(palette.muted) }
                        else if programs.isEmpty { Text("No upcoming programs in the last update. Ask at the visitor center.").foregroundStyle(palette.muted) }
                        ForEach(programs) { program in VStack(alignment:.leading,spacing:8) { Text(program.title).font(.system(.title3,design:.serif)); Text(park.programDate(program.date)).font(.caption);Text(program.description).font(.subheadline).foregroundStyle(palette.muted) } }
                    } else { Text("Programs are not checked yet. Ask at the visitor center for current night-sky programs.").foregroundStyle(palette.muted) }
                } }
                ShareCardButton(night:night)
                Text("\(park.description)").font(.subheadline).foregroundStyle(palette.muted).frame(maxWidth:.infinity,alignment:.leading)
                NavigationLink("About the data") { AboutDataView() }.font(.subheadline)
            }.padding(24)
        }.defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top).background(NightBackground(seed:park.id,score:night.score.value)).navigationTitle(park.shortName).navigationBarTitleDisplayMode(.inline)
            .toolbar { saveToolbar }
            .sheet(isPresented:$breakdown) { NavigationStack { ScoreBreakdownView(night:night) }.nyxPresentation().presentationDetents([.large]) }
            .alert("Unable to save",isPresented:$persistenceError) { Button("OK",role:.cancel) {} } message:{ Text("Your changes could not be stored. Try again when space is available.") }
            .task { await model.refresh([park]) }
            .refreshable { await model.refresh([park],force:true) }
    }
    @ToolbarContentBuilder private var saveToolbar: some ToolbarContent {
        if #available(iOS 27.0,*) {
            ToolbarItem(placement:.topBarPinnedTrailing) { saveButton }
        } else { ToolbarItem(placement:.topBarTrailing) { saveButton } }
    }
    private var saveButton:some View {
        Button { if let item=saved.first(where:{$0.parkID==park.id}) { context.delete(item) } else { context.insert(SavedPark(parkID:park.id)) }; do { try context.save() } catch { context.rollback();persistenceError=true } } label:{ Image(systemName:isSaved ? "bookmark.fill" : "bookmark") }
            .accessibilityLabel(isSaved ? "Unsave park" : "Save park")
    }
}
struct ScoreBreakdownView: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dismiss) private var dismiss
    let night:Night
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Text("A number with a reason").font(.system(.largeTitle,design:.serif))
            Text("\(night.score.value)/100 · \(night.score.band.label)").font(.system(.title,design:.serif)).foregroundStyle(palette.accent)
            row("Moonlight",points:night.score.moonPoints,of:40,detail:String(localized:"Illumination and the part of true darkness when the Moon is below the horizon."))
            if let cloud=night.score.cloudPoints { row("Cloud cover",points:cloud,of:25,detail:String(localized:"The hourly forecast averaged over the complete dark window.")) }
            row("Light pollution",points:night.score.bortlePoints,of:20,detail:String(localized:"A conservative Bortle estimate. It is not a measurement."))
            row("Length of darkness",points:night.score.lengthPoints,of:15,detail:String(localized:"Astronomical darkness, with ten hours receiving full credit."))
            if !night.score.hasForecast { Text("Clouds are unknown. The remaining components are scaled to 100. This estimate may change when a forecast arrives.").foregroundStyle(palette.muted) }
            if night.sky.darkHours==0 { Text("No true darkness tonight at this latitude. The score is capped below 40.").foregroundStyle(palette.accent) }
            else if ScoreEngine.cap(darkHours:night.sky.darkHours)<100 { Text("True darkness lasts only \(Duration.seconds(night.sky.darkHours*3600).formatted(.units(allowed:[.hours,.minutes],width:.wide))) tonight, so the score is held to \(ScoreEngine.cap(darkHours:night.sky.darkHours)) or less.").foregroundStyle(palette.accent) }
            Text("The score is a planning guide, not a guarantee of visibility or safe access.").font(.caption).foregroundStyle(palette.muted)
            ShareCardButton(night:night)
        }.padding(24) }.background(Color.black).foregroundStyle(palette.ink).navigationTitle("Score breakdown").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
    }
    /// `weight` is the component's share of 100; without clouds the others are scaled up to fill it.
    private func row(_ title:LocalizedStringKey,points:Double,of weight:Double,detail:String)->some View {
        let maximum=night.score.hasForecast ? weight : weight/0.75
        return VStack(alignment:.leading,spacing:8) {
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.firstTextBaseline) { Text(title).font(.headline);Spacer();amount(points,of:maximum) }
                VStack(alignment:.leading,spacing:4) { Text(title).font(.headline);amount(points,of:maximum) }
            }
            GeometryReader { proxy in
                ZStack(alignment:.leading) {
                    Capsule().fill(palette.line)
                    Capsule().fill(palette.accent).frame(width:proxy.size.width*min(1,max(0,points/maximum)))
                }
            }.frame(height:4).accessibilityHidden(true)
            Text(detail).font(.subheadline).foregroundStyle(palette.muted)
        }
        .accessibilityElement(children:.combine)
    }
    private func amount(_ points:Double,of maximum:Double)->some View {
        Text("\(Int(points.rounded())) of \(Int(maximum.rounded()))").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent)
    }
}
#Preview("Park row") { if let p=PlanModel().home { ParkRow(night:PlanModel().night(p)).padding().background(.black) } }
#Preview("Detail") { let m=PlanModel();if let p=m.home { NavigationStack { ParkDetailView(park:p) }.environment(m).modelContainer(for:[SavedPark.self,JournalEntry.self],inMemory:true).preferredColorScheme(.dark) } }
