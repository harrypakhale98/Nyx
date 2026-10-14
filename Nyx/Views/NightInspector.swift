import SwiftUI

/// The night's score breakdown in a trailing inspector, beside the month or the park's page in a
/// wide iPad window (`WideLayout.inspector`). Narrower windows and accessibility sizes keep the sheet.
/// `actions` adds what the screen offers for that night (Plan: open it, add it to Calendar).
struct NightInspector<Actions: View>: View {
    @Environment(\.nyx) private var palette
    let night: Night
    var isTonight=true
    /// The inspector's own close button; nil where the screen's toolbar already toggles it.
    let close: (()->Void)?
    @ViewBuilder var actions: Actions
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                ScoreBreakdownView(night:night,isTonight:isTonight,inline:true)
                actions
            }.padding(.horizontal,22).padding(.vertical,20)
        }
        .id(night.id)
        .background(palette.panel.ignoresSafeArea())
        .overlay(alignment:.leading) { Rectangle().fill(palette.line).frame(width:0.5).ignoresSafeArea().accessibilityHidden(true) }
        .toolbar {
            if let close {
                ToolbarItem(placement:.primaryAction) {
                Button("Close",systemImage:"xmark",action:close).labelStyle(.iconOnly)
                    .help("Close the breakdown")
                    .accessibilityLabel("Close the score breakdown").accessibilityInputLabels([Text("Close"),Text("Close breakdown")])
                }
            }
        }
        .inspectorColumnWidth(min:320,ideal:380,max:440)
    }
}
extension NightInspector where Actions == EmptyView {
    init(night:Night,isTonight:Bool=true,close:(()->Void)?) { self.init(night:night,isTonight:isTonight,close:close,actions:{ EmptyView() }) }
}
#Preview("Inspector") {
    let model=PlanModel()
    if let park=model.home {
        NavigationStack { Color.black.inspector(isPresented:.constant(true)) { NightInspector(night:model.night(park)) {} } }
            .environment(model).preferredColorScheme(.dark)
    }
}
#Preview("Inspector • AX3") {
    let model=PlanModel()
    if let park=model.home {
        NightInspector(night:model.night(park)) {} actions:{ Button("Open this night") {}.buttonStyle(.bordered) }
            .environment(model).dynamicTypeSize(.accessibility3).preferredColorScheme(.dark)
    }
}
