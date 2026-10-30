import SwiftUI
import TipKit

struct TonightView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
    @Environment(\.nyxAccess) private var access
    @State private var shooting=0.0
    /// The pull's gathered star; only the meteor's overlay reads it.
    @State private var pull=PullGather()
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
    /// (`prepared`), the page ranks a shortlist (`PlanModel.shortlist`), never hundreds at once.
    private func best(_ all:[Park])->[Park] { Array(model.ranked(pool(all)).prefix(5)) }
    private func pool(_ all:[Park])->[Park] {
        prepared==TonightReach.key(all) ? all : model.shortlist(all)
    }
    /// The places in reach whose tonight has been worked out in the background (`TonightReach.key`).
    @State private var prepared:String?
    /// The same for the places a wider radius would add (`farther(than:shortlist:)`).
    @State private var widerPrepared:String?
    /// The places' 30 nights behind "Darker on…" (`NightPlanner.horizon`), worked out off the main thread first.
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
    /// The night the dial shows, in nights after tonight (`TonightScrub`, 0…13): stepped by a horizontal
    /// drag across the dial, VoiceOver's adjustable action, ⌘← ⌘→ where no river is beside it, or the
    /// step buttons. Each night re-ranks the places in reach, so the dial answers "where" for any night.
    @State private var dialNight=TonightView.debugNight
    /// The night the page's sky follows: the dial's once the finger lifts, so the sky and its Moon change
    /// once on release rather than on every detent, as the river holds the park page's sky.
    @State private var skyNight=TonightView.debugNight
    /// The dial's night as the current drag began; nil between drags.
    @State private var dragFrom:Int?
    /// True while a finger scrubs the dial (`DialPan` begins only on a sideways drag, so the page still
    /// scrolls); nil once it lifts or the system cancels the drag.
    @State private var dialDrag:Bool?=nil
    /// Bumped once per night the dial steps to: the light tick of a scrub detent.
    @State private var dialDetents=0
    @State private var dialTipDone=false
    @Environment(\.layoutDirection) private var layoutDirection
    private let dialTip=DialNightsTip()
    /// `-nyx-tonight-night 6` (DEBUG captures): the dial opens on that night.
    private static var debugNight:Int {
        #if DEBUG
        return TonightScrub.clamp(Int(DebugScenario.number("-nyx-tonight-night") ?? 0))
        #else
        return 0
        #endif
    }
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
        let heroReady=best.first.map { heroSettledKey==revealKey(model.night($0)) } ?? false
        // Another night on the dial waits for the places' coming nights, worked out off the main thread for
        // "Darker on…" (`aheadPrepared`): a step then only reads nights the model already keeps.
        let aheadParks=aheadPool
        let ready = !best.isEmpty && !loading && aheadPrepared==TonightReach.key(aheadParks)
        let offset=ready ? dialNight : 0, skyOffset=ready ? skyNight : 0
        let shown=answer(offset:offset,best:best,ahead:aheadParks)
        let sky=skyOffset==offset ? shown.first : answer(offset:skyOffset,best:best,ahead:aheadParks).first
        ScrollViewReader { proxy in
        ScrollView {
            if wide, !loading, !empty, let park=best.first, let night=shown.first {
                VStack(alignment:.leading,spacing:22) {
                    if !model.startChosen { firstRun }
                    // The two columns meet at iPhone Duo's fold on its inner display, half open or flat.
                    FoldColumns(narrow:.trailing,narrowMax:500,spacing:NyxMetrics.columnGap) {
                        VStack(spacing:26) { GoingPanel(hero:offset==0 ? park : nil); hero(night,others:Array(shown.dropFirst()),offset:offset,ready:ready); if offset==0 { farther(than:park,shortlist:widerList) }; darkArea(all); ahead(night.park,held:offset>0 ? night.id : nil) }.frame(maxWidth:.infinity)
                        VStack(alignment:.leading,spacing:22) { StartingPointPanel(rule:false,choose:{ chooseHome=true },nearMe:nearMe).id(Self.startID); more(shown,offset:offset); fromHome(hero:park); LookingBackPanel(); extras }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    // Where, then when: the week at every park in reach fills the window's lower half.
                    weekAcross
                }.padding(NyxMetrics.pagePadding).readableColumn(WideLayout.twoColumnMaximum)
            } else {
                VStack(alignment:.leading,spacing:22) {
                    if !model.startChosen { firstRun }
                    // A night the person said they are going to leads: their own plan before tonight's answer.
                    // At accessibility sizes it follows the answer, so the score stays on the first screen.
                    if !loading, !typeSize.isAccessibilitySize { GoingPanel(hero:offset==0 ? best.first : nil) }
                    if loading { ConstellationLoader().frame(maxWidth:.infinity) }
                    else if empty { CalmState(symbol:"moon.stars",title:"A little farther from here",message:emptyMessage);farther(than:nil,shortlist:widerList);darkArea(all);StartingPointPanel(choose:{ chooseHome=true },nearMe:nearMe).id(Self.startID);fromHome(hero:nil) }
                    else if let park=best.first, let night=shown.first {
                        hero(night,others:Array(shown.dropFirst()),offset:offset,ready:ready)
                        if typeSize.isAccessibilitySize { GoingPanel(hero:offset==0 ? park : nil) }
                        // "Darker within …" is weighed from tonight, so it waits while the dial holds a later night.
                        if offset==0 { farther(than:park,shortlist:widerList) }
                        darkArea(all)
                        // The answer, then the alternatives; then where "within reach" is measured from.
                        more(shown,offset:offset)
                        StartingPointPanel(heading:best.count>1,choose:{ chooseHome=true },nearMe:nearMe).id(Self.startID)
                        fromHome(hero:park)
                        LookingBackPanel()
                    }
                    extras
                }.padding(24).readableColumn()
            }
        }.scrollDisabled(scrubbing).onPreferenceChange(RiverScrubbingKey.self) { scrubbing=$0 }
        // The loader gives way to the answer (or the calm empty state) in a dissolve, never a cut.
        .animation(NyxMotion.spring(reduced:reduceMotion),value:loading)
        .animation(NyxMotion.spring(reduced:reduceMotion),value:empty)
        // Pulled past the top by a finger, the meteor's star gathers; at rest again, the next pull may launch one.
        .onScrollGeometryChange(for:Double.self) { ShootingStar.gather(overscroll:-($0.contentOffset.y+$0.contentInsets.top)) } action:{ _,new in
            withAnimation(NyxMotion.tracking) { pull.pull=new }
        }
        .onScrollPhaseChange { _,phase in
            withAnimation(NyxMotion.tracking) { pull.interacting = phase == .interacting }
            if phase == .idle { pull.spent=false }
        }
        // The fold, read on the scroll view itself so the columns keep it however far the page scrolls.
        .foldSource()
        // `-nyx-scroll 0…1` (DEBUG) opens partway down, for review captures of the starting point.
        .defaultScrollAnchor(DebugScenario.number("-nyx-scroll").map { UnitPoint(x:0.5,y:$0) } ?? (DebugScenario.isEnabled("bottom") ? .bottom : .top))
        .onChange(of:toStart) { withAnimation(reduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo(Self.startID,anchor:.center) } }
        }
        // ⌘← ⌘→ move the river beside the answer on a wide iPad, else the dial's night.
        .nightKeys(enabled:!empty && (wide || ready)) { delta in if wide { stepRiver(delta) } else { stepDial(delta) } }
        // The sky is the dial's night once a finger lets go of it (`skyNight`).
        .background(NightBackground(seed:model.homeID,score:sky?.score.value,park:sky?.park,night:sky.map { TonightScrub.evening($0.park,tonight:model.tonight($0.park),offset:skyOffset) })).navigationTitle("Tonight").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection,trigger:dialDetents)
        // The finger lifts: the sky follows to the night it left, on the shared spring (a dissolve without motion).
        .onChange(of:dialDrag==true) { _,now in
            guard !now else { return }
            dragFrom=nil
            if skyNight != dialNight { withAnimation(NyxMotion.spring(reduced:reduceMotion)) { skyNight=dialNight } }
        }
        // A new night (sunrise turned it over): "three nights on" means another night now, so the dial starts at tonight.
        .onChange(of:model.today) { dialNight=0; skyNight=0 }
        // Wide: the river beside the dial follows the night the dial steps to, so a choice made on the river before gives way.
        .onChange(of:dialNight) { riverNight=nil }
        // The nights the dial steps to: what's up each night (the verdict under the dial) worked out off the main thread.
        .task(id:ready ? TonightReach.key(aheadParks) : nil) {
            guard ready else { return }
            await model.prepareWhatsUp((1..<TonightScrub.nights).compactMap { answer(offset:$0,best:best,ahead:aheadParks).first })
        }
            .tabRootToolbar()
            // ⌘R's note says a forecast's time as the pull does, in the answer's own time.
            .environment(\.refreshTimeZone,best.first?.timeZone)
            // The pill and the rows open the night the dial shows: tonight, or the night it was stepped to.
            .navigationDestination(for:ZoomRoute.self) { route in
                let night=offset==0 ? nil : TonightScrub.evening(route.park,tonight:model.tonight(route.park),offset:offset)
                ParkDetailView(park:route.park,initialDate:night).modifier(ParkTransition(sourceID:route.source,namespace:zoom)).onAppear { ReviewPrompt.noteNightViewed(score:model.night(route.park,on:night).score.value) }
            }
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
                await model.prepareNights(pool,count:NightPlanner.horizon)
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
            .overlay(alignment:.top) { PullMeteor(progress:shooting,pull:pull,off:reduceMotion || access.reduceHighlighting).frame(height:170) }
            .sensoryFeedback(.selection,trigger:refreshed)
            .sensoryFeedback(.impact(weight:.light,intensity:0.8),trigger:found)
            // The double tap is the reveal's last beat, after the landing and any 70/90 pulses.
            .task(id:heroReady ? worthy : nil) { await feelFound(heroReady ? worthy : nil) }
            .measuringWidth($width)
            .refreshable {
                // The shooting star is a highlight: it stays home under Reduce Highlighting Effects.
                if !reduceMotion && !access.reduceHighlighting && shooting==0 {
                    // The gathered star becomes the meteor's head as it leaves (⌘R, with nothing gathered, just launches).
                    withAnimation(ShootingStar.launch) { shooting=1; pull.spent = pull.pull>0 } completion:{ shooting=0 }
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
        } else {
            // The way back to location, as the starting-point panel offers once a place is chosen.
            Button { if let url=URL(string:UIApplication.openSettingsURLString) { openURL(url) } } label:{ Label("Settings",systemImage:"location.slash").frame(minHeight:30) }
                .secondaryAction().accessibilityLabel("Turn on location in Settings")
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
    private func reachLine(_ park:Park,day:String)->some View {
        Button { toStart+=1 } label:{
            // The small arrow says the line leads somewhere; the target reaches 44 pt without moving the line.
            HStack(alignment:.firstTextBaseline,spacing:5) {
                answerLine(day:day)
                if !typeSize.isAccessibilitySize { Image(systemName:"arrow.down").font(.caption2.weight(.semibold)).accessibilityHidden(true) }
            }
            .padding(.vertical,14).contentShape(Rectangle()).padding(.vertical,-14)
        }.buttonStyle(.plain)
        .accessibilityHint("Shows the starting point and radius.")
    }
    /// The line above the answer, all data: the night, and where "in reach" is measured from.
    /// Never "nearby" for a starting park or city; an example until a starting point is chosen.
    /// At accessibility sizes the two facts stack as two lines, with no "·" left dangling at a wrap.
    @ViewBuilder private func answerLine(day:String)->some View {
        let radius=SearchRadius.label(model.radiusMeters)
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
        return model.shortlist(wide)
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
    /// Wide iPad: where, then when. The answer's park and its next thirty nights beside it, with the
    /// chosen night one tap away. While the dial holds a later night (`held`), the river is that night's
    /// park with that night chosen, so the two never show different places. (On iPhone the river lives
    /// on the park's page.)
    private func ahead(_ park:Park,held:Date?=nil)->some View {
        let tonight=model.tonight(park), nights=model.nights(park,from:tonight,count:NightPlanner.horizon)
        let picked=riverNight?.night(at:park) ?? held
        let chosen=picked.flatMap { id in nights.first { $0.id==id } }
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
        // The river's own park and night: the dial's held night when it holds one (`ahead(_:held:)`).
        let best=best(candidates)
        let held=dialNight>0 ? answer(offset:dialNight,best:best,ahead:aheadPool).first : nil
        guard let park=held?.park ?? best.first else { return }
        let tonight=model.tonight(park), current=riverNight?.night(at:park) ?? held?.id ?? tonight
        let next=park.date(current,addingDays:delta)
        guard next>=tonight, next<park.date(tonight,addingDays:NightPlanner.horizon) else { return }
        withAnimation(reduceMotion ? nil : NyxMotion.spring) { riverNight=RiverChoice(parkID:park.id,night:next) }
    }
    /// The answer for the night `offset` nights after tonight: the places in reach ranked for that night,
    /// at most five, each place's night in its own time zone. Tonight ranks the page's pool (`best`);
    /// a later night the places whose coming nights are already worked out (`aheadPool`). Every night
    /// is one the model keeps (`PlanModel.night`), so a step is a sort of memoised nights, not astronomy.
    private func answer(offset:Int,best:[Park],ahead:[Park])->[Night] {
        guard offset>0 else { return best.map { model.night($0) } }
        return Array(NightPlanner.ranked(ahead.map { model.night($0,on:TonightScrub.evening($0,tonight:model.tonight($0),offset:offset)) }).prefix(5))
    }
    private func hero(_ night:Night,others:[Night],offset:Int,ready:Bool)->some View {
        let park=night.park
        let large=typeSize.isAccessibilitySize, later=offset>0
        // The first line is the answer's own context: the night, and from where. At accessibility sizes
        // it follows the dial and the closure, so the park, its score and any closure fill the first screen.
        // Another night than tonight is said in starlight, so the held night reads as chosen, not as the default.
        let context=reachLine(park,day:park.dayLabel(night.id)).eyebrow()
            .foregroundStyle(later ? palette.ink : palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        // A forecast older than the age at which clouds are asked for again says when it is from.
        let stale=night.score.hasForecast ? night.forecastUpdated.flatMap { model.forecastIsStale($0) ? $0 : nil } : nil
        let closure=park.nps == nil ? nil : model.closure(park)
        let scores=Dictionary(others.map { ($0.park.id,$0.score.value) },uniquingKeysWith:{ first,_ in first })
        return VStack(spacing:10) {
            if !large { context }
            // The park as a glass pill; the other parks in reach grow out of it (`ParkPillPicker`), scored for the dial's night.
            ParkPillPicker(park:park,others:others.map(\.park),score:{ scores[$0.id] ?? model.night($0).score.value },zoom:zoom,night:later ? park.dayLabel(night.id) : nil)
            let range=CelestialGauge.modelRange(model.outlook(night),basis:night.basis)
            dial(night,basis:night.basisCaption(),range:range,offset:offset,ready:ready)
            // A closure is the one line here that must never be lost in the sky: straight under the score,
            // as on the park's page, on a dark scrim.
            if let closure { ClosureLabel(closure,prominence:.hero) }
            // Switch Control and "prefers action slider alternative": the nights a button at a time.
            if ready && access.preferSteps { dialSteps(offset) }
            // A later night is held after the finger lifts, with the way back right under it.
            if later { backToTonight }
            if large { context }
            // The rest in the park page's order (`NightNotes`), the alerts in Tonight's own words.
            NightNotes(night:night,isTonight:!later,range:range) { alerts(park,closure:closure,stale:stale) }
            // "Darker on…", an eclipse or shower ahead, and field mode are tonight's: weighed against tonight
            // and said from it, they would contradict a later night on the dial, so they wait for its return.
            if !later {
                nudge(park:park,tonight:night)
                fieldOffer(best:park)
            }
        }.frame(maxWidth:.infinity)
    }
    /// The dial, which steps through the coming nights under a sideways drag (`dialScrub`), VoiceOver's
    /// swipe up or down, or the step buttons. Nothing steps until the places' nights are ready (`ready`).
    private func dial(_ night:Night,basis:String?,range:ClosedRange<Int>?,offset:Int,ready:Bool)->some View {
        let large=typeSize.isAccessibilitySize
        return CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast,spokenBasis:basis,
                              revealKey:revealKey(night),range:range,night:model.ring(night)) { heroSettledKey=$0 }
            // At accessibility sizes the dial is held small enough that a closure under it is on the first screen.
            .environment(\.gaugeAccessibleMax,Self.accessibleDial).frame(height:large ? nil : wide ? 300 : 240)
            .modifier(DepthParallax(depth:0.08))
            .contentShape(Rectangle())
            .gesture(DialPan(enabled:ready) { dialScrub($0) })
            // VoiceOver steps the nights without the drag: the value is the night, the place and its score.
            .accessibilityValue(TonightScrub.spokenValue(night,tonight:offset==0))
            .accessibilityHint(ready ? Text("Steps through the next two weeks of nights, each with the darkest place in reach.") : Text(verbatim:""))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: stepDial(1)
                case .decrement: stepDial(-1)
                @unknown default: break
                }
            }
            // Found once, then out of the way: the first step closes it. Not in night vision, where it would be
            // the brightest thing on the screen, nor before a starting point, while the first-run question leads.
            .popoverTip(ready && model.startChosen && !palette.nightVision && (DebugScenario.screen == nil || DebugScenario.isEnabled("dial-tip")) ? dialTip : nil)
            // While a finger scrubs the dial the page holds still, as for the river.
            .preference(key:RiverScrubbingKey.self,value:dialDrag==true)
    }
    /// A mostly sideways drag across the dial steps a night every `TonightScrub.pitch` points: toward the
    /// leading edge for later nights, which come in from the trailing edge as pages do. Measured on the
    /// screen, so the dial shifting under the finger (a longer name in the pill) never steps a night.
    private func dialScrub(_ translation:CGSize?) {
        guard let translation else { dialDrag=nil; return }
        if dialDrag == nil { dialDrag=true }
        let from=dragFrom ?? dialNight
        if dragFrom==nil { dragFrom=from }
        chooseNight(TonightScrub.offset(from:from,translation:translation.width,rightToLeft:layoutDirection == .rightToLeft))
    }
    /// One step, from VoiceOver, a key or a button; nothing until the places' nights are ready.
    private func stepDial(_ delta:Int) {
        guard aheadPrepared==TonightReach.key(aheadPool) else { return }
        chooseNight(dialNight+delta)
    }
    /// The dial moves to a night: the numeral sweeps there on the shared spring (`CelestialGauge`), or
    /// dissolves under Reduce Motion, with one light tick per night. A finger keeps the sky until it lifts.
    private func chooseNight(_ offset:Int) {
        let next=TonightScrub.clamp(offset)
        guard next != dialNight else { return }
        withAnimation(NyxMotion.spring(reduced:reduceMotion)) {
            dialNight=next
            if dialDrag != true { skyNight=next }
        }
        dialDetents+=1
        if !dialTipDone { dialTipDone=true; dialTip.invalidate(reason:.actionPerformed) }
    }
    /// The way back from a held night: starlight glass under the dial, as the page's other actions.
    private var backToTonight: some View {
        Button { chooseNight(0) } label:{
            HStack(spacing:8) {
                Image(systemName:"arrow.uturn.backward").imageScale(.small).accessibilityHidden(true)
                Text("Back to tonight").multilineTextAlignment(.leading)
            }
        }.buttonStyle(.capsuleAction).padding(.top,4)
        .accessibilityInputLabels([Text("Back to tonight"),Text("Tonight")])
    }
    /// Previous and next night as buttons, side by side or stacked at accessibility sizes. A step that
    /// cannot be taken is set in the muted ink, which keeps its contrast in night vision.
    private func dialSteps(_ offset:Int)->some View {
        let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:10)) : AnyLayout(HStackLayout(spacing:12))
        let first=offset<=0, last=offset>=TonightScrub.last
        return layout {
            Button { stepDial(-1) } label:{ Label("Previous night",systemImage:"chevron.backward").frame(maxWidth:.infinity,minHeight:30).foregroundStyle(first ? palette.muted : palette.ink) }.disabled(first)
            Button { stepDial(1) } label:{ Label("Next night",systemImage:"chevron.forward").frame(maxWidth:.infinity,minHeight:30).foregroundStyle(last ? palette.muted : palette.ink) }.disabled(last)
        }
        .secondaryAction().font(.subheadline.weight(.medium))
        .accessibilityElement(children:.contain)
    }
    /// The park's alerts under the answer, with the forecast's age when it is old. A place the Park
    /// Service does not run: Nyx cannot see its closures, and says so. Nothing listed beyond a closure
    /// already said under the dial: the age alone. Alerts listed: they and the age share one quiet
    /// caption, the safety cue kept. Otherwise the alerts' summary.
    @ViewBuilder private func alerts(_ park:Park,closure:String?,stale:Date?)->some View {
        if park.nps == nil {
            if let stale { forecastAsOf(park,stale) }
            UnknownClosuresNote(park:park,compact:true).padding(.horizontal,12)
        }
        else if closure != nil { if let stale { forecastAsOf(park,stale) } }
        else if let listed=model.alertFacts(park) { CaveatLine(facts:listed+(stale.map { [String(localized:"forecast from \(park.timestamp($0))")] } ?? [])).padding(.horizontal,12) }
        else {
            if let stale { forecastAsOf(park,stale) }
            Text(model.alertSummary(park)).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center).padding(.horizontal,12)
        }
    }
    private func forecastAsOf(_ park:Park,_ updated:Date)->some View {
        Text("Forecast as of \(park.timestamp(updated))").font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center)
    }
    /// The hero dial's reveal key for a park's night.
    private func revealKey(_ night:Night)->String {
        ScoreReveals.key(parkID:night.park.id,night:night.park.isoDay(night.id),score:night.score.value)
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
    /// The other places in reach for the dial's night, each row's week starting from it.
    @ViewBuilder private func more(_ shown:[Night],offset:Int)->some View {
        if shown.count>1, let first=shown.first {
            if offset>0 { Eyebrow(text:"Other dark places in reach on \(first.park.dayLabel(first.id))") } else { Eyebrow(text:"Other dark places in reach") }
            // Rows and hairlines in their own stack, as on Parks: the page's spacing would double each gap.
            VStack(spacing:0) {
                ForEach(Array(shown.dropFirst()),id:\.park.id) { night in
                    let park=night.park
                    NavigationLink(value:ZoomRoute.row(park)) { ParkRow(night:night,closure:model.closure(park),week:model.nights(park,from:TonightScrub.evening(park,tonight:model.tonight(park),offset:offset),count:7)) }.buttonStyle(.plain).matchedTransitionSource(id:ZoomRoute.row(park).source,in:zoom).parkRowActions(park) { saveFailed=true };Divider().overlay(palette.line)
                }
            }
            // Only worth saying when a row actually reads "Estimate", in the rows' own words, as on Parks.
            if let note=UsualCloudsNote(Array(shown.dropFirst())) { Text(note.estimate).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
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
        let nights=model.nights(dark.place,from:model.tonight(dark.place),count:NightPlanner.horizon)
        return LightsOut.Target(place:dark.place,meters:dark.meters,homeClass:home.bortle,homeKnown:home.known,best:NightPlanner.best(nights))
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
        let now=model.present
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
        let here=model.nights(tonight.park,from:model.tonight(tonight.park),count:NightPlanner.horizon)
        let ahead=NightVerdict.darkerAhead(than:tonight,here:here,across:aheadPool.map { model.nights($0,from:model.tonight($0),count:NightPlanner.horizon) },closures:closures)
        if let ahead {
            capsule(text:NightVerdict.capsule(ahead,here:ahead.park.id==tonight.park.id),hint:"Opens that night at the park.") {
                ParkDetailView(park:ahead.park,initialDate:ahead.id)
            } icon:{ Image(systemName:"moon.stars").imageScale(.small) }
            // A darker night somewhere the car cannot go says so before the tap, not after.
            if !ahead.park.drivable { AccessNoteLabel(park:ahead.park,alignment:.center).padding(.horizontal,12) }
            // Darker is the sky alone: a closure there is said beside it, never weighed into it. At the
            // answer's own park it is already said under the dial, and is not said twice.
            if ahead.park.id != tonight.park.id, let closure=model.closure(ahead.park) {
                ClosureLabel(closure,centered:true).padding(.horizontal,12)
            }
        }
    }
    private func capsule<Destination:View,Icon:View>(text:String,hint:LocalizedStringKey,@ViewBuilder destination:@escaping ()->Destination,@ViewBuilder icon:()->Icon)->some View {
        let mark=icon()
        // A one-line capsule too wide for the column breaks at its dot, never mid-phrase, in a rounded
        // rectangle (a capsule's rim would cut two lines); VoiceOver still reads the one line.
        let broken=text.contains("\n") ? nil : text.range(of:" · ").map { text.replacingCharacters(in:$0,with:"\n") }
        return Group {
            if let broken {
                ViewThatFits(in:.horizontal) {
                    capsuleLink(Text(text),destination:destination,icon:mark)
                    capsuleLink(Text(broken).accessibilityLabel(text),rounded:true,destination:destination,icon:mark)
                }
            } else { capsuleLink(Text(text),destination:destination,icon:mark) }
        }.padding(.top,4)
        .accessibilityHint(hint)
    }
    private func capsuleLink<Destination:View,Icon:View>(_ text:Text,rounded:Bool=false,destination:@escaping ()->Destination,icon:Icon)->some View {
        NavigationLink { destination() } label:{
            HStack(spacing:8) {
                icon.accessibilityHidden(true)
                text.multilineTextAlignment(.leading)
                Image(systemName:"chevron.forward").imageScale(.small).font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
        }.buttonStyle(CapsuleActionStyle(rounded:rounded))
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
        // The choice stays pinned under the message, so the sheet at half height never shows only Close.
        NavigationStack { ScrollView { CalmState(symbol:symbol,title:title,message:message).padding(.horizontal,24) }.background(Color.black)
            .safeAreaInset(edge:.bottom) { VStack(spacing:14) { Button(action,action:proceed).secondaryAction();Button("Continue without it") { dismiss() }.frame(minHeight:44) }.padding(.horizontal,24).padding(.vertical,12).frame(maxWidth:.infinity).background(Color.black) }
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { dismiss() } } } }
            // Three quarters, not half: on an iPhone SE half the screen held the pinned choice and only the
            // title above it, so the reason was out of sight.
            .presentationDetents([.fraction(0.75),.large])
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
/// Tonight's dial stepped through the coming nights, apart from the view so it can be tested. Each
/// step is a night after tonight, counted in each place's own time zone, so "Friday" is Friday night
/// wherever the place is; the dial shows the darkest place in reach that night.
nonisolated enum TonightScrub {
    /// Tonight and the next 13 nights: two weeks, the reach of the cloud forecast and its early look,
    /// and the nights "where is darkest" can still be planned around. Every later night is Plan's.
    static let nights=14
    static var last:Int { nights-1 }
    /// Points of sideways drag per night: two weeks in about one sweep of a thumb across the dial.
    static let pitch=24.0
    static func clamp(_ offset:Int)->Int { min(last,max(0,offset)) }
    /// The river's rule, so both read a drag alike: mostly sideways scrubs, anything else scrolls the page.
    static func isHorizontal(_ translation:CGSize)->Bool { abs(translation.width)>abs(translation.height) }
    /// The night a drag reaches from the night it began on: a night per `pitch` points (from half a pitch,
    /// so the first step comes early), later toward the leading edge (left, or right in a right-to-left
    /// language), held to tonight and the last night.
    static func offset(from start:Int,translation:Double,rightToLeft:Bool=false,pitch:Double=pitch)->Int {
        let steps=Int((translation/pitch).rounded())
        return clamp(start+(rightToLeft ? steps : -steps))
    }
    /// The date `offset` nights after a place's tonight, as `PlanModel.nights(_:from:count:)` steps it.
    static func evening(_ park:Park,tonight:Date,offset:Int)->Date { offset==0 ? tonight : park.date(tonight,addingDays:offset) }
    /// The dial's value for VoiceOver: "Fri, Oct 30: Joshua Tree, 82, Excellent", the score with what it
    /// rests on beyond the forecast ("82, usual clouds", `NightVerdict.scored`); "Tonight: …" tonight.
    static func spokenValue(_ night:Night,tonight:Bool)->String {
        let day=tonight ? String(localized:"Tonight") : night.park.dayLabel(night.id)
        return String(localized:"\(day): \(night.park.shortName), \(NightVerdict.scored(night)), \(night.score.band.label)")
    }
}
/// The dial's sideways drag, as a UIKit pan that begins only when the finger moves more across than
/// up or down. A SwiftUI drag on the dial, even a simultaneous one, kept a swipe that began on it from
/// scrolling the page (seen on an iPhone SE, where the dial is a third of the first screen).
/// `changed` gets the translation in the window while dragging, and nil when the drag ends or is cancelled.
private struct DialPan: UIGestureRecognizerRepresentable {
    var enabled=true
    let changed:(CGSize?)->Void
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer:UIGestureRecognizer)->Bool {
            guard let pan=recognizer as? UIPanGestureRecognizer else { return true }
            let velocity=pan.velocity(in:pan.view)
            return TonightScrub.isHorizontal(CGSize(width:velocity.x,height:velocity.y))
        }
    }
    func makeCoordinator(converter:CoordinateSpaceConverter)->Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context:Context)->UIPanGestureRecognizer {
        let recognizer=UIPanGestureRecognizer()
        recognizer.delegate=context.coordinator
        recognizer.isEnabled=enabled
        return recognizer
    }
    func updateUIGestureRecognizer(_ recognizer:UIPanGestureRecognizer,context:Context) { recognizer.isEnabled=enabled }
    func handleUIGestureRecognizerAction(_ recognizer:UIPanGestureRecognizer,context:Context) {
        switch recognizer.state {
        case .began,.changed: let moved=recognizer.translation(in:nil); changed(CGSize(width:moved.x,height:moved.y))
        default: changed(nil)
        }
    }
}
/// Tonight's dial steps through the nights, which nothing on it shows: said once, and closed by the first step.
struct DialNightsTip: Tip {
    /// One donation per launch. The first launch is for the answer itself (the tip would sit over the
    /// place the score is for), so the dial's hidden gesture is offered from the second launch on.
    static let launched=Tips.Event(id:"nyx.launched")
    var rules: [Rule] { #Rule(Self.launched) { $0.donations.count >= 2 } }
    var title: Text { Text("Drag across the dial") }
    var message: Text? { Text("Step through the next two weeks. Each night shows the darkest place in reach.") }
    var image: Image? { Image(systemName:"hand.draw") }
}
