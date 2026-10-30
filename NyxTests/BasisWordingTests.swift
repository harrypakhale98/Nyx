import Foundation
import Testing
@testable import Nyx

/// One night reads the same everywhere: the park page, the calendar, the river, the widget, Siri
/// and the share card all take what the score rests on from the same words (`Night.basisLabel`,
/// `noForecastSentence`, `bandWithBasis`, `smokeSentence`).
@MainActor @Suite struct BasisWordingTests {
    let parks: [Park] = (try? ParkData.load()) ?? []
    let now = Date(timeIntervalSince1970: 1_792_180_800) // 2026-10-16 20:00 UTC

    func night(_ park: Park, daysAhead: Int = 0, forecast: Forecast? = nil, detail: ForecastDetail? = nil, climate: CloudClimate = .shared) -> Night {
        let sky = AstronomyEngine().conditions(for: park, on: park.date(park.currentNight(at: now), addingDays: daysAhead))
        return NightPlanner.night(park: park, sky: sky, forecast: forecast, detail: detail, now: now, climate: climate)
    }
    /// Every surface's words for one night, in one list.
    func surfaces(_ night: Night) -> [String] {
        [night.basisCaption(typical: true) ?? "", night.spokenSummary(.calendar(event: nil)), night.spokenSummary(.river),
         night.widgetSummary(closure: nil), TonightAnswer(night: night).dialog(voiceOnly: false), ShareCard(night: night).summary]
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
    /// An early look where the place has no usual clouds counts the forecast as it stands, and no
    /// surface says it was eased toward clouds nobody knows.
    @Test func anEarlyLookWithoutUsualCloudsIsCountedAsItStandsEverywhere() throws {
        let jotr = try park("jotr")
        let first = (floor(now.timeIntervalSince1970/3600)-24)*3600
        let hours = (0..<(17*24)).map { first+Double($0)*3600 }
        let forecast = Forecast(updated: now, times: hours, clouds: hours.map { _ in 80 })
        let bare = night(jotr, daysAhead: 6, forecast: forecast, climate: CloudClimate(parks: [:])), eased = night(jotr, daysAhead: 6, forecast: forecast)
        try #require(bare.basis.isEarlyLook && bare.usualCloud == nil && eased.basis.isEarlyLook && eased.usualCloud != nil)
        let words = [bare.basisCaption() ?? "", ScoreBreakdownView.cloudFact(bare), ScoreBreakdownView.cloudDetail(usualClouds: false, context: false),
                     ScoreBreakdownView.cloudDetail(usualClouds: false, context: true), NightLookup.basis(bare), FieldView.basisNote(bare.score, usualClouds: false) ?? "",
                     CalendarView.legend([bare]), UsualCloudsNote.trip([bare]) ?? ""]
        for line in words {
            #expect(line.contains("as it stands"), "\(line)")
            #expect(!line.contains("eased") && !line.contains(" ease "), "\(line)")
        }
        let fact = ScoreBreakdownView.cloudFact(bare)
        #expect(fact.hasPrefix("Early look: a forecast of 80% from ") && fact.hasSuffix(" days out, counted as it stands.") && !fact.contains("Counted as"))
        #expect(FieldView.basisNote(bare.score, usualClouds: false) == bare.basisCaption())
        // With usual clouds, the words are as before.
        #expect(FieldView.basisNote(eased.score, usualClouds: true) == eased.basisCaption() && eased.basisCaption()?.contains("eased toward usual clouds") == true)
        #expect(ScoreBreakdownView.cloudFact(eased).contains("eased toward the usual clouds") && NightLookup.basis(eased).contains("eased toward usual clouds"))
        #expect(CalendarView.legend([eased]).hasPrefix("Solid: full forecast. Half-filled: an early look, the forecast eased toward the usual clouds."))
        #expect(CalendarView.legend([eased, bare]).contains("eased toward the usual clouds, or counted as it stands where those are not known."))
        #expect(UsualCloudsNote.trip([eased, bare]) == "Nights marked \"Early look\" ease the forecast toward each park's usual clouds for the month, or count it as it stands where those are not known.")
        // A stay's unmarked early look with no usual clouds leans on none.
        #expect(UsualCloudsNote.trip([night(jotr, daysAhead: 1, forecast: forecast)], unmarked: [bare]) == nil)
        #expect(CloudBasis.forecast.earlyLookCaption(usualClouds: false) == nil && CloudBasis.usual.earlyLookCaption(usualClouds: true) == nil)
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
        for words in [smoky.spokenSummary(.river), smoky.spokenSummary(.calendar(event: nil)), smoky.widgetSummary(closure: nil, ahead: true)] {
            #expect(words.contains("Smoke or haze limits this night to 59."), "\(words)")
        }
        for words in [smoky.widgetSummary(closure: nil), TonightAnswer(night: smoky).dialog(voiceOnly: false), TonightAnswer(night: smoky).dialog(voiceOnly: true)] {
            #expect(words.contains("Smoke or haze limits tonight to 59."), "\(words)")
        }
        #expect(smoky.spokenSummary(.scoreWithBasis).hasSuffix("haze or smoke"))
        #expect(ShareCard(night: smoky).basis.hasSuffix("· Heavy smoke or haze"))
        #expect(smoky.spokenRow(closure:nil).contains("Heavy smoke or haze."))
        #expect(WeekAcrossParks.spoken(smoky, isBest: false).contains("Heavy smoke or haze"))
        // A night smoke does not hold down says nothing about smoke.
        let clear = night(jotr, forecast: forecast)
        #expect(clear.smokeLabel == nil && !clear.spokenSummary(.river).contains("Smoke"))
    }
}
