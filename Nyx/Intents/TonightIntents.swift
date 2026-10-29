import AppIntents
import Foundation

/// The park a spoken question is about when it names none: the night under way on the Lock Screen
/// (field mode or a followed night), else the starting park, as the journal action chooses.
enum IntentPark {
    /// `place` finds what the library lacks by id: an unfollowed world catalogue place (`ParkLibrary.place`),
    /// chosen from a search or the starting park abroad.
    static func resolve(_ entity: ParkEntity?, library: [Park], inProgress: String?, home: String?, place: (String) -> Park? = { _ in nil }) throws -> Park {
        func find(_ id: String) -> Park? { library.first(where:{ $0.id==id }) ?? place(id) }
        if let entity {
            guard let park=find(entity.id) else { throw NyxIntentError.parkNotFound }
            return park
        }
        for id in [inProgress, home, Park.defaultID].compactMap({ $0 }) { if let park=find(id) { return park } }
        guard let first=library.first else { throw NyxIntentError.parkNotFound }
        return first
    }
    /// From the device's own state: the activity running now, and the starting park.
    static func resolve(_ entity: ParkEntity?, snapshot: SavedSkySnapshot?=SharedSettings.read()) throws -> Park {
        try resolve(entity, library:ParkLibrary.places(snapshot:snapshot), inProgress:FieldActivities.current?.attributes.parkID, home:UserDefaults.standard.string(forKey:"homePark"),
                    place:{ ParkLibrary.place($0,snapshot:snapshot) })
    }
}

// MARK: When is it dark

/// "When is it dark tonight?" True darkness, start to end, in the park's own time, or plainly that
/// there is none at this latitude. A closure is said first. Returns when true darkness begins
/// (sunset, or the evening, where there is none), as Find the best night does.
struct DarkTonightIntent: AppIntent {
    static let title: LocalizedStringResource="When true darkness falls tonight"
    static let description=IntentDescription("Says when true darkness begins and ends tonight at a park or dark-sky place, in the place's own time, worked out on this device. Leave the park empty for your starting park.")
    @Parameter(title:"Park",description:"Leave empty for your starting park.") var park: ParkEntity?
    static var parameterSummary: some ParameterSummary { Summary("When true darkness falls at \(\.$park) tonight") }
    init() {}
    // The night under way is read from the app's Live Activities, on the main actor.
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let shared=await SharedSettings.load()
        let selected=try IntentPark.resolve(park,snapshot:shared)
        let now=Date.now
        let sky=AstronomyEngine().conditions(for:selected,on:selected.currentNight(at:now))
        var voiceOnly=false
        if #available(iOS 27.0,*) { voiceOnly=systemContext.isVoiceOnly }
        let closure=IntentClosure.closure(selected,shared:shared)
        let dialog=DarkWindowAnswer.dialog(park:selected,sky:sky,closure:closure,voiceOnly:voiceOnly)
        return .result(value:sky.darkStart ?? sky.sunset ?? sky.evening,dialog:IntentDialog(stringLiteral:dialog))
    }
}

// MARK: What's up

/// "What's up tonight?" The first three things in What's up (an eclipse or a shower first, then
/// the Milky Way core and the brightest planets), said briefly with park-local times.
struct WhatsUpTonightIntent: AppIntent {
    static let title: LocalizedStringResource="What's up tonight"
    static let description=IntentDescription("Names what is worth seeing tonight at a park or dark-sky place: the Milky Way core, bright planets, a meteor shower or an eclipse, with times in the park's own time. Leave the park empty for your starting park.")
    @Parameter(title:"Park",description:"Leave empty for your starting park.") var park: ParkEntity?
    static var parameterSummary: some ParameterSummary { Summary("What's up tonight at \(\.$park)") }
    init() {}
    // The night under way is read from the app's Live Activities, on the main actor.
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let shared=await SharedSettings.load()
        let selected=try IntentPark.resolve(park,snapshot:shared)
        let now=Date.now
        let sky=AstronomyEngine().conditions(for:selected,on:selected.currentNight(at:now))
        // NOAA's aurora forecast as the app last kept it (no request from Siri), unless switched off.
        let outlook=NetworkService.aurora.isOn() ? await AuroraService().cached() : nil
        let whatsUp=WhatsUp(park:selected,sky:sky,isTonight:true,aurora:AuroraForecast.item(outlook,park:selected,sky:sky,now:now))
        var voiceOnly=false
        if #available(iOS 27.0,*) { voiceOnly=systemContext.isVoiceOnly }
        let closure=IntentClosure.closure(selected,shared:shared)
        let dialog=WhatsUpAnswer.dialog(whatsUp,park:selected,closure:closure,voiceOnly:voiceOnly)
        return .result(dialog:IntentDialog(stringLiteral:dialog))
    }
}
