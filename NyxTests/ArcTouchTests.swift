import Foundation
import Testing
@testable import Nyx

/// Feel the night under your finger (`ArcTouch`), and the drawn marks that follow Bold Text and
/// Increase Contrast. Real computed nights throughout.
@MainActor @Suite struct ArcTouchTests {
    let engine = AstronomyEngine()
    func park(_ id: String) throws -> Park { try #require(try ParkData.load().first(where: { $0.id == id })) }
    func night(_ park: Park, _ day: String) throws -> Night {
        let sky = engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
        return Night(park: park, sky: sky, score: ScoreEngine().score(sky: sky, bortle: park.bortleEstimate, cloudCover: nil), cloudCover: nil, forecastUpdated: nil)
    }
    /// The night's nights, one per evening, `days` from `start`.
    func nights(_ park: Park, from start: String, days: Int) throws -> [Night] {
        let first = try #require(try? Date(start+"T20:00:00Z", strategy: .iso8601))
        return (0..<days).map { day in
            let sky = engine.conditions(for: park, on: park.evening(first.addingTimeInterval(Double(day)*86_400)))
            return Night(park: park, sky: sky, score: ScoreEngine().score(sky: sky, bortle: park.bortleEstimate, cloudCover: nil), cloudCover: nil, forecastUpdated: nil)
        }
    }

    /// Denali at the solstice: the finger never meets true darkness, never clicks for it, and every
    /// resting line says why, in the arc's own sentence.
    @Test func denaliInJuneHasNoTrueDarknessCrossing() throws {
        let dena = try park("dena"), june = try night(dena, "2026-06-21")
        #expect(june.sky.darkHours == 0)
        let columns = ArcTouch.columns(night: june, window: ArcTouch.window(june))
        #expect(columns.count == ArcTouch.columnCount)
        #expect(!columns.contains { $0.sky == .darkness })
        #expect(!columns.flatMap(\.crossings).contains { $0.firm })
        #expect(ArcTouch.crossed(columns, from: 0, to: columns.count-1).allSatisfy { !$0.firm })
        for x in stride(from: 0.0, through: 390, by: 39) {
            let sample = ArcTouch.sample(x: x, width: 390, columns: columns, night: june)
            #expect(sample.spoken.hasSuffix("No true darkness tonight at this latitude."))
            #expect(sample.crossing?.firm != true)
        }
        // Another night than tonight names it as such, as the arc does.
        let later = ArcTouch.sample(x: 195, width: 390, columns: columns, night: june, tonight: false)
        #expect(later.spoken.hasSuffix("No true darkness on this night at this latitude."))
    }

    /// A Moon rising inside true darkness ticks in the column the arc draws it in, and the sky's
    /// words change from "Moon down" to "Moon up" across it, in park time.
    @Test func moonriseInsideTheWindowCrossesAtItsColumn() throws {
        let jotr = try park("jotr")
        let night = try #require(try nights(jotr, from: "2026-10-01", days: 30).first { night in
            guard let rise = night.sky.moonrise, let start = night.sky.darkStart, let end = night.sky.darkEnd else { return false }
            return rise > start.addingTimeInterval(3600) && rise < end.addingTimeInterval(-3600)
        })
        let window = ArcTouch.window(night), rise = try #require(night.sky.moonrise)
        let expected = Int(rise.timeIntervalSince(window.start)/window.end.timeIntervalSince(window.start)*Double(ArcTouch.columnCount))
        let columns = ArcTouch.columns(night: night, window: window)
        #expect(columns[expected].crossings.contains(.moonrise))
        #expect(columns.indices.filter { columns[$0].crossings.contains(.moonrise) } == [expected])
        let width = 384.0, x = (Double(expected)+0.5)*width/Double(ArcTouch.columnCount)
        let sample = ArcTouch.sample(x: x, width: width, night: night, window: window)
        #expect(sample.column == expected && sample.crossing == .moonrise)
        #expect(!ArcTouch.Milestone.moonrise.firm && ArcTouch.Milestone.darknessBegins.firm)
        // Before and after: the same true darkness, the Moon down then up.
        let before = columns[expected-3], after = columns[expected+3]
        #expect(before.sky == .darkness && !before.moonUp && after.sky == .darkness && after.moonUp)
        let spoken = ArcTouch.spoken(before, night: night)
        #expect(spoken.hasSuffix(". True darkness. Moon down."))
        #expect(ArcTouch.spoken(after, night: night).hasSuffix(". True darkness. Moon up."))
        // Park-local, to five minutes.
        let rounded = Date(timeIntervalSince1970: (before.date.timeIntervalSince1970/300).rounded()*300)
        #expect(spoken.hasPrefix(jotr.time(rounded)+"."))
        // A quick slide across the whole arc still meets each moment once, in order.
        let crossed = ArcTouch.crossed(columns, from: 0, to: columns.count-1)
        #expect(crossed.filter { $0 == .moonrise }.count == 1)
        #expect(crossed.contains(.darknessBegins) && crossed.contains(.darknessEnds))
        let begins = try #require(crossed.firstIndex(of: .darknessBegins)), ends = try #require(crossed.firstIndex(of: .darknessEnds)), risen = try #require(crossed.firstIndex(of: .moonrise))
        #expect(begins < risen && risen < ends)
        #expect(ArcTouch.crossed(columns, from: columns.count-1, to: 0) == crossed.reversed())
    }

    /// Near a new Moon the hum grows steadily through evening twilight into true darkness and
    /// fades steadily through morning twilight, the same strengths Feel tonight plays.
    @Test func strengthIsMonotonicThroughTwilight() throws {
        let jotr = try park("jotr")
        let night = try #require(try nights(jotr, from: "2026-10-01", days: 30).min { $0.sky.moon.illumination < $1.sky.moon.illumination })
        #expect(night.sky.moon.illumination < 0.05)
        let columns = ArcTouch.columns(night: night, window: ArcTouch.window(night))
        let sunset = try #require(columns.firstIndex { $0.sky == .twilight })
        let dark = try #require(columns.firstIndex { $0.sky == .darkness })
        let dawn = try #require(columns.lastIndex { $0.sky == .darkness })
        let sunrise = try #require(columns.lastIndex { $0.sky == .twilight })
        #expect(sunset < dark && dark < dawn && dawn < sunrise)
        let evening = columns[sunset...dark].map(\.strength), morning = columns[dawn...sunrise].map(\.strength)
        #expect(zip(evening, evening.dropFirst()).allSatisfy { $0 <= $1+1e-9 })
        #expect(zip(morning, morning.dropFirst()).allSatisfy { $0+1e-9 >= $1 })
        #expect(evening.first ?? 1 < 0.3 && evening.last ?? 0 > 0.9)
        // The sky's words through the evening: Sun up, twilight, then true darkness.
        #expect(columns[0].sky == .sunUp && ArcTouch.spoken(columns[0], night: night).hasSuffix(". Sun up."))
        #expect(ArcTouch.spoken(columns[sunset], night: night).hasSuffix(". Twilight."))
        // The same strength rule as Feel tonight.
        let mid = columns[(dark+dawn)/2]
        let sun = engine.solarAltitude(at: mid.date, park: jotr), moon = engine.lunarAltitude(at: mid.date, park: jotr)
        #expect(abs(mid.strength - NightTouch.strength(darkness: NightSonification.darkness(sunAltitude: sun), moonlight: night.sky.moon.illumination*min(1, max(0, moon/3)))) < 1e-12)
    }

    /// Bold Text and Increase Contrast make outlines 1.6× heavier; nothing changes otherwise.
    @Test func strokeFollowsBoldTextAndIncreaseContrast() {
        #expect(NyxPalette(nightVision: false, highContrast: false).stroke == 1)
        #expect(NyxPalette(nightVision: true, highContrast: false).stroke == 1)
        #expect(NyxPalette(nightVision: false, highContrast: true).stroke == 1.6)
        #expect(NyxPalette(nightVision: false, highContrast: false, boldText: true).stroke == 1.6)
        #expect(NyxPalette(nightVision: true, highContrast: false, brighterRed: true, boldText: true).stroke == 1.6)
    }
    /// A mark that is not filled never shrinks below 2.6 pt × stroke, so a score-40 early look
    /// still shows its half; filled marks keep the size their score gives them.
    @Test func unfilledMarksKeepAMinimumRadius() {
        let forty = 1.3+3.6*pow(0.4, 1.5)
        #expect(forty < 2.6)
        #expect(NightMark.drawnRadius(forty, fill: .half, stroke: 1) == 2.6)
        #expect(NightMark.drawnRadius(forty, fill: .hollow, stroke: 1.6) == 2.6*1.6)
        #expect(NightMark.drawnRadius(forty, fill: .full, stroke: 1.6) == forty)
        #expect(NightMark.drawnRadius(5, fill: .half, stroke: 1) == 5)
    }
    /// The week strip's pitch grows with the caption beside it and stops at 1.8×.
    @Test func weekStripPitchScalesAndCaps() {
        #expect(WeekStrip.pitch(13) == 13)
        #expect(WeekStrip.pitch(11) == 13)
        #expect(WeekStrip.pitch(17) == 17)
        #expect(abs(WeekStrip.pitch(40) - 23.4) < 1e-9)
    }
}
