import SwiftUI

/// Plan: the one place for "when". One park's month (the calendar), or the best park in reach for
/// each night you are free (the trip planner). A segmented control floats under the bar, so either
/// answer is one tap from the other; each keeps its own choices while the other is open.
struct PlanView: View {
    enum Mode: String, CaseIterable { case month, free }
    @Environment(PlanModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @SceneStorage("planMode") private var mode:Mode = .month
    var body: some View {
        Group {
            switch mode {
            // The picker lives inside the month, so the inspector's column stays clear of it.
            case .month: CalendarView(bar:AnyView(picker))
            case .free: TripPlannerView(embedded:true)
            }
        }
        .safeAreaBar(edge:.top,spacing:0) { if mode == .free { picker } }
        .navigationTitle("Plan").navigationBarTitleDisplayMode(.inline)
        .tabRootToolbar()
        .toolbar {
            // Ask Nyx plans over the same nights, on this device; only where the model is available.
            if OnDeviceGuide.available {
                ToolbarItem(placement:.topBarTrailing) {
                    NavigationLink { GuideView(mode:.planning) } label:{ Image(systemName:"sparkles") }
                        .accessibilityLabel("Ask Nyx").accessibilityInputLabels([Text("Ask Nyx"),Text("Ask")])
                }
            }
        }
        // A park dragged here (from Parks, Tonight or the map, or another window) opens its month.
        .acceptsPark("Plan this park",systemImage:"calendar") { park in
            model.calendarRequest=CalendarRequest(parkID:park.id,year:nil,month:nil)
        }
        // A `nyx://calendar` link always lands on the month it names.
        .onChange(of:model.calendarRequest,initial:true) { _,request in if request != nil { mode = .month } }
        .task { if DebugScenario.isEnabled("plan-trip") { mode = .free } }
    }
    /// Segmented where it fits; at accessibility sizes a menu, which grows with the text instead of truncating.
    @ViewBuilder private var picker: some View {
        let control=Picker("Plan",selection:$mode) {
            Text("One park").tag(Mode.month)
            Text("My free nights").tag(Mode.free)
        }
        Group {
            if typeSize.isAccessibilitySize { control.pickerStyle(.menu).frame(maxWidth:.infinity,alignment:.leading) }
            else { control.pickerStyle(.segmented) }
        }
        .padding(.horizontal,24).padding(.vertical,8)
        .frame(maxWidth:WideLayout.readableWidth).frame(maxWidth:.infinity)
        .accessibilityHint("One park's month, or the best park for each night you are free.")
    }
}
#Preview("Plan") { NavigationStack { PlanView() }.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Plan AX5") { NavigationStack { PlanView() }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
