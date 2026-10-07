import Foundation
import Testing
@testable import Nyx

/// The bundled cloud climatology (ERA5 2015–2024) and the ranking that uses it beyond the forecast.
struct CloudClimateTests {
    let parks = (try? ParkData.load()) ?? []
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    func evening(_ park: Park, _ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    @Test func everyParkHasTwelvePlausibleMonths() throws {
        let climate = try #require(CloudClimate.load())
        #expect(parks.count == 63)
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
    @Test func sentenceSaysHowOftenNightsAreClear() {
        #expect(CloudClimate.Typical(month: 11, cloud: 12, clear: 78).sentence(monthName: "November") == "About 8 in 10 November nights here are mostly clear.")
        #expect(CloudClimate.Typical(month: 1, cloud: 90, clear: 3).sentence(monthName: "January") == "January nights here are rarely clear.")
        #expect(CloudClimate.Typical(month: 9, cloud: 2, clear: 97).sentence(monthName: "September") == "September nights here are nearly always clear.")
    }
    /// Beyond the forecast a night ranks with its park's usual clouds: never as if clear, and a
    /// cloudy-climate park never ties a desert on Moon and darkness alone.
    @Test func estimatesRankWithUsualClouds() throws {
        let jotr = try park("jotr"), engine = AstronomyEngine(), scoring = ScoreEngine()
        let sky = engine.conditions(for: jotr, on: try evening(jotr, 2027, 11, 6))
        let estimate = Night(park: jotr, sky: sky, score: scoring.score(sky: sky, bortle: jotr.bortleEstimate, cloudCover: nil), cloudCover: nil, forecastUpdated: nil)
        let clearNovember = CloudClimate(parks: ["jotr": .init(cloud: Array(repeating: 10, count: 12), clear: Array(repeating: 85, count: 12))])
        let cloudyNovember = CloudClimate(parks: ["jotr": .init(cloud: Array(repeating: 80, count: 12), clear: Array(repeating: 10, count: 12))])
        #expect(estimate.rankScore(clearNovember) == scoring.score(sky: sky, bortle: jotr.bortleEstimate, cloudCover: 10).value)
        #expect(estimate.rankScore(cloudyNovember) == scoring.score(sky: sky, bortle: jotr.bortleEstimate, cloudCover: 80).value)
        #expect(estimate.rankScore(cloudyNovember) < estimate.rankScore(clearNovember))
        // A night with a forecast ranks by its own score, whatever the climate.
        let forecast = Night(park: jotr, sky: sky, score: scoring.score(sky: sky, bortle: jotr.bortleEstimate, cloudCover: 20), cloudCover: 20, forecastUpdated: .now)
        #expect(forecast.rankScore(cloudyNovember) == forecast.score.value)
        // No climate data: the score itself.
        #expect(estimate.rankScore(CloudClimate(parks: [:])) == estimate.score.value)
    }
    /// The real table: the same new-moon night beyond the forecast ranks lower at Olympic than at
    /// Death Valley, by more than their Bortle estimates alone explain.
    @Test func cloudyParksRankBelowDesertsBeyondTheForecast() throws {
        let deva = try park("deva"), olym = try park("olym"), planner = NightPlanner(forecasts: [:])
        let a = planner.night(deva, on: try evening(deva, 2027, 11, 6), now: .now)
        let b = planner.night(olym, on: try evening(olym, 2027, 11, 6), now: .now)
        #expect(!a.score.hasForecast && !b.score.hasForecast)
        #expect(a.score.value - b.score.value < a.rankScore - b.rankScore)
        #expect(NightPlanner.best([b, a])?.park.id == "deva")
        #expect(b.typicalClouds?.contains("November") == true)
    }
}
