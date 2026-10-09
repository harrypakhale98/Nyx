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
    /// The subtle double tap: Tonight's answer is a night a reminder would announce.
    @State private var found=0
    /// The park, night and score the hero dial last settled on (`ScoreReveals.key`): the double tap
    /// waits until it is the hero's own, so a new park or ranking waits for its dial too.
    @State private var heroSettledKey:String?
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
    /// Ranked once per update of the page (the body reads it into `best` and passes it down).
    private var best:[Park] { Array(model.ranked(candidates).prefix(5)) }
    @State private var width=0.0
    /// Wide iPad: the night chosen on the best park's river, and whether it is being dragged.
    @State private var riverNight:Date?
    @State private var scrubbing=false
    /// A wide iPad: the answer on the left, the ways to change the question on the right.
    private var wide:Bool { WideLayout.columns(width:width,largeText:typeSize.isAccessibilitySize)==2 }
    private var loading:Bool { DebugScenario.state=="loading" }
    var body: some View {
        let best=self.best
        let empty=best.isEmpty || DebugScenario.state=="empty"
        let worthy=worthyNight(best.first,empty:empty)
        let heroReady=best.first.map { heroSettledKey==revealKey($0) } ?? false
        ScrollView {
            if wide, !loading, !empty, let park=best.first {
                VStack(alignment:.leading,spacing:22) {
                    if !model.startChosen { firstRun }
                    HStack(alignment:.top,spacing:36) {
                        VStack(spacing:26) { hero(park,others:Array(best.dropFirst())); farther(than:park); ahead(park) }.frame(maxWidth:.infinity)
                        VStack(alignment:.leading,spacing:22) { startingPoint(heading:false); more(best); fromHome; extras }.frame(maxWidth:500)
                    }
                    // Where, then when: the week at every park in reach fills the window's lower half.
                    weekAcross
                }.padding(24)
            } else {
                VStack(alignment:.leading,spacing:22) {
                    if !model.startChosen { firstRun }
                    if loading { ConstellationLoader().frame(maxWidth:.infinity) }
                    else if empty { CalmState(symbol:"moon.stars",title:"A little farther from here",message:"No national parks fall inside this radius. Widen it or choose a different starting point.");farther(than:nil);startingPoint(heading:false);fromHome }
                    else if let park=best.first {
                        hero(park,others:Array(best.dropFirst()))
                        farther(than:park)
                        // The answer, then the alternatives; then where "within reach" is measured from.
                        more(best)
                        startingPoint(heading:best.count>1)
                        fromHome
                    }
                    extras
                }.padding(24).readableColumn()
            }
        }.scrollDisabled(scrubbing).onPreferenceChange(RiverScrubbingKey.self) { scrubbing=$0 }
        // `-nyx-scroll 0…1` (DEBUG) opens partway down, for review captures of the starting point.
        .defaultScrollAnchor(DebugScenario.number("-nyx-scroll").map { UnitPoint(x:0.5,y:$0) } ?? (DebugScenario.isEnabled("bottom") ? .bottom : .top))
        .nightKeys(enabled:wide && !empty) { delta in stepRiver(delta) }
        .background(NightBackground(seed:model.homeID,score:best.first.map { model.night($0).score.value },park:best.first,night:best.first.map { model.tonight($0) })).navigationTitle("Tonight").navigationBarTitleDisplayMode(.inline)
            .tabRootToolbar()
            .navigationDestination(for:ZoomRoute.self) { route in ParkDetailView(park:route.park).modifier(ParkTransition(sourceID:route.source,namespace:zoom)).onAppear { ReviewPrompt.noteNightViewed(score:model.night(route.park).score.value) } }
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
            .sensoryFeedback(.impact(weight:.light,intensity:0.8),trigger:found)
            // The double tap is the reveal's last beat, after the landing and any 70/90 pulses.
            .task(id:heroReady ? worthy : nil) { await feelFound(heroReady ? worthy : nil) }
            .measuringWidth($width)
            .refreshable {
                // The shooting star is a highlight: it stays home under Reduce Highlighting Effects.
                if !systemReduceMotion && !forcedReduceMotion && !access.reduceHighlighting && shooting==0 {
                    withAnimation(ShootingStar.launch) { shooting=1 } completion:{ shooting=0 }
                }
                let before=model.forecasts.mapValues(\.updated)
                await model.refresh(candidates,force:true)
                // Said as it is: new forecasts (or ones minutes old), or saved data and why.
                let fetched=model.forecasts.contains { id,forecast in before[id] != forecast.updated }
                let current=model.forecasts.values.contains { Date.now.timeIntervalSince($0.updated)<600 }
                let line: String
                if model.weatherEnabled && (fetched || current) { refreshed+=1; line=String(localized:"Updated") }
                else if !model.weatherEnabled { line=String(localized:"Cloud forecasts are off in Your privacy. Showing saved data.") }
                else { line=String(localized:"Could not reach the forecast. Showing saved data.") }
                // The haptic is felt; this is heard, politely, after anything VoiceOver is already saying.
                NightListener.announce(line,priority:.low)
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
    /// At accessibility sizes the two facts stack as two lines, with no "·" left dangling at a wrap.
    @ViewBuilder private func answerLine(_ park:Park)->some View {
        let day=park.dayLabel(model.night(park).id), radius=Self.distance(model.radiusMiles)
        if typeSize.isAccessibilitySize {
            VStack(spacing:4) {
                Text(day)
                if !model.startChosen { Text("Example: from \(model.originName)") } else { Text("Darkest within \(radius)") }
            }.accessibilityElement(children:.combine)
        } else if !model.startChosen { Text("\(day) · Example: from \(model.originName)") }
        // The card below names where from ("From Joshua Tree", "Near me") and how it is measured.
        else { Text("\(day) · Darkest within \(radius)") }
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
    /// The next seven nights across the parks in reach (`WeekAcrossParks`), wide windows only.
    private var weekAcross: some View {
        let radius=Self.distance(model.radiusMiles)
        let reach=location.latitude != nil ? String(localized:"within \(radius) of you") : String(localized:"within \(radius) of \(model.originName)")
        return WeekAcrossParksPanel(week:.make(model.ranked(candidates).map { model.nights($0,from:model.tonight($0),count:WeekAcrossParks.nights) }),reach:reach)
    }
    private func stepRiver(_ delta:Int) {
        guard let park=best.first else { return }
        let tonight=model.tonight(park), current=riverNight ?? tonight
        let next=park.date(current,addingDays:delta)
        guard next>=tonight, next<park.date(tonight,addingDays:30) else { return }
        withAnimation(systemReduceMotion || forcedReduceMotion ? nil : NyxMotion.spring) { riverNight=next }
    }
    private func hero(_ park:Park,others:[Park])->some View {
        let night=model.night(park)
        return VStack(spacing:10) {
            // The first line is the answer's own context: the night, and from where.
            answerLine(park).font(.caption.weight(.medium)).kerning(typeSize.isAccessibilitySize ? 0 : 1.6).textCase(typeSize.isAccessibilitySize ? nil : .uppercase)
                .foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            // The park as a glass pill; the other parks in reach grow out of it (`ParkPillPicker`).
            ParkPillPicker(park:park,others:others,score:{ model.night($0).score.value },zoom:zoom)
            let basis=night.basisCaption(unavailable:!model.beyondForecast(night))
            CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast,spokenBasis:basis,
                           revealKey:revealKey(park),
                           range:CelestialGauge.modelRange(model.outlook(night),basis:night.basis)) { heroSettledKey=$0 }
                .frame(height:typeSize.isAccessibilitySize ? nil : wide ? 300 : 240)
                .modifier(DepthParallax(depth:0.08))
            // Only the exceptions (no forecast yet, an early look); a full forecast is the norm and goes unsaid.
            // The gauge speaks this line, so VoiceOver does not hear it twice.
            if let basis { Text(basis).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center).accessibilityHidden(true) }
            // A forecast more than six hours old says when it is from.
            let stale=night.score.hasForecast ? night.forecastUpdated.flatMap { Date.now.timeIntervalSince($0)>6*3600 ? $0 : nil } : nil
            // A closure is the one line here that must never be lost in the sky: it sits on a dark scrim.
            if let closure=model.closure(park) {
                if let stale { forecastAsOf(park,stale) }
                Label(closure,systemImage:"exclamationmark.triangle").font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.center)
                .padding(.horizontal,12).padding(.vertical,6).background(Color.black.opacity(0.6),in:RoundedRectangle(cornerRadius:12)) }
            // Nothing listed: the alerts and the forecast's age share one quiet caption, the safety cue kept.
            else if let listed=model.alertFacts(park) { CaveatLine(facts:listed+(stale.map { [String(localized:"forecast from \(park.timestamp($0))")] } ?? [])).padding(.horizontal,12) }
            else {
                if let stale { forecastAsOf(park,stale) }
                Text(model.alertSummary(park)).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center).padding(.horizontal,12)
            }
            if let smoke=model.smokeCaveat(night) { Label(smoke,systemImage:"smoke").font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.center).padding(.horizontal,12) }
            AccessNoteLabel(park:park,alignment:.center).padding(.horizontal,12)
            nudge(park:park,tonight:night)
            fieldOffer(best:park)
        }.frame(maxWidth:.infinity)
    }
    private func forecastAsOf(_ park:Park,_ updated:Date)->some View {
        Text("Forecast as of \(park.timestamp(updated))").font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center)
    }
    /// The hero dial's reveal key for a park tonight.
    private func revealKey(_ park:Park)->String {
        let night=model.night(park)
        return ScoreReveals.key(parkID:park.id,night:park.isoDay(night.id),score:night.score.value)
    }
    /// Tonight's answer when a reminder would announce it (`NotificationScheduler.worthAReminder`),
    /// as "park-day"; nil otherwise, and until a starting point is chosen.
    private func worthyNight(_ best:Park?,empty:Bool)->String? {
        guard model.startChosen, !loading, !empty, let park=best else { return nil }
        let night=model.night(park)
        return NotificationScheduler.worthAReminder(night) ? park.id+"-"+park.isoDay(night.id) : nil
    }
    /// The haptic vocabulary's subtle double tap, once per park and night, 0.8 s after the gauge
    /// has settled (0.6 s without motion), so it never overlaps the count-up's pulses.
    private func feelFound(_ key:String?) async {
        guard let key, DebugScenario.screen == nil, !FoundNights.felt(key) else { return }
        try? await Task.sleep(for:.seconds(systemReduceMotion || forcedReduceMotion ? 0.6 : 0.8))
        guard !Task.isCancelled else { return }
        FoundNights.note(key)
        found+=1
        try? await Task.sleep(for:.milliseconds(120))
        found+=1
    }
    @ViewBuilder private func more(_ best:[Park])->some View {
        if best.count>1 {
            Eyebrow(text:"More skies within reach")
            ForEach(Array(best.dropFirst())) { park in NavigationLink(value:ZoomRoute.row(park)) { ParkRow(night:model.night(park),closure:model.closure(park),week:model.nights(park,from:model.tonight(park),count:7)) }.buttonStyle(.plain).matchedTransitionSource(id:ZoomRoute.row(park).source,in:zoom).hoverEffect(.highlight).draggable(park);Divider().overlay(palette.line) }
            // Only worth saying when a row actually reads "Estimate", as on Parks.
            if best.dropFirst().contains(where:{ model.night($0).basis == .usual }) { Text("Scores marked Estimate have no cloud forecast yet and use each park's usual clouds.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
        }
    }
    /// The sky over the starting point itself, for anyone not travelling tonight: the device's
    /// location only when Near me is already in use, else the chosen city or park. Not on first
    /// run, where the starting point is only an example.
    @ViewBuilder private var fromHome: some View {
        let here=location.latitude.flatMap { lat in location.longitude.map { (latitude:lat,longitude:$0) } }
        if model.startChosen, let origin=HomeSky.origin(location:here,place:model.homePlace,park:model.home) { FromHomePanel(origin:origin,now:model.today) }
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
    /// "From Joshua Tree · 200 mi ⌃" on the first line; how the distance is measured under it, with
    /// Near me trailing that line in full words. Below the alternatives it carries its own heading,
    /// so the headings rotor finds it.
    @ViewBuilder private func startingPoint(heading:Bool)->some View {
        if heading { Eyebrow(text:"Starting point") }
        Panel { VStack(alignment:.leading,spacing:0) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:6) { origin(wraps:false); dot; radiusMenu }
                // A long name, or accessibility sizes: the name wraps and the radius goes underneath.
                VStack(alignment:.leading,spacing:4) { origin(wraps:true); radiusMenu }
            }
            ViewThatFits(in:.horizontal) {
                HStack(spacing:8) { crowFlies; Spacer(minLength:8); locationControl }
                VStack(alignment:.leading,spacing:8) { crowFlies; locationControl }
            }
            if location.denied || DebugScenario.state=="no-location" { Text("Location is off. Choose your city or the park closest to you.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).padding(.top,8) }
            if let message=location.message { Text(message).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).padding(.top,8) }
        }
        // The layouts settle on their first pass; a surrounding animation must not morph one into another.
        .transaction { $0.animation=nil }
        // One container, so the accessibility audit can find the row (`startingPoint`).
        .accessibilityElement(children:.contain).accessibilityIdentifier("startingPoint") }
    }
    /// Heard with the radius it qualifies ("Radius, 200 mi, as the crow flies"), so not read again here.
    private var crowFlies: some View {
        Text("as the crow flies").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).accessibilityHidden(true)
    }
    private var dot: some View { Text(verbatim:"·").font(.subheadline).foregroundStyle(palette.muted).accessibilityHidden(true) }
    private func origin(wraps:Bool)->some View {
        Button { chooseHome=true } label:{
            Group {
                if location.latitude==nil { Label(String(localized:"From \(model.homePlace?.label ?? model.originName)"),systemImage:model.homePlace == nil ? "mappin.and.ellipse" : "building.2") }
                else { Label("From your location",systemImage:"location.fill") }
            }.multilineTextAlignment(.leading).fixedSize(horizontal:!wraps,vertical:true)
        }.font(.subheadline).frame(minHeight:44).contentShape(Rectangle()).accessibilityHint("Choose a city, town or park to start from")
    }
    /// Near me (or Settings when location is off), always in words: it is the main way into location.
    @ViewBuilder private var locationControl:some View {
        if location.locating { ProgressView().accessibilityLabel("Finding your location") }
        else if location.denied { Button { if let url=URL(string:UIApplication.openSettingsURLString) { openURL(url) } } label:{ Label("Settings",systemImage:"location.slash").font(.subheadline).frame(minHeight:30) }.buttonStyle(.bordered).fixedSize().accessibilityLabel("Turn on location in Settings").accessibilityInputLabels([Text("Settings"),Text("Turn on location")]) }
        else if location.latitude==nil { Button { explainLocation=true } label:{ Label("Near me",systemImage:"location").font(.subheadline).frame(minHeight:30) }.buttonStyle(.bordered).fixedSize().accessibilityLabel("Use my location").accessibilityInputLabels([Text("Near me"),Text("Use my location")]) }
    }
    /// The radius as the distance itself in amber with the system's up-down chevrons; a menu of four
    /// distances. A plain label, so "200 mi" sits on the row's text with no control inset of its own.
    private var radiusMenu:some View {
        @Bindable var model=model
        let distance=Self.distance(model.radiusMiles)
        return Menu {
            Picker("Radius",selection:$model.radiusMiles) {
                ForEach([100.0,200,500,1000],id:\.self) { miles in Text(Self.distance(miles)).tag(miles) }
            }.pickerStyle(.inline)
        } label:{
            HStack(spacing:4) {
                Text(distance)
                Image(systemName:"chevron.up.chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .font(.subheadline).foregroundStyle(palette.accent).frame(minWidth:44,minHeight:44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).fixedSize()
        .accessibilityLabel("Radius").accessibilityValue(distance+", "+String(localized:"as the crow flies")).accessibilityInputLabels([Text("Radius"),Text("Distance")])
    }
}
/// The quiet facts under Tonight's dial when nothing is closed: "No closures listed · check alerts
/// before you go · forecast from Oct 8, 1:51 PM" on one line when it fits, wrapped at a dot when it
/// does not, and one fact per line, each a sentence, at accessibility sizes.
struct CaveatLine: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let facts:[String]
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize || facts.count<2 { stacked }
            else {
                ViewThatFits(in:.horizontal) {
                    line(facts)
                    VStack(spacing:2) { line(Array(facts.dropLast())); line([Self.sentence(facts[facts.count-1])]) }
                    stacked
                }
            }
        }
        .font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center)
    }
    /// Each line speaks its facts as sentences, without the dots. (Not one ignoring container over the
    /// `ViewThatFits`: the accessibility audit then finds the unused layouts as empty, too-small nodes.)
    private func line(_ parts:[String])->some View {
        Text(parts.joined(separator:" · ")).lineLimit(1).accessibilityLabel(parts.map(Self.sentence).joined(separator:". "))
    }
    private var stacked: some View {
        VStack(spacing:2) { ForEach(Array(facts.enumerated()),id:\.offset) { _,fact in Text(Self.sentence(fact)).fixedSize(horizontal:false,vertical:true) } }
    }
    /// A fact that starts a line starts with a capital, in either language.
    static func sentence(_ fact:String)->String { fact.prefix(1).uppercased(with:.current)+fact.dropFirst() }
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
#Preview("Caveat • two facts") { CaveatLine(facts:[String(localized:"No closures listed"),String(localized:"check alerts before you go")]).padding(24).frame(width:402).background(.black).preferredColorScheme(.dark) }
#Preview("Caveat • no alerts listed") { CaveatLine(facts:[String(localized:"No alerts listed"),String(localized:"confirm access before you go")]).padding(24).frame(width:402).background(.black).preferredColorScheme(.dark) }
#Preview("Caveat • old forecast, wraps at the last dot") { CaveatLine(facts:[String(localized:"No closures listed"),String(localized:"check alerts before you go"),"forecast from Oct 8, 1:51 PM"]).padding(24).frame(width:402).background(.black).preferredColorScheme(.dark) }
#Preview("Caveat • old forecast, AX5") { CaveatLine(facts:[String(localized:"No closures listed"),String(localized:"check alerts before you go"),"forecast from Oct 8, 1:51 PM"]).padding(24).frame(width:402).background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
#Preview("Caveat • night vision") { CaveatLine(facts:[String(localized:"No closures listed"),String(localized:"check alerts before you go"),"forecast from Oct 8, 1:51 PM"]).padding(24).frame(width:402).background(.black).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark) }
/// The nights Tonight has already marked with the double tap, so each is felt once.
enum FoundNights {
    private static let key="foundNights"
    static func felt(_ night:String,defaults:UserDefaults = .standard)->Bool { (defaults.stringArray(forKey:key) ?? []).contains(night) }
    /// Keeps the last 20, which covers every park in reach for weeks of nights.
    static func note(_ night:String,defaults:UserDefaults = .standard) {
        let list=(defaults.stringArray(forKey:key) ?? []).filter { $0 != night }+[night]
        defaults.set(Array(list.suffix(20)),forKey:key)
    }
}
