import SwiftUI
import CoreLocation
import EventKit
import EventKitUI

/// "I'm free Oct 10–17": the best park in reach for each night, the single best night, and
/// a line on why. Planned on this iPhone from cached forecasts and park updates; nothing is fetched.
/// Plan's second mode ("My free nights"); the choices are kept for the window while the month is open.
struct TripPlannerView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
    /// Inside Plan, which names the page and holds the toolbar; alone (a DEBUG route) it names itself.
    var embedded=false
    /// The chosen nights as seconds since 1970; 0 until chosen, which means from tonight for a week.
    @SceneStorage("tripFirst") private var firstStamp=0.0
    @SceneStorage("tripLast") private var lastStamp=0.0
    /// The farthest hop between back-to-back nights, in metres (`SearchRadius`): 300 miles, or 500 km.
    /// The starting point and the radius are Tonight's (`StartingPointPanel`), one for the whole app.
    @SceneStorage("tripHopMeters") private var maxHop=SearchRadius.tripStandard()
    @SceneStorage("tripWeekends") private var weekendsOnly=false
    /// On by default: a plan that ends at a ferry dock at midnight is not a plan.
    @SceneStorage("tripDrivable") private var drivableOnly=true
    @State private var choosingStart=false
    @State private var explainLocation=false
    @State private var plan:TripPlan?
    @State private var planning=false
    @State private var calendarStay:TripStay?
    @State private var planned=0
    /// The inputs last announced, so returning to the page refreshes the plan without saying it again.
    @State private var announced:String?
    @State private var prepared=false
    @State private var width=0.0
    /// The best night's numeral: the hero, scaling with Dynamic Type but never past the screen.
    @ScaledMetric(relativeTo:.largeTitle) private var heroSize=96.0
    /// The planning inputs on the left and the plan on the right, on a wide iPad.
    private var wide:Bool { WideLayout.columns(width:width,largeText:typeSize.isAccessibilitySize)==2 }
    /// Never earlier than last night: a window kept from another day starts again from tonight.
    private var first:Date { firstStamp>0 && firstStamp>=Date.now.timeIntervalSince1970-86400 ? Date(timeIntervalSince1970:firstStamp) : Date.now }
    private var last:Date { lastStamp>0 && lastStamp>=first.timeIntervalSince1970 ? Date(timeIntervalSince1970:lastStamp) : first.addingTimeInterval(6*86400) }
    private var firstBinding:Binding<Date> { Binding(get:{ first },set:{ firstStamp=$0.timeIntervalSince1970; clampLast() }) }
    private var lastBinding:Binding<Date> { Binding(get:{ last },set:{ lastStamp=$0.timeIntervalSince1970 }) }
    /// Brings the last night back inside the picker's range, as the first night or weekends only change.
    private func clampLast() {
        let clamped=TripPlanner.clampedLast(last,first:first,weekendsOnly:weekendsOnly)
        if clamped != last { lastStamp=clamped.timeIntervalSince1970 }
    }
    private var days:[TripDay] { TripPlanner.days(first:TripDay(first),last:TripDay(last),weekendsOnly:weekendsOnly) }
    /// Where distances are measured from: the device under Near me, else the starting point (`PlanModel.reachOrigin`).
    private var point:CLLocationCoordinate2D? { model.reachOrigin.map { CLLocationCoordinate2D(latitude:$0.latitude,longitude:$0.longitude) } }
    private var radius:Double { model.radiusMeters }
    /// Which start the plan is from: the chosen park or place, or the device on a 0.05° grid, so a
    /// location refreshed a few metres away never plans (and announces) the same trip again.
    private var reachIdentity:String {
        guard let lat=model.location.latitude, let lon=model.location.longitude else { return "\(model.homeID)-\(model.homePlace?.id ?? "")" }
        return "here-\(Int((lat*20).rounded()))-\(Int((lon*20).rounded()))"
    }
    /// What the person chose; a change is announced.
    private var choices:String { "\(TripDay(first).iso)-\(TripDay(last).iso)-\(radius)-\(maxHop)-\(weekendsOnly)-\(drivableOnly)-\(reachIdentity)" }
    /// The choices and the data under them: new clouds, smoke or a closure plan again, quietly.
    private var inputs:String { "\(choices)-\(model.dataRevision)" }
    var body: some View {
        ScrollViewReader { proxy in ScrollView {
            if wide {
                // The two columns meet at iPhone Duo's fold on its inner display, half open or flat.
                FoldColumns(narrow:.leading,narrowMax:420,spacing:32) {
                    VStack(alignment:.leading,spacing:22) { intro; startingPoint; Panel { controls } }.frame(maxWidth:.infinity,alignment:.leading)
                    VStack(alignment:.leading,spacing:24) {
                        if let best=plan?.best { hero(best) }
                        results
                    }.frame(maxWidth:.infinity)
                }.padding(NyxMetrics.pagePadding).readableColumn(WideLayout.twoColumnMaximum)
            } else {
                VStack(alignment:.leading,spacing:24) {
                    intro
                    // The answer first; the questions that shape it just below.
                    if let best=plan?.best { hero(best) }
                    startingPoint
                    Panel { controls }
                    results
                }.padding(24).readableColumn()
            }
        }
        // DEBUG store capture (`-nyx-trip-route`): the route card at the top, once the plan is in.
        .onChange(of:plan?.best?.id) { _,_ in if DebugScenario.isEnabled("trip-route") { Task { try? await Task.sleep(for:.milliseconds(400)); proxy.scrollTo("route",anchor:.top) } } }
        }
        .measuringWidth($width)
        .foldSource()
        .defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top)
        .background(NightBackground(seed:"trip",park:plan?.best?.night.park,night:plan?.best?.night.id))
        .modifier(StandaloneTitle(embedded:embedded))
        .toolbar { if let plan, !plan.stops.isEmpty { ToolbarItem(placement:.topBarTrailing) {
            ShareLink(item:TripPlanner.shareText(plan,distance:Self.miles)) { Label("Share plan",systemImage:"square.and.arrow.up") }.accessibilityLabel("Share plan")
        } } }
        .modifier(StartingPointSheets(choosing:$choosingStart,explaining:$explainLocation))
        .sheet(item:$calendarStay) { stay in
            if let draft=CalendarDraft(stay:stay.stops) { CalendarEditor(draft:draft) { calendarStay=nil }.ignoresSafeArea().nyxPresentation() }
        }
        .sensoryFeedback(.selection,trigger:planned)
        .onChange(of:weekendsOnly) { clampLast() }
        .task {
            guard !prepared else { return }
            prepared=true
            #if DEBUG
            if let date=DebugScenario.date { firstStamp=date.timeIntervalSince1970; lastStamp=date.addingTimeInterval(6*86400).timeIntervalSince1970 }
            else if DebugScenario.screen != nil { firstStamp=0; lastStamp=0 }
            if DebugScenario.screen != nil { maxHop=SearchRadius.tripStandard(); weekendsOnly=false; drivableOnly=true }
            if DebugScenario.state=="weekends" { weekendsOnly=true; lastStamp=first.addingTimeInterval(27*86400).timeIntervalSince1970 }
            // Boat and plane parks included, close in: `-nyx-park chis` shows the access notes in the plan.
            if DebugScenario.state=="boats" { drivableOnly=false }
            #endif
            // Cached forecasts are enough; a refresh that is already due arrives in the background.
            Task { await model.refreshForecasts(watching:[]) }
        }
        .task(id:inputs) {
            guard prepared else { return }
            try? await Task.sleep(for:.milliseconds(200))
            guard !Task.isCancelled else { return }
            planning=true
            guard let point else { planning=false; return }
            let result=await model.planTrip(days:days,latitude:point.latitude,longitude:point.longitude,radiusMeters:radius,maxHopMeters:maxHop,drivableOnly:drivableOnly)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : NyxMotion.spring) { plan=result }
            planning=false
            // Only a change of plan is spoken and felt; a return to the page is not.
            let key=choices
            guard key != announced else { return }
            announced=key
            // The plan changes above and below the controls; say what it now leads with.
            AccessibilityNotification.Announcement(result.best.map { String(localized:"Best night: \($0.night.park.shortName), \($0.night.score.value)") } ?? String(localized:"No nights to plan")).post()
            if result.best != nil { planned+=1 }
        }
    }
    private static func miles(_ meters:Double)->String { Measurement(value:meters,unit:UnitLength.meters).formatted(.measurement(width:.abbreviated,usage:.road)) }
    /// One plain line on what this mode answers; Plan's bar already names the page.
    private var intro:some View {
        Text("The best park in reach for each night you are free.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
    }
    @ViewBuilder private var controls:some View {
        VStack(alignment:.leading,spacing:16) {
            DatePicker("First night",selection:firstBinding,in:Date.now.addingTimeInterval(-86400)...Date.now.addingTimeInterval(365*86400),displayedComponents:.date)
            DatePicker("Last night",selection:lastBinding,in:first...TripPlanner.latestLast(first:first,weekendsOnly:weekendsOnly),displayedComponents:.date)
            Toggle(isOn:$weekendsOnly) { VStack(alignment:.leading,spacing:2) { Text("Weekends only"); Text("Nights before your days off").font(.caption).foregroundStyle(palette.muted) } }.tint(palette.controlTint)
            Text("\(days.count) nights, at most \(TripPlanner.maxNights)").font(.caption).foregroundStyle(palette.muted)
            Divider().overlay(palette.line)
            distancePicker(title:"Farthest between nights",selection:$maxHop,values:SearchRadius.hopSteps(),note:"straight line, back-to-back nights")
            Toggle(isOn:$drivableOnly) { VStack(alignment:.leading,spacing:2) { Text("Parks you can drive to"); Text("Leaves out parks reached only by boat or plane").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) } }.tint(palette.controlTint)
        }
    }
    /// The one starting point and radius, as Tonight shows them.
    private var startingPoint:some View {
        StartingPointPanel(choose:{ choosingStart=true },nearMe:{ StartingPointSheets.nearMe(model) { explainLocation=true } })
    }
    private func distancePicker(title:LocalizedStringKey,selection:Binding<Double>,values:[Double],note:LocalizedStringKey)->some View {
        ViewThatFits(in:.horizontal) {
            HStack(alignment:.firstTextBaseline) { VStack(alignment:.leading,spacing:2) { Text(title).fixedSize(horizontal:false,vertical:true); Text(note).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }.layoutPriority(1); Spacer(minLength:8); menu(title:title,selection:selection,values:values) }
            VStack(alignment:.leading,spacing:4) { Text(title); Text(note).font(.caption).foregroundStyle(palette.muted); menu(title:title,selection:selection,values:values) }
        }
    }
    private func menu(title:LocalizedStringKey,selection:Binding<Double>,values:[Double])->some View {
        // At accessibility sizes the menu's label wraps rather than widening the page.
        WrappingMenuPicker(title:title,selection:selection,current:SearchRadius.label(selection.wrappedValue)) {
            ForEach(SearchRadius.choices(values,keeping:selection.wrappedValue),id:\.self) { meters in Text(SearchRadius.label(meters)).tag(meters) }
        }
    }
    @ViewBuilder private var results:some View {
        if let plan {
            if plan.stops.isEmpty {
                CalmState(symbol:"moon.stars",title:plan.candidates==0 ? "No parks in reach" : "No nights to plan",message:plan.candidates==0 ? (onlyByBoatOrPlane ? "The only parks inside this radius are reached by boat or plane. Turn off Parks you can drive to, or widen the radius." : "No parks or dark-sky places fall inside this radius. Widen it or choose a different starting point.") : "Weekends only leaves no night before a day off in these dates. Add a weekend or include weeknights.")
            } else {
                Panel { VStack(alignment:.leading,spacing:12) {
                    Eyebrow(text:"The route")
                    SkyMapView(content:routeContent(plan),summary:routeSummary(plan))
                    Text("Your nights as stars among the parks and dark-sky places, joined night to night. The ring marks the best night.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                } }.id("route")
                VStack(spacing:0) {
                    // Back-to-back nights at one park are one stay: one row, one calendar event.
                    // The access note once per park, on its first stay, rather than on every row.
                    let stays=TripPlanner.stays(plan.stops).compactMap(TripStay.init)
                    let firsts=Set(stays.reduce(into:[String:String]()) { seen,stay in if seen[stay.park.id]==nil { seen[stay.park.id]=stay.id } }.values)
                    ForEach(stays) { stay in
                        TripStayRow(stay:stay,addToCalendar:{ calendarStay=stay },distance:Self.miles,showsAccess:firsts.contains(stay.id))
                        if stay.id != stays.last?.id { Divider().overlay(palette.line) }
                    }
                }
                VStack(alignment:.leading,spacing:6) {
                    if let note=UsualCloudsNote.trip(TripStay.marked(plan.stops),unmarked:TripStay.unmarked(plan.stops)) { Text(note).fixedSize(horizontal:false,vertical:true) }
                    Text("Distances are straight lines, not roads. Scores are estimates; a closure in the last park update counts against a park. Check closures and the forecast before you go.").fixedSize(horizontal:false,vertical:true)
                }.font(.caption).foregroundStyle(palette.muted)
                ShareLink(item:TripPlanner.shareText(plan,distance:Self.miles)) { Label("Share plan",systemImage:"square.and.arrow.up") }.secondaryAction()
            }
        } else if planning || !prepared { ProgressView("Planning your nights").frame(maxWidth:.infinity).padding(.vertical,30) }
    }
    /// An empty plan only because the drive-to filter left out the boat-and-plane parks in reach.
    private var onlyByBoatOrPlane:Bool {
        guard drivableOnly, let point else { return false }
        return !model.tripCandidates(latitude:point.latitude,longitude:point.longitude,radiusMeters:radius).isEmpty
    }
    private func hero(_ best:TripStop)->some View {
        let park=best.night.park
        return NavigationLink { ParkDetailView(park:park,initialDate:best.night.id).onAppear { ReviewPrompt.noteNightViewed(score:best.night.score.value) } } label:{
            VStack(spacing:10) {
                Eyebrow(text:"The best night")
                Text(park.shortName).font(.system(.title,design:.serif)).multilineTextAlignment(.center).foregroundStyle(palette.ink)
                Text(park.dayLabel(best.night.id)).font(.subheadline).foregroundStyle(palette.muted)
                Text("\(best.night.score.value)").scoreNumeral(size:min(heroSize,150),accent:palette.accent)
                    .contentTransition(.numericText(value:Double(best.night.score.value)))
                Text(best.night.bandWithBasis).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).multilineTextAlignment(.center)
                Text(best.reason).font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                if let closure=best.closure { Label(closure,systemImage:"exclamationmark.triangle").font(.subheadline).labelStyle(.caution).multilineTextAlignment(.center) }
                AccessNoteLabel(park:park,alignment:.center)
            }.frame(maxWidth:.infinity)
        }.buttonStyle(.plain)
        .accessibilityElement(children:.combine)
        .accessibilityHint("Opens that night at the park.")
    }
    /// The route on a map fitted around the trip's places and the parks in reach of its first night
    /// (Lambert, centred on them), so a trip of a few hundred kilometres fills the panel wherever
    /// on Earth it runs.
    private func routeContent(_ plan:TripPlan)->SkyMapContent {
        let first=plan.stops[0].night.park
        let nearby=model.tripCandidates(latitude:first.latitude,longitude:first.longitude,radiusMeters:radius,drivableOnly:drivableOnly)
        let frame=MapFrame.fitting(plan.stops.map { GeoPoint($0.night.park) }+nearby.map(GeoPoint.init),aspect:SkyMap.aspect,padding:0.08,minimumKm:700)
        func at(_ park:Park)->CGPoint { frame.point(park) ?? CGPoint(x:0.5,y:frame.aspect/2) }
        var seen:[String:Int]=[:]
        let stars=plan.stops.map { stop in
            // A park chosen for several nights gathers a small cluster, as in your constellation.
            let n=seen[stop.night.park.id,default:0]; seen[stop.night.park.id]=n+1
            let base=at(stop.night.park), radius=0.012*Double(n).squareRoot(), angle=Double(n)*2.399963
            return SkyMapContent.Star(id:stop.id,point:CGPoint(x:base.x+radius*cos(angle),y:base.y+radius*sin(angle)),brightness:0.3+0.7*Double(stop.night.score.value)/100,ringed:stop.isBest,label:"")
        }
        // Night to night, only where the nights are back to back and the park changes.
        let edges=zip(plan.stops,plan.stops.dropFirst()).compactMap { a,b in
            b.hopMeters.flatMap { $0>1000 ? (at(a.night.park),at(b.night.park)) : nil }
        }
        return SkyMapContent(stars:stars,figures:edges.isEmpty ? [] : [edges],frame:frame,background:SkyMap.background(model.mapPlaces,in:frame))
    }
    private func routeSummary(_ plan:TripPlan)->String {
        let parks=Array(NSOrderedSet(array:plan.stops.map(\.night.park.shortName))).compactMap { $0 as? String }
        return String(localized:"Route map: \(Phrase.list(parks)).")
    }
}
/// Alone, the planner names its own page; inside Plan, Plan does.
private struct StandaloneTitle: ViewModifier {
    let embedded:Bool
    @ViewBuilder func body(content:Content)->some View {
        if embedded { content } else { content.navigationTitle("My free nights").navigationBarTitleDisplayMode(.inline) }
    }
}
/// Back-to-back nights at one park: one row, one calendar event.
nonisolated struct TripStay: Identifiable, Sendable {
    let stops:[TripStop]
    let park:Park
    /// Nil for no nights (`TripPlanner.stays` makes none).
    init?(_ stops:[TripStop]) { guard let park=stops.first?.night.park else { return nil }; self.stops=stops; self.park=park }
    var id:String { stops.first?.id ?? "" }
    var isBest:Bool { stops.contains(where:\.isBest) }
    /// The stay's darkest night, whose score leads the row.
    var best:TripStop? { stops.first(where:\.isBest) ?? stops.max { NightPlanner.better($1.night,$0.night) } }
    /// The nights whose marks the rows show ("Early look", "Cloud forecast unavailable"): each
    /// stay's leading night, so the note under the plan names no mark that no row shows.
    static func marked(_ stops:[TripStop])->[Night] { TripPlanner.stays(stops).compactMap { TripStay($0)?.best?.night } }
    /// The other nights of each stay: their scores are listed beneath the row, their marks are not.
    static func unmarked(_ stops:[TripStop])->[Night] {
        TripPlanner.stays(stops).compactMap(TripStay.init).flatMap { stay in stay.stops.filter { $0.id != stay.best?.id }.map(\.night) }
    }
}
/// One stay of the plan: the dates, the park, the score, why, and what to check. A stay of several
/// nights reads "3 nights at Death Valley" with each night's score beneath it.
struct TripStayRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(PlanModel.self) private var model
    @ScaledMetric(relativeTo:.title) private var scoreSize=40.0
    /// A save from the stop's menu could not be stored.
    @State private var saveFailed=false
    let stay: TripStay
    let addToCalendar: ()->Void
    let distance: (Double)->String
    var showsAccess=true
    var body: some View {
        if let first=stay.stops.first, let last=stay.stops.last, let lead=stay.best {
            let park=stay.park, night=lead.night, several=stay.stops.count>1
            VStack(alignment:.leading,spacing:10) {
                NavigationLink { ParkDetailView(park:park,initialDate:night.id) } label:{
                    Group {
                        if typeSize.isAccessibilitySize {
                            // At accessibility sizes the lines and the score stack, as Ask Nyx's records do,
                            // so neither the dates nor the park's name are squeezed beside the numeral.
                            VStack(alignment:.leading,spacing:6) {
                                lines(first:first,last:last,lead:lead)
                                HStack(alignment:.firstTextBaseline,spacing:8) { scoreNumeral(night); Text(night.compactBandLabel).font(.caption2).foregroundStyle(palette.muted) }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        } else {
                            HStack(alignment:.top,spacing:14) {
                                lines(first:first,last:last,lead:lead)
                                Spacer(minLength:8)
                                VStack(alignment:.trailing,spacing:0) {
                                    scoreNumeral(night)
                                    Text(basisWord(night)).font(.caption2).foregroundStyle(palette.muted)
                                }
                            }
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(spoken)
                .accessibilityHint(several ? "Opens the best of these nights at the park." : "Opens that night at the park.")
                // The park as a row anywhere else: its menu, the pointer's highlight, and dragging it onto Plan or Journal.
                .parkRowActions(park) { saveFailed=true }
                .parkSaveAlert(isPresented:$saveFailed,journalUnavailable:model.journalUnavailable)
                Button(action:addToCalendar) { Label(several ? String(localized:"Add \(stay.stops.count) nights to Calendar") : String(localized:"Add to Calendar"),systemImage:"calendar.badge.plus").font(.subheadline).frame(minHeight:44) }
                    .buttonStyle(.nyxAction).foregroundStyle(palette.ink)
                    .accessibilityLabel(several ? String(localized:"Add \(stay.stops.count) nights at \(park.shortName) to Calendar") : String(localized:"Add \(park.shortName) on \(park.dayLabel(night.id)) to Calendar"))
                    .accessibilityInputLabels([Text("Add to Calendar"),Text("Add \(park.shortName) to Calendar")])
            }.padding(.vertical,14)
            .background { if stay.isBest { RoundedRectangle(cornerRadius:18).fill(palette.ink.opacity(palette.nightVision ? 0.1 : 0.06)).padding(.horizontal,-12) } }
        }
    }
    /// The dates, the park, why, and what to check.
    private func lines(first:TripStop,last:TripStop,lead:TripStop)->some View {
        let park=stay.park, night=lead.night, several=stay.stops.count>1
        return VStack(alignment:.leading,spacing:4) {
            // At accessibility sizes the badge goes under the dates rather than squeezing them.
            dateRow {
                (several ? Text("\(park.dayLabel(first.night.id)) – \(park.dayLabel(last.night.id))") : Text(verbatim:park.dayLabel(night.id))).font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                if stay.isBest { Text("Best night").font(.caption2.weight(.semibold)).padding(.horizontal,8).padding(.vertical,3).foregroundStyle(palette.nightVision ? palette.ink : Color.black).background(Capsule().fill(palette.ink.opacity(palette.nightVision ? 0.35 : 1))) }
            }
            Text(several ? String(localized:"\(stay.stops.count) nights at \(park.shortName)") : park.shortName).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            if several { Text(nightly).font(.caption.monospacedDigit()).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
            Text(lead.reason).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if let hop=first.hopMeters, hop>1000 { Label(String(localized:"\(distance(hop)) from the night before"),systemImage:"arrow.triangle.turn.up.right.diamond").font(.caption).foregroundStyle(palette.muted) }
            if let label=night.basisLabel { Text(label).font(.caption).foregroundStyle(palette.muted) }
            if let closure=stay.stops.compactMap(\.closure).first { Label(String(localized:"Closure alert: \(closure)"),systemImage:"exclamationmark.triangle").font(.caption).labelStyle(.caution).fixedSize(horizontal:false,vertical:true) }
            if showsAccess { AccessNoteLabel(park:park) }
        }
    }
    /// The dates and the best-night badge: side by side, or the badge under the dates at accessibility sizes.
    private func dateRow<Content:View>(@ViewBuilder _ content:()->Content)->some View {
        let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:4)) : AnyLayout(HStackLayout(spacing:8))
        return layout { content() }
    }
    private func scoreNumeral(_ night:Night)->some View {
        Text("\(night.score.value)").scoreNumeral(size:min(scoreSize,64),accent:palette.accent)
    }
    /// The word under a stay's score in the three words every surface uses: the band on a full
    /// forecast, "Early look", or "Usual clouds" (the band alone where the place has no usual clouds).
    private func basisWord(_ night:Night)->String {
        switch night.basis {
        case .forecast: night.score.band.label
        case .blended: String(localized:"Early look")
        case .usual: night.score.cloudPoints == nil ? night.score.band.label : String(localized:"Usual clouds")
        }
    }
    /// "Tue 94 · Wed 97 · Thu 95", in the park's own days.
    private var nightly:String {
        var format=Date.FormatStyle.dateTime.weekday(.abbreviated)
        format.timeZone=stay.park.timeZone
        return stay.stops.map { "\($0.night.id.formatted(format)) \($0.night.score.value)" }.joined(separator:" · ")
    }
    private var spoken:String {
        let park=stay.park
        guard let lead=stay.best, let first=stay.stops.first, let last=stay.stops.last else { return park.shortName }
        let night=lead.night
        var parts:[String]
        if stay.stops.count>1 {
            parts=[String(localized:"\(stay.stops.count) nights at \(park.shortName), \(park.dayLabel(first.night.id)) to \(park.dayLabel(last.night.id))")]
            if stay.isBest { parts.append(String(localized:"Includes the best night")) }
            parts+=stay.stops.map { $0.night.spokenSummary(.dayWithBasis) }
        } else {
            parts=[stay.isBest ? String(localized:"Best night. \(park.dayLabel(night.id))") : park.dayLabel(night.id),park.shortName,
                   night.spokenSummary(.scoreWithBasis)]
        }
        parts.append(lead.reason)
        if let hop=first.hopMeters, hop>1000 { parts.append(String(localized:"\(distance(hop)) from the night before")) }
        if let closure=stay.stops.compactMap(\.closure).first { parts.append(String(localized:"Closure alert: \(closure)")) }
        if let access=park.accessNote { parts.append(String(localized:"Getting there: \(access)")) }
        return Phrase.sentences(parts)
    }
}
/// The system's own event editor, filled in with the night. It runs outside Nyx: the person
/// chooses the calendar and saves, and Nyx is never given access to read any calendar (iOS 17+).
struct CalendarEditor: UIViewControllerRepresentable {
    let draft: CalendarDraft
    let done: ()->Void
    func makeCoordinator()->Coordinator { Coordinator(done:done) }
    func makeUIViewController(context:Context)->EKEventEditViewController {
        let store=context.coordinator.store
        let event=EKEvent(eventStore:store)
        event.title=draft.title; event.startDate=draft.start; event.endDate=draft.end; event.timeZone=draft.timeZone
        event.location=draft.location; event.notes=draft.notes; event.url=draft.url
        let controller=EKEventEditViewController()
        controller.eventStore=store; controller.event=event; controller.editViewDelegate=context.coordinator
        return controller
    }
    func updateUIViewController(_ controller:EKEventEditViewController,context:Context) {}
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let store=EKEventStore()
        let done: ()->Void
        init(done: @escaping ()->Void) { self.done=done }
        func eventEditViewController(_ controller:EKEventEditViewController,didCompleteWith action:EKEventEditViewAction) { done() }
    }
}
/// The device's position once, and only if location was already allowed. Never asks.
@MainActor final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager=CLLocationManager()
    private var continuation:CheckedContinuation<CLLocationCoordinate2D?,Never>?
    private static var active:[OneShotLocation]=[]
    static func current() async -> CLLocationCoordinate2D? {
        let locator=OneShotLocation()
        guard [.authorizedWhenInUse,.authorizedAlways].contains(locator.manager.authorizationStatus) else { return nil }
        active.append(locator)
        defer { active.removeAll { $0 === locator } }
        return await withCheckedContinuation { continuation in
            locator.continuation=continuation
            locator.manager.delegate=locator
            locator.manager.desiredAccuracy=kCLLocationAccuracyThreeKilometers
            locator.manager.requestLocation()
        }
    }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) { finish(locations.last?.coordinate) }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:any Error) { finish(nil) }
    private func finish(_ value:CLLocationCoordinate2D?) { continuation?.resume(returning:value); continuation=nil }
}
