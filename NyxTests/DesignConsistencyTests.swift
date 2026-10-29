import Foundation
import Testing
@testable import Nyx

/// Consistency across surfaces: the iPhone's brighter red reaching the wrist, the score's basis on
/// every surface that has no room for a caption, the Moon's symbol from the southern sky, the
/// iPad's readable page widths, and the journal editor that never throws a night away unasked.
struct DesignConsistencyTests {
    @Test func brighterRedTravelsToTheWatchAndOldContextsReadStandard() throws {
        let context = WatchContext.make(savedParkIDs: ["jotr"], homeParkID: "jotr", nightVision: true, brighterRed: true, forecasts: [:])
        let received = try #require(context.data.flatMap(WatchContext.init(data:)))
        #expect(received.brighterRed && received.nightVision)
        // A context from an iPhone before 2.0 (17) carries no choice: the standard red, as before.
        let bytes = try #require(context.data)
        let object = try JSONSerialization.jsonObject(with: bytes)
        var sent = try #require(object as? [String: Any])
        sent["brighterRed"] = nil
        let older = try #require(WatchContext(data: try JSONSerialization.data(withJSONObject: sent)))
        #expect(!older.brighterRed && older.homeParkID == "jotr")
        // The choice is part of what the iPhone compares before sending again.
        #expect(context != context.sentWithout(brighterRed: true))
    }

    @Test func theBandCarriesItsBasisWhereNoCaptionFits() {
        func score(_ basis: CloudBasis) -> DarknessScore {
            DarknessScore(value: 81, moonPoints: 38, cloudPoints: 18, bortlePoints: 15, lengthPoints: 10, basis: basis)
        }
        #expect(score(.forecast).bandWithBasis == ScoreBand.band(81).label)
        #expect(score(.blended(weight: 0.5, leadDays: 6)).bandWithBasis == "\(ScoreBand.band(81).label), early look")
        #expect(score(.usual).bandWithBasis == "\(ScoreBand.band(81).label), usual clouds")
    }

    @Test func theMoonsSymbolTurnsForTheSouthernSky() {
        let cases: [(Double, String, String)] = [
            (0.10, "moonphase.waxing.crescent", "moonphase.waning.crescent"),
            (0.25, "moonphase.first.quarter", "moonphase.last.quarter"),
            (0.40, "moonphase.waxing.gibbous", "moonphase.waning.gibbous"),
            (0.50, "moonphase.full.moon", "moonphase.full.moon"),
            (0.60, "moonphase.waning.gibbous", "moonphase.waxing.gibbous"),
            (0.75, "moonphase.last.quarter", "moonphase.first.quarter"),
            (0.90, "moonphase.waning.crescent", "moonphase.waxing.crescent"),
            (0.00, "moonphase.new.moon", "moonphase.new.moon"),
        ]
        for (fraction, north, south) in cases {
            let phase = MoonPhase(fraction: fraction)
            #expect(phase.symbolName(southern: false) == north)
            #expect(phase.symbolName(southern: true) == south)
        }
    }

    @Test func twoColumnPagesKeepAReadableWidth() {
        #expect(WideLayout.pageWidth(width: 402, largeText: false) == WideLayout.readableWidth)
        #expect(WideLayout.pageWidth(width: 1366, largeText: false) == WideLayout.twoColumnMaximum)
        // At accessibility sizes the split waits, and the page with it.
        #expect(WideLayout.pageWidth(width: 1024, largeText: true) == WideLayout.readableWidth)
        #expect(WideLayout.twoColumnMaximum > WideLayout.twoColumnWidth)
    }

    @MainActor @Test func aPlaceNoLongerSavedIsNamedTheSameOnEveryWidget() {
        #expect(UnsavedPlaceFace.title("Eifel") == "Eifel is no longer saved in Nyx.")
        #expect(UnsavedPlaceFace.title("") == "This place is no longer saved in Nyx.")
    }

    @MainActor @Test func theJournalEditorKnowsWhenThereIsSomethingToLose() {
        let editor = JournalEditorModel()
        #expect(!editor.hasChanges)
        editor.notes = "Zodiacal light before dawn"
        #expect(editor.hasChanges)
        // A prefill, or the date moving to the night just seen, is the starting point.
        editor.markClean()
        #expect(!editor.hasChanges)
        editor.observedBortle += 1
        #expect(editor.hasChanges)
        // Saved, there is nothing to lose.
        editor.saved = true
        #expect(!editor.hasChanges)
    }
}

private extension WatchContext {
    /// The same context with the brighter-red choice flipped off, everything else as sent.
    func sentWithout(brighterRed: Bool) -> WatchContext {
        WatchContext(sent: sent, savedParkIDs: savedParkIDs, homeParkID: homeParkID, nightVision: nightVision, brighterRed: !brighterRed, forecasts: forecasts,
                     details: details, closures: closures, ranges: ranges, places: places, usualClouds: usualClouds)
    }
}
