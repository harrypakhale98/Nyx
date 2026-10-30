import Foundation
import Testing
@testable import Nyx

/// One voice on every device: Siri's tonight answer (`TonightAnswer`) built once for the iPhone,
/// the watch and Vision Pro; one credits list whose licences no device shortens; one table of
/// network switches whose keys never move; and the Moon said by the same rule everywhere.
struct OneVoiceTests {
    private let now = Date(timeIntervalSince1970: 1_796_158_800)
    private static let spot = Place(spotID: "pin:00000000-0000-4000-8000-0000000000cd", name: "Pullout off Pinto Basin Road", latitude: 33.92, longitude: -115.93,
                                    timeZoneID: "America/Los_Angeles", countryCode: "US", region: "California")
    private func tonight(_ park: Park, forecast: Forecast? = nil, detail: ForecastDetail? = nil, climate: CloudClimate = .shared) -> Night {
        NightPlanner.night(park: park, sky: AstronomyEngine().conditions(for: park, on: park.currentNight(at: now)), forecast: forecast, detail: detail, now: now, climate: climate)
    }

    // MARK: Siri

    /// A closure first, then the score, then what smoke and closures leave unknown, in that order.
    @Test func closureComesFirstAndUnknownsLast() throws {
        let jotr = try park("jotr")
        let night = tonight(jotr)
        let smokeOff = String(localized: "Smoke and haze are off in Your privacy, so smoke is not counted.")
        let alertsOff = String(localized: "Park alerts are off in Your privacy, so closures are not checked.")
        let inputs = ScoreInputs(smokeOn: false, alertsOn: false)
        let open = DarknessAnswer.dialog(night, closure: nil, inputs: inputs, voiceOnly: false)
        let body = TonightAnswer(night: night).dialog()
        #expect(open == Sentences.join([body, smokeOff, alertsOff]))
        // With a closure known, it leads and nothing claims closures were not checked.
        let closed = DarknessAnswer.dialog(night, closure: "Keys View Road closed at night", inputs: inputs, voiceOnly: false)
        #expect(closed == Sentences.join([String(localized: "Closure alert: Keys View Road closed at night")+".", body, smokeOff]))
        #expect(!closed.contains(alertsOff))
    }
    /// The iPhone now says smoke is not counted, as Vision Pro did: off in Your privacy, or no
    /// forecast here yet; never when the smoke forecast counts.
    @Test func iPhoneSaysWhenSmokeIsNotCounted() throws {
        let jotr = try park("jotr")
        let off = DarknessAnswer(park: jotr, forecast: nil, detail: nil, inputs: ScoreInputs(smokeOn: false, alerts: ParkAlertsCache(updated: now, alerts: [jotr.nps ?? "": []])), now: now)
        #expect(off.dialog.hasSuffix(String(localized: "Smoke and haze are off in Your privacy, so smoke is not counted.")))
        let notYet = DarknessAnswer(park: jotr, forecast: nil, detail: nil, inputs: ScoreInputs(alerts: ParkAlertsCache(updated: now, alerts: [jotr.nps ?? "": []])), now: now)
        #expect(notYet.dialog.hasSuffix(String(localized: "No smoke forecast on this device yet, so smoke is not counted.")))
        // A smoke forecast that covers the night counts, and says nothing.
        let first = (floor(now.timeIntervalSince1970/3600)-24)*3600
        let hours = (0..<(4*24)).map { first+Double($0)*3600 }
        let air = HourlySeries(updated: now, times: hours, values: ["aerosol_optical_depth": hours.map { _ in 0.05 }])
        let counted = DarknessAnswer(park: jotr, forecast: nil, detail: ForecastDetail(air: air), inputs: ScoreInputs(alerts: ParkAlertsCache(updated: now, alerts: [jotr.nps ?? "": []])), now: now)
        #expect(!counted.dialog.contains("smoke is not counted"))
    }
    /// A place the Park Service does not run says Nyx cannot know its closures, full and voice-only;
    /// a national park whose closures were checked says nothing of the kind.
    @Test func placesOutsideTheParkServiceSayClosuresAreUnknown() throws {
        let abroad = try #require(ParkLibrary.catalog().first)
        for (place, line) in [(abroad, String(localized: "Nyx can't check closures here. Check the park's own site before you go.")),
                              (Self.spot, String(localized: "Nyx has no alerts for this place. Check access, local rules and closures before you go."))] {
            #expect(ClosureLine.unknown(place) == line)
            for voiceOnly in [false, true] { #expect(TonightAnswer(night: tonight(place)).dialog(voiceOnly: voiceOnly).hasSuffix(line)) }
        }
        let jotr = try park("jotr")
        #expect(ClosureLine.unknown(jotr) == nil)
        let checked = ScoreInputs(smokeKnown: [jotr.id], alerts: ParkAlertsCache(updated: now, alerts: [jotr.nps ?? "": []]))
        #expect(checked.uncheckedNote(jotr, closure: nil) == nil)
        #expect(ScoreInputs().uncheckedNote(jotr, closure: nil) == String(localized: "Access not checked. Confirm closures with the park."))
        #expect(ScoreInputs().uncheckedNote(Self.spot, closure: nil) == nil)
    }
    /// Voice-only keeps one caveat: the clouds without a forecast, else smoke; the closures line stays.
    @Test func voiceOnlyKeepsOneCaveat() throws {
        let jotr = try park("jotr")
        let night = tonight(jotr)
        try #require(!night.score.hasForecast && night.sky.darkHours > 0)
        let smokeOff = String(localized: "Smoke and haze are off in Your privacy, so smoke is not counted.")
        let alertsOff = String(localized: "Park alerts are off in Your privacy, so closures are not checked.")
        let voice = TonightAnswer(night: night, smokeNote: smokeOff, unchecked: alertsOff).dialog(voiceOnly: true)
        #expect(!voice.contains(smokeOff) && voice.hasSuffix(alertsOff) && !voice.contains("Confirm conditions"))
        // With a full forecast there is no cloud caveat, so smoke is the one said.
        let first = (floor(now.timeIntervalSince1970/3600)-24)*3600
        let hours = (0..<(4*24)).map { first+Double($0)*3600 }
        let clear = tonight(jotr, forecast: Forecast(updated: now, times: hours, clouds: hours.map { _ in 0 }))
        try #require(clear.score.hasForecast)
        #expect(TonightAnswer(night: clear, smokeNote: smokeOff).dialog(voiceOnly: true) == Sentences.join([String(localized: "Tonight at \(jotr.shortName): \(clear.score.value), \(clear.score.band.label)."), smokeOff]))
        // Smoke that holds the score down is always said, since it is why the score is low, beside the clouds' caveat.
        let air = HourlySeries(updated: now, times: hours, values: ["aerosol_optical_depth": hours.map { _ in 0.6 }])
        let smoky = tonight(jotr, detail: ForecastDetail(air: air))
        let cap = try #require(smoky.smokeSentence(tonight: true))
        try #require(!smoky.score.hasForecast)
        let spoken = TonightAnswer(night: smoky, smokeNote: smokeOff).dialog(voiceOnly: true)
        #expect(spoken.contains(cap) && !spoken.contains(smokeOff))
        // The full answer says a full forecast in the one sentence every device uses.
        #expect(TonightAnswer(night: clear).dialog().contains(String(localized: "Includes cloud forecast.")))
    }
    /// The watch's clouds sentence takes the basis line's place, and nothing else changes.
    @Test func theWatchKeepsItsOwnCloudsLineOnly() throws {
        let night = tonight(try park("jotr"))
        let sent = "From the cloud forecast your iPhone sent at 9:00 PM."
        let watch = TonightAnswer(night: night, closure: "Road closed", clouds: sent).dialog()
        let phone = TonightAnswer(night: night, closure: "Road closed").dialog()
        #expect(watch == phone.replacingOccurrences(of: night.cloudSentence(), with: sent))
    }
    /// Cloud forecasts switched off: a forecast that should reach the night says why it is missing.
    @Test func forecastsOffIsSaid() throws {
        let night = tonight(try park("jotr"))
        try #require(night.basis == .usual && !night.beyondForecast)
        let off = String(localized: "Cloud forecasts are off in Your privacy.")
        #expect(TonightAnswer(night: night, forecastsOn: false).dialog().contains(off))
        #expect(!TonightAnswer(night: night).dialog().contains(off))
        #expect(night.cloudCaption(forecastsOn: false).hasSuffix(off))
    }

    // MARK: Usual clouds

    /// The month's sentence comes from the climate the night was scored with: a place whose months
    /// the iPhone handed over says it off the phone, where the bundled file does not hold it.
    @Test func usualCloudsSentenceFollowsTheCarriedClimate() throws {
        let months = CloudClimate.Months(cloud: Array(repeating: 40, count: 12), clear: Array(repeating: 80, count: 12))
        let carried = tonight(Self.spot, climate: CloudClimate(parks: [:]).carrying([Self.spot.id: months]))
        #expect(carried.basis == .usual && carried.usualCloud == 40)
        let sentence = try #require(carried.typicalClouds)
        #expect(sentence.hasPrefix("About 8 in 10 ") && sentence.hasSuffix(" nights here are mostly clear."))
        #expect(tonight(Self.spot, climate: CloudClimate(parks: [:])).typicalClouds == nil)
    }

    // MARK: Credits

    /// CC BY asks for the licence to be named: the watch and Vision Pro carry the iPhone's own lines,
    /// with ERA5's citation and licence and the star catalogue's authors and archive.
    @Test func everyDeviceNamesTheLicences() {
        let era5 = String(localized: "Usual clouds: contains modified Copernicus Climate Change Service information (2026): ERA5, 2015 to 2024, Hersbach et al. 2020, CC BY 4.0.")
        let stars = String(localized: "Stars: the Yale Bright Star Catalogue (Hoffleit and Warren), via NASA HEASARC.")
        for device in [Credits.Device.phone, .watch, .vision] {
            let lines = Credits.Section.allCases.flatMap { $0.lines(for: device) }
            #expect(lines.contains(era5) && lines.contains(stars), "\(device)")
            #expect(lines.contains { $0.contains("Hersbach et al. 2020, CC BY 4.0") } && lines.contains { $0.contains("(Hoffleit and Warren), via NASA HEASARC") })
            #expect(lines.contains(String(localized: "Neither the European Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains.")))
        }
        // The iPhone's list is every source, so no other device credits one the iPhone does not.
        let phone = Set(Credits.Section.allCases.flatMap { $0.lines(for: .phone) })
        let open = String(localized: "Weather data by Open-Meteo.com (CC BY 4.0), as averaged by Nyx.")
        for device in [Credits.Device.watch, .vision] {
            #expect(Set(Credits.Section.allCases.flatMap { $0.lines(for: device) }).subtracting(phone) == [open])
        }
    }

    // MARK: Network switches

    /// The four switches keep the keys people's choices are stored under, so no one's resets.
    @Test func networkSwitchesKeepTheirKeys() throws {
        let keys = Dictionary(uniqueKeysWithValues: NetworkService.allCases.map { ($0.host, $0.key) })
        #expect(keys == ["developer.nps.gov": "npsEnabled", "api.open-meteo.com": "weatherEnabled", "air-quality-api.open-meteo.com": "smokeEnabled",
                         "services.swpc.noaa.gov": "auroraEnabled"])
        #expect(SafeHTTP.preferences == keys && SafeHTTP.hosts.count == 4)
        let suite = "one-voice-\(UUID().uuidString)", defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for service in NetworkService.allCases {
            #expect(service.isOn(defaults))
            defaults.set(false, forKey: service.key)
            #expect(!service.isOn(defaults))
            let url = try #require(URL(string: "https://\(service.host)/x"))
            #expect(SafeHTTP.refusal(url, defaults: defaults) == .cancelled)
        }
    }

    // MARK: The Moon

    /// Vision Pro's Moon note under its night is the glance the iPhone's Moonlight caption uses
    /// (`SkyConditions.moonShort`): the rise and set are the value above it, so the note says what they
    /// mean for true darkness; nothing of the kind without true darkness.
    @Test func visionMoonNoteIsTheSharedRule() throws {
        let jotr = try park("jotr")
        var found: Set<String> = []
        for offset in 0..<30 {
            let sky = AstronomyEngine().conditions(for: jotr, on: jotr.date(jotr.currentNight(at: now), addingDays: offset))
            let note = sky.moonShort(park: jotr)
            switch sky.moonInDarkness {
            case .allFree: #expect(note == String(localized: "Moon down")); found.insert("free")
            case .allUp: #expect(note == String(localized: "Dark, Moon up")); found.insert("up")
            case .risesAt(let rise): #expect(note == String(localized: "Moon-free until \(jotr.time(rise))")); found.insert("rises")
            case .partial(let free): #expect(note == String(localized: "Moon-free for \(free)% of true darkness")); found.insert("partial")
            default: break
            }
        }
        #expect(found.contains("free"))
        let denali = try park("dena")
        let june = AstronomyEngine().conditions(for: denali, on: try #require(TripDay(iso: "2026-06-21")).evening(in: denali))
        #expect(june.darkHours == 0 && june.moonSentence(park: denali, withLit: false) == nil)
        // The Moon itself, as VoiceOver says it on every device: the phase first, no "Moon," before it.
        #expect(june.moon.spoken == String(localized: "\(june.moon.name), \(june.moon.percentLit) percent lit"))
    }
    /// The sky's state in one set of words for Tonight's sky and Vision Pro's.
    @Test func skyPhaseNames() {
        #expect(SkyPhase.name(sunAltitude: 5) == String(localized: "The Sun is up"))
        #expect(SkyPhase.name(sunAltitude: -3) == String(localized: "Twilight"))
        #expect(SkyPhase.name(sunAltitude: -9) == String(localized: "Late twilight"))
        #expect(SkyPhase.name(sunAltitude: -15) == String(localized: "Nearly dark"))
        #expect(SkyPhase.name(sunAltitude: -25) == String(localized: "True darkness"))
    }
}
