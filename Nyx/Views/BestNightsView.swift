import SwiftUI

/// Plan's first mode, "Best nights": the best night of the next 30 among every place in reach of the
/// one starting point and radius, then each other place at its best. Worked out on this device from
/// the forecasts at hand (a refresh that is due is asked for, as the trip planner does) and each
/// place's usual clouds; nothing it ranks changes Tonight's answer or what the widgets and Apple Watch follow.
struct BestNightsView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
    @State private var ranking:BestNightsInReach?
    /// A save from a place's menu could not be stored.
    @State private var saveFailed=false
    @State private var choosing=false
    @State private var explaining=false
    @State private var width=0.0
    private var wide:Bool { WideLayout.columns(width:width,largeText:typeSize.isAccessibilitySize)==2 }
    /// Abroad, the world catalogue must arrive before "in reach" means anything; and caches the loader
    /// is about to replace are never ranked (Tonight waits for the same).
    private var loading:Bool {
        if DebugScenario.state=="loading" || model.cachesPending { return true }
        guard !model.catalogIsReady, let from=model.reachOrigin else { return false }
        return !USOutline.contains(latitude:from.latitude,longitude:from.longitude)
    }
    /// Ranked again when the places in reach, the radius, the day or the data change.
    private var key:String {
        guard !loading else { return "loading" }
        let places=model.placesInReach().places
        return "\(TonightReach.key(places))-\(Int(model.radiusMeters))-\(model.dataRevision)-\(Int(Calendar.current.startOfDay(for:model.today).timeIntervalSince1970))"
    }
    var body: some View {
        ScrollView {
            if wide {
                // The two columns meet at iPhone Duo's fold on its inner display, half open or flat. The
                // answer leads the first column, above where it is measured from; the places follow beside it.
                FoldColumns(narrow:.leading,narrowMax:420,spacing:NyxMetrics.columnGap) {
                    VStack(alignment:.leading,spacing:24) { intro; answer; startingPoint }.frame(maxWidth:.infinity,alignment:.leading)
                    VStack(alignment:.leading,spacing:24) { others }.frame(maxWidth:.infinity)
                }.padding(NyxMetrics.pagePadding).readableColumn(WideLayout.twoColumnMaximum)
            } else {
                VStack(alignment:.leading,spacing:24) {
                    // At accessibility sizes the answer comes first, so its score is on the first screen.
                    if typeSize.isAccessibilitySize { answer; intro } else { intro; answer }
                    others
                    startingPoint
                }.padding(24).readableColumn()
            }
        }
        .measuringWidth($width)
        .foldSource()
        .defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top)
        .background(NightBackground(seed:"best",park:ranking?.best?.park,night:ranking?.best?.id))
        .modifier(StartingPointSheets(choosing:$choosing,explaining:$explaining))
        .parkSaveAlert(isPresented:$saveFailed,journalUnavailable:model.journalUnavailable)
        .task(id:key) { await rank(key) }
        // Cached forecasts are enough to rank; a refresh that is already due arrives in the background.
        // Closures rank as well as show, so the parks' alerts are asked for here as on a park's page; a
        // capture reads the cached ones (`refreshParkUpdates` asks the network only when live).
        .task {
            if DebugScenario.screen == nil { await model.refreshForecasts(watching:[]) }
            await model.refreshParkUpdates([])
        }
    }
    /// One plain line on what this mode answers; Plan's bar already names the page. Before a starting
    /// point is chosen the answer is from the example town, and says so, as Tonight does.
    private var intro:some View {
        VStack(alignment:.leading,spacing:6) {
            Text("The darkest night at each place in reach, over the next 30 nights.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if !model.startChosen { Text("Example: from \(model.originName)").font(.caption.weight(.medium)).foregroundStyle(palette.ink) }
        }
    }
    private var startingPoint:some View {
        StartingPointPanel(heading:true,choose:{ choosing=true },nearMe:{ StartingPointSheets.nearMe(model) { explaining=true } })
    }
    /// The best night in reach, or why there is none yet.
    @ViewBuilder private var answer:some View {
        if !loading, let ranking, let best=ranking.best {
            BestNightHero(night:best,closure:ranking.closures[best.park.id]) { saveFailed=true }
        } else if !loading, ranking != nil {
            CalmState(symbol:"moon.stars",title:"A little farther from here",message:"No parks or dark-sky places fall inside this radius. Widen it or choose a different starting point.")
        } else {
            // Gone at once when the answer lands: faded out beside the arriving rows it could be left behind.
            ProgressView().frame(maxWidth:.infinity,minHeight:120).accessibilityLabel("Ranking the nights in reach").transition(.identity)
        }
    }
    /// The hero is the first place; the list goes on from the second.
    @ViewBuilder private var others:some View {
        if !loading, let ranking, ranking.best != nil {
            let others=Array(ranking.rows.dropFirst())
            VStack(alignment:.leading,spacing:12) {
                if !others.isEmpty {
                    Eyebrow(text:"Other places, each at its best")
                    VStack(spacing:0) {
                        ForEach(others) { row in
                            self.row(row.best,closure:ranking.closures[row.id])
                            if row.id != others.last?.id { Divider().overlay(palette.line) }
                        }
                    }
                }
                notes(ranking)
            }
        }
    }
    @ViewBuilder private func notes(_ ranking:BestNightsInReach)->some View {
        Group {
            if ranking.inReach>ranking.total { Text("Ranked from the \(ranking.total) places with the darkest skies nearest your starting point, of \(ranking.inReach) in reach.") }
            else if ranking.total>ranking.rows.count { Text("The \(ranking.rows.count) best of \(ranking.total) places in reach.") }
            // A closure moves a place down without changing its score, so a lower number can lead: say why.
            if ranking.rows.contains(where:{ ranking.closures[$0.id] != nil }) { Text("A place with a closure in its latest park alert ranks lower. Its score stays the same.") }
            if ranking.rows.contains(where:{ $0.best.basis != .forecast }) { Text("Nights past the forecast are ranked on each place's usual clouds and the Moon. Check again as they come closer.") }
        }.font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
    }
    /// The place and its night beside the score; at accessibility sizes the score goes underneath, as
    /// the trip planner's stays do, so a long name keeps the width.
    private func row(_ night:Night,closure:String?)->some View {
        let park=night.park
        let words=VStack(alignment:.leading,spacing:4) {
            Text(park.shortName).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).multilineTextAlignment(.leading)
            // The night, then what it rests on in the hero's words ("Thu, Nov 5, usual clouds"; the
            // hero says "Excellent, usual clouds"), so one screen says it one way. The note below explains them.
            Text(night.score.withBasis(park.dayLabel(night.id))).font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(.leading)
            if let closure { ClosureLabel(closure) }
            AccessNoteLabel(park:park,alignment:.leading)
        }.fixedSize(horizontal:false,vertical:true)
        let score=HStack(alignment:.firstTextBaseline,spacing:6) {
            Text("\(night.score.value)").scoreNumeral(.title,accent:palette.accent)
            Text(night.score.band.label).font(.caption).foregroundStyle(palette.muted)
        }
        return NavigationLink { ParkDetailView(park:park,initialDate:night.id).onAppear { ReviewPrompt.noteNightViewed(score:night.score.value) } } label:{
            Group {
                if typeSize.isAccessibilitySize { VStack(alignment:.leading,spacing:6) { words; score } }
                else { HStack(alignment:.firstTextBaseline,spacing:12) { words; Spacer(minLength:8); score } }
            }.padding(.vertical,12).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(BestNightsInReach.spoken(night,closure:closure))
        .accessibilityHint("Opens that night at the park.")
        .accessibilityAddTraits(.isButton)
        .parkRowActions(park) { saveFailed=true }
    }
    /// Each place's next 30 nights, worked out off the main thread first (`prepareNights`), then
    /// scored as every other screen scores them, so the numbers match the park pages exactly. Abroad a
    /// radius can hold hundreds of places: a shortlist is ranked (`PlanModel.shortlist`). The result
    /// is kept by its key in the model, so coming back to the page shows it at once.
    private func rank(_ key:String) async {
        guard key != "loading" else { return }
        if let kept=model.bestNightsKept, kept.key==key { ranking=kept.ranking; return }
        try? await Task.sleep(for:.milliseconds(150))
        guard !Task.isCancelled else { return }
        let all=model.placesInReach().places
        let pool=model.shortlist(all)
        await model.prepareNights(pool,count:NightPlanner.horizon)
        guard !Task.isCancelled else { return }
        let months=pool.map { model.nights($0,from:model.tonight($0),count:NightPlanner.horizon) }
        let closed=Dictionary(pool.compactMap { park in model.closure(park).map { (park.id,$0) } },uniquingKeysWith:{ first,_ in first })
        let result=BestNightsInReach.make(months,closures:closed,inReach:all.count)
        model.bestNightsKept=(key,result)
        // The first answer simply appears; a later one (a new radius or day) moves on the shared spring.
        withAnimation(reduceMotion || ranking == nil ? nil : NyxMotion.spring) { ranking=result }
    }
}
/// "The best night", one place's best night as a hero, on Best nights and in the trip planner alike:
/// one row of small capitals over the place, the night, the numeral, then the band and what it rests on
/// as a quiet line under it (never a second heading). A closure sits directly under the score, on a
/// dark scrim (`ClosureLabel`). A tap opens that night; a long press is the park row's menu
/// (`parkRowActions`), as every place standing in a list has.
struct BestNightHero: View {
    @Environment(\.nyx) private var palette
    @MotionReduced private var reduceMotion: Bool
    /// The numeral, scaling with Dynamic Type but never past the screen.
    @ScaledMetric(relativeTo:.largeTitle) private var heroSize=96.0
    let night: Night
    let closure: String?
    /// Why this night (the trip planner's reason), under the closure.
    var reason: String?=nil
    /// A save from the menu could not be stored.
    let failed: ()->Void
    var body: some View {
        let park=night.park
        NavigationLink { ParkDetailView(park:park,initialDate:night.id).onAppear { ReviewPrompt.noteNightViewed(score:night.score.value) } } label:{
            VStack(spacing:10) {
                Eyebrow(text:"The best night",meta:true)
                Text(park.shortName).font(.system(.title,design:.serif)).multilineTextAlignment(.center).foregroundStyle(palette.ink)
                Text(park.dayLabel(night.id)).font(.subheadline).foregroundStyle(palette.muted)
                Text("\(night.score.value)").scoreNumeral(size:min(heroSize,150),accent:palette.accent)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value:Double(night.score.value)))
                Text(night.bandWithBasis).font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(.center)
                if let closure { ClosureLabel(closure,prominence:.hero) }
                if let reason { Text(reason).font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true) }
                AccessNoteLabel(park:park,alignment:.center)
            }.frame(maxWidth:.infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityElement(children:.combine)
        .accessibilityHint("Opens that night at the park.")
        .parkRowActions(park,failed:failed)
    }
}
#Preview("The best night") {
    let m=PlanModel()
    if let p=m.home { NavigationStack { BestNightHero(night:m.night(p),closure:nil) {}.padding(24) }.environment(m).background(.black).preferredColorScheme(.dark) }
}
#Preview("The best night • closure, reason, AX5") {
    let m=PlanModel()
    if let p=m.home {
        NavigationStack { ScrollView { BestNightHero(night:m.night(p),closure:"Keys View Road closed at night",reason:"Moon-free through all of true darkness") {}.padding(24) } }
            .environment(m).background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
    }
}
#Preview("Best nights") { NavigationStack { BestNightsView() }.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Best nights AX5") { NavigationStack { BestNightsView() }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
