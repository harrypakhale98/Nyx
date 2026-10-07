import Foundation
import Testing
@testable import Nyx

/// The watch's own logic: Automatic colours, the dark-adaptation clock, the next dark moment, the
/// Moon right now and the age of the clouds.
struct WristSkyTests {
    func park(_ id: String) throws -> Park { try #require(try ParkData.load().first { $0.id == id }) }
    func local(_ park: Park, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try #require(park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }
    private let engine = AstronomyEngine()

    @Test func explicitPalettesNeverChangeAndMatchIPhoneDefaultsToRed() throws {
        let jotr = try park("jotr")
        let noon = try local(jotr, 2026, 10, 7, 12), midnight = try local(jotr, 2026, 10, 8, 0)
        for date in [noon, midnight] {
            #expect(PaletteChoice.red.nightVision(phone: false, park: jotr, at: date))
            #expect(!PaletteChoice.standard.nightVision(phone: true, park: jotr, at: date))
            #expect(PaletteChoice.phone.nightVision(phone: false, park: jotr, at: date) == false)
            // Before the first sync, red: at a dark site that is the safe default.
            #expect(PaletteChoice.phone.nightVision(phone: nil, park: nil, at: date))
        }
        #expect(PaletteChoice.allCases.first == .automatic)
    }

    @Test func automaticIsRedFromCivilDuskToCivilDawnAtThePark() throws {
        let jotr = try park("jotr")
        #expect(!PaletteChoice.automatic.nightVision(phone: true, park: jotr, at: try local(jotr, 2026, 10, 7, 12)))
        #expect(PaletteChoice.automatic.nightVision(phone: false, park: jotr, at: try local(jotr, 2026, 10, 8, 0)))
        // The switch is the Sun crossing −6°: civil dusk and civil dawn, to the minute.
        let changes = WristSky.paletteChanges(at: jotr, from: try local(jotr, 2026, 10, 7, 12), to: try local(jotr, 2026, 10, 8, 12))
        #expect(changes.count == 2)
        for change in changes {
            #expect(abs(engine.solarAltitude(at: change, park: jotr) + 6) < 0.05)
            #expect(WristSky.isCivilNight(at: jotr, change.addingTimeInterval(-120)) != WristSky.isCivilNight(at: jotr, change.addingTimeInterval(120)))
        }
        // Civil dusk falls after sunset and before true darkness.
        let sky = engine.conditions(for: jotr, on: try local(jotr, 2026, 10, 7, 12))
        let dusk = try #require(changes.first), sunset = try #require(sky.sunset), dark = try #require(sky.darkStart)
        #expect(dusk > sunset && dusk < dark)
        // Under the June midnight sun at Denali the Sun never drops 6°: never red. Gates of the
        // Arctic in December is red at midnight, and not at noon (the Sun is only just below the horizon).
        let dena = try park("dena"), gaar = try park("gaar")
        #expect(!PaletteChoice.automatic.nightVision(phone: nil, park: dena, at: try local(dena, 2026, 6, 21, 1)))
        #expect(PaletteChoice.automatic.nightVision(phone: nil, park: gaar, at: try local(gaar, 2026, 12, 21, 0)))
        #expect(!PaletteChoice.automatic.nightVision(phone: nil, park: gaar, at: try local(gaar, 2026, 12, 21, 13)))
        // No park chosen yet: the watch's own clock, red from 6 PM to 7 AM.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jotr.timeZone
        #expect(PaletteChoice.automatic.nightVision(phone: nil, park: nil, at: try local(jotr, 2026, 10, 7, 23), calendar: calendar))
        #expect(!PaletteChoice.automatic.nightVision(phone: nil, park: nil, at: try local(jotr, 2026, 10, 7, 12), calendar: calendar))
    }

    @Test func adaptationClockCountsThirtyMinutesAndRemindsAt25And30() {
        let start = Date(timeIntervalSince1970: 1_791_158_400)
        let clock = AdaptationClock(start: start)
        #expect(clock.elapsedMinutes(at: start) == 0)
        #expect(clock.elapsedMinutes(at: start.addingTimeInterval(12*60+30)) == 12)
        #expect(clock.progress(at: start.addingTimeInterval(15*60)) == 0.5)
        #expect(!clock.isAdapted(at: start.addingTimeInterval(29*60+59)))
        #expect(clock.isAdapted(at: start.addingTimeInterval(30*60)))
        #expect(clock.elapsedMinutes(at: start.addingTimeInterval(45*60)) == 30 && clock.progress(at: start.addingTimeInterval(45*60)) == 1)
        // A clock read before its start (a changed clock) shows nothing elapsed.
        #expect(clock.elapsed(at: start.addingTimeInterval(-30)) == 0)
        let reminders = clock.reminders(after: start)
        #expect(reminders.map(\.minutes) == [25, 30])
        #expect(reminders.map(\.date) == [start.addingTimeInterval(25*60), start.addingTimeInterval(30*60)])
        #expect(clock.reminders(after: start.addingTimeInterval(26*60)).map(\.minutes) == [30])
        #expect(clock.reminders(after: start.addingTimeInterval(31*60)).isEmpty)
        // Forgotten the next time after three hours, or when it would start in the future.
        #expect(!clock.isStale(at: start.addingTimeInterval(3*3600-1)))
        #expect(clock.isStale(at: start.addingTimeInterval(3*3600)))
        #expect(clock.isStale(at: start.addingTimeInterval(-120)))
    }

    @Test func nextDarkIsTheNextMoonFreeTrueDarkness() throws {
        let jotr = try park("jotr")
        var kinds: Set<String> = []
        for day in 1...30 {
            for hour in [17, 22, 2] {
                let now = try local(jotr, 2026, 10, hour == 2 ? day+1 : day, hour)
                let moment = DarkMoment.next(at: jotr, now: now)
                func trulyDark(_ date: Date) -> Bool {
                    engine.solarAltitude(at: date, park: jotr) < -18 && engine.lunarAltitude(at: date, park: jotr) + 0.833 < 0
                }
                switch moment {
                case .begins(let date, let moonset):
                    kinds.insert(moonset ? "moonset" : "darkness")
                    #expect(date > now, "\(day) \(hour)")
                    #expect(trulyDark(date.addingTimeInterval(120)), "\(day) \(hour)")
                    #expect(!trulyDark(date.addingTimeInterval(-120)), "\(day) \(hour)")
                    // Opened by the Moon setting means the Sun was already 18° down.
                    if moonset { #expect(engine.solarAltitude(at: date.addingTimeInterval(-120), park: jotr) < -18) }
                    #expect(moment.target(at: now) == date)
                case .darkNow(let until, let moonrise):
                    kinds.insert("now")
                    #expect(trulyDark(now) && until > now, "\(day) \(hour)")
                    #expect(!trulyDark(until.addingTimeInterval(120)))
                    if moonrise { #expect(engine.lunarAltitude(at: until.addingTimeInterval(120), park: jotr) + 0.833 > 0) }
                case .moonlit(let from, let to):
                    kinds.insert("moonlit")
                    #expect(to > now && from < to)
                    #expect(engine.lunarAltitude(at: from.addingTimeInterval(to.timeIntervalSince(from)/2), park: jotr) + 0.833 > 0)
                case .none:
                    Issue.record("Joshua Tree always has true darkness in October (\(day) \(hour))")
                }
            }
        }
        // October 2026 holds every kind of answer: a new moon, a full moon and the quarters between.
        #expect(kinds == ["moonset", "darkness", "now", "moonlit"])
        // Under the June midnight sun there is nothing to count down to, and the watch says so.
        let dena = try park("dena")
        #expect(DarkMoment.next(at: dena, now: try local(dena, 2026, 6, 21, 18)) == .none)
        #expect(DarkMoment.none.target(at: .now) == nil)
    }

    @Test func moonNowIsUpExactlyWhenItsNextEventIsASet() throws {
        for id in ["jotr", "npsa", "gaar"] {
            let park = try park(id)
            let start = try local(park, 2026, 10, 1, 0)
            for step in 0..<60 {
                let now = start.addingTimeInterval(Double(step)*7*3600)
                let moon = MoonNow(at: now, park: park)
                #expect(moon.percent == Int((engine.moonPhase(at: now).illumination*100).rounded()))
                // Above the Arctic Circle the Moon can stay up, or down, for more than a day.
                guard let next = moon.next else { #expect(id == "gaar", "\(id) \(step)"); continue }
                #expect(next.date > now && next.date < now.addingTimeInterval(2*86400))
                // The next crossing from above the horizon is a set, from below a rise.
                #expect(moon.isUp == !next.rises, "\(id) \(step)")
                // And it is the first: nothing crosses in between.
                let midway = now.addingTimeInterval(next.date.timeIntervalSince(now)/2)
                #expect((engine.lunarAltitude(at: midway, park: park) + 0.833 > 0) == moon.isUp, "\(id) \(step)")
            }
        }
        // Without a park, the phase alone.
        let none = MoonNow(at: .now, park: nil)
        #expect(none.isUp == nil && none.next == nil)
    }

    @Test func cloudSourceSaysHowOldTheCloudsAreAndWhenTheyExpired() throws {
        let jotr = try park("jotr"), yell = try park("yell")
        let updated = Date(timeIntervalSince1970: 1_791_158_400)
        let times = (0..<72).map { updated.timeIntervalSince1970 + Double($0)*3600 }
        let forecast = Forecast(updated: updated, times: times, clouds: times.map { _ in 40 })
        let context = WatchContext.make(savedParkIDs: ["deva"], homeParkID: "jotr", nightVision: true, forecasts: ["jotr": forecast], now: updated)
        #expect(CloudSource.of(context: nil, park: jotr, now: updated) == .unsynced)
        #expect(CloudSource.unsynced.line(for: jotr) == nil)
        let fresh = CloudSource.of(context: context, park: jotr, now: updated.addingTimeInterval(35*3600))
        #expect(fresh == .fresh(updated) && !fresh.isStale)
        #expect(fresh.line(for: jotr)?.hasPrefix("Clouds from") == true)
        let expired = CloudSource.of(context: context, park: jotr, now: updated.addingTimeInterval(36*3600))
        #expect(expired == .expired(updated) && expired.isStale)
        #expect(expired.line(for: jotr) == "No recent forecast. Open Nyx on iPhone to refresh.")
        // The same limit the score uses: clouds stop counting exactly when the watch calls them old.
        let window = (updated.addingTimeInterval(40*3600), updated.addingTimeInterval(44*3600))
        #expect(forecast.mean(from: window.0, to: window.1, now: updated.addingTimeInterval(CloudSource.lifetime-1)) != nil)
        #expect(forecast.mean(from: window.0, to: window.1, now: updated.addingTimeInterval(CloudSource.lifetime)) == nil)
        // A saved park whose clouds did not travel can be refreshed; a park never saved cannot.
        #expect(CloudSource.of(context: context, park: try park("deva"), now: updated) == .missing(followed: true))
        #expect(CloudSource.of(context: context, park: yell, now: updated) == .missing(followed: false))
        #expect(CloudSource.missing(followed: false).line(for: yell) == "Save this park on iPhone for its clouds.")
        #expect(!CloudSource.missing(followed: false).isStale)
    }
}
