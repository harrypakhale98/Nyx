import AppIntents
import Foundation
import WidgetKit

struct ParkEntity:AppEntity {
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"National park")
    static let defaultQuery=ParkQuery()
    let id:String
    let name:String
    var displayRepresentation:DisplayRepresentation { DisplayRepresentation(title:"\(name)") }
}
struct ParkQuery:EntityStringQuery {
    func entities(for identifiers:[String]) async throws -> [ParkEntity] { try ParkData.load().filter{identifiers.contains($0.id)}.map{ParkEntity(id:$0.id,name:$0.shortName)} }
    func suggestedEntities() async throws -> [ParkEntity] { try ParkData.load().map{ParkEntity(id:$0.id,name:$0.shortName)} }
    func entities(matching string:String) async throws -> [ParkEntity] { try ParkData.load().filter{$0.matches(string)}.map{ParkEntity(id:$0.id,name:$0.shortName)} }
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
        let forecast=SharedSettings.read()?.forecasts[selected.id]
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
    }
}
struct NightVisionIntent:SetValueIntent {
    static let title:LocalizedStringResource="Set night vision"
    @Parameter(title:"Enabled") var value:Bool
    init() {}
    init(value:Bool) { self.value=value }
    func perform() async throws -> some IntentResult {
        SharedSettings.defaults.set(value,forKey:"nightVision")
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}
