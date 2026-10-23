import Foundation
import Testing
@testable import Nyx

/// The plain sentence under the dial (`NightVerdict`) and the one way every dial says how sure the
/// forecast is (`ForecastSpread`). Real computed nights from the engine, no mocked sky.
@Suite struct NightVerdictTests {
    let engine = AstronomyEngine()
    func sky(_ park: Park, _ day: String) throws -> SkyConditions {
        engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
    }
    func night(_ park: Park, _ sky: SkyConditions, score: Int) -> Night {
        Night(park: park, sky: sky, score: DarknessScore(value: score, moonPoints: 30, cloudPoints: 20, bortlePoints: 16, lengthPoints: 10), cloudCover: 10, forecastUpdated: .now)
    }
    func verdict(_ park: Park, _ sky: SkyConditions, darker: Night? = nil) -> NightVerdict.Line? {
        NightVerdict.line(sky: sky, core: SkyAlmanac().core(for: park, sky: sky), park: park, darker: darker)
    }

    /// Joshua Tree on Oct 21, 2026: a waxing gibbous Moon sets in the small hours, the core is up only
    /// at dusk, under it. The line says both, so "Good" never reads as a Milky Way night.
    @Test func brightMoonAndBriefCoreAreSaidFirst() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-10-21")
        let line = try #require(verdict(jotr, sky))
        #expect(line.text.hasPrefix("Moon up until "))
        #expect(line.text.contains("% lit."))
        #expect(line.text.contains("Milky Way core"))
        #expect(!line.text.contains("with the Moon down"))
    }
    /// A moonless summer night: no Moon in the way, and the core's Moon-free hours as a range,
    /// spoken as "from … to …".
    @Test func moonlessSummerNightGivesTheCoreWindow() throws {
        let jotr = try park("jotr")
        let days = (1...28).map { String(format: "2027-07-%02d", $0) }
        let dark = try #require(try days.map { try sky(jotr, $0) }.first { $0.moon.illumination < 0.05 })
        let line = try #require(verdict(jotr, dark))
        // In the watch's and share card's words.
        #expect(line.text.hasPrefix("Moon-free through all of true darkness.") || line.text.hasPrefix("Moon too thin to matter, "))
        #expect(line.text.contains("Milky Way core clear of moonlight, "))
        #expect(line.spoken.contains("Milky Way core clear of moonlight from "))
        #expect(!line.spoken.contains(" – "))
    }
    /// Winter in the north: the core is not up in true darkness, said plainly rather than left out.
    @Test func coreOutOfSeasonIsSaid() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-12-13")
        #expect(verdict(jotr, sky)?.text.contains("Milky Way core not up in true darkness.") == true)
    }
    /// Alaska, where the core never climbs: no core sentence (What's up explains it there), and no
    /// line at all on a night with no true darkness.
    /// A night beyond the forecast is never named beside tonight's as if both were forecasts.
    @Test func laterNightsSayWhatTheyRestOn() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-10-28")
        func scored(_ basis: CloudBasis) -> String {
            NightVerdict.scored(Night(park: jotr, sky: sky, score: DarknessScore(value: 82, moonPoints: 30, cloudPoints: 20, bortlePoints: 16, lengthPoints: 10, basis: basis), cloudCover: nil, forecastUpdated: nil))
        }
        #expect(scored(.forecast) == "82")
        #expect(scored(.usual) == "82, an estimate")
        #expect(scored(.blended(weight: 0.5, leadDays: 6)) == "82, an early look")
    }
    /// "All through true darkness" means one thing on every device: the rounded Moon-free percent the
    /// watch and Vision Pro show is 100 exactly when the iPhone's line says it.
    @Test func wholeNightMoonMatchesTheWatch() throws {
        let jotr = try park("jotr")
        let days = (1...60).map { Calendar.current.date(byAdding: .day, value: $0, to: Date(timeIntervalSince1970: 1_793_000_000)) ?? .now }
        for day in days {
            let sky = engine.conditions(for: jotr, on: jotr.evening(day))
            guard sky.darkHours > 0, let line = NightVerdict.moonSentence(sky: sky, park: jotr) else { continue }
            #expect(line.hasPrefix("Moon-free through all") == (sky.moonDownPercent == 100))
            if sky.moonDownPercent == 0 && sky.moon.illumination >= 0.05 { #expect(line.hasPrefix("Moon up all through")) }
        }
    }
    @Test func farNorthAndNoDarknessStayQuiet() throws {
        let gaar = try park("gaar"), dena = try park("dena")
        let winter = try sky(gaar, "2027-01-15")
        #expect(verdict(gaar, winter)?.text.contains("Milky Way") != true)
        #expect(verdict(dena, try sky(dena, "2027-06-21")) == nil)
    }
    /// A darker night is named only when it clears the shown one by the margin and reaches Good,
    /// the earliest of equals.
    @Test func darkerNightNeedsAClearMargin() throws {
        let jotr = try park("jotr")
        let days = ["2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24"]
        let skies = try days.map { try sky(jotr, $0) }
        let shown = night(jotr, skies[0], score: 64)
        #expect(NightVerdict.darker(than: shown, among: [night(jotr, skies[1], score: 70)]) == nil)
        let picked = NightVerdict.darker(than: shown, among: [night(jotr, skies[1], score: 74), night(jotr, skies[2], score: 82), night(jotr, skies[3], score: 82)])
        #expect(picked?.id == skies[2].evening)
        let low = night(jotr, skies[0], score: 40)
        #expect(NightVerdict.darker(than: low, among: [night(jotr, skies[1], score: 55)]) == nil)
        // Never a night before the one shown.
        #expect(NightVerdict.darker(than: night(jotr, skies[2], score: 50), among: [night(jotr, skies[1], score: 90)]) == nil)
        let line = try #require(verdict(jotr, skies[0], darker: picked))
        #expect(line.text.hasSuffix("82."))
        #expect(line.text.contains("Darker on "))
    }
    /// What's up shows the first three blocks of the shared order and keeps every other one, in the
    /// same order, behind "More up tonight": nothing dropped, nothing reordered.
    @MainActor @Test func whatsUpLeadsWithThreeAndKeepsTheRest() throws {
        let jotr = try park("jotr")
        let up = WhatsUp(park: jotr, sky: try sky(jotr, "2026-10-21"), isTonight: true)
        let blocks = WhatsUpPanel.blocks(up), layout = up.layout
        let all = layout.first.map(\.id) + (up.planets.isEmpty ? [] : ["planets"]) + layout.after.map(\.id)
        #expect(blocks.shown.count == min(WhatsUpPanel.leading, all.count))
        #expect((blocks.shown + blocks.more).map(\.id) == all)
        #expect(blocks.shown.first?.id == layout.first.first?.id)
        #expect(blocks.shown.contains { $0.id == "planets" })
    }
    /// When a cap holds the score below its parts, the readout says the cap, then their sum, in the breakdown's words, so the
    /// four numbers and the dial never seem to disagree; with no binding cap it says nothing.
    @Test func readoutSaysTheSumBeforeTheCap() {
        let capped = DarknessScore(value: 64, moonPoints: 22, cloudPoints: 21, bortlePoints: 15, lengthPoints: 15, limit: .moonlight(64))
        #expect(ScoreReadout.limitLine(capped, tonight: true) == "Moonlight limits tonight to 64. The four parts add up to 73; the score takes the lowest cap that applies.")
        #expect(ScoreReadout.limitLine(capped, tonight: false) == "Moonlight limits this night to 64. The four parts add up to 73; the score takes the lowest cap that applies.")
        let loose = DarknessScore(value: 73, moonPoints: 22, cloudPoints: 21, bortlePoints: 15, lengthPoints: 15, limit: .moonlight(80))
        #expect(ScoreReadout.limitLine(loose, tonight: true) == nil)
    }
    /// Tonight and the park's page say a night's uncertainty the same way: the cloud spread when the
    /// models disagree, the score range otherwise, nothing when neither applies.
    @Test func forecastSpreadIsOneLine() {
        let apart = ModelAgreement(low: 0, high: 78)
        #expect(ForecastSpread.line(agreement: apart, range: 30...64, tonight: true) == apart.sentence(tonight: true))
        #expect(ForecastSpread.line(agreement: ModelAgreement(low: 10, high: 40), range: 52...64, tonight: true) == ShareCard.rangeLine(52...64))
        #expect(ForecastSpread.line(agreement: ModelAgreement(low: 10, high: 12), range: nil, tonight: false) == nil)
    }
}
