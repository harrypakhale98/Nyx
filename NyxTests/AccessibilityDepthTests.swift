import Foundation
import Testing
@testable import Nyx

/// The sky for everyone: the night as sound, Audio Graph data, the Moon's haptic texture, and the
/// shapes that stand in for colour. Real computed nights throughout.
@Suite struct AccessibilityDepthTests {
    let engine = AstronomyEngine()
    func park(_ id: String) throws -> Park { try #require(try ParkData.load().first(where: { $0.id == id })) }
    func night(_ park: Park, _ day: String, clouds: Double?=nil) throws -> Night {
        let sky = engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
        return Night(park: park, sky: sky, score: ScoreEngine().score(sky: sky, bortle: park.bortleEstimate, cloudCover: clouds), cloudCover: clouds, forecastUpdated: nil)
    }

    // MARK: Listen to tonight

    /// Geminid night at Joshua Tree: sunset opens the sound, sunrise ends it, every moment in between
    /// lands where the clock puts it, and the tone is an octave lower in true darkness than at dusk.
    @Test func sonificationMapsTheNightOntoTwelveSeconds() throws {
        let jotr = try park("jotr"), night = try night(jotr, "2026-12-13")
        let sound = NightSonification(park: jotr, sky: night.sky)
        let sunset = try #require(night.sky.sunset), sunrise = try #require(night.sky.sunrise), dark = try #require(night.sky.darkStart)
        #expect(sound.window.start == sunset && sound.window.end == sunrise && sound.duration == 12)
        let kinds = sound.cues.map(\.kind)
        #expect(kinds.first == .sunset && kinds.last == .sunrise && kinds.contains(.darkness) && kinds.contains(.dawn))
        #expect(zip(sound.cues, sound.cues.dropFirst()).allSatisfy { $0.offset <= $1.offset })
        let first = try #require(sound.cues.first), last = try #require(sound.cues.last)
        #expect(abs(first.offset) < 0.01 && abs(last.offset - 12) < 0.01)
        let expected = dark.timeIntervalSince(sunset)/sunrise.timeIntervalSince(sunset)*12
        let darkness = try #require(sound.cues.first { $0.kind == .darkness })
        #expect(abs(darkness.offset - expected) < 0.001)
        // An octave from dusk to true darkness.
        #expect(abs(NightSonification.frequency(darkness: 0) - 330) < 0.001 && abs(NightSonification.frequency(darkness: 1) - 165) < 0.001)
        #expect(sound.control(at: 0).frequency > 320 && abs(sound.control(at: 6).frequency - 165) < 1)
        // The transcript says each moment in park time, after the opening line.
        #expect(sound.transcript.count == sound.cues.count+1)
        #expect(sound.transcript.contains("True darkness at \(jotr.time(dark))"))
        #expect(sound.opening.hasPrefix("Joshua Tree"))
    }
    /// A bright Moon rising in the night: a rising pulse, and the tone quiets once it is up.
    @Test func moonriseQuietsTheToneAndPulses() throws {
        let jotr = try park("jotr")
        var found: (NightSonification, NightSonification.Cue)?
        for day in 1...28 where found == nil {
            let night = try night(jotr, String(format: "2026-11-%02d", day))
            let sound = NightSonification(park: jotr, sky: night.sky)
            if night.sky.moon.illumination > 0.4, let rise = sound.cues.first(where: { $0.kind == .moonrise && $0.offset > 2 && $0.offset < 9 }) { found = (sound, rise) }
        }
        let (sound, rise) = try #require(found)
        #expect(rise.sound == .pulseRising && rise.line.hasPrefix("Moonrise at"))
        #expect(sound.control(at: rise.offset+1.2).gain < sound.control(at: rise.offset-0.6).gain-0.1)
        #expect(NightSonification.gain(moonlight: 0) == 1 && abs(NightSonification.gain(moonlight: 1) - 0.4) < 1e-9)
    }
    /// The rendered sound has the right length, never clips, and the core's chime is heard.
    @Test func renderedSoundStaysInRange() throws {
        let jotr = try park("jotr"), night = try night(jotr, "2026-07-15")
        let sound = NightSonification(park: jotr, sky: night.sky)
        let rate = 4000.0, samples = sound.render(sampleRate: rate)
        #expect(samples.count == 48_000)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 0.85 })
        #expect(samples.map { abs($0) }.max() ?? 0 > 0.05)
        let chime = try #require(sound.cues.first { $0.sound == .chime })
        let at = Int(chime.offset*rate)
        func energy(_ range: Range<Int>) -> Float { samples[range].reduce(0) { $0+$1*$1 } }
        #expect(energy(at..<(at+400)) > energy((at-800)..<(at-400)))
    }
    /// Denali at midsummer: no true darkness, said plainly, and still a calm, finite sound.
    @Test func midnightSunSoundsWithoutDarkness() throws {
        let dena = try park("dena"), night = try night(dena, "2026-06-21")
        let sound = NightSonification(park: dena, sky: night.sky)
        #expect(!sound.cues.contains { $0.kind == .darkness })
        #expect(sound.opening.contains("No true darkness"))
        #expect(sound.darkness.allSatisfy { $0 < 1 })
        #expect(sound.render(sampleRate: 2000).allSatisfy { $0.isFinite })
    }

    // MARK: Audio Graphs

    @Test func riverChartCarriesScoresEstimatesAndModelSpread() throws {
        let jotr = try park("jotr")
        let nights = try ["2026-12-10", "2026-12-11", "2026-12-12"].enumerated().map { i, day in try night(jotr, day, clouds: i == 2 ? nil : 10) }
        var outlook = NightOutlook(); outlook.scoreRange = 70...88
        let chart = NightChart.nights(nights, title: "River", outlooks: [nights[1].id: outlook], events: [nights[2].id: "Geminids peak"])
        #expect(chart.series.count == 3)
        let scores = chart.series[0]
        #expect(scores.continuous && scores.points.map(\.y) == nights.map { Double($0.score.value) })
        #expect(scores.points[2].label == "Estimate, moon and darkness only. Geminids peak")
        #expect(scores.points[0].label == nights[0].score.band.label)
        #expect(chart.series[1].points == [NightChart.Point(x: 1, y: 88, label: nil)] && chart.series[2].points == [NightChart.Point(x: 1, y: 70, label: nil)])
        #expect(chart.x.describe(1) == jotr.dayLabel(nights[1].id) && chart.y.describe(94) == "94 out of 100")
        #expect(chart.y.range == 0...100 && chart.x.range == 0...2)
        #expect(chart.summary.contains("1 of 3 nights have no cloud forecast yet."))
        // Without a spread, one series.
        #expect(NightChart.nights(nights, title: "River").series.count == 1)
    }
    @Test func skyChartTracesSunMoonAndCoreInDegrees() throws {
        let jotr = try park("jotr"), night = try night(jotr, "2026-07-15")
        let sunset = try #require(night.sky.sunset), sunrise = try #require(night.sky.sunrise)
        let chart = NightChart.sky(night, window: (sunset.addingTimeInterval(-3600), sunrise.addingTimeInterval(3600)), summary: "Summary")
        #expect(chart.series.map(\.name).first == "Sun" && chart.series.count == 3 && chart.series[2].name == "Milky Way core")
        // One hour in is sunset: the Sun sits on the horizon.
        let sun = try #require(chart.series[0].points.first { abs($0.x - 1) < 0.01 }?.y)
        #expect(abs(sun) <= 1.5)
        #expect(chart.series[0].points.allSatisfy { ($0.y ?? 0) >= -90 && ($0.y ?? 0) <= 90 })
        #expect(chart.y.describe(12) == "12° up" && chart.y.describe(-5) == "5° below the horizon")
        #expect(chart.x.describe(1) == jotr.time(sunset))
    }

    // MARK: Feel the Moon

    @Test func moonTextureFollowsThePhase() {
        let new = MoonTexture.moon(illumination: 0, waxing: true), full = MoonTexture.moon(illumination: 1, waxing: false)
        #expect(new.taps.count == 3 && new.hum == nil && new.taps.allSatisfy { $0.sharpness == 1 })
        #expect(full.taps.count == 12 && full.taps.allSatisfy { abs($0.sharpness - 0.25) < 1e-9 })
        guard let hum = full.hum else { Issue.record("A full Moon has a hum"); return }
        #expect(abs(hum.intensity - 0.8) < 1e-9 && hum.sharpness < 0.1 && hum.from > hum.to)
        let waxing = MoonTexture.moon(illumination: 0.5, waxing: true)
        #expect(waxing.hum.map { $0.from < $0.to } == true)
        // Sparse and sharp to dense and soft, step by step.
        let steps = stride(from: 0.0, through: 1, by: 0.1).map { MoonTexture.moon(illumination: $0, waxing: true) }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.taps.count <= $1.taps.count && $0.taps[0].sharpness > $1.taps[0].sharpness })
        #expect(new.taps.allSatisfy { $0.time > 0 && $0.time < 1.2 })
    }
    @Test func riverDetentSharpensWithScore() {
        let poor = MoonTexture.detent(score: 0), pristine = MoonTexture.detent(score: 100)
        #expect(abs(poor.intensity - 0.3) < 1e-9 && abs(poor.sharpness - 0.15) < 1e-9)
        #expect(abs(pristine.intensity - 0.9) < 1e-9 && abs(pristine.sharpness - 1) < 1e-9)
        #expect(MoonTexture.detent(score: 140) == pristine && MoonTexture.detent(score: 60).sharpness < MoonTexture.detent(score: 80).sharpness)
    }

    // MARK: Without colour

    @Test func nightMarksCarryBandsAndForecastsInShape() {
        #expect(NightMark.mark(score: 92, hasForecast: true, differentiate: true) == .star(filled: true))
        #expect(NightMark.mark(score: 75, hasForecast: false, differentiate: true) == .star(filled: false))
        #expect(NightMark.mark(score: 74, hasForecast: true, differentiate: true) == .dot(filled: true))
        #expect(NightMark.mark(score: 92, hasForecast: false, differentiate: false) == .dot(filled: false))
        let dot = NightMark.dot(filled: true).path(center: .zero, radius: 4).boundingRect
        let star = NightMark.star(filled: true).path(center: .zero, radius: 4).boundingRect
        #expect(star.height > dot.height && abs(dot.width - 8) < 0.01)
    }
    @MainActor @Test func bestNightsRotorSkipsPastNightsAndKeepsDateOrder() throws {
        let jotr = try park("jotr")
        let nights = try (1...20).map { try night(jotr, String(format: "2026-12-%02d", $0), clouds: 0) }
        let tonight = nights[4].id
        let stops = CalendarView.bestNights(nights, after: tonight)
        #expect(!stops.isEmpty && stops.allSatisfy { $0.id >= tonight })
        #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.id < $1.id })
        let byID = Dictionary(uniqueKeysWithValues: nights.map { ($0.id, $0) })
        #expect(stops.allSatisfy { (byID[$0.id]?.score.value ?? 0) >= 75 } || stops.count <= 3)
    }

    // MARK: Speech

    @Test func pronunciationsAnnotateOnlyTheirWords() {
        let text = "Bortle estimate, class 2 of 9. Bortle is a scale."
        let found = NyxSpeech.annotations(in: text)
        #expect(found.count == 2 && found.allSatisfy { text[$0.range] == "Bortle" && $0.ssml.contains("phoneme") })
        #expect(NyxSpeech.annotations(in: "Darkness score 94").isEmpty)
        #expect(NyxSpeech.annotations(in: "Sagittarius A* is the core.").first?.ssml.contains("star") == true)
    }
}
