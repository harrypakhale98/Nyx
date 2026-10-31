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
    /// Denali on June 15, 2026 has no true darkness: its cap is never said as short hours, on the
    /// readout, the breakdown, Vision Pro or an "I'm going" check alike.
    @Test func noDarknessIsNeverShortHours() throws {
        let dena = try park("dena"), evening = try #require(dena.calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 13)))
        let sky = AstronomyEngine().conditions(for: dena, on: dena.evening(evening))
        #expect(sky.darkHours == 0)
        let score = ScoreEngine().score(sky: sky, bortle: dena.bortleEstimate, cloud: 0, basis: .forecast, aerosol: nil)
        #expect(score.value == 39 && score.limit == .darkness(39))
        #expect(score.limitSentence(tonight: true) == "With no true darkness, tonight can reach only 39.")
        #expect(score.limitSentence(tonight: false) == "With no true darkness, this night can reach only 39.")
        #expect(ScoreReadout.limitLine(score, tonight: true)?.contains("Short hours") == false)
        // A short night keeps its own words.
        let short = DarknessScore(value: 60, moonPoints: 30, cloudPoints: 25, bortlePoints: 15, lengthPoints: 1.5, limit: .darkness(60))
        #expect(short.limitSentence(tonight: true) == "Short hours of true darkness limit tonight to 60.")
        // Ask Nyx's record and the breakdown say it the same way, and say the cap once.
        let night = Night(park: dena, sky: sky, score: score, cloudCover: 4, forecastUpdated: .now)
        #expect(NightLookup.basis(night) == "cloud forecast included, 4% cloud; With no true darkness, this night can reach only 39.")
        #expect(ScoreBreakdownView.darknessNote(night, tonight: true) == "No true darkness tonight at this latitude.")
        let glac = try park("glac"), early = try #require(glac.calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 13)))
        let shortSky = AstronomyEngine().conditions(for: glac, on: glac.evening(early))
        try #require(shortSky.darkHours > 0 && ScoreEngine.cap(darkHours: shortSky.darkHours) < 100)
        let held = DarknessScore(value: 50, moonPoints: 30, cloudPoints: 25, bortlePoints: 15, lengthPoints: 1, limit: .darkness(50))
        #expect(ScoreBreakdownView.darknessNote(Night(park: glac, sky: shortSky, score: held, cloudCover: 0, forecastUpdated: .now), tonight: true) == nil)
        // When another cap binds, the darkness cap is still said, once, in the footer.
        let clouded = DarknessScore(value: 30, moonPoints: 30, cloudPoints: 5, bortlePoints: 15, lengthPoints: 1, limit: .clouds(30))
        #expect(ScoreBreakdownView.darknessNote(Night(park: glac, sky: shortSky, score: clouded, cloudCover: 80, forecastUpdated: .now), tonight: true)?.hasPrefix("True darkness lasts only ") == true)
        #expect(ScoreBreakdownView.darknessNote(Night(park: dena, sky: sky, score: clouded, cloudCover: 80, forecastUpdated: .now), tonight: false)
                == "No true darkness on this night at this latitude. The score is capped below 40.")
    }
    /// A night with no true darkness averages its clouds over other hours, and says which: Denali sets
    /// and rises in June (sunset to sunrise), Gates of the Arctic has the midnight Sun (four darkest hours).
    @Test func cloudsWithoutDarknessNameTheirHours() throws {
        for (id, hours, words) in [("dena", SkyConditions.CloudHours.sunsetToSunrise, "from sunset to sunrise"), ("gaar", .darkestHours, "over the four darkest hours")] {
            let place = try park(id), day = try #require(place.calendar.date(from: DateComponents(year: 2027, month: 6, day: 20, hour: 13)))
            let sky = AstronomyEngine().conditions(for: place, on: place.evening(day))
            try #require(sky.darkHours == 0, "\(id)")
            #expect(sky.cloudHours == hours, "\(id)")
            let night = Night(park: place, sky: sky, score: DarknessScore(value: 39, moonPoints: 30, cloudPoints: 24, bortlePoints: 20, lengthPoints: 0), cloudCover: 4, forecastUpdated: .now)
            let cover = try #require(night.coverSentence)
            #expect(cover == "4% average cover \(words).", "\(cover)")
            for usual in [true, false] {
                for context in [true, false] {
                    let detail = ScoreBreakdownView.cloudDetail(usualClouds: usual, context: context, hours: sky.cloudHours)
                    #expect(detail.hasPrefix("With no true darkness, the hourly forecast is averaged ") && detail.contains(words), "\(detail)")
                    #expect(!detail.contains("over true darkness"), "\(detail)")
                }
            }
            for line in [night.cloudCaption(), ScoreBreakdownView.cloudFact(night)] { #expect(!line.contains("true darkness"), "\(line)") }
        }
        // A night with true darkness keeps its words.
        let jotr = try park("jotr"), day = try #require(jotr.calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 13)))
        let sky = AstronomyEngine().conditions(for: jotr, on: jotr.evening(day))
        #expect(sky.cloudHours == .darkness)
        #expect(Night(park: jotr, sky: sky, score: DarknessScore(value: 70, moonPoints: 20, cloudPoints: 24, bortlePoints: 15, lengthPoints: 11), cloudCover: 4, forecastUpdated: .now).coverSentence == "4% average cover through true darkness.")
        #expect(ScoreBreakdownView.cloudDetail(usualClouds: true, context: false).hasPrefix("The hourly forecast averaged over true darkness. Beyond about three days "))
    }

    /// One sample snapshot for the widget and complication galleries: Joshua Tree, no forecast.
    @Test func theGallerySampleIsJoshuaTree() throws {
        let sample = try #require(SavedSkySnapshot.sample)
        #expect(sample.parks.map(\.id) == [Park.defaultID] && sample.forecasts.isEmpty)
    }
}
