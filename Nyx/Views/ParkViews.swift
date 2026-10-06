import SwiftUI
import SwiftData
import TipKit

struct ParkRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let night: Night
    var closure: String?=nil
    /// Tonight and the six nights after it, for the week strip.
    var week: [Night]=[]
    /// Said in the row while the Parks list is narrowed to step-free viewing, so the match is visible.
    var stepFree=false
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
            .accessibilityLabel("\(night.park.shortName), \(night.park.state). \(stepFree ? String(localized:"Step-free viewing.") : "") Darkness score \(night.score.value), \(night.score.band.label). \(night.score.hasForecast ? String(localized:"Cloud forecast included.") : String(localized:"Moon and darkness only.")) \(WeekStrip.summary(week) ?? "") \(closure.map { String(localized:"Closure alert: \($0)") } ?? "")")
    }
    private var names: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(night.park.shortName).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            Text("\(night.park.state)\(night.park.darkSkyDesignated ? " · "+String(localized:"Dark-Sky designated") : "")").font(.caption).foregroundStyle(palette.muted)
            if stepFree { Label("Step-free viewing",systemImage:"figure.roll").font(.caption).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
            if week.count>1 { WeekStrip(nights:week).padding(.top,4) }
        }
    }
    private var number: some View {
        VStack(alignment:.trailing,spacing:2) { Text("\(night.score.value)").font(.system(.largeTitle,design:.serif)).foregroundStyle(palette.accent); Text(night.score.hasForecast ? night.score.band.label : String(localized:"Estimate")).font(.caption2).foregroundStyle(palette.muted) }
    }
}
/// The Parks list's narrowing switches, kept apart from the view so they can be tested.
nonisolated struct ParkFilter {
    var darkOnly=false
    var stepFreeOnly=false
    func includes(_ park:Park,access:AccessData = .shared)->Bool {
        (!darkOnly || park.darkSkyDesignated) && (!stepFreeOnly || access.hasStepFreeViewing(park.id))
    }
}
struct ParksView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Query(sort:\SavedPark.savedAt) private var saved: [SavedPark]
    @State private var search=""
    @State private var darkOnly=false
    @State private var stepFreeOnly=DebugScenario.state=="step-free"
    @State private var savedOnly=false
    @AppStorage("parksByScore") private var byScore=false
    @Namespace private var zoom
    private var filtered:[Park] {
        let filter=ParkFilter(darkOnly:darkOnly,stepFreeOnly:stepFreeOnly)
        let matching=model.parks.filter { p in filter.includes(p) && (!savedOnly || saved.contains{$0.parkID==p.id}) && (search.isEmpty || p.matches(search)) }
        return byScore ? model.ranked(matching) : matching
    }
    /// Saved parks lead the list only when nothing narrows it.
    private var narrowed:Bool { darkOnly || stepFreeOnly || savedOnly }
    private var showsSavedSection:Bool { !saved.isEmpty && !savedOnly && search.isEmpty && !darkOnly && !stepFreeOnly }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Eyebrow(text:byScore ? LocalizedStringKey("Darkest tonight first") : narrowed ? LocalizedStringKey("\(filtered.count) of 63 parks") : LocalizedStringKey("63 places to look up"))
                Text("Find your dark sky").font(.system(.largeTitle,design:.serif)).foregroundStyle(palette.ink)
                // Only worth saying when a row actually reads "Estimate".
                if filtered.contains(where:{ !model.night($0).score.hasForecast }) { Text("Scores without a cloud forecast are marked as estimates.").font(.subheadline).foregroundStyle(palette.muted) }
                if stepFreeOnly { Text("Parks with at least one viewing spot that nps.gov describes as step-free or partly step-free. Check with the park before you go.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                if DebugScenario.state=="loading" { ForEach(0..<5,id:\.self) { _ in SkeletonRow() } }
                else if filtered.isEmpty || DebugScenario.state=="empty" { CalmState(symbol:"sparkle.magnifyingglass",title:"No parks in this sky",message:"Try another name or widen your filters.") }
                else {
                    if showsSavedSection {
                        Eyebrow(text:"Saved for later")
                        ForEach(model.parks.filter{p in saved.contains{$0.parkID==p.id}}) { p in link(p) }
                        Eyebrow(text:"All national parks")
                    }
                    LazyVStack(spacing:0) { ForEach(filtered.filter { p in !(showsSavedSection && saved.contains{$0.parkID==p.id}) }) { p in link(p); Divider().overlay(palette.line) } }
                }
            }.padding(24)
        }.background(NightBackground()).navigationTitle("Parks").navigationBarTitleDisplayMode(.inline)
            .searchable(text:$search,prompt:"Park or state")
            // One request brings cloud forecasts for all 63 parks, so every score can include clouds.
            .task { await model.refresh(model.parks,parkUpdates:false) }
            .refreshable { await model.refresh(model.parks,force:true,parkUpdates:false) }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Menu {
                Picker("Sort",selection:$byScore) { Label("Name",systemImage:"textformat").tag(false); Label("Darkest tonight",systemImage:"moon.stars").tag(true) }
                Section { Toggle("Dark-Sky designated only",isOn:$darkOnly); Toggle("Step-free viewing",isOn:$stepFreeOnly); Toggle("Saved parks only",isOn:$savedOnly) }
            } label:{ Image(systemName:"line.3.horizontal.decrease") }.accessibilityLabel("Sort and filter parks") } }
            .navigationDestination(for:Park.self) { park in ParkDetailView(park:park).navigationTransition(.zoom(sourceID:park.id,in:zoom)) }
    }
    private func link(_ park:Park)->some View {
        NavigationLink(value:park) { ParkRow(night:model.night(park),closure:model.closure(park),week:model.nights(park,from:model.tonight(park),count:7),stepFree:stepFreeOnly) }.buttonStyle(.plain).matchedTransitionSource(id:park.id,in:zoom)
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
    @State private var scrubbing=false
    private var night:Night { model.night(park,on:selected ?? initialDate ?? model.tonight(park)) }
    private var isSaved:Bool { saved.contains{$0.parkID==park.id} }
    private var outlook:NightOutlook? { model.outlook(night) }
    /// Agreement and the cloud layer, under the cloud figure.
    private var cloudContext:[String] {
        guard let outlook else { return [] }
        return [outlook.agreement?.sentence(tonight:night.id==model.tonight(park)),outlook.layers?.note].compactMap { $0 }
    }
    /// What to bring, one short line each: the coldest hour, dew on optics, and wind. Lines with
    /// no data are left out; with none, the section is not shown.
    private var nightItself:[(symbol:String,text:String)] {
        guard let outlook else { return [] }
        let cold=outlook.coldest.map { cold in
            outlook.coldestAt.map { String(localized:"Down to \(NightOutlook.temperature(cold)) around \(park.time($0))") } ?? String(localized:"Down to \(NightOutlook.temperature(cold))")
        }
        let lines:[(String,String?)]=[("thermometer.low",cold),("drop",outlook.dewLikely ? String(localized:"Dew likely on lenses") : nil),("wind",outlook.gustText)]
        return lines.compactMap { symbol,text in text.map { (symbol,$0) } }
    }
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
                        .modifier(DepthParallax(depth:0.1))
                    if night.sky.state == .polarNight { Text("The Sun stays below the horizon today.").font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(.center) }
                    if night.sky.darkHours==0 { Text(SkyConditions.noDarknessMessage(tonight:night.id==model.tonight(park))).font(.body).foregroundStyle(palette.accent).multilineTextAlignment(.center) }
                    if !night.score.hasForecast { Text(model.beyondForecast(night) ? String(localized:"Moon and darkness only — forecast not yet available.") : String(localized:"Cloud forecast unavailable. Moon and darkness only.")).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center) }
                    if let smoke=model.smokeCaveat(night) { Label(smoke,systemImage:"smoke").font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true).padding(.horizontal,12) }
                    ScoreReadout(score:night.score,agreement:outlook?.agreement) { breakdown=true }.padding(.top,typeSize.isAccessibilitySize ? 8 : 18)
                        .popoverTip(DebugScenario.screen == nil && !palette.nightVision ? ScoreTip() : nil)
                    if night.id==model.tonight(park) { FieldEntry(park:park,night:night).padding(.top,typeSize.isAccessibilitySize ? 4 : 10) }
                }
                Panel { let river=model.nights(park,from:riverStart,count:30); TimeRiver(nights:river,selected:Binding(get:{selected ?? initialDate ?? model.tonight(park)},set:{selected=$0}),startsTonight:riverStart==model.tonight(park),outlooks:model.outlooks(river),markers:model.markers(river)) }
                Panel { VStack(alignment:.leading,spacing:8) { Label("Before you go",systemImage:"exclamationmark.shield").font(.subheadline.weight(.medium)); Text(model.alertSummary(park)).font(.subheadline).foregroundStyle(palette.muted);
                    if let data=model.enrichments[park.id],!data.alerts.isEmpty {
                        DisclosureGroup("All park alerts (\(data.alerts.count))") {
                            ForEach(data.alerts) { alert in VStack(alignment:.leading,spacing:8) { Text(alert.title).font(.headline);Text(alert.description).font(.subheadline).foregroundStyle(palette.muted) }.padding(.vertical,8) }
                        }
                    }
                     if let data=model.enrichments[park.id] { Text("Park update: \(park.timestamp(data.updated))").font(.caption).foregroundStyle(palette.muted) } } }
                Panel { SkyArc(night:night,isTonight:night.id==model.tonight(park),core:model.whatsUp(night).core) }
                Panel {
                    VStack(alignment:.leading,spacing:18) {
                        WhatsUpPanel(whatsUp:model.whatsUp(night),isTonight:night.id==model.tonight(park))
                        // Tonight's wake-ups (AlarmKit), beside the moments they are for.
                        if FieldAlarms.supported, night.id==model.tonight(park) {
                            let options=FieldNight.alarmOptions(park:park,sky:night.sky,at:DebugScenario.date ?? .now)
                            if !options.isEmpty { Divider().overlay(palette.line); FieldAlarmRows(park:park,options:options,showsHeading:true) }
                        }
                    }
                }
                Panel {
                    VStack(alignment:.leading,spacing:18) {
                        Eyebrow(text:"Moonlight")
                        HStack(alignment:.center,spacing:24) {
                            let moon=AstronomyEngine().moon(for:night)
                            MoonView(geometry:moon.geometry,moment:String(localized:"at \(park.time(moon.moment))")).frame(width:70,height:70)
                            VStack(alignment:.leading,spacing:6) { Text(night.sky.moon.name).font(.system(.title3,design:.serif));Text("\(Int((night.sky.moon.illumination*100).rounded()))% illuminated").font(.subheadline).foregroundStyle(palette.muted) }
                        }
                        LabeledContent("Moonrise",value:park.time(night.sky.moonrise))
                        LabeledContent("Moonset",value:park.time(night.sky.moonset))
                        Text("Below the horizon for \(Int((night.sky.moonBelowFraction*100).rounded()))% of true darkness.").font(.caption).foregroundStyle(palette.muted)
                    }
                }
                Panel { VStack(alignment:.leading,spacing:16) {
                    Eyebrow(text:"What the sky may hold")
                    VStack(alignment:.leading,spacing:6) {
                        LabeledContent("Cloud cover",value:night.cloudCover.map{String(localized:"\(Int($0.rounded()))% average")} ?? String(localized:"Unavailable"))
                        ForEach(cloudContext,id:\.self) { line in Text(line).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                    }
                    if let clarity=outlook?.clarity {
                        VStack(alignment:.leading,spacing:6) {
                            LabeledContent("Air",value:clarity.label)
                            Text("Aerosol forecast from CAMS. Not part of the score.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                        }
                    } else if let haze=outlook?.hazeText { Text(haze).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                    if let updated=night.forecastUpdated { Text("Open-Meteo · updated \(park.timestamp(updated))").font(.caption).foregroundStyle(palette.muted) }
                    if !nightItself.isEmpty {
                        Divider().overlay(palette.line)
                        VStack(alignment:.leading,spacing:10) {
                            Eyebrow(text:"The night itself")
                            ForEach(nightItself,id:\.text) { line in
                                Label { Text(line.text).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:line.symbol).foregroundStyle(palette.accent).accessibilityHidden(true) }
                                    .font(.subheadline).foregroundStyle(palette.ink)
                            }
                        }
                    }
                    Divider().overlay(palette.line)
                    LightPollution(park:park)
                } }
                Panel { ViewingSpots(park:park) }
                Panel { VStack(alignment:.leading,spacing:14) {
                    Eyebrow(text:"Ranger night-sky programs")
                    if let data=model.enrichments[park.id] {
                        let programs=data.programs.filter{$0.date>=park.isoDay(model.today)}
                        if programs.isEmpty && data.programsUpdated == nil { Text("Programs could not be checked in the last update. Ask at the visitor center for current night-sky programs.").foregroundStyle(palette.muted) }
                        else if programs.isEmpty { Text("No upcoming programs in the last update. Ask at the visitor center.").foregroundStyle(palette.muted) }
                        ForEach(programs) { program in VStack(alignment:.leading,spacing:8) { Text(program.title).font(.system(.title3,design:.serif)); Text(park.programDate(program.date)).font(.caption);Text(program.description).font(.subheadline).foregroundStyle(palette.muted) } }
                    } else { Text("Programs are not checked yet. Ask at the visitor center for current night-sky programs.").foregroundStyle(palette.muted) }
                } }
                Panel { ProtectThisSky(park:park) }
                ShareCardButton(night:night)
                Text("\(park.description)").font(.subheadline).foregroundStyle(palette.muted).frame(maxWidth:.infinity,alignment:.leading)
                NavigationLink("About the data") { AboutDataView() }.font(.subheadline)
            }.padding(24)
        }.scrollDisabled(scrubbing).onPreferenceChange(RiverScrubbingKey.self) { scrubbing=$0 }
        // Left open past sunrise, the river moves on to the new tonight; a chosen night that has
        // dropped off it is released, so the gauge and the river always show the same night.
        .onChange(of:riverStart) { _,start in
            if let chosen=selected, chosen<start || chosen>=park.date(start,addingDays:30) { selected=nil }
        }
        .defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top).background(NightBackground(seed:park.id,score:night.score.value,park:park,night:night.id)).navigationTitle(park.shortName).navigationBarTitleDisplayMode(.inline)
            .toolbar { saveToolbar }
            .sheet(isPresented:$breakdown) { NavigationStack { ScoreBreakdownView(night:night,isTonight:night.id==model.tonight(park)) }.nyxPresentation().presentationDetents([.large]) }
            .alert("Unable to save",isPresented:$persistenceError) { Button("OK",role:.cancel) {} } message:{ Text("Your changes could not be stored. Try again when space is available.") }
            .task { await model.prepareWhatsUp(model.nights(park,from:riverStart,count:30)) }
            .task { await model.refresh([park],programs:true) }
            .refreshable { await model.refresh([park],force:true,programs:true) }
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
    @Environment(PlanModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let night:Night
    var isTonight=true
    @ScaledMetric(relativeTo:.largeTitle) private var numeralSize=72.0
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:26) {
            VStack(alignment:.leading,spacing:10) {
                Eyebrow(text:"\(night.park.shortName) · \(night.park.dayLabel(night.id))")
                Text("A number with a reason").font(.system(.largeTitle,design:.serif)).fixedSize(horizontal:false,vertical:true)
            }
            HStack(alignment:.firstTextBaseline,spacing:12) {
                Text("\(night.score.value)").font(.system(size:numeralSize,weight:.light,design:.serif)).tracking(-3).foregroundStyle(palette.accent)
                VStack(alignment:.leading,spacing:2) { Text(night.score.band.label).font(.system(.title2,design:.serif)); Text("out of 100").font(.caption).foregroundStyle(palette.muted) }
            }
            .accessibilityElement(children:.combine)
            row("Moonlight",points:night.score.moonPoints,of:40,fact:moonFact,detail:String(localized:"Illumination and the part of true darkness when the Moon is below the horizon."))
            row("Cloud cover",points:night.score.cloudPoints,of:25,fact:night.cloudCover.map { String(localized:"\(Int($0.rounded()))% average cover across the dark window.") } ?? String(localized:"No forecast covers this night yet."),
                context:cloudContext,
                detail:cloudContext.isEmpty ? String(localized:"The hourly forecast averaged over the complete dark window.")
                    : String(localized:"The hourly forecast averaged over the complete dark window. Model agreement, cloud layers and smoke are context; they do not change the score."))
            row("Light pollution",points:night.score.bortlePoints,of:20,fact:String(localized:"Bortle class \(night.park.bortleEstimate) of 9, estimated."),context:lightContext,detail:String(localized:"A conservative Bortle estimate. It is not a measurement."))
            row("Length of darkness",points:night.score.lengthPoints,of:15,fact:night.sky.darkHours>0 ? String(localized:"\(darkness) of true darkness.") : String(localized:"No true darkness."),detail:String(localized:"Astronomical darkness, with ten hours receiving full credit."))
            if !night.score.hasForecast { Text("Clouds are unknown. The remaining components are scaled to 100. This estimate may change when a forecast arrives.").foregroundStyle(palette.muted) }
            if night.sky.darkHours==0 { Text(isTonight ? String(localized:"No true darkness tonight at this latitude. The score is capped below 40.") : String(localized:"No true darkness on this night at this latitude. The score is capped below 40.")).foregroundStyle(palette.accent) }
            else if ScoreEngine.cap(darkHours:night.sky.darkHours)<100 { Text(isTonight ? String(localized:"True darkness lasts only \(darkness) tonight, so the score is held to \(ScoreEngine.cap(darkHours:night.sky.darkHours)) or less.") : String(localized:"True darkness lasts only \(darkness) on this night, so the score is held to \(ScoreEngine.cap(darkHours:night.sky.darkHours)) or less.")).foregroundStyle(palette.accent) }
            if let event=model.events(night).item(park:night.park,sky:night.sky,isTonight:isTonight) {
                // An eclipse or a shower peak is a reason to go, said beside the score, never in it.
                HStack(alignment:.top,spacing:14) {
                    SkyGlyph(item:event.kind,color:palette.accent).frame(width:22,height:22).padding(.top,2)
                    VStack(alignment:.leading,spacing:6) {
                        Text([event.title,event.note].compactMap { $0 }.joined(separator:", ")).font(.headline)
                        if let value=event.value { Text(value).font(.system(.title3,design:.serif)).foregroundStyle(palette.accent) }
                        Text(event.detail).font(.system(.callout,design:.serif)).fixedSize(horizontal:false,vertical:true)
                        Text("Also in the sky this night. Not part of the score.").font(.footnote).foregroundStyle(palette.muted)
                    }
                }
                .accessibilityElement(children:.ignore).accessibilityLabel(event.spoken+" "+String(localized:"Also in the sky this night. Not part of the score."))
            }
            Text("The score is a planning guide, not a guarantee of visibility or safe access.").font(.caption).foregroundStyle(palette.muted)
            ShareCardButton(night:night)
        }.padding(24) }
        .background(NightBackground(score:night.score.value,park:night.park,night:night.id)).foregroundStyle(palette.ink).navigationTitle("Score breakdown").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
    }
    private var moonFact:String {
        let lit=String(localized:"\(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded()))% lit.")
        guard night.sky.darkHours>0 else { return lit }
        return lit+" "+String(localized:"Below the horizon for \(Int((night.sky.moonBelowFraction*100).rounded()))% of true darkness.")
    }
    /// Model agreement, the cloud layer and the air, each one sentence with a quiet symbol, so the
    /// context reads as a step below the fact the score was computed from.
    private var cloudContext:[(symbol:String,text:String)] {
        guard let outlook=model.outlook(night) else { return [] }
        let lines:[(String,String?)]=[("rectangle.split.3x1",outlook.agreement?.sentence(tonight:isTonight)),("cloud",outlook.layers?.note),
                                      ("smoke",outlook.clarity?.sentence),("sun.haze",outlook.clarity == nil ? outlook.hazeText : nil)]
        return lines.compactMap { symbol,text in text.map { (symbol,$0) } }
    }
    /// NASA's night lights, as context beside the estimate the score uses.
    private var lightContext:[(symbol:String,text:String)] {
        guard let site=SkyGlow.shared.park(night.park.id) else { return [] }
        return [("globe.americas",String(localized:"Satellite night lights: \(SkyGlow.levelLabel(SkyGlow.shared.level(site.glow))). Context only; not part of the score."))]
    }
    private var darkness:String { Duration.seconds(night.sky.darkHours*3600).formatted(.units(allowed:[.hours,.minutes],width:.wide)) }
    /// `weight` is the component's share of 100; without clouds the others are scaled up to fill it.
    /// Each part states the fact it was scored from, then how it is scored.
    private func row(_ title:LocalizedStringKey,points:Double?,of weight:Double,fact:String,context:[(symbol:String,text:String)]=[],detail:String)->some View {
        let maximum=night.score.hasForecast || points==nil ? weight : weight/0.75
        return VStack(alignment:.leading,spacing:9) {
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.firstTextBaseline) { Text(title).font(.headline);Spacer();amount(points,of:maximum) }
                VStack(alignment:.leading,spacing:4) { Text(title).font(.headline);amount(points,of:maximum) }
            }
            GeometryReader { proxy in
                ZStack(alignment:.leading) {
                    if let points {
                        Capsule().fill(palette.line)
                        Capsule().fill(palette.accent).frame(width:points>0 ? max(4,proxy.size.width*min(1,points/maximum)) : 0)
                    } else { Capsule().stroke(palette.line,style:StrokeStyle(lineWidth:1,dash:[2,3])) }
                }
            }.frame(height:4).accessibilityHidden(true)
            Text(fact).font(.system(.body,design:.serif)).fixedSize(horizontal:false,vertical:true)
            if !context.isEmpty {
                VStack(alignment:.leading,spacing:6) {
                    ForEach(context,id:\.text) { line in
                        Label { Text(line.text).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:line.symbol).foregroundStyle(palette.muted).accessibilityHidden(true) }
                    }
                }.font(.system(.callout,design:.serif)).foregroundStyle(palette.ink.opacity(palette.nightVision ? 1 : 0.88)).padding(.top,2)
            }
            Text(detail).font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
        .padding(.vertical,2)
        .accessibilityElement(children:.combine)
    }
    @ViewBuilder private func amount(_ points:Double?,of maximum:Double)->some View {
        if let points { Text("\(Int(points.rounded())) of \(Int(maximum.rounded()))").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent) }
        else { Text("Unknown").font(.system(.title3,design:.serif)).foregroundStyle(palette.muted) }
    }
}
#Preview("Park row") { if let p=PlanModel().home { ParkRow(night:PlanModel().night(p)).padding().background(.black) } }
#Preview("Detail") { let m=PlanModel();if let p=m.home { NavigationStack { ParkDetailView(park:p) }.environment(m).modelContainer(for:[SavedPark.self,JournalEntry.self],inMemory:true).preferredColorScheme(.dark) } }
