import SwiftUI

/// Plan: the one place for "when". It opens on the best nights in reach over the next 30 (where and
/// which night, this month); then one park's month (the calendar), or the best park in reach for each
/// night you are free (the trip planner). A segmented control floats under the bar, so each answer is
/// one tap from the others. The starting point and radius are Tonight's, one for the whole app.
struct PlanView: View {
    enum Mode: String, CaseIterable { case best, month, free }
    @Environment(PlanModel.self) private var model
    /// This window's commands, which carry its calendar requests.
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Kept per window. A new key, so a window saved on the month before best nights existed opens on them.
    @SceneStorage("planView") private var mode:Mode = .best
    /// The mode a DEBUG route names (`-nyx-screen plan|calendar|best`, `-nyx-plan-trip`), chosen before the
    /// first frame so a capture or a test never starts another mode's work; cleared by the picker.
    @State private var forced:Mode? = Self.routed
    private static var routed:Mode? {
        if DebugScenario.isEnabled("plan-trip") { return .free }
        switch DebugScenario.screen { case "plan","calendar": return .month; case "best": return .best; default: return nil }
    }
    private var shown:Mode { forced ?? mode }
    /// The page's width, so the picker over the trip planner is as wide as the planner's page.
    @State private var width=0.0
    var body: some View {
        Group {
            switch shown {
            // The picker lives inside the month, so the inspector's column stays clear of it.
            case .month: CalendarView(bar:AnyView(picker))
            case .best: BestNightsView()
            case .free: TripPlannerView(embedded:true)
            }
        }
        .safeAreaBar(edge:.top,spacing:0) { if shown != .month { picker.readableColumn(WideLayout.pageWidth(width:width,largeText:typeSize.isAccessibilitySize)) } }
        .measuringWidth($width)
        .navigationTitle("Plan").navigationBarTitleDisplayMode(.inline)
        .tabRootToolbar()
        .toolbar {
            // Ask Nyx plans over the same nights, on this device; only where the model is available.
            if OnDeviceGuide.available {
                ToolbarItem(placement:.topBarTrailing) {
                    NavigationLink { GuideView(mode:.planning) } label:{ Label("Ask Nyx",systemImage:"sparkles") }
                        .accessibilityLabel("Ask Nyx").accessibilityInputLabels([Text("Ask Nyx"),Text("Ask")])
                }
            }
        }
        // A park dragged here (from Parks, Tonight or the map, or another window) opens its month.
        .acceptsPark("Plan this park",systemImage:"calendar") { park in
            commands?.calendarRequest=CalendarRequest(parkID:park.id,year:nil,month:nil)
        }
        // A `nyx://calendar` link always lands on the month it names.
        .onChange(of:commands?.calendarRequest,initial:true) { _,request in if request != nil { forced=nil; mode = .month } }
    }
    /// Segmented where it fits; at accessibility sizes a menu, which grows with the text instead of truncating.
    @ViewBuilder private var picker: some View {
        let control=Picker("Plan",selection:Binding(get:{ shown },set:{ forced=nil; mode=$0 })) {
            Text("Best nights").tag(Mode.best)
            Text("One park").tag(Mode.month)
            Text("My free nights").tag(Mode.free)
        }
        Group {
            if typeSize.isAccessibilitySize { control.pickerStyle(.menu).frame(maxWidth:.infinity,alignment:.leading) }
            else { control.pickerStyle(.segmented) }
        }
        // As wide as the page under it (the month's column, or the planner's), set by whoever places it.
        .padding(.horizontal,24).padding(.vertical,8)
        .accessibilityHint("The best nights in reach this month, one park's month, or the best park for each night you are free.")
    }
}
#Preview("Plan") { NavigationStack { PlanView() }.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Plan AX5") { NavigationStack { PlanView() }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
