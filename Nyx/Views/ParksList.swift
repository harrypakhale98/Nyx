import SwiftUI
import SwiftData

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
    /// Worked out once per update of the list (the body reads it into `shown`): ranking 63 parks is not free.
    private var filtered:[Park] {
        let filter=ParkFilter(darkOnly:darkOnly,stepFreeOnly:stepFreeOnly)
        let savedIDs=Set(saved.map(\.parkID)), query=Park.folded(search)
        let matching=model.parks.filter { p in filter.includes(p) && (!savedOnly || savedIDs.contains(p.id)) && (query.isEmpty || p.matches(folded:query)) }
        return byScore ? model.ranked(matching) : matching
    }
    /// Saved parks lead the list only when nothing narrows it.
    private var narrowed:Bool { darkOnly || stepFreeOnly || savedOnly }
    private var showsSavedSection:Bool { !saved.isEmpty && !savedOnly && search.isEmpty && !darkOnly && !stepFreeOnly }
    var body: some View {
        let shown=filtered
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Eyebrow(text:byScore ? LocalizedStringKey("Darkest tonight first") : "\(Self.countLine(shown:shown.count,of:model.parks.count,narrowed:narrowed))")
                if typeSize.isAccessibilitySize { InlineSearchField(text:$search,prompt:"Park or state",focus:$searchFocused) }
                // Only worth saying when a row actually reads "Estimate".
                if shown.contains(where:{ model.night($0).basis == .usual }) { Text("Scores marked Estimate have no cloud forecast yet and use each park's usual clouds.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                if stepFreeOnly { Text("Parks with at least one viewing spot that nps.gov describes as step-free or partly step-free. Check with the park before you go.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                if DebugScenario.state=="loading" { ForEach(0..<5,id:\.self) { _ in SkeletonRow() } }
                else if shown.isEmpty || DebugScenario.state=="empty" { CalmState(symbol:"sparkle.magnifyingglass",title:"No parks in this sky",message:"Try another name or widen your filters.") }
                else {
                    if showsSavedSection {
                        Eyebrow(text:"Saved for later")
                        ForEach(model.parks.filter{p in saved.contains{$0.parkID==p.id}}) { p in link(p) }
                        Eyebrow(text:"All national parks")
                    }
                    LazyVStack(spacing:0) { ForEach(shown.filter { p in !(showsSavedSection && saved.contains{$0.parkID==p.id}) }) { p in link(p); Divider().overlay(palette.line) } }
                }
            }.padding(24)
            .background { SearchEnder(request:commands?.sheetRequest?.id) }
            // VoiceOver rotors: jump straight to the parks with a closure alert, or a Pristine sky tonight.
            .accessibilityRotor(Text("Closures"),entries:rotor(shown) { park in model.closure(park).map { String(localized:"\(park.shortName): \($0)") } },entryID:\.id,entryLabel:\.label)
            .accessibilityRotor(Text("Pristine nights"),entries:rotor(shown) { park in
                let night=model.night(park); return night.score.value>=90 ? String(localized:"\(park.shortName), \(night.score.value)") : nil
            },entryID:\.id,entryLabel:\.label)
        }.background(NightBackground(veil:0.45)).navigationTitle("Parks").navigationBarTitleDisplayMode(.inline)
            .modifier(SystemSearch(text:$search,focused:$searchFocused,prompt:"Park or state",enabled:!typeSize.isAccessibilitySize))
            .alert("Unable to save",isPresented:$saveFailed) { Button("OK",role:.cancel) {} } message:{ Text(model.journalUnavailable ? "Saved parks are kept with your journal, which could not be opened. Nothing was changed." : "Your changes could not be stored. Try again when space is available.") }
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
    /// The eyebrow over the list: "63 places to look up", or "12 of 63 parks" while a filter narrows it.
    nonisolated static func countLine(shown:Int,of total:Int,narrowed:Bool)->String {
        narrowed ? String(localized:"\(shown) of \(total) parks") : String(localized:"\(total) places to look up")
    }
    struct RotorPark: Identifiable { let id: String; let label: String }
    /// One rotor stop for each park on screen that `label` names, in the order shown.
    private func rotor(_ shown:[Park],_ label:(Park)->String?)->[RotorPark] {
        let sectioned = showsSavedSection
        let first=sectioned ? model.parks.filter { p in saved.contains { $0.parkID==p.id } } : []
        let rest=shown.filter { p in !(sectioned && saved.contains { $0.parkID==p.id }) }
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
                // iPad: drag a park onto Plan (its month) or Journal (a new entry), or out as its name.
                .draggable(park)
        } else {
            NavigationLink(value:park) { row }.buttonStyle(.plain).matchedTransitionSource(id:park.id,in:zoom).hoverEffect(.highlight).contextMenu { rowMenu(park) }
                .draggable(park)
        }
    }
    /// Long press, or a secondary click with a pointer.
    @ViewBuilder private func rowMenu(_ park:Park)->some View {
        let isSaved=saved.contains { $0.parkID==park.id }
        Button(isSaved ? "Remove from saved parks" : "Save park",systemImage:isSaved ? "bookmark.slash" : "bookmark") {
            // Saved parks share the journal's store; a save into its stand-in would not last.
            guard !model.journalUnavailable else { saveFailed=true; return }
            if let item=saved.first(where:{ $0.parkID==park.id }) { context.delete(item) } else { context.insert(SavedPark(parkID:park.id)) }
            do { try context.save() } catch { context.rollback();saveFailed=true }
        }
        Button("Show in Plan",systemImage:"calendar") { commands?.calendarRequest=CalendarRequest(parkID:park.id,year:nil,month:nil); commands?.tab=2 }
        OpenParkWindowButton(park:park)
    }
    private func focusSearchIfAsked() {
        guard commands?.takeSearch() == true else { return }
        Task { try? await Task.sleep(for:.milliseconds(250)); searchFocused=true }
    }
}
