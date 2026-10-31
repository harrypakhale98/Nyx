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

    /// Every cache stamped while the clock ran ahead is due again, even within a forced refresh's
    /// wait, and is not described meanwhile: park alerts, programs and campgrounds, forecast detail
    /// and smoke, summit layers.
    @Test func everyCacheStampedInTheFutureIsDue() {
        let ahead=now.addingTimeInterval(2*86400)
        #expect(ParkStore.stale(ahead, maxAge: 6*3600, force: true, now: now))
        #expect(ParkStore.stale(ahead, maxAge: 6*3600, force: false, now: now))
        #expect(ParkStore.retryable(ahead, force: false, now: now))
        #expect(!ParkStore.stale(now.addingTimeInterval(600), maxAge: 6*3600, force: true, now: now))
        #expect(ForecastReuse.due(ahead, now: now, force: true, normal: ForecastReuse.detail, forced: ForecastReuse.airForced))
        #expect(ForecastReuse.retryable(ahead, now: now, force: false))
        #expect(!ForecastReuse.due(now.addingTimeInterval(-60), now: now, force: true, normal: ForecastReuse.detail, forced: ForecastReuse.airForced))
        let future=HourlySeries(updated: ahead, times: [], values: [:]), present=HourlySeries(updated: now, times: [], values: [:])
        #expect(!future.usable(now: now) && present.usable(now: now))
        // Forecast detail: the part made now replaces the one stamped ahead, given the present.
        #expect(ForecastDetail(air: future).newer(ForecastDetail(air: present), now: now).air == present)
        #expect(ForecastDetail(air: future).newer(ForecastDetail(air: present)).air == future)
        #expect(Forecast.newer(now, than: ahead, now: now) && !Forecast.newer(now.addingTimeInterval(-3600), than: now, now: now))
    }
    /// Summit layers kept while the clock ran ahead are asked for again, and the fresh ones are kept.
    @Test func summitLayersStampedInTheFutureAreAskedAgain() async throws {
        let clock=BudgetClock(now.addingTimeInterval(2*86400))
        let http=PathHTTP([:])
        let summit=try #require(TestData.parks.first { $0.aboveInversion == true })
        let service=SummitLayerService(transport: http, persist: false, clock: { clock.now })
        #expect(await service.layers(for: [summit], network: true)[summit.id]?.updated == clock.now)
        clock.advance(-2*86400)
        #expect(await service.layers(for: [summit], network: true)[summit.id]?.updated == now)
        #expect(await http.urls.count == 2)
    }

    @Test func theLedgerRemembersANightThroughTheSpacing() {
        let ledger = ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)")
        let fiveDaysAgo = "jotr-\(now.timeIntervalSince1970 - 5*86400)"
        let longAgo = "jotr-\(now.timeIntervalSince1970 - Double(NotificationScheduler.spacing + 2)*86400)"
        ledger.record([fiveDaysAgo, longAgo], now: now)
        #expect(ledger.ids == [fiveDaysAgo])
    }
}
