import AppIntents
import CoreSpotlight
import Foundation
import Testing
@testable import Nyx

/// Widgets (relevance, month, park cycling), the "Find the best night" intent, Spotlight entities,
/// Ask Nyx's tools and the MetricKit reading: everything the platform surfaces compute.
@MainActor struct PlatformTests {
    let parks: [Park]
    init() throws { parks=try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    /// 2026-12-01, 21:00 UTC: afternoon in every US park, so "tonight" is Dec 1 everywhere.
    let now = Date(timeIntervalSince1970: 1_796_158_800)
    /// A full cloud forecast for `days` days from yesterday, clear (5%) unless `cover` says otherwise.
    func forecast(days: Int = 16, cover: Double = 5) -> Forecast {
        let first = (floor(now.timeIntervalSince1970/86400)-1)*86400
        let hours = (0..<(days*24)).map { first+Double($0)*3600 }
        return Forecast(updated: now.addingTimeInterval(-1800), times: hours, clouds: hours.map { _ in cover })
    }
    func night(_ park: Park, offset: Int = 0, value: Int, forecast: Bool) -> Night {
        let sky = AstronomyEngine().conditions(for: park, on: park.date(park.currentNight(at: now), addingDays: offset))
        return Night(park: park, sky: sky, score: DarknessScore(value: value, moonPoints: 30, cloudPoints: forecast ? 20 : nil, bortlePoints: 15, lengthPoints: 10), cloudCover: forecast ? 5 : nil, forecastUpdated: forecast ? now : nil)
    }

    // MARK: Widget relevance

    @Test func duskWindowCoversSunsetToAnHourIntoDarknessOnGoodNights() throws {
        let jotr = try park("jotr")
        let good = night(jotr, value: 72, forecast: true)
        let window = try #require(NightPlanner.duskWindow(good))
        let sunset = try #require(good.sky.sunset), dark = try #require(good.sky.darkStart)
        #expect(window.start == sunset.addingTimeInterval(-90*60))
        #expect(window.end == dark.addingTimeInterval(3600))
        // Fair nights never rise; a moon-and-darkness-only score must reach Excellent.
        #expect(NightPlanner.duskWindow(night(jotr, value: 59, forecast: true)) == nil)
        #expect(NightPlanner.duskWindow(night(jotr, value: 72, forecast: false)) == nil)
        #expect(NightPlanner.duskWindow(night(jotr, value: 80, forecast: false)) != nil)
        // Inside the window the widget's score is the night's; outside it is zero.
        let inside = NightPlanner.relevance(at: sunset, nights: [good])
        #expect(abs(inside.score - 0.72) < 0.0001 && inside.duration == window.end.timeIntervalSince(sunset))
        #expect(NightPlanner.relevance(at: window.start.addingTimeInterval(-60), nights: [good]).score == 0)
        // Two saved parks at dusk together: the better night sets the relevance.
        let both = NightPlanner.relevance(at: sunset, nights: [good, night(jotr, value: 91, forecast: true)])
        #expect(abs(both.score - 0.91) < 0.0001)
    }
    @Test func noDuskWindowWithoutTrueDarkness() throws {
        // Denali in June: no astronomical darkness, so no "go tonight" moment, whatever the score.
        let dena = try park("dena")
        let june = Date(timeIntervalSince1970: 1_782_086_400)
        let sky = AstronomyEngine().conditions(for: dena, on: dena.currentNight(at: june))
        #expect(sky.darkHours == 0)
        let midsummer = Night(park: dena, sky: sky, score: DarknessScore(value: 39, moonPoints: 40, cloudPoints: 25, bortlePoints: 17, lengthPoints: 0), cloudCover: 0, forecastUpdated: june)
        #expect(NightPlanner.duskWindow(midsummer) == nil)
    }

    // MARK: Large widget month

    @Test func monthStartsUnderTonightsWeekdayAndMarksTheBestAndEvents() throws {
        let jotr = try park("jotr")
        let planner = NightPlanner(forecasts: ["jotr": forecast()])
        let clock = ContinuousClock()
        var month: NightPlanner.Month?
        let elapsed = clock.measure { month = planner.month(jotr, at: now) }
        let result = try #require(month)
        // Measured for the widget's budget: 30+ skies plus shower and eclipse checks, once per night turnover.
        print("Large widget month (jotr, 35 cells, events): \(elapsed)")
        #expect(elapsed < .seconds(2))
        #expect(result.nights.count == 35)
        let lead = result.nights.prefix { $0 == nil }.count
        var calendar = jotr.calendar; calendar.firstWeekday = Calendar.current.firstWeekday
        #expect(lead == (calendar.component(.weekday, from: jotr.currentNight(at: now)) - calendar.firstWeekday + 7) % 7)
        #expect(result.tonight?.id == jotr.currentNight(at: now))
        let nights = result.nights.compactMap { $0 }
        #expect(result.best == nights.sorted(by: NightPlanner.better).first?.id)
        // Clouds only where the forecast reaches (16 days from yesterday); hollow after that.
        #expect(!nights.prefix(10).contains { !$0.score.hasForecast })
        #expect(!nights.suffix(10).contains { $0.score.hasForecast })
        // The Geminids peak (Dec 13-14, 2026) carries the meteor glyph.
        let marked = nights.filter { result.events[$0.id] == .meteors }.map { jotr.isoDay($0.id) }
        #expect(marked.contains { $0.hasPrefix("2026-12-1") })
    }

    // MARK: Cycling saved parks

    @Test func cyclingWalksSavedParksByTonightsScoreThenReturnsToTheBest() throws {
        let suite = "nyx-tests-widget-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = try ["jotr", "grba", "deva"].map(park)
        let snapshot = SavedSkySnapshot(parks: saved, forecasts: [:])
        let planner = NightPlanner(forecasts: [:])
        let tonight = saved.map { planner.night($0, on: $0.currentNight(at: now), now: now) }
        let order = WidgetSelection.ordered(tonight).map(\.park.id)
        #expect(WidgetSelection.pick(tonight, defaults: defaults)?.park.id == order[0])
        var seen: [String] = []
        for _ in 0..<3 {
            WidgetSelection.cycle(snapshot: snapshot, now: now, defaults: defaults)
            seen.append(try #require(WidgetSelection.pick(tonight, defaults: defaults)).park.id)
        }
        #expect(seen == [order[1], order[2], order[0]])
        #expect(WidgetSelection.position(of: try #require(tonight.first { $0.park.id == order[2] }), in: tonight) == 3)
        // The next day the choice lapses: tomorrow's nights do not match the chosen night.
        WidgetSelection.cycle(snapshot: snapshot, now: now, defaults: defaults)
        let tomorrow = saved.map { planner.night($0, on: $0.date($0.currentNight(at: now), addingDays: 1), now: now) }
        #expect(WidgetSelection.pick(tomorrow, defaults: defaults)?.park.id == WidgetSelection.ordered(tomorrow).first?.park.id)
        // One saved park: nothing to cycle, and no stale choice is kept.
        WidgetSelection.cycle(snapshot: SavedSkySnapshot(parks: [saved[0]], forecasts: [:]), now: now, defaults: defaults)
        #expect(defaults.dictionary(forKey: WidgetSelection.key) == nil)
    }

    // MARK: Find the best night

    @Test func bestNightIsTheHighestScoreInTheRangeAndClamped() throws {
        let jotr = try park("jotr"), grba = try park("grba")
        let planner = NightPlanner(forecasts: ["jotr": forecast()])
        let answer = try #require(BestNightSearch.answer(parks: [jotr, grba], planner: planner, from: now, nights: 14, now: now))
        let all = [jotr, grba].flatMap { planner.nights($0, from: now, count: 14, now: now) }
        // Ranked as every list of nights is: the score with a forecast, the usual clouds without one.
        #expect(answer.best.rankScore == all.map(\.rankScore).max())
        #expect(answer.ranked.count == 5 && zip(answer.ranked, answer.ranked.dropFirst()).allSatisfy { NightPlanner.better($0, $1) })
        #expect(BestNightSearch.answer(parks: [jotr], planner: planner, from: now, nights: 0, now: now)?.count == 1)
        #expect(BestNightSearch.answer(parks: [jotr], planner: planner, from: now, nights: 99, now: now)?.count == 30)
        #expect(BestNightSearch.answer(parks: [], planner: planner, from: now, nights: 14, now: now) == nil)
        // A night with a forecast outranks an equal rank without one: it is the surer number. (A night
        // without a forecast ranks by its score under the park's usual clouds, `Night.rankScore`.)
        let unsure = night(jotr, offset: 1, value: 80, forecast: false)
        let sure = night(jotr, offset: 3, value: unsure.rankScore, forecast: true)
        #expect(NightPlanner.best([unsure, sure])?.id == sure.id)
    }
    /// A picked day is that day's night, whatever the time attached to it: midnight Pacific, or
    /// 9 AM Eastern (before sunrise in California), never starts the night before. A day already
    /// past starts tonight.
    @Test func pickedStartDayIsThatNight() throws {
        let jotr = try park("jotr")
        let planner = NightPlanner(forecasts: [:])
        var pacific = Calendar(identifier: .gregorian); pacific.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let midnight = try #require(pacific.date(from: DateComponents(year: 2026, month: 12, day: 10)))
        let picked = TripDay(midnight, calendar: pacific)
        #expect(picked.iso == "2026-12-10")
        let answer = try #require(BestNightSearch.answer(parks: [jotr], planner: planner, day: picked, nights: 3, now: now))
        #expect(answer.ranked.allSatisfy { jotr.isoDay($0.id) >= "2026-12-10" })
        #expect(Set(answer.ranked.map { jotr.isoDay($0.id) }) == ["2026-12-10", "2026-12-11", "2026-12-12"])
        let past = try #require(BestNightSearch.answer(parks: [jotr], planner: planner, day: TripDay(year: 2020, month: 1, day: 1), nights: 1, now: now))
        #expect(past.best.id == jotr.currentNight(at: now))
        #expect(BestNightSearch.answer(parks: [jotr], planner: planner, day: nil, nights: 1, now: now)?.best.id == jotr.currentNight(at: now))
    }
    /// A journal entry written after midnight or the next morning belongs to the night before;
    /// one written after sunset, to tonight.
    @Test func journalNightIsTheLastNightBegun() throws {
        let jotr = try park("jotr")
        var pacific = Calendar(identifier: .gregorian); pacific.timeZone = jotr.timeZone
        func at(_ day: Int, _ hour: Int) throws -> Date { try #require(pacific.date(from: DateComponents(year: 2026, month: 12, day: day, hour: hour))) }
        #expect(jotr.isoDay(jotr.lastNightBegun(at: try at(5, 1))) == "2026-12-04")
        #expect(jotr.isoDay(jotr.lastNightBegun(at: try at(5, 10))) == "2026-12-04")
        #expect(jotr.isoDay(jotr.lastNightBegun(at: try at(5, 21))) == "2026-12-05")
    }
    @Test func bestNightDialogIsHonestAndShorterForVoice() throws {
        let jotr = try park("jotr")
        let planner = NightPlanner(forecasts: [:])
        let answer = try #require(BestNightSearch.answer(parks: [jotr], planner: planner, from: now, nights: 30, now: now))
        let full = BestNightSearch.dialog(answer, voiceOnly: false), voice = BestNightSearch.dialog(answer, voiceOnly: true)
        #expect(full.contains("Joshua Tree") && full.contains("\(answer.best.score.value) out of 100"))
        #expect(full.contains("Moon and darkness only") && full.contains("Confirm park access"))
        #expect(voice.count < full.count && voice.contains("Clouds aren't forecast yet."))
        // Gates of the Arctic in June: no true darkness, said plainly.
        let gaar = try park("gaar")
        let june = Date(timeIntervalSince1970: 1_782_086_400)
        let polar = try #require(BestNightSearch.answer(parks: [gaar], planner: planner, from: june, nights: 7, now: june))
        #expect(BestNightSearch.dialog(polar, voiceOnly: false).hasPrefix("No true darkness"))
    }
    @Test func snippetBrowsingStepsThroughTheRankedNightsAndWraps() throws {
        let suite = "nyx-tests-browse-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        BestNightBrowse.reset(defaults)
        for expected in [1, 2, 0] { BestNightBrowse.advance(count: 3, defaults); #expect(BestNightBrowse.rank(defaults) == expected) }
    }

    // MARK: Spotlight and App Intents

    @Test func spotlightItemsAreTheParkEntities() throws {
        let items = SpotlightIndexer.items(parks)
        #expect(items.count == 63 && Set(items.map(\.uniqueIdentifier)) == Set(parks.map(\.id)))
        let jotr = try #require(items.first { $0.uniqueIdentifier == "jotr" })
        #expect(jotr.domainIdentifier == SpotlightIndexer.domain)
        #expect(jotr.attributeSet.title == "Joshua Tree" && jotr.attributeSet.keywords?.contains("dark sky park") == true)
        #expect(try #require(items.first { $0.uniqueIdentifier == "dena" }).attributeSet.keywords?.contains("dark sky park") == false)
        if #available(iOS 27.0, *) {
            #expect(jotr.relatedAppEntityIdentifier == EntityIdentifier(for: ParkEntity.self, identifier: "jotr"))
        }
        let entity = ParkEntity(try park("jotr"))
        #expect(entity.id == "jotr" && entity.name == "Joshua Tree" && entity.state == "CA" && entity.darkSky)
        #expect(entity.attributeSet.contentDescription == jotr.attributeSet.contentDescription)
    }
    @Test func parkQueryFindsParksAndSuggestsAll() async throws {
        let query = ParkQuery()
        #expect(try await query.suggestedEntities().count == 63)
        #expect(try await query.entities(matching: "joshua").map(\.id) == ["jotr"])
        #expect(try await query.entities(for: ["grca", "arch"]).map(\.id).sorted() == ["arch", "grca"])
    }
    @Test func openParkRequestIsTakenOnceAndExpires() throws {
        let suite = "nyx-tests-open-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        ParkOpenRequest.post(parkID: "grca", now: now, defaults: defaults)
        #expect(ParkOpenRequest.take(now: now.addingTimeInterval(5), defaults: defaults) == "grca")
        #expect(ParkOpenRequest.take(now: now.addingTimeInterval(6), defaults: defaults) == nil)
        ParkOpenRequest.post(parkID: "grca", now: now, defaults: defaults)
        #expect(ParkOpenRequest.take(now: now.addingTimeInterval(120), defaults: defaults) == nil)
    }

    // MARK: Ask Nyx's tools

    @Test func toolsReturnComputedRecordsTheModelCanCite() throws {
        let lookup = NightLookup(parks: parks, forecasts: ["jotr": forecast()], now: now)
        let best = lookup.bestNights(park: "Joshua Tree", from: "2026-12-01", nights: 30)
        #expect(best.count == 5 && best.allSatisfy { $0.hasPrefix("Joshua Tree;") && $0.contains("(2026-12-") })
        // Records carry the engine's own score, best first.
        let planner = NightPlanner(forecasts: ["jotr": forecast()])
        let top = try #require(planner.bestNights([try park("jotr")], from: now, count: 30, now: now, limit: 1).first)
        #expect(best[0] == lookup.describe(top))
        #expect(best[0].contains("cloud forecast included") && best.last?.contains("score") == true)
        // "tonight" and unreadable dates start tonight; an unknown park says so instead of guessing.
        #expect(lookup.bestNights(park: "joshua tree", from: "tonight", nights: 3, limit: 3).count == 3)
        #expect(lookup.bestNights(park: "Atlantis", from: "tonight", nights: 3).first?.hasPrefix("No national park matched") == true)
        // What's up on the Geminid peak names the shower.
        let sky = lookup.whatsUp(park: "Joshua Tree", on: "2026-12-13")
        #expect(sky.first?.contains("2026-12-13") == true && sky.contains { $0.contains("Geminids") })
        // Parks near Arches: straight-line miles only, within the radius, Canyonlands among them.
        let near = lookup.parksNear(park: "Arches", radiusMiles: 150)
        #expect(near.contains { $0.hasPrefix("Canyonlands") } && near.allSatisfy { $0.contains("straight-line") })
        let miles = near.compactMap { $0.split(separator: ";").dropFirst().first?.split(separator: " ").first.flatMap { Int($0) } }
        #expect(miles.count == near.count && miles.allSatisfy { $0 <= 150 })
        // The starting park counts (0 miles); American Samoa has no other park within reach.
        let samoa = lookup.parksNear(park: "American Samoa", radiusMiles: 100)
        #expect(samoa.count == 1 && samoa[0].contains("0 miles straight-line"))
    }
    @Test func ledgerNumbersToolRecordsAfterTheInjectedOnes() {
        let ledger = GuideLedger(firstID: 4)
        #expect(ledger.add(["a", "b"]) == "ID 4: a\nID 5: b")
        #expect(ledger.add(["c"]) == "ID 6: c")
        #expect(ledger.ids == [4, 5, 6] && ledger.all == ["a", "b", "c"])
    }

    // MARK: MetricKit

    @Test func luminanceReadingIsOnlyEverAMeasuredValue() throws {
        let end = now
        #expect(LuminanceReading.make(percent: nil, end: end) == nil)
        #expect(LuminanceReading.make(percent: .nan, end: end) == nil)
        #expect(LuminanceReading.make(percent: 140, end: end) == nil)
        let dim = try #require(LuminanceReading.make(percent: 0.4, end: end))
        #expect(dim.rounded == 1 && !dim.sentence.contains("Debug"))
        #expect(try #require(LuminanceReading.make(percent: 6.6, end: end)).sentence.contains("averaged 7%"))
        let suite = "nyx-tests-luminance-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LuminanceReading.load(defaults) == nil)
        dim.save(defaults)
        #expect(LuminanceReading.load(defaults) == dim)
        #expect(LuminanceReading.fixture.sentence.hasPrefix("Debug fixture, not a measurement."))
    }
}
