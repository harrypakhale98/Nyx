import Foundation
import Testing
import UniformTypeIdentifiers
import WidgetKit
@testable import Nyx

/// The Tonight widget's previous and next night buttons (each widget keeps its own night, within
/// the week, until sunrise turns the night over) and a night dragged from Plan's month onto the
/// Journal (its id and Gregorian day in the park's zone, read back as the same night).
@MainActor @Suite struct NightStepAndDragTests {
    private let now = Date(timeIntervalSince1970: 1_791_158_400) // 2026-10-05 00:00 UTC
    private func park(_ id: String) throws -> Park { try #require(try ParkData.load().first { $0.id == id }) }
    private func suite() throws -> (UserDefaults, String) {
        let name = "nyx-tests-night-step-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    // MARK: Night buttons

    @Test func aWidgetKeepsItsOwnNightWithinTheWeek() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let jotr = try park("jotr")
        let tonight = jotr.currentNight(at: now)
        let medium = WidgetNightStep.scope(place: nil, family: "medium"), large = WidgetNightStep.scope(place: nil, family: "large")
        let pinned = WidgetNightStep.scope(place: "jotr", family: "medium")
        #expect(medium != large && medium != pinned)
        // Nothing kept: tonight.
        #expect(WidgetNightStep.offset(scope: medium, park: "jotr", tonight: tonight, defaults: defaults) == 0)
        WidgetNightStep.set(3, scope: medium, park: "jotr", tonight: tonight, now: now, defaults: defaults)
        #expect(WidgetNightStep.offset(scope: medium, park: "jotr", tonight: tonight, defaults: defaults) == 3)
        // Two widgets never move each other: another size, or the same size set to one park.
        #expect(WidgetNightStep.offset(scope: large, park: "jotr", tonight: tonight, defaults: defaults) == 0)
        #expect(WidgetNightStep.offset(scope: pinned, park: "jotr", tonight: tonight, defaults: defaults) == 0)
        WidgetNightStep.set(5, scope: large, park: "jotr", tonight: tonight, now: now, defaults: defaults)
        #expect(WidgetNightStep.offset(scope: medium, park: "jotr", tonight: tonight, defaults: defaults) == 3)
        // Another place (the "2 of 3" button moved on) or another tonight (sunrise): tonight again.
        #expect(WidgetNightStep.offset(scope: medium, park: "grba", tonight: tonight, defaults: defaults) == 0)
        #expect(WidgetNightStep.offset(scope: medium, park: "jotr", tonight: jotr.date(tonight, addingDays: 1), defaults: defaults) == 0)
        // Held to the week: tonight and the six nights after it.
        WidgetNightStep.set(12, scope: medium, park: "jotr", tonight: tonight, now: now, defaults: defaults)
        #expect(WidgetNightStep.offset(scope: medium, park: "jotr", tonight: tonight, defaults: defaults) == WidgetNightStep.nights-1)
        WidgetNightStep.set(-2, scope: large, park: "jotr", tonight: tonight, now: now, defaults: defaults)
        #expect(WidgetNightStep.offset(scope: large, park: "jotr", tonight: tonight, defaults: defaults) == 0)
        // Back on tonight keeps nothing for that widget.
        #expect(defaults.dictionary(forKey: WidgetNightStep.key)?[large] == nil)
        WidgetNightStep.set(0, scope: medium, park: "jotr", tonight: tonight, now: now, defaults: defaults)
        #expect(defaults.dictionary(forKey: WidgetNightStep.key) == nil)
    }

    @Test func oldNightsAreForgottenAndANewSavedPlaceStartsOnTonight() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let jotr = try park("jotr")
        let tonight = jotr.currentNight(at: now)
        let saved = WidgetNightStep.scope(place: nil, family: "medium"), pinned = WidgetNightStep.scope(place: "jotr", family: "large")
        WidgetNightStep.set(2, scope: saved, park: "jotr", tonight: tonight, now: now, defaults: defaults)
        WidgetNightStep.set(4, scope: pinned, park: "jotr", tonight: tonight, now: now, defaults: defaults)
        // "Next saved place" resets the widgets that follow the saved places, not one set to a park.
        WidgetNightStep.clearSaved(defaults: defaults)
        #expect(WidgetNightStep.offset(scope: saved, park: "jotr", tonight: tonight, defaults: defaults) == 0)
        #expect(WidgetNightStep.offset(scope: pinned, park: "jotr", tonight: tonight, defaults: defaults) == 4)
        // A widget removed long ago leaves nothing behind once another widget moves, three days on.
        let later = now.addingTimeInterval(3*86400)
        WidgetNightStep.set(1, scope: saved, park: "jotr", tonight: jotr.currentNight(at: later), now: later, defaults: defaults)
        #expect(defaults.dictionary(forKey: WidgetNightStep.key)?.keys.sorted() == [saved])
    }

    @Test func theTimelineShowsTheChosenNightUntilSunrise() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let jotr = try park("jotr")
        let scope = WidgetNightStep.scope(place: "jotr", family: "large")
        var builder = TonightTimeline(snapshot: SavedSkySnapshot(parks: [jotr], forecasts: [:]), large: true, pinned: jotr)
        builder.stepScope = scope
        builder.stepDefaults = defaults
        // Never tapped: tonight, exactly as before.
        let first = builder.entry(at: now)
        let night = try #require(first.night)
        #expect(first.offset == 0 && first.shown?.id == night.id && first.stepScope == scope)
        WidgetNightStep.set(3, scope: scope, park: "jotr", tonight: night.id, now: now, defaults: defaults)
        let moved = builder.entry(at: now.addingTimeInterval(3600))
        #expect(moved.offset == 3)
        #expect(moved.night?.id == night.id)
        #expect(moved.shown?.id == jotr.date(night.id, addingDays: 3))
        // The month stays tonight's, and the closure and relevance are tonight's.
        #expect(moved.month?.tonight?.id == night.id)
        // A second past sunrise the night turns over, and the widget is back on (the new) tonight.
        let turnover = try #require(jotr.nightTurnovers(from: now, to: now.addingTimeInterval(36*3600)).first)
        let next = builder.entry(at: turnover)
        #expect(next.night?.id == jotr.date(night.id, addingDays: 1))
        #expect(next.offset == 0 && next.shown?.id == next.night?.id)
        // Families without the buttons keep tonight, whatever is kept.
        var small = TonightTimeline(snapshot: SavedSkySnapshot(parks: [jotr], forecasts: [:]), large: false, pinned: jotr)
        small.stepDefaults = defaults
        let plain = small.entry(at: now)
        #expect(plain.offset == 0 && plain.stepScope == nil && plain.shown?.id == night.id)
    }

    @Test func theShownNightIsMarkedTonightIncluded() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let jotr = try park("jotr")
        let scope = WidgetNightStep.scope(place: "jotr", family: "medium")
        var builder = TonightTimeline(snapshot: SavedSkySnapshot(parks: [jotr], forecasts: [:]), large: false, pinned: jotr)
        builder.stepScope = scope
        builder.stepDefaults = defaults
        // Tonight: the week's first column carries the plate, as the large widget's month marks tonight.
        let tonight = builder.entry(at: now)
        #expect(tonight.week.count == WidgetNightStep.nights)
        #expect(tonight.week.map { tonight.marks($0) } == [true] + Array(repeating: false, count: WidgetNightStep.nights-1))
        let night = try #require(tonight.night)
        WidgetNightStep.set(3, scope: scope, park: "jotr", tonight: night.id, now: now, defaults: defaults)
        let moved = builder.entry(at: now)
        #expect(moved.week.indices.filter { moved.marks(moved.week[$0]) } == [3])
        // The gallery and the families without buttons mark nothing.
        var plain = TonightTimeline(snapshot: SavedSkySnapshot(parks: [jotr], forecasts: [:]), large: false, pinned: jotr)
        plain.stepDefaults = defaults
        let gallery = plain.entry(at: now)
        #expect(!gallery.week.contains { gallery.marks($0) })
    }

    @Test func aTapOnANightAheadOpensThatNight() throws {
        let jotr = try park("jotr")
        let planner = NightPlanner(forecasts: [:])
        let tonight = planner.night(jotr, on: jotr.currentNight(at: now), now: now)
        let ahead = planner.night(jotr, on: jotr.date(tonight.id, addingDays: 3), now: now)
        // Tonight opens the park, as before; nothing saved opens Tonight.
        #expect(TonightEntry.link(face: tonight, tonight: tonight)?.absoluteString == "nyx://park/jotr")
        #expect(TonightEntry.link(face: nil, tonight: nil)?.absoluteString == "nyx://tonight")
        // A night ahead opens the park on that night, the score the face showed.
        let link = try #require(TonightEntry.link(face: ahead, tonight: tonight))
        let day = try #require(TripDay(iso: jotr.isoDay(ahead.id)))
        #expect(DeepLink(link) == .parkNight(park: "jotr", day: day))
        #expect(day.evening(in: jotr) == ahead.id)
        #expect(DeepLink.parkNight(park: "jotr", day: day).url == link)
        // A link whose night is not a real day, or out of range, still opens the park.
        for bad in ["2026-02-30", "tomorrow", "0001-01-01", "9999-12-31", ""] {
            #expect(DeepLink(try #require(URL(string: "nyx://park/jotr?night=\(bad)"))) == .park("jotr"), "\(bad)")
        }
        // A park link carrying a night still drags in as the park.
        #expect(try Park.transferred(url: link).id == "jotr")
    }

    @Test func aNightAheadIsSpokenWithItsDateBasisAndMoon() throws {
        let jotr = try park("jotr")
        var builder = TonightTimeline(snapshot: SavedSkySnapshot(parks: [jotr], forecasts: [:]), large: false, pinned: jotr)
        var entry = builder.entry(at: now)
        entry.stepScope = WidgetNightStep.scope(place: "jotr", family: "medium")
        entry.offset = 4
        let shown = try #require(entry.shown)
        let spoken = TonightWidgetView.summary(shown, entry: entry, family: .systemMedium)
        // The night's own date and score, its band with the usual-clouds caption as the app words it, and its Moon.
        #expect(spoken.hasPrefix("Joshua Tree, \(jotr.dayLabel(shown.id)): \(shown.score.value) out of 100, \(shown.score.band.label)."))
        #expect(shown.basis == .usual)
        #expect(spoken.contains(try #require(shown.basisCaption())))
        #expect(spoken.contains("\(shown.sky.moon.name), \(Int((shown.sky.moon.illumination*100).rounded())) percent lit."))
        // Tonight's summary is unchanged by the buttons.
        entry.offset = 0
        let tonight = try #require(entry.night)
        #expect(TonightWidgetView.summary(tonight, entry: entry, family: .systemMedium).hasPrefix(tonight.spokenSummary(.widget)))
        // A closure is still said whole, after the score.
        entry.offset = 4
        entry.closure = "Keys View Road closed at night"
        let closed = TonightWidgetView.summary(shown, entry: entry, family: .systemLarge)
        let score = try #require(closed.range(of: "out of 100")), alert = try #require(closed.range(of: "Closure alert: Keys View Road closed at night"))
        #expect(score.upperBound <= alert.lowerBound)
    }

    // MARK: Dragging a night onto the Journal

    @Test func aDraggedNightNamesTheSameNightInThePlacesOwnZone() throws {
        let planner = NightPlanner(forecasts: [:])
        // Joshua Tree (Pacific), American Samoa (UTC-11), Virgin Islands (Atlantic), Gates of the Arctic.
        for id in ["jotr", "npsa", "viis", "gaar"] {
            let place = try park(id)
            for night in planner.nights(place, from: now, count: 9, now: now) {
                let transfer = NightTransfer(night)
                #expect(transfer.place == id)
                // A Gregorian day in the place's zone, whatever the device's calendar or zone.
                #expect(transfer.night == place.isoDay(night.id))
                #expect(transfer.night.count == 10)
                let decoded = try JSONDecoder().decode(NightTransfer.self, from: JSONEncoder().encode(transfer))
                #expect(decoded == transfer)
                #expect(decoded.date(at: place) == night.id, "\(id) \(transfer.night)")
            }
        }
        let jotr = try park("jotr")
        // Not a real day, or another place: no night.
        #expect(NightTransfer(place: "jotr", night: "2026-02-30").date(at: jotr) == nil)
        #expect(NightTransfer(place: "jotr", night: "tonight").date(at: jotr) == nil)
        #expect(NightTransfer(place: "grba", night: "2026-10-05").date(at: jotr) == nil)
    }

    @Test func theJournalTakesANightOrAPark() async throws {
        let jotr = try park("jotr")
        let night = NightPlanner(forecasts: [:]).night(jotr, on: jotr.currentNight(at: now), now: now)
        let transfer = NightTransfer(night)
        // Nyx's own night only: Plan, which takes a park, never offers itself under a lifted night.
        #expect(transfer.exportedContentTypes() == [.nyxNight])
        let data = try await transfer.exported(as: .nyxNight)
        #expect(try await JournalDrop(importing: data, contentType: .nyxNight) == .night(transfer))
        // The Journal still takes a park dragged from any list, as tonight at that park.
        let place = try await jotr.exported(as: .nyxPark)
        #expect(try await JournalDrop(importing: place, contentType: .nyxPark) == .park("jotr"))
        #expect(JournalDrop.importedContentTypes().first == .nyxNight)
    }

    @Test func aMalformedOrHostileNightIsRefused() async throws {
        func data(_ json: String) -> Data { Data(json.utf8) }
        let refused: [Data] = [
            data("{}"), data("not json"), data(#"{"place":"jotr"}"#),
            // Not a stored place id: a path, upper case, a near-miss namespace.
            data(#"{"place":"../../jotr","night":"2026-10-05"}"#), data(#"{"place":"JOTR","night":"2026-10-05"}"#),
            data(#"{"place":"pin:not-a-uuid","night":"2026-10-05"}"#),
            // Not a real day in the years Nyx accepts.
            data(#"{"place":"jotr","night":"0001-01-01"}"#), data(#"{"place":"jotr","night":"2026-1-5"}"#),
            data(#"{"place":"jotr","night":"99999-01-01"}"#), data(#"{"place":"jotr","night":"2026-02-30"}"#),
            // Far larger than a night ever is.
            data(#"{"place":"jotr","night":"2026-10-05","pad":""# + String(repeating: "x", count: 4096) + #""}"#)
        ]
        for payload in refused {
            await #expect(throws: (any Error).self) { try await JournalDrop(importing: payload, contentType: .nyxNight) }
        }
        let good = try await JournalDrop(importing: data(#"{"place":"jotr","night":"2026-10-05"}"#), contentType: .nyxNight)
        #expect(good == .night(NightTransfer(place: "jotr", night: "2026-10-05")))
        // Built in code rather than received, a day outside those years still names no night.
        let jotr = try park("jotr")
        #expect(NightTransfer(place: "jotr", night: "1850-06-01").date(at: jotr) == nil)
    }

    @Test func recordingANightFillsItAsKeepThisNightAndNeverAheadOfNow() throws {
        let jotr = try park("jotr")
        let planner = NightPlanner(forecasts: [:])
        let tonight = jotr.currentNight(at: now)
        let past = planner.night(jotr, on: jotr.date(tonight, addingDays: -4), now: now)
        let recorded = try #require(JournalPrefill.recording(past, tonight: tonight, now: now))
        #expect(recorded == JournalPrefill(night: past))
        #expect(recorded.date == jotr.evening(past.id) && recorded.parkID == "jotr" && recorded.observedBortle == jotr.bortleEstimate)
        // Tonight before its evening: dated now, the same day, since the editor takes no date still ahead.
        let tonightNight = planner.night(jotr, on: tonight, now: now)
        let morning = jotr.evening(tonight).addingTimeInterval(-3*3600)
        let early = try #require(JournalPrefill.recording(tonightNight, tonight: tonight, now: morning))
        #expect(early.date == morning && jotr.isoDay(early.date) == jotr.isoDay(tonight))
        // A night still ahead has not happened: nothing to record.
        let ahead = planner.night(jotr, on: jotr.date(tonight, addingDays: 2), now: now)
        #expect(JournalPrefill.recording(ahead, tonight: tonight, now: now) == nil)
    }
}
