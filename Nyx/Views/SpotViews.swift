import SwiftUI
import SwiftData

// Saved spots on screen (G3): how a spot names itself beside the parks, its own panel on its page
// (where it is, rename, delete), and the feed that hands the store's spots to the model.

extension Place {
    /// A spot's region in the reader's words: "California"; "Ontario, Canada"; "France". Empty far
    /// from every town on Nyx's list, where no country was known.
    var spotLocality: String {
        guard !countryCode.isEmpty else { return region }
        return StartingPlaces.regionName(countryCode:countryCode,region:region)
    }
    /// The line under a place's name: a park's states ("CA · NV"), a spot's region and country.
    var regionLine: String { isSavedSpot ? spotLocality : region.replacingOccurrences(of:",",with:" · ") }
    /// The eyebrow over a place's name on its page and in Plan: a park's states and its Dark Sky
    /// status (data, not a slogan); "Your spot · California" for a spot the person saved.
    var placeEyebrow: String {
        if isSavedSpot {
            let locality=spotLocality
            return locality.isEmpty ? String(localized:"Your spot") : String(localized:"Your spot · \(locality)")
        }
        let states=region.replacingOccurrences(of:",",with:" · ")
        return darkSkyDesignated ? String(localized:"\(states) · International Dark Sky Park") : states
    }
}

/// Hands the store's saved spots to the model whenever they change (`PlanModel.setSpots`), for a
/// scene whose root is not `RootView` (a park's own iPad window). `RootView` does the same itself,
/// ahead of its saved-place updates.
struct SavedSpotsFeed: View {
    @Environment(PlanModel.self) private var model
    @Query private var spots: [SavedSpot]
    var body: some View {
        Color.clear.frame(width:0,height:0).accessibilityHidden(true)
            .onAppear { model.setSpots(spots) }
            .onChange(of:SavedSpotsFeed.signature(spots)) { _,_ in model.setSpots(spots) }
    }
    /// Everything about the spots that the model shows: a rename or a move is a change, an untouched store is not.
    static func signature(_ spots:[SavedSpot])->[String] {
        spots.map { "\($0.id)|\($0.name)|\($0.latitude)|\($0.longitude)|\($0.timeZoneID)|\($0.countryCode)|\($0.region)|\($0.note ?? "")" }
    }
}

/// A spot's own panel on its page, where the parks have their viewing spots: where it is (to copy,
/// or hand to Maps), whose clock its times keep, what its clouds cost in privacy, and Rename and
/// Delete. Deleting asks first, and closes the page.
struct SpotPanel: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let spot: Park
    @State private var copied=false
    @State private var renaming=false
    @State private var newName=""
    @State private var confirmingDelete=false
    @State private var failed=false
    private var coordinates: String { "\(CoordinateText.field((spot.latitude*10_000).rounded()/10_000)), \(CoordinateText.field((spot.longitude*10_000).rounded()/10_000))" }
    var body: some View {
        Panel {
            VStack(alignment:.leading,spacing:14) {
                Eyebrow(text:"Your spot")
                VStack(alignment:.leading,spacing:6) {
                    Text(SpotNaming.coordinates(latitude:spot.latitude,longitude:spot.longitude)).font(.system(.title3,design:.serif).monospacedDigit()).foregroundStyle(palette.ink)
                    Text(clockLine).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }.accessibilityElement(children:.combine)
                if !spot.description.isEmpty { Text(spot.description).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:10) { placeActions }
                    VStack(alignment:.leading,spacing:6) { placeActions }
                }
                if copied { Text("Copied \(coordinates)").font(.caption.monospacedDigit()).foregroundStyle(palette.muted).transition(.opacity) }
                Text(cloudLine).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                Divider().overlay(palette.line)
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:10) { editActions }
                    VStack(alignment:.leading,spacing:6) { editActions }
                }
            }
        }
        .sensoryFeedback(.success,trigger:copied) { _,new in new }
        .alert("Rename spot",isPresented:$renaming) {
            TextField("Name",text:$newName).textInputAutocapitalization(.words)
            Button("Cancel",role:.cancel) {}
            Button("Save") { rename() }
        } message:{ Text("Only this iPhone knows the name.") }
        .confirmationDialog("Delete \(spot.shortName)?",isPresented:$confirmingDelete,titleVisibility:.visible) {
            Button("Delete spot",role:.destructive) { delete() }
            Button("Cancel",role:.cancel) {}
        } message:{ Text("It leaves your saved places, widgets and reminders. Journal entries written there keep their words and photos.") }
        .alert("Unable to save",isPresented:$failed) { Button("OK",role:.cancel) {} } message:{
            Text(model.journalUnavailable ? "Saved spots are kept with your journal, which could not be opened. Nothing was changed." : "Your changes could not be stored. Try again when space is available.")
        }
    }
    @ViewBuilder private var placeActions: some View {
        Button {
            UIPasteboard.general.string="\(spot.latitude), \(spot.longitude)"
            copied=true
            Task { try? await Task.sleep(for:.seconds(3)); copied=false }
        } label:{ Label("Copy coordinates",systemImage:"doc.on.doc").font(.footnote.weight(.medium)).frame(minHeight:44) }
            .buttonStyle(.borderless).foregroundStyle(palette.accent)
            .accessibilityHint(String(localized:"Copies \(coordinates)."))
        if let url=MapsHandOff.directions(latitude:spot.latitude,longitude:spot.longitude) {
            Button { openURL(url) } label:{ Label("Directions in Maps",systemImage:"arrow.triangle.turn.up.right.diamond").font(.footnote.weight(.medium)).frame(minHeight:44) }
                .buttonStyle(.borderless).foregroundStyle(palette.accent)
                .accessibilityHint("Opens Apple Maps with driving directions. Nyx sends nothing.")
        }
    }
    @ViewBuilder private var editActions: some View {
        Button { newName=spot.name; renaming=true } label:{ Label("Rename",systemImage:"pencil").font(.footnote.weight(.medium)).frame(minHeight:44) }
            .buttonStyle(.borderless).foregroundStyle(palette.accent)
            .accessibilityLabel("Rename spot")
        Button(role:.destructive) { confirmingDelete=true } label:{ Label("Delete spot",systemImage:"trash").font(.footnote.weight(.medium)).frame(minHeight:44) }
            .buttonStyle(.borderless).foregroundStyle(palette.accent)
    }
    /// Whose clock the page keeps, and where that came from.
    private var clockLine: String {
        let zone=spot.timeZone.localizedName(for:.generic,locale:.current) ?? spot.timeZoneID
        return String(localized:"Times here keep \(zone), from the nearest town on Nyx's list. Near a border, that can be the neighbor's.")
    }
    /// What this spot's clouds cost, as Your privacy says it.
    private var cloudLine: String {
        model.weatherEnabled && model.spotForecastsEnabled
            ? String(localized:"Saved on this iPhone. Its clouds are asked for with its position rounded to about 11 km.")
            : String(localized:"Saved on this iPhone. Clouds at your saved spots is off in Your privacy, so this spot uses its usual clouds.")
    }
    private func rename() {
        let name=SpotNaming.finalName(typed:newName,offered:spot.name)
        guard name != spot.name else { return }
        guard !model.journalUnavailable else { failed=true; return }
        let id=spot.id
        do {
            guard let record=try context.fetch(FetchDescriptor<SavedSpot>(predicate:#Predicate { $0.id == id })).first else { return }
            record.name=name
            try context.save()
        } catch { context.rollback(); failed=true }
    }
    private func delete() {
        guard !model.journalUnavailable else { failed=true; return }
        do { try SavedSpots.delete(spot.id,in:context); dismiss() } catch { failed=true }
    }
}

#if DEBUG
/// Preview spots: Twentynine Palms's edge, and a field outside Lyon.
enum SpotPreview {
    static var mojave: Park { Place(spotID:"pin:preview-mojave",name:"North pullout",latitude:34.18,longitude:-116.05,timeZoneID:"America/Los_Angeles",countryCode:"US",region:"CA",note:"Gate locks at 10. Park by the cattle guard.") }
    static var lyon: Park { Place(spotID:"pin:preview-lyon",name:"Near Lyon",latitude:45.88,longitude:4.95,timeZoneID:"Europe/Paris",countryCode:"FR",region:"Auvergne-Rhone-Alpes") }
}
#Preview("Spot panel") {
    ScrollView { SpotPanel(spot:SpotPreview.mojave).padding(24) }.background(Color.black).environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true).preferredColorScheme(.dark)
}
#Preview("Spot panel · abroad, AX5") {
    ScrollView { SpotPanel(spot:SpotPreview.lyon).padding(24) }.background(Color.black).environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
}
#Preview("Spot panel · night vision") {
    ScrollView { SpotPanel(spot:SpotPreview.mojave).padding(24) }.background(Color.black).environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true)
        .environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark)
}
#Preview("Spot page") {
    let model=PlanModel()
    model.setSpots(places:[SpotPreview.mojave])
    return NavigationStack { ParkDetailView(park:SpotPreview.mojave) }.environment(model).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true).preferredColorScheme(.dark)
}
#endif

/// The choices of a park menu (Plan's month, a journal entry): the person's spots first when there
/// are any, then the national parks, each under its heading; the parks alone otherwise, as before.
struct PlacePickerOptions: View {
    @Environment(PlanModel.self) private var model
    let title: LocalizedStringKey
    @Binding var selection: String
    var body: some View {
        Picker(title,selection:$selection) {
            if model.spots.isEmpty {
                ForEach(model.parks) { Text($0.shortName).tag($0.id) }
            } else {
                Section("Your spots") { ForEach(model.spots) { Text($0.shortName).tag($0.id) } }
                Section("National parks") { ForEach(model.parks) { Text($0.shortName).tag($0.id) } }
            }
        }
    }
}
