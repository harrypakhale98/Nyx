import SwiftUI
import SwiftData
import CoreLocation

/// "Save a spot": a place of the person's own (a backyard, a pullout, a field they know), scored
/// like a park from then on. Three ways to say where it is: where they stand now (location asked
/// for here, in context, after Nyx's own explainer), typed or pasted coordinates, or a city or town
/// from the bundled list. Then a name, offered from the nearest town, and Save. Nothing is looked up
/// on a server: the spot's time zone and region come from the nearest bundled town (`SavedSpots.make`).
/// No map to pick from: MapKit would ask Apple's servers, a host Nyx does not use (the world map is G4).
struct SaveSpotView: View {
    enum Source: String, CaseIterable, Identifiable, Hashable {
        case here, coordinates, place
        var id: String { rawValue }
    }
    @Environment(PlanModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nyx) private var palette
    @Environment(\.openURL) private var openURL
    @State private var source: Source
    @State private var locator: SpotLocator
    @State private var latitudeText=""
    @State private var longitudeText=""
    @State private var search: String
    @State private var chosen: StartingPlace?
    @State private var name=""
    @State private var explainLocation=false
    @State private var saveFailed=false
    /// The success thump when the spot is saved (the haptic vocabulary's "saved").
    @State private var savedCount=0
    @FocusState private var focus: Field?
    private enum Field: Hashable { case latitude, longitude, search, name }
    /// Told the new spot's id once it is saved.
    var onSaved: ((String)->Void)?=nil

    init(source: Source = .here, place: StartingPlace?=nil, search: String="", locator: SpotLocator?=nil, onSaved: ((String)->Void)?=nil) {
        _source=State(initialValue:place == nil ? source : .place)
        _chosen=State(initialValue:place)
        _search=State(initialValue:place?.name ?? search)
        _locator=State(initialValue:locator ?? SpotLocator())
        self.onSaved=onSaved
    }
    /// Where the spot would be saved, once the chosen way has an answer.
    private var point: CoordinateText.Point? {
        switch source {
        case .here:
            if case .found(let fix)=locator.state { return CoordinateText.Point(latitude:fix.latitude,longitude:fix.longitude) }
            return nil
        case .coordinates:
            guard case .value(let latitude)=CoordinateText.reading(latitudeText,axis:.latitude),
                  case .value(let longitude)=CoordinateText.reading(longitudeText,axis:.longitude) else { return nil }
            return CoordinateText.Point(latitude:latitude,longitude:longitude)
        case .place:
            return chosen.map { CoordinateText.Point(latitude:$0.latitude,longitude:$0.longitude) }
        }
    }
    /// The name offered in the field: a chosen town's own name, else "Near <town>" or the coordinates.
    private var offeredName: String {
        guard let point else { return "" }
        if source == .place, let chosen { return chosen.name }
        return SpotNaming.defaultName(latitude:point.latitude,longitude:point.longitude)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Where is it?",selection:$source) {
                        Label("Where I am now",systemImage:"location").tag(Source.here)
                        Label("Coordinates",systemImage:"number").tag(Source.coordinates)
                        Label("A city or town",systemImage:"building.2").tag(Source.place)
                    }
                    .pickerStyle(.inline).labelsHidden()
                } header:{ Text("Where is it?") }
                .listRowBackground(palette.panel)
                switch source {
                case .here: hereSection
                case .coordinates: coordinatesSection
                case .place: placeSection
                }
                if point != nil {
                    Section {
                        TextField("Name",text:$name,prompt:Text(offeredName),axis:.vertical)
                            .lineLimit(1...3).textInputAutocapitalization(.words).submitLabel(.done).focused($focus,equals:.name)
                            .onChange(of:name) { _,new in if new.contains("\n") { name=new.replacingOccurrences(of:"\n",with:"") } }
                            .accessibilityLabel("Name")
                    } header:{ Text("Name") } footer:{
                        Text("Leave it empty to use \"\(offeredName)\".").foregroundStyle(palette.muted)
                    }
                    .listRowBackground(palette.panel)
                }
                Section {
                    ForEach(privacyLines,id:\.self) { line in
                        Text(line).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                    }
                } header:{ Text("On this iPhone") }
                .listRowBackground(palette.panel)
            }
            .nightForm().readableForm()
            .navigationTitle("Save a spot").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button(role:.cancel) { dismiss() } }
                // iOS 26's confirm glyph, which the system dims until there is a place to save.
                ToolbarItem(placement:.confirmationAction) { Button(role:.confirm) { save() }.accessibilityLabel("Save").accessibilityInputLabels([Text("Save"),Text("Save a spot")]).disabled(point == nil) }
            }
            .sheet(isPresented:$explainLocation) {
                PermissionExplainer(symbol:"location",title:"Save where you are",message:"Nyx reads where you are once, to save this spot. Nothing is sent unless you save it.",action:"Use my location") {
                    explainLocation=false; locator.locate()
                }.nyxPresentation()
            }
            .alert("Unable to save",isPresented:$saveFailed) { Button("OK",role:.cancel) {} } message:{
                Text(model.journalUnavailable ? "Saved spots are kept with your journal, which could not be opened. Nothing was changed." : "Your changes could not be stored. Try again when space is available.")
            }
            // A light tick, as for every small keep (a copied spot, a bookmark): the success thump is the journal's.
            .sensoryFeedback(.selection,trigger:savedCount)
            .onChange(of:source) { _,_ in focus=nil }
        }
    }

    // MARK: Where I am now

    @ViewBuilder private var hereSection: some View {
        Section {
            switch locator.state {
            case .idle:
                Button { useLocation() } label:{ Label("Use where I am now",systemImage:"location.fill").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }
                    .foregroundStyle(palette.accent)
            case .locating:
                HStack(spacing:10) { ProgressView(); Text("Finding where you are") }.foregroundStyle(palette.muted).frame(minHeight:44)
                    .accessibilityElement(children:.combine)
            case .found(let fix):
                VStack(alignment:.leading,spacing:6) {
                    Text(SpotNaming.coordinates(latitude:fix.latitude,longitude:fix.longitude)).font(.body.monospacedDigit()).foregroundStyle(palette.ink)
                    Text(SpotLocator.accuracyLine(fix)).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
                .accessibilityElement(children:.combine)
                Button { locator.locate() } label:{ Text("Find again").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }
                    .foregroundStyle(palette.accent)
            case .denied:
                Text("Location is off for Nyx. Turn it on in Settings, or type the coordinates instead.").foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                Button { if let url=URL(string:UIApplication.openSettingsURLString) { openURL(url) } } label:{ Label("Open Settings",systemImage:"gear").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }
                    .foregroundStyle(palette.accent)
            case .failed:
                Text("Your location is unavailable right now. Try again, or type the coordinates instead.").foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                Button { locator.locate() } label:{ Text("Try again").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }
                    .foregroundStyle(palette.accent)
            }
        } header:{ Text("Where I am now") } footer:{
            Text("Nyx reads your location once, on this iPhone, only when you ask.").foregroundStyle(palette.muted)
        }
        .listRowBackground(palette.panel)
    }
    /// Nyx's explainer first, the first time; the system's question follows from it.
    private func useLocation() {
        if locator.needsPermission { explainLocation=true } else { locator.locate() }
    }

    // MARK: Coordinates

    @ViewBuilder private var coordinatesSection: some View {
        Section {
            coordinateField("Latitude",example:"34.01",text:$latitudeText,field:.latitude,axis:.latitude)
            coordinateField("Longitude",example:"-116.18",text:$longitudeText,field:.longitude,axis:.longitude)
        } header:{ Text("Coordinates") } footer:{
            Text("In decimal degrees, such as 34.01, -116.18. South and west are negative. You can paste both at once.").foregroundStyle(palette.muted)
        }
        .listRowBackground(palette.panel)
    }
    private func coordinateField(_ title:LocalizedStringKey,example:String,text:Binding<String>,field:Field,axis:CoordinateText.Axis)->some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.subheadline).foregroundStyle(palette.muted).accessibilityHidden(true)
            TextField(title,text:text,prompt:Text(verbatim:example))
                .keyboardType(.numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
                .font(.body.monospacedDigit()).focused($focus,equals:field)
                .onChange(of:text.wrappedValue) { old,new in splitIfPair(old:old,new:new) }
                .accessibilityLabel(title)
            if let problem=Self.problem(CoordinateText.reading(text.wrappedValue,axis:axis),axis:axis) {
                Text(problem).font(.caption).foregroundStyle(palette.accent).fixedSize(horizontal:false,vertical:true)
            }
        }
        .padding(.vertical,4)
    }
    /// A pair pasted into either field fills both. Only a paste (several characters at once): typing
    /// "34.01, -116.18" key by key must not split at "34.01, -1".
    private func splitIfPair(old:String,new:String) {
        guard new.count>=old.count+3, case .point(let point)=CoordinateText.pair(new) else { return }
        latitudeText=CoordinateText.field(point.latitude)
        longitudeText=CoordinateText.field(point.longitude)
    }
    /// What is wrong with a field, in words, or nil.
    static func problem(_ reading:CoordinateText.Reading,axis:CoordinateText.Axis)->String? {
        switch reading {
        case .empty, .value: return nil
        case .outOfRange: return axis == .latitude ? String(localized:"Latitude runs from -90 to 90.") : String(localized:"Longitude runs from -180 to 180.")
        case .unreadable: return axis == .latitude ? String(localized:"Use decimal degrees, such as 34.01.") : String(localized:"Use decimal degrees, such as -116.18.")
        }
    }

    // MARK: A city or town

    @ViewBuilder private var placeSection: some View {
        let results=StartingPlaces.search(search,limit:8)
        Section {
            TextField("City or town",text:$search,prompt:Text("City or town"))
                .autocorrectionDisabled().textInputAutocapitalization(.words).submitLabel(.search).focused($focus,equals:.search)
            ForEach(results) { place in
                let selected=place == chosen
                Button { chosen=place; focus=nil } label:{
                    HStack {
                        VStack(alignment:.leading,spacing:2) {
                            Text(place.name).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                            Text(place.regionName).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                        }
                        Spacer(minLength:8)
                        if selected { Image(systemName:"checkmark").foregroundStyle(palette.accent).accessibilityHidden(true) }
                    }.frame(minHeight:44).contentShape(Rectangle())
                }
                .accessibilityElement(children:.combine)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if !search.trimmingCharacters(in:.whitespaces).isEmpty, results.isEmpty {
                Text("No city or town by that name. Try a nearby larger one.").font(.subheadline).foregroundStyle(palette.muted)
            }
        } header:{ Text("A city or town") } footer:{
            Text("The spot sits at the town's point on Nyx's list, not at a particular field or hill. For somewhere outside town, use coordinates.").foregroundStyle(palette.muted)
        }
        .listRowBackground(palette.panel)
    }

    // MARK: Saving

    /// What saving sends, said where it is decided. Where the person stands is sent only if they save it.
    private var privacyLines: [String] {
        var lines=[String(localized:"Nyx saves this spot on this iPhone. Its clouds are asked for with its position rounded to about \(SpotForecast.roundingDistance()).")]
        if source == .here { lines.append(String(localized:"This is where you are now. If you save it, its rounded position is asked about like any spot's. If you don't, nothing is sent.")) }
        if !(model.weatherEnabled && model.spotForecastsEnabled) {
            lines.append(String(localized:"Clouds at your saved spots is off in Your privacy, so nothing is sent: the spot uses its usual clouds."))
        }
        return lines
    }
    private func save() {
        guard let point else { return }
        // Spots share the journal's store; a save into its stand-in would not last.
        guard !model.journalUnavailable else { saveFailed=true; return }
        let spot=SavedSpots.make(name:SpotNaming.finalName(typed:name,offered:offeredName),latitude:point.latitude,longitude:point.longitude)
        do {
            try SavedSpots.save(spot,in:context)
            savedCount+=1
            onSaved?(spot.id)
            dismiss()
        } catch { saveFailed=true }
    }
}

/// One reading of where this iPhone is, for saving a spot: as precise as the person allows, asked
/// for only when they tap, never kept running. Its own manager, so Tonight's "Near me" (which
/// measures from a rougher fix) is left as it was.
@MainActor @Observable final class SpotLocator: NSObject, CLLocationManagerDelegate {
    struct Fix: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        /// Metres, as Core Location reports the horizontal accuracy.
        let accuracy: Double
        /// Precise Location is off for Nyx: the fix is only good to a few kilometers.
        let reduced: Bool
    }
    enum State: Equatable, Sendable { case idle, locating, found(Fix), denied, failed }
    var state: State
    @ObservationIgnored private let manager=CLLocationManager()
    @ObservationIgnored private let live: Bool
    /// `state` other than idle: a fixed state for previews, never asking Core Location.
    init(state: State = .idle) {
        self.state=state
        live=state == .idle
        super.init()
        manager.delegate=self
        manager.desiredAccuracy=kCLLocationAccuracyBest
    }
    /// True until the person has answered the system's question once.
    var needsPermission: Bool { live && manager.authorizationStatus == .notDetermined }
    func locate() {
        guard live else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: state = .locating; manager.requestLocation()
        case .denied, .restricted: state = .denied
        default: state = .locating; manager.requestWhenInUseAuthorization()
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard live else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: if state == .locating { manager.requestLocation() }
        case .denied, .restricted: if state == .locating { state = .denied }
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location=locations.last else { state = .failed; return }
        state = .found(Fix(latitude:location.coordinate.latitude,longitude:location.coordinate.longitude,
                           accuracy:location.horizontalAccuracy,reduced:manager.accuracyAuthorization == .reducedAccuracy))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        if (error as? CLError)?.code == .denied { state = .denied } else { state = .failed }
    }
    /// "Within about 20 m." In the reader's units; with Precise Location off, that said plainly.
    static func accuracyLine(_ fix: Fix) -> String {
        if fix.reduced { return String(localized:"Precise Location is off for Nyx, so this is only good to a few kilometers. You can turn it on in Settings.") }
        guard fix.accuracy > 0 else { return String(localized:"Accuracy unknown.") }
        let distance=Measurement(value:fix.accuracy,unit:UnitLength.meters).formatted(.measurement(width:.abbreviated,usage:.road))
        return String(localized:"Within about \(distance).")
    }
}

#Preview("Save a spot · where I am") {
    SaveSpotView().environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true).preferredColorScheme(.dark)
}
#Preview("Save a spot · found") {
    SaveSpotView(locator:SpotLocator(state:.found(.init(latitude:34.0123,longitude:-116.1834,accuracy:18,reduced:false)))).environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true).preferredColorScheme(.dark)
}
#Preview("Save a spot · precise off") {
    SaveSpotView(locator:SpotLocator(state:.found(.init(latitude:34.01,longitude:-116.18,accuracy:3000,reduced:true)))).environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true).preferredColorScheme(.dark)
}
#Preview("Save a spot · location off") {
    SaveSpotView(locator:SpotLocator(state:.denied)).environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true).preferredColorScheme(.dark)
}
#Preview("Save a spot · unavailable") {
    SaveSpotView(locator:SpotLocator(state:.failed)).environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true).preferredColorScheme(.dark)
}
#Preview("Save a spot · coordinates") {
    SaveSpotView(source:.coordinates).environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true).preferredColorScheme(.dark)
}
#Preview("Save a spot · a town, AX5") {
    SaveSpotView(source:.place,search:"Twentynine").environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
}
#Preview("Save a spot · night vision") {
    SaveSpotView(source:.coordinates).environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true)
        .environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark)
}
#Preview("Save a spot · iPad width") {
    SaveSpotView(source:.coordinates).environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self,SavedSpot.self],inMemory:true)
        .environment(\.horizontalSizeClass,.regular).frame(width:1000,height:800).preferredColorScheme(.dark)
}
