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
    /// iPhone Duo's fold while it is half open (`readingFold`); nil everywhere else.
    @State private var fold: Fold?
    /// The tab's and the list's leading edges on screen, in whole points: the floating sidebar starts a
    /// margin in from the tab, and the list must end at the fold measured from the tab's edge.
    @State private var tabMinX=0.0
    @State private var listMinX=0.0
    /// The list's width that puts its edge on the fold, when the fold leaves room for both columns.
    private var listAtFold: Double? { ParksTab.listWidth(fold:fold,width:width,sidebarMargin:listMinX-tabMinX) }
    /// The list column's width when iPhone Duo is half open like a book: from the sidebar's own margin to
    /// the fold's near edge, so the park column starts there (and keeps the fold's width clear of its
    /// content). Nil when there is no such fold or it leaves either side narrower than 330 points.
    nonisolated static func listWidth(fold:Fold?,width:Double,sidebarMargin:Double)->Double? {
        guard let edge=fold?.leadingWidth(in:width,minimum:330) else { return nil }
        return edge-min(40,max(0,sidebarMargin))
    }
    /// List or map, kept for the window (and across a relaunch, like Plan's mode). `-nyx-parks-map` (or the `parks-map` route) opens the map.
    @SceneStorage(ParksTab.mapKey) private var showsMap=DebugScenario.parksMap
    /// A screen route (DEBUG captures and the accessibility audit) keeps its own restored state, so a run of
    /// `parks-map` never leaves the next `parks` launch opening on the map and switching to the list mid-audit.
    private static var mapKey: String { DebugScenario.screen == nil ? "parksShowsMap" : DebugScenario.parksMap ? "parksShowsMap-route-map" : "parksShowsMap-route-list" }
    var body: some View {
        Group {
            if split && !showsMap {
                NavigationSplitView {
                    ParksView(selection:$selection).onGeometryChange(for:Double.self) { $0.frame(in:.global).minX.rounded() } action:{ listMinX=$0 }.modifier(listRefresh).toolbar { mapToggle }.tabRootToolbar()
                        // iPhone Duo half open like a book: the list ends at the fold, so the park beside it
                        // starts on the other half (the column's usual 390 points could not reach it). Held at
                        // that width: the split keeps a column's first width while it stays within the range.
                        .navigationSplitViewColumnWidth(min:listAtFold ?? 330,ideal:listAtFold ?? 390,max:listAtFold ?? 460)
                } detail: {
                    NavigationStack {
                        if let park=selection.flatMap({ model.park($0) }) { ParkDetailView(park:park).id(park.id) }
                        else { CalmState(symbol:"mountain.2",title:"Choose a park",message:"Its sky tonight, and the nights ahead, will open here.").frame(maxHeight:.infinity).background(NightBackground()) }
                    }
                    // The list ends at the fold's near edge; the park starts past its far edge, so its margin,
                    // its index and its bar (Back among it) sit on the other half rather than on the crease.
                    // Padding rather than safe area: bars and the park's pinned index extend into a safe area.
                    .padding(.leading,listAtFold == nil ? 0 : fold?.width ?? 0)
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
