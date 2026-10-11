import SwiftUI
import SwiftData

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
    @Environment(PlanModel.self) var model
    @Environment(\.nyx) var palette
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(\.dynamicTypeSize) var typeSize
    @Query private var saved:[SavedPark]
    /// The place the page was opened with. A saved spot is read again from the model (`park`), so a
    /// rename shows at once; once deleted, the page keeps what it opened with until it closes.
    private let given:Park
    var park:Park { given.isSavedSpot ? (model.park(given.id) ?? given) : given }
    var initialDate:Date?=nil
    /// Opened from a link to that night's What's up (`nyx://whatsup`): scroll there once.
    var focusWhatsUp=false
    /// Told whenever the night on show changes, so a park's own window can keep it (`ParkWindowRoot`).
    var nightChanged:((Date)->Void)?=nil
    init(park:Park,initialDate:Date?=nil,focusWhatsUp:Bool=false,nightChanged:((Date)->Void)?=nil) {
        given=park; _selected=State(initialValue:nil); self.initialDate=initialDate; self.focusWhatsUp=focusWhatsUp; self.nightChanged=nightChanged
    }
    @State var selected:Date?
    @State private var breakdown=false
    /// The breakdown beside the page in a wide window (`WideLayout.inspector`); a sheet otherwise.
    @State private var inspector=false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @State private var persistenceError=false
    @State private var scrubbing=false
    /// A finger holds the sky arc: the page holds still, the Moon keeps its relief.
    @State private var holdingArc=false
    @State private var width=0.0
    @State private var chapter=ParkChapter.tonight
    /// Chapter positions, kept out of observation so scrolling never re-evaluates the page.
    @State private var tracker=ChapterTracker()
    @State var titleGone=false
    @State var showsSky=DebugScenario.isEnabled("sky-view")
    @State private var description=false
    /// What's up has been scrolled to for a link that asked for it (`focusWhatsUp`).
    @State private var focusedWhatsUp=false
    var night:Night { model.night(park,on:selected ?? initialDate ?? model.tonight(park)) }
    var isTonight:Bool { night.id==model.tonight(park) }
    private var isSaved:Bool { saved.contains{$0.parkID==park.id} }
    var outlook:NightOutlook? { model.outlook(night) }
    /// The river covers tonight and the next 29 nights, or starts at a night chosen outside that span.
    var riverStart:Date {
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
                            .scrollDisabled(scrubbing || holdingArc).frame(width:WideLayout.leadingWidth(width))
                        // The sky arc lives here, so its held finger holds this column still too.
                        ScrollView { VStack(spacing:26) { skyChapter; placeChapter }.padding(24) }
                            .scrollDisabled(scrubbing || holdingArc)
                    }
                } else {
                    ScrollView {
                        VStack(spacing:26) {
                            tonightChapter(proxy).modifier(ChapterTop(chapter:.tonight,report:report))
                            skyChapter.modifier(ChapterTop(chapter:.sky,report:report))
                            placeChapter.modifier(ChapterTop(chapter:.place,report:report))
                        }.padding(24).readableColumn()
                    }
                    .scrollDisabled(scrubbing || holdingArc)
                    .safeAreaBar(edge:.top) { if showsIndex { index(proxy) } }
                }
            }
            .onPreferenceChange(RiverScrubbingKey.self) { scrubbing=$0 }
            .onPreferenceChange(ArcHoldingKey.self) { holdingArc=$0 }
            // The Moon hero drops its relief while the river or the Moon is scrubbed.
            .environment(\.moonRelief,!scrubbing)
            .task {
                // DEBUG store capture (`-nyx-listen`): the shape of the night at the top.
                if DebugScenario.isEnabled("listen") {
                    try? await Task.sleep(for:.milliseconds(500))
                    proxy.scrollTo("sky",anchor:.top); return
                }
                #if DEBUG
                // DEBUG captures: `-nyx-chapter sky|place|moon|spots|programs` opens at that part of the page.
                // The page grows above the target as What's up and its alarm rows arrive, so the scroll is
                // repeated until that has settled (about 3 s); the Moon is centred, every other part at the top.
                if let target=ProcessInfo.processInfo.arguments.firstIndex(of:"-nyx-chapter").flatMap({ ProcessInfo.processInfo.arguments.dropFirst($0+1).first }) {
                    let id=ParkChapter(rawValue:target).map { AnyHashable($0) } ?? AnyHashable(target)
                    let anchor:UnitPoint=target=="moon" ? .center : .top
                    try? await Task.sleep(for:.milliseconds(700))
                    for _ in 0..<10 {
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo(id,anchor:anchor)
                        try? await Task.sleep(for:.milliseconds(250))
                    }
                    return
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
                // Once per page: coming back from a pushed page keeps the reader where they were.
                guard focusWhatsUp, !focusedWhatsUp else { return }
                // After the zoom or sheet settles, so the scroll reads as arriving rather than jumping.
                try? await Task.sleep(for:.milliseconds(500))
                guard !Task.isCancelled else { return }
                focusedWhatsUp=true
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
        // Handoff to another device, and the park Siri sees on screen.
        .parkHandoff(park,night:night.id)
        .defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top).background(NightBackground(seed:park.id,score:night.score.value,park:park,night:night.id))
            // Under the full-screen sky the page's own stars and dial rest, so the turning sky has the frames.
            .environment(\.skyResting,showsSky)
            .navigationTitle(park.shortName).navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }.modifier(SkyFullBleed(enabled:!wide))
            .sheet(isPresented:$breakdown) { NavigationStack { ScoreBreakdownView(night:night,isTonight:isTonight) }.nyxPresentation().presentationDetents([.large]) }
            // Wide iPad: the breakdown stays beside the page and follows the river's night.
            // The close button only while it is open: iOS 27 lends a closed inspector's toolbar to the page's bar.
            .inspector(isPresented:$inspector) { NightInspector(night:night,isTonight:isTonight,close:inspector ? { inspector=false } : nil) }
            .onChange(of:width) { _,_ in if inspector, !inspectorRoom { inspector=false } }
            .onChange(of:sizeClass) { _,_ in if inspector, !inspectorRoom { inspector=false } }
            // Only a night chosen here is kept: storing the one the page opened on would hold a
            // restored window on that date after it has passed.
            .onChange(of:night.id) { _,id in nightChanged?(id) }
            // DEBUG captures (`-nyx-inspector`): the breakdown open beside the page where it has room.
            .task { if DebugScenario.isEnabled("inspector") { try? await Task.sleep(for:.seconds(1)); if inspectorRoom { inspector=true } } }
            .modifier(ReportsVisiblePark(parkID:park.id))
            .fullScreenCover(isPresented:$showsSky) { TonightSkyView(night:night,isTonight:isTonight).environment(\.nyx,palette).nyxPresentation().modifier(DebugTypeSize()) }
            .alert("Unable to save",isPresented:$persistenceError) { Button("OK",role:.cancel) {} } message:{ Text(model.journalUnavailable ? "Saved parks are kept with your journal, which could not be opened. Nothing was changed." : "Your changes could not be stored. Try again when space is available.") }
            // Again whenever the river moves on (left open past sunrise, or a night chosen beyond it).
            .task(id:riverStart) { await model.prepareWhatsUp(model.nights(park,from:riverStart,count:30)) }
            // Park alerts and ranger programs only where the Park Service runs the place: a saved spot asks it nothing.
            .task { await model.refresh([park],parkUpdates:park.nps != nil,programs:park.nps != nil) }
            .refreshable { await model.refresh([park],force:true,parkUpdates:park.nps != nil,programs:park.nps != nil) }
    }
    /// Room for the breakdown beside the page (`WideLayout.inspector`).
    private var inspectorRoom:Bool { WideLayout.inspector(width:width,open:inspector,regular:sizeClass == .regular,largeText:typeSize.isAccessibilitySize) }
    func showBreakdown() {
        if inspectorRoom { withAnimation(reduceMotion ? nil : NyxMotion.spring) { inspector=true } } else { breakdown=true }
    }
    private func report(_ which:ParkChapter,_ top:CGFloat) {
        tracker.tops[which]=top
        let now=ParkChapter.current(tops:tracker.tops,line:showsIndex ? 140 : 100)
        if now != chapter { chapter=now }
    }
    /// Moves the chosen night within the river's thirty; false when that would leave them.
    @discardableResult func step(_ delta:Int)->Bool {
        let next=park.date(night.id,addingDays:delta)
        guard next>=riverStart, next<park.date(riverStart,addingDays:30) else { return false }
        withAnimation(reduceMotion ? nil : NyxMotion.spring) { selected=next }
        return true
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
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // The park's name returns to the bar once its title has scrolled away, never both at once.
        ToolbarItem(placement:.principal) {
            Text(park.shortName).font(.headline).opacity(titleGone || wide ? 1 : 0).accessibilityHidden(!(titleGone || wide))
        }
        if #available(iOS 27.0,*) {
            ToolbarItem(placement:.topBarPinnedTrailing) { saveButton }
        } else { ToolbarItem(placement:.topBarTrailing) { saveButton } }
        ToolbarItem(placement:.topBarTrailing) { ShareNightMenu(night:night) }
        // iPad: this park in a window of its own, beside another (not in a park's own window).
        if multipleWindows, commands?.parkWindow != true {
            ToolbarItem(placement:.topBarTrailing) { OpenParkWindowButton(park:park,night:selected).labelStyle(.iconOnly).help("Open in New Window") }
        }
    }
    private var saveButton:some View {
        Button { guard !model.journalUnavailable else { persistenceError=true; return }; if let item=saved.first(where:{$0.parkID==park.id}) { context.delete(item) } else { context.insert(SavedPark(parkID:park.id)) }; do { try context.save() } catch { context.rollback();persistenceError=true } } label:{ Image(systemName:isSaved ? "bookmark.fill" : "bookmark") }
            .modifier(SaveButtonWords(saved:isSaved,spot:park.isSavedSpot))
    }
}
/// The bookmark's words. For a park, saving it; for a spot (always kept in Your spots until it is
/// deleted), following it: a followed spot is in the widgets, reminders and on Apple Watch.
private struct SaveButtonWords: ViewModifier {
    let saved: Bool
    let spot: Bool
    func body(content:Content)->some View {
        if spot {
            content.accessibilityLabel(saved ? "Stop following this spot" : "Follow this spot")
                .accessibilityHint("Followed spots appear in widgets, reminders and on Apple Watch.")
                .accessibilityInputLabels(saved ? [Text("Stop following"),Text("Unsave")] : [Text("Follow"),Text("Save")])
        } else {
            content.accessibilityLabel(saved ? "Remove from saved parks" : "Save park")
                .accessibilityInputLabels(saved ? [Text("Remove from saved parks"),Text("Unsave"),Text("Unsave park")] : [Text("Save"),Text("Save park")])
        }
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
#Preview("Detail") { let m=PlanModel();if let p=m.home { NavigationStack { ParkDetailView(park:p) }.environment(m).modelContainer(for:[SavedPark.self,JournalEntry.self],inMemory:true).preferredColorScheme(.dark) } }

/// iOS 27: the navigation bar recedes as the park's page scrolls down, so its sky runs edge to edge;
/// it returns on the way back up. Like the tab bar (`RootView`), it stays in place under VoiceOver,
/// Switch Control and accessibility sizes, where a bar that moves costs someone their place.
/// iOS 26 keeps the standard bar.
private struct SkyFullBleed: ViewModifier {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Off in two columns, where the night's column stays put beside the scrolling detail and bars
    /// receding over one column would read as a glitch.
    var enabled=true
    /// Same view either way, so turning VoiceOver on mid-page keeps the page where it is.
    private var recedes:Bool { !voiceOver && !switchControl && !typeSize.isAccessibilitySize && !DebugScenario.isEnabled("ax5") }
    @ViewBuilder func body(content:Content)->some View {
        if #available(iOS 27.0,*), enabled { content.toolbarMinimizationBehavior(recedes ? .onScrollDown : .never,for:.navigationBar) } else { content }
    }
}
