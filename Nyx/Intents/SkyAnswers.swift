import Foundation

// The words of "When is it dark tonight?" and "What's up tonight?", one set for every device that
// answers them: the iPhone's and iPad's intents (TonightIntents.swift), Apple Watch's and Vision Pro's. Pure: the
// intents find the place, its night and its closure; these say them.

/// The dark window in words, apart from the intent so it can be tested.
nonisolated enum DarkWindowAnswer {
    /// "True darkness tonight at Joshua Tree: from 7:42 PM to 5:10 AM. Sunset is at 6:14 PM."
    /// Voice-only (iOS or visionOS 27, no screen in view) keeps the window alone. Times are the park's; when
    /// they are not this device's, the answer names the park's time zone.
    static func dialog(park: Park, sky: SkyConditions, closure: String?, voiceOnly: Bool, device: TimeZone = .current) -> String {
        var sentences: [String]=[]
        if sky.darkHours>0, let start=sky.darkStart, let end=sky.darkEnd {
            if voiceOnly {
                sentences=[String(localized:"Tonight at \(park.shortName): true darkness from \(park.time(start)) to \(park.time(end)).")]
            } else {
                sentences=[String(localized:"True darkness tonight at \(park.shortName): from \(park.time(start)) to \(park.time(end)).")]
                if let sunset=sky.sunset { sentences.append(String(localized:"Sunset is at \(park.time(sunset)).")) }
            }
            sentences.append(zoneNote(park:park,at:start,device:device))
        } else {
            sentences=[String(localized:"\(park.shortName) has no true darkness tonight at this latitude.")]
            if !voiceOnly {
                if let sunset=sky.sunset, let sunrise=sky.sunrise {
                    sentences.append(String(localized:"The sky stays in twilight from sunset at \(park.time(sunset)) to sunrise at \(park.time(sunrise))."))
                    sentences.append(zoneNote(park:park,at:sunset,device:device))
                } else if sky.state == .polarDay {
                    sentences.append(String(localized:"The Sun stays up all night."))
                }
            }
        }
        return ClosureLine.around(Sentences.join(sentences),park:park,closure:closure)
    }
    /// "Times in Pacific Time." only when the park's clock differs from this device's: the note every
    /// surface sets under park-local times, as a sentence.
    static func zoneNote(park: Park, at date: Date, device: TimeZone) -> String {
        park.timeZone.secondsFromGMT(for:date)==device.secondsFromGMT(for:date) ? "" : Sentences.end(String(localized:"Times in \(park.timeZoneName)"))
    }
}

// MARK: What's up

/// What's up in a few spoken sentences, apart from the intent so it can be tested.
nonisolated enum WhatsUpAnswer {
    static let limit=3
    static func dialog(_ whatsUp: WhatsUp, park: Park, closure: String?, voiceOnly: Bool, device: TimeZone = .current) -> String {
        let lines=whatsUp.items.prefix(limit).map { line($0,core:whatsUp.coreNight,park:park,voiceOnly:voiceOnly) }
        let lead=String(localized:"Tonight at \(park.shortName)")+"."
        let zone=DarkWindowAnswer.zoneNote(park:park,at:whatsUp.coreNight.highest,device:device)
        return ClosureLine.around(Sentences.join([lead]+lines+[zone]),park:park,closure:closure)
    }
    /// One item, briefly: the core's dark hours, a shower's rate, a planet's times. The panel's
    /// longer notes (the published rate, the Moon's share of the core's hours) stay in the app.
    static func line(_ item: WhatsUp.Item, core: SkyAlmanac.CoreNight, park: Park, voiceOnly: Bool) -> String {
        switch item.kind {
        case .core:
            if item.timed, let dark=core.dark { return String(localized:"Milky Way core: up in true darkness from \(park.time(dark.start)) to \(park.time(dark.end)).") }
            return item.value.map { Sentences.end("\(item.title): \($0)") } ?? item.spoken
        case .meteors:
            guard let note=item.note, let value=item.value else { return item.spoken }
            return String(localized:"\(item.title), \(note): \(value).")
        case .planet:
            guard voiceOnly, let note=item.note, let value=item.value else { return item.spoken }
            return String(localized:"\(item.title), \(note): \(value).")
        case .eclipse, .aurora, .pairing, .moon, .planetBest, .season, .gegenschein, .deepSky:
            return item.spoken
        }
    }
}

extension ClosureLine {
    /// Every other spoken answer about a place, as to closures: a park's closure first; at a place
    /// the Park Service does not run, a last sentence that says Nyx cannot know its closures
    /// (`ClosureLine.unknown`), so silence never reads as "nothing is closed".
    nonisolated static func around(_ body:String,park:Park,closure:String?)->String {
        first(Sentences.join([body,unknown(park) ?? ""]),closure:closure)
    }
}
