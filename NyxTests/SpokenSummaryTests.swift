import Foundation
import SwiftUI
import Testing
@testable import Nyx

/// `Night.spokenSummary` gathers the sentences that say a night's score. Each style must say exactly
/// what its surface said before, under the same String Catalog key: every oracle below is the
/// inline expression the surface used, copied unchanged. The night look's colours keep their values.
@MainActor struct SpokenSummaryTests {
    let parks: [Park]
    let engine=AstronomyEngine()
    init() throws { parks=try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    /// A real sky on `iso`'s evening at the park, with a hand-set score and cloud basis.
    func night(_ id: String, _ iso: String, _ value: Int, _ basis: CloudBasis, usual: Double?=nil, moonAndDarkOnly: Bool=false) throws -> Night {
        let place=try park(id)
        let sky=engine.conditions(for: place, on: try #require(TripDay(iso: iso)).evening(in: place))
        let score=DarknessScore(value: value, moonPoints: 30, cloudPoints: moonAndDarkOnly ? nil : 20, bortlePoints: 17.5, lengthPoints: 12, basis: basis)
        // The month's share of clear nights from the bundled climate, as `NightPlanner.night` keeps it.
        let clear=usual == nil ? nil : CloudClimate.shared.typical(place, on: sky.evening)?.clear
        return Night(park: place, sky: sky, score: score, cloudCover: basis == .forecast ? 5 : nil, forecastUpdated: nil, usualCloud: usual, usualClear: clear)
    }
    /// A forecast, an early look, the usual clouds, Moon and darkness only, and two nights without true darkness.
    func fixtures() throws -> [Night] {
        [try night("arch", "2026-10-08", 94, .forecast),
         try night("arch", "2026-10-20", 81, .blended(weight: 0.5, leadDays: 8.4)),
         try night("arch", "2026-11-10", 73, .usual, usual: 30),
         try night("jotr", "2026-11-12", 66, .usual, moonAndDarkOnly: true),
         try night("dena", "2026-06-21", 35, .forecast),
         try night("dena", "2026-06-22", 30, .usual, usual: 60)]
    }

    @Test func fixturesCoverEveryBasisAndNoDarkness() throws {
        let nights=try fixtures()
        #expect(nights.contains { $0.basis == .forecast } && nights.contains { $0.basis.isEarlyLook } && nights.contains { $0.basis == .usual })
        #expect(nights.contains { $0.usualCloud == nil && $0.basis == .usual } && nights.contains { $0.sky.darkHours == 0 })
        #expect(nights.contains { $0.typicalClouds != nil })
    }
    /// The time river, the calendar's list, the widget and the chart.
    @Test func screenSentencesAreUnchanged() throws {
        for night in try fixtures() {
            let clouds=night.basisCaption(typical:true) ?? String(localized:"Includes cloud forecast.")
            #expect(night.spokenSummary(.river) == String(localized:"\(night.park.dayLabel(night.id)), \(night.score.value) out of 100, \(night.score.band.label). \(clouds)"))
            for name in [nil, "Lunar eclipse"] as [String?] {
                let marker=name.map { ". "+$0 } ?? ""
                #expect(night.spokenSummary(.calendar(event: name)) == String(localized:"\(night.park.dayLabel(night.id)), \(night.score.value) out of 100, \(night.score.band.label). \(night.basisCaption(typical:true) ?? String(localized:"Includes cloud forecast."))\(marker)"))
            }
            #expect(night.spokenSummary(.widget) == String(localized:"\(night.park.shortName), \(night.score.value) out of 100, \(night.score.band.label). \(night.basisCaption() ?? String(localized:"Includes cloud forecast."))"))
            #expect(night.spokenSummary(.chartBest) == String(localized:"Best night: \(night.park.dayLabel(night.id)), \(night.score.value) out of 100, \(night.score.band.label)."))
            // Siri's card says what the clouds rest on with the band (2.0 design review): "Excellent, usual clouds".
            #expect(night.spokenSummary(.snippet) == String(localized:"\(night.park.shortName) tonight: \(night.score.value) out of 100, \(night.bandWithBasis). \(night.sky.moon.name), \(night.sky.moon.percentLit) percent lit."))
        }
        // The calendar's list reads in English as the time river does, under its own key.
        let first=try #require(try fixtures().first)
        #expect(first.spokenSummary(.calendar(event: nil)) == first.spokenSummary(.river))
        #expect(first.spokenSummary(.river) == "\(first.park.dayLabel(first.id)), 94 out of 100, Pristine. Includes cloud forecast.")
    }
    /// The trip planner's row, shared text and calendar notes.
    @Test func tripSentencesAreUnchanged() throws {
        for night in try fixtures() {
            let park=night.park, reason=TripPlanner.reason(night)
            #expect(night.spokenSummary(.dayWithBasis) == String(localized:"\(park.dayLabel(night.id)), \(night.score.value) out of 100, \(night.bandWithBasis)"))
            #expect(night.spokenSummary(.scoreWithBasis) == String(localized:"\(night.score.value) out of 100, \(night.bandWithBasis)"))
            #expect(night.spokenSummary(.tripLine(reason: reason)) == String(localized:"\(park.dayLabel(night.id)): \(park.shortName), \(night.score.value) out of 100, \(night.bandWithBasis). \(reason)."))
            #expect(night.spokenSummary(.stayNote(reason: reason)) == String(localized:"\(park.dayLabel(night.id)): darkness score \(night.score.value) out of 100 (\(night.bandWithBasis)). \(reason)."))
            let note=night.score.hasForecast
                ? String(localized:"Darkness score \(night.score.value) out of 100 (\(night.score.band.label)), with the cloud forecast as Nyx last saw it.")
                : String(localized:"Darkness score \(night.score.value) out of 100 (\(night.score.band.label)).")+" "+(night.basisCaption(typical:true) ?? "")
            #expect(night.spokenSummary(.eventNote) == note)
            #expect(CalendarDraft(night: night, closure: nil).notes.hasPrefix(note+"\n"+reason+"."))
        }
    }
    /// Siri's answers for tonight and for the best night, full and voice-only.
    @Test func siriSentencesAreUnchanged() throws {
        for night in try fixtures() {
            let park=night.park, score=night.score
            for voiceOnly in [false, true] {
                let body:String
                if night.sky.darkHours==0 { body=String(localized:"No true darkness tonight at \(park.shortName). The darkness score is \(score.value) out of 100.") }
                else if voiceOnly {
                    let basis=score.hasForecast ? "" : " "+(night.basis.isEarlyLook ? String(localized:"An early look at the clouds.") : night.withTypicalClouds(String(localized:"No cloud forecast yet.")))
                    let tonight=String(localized:"Tonight")
                    body=String(localized:"\(tonight) at \(park.shortName): \(score.value), \(score.band.label).")+basis
                }
                else if let caption=night.basisCaption() { body=String(localized:"\(park.shortName): \(score.value) out of 100, \(score.band.label). \(caption) Confirm conditions and park access before traveling.") }
                else { body=String(localized:"\(park.shortName): \(score.value) out of 100, \(score.band.label). \(String(localized:"Includes cloud forecast.")) Confirm conditions and park access before traveling.") }
                // One answer on every device (`TonightAnswer`), which the iPhone's intent says.
                #expect(TonightAnswer(night: night).dialog(voiceOnly: voiceOnly) == body)
                #expect(DarknessAnswer.dialog(night, closure: nil, voiceOnly: voiceOnly) == body)
                #expect(DarknessAnswer.dialog(night, closure: "Park closed.", voiceOnly: voiceOnly) == "Closure alert: Park closed. "+body)

                let answer=BestNightSearch.Answer(nights: [night], count: 14)
                let best=bestOracle(answer, voiceOnly: voiceOnly)
                #expect(night.spokenSummary(.siriBest(count: 14, voiceOnly: voiceOnly, noDarkness: answer.noDarkness)) == best)
                #expect(BestNightSearch.dialog(answer, voiceOnly: voiceOnly) == best)
            }
        }
    }
    /// `BestNightSearch.dialog` as it was written inline.
    func bestOracle(_ answer: BestNightSearch.Answer, voiceOnly: Bool) -> String {
        let night=answer.best, park=night.park
        let day=park.programDate(park.isoDay(night.id))
        if voiceOnly {
            let basis=night.score.hasForecast ? "" : " "+(night.basis.isEarlyLook ? String(localized:"An early look at the clouds.") : night.withTypicalClouds(String(localized:"No cloud forecast yet.")))
            return String(localized:"\(day) at \(park.shortName): \(night.score.value), \(night.score.band.label).")+basis
        }
        if answer.noDarkness {
            return String(localized:"No true darkness at \(park.shortName) in the next \(answer.count) nights. The best is \(day), \(night.score.value) out of 100.")
        }
        let basis=night.basisCaption(typical:true) ?? String(localized:"Includes cloud forecast.")
        return String(localized:"The best of the next \(answer.count) nights: \(day) at \(park.shortName), \(night.score.value) out of 100, \(night.score.band.label). \(basis) Confirm conditions and park access before traveling.")
    }

    // MARK: Colours

    @Test func nightLookColoursKeepTheirValues() {
        #expect(NyxPalette.starlightRGB == SIMD3<Double>(0.961,0.945,0.902) && NyxPalette.amberRGB == SIMD3<Double>(1,0.706,0.329))
        #expect(NyxPalette.starlight == Color(red:0.961,green:0.945,blue:0.902) && NyxPalette.amber == Color(red:1,green:0.706,blue:0.329))
        #expect(NightLook.starlight == SIMD3<Double>(0.961,0.945,0.902) && NightLook.amber == SIMD3<Double>(1,0.706,0.329))
        for nightVision in [false, true] {
            for highContrast in [false, true] {
                let palette=NyxPalette(nightVision: nightVision, highContrast: highContrast)
                #expect(palette.ink == (nightVision ? .white : Color(red:0.961,green:0.945,blue:0.902)))
                #expect(palette.accent == (nightVision ? palette.ink : Color(red:1,green:0.706,blue:0.329)))
                // Siri's cards: `LinearGradient(colors:[.black,palette.panel],startPoint:.top,endPoint:.bottom)`.
                #expect(palette.snippetGradient == Gradient(colors:[.black,palette.panel]))
            }
        }
        let day=NightLook(nightVision: false)
        #expect(day.ink == Color(red:0.961,green:0.945,blue:0.902) && day.accent == Color(red:1,green:0.706,blue:0.329))
    }
}
