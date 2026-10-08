import SwiftUI

struct TonightView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @Environment(\.nyxAccess) private var access
    @State private var shooting=0.0
    @State private var refreshed=0
    @Environment(\.openURL) private var openURL
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(\.scenePhase) private var scenePhase
    private var location:LocationService { model.location }
    @State private var explainLocation=false
    @State private var chooseHome=false
    /// "Near me" chosen in the starting-point sheet: the location explainer follows once it closes.
    @State private var nearMeAfterPicker=false
    @Namespace private var zoom
    private var candidates:[Park] { model.nearby(latitude:location.latitude,longitude:location.longitude) }
    private var best:[Park] { Array(model.ranked(candidates).prefix(5)) }
    @State private var width=0.0
    /// Wide iPad: the night chosen on the best park's river, and whether it is being dragged.
    @State private var riverNight:Date?
    @State private var scrubbing=false
    /// A wide iPad: the answer on the left, the ways to change the question on the right.
    private var wide:Bool { WideLayout.columns(width:width,largeText:typeSize.isAccessibilitySize)==2 }
    private var loading:Bool { DebugScenario.state=="loading" }
    private var empty:Bool { best.isEmpty || DebugScenario.state=="empty" }
    var body: some View {
        ScrollView {
            if wide, !loading, !empty, let park=best.first {
                VStack(alignment:.leading,spacing:22) {
                    if !model.startChosen { firstRun }
                    HStack(alignment:.top,spacing:36) {
                        VStack(spacing:26) { hero(park); farther(than:park); ahead(park) }.frame(maxWidth:.infinity)
                        VStack(alignment:.leading,spacing:22) { startingPoint; more; footnote; extras }.frame(maxWidth:500)
                    }
                }.padding(24)
            } else {
                VStack(alignment:.leading,spacing:22) {
                    if !model.startChosen { firstRun }
                    if loading { ConstellationLoader().frame(maxWidth:.infinity) }
                    else if empty { CalmState(symbol:"moon.stars",title:"A little farther from here",message:"No national parks fall inside this radius. Widen it or choose a different starting point.");farther(than:nil);startingPoint }
                    else if let park=best.first {
                        hero(park)
                        farther(than:park)
                        startingPoint
                        more
                        footnote
                    }
                    extras
                }.padding(24).readableColumn()
            }
        }.scrollDisabled(scrubbing).onPreferenceChange(RiverScrubbingKey.self) { scrubbing=$0 }
        .nightKeys(enabled:wide && !empty) { delta in stepRiver(delta) }
        .background(NightBackground(seed:model.homeID,score:best.first.map { model.night($0).score.value },park:best.first,night:best.first.map { model.tonight($0) })).navigationTitle("Tonight").navigationBarTitleDisplayMode(.inline)
            .tabRootToolbar()
            .navigationDestination(for:Park.self) { park in ParkDetailView(park:park).modifier(ParkTransition(sourceID:park.id,namespace:zoom)).onAppear { ReviewPrompt.noteNightViewed(score:model.night(park).score.value) } }
            .sheet(isPresented:$chooseHome,onDismiss:{ if nearMeAfterPicker { nearMeAfterPicker=false; explainLocation=true } }) {
                NavigationStack { StartingPointPicker(nearMe:{ nearMeAfterPicker=true },selectedParkID:model.homeID,selectedPlace:model.homePlace,locationOff:location.denied || DebugScenario.state=="no-location") { choice in
                    switch choice {
                    case .park(let id): model.choose(parkID:id)
                    case .place(let place): model.choose(place)
                    }
                    location.clear()
                } }.nyxPresentation().presentationDetents([.large])
            }
            .sheet(isPresented:$explainLocation) { PermissionExplainer(symbol:"location",title:"Find a sky nearby",message:"Nyx uses your location once to find parks within a straight-line radius. It stays on this iPhone. You can also choose a city or a park.",action:"Use my location") { explainLocation=false;location.request() }.nyxPresentation() }
            .task(id:model.homeID+(model.homePlace?.id ?? "")+String(model.radiusMiles)+(location.latitude?.description ?? "manual")) { await model.refresh(candidates) }
            // A location found is a starting point chosen.
            .onChange(of:location.latitude != nil) { _,found in if found, DebugScenario.screen == nil { model.startChosen=true } }
            // Back from the background: where you are may have changed, and so may the sky.
            .onChange(of:scenePhase) { _,phase in
                guard phase == .active, DebugScenario.screen == nil else { return }
                location.refreshIfAuthorized()
                if model.lastRefresh.map({ Date.now.timeIntervalSince($0)>3600 }) ?? true { Task { await model.refresh(candidates) } }
            }
            .overlay(alignment:.top) { ShootingStar(progress:shooting).frame(height:170) }
            .sensoryFeedback(.selection,trigger:refreshed)
            .measuringWidth($width)
            .refreshable {
                // The shooting star is a highlight: it stays home under Reduce Highlighting Effects.
                if !systemReduceMotion && !forcedReduceMotion && !access.reduceHighlighting && shooting==0 {
                    withAnimation(.spring(response:0.9,dampingFraction:1)) { shooting=1 } completion:{ shooting=0 }
                }
                await model.refresh(candidates,force:true);refreshed+=1
            }
    }
    /// First run, until a starting point is chosen: the question, asked in place, with no permission
    /// up front. The answer below is labelled an example until then.
    private var firstRun: some View {
        Panel { VStack(alignment:.leading,spacing:14) {
            Text("Where do you start from?").font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
            Text(location.denied ? "Location is off. Choose your city or the park closest to you." : "Nyx measures straight-line distances from there. Until you choose, the night below is an example.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            ViewThatFits(in:.horizontal) {
                HStack(spacing:12) { firstRunButtons }
                VStack(alignment:.leading,spacing:12) { firstRunButtons }
            }
        } }
    }
    @ViewBuilder private var firstRunButtons: some View {
        if !location.denied {
            Button { explainLocation=true } label:{ Label("Near me",systemImage:"location").frame(minHeight:30) }
                .buttonStyle(.borderedProminent).foregroundStyle(Color.black)
                .accessibilityLabel("Use my location").accessibilityInputLabels([Text("Near me"),Text("Use my location")])
        }
        Button { chooseHome=true } label:{ Label("Choose a starting point",systemImage:"mappin.and.ellipse").frame(minHeight:30) }
            .buttonStyle(.bordered).accessibilityInputLabels([Text("Choose a starting point"),Text("Choose a city"),Text("Choose a park")])
    }
    /// The line above the answer, all data: the night, and where "in reach" is measured from.
    /// Never "nearby" for a starting park or city; an example until a starting point is chosen.
    private func answerLine(_ park:Park)->Text {
        let day=park.dayLabel(model.night(park).id), radius=Self.distance(model.radiusMiles)
        if !model.startChosen { return Text("\(day) · Example: from \(model.originName)") }
        if location.latitude != nil { return Text("\(day) · Darkest within \(radius) of you") }
        return Text("\(day) · Darkest within \(radius) of \(model.originName)")
    }
    private static func distance(_ miles:Double)->String { Measurement(value:miles,unit:UnitLength.miles).formatted(.measurement(width:.abbreviated,usage:.road)) }
    /// A thin answer (fewer than three parks in reach, or a bright sky at the best of them) points to
    /// the darkest park within 500 miles when it scores higher tonight. A tap widens the radius.
    @ViewBuilder private func farther(than best:Park?)->some View {
        let wider=500.0
        if model.radiusMiles<wider, candidates.count<3 || (best?.bortleEstimate ?? 9)>=5 {
            let inReach=Set(candidates.map(\.id)), bestScore=best.map { model.night($0).score.value } ?? -1
            if let far=model.ranked(model.nearby(latitude:location.latitude,longitude:location.longitude,radiusMiles:wider)).first(where:{ !inReach.contains($0.id) }),
               model.night(far).score.value>bestScore {
                Button { withAnimation(systemReduceMotion || forcedReduceMotion ? nil : NyxMotion.spring) { model.radiusMiles=wider } } label:{
                    HStack(spacing:8) {
                        Image(systemName:"scope").imageScale(.small).accessibilityHidden(true)
                        Text("Darker within \(Self.distance(wider)): \(far.shortName), \(model.night(far).score.value) tonight").multilineTextAlignment(.leading)
                        Image(systemName:"chevron.forward").imageScale(.small).font(.caption.weight(.semibold)).accessibilityHidden(true)
                    }
                    .font(.subheadline).foregroundStyle(palette.accent).padding(.vertical,10).padding(.horizontal,16).frame(minHeight:44)
                    .background(Capsule().fill(palette.accent.opacity(palette.nightVision ? 0 : 0.1))).overlay(Capsule().stroke(palette.accent.opacity(0.35),lineWidth:0.5))
                }.buttonStyle(.plain).frame(maxWidth:.infinity)
                .accessibilityHint("Widens the radius to \(Self.distance(wider)).")
            }
        }
    }
    /// Wide iPad: where, then when. The best park's next thirty nights beside the answer, with the
    /// chosen night one tap away. (On iPhone the river lives on the park's page.)
    private func ahead(_ park:Park)->some View {
        let tonight=model.tonight(park), nights=model.nights(park,from:tonight,count:30)
        let chosen=riverNight.flatMap { id in nights.first { $0.id==id } }
        return Panel { VStack(alignment:.leading,spacing:14) {
            TimeRiver(nights:nights,selected:Binding(get:{ chosen?.id ?? tonight },set:{ riverNight=$0 }),outlooks:model.outlooks(nights),markers:model.markers(nights))
            if let chosen, chosen.id != tonight {
                capsule(text:String(localized:"Open \(park.dayLabel(chosen.id)) at \(park.shortName)"),hint:"Opens that night at the park.") { ParkDetailView(park:park,initialDate:chosen.id) } icon:{ Image(systemName:"moon.stars").imageScale(.small) }
            }
        } }
    }
    private func stepRiver(_ delta:Int) {
        guard let park=best.first else { return }
        let tonight=model.tonight(park), current=riverNight ?? tonight
        let next=park.date(current,addingDays:delta)
        guard next>=tonight, next<park.date(tonight,addingDays:30) else { return }
        withAnimation(systemReduceMotion || forcedReduceMotion ? nil : NyxMotion.spring) { riverNight=next }
    }
    private func hero(_ park:Park)->some View {
        let night=model.night(park)
        return VStack(spacing:10) {
            // The first line is the answer's own context: the night, and from where.
            answerLine(park).font(.caption.weight(.medium)).kerning(typeSize.isAccessibilitySize ? 0 : 1.6).textCase(typeSize.isAccessibilitySize ? nil : .uppercase)
                .foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            NavigationLink(value:park) { HStack { Text(park.shortName).font(.system(.title2,design:.serif));Image(systemName:"arrow.up.right").font(.subheadline).accessibilityHidden(true) }.padding(.vertical,14).padding(.horizontal,22).modifier(ParkPill()) }.buttonStyle(.plain).matchedTransitionSource(id:park.id,in:zoom)
                .hoverEffect(.lift)
            CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast).frame(height:typeSize.isAccessibilitySize ? nil : wide ? 300 : 240)
                .modifier(DepthParallax(depth:0.08))
            Text(night.basisCaption(unavailable:!model.beyondForecast(night)) ?? String(localized:"Forecast included")).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            // A forecast more than six hours old says when it is from.
            if night.score.hasForecast, let updated=night.forecastUpdated, Date.now.timeIntervalSince(updated)>6*3600 {
                Text("Forecast as of \(park.timestamp(updated))").font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            }
            // A closure is the one line here that must never be lost in the sky: it sits on a dark scrim.
            if let closure=model.closure(park) { Label(closure,systemImage:"exclamationmark.triangle").font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.center)
                .padding(.horizontal,12).padding(.vertical,6).background(Color.black.opacity(0.6),in:RoundedRectangle(cornerRadius:12)) }
            else { Text(model.alertSummary(park)).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center).padding(.horizontal,12) }
            if let smoke=model.smokeCaveat(night) { Label(smoke,systemImage:"smoke").font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.center).padding(.horizontal,12) }
            AccessNoteLabel(park:park,alignment:.center).padding(.horizontal,12)
            nudge(park:park,tonight:night)
            fieldOffer(best:park)
        }.frame(maxWidth:.infinity)
    }
    @ViewBuilder private var more: some View {
        if best.count>1 {
            Eyebrow(text:"More skies within reach")
            ForEach(Array(best.dropFirst())) { park in NavigationLink(value:park) { ParkRow(night:model.night(park),closure:model.closure(park),week:model.nights(park,from:model.tonight(park),count:7)) }.buttonStyle(.plain).matchedTransitionSource(id:park.id,in:zoom).hoverEffect(.highlight);Divider().overlay(palette.line) }
        }
    }
    private var footnote: some View {
        Text("Each park uses its own local date. Scores without a full forecast can change when one arrives.").font(.caption).foregroundStyle(palette.muted)
    }
    @ViewBuilder private var extras: some View {
        if DebugScenario.state=="error" || DebugScenario.state=="offline" || (model.weatherEnabled && candidates.contains { model.staleForecasts.contains($0.id) }) { Panel { Label("Offline calculations are ready. Refresh when a connection returns.",systemImage:"wifi.slash").font(.subheadline).foregroundStyle(palette.muted) } }
    }
    /// One quiet line under the hero, never more, the most significant first: a lunar eclipse the
    /// best park can see within the next three nights, then a major meteor shower's peak worth the
    /// trip there (at least 20 an hour with the Moon down), then a clearly darker night ahead.
    @ViewBuilder private func nudge(park:Park,tonight:Night)->some View {
        if let event=upcomingEvent(park) {
            capsule(text:event.text,hint:"Opens that night at the park.") { ParkDetailView(park:park,initialDate:event.night.id) } icon:{
                SkyGlyph(SkyGlyph.Kind(event.glyph),color:palette.accent).frame(width:15,height:15)
            }
        } else { darkerAhead(than:tonight) }
    }
    /// Field mode, offered after sunset when this iPhone is already known to be in or near a park
    /// (location is never asked for just for this), or while a Stargazing Focus is on.
    @ViewBuilder private func fieldOffer(best:Park)->some View {
        if FieldPresenter.supported { fieldOfferButton(best:best) }
    }
    @ViewBuilder private func fieldOfferButton(best:Park)->some View {
        let now=DebugScenario.date ?? Date.now
        let here=location.latitude.flatMap { lat in location.longitude.flatMap { model.fieldPark(latitude:lat,longitude:$0) } }
        let focus=StargazingFocus.offersField() || DebugScenario.state=="stargazing"
        if let here, Self.isEvening(here,model.night(here),now:now) {
            fieldButton(park:here,text:String(localized:"You're at \(here.shortName). Start field mode"))
        } else if focus, Self.isEvening(best,model.night(best),now:now) || DebugScenario.state=="stargazing" {
            fieldButton(park:best,text:String(localized:"Stargazing Focus is on. Field mode at \(best.shortName)"))
        }
    }
    /// From sunset until the night is over.
    private static func isEvening(_ park:Park,_ night:Night,now:Date)->Bool {
        guard let sunset=night.sky.sunset else { return false }
        return now>=sunset && !FieldNight.isOver(night.sky,at:now)
    }
    private func fieldButton(park:Park,text:String)->some View {
        Button { FieldPresenter.present(park:park,model:model,from:commands?.topController ?? SceneCommands.top(in:nil)) } label:{
            HStack(spacing:8) {
                Image(systemName:"scope").imageScale(.small).accessibilityHidden(true)
                Text(text).multilineTextAlignment(.leading)
                Image(systemName:"chevron.forward").imageScale(.small).font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .font(.subheadline).foregroundStyle(palette.accent).padding(.vertical,10).padding(.horizontal,16).frame(minHeight:44)
            .background(Capsule().fill(palette.accent.opacity(palette.nightVision ? 0 : 0.1))).overlay(Capsule().stroke(palette.accent.opacity(0.35),lineWidth:0.5))
        }.buttonStyle(.plain).padding(.top,4)
        .accessibilityHint("Opens field mode: a dark red screen with tonight's milestones and where to look.")
    }
    private func upcomingEvent(_ park:Park)->(night:Night,glyph:WhatsUp.Events.Glyph,text:String)? {
        let first=model.tonight(park)
        let nights=model.nights(park,from:first,count:4)
        func when(_ night:Night)->String { night.id==first ? String(localized:"tonight") : String(localized:"on \(park.dayLabel(night.id))") }
        for night in nights {
            if let eclipse=model.events(night).eclipse, let visible=eclipse.visible {
                return (night,.eclipse,String(localized:"\(WhatsUp.eclipseName(eclipse.eclipse)) \(when(night)) at \(park.shortName), \(park.time(visible.start))"))
            }
        }
        for night in nights {
            if let shower=model.events(night).reminderShower {
                return (night,.meteors,String(localized:"\(shower.shower.localizedName) peak \(when(night)): \(WhatsUp.rateText(shower.hourlyRate)) at \(park.shortName)"))
            }
        }
        return nil
    }
    /// Tonight answers where; this answers when. The darkest of the next six nights across every
    /// park in reach, shown only when it is clearly better than tonight's best.
    @ViewBuilder private func darkerAhead(than tonight:Night)->some View {
        let ahead=candidates.flatMap { park in model.nights(park,from:park.date(model.tonight(park),addingDays:1),count:6) }
            .reduce(nil as Night?) { best,night in best.map { night.score.value>$0.score.value ? night : $0 } ?? night }
        if let ahead, ahead.score.value>=tonight.score.value+5 {
            capsule(text:String(localized:"Darker on \(ahead.park.dayLabel(ahead.id)): \(ahead.score.value) at \(ahead.park.shortName)"),hint:"Opens that night at the park.") {
                ParkDetailView(park:ahead.park,initialDate:ahead.id)
            } icon:{ Image(systemName:"moon.stars").imageScale(.small) }
            // A darker night somewhere the car cannot go says so before the tap, not after.
            if !ahead.park.drivable { AccessNoteLabel(park:ahead.park,alignment:.center).padding(.horizontal,12) }
        }
    }
    private func capsule<Destination:View,Icon:View>(text:String,hint:LocalizedStringKey,@ViewBuilder destination:@escaping ()->Destination,@ViewBuilder icon:()->Icon)->some View {
        NavigationLink { destination() } label:{
            HStack(spacing:8) {
                icon().accessibilityHidden(true)
                Text(text).multilineTextAlignment(.leading)
                Image(systemName:"chevron.forward").imageScale(.small).font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .font(.subheadline).foregroundStyle(palette.accent).padding(.vertical,10).padding(.horizontal,16).frame(minHeight:44)
            .background(Capsule().fill(palette.accent.opacity(palette.nightVision ? 0 : 0.1))).overlay(Capsule().stroke(palette.accent.opacity(0.35),lineWidth:0.5))
        }.buttonStyle(.plain).padding(.top,4)
        .accessibilityHint(hint)
    }
    /// The starting point is a chosen park, a city or town, or the device location: one at a time.
    private var startingPoint:some View {
        Panel { VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.center) {
                Button { chooseHome=true } label:{
                    if location.latitude==nil { Label(String(localized:"From \(model.homePlace?.label ?? model.originName)"),systemImage:model.homePlace == nil ? "mappin.and.ellipse" : "building.2") }
                    else { Label("From your location",systemImage:"location.fill") }
                }.font(.subheadline).frame(minHeight:44).contentShape(Rectangle()).accessibilityHint("Choose a city, town or park to start from")
                Spacer(minLength:8)
                if location.locating { ProgressView().accessibilityLabel("Finding your location") }
                else if location.denied { Button { if let url=URL(string:UIApplication.openSettingsURLString) { openURL(url) } } label:{ Label("Settings",systemImage:"location.slash").font(.subheadline) }.buttonStyle(.bordered).accessibilityLabel("Turn on location in Settings").accessibilityInputLabels([Text("Settings"),Text("Turn on location")]) }
                else if location.latitude==nil { Button { explainLocation=true } label:{ Label("Near me",systemImage:"location").font(.subheadline) }.buttonStyle(.bordered).accessibilityLabel("Use my location").accessibilityInputLabels([Text("Near me"),Text("Use my location")]) }
            }
            ViewThatFits(in:.horizontal) {
                HStack { radiusPicker;Text("as the crow flies").font(.caption).foregroundStyle(palette.muted) }
                VStack(alignment:.leading,spacing:8) { radiusPicker;Text("as the crow flies").font(.caption).foregroundStyle(palette.muted) }
            }
            if location.denied || DebugScenario.state=="no-location" { Text("Location is off. Choose your city or the park closest to you.").font(.caption).foregroundStyle(palette.muted) }
            if let message=location.message { Text(message).font(.caption).foregroundStyle(palette.muted) }
        } }
    }
    private var radiusPicker:some View {
        @Bindable var model=model
        return Picker("Radius",selection:$model.radiusMiles) {
            ForEach([100.0,200,500,1000],id:\.self) { miles in Text(Measurement(value:miles,unit:UnitLength.miles),format:.measurement(width:.abbreviated,usage:.road)).fixedSize().tag(miles) }
        }.pickerStyle(.menu).fixedSize(horizontal:true,vertical:false)
    }
}
/// Liquid Glass normally; a solid dark capsule in night vision, where the red filter
/// flattens glass toward the text colour and costs contrast.
private struct ParkPill:ViewModifier {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content:Content)->some View {
        if palette.nightVision || reduceTransparency {
            content.background(Color.black,in:Capsule()).overlay(Capsule().stroke(palette.line,lineWidth:0.8))
        // Tinted like the panels, so the name keeps its contrast over a bright stretch of the Milky Way.
        } else { content.glassEffect(.regular.tint(palette.panel.opacity(0.5))) }
    }
}
struct PermissionExplainer: View {
    @Environment(\.dismiss) private var dismiss
    let symbol:String
    let title:LocalizedStringKey
    let message:LocalizedStringKey
    let action:LocalizedStringKey
    let proceed:()->Void
    var body: some View {
        NavigationStack { ScrollView { VStack(spacing:24) { CalmState(symbol:symbol,title:title,message:message);Button(action,action:proceed).buttonStyle(.borderedProminent).foregroundStyle(Color.black);Button("Continue without it") { dismiss() } }.padding(24) }.background(Color.black).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { dismiss() } } } }.presentationDetents([.medium,.large])
    }
}
#Preview("Tonight") { NavigationStack { TonightView() }.environment(PlanModel()).preferredColorScheme(.dark) }
