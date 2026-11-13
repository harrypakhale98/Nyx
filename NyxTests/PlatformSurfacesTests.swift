import ActivityKit
import AppIntents
import CoreLocation
import CoreSpotlight
import Foundation
import GeoToolbox
import SwiftUI
import Testing
@testable import Nyx

/// Platform surfaces: a followed night's Live Activity (when it starts, heading out, the
/// stale face), the tab bar's night in progress, the widgets' park setting and Moon pictures, the
/// Tonight control, Siri's values, Handoff, the journal by voice, the alarms' "Open sky" and the
/// reminders' forecast-model reason.
@MainActor struct PlatformSurfacesTests {
    let parks: [Park]
    let engine=AstronomyEngine()
    init() throws { parks=try ParkData.load() }
    func sky(_ park: Park, _ day: String) throws -> SkyConditions {
        engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
    }
    /// 2026-12-01, 21:00 UTC: afternoon in every US park.
    let now=Date(timeIntervalSince1970: 1_796_158_800)
    func forecast(cover: Double=5) -> Forecast {
        let first=(floor(now.timeIntervalSince1970/86400)-1)*86400
        let hours=(0..<(16*24)).map { first+Double($0)*3600 }
        return Forecast(updated: now.addingTimeInterval(-1800), times: hours, clouds: hours.map { _ in cover })
    }

    // MARK: Following a night

    /// Half an hour before sunset on an ordinary night; later on a long winter night, so the
    /// system's eight-hour limit still covers an hour past the middle of true darkness.
    @Test func followStartIsBeforeSunsetUnlessTheNightIsTooLong() throws {
        let jotr=try park("jotr"), october=try self.sky(jotr, "2026-10-09")
        let sunset=try #require(october.sunset)
        #expect(FieldActivityAttributes.followStart(october) == sunset.addingTimeInterval(-1800))
        // Denali in December: about 18 hours from sunset to sunrise.
        let dena=try park("dena"), december=try self.sky(dena, "2026-12-20")
        let start=FieldActivityAttributes.followStart(december)
        let window=december.cloudWindow
        let middle=window.start.addingTimeInterval(window.end.timeIntervalSince(window.start)/2)
        #expect(start>(december.sunset ?? window.start).addingTimeInterval(-1800))
        #expect(abs(start.addingTimeInterval(FieldActivityAttributes.activeLimit).timeIntervalSince(middle.addingTimeInterval(3600)))<1)
        // Always before true darkness begins on that winter night, so the alert still comes first.
        #expect(start<(december.darkStart ?? .distantFuture))
        // No true darkness (Denali in June): still a moment inside the evening.
        let june=try self.sky(dena, "2026-06-21")
        #expect(FieldActivityAttributes.followStart(june)>june.evening)
    }
    @Test func followAlertNamesTheParkAndTrueDarknessInParkTime() throws {
        let jotr=try park("jotr"), sky=try self.sky(jotr, "2026-10-09")
        let alert=FieldActivityAttributes.followAlert(park: jotr, sky: sky, device: jotr.timeZone)
        #expect(alert.title == "Tonight at Joshua Tree")
        let dark=try #require(sky.darkStart)
        #expect(alert.body == "True darkness at \(jotr.time(dark))")
        // A phone keeping another clock hears whose time it is, as the reminders say it: Petrified
        // Forest keeps Mountain Standard Time all year, an hour off California's clock in December.
        let pefo=try park("pefo"), december=try self.sky(pefo, "2026-12-13")
        let pefoDark=try #require(december.darkStart)
        let zoned=FieldActivityAttributes.followAlert(park: pefo, sky: december, device: try #require(TimeZone(identifier: "America/Los_Angeles")))
        #expect(zoned.body == "True darkness at \(pefo.zonedTime(pefoDark, device: try #require(TimeZone(identifier: "America/Los_Angeles"))))")
        #expect(zoned.body.hasSuffix("MST"))
        #expect(FieldActivityAttributes.followAlert(park: pefo, sky: december, device: pefo.timeZone).body == "True darkness at \(pefo.time(pefoDark))")
        let dena=try park("dena"), june=try self.sky(dena, "2026-06-21")
        #expect(!FieldActivityAttributes.followAlert(park: dena, sky: june).body.hasPrefix("True darkness at"))
    }
    /// Heading out until true darkness begins; the night is recorded so it is followed once.
    @Test func headingOutLastsUntilTrueDarkness() throws {
        let jotr=try park("jotr"), sky=try self.sky(jotr, "2026-12-13")
        let attributes=FieldActivityAttributes(night: FieldNight(park: jotr, sky: sky), score: 94, band: "Pristine", closure: "Keys View Road closed")
        let start=try #require(sky.darkStart)
        #expect(attributes.nightID == sky.evening && attributes.closure == "Keys View Road closed")
        #expect(attributes.state(at: start.addingTimeInterval(-600), nightVision: false, heading: true).heading == true)
        #expect(attributes.state(at: start.addingTimeInterval(60), nightVision: false, heading: true).heading == nil)
        #expect(attributes.state(at: start.addingTimeInterval(-600), nightVision: false).heading == nil)
        #expect(attributes.covers(parkID: "jotr", night: sky.evening) && !attributes.covers(parkID: "jotr", night: jotr.date(sky.evening, addingDays: 1)))
        #expect(!attributes.covers(parkID: "deva", night: sky.evening))
        // An activity from 1.1 (7), with no night recorded, matches the night whose sunset it starts from.
        var legacy=attributes
        legacy.nightID=nil
        #expect(legacy.covers(parkID: "jotr", night: sky.evening) && !legacy.covers(parkID: "jotr", night: jotr.date(sky.evening, addingDays: 1)))
        // Still within ActivityKit's 4 KB with the new fields.
        let state=attributes.state(at: start, nightVision: true, heading: true)
        #expect(try JSONEncoder().encode(attributes).count+JSONEncoder().encode(state).count<4096)
        // A state written before `heading` and `updated` existed still decodes.
        let old=#"{"nightVision":false,"finished":false}"#.data(using: .utf8) ?? Data()
        #expect(try JSONDecoder().decode(FieldActivityAttributes.ContentState.self, from: old).heading == nil)
        // Only the moment it was worked out changing is no reason to update.
        var later=state
        later.updated=start.addingTimeInterval(600)
        #expect(!FieldActivities.changed(state, later, attributes: attributes))
        later.nightVision=false
        #expect(FieldActivities.changed(state, later, attributes: attributes))
    }
    /// With no true darkness (Denali in June), heading out ends at sunset: the face counts down to
    /// sunset by name and goes stale there, never to the Moon or a planet after it.
    @Test func headingOutWithoutDarknessEndsAtSunset() throws {
        let dena=try park("dena"), june=try self.sky(dena, "2027-06-20")
        try #require(june.darkStart == nil && june.sunset != nil)
        let attributes=FieldActivityAttributes(night: FieldNight(park: dena, sky: june), score: 30, band: "Poor")
        let start=FieldActivityAttributes.followStart(june)
        try #require(start<attributes.dusk)
        let content=attributes.content(at: start, nightVision: false, heading: true)
        #expect(content.state.heading == true)
        #expect(content.state.next?.date == attributes.dusk && content.state.next?.symbol == "sunset")
        #expect(content.staleDate == attributes.dusk)
        // Once stale, the schedule lists every mark of the night after sunset.
        #expect(attributes.schedule(content.state) == attributes.milestones.filter { $0.date>attributes.dusk })
        // Past sunset the night runs as before.
        let after=attributes.state(at: attributes.dusk.addingTimeInterval(60), nightVision: false, heading: true)
        #expect(after.heading == nil && after.next == attributes.milestones.first { $0.date>attributes.dusk.addingTimeInterval(60) })
    }
    /// A crescent Moon setting in the twilight before true darkness does not end heading out early:
    /// the activity counts down to true darkness and goes stale only then, so the closure, "Tonight
    /// at …" and the sunset and true-darkness times stay on a locked phone until arrival.
    @Test func headingOutCountsToTrueDarknessPastAnEarlyMoonset() throws {
        let dusk=now.addingTimeInterval(3600)
        func at(_ minutes: Double) -> Date { dusk.addingTimeInterval(minutes*60) }
        let attributes=FieldActivityAttributes(parkID: "jotr", parkName: "Joshua Tree", score: 78, band: "Excellent", dusk: dusk, dawn: at(760),
            darkStart: at(85), darkEnd: at(670),
            milestones: [.init(title: "Moonset", date: at(40), symbol: "moonset"), .init(title: "True darkness", date: at(85), symbol: "moon.stars"),
                         .init(title: "Dawn twilight", date: at(670), symbol: "sun.horizon")],
            timeZoneID: "America/Los_Angeles", closure: "Keys View Road closed")
        let content=attributes.content(at: at(-30), nightVision: false, heading: true)
        #expect(content.state.heading == true && content.state.next?.date == at(85))
        #expect(content.staleDate == attributes.darkStart)
        // A minute before true darkness: still fresh, heading out, counting to it, closure shown.
        #expect(at(84)<(content.staleDate ?? .distantPast))
        #expect(attributes.shown(content.state, isStale: false)?.title == "True darkness")
        #expect(attributes.closure(content.state) == "Keys View Road closed")
        // Not heading out (field mode), the Moon's setting is still the next moment.
        #expect(attributes.state(at: at(-30), nightVision: false).next?.date == at(40))
        // Once it has gone stale, the schedule lists what follows true darkness.
        #expect(attributes.schedule(content.state).map(\.title) == ["Dawn twilight"])
    }
    /// Three hours after the moment the activity was counting down to, with no update, the
    /// face names no moment next: it lists the night's remaining times and when it was updated.
    @Test func staleFaceListsTimesThreeHoursLater() throws {
        let jotr=try park("jotr"), sky=try self.sky(jotr, "2026-12-13")
        let attributes=FieldActivityAttributes(night: FieldNight(park: jotr, sky: sky), score: 94, band: "Pristine")
        let start=try #require(sky.darkStart)
        let state=attributes.state(at: start.addingTimeInterval(-300), nightVision: false)
        let next=try #require(state.next)
        #expect(next.date == start)
        // Three hours on: stale. Nothing is counted down to; the island names sunrise, which stays true.
        #expect(attributes.shown(state, isStale: true) == nil)
        let mark=FieldActivityMark(attributes: attributes, state: state, isStale: true)
        #expect(mark.milestone == nil && mark.title == "Sunrise" && mark.symbol == "sunrise")
        // VoiceOver hears a milestone's name once, from its countdown; sunrise's clock time does not name it.
        #expect(!mark.namedByCountdown && FieldActivityMark(attributes: attributes, state: state, isStale: false).namedByCountdown)
        #expect(FieldActivityMark(attributes: attributes, state: attributes.state(at: attributes.dawn, nightVision: false), isStale: false).namedByCountdown)
        let schedule=attributes.schedule(state)
        #expect(!schedule.isEmpty && schedule.allSatisfy { $0.date>next.date } && schedule == attributes.after(next))
        // Fresh, it still counts down to the next moment.
        #expect(attributes.shown(state, isStale: false) == next)
        // "Updated 7:44 PM", or with the weekday when it was planned on another day; park time.
        let format=FieldActivityUpdated.format(start, dusk: attributes.dusk, zone: jotr.timeZone)
        #expect(format.timeZone == jotr.timeZone)
        let planned=FieldActivityUpdated.format(start.addingTimeInterval(-3*86400), dusk: attributes.dusk, zone: jotr.timeZone)
        #expect(start.addingTimeInterval(-3*86400).formatted(planned) != start.addingTimeInterval(-3*86400).formatted(format))
        // The stale face draws three hours after its moment.
        let face=FieldActivityLockView(attributes: attributes, state: state, isStale: true).frame(width: 360).background(Color.black)
        let renderer=ImageRenderer(content: face)
        #expect(renderer.uiImage != nil)
        let small=ImageRenderer(content: FieldActivitySmallView(attributes: attributes, state: state, isStale: true).frame(width: 170, height: 84))
        #expect(small.uiImage != nil)
    }
    /// The faces keep park time. On an iPhone whose clock is elsewhere (Denver, for Joshua Tree),
    /// they name the park's short zone once beside its name ("· PST") and VoiceOver hears whose time
    /// it is; on the park's own clock nothing changes.
    @Test func fieldFacesNameTheParkZoneOnlyOnAnotherClock() throws {
        let jotr=try park("jotr"), sky=try self.sky(jotr, "2026-12-13")
        let denver=try #require(TimeZone(identifier: "America/Denver"))
        let attributes=FieldActivityAttributes(night: FieldNight(park: jotr, sky: sky), score: 94, band: "Pristine")
        #expect(!jotr.timeZone.keepsOtherTime(at: attributes.dusk, device: jotr.timeZone) && jotr.timeZone.keepsOtherTime(at: attributes.dusk, device: denver))
        #expect(jotr.timeZone.shortName(at: attributes.dusk, locale: Locale(identifier: "en_US")) == "PST")
        #expect(jotr.timeZone.shortName(at: attributes.dusk, locale: Locale(identifier: "de_DE")) == "GMT-8")
        // Named only where the clock differs from this device's.
        #expect(attributes.namedZone(nil, device: denver) == jotr.timeZone && attributes.namedZone(nil, device: jotr.timeZone) == nil)
        #expect(jotr.timeZone.timesNote == "Times in \(jotr.timeZoneName).")
        #expect(jotr.timeZone.spokenZone(at: attributes.dusk, device: denver) == jotr.timeZone.timesNote)
        #expect(jotr.timeZone.spokenZone(at: attributes.dusk, device: jotr.timeZone) == nil)
        // The faces draw with the zone named.
        let face=FieldActivityLockView(attributes: attributes, state: attributes.state(at: attributes.dusk, nightVision: false), isStale: true)
            .environment(\.fieldParkZone, denver).frame(width: 360).background(Color.black)
        #expect(ImageRenderer(content: face).uiImage != nil)
    }
    /// The night the clocks fall back in Los Angeles (2026-11-01, 2 AM), Grand Canyon keeps MST: the
    /// two clocks agree at dusk and differ by sunrise, so the faces still name the park's zone.
    @Test func fieldFacesNameTheZoneOnTheNightTheClocksChange() throws {
        let grca=try park("grca"), sky=try self.sky(grca, "2026-10-31")
        let la=try #require(TimeZone(identifier: "America/Los_Angeles"))
        let attributes=FieldActivityAttributes(night: FieldNight(park: grca, sky: sky), score: 80, band: "Excellent")
        #expect(!grca.timeZone.keepsOtherTime(at: attributes.dusk, device: la) && grca.timeZone.keepsOtherTime(at: attributes.dawn, device: la))
        #expect(attributes.namedZone(nil, device: la) == grca.timeZone)
        #expect(attributes.namedZone(nil, device: grca.timeZone) == nil)
    }
    @Test func tabStripShowsAFollowedNightFromThreeHoursBeforeSunsetUntilDawn() throws {
        let jotr=try park("jotr"), sky=try self.sky(jotr, "2026-12-13")
        let attributes=FieldActivityAttributes(night: FieldNight(park: jotr, sky: sky), score: 94, band: "Pristine")
        let pending=NightFollowing.Followed(attributes: attributes, started: false)
        #expect(NightFollowing.inProgress([pending], at: attributes.dusk.addingTimeInterval(-4*3600)) == nil)
        #expect(NightFollowing.inProgress([pending], at: attributes.dusk.addingTimeInterval(-2*3600)) == pending)
        #expect(NightFollowing.inProgress([pending], at: attributes.dawn) == nil)
        let running=NightFollowing.Followed(attributes: attributes, started: true)
        #expect(NightFollowing.inProgress([running], at: attributes.dusk.addingTimeInterval(-5*3600)) == running)
        // What it says: sunset first, then each moment, then sunrise; whole minutes, never seconds.
        #expect(NightStatus(attributes, at: attributes.dusk.addingTimeInterval(-80*60)).line == "Sunset in \(NightStatus.duration(80*60))")
        let start=try #require(sky.darkStart)
        let dark=NightStatus(attributes, at: start.addingTimeInterval(-14*60-20))
        #expect(dark.line.hasPrefix("True darkness in") && dark.short == NightStatus.duration(14*60+20) && dark.symbol == "moon.stars")
        #expect(NightStatus.duration(14*60+20) == NightStatus.duration(15*60))
        #expect(NightStatus(attributes, at: attributes.dawn.addingTimeInterval(-60)).line.hasPrefix("Sunrise at"))
    }

    // MARK: Widgets and the control

    @Test func tonightWidgetDefaultsToTheDarkestSavedParkAndCanFollowOne() throws {
        let jotr=try park("jotr"), deva=try park("deva"), acad=try park("acad")
        let snapshot=SavedSkySnapshot(parks: [acad, jotr, deva], forecasts: [:], closures: ["deva": "Badwater Road closed"])
        var darkest=TonightTimeline(snapshot: snapshot, large: false)
        let entry=darkest.entry(at: now)
        let ranked=WidgetSelection.ordered(snapshot.parks.map { snapshot.planner.night($0, on: $0.currentNight(at: now), now: now) })
        #expect(entry.night?.park.id == ranked.first?.park.id && entry.savedCount == 3 && entry.position == 1)
        // Set to one park: that park, with no "2 of 3" and its own closure line.
        var pinned=TonightTimeline(snapshot: snapshot, large: true, pinned: deva)
        let one=pinned.entry(at: now)
        #expect(one.night?.park.id == "deva" && one.savedCount == 0 && one.position == 0 && one.month != nil)
        #expect(one.closure == "Badwater Road closed")
        // A park that is not saved still shows, scored on its usual clouds, without a closure.
        var unsaved=TonightTimeline(snapshot: snapshot, large: false, pinned: try park("grba"))
        let grba=unsaved.entry(at: now)
        #expect(grba.night?.park.id == "grba" && grba.night?.basis == .usual && grba.closure == nil)
        // The control reads the same: "Tonight 93" for the darkest saved park, nothing before any is saved.
        let control=TonightControlValue(snapshot: snapshot, pinned: nil, now: now)
        #expect(control.parkID == entry.night?.park.id && control.score == entry.night?.score.value)
        let empty=TonightControlValue(snapshot: nil, pinned: nil, now: now)
        #expect(empty.parkID == nil && empty.score == nil)
        // A control has no VoiceOver label of its own: a closure is said in its second line, beside the glyph.
        let closed=TonightControlValue(snapshot: snapshot, pinned: deva, now: now)
        #expect(closed.symbol == ClosureLine.symbol && closed.closure == "Badwater Road closed")
        #expect(closed.subtitle == "\(deva.shortName) · Badwater Road closed")
        let open=TonightControlValue(snapshot: snapshot, pinned: jotr, now: now)
        #expect(open.closure == nil && open.symbol != ClosureLine.symbol && open.subtitle == jotr.shortName)
        #expect(empty.subtitle == "Save a place in Nyx")
        // The widget's default setting is no park (today's behaviour), so placed widgets keep it.
        #expect(TonightWidgetIntent().park == nil && MoonWidgetIntent().park == nil && TonightControlIntent().park == nil)
    }
    @Test func smartStackKnowsWhereTheParkIs() throws {
        let jotr=try park("jotr")
        let region=TonightTimeline.region(jotr)
        let spot=try #require(jotr.viewingSpots.first)
        #expect(region.radius == 25_000 && region.center.latitude == spot.latitude && region.center.longitude == spot.longitude)
    }
    /// The widget shows the picture of its own night only; a neighbouring night's picture would
    /// show another phase, so without one it draws the vector Moon.
    @Test func widgetMoonIsTheExactNightOnly() throws {
        let night=Date(timeIntervalSince1970: 1_800_000_000), park="test-moon-\(UUID().uuidString.prefix(8))"
        let next=try #require(SharedSettings.moonImageURL(park: park, night: night.addingTimeInterval(86400)))
        try Data([0]).write(to: next)
        defer { try? FileManager.default.removeItem(at: next) }
        #expect(SharedSettings.moonImage(park: park, night: night) == nil)
        let exact=try #require(SharedSettings.moonImageURL(park: park, night: night))
        try Data([0]).write(to: exact)
        defer { try? FileManager.default.removeItem(at: exact) }
        #expect(SharedSettings.moonImage(park: park, night: night) == exact)
        #expect(SavedSkySync.moonNights == 7)
    }

    // MARK: Siri and Shortcuts

    @Test func darknessIntentReturnsTheScoreItSays() throws {
        let jotr=try park("jotr")
        let answer=DarknessAnswer(park: jotr, forecast: forecast(), detail: nil, now: now)
        let expected=NightPlanner.night(park: jotr, sky: engine.conditions(for: jotr, on: jotr.currentNight(at: now)), forecast: forecast(), detail: nil, now: now)
        #expect(answer.night.score.value == expected.score.value)
        #expect(answer.dialog.hasPrefix("Joshua Tree: \(expected.score.value) out of 100"))
        // Gates of the Arctic in June: no true darkness, said first.
        let gaar=try park("gaar")
        let june=DarknessAnswer(park: gaar, forecast: nil, detail: nil, now: Date(timeIntervalSince1970: 1_781_960_400))
        #expect(june.dialog.hasPrefix("No true darkness tonight at"))
    }
    @Test func bestNightIntentReturnsWhenTrueDarknessBegins() throws {
        let jotr=try park("jotr")
        let answer=try #require(BestNightSearch.answer(parks: [jotr], planner: NightPlanner(forecasts: ["jotr": forecast()]), from: now, nights: 14, now: now))
        #expect(BestNightSearch.value(answer) == answer.best.sky.darkStart)
    }
    @Test func parkEntityExposesStateDesignationAndBortle() throws {
        let entity=ParkEntity(try park("jotr"))
        #expect(entity.stateName == "CA" && entity.designation == "International Dark Sky Park" && entity.bortleClass == entity.bortle && entity.bortle>0)
        #expect(entity.attributeSet.keywords?.contains("Bortle \(entity.bortle)") == true)
        #expect(ParkEntity(try park("dena")).designation.isEmpty)
    }

    // MARK: Handoff

    @Test func handoffCarriesTheParkAndItsNight() throws {
        let jotr=try park("jotr"), sky=try self.sky(jotr, "2026-12-13")
        let handoff=ParkHandoff(park: jotr, night: sky.evening)
        #expect(handoff.userInfo == ["park": "jotr", "night": "2026-12-13"])
        let back=try #require(ParkHandoff(userInfo: handoff.userInfo))
        #expect(back == handoff && back.evening(in: jotr) == sky.evening)
        // American Samoa's night is its own calendar day, not the phone's.
        let npsa=try park("npsa"), samoa=try self.sky(npsa, "2026-12-13")
        #expect(ParkHandoff(userInfo: ParkHandoff(park: npsa, night: samoa.evening).userInfo)?.evening(in: npsa) == samoa.evening)
        #expect(ParkHandoff(userInfo: ["park": "../x"]) == nil && ParkHandoff(userInfo: [:]) == nil && ParkHandoff(userInfo: nil) == nil)
        #expect(ParkHandoff(userInfo: ["park": "jotr", "night": "2026-13-40"])?.night == nil)
        #expect(ParkHandoff.type == "com.harrypakhale.nyx.park")
    }

    // MARK: Journal by voice

    @Test func spokenEntriesGoToTonightsParkOrTheNearestOne() throws {
        let jotr=try park("jotr")
        #expect(JournalAccess.defaultParkID(location: nil, inProgress: "deva", home: "acad") == "deva")
        let place=JournalAccess.place(jotr)
        #expect(place.commonName == jotr.name && place.coordinate?.latitude == jotr.latitude)
        #expect(JournalAccess.defaultParkID(location: place, inProgress: nil, home: "acad") == "jotr")
        let chicago=PlaceDescriptor(representations: [.coordinate(CLLocationCoordinate2D(latitude: 41.88, longitude: -87.63))], commonName: "Chicago")
        #expect(JournalAccess.defaultParkID(location: chicago, inProgress: nil, home: "acad") == "acad")
    }

    // MARK: Alarms and reminders

    @Test func onlyTheCoreAlarmOpensTheSky() {
        #expect(FieldAlarms.opensSky(.core) && !FieldAlarms.opensSky(.darkness) && !FieldAlarms.opensSky(.moonset))
    }
    /// A reminder says all three forecast models are clear only when they are.
    @Test func reminderCitesTheModelsOnlyWhenAllThreeAreClear() throws {
        let jotr=try park("jotr"), sky=try self.sky(jotr, "2026-12-13")
        let night=Night(park: jotr, sky: sky, score: DarknessScore(value: 94, moonPoints: 40, cloudPoints: 25, bortlePoints: 17, lengthPoints: 12), cloudCover: 5, forecastUpdated: now)
        let plain=NotificationScheduler.reason(night)
        #expect(NotificationScheduler.reason(night, models: ModelAgreement(low: 2, high: 9)) == "\(plain); all three forecast models clear")
        #expect(NotificationScheduler.reason(night, models: ModelAgreement(low: 2, high: 30)) == plain)
        #expect(NotificationScheduler.reason(night, models: ModelAgreement(low: 20, high: 30)) == plain)
        #expect(NotificationScheduler.body(night, models: ModelAgreement(low: 2, high: 9)).contains("all three forecast models clear"))
        #expect(!NotificationScheduler.modelsClear(nil))
        // A night with no forecast in its score never cites the models, whatever the detail says.
        let usual=Night(park: jotr, sky: sky, score: DarknessScore(value: 94, moonPoints: 40, cloudPoints: nil, bortlePoints: 17, lengthPoints: 12), cloudCover: nil, forecastUpdated: nil)
        #expect(NotificationScheduler.agreement(usual, detail: ForecastDetail(), now: now) == nil)
    }
}
