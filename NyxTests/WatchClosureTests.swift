import Foundation
import Testing
@testable import Nyx

/// A park's closure on its way to the wrist, where it stands beside the score on the watch's
/// Tonight and on every complication: the iPhone's context carries it, the followed parks' first
/// when room runs short, and a context from before closures still decodes. The complication views
/// themselves (`WristClosure`, `WatchComplicationView`) build only in the watch targets.
struct WatchClosureTests {
    private let now = Date(timeIntervalSince1970: 1_791_158_400) // 2026-10-05 00:00 UTC

    @Test func closuresTravelWithTheContext() throws {
        let closures = ["deva": "Badwater Road closed", "yell": "Beartooth Highway closed for the season"]
        let context = WatchContext.make(savedParkIDs: ["jotr", "deva"], homeParkID: "grba", nightVision: false, forecasts: [:], closures: closures, now: now)
        let decoded = try #require(WatchContext(dictionary: context.dictionary))
        // While there is room every closure travels, followed or not: a complication can be set to any park.
        #expect(decoded.closures == closures)
        #expect(decoded.closures["jotr"] == nil)
        #expect(decoded == context)
    }

    @Test func followedParksKeepTheirClosuresWhenRoomRunsShort() throws {
        let ids = try ParkData.load().map(\.id)
        // About 1 KB each: all 63 would overflow the context's budget.
        let long = String(repeating: "Road closed. ", count: 80)
        let context = WatchContext.make(savedParkIDs: ["zion", "jotr"], homeParkID: "deva", nightVision: false, forecasts: [:],
                                        closures: Dictionary(uniqueKeysWithValues: ids.map { ($0, long) }), now: now)
        #expect(context.closures.count < ids.count)
        for id in ["zion", "jotr", "deva"] { #expect(context.closures[id] == long) }
        let data = try #require(context.data)
        #expect(data.count <= WatchContext.byteBudget)
    }

    @Test func aContextFromBeforeClosuresStillDecodes() throws {
        let context = WatchContext.make(savedParkIDs: ["jotr"], homeParkID: "jotr", nightVision: true, forecasts: [:],
                                        closures: ["jotr": "Keys View Road closed"], now: now)
        let data = try #require(context.data)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.contains("closures"))
        object["closures"] = nil
        let old = try #require(WatchContext(data: try JSONSerialization.data(withJSONObject: object)))
        #expect(old.closures.isEmpty && old.homeParkID == "jotr" && old.savedParkIDs == ["jotr"] && old.nightVision)
    }
}
