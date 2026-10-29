import Foundation
import Testing
@testable import Nyx

/// The words the wrist and the widgets share with the iPhone: the week's best night, a park's
/// short name, the Moon during true darkness and the Moon right now.
struct WatchWordsTests {
    private let engine = AstronomyEngine()
    private static func phase(lit illumination: Double) -> MoonPhase { MoonPhase(fraction: acos(1-2*illumination)/(2*Double.pi)) }
    /// A week at `park` from October 1, 2026, each night given the score in `scores` (and `parts`
    /// points of moonlight, which break equal scores, `NightPlanner.better`).
    private func week(_ park: Park, _ scores: [Int], parts: [Double]? = nil) throws -> [Night] {
        let first = try #require(park.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)))
        return scores.enumerated().map { index, score in
            let sky = engine.conditions(for: park, on: park.date(first, addingDays: index))
            return Night(park: park, sky: sky, score: DarknessScore(value: score, moonPoints: parts?[index] ?? 30, cloudPoints: 20, bortlePoints: 16, lengthPoints: 10),
                         cloudCover: 5, forecastUpdated: first)
        }
    }

    // MARK: Best this week

    @Test func weekBestSaysTonightEveryNightOrTheDayAndScore() throws {
        let jotr = try park("jotr")
        #expect(WeekBest.label([]) == nil)
        #expect(try WeekBest.label(week(jotr, [88, 70, 60, 75, 80, 66, 71])) == "Best this week: tonight")
        // A single night is tonight's best, never "every night".
        #expect(try WeekBest.label(week(jotr, [42])) == "Best this week: tonight")
        // Usual clouds all week: no night to single out.
        #expect(try WeekBest.label(week(jotr, Array(repeating: 61, count: 7))) == "Best this week: every night")
        let later = try week(jotr, [60, 70, 82, 75, 80, 66, 71])
        let day = later[2].id.formatted(Date.FormatStyle(timeZone: jotr.timeZone).weekday(.abbreviated))
        #expect(WeekBest.label(later) == "Best this week: \(day) · 82")
        #expect(WeekBest.label(later) == WeekBest.label(try #require(NightPlanner.best(later)), first: later[0]))
    }
    /// Equal top scores name the night the iPhone's ranking puts first (here the larger sum of parts),
    /// not simply the earlier one.
    @Test func weekBestBreaksTiesByTheRanking() throws {
        let jotr = try park("jotr")
        let tied = try week(jotr, [60, 80, 70, 65, 80, 62, 61], parts: [30, 30, 30, 30, 34, 30, 30])
        let best = try #require(NightPlanner.best(tied))
        #expect(best.id == tied[4].id)
        let day = best.id.formatted(Date.FormatStyle(timeZone: jotr.timeZone).weekday(.abbreviated))
        #expect(WeekBest.label(tied) == "Best this week: \(day) · 80")
    }

    // MARK: Names

    @Test func americanSamoaIsShortenedOnEveryDevice() throws {
        #expect(Park.shortened("National Park of American Samoa") == "American Samoa")
        #expect(try park("npsa").shortName == "American Samoa")
        #expect(try park("jotr").shortName == "Joshua Tree")
        #expect(Park.shortened("Wrangell-St. Elias National Park & Preserve") == "Wrangell-St. Elias")
        #expect(Park.shortened("Constitution 1857 National Park") == "Constitution 1857 National Park")
        #expect(Park.spotPrefix == SavedSpots.prefix)
    }

    // MARK: The Moon

    /// The watch's Tonight Moon line is the iPhone's sentence without how much is lit (the line above
    /// says it): a thin Moon is "too thin to matter", whatever its hours.
    @Test func wristMoonLineFollowsTheSharedRule() throws {
        let jotr = try park("jotr")
        let first = try #require(jotr.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)))
        let moonlit = try #require((0..<60).lazy.map { self.engine.conditions(for: jotr, on: jotr.date(first, addingDays: $0)) }.first { $0.darkHours > 3 && $0.moonDownPercent == 0 })
        #expect(moonlit.moonSentence(park: jotr, withLit: false) == "Moon up all through true darkness.")
        #expect(moonlit.moonShort(park: jotr) == "Dark, Moon up")
        let thin = SkyConditions(evening: moonlit.evening, end: moonlit.end, sunset: moonlit.sunset, sunrise: moonlit.sunrise, civilDusk: moonlit.civilDusk,
                                 nauticalDusk: moonlit.nauticalDusk, darkStart: moonlit.darkStart, darkEnd: moonlit.darkEnd, state: moonlit.state,
                                 moon: Self.phase(lit: 0.03), moonrise: moonlit.moonrise, moonset: moonlit.moonset,
                                 moonBelowFraction: moonlit.moonBelowFraction, darkHours: moonlit.darkHours, moonlight: moonlit.moonlight, lowestSun: moonlit.lowestSun)
        #expect(thin.moonSentence(park: jotr, withLit: false) == "Moon too thin to matter.")
    }
    /// The iPhone's Moon widget and the watch's Moon complication share one set of words.
    @Test func moonWordsAreOneBuilder() throws {
        let jotr = try park("jotr")
        let now = Date(timeIntervalSince1970: 1_791_158_400)
        let moon = MoonNow(at: now, park: jotr), next = try #require(moon.next), up = moon.isUp == true
        let text = MoonRectangleText(moon: moon, park: jotr, locale: Locale(identifier: "en_US"))
        #expect(text.litNow == "\(moon.phase.percentLit)% lit · \(up ? "up" : "down") now")
        let at = jotr.time(next.date)
        #expect(text.spoken == "\(moon.phase.spoken). The Moon is \(up ? "up" : "down"). \(next.rises ? "Moonrise" : "Moonset") at \(at), Joshua Tree.")
        #expect(text.glance(time: at) == "\(moon.phase.percentLit)% · \(next.rises ? "rises" : "sets") \(at)")
        // A watch writes the park's zone into the visible time; VoiceOver keeps the park's time.
        let zoned = MoonRectangleText(moon: moon, park: jotr, locale: Locale(identifier: "en_US")) { _, _ in "8:12 PM PDT" }
        #expect(zoned.shortEvent == (next.rises ? "Rises 8:12 PM PDT" : "Sets 8:12 PM PDT") && zoned.spoken == text.spoken)
        // Without a park: the phase and its light, no up or down, no event.
        let anywhere = MoonRectangleText(moon: MoonNow(at: now, park: nil), park: nil, locale: Locale(identifier: "en_US"))
        #expect(anywhere.litNow == anywhere.lit && anywhere.event == nil && anywhere.glance(time: at) == anywhere.lit)
        #expect(anywhere.spoken == "\(moon.phase.spoken).")
    }

    // MARK: Clouds

    @Test func aCloudLineExplainsItselfUnlessFreshOrUnsynced() {
        let now = Date(timeIntervalSince1970: 1_791_158_400)
        #expect(!CloudSource.unsynced.explainsItself && !CloudSource.fresh(now).explainsItself)
        for source in [CloudSource.expired(now), .missing(followed: true), .missing(followed: false), .dropped, .wanted, .spotsOff] {
            #expect(source.explainsItself, "\(source)")
        }
    }
}
