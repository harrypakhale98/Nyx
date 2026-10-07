import SwiftUI

/// The Parks tab. In a wide iPad window the list stands beside the park (a split view); in a
/// narrow window and on iPhone it is a stack. The chosen park carries across a resize: narrowing
/// the window keeps the park on screen, widening it keeps the park selected.
struct ParksTab: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @State private var selection: String?
    @State private var path: [Park]=[]
    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    ParksView(selection:$selection).tabRootToolbar().navigationSplitViewColumnWidth(min:330,ideal:390,max:460)
                } detail: {
                    NavigationStack {
                        if let park=selection.flatMap({ model.park($0) }) { ParkDetailView(park:park).id(park.id) }
                        else { CalmState(symbol:"mountain.2",title:"Choose a park",message:"Its sky tonight, and the nights ahead, will open here.").frame(maxHeight:.infinity).background(NightBackground()) }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path:$path) { ParksView().tabRootToolbar() }
            }
        }
        // The page never opens empty: the starting park until another is chosen.
        .onAppear { if selection == nil { selection=path.last?.id ?? model.home?.id } }
        .onChange(of:sizeClass) { old,new in
            if new == .compact, old == .regular, let park=selection.flatMap({ model.park($0) }) { path=[park] }
            else if new == .regular, let last=path.last { selection=last.id }
        }
        // ⌘F returns to the list.
        .onChange(of:commands?.searchRequest) { _,_ in path.removeAll() }
    }
}
