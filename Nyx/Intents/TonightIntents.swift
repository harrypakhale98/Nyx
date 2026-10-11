import AppIntents
import Foundation

/// The park a spoken question is about when it names none: the night under way on the Lock Screen
/// (field mode or a followed night), else the starting park, as the journal action chooses.
enum IntentPark {
    static func resolve(_ entity: ParkEntity?, library: [Park], inProgress: String?, home: String?) throws -> Park {
        if let entity {
            guard let park=library.first(where:{ $0.id==entity.id }) else { throw NyxIntentError.parkNotFound }
            return park
        }
        for id in [inProgress, home, "jotr"].compactMap({ $0 }) { if let park=library.first(where:{ $0.id==id }) { return park } }
        guard let first=library.first else { throw NyxIntentError.parkNotFound }
        return first
    }
    /// From the device's own state: the activity running now, and the starting park.
    static func resolve(_ entity: ParkEntity?) throws -> Park {
        try resolve(entity, library:ParkData.load(), inProgress:FieldActivities.current?.attributes.parkID, home:UserDefaults.standard.string(forKey:"homePark"))
    }
}

// MARK: When is it dark

/// "When is it dark tonight?" True darkness, start to end, in the park's own time, or plainly that
/// there is none at this latitude. A closure is said first. Returns when true darkness begins
/// (sunset, or the evening, where there is none), as Find the best night does.
struct DarkTonightIntent: AppIntent {
    static let title: LocalizedStringResource="When true darkness falls tonight"
    static let description=IntentDescription("Says when true darkness begins and ends tonight at a national park, in the park's own time, worked out on this iPhone. Leave the park empty for your starting park.")
    @Parameter(title:"Park",description:"Leave empty for your starting park.") var park: ParkEntity?
    static var parameterSummary: some ParameterSummary { Summary("When true darkness falls at \(\.$park) tonight") }
    init() {}
    // The night under way is read from the app's Live Activities, on the main actor.
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let selected=try IntentPark.resolve(park)
        let now=Date.now
        let sky=AstronomyEngine().conditions(for:selected,on:selected.currentNight(at:now))
        var voiceOnly=false
        if #available(iOS 27.0,*) { voiceOnly=systemContext.isVoiceOnly }
        let closure=SharedSettings.read()?.closures[selected.id]
        let dialog=DarkWindowAnswer.dialog(park:selected,sky:sky,closure:closure,voiceOnly:voiceOnly)
        return .result(value:sky.darkStart ?? sky.sunset ?? sky.evening,dialog:IntentDialog(stringLiteral:dialog))
    }
}

/// The dark window in words, apart from the intent so it can be tested.
nonisolated enum DarkWindowAnswer {
    /// "True darkness tonight at Joshua Tree: from 7:42 PM to 5:10 AM. Sunset is at 6:14 PM."
    /// Voice-only (iOS 27, no screen in view) keeps the window alone. Times are the park's; when
    /// they are not this device's, the answer names the park's time zone.
    static func dialog(park: Park, sky: SkyConditions, closure: String?, voiceOnly: Bool, device: TimeZone = .current) -> String {
        var body: String
        if sky.darkHours>0, let start=sky.darkStart, let end=sky.darkEnd {
            if voiceOnly {
                body=String(localized:"Tonight at \(park.shortName): true darkness from \(park.time(start)) to \(park.time(end)).")
            } else {
                body=String(localized:"True darkness tonight at \(park.shortName): from \(park.time(start)) to \(park.time(end)).")
                if let sunset=sky.sunset { body+=" "+String(localized:"Sunset is at \(park.time(sunset)).") }
            }
            body+=zoneNote(park:park,at:start,device:device)
        } else {
            body=String(localized:"\(park.shortName) has no true darkness tonight at this latitude.")
            if !voiceOnly {
                if let sunset=sky.sunset, let sunrise=sky.sunrise {
                    body+=" "+String(localized:"The sky stays in twilight from sunset at \(park.time(sunset)) to sunrise at \(park.time(sunrise)).")
                    body+=zoneNote(park:park,at:sunset,device:device)
                } else if sky.state == .polarDay {
                    body+=" "+String(localized:"The Sun stays up all night.")
                }
            }
        }
        return DarknessAnswer.closureFirst(body,closure:closure)
    }
    /// " Times are Pacific Time." only when the park's clock differs from this device's.
    static func zoneNote(park: Park, at date: Date, device: TimeZone) -> String {
        park.timeZone.secondsFromGMT(for:date)==device.secondsFromGMT(for:date) ? "" : " "+String(localized:"Times are \(park.timeZoneName).")
    }
}

// MARK: What's up

/// "What's up tonight?" The first three things in What's up (an eclipse or a shower first, then
/// the Milky Way core and the brightest planets), said briefly with park-local times.
struct WhatsUpTonightIntent: AppIntent {
    static let title: LocalizedStringResource="What's up tonight"
    static let description=IntentDescription("Names what is worth seeing tonight at a national park: the Milky Way core, bright planets, a meteor shower or an eclipse, with times in the park's own time. Leave the park empty for your starting park.")
    @Parameter(title:"Park",description:"Leave empty for your starting park.") var park: ParkEntity?
    static var parameterSummary: some ParameterSummary { Summary("What's up tonight at \(\.$park)") }
    init() {}
    // The night under way is read from the app's Live Activities, on the main actor.
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let selected=try IntentPark.resolve(park)
        let now=Date.now
        let sky=AstronomyEngine().conditions(for:selected,on:selected.currentNight(at:now))
        let whatsUp=WhatsUp(park:selected,sky:sky,isTonight:true)
        var voiceOnly=false
        if #available(iOS 27.0,*) { voiceOnly=systemContext.isVoiceOnly }
        let closure=SharedSettings.read()?.closures[selected.id]
        let dialog=WhatsUpAnswer.dialog(whatsUp,park:selected,closure:closure,voiceOnly:voiceOnly)
        return .result(dialog:IntentDialog(stringLiteral:dialog))
    }
}

/// What's up in a few spoken sentences, apart from the intent so it can be tested.
nonisolated enum WhatsUpAnswer {
    static let limit=3
    static func dialog(_ whatsUp: WhatsUp, park: Park, closure: String?, voiceOnly: Bool, device: TimeZone = .current) -> String {
        let lines=whatsUp.items.prefix(limit).map { line($0,core:whatsUp.coreNight,park:park,voiceOnly:voiceOnly) }
        let lead=String(localized:"Tonight at \(park.shortName)")+"."
        let zone=DarkWindowAnswer.zoneNote(park:park,at:whatsUp.coreNight.highest,device:device)
        return DarknessAnswer.closureFirst(([lead]+lines).joined(separator:" ")+zone,closure:closure)
    }
    /// One item, briefly: the core's dark hours, a shower's rate, a planet's times. The panel's
    /// longer notes (the published rate, the Moon's share of the core's hours) stay in the app.
    static func line(_ item: WhatsUp.Item, core: SkyAlmanac.CoreNight, park: Park, voiceOnly: Bool) -> String {
        switch item.kind {
        case .core:
            if item.timed, let dark=core.dark { return String(localized:"Milky Way core: up in true darkness from \(park.time(dark.start)) to \(park.time(dark.end)).") }
            return item.value.map { DarknessAnswer.sentence("\(item.title): \($0)") } ?? item.spoken
        case .meteors:
            guard let note=item.note, let value=item.value else { return item.spoken }
            return String(localized:"\(item.title), \(note): \(value).")
        case .planet:
            guard voiceOnly, let note=item.note, let value=item.value else { return item.spoken }
            return String(localized:"\(item.title), \(note): \(value).")
        case .eclipse:
            return item.spoken
        }
    }
}
