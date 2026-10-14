import Foundation
import Testing
@testable import Nyx

/// One night reads the same everywhere: the park page, the calendar, the river, the widget, Siri
/// and the share card all take what the score rests on from the same words (`Night.basisLabel`,
/// `noForecastSentence`, `bandWithBasis`, `smokeSentence`).
@MainActor @Suite struct BasisWordingTests {
    let parks: [Park] = (try? ParkData.load()) ?? []
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    let now = Date(timeIntervalSince1970: 1_792_180_800) // 2026-10-16 20:00 UTC

    func night(_ park: Park, daysAhead: Int = 0, forecast: Forecast? = nil, detail: ForecastDetail? = nil, climate: CloudClimate = .shared) -> Night {
        let sky = AstronomyEngine().conditions(for: park, on: park.date(park.currentNight(at: now), addingDays: daysAhead))
        return NightPlanner.night(park: park, sky: sky, forecast: forecast, detail: detail, now: now, climate: climate)
    }
    /// Every surface's words for one night, in one list.
    func surfaces(_ night: Night) -> [String] {
        [night.basisCaption(typical: true) ?? "", night.spokenSummary(.calendar(event: nil)), night.spokenSummary(.river),
         night.spokenSummary(.widget), night.spokenSummary(.siriTonight(voiceOnly: false)), ShareCard(night: night).summary]
    }

    @Test func missingWithinTheHorizonIsUnavailableEverywhere() throws {
        let tonight = night(try park("jotr"))
        #expect(tonight.basis == .usual && !tonight.beyondForecast)
        #expect(tonight.basisLabel == "Cloud forecast unavailable" && tonight.noForecastSentence == "Cloud forecast unavailable.")
        for words in surfaces(tonight) {
            #expect(words.contains("Cloud forecast unavailable"), "\(words)")
            #expect(!words.contains("No cloud forecast yet"), "\(words)")
        }
        #expect(ShareCard(night: tonight).basis == "Cloud forecast unavailable · usual clouds for the month")
        #expect(tonight.bandWithBasis.hasSuffix(", usual clouds"))
    }
    @Test func beyondTheHorizonIsNotYetEverywhere() throws {
        let later = night(try park("jotr"), daysAhead: 12)
        #expect(later.basis == .usual && later.beyondForecast)
        for words in surfaces(later) {
            #expect(words.contains("No cloud forecast yet"), "\(words)")
            #expect(!words.contains("unavailable"), "\(words)")
        }
        #expect(ShareCard(night: later).basis == "No cloud forecast yet · usual clouds for the month")
    }
    @Test func withoutUsualCloudsTheScoreSaysMoonAndDarknessOnly() throws {
        let bare = night(try park("jotr"), climate: CloudClimate(parks: [:]))
        #expect(bare.usualCloud == nil && bare.score.cloudPoints == nil)
        #expect(bare.bandWithBasis == "\(bare.score.band.label), Moon and darkness only")
        #expect(bare.basisCaption() == "Cloud forecast unavailable. This score counts the Moon and darkness only.")
        #expect(ShareCard(night: bare).basis == "Cloud forecast unavailable · Moon and darkness only")
        #expect(NightLookup.basis(bare).hasPrefix("cloud forecast unavailable; scored on the Moon and darkness only"))
        for words in [bare.bandWithBasis, bare.spokenSummary(.scoreWithBasis), ShareCard(night: bare).basis] { #expect(!words.contains("usual clouds"), "\(words)") }
    }
    @Test func smokeThatLimitsTheScoreIsSaidEverywhere() throws {
        let jotr = try park("jotr")
        let first = (floor(now.timeIntervalSince1970/3600)-24)*3600
        let hours = (0..<(17*24)).map { first+Double($0)*3600 }
        let forecast = Forecast(updated: now, times: hours, clouds: hours.map { _ in 0 })
        let air = HourlySeries(updated: now, times: hours, values: ["aerosol_optical_depth": hours.map { _ in 0.6 }])
        let smoky = night(jotr, forecast: forecast, detail: ForecastDetail(air: air))
        #expect(smoky.score.limit == .smoke(59) && smoky.smokeLabel == "Heavy smoke or haze")
        #expect(smoky.bandWithBasis == "\(smoky.score.band.label), haze or smoke")
        for words in [smoky.spokenSummary(.river), smoky.spokenSummary(.calendar(event: nil)), smoky.spokenSummary(.widgetNight)] {
            #expect(words.contains("Smoke or haze limits this night to 59."), "\(words)")
        }
        for words in [smoky.spokenSummary(.widget), smoky.spokenSummary(.siriTonight(voiceOnly: false)), smoky.spokenSummary(.siriTonight(voiceOnly: true))] {
            #expect(words.contains("Smoke or haze limits tonight to 59."), "\(words)")
        }
        #expect(smoky.spokenSummary(.scoreWithBasis).hasSuffix("haze or smoke"))
        #expect(ShareCard(night: smoky).basis.hasSuffix("· Heavy smoke or haze"))
        #expect(ParkRow.spokenLabel(night: smoky, closure: nil).contains("Heavy smoke or haze."))
        #expect(WeekAcrossParks.spoken(smoky, isBest: false).contains("Heavy smoke or haze"))
        // A night smoke does not hold down says nothing about smoke.
        let clear = night(jotr, forecast: forecast)
        #expect(clear.smokeLabel == nil && !clear.spokenSummary(.river).contains("Smoke"))
    }
}
