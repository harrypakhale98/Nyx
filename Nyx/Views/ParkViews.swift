import SwiftUI
import SwiftData
import TipKit

/// How a visitor reaches the night sky, for parks a car cannot simply drive to: one calm line
/// wherever a park is recommended. Nothing for the parks you can drive into.
struct AccessNoteLabel: View {
    @Environment(\.nyx) private var palette
    let park: Park
    var alignment: HorizontalAlignment = .leading
    var body: some View {
        if let note=park.accessNote {
            Label { Text(note).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:park.drivable ? "road.lanes" : "ferry") }
                .font(.caption).foregroundStyle(palette.muted)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(String(localized:"Getting there: \(note)"))
        }
    }
}
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
            // Short, so a list of 63 parks is quick to swipe through: the name, the score, the band and
            // any closure. The rest is a "More content" swipe away (the closure first there too).
            .accessibilityLabel(ParkRow.spokenLabel(night:night,closure:closure))
            .modifier(ParkRowContent(items:ParkRow.moreContent(night:night,closure:closure,week:week,stepFree:stepFree)))
    }
    /// "Zion. Darkness score 88, Excellent. Closure alert: Kolob Canyons Road closed."
    static func spokenLabel(night:Night,closure:String?)->String {
        let main=String(localized:"\(night.park.shortName). Darkness score \(night.score.value), \(night.score.band.label).")
        return closure.map { main+" "+String(localized:"Closure alert: \($0)") } ?? main
    }
    /// The row's custom content, most important first.
    static func moreContent(night:Night,closure:String?,week:[Night],stepFree:Bool)->[ParkRowContent.Item] {
        var items:[ParkRowContent.Item]=[]
        if let closure { items.append(.init(label:String(localized:"Closure alert"),value:closure,high:true)) }
        items.append(.init(label:String(localized:"Clouds"),value:night.basisLabel ?? String(localized:"Cloud forecast included"),high:false))
        if let summary=WeekStrip.summary(week) { items.append(.init(label:String(localized:"This week"),value:summary,high:false)) }
        if stepFree { items.append(.init(label:String(localized:"Step-free viewing"),value:String(localized:"Yes"),high:false)) }
        if !night.park.drivable { items.append(.init(label:String(localized:"Getting there"),value:String(localized:"No road access"),high:false)) }
        items.append(.init(label:String(localized:"State"),value:night.park.state.replacingOccurrences(of:",",with:", "),high:false))
        return items
    }
    private var names: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(night.park.shortName).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            Text("\(night.park.state.replacingOccurrences(of:",",with:" · "))\(night.park.darkSkyDesignated ? " · "+String(localized:"Dark Sky designated") : "")").font(.caption).foregroundStyle(palette.muted)
            if stepFree { Label("Step-free viewing",systemImage:"figure.roll").font(.caption).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
            if !night.park.drivable { Label("No road access",systemImage:"ferry").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            if week.count>1 { WeekStrip(nights:week).padding(.top,4) }
        }
    }
    private var number: some View {
        // The score never wraps, whatever the column width; the name beside it does.
        VStack(alignment:typeSize.isAccessibilitySize ? .leading : .trailing,spacing:2) { Text("\(night.score.value)").font(.system(.largeTitle,design:.serif)).foregroundStyle(palette.accent); Text(night.compactBandLabel).font(.caption2).foregroundStyle(palette.muted) }.fixedSize()
    }
}
/// A row's "More content" for VoiceOver (`accessibilityCustomContent`).
struct ParkRowContent: ViewModifier {
    struct Item: Equatable { let label: String; let value: String; let high: Bool }
    let items: [Item]
    func body(content:Content)->some View {
        items.reduce(AnyView(content)) { view,item in
            AnyView(view.accessibilityCustomContent(Text(item.label),Text(item.value),importance:item.high ? .high : .default))
        }
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
    @Environment(\.modelContext) private var context
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Query(sort:\SavedPark.savedAt) private var saved: [SavedPark]
    /// Beside the park on a wide iPad: rows choose the park shown in the detail column instead of pushing it.
    var selection: Binding<String?>?=nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var searchFocused: Bool
    @State private var search=""
    @State private var darkOnly=false
    @State private var stepFreeOnly=DebugScenario.state=="step-free"
    @State private var savedOnly=false
    @State private var saveFailed=false
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
                if typeSize.isAccessibilitySize { InlineSearchField(text:$search,prompt:"Park or state",focus:$searchFocused) }
                // Only worth saying when a row actually reads "Estimate".
                if filtered.contains(where:{ model.night($0).basis == .usual }) { Text("Scores marked Estimate have no cloud forecast yet and use each park's usual clouds.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
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
            // VoiceOver rotors: jump straight to the parks with a closure alert, or a Pristine sky tonight.
            .accessibilityRotor(Text("Closures"),entries:rotor { park in model.closure(park).map { String(localized:"\(park.shortName): \($0)") } },entryID:\.id,entryLabel:\.label)
            .accessibilityRotor(Text("Pristine nights"),entries:rotor { park in
                let night=model.night(park); return night.score.value>=90 ? String(localized:"\(park.shortName), \(night.score.value)") : nil
            },entryID:\.id,entryLabel:\.label)
        }.background(NightBackground()).navigationTitle("Parks").navigationBarTitleDisplayMode(.inline)
            .modifier(SystemSearch(text:$search,focused:$searchFocused,prompt:"Park or state",enabled:!typeSize.isAccessibilitySize))
            .alert("Unable to save",isPresented:$saveFailed) { Button("OK",role:.cancel) {} } message:{ Text("Your changes could not be stored. Try again when space is available.") }
            // ⌘F from anywhere in the window.
            .onChange(of:commands?.searchRequest) { _,_ in focusSearchIfAsked() }
            .onAppear { focusSearchIfAsked() }
            // One request brings cloud forecasts for all 63 parks, so every score can include clouds.
            .task { await model.refresh(model.parks,parkUpdates:false) }
            .refreshable { await model.refresh(model.parks,force:true,parkUpdates:false) }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Menu {
                Picker("Sort",selection:$byScore) { Label("Name",systemImage:"textformat").tag(false); Label("Darkest tonight",systemImage:"moon.stars").tag(true) }
                Section { Toggle("Dark Sky designated only",isOn:$darkOnly); Toggle("Step-free viewing",isOn:$stepFreeOnly); Toggle("Saved parks only",isOn:$savedOnly) }
            } label:{ Image(systemName:"line.3.horizontal.decrease") }.accessibilityLabel("Sort and filter parks").accessibilityInputLabels([Text("Filter"),Text("Sort"),Text("Sort and filter")]) } }
            .navigationDestination(for:Park.self) { park in ParkDetailView(park:park).modifier(ParkTransition(sourceID:park.id,namespace:zoom)) }
    }
    struct RotorPark: Identifiable { let id: String; let label: String }
    /// One rotor stop for each park on screen that `label` names, in the order shown.
    private func rotor(_ label:(Park)->String?)->[RotorPark] {
        let sectioned = showsSavedSection
        let first=sectioned ? model.parks.filter { p in saved.contains { $0.parkID==p.id } } : []
        let rest=filtered.filter { p in !(sectioned && saved.contains { $0.parkID==p.id }) }
        return (first+rest).compactMap { park in label(park).map { RotorPark(id:park.id,label:$0) } }
    }
    @ViewBuilder private func link(_ park:Park)->some View {
        let row=ParkRow(night:model.night(park),closure:model.closure(park),week:model.nights(park,from:model.tonight(park),count:7),stepFree:stepFreeOnly)
        if let selection {
            let chosen=selection.wrappedValue==park.id
            Button { selection.wrappedValue=park.id } label:{
                row.padding(.horizontal,12).background(RoundedRectangle(cornerRadius:16).fill(palette.accent.opacity(chosen ? (palette.nightVision ? 0.22 : 0.13) : 0))).padding(.horizontal,-12)
                    .contentShape(.hoverEffect,RoundedRectangle(cornerRadius:16).inset(by:-2))
            }.buttonStyle(.plain).hoverEffect(.highlight)
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .contextMenu { rowMenu(park) }
        } else {
            NavigationLink(value:park) { row }.buttonStyle(.plain).matchedTransitionSource(id:park.id,in:zoom).hoverEffect(.highlight).contextMenu { rowMenu(park) }
        }
    }
    /// Long press, or a secondary click with a pointer.
    @ViewBuilder private func rowMenu(_ park:Park)->some View {
        let isSaved=saved.contains { $0.parkID==park.id }
        Button(isSaved ? "Unsave park" : "Save park",systemImage:isSaved ? "bookmark.slash" : "bookmark") {
            if let item=saved.first(where:{ $0.parkID==park.id }) { context.delete(item) } else { context.insert(SavedPark(parkID:park.id)) }
            do { try context.save() } catch { context.rollback();saveFailed=true }
        }
        Button("Show in Calendar",systemImage:"calendar") { model.calendarRequest=CalendarRequest(parkID:park.id,year:nil,month:nil); commands?.tab=2 }
    }
    private func focusSearchIfAsked() {
        guard commands?.takeSearch() == true else { return }
        Task { try? await Task.sleep(for:.milliseconds(250)); searchFocused=true }
    }
}
/// A park's page in three chapters on one scroll: **Tonight** (the score with any closure beside
/// it, the best window, the river and what to check before you go), **The sky** (the real sky,
/// the shape of the night, what's up, the Moon at size, clouds and air) and **The place** (sky
/// glow, spots, ranger programs, what protects this sky, the park in the Park Service's words).
/// A pinned segmented index jumps between them and follows the scroll; at accessibility sizes it
/// steps aside and the chapter headings carry the page (they are VoiceOver headings throughout).
enum ParkChapter: String, CaseIterable, Identifiable, Hashable {
    case tonight, sky, place
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .tonight: "Tonight"
        case .sky: "The sky"
        case .place: "The place"
        }
    }
    /// The chapter in view: the last whose top has reached the reading line under the index.
    static func current(tops:[ParkChapter:CGFloat],line:CGFloat)->ParkChapter {
        allCases.last { (tops[$0] ?? .infinity)<=line } ?? .tonight
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
    /// Opened from a link to that night's What's up (`nyx://whatsup`): scroll there once.
    var focusWhatsUp=false
    @State private var selected:Date?
    @State private var breakdown=false
    @State private var persistenceError=false
    @State private var scrubbing=false
    @State private var width=0.0
    @State private var chapter=ParkChapter.tonight
    /// Chapter positions, kept out of observation so scrolling never re-evaluates the page.
    @State private var tracker=ChapterTracker()
    @State private var titleGone=false
    @State private var showsSky=DebugScenario.isEnabled("sky-view")
    @State private var description=false
    private var night:Night { model.night(park,on:selected ?? initialDate ?? model.tonight(park)) }
    private var isTonight:Bool { night.id==model.tonight(park) }
    private var isSaved:Bool { saved.contains{$0.parkID==park.id} }
    private var outlook:NightOutlook? { model.outlook(night) }
    /// Agreement and the cloud layer, under the cloud figure.
    private var cloudContext:[String] {
        guard let outlook else { return [] }
        return [outlook.agreement?.sentence(tonight:isTonight),night.upperCloudOnly ? nil : outlook.layers?.note].compactMap { $0 }
    }
    /// The cloud figure beside "Clouds": the forecast's average, else the park's usual cloud.
    private var cloudValue:String {
        if let cloud=night.cloudCover { return String(localized:"\(Int(cloud.rounded()))% average") }
        if let usual=night.usualCloud { return String(localized:"Usually \(Int(usual.rounded()))%") }
        return String(localized:"Unavailable")
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
    /// Two columns on a wide iPad: tonight (gauge, river, access) stays in view on the left while
    /// the sky and the place scroll on the right. One readable column otherwise.
    private var wide:Bool { WideLayout.columns(width:width,largeText:typeSize.isAccessibilitySize)==2 }
    /// The pinned index: one column, standard text sizes (segments do not grow with the text).
    private var showsIndex:Bool { !wide && !typeSize.isAccessibilitySize }
    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if wide {
                    HStack(alignment:.top,spacing:0) {
                        ScrollView { VStack(spacing:26) { tonightChapter(proxy) }.padding(24) }
                            .scrollDisabled(scrubbing).frame(width:WideLayout.leadingWidth(width))
                        ScrollView { VStack(spacing:26) { skyChapter; placeChapter }.padding(24) }
                    }
                } else {
                    ScrollView {
                        VStack(spacing:26) {
                            tonightChapter(proxy).modifier(ChapterTop(chapter:.tonight,report:report))
                            skyChapter.modifier(ChapterTop(chapter:.sky,report:report))
                            placeChapter.modifier(ChapterTop(chapter:.place,report:report))
                        }.padding(24).readableColumn()
                    }
                    .scrollDisabled(scrubbing)
                    .safeAreaBar(edge:.top) { if showsIndex { index(proxy) } }
                }
            }
            .onPreferenceChange(RiverScrubbingKey.self) { scrubbing=$0 }
            .task {
                // DEBUG store capture (`-nyx-listen`): the shape of the night at the top.
                if DebugScenario.isEnabled("listen") {
                    try? await Task.sleep(for:.milliseconds(500))
                    proxy.scrollTo("sky",anchor:.top); return
                }
                #if DEBUG
                // DEBUG captures: `-nyx-chapter sky|place|moon|spots|programs` opens at that part of the page.
                if let target=ProcessInfo.processInfo.arguments.firstIndex(of:"-nyx-chapter").flatMap({ ProcessInfo.processInfo.arguments.dropFirst($0+1).first }) {
                    try? await Task.sleep(for:.milliseconds(700))
                    proxy.scrollTo(ParkChapter(rawValue:target).map { AnyHashable($0) } ?? AnyHashable(target),anchor:.top); return
                }
                // DEBUG promo capture (`-nyx-demo-river`): the river in view, then a slow scrub along its
                // thirty nights and back to the best one, as a finger would drag it. Never in Release.
                if DebugScenario.isEnabled("demo-river") {
                    try? await Task.sleep(for:.milliseconds(600))
                    proxy.scrollTo("river",anchor:.center)
                    try? await Task.sleep(for:.seconds(2.5))
                    let nights=model.nights(park,from:riverStart,count:30)
                    for night in nights { guard !Task.isCancelled else { return }; selected=night.id; try? await Task.sleep(for:.milliseconds(110)) }
                    let best=nights.prefix(20).max { $0.score.value < $1.score.value }
                    for night in nights.reversed() where night.id >= (best?.id ?? night.id) { guard !Task.isCancelled else { return }; selected=night.id; try? await Task.sleep(for:.milliseconds(70)) }
                    return
                }
                #endif
                guard focusWhatsUp else { return }
                // After the zoom or sheet settles, so the scroll reads as arriving rather than jumping.
                try? await Task.sleep(for:.milliseconds(500))
                withAnimation(reduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo("whatsup",anchor:.top) }
            }
        }
        .measuringWidth($width)
        // iPad keyboard: ⌘← and ⌘→ move along the river, as dragging it does.
        .nightKeys { delta in step(delta) }
        // Left open past sunrise, the river moves on to the new tonight; a chosen night that has
        // dropped off it is released, so the gauge and the river always show the same night.
        .onChange(of:riverStart) { _,start in
            if let chosen=selected, chosen<start || chosen>=park.date(start,addingDays:30) { selected=nil }
        }
        .onAppear { KeepThisNight.container=context.container }
        .defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top).background(NightBackground(seed:park.id,score:night.score.value,park:park,night:night.id)).navigationTitle(park.shortName).navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }.modifier(SkyFullBleed(enabled:!wide))
            .sheet(isPresented:$breakdown) { NavigationStack { ScoreBreakdownView(night:night,isTonight:isTonight) }.nyxPresentation().presentationDetents([.large]) }
            .fullScreenCover(isPresented:$showsSky) { TonightSkyView(night:night,isTonight:isTonight).environment(\.nyx,palette).nyxPresentation() }
            .alert("Unable to save",isPresented:$persistenceError) { Button("OK",role:.cancel) {} } message:{ Text("Your changes could not be stored. Try again when space is available.") }
            .task { await model.prepareWhatsUp(model.nights(park,from:riverStart,count:30)) }
            .task { await model.refresh([park],programs:true) }
            .refreshable { await model.refresh([park],force:true,programs:true) }
    }
    private func report(_ which:ParkChapter,_ top:CGFloat) {
        tracker.tops[which]=top
        let now=ParkChapter.current(tops:tracker.tops,line:showsIndex ? 140 : 100)
        if now != chapter { chapter=now }
    }
    private func step(_ delta:Int) {
        let next=park.date(night.id,addingDays:delta)
        guard next>=riverStart, next<park.date(riverStart,addingDays:30) else { return }
        withAnimation(reduceMotion ? nil : NyxMotion.spring) { selected=next }
    }
    private func index(_ proxy:ScrollViewProxy)->some View {
        Picker("Chapter",selection:Binding(get:{ chapter },set:{ target in
            chapter=target
            withAnimation(reduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo(target,anchor:.top) }
        })) { ForEach(ParkChapter.allCases) { Text($0.title).tag($0) } }
        .pickerStyle(.segmented)
        .padding(.horizontal,24).padding(.vertical,6)
        .frame(maxWidth:WideLayout.proseWidth)
        .accessibilityLabel("Jump to a part of the page")
    }
    // MARK: Tonight

    @ViewBuilder private func tonightChapter(_ proxy:ScrollViewProxy)->some View {
        hero(proxy)
        river
        alerts
    }
    /// The park's state and Dark Sky status: the eyebrow carries data, not a slogan.
    private var eyebrow:String {
        let state=park.state.replacingOccurrences(of:",",with:" · ")
        return park.darkSkyDesignated ? String(localized:"\(state) · International Dark Sky Park") : state
    }
    private func hero(_ proxy:ScrollViewProxy)->some View {
        VStack(spacing:12) {
            Eyebrow(text:"\(eyebrow)")
            Text(park.shortName).font(.system(.largeTitle,design:.serif)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                .onGeometryChange(for:Bool.self) { $0.frame(in:.scrollView).maxY<0 } action:{ titleGone=$0 }
            Text(park.dayLabel(night.id)).font(.subheadline).foregroundStyle(palette.muted)
            // The closure is the one line that must never be lost in the sky: on a dark scrim, beside the score.
            if let closure=model.closure(park) {
                Label(closure,systemImage:"exclamationmark.triangle").font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.center)
                    .fixedSize(horizontal:false,vertical:true)
                    .padding(.horizontal,12).padding(.vertical,6).background(Color.black.opacity(0.6),in:RoundedRectangle(cornerRadius:12))
                    .accessibilityLabel(String(localized:"Closure alert: \(closure)"))
            }
            if otherAlerts>0 {
                Button { withAnimation(reduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo("alerts",anchor:.top) } } label:{
                    Label("Before you go (\(otherAlerts))",systemImage:"exclamationmark.shield").font(.footnote.weight(.medium)).frame(minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(palette.ink)
                .accessibilityHint("Shows the park's other alerts.")
            }
            AccessNoteLabel(park:park,alignment:.center).frame(maxWidth:420).padding(.horizontal,12)
            // The dial opens at the bottom; let the lines below tuck into that space.
            CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast)
                .padding(.bottom,typeSize.isAccessibilitySize ? 0 : -28)
                .scrollTransition { [motionReduced = reduceMotion] view,phase in view.scaleEffect(motionReduced || phase.isIdentity ? 1 : 0.95).opacity(motionReduced || phase.isIdentity ? 1 : 0.8) }
                .modifier(DepthParallax(depth:0.1))
            if night.sky.state == .polarNight { Text("The Sun stays below the horizon today.").font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(.center) }
            if night.sky.darkHours==0 { Text(SkyConditions.noDarknessMessage(tonight:isTonight)).font(.body).foregroundStyle(palette.accent).multilineTextAlignment(.center) }
            if let caption=night.basisCaption(unavailable:!model.beyondForecast(night),typical:true) { Text(caption).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center) }
            if let smoke=model.smokeCaveat(night) { Label(smoke,systemImage:"smoke").font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true).padding(.horizontal,12) }
            if let window=model.clearWindow(night) {
                // At accessibility sizes the glyph would take a column of its own: the words alone.
                Label { Text(window.line(park:park)).fixedSize(horizontal:false,vertical:true) } icon:{ if !typeSize.isAccessibilitySize { Image(systemName:"sparkles").accessibilityHidden(true) } }
                    .font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(.center).padding(.horizontal,12)
                    .accessibilityElement(children:.combine)
            }
            ScoreReadout(score:night.score,agreement:outlook?.agreement,isTonight:isTonight) { breakdown=true }.padding(.top,typeSize.isAccessibilitySize ? 8 : 18)
                .popoverTip(DebugScenario.screen == nil && !palette.nightVision ? ScoreTip() : nil)
            if isTonight { FieldEntry(park:park,night:night).padding(.top,typeSize.isAccessibilitySize ? 4 : 10) }
            KeepThisNightOffer(park:park).padding(.top,4)
        }
    }
    /// Alerts other than the closure shown beside the score.
    private var otherAlerts:Int {
        let alerts=model.enrichments[park.id]?.alerts ?? []
        return alerts.count-(model.closure(park) == nil ? 0 : 1)
    }
    private var river: some View {
        Panel {
            let river=model.nights(park,from:riverStart,count:30)
            TimeRiver(nights:river,selected:Binding(get:{selected ?? initialDate ?? model.tonight(park)},set:{selected=$0}),startsTonight:riverStart==model.tonight(park),outlooks:model.outlooks(river),markers:model.markers(river),open:{ _ in breakdown=true })
            if model.detailPausedForLowData { Label("Forecast detail paused in Low Data Mode.",systemImage:"antenna.radiowaves.left.and.right.slash").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).padding(.top,8) }
            Divider().overlay(palette.line).padding(.top,10)
            AddNightToCalendar(night:night)
        }.id("river")
    }
    private var alerts: some View {
        Panel { VStack(alignment:.leading,spacing:8) {
            Label(otherAlerts>0 ? "Before you go (\(otherAlerts))" : "Before you go",systemImage:"exclamationmark.shield").font(.subheadline.weight(.medium)).accessibilityAddTraits(.isHeader)
            Text(model.alertSummary(park)).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if model.alertsBusy { AlertsBusyNote(park:park,summarySaysBusy:model.enrichments[park.id] == nil) }
            if let data=model.enrichments[park.id],!data.alerts.isEmpty {
                DisclosureGroup {
                    ForEach(AlertRanking.ranked(data.alerts)) { alert in VStack(alignment:.leading,spacing:8) { Text(alert.displayTitle(park:park)).font(.headline).accessibilityAddTraits(.isHeader);Text(alert.description).font(.subheadline).foregroundStyle(palette.muted) }.padding(.vertical,8) }
                } label:{ Text("All park alerts (\(data.alerts.count))").frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }
            }
            if let data=model.enrichments[park.id] { Text("Park update: \(park.timestamp(data.updated))").font(.caption).foregroundStyle(palette.muted) }
        } }.id("alerts")
    }
    // MARK: The sky

    private func chapterHeading(_ chapter:ParkChapter,detail:String)->some View {
        VStack(alignment:.leading,spacing:4) {
            Eyebrow(text:"\(detail)")
            Text(chapter.title).font(.system(.title,design:.serif)).foregroundStyle(palette.ink).accessibilityAddTraits(.isHeader)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.top,typeSize.isAccessibilitySize ? 8 : 18)
    }
    @ViewBuilder private var skyChapter: some View {
        chapterHeading(.sky,detail:park.dayLabel(night.id))
        SkyWindowCard(night:night,isTonight:isTonight) { showsSky=true }
        Panel { VStack(alignment:.leading,spacing:16) {
            SkyArc(night:night,isTonight:isTonight,core:model.whatsUp(night).core)
            Divider().overlay(palette.line)
            SoundAndTouchRow(night:night,isTonight:isTonight,expanded:DebugScenario.isEnabled("listen"))
        } }.id("sky")
        Panel {
            VStack(alignment:.leading,spacing:18) {
                WhatsUpPanel(whatsUp:model.whatsUp(night),isTonight:isTonight,notes:model.skyNotes(night))
                // Tonight's wake-ups (AlarmKit), beside the moments they are for.
                if FieldAlarms.supported, isTonight {
                    let options=FieldNight.alarmOptions(park:park,sky:night.sky,at:DebugScenario.date ?? .now)
                    if !options.isEmpty { Divider().overlay(palette.line); FieldAlarmRows(park:park,options:options,showsHeading:true) }
                }
            }
        }.id("whatsup")
        Panel {
            VStack(alignment:.leading,spacing:18) {
                Eyebrow(text:"Moonlight")
                MoonHero(night:night) { delta in step(delta) }
                Text("Below the horizon for \(Int((night.sky.moonBelowFraction*100).rounded()))% of true darkness.").font(.caption).foregroundStyle(palette.muted).frame(maxWidth:.infinity)
                    .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            }
        }.id("moon")
        Panel { VStack(alignment:.leading,spacing:16) {
            Eyebrow(text:"Clouds and the air")
            VStack(alignment:.leading,spacing:6) {
                LabeledContent("Clouds",value:cloudValue)
                if night.upperCloudOnly { Text("The summit sits above most low cloud, so the score counts mid and high cloud only.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                ForEach(cloudContext,id:\.self) { line in Text(line).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            }
            if let clarity=outlook?.clarity {
                VStack(alignment:.leading,spacing:6) {
                    LabeledContent("Air",value:clarity.label)
                    Text("Smoke and haze forecast from Copernicus (CAMS), the European atmosphere service. Not part of the score.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
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
        } }
    }
    // MARK: The place

    @ViewBuilder private var placeChapter: some View {
        chapterHeading(.place,detail:eyebrow)
        Panel { VStack(alignment:.leading,spacing:12) { Eyebrow(text:"Sky glow"); LightPollution(park:park) } }
        Panel { ViewingSpots(park:park) }.id("spots")
        // Where to stay draws its own panel; campgrounds come from the same all-parks NPS data, kept a week.
        WhereToStayPanel(park:park).id("stay")
        Panel { VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:"Ranger night-sky programs")
            if let data=model.enrichments[park.id] {
                let programs=data.programs.filter{$0.date>=park.isoDay(model.today)}
                if programs.isEmpty && data.programsUpdated == nil { Text("Programs could not be checked in the last update. Ask at the visitor center for current night-sky programs.").foregroundStyle(palette.muted) }
                else if programs.isEmpty { Text("No upcoming programs in the last update. Ask at the visitor center.").foregroundStyle(palette.muted) }
                ForEach(programs) { program in ProgramCard(park:park,program:program) }
            } else { Text("Programs are not checked yet. Ask at the visitor center for current night-sky programs.").foregroundStyle(palette.muted) }
        } }.id("programs")
        Panel { ProtectThisSky(park:park) }
        if !park.description.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                Eyebrow(text:"From the National Park Service")
                ClampedText(text:park.description,lines:4)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
        AboutDataLink().font(.subheadline)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // The park's name returns to the bar once its title has scrolled away, never both at once.
        ToolbarItem(placement:.principal) {
            Text(park.shortName).font(.headline).opacity(titleGone || wide ? 1 : 0).accessibilityHidden(!(titleGone || wide))
        }
        if #available(iOS 27.0,*) {
            ToolbarItem(placement:.topBarPinnedTrailing) { saveButton }
        } else { ToolbarItem(placement:.topBarTrailing) { saveButton } }
        ToolbarItem(placement:.topBarTrailing) { ShareNightMenu(night:night) }
    }
    private var saveButton:some View {
        Button { if let item=saved.first(where:{$0.parkID==park.id}) { context.delete(item) } else { context.insert(SavedPark(parkID:park.id)) }; do { try context.save() } catch { context.rollback();persistenceError=true } } label:{ Image(systemName:isSaved ? "bookmark.fill" : "bookmark") }
            .accessibilityLabel(isSaved ? "Unsave park" : "Save park")
            .accessibilityInputLabels(isSaved ? [Text("Unsave"),Text("Unsave park")] : [Text("Save"),Text("Save park")])
    }
}
/// Reports where a chapter's top sits in the scroll view, for the pinned index.
private struct ChapterTop: ViewModifier {
    let chapter: ParkChapter
    let report: (ParkChapter,CGFloat)->Void
    func body(content:Content)->some View {
        // A container, so the chapter's id and its position travel together.
        VStack(spacing:26) { content }
            .id(chapter)
            .onGeometryChange(for:CGFloat.self) { $0.frame(in:.scrollView).minY.rounded() } action:{ report(chapter,$0) }
    }
}
private final class ChapterTracker { var tops:[ParkChapter:CGFloat]=[:] }
/// Text clamped to a few lines with "More" when it runs longer; "Less" folds it again.
struct ClampedText: View {
    @Environment(\.nyx) private var palette
    let text: String
    var lines=3
    var font: Font = .subheadline
    @State private var expanded=false
    @State private var full: CGFloat=0
    @State private var clamped: CGFloat=0
    private var truncates: Bool { full>clamped+1 }
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(text).font(font).foregroundStyle(palette.muted).lineLimit(expanded ? nil : lines)
                .fixedSize(horizontal:false,vertical:true)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action:{ if !expanded { clamped=$0 } }
                .background {
                    Text(text).font(font).fixedSize(horizontal:false,vertical:true).hidden()
                        .onGeometryChange(for:CGFloat.self) { $0.size.height } action:{ full=$0 }
                        .accessibilityHidden(true)
                }
            if truncates || expanded {
                Button(expanded ? "Less" : "More") { expanded.toggle() }
                    .font(font.weight(.medium)).foregroundStyle(palette.accent).frame(minHeight:44).contentShape(Rectangle())
                    .accessibilityHint(expanded ? "Shows less." : "Shows the rest.")
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
/// A ranger program: title, when and where, then NPS's description clamped to three lines.
private struct ProgramCard: View {
    @Environment(\.nyx) private var palette
    let park: Park
    let program: RangerProgram
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(program.title).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
            Label([park.programDate(program.date),program.time].compactMap { $0 }.joined(separator:" · "),systemImage:"calendar").font(.footnote).foregroundStyle(palette.ink)
            if let location=program.location { Label(location,systemImage:"mappin.and.ellipse").font(.footnote).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
            ClampedText(text:program.description,lines:3)
        }
    }
}
/// "Listen to this night" and "Feel the Moon" in one row that opens, kept out of the visual path.
/// Both stay reachable as VoiceOver actions on the row, opened or not.
struct SoundAndTouchRow: View {
    @Environment(\.nyx) private var palette
    let night: Night
    var isTonight=true
    var expanded=false
    @State private var open: Bool?
    var body: some View {
        DisclosureGroup(isExpanded:Binding(get:{ open ?? expanded },set:{ open=$0 })) {
            VStack(alignment:.leading,spacing:14) {
                NightListenView(night:night,isTonight:isTonight,expanded:expanded)
                if MoonHaptics.enabled {
                    Button { feel() } label:{ Label("Feel the Moon",systemImage:"hand.tap").font(.subheadline.weight(.medium)).frame(minHeight:44).contentShape(Rectangle()) }
                        .buttonStyle(.nyxAction).foregroundStyle(palette.accent)
                        .accessibilityHint("Plays the Moon's phase as a texture: sharp, sparse taps for a new moon, a broad swell for a full moon.")
                }
            }.padding(.top,8)
        } label:{
            Label("Sound and touch",systemImage:"waveform").font(.subheadline.weight(.medium)).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
        }
        .tint(palette.accent)
        .accessibilityActions {
            Button(isTonight ? String(localized:"Listen to tonight") : String(localized:"Listen to this night")) { NightListener.shared.play(NightSonification(park:night.park,sky:night.sky)) }
            if MoonHaptics.enabled { Button("Feel the Moon") { feel() } }
        }
    }
    private func feel() { MoonHaptics.shared.play(.moon(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing)) }
}
struct ScoreBreakdownView: View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let night:Night
    var isTonight=true
    /// Beside the month on a wide iPad: the breakdown without its own page, background or Done.
    var inline=false
    @ScaledMetric(relativeTo:.largeTitle) private var numeralSize=72.0
    var body: some View {
        if inline { content }
        else {
            ScrollView { content.padding(24).readableColumn() }
                .background(NightBackground(score:night.score.value,park:night.park,night:night.id)).foregroundStyle(palette.ink).navigationTitle("Score breakdown").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private var content: some View {
        VStack(alignment:.leading,spacing:26) {
            VStack(alignment:.leading,spacing:10) {
                Eyebrow(text:"\(night.park.shortName) · \(night.park.dayLabel(night.id))")
                Text("A number with a reason").font(.system(.largeTitle,design:.serif)).fixedSize(horizontal:false,vertical:true)
            }
            HStack(alignment:.firstTextBaseline,spacing:12) {
                Text("\(night.score.value)").font(.system(size:numeralSize,weight:.light,design:.serif)).tracking(-3).foregroundStyle(palette.accent)
                VStack(alignment:.leading,spacing:2) { Text(night.score.band.label).font(.system(.title2,design:.serif)); Text("out of 100").font(.caption).foregroundStyle(palette.muted) }
            }
            .accessibilityElement(children:.combine)
            // The weakest link, said beside the number it sets, before the parts that add up to more.
            if let limit=night.score.limit, limit.cap<partsSum {
                if case .darkness = limit {} else {
                    Text(limit.sentence(tonight:isTonight)+" "+String(localized:"The four parts add up to \(partsSum); the score takes the lowest cap that applies.")).foregroundStyle(palette.accent).fixedSize(horizontal:false,vertical:true)
                }
            }
            row("Moonlight",points:night.score.moonPoints,of:40,fact:moonFact,detail:String(localized:"How bright the Moon is by phase and how high it stands, through true darkness. A low Moon counts for less than a high one."))
            row("Clouds",points:night.score.cloudPoints,of:25,fact:cloudFact,
                context:cloudContext,
                detail:cloudContext.isEmpty ? String(localized:"The hourly forecast averaged over true darkness. Beyond about three days it is eased toward the park's usual clouds for the month; with no forecast, the usual clouds count alone.")
                    : String(localized:"The hourly forecast averaged over true darkness, eased toward the park's usual clouds beyond about three days. Model agreement and cloud layers are context; heavy smoke can cap the score."))
            row("Sky glow",points:night.score.bortlePoints,of:20,fact:String(localized:"Bortle class \(night.park.bortleEstimate) of 9, estimated."),context:lightContext,detail:String(localized:"Artificial light in the sky, as a conservative Bortle estimate. It is not a measurement."))
            row("True darkness",points:night.score.lengthPoints,of:15,fact:night.sky.darkHours>0 ? String(localized:"\(darkness) of true darkness.") : String(localized:"No true darkness."),detail:String(localized:"True darkness: the Sun more than 18° below the horizon. Ten hours earn full credit."))
            if let caption=night.basisCaption(unavailable:!model.beyondForecast(night),typical:true) { Text(caption+" "+String(localized:"The score will change as a forecast arrives.")).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
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
        }
    }
    /// The four parts' sum before any cap, as the readout shows them.
    private var partsSum:Int { Int((night.score.moonPoints+(night.score.cloudPoints ?? 0)+night.score.bortlePoints+night.score.lengthPoints).rounded()) }
    private var cloudFact:String {
        switch night.basis {
        case .forecast: return night.cloudCover.map { String(localized:"\(Int($0.rounded()))% average cover through true darkness.") } ?? String(localized:"No forecast covers this night yet.")
        case .blended(_, let lead):
            guard let forecast=night.cloudCover, let counted=night.score.cloudUsed else { return String(localized:"An early look at the clouds.") }
            return String(localized:"Early look: a forecast of \(Int(forecast.rounded()))% from \(max(1,Int(lead.rounded()))) days out, eased toward the usual clouds. Counted as \(Int(counted.rounded()))%.")
        case .usual:
            guard let usual=night.usualCloud else { return String(localized:"No forecast covers this night yet.") }
            return String(localized:"No forecast covers this night yet. Usual cloud here this month: \(Int(usual.rounded()))%.")
        }
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
    /// `weight` is the component's share of 100; with no cloud figure at all the others are scaled up to fill it.
    /// Each part states the fact it was scored from, then how it is scored.
    private func row(_ title:LocalizedStringKey,points:Double?,of weight:Double,fact:String,context:[(symbol:String,text:String)]=[],detail:String)->some View {
        let maximum=night.score.cloudPoints != nil || points==nil ? weight : weight/0.75
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

/// iOS 27: the bars recede as the park's page scrolls down, so its sky runs edge to edge; they
/// return on the way back up. iOS 26 keeps the standard bars.
private struct SkyFullBleed: ViewModifier {
    /// Off in two columns, where the night's column stays put beside the scrolling detail and bars
    /// receding over one column would read as a glitch.
    var enabled=true
    @ViewBuilder func body(content:Content)->some View {
        if #available(iOS 27.0,*), enabled { content.toolbarMinimizationBehavior(.onScrollDown,for:.navigationBar,.tabBar) } else { content }
    }
}
#Preview("Access note • boat, limited road, none") {
    let parks=(try? ParkData.load()) ?? []
    VStack(alignment:.leading,spacing:20) {
        ForEach(parks.filter { ["chis","dena","jotr"].contains($0.id) }) { park in
            VStack(alignment:.leading,spacing:4) { Text(park.shortName).font(.headline); AccessNoteLabel(park:park) }
        }
    }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(.black).preferredColorScheme(.dark)
}

/// The system search field in the navigation bar, except at accessibility text sizes, where the
/// screen shows `InlineSearchField` instead: on iOS 27 the bar's field keeps its height while its
/// text grows, so at AX5 it draws neither placeholder nor text and does not take a tap.
struct SystemSearch: ViewModifier {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let prompt: LocalizedStringKey
    let enabled: Bool
    func body(content:Content)->some View {
        if enabled { content.searchable(text:$text,prompt:prompt).searchFocused(focused) } else { content }
    }
}
/// A search field in the page itself, for accessibility text sizes: it grows and wraps with the text.
struct InlineSearchField: View {
    @Environment(\.nyx) private var palette
    @Binding var text: String
    let prompt: LocalizedStringKey
    var focus: FocusState<Bool>.Binding
    var body: some View {
        HStack(alignment:.center,spacing:10) {
            Image(systemName:"magnifyingglass").foregroundStyle(palette.muted).accessibilityHidden(true)
            TextField(prompt,text:$text,axis:.vertical).lineLimit(1...3).submitLabel(.search).focused(focus)
                .autocorrectionDisabled().textInputAutocapitalization(.words)
                .onChange(of:text) { _,new in if new.contains("\n") { text=new.replacingOccurrences(of:"\n",with:"") } }
                .accessibilityLabel("Search parks")
            if !text.isEmpty {
                Button { text="" } label:{ Image(systemName:"xmark.circle.fill").foregroundStyle(palette.muted).frame(minWidth:44,minHeight:44) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        // Capped at AX3 (still very large) so the whole prompt fits beside the glass on a phone.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .padding(.horizontal,16).padding(.vertical,10).frame(minHeight:44)
        // The whole capsule takes the tap, not only the line of text.
        .contentShape(Rectangle()).onTapGesture { focus.wrappedValue=true }
        .background(RoundedRectangle(cornerRadius:22,style:.continuous).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius:22,style:.continuous).stroke(palette.line,lineWidth:0.5))
    }
}
/// NPS is refusing requests (the shared hourly quota, or a struggling service): say so calmly and
/// offer the park's own current-conditions page, opened in Safari.
struct AlertsBusyNote: View {
    @Environment(\.nyx) private var palette
    let park: Park
    /// True when the summary above already says the alerts are busy.
    var summarySaysBusy=false
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            if !summarySaysBusy { Text("Park alerts are busy. Check current conditions on nps.gov.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            if let url=BrowserLink.parkConditions(park) {
                Link(destination:url) { Label("Current conditions on nps.gov",systemImage:"safari").font(.subheadline).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }
                    .foregroundStyle(palette.accent).accessibilityHint("Opens the park's page in Safari.")
            }
        }
    }
}
#Preview("Alerts busy") { if let park=try? ParkData.load().first { AlertsBusyNote(park:park).padding(24).background(Color.black).preferredColorScheme(.dark) } }
