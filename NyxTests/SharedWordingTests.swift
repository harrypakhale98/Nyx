import Foundation
import Testing
@testable import Nyx

/// The words the iPhone, Apple Watch and Vision Pro all say, each built once in a file every target
/// compiles: a park row's spoken label, the widget and complication summary, the Moon's rise and
/// set, a park's states and eyebrow, and what holds a score below its parts.
@MainActor struct SharedWordingTests {
    let engine = AstronomyEngine()
    let closure = "Keys View Road closed at night"
    func night(_ id: String, _ iso: String, _ value: Int, _ basis: CloudBasis = .forecast, limit: ScoreLimit? = nil) throws -> Night {
        let place = try park(id)
        let sky = engine.conditions(for: place, on: try #require(TripDay(iso: iso)).evening(in: place))
        let score = DarknessScore(value: value, moonPoints: 30, cloudPoints: 20, bortlePoints: 17.5, lengthPoints: 12, basis: basis, limit: limit)
        return Night(park: place, sky: sky, score: score, cloudCover: basis == .forecast ? 5 : nil, forecastUpdated: nil, usualCloud: basis == .forecast ? nil : 30)
    }

    /// The iPhone's row label, unchanged; the watch and Vision Pro say what the clouds rest on with the band.
    @Test func aParkRowIsSpokenOneWayOnEveryDevice() throws {
        let clear = try night("jotr", "2026-10-08", 88)
        #expect(clear.spokenRow(closure: nil) == "Joshua Tree. Darkness score 88, Excellent.")
        #expect(clear.spokenRow(closure: closure) == "Joshua Tree. Darkness score 88, Excellent. Closure alert: \(closure)")
        #expect(clear.spokenRow(closure: nil, withBasis: true) == clear.spokenRow(closure: nil))
        let early = try night("jotr", "2026-10-20", 81, .blended(weight: 0.5, leadDays: 8.4))
        #expect(early.spokenRow(closure: nil) == "Joshua Tree. Darkness score 81, Excellent.")
        #expect(early.spokenRow(closure: closure, withBasis: true) == "Joshua Tree. Darkness score 81, Excellent, early look. Closure alert: \(closure)")
        // Smoke that holds the score down is said once: as its own word, or with the band.
        let smoky = try night("jotr", "2026-10-08", 55, limit: .smoke(55))
        #expect(smoky.spokenRow(closure: nil) == "Joshua Tree. Darkness score 55, Fair. Heavy smoke or haze.")
        #expect(smoky.spokenRow(closure: nil, withBasis: true) == "Joshua Tree. Darkness score 55, Fair, haze or smoke.")
    }

    /// The iPhone widget and the watch's complications: the closure with its full stop right after the
    /// score, "Includes cloud forecast." with a forecast, and smoke said for tonight or for the night ahead.
    @Test func widgetAndComplicationSayTheSameSummary() throws {
        let clear = try night("jotr", "2026-10-08", 94)
        #expect(clear.widgetSummary(closure: nil) == "Joshua Tree, 94 out of 100, Pristine. Includes cloud forecast.")
        #expect(clear.widgetSummary(closure: closure) == "Joshua Tree, 94 out of 100, Pristine. Closure alert: \(closure). Includes cloud forecast.")
        let usual = try night("jotr", "2026-11-10", 73, .usual)
        #expect(usual.widgetSummary(closure: nil) == "Joshua Tree, 73 out of 100, Good. \(try #require(usual.basisCaption()))")
        let smoky = try night("jotr", "2026-10-08", 55, limit: .smoke(55))
        #expect(smoky.widgetSummary(closure: nil).hasSuffix("Smoke or haze limits tonight to 55."))
        let ahead = smoky.widgetSummary(closure: closure, ahead: true)
        #expect(ahead.hasPrefix("Joshua Tree, \(smoky.park.dayLabel(smoky.id)): 55 out of 100, Fair. Closure alert: \(closure)."))
        #expect(ahead.hasSuffix("Smoke or haze limits this night to 55."))
    }

    /// The Moon's line on the iPhone's From home panel and Vision Pro's Moon cell: rises and sets
    /// before sunrise in time order, never a rise late the next morning, else up or below all night.
    @Test func moonTimesStopAtSunriseInTimeOrder() throws {
        let jotr = try park("jotr")
        for day in 0..<30 {
            let sky = engine.conditions(for: jotr, on: jotr.date(jotr.currentNight(at: try date("2026-10-01T20:00:00Z")), addingDays: day))
            let line = sky.moonTimes(park: jotr), morning = sky.sunrise ?? sky.end
            let rise = sky.moonrise.flatMap { $0 < morning ? $0 : nil }, set = sky.moonset.flatMap { $0 < morning ? $0 : nil }
            switch (rise, set) {
            case let (rise?, set?):
                let words = [(rise, "Rises \(jotr.time(rise))"), (set, "Sets \(jotr.time(set))")].sorted { $0.0 < $1.0 }.map(\.1)
                #expect(line == words.joined(separator: " · "), "\(line)")
            case let (rise?, nil): #expect(line == "Rises \(jotr.time(rise))")
            case let (nil, set?): #expect(line == "Sets \(jotr.time(set))")
            case (nil, nil): #expect(line == "Up all night" || line == "Below the horizon all night", "\(line)")
            }
            if let late = sky.moonrise, late >= morning { #expect(!line.contains(jotr.time(late)) || line.contains("Sets")) }
        }
        // From home says the same words for the same sky.
        let origin = try #require(HomeSky.origin(location: nil, place: nil, park: jotr))
        let home = HomeSky(origin: origin, now: try date("2026-10-08T20:00:00Z"))
        #expect(home.moonTimes == home.sky.moonTimes(park: home.place))
    }

    /// A park's states under its name and its eyebrow, the same on every device.
    @Test func statesLineAndEyebrowAreSharedRules() throws {
        let yell = try park("yell")
        #expect(yell.statesLine == yell.region.replacingOccurrences(of: ",", with: " · ") && yell.statesLine.contains(" · "))
        let designated = try #require(TestData.parks.first { $0.darkSkyDesignated && $0.kind == .nationalPark })
        #expect(designated.parkEyebrow == "\(designated.statesLine) · International Dark Sky Park")
        let plain = try #require(TestData.parks.first { !$0.darkSkyDesignated && $0.kind == .nationalPark })
        #expect(plain.parkEyebrow == plain.statesLine)
        // The iPhone's own lines rest on them for a park.
        #expect(yell.regionLine == yell.statesLine && designated.placeEyebrow == designated.parkEyebrow)
    }

    /// What holds a score below its parts, said on Vision Pro alone and on the iPhone before the parts' sum.
    @Test func theLimitSentenceIsOneRule() {
        let capped = DarknessScore(value: 64, moonPoints: 22, cloudPoints: 21, bortlePoints: 15, lengthPoints: 15, limit: .moonlight(64))
        #expect(capped.limitSentence(tonight: true) == "Moonlight limits tonight to 64.")
        #expect(capped.limitSentence(tonight: false) == "Moonlight limits this night to 64.")
        #expect(ScoreReadout.limitLine(capped, tonight: true)?.hasPrefix(capped.limitSentence(tonight: true) ?? "-") == true)
        let loose = DarknessScore(value: 73, moonPoints: 22, cloudPoints: 21, bortlePoints: 15, lengthPoints: 15, limit: .moonlight(80))
        #expect(loose.limitSentence(tonight: true) == nil)
        #expect(DarknessScore(value: 73, moonPoints: 22, cloudPoints: 21, bortlePoints: 15, lengthPoints: 15).limitSentence(tonight: true) == nil)
    }

    /// One sample snapshot for the widget and complication galleries: Joshua Tree, no forecast.
    @Test func theGallerySampleIsJoshuaTree() throws {
        let sample = try #require(SavedSkySnapshot.sample)
        #expect(sample.parks.map(\.id) == [Park.defaultID] && sample.forecasts.isEmpty)
    }
}
