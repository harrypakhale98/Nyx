import AppIntents
import CoreSpotlight
import Foundation

/// A place: a curated park, a world catalogue place or a saved spot, for Siri, Shortcuts, Spotlight,
/// and the widgets' and controls' park choice. Shared by the app and the widget extension. Indexed (iOS 18+), so Spotlight's semantic search
/// finds "dark sky park in Utah" and a tap opens the park through `OpenParkIntent`; its region,
/// Dark Sky designation and Bortle class are entity properties (iOS 26), so Shortcuts can filter
/// on them ("Places where Dark Sky designation is International Dark Sky Park").
struct ParkEntity:IndexedEntity {
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"Place")
    static let defaultQuery=ParkQuery()
    let id:String
    let name:String
    var state:String=""
    var darkSky=false
    /// The DarkSky designation's own name (`Park.designationName`): "International Dark Sky Reserve",
    /// "Urban Night Sky Place". Empty without one.
    var designationName=""
    var bortle=0
    /// A place from the world catalogue (`wd:`, G4): its ISO country code, so Siri and Spotlight can
    /// say where it is ("Catalonia, Spain"). Empty for the curated parks and saved spots.
    var country:String=""
    /// Whether "national park" describes it (a Dark Sky community or reserve abroad is not one).
    var nationalPark=true
    /// A catalogue place's English name when the app shows it in another language, so Spotlight finds either.
    var englishName=""
    /// A spot the person saved (`pin:`), rather than a catalogue park.
    var isSpot:Bool { id.hasPrefix(ParkLibrary.spotPrefix) }
    var displayRepresentation:DisplayRepresentation {
        if isSpot { return DisplayRepresentation(title:"\(name)",subtitle:"Your spot",image:.init(systemName:"mappin.and.ellipse")) }
        let place=Self.locality(state:state,country:country)
        return DisplayRepresentation(title:"\(name)",subtitle:place.isEmpty ? nil : "\(place)",image:.init(systemName:darkSky ? "moon.stars" : "mountain.2"))
    }
    /// "CA" for a curated park, as before; "Catalonia, Spain" for a place abroad, the country in the reader's language.
    static func locality(state:String,country:String)->String {
        guard !country.isEmpty else { return state }
        let name=Locale.current.localizedString(forRegionCode:country) ?? country
        let region=state.replacingOccurrences(of:",",with:" · ")
        return region.isEmpty || region==name ? name : "\(region), \(name)"
    }
    /// The state or states, or a region abroad, also Spotlight's state-or-province field.
    @ComputedProperty(title:"Region",indexingKey:\.stateOrProvince)
    var stateName:String { state }
    /// "International Dark Sky Park", "Urban Night Sky Place" and the rest, or empty. Indexed as the
    /// item's theme: the designation is what the place's night is known for.
    @ComputedProperty(title:"Dark Sky designation",indexingKey:\.theme)
    var designation:String { designationName.isEmpty && darkSky ? String(localized:"International Dark Sky Park") : designationName }
    /// The park's estimated Bortle class, 1 (darkest) to 9. No Spotlight field fits a 1–9 sky
    /// class (a custom key's initializer can fail, which a property's key may not), so Spotlight
    /// finds it as the keyword "Bortle 2"; Shortcuts filters the number.
    @ComputedProperty(title:"Bortle class")
    var bortleClass:Int { bortle }
    init(id:String,name:String) { self.id=id; self.name=name }
    init(_ park:Park) {
        id=park.id; name=park.shortName; state=park.region; darkSky=park.darkSkyDesignated; bortle=park.bortleEstimate
        designationName=park.designationName ?? ""
        if park.isCatalogPlace { country=park.countryCode; nationalPark=park.kind == .nationalPark; englishName=park.englishName.map(Park.shortened) ?? "" }
    }
    /// Shared with `SpotlightIndexer`'s items, so the entity and the item describe the park alike.
    var attributeSet:CSSearchableItemAttributeSet { Self.attributes(name:name,state:state,darkSky:darkSky,bortle:bortle,country:country,nationalPark:nationalPark,englishName:englishName) }
    static func attributes(name:String,state:String,darkSky:Bool,bortle:Int=0,country:String="",nationalPark:Bool=true,englishName:String="")->CSSearchableItemAttributeSet {
        let attributes=CSSearchableItemAttributeSet(contentType:.text)
        let place=locality(state:state,country:country)
        attributes.title=name
        attributes.displayName=name
        attributes.contentDescription=String(localized:"Plan a dark-sky night at \(name), \(place).")
        let countryName=country.isEmpty ? [] : [Locale.current.localizedString(forRegionCode:country) ?? country]
        // The English words stay beside the reader's own, so a search in either finds the place.
        let english:[String]=["stars","stargazing"]+(nationalPark ? ["national park"] : [])+["night sky","Milky Way"]+(darkSky ? ["dark sky park"] : [])
        var local:[String]=[String(localized:"stars"),String(localized:"stargazing")]
        if nationalPark { local.append(String(localized:"national park")) }
        local+=[String(localized:"night sky"),String(localized:"Milky Way")]
        if darkSky { local.append(String(localized:"dark sky park")) }
        var words:[String]=[]
        for word in english+local+[name,englishName,state]+countryName where !word.isEmpty && !words.contains(word) { words.append(word) }
        attributes.keywords=words+(bortle>0 ? ["Bortle \(bortle)"] : [])
        return attributes
    }
}
struct ParkQuery:EntityStringQuery {
    /// Parks, followed places and any world catalogue place by its `wd:` id, in the order asked.
    func entities(for identifiers:[String]) async throws -> [ParkEntity] {
        let snapshot=SharedSettings.read(), library=try ParkLibrary.places(snapshot:snapshot)
        var seen=Set<String>()
        return identifiers.filter { seen.insert($0).inserted }
            .compactMap { id in
                if let place=library.first(where: { $0.id==id }) ?? ParkLibrary.place(id,snapshot:snapshot) { return ParkEntity(place) }
                // A spot or place abroad no longer followed stays the widget's or control's setting, with no
                // name, so it can say the place is no longer saved instead of quietly showing another one.
                return Self.unsavedPlace(id) ? ParkEntity(id:id,name:"") : nil
            }
    }
    /// A well-formed spot or catalogue id (`pin:…`, `wd:Q…`) that no list knows any more.
    static func unsavedPlace(_ id:String)->Bool {
        (id.hasPrefix("pin:") || id.hasPrefix("wd:Q")) && id.count<=64 && !id.contains(where: { $0.isWhitespace || $0=="/" })
    }
    /// Saved spots first, then followed places abroad and saved parks (the ones people ask about), then
    /// the rest of the 63 by name. Never the whole world: a list of 3,400 helps no one choose.
    func suggestedEntities() async throws -> [ParkEntity] { try ParkLibrary.suggested().map(ParkEntity.init) }
    /// The parks and followed places that match, then the world catalogue's best matches (`ParkLibrary.search`).
    func entities(matching string:String) async throws -> [ParkEntity] {
        let known=try ParkLibrary.places().filter { $0.matches(string) }
        let ids=Set(known.map(\.id))
        return (known+ParkLibrary.search(string).filter { !ids.contains($0.id) }).map(ParkEntity.init)
    }
}
/// The places Siri, Shortcuts and the widgets can name: the bundled parks, then the places the person
/// follows that are not among them (saved spots, and world catalogue places), as the app last wrote
/// them to the App Group's snapshot (`SavedSkySnapshot.parks` carries each one whole). Curated ids
/// resolve exactly as before; a place no longer followed leaves the snapshot, and these lists, at the
/// app's next update. Any catalogue place resolves by its `wd:` id and is found by search, in the app
/// (which bundles `catalog.json`); the widget extension bundles no catalogue and knows only the followed ones.
nonisolated enum ParkLibrary {
    static let spotPrefix="pin:"
    /// The followed spots in a snapshot, in its order.
    static func spots(in snapshot:SavedSkySnapshot?)->[Park] { (snapshot?.parks ?? []).filter { $0.id.hasPrefix(spotPrefix) } }
    /// The followed places that are not bundled parks: spots first, then catalogue places, each in the snapshot's order.
    static func followed(in snapshot:SavedSkySnapshot?)->[Park] {
        spots(in:snapshot)+(snapshot?.parks ?? []).filter(\.isCatalogPlace)
    }
    static func places(snapshot:SavedSkySnapshot?=SharedSettings.read(),bundle:Bundle = .main) throws -> [Park] {
        let parks=try ParkData.load(bundle:bundle)
        let known=Set(parks.map(\.id))
        return parks+followed(in:snapshot).filter { !known.contains($0.id) }
    }
    /// One place by id: a park, a followed place, or (in the app) any world catalogue place.
    static func place(_ id:String,snapshot:SavedSkySnapshot?=SharedSettings.read()) -> Park? {
        if id.hasPrefix(spotPrefix) { return spots(in:snapshot).first { $0.id==id } }
        if id.hasPrefix(Park.catalogPrefix) { return snapshot?.parks.first { $0.id==id } ?? catalog().first { $0.id==id } }
        return (try? ParkData.load())?.first { $0.id==id }
    }
    /// Spots first, then followed places abroad, then saved parks, then every other park by name: the
    /// order a park choice offers them.
    static func suggested(snapshot:SavedSkySnapshot?=SharedSettings.read(),bundle:Bundle = .main) throws -> [Park] {
        let saved=Set(snapshot?.parks.map(\.id) ?? [])
        let parks=try ParkData.load(bundle:bundle).sorted { (saved.contains($0.id) ? 0 : 1, $0.shortName)<(saved.contains($1.id) ? 0 : 1, $1.shortName) }
        let known=Set(parks.map(\.id))
        return followed(in:snapshot).filter { !known.contains($0.id) }+parks
    }
    /// The world catalogue in this bundle (`CatalogData`, decoded once per process and shared with the
    /// app's model); empty where it is not bundled (the widget extension).
    static func catalog(bundle:Bundle = .main)->[Park] { (try? CatalogData.load(bundle:bundle)) ?? [] }
    /// The catalogue places whose name, region or country matches, folded as the park list folds it
    /// ("Albanya" finds Albanyà): the whole name first, then a name or word that begins with it, then
    /// the rest; by name within each. At most `limit`.
    static func search(_ text:String,limit:Int=25,bundle:Bundle = .main)->[Park] {
        let needle=Park.folded(text)
        guard !needle.isEmpty, limit>0 else { return [] }
        var countries:[String:String]=[:]
        func country(_ code:String)->String {
            if let kept=countries[code] { return kept }
            let folded=Park.folded(Locale.current.localizedString(forRegionCode:code) ?? code)
            countries[code]=folded
            return folded
        }
        let ranked:[(Park,Int)]=catalog(bundle:bundle).compactMap { place in
            // Local and English names rank alike (a German "Eifel" or "Nationalpark Eifel" is found by either).
            let names=place.searchNames.map(Park.folded)
            if names.contains(needle) { return (place,0) }
            if names.contains(where: { $0.hasPrefix(needle) }) { return (place,1) }
            if names.contains(where: { $0.contains(" "+needle) }) { return (place,2) }
            if place.matches(folded:needle) || country(place.countryCode).contains(needle) { return (place,3) }
            return nil
        }
        return ranked.sorted { ($0.1,$0.0.name,$0.0.id)<($1.1,$1.0.name,$1.0.id) }.prefix(limit).map(\.0)
    }
}
/// Opens a park in Nyx: a Spotlight result, a snippet's "Open in Nyx", or Shortcuts.
struct OpenParkIntent:OpenIntent {
    static let title:LocalizedStringResource="Open park"
    static let description=IntentDescription("Opens a park or dark-sky place in Nyx: its darkness score, Moon and sky, and closures where Nyx can check them.")
    @Parameter(title:"Park") var target:ParkEntity
    init() {}
    init(target:ParkEntity) { self.target=target }
    func perform() async throws -> some IntentResult {
        ParkOpenRequest.post(parkID:target.id)
        return .result()
    }
}
/// A park to open, handed from an intent to the app's root view. Stored as well as posted, because
/// a cold launch may run the intent before any view is listening; stored in the App Group's
/// defaults, as `FieldModeRequest` is, so it reaches the app from whichever process ran the intent.
nonisolated enum ParkOpenRequest {
    static let key="parkOpenRequest"
    static let notification=Notification.Name("NyxParkOpenRequest")
    /// `parkID` nil asks for the Tonight tab.
    static func post(parkID:String?,now:Date = .now,defaults:UserDefaults = SharedSettings.defaults) {
        defaults.set(["park":parkID ?? "","at":now.timeIntervalSince1970],forKey:key)
        NotificationCenter.default.post(name:notification,object:nil)
    }
    /// The pending request, once, if it was made within the last minute. `parkID` is nil for Tonight.
    struct Pending:Equatable { let parkID:String? }
    static func take(now:Date = .now,defaults:UserDefaults = SharedSettings.defaults)->Pending? {
        guard let request=defaults.dictionary(forKey:key) else { return nil }
        defaults.removeObject(forKey:key)
        guard let at=request["at"] as? Double,abs(now.timeIntervalSince1970-at)<60 else { return nil }
        let park=request["park"] as? String
        return Pending(parkID:park?.isEmpty == false ? park : nil)
    }
}

// MARK: Widget and control configuration

/// The Tonight's sky widget's one setting: a park to follow, or none for the darkest of the saved
/// parks tonight (the behaviour before the setting existed, so widgets already placed keep it).
struct TonightWidgetIntent:WidgetConfigurationIntent {
    static let title:LocalizedStringResource="Tonight's sky"
    static let description=IntentDescription("Shows one park's night, or the darkest of your saved parks. Saved parks carry their cloud forecast.")
    @Parameter(title:"Park",description:"Leave empty for the darkest of your saved parks tonight.") var park:ParkEntity?
    init() {}
    init(park:ParkEntity?) { self.park=park }
}
/// The Moon widget's setting: whose rise and set times to show. Empty: the first saved park, and
/// with none saved, the phase alone (the same everywhere).
struct MoonWidgetIntent:WidgetConfigurationIntent {
    static let title:LocalizedStringResource="The Moon"
    static let description=IntentDescription("Tonight's Moon: its phase, how much is lit, and when it rises or sets at a park.")
    @Parameter(title:"Park",description:"Leave empty for your first saved park.") var park:ParkEntity?
    init() {}
    init(park:ParkEntity?) { self.park=park }
}
/// The Tonight control's setting, as the widget's.
struct TonightControlIntent:ControlConfigurationIntent {
    static let title:LocalizedStringResource="Tonight's score"
    @Parameter(title:"Park",description:"Leave empty for the darkest of your saved parks tonight.") var park:ParkEntity?
    init() {}
    init(park:ParkEntity?) { self.park=park }
}
/// The Tonight control's tap: opens the park it shows, or Nyx's Tonight tab before any park is saved.
struct OpenTonightParkIntent:AppIntent {
    static let title:LocalizedStringResource="Open tonight's park"
    static let isDiscoverable=false
    static let supportedModes:IntentModes = .foreground
    @Parameter(title:"Park") var parkID:String?
    init() {}
    init(parkID:String?) { self.parkID=parkID }
    func perform() async throws -> some IntentResult {
        ParkOpenRequest.post(parkID:parkID?.isEmpty == false ? parkID : nil)
        return .result()
    }
}
