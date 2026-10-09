import Foundation
import Synchronization
import Testing
@testable import Nyx

/// Ask Nyx shows its work: citations generated first, partial text only when grounded (a number
/// still arriving held back), lookups listed in the tools' own terms as they happen, and record
/// rows in the app's words while the model's input stays as it was.
@MainActor struct GuideStreamingTests {
    let parks: [Park]
    init() throws { parks=try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    /// 2026-12-01, 21:00 UTC: afternoon in every US park.
    let now=Date(timeIntervalSince1970: 1_796_158_800)

    /// Guided generation fills properties in declaration order: the citations come first.
    @Test func answerDeclaresCitationsBeforeText() {
        let labels=Mirror(reflecting: GuideAnswer(sourceIDs: [1], text: "Arches")).children.compactMap(\.label)
        #expect(labels == ["sourceIDs", "text"])
    }

    /// A trailing run of digits waits for the next character, so "9" on its way to "94" never shows.
    @Test func trailingDigitsAreHeldBack() {
        #expect(OnDeviceGuide.heldBack("Arches scores 9") == "Arches scores ")
        #expect(OnDeviceGuide.heldBack("Arches scores 94.") == "Arches scores 94.")
        #expect(OnDeviceGuide.heldBack("1999") == "")
        let facts=["Arches; Fri, Oct 9 (2026-10-09); score 94/100 Pristine"]
        // "9" alone is no number in the records; held back, the rest may show.
        #expect(OnDeviceGuide.partial("Arches on Oct 9 scores 9", ids: [0], valid: [0], facts: facts) == "Arches on Oct 9 scores ")
        #expect(OnDeviceGuide.partial("Arches on Oct 9 scores 94", ids: [0], valid: [0], facts: facts) == "Arches on Oct 9 scores ")
        #expect(OnDeviceGuide.partial("Arches on Oct 9 scores 94,", ids: [0], valid: [0], facts: facts) == "Arches on Oct 9 scores 94,")
    }

    /// Partial text appears only with every citation real and every number in the records.
    @Test func partialTextOnlyWhenGrounded() {
        let facts=["Arches; Fri, Oct 9 (2026-10-09); score 94/100 Pristine"]
        #expect(OnDeviceGuide.partial("Arches scores 94.", ids: [], valid: [0], facts: facts) == nil)
        #expect(OnDeviceGuide.partial("Arches scores 94.", ids: [0, 7], valid: [0], facts: facts) == nil)
        #expect(OnDeviceGuide.partial("Arches scores 97.", ids: [0], valid: [0], facts: facts) == nil)
        #expect(OnDeviceGuide.partial("Arches is Pristine!", ids: [0], valid: [0], facts: facts) == nil)
        #expect(OnDeviceGuide.partial("  ", ids: [0], valid: [0], facts: facts) == nil)
        #expect(OnDeviceGuide.partial("Arches scores 94.", ids: [0], valid: [0], facts: facts) == "Arches scores 94.")
    }

    /// Each lookup is named in the tool's own arguments, resolved to the park the person knows.
    @Test func lookupsReadInPlainWords() throws {
        let lookup=NightLookup(parks: parks, forecasts: [:], now: now)
        #expect(lookup.bestNightsLookup(park: "arches", from: "2026-10-09", nights: 30) == "Best nights · Arches · 30 nights from Oct 9")
        #expect(lookup.bestNightsLookup(park: "Arches", from: "tonight", nights: 99) == "Best nights · Arches · 30 nights from tonight")
        #expect(lookup.whatsUpLookup(park: "Arches", on: "2026-10-09") == "What's up · Arches · Oct 9")
        #expect(lookup.whatsUpLookup(park: "Arches", on: "tonight") == "What's up · Arches · tonight")
        // Distances follow the device's units; the radius is straight-line, as the tool's is.
        let near=lookup.parksNearLookup(park: "Joshua Tree", radiusMiles: 200)
        let radius=Measurement(value: 200, unit: UnitLength.miles).formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
        #expect(near == "Parks near · Joshua Tree · within \(radius)")
        // A name no park matches is shown as the model wrote it.
        #expect(lookup.whatsUpLookup(park: "Atlantis", on: "tonight") == "What's up · Atlantis · tonight")
    }

    /// The ledger tells the screen of each lookup as it happens, with the whole list so far.
    @Test func ledgerReportsLookupsAsTheyHappen() {
        let ledger=GuideLedger(firstID: 0)
        let seen=Seen()
        ledger.reset(firstID: 3, lookup: NightLookup(parks: parks, forecasts: [:], now: now)) { lines in seen.lines.withLock { $0.append(lines) } }
        #expect(ledger.add(["a"], lookup: "Best nights · Arches · 30 nights from Oct 9") == "ID 3: a")
        #expect(ledger.add(["b", "c"], lookup: "What's up · Arches · Oct 9") == "ID 4: b\nID 5: c")
        // Records with no lookup (none today) are numbered but not listed.
        _=ledger.add(["d"])
        #expect(seen.lines.withLock { $0 } == [["Best nights · Arches · 30 nights from Oct 9"], ["Best nights · Arches · 30 nights from Oct 9", "What's up · Arches · Oct 9"]])
        #expect(ledger.ids == [3, 4, 5, 6] && ledger.lookups.count == 2 && ledger.lookup != nil)
        // A new question starts empty.
        ledger.reset(firstID: 1, lookup: nil)
        #expect(ledger.all.isEmpty && ledger.lookups.isEmpty && ledger.lookup == nil && ledger.firstID == 1)
    }

    /// Rows speak Nyx; the model's input is untouched (its wording and its parsing back).
    @Test func recordRowsUseTheAppsWordsAndLeaveTheModelInputAlone() throws {
        let arch=try park("arch")
        let lookup=NightLookup(parks: parks, forecasts: [:], now: now)
        let night=NightPlanner(forecasts: [:]).night(arch, on: arch.currentNight(at: now), now: now)
        let line=lookup.describe(night)
        // The model still reads its own record, lower case and all.
        #expect(line.hasPrefix("Arches; ") && line.contains("score \(night.score.value)/100") && line.contains("no cloud forecast yet; scored with the park's usual clouds for the month"))
        let record=GuideRecord(line, parks: parks) { $0.currentNight(at: self.now) }
        #expect(record.park?.id == "arch" && record.score == night.score.value && record.detail == nil)
        // The row says it the app's way.
        #expect(GuideRecordRow.basis(night) == "No cloud forecast yet")
        #expect(GuideRecordRow.sharedCaption("No cloud forecast yet") == "No cloud forecast yet · usual clouds for the month")
        // A "parks near" record keeps its distance, the one thing the row cannot work out.
        let near=GuideRecord("Arches, UT; 220 miles straight-line from Denver, CO; tonight 88/100 Excellent", parks: parks) { $0.currentNight(at: self.now) }
        #expect(near.detail == "220 miles straight-line from Denver, CO")
    }
}

/// What the ledger reported, collected from its callback.
private final class Seen: Sendable { let lines=Mutex<[[String]]>([]) }
