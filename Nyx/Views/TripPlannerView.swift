import SwiftUI
import CoreLocation
import EventKit
import EventKitUI

/// "I'm free Oct 10–17, within 300 miles": the best park for each night, the single best night, and
/// a line on why. Planned on this iPhone from cached forecasts and park updates; nothing is fetched.
struct TripPlannerView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var first=Date.now
    @State private var last=Date.now.addingTimeInterval(6*86400)
    @State private var radius=300.0
    @State private var maxHop=300.0
    @State private var weekendsOnly=false
    @State private var originID=""
    @State private var useDevice=false
    @State private var device:CLLocationCoordinate2D?
    @State private var choosingPark=false
    @State private var plan:TripPlan?
    @State private var planning=false
    @State private var calendarStop:TripStop?
    @State private var planned=0
    @State private var prepared=false
    /// The best night's numeral: the hero, scaling with Dynamic Type but never past the screen.
    @ScaledMetric(relativeTo:.largeTitle) private var heroSize=96.0
    private var origin:Park? { model.park(originID) ?? model.home }
    private var days:[TripDay] { TripPlanner.days(first:TripDay(first),last:TripDay(last),weekendsOnly:weekendsOnly) }
    private var inputs:String { "\(TripDay(first).iso)-\(TripDay(last).iso)-\(radius)-\(maxHop)-\(weekendsOnly)-\(originID)-\(useDevice)-\(device?.latitude ?? 0)-\(model.forecasts.count)" }
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Eyebrow(text:"Reasons to go")
            Text("Plan a trip").font(.system(.largeTitle,design:.serif))
            Text("The darkest park in reach for each night you are free.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            // The answer first; the questions that shape it just below.
            if let best=plan?.best { hero(best) }
            Panel { controls }
            results
        }.padding(24) }
        .defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top)
        .background(NightBackground(seed:"trip",park:plan?.best?.night.park,night:plan?.best?.night.id))
        .navigationTitle("Plan a trip").navigationBarTitleDisplayMode(.inline)
        .toolbar { if let plan, !plan.stops.isEmpty { ToolbarItem(placement:.topBarTrailing) {
            ShareLink(item:TripPlanner.shareText(plan,distance:Self.miles)) { Image(systemName:"square.and.arrow.up") }.accessibilityLabel("Share plan")
        } } }
        .sheet(isPresented:$choosingPark) { NavigationStack { ParkPickerView(selection:Binding(get:{ origin?.id ?? "" },set:{ originID=$0; useDevice=false })) }.nyxPresentation() }
        .sheet(item:$calendarStop) { stop in CalendarEditor(draft:CalendarDraft(stop:stop)) { calendarStop=nil }.ignoresSafeArea() }
        .sensoryFeedback(.selection,trigger:planned)
        .task {
            guard !prepared else { return }
            prepared=true
            originID=model.homeID
            #if DEBUG
            if let date=DebugScenario.date { first=date; last=date.addingTimeInterval(6*86400) }
            if DebugScenario.state=="weekends" { weekendsOnly=true; last=first.addingTimeInterval(27*86400) }
            #endif
            // Location only if it was already allowed: the trip planner never asks for it.
            if DebugScenario.screen == nil, let fix=await OneShotLocation.current() { device=fix; useDevice=true }
            // Cached forecasts are enough; a refresh that is already due arrives in the background.
            Task { await model.refreshForecasts(watching:[]) }
        }
        .task(id:inputs) {
            guard prepared else { return }
            if last<first { last=first }
            try? await Task.sleep(for:.milliseconds(200))
            guard !Task.isCancelled else { return }
            planning=true
            let point=useDevice ? device : origin.map { CLLocationCoordinate2D(latitude:$0.latitude,longitude:$0.longitude) }
            guard let point else { planning=false; return }
            let result=await model.planTrip(days:days,latitude:point.latitude,longitude:point.longitude,radiusMiles:radius,maxHopMiles:maxHop)
            guard !Task.isCancelled else { return }
            withAnimation(NyxMotion.spring) { plan=result }
            planning=false
            if result.best != nil { planned+=1 }
        }
    }
    private static func miles(_ meters:Double)->String { Measurement(value:meters,unit:UnitLength.meters).formatted(.measurement(width:.abbreviated,usage:.road)) }
    @ViewBuilder private var controls:some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:8) {
                Text("From").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                if device != nil {
                    Picker("Starting point",selection:$useDevice) { Text("Your location").tag(true); Text(origin?.shortName ?? "").tag(false) }.pickerStyle(.segmented)
                }
                if !useDevice {
                    Button { choosingPark=true } label:{
                        HStack { Label(origin?.shortName ?? "",systemImage:"mappin.and.ellipse").fixedSize(horizontal:false,vertical:true); Spacer(minLength:8); Image(systemName:"chevron.up.chevron.down").imageScale(.small).accessibilityHidden(true) }
                            .frame(minHeight:44).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(palette.accent).accessibilityLabel("Starting park").accessibilityValue(origin?.shortName ?? "").accessibilityHint("Choose a starting park")
                }
            }
            Divider().overlay(palette.line)
            DatePicker("First night",selection:$first,in:Date.now.addingTimeInterval(-86400)...Date.now.addingTimeInterval(365*86400),displayedComponents:.date)
            DatePicker("Last night",selection:$last,in:first...first.addingTimeInterval(Double(weekendsOnly ? 69 : 13)*86400),displayedComponents:.date)
            Toggle(isOn:$weekendsOnly) { VStack(alignment:.leading,spacing:2) { Text("Weekends only"); Text("Friday and Saturday nights").font(.caption).foregroundStyle(palette.muted) } }.tint(palette.controlTint)
            Text(days.count==1 ? String(localized:"One night") : String(localized:"\(days.count) nights, at most \(TripPlanner.maxNights)")).font(.caption).foregroundStyle(palette.muted)
            Divider().overlay(palette.line)
            distancePicker(title:"Within",selection:$radius,values:[100,200,300,500,1000],note:"as the crow flies")
            distancePicker(title:"Longest drive between nights",selection:$maxHop,values:[100,200,300,500],note:"straight line, back-to-back nights")
        }
    }
    private func distancePicker(title:LocalizedStringKey,selection:Binding<Double>,values:[Double],note:LocalizedStringKey)->some View {
        ViewThatFits(in:.horizontal) {
            HStack(alignment:.firstTextBaseline) { VStack(alignment:.leading,spacing:2) { Text(title); Text(note).font(.caption).foregroundStyle(palette.muted) }; Spacer(minLength:8); menu(title:title,selection:selection,values:values) }
            VStack(alignment:.leading,spacing:4) { Text(title); Text(note).font(.caption).foregroundStyle(palette.muted); menu(title:title,selection:selection,values:values) }
        }
    }
    private func menu(title:LocalizedStringKey,selection:Binding<Double>,values:[Double])->some View {
        Picker(title,selection:selection) {
            ForEach(values,id:\.self) { miles in Text(Measurement(value:miles,unit:UnitLength.miles),format:.measurement(width:.abbreviated,usage:.road)).tag(miles) }
        }.pickerStyle(.menu).fixedSize()
    }
    @ViewBuilder private var results:some View {
        if let plan {
            if plan.stops.isEmpty {
                CalmState(symbol:"moon.stars",title:plan.candidates==0 ? "No parks in reach" : "No nights to plan",message:plan.candidates==0 ? "No national parks fall inside this radius. Widen it or start from another park." : "Weekends only leaves no Friday or Saturday in these dates. Add a weekend or include weeknights.")
            } else {
                Panel { VStack(alignment:.leading,spacing:12) {
                    Eyebrow(text:"The route")
                    SkyMapView(content:routeContent(plan),summary:routeSummary(plan))
                    Text("Your nights as stars among the national parks, joined night to night. The ring marks the best night.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                } }
                VStack(spacing:0) {
                    ForEach(plan.stops) { stop in
                        TripStopRow(stop:stop,addToCalendar:{ calendarStop=stop },distance:Self.miles)
                        if stop.id != plan.stops.last?.id { Divider().overlay(palette.line) }
                    }
                }
                VStack(alignment:.leading,spacing:6) {
                    if plan.moonOnlyNights>0 { Text("Nights marked \"Moon and darkness only\" are beyond the cloud forecast, or not every park had one; they are compared without clouds.").fixedSize(horizontal:false,vertical:true) }
                    Text("Distances are straight lines, not roads. Scores are estimates; a closure in the last park update counts against a park. Check closures and the forecast before you go.").fixedSize(horizontal:false,vertical:true)
                }.font(.caption).foregroundStyle(palette.muted)
                ShareLink(item:TripPlanner.shareText(plan,distance:Self.miles)) { Label("Share plan",systemImage:"square.and.arrow.up") }.buttonStyle(.bordered)
            }
        } else if planning || !prepared { ProgressView("Planning your nights").frame(maxWidth:.infinity).padding(.vertical,30) }
    }
    private func hero(_ best:TripStop)->some View {
        let park=best.night.park
        return NavigationLink { ParkDetailView(park:park,initialDate:best.night.id) } label:{
            VStack(spacing:10) {
                Eyebrow(text:"The best night")
                Text(park.shortName).font(.system(.title,design:.serif)).multilineTextAlignment(.center).foregroundStyle(palette.ink)
                Text(park.dayLabel(best.night.id)).font(.subheadline).foregroundStyle(palette.muted)
                Text("\(best.night.score.value)").font(.system(size:min(heroSize,150),weight:.light,design:.serif)).kerning(3).foregroundStyle(palette.accent)
                    .contentTransition(.numericText(value:Double(best.night.score.value)))
                Text(best.night.score.hasForecast ? best.night.score.band.label : String(localized:"Moon and darkness only")).font(.subheadline).foregroundStyle(palette.ink)
                Text(best.reason).font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                if let closure=best.closure { Label(closure,systemImage:"exclamationmark.triangle").font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.center) }
            }.frame(maxWidth:.infinity)
        }.buttonStyle(.plain)
        .accessibilityElement(children:.combine)
        .accessibilityHint("Opens that night at the park.")
    }
    private func routeContent(_ plan:TripPlan)->SkyMapContent {
        let points=plan.stops.map { SkyMap.position($0.night.park) }
        var seen:[String:Int]=[:]
        let stars=plan.stops.map { stop in
            // A park chosen for several nights gathers a small cluster, as in your constellation.
            let n=seen[stop.night.park.id,default:0]; seen[stop.night.park.id]=n+1
            let base=SkyMap.position(stop.night.park), radius=0.004*Double(n).squareRoot(), angle=Double(n)*2.399963
            return SkyMapContent.Star(id:stop.id,point:CGPoint(x:base.x+radius*cos(angle),y:base.y+radius*sin(angle)),brightness:0.3+0.7*Double(stop.night.score.value)/100,ringed:stop.isBest,label:"")
        }
        // Night to night, only where the nights are back to back and the park changes.
        let edges=zip(plan.stops,plan.stops.dropFirst()).compactMap { a,b in
            b.hopMeters.flatMap { $0>1000 ? (SkyMap.position(a.night.park),SkyMap.position(b.night.park)) : nil }
        }
        let nearby=TripPlanner.candidates(model.parks,latitude:plan.stops[0].night.park.latitude,longitude:plan.stops[0].night.park.longitude,radiusMiles:radius).map(SkyMap.position)
        return SkyMapContent(stars:stars,figures:edges.isEmpty ? [] : [edges],viewport:SkyMapContent.viewport(around:points+nearby),showsInsets:false)
    }
    private func routeSummary(_ plan:TripPlan)->String {
        let parks=Array(NSOrderedSet(array:plan.stops.map(\.night.park.shortName))).compactMap { $0 as? String }
        return String(localized:"Route map: \(parks.joined(separator:", ")).")
    }
}
/// One night of the plan: the date, the park, the score, why, and what to check.
struct TripStopRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let stop: TripStop
    let addToCalendar: ()->Void
    let distance: (Double)->String
    var body: some View {
        let night=stop.night, park=night.park
        VStack(alignment:.leading,spacing:10) {
            NavigationLink { ParkDetailView(park:park,initialDate:night.id) } label:{
                HStack(alignment:.top,spacing:14) {
                    VStack(alignment:.leading,spacing:4) {
                        HStack(spacing:8) {
                            Text(park.dayLabel(night.id)).font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                            if stop.isBest { Text("Best night").font(.caption2.weight(.semibold)).padding(.horizontal,8).padding(.vertical,3).foregroundStyle(palette.nightVision ? palette.ink : Color.black).background(Capsule().fill(palette.accent.opacity(palette.nightVision ? 0.35 : 1))) }
                        }
                        Text(park.shortName).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                        Text(stop.reason).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                        if let hop=stop.hopMeters, hop>1000 { Label(String(localized:"\(distance(hop)) from the night before"),systemImage:"arrow.triangle.turn.up.right.diamond").font(.caption).foregroundStyle(palette.muted) }
                        if !night.score.hasForecast { Text("Moon and darkness only").font(.caption).foregroundStyle(palette.muted) }
                        if let closure=stop.closure { Label(String(localized:"Closure alert: \(closure)"),systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(palette.accent).fixedSize(horizontal:false,vertical:true) }
                    }
                    Spacer(minLength:8)
                    VStack(alignment:.trailing,spacing:0) {
                        Text("\(night.score.value)").font(.system(size:typeSize.isAccessibilitySize ? 34 : 40,weight:.light,design:.serif)).foregroundStyle(palette.accent)
                        Text(night.score.hasForecast ? night.score.band.label : String(localized:"Estimate")).font(.caption2).foregroundStyle(palette.muted)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(spoken)
            .accessibilityHint("Opens that night at the park.")
            Button(action:addToCalendar) { Label("Add to Calendar",systemImage:"calendar.badge.plus").font(.subheadline).frame(minHeight:44) }
                .buttonStyle(.plain).foregroundStyle(palette.accent)
                .accessibilityLabel(String(localized:"Add \(park.shortName) on \(park.dayLabel(night.id)) to Calendar"))
        }.padding(.vertical,14)
        .background { if stop.isBest { RoundedRectangle(cornerRadius:18).fill(palette.accent.opacity(palette.nightVision ? 0.08 : 0.07)).padding(.horizontal,-12) } }
    }
    private var spoken:String {
        let night=stop.night, park=night.park
        var parts=[stop.isBest ? String(localized:"Best night. \(park.dayLabel(night.id))") : park.dayLabel(night.id),park.shortName,
                   String(localized:"\(night.score.value) out of 100, \(night.score.hasForecast ? night.score.band.label : String(localized:"moon and darkness only"))"),stop.reason]
        if let hop=stop.hopMeters, hop>1000 { parts.append(String(localized:"\(distance(hop)) from the night before")) }
        if let closure=stop.closure { parts.append(String(localized:"Closure alert: \(closure)")) }
        return parts.joined(separator:". ")
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
