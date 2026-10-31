import SwiftUI

/// The night's score breakdown in a trailing inspector, beside the month or the park's page in a
/// wide iPad window (`WideLayout.inspector`). Narrower windows and accessibility sizes keep the sheet.
/// `actions` adds what the screen offers for that night (Plan: open it, add it to Calendar). The screen's
/// own bar shows and hides it ("Hide the breakdown"): items in an inspector's bar are dropped in some splits.
struct NightInspector<Actions: View>: View {
    @Environment(\.nyx) private var palette
    let night: Night
    var isTonight=true
    @ViewBuilder var actions: Actions
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                ScoreBreakdownView(night:night,isTonight:isTonight,inline:true)
                actions
            }.padding(.horizontal,22).padding(.vertical,20)
        }
        .id(night.id).foregroundStyle(palette.ink)
        // Open to the night like the page beside it: void black, not an indigo box, parted from the
        // month or the park by one starlight hairline that thickens with Increase Contrast and Bold Text.
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment:.leading) { Rectangle().fill(palette.line).frame(width:0.5*palette.stroke).ignoresSafeArea().accessibilityHidden(true) }
        .inspectorColumnWidth(min:320,ideal:380,max:440)
    }
}
extension NightInspector where Actions == EmptyView {
    init(night:Night,isTonight:Bool=true) { self.init(night:night,isTonight:isTonight,actions:{ EmptyView() }) }
}
#Preview("Inspector") {
    let model=PlanModel()
    if let park=model.home {
        NavigationStack { Color.black.inspector(isPresented:.constant(true)) { NightInspector(night:model.night(park)) } }
            .environment(model).preferredColorScheme(.dark)
    }
}
#Preview("Inspector • AX3") {
    let model=PlanModel()
    if let park=model.home {
        NightInspector(night:model.night(park)) { Button("Open this night") {}.secondaryAction() }
            .environment(model).dynamicTypeSize(.accessibility3).preferredColorScheme(.dark)
    }
}
