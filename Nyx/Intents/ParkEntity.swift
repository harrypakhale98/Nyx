import AppIntents
import CoreSpotlight
import Foundation

/// A national park, for Siri, Shortcuts, Spotlight, and the widgets' and controls' park choice.
/// Shared by the app and the widget extension. Indexed (iOS 18+), so Spotlight's semantic search
/// finds "dark sky park in Utah" and a tap opens the park through `OpenParkIntent`; its state,
/// Dark Sky designation and Bortle class are entity properties (iOS 26), so Shortcuts can filter
/// on them ("National parks where Dark Sky designation is International Dark Sky Park").
struct ParkEntity:IndexedEntity {
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"National park")
    static let defaultQuery=ParkQuery()
    let id:String
    let name:String
    var state:String=""
    var darkSky=false
    var bortle=0
    var displayRepresentation:DisplayRepresentation {
        DisplayRepresentation(title:"\(name)",subtitle:state.isEmpty ? nil : "\(state)",image:.init(systemName:darkSky ? "moon.stars" : "mountain.2"))
    }
    /// The state or states, also Spotlight's state field.
    @ComputedProperty(title:"State",indexingKey:\.stateOrProvince)
    var stateName:String { state }
    /// "International Dark Sky Park", or empty. Indexed as the item's theme: the designation is
    /// what the park's night is known for.
    @ComputedProperty(title:"Dark Sky designation",indexingKey:\.theme)
    var designation:String { darkSky ? String(localized:"International Dark Sky Park") : "" }
    /// The park's estimated Bortle class, 1 (darkest) to 9. No Spotlight field fits a 1–9 sky
    /// class (a custom key's initializer can fail, which a property's key may not), so Spotlight
    /// finds it as the keyword "Bortle 2"; Shortcuts filters the number.
    @ComputedProperty(title:"Bortle class")
    var bortleClass:Int { bortle }
    init(id:String,name:String) { self.id=id; self.name=name }
    init(_ park:Park) { id=park.id; name=park.shortName; state=park.state; darkSky=park.darkSkyDesignated; bortle=park.bortleEstimate }
    /// Shared with `SpotlightIndexer`'s items, so the entity and the item describe the park alike.
    var attributeSet:CSSearchableItemAttributeSet { Self.attributes(name:name,state:state,darkSky:darkSky,bortle:bortle) }
    static func attributes(name:String,state:String,darkSky:Bool,bortle:Int=0)->CSSearchableItemAttributeSet {
        let attributes=CSSearchableItemAttributeSet(contentType:.text)
        attributes.title=name
        attributes.displayName=name
        attributes.contentDescription=String(localized:"Plan a dark-sky night at \(name), \(state).")
        attributes.keywords=["stars","stargazing","national park","night sky","Milky Way",name,state]+(darkSky ? ["dark sky park"] : [])+(bortle>0 ? ["Bortle \(bortle)"] : [])
        return attributes
    }
}
struct ParkQuery:EntityStringQuery {
    func entities(for identifiers:[String]) async throws -> [ParkEntity] { try ParkData.load().filter{identifiers.contains($0.id)}.map(ParkEntity.init) }
    /// Saved parks first (the ones people ask about), then the rest by name.
    func suggestedEntities() async throws -> [ParkEntity] {
        let saved=Set(SharedSettings.read()?.parks.map(\.id) ?? [])
        return try ParkData.load().sorted { (saved.contains($0.id) ? 0 : 1, $0.shortName)<(saved.contains($1.id) ? 0 : 1, $1.shortName) }.map(ParkEntity.init)
    }
    func entities(matching string:String) async throws -> [ParkEntity] { try ParkData.load().filter{$0.matches(string)}.map(ParkEntity.init) }
}
/// Opens a park in Nyx: a Spotlight result, a snippet's "Open in Nyx", or Shortcuts.
struct OpenParkIntent:OpenIntent {
    static let title:LocalizedStringResource="Open park"
    static let description=IntentDescription("Opens a national park in Nyx: its darkness score, Moon, sky and closures.")
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
