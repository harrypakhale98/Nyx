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
        // The three words every list uses: no label, "early look", "usual clouds".
        #expect(scored(.usual) == "82, usual clouds")
        #expect(scored(.blended(weight: 0.5, leadDays: 6)) == "82, early look")
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
    /// A short name never ends in a bare number: "Constitution 1857" read as a place and a figure.
    @Test func shortNamesKeepADesignationAfterANumber() {
        #expect(Park.shortened("Constitution 1857 National Park") == "Constitution 1857 National Park")
        #expect(Park.shortened("Etosha National Park") == "Etosha")
        #expect(Park.shortened("Wrangell-St. Elias National Park & Preserve") == "Wrangell-St. Elias")
    }
    @Test func farNorthAndNoDarknessStayQuiet() throws {
        let gaar = try park("gaar"), dena = try park("dena")
        let winter = try sky(gaar, "2027-01-15")
        #expect(verdict(gaar, winter)?.text.contains("Milky Way") != true)
        #expect(verdict(dena, try sky(dena, "2027-06-21")) == nil)
    }
    /// A darker night is named only when it is the place's best night, clears the shown one by the
    /// margin and reaches Good; equals are told apart as every best night is (`NightPlanner.better`).
    @Test func darkerNightNeedsAClearMargin() throws {
        let jotr = try park("jotr")
        let days = ["2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24"]
        let skies = try days.map { try sky(jotr, $0) }
        let shown = night(jotr, skies[0], score: 64)
        #expect(NightVerdict.darker(than: shown, among: [shown, night(jotr, skies[1], score: 70)]) == nil)
        let ahead = [shown, night(jotr, skies[1], score: 74), night(jotr, skies[2], score: 82), night(jotr, skies[3], score: 82)]
        let picked = NightVerdict.darker(than: shown, among: ahead)
        #expect(picked?.id == NightPlanner.ranked(ahead).first?.id && picked?.score.value == 82)
        let low = night(jotr, skies[0], score: 40)
        #expect(NightVerdict.darker(than: low, among: [low, night(jotr, skies[1], score: 55)]) == nil)
        // Never a night before the one shown: the best night has passed it, and a lesser one is not named instead.
        #expect(NightVerdict.darker(than: night(jotr, skies[2], score: 50), among: [night(jotr, skies[1], score: 90), night(jotr, skies[3], score: 75)]) == nil)
        let line = try #require(verdict(jotr, skies[0], darker: picked))
        #expect(line.text.hasSuffix("82."))
        #expect(line.text.contains("Darker on "))
    }
    /// One answer to "which is this park's best night": the park page's "Darker on…", Tonight's
    /// capsule, Best nights and With the lights out name the same night with the same number, and
    /// Tonight prefers the answer's own park when it has a clearly darker night, even where another
    /// place ranks higher because a closure counts against this one.
    @Test func everySurfaceNamesTheSameBestNight() throws {
        let jotr = try park("jotr"), grba = try park("grba")
        let days = (21...30).map { "2026-10-\($0)" }
        let skies = try days.map { try sky(jotr, $0) }, other = try days.map { try sky(grba, $0) }
        let scores = [49, 55, 62, 70, 82, 80, 82, 66, 58, 50]
        let here = zip(skies, scores).map { night(jotr, $0, score: $1) }
        let there = zip(other, [50, 52, 60, 64, 70, 77, 75, 70, 60, 55]).map { night(grba, $0, score: $1) }
        let best = try #require(NightVerdict.best(here))
        #expect(best.score.value == 82 && best.id == NightPlanner.ranked(here).first?.id)
        // The park page, from tonight or from any night before the best.
        #expect(NightVerdict.darker(than: here[0], among: here)?.id == best.id)
        #expect(NightVerdict.darker(than: here[2], among: here)?.id == best.id)
        // Best nights' row for the park, and With the lights out.
        let ranking = BestNightsInReach.make([here, there])
        #expect(ranking.rows.first { $0.id == jotr.id }?.best.id == best.id)
        #expect(LightsOut.best(here, closure: "Road closed")?.id == best.id)
        // Tonight: the answer's own park first, though a closure ranks another place above it.
        let closures = [jotr.id: "Road closed"]
        #expect(BestNightsInReach.make([here, there], closures: closures).best?.park.id == grba.id)
        #expect(NightVerdict.darkerAhead(than: here[0], here: here, across: [here, there], closures: closures)?.id == best.id)
        // With nothing clearly darker at the answer's park, Best nights' best in reach, by the same margin.
        let flat = here.map { night(jotr, $0.sky, score: min($0.score.value, 55)) }
        let elsewhere = try #require(NightVerdict.darkerAhead(than: flat[0], here: flat, across: [flat, there], closures: [:]))
        #expect(elsewhere.park.id == grba.id && elsewhere.score.value == 77)
        #expect(NightVerdict.capsule(elsewhere, here: false) == "Darker on \(grba.dayLabel(elsewhere.id))\n\(grba.shortName) · 77")
        #expect(NightVerdict.capsule(best, here: true) == "Darker on \(jotr.dayLabel(best.id)) · 82")
    }
    /// Tonight's "Darker on…" and the park page's verdict use one rule: ten points clear of the night
    /// shown and at least Good, so the two never name darker nights by different measures.
    @Test func oneRuleForADarkerNight() throws {
        let jotr = try park("jotr"), skies = try ["2026-10-21", "2026-10-22"].map { try sky(jotr, $0) }
        let shown = night(jotr, skies[0], score: 50)
        #expect(!NightVerdict.clearlyDarker(night(jotr, skies[1], score: 59), than: shown))
        #expect(NightVerdict.clearlyDarker(night(jotr, skies[1], score: 60), than: shown))
        let good = night(jotr, skies[0], score: 64)
        #expect(!NightVerdict.clearlyDarker(night(jotr, skies[1], score: 73), than: good))
        #expect(NightVerdict.clearlyDarker(night(jotr, skies[1], score: 74), than: good))
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
    /// When a cap holds the score below its parts, the readout says the cap, then their sum, in plain words, so the
    /// four numbers and the dial never seem to disagree; with no binding cap it says nothing.
    @Test func readoutSaysTheSumBeforeTheCap() {
        let capped = DarknessScore(value: 64, moonPoints: 22, cloudPoints: 21, bortlePoints: 15, lengthPoints: 15, limit: .moonlight(64))
        #expect(ScoreReadout.limitLine(capped, tonight: true) == "Moonlight limits tonight to 64. The four parts alone would give 73.")
        #expect(ScoreReadout.limitLine(capped, tonight: false) == "Moonlight limits this night to 64. The four parts alone would give 73.")
        let loose = DarknessScore(value: 73, moonPoints: 22, cloudPoints: 21, bortlePoints: 15, lengthPoints: 15, limit: .moonlight(80))
        #expect(ScoreReadout.limitLine(loose, tonight: true) == nil)
        // The part that holds the score is the one ringed; smoke has no part, and a loose cap marks none.
        #expect(ScoreReadout.limiting(capped) == .moon && ScoreReadout.limiting(loose) == nil)
        let smoky = DarknessScore(value: 40, moonPoints: 22, cloudPoints: 21, bortlePoints: 15, lengthPoints: 15, limit: .smoke(40))
        #expect(ScoreReadout.limiting(smoky) == nil && ScoreReadout.limitLine(smoky, tonight: true) != nil)
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
