import SwiftUI

/// Where distances are measured from: near me, a US city or town (the bundled Census list, so
/// "Chicago, IL" works with location off and no network), or a national park. Used by Tonight and
/// by Plan's "My free nights".
struct StartingPointPicker: View {
    enum Choice: Equatable { case park(String), place(StartingPlace) }
    @Environment(PlanModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    /// "Near me" as the first row, when the caller offers it.
    var nearMe:(()->Void)?=nil
    var selectedParkID:String?=nil
    var selectedPlace:StartingPlace?=nil
    /// Location was turned off for Nyx: say what works instead.
    var locationOff=false
    let choose:(Choice)->Void
    @State private var search=DebugScenario.place ?? ""
    @FocusState private var searchFocused:Bool
    var body: some View {
        let places=StartingPlaces.search(search,limit:12)
        let parks=model.parks.filter { search.isEmpty || $0.matches(search) }
        List {
            // The bar's search field fails at accessibility sizes on iOS 27 (see `SystemSearch`).
            if typeSize.isAccessibilitySize { PlaceSearchField(text:$search,focus:$searchFocused).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:8,leading:16,bottom:8,trailing:16)) }
            if locationOff { Section { Text("Location is off. Choose your city or the park closest to you.").font(.subheadline).foregroundStyle(palette.ink) }.listRowBackground(palette.panel) }
            if let nearMe, search.isEmpty, !locationOff {
                Section { Button { dismiss(); nearMe() } label:{ Label("Near me",systemImage:"location").frame(minHeight:44,alignment:.leading) }.accessibilityLabel("Use my location") }.listRowBackground(palette.panel)
            }
            if search.isEmpty {
                Section { Text("Search for your city or town, such as Chicago or Denver, or choose a park.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }.listRowBackground(palette.panel)
            } else if !places.isEmpty {
                Section("Cities and towns") {
                    ForEach(places) { place in row(title:place.name,detail:StartingPlaces.stateNames[place.state] ?? place.state,selected:place==selectedPlace) { choose(.place(place)); dismiss() } }
                }.listRowBackground(palette.panel)
            }
            if !parks.isEmpty {
                Section("National parks") {
                    ForEach(parks) { park in row(title:park.shortName,detail:park.state.replacingOccurrences(of:",",with:" · "),selected:selectedPlace == nil && park.id==selectedParkID) { choose(.park(park.id)); dismiss() } }
                }.listRowBackground(palette.panel)
            } else if places.isEmpty {
                Section { Text("No city, town or park by that name. Try a nearby larger city.").font(.subheadline).foregroundStyle(palette.muted) }.listRowBackground(palette.panel)
            }
        }
        .nightForm()
        .modifier(SystemSearch(text:$search,focused:$searchFocused,prompt:"City, town or park",enabled:!typeSize.isAccessibilitySize))
        .navigationTitle("Starting point").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
    }
    private func row(title:String,detail:String,selected:Bool,action:@escaping ()->Void)->some View {
        Button(action:action) {
            HStack {
                VStack(alignment:.leading,spacing:2) { Text(title).foregroundStyle(palette.ink); Text(detail).font(.caption).foregroundStyle(palette.muted) }
                Spacer(minLength:8)
                if selected { Image(systemName:"checkmark").foregroundStyle(palette.accent).accessibilityHidden(true) }
            }.frame(minHeight:44).contentShape(Rectangle())
        }
        .accessibilityElement(children:.combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
/// The picker's search field in the page itself, for accessibility text sizes, where it grows and wraps.
private struct PlaceSearchField: View {
    @Environment(\.nyx) private var palette
    @Binding var text:String
    var focus:FocusState<Bool>.Binding
    var body: some View {
        HStack(alignment:.center,spacing:10) {
            Image(systemName:"magnifyingglass").foregroundStyle(palette.muted).accessibilityHidden(true)
            TextField("City, town or park",text:$text,axis:.vertical).lineLimit(1...3).submitLabel(.search).focused(focus)
                .autocorrectionDisabled().textInputAutocapitalization(.words)
                .onChange(of:text) { _,new in if new.contains("\n") { text=new.replacingOccurrences(of:"\n",with:"") } }
                .accessibilityLabel("Search cities, towns and parks")
            if !text.isEmpty {
                Button { text="" } label:{ Image(systemName:"xmark.circle.fill").foregroundStyle(palette.muted).frame(minWidth:44,minHeight:44) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .padding(.horizontal,16).padding(.vertical,10).frame(minHeight:44)
        .contentShape(Rectangle()).onTapGesture { focus.wrappedValue=true }
        .background(RoundedRectangle(cornerRadius:22,style:.continuous).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius:22,style:.continuous).stroke(palette.line,lineWidth:0.5))
    }
}
#Preview("Starting point") { NavigationStack { StartingPointPicker(nearMe:{},selectedParkID:"jotr") { _ in } }.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Starting point · location off · AX5") { NavigationStack { StartingPointPicker(locationOff:true) { _ in } }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
