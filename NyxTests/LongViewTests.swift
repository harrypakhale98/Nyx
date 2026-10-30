import Foundation
import Testing
@testable import Nyx

/// The long view: weekends around new moons, the Milky Way's season, and the calendar file.
@Suite struct LongViewTests {
    let engine = AstronomyEngine()
    let start = Date(timeIntervalSince1970: 1_792_663_200) // 2026-10-22, 10:00 UTC
    func night(_ park: Park, _ evening: Date, score: Int) -> Night {
        Night(park: park, sky: engine.conditions(for: park, on: evening), score: DarknessScore(value: score, moonPoints: 30, cloudPoints: 20, bortlePoints: 16, lengthPoints: 10, basis: .usual), cloudCover: nil, forecastUpdated: nil)
    }

    @Test func sixNewMoonsAMonthApart() {
        let moons = DarkWeekends.newMoons(after: start)
        #expect(moons.count == 6)
        #expect(moons.first.map { $0 > start } == true)
        for (a, b) in zip(moons, moons.dropFirst()) {
            let days = b.timeIntervalSince(a)/86400
            #expect(days > 29 && days < 30.1)
        }
        // Each one is a new moon: almost none of the disc lit.
        #expect(moons.allSatisfy { engine.moonPhase(at: $0).illumination < 0.01 })
    }
    @Test func weekendsAreFridaysNearTheNewMoon() throws {
        let jotr = try park("jotr"), moon = try #require(DarkWeekends.newMoons(after: start, count: 1).first)
        var satSun = Calendar(identifier: .gregorian); satSun.locale = Locale(identifier: "en_US")
        let fridays = DarkWeekends.firstNights(around: moon, park: jotr, calendar: satSun)
        #expect(!fridays.isEmpty)
        #expect(fridays.allSatisfy { jotr.calendar.component(.weekday, from: $0) == 6 })
        #expect(fridays.allSatisfy { abs($0.timeIntervalSince(jotr.evening(moon))) <= Double(DarkWeekends.reach)*86400+3600 })
    }
    @Test func weekendsFollowTheRegionsDaysOff() throws {
        // Where the weekend is Friday and Saturday, its nights are Thursday and Friday.
        let jotr = try park("jotr"), moon = try #require(DarkWeekends.newMoons(after: start, count: 1).first)
        var friSat = Calendar(identifier: .gregorian); friSat.locale = Locale(identifier: "he_IL")
        let thursdays = DarkWeekends.firstNights(around: moon, park: jotr, calendar: friSat)
        #expect(!thursdays.isEmpty)
        #expect(thursdays.allSatisfy { jotr.calendar.component(.weekday, from: $0) == 5 })
    }
    @Test func planPicksTheBestWeekendAndSkipsPastOnes() throws {
        let jotr = try park("jotr"), moons = DarkWeekends.newMoons(after: start, count: 2)
        var satSun = Calendar(identifier: .gregorian); satSun.locale = Locale(identifier: "en_US")
        // Scores rise through the days, so the later weekend near a moon wins when there are two.
        let first = jotr.evening(start)
        let score = { (evening: Date) in 50+Int((evening.timeIntervalSince(first)/86400).rounded()) % 40 }
        let plan = DarkWeekends.plan(park: jotr, newMoons: moons, tonight: first, closure: nil, calendar: satSun) { night(jotr, $0, score: score($0)) }
        #expect(plan.count == moons.count)
        for weekend in plan {
            #expect(jotr.calendar.component(.weekday, from: weekend.firstNight.id) == 6)
            #expect(weekend.secondNight.id == jotr.date(weekend.firstNight.id, addingDays: 1))
            #expect(weekend.firstNight.id >= first)
            // The weekend whose better night scores highest of those around its new moon.
            let rivals = DarkWeekends.firstNights(around: weekend.newMoon, park: jotr, calendar: satSun).filter { $0 >= first }
            #expect(weekend.best.score.value == rivals.map { max(score($0), score(jotr.date($0, addingDays: 1))) }.max())
        }
        #expect(DarkWeekends.spoken(plan[0]).contains("New moon"))
    }
    @Test func milkyWaySeasonByLatitude() throws {
        let jotr = try park("jotr")
        // In late October the core still clears an hour of true darkness at Joshua Tree, not for long.
        let autumn = try #require(CoreSeason.find(park: jotr, from: start))
        #expect(autumn.start <= autumn.end)
        #expect(autumn.sentence(jotr).hasPrefix("Milky Way season at \(jotr.shortName)"))
        // From December the next season lies ahead and opens in late winter.
        let winter = try #require(CoreSeason.find(park: jotr, from: Date(timeIntervalSince1970: 1_796_083_200))) // 2026-12-01
        #expect(!winter.now)
        let month = jotr.calendar.component(.month, from: winter.start)
        #expect((1...4).contains(month))
        #expect(winter.sentence(jotr).contains("opens about"))
        // Far north, the core never stands an hour in true darkness.
        #expect(CoreSeason.find(park: try park("gaar"), from: start) == nil)
    }
    /// Write-only access cannot see the calendar, so the nights added are kept here and never added twice.
    @MainActor @Test func calendarLedgerSkipsNightsAlreadyAdded() throws {
        let jotr = try park("jotr"), defaults = isolatedDefaults()
        let nights = [night(jotr, jotr.evening(start), score: 80), night(jotr, jotr.date(jotr.evening(start), addingDays: 1), score: 82)]
        #expect(CalendarWriter.fresh(nights, defaults: defaults).count == 2)
        defaults.set([CalendarWriter.id(nights[0])], forKey: CalendarWriter.key)
        #expect(CalendarWriter.fresh(nights, defaults: defaults).map(\.id) == [nights[1].id])
        #expect(CalendarWriter.id(nights[0]) == "jotr-\(jotr.isoDay(nights[0].id))")
    }
    @Test func calendarFileIsValidICalendar() throws {
        let jotr = try park("jotr")
        let nights = [night(jotr, jotr.evening(start), score: 80), night(jotr, jotr.date(jotr.evening(start), addingDays: 1), score: 82)]
        let text = DarkNightsCalendar(park: jotr, nights: nights).text(now: start)
        #expect(text.hasPrefix("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"))
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
        #expect(text.components(separatedBy: "BEGIN:VEVENT").count == 3)
        #expect(text.contains("DTSTAMP:20261022T100000Z"))
        #expect(text.contains("UID:nyx-jotr-"))
        // No physical line longer than 75 bytes.
        #expect(text.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        #expect(DarkNightsCalendar.escape("a, b; c\nd\\") == "a\\, b\\; c\\nd\\\\")
    }
}
