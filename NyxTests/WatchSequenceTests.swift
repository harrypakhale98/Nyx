import Foundation
import Testing
@testable import Nyx

/// Which of two contexts from the iPhone is the newer one: told by the iPhone's hand-over number
/// when both carry one, so an iPhone clock set back never keeps a new context off the wrist, and by
/// when it was sent for a context from an iPhone that numbers none.
struct WatchSequenceTests {
    private let now = Date(timeIntervalSince1970: 1_791_158_400) // 2026-10-05 00:00 UTC

    private func context(sent: Date, sequence: Int64?) -> WatchContext {
        let made = WatchContext.make(savedParkIDs: ["jotr"], homeParkID: "deva", nightVision: false, forecasts: [:], now: sent)
        return sequence.map { made.numbered($0) } ?? made
    }

    @Test func theNextNumberNeverGoesBack() {
        let clock = Int64(now.timeIntervalSince1970*1000)
        #expect(WatchContext.nextSequence(after: nil, now: now) == clock)
        // A clock set back an hour: still one past the last.
        #expect(WatchContext.nextSequence(after: clock, now: now.addingTimeInterval(-3600)) == clock+1)
        // Sent within the same millisecond: still higher.
        #expect(WatchContext.nextSequence(after: clock, now: now) == clock+1)
        // Time moved on: the clock, which is higher.
        #expect(WatchContext.nextSequence(after: clock, now: now.addingTimeInterval(60)) == clock+60_000)
    }

    @Test func aNewerNumberWinsWhateverTheClockSaid() {
        let held = context(sent: now, sequence: 10)
        // The iPhone's clock went back an hour, but this is the hand-over after it.
        #expect(WatchContext.isNewer(context(sent: now.addingTimeInterval(-3600), sequence: 11), than: held))
        // The same hand-over again (its complication transfer), or an older one arriving late.
        #expect(!WatchContext.isNewer(context(sent: now, sequence: 10), than: held))
        #expect(!WatchContext.isNewer(context(sent: now.addingTimeInterval(3600), sequence: 9), than: held))
        #expect(WatchContext.isNewer(held, than: nil))
    }

    @Test func withoutNumbersTheTimeSentDecides() {
        let held = context(sent: now, sequence: nil)
        #expect(WatchContext.isNewer(context(sent: now.addingTimeInterval(1), sequence: nil), than: held))
        #expect(!WatchContext.isNewer(context(sent: now, sequence: nil), than: held))
        // The first numbered context after an iPhone that numbered none: by time, as before.
        #expect(WatchContext.isNewer(context(sent: now.addingTimeInterval(1), sequence: 5), than: held))
    }

    @Test func theNumberTravelsAndOldContextsStillDecode() throws {
        let numbered = context(sent: now, sequence: 42)
        let decoded = try #require(WatchContext(dictionary: numbered.dictionary))
        #expect(decoded.sequence == 42)
        #expect(decoded == numbered)
        // What it says is compared without its number, so an unchanged context is not sent again.
        #expect(numbered.sent(at: .distantPast) == context(sent: now, sequence: 7).sent(at: .distantPast))
        let data = try #require(numbered.data)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["sequence"] = nil
        let old = try #require(WatchContext(data: try JSONSerialization.data(withJSONObject: object)))
        #expect(old.sequence == nil && old.sent == numbered.sent)
    }
}
