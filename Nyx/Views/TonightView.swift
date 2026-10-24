import SwiftUI

struct TonightView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
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
    /// The answer's "Darkest within 200 mi" was tapped: the page moves to where that reach is set.
    @State private var toStart=0
    /// A save from a park row's menu could not be stored.
    @State private var saveFailed=false
    @Namespace private var zoom
    private func nearMe() { StartingPointSheets.nearMe(model) { explainLocation=true } }
    private var candidates:[Park] { reach().places }
    /// Everything in reach (`PlanModel.placesInReach`), as Plan's best nights and the trip planner see it.
    private func reach(radiusMeters:Double?=nil)->(places:[Park],world:Bool) { model.placesInReach(radiusMeters:radiusMeters) }
    private var from:(latitude:Double,longitude:Double)? { model.reachOrigin }
    /// Ranked once per update of the page (the body reads it into `best` and passes it down). Abroad a
    /// radius can hold hundreds of places: until their nights are worked out off the main thread
    /// (`prepared`), the page ranks a shortlist (`TonightReach.shortlist`), never hundreds at once.
    private func best(_ all:[Park])->[Park] { Array(model.ranked(pool(all)).prefix(5)) }
    private func pool(_ all:[Park])->[Park] {
        all.count<=TonightReach.shortlistSize || prepared==TonightReach.key(all) ? all : TonightReach.shortlist(all,latitude:from?.latitude ?? 0,longitude:from?.longitude ?? 0)
    }
    /// The places in reach whose tonight has been worked out in the background (`TonightReach.key`).
    @State private var prepared:String?
    /// The same for the places a wider radius would add (`farther(than:shortlist:)`).
    @State private var widerPrepared:String?
    /// The places' 30 nights behind "Darker on…" (`NightVerdict.horizon`), worked out off the main thread first.
    @State private var aheadPrepared:String?
    /// The nearest dark sky when the places in reach are bright or absent (`DarkerSky`), for the
    /// key it was worked out for; worked out off the main thread from the bundled light map.
    @State private var darkerSky:(key:String,offer:DarkerSky.Offer?)?
    @State private var width=0.0
    /// Wide iPad: the night chosen on the best park's river, with that park, and whether it is being
    /// dragged. Kept with its park, so a new best park (another radius or starting point) starts at
    /// its own tonight rather than carrying the old park's date.
    @State private var riverNight:RiverChoice?
    @State private var scrubbing=false
    /// A wide iPad: the answer on the left, the ways to change the question on the right.
    private var wide:Bool { WideLayout.columns(width:width,largeText:typeSize.isAccessibilitySize)==2 }
    /// The world catalogue abroad, or the offline caches still being read after the first frame
    /// (`PlanModel.cachesPending`): the loader, never a score those reads are about to change.
    private var loading:Bool { DebugScenario.state=="loading" || awaitingWorld || model.cachesPending }
    /// From outside the US the answer weighs the world catalogue, read off the main thread from launch:
    /// until it is ready the page shows the loader, never the national parks' empty state or a US-only
    /// answer that would change a moment later.
    private var awaitingWorld:Bool {
        guard !model.catalogIsReady, let from else { return false }
        return !USOutline.contains(latitude:from.latitude,longitude:from.longitude)
    }
    var body: some View {
        let all=candidates
        let best=self.best(all)
        let widerList=widerShortlist(than:best.first,inReach:all)
        let empty=best.isEmpty || DebugScenario.state=="empty"
        let worthy=worthyNight(best.first,empty:empty)
        let heroReady=best.first.map { heroSettledKey==revealKey($0) } ?? false
        ScrollViewReader { proxy in
        ScrollView {
            if wide, !loading, !empty, let park=best.first {
                VStack(alignment:.leading,spacing:22) {
                    if !model.startChosen { firstRun }
                    // The two columns meet at iPhone Duo's fold on its inner display, half open or flat.
                    FoldColumns(narrow:.trailing,narrowMax:500,spacing:36) {
                        VStack(spacing:26) { GoingPanel(hero:park); hero(park,others:Array(best.dropFirst())); farther(than:park,shortlist:widerList); darkArea(all); ahead(park) }.frame(maxWidth:.infinity)
                        VStack(alignment:.leading,spacing:22) { StartingPointPanel(choose:{ chooseHome=true },nearMe:nearMe).id(Self.startID); more(best); fromHome(hero:park); LookingBackPanel(); extras }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    // Where, then when: the week at every park in reach fills the window's lower half.
                    weekAcross
                }.padding(NyxMetrics.pagePadding).readableColumn(WideLayout.twoColumnMaximum)
            } else {
                VStack(alignment:.leading,spacing:22) {
                    if !model.startChosen { firstRun }
                    // A night the person said they are going to leads: their own plan before tonight's answer.
                    // At accessibility sizes it follows the answer, so the score stays on the first screen.
                    if !loading, !typeSize.isAccessibilitySize { GoingPanel(hero:best.first) }
                    if loading { ConstellationLoader().frame(maxWidth:.infinity) }
                    else if empty { CalmState(symbol:"moon.stars",title:"A little farther from here",message:emptyMessage);farther(than:nil,shortlist:widerList);darkArea(all);StartingPointPanel(choose:{ chooseHome=true },nearMe:nearMe).id(Self.startID);fromHome(hero:nil) }
                    else if let park=best.first {
                        hero(park,others:Array(best.dropFirst()))
                        if typeSize.isAccessibilitySize { GoingPanel(hero:park) }
                        farther(than:park,shortlist:widerList)
                        darkArea(all)
                        // The answer, then the alternatives; then where "within reach" is measured from.
                        more(best)
                        StartingPointPanel(heading:best.count>1,choose:{ chooseHome=true },nearMe:nearMe).id(Self.startID)
                        fromHome(hero:park)
                        LookingBackPanel()
                    }
                    extras
                }.padding(24).readableColumn()
            }
        }.scrollDisabled(scrubbing).onPreferenceChange(RiverScrubbingKey.self) { scrubbing=$0 }
        // The fold, read on the scroll view itself so the columns keep it however far the page scrolls.
        .foldSource()
        // `-nyx-scroll 0…1` (DEBUG) opens partway down, for review captures of the starting point.
        .defaultScrollAnchor(DebugScenario.number("-nyx-scroll").map { UnitPoint(x:0.5,y:$0) } ?? (DebugScenario.isEnabled("bottom") ? .bottom : .top))
        .onChange(of:toStart) { withAnimation(reduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo(Self.startID,anchor:.center) } }
        }
        .nightKeys(enabled:wide && !empty) { delta in stepRiver(delta) }
        .background(NightBackground(seed:model.homeID,score:best.first.map { model.night($0).score.value },park:best.first,night:best.first.map { model.tonight($0) })).navigationTitle("Tonight").navigationBarTitleDisplayMode(.inline)
            .tabRootToolbar()
            // ⌘R's note says a forecast's time as the pull does, in the answer's own time.
            .environment(\.refreshTimeZone,best.first?.timeZone)
            .navigationDestination(for:ZoomRoute.self) { route in ParkDetailView(park:route.park).modifier(ParkTransition(sourceID:route.source,namespace:zoom)).onAppear { ReviewPrompt.noteNightViewed(score:model.night(route.park).score.value) } }
            .modifier(StartingPointSheets(choosing:$chooseHome,explaining:$explainLocation))
            .parkSaveAlert(isPresented:$saveFailed,journalUnavailable:model.journalUnavailable)
            // Keyed on the places in reach, not the raw fix: a location that moves a few metres, or a
            // catalogue that arrives with nothing new in range, never cancels and re-sends the request.
            // The places a wider radius would add: their nights worked out off the main thread before they are ranked.
            .task(id:TonightReach.key(widerList)) {
                let list=widerList
                guard !list.isEmpty else { return }
                await model.prepareNights(list,count:1)
                if !Task.isCancelled { widerPrepared=TonightReach.key(list) }
            }
            .task(id:loading ? nil : darkerSkyKey(all)) {
                guard let key=darkerSkyKey(all), let from else { return }
                let radius=model.radiusMeters, darkest=all.map(\.bortleEstimate).min()
                let offer=await Task.detached(priority:.utility) { DarkerSky.offer(from:from,radiusMeters:radius,darkestInReach:darkest) }.value
                if !Task.isCancelled { darkerSky=(key,offer) }
            }
            // "Darker on…" weighs each place's next 30 nights, as Best nights does: their astronomy is
            // worked out off the main thread, and the capsule waits for it rather than hitch the first frame.
            .task(id:loading ? nil : TonightReach.key(aheadPool)) {
                let pool=aheadPool
                guard !loading, !pool.isEmpty else { return }
                await model.prepareNights(pool,count:NightVerdict.horizon)
                if !Task.isCancelled { aheadPrepared=TonightReach.key(pool) }
            }
            .task(id:TonightReach.key(all)) {
                // Hundreds of places in reach (abroad): tonight at each, worked out off the main thread, before ranking them all.
                if all.count>TonightReach.shortlistSize {
                    await model.prepareNights(all,count:1)
                    prepared=TonightReach.key(all)
                }
                await model.refresh(all)
            }
            // The answer here is the one the widgets and Apple Watch follow too (`PlanModel.tonightPickID`):
            // once a starting point is chosen, and never one the loader is about to replace. Stamped
            // again when the night turns over (`model.today`), so the same place picked again tonight
            // is followed tonight rather than expiring with last night's pick.
            .onChange(of:loading ? nil : TonightPickKey(id:model.startChosen && !empty ? best.first?.id : nil,night:model.today),initial:true) { _,key in
                if let key, DebugScenario.screen == nil { model.tonightPickID=key.id }
            }
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
                if !reduceMotion && !access.reduceHighlighting && shooting==0 {
                    withAnimation(ShootingStar.launch) { shooting=1 } completion:{ shooting=0 }
                }
                let before=model.forecasts.mapValues(\.updated)
                await model.refresh(candidates,force:true)
                // Said as it is: new forecasts (or ones minutes old), one too recent to ask about again, or saved data and why.
                let outcome=RefreshOutcome.of(model,before:before)
                if outcome == .updated { refreshed+=1 }
                // In the answer's own time, as its "Forecast as of" caption.
                let line=outcome.line(in:best.first?.timeZone ?? .current)
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
            Button { nearMe() } label:{ Label("Near me",systemImage:"location").frame(minHeight:30) }
                .secondaryAction()
                .accessibilityLabel("Use my location").accessibilityInputLabels([Text("Near me"),Text("Use my location")])
        }
        Button { chooseHome=true } label:{ Label("Choose a starting point",systemImage:"mappin.and.ellipse").frame(minHeight:30) }
            .secondaryAction().accessibilityInputLabels([Text("Choose a starting point"),Text("Choose a city"),Text("Choose a park")])
    }
    /// Where the starting point and its radius are set (`StartingPointPanel`), for the answer's line to lead to.
    private static let startID="startingPoint"
    /// The hero dial's side at accessibility sizes: the numeral stays over 80 pt inside it.
    private static let accessibleDial=200.0
    /// The answer's line, and the way to what it names: a tap moves the page to the starting point and
    /// its radius, which sit below the answer and its alternatives.
    private func reachLine(_ park:Park)->some View {
        Button { toStart+=1 } label:{
            // The small arrow says the line leads somewhere; the target reaches 44 pt without moving the line.
            HStack(alignment:.firstTextBaseline,spacing:5) {
                answerLine(park)
                if !typeSize.isAccessibilitySize { Image(systemName:"arrow.down").font(.caption2.weight(.semibold)).accessibilityHidden(true) }
            }
            .padding(.vertical,14).contentShape(Rectangle()).padding(.vertical,-14)
        }.buttonStyle(.plain)
        .accessibilityHint("Shows the starting point and radius.")
    }
    /// The line above the answer, all data: the night, and where "in reach" is measured from.
    /// Never "nearby" for a starting park or city; an example until a starting point is chosen.
    /// At accessibility sizes the two facts stack as two lines, with no "·" left dangling at a wrap.
    @ViewBuilder private func answerLine(_ park:Park)->some View {
        let day=park.dayLabel(model.night(park).id), radius=SearchRadius.label(model.radiusMeters)
        if typeSize.isAccessibilitySize {
            VStack(spacing:4) {
                Text(day)
                if !model.startChosen { Text("Example: from \(model.originName)") } else { Text("Darkest within \(radius)") }
            }.accessibilityElement(children:.combine)
        } else if !model.startChosen { Text("\(day) · Example: from \(model.originName)") }
        // The card below names where from ("From Joshua Tree", "Near me") and how it is measured.
        else { Text("\(day) · Darkest within \(radius)") }
    }
    /// The places a wider radius would add, when the answer is thin (fewer than three parks in
    /// reach, or a bright sky at the best of them); empty otherwise. Abroad, a shortlist.
    private func widerShortlist(than best:Park?,inReach current:[Park])->[Park] {
        guard model.radiusMeters<SearchRadius.wider(), current.count<3 || (best?.bortleEstimate ?? 9)>=5 else { return [] }
        let inReach=Set(current.map(\.id))
        let wide=reach(radiusMeters:SearchRadius.wider()).places.filter { !inReach.contains($0.id) }
        return wide.count>TonightReach.shortlistSize ? TonightReach.shortlist(wide,latitude:from?.latitude ?? 0,longitude:from?.longitude ?? 0) : wide
    }
    /// A thin answer points to the darkest park within 500 miles (800 km) when it scores higher
    /// tonight. A tap widens the radius. Ranked only once the shortlist's nights have been worked
    /// out off the main thread (`widerPrepared`); until then nothing is offered.
    @ViewBuilder private func farther(than best:Park?,shortlist:[Park])->some View {
        let wider=SearchRadius.wider()
        if !shortlist.isEmpty, widerPrepared==TonightReach.key(shortlist) {
            let bestScore=best.map { model.night($0).score.value } ?? -1
            if let far=model.ranked(shortlist).first,
               model.night(far).score.value>bestScore {
                Button { withAnimation(reduceMotion ? nil : NyxMotion.spring) { model.radiusMeters=wider } } label:{
                    HStack(spacing:8) {
                        Image(systemName:"scope").imageScale(.small).accessibilityHidden(true)
                        Text("Darker within \(SearchRadius.label(wider)): \(far.shortName), \(model.night(far).score.value) tonight").multilineTextAlignment(.leading)
                        Image(systemName:"chevron.forward").imageScale(.small).font(.caption.weight(.semibold)).accessibilityHidden(true)
                    }
                }.buttonStyle(.capsuleAction).frame(maxWidth:.infinity)
                .accessibilityHint("Widens the radius to \(SearchRadius.label(wider)).")
            }
        }
    }
    /// What the nearest dark sky depends on: where from (to about 100 m), the radius, and the darkest
    /// class in reach. Nil before there is a starting point or when a place in reach is dark already.
    private func darkerSkyKey(_ all:[Park])->String? {
        guard let from else { return nil }
        let darkest=all.map(\.bortleEstimate).min()
        guard DarkerSky.needed(darkestInReach:darkest) != nil else { return nil }
        return String(format:"%.3f,%.3f,%.0f,%d",from.latitude,from.longitude,model.radiusMeters,darkest ?? 0)
    }
    /// The nearest dark sky (`DarkerSkyPanel`) once worked out for what is in reach now; nothing
    /// while it is being worked out, so a stale pointer never shows beside a new answer.
    @ViewBuilder private func darkArea(_ all:[Park])->some View {
        if let darkerSky, darkerSky.key==darkerSkyKey(all), let offer=darkerSky.offer { DarkerSkyPanel(offer:offer) }
    }
    /// Wide iPad: where, then when. The best park's next thirty nights beside the answer, with the
    /// chosen night one tap away. (On iPhone the river lives on the park's page.)
    private func ahead(_ park:Park)->some View {
        let tonight=model.tonight(park), nights=model.nights(park,from:tonight,count:30)
        let chosen=riverNight?.night(at:park).flatMap { id in nights.first { $0.id==id } }
        return Panel { VStack(alignment:.leading,spacing:14) {
            TimeRiver(nights:nights,selected:Binding(get:{ chosen?.id ?? tonight },set:{ riverNight=RiverChoice(parkID:park.id,night:$0) }),outlooks:model.outlooks(nights),markers:model.markers(nights))
            if let chosen, chosen.id != tonight {
                capsule(text:String(localized:"Open \(park.dayLabel(chosen.id)) at \(park.shortName)"),hint:"Opens that night at the park.") { ParkDetailView(park:park,initialDate:chosen.id) } icon:{ Image(systemName:"moon.stars").imageScale(.small) }
            }
        } }
    }
    /// The next seven nights across the parks in reach (`WeekAcrossParks`), wide windows only.
    private var weekAcross: some View {
        let radius=SearchRadius.label(model.radiusMeters)
        let reach=location.latitude != nil ? String(localized:"within \(radius) of you") : String(localized:"within \(radius) of \(model.originName)")
        let closures=Dictionary(aheadPool.compactMap { park in model.closure(park).map { (park.id,$0) } },uniquingKeysWith:{ first,_ in first })
        return WeekAcrossParksPanel(week:.make(aheadPool.map { model.nights($0,from:model.tonight($0),count:WeekAcrossParks.nights) },closures:closures),reach:reach)
    }
    /// The places whose coming nights are looked at (the darker night ahead, the week across parks):
    /// all of them in the US as before; abroad, the twelve best tonight, so a radius of hundreds of
    /// places never asks for thousands of nights.
    private var aheadPool:[Park] {
        let ranked=model.ranked(pool(candidates))
        return reach().world ? Array(ranked.prefix(TonightReach.aheadSize)) : ranked
    }
    /// Nothing in reach. Once the catalogue is read, nothing of any kind is (from a US starting point too,
    /// `TonightReach` weighs every place when no national park is in range); before, only the parks were looked at.
    private var emptyMessage:LocalizedStringKey {
        guard !model.catalog.isEmpty else {
            return "No national parks fall inside this radius. Widen it or choose a different starting point."
        }
        return "No parks or dark-sky places fall inside this radius. Widen it or choose a different starting point."
    }
    private func stepRiver(_ delta:Int) {
        guard let park=best(candidates).first else { return }
        let tonight=model.tonight(park), current=riverNight?.night(at:park) ?? tonight
        let next=park.date(current,addingDays:delta)
        guard next>=tonight, next<park.date(tonight,addingDays:30) else { return }
        withAnimation(reduceMotion ? nil : NyxMotion.spring) { riverNight=RiverChoice(parkID:park.id,night:next) }
    }
    private func hero(_ park:Park,others:[Park])->some View {
        let night=model.night(park)
        let large=typeSize.isAccessibilitySize
        // The first line is the answer's own context: the night, and from where. At accessibility sizes
        // it follows the dial and the closure, so the park, its score and any closure fill the first screen.
        let context=reachLine(park).font(.caption.weight(.medium)).kerning(large ? 0 : 1.6).textCase(large || !Lettering.spaced ? nil : .uppercase)
            .foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        // A forecast more than six hours old says when it is from.
        let stale=night.score.hasForecast ? night.forecastUpdated.flatMap { Date.now.timeIntervalSince($0)>6*3600 ? $0 : nil } : nil
        let closure=park.nps == nil ? nil : model.closure(park)
        return VStack(spacing:10) {
            if !large { context }
            // The park as a glass pill; the other parks in reach grow out of it (`ParkPillPicker`).
            ParkPillPicker(park:park,others:others,score:{ model.night($0).score.value },zoom:zoom)
            let basis=night.basisCaption()
            let range=CelestialGauge.modelRange(model.outlook(night),basis:night.basis)
            CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast,spokenBasis:basis,
                           revealKey:revealKey(park),range:range,night:model.ring(night)) { heroSettledKey=$0 }
                // At accessibility sizes the dial is held small enough that a closure under it is on the first screen.
                .environment(\.gaugeAccessibleMax,Self.accessibleDial).frame(height:large ? nil : wide ? 300 : 240)
                .modifier(DepthParallax(depth:0.08))
            // A closure is the one line here that must never be lost in the sky: straight under the score,
            // as on the park's page, on a dark scrim.
            if let closure {
                Label(closure,systemImage:"exclamationmark.triangle").font(.subheadline).labelStyle(.caution).multilineTextAlignment(large ? .leading : .center)
                    .fixedSize(horizontal:false,vertical:true)
                    .padding(.horizontal,12).padding(.vertical,6).background(Color.black.opacity(0.6),in:RoundedRectangle(cornerRadius:12))
                    .accessibilityLabel(String(localized:"Closure alert: \(closure)"))
            }
            if large { context }
            // The night in plain words: where the Moon is, and whether the Milky Way is worth the drive.
            if let verdict=NightVerdict.line(sky:night.sky,core:model.whatsUp(night).coreNight,park:park) {
                Text(verdict.text).font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(.center)
                    .fixedSize(horizontal:false,vertical:true).padding(.horizontal,12)
                    .accessibilityLabel(verdict.spoken)
            }
            // Only the exceptions (no forecast yet, an early look); a full forecast is the norm and goes unsaid.
            // The gauge speaks this line, so VoiceOver does not hear it twice.
            if let basis { Text(basis).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center).accessibilityHidden(true) }
            skyLine(night,range:range)
            // A place the Park Service does not run: Nyx cannot see its closures, and says so.
            if park.nps == nil {
                if let stale { forecastAsOf(park,stale) }
                UnknownClosuresNote(park:park,compact:true).padding(.horizontal,12)
            }
            else if closure != nil { if let stale { forecastAsOf(park,stale) } }
            // Nothing listed: the alerts and the forecast's age share one quiet caption, the safety cue kept.
            else if let listed=model.alertFacts(park) { CaveatLine(facts:listed+(stale.map { [String(localized:"forecast from \(park.timestamp($0))")] } ?? [])).padding(.horizontal,12) }
            else {
                if let stale { forecastAsOf(park,stale) }
                Text(model.alertSummary(park)).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center).padding(.horizontal,12)
            }
            if let smoke=model.smokeCaveat(night) { Label(smoke,systemImage:"smoke").font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(.center).padding(.horizontal,12) }
            AccessNoteLabel(park:park,alignment:.center).padding(.horizontal,12)
            nudge(park:park,tonight:night)
            fieldOffer(best:park)
        }.frame(maxWidth:.infinity)
    }
    /// One sky line under the dial, the first that applies: the forecast models disagreeing (said
    /// first, because the best window rests on the same clouds), then a clear, dark stretch that is
    /// only part of the night (a Moon up all evening, cloud clearing late), else the models' range
    /// in words, as the share card and the river say it (the gauge speaks the range).
    /// The disagreement and the range are `ForecastSpread`'s, as on the park's page.
    @ViewBuilder private func skyLine(_ night:Night,range:ClosedRange<Int>?)->some View {
        let agreement=model.outlook(night)?.agreement
        if agreement?.band == .disagree, let spread=ForecastSpread.line(agreement:agreement,range:range,tonight:true) {
            Text(spread).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal:false,vertical:true).padding(.horizontal,12)
        } else if let window=partialWindow(night) {
            // At accessibility sizes the glyph would take a column of its own: the words alone.
            Label { Text(window.line(park:night.park)).fixedSize(horizontal:false,vertical:true) } icon:{ if !typeSize.isAccessibilitySize { Image(systemName:window.moonlit ? "moon" : "sparkles").accessibilityHidden(true) } }
                .font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(.center).padding(.horizontal,12)
                .accessibilityElement(children:.combine)
        } else if let spread=ForecastSpread.line(agreement:agreement,range:range,tonight:true) {
            Text(spread).font(.caption).monospacedDigit().foregroundStyle(palette.muted).multilineTextAlignment(.center).accessibilityHidden(true)
        }
    }
    /// Tonight's best clear window when it is still ahead and covers at most three quarters of the
    /// true darkness: a score earned late in the night must not read as an evening's promise.
    private func partialWindow(_ night:Night)->ClearWindow? {
        guard let window=model.clearWindow(night), window.interval.end>Date.now, night.sky.darkHours>0,
              window.interval.duration<=0.75*night.sky.darkHours*3600 else { return nil }
        return window
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
        try? await Task.sleep(for:.seconds(reduceMotion ? 0.6 : 0.8))
        guard !Task.isCancelled else { return }
        FoundNights.note(key)
        found+=1
        try? await Task.sleep(for:.milliseconds(120))
        found+=1
    }
    @ViewBuilder private func more(_ best:[Park])->some View {
        if best.count>1 {
            Eyebrow(text:"More skies within reach")
            ForEach(Array(best.dropFirst())) { park in NavigationLink(value:ZoomRoute.row(park)) { ParkRow(night:model.night(park),closure:model.closure(park),week:model.nights(park,from:model.tonight(park),count:7)) }.buttonStyle(.plain).matchedTransitionSource(id:ZoomRoute.row(park).source,in:zoom).parkRowActions(park) { saveFailed=true };Divider().overlay(palette.line) }
            // Only worth saying when a row actually reads "Estimate", in the rows' own words, as on Parks.
            if let note=UsualCloudsNote(best.dropFirst().map { model.night($0) }) { Text(note.estimate).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
        }
    }
    /// The sky over the starting point itself, for anyone not travelling tonight: the device's
    /// location only when Near me is already in use, else the chosen city or park. Not on first
    /// run, where the starting point is only an example. Not when the starting point is the park the
    /// answer already shows: its sky is that park's, one tap away, and would only be said twice.
    @ViewBuilder private func fromHome(hero:Park?)->some View {
        let here=location.latitude.flatMap { lat in location.longitude.map { (latitude:lat,longitude:$0) } }
        if model.startChosen, let origin=HomeSky.origin(location:here,place:model.homePlace,park:model.home), !FromHomePanel.repeats(origin,hero:hero) {
            FromHomePanel(origin:origin,now:model.today,lightsOut:lightsOut(origin))
        }
    }
    /// The darkest place in reach of a town or of where the person is (never of a park), when it is
    /// plainly darker, with its best night in the next two weeks.
    private func lightsOut(_ origin:HomeSky.Origin)->LightsOut.Target? {
        guard origin.source != .park else { return nil }
        let home=LightsOut.homeClass(latitude:origin.latitude,longitude:origin.longitude)
        guard let dark=LightsOut.darkest(candidates,latitude:origin.latitude,longitude:origin.longitude,homeClass:home.bortle) else { return nil }
        let nights=model.nights(dark.place,from:model.tonight(dark.place),count:LightsOut.horizon)
        return LightsOut.Target(place:dark.place,meters:dark.meters,homeClass:home.bortle,homeKnown:home.known,best:LightsOut.best(nights,closure:model.closure(dark.place)))
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
                SkyGlyph(SkyGlyph.Kind(event.glyph),color:palette.ink).frame(width:15,height:15)
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
        }.buttonStyle(.capsuleAction).padding(.top,4)
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
    /// Tonight answers where; this answers when (`NightVerdict.darkerAhead`): the answer's own park's
    /// best night when it is clearly darker (its page's "Darker on…"), else Best nights' best night in
    /// reach, a closed park after the open ones. Said with what it rests on ("77, usual clouds").
    @ViewBuilder private func darkerAhead(than tonight:Night)->some View {
        if aheadPrepared == TonightReach.key(aheadPool) { darkerCapsule(than:tonight) }
    }
    @ViewBuilder private func darkerCapsule(than tonight:Night)->some View {
        let closures=Dictionary(aheadPool.compactMap { park in model.closure(park).map { (park.id,$0) } },uniquingKeysWith:{ first,_ in first })
        let here=model.nights(tonight.park,from:model.tonight(tonight.park),count:NightVerdict.horizon)
        let ahead=NightVerdict.darkerAhead(than:tonight,here:here,across:aheadPool.map { model.nights($0,from:model.tonight($0),count:NightVerdict.horizon) },closures:closures)
        if let ahead {
            capsule(text:NightVerdict.capsule(ahead,here:ahead.park.id==tonight.park.id),hint:"Opens that night at the park.") {
                ParkDetailView(park:ahead.park,initialDate:ahead.id)
            } icon:{ Image(systemName:"moon.stars").imageScale(.small) }
            // A darker night somewhere the car cannot go says so before the tap, not after.
            if !ahead.park.drivable { AccessNoteLabel(park:ahead.park,alignment:.center).padding(.horizontal,12) }
            // Darker is the sky alone: a closure there is said beside it, never weighed into it. At the
            // answer's own park it is already said under the dial, and is not said twice.
            if ahead.park.id != tonight.park.id, let closure=model.closure(ahead.park) {
                Label(closure,systemImage:"exclamationmark.triangle").font(.footnote).labelStyle(.caution).multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .center)
                    .fixedSize(horizontal:false,vertical:true).padding(.horizontal,12)
                    .accessibilityLabel(String(localized:"Closure alert: \(closure)"))
            }
        }
    }
    private func capsule<Destination:View,Icon:View>(text:String,hint:LocalizedStringKey,@ViewBuilder destination:@escaping ()->Destination,@ViewBuilder icon:()->Icon)->some View {
        NavigationLink { destination() } label:{
            HStack(spacing:8) {
                icon().accessibilityHidden(true)
                Text(text).multilineTextAlignment(.leading)
                Image(systemName:"chevron.forward").imageScale(.small).font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
        }.buttonStyle(.capsuleAction).padding(.top,4)
        .accessibilityHint(hint)
    }
}
extension EnvironmentValues {
    /// The most a dial may measure across at accessibility sizes (`CelestialGauge`): Tonight holds
    /// it smaller, so the pill, the score and a closure under it all fit the first screen.
    @Entry var gaugeAccessibleMax: Double = .infinity
}
/// Tonight's answer and the moment "tonight" is judged from: either changing hands the pick on.
private struct TonightPickKey: Equatable {
    let id: String?
    let night: Date
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
        Text(parts.joined(separator:" · ")).lineLimit(1).accessibilityLabel(Phrase.sentences(parts.map(Self.sentence)))
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
        NavigationStack { ScrollView { VStack(spacing:24) { CalmState(symbol:symbol,title:title,message:message);Button(action,action:proceed).secondaryAction();Button("Continue without it") { dismiss() } }.padding(24) }.background(Color.black).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { dismiss() } } } }.presentationDetents([.medium,.large])
            // A form-sized card on iPad, never a page stretched across the window.
            .presentationSizing(.form)
    }
}
#Preview("Tonight") { NavigationStack { TonightView() }.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Tonight • from abroad") { NavigationStack { TonightView() }.environment(TonightReach.previewModel(from:"Reykjavík")).preferredColorScheme(.dark) }
#Preview("Tonight • from abroad, AX5, night vision") {
    NavigationStack { TonightView() }.environment(TonightReach.previewModel(from:"Paris")).dynamicTypeSize(.accessibility5)
        .environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark)
}
#Preview("Tonight • from abroad, wide iPad") { NavigationStack { TonightView() }.environment(TonightReach.previewModel(from:"Sydney")).frame(width:1180,height:820).preferredColorScheme(.dark) }
#Preview("Caveat • two facts") { CaveatLine(facts:[String(localized:"No closures listed"),String(localized:"check alerts before you go")]).padding(24).frame(width:402).background(.black).preferredColorScheme(.dark) }
#Preview("Caveat • no alerts listed") { CaveatLine(facts:[String(localized:"No alerts listed"),String(localized:"confirm access before you go")]).padding(24).frame(width:402).background(.black).preferredColorScheme(.dark) }
#Preview("Caveat • old forecast, wraps at the last dot") { CaveatLine(facts:[String(localized:"No closures listed"),String(localized:"check alerts before you go"),"forecast from Oct 8, 1:51 PM"]).padding(24).frame(width:402).background(.black).preferredColorScheme(.dark) }
#Preview("Caveat • old forecast, AX5") { CaveatLine(facts:[String(localized:"No closures listed"),String(localized:"check alerts before you go"),"forecast from Oct 8, 1:51 PM"]).padding(24).frame(width:402).background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
#Preview("Caveat • night vision") { CaveatLine(facts:[String(localized:"No closures listed"),String(localized:"check alerts before you go"),"forecast from Oct 8, 1:51 PM"]).padding(24).frame(width:402).background(.black).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark) }
/// Which places Tonight weighs, apart from the view so it can be tested.
nonisolated enum TonightReach {
    /// Beyond this many places in reach, the first ranking is of a shortlist until every night is ready.
    static let shortlistSize=40
    /// Abroad, the coming nights are looked at for this many of the best places tonight.
    static let aheadSize=12
    /// From a US starting point with only US places in range: the national parks, exactly as before
    /// the world catalogue (US dark-sky places and saved spots stay out of Tonight there, as they did).
    /// From anywhere else, near a border, or where no national park is in reach: every place in range,
    /// curated, catalogue and saved spots alike, ranked as the parks always were.
    static func candidates(parks:[Park],places:[Park],originInUS:Bool)->[Park] {
        if originInUS, !parks.isEmpty, places.allSatisfy({ $0.countryCode.uppercased()=="US" }) { return parks }
        return places
    }
    /// At most `limit` places to rank first: every curated park and saved spot in reach, then catalogue
    /// places by what their sky offers before any forecast (the lower Bortle class first, a DarkSky
    /// designation next), then the nearer. Only an order of work: the answer is still the best score.
    static func shortlist(_ places:[Park],latitude:Double,longitude:Double,limit:Int=shortlistSize)->[Park] {
        let kept=places.filter { !$0.isCatalogPlace }
        let rest=places.filter(\.isCatalogPlace).map { ($0,$0.distanceMeters(latitude:latitude,longitude:longitude)) }.sorted { a,b in
            if a.0.bortleEstimate != b.0.bortleEstimate { return a.0.bortleEstimate<b.0.bortleEstimate }
            if a.0.darkSkyDesignated != b.0.darkSkyDesignated { return a.0.darkSkyDesignated }
            return (a.1,a.0.id)<(b.1,b.0.id)
        }.map(\.0)
        return Array((kept+rest).prefix(max(limit,kept.count)))
    }
    /// The same places in reach, the same key: whether their nights have been worked out.
    static func key(_ places:[Park])->String { places.map(\.id).sorted().joined(separator:",") }
    /// For previews: a model starting from a city abroad, with the catalogue on its way.
    @MainActor static func previewModel(from city:String)->PlanModel {
        let model=PlanModel()
        model.prepareCatalog()
        if let place=StartingPlaces.all.first(where:{ $0.name==city }) { model.choose(place) }
        return model
    }
}
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
/// The night chosen on Tonight's river (wide windows), with the park it was chosen at.
struct RiverChoice: Equatable {
    let parkID: String
    let night: Date
    /// The night, when it was chosen at this park; nil at any other.
    func night(at park: Park) -> Date? { parkID==park.id ? night : nil }
}
