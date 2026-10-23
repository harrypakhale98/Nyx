import Foundation
import Testing
@testable import Nyx

/// Going: the nights kept, when a change is worth saying, the better choice, the time to leave,
/// what is saved for offline use and the plan sent to someone. Real computed skies; scores set by hand.
@Suite struct GoingTests {
    let engine = AstronomyEngine()
    func sky(_ park: Park, _ day: String) throws -> SkyConditions {
        engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
    }
    func night(_ park: Park, _ sky: SkyConditions, score: Int, basis: CloudBasis = .forecast, limit: ScoreLimit? = nil) -> Night {
        Night(park: park, sky: sky, score: DarknessScore(value: score, moonPoints: 30, cloudPoints: 20, bortlePoints: 16, lengthPoints: 10, basis: basis, limit: limit),
              cloudCover: 10, forecastUpdated: .now)
    }

    // MARK: The nights kept

    @MainActor @Test func keepsSoonestFourAndLetsOldNightsGo() throws {
        let defaults = isolatedDefaults()
        let store = GoingNights(defaults: defaults), jotr = try park("jotr")
        let days = ["2026-10-24", "2026-10-22", "2026-10-26", "2026-10-23", "2026-10-28"]
        for (index, day) in days.enumerated() { store.go(night(jotr, try sky(jotr, day), score: 70+index)) }
        #expect(store.nights.count == GoingNights.limit)
        #expect(store.nights.map(\.night) == store.nights.map(\.night).sorted())
        let latest = try sky(jotr, "2026-10-28").evening
        #expect(!store.nights.contains { $0.night == latest })
        // Kept on this iPhone, read back as written.
        #expect(GoingNights(defaults: defaults).nights == store.nights)
        // Going twice keeps one; the first score stays the one changes are measured from.
        let first = try #require(store.nights.first)
        store.go(night(jotr, try sky(jotr, "2026-10-22"), score: 20))
        #expect(store.nights.first == first)
        store.prune(now: first.night.addingTimeInterval(37*3600))
        #expect(!store.nights.contains(first))
    }
    @MainActor @Test func driveAndAnnouncedAreKept() throws {
        let store = GoingNights(defaults: isolatedDefaults()), jotr = try park("jotr")
        store.go(night(jotr, try sky(jotr, "2026-10-24"), score: 82))
        let going = try #require(store.nights.first)
        store.setDrive(195, for: going); store.announced(60, for: going)
        #expect(store.nights.first?.driveMinutes == 195 && store.nights.first?.announcedScore == 60)
        store.stop(going)
        #expect(store.nights.isEmpty)
    }

    // MARK: When a change is worth saying

    @Test func fallIsFifteenOrALowerBand() {
        #expect(GoingCheck.fell(chosen: 82, to: 67))
        // Twelve points within one band (Good) is not a fall.
        #expect(!GoingCheck.fell(chosen: 72, to: 60))
        // Into a lower band by more than a few points: Excellent 78 to Good 72.
        #expect(GoingCheck.fell(chosen: 78, to: 72))
        // Across a band edge by two points is not news.
        #expect(!GoingCheck.fell(chosen: 76, to: 74))
    }
    @Test func announcedOnceThenOnlyIfFurther() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-10-24")
        var going = GoingNight(parkID: "jotr", night: sky.evening, chosenScore: 82, chosenAt: .now)
        #expect(GoingCheck.announces(going, night: night(jotr, sky, score: 60)))
        going.announcedScore = 60
        #expect(!GoingCheck.announces(going, night: night(jotr, sky, score: 55)))
        #expect(GoingCheck.announces(going, night: night(jotr, sky, score: 50)))
        // A month's usual clouds alone never trigger an alert.
        #expect(!GoingCheck.announces(GoingNight(parkID: "jotr", night: sky.evening, chosenScore: 82, chosenAt: .now), night: night(jotr, sky, score: 40, basis: .usual)))
    }
    @Test func statusReadsTheNight() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-10-24")
        #expect(GoingCheck.status(chosen: 82, night: night(jotr, sky, score: 80), agreement: ModelAgreement(low: 5, high: 10)) == .good)
        #expect(GoingCheck.status(chosen: 82, night: night(jotr, sky, score: 80), agreement: ModelAgreement(low: 0, high: 70)) == .uncertain)
        #expect(GoingCheck.status(chosen: 82, night: night(jotr, sky, score: 80, basis: .usual), agreement: nil) == .uncertain)
        #expect(GoingCheck.status(chosen: 82, night: night(jotr, sky, score: 50), agreement: nil) == .worse)
    }

    // MARK: The better choice

    @Test func alternativeIsClearlyBetterOpenAndNear() throws {
        let jotr = try park("jotr"), deva = try park("deva")
        let friday = try sky(jotr, "2026-10-23"), saturday = try sky(jotr, "2026-10-24")
        let shown = night(jotr, friday, score: 50)
        let same = [night(jotr, saturday, score: 72)]
        let near = [(night: night(deva, try sky(deva, "2026-10-23"), score: 72), meters: 200_000.0, closed: false)]
        // Equal scores: the same place first.
        #expect(GoingCheck.alternative(to: shown, sameplace: same, nearby: near)?.meters == nil)
        // A higher score elsewhere wins; a closed place never does.
        let better = [(night: night(deva, try sky(deva, "2026-10-23"), score: 80), meters: 120_000.0, closed: false)]
        #expect(GoingCheck.alternative(to: shown, sameplace: same, nearby: better)?.night.park.id == "deva")
        let closed = [(night: night(deva, try sky(deva, "2026-10-23"), score: 95), meters: 120_000.0, closed: true)]
        #expect(GoingCheck.alternative(to: shown, sameplace: same, nearby: closed)?.night.park.id == "jotr")
        // Not 10 better, or not Good: nothing.
        #expect(GoingCheck.alternative(to: shown, sameplace: [night(jotr, saturday, score: 58)], nearby: []) == nil)
        #expect(GoingCheck.alternative(to: night(jotr, friday, score: 70), sameplace: [night(jotr, saturday, score: 75)], nearby: []) == nil)
    }
    @Test func summarySaysNowThenWhyThenTheChoice() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-10-23")
        let going = GoingNight(parkID: "jotr", night: sky.evening, chosenScore: 82, chosenAt: .now)
        let fallen = night(jotr, sky, score: 48, limit: .clouds(48))
        let better = GoingCheck.Alternative(night: night(jotr, try self.sky(jotr, "2026-10-24"), score: 86), meters: nil)
        let words = GoingCheck.summary(going, night: fallen, alternative: better)
        #expect(words.hasPrefix("Now 48, Fair, down from 82 when you chose it."))
        #expect(words.contains("Clouds limit this night to 48."))
        #expect(words.hasSuffix("is 86 there."))
    }

    // MARK: Leaving and being ready

    @Test func leaveByWorksBackFromSunset() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-10-24")
        let sunset = try #require(sky.sunset)
        #expect(LeaveBy.time(sky: sky, driveMinutes: 195) == sunset.addingTimeInterval(-195*60))
        #expect(LeaveBy.time(sky: sky, driveMinutes: nil) == nil)
        let here = try #require(LeaveBy.line(park: jotr, sky: sky, driveMinutes: 195, deviceZone: jotr.timeZone))
        #expect(here.hasPrefix("Leave by ") && here.contains("to arrive before sunset (\(jotr.time(sunset)))."))
        #expect(!here.contains("your time"))
        // From another time zone, the person's own clock too.
        let eastern = try #require(TimeZone(identifier: "America/New_York"))
        let away = try #require(LeaveBy.line(park: jotr, sky: sky, driveMinutes: 195, deviceZone: eastern))
        #expect(away.contains("your time."))
        #expect(LeaveBy.drive(195).contains("3") && LeaveBy.drive(195).contains("15"))
    }
    @Test func offlineLineSaysWhatIsKeptAndHowOld() throws {
        let jotr = try park("jotr"), now = Date()
        let fresh = OfflineReady.line(park: jotr, forecast: now.addingTimeInterval(-3600), alerts: now.addingTimeInterval(-1800), parkServicePlace: true, now: now)
        #expect(fresh.contains("park alerts from") && !fresh.contains("Refresh before"))
        let old = OfflineReady.line(park: jotr, forecast: now.addingTimeInterval(-8*3600), alerts: nil, parkServicePlace: true, now: now)
        #expect(!old.contains("park alerts") && old.hasSuffix("Refresh before you lose signal."))
        #expect(OfflineReady.line(park: jotr, forecast: nil, alerts: nil, parkServicePlace: true, now: now).hasPrefix("No cloud forecast is saved"))
    }

    // MARK: Telling someone

    @Test func planNamesThePlaceTimesAndHelp() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-10-24")
        let spot = jotr.viewingSpots.first
        let message = TellSomeone.message(night: night(jotr, sky, score: 80), spot: spot, closure: "Geology tour road temporarily closed")
        #expect(message.contains(spot?.name ?? jotr.shortName))
        #expect(message.contains("https://maps.apple.com/?ll="))
        #expect(message.contains("I expect to be back by sunrise"))
        #expect(message.contains("Closure alert: Geology tour road temporarily closed."))
        #expect(message.contains("call 911"))
        let catalog = try TestData.catalog()
        let abroad = try #require(catalog.first { $0.countryCode != "US" })
        let away = TellSomeone.message(night: night(abroad, try self.sky(abroad, "2026-10-24"), score: 80), spot: nil, closure: nil)
        #expect(away.contains("local emergency number") && !away.contains("911"))
    }
    @Test func goingPlacesAreFollowed() {
        let ids = SavedSkySync.followedIDs(saved: ["jotr"], home: "chis", tonight: nil, watch: [], widgets: [], going: ["deva", "jotr"])
        #expect(ids.contains("deva"))
        #expect(ids.filter { $0 == "jotr" }.count == 1)
    }
}
