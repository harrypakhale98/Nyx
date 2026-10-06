import Foundation
import Testing
@testable import Nyx

/// What shows in "What's up", in what order and words, and when a shower earns a reminder.
/// Real computed nights from the bundled table; no mocked rates except where a rule is isolated.
@Suite struct WhatsUpTests {
    let engine = AstronomyEngine()
    func park(_ id: String) throws -> Park { try #require(try ParkData.load().first(where: { $0.id == id })) }
    func sky(_ park: Park, _ day: String) throws -> SkyConditions {
        engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
    }
    func night(_ park: Park, _ day: String, clouds: Double? = 5) throws -> Night {
        let sky = try sky(park, day)
        return Night(park: park, sky: sky, score: DarknessScore(value: 80, moonPoints: 30, cloudPoints: clouds.map { _ in 24 }, bortlePoints: 16, lengthPoints: 10), cloudCover: clouds, forecastUpdated: clouds == nil ? nil : .now)
    }

    @Test func bundledTableLoadsWithParsedPeaks() throws {
        let events = SkyEvents.shared
        #expect(events.meteorShowers.count == 13 && events.lunarEclipses.count == 17)
        let geminids = try #require(events.meteorShowers.first { $0.code == "GEM" })
        #expect(geminids.publishedPeaks?[2026] == (try? Date("2026-12-14T14:00:00Z", strategy: .iso8601)))
        #expect(events.lunarEclipses.first { $0.date == "2027-07-18" }?.penumbralMagnitude == 0.0014)
    }
    /// Timed core on a July night at Joshua Tree: a range in the figure, the same range spoken.
    @Test func coreIsTimedInSummer() throws {
        let jotr = try park("jotr")
        let up = WhatsUp(park: jotr, sky: try sky(jotr, "2027-07-10"), isTonight: true)
        #expect(up.core.timed && up.core.value?.contains("–") == true)
        #expect(up.core.spoken.contains("up in true darkness from"))
        #expect(up.core.detail.contains("south") && up.core.detail.contains("Moon-free from"))
    }
    /// Alaska keeps the seasonal guidance's words; no time is invented.
    @Test func coreNeverRisesInAlaska() throws {
        let dena = try park("dena"), sky = try sky(dena, "2027-01-15")
        let core = WhatsUp(park: dena, sky: sky, isTonight: true).core
        #expect(!core.timed && core.value == "Below the horizon")
        #expect(core.detail == engine.milkyWayGuidance(for: sky, park: dena))
    }
    @Test func coreOutOfSeasonIsSaidPlainly() throws {
        let jotr = try park("jotr")
        #expect(WhatsUp(park: jotr, sky: try sky(jotr, "2026-12-13"), isTonight: true).core.value == "Out of the night sky")
    }
    @Test func planetsBrightestFirstInWords() throws {
        let jotr = try park("jotr")
        let up = WhatsUp(park: jotr, sky: try sky(jotr, "2026-12-13"), isTonight: true)
        #expect(up.planets.first?.title == "Venus")
        #expect(up.planets.allSatisfy { ["very bright", "bright", "faint"].contains($0.note ?? "") })
        #expect(WhatsUp.brightness(-4) == "very bright" && WhatsUp.brightness(0.5) == "bright" && WhatsUp.brightness(1.5) == "faint")
        #expect(up.items.map(\.kind).first == .meteors)
    }
    /// Geminids 2026 from Joshua Tree: a glyph, a reminder, a rounded rate and the published ZHR beside it.
    @Test func geminidPeakAtJoshuaTree() throws {
        let jotr = try park("jotr")
        let up = WhatsUp(park: jotr, sky: try sky(jotr, "2026-12-13"), isTonight: true)
        #expect(up.events.glyph == .meteors && up.events.reminderShower?.shower.code == "GEM")
        let item = try #require(up.shower)
        #expect(item.note == "peak tonight" && item.value == "about 130 an hour")
        #expect(item.detail.contains("Moon down") && item.footnote?.contains("150 an hour") == true)
        #expect(up.events.headline(park: jotr) == "Geminids peak")
    }
    /// Quadrantids 2027: a sharp peak in early evening with the radiant low, said plainly; no reminder.
    @Test func poorPeakSaysWhy() throws {
        let jotr = try park("jotr")
        let up = WhatsUp(park: jotr, sky: try sky(jotr, "2027-01-03"), isTonight: true)
        let item = try #require(up.shower)
        #expect(item.detail.contains("radiant is low"))
        #expect(up.events.reminderShower == nil && up.events.glyph == .meteors)
    }
    @Test func peakNoteCountsFromTheNightShown() throws {
        let jotr = try park("jotr")
        let item = try #require(WhatsUp(park: jotr, sky: try sky(jotr, "2026-12-10"), isTonight: false).shower)
        #expect(item.note == "peak in 3 nights")
    }
    @Test func showerSelectionRules() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-12-13"), now = Date.now
        func shower(_ code: String, zhr: Double) -> SkyAlmanac.MeteorShower {
            SkyAlmanac.MeteorShower(code: code, name: code, start: "12-01", end: "12-31", peakSolarLongitude: 262, radiantRA: 112, radiantDec: 33, zhr: zhr, velocity: 35)
        }
        func night(_ s: SkyAlmanac.MeteorShower, rate: Int, peak: Bool) -> SkyAlmanac.ShowerNight {
            SkyAlmanac.ShowerNight(shower: s, peak: now, isPeakNight: peak, activity: 1, best: sky.darkStart, radiantAltitude: 40, moonDownAtBest: true, hourlyRate: rate)
        }
        // Under two an hour is hidden unless it is a notable shower's peak night.
        #expect(WhatsUp.Events.featured([night(shower("A", zhr: 5), rate: 1, peak: true)]) == nil)
        #expect(WhatsUp.Events.featured([night(shower("B", zhr: 80), rate: 1, peak: true)])?.shower.code == "B")
        #expect(WhatsUp.Events.featured([night(shower("C", zhr: 80), rate: 1, peak: false)]) == nil)
        #expect(WhatsUp.Events.featured([night(shower("D", zhr: 20), rate: 9, peak: false), night(shower("E", zhr: 150), rate: 40, peak: false)])?.shower.code == "E")
        // Reminders need a major shower's peak night, 20 an hour and the Moon down.
        #expect(WhatsUp.Events(shower: night(shower("F", zhr: 60), rate: 20, peak: true), eclipse: nil).reminderShower != nil)
        #expect(WhatsUp.Events(shower: night(shower("G", zhr: 20), rate: 25, peak: true), eclipse: nil).reminderShower == nil)
        #expect(WhatsUp.Events(shower: night(shower("H", zhr: 60), rate: 19, peak: true), eclipse: nil).reminderShower == nil)
        #expect(WhatsUp.rounded(rate: 137) == 140 && WhatsUp.rounded(rate: 23) == 25 && WhatsUp.rounded(rate: 7) == 7)
        #expect(WhatsUp.rateText(0) == "fewer than 1 an hour")
    }
    /// 2029-06-26 total eclipse: seen from Everglades with the Moon up; the eclipse outranks any shower.
    @Test func eclipseSeenAndUnseen() throws {
        let ever = try park("ever")
        let up = WhatsUp(park: ever, sky: try sky(ever, "2029-06-25"), isTonight: true)
        #expect(up.events.glyph == .eclipse && up.items.first?.kind == .eclipse)
        #expect(up.eclipse?.title == "Total lunar eclipse" && up.eclipse?.spoken.contains("Totality from") == true)
        // 2028-12-31 at 16:52 UTC (8:52 am in California, the night of Dec 30): Moon set, so no mark and an honest line.
        let jotr = try park("jotr")
        let hidden = WhatsUp(park: jotr, sky: try sky(jotr, "2028-12-30"), isTonight: true)
        #expect(hidden.events.glyph == nil)
        #expect(hidden.eclipse?.detail == "Not visible from this park: the Moon is below the horizon.")
        // The faintest penumbral eclipses are never shown.
        let faint = try #require(SkyEvents.shared.lunarEclipses.first { $0.date == "2027-07-18" })
        #expect(!WhatsUp.Events.worthShowing(faint))
    }
    @Test func showerRemindersOnePerNight() throws {
        let jotr = try park("jotr"), deva = try park("deva")
        let peak = try night(jotr, "2026-12-13"), other = try night(deva, "2026-12-13")
        let scheduler = NotificationScheduler(center: StubNotifications(), ledger: ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)"))
        let morning = try #require(try? Date("2026-12-13T15:00:00Z", strategy: .iso8601))
        let plans = scheduler.plans(nights: [peak, other], now: morning, showers: true)
        let meteors = plans.filter { $0.id.contains("-meteors-") }
        #expect(meteors.count == 1)
        let plan = try #require(meteors.first)
        #expect(plan.title.hasPrefix("Geminids peak tonight at"))
        #expect(plan.body.hasPrefix("About") && plan.body.contains("Moon down"))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = plan.timeZone
        #expect(calendar.component(.hour, from: plan.fireDate) == 16)
        // Off, overcast, or already issued: nothing.
        #expect(scheduler.plans(nights: [peak], now: morning, showers: false).isEmpty)
        #expect(scheduler.plans(nights: [try night(jotr, "2026-12-13", clouds: 90)], now: morning, showers: true).isEmpty)
        #expect(scheduler.plans(nights: [peak], now: morning, delivered: [NotificationScheduler.showerIdentifier(park: jotr, night: peak.id)], showers: true).isEmpty)
    }
    /// A shower reminder keeps its own title, shares the 64 budget and the ledger.
    @Test func showerReminderIsScheduledOnceAndNeverRetitled() async throws {
        let jotr = try park("jotr"), peak = try night(jotr, "2026-12-13")
        let morning = try #require(try? Date("2026-12-13T15:00:00Z", strategy: .iso8601))
        let center = StubNotifications(ids: (0..<64).map { "unrelated-\($0)" })
        let ledger = ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)")
        let full = NotificationScheduler(center: center, ledger: ledger)
        await full.reschedule(nights: [peak], now: morning, showers: true)
        #expect(await center.requests.isEmpty)
        let open = StubNotifications(), scheduler = NotificationScheduler(center: open, ledger: ledger)
        await scheduler.reschedule(nights: [peak], now: morning, showers: true) { _ in "A night to consider" }
        #expect(await open.requests.map(\.title) == ["Geminids peak tonight at Joshua Tree"])
        let id = try #require(await open.requests.first?.id)
        await open.remove([id])
        await scheduler.reschedule(nights: [peak], now: morning.addingTimeInterval(60), showers: true)
        #expect(await open.requests.isEmpty)
    }
}
