import SwiftUI

/// The Parks tab. In a wide iPad window the list stands beside the park (a split view); in a
/// narrow window and on iPhone it is a stack. The chosen park carries across a resize: narrowing
/// the window keeps the park on screen, widening it keeps the park selected. The map of tonight
/// takes the whole width everywhere, and a park opens over it as from a row.
struct ParksTab: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    /// The park beside the list, kept for the window (and restored with it).
    @SceneStorage("parksPark") private var selection: String?
    @State private var path: [Park]=[]
    /// List or map, kept for the window (and across a relaunch, like Plan's mode). `-nyx-parks-map` opens the map.
    @SceneStorage("parksShowsMap") private var showsMap=DebugScenario.isEnabled("parks-map")
    var body: some View {
        Group {
            if sizeClass == .regular && !showsMap {
                NavigationSplitView {
                    ParksView(selection:$selection).toolbar { mapToggle }.tabRootToolbar().navigationSplitViewColumnWidth(min:330,ideal:390,max:460)
                } detail: {
                    NavigationStack {
                        if let park=selection.flatMap({ model.park($0) }) { ParkDetailView(park:park).id(park.id) }
                        else { CalmState(symbol:"mountain.2",title:"Choose a park",message:"Its sky tonight, and the nights ahead, will open here.").frame(maxHeight:.infinity).background(NightBackground()) }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path:$path) {
                    Group {
                        if showsMap {
                            ParksMapView { park in path.append(park) }
                                .navigationDestination(for:Park.self) { park in ParkDetailView(park:park) }
                        } else { ParksView() }
                    }.toolbar { mapToggle }.tabRootToolbar()
                }
            }
        }
        // The page never opens empty: the starting park until another is chosen.
        .onAppear { if selection == nil { selection=path.last?.id ?? model.home?.id } }
        .onChange(of:sizeClass) { old,new in
            guard !showsMap else { return }
            if new == .compact, old == .regular, let park=selection.flatMap({ model.park($0) }) { path=[park] }
            else if new == .regular, let last=path.last { selection=last.id }
        }
        // On a wide iPad the list returns beside the park last opened from the map.
        .onChange(of:showsMap) { _,map in
            guard sizeClass == .regular else { return }
            if !map, let last=path.last { selection=last.id }
            path.removeAll()
        }
        // ⌘F returns to the list.
        .onChange(of:commands?.searchRequest) { _,_ in path.removeAll(); showsMap=false }
    }
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
