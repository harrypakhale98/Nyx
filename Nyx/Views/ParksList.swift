import SwiftUI
import SwiftData

/// The Parks tab's list. From a US starting point it is the 63 national parks exactly as before the
/// world catalogue (G4), with one quiet "Around the world" row at the foot that opens the rest of the
/// world by country. From anywhere else the person's own country leads, then the world by country
/// (the US parks among them). Search finds any place by name, region or country, accents folded.
/// Places abroad are scored only as their rows appear, and their forecasts are asked for only for
/// what is on screen (`OnScreen`), by whole 10° tiles (`PlanModel.refreshForecasts(for:)`).
struct ParksView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.modelContext) private var context
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
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
    /// "Save a spot" is open.
    @State private var addingSpot=false
    /// A spot whose deletion waits for the person to confirm it.
    @State private var deletingSpot:Park?
    @AppStorage("parksByScore") private var byScore=false
    @Namespace private var zoom
    /// The world by country, worked out off the main thread once the catalogue is read (and again when
    /// the starting point moves to another country, which leads the list).
    @State private var groups:[CountryGroup]=[]
    /// Catalogue places matching the search (`PlanModel.searchPlaces`), and whether the limit cut them short.
    @State private var found:[Park]=[]
    @State private var foundCapped=false
    /// The countries opened in the world list, for this window.
    @State private var openCountries:Set<String>=[]
    /// The "Around the world" row under the US parks, open or closed, kept for the window.
    @SceneStorage("parksWorldOpen") private var worldOpen=false
    /// The catalogue rows on screen, so their forecasts are asked for and nothing else.
    @State private var onScreen=OnScreenForecasts()
    private var reduceMotion:Bool { systemReduceMotion || forcedReduceMotion }
    /// Worked out once per update of the list (the body reads it into `shown`): ranking 63 parks is not free.
    private var filtered:[Park] {
        let filter=ParkFilter(darkOnly:darkOnly,stepFreeOnly:stepFreeOnly)
        let savedIDs=Set(saved.map(\.parkID)), query=Park.folded(search)
        let matching=model.parks.filter { p in filter.includes(p) && (!savedOnly || savedIDs.contains(p.id)) && (query.isEmpty || p.matches(folded:query)) }
        return byScore ? model.ranked(matching) : matching
    }
    /// The person's own spots, above the parks: always, unless a filter only parks can meet is on
    /// (Dark Sky designation, step-free viewing); a search finds them by name like the parks.
    private var shownSpots:[Park] {
        guard !darkOnly, !stepFreeOnly else { return [] }
        let savedIDs=Set(saved.map(\.parkID)), query=Park.folded(search)
        return model.spots.filter { spot in (!savedOnly || savedIDs.contains(spot.id)) && (query.isEmpty || spot.matches(folded:query)) }
    }
    /// Saved parks lead the list only when nothing narrows it.
    private var narrowed:Bool { darkOnly || stepFreeOnly || savedOnly }
    private var showsSavedSection:Bool { !saved.isEmpty && !savedOnly && search.isEmpty && !darkOnly && !stepFreeOnly }
    /// The country that leads the world list: the starting point's, or before one is chosen this device's region.
    private var homeCountry:String {
        WorldBrowse.homeCountry(startChosen:model.startChosen,place:model.homePlace?.countryCode,park:model.home?.countryCode,region:Locale.current.region?.identifier)
    }
    /// The world is shown once the catalogue is read, and never under step-free viewing (nps.gov is its only source).
    private var worldShown:Bool { !model.catalog.isEmpty && !groups.isEmpty && !stepFreeOnly }
    /// Browsing abroad: the person's own country and the world by country take the national parks' place.
    private var abroad:Bool { worldShown && homeCountry != "US" && search.isEmpty && !savedOnly }
    /// Abroad, until the world catalogue is read (off the main thread from launch) and grouped by country:
    /// skeleton rows, never the US national parks standing in for the person's own country.
    private var awaitingWorld:Bool {
        guard homeCountry != "US", search.isEmpty, !savedOnly, !stepFreeOnly else { return false }
        return !model.catalogIsReady || (!model.catalog.isEmpty && groups.isEmpty)
    }
    /// Followed catalogue places, for "Saved for later" and "Saved parks only", narrowed like the parks.
    private var savedWorld:[Park] {
        guard !model.catalog.isEmpty, !stepFreeOnly else { return [] }
        let filter=ParkFilter(darkOnly:darkOnly), query=Park.folded(search)
        return saved.compactMap { model.park($0.parkID) }.filter { $0.isCatalogPlace && filter.includes($0) && (query.isEmpty || $0.matches(folded:query)) }
    }
    /// The world by country as shown: narrowed by Dark Sky designation; from a US starting point without
    /// the curated parks (listed above it); without the saved places while "Saved for later" lists them.
    private var shownGroups:[CountryGroup] {
        guard worldShown else { return [] }
        let hidden=showsSavedSection ? Set(saved.map(\.parkID)) : []
        return WorldBrowse.narrowed(groups,darkOnly:darkOnly,curated:homeCountry != "US",hiding:hidden)
    }
    /// The scrolling list itself.
    @ViewBuilder private var list: some View {
        // Also while the offline caches are still being read after the first frame (`cachesPending`).
        let abroad:Bool=self.abroad, waiting:Bool=awaitingWorld || model.cachesPending
        let shown:[Park]=abroad || waiting ? [] : filtered, spots=shownSpots
        let savedWorld:[Park]=self.savedWorld, groups:[CountryGroup]=shownGroups
        let found:[Park]=worldShown && !search.isEmpty ? self.found.filter { ParkFilter(darkOnly:darkOnly).includes($0) } : []
        let home:String=homeCountry
        let own:CountryGroup?=abroad ? groups.first(where:{ $0.code==home }) : nil
        let others:[CountryGroup]=groups.filter { $0.code != own?.code }
        let savedParks:[Park]=showsSavedSection ? model.parks.filter { p in saved.contains { $0.parkID==p.id } } : []
        let savedListed:[Park]=showsSavedSection ? savedParks+savedWorld : []
        let line:String=countLine(listed:listedCount(abroad:abroad,shown:shown,groups:groups,found:found,savedWorld:savedWorld))
        let eyebrow:LocalizedStringKey=byScore && !abroad ? "Darkest tonight first" : "\(line)"
        let nothing:Bool=isEmpty(shown:shown,spots:spots,found:found,savedWorld:savedWorld,groups:groups,abroad:abroad)
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                // Waiting for the world, no count yet: "63 places" would describe only the US parks.
                if !waiting { Eyebrow(text:eyebrow) }
                if typeSize.isAccessibilitySize { InlineSearchField(text:$search,prompt:searchPrompt,focus:$searchFocused) }
                // Only worth saying when a row actually reads "Estimate".
                if !waiting, estimateShown(shown:shown,own:own) { Text("Scores marked Estimate have no cloud forecast yet and use each park's usual clouds.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                if stepFreeOnly { Text("Parks with at least one viewing spot that nps.gov describes as step-free or partly step-free. Check with the park before you go.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                if DebugScenario.state=="loading" || waiting { ForEach(0..<5,id:\.self) { _ in SkeletonRow() } }
                else if nothing || DebugScenario.state=="empty" { CalmState(symbol:"sparkle.magnifyingglass",title:"No parks in this sky",message:"Try another name or widen your filters.") }
                else { sections(shown:shown,spots:spots,found:found,savedWorld:savedWorld,savedListed:savedListed,groups:groups,own:own,others:others,abroad:abroad) }
            }.padding(NyxMetrics.pagePadding).readableColumn()
            .background { SearchEnder(request:commands?.sheetRequest?.id) }
            // VoiceOver rotors: jump straight to the parks with a closure alert, or a Pristine sky tonight.
            // The rows already on screen only: a rotor never scores the whole world.
            .accessibilityRotor(Text("Closures"),entries:rotor(spots,shown) { park in model.closure(park).map { String(localized:"\(park.shortName): \($0)") } },entryID:\.id,entryLabel:\.label)
            .accessibilityRotor(Text("Pristine nights"),entries:rotor(spots,shown) { park in
                let night=model.night(park); return night.score.value>=90 ? String(localized:"\(park.shortName), \(night.score.value)") : nil
            },entryID:\.id,entryLabel:\.label)
        }.background(NightBackground(veil:0.45)).navigationTitle("Parks").navigationBarTitleDisplayMode(.inline)
            .modifier(SystemSearch(text:$search,focused:$searchFocused,prompt:searchPrompt,enabled:!typeSize.isAccessibilitySize))
    }
    var body: some View {
        withWorld(list)
            .sheet(isPresented:$addingSpot) { SaveSpotView().nyxPresentation() }
            .confirmationDialog(deletingSpot.map { String(localized:"Delete \($0.shortName)?") } ?? "",isPresented:Binding(get:{ deletingSpot != nil },set:{ if !$0 { deletingSpot=nil } }),titleVisibility:.visible,presenting:deletingSpot) { spot in
                Button("Delete spot",role:.destructive) { deleteSpot(spot) }
                Button("Cancel",role:.cancel) {}
            } message:{ _ in Text("It leaves your saved places, widgets and reminders. Journal entries written there keep their words and photos.") }
            .parkSaveAlert(isPresented:$saveFailed,journalUnavailable:model.journalUnavailable)
            // ⌘F from anywhere in the window.
            .onChange(of:commands?.searchRequest) { _,_ in focusSearchIfAsked() }
            .onAppear { focusSearchIfAsked() }
            // One request brings cloud forecasts for all 63 parks, so every score can include clouds.
            .task { await model.refresh(model.parks,parkUpdates:false) }
            .refreshable { await refreshAll() }
            .toolbar { ToolbarItem(placement:.topBarTrailing) {
                Button { addingSpot=true } label:{ Label("Save a spot",systemImage:"plus") }
                    .accessibilityInputLabels([Text("Save a spot"),Text("Add a spot"),Text("New spot")]).help("Save a spot")
            } }
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Menu {
                // Abroad the list is by country and name; the darkest place within reach tonight is Tonight's answer.
                if !abroad { Picker("Sort",selection:$byScore) { Label("Name",systemImage:"textformat").tag(false); Label("Darkest tonight",systemImage:"moon.stars").tag(true) } }
                Section { Toggle("Dark Sky designated only",isOn:$darkOnly); Toggle("Step-free viewing",isOn:$stepFreeOnly); Toggle("Saved parks only",isOn:$savedOnly) }
            } label:{ Label("Sort and filter",systemImage:"line.3.horizontal.decrease") }.accessibilityLabel("Sort and filter parks").accessibilityInputLabels([Text("Filter"),Text("Sort"),Text("Sort and filter")]) } }
            .navigationDestination(for:Park.self) { park in ParkDetailView(park:park).modifier(ParkTransition(sourceID:park.id,namespace:zoom)) }
    }
    /// The list's sections under its eyebrow: your spots, saved places, then the parks or the world.
    @ViewBuilder private func sections(shown:[Park],spots:[Park],found:[Park],savedWorld:[Park],savedListed:[Park],groups:[CountryGroup],own:CountryGroup?,others:[CountryGroup],abroad:Bool)->some View {
        // Your spots: the places the person saved, scored like the parks, then a way to add another.
        if !spots.isEmpty {
            Eyebrow(text:"Your spots")
            ForEach(spots) { spot in link(spot) }
            if search.isEmpty { addSpotRow }
        }
        if showsSavedSection {
            Eyebrow(text:"Saved for later")
            ForEach(savedListed) { p in savedRow(p) }
        }
        if abroad { abroadSections(own:own,others:others) }
        else { homeSections(shown:shown,spots:spots,found:found,savedWorld:savedWorld,groups:groups) }
    }
    /// A saved place above the list: a park with its week, a place abroad as in the world list.
    @ViewBuilder private func savedRow(_ place:Park)->some View {
        if place.isCatalogPlace { worldRow(place,divided:false) } else { link(place) }
    }
    /// Abroad: the person's own country first, then the rest of the world by country.
    @ViewBuilder private func abroadSections(own:CountryGroup?,others:[CountryGroup])->some View {
        if let own {
            Eyebrow(text:"\(own.name)")
            LazyVStack(spacing:0) { ForEach(own.places) { p in worldRow(p) } }
        }
        if !others.isEmpty {
            Eyebrow(text:"Around the world")
            Text(WorldBrowse.summary(others)).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            countries(others)
        }
    }
    /// From a US starting point (or while searching or narrowing to saved places): the national parks
    /// as before, the search's matches abroad, and one row that opens the world.
    @ViewBuilder private func homeSections(shown:[Park],spots:[Park],found:[Park],savedWorld:[Park],groups:[CountryGroup])->some View {
        let fromUS=homeCountry=="US"
        // Searching from abroad, the places that match come first; the US parks follow.
        if !fromUS, !found.isEmpty { foundSection(found,heading:!spots.isEmpty) }
        if !shown.isEmpty || (savedOnly && !savedWorld.isEmpty) {
            if !spots.isEmpty || showsSavedSection || (!fromUS && !found.isEmpty) { Eyebrow(text:"US national parks") }
            LazyVStack(spacing:0) {
                ForEach(shown.filter { p in !(showsSavedSection && saved.contains { $0.parkID==p.id }) }) { p in link(p); Divider().overlay(palette.line) }
                if savedOnly { ForEach(savedWorld) { p in worldRow(p) } }
            }
        }
        if fromUS, !found.isEmpty { foundSection(found,heading:true) }
        // From a US starting point the world waits behind one row, so the list reads as it always has.
        if worldShown, search.isEmpty, !savedOnly, !groups.isEmpty { worldEntry(groups) }
    }
    /// The world catalogue's work for the list: grouping by country off the main thread (once the
    /// catalogue is read, and again for another home country), and the search's matches abroad.
    private func withWorld(_ content:some View)->some View {
        content
            .task(id:"\(model.catalog.count)|\(homeCountry)") { await group() }
            .task(id:"\(model.catalog.count)|\(search)") { searchWorld() }
    }
    private func group() async {
        guard !model.catalog.isEmpty else { groups=[]; return }
        let places:[Park]=model.parks+model.catalog, home:String=homeCountry
        groups=await Task.detached(priority:.userInitiated) { WorldBrowse.groups(places,home:home) }.value
    }
    /// The catalogue's matches for the search, once per change of the words (folded and ranked by the model).
    private func searchWorld() {
        guard !search.isEmpty, !model.catalog.isEmpty else { found=[]; foundCapped=false; return }
        let results=model.searchPlaces(search,limit:WorldBrowse.searchLimit)
        found=results.filter(\.isCatalogPlace); foundCapped=results.count>=WorldBrowse.searchLimit
    }
    /// Pull to refresh: the parks' forecasts, and the places abroad on screen.
    private func refreshAll() async {
        await model.refresh(model.parks,force:true,parkUpdates:false)
        let visible=onScreen.visible
        if !visible.isEmpty { await model.refreshForecasts(for:visible,force:true) }
    }
    /// With the world catalogue the search reaches every country, so the prompt says so.
    private var searchPrompt:LocalizedStringKey { model.catalog.isEmpty ? "Park or state" : "Park, region or country" }
    /// Nothing to list: the calm empty state instead.
    private func isEmpty(shown:[Park],spots:[Park],found:[Park],savedWorld:[Park],groups:[CountryGroup],abroad:Bool)->Bool {
        guard shown.isEmpty, spots.isEmpty, found.isEmpty else { return false }
        if savedOnly, !savedWorld.isEmpty { return false }
        return abroad ? groups.isEmpty : true
    }
    /// How many places the list shows, for the eyebrow while a filter narrows it.
    private func listedCount(abroad:Bool,shown:[Park],groups:[CountryGroup],found:[Park],savedWorld:[Park])->Int {
        if abroad { return groups.reduce(0) { $0+$1.places.count } }
        guard worldShown, homeCountry != "US" else { return shown.count }
        return shown.count+found.count+(savedOnly ? savedWorld.count : 0)
    }
    /// The eyebrow's count: the 63 parks from a US starting point, exactly as before; from anywhere
    /// else, once the catalogue is read, every place Nyx can look up ("3,422 places to look up").
    private func countLine(listed:Int)->String {
        let world=worldShown && homeCountry != "US"
        return Self.countLine(shown:listed,of:world ? model.parks.count+model.catalog.count : model.parks.count,narrowed:narrowed)
    }
    /// "Estimate" is explained when a row on screen reads it: the parks as before, or abroad the first
    /// rows of the person's own country (already scored, being the first on screen; never the whole country).
    private func estimateShown(shown:[Park],own:CountryGroup?)->Bool {
        shown.contains { model.night($0).basis == .usual } || (own?.places.prefix(6).contains { model.night($0).basis == .usual } ?? false)
    }
    /// The eyebrow over the list: "63 places to look up", or "12 of 63 parks" while a filter narrows it.
    nonisolated static func countLine(shown:Int,of total:Int,narrowed:Bool)->String {
        narrowed ? String(localized:"\(shown) of \(total) parks") : String(localized:"\(total) places to look up")
    }
    struct RotorPark: Identifiable { let id: String; let label: String }
    /// One rotor stop for each park on screen that `label` names, in the order shown.
    private func rotor(_ spots:[Park],_ shown:[Park],_ label:(Park)->String?)->[RotorPark] {
        let sectioned = showsSavedSection
        let first=sectioned ? model.parks.filter { p in saved.contains { $0.parkID==p.id } } : []
        let rest=shown.filter { p in !(sectioned && saved.contains { $0.parkID==p.id }) }
        return (spots+first+rest).compactMap { park in label(park).map { RotorPark(id:park.id,label:$0) } }
    }
    /// The search's matches in the world catalogue, with a word when the list was cut short.
    @ViewBuilder private func foundSection(_ found:[Park],heading:Bool)->some View {
        if heading { Eyebrow(text:"Around the world") }
        LazyVStack(spacing:0) { ForEach(found) { p in worldRow(p) } }
        if foundCapped { Text("The first \(WorldBrowse.searchLimit) matches. Add a word to narrow them.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
    }
    /// From a US starting point: one row under the parks that opens the world by country.
    @ViewBuilder private func worldEntry(_ groups:[CountryGroup])->some View {
        let summary=WorldBrowse.summary(groups)
        Button { withAnimation(reduceMotion ? nil : NyxMotion.spring) { worldOpen.toggle() } } label:{
            HStack(alignment:.center,spacing:12) {
                Image(systemName:"globe").font(.title3).foregroundStyle(palette.accent).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4) {
                    Text("Around the world").font(.system(.title3,design:.serif)).foregroundStyle(palette.ink)
                    Text(summary).font(.caption).foregroundStyle(palette.muted)
                }.multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:8)
                Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted)
                    .rotationEffect(.degrees(worldOpen ? 90 : 0)).accessibilityHidden(true)
            }
            .padding(.vertical,14).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverEffect(.highlight).padding(.top,6)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("Around the world")
        .accessibilityValue(summary+", "+(worldOpen ? String(localized:"Expanded") : String(localized:"Collapsed")))
        .accessibilityAddTraits([.isButton,.isHeader])
        .accessibilityHint(worldOpen ? "Hides the places abroad." : "Shows parks and dark-sky places in other countries, by country.")
        .sensoryFeedback(.selection,trigger:worldOpen)
        if worldOpen { countries(groups) }
    }
    /// Countries as rows that open in place, and the open ones' places under them: one lazy stack,
    /// so only the rows on screen are built, and only they are scored.
    private func countries(_ groups:[CountryGroup])->some View {
        LazyVStack(spacing:0) {
            ForEach(WorldBrowse.rows(groups,open:openCountries)) { row in
                switch row {
                case .country(let group,let open): countryRow(group,open:open); Divider().overlay(palette.line)
                case .place(let place): worldRow(place)
                }
            }
        }
    }
    private func countryRow(_ group:CountryGroup,open:Bool)->some View {
        Button {
            withAnimation(reduceMotion ? nil : NyxMotion.spring) { if open { openCountries.remove(group.code) } else { openCountries.insert(group.code) } }
        } label:{
            HStack(alignment:.firstTextBaseline,spacing:12) {
                Text(group.name).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:8)
                Text(group.places.count,format:.number).font(.subheadline).monospacedDigit().foregroundStyle(palette.muted).fixedSize()
                Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted)
                    .rotationEffect(.degrees(open ? 90 : 0)).accessibilityHidden(true)
            }
            .padding(.vertical,14).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(group.name)
        .accessibilityValue(group.places.count.formatted()+", "+(open ? String(localized:"Expanded") : String(localized:"Collapsed")))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(open ? "Hides its places." : "Shows its parks and dark-sky places.")
        .sensoryFeedback(.selection,trigger:open)
    }
    /// A catalogue place (or, abroad, a US park in its country) in the world list: tonight's score only,
    /// no week strip (seven nights a row would be seven times the work while scrolling), and its
    /// forecast asked for while it is on screen.
    @ViewBuilder private func worldRow(_ place:Park,divided:Bool=true)->some View {
        link(place,week:!place.isCatalogPlace)
            .onAppear { onScreen.appeared(place,model:model) }
            .onDisappear { onScreen.disappeared(place.id) }
        if divided { Divider().overlay(palette.line) }
    }
    /// "Save another spot", under the spots already saved.
    private var addSpotRow: some View {
        Button { addingSpot=true } label:{
            Label("Save another spot",systemImage:"plus.circle").font(.subheadline.weight(.medium)).foregroundStyle(palette.accent)
                .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    /// Deletes a spot from the list's menu, after the person confirmed it.
    private func deleteSpot(_ spot:Park) {
        deletingSpot=nil
        guard !model.journalUnavailable else { saveFailed=true; return }
        do {
            try SavedSpots.delete(spot.id,in:context)
            if selection?.wrappedValue == spot.id { selection?.wrappedValue=nil }
        } catch { saveFailed=true }
    }
    @ViewBuilder private func link(_ park:Park,week:Bool=true)->some View {
        let row=ParkRow(night:model.night(park),closure:model.closure(park),week:week ? model.nights(park,from:model.tonight(park),count:7) : [],stepFree:stepFreeOnly)
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
    /// Long press, or a secondary click with a pointer: the menu every park row shares (`ParkRowMenu`),
    /// with deleting a spot, which this list confirms.
    private func rowMenu(_ park:Park)->some View {
        ParkRowMenu(park:park,failed:{ saveFailed=true },deleteSpot:{ deletingSpot=$0 })
    }
    private func focusSearchIfAsked() {
        guard commands?.takeSearch() == true else { return }
        Task { try? await Task.sleep(for:.milliseconds(250)); searchFocused=true }
    }
}

/// The bookmark's words, one place for the list's menu and a place's page: saving a park, following a
/// spot, saving a place abroad (a town or a reserve is not a park).
enum SaveWords {
    static func title(saved:Bool,spot:Bool,place:Bool)->LocalizedStringKey {
        if spot { return saved ? "Stop following this spot" : "Follow this spot" }
        if place { return saved ? "Remove from saved places" : "Save place" }
        return saved ? "Remove from saved parks" : "Save park"
    }
}

/// One country of the world list: its code, its name in the reader's language, its places by name.
nonisolated struct CountryGroup: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let places: [Park]
    var id: String { code }
}

/// The world list's order and shape, apart from the view so it can be tested.
nonisolated enum WorldBrowse {
    /// How many catalogue matches a search shows at once.
    static let searchLimit=50
    /// The country that leads: the starting city's, or a starting park's; before a starting point is
    /// chosen, this device's region (the example park is in the US for everyone). The US when unknown.
    static func homeCountry(startChosen:Bool,place:String?,park:String?,region:String?)->String {
        let code=startChosen ? (place ?? park) : region
        return code.map { $0.uppercased() }.flatMap { $0.count==2 ? $0 : nil } ?? "US"
    }
    /// Places by country: the home country first, then the others alphabetically by their name in the
    /// reader's language; within a country, by the name each row shows (`shownBefore`).
    static func groups(_ places:[Park],home:String?,name:(String)->String = StartingPlaces.countryName)->[CountryGroup] {
        let byCountry=Dictionary(grouping:places) { $0.countryCode.uppercased() }
        let groups=byCountry.map { code,list in
            // Each place's shown name worked out once, not once per comparison.
            let keyed=list.map { (place:$0,shown:$0.shortName) }
            return CountryGroup(code:code,name:code.isEmpty ? String(localized:"Elsewhere") : name(code),
                                places:keyed.sorted { shownBefore($0.place,$1.place,shown:($0.shown,$1.shown)) }.map(\.place))
        }
        let home=home?.uppercased()
        return groups.sorted { a,b in
            if (a.code==home) != (b.code==home) { return a.code==home }
            let order=a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.code<b.code : order == .orderedAscending
        }
    }
    /// The order a list shows places in: by the name its rows show (`shortName`, in the reader's language:
    /// "Bayerischer Wald" before "Rhön", whatever their full names), accents and case folded and numbers in
    /// order; then by the full name, then the id. The world list and the search's ties both use it.
    static func shownBefore(_ a:Park,_ b:Park)->Bool { shownBefore(a,b,shown:(a.shortName,b.shortName)) }
    private static func shownBefore(_ a:Park,_ b:Park,shown:(String,String))->Bool {
        let order=shown.0.localizedStandardCompare(shown.1)
        if order != .orderedSame { return order == .orderedAscending }
        let full=a.name.localizedStandardCompare(b.name)
        return full == .orderedSame ? a.id<b.id : full == .orderedAscending
    }
    /// The groups as shown: Dark Sky designated only when asked, the curated parks only when they are
    /// not listed above (`curated`), `hiding` the places listed elsewhere; empty countries dropped.
    static func narrowed(_ groups:[CountryGroup],darkOnly:Bool,curated:Bool,hiding:Set<String>)->[CountryGroup] {
        groups.compactMap { group in
            let places=group.places.filter { (curated || !$0.curated) && (!darkOnly || $0.darkSkyDesignated) && !hiding.contains($0.id) }
            return places.isEmpty ? nil : CountryGroup(code:group.code,name:group.name,places:places)
        }
    }
    /// One row of the world list: a country (open or not), or a place of an open country.
    enum Row: Identifiable, Hashable, Sendable {
        case country(CountryGroup,open:Bool)
        case place(Park)
        var id: String {
            switch self {
            case .country(let group,_): "country:"+group.code
            case .place(let place): place.id
            }
        }
    }
    /// Every country, and under each open one its places. A closed country adds no place rows, so
    /// nothing of it is built or scored.
    static func rows(_ groups:[CountryGroup],open:Set<String>)->[Row] {
        groups.flatMap { group in
            let isOpen=open.contains(group.code)
            return [Row.country(group,open:isOpen)]+(isOpen ? group.places.map(Row.place) : [])
        }
    }
    /// "3,359 parks and dark-sky places in 172 countries".
    static func summary(_ groups:[CountryGroup])->String {
        let places=groups.reduce(0) { $0+$1.places.count }
        return String(localized:"\(places) parks and dark-sky places in \(groups.count) countries")
    }
}

/// The catalogue rows on screen, in the order they appeared, and which of them have had their
/// forecasts asked for. A row is asked for once, when it first appears; never one that is not on
/// screen, so scrolling past a country costs only what was seen.
nonisolated struct OnScreen: Sendable {
    /// At most this many places in one call to the model (which asks by whole tiles in any case).
    static let batch=60
    private(set) var visible:[Park]=[]
    private(set) var requested:Set<String>=[]
    mutating func appeared(_ place:Park) { if !visible.contains(where:{ $0.id==place.id }) { visible.append(place) } }
    mutating func disappeared(_ id:String) { visible.removeAll { $0.id==id } }
    /// The rows on screen not yet asked for, oldest first, at most `limit`; marked as asked.
    mutating func takeUnrequested(limit:Int=OnScreen.batch)->[Park] {
        let fresh=Array(visible.filter { !requested.contains($0.id) }.prefix(limit))
        requested.formUnion(fresh.map(\.id))
        return fresh
    }
    /// Of a map's places (all on screen at once, so none "appears"), the catalogue places not yet
    /// asked for, in the map's order; marked as asked. Curated parks and spots have their own requests.
    mutating func takeUnrequested(from places:[Park])->[Park] {
        let fresh=places.filter { $0.isCatalogPlace && !requested.contains($0.id) }
        requested.formUnion(fresh.map(\.id))
        return fresh
    }
}

/// `OnScreen` for the list, held outside observation so rows coming and going never redraw it. Asks
/// the model once scrolling has settled for a moment (`settle`), not for every row that flies past.
@MainActor final class OnScreenForecasts {
    private var window=OnScreen()
    private var pending:Task<Void,Never>?
    static let settle=Duration.milliseconds(700)
    var visible:[Park] { window.visible }
    func appeared(_ place:Park,model:PlanModel) {
        window.appeared(place)
        pending?.cancel()
        pending=Task { [weak self] in
            try? await Task.sleep(for:Self.settle)
            guard !Task.isCancelled, let self else { return }
            let batch=self.window.takeUnrequested()
            if !batch.isEmpty { await model.refreshForecasts(for:batch) }
        }
    }
    func disappeared(_ id:String) { window.disappeared(id) }
    /// For a map: call once it has settled (`settle`) on an area. Asks for the catalogue places it
    /// draws that have not been asked for yet; the model asks by whole tiles within its budget.
    func shown(_ places:[Park],model:PlanModel) async {
        let batch=window.takeUnrequested(from:places)
        if !batch.isEmpty { await model.refreshForecasts(for:batch) }
    }
}

#Preview("Parks") { NavigationStack { ParksView() }.environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self],inMemory:true).preferredColorScheme(.dark) }
#Preview("Parks • AX5") { NavigationStack { ParksView() }.environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self],inMemory:true).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
#Preview("Parks • night vision") {
    NavigationStack { ParksView() }.environment(PlanModel()).modelContainer(for:[SavedPark.self,JournalEntry.self],inMemory:true)
        .environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark)
}
#Preview("World rows • a country open") {
    @Previewable @State var open:Set<String>=["ES"]
    let groups=WorldBrowse.groups(WorldPreview.places,home:"ES")
    ScrollView { LazyVStack(alignment:.leading,spacing:0) {
        ForEach(WorldBrowse.rows(groups,open:open)) { row in
            switch row {
            case .country(let group,let isOpen): Button(group.name) { if isOpen { open.remove(group.code) } else { open.insert(group.code) } }.frame(minHeight:44)
            case .place(let place): ParkRow(night:PlanModel().night(place))
            }
        }
    }.padding(24) }.background(.black).preferredColorScheme(.dark)
}
