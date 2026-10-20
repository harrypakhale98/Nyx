import Foundation
import Testing
@testable import Nyx

/// What Siri says for the 1.4 shortcuts: when it is dark, what's up, following a night, and which
/// park an unnamed question is about. Real computed nights from the bundled parks; the words are
/// the pure functions the intents call, since Siri itself is not reachable from unit tests.
@MainActor struct ShortcutsTests {
    let parks: [Park]
    let engine=AstronomyEngine()
    init() throws { parks=try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    func sky(_ park: Park, _ day: String) throws -> SkyConditions {
        engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
    }
    let closure="Keys View Road closed at night"

    // MARK: When is it dark

    @Test func darkWindowSaysStartAndEndInParkTime() throws {
        let jotr=try park("jotr"), sky=try sky(jotr, "2026-10-12")
        let start=try #require(sky.darkStart), end=try #require(sky.darkEnd)
        let full=DarkWindowAnswer.dialog(park: jotr, sky: sky, closure: nil, voiceOnly: false, device: jotr.timeZone)
        #expect(full.hasPrefix("True darkness tonight at \(jotr.shortName): from \(jotr.time(start)) to \(jotr.time(end))."))
        #expect(full.contains("Sunset is at \(jotr.time(sky.sunset))."))
        // Same clock as the device: no time zone said.
        #expect(!full.contains("Times are"))
        let voice=DarkWindowAnswer.dialog(park: jotr, sky: sky, closure: nil, voiceOnly: true, device: jotr.timeZone)
        #expect(voice == "Tonight at \(jotr.shortName): true darkness from \(jotr.time(start)) to \(jotr.time(end)).")
        #expect(!full.contains("!") && !voice.contains("!"))
    }
    @Test func darkWindowNamesTheParksZoneWhenTheDeviceIsElsewhere() throws {
        let jotr=try park("jotr"), sky=try sky(jotr, "2026-10-12")
        let eastern=try #require(TimeZone(identifier: "America/New_York"))
        let full=DarkWindowAnswer.dialog(park: jotr, sky: sky, closure: nil, voiceOnly: false, device: eastern)
        #expect(full.hasSuffix("Times are \(jotr.timeZoneName)."))
        #expect(DarkWindowAnswer.dialog(park: jotr, sky: sky, closure: nil, voiceOnly: true, device: eastern).hasSuffix("Times are \(jotr.timeZoneName)."))
    }
    @Test func denaliInJuneHasNoTrueDarkness() throws {
        let denali=try park("dena"), sky=try sky(denali, "2026-06-21")
        #expect(sky.darkHours == 0)
        let full=DarkWindowAnswer.dialog(park: denali, sky: sky, closure: nil, voiceOnly: false, device: denali.timeZone)
        #expect(full.hasPrefix("\(denali.shortName) has no true darkness tonight at this latitude."))
        if let sunset=sky.sunset, let sunrise=sky.sunrise {
            #expect(full.contains("The sky stays in twilight from sunset at \(denali.time(sunset)) to sunrise at \(denali.time(sunrise))."))
        }
        #expect(!full.contains("True darkness tonight"))
        // Voice-only keeps the one sentence.
        #expect(DarkWindowAnswer.dialog(park: denali, sky: sky, closure: nil, voiceOnly: true, device: denali.timeZone) == "\(denali.shortName) has no true darkness tonight at this latitude.")
    }
    @Test func darkWindowSaysTheClosureFirst() throws {
        let jotr=try park("jotr"), sky=try sky(jotr, "2026-10-12")
        let plain=DarkWindowAnswer.dialog(park: jotr, sky: sky, closure: nil, voiceOnly: false, device: jotr.timeZone)
        let closed=DarkWindowAnswer.dialog(park: jotr, sky: sky, closure: closure, voiceOnly: false, device: jotr.timeZone)
        #expect(closed == "Closure alert: \(closure). "+plain)
        let voice=DarkWindowAnswer.dialog(park: jotr, sky: sky, closure: closure, voiceOnly: true, device: jotr.timeZone)
        #expect(voice.hasPrefix("Closure alert: \(closure). Tonight at \(jotr.shortName): "))
        // A blank headline is no closure.
        #expect(DarkWindowAnswer.dialog(park: jotr, sky: sky, closure: "  ", voiceOnly: false, device: jotr.timeZone) == plain)
        // The darkness score's dialog still leads with the same words.
        #expect(DarknessAnswer.closureFirst("Body.", closure: "Park closed.") == "Closure alert: Park closed. Body.")
    }

    // MARK: What's up

    @Test func whatsUpSaysThreeThingsBrieflyWithParkTimes() throws {
        let jotr=try park("jotr"), sky=try sky(jotr, "2026-08-12")
        let whatsUp=WhatsUp(park: jotr, sky: sky, isTonight: true)
        let dialog=WhatsUpAnswer.dialog(whatsUp, park: jotr, closure: nil, voiceOnly: false, device: jotr.timeZone)
        let lines=whatsUp.items.prefix(3).map { WhatsUpAnswer.line($0, core: whatsUp.coreNight, park: jotr, voiceOnly: false) }
        #expect(dialog == (["Tonight at \(jotr.shortName)."]+lines).joined(separator: " "))
        #expect(lines.count == min(3, whatsUp.items.count))
        // Summer in the desert: the core is up in true darkness, timed in park time.
        let dark=try #require(whatsUp.coreNight.dark)
        #expect(whatsUp.core.timed)
        #expect(WhatsUpAnswer.line(whatsUp.core, core: whatsUp.coreNight, park: jotr, voiceOnly: false)
                == "Milky Way core: up in true darkness from \(jotr.time(dark.start)) to \(jotr.time(dark.end)).")
        // A shower is its rate and when it peaks, without the published rate's long footnote.
        if let shower=whatsUp.shower, let note=shower.note, let value=shower.value {
            #expect(dialog.contains("\(shower.title), \(note): \(value)."))
            #expect(!dialog.contains("International Meteor Organization"))
        }
        #expect(!dialog.contains("!"))
    }
    @Test func whatsUpVoiceOnlyShortensPlanetsAndKeepsTheClosure() throws {
        let jotr=try park("jotr"), sky=try sky(jotr, "2026-10-12")
        let whatsUp=WhatsUp(park: jotr, sky: sky, isTonight: true)
        let voice=WhatsUpAnswer.dialog(whatsUp, park: jotr, closure: closure, voiceOnly: true, device: jotr.timeZone)
        #expect(voice.hasPrefix("Closure alert: \(closure). Tonight at \(jotr.shortName). "))
        for planet in whatsUp.planets {
            let line=WhatsUpAnswer.line(planet, core: whatsUp.coreNight, park: jotr, voiceOnly: true)
            #expect(line == "\(planet.title), \(planet.note ?? ""): \(planet.value ?? "").")
            #expect(WhatsUpAnswer.line(planet, core: whatsUp.coreNight, park: jotr, voiceOnly: false) == planet.spoken)
        }
    }
    @Test func whatsUpWithoutTrueDarknessStillAnswers() throws {
        let denali=try park("dena"), sky=try sky(denali, "2026-06-21")
        let whatsUp=WhatsUp(park: denali, sky: sky, isTonight: true)
        let dialog=WhatsUpAnswer.dialog(whatsUp, park: denali, closure: nil, voiceOnly: false, device: denali.timeZone)
        #expect(dialog.hasPrefix("Tonight at \(denali.shortName). "))
        #expect(!dialog.contains("up in true darkness"))
    }

    // MARK: Follow this night

    @Test func everyFollowResultHasAnHonestDialog() throws {
        let jotr=try park("jotr"), night=jotr.evening(try #require(try? Date("2026-10-16T20:00:00Z", strategy: .iso8601)))
        let day=FollowNightWords.day(jotr, night)
        let start=night.addingTimeInterval(5.5*3600)
        let scheduled=FollowNightWords.followed(.scheduled(start), park: jotr, night: night)
        #expect(scheduled == "Following \(jotr.shortName) on \(day). On your Lock Screen from \(jotr.time(start)), without opening Nyx.")
        #expect(FollowNightWords.followed(.started, park: jotr, night: night) == "Following \(jotr.shortName) on \(day). On your Lock Screen now, until dawn.")
        #expect(FollowNightWords.followed(.alreadyFollowing, park: jotr, night: night) == "You are already following \(jotr.shortName) on \(day).")
        #expect(FollowNightWords.followed(.over, park: jotr, night: night).contains("is over"))
        #expect(FollowNightWords.followed(.unavailable, park: jotr, night: night).contains("Live Activities may be off"))
        for result: FieldActivities.FollowResult in [.scheduled(start), .started, .alreadyFollowing, .over, .unavailable] {
            let words=FollowNightWords.followed(result, park: jotr, night: night)
            #expect(!words.isEmpty && !words.contains("!"))
        }
        #expect(day.contains("October"))
    }
    @Test func unfollowFindsTheNightAndSaysWhenNothingIsFollowed() throws {
        let jotr=try park("jotr"), acad=try park("acad")
        let friday=jotr.evening(try #require(try? Date("2026-10-16T20:00:00Z", strategy: .iso8601)))
        let saturday=acad.evening(try #require(try? Date("2026-10-17T20:00:00Z", strategy: .iso8601)))
        let followed: [(park: Park, night: Date)]=[(jotr, friday), (acad, saturday)]
        // Nothing named: the soonest.
        #expect(FollowNightWords.target(followed, park: nil, night: nil)?.park.id == "jotr")
        // A park: its soonest.
        #expect(FollowNightWords.target(followed, park: acad, night: nil)?.night == saturday)
        // A night picked as a day in the person's calendar finds that park's evening.
        var eastern=Calendar(identifier: .gregorian)
        eastern.timeZone=try #require(TimeZone(identifier: "America/New_York"))
        let midnight=try #require(eastern.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        #expect(FollowNightWords.target(followed, park: jotr, night: midnight, calendar: eastern)?.night == friday)
        #expect(FollowNightWords.target(followed, park: nil, night: midnight, calendar: eastern)?.park.id == "jotr")
        #expect(FollowNightWords.target(followed, park: try park("dena"), night: nil) == nil)
        #expect(FollowNightWords.target([], park: nil, night: nil) == nil)

        #expect(FollowNightWords.unfollowed((jotr, friday), park: nil) == "Stopped following \(jotr.shortName) on \(FollowNightWords.day(jotr, friday)). It is off your Lock Screen.")
        #expect(FollowNightWords.unfollowed(nil, park: acad) == "You are not following a night at \(acad.shortName).")
        #expect(FollowNightWords.unfollowed(nil, park: nil) == "You are not following any nights.")
    }
    /// Stop following finds a saved spot's night as it finds a park's: through every place a night
    /// can be followed at, not the 63 parks alone. A night whose dawn has passed is left out unless named.
    @Test func unfollowFindsASavedSpotsNight() throws {
        let spot=Place(spotID: "pin:00000000-0000-4000-8000-0000000000aa", name: "Pullout off Pinto Basin Road", latitude: 33.92, longitude: -115.93,
                       timeZoneID: "America/Los_Angeles", countryCode: "US", region: "California")
        let jotr=try park("jotr")
        let spotNight=FieldActivityAttributes(night: FieldNight(park: spot, sky: try sky(spot, "2026-10-16")), score: 90, band: "Pristine", closure: nil)
        let parkNight=FieldActivityAttributes(night: FieldNight(park: jotr, sky: try sky(jotr, "2026-10-17")), score: 80, band: "Excellent", closure: nil)
        let places=[spot, jotr]
        let find: (String) -> Park? = { id in places.first { $0.id == id } }
        let before=spotNight.dusk.addingTimeInterval(-3600)
        let followed=FollowNightWords.followed([spotNight, parkNight], named: nil, now: before, find: find)
        #expect(followed.map(\.park.id) == [spot.id, "jotr"])
        #expect(FollowNightWords.target(followed, park: spot, night: nil)?.night == spotNight.nightID)
        // The spot's dawn has passed: the soonest night still ahead is the park's, unless the spot's night is named.
        let after=spotNight.dawn.addingTimeInterval(60)
        #expect(FollowNightWords.followed([spotNight, parkNight], named: nil, now: after, find: find).map(\.park.id) == ["jotr"])
        #expect(FollowNightWords.followed([spotNight, parkNight], named: before, now: after, find: find).count == 2)
        // A place that can no longer be found is left out, never matched to another.
        #expect(FollowNightWords.followed([spotNight], named: nil, now: before, find: { _ in nil }).isEmpty)
    }
    @Test func aNightsOwnEveningIsKeptAndAPickedDayIsThePersonsDay() throws {
        let jotr=try park("jotr")
        let evening=jotr.evening(try #require(try? Date("2026-10-16T20:00:00Z", strategy: .iso8601)))
        // The best-night card hands over the night's own evening: kept, whatever the device's zone.
        var tokyo=Calendar(identifier: .gregorian)
        tokyo.timeZone=try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(FollowNightWords.evening(of: evening, at: jotr, calendar: tokyo) == evening)
        // Midnight on the 16th in New York is 9 PM on the 15th at Joshua Tree, but the person meant the 16th.
        var eastern=Calendar(identifier: .gregorian)
        eastern.timeZone=try #require(TimeZone(identifier: "America/New_York"))
        let midnight=try #require(eastern.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        #expect(FollowNightWords.evening(of: midnight, at: jotr, calendar: eastern) == evening)
    }

    // MARK: Which park

    @Test func anUnnamedParkIsTheNightUnderWayThenTheStartingPark() throws {
        #expect(try IntentPark.resolve(nil, library: parks, inProgress: nil, home: "dena").id == "dena")
        #expect(try IntentPark.resolve(nil, library: parks, inProgress: "acad", home: "dena").id == "acad")
        #expect(try IntentPark.resolve(nil, library: parks, inProgress: nil, home: nil).id == "jotr")
        #expect(try IntentPark.resolve(nil, library: parks, inProgress: "gone", home: "gone").id == "jotr")
        #expect(try IntentPark.resolve(ParkEntity(id: "grca", name: "Grand Canyon"), library: parks, inProgress: "acad", home: "dena").id == "grca")
        #expect(throws: NyxIntentError.self) { try IntentPark.resolve(ParkEntity(id: "nowhere", name: "Nowhere"), library: parks, inProgress: nil, home: nil) }
    }
}
