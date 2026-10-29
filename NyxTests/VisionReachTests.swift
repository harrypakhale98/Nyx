import Foundation
import Testing
@testable import Nyx

/// Vision Pro's reach in 1.4: the planner's darkest of the next 30 nights (`NightsAhead`; 14 at first) and
/// the widget's large face, the Moon over the coming week (`MoonWeek`). Both are shared code the
/// visionOS targets compile, tested here against the iPhone's engine.
struct VisionReachTests {
    private static func park(_ id: String) throws -> Park { try #require(try ParkData.load().first { $0.id == id }) }
    private static func date(_ iso: String) throws -> Date { try Date(iso, strategy: .iso8601) }
    /// Constant cover, issued at `issued`: sixteen days of hours from the day before, like Open-Meteo's.
    private static func forecast(cover: Double, issued: Date) -> Forecast {
        let start = (issued.timeIntervalSince1970/3600).rounded(.down)*3600-86400
        let times = (0..<384).map { start+Double($0)*3600 }
        return Forecast(updated: issued, times: times, clouds: times.map { _ in cover })
    }

    // MARK: Darkest of the next 30 nights

    /// Vision Pro looks as far ahead as the iPhone's best night (`NightPlanner.horizon`), so a park's
    /// darkest night is the same night on both; every older name for that window is the same window.
    @Test func reachIsTheIPhonesBestNightHorizon() throws {
        let park = try Self.park("jotr"), now = try Self.date("2026-10-10T21:00:00Z")
        let ahead = NightsAhead(park: park, planner: NightPlanner(forecasts: [:]), now: now, limit: .max)
        #expect(ahead.picks.count == NightPlanner.horizon)
    }
    /// The picks are `NightPlanner.bestNights` over tonight and the next 29 nights, in its
    /// order, and each offset steps the planner to exactly that night.
    @Test func picksAreThePlannersBestNightsWithTheirOffsets() throws {
        let park = try Self.park("jotr"), now = try Self.date("2026-10-10T21:00:00Z")
        let planner = NightPlanner(forecasts: [park.id: Self.forecast(cover: 30, issued: now)])
        let ahead = NightsAhead(park: park, planner: planner, now: now)
        let expected = planner.bestNights([park], from: now, count: NightPlanner.horizon, now: now, limit: 3)
        #expect(ahead.picks.count == 3)
        #expect(ahead.picks.map(\.id) == expected.map(\.id))
        #expect(ahead.picks.map(\.night.score.value) == expected.map(\.score.value))
        let tonight = park.currentNight(at: now)
        for pick in ahead.picks {
            #expect((0..<NightPlanner.horizon).contains(pick.offset))
            // The planner's own night for that offset (`VisionModel.night(for:)`) is the pick's night.
            #expect(park.date(tonight, addingDays: pick.offset) == pick.night.id)
        }
        // Best first, by the one ranking every surface uses.
        for (a, b) in zip(ahead.picks, ahead.picks.dropFirst()) { #expect(!NightPlanner.better(b.night, a.night)) }
    }
    /// Without any forecast, every night rests on the usual clouds, so the first pick is the one
    /// explained beneath ("No cloud forecast yet. …"), and none is presented as forecast.
    @Test func withoutAForecastEveryPickIsAnEstimate() throws {
        let park = try Self.park("arch"), now = try Self.date("2026-11-03T20:00:00Z")
        let ahead = NightsAhead(park: park, planner: NightPlanner(forecasts: [:]), now: now)
        #expect(!ahead.picks.isEmpty)
        #expect(ahead.picks.allSatisfy { $0.night.basis == .usual && $0.night.compactBandLabel == String(localized: "Estimate") })
        #expect(ahead.firstEstimate?.id == ahead.picks.first?.id)
    }
    /// With a full forecast tonight, the first night not fully forecast is the one explained; a
    /// forecast night is never called an estimate.
    @Test func firstEstimateSkipsForecastNights() throws {
        let park = try Self.park("jotr"), now = try Self.date("2026-10-10T21:00:00Z")
        let ahead = NightsAhead(park: park, planner: NightPlanner(forecasts: [park.id: Self.forecast(cover: 0, issued: now)]), now: now, limit: 14)
        #expect(ahead.picks.count == 14)
        let first = try #require(ahead.firstEstimate)
        #expect(!first.night.score.hasForecast)
        let before = ahead.picks.prefix { $0.id != first.id }
        #expect(before.allSatisfy { $0.night.score.hasForecast })
    }
    /// Denali in June has no true darkness on any of the nights: still ranked, and said once.
    @Test func noTrueDarknessInReachIsSaid() throws {
        let denali = try Self.park("dena"), june = try Self.date("2026-06-21T21:00:00Z")
        #expect(NightsAhead(park: denali, planner: NightPlanner(forecasts: [:]), now: june).noDarkness)
        let arches = try Self.park("arch")
        #expect(!NightsAhead(park: arches, planner: NightPlanner(forecasts: [:]), now: june).noDarkness)
    }
    /// Offsets count park-local nights, across the change from daylight time and never below zero.
    @Test func offsetsCountParkNights() throws {
        let park = try Self.park("grsm")
        let tonight = park.evening(try Self.date("2026-10-30T18:00:00Z"))
        #expect(NightsAhead.offset(of: tonight, after: tonight, in: park) == 0)
        #expect(NightsAhead.offset(of: park.date(tonight, addingDays: 5), after: tonight, in: park) == 5)
        #expect(NightsAhead.offset(of: park.date(tonight, addingDays: -2), after: tonight, in: park) == 0)
    }

    // MARK: The Moon over the coming week

    private static func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }
    /// Seven nights after tonight, each at 10 PM local on consecutive days, across a clock change.
    @Test func weekIsTheNextSevenEvenings() throws {
        let calendar = try Self.calendar("America/Denver")
        // 2 PM on Friday, October 30, 2026 in Denver; clocks go back on Sunday, November 1.
        let week = MoonWeek(at: try Self.date("2026-10-30T20:00:00Z"), calendar: calendar)
        #expect(week.nights.count == 7)
        for (index, night) in week.nights.enumerated() {
            let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: night.date)
            #expect(parts.hour == MoonWeek.hour && parts.minute == 0)
            #expect(parts.month == 10 ? parts.day == 31 : parts.day == index)
        }
    }
    /// Before 6 AM it is still last night, so the week starts from tonight's evening, not tomorrow's.
    @Test func earlyMorningIsStillLastNight() throws {
        let calendar = try Self.calendar("America/Los_Angeles")
        // 2 AM on October 11 in Los Angeles: still the night of October 10.
        let late = try Self.date("2026-10-11T09:00:00Z"), evening = try Self.date("2026-10-11T03:00:00Z")
        #expect(MoonWeek.tonight(at: late, calendar: calendar) == MoonWeek.tonight(at: evening, calendar: calendar))
        #expect(calendar.component(.day, from: MoonWeek(at: late, calendar: calendar).nights[0].date) == 11)
        // 7 AM is a new day.
        let morning = try Self.date("2026-10-11T14:00:00Z")
        #expect(calendar.component(.day, from: MoonWeek(at: morning, calendar: calendar).nights[0].date) == 12)
    }
    /// Each night's lit fraction is the engine's, and the next new moon is a true new moon: after
    /// the date, the Moon dark there, and one lunar month before the one after it.
    @Test func phasesAndTheNextNewMoon() throws {
        let engine = AstronomyEngine(), calendar = try Self.calendar("America/Denver")
        let now = try Self.date("2026-10-14T03:00:00Z")
        let week = MoonWeek(at: now, calendar: calendar)
        for night in week.nights {
            #expect(abs(night.illumination-engine.moonPhase(at: night.date).illumination) < 1e-9)
            #expect(night.waxing == engine.moonPhase(at: night.date).waxing)
        }
        #expect(week.nextNewMoon > now)
        #expect(engine.moonPhase(at: week.nextNewMoon).illumination < 0.001)
        let following = MoonWeek.newMoon(after: week.nextNewMoon.addingTimeInterval(86400))
        #expect(abs(following.timeIntervalSince(week.nextNewMoon)/86400-AstronomyEngine.synodicDays) < 0.6)
    }
    /// The new moon's night is ringed only when it falls within the week, on the evening nearest it.
    @Test func newMoonNightIsMarkedWithinTheWeek() throws {
        let calendar = try Self.calendar("America/Denver")
        let start = try Self.date("2026-10-14T03:00:00Z")
        let newMoon = MoonWeek.newMoon(after: start)
        let before = MoonWeek(at: newMoon.addingTimeInterval(-3*86400), calendar: calendar)
        let index = try #require(before.newMoonNight)
        #expect(abs(before.nights[index].date.timeIntervalSince(newMoon)) <= 12*3600)
        #expect(before.nights[index].illumination < 0.02)
        // Just after a new moon, the next one is a month away: nothing in the week is ringed.
        #expect(MoonWeek(at: newMoon.addingTimeInterval(86400), calendar: calendar).newMoonNight == nil)
    }
}
