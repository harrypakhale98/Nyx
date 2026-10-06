import AppIntents
import CoreSpotlight
import Foundation

/// A national park, for Siri, Shortcuts and Spotlight. Indexed (iOS 18+), so Spotlight's
/// semantic search finds "dark sky park in Utah" and a tap opens the park through `OpenParkIntent`.
struct ParkEntity:IndexedEntity {
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"National park")
    static let defaultQuery=ParkQuery()
    let id:String
    let name:String
    var state:String=""
    var darkSky=false
    var displayRepresentation:DisplayRepresentation {
        DisplayRepresentation(title:"\(name)",subtitle:state.isEmpty ? nil : "\(state)",image:.init(systemName:darkSky ? "moon.stars" : "mountain.2"))
    }
    init(id:String,name:String) { self.id=id; self.name=name }
    init(_ park:Park) { id=park.id; name=park.shortName; state=park.state; darkSky=park.darkSkyDesignated }
    /// Shared with `SpotlightIndexer`'s items, so the entity and the item describe the park alike.
    var attributeSet:CSSearchableItemAttributeSet { Self.attributes(name:name,state:state,darkSky:darkSky) }
    static func attributes(name:String,state:String,darkSky:Bool)->CSSearchableItemAttributeSet {
        let attributes=CSSearchableItemAttributeSet(contentType:.text)
        attributes.title=name
        attributes.displayName=name
        attributes.contentDescription=String(localized:"Plan a dark-sky night at \(name), \(state).")
        attributes.keywords=["stars","stargazing","national park","night sky","Milky Way",name,state]+(darkSky ? ["dark sky park"] : [])
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
/// iOS 27 asks the app to rebuild its Spotlight entries (after a restore, or when the index is lost).
/// Nyx keeps its parks in the default index, with no protection class: they are public facts.
@available(iOS 27.0,*)
extension ParkQuery:IndexedEntityQuery {
    func reindexEntities(for identifiers:[String],indexDescription:CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer.index(ParkData.load().filter { identifiers.contains($0.id) })
    }
    func reindexAllEntities(indexDescription:CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer.index(ParkData.load())
    }
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
/// a cold launch may run the intent before any view is listening.
nonisolated enum ParkOpenRequest {
    static let key="parkOpenRequest"
    static let notification=Notification.Name("NyxParkOpenRequest")
    static func post(parkID:String,now:Date = .now,defaults:UserDefaults = .standard) {
        defaults.set(["park":parkID,"at":now.timeIntervalSince1970],forKey:key)
        NotificationCenter.default.post(name:notification,object:nil)
    }
    /// The pending park, once, if it was asked for within the last minute.
    static func take(now:Date = .now,defaults:UserDefaults = .standard)->String? {
        guard let request=defaults.dictionary(forKey:key) else { return nil }
        defaults.removeObject(forKey:key)
        guard let at=request["at"] as? Double,abs(now.timeIntervalSince1970-at)<60,let park=request["park"] as? String,!park.isEmpty else { return nil }
        return park
    }
}
struct DarknessIntent:AppIntent {
    static let title:LocalizedStringResource="Tonight's darkness score"
    static let description=IntentDescription("Find the on-device darkness estimate for a national park.")
    @Parameter(title:"Park") var park:ParkEntity
    static var parameterSummary:some ParameterSummary { Summary("Darkness at \(\.$park) tonight") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parks=try ParkData.load()
        guard let selected=parks.first(where:{$0.id==park.id}) else { return .result(dialog:"That park could not be found in the bundled library.") }
        let sky=AstronomyEngine().conditions(for:selected,on:selected.currentNight(at:.now))
        // Saved parks share their forecast with the widget; the app's own cache may be newer.
        let forecast=[SharedSettings.read()?.forecasts[selected.id],CacheDirectory.read(Forecast.self,name:"weather-\(selected.id)")]
            .compactMap { $0 }.max { $0.updated<$1.updated }
        let clouds=forecast?.mean(from:sky.cloudWindow.start,to:sky.cloudWindow.end)
        let score=ScoreEngine().score(sky:sky,bortle:selected.bortleEstimate,cloudCover:clouds)
        if sky.darkHours==0 { return .result(dialog:"No true darkness tonight at \(selected.shortName). The darkness score is \(score.value) out of 100.") }
        if clouds==nil { return .result(dialog:"\(selected.shortName): \(score.value) out of 100, \(score.band.label). Moon and darkness only. Clouds and park access are unknown.") }
        return .result(dialog:"\(selected.shortName): \(score.value) out of 100, \(score.band.label). Includes a cached cloud forecast. Confirm conditions and park access before traveling.")
    }
}
struct NyxShortcuts:AppShortcutsProvider {
    static var appShortcuts:[AppShortcut] {
        AppShortcut(intent:DarknessIntent(),phrases:["What is the darkness score at \(\.$park) in \(.applicationName)","Check tonight's sky at \(\.$park) with \(.applicationName)"],shortTitle:"Tonight's sky",systemImageName:"moon.stars")
        AppShortcut(intent:FindBestNightIntent(),phrases:["Find the best night at \(\.$park) with \(.applicationName)","When is the darkest night at \(\.$park) in \(.applicationName)","Find the best night for stars with \(.applicationName)"],shortTitle:"Best night",systemImageName:"calendar")
        AppShortcut(intent:StartFieldModeIntent(),phrases:["Start field mode at \(\.$park) in \(.applicationName)","I'm stargazing at \(\.$park) with \(.applicationName)"],shortTitle:"Field mode",systemImageName:"scope")
    }
}
