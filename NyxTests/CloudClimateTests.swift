import Foundation
import Testing
@testable import Nyx

/// The bundled cloud climatology (ERA5 2015–2024) and the ranking that uses it beyond the forecast.
struct CloudClimateTests {
    let parks = (try? ParkData.load()) ?? []
    /// 2027-10-01 00:00 UTC: weeks before the nights these tests score, whatever day they run.
    static let now = Date(timeIntervalSince1970: 1_822_348_800)
    func evening(_ park: Park, _ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    @Test func everyParkHasTwelvePlausibleMonths() throws {
        let climate = try #require(CloudClimate.load())
        #expect(!parks.isEmpty)
        for park in parks {
            let months = try #require(climate.parks[park.id], "\(park.id) missing")
            #expect(months.cloud.count == 12 && months.clear.count == 12)
            for (cloud, clear) in zip(months.cloud, months.clear) {
                let cloud = try #require(cloud), clear = try #require(clear)
                #expect((0...100).contains(cloud) && (0...100).contains(clear))
            }
        }
    }
    /// Known climates, as a sanity check on the build: the Mojave's autumn nights are mostly clear,
    /// the Olympic Peninsula's winter nights mostly overcast.
    @Test func knownClimatesLookRight() throws {
        let climate = try #require(CloudClimate.load())
        let deva = try park("deva"), olym = try park("olym")
        let desert = try #require(climate.typical(deva, on: try evening(deva, 2027, 10, 15)))
        let rainforest = try #require(climate.typical(olym, on: try evening(olym, 2027, 11, 15)))
        #expect(desert.clear >= 60 && desert.cloud <= 30)
        #expect(rainforest.clear <= 35 && rainforest.cloud >= 60)
        #expect(desert.month == 10 && rainforest.month == 11)
    }
    /// Denali and Kenai Fjords take their usual clouds where their forecast is asked for, the visitor
    /// centres, so the score reads the same sky either side of the forecast horizon: Denali's June
    /// nights by the park road are clearer than at the park's centre (81).
    @Test func forecastSitesKeepTheirOwnUsualClouds() throws {
        let climate = try #require(CloudClimate.load())
        let dena = try park("dena"), kefj = try park("kefj")
        #expect(climate.typical(dena, on: try evening(dena, 2027, 6, 15)) == CloudClimate.Typical(month: 6, cloud: 63, clear: 23))
        #expect(climate.typical(kefj, on: try evening(kefj, 2027, 10, 15)) == CloudClimate.Typical(month: 10, cloud: 81, clear: 9))
    }
    @Test func sentenceSaysHowOftenNightsAreClear() {
        #expect(CloudClimate.Typical(month: 11, cloud: 12, clear: 78).sentence(monthName: "November") == "About 8 in 10 November nights here are mostly clear.")
        #expect(CloudClimate.Typical(month: 1, cloud: 90, clear: 3).sentence(monthName: "January") == "January nights here are rarely clear.")
        #expect(CloudClimate.Typical(month: 9, cloud: 2, clear: 97).sentence(monthName: "September") == "Nearly every September night here is mostly clear.")
    }
    /// Beyond the forecast a night is scored with its park's usual clouds: never as if clear, and
    /// a cloudy-climate park never ties a desert. (Since score v2 the usual clouds are in the score
    /// itself, not only in the ranking.)
    @Test func estimatesScoreWithUsualClouds() throws {
        let jotr = try park("jotr"), engine = AstronomyEngine(), scoring = ScoreEngine()
        let sky = engine.conditions(for: jotr, on: try evening(jotr, 2027, 11, 6))
        let clearNovember = CloudClimate(parks: ["jotr": .init(cloud: Array(repeating: 10, count: 12), clear: Array(repeating: 85, count: 12))])
        let cloudyNovember = CloudClimate(parks: ["jotr": .init(cloud: Array(repeating: 80, count: 12), clear: Array(repeating: 10, count: 12))])
        let clear = NightPlanner.night(park: jotr, sky: sky, forecast: nil, detail: nil, now: Self.now, climate: clearNovember)
        let cloudy = NightPlanner.night(park: jotr, sky: sky, forecast: nil, detail: nil, now: Self.now, climate: cloudyNovember)
        #expect(clear.score.value == scoring.score(sky: sky, bortle: jotr.bortleEstimate, cloud: 10, basis: .usual, aerosol: nil).value)
        #expect(cloudy.score.value == scoring.score(sky: sky, bortle: jotr.bortleEstimate, cloud: 80, basis: .usual, aerosol: nil).value)
        #expect(cloudy.score.value < clear.score.value && cloudy.score.value <= ScoreEngine.cloudCap(80))
        #expect(clear.basis == .usual && clear.cloudCover == nil && clear.usualCloud == 10)
        // No climate data and no forecast: the guard keeps the old scaling, labelled as Moon and darkness only.
        let none = NightPlanner.night(park: jotr, sky: sky, forecast: nil, detail: nil, now: Self.now, climate: CloudClimate(parks: [:]))
        #expect(none.score.cloudPoints == nil && none.basisCaption()?.contains(String(localized: "This score counts the Moon and darkness only.")) == true)
    }
    /// Every park has twelve months of usual clouds, so the no-cloud guard never runs for real parks.
    @Test func everyParkHasUsualClouds() throws {
        for park in try ParkData.load() {
            for month in 1...12 {
                #expect(CloudClimate.shared.typical(park, on: try evening(park, 2027, month, 15)) != nil, "\(park.id) \(month)")
            }
        }
    }
    /// The real table: the same new-moon night beyond the forecast ranks lower at Olympic than at
    /// Death Valley, by more than their Bortle estimates alone explain.
    @Test func cloudyParksRankBelowDesertsBeyondTheForecast() throws {
        let deva = try park("deva"), olym = try park("olym"), planner = NightPlanner(forecasts: [:])
        let a = planner.night(deva, on: try evening(deva, 2027, 11, 6), now: Self.now)
        let b = planner.night(olym, on: try evening(olym, 2027, 11, 6), now: Self.now)
        #expect(!a.score.hasForecast && !b.score.hasForecast)
        #expect(a.score.value > b.score.value)
        #expect(NightPlanner.best([b, a])?.park.id == "deva")
        #expect(b.typicalClouds?.contains("November") == true)
    }
    /// Beyond the forecast the clouds cap binds on every Moon-dark night, so a night reads its usual
    /// cloud at the nearest new Moon: Joshua Tree's November 2026 nights up to the 23rd (full Moon on
    /// the 24th) share one cap, the new Moon on the 9th outranks the 35%-lit 2nd, the month's best
    /// night is a moonless one around the new Moon with its score (past ten hours of darkness the
    /// sums of a moonless night and the 13th's thin crescent tie, and the Moon-free hours decide), and
    /// the week from the 1st rings the 8th, not a crescent. The month and its share of clear nights stay the night's own.
    @Test func newMoonLeadsBeyondTheForecast() throws {
        let jotr = try park("jotr"), planner = NightPlanner(forecasts: [:])
        let now = try evening(jotr, 2026, 10, 20)
        let nights = try (1...30).map { planner.night(jotr, on: try evening(jotr, 2026, 11, $0), now: now) }
        let second = nights[1], ninth = nights[8]
        #expect(nights.allSatisfy { $0.basis == .usual && $0.beyondForecast })
        let shared = Set(nights[0...22].compactMap(\.usualCloud))
        #expect(shared.count == 1 && second.usualCloud == ninth.usualCloud)
        #expect(nights[23].usualCloud != ninth.usualCloud && Set(nights[23...].compactMap(\.usualCloud)).count == 1)
        #expect(NightPlanner.better(ninth, second))
        let best = try #require(NightPlanner.ranked(nights).first)
        #expect((6...10).contains(jotr.calendar.component(.day, from: best.id)) && best.score.value == ninth.score.value, "\(best.id)")
        #expect(NightPlanner.best(nights)?.id == best.id && TripPlanner.Tie(best).beats(TripPlanner.Tie(nights[12])) == true)
        #expect(NightPlanner.ranked(Array(nights[0...7])).first?.id == nights[7].id)
        // Death Valley's month names a moonless night too, never the 12th's crescent.
        let deva = try park("deva")
        let devaNights = try (1...30).map { planner.night(deva, on: try evening(deva, 2026, 11, $0), now: now) }
        let devaBest = try #require(NightPlanner.best(devaNights))
        #expect((6...11).contains(deva.calendar.component(.day, from: devaBest.id)), "\(devaBest.id)")
        #expect(second.usualClear == CloudClimate.shared.typical(jotr, on: second.id)?.clear && second.typicalClouds?.contains("November") == true)
    }
    /// The nearest new Moon, from either side of the month: 2026's fall on Oct 10, Nov 9 and Dec 9 (UTC).
    @Test func nearestNewMoonIsFoundFromEitherSide() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        func day(_ month: Int, _ day: Int) throws -> Date { try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))) }
        for (from, expected) in [((10, 20), (10, 10)), ((10, 30), (11, 9)), ((11, 9), (11, 9)), ((11, 21), (11, 9)), ((11, 28), (12, 9))] {
            let found = NightPlanner.newMoon(nearest: try day(from.0, from.1))
            #expect(calendar.component(.month, from: found) == expected.0 && calendar.component(.day, from: found) == expected.1, "\(from)")
            #expect(AstronomyEngine().moonPhase(at: found).isNew)
        }
    }
    /// Every evening of one lunation finds the same new Moon, to the local day, even where it falls
    /// minutes after a park's midnight: 00:04 on July 5, 2035 in Hawaiʻi.
    @Test func oneLunationFindsOneNewMoonDay() throws {
        let hale = try park("hale")
        for day in 0..<28 {
            let night = hale.date(try evening(hale, 2035, 6, 21), addingDays: day)
            #expect(hale.isoDay(NightPlanner.newMoon(nearest: night)) == "2035-07-05", "\(hale.isoDay(night))")
        }
    }
    /// Usual clouds ease between months instead of stepping on the 1st: the 15th keeps the month's
    /// own value, and October 31 and November 1 at Death Valley read within a point of each other.
    @Test func usualCloudsEaseBetweenMonths() throws {
        let climate = CloudClimate.shared
        let deva = try #require(try ParkData.load().first { $0.id == "deva" })
        let october = try #require(climate.typical(deva, on: try evening(deva, 2026, 10, 15)))
        let november = try #require(climate.typical(deva, on: try evening(deva, 2026, 11, 15)))
        let last = try #require(climate.typical(deva, on: try evening(deva, 2026, 10, 31))?.cloud)
        let first = try #require(climate.typical(deva, on: try evening(deva, 2026, 11, 1))?.cloud)
        #expect(abs(first-last) < 1)
        #expect(min(october.cloud, november.cloud) <= last && last <= max(october.cloud, november.cloud))
        // The month and its share of clear nights stay the month's own, for its sentence.
        #expect(climate.typical(deva, on: try evening(deva, 2026, 10, 31))?.month == 10)
        #expect(climate.typical(deva, on: try evening(deva, 2026, 10, 31))?.clear == october.clear)
    }
}
