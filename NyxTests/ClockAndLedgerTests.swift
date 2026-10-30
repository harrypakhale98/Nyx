import Foundation
import Testing
@testable import Nyx

/// A clock that ran ahead and then came back, and the reminder ledger's memory of announced nights.
struct ClockAndLedgerTests {
    let now = Date(timeIntervalSince1970: 1_790_899_200)

    @Test func aForecastStampedInTheFutureGivesWayToAFreshOne() {
        let ahead = Forecast(updated: now.addingTimeInterval(86400), times: [], clouds: [])
        let fresh = Forecast(updated: now, times: [], clouds: [])
        #expect(!Forecast.replaces(fresh, ahead))
        #expect(Forecast.replaces(fresh, ahead, now: now))
        // A newer forecast that landed first still is never replaced by an older one.
        let newer = Forecast(updated: now.addingTimeInterval(-60), times: [], clouds: [])
        let older = Forecast(updated: now.addingTimeInterval(-3600), times: [], clouds: [])
        #expect(!Forecast.replaces(older, newer, now: now))
    }

    @Test func cloudsStampedInTheFutureAreDue() {
        #expect(ForecastReuse.cloudsDue(now.addingTimeInterval(86400), now: now, force: false))
        #expect(!ForecastReuse.cloudsDue(now.addingTimeInterval(-60), now: now, force: false))
        #expect(!ForecastReuse.cloudsDue(now.addingTimeInterval(600), now: now, force: false))
        #expect(ForecastReuse.cloudsDue(nil, now: now, force: false))
    }

    @Test func theLedgerRemembersANightThroughTheSpacing() {
        let ledger = ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)")
        let fiveDaysAgo = "jotr-\(now.timeIntervalSince1970 - 5*86400)"
        let longAgo = "jotr-\(now.timeIntervalSince1970 - Double(NotificationScheduler.spacing + 2)*86400)"
        ledger.record([fiveDaysAgo, longAgo], now: now)
        #expect(ledger.ids == [fiveDaysAgo])
    }
}
