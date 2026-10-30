import Foundation
import Testing
@testable import Nyx

/// Tonight's dial stepped through the coming nights (`TonightScrub`): how a drag becomes a night, the
/// two weeks it is held to, the nights it names in each place's own time, and what VoiceOver hears.
@Suite struct TonightScrubTests {
    let engine = AstronomyEngine()
    func night(_ park: Park, _ day: String, score: Int, basis: CloudBasis = .forecast) throws -> Night {
        let sky = engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
        return Night(park: park, sky: sky, score: DarknessScore(value: score, moonPoints: 30, cloudPoints: basis == .forecast ? 20 : 15, bortlePoints: 16, lengthPoints: 10, basis: basis), cloudCover: basis == .forecast ? 10 : nil, forecastUpdated: basis == .forecast ? .now : nil)
    }

    /// Tonight and the next 13 nights, never before tonight or past the last.
    @Test func nightsAreHeldToTwoWeeks() {
        #expect(TonightScrub.nights == 14 && TonightScrub.last == 13)
        #expect(TonightScrub.clamp(-3) == 0)
        #expect(TonightScrub.clamp(0) == 0)
        #expect(TonightScrub.clamp(7) == 7)
        #expect(TonightScrub.clamp(13) == 13)
        #expect(TonightScrub.clamp(40) == 13)
    }
    /// A night per pitch, the first from half a pitch; toward the leading edge is later, as pages turn.
    @Test func aDragStepsANightPerPitch() {
        let pitch = TonightScrub.pitch
        #expect(TonightScrub.offset(from: 0, translation: 0) == 0)
        #expect(TonightScrub.offset(from: 0, translation: -pitch*0.45) == 0)
        #expect(TonightScrub.offset(from: 0, translation: -pitch*0.5) == 1)
        #expect(TonightScrub.offset(from: 0, translation: -pitch) == 1)
        #expect(TonightScrub.offset(from: 0, translation: -pitch*5) == 5)
        // Back toward tonight from a held night.
        #expect(TonightScrub.offset(from: 6, translation: pitch*2) == 4)
        // Held at both ends, however far the finger goes.
        #expect(TonightScrub.offset(from: 3, translation: pitch*10) == 0)
        #expect(TonightScrub.offset(from: 10, translation: -pitch*30) == 13)
        // In a right-to-left language the later nights come in from the left.
        #expect(TonightScrub.offset(from: 0, translation: pitch*3, rightToLeft: true) == 3)
        #expect(TonightScrub.offset(from: 3, translation: -pitch*3, rightToLeft: true) == 0)
        // The whole two weeks fit one sweep across a phone's column (about 354 pt).
        #expect(Double(TonightScrub.last)*pitch <= 354)
    }
    /// Only a mostly sideways drag scrubs; the river's rule, so a page scroll is never taken for a scrub.
    @Test func onlyASidewaysDragScrubs() {
        #expect(TonightScrub.isHorizontal(CGSize(width: 12, height: 3)))
        #expect(TonightScrub.isHorizontal(CGSize(width: -12, height: -11)))
        #expect(!TonightScrub.isHorizontal(CGSize(width: 4, height: 12)))
        #expect(!TonightScrub.isHorizontal(CGSize(width: 8, height: -8)))
    }
    /// Each step is the next night at each place, in its own time zone, as `PlanModel.nights` steps
    /// them: fourteen distinct evenings a day apart, tonight first.
    @Test func eachStepIsTheNextNightInThePlacesOwnTime() throws {
        for id in ["jotr", "hale", "npsa", "gaar"] {
            let place = try park(id)
            let tonight = place.currentNight(at: Date(timeIntervalSince1970: 1_793_300_000))
            #expect(TonightScrub.evening(place, tonight: tonight, offset: 0) == tonight)
            let evenings = (0..<TonightScrub.nights).map { place.evening(TonightScrub.evening(place, tonight: tonight, offset: $0)) }
            #expect(Set(evenings).count == TonightScrub.nights, "\(id)")
            for (a, b) in zip(evenings, evenings.dropFirst()) {
                #expect(place.calendar.dateComponents([.day], from: a, to: b).day == 1, "\(id)")
            }
            #expect(evenings[3] == place.evening(place.date(tonight, addingDays: 3)))
        }
    }
    /// Each night re-ranks the places by the rule every best night uses: the darkest leads the pill.
    @Test func eachNightLeadsWithItsDarkestPlace() throws {
        let jotr = try park("jotr"), deva = try park("deva"), grba = try park("grba")
        let nights = [try night(jotr, "2026-10-30", score: 64), try night(deva, "2026-10-30", score: 82), try night(grba, "2026-10-30", score: 71)]
        #expect(NightPlanner.ranked(nights).map(\.park.id) == ["deva", "grba", "jotr"])
    }
    /// VoiceOver's value: the night, the place, its score and band; beyond the forecast the score says
    /// what it rests on, in the words every list uses (`NightVerdict.scored`).
    @Test func theValueNamesTheNightThePlaceAndTheScore() throws {
        let jotr = try park("jotr")
        let forecast = try night(jotr, "2026-10-30", score: 82)
        let day = jotr.dayLabel(forecast.id)
        #expect(TonightScrub.spokenValue(forecast, tonight: false) == "\(day): Joshua Tree, 82, Excellent")
        #expect(TonightScrub.spokenValue(forecast, tonight: true) == "Tonight: Joshua Tree, 82, Excellent")
        let usual = try night(jotr, "2026-11-04", score: 61, basis: .usual)
        #expect(TonightScrub.spokenValue(usual, tonight: false) == "\(jotr.dayLabel(usual.id)): Joshua Tree, 61, usual clouds, Good")
        let early = try night(jotr, "2026-11-01", score: 77, basis: .blended(weight: 0.5, leadDays: 6))
        #expect(TonightScrub.spokenValue(early, tonight: false).hasSuffix("Joshua Tree, 77, early look, Excellent"))
    }
}
