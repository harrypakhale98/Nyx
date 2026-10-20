import SwiftUI

/// The Parks tab. In a wide window the list stands beside the park (a split view); in a narrower
/// window, a regular-width one included, and on iPhone it is a stack. The window's width decides
/// (`split`), never the device. The chosen park carries across a resize: narrowing
/// the window keeps the park on screen, widening it keeps the park selected. The map of tonight
/// takes the whole width everywhere, and a park opens over it as from a row.
struct ParksTab: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The tab's own width, measured: it chooses the split (`split`).
    @State private var width=0.0
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    /// The park beside the list, kept for the window (and restored with it).
    @SceneStorage("parksPark") private var selection: String?
    @State private var path: [Park]=[]
    /// iPhone Duo's fold on its inner display, half open or flat (`readingFold`); nil everywhere else.
    @State private var fold: Fold?
    /// The tab's and the list's leading edges on screen, in whole points: the floating sidebar starts a
    /// margin in from the tab, and the list must end at the fold measured from the tab's edge.
    @State private var tabMinX=0.0
    @State private var listMinX=0.0
    /// The list's width as laid out, in whole points: once it is back at 390 after the fold, it is let go.
    @State private var listWidthSeen=0.0
    /// The fold has just gone (the Duo closed, or the window left the inner display): the list is held at 390 until it is laid out there,
    /// since the split keeps a column's width while it stays within the range (`listColumn`).
    @State private var returningFlat=false
    /// Whether the list is beside the park; the person can hide it with the sidebar button.
    /// (`-nyx-list-hidden`, DEBUG: opens with the list hidden.)
    // The split appears only where two columns fit (`split`), so the list starts beside the park there:
    // `.automatic` left it hidden on iPhone Duo's inner display, which the system treats as narrow.
    @State private var columnVisibility:NavigationSplitViewVisibility=DebugScenario.isEnabled("list-hidden") ? .detailOnly : .all
    /// The list's width that puts its edge on the fold, when the fold leaves room for both columns.
    private var listAtFold: Double? { ParksTab.listWidth(fold:fold,width:width,sidebarMargin:listMinX-tabMinX) }
    /// The list column's width on iPhone Duo's inner display (half open or flat): from the sidebar's own margin to
    /// the fold's near edge, so the park column starts there (and keeps the fold's width clear of its
    /// content). Nil when there is no such fold or it leaves either side narrower than 330 points.
    nonisolated static func listWidth(fold:Fold?,width:Double,sidebarMargin:Double)->Double? {
        guard let edge=fold?.leadingWidth(in:width,minimum:330) else { return nil }
        return edge-min(40,max(0,sidebarMargin))
    }
    /// The list column's range. Held at the fold's width while the inner display is open, and at 390 just after (the
    /// split keeps a column's current width while it is inside the range, so the fold's width would
    /// otherwise outlast the fold); otherwise 330 to 460 from 390.
    nonisolated static func listColumn(atFold:Double?,returningFlat:Bool)->(min:Double,ideal:Double,max:Double) {
        if let atFold { return (atFold,atFold,atFold) }
        return returningFlat ? (390,390,390) : (330,390,460)
    }
    /// The park column's range while the list is held at the fold: as narrow as the other half. Open flat, the
    /// split's own minimum for the park is wider than that half, so it floated the list over a dimmed park
    /// instead of setting them side by side (half open it tiles them either way). Nil without the fold.
    nonisolated static func parkColumn(atFold:Double?,width:Double)->(min:Double,ideal:Double,max:Double)? {
        guard let atFold else { return nil }
        let rest=(width-atFold).rounded(.down)
        return (min(330,rest),rest,rest)
    }
    /// How far the park keeps from its column's leading edge: the fold's width while the list ends at the
    /// fold and is shown; nothing when the person hides the list (the park then reads the fold itself).
    nonisolated static func parkInset(fold:Fold?,listAtFold:Double?,listShown:Bool)->Double {
        guard listShown, listAtFold != nil, let fold else { return 0 }
        return fold.width
    }
    /// List or map, kept for the window (and across a relaunch, like Plan's mode). `-nyx-parks-map` (or the `parks-map` route) opens the map.
    @SceneStorage(ParksTab.mapKey) private var showsMap=DebugScenario.parksMap
    /// A screen route (DEBUG captures and the accessibility audit) keeps its own restored state, so a run of
    /// `parks-map` never leaves the next `parks` launch opening on the map and switching to the list mid-audit.
    private static var mapKey: String { DebugScenario.screen == nil ? "parksShowsMap" : DebugScenario.parksMap ? "parksShowsMap-route-map" : "parksShowsMap-route-list" }
    var body: some View {
        Group {
            if split && !showsMap {
                let column=ParksTab.listColumn(atFold:listAtFold,returningFlat:returningFlat)
                NavigationSplitView(columnVisibility:$columnVisibility) {
                    ParksView(selection:$selection)
                        .onGeometryChange(for:Double.self) { $0.frame(in:.global).minX.rounded() } action:{ listMinX=$0 }
                        .onGeometryChange(for:Double.self) { $0.size.width.rounded() } action:{ listWidthSeen=$0 }
                        .modifier(listRefresh).toolbar { mapToggle }.tabRootToolbar()
                        // The column's bar is full with its buttons, so the title only showed as a lone "…";
                        // the selected Parks tab names the column.
                        .toolbar(removing:.title)
                        // iPhone Duo's inner display (half open or flat): the list ends at the fold, so the park beside it
                        // starts on the other half (the column's usual 390 points could not reach it). Held at
                        // that width, and at 390 once the fold has gone until the list is back there (`listColumn`).
                        .navigationSplitViewColumnWidth(min:column.min,ideal:column.ideal,max:column.max)
                } detail: {
                    NavigationStack {
                        if let park=selection.flatMap({ model.park($0) }) { ParkDetailView(park:park).id(park.id) }
                        // A place abroad restored with the window, before the world catalogue is read.
                        else if let selection, model.awaitsCatalog(selection) { ConstellationLoader().frame(maxWidth:.infinity,maxHeight:.infinity).background(NightBackground()) }
                        else { CalmState(symbol:"mountain.2",title:"Choose a park",message:"Its sky tonight, and the nights ahead, will open here.").frame(maxHeight:.infinity).background(NightBackground()) }
                    }
                    // The list ends at the fold's near edge; the park starts past its far edge, so its margin,
                    // its index and its bar (Back among it) sit on the other half rather than on the crease.
                    // Padding rather than safe area: bars and the park's pinned index extend into a safe area.
                    .padding(.leading,ParksTab.parkInset(fold:fold,listAtFold:listAtFold,listShown:columnVisibility != .detailOnly))
                    .modifier(ParkColumnWidth(range:ParksTab.parkColumn(atFold:listAtFold,width:width)))
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path:$path) {
                    Group {
                        if showsMap {
                            ParksMapView { park in path.append(park) }
                                .modifier(RefreshKey { await model.refresh(model.parks,force:true) })
                                .navigationDestination(for:Park.self) { park in ParkDetailView(park:park) }
                        } else { ParksView().modifier(listRefresh) }
                    }.toolbar { mapToggle }.tabRootToolbar()
                }
            }
        }
        .measuringWidth($width)
        .readingFold($fold)
        .onGeometryChange(for:Double.self) { $0.frame(in:.global).minX.rounded() } action:{ tabMinX=$0 }
        // When the fold goes, the list returns to 390 and is then let go within its usual range.
        .onChange(of:listAtFold) { old,new in returningFlat=old != nil && new == nil && abs(listWidthSeen-390)>=1 }
        .onChange(of:listWidthSeen) { _,seen in if returningFlat, abs(seen-390)<1 { returningFlat=false } }
        // The page never opens empty: the starting park until another is chosen.
        .onAppear {
            if selection == nil { selection=path.last?.id ?? model.home?.id }
            // A screen route (DEBUG captures and the accessibility audit) opens what it names, not the map or
            // list a previous run left in the window's restored state.
            if DebugScenario.screen != nil { showsMap=DebugScenario.parksMap }
        }
        .onChange(of:split) { old,new in
            guard !showsMap else { return }
            if old, !new, let park=selection.flatMap({ model.park($0) }) { path=[park] }
            else if new, let last=path.last { selection=last.id }
        }
        // In a wide window the list returns beside the park last opened from the map.
        .onChange(of:showsMap) { _,map in
            guard split else { return }
            if !map, let last=path.last { selection=last.id }
            path.removeAll()
        }
        // ⌘F returns to the list.
        .onChange(of:commands?.searchRequest) { _,_ in path.removeAll(); showsMap=false }
    }
    /// The list beside the park from the width where a page takes two columns (`WideLayout`, 860 pt,
    /// 1180 at accessibility text sizes; iPhone Duo's inner display in landscape, as Mail does): narrower, the park beside a 390-point list would be cramped,
    /// so an 11-inch iPad in portrait or a 700-point window keeps the list and pushes the park.
    /// Unmeasured (0) is a stack, so the first measurement never pushes the chosen park.
    nonisolated static func split(width:Double,largeText:Bool)->Bool { width>0 && WideLayout.columns(width:width,largeText:largeText)==2 }
    private var split:Bool { Self.split(width:width,largeText:typeSize.isAccessibilitySize) }
    /// ⌘R on the list: its own pull-to-refresh, which lives inside `ParksView`.
    private var listRefresh:RefreshKey { RefreshKey { await model.refresh(model.parks,force:true,parkUpdates:false) } }
    /// List or map: one button that says what it shows next, with a light tick.
    private var mapToggle: some ToolbarContent {
        ToolbarItem(placement:.topBarTrailing) {
            Button { showsMap.toggle() } label:{ Label(showsMap ? "Show list" : "Show map",systemImage:showsMap ? "list.bullet" : "map") }
                .accessibilityInputLabels(showsMap ? [Text("List"),Text("Show list")] : [Text("Map"),Text("Show map")])
                .help(showsMap ? "Show list" : "Show map")
                .sensoryFeedback(.selection,trigger:showsMap)
        }
    }
}

/// The park column's width range, where the list is held at the fold (`ParksTab.parkColumn`); the split's own otherwise.
private struct ParkColumnWidth: ViewModifier {
    let range:(min:Double,ideal:Double,max:Double)?
    func body(content: Content) -> some View {
        if let range { content.navigationSplitViewColumnWidth(min:range.min,ideal:range.ideal,max:range.max) } else { content }
    }
}
