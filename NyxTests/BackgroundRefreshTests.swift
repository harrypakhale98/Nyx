import Foundation
import Testing
import UIKit
@testable import Nyx

/// A background refresh has about 30 seconds: a cancelled caller stops waiting at once, the
/// request goes on for anyone else, and the run itself stops at its deadline.
struct BackgroundRefreshTests {
    func park() throws -> Park { try #require(try ParkData.load().first { $0.id=="jotr" }) }
    private func waitUntilHeld(_ http: GatedHTTP) async throws {
        var tries=0
        while !(await http.waiting), tries<500 { tries+=1; try await Task.sleep(for: .milliseconds(5)) }
        #expect(await http.waiting)
    }
    @Test func cancelledForecastCallerStopsWaiting() async throws {
        let p=try park()
        let http=GatedHTTP(body: "{\"hourly\":{\"time\":[1700000000,1700003600],\"cloud_cover\":[20,60]}}")
        let service=WeatherService(transport: http, persist: false)
        let first=Task { await service.forecasts(for: [p], network: true, force: true) }
        try await waitUntilHeld(http)
        let second=Task { await service.forecasts(for: [p], network: true, force: true) }
        first.cancel()
        // Returned while the request is still held: nothing cached yet, so nothing.
        #expect(await first.value.isEmpty)
        await http.release()
        // The other caller still gets the forecast.
        #expect(await second.value[p.id]?.clouds == [20, 60])
        #expect(await service.forecast(for: p, network: false)?.clouds == [20, 60])
    }
    @Test func cancelledAlertsCallerStopsWaiting() async throws {
        let p=try park()
        let http=GatedHTTP(body: "{\"total\":\"1\",\"data\":[{\"id\":\"closed\",\"title\":\"Road closed\",\"description\":\"Storm\",\"category\":\"Park Closure\",\"parkCode\":\"jotr\"}]}")
        let store=ParkStore(transport: http, persist: false)
        let waiting=Task { await store.alerts(for: [p], key: "test", network: true, force: true) }
        try await waitUntilHeld(http)
        waiting.cancel()
        #expect(await waiting.value.cache == nil)
        await http.release()
    }
    /// Programs and campgrounds wait as alerts do: a cancelled caller returns the cache at once,
    /// even while another caller's request is still held.
    @Test func cancelledProgramsAndCampgroundsCallersStopWaiting() async throws {
        let p=try park()
        let http=GatedHTTP(body: "{\"total\":\"0\",\"data\":[]}")
        let store=ParkStore(transport: http, persist: false)
        let first=Task { await store.programs(for: p, key: "test", network: true, force: true) }
        try await waitUntilHeld(http)
        let second=Task { await store.programs(for: p, key: "test", network: true, force: true) }
        try await Task.sleep(for: .milliseconds(50))
        second.cancel(); first.cancel()
        #expect(await second.value == nil)
        #expect(await first.value == nil)
        await http.release()
        let campsHTTP=GatedHTTP(body: "{\"total\":\"0\",\"data\":[]}")
        let camps=ParkStore(transport: campsHTTP, persist: false)
        let waiting=Task { await camps.campgrounds(for: [p], key: "test", network: true, force: true) }
        try await waitUntilHeld(campsHTTP)
        waiting.cancel()
        #expect(await waiting.value == nil)
        await campsHTTP.release()
    }
    /// One page in the background: a set that needs more is not kept, the last complete one stays.
    @Test func backgroundAlertsAskForOnePage() async throws {
        let p=try park()
        let body="{\"total\":\"900\",\"data\":[{\"id\":\"closed\",\"title\":\"Road closed\",\"description\":\"Storm\",\"category\":\"Park Closure\",\"parkCode\":\"jotr\"}]}"
        let http=StubHTTP(["/api/v1/alerts": body])
        let store=ParkStore(transport: http, persist: false)
        #expect(await store.alerts(for: [p], key: "test", network: true, force: true, pages: 1).cache == nil)
        #expect(await http.urls.count == 1)
        let all=ParkStore(transport: StubHTTP(["/api/v1/alerts": body]), persist: false)
        #expect(await all.alerts(for: [p], key: "test", network: true, force: true).cache?.alerts["jotr"]?.count == 4)
    }
    @MainActor @Test func backgroundRunStopsAtItsDeadline() async {
        let clock=ContinuousClock(), start=clock.now
        let finished=await SavedSkySync.run(within: .milliseconds(100)) { try? await Task.sleep(for: .seconds(30)) }
        #expect(!finished)
        if Bench.enabled { #expect(clock.now-start < .seconds(5)) }
        #expect(await SavedSkySync.run(within: .seconds(5)) {})
    }
    /// The background time given for the watch's answer is handed back once: when the run ends, or
    /// when iOS says time is up (which also cancels the run), whichever comes first, even before
    /// iOS's identifier arrived. The run keeps three seconds short of what iOS gives, at most 20 s.
    @MainActor @Test func backgroundTimeEndsOnce() async {
        var ended:[UIBackgroundTaskIdentifier]=[]
        let id=UIBackgroundTaskIdentifier(rawValue: 7)
        let time=BackgroundTime { ended.append($0) }
        time.began(id)
        let run=Task { _=try? await Task.sleep(for: .seconds(30)) }
        time.run=run
        time.expire(); time.end(); time.expire()
        #expect(ended == [id] && run.isCancelled)
        ended=[]
        let early=BackgroundTime { ended.append($0) }
        early.end(); early.began(id); early.end()
        #expect(ended == [id])
        ended=[]
        let none=BackgroundTime { ended.append($0) }
        none.began(.invalid); none.end()
        #expect(ended.isEmpty)
        #expect(SavedSkySync.budget(remaining: 30) == .seconds(20))
        #expect(SavedSkySync.budget(remaining: 10) == .seconds(7))
        #expect(SavedSkySync.budget(remaining: .greatestFiniteMagnitude) == .seconds(20))
        #expect(SavedSkySync.budget(remaining: 0) == .seconds(1))
    }
    /// The Tonight control alone is someone to serve: a background refresh runs, and ends by
    /// reloading it. Night vision and field mode show no forecast; a list that cannot be read counts.
    @Test func tonightControlCountsOutsideTheApp() {
        #expect(!SavedSkySync.showsTonight(widgets: 0, controls: []))
        #expect(!SavedSkySync.showsTonight(widgets: 0, controls: ["NightVisionControl", "FieldModeControl"]))
        #expect(SavedSkySync.showsTonight(widgets: 0, controls: ["FieldModeControl", WidgetSelection.controlKind]))
        #expect(SavedSkySync.showsTonight(widgets: 2, controls: []))
        #expect(SavedSkySync.showsTonight(widgets: nil, controls: []))
        #expect(SavedSkySync.showsTonight(widgets: 0, controls: nil))
    }
    /// With a Tonight control, the next background refresh is asked for a little after its park's
    /// sunrise, when "tonight" there becomes the coming night; otherwise about six hours on.
    @Test func nextRefreshFollowsTheControlsSunrise() throws {
        let jotr=try park()
        let now=try #require(jotr.calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 2)))
        let turnovers=jotr.nightTurnovers(from: now, to: now.addingTimeInterval(2*86400))
        let delay=SavedSkySync.refreshDelay(now: now, turnovers: turnovers)
        #expect(delay < SavedSkySync.refreshInterval)
        #expect(jotr.currentNight(at: now.addingTimeInterval(delay)) == jotr.date(jotr.currentNight(at: now), addingDays: 1))
        let sunrise=try #require(turnovers.first)
        #expect(delay == sunrise.timeIntervalSince(now) + 600)
        #expect(SavedSkySync.refreshDelay(now: now, turnovers: []) == 6*3600)
        #expect(SavedSkySync.refreshDelay(now: now, turnovers: [now.addingTimeInterval(-60)]) == 6*3600)
        #expect(SavedSkySync.refreshDelay(now: now, turnovers: [now.addingTimeInterval(9*3600)]) == 6*3600)
        // The earliest still ahead, never under a quarter of an hour.
        #expect(SavedSkySync.refreshDelay(now: now, turnovers: [now.addingTimeInterval(3*3600), now.addingTimeInterval(3600)]) == 3600+600)
        #expect(SavedSkySync.refreshDelay(now: now, turnovers: [now.addingTimeInterval(120)]) == 15*60)
        // A control set to a place follows it; one on the darkest saved place follows them all.
        #expect(SavedSkySync.controlPlaces([nil, "deva", "jotr"], saved: ["jotr", "arch"]) == ["jotr", "arch", "deva"])
        #expect(SavedSkySync.controlPlaces(["deva"], saved: ["jotr"]) == ["deva"])
        #expect(SavedSkySync.controlPlaces([], saved: ["jotr"]).isEmpty)
    }
    /// Nights worked out off the main thread (launch, Parks, the calendar's next months) score
    /// exactly as nights worked out on demand.
    @MainActor @Test func preparedNightsScoreTheSame() async throws {
        func model() -> PlanModel {
            PlanModel(weather: WeatherService(transport: StubHTTP([:]), persist: false), parkStore: ParkStore(transport: StubHTTP([:]), persist: false), detail: ForecastDetailService(transport: StubHTTP([:]), persist: false))
        }
        let fresh=model(), prepared=model()
        let parks=fresh.parks.filter { ["jotr", "dena", "npsa", "gaar"].contains($0.id) }
        await prepared.prepareNights(parks, count: 7)
        for park in parks {
            let a=fresh.nights(park, from: fresh.tonight(park), count: 7), b=prepared.nights(park, from: prepared.tonight(park), count: 7)
            #expect(a.map(\.score.value) == b.map(\.score.value))
            #expect(a.map(\.sky.darkHours) == b.map(\.sky.darkHours))
        }
        // Launch reads the starting point as the model does: Joshua Tree and the parks within 200 miles.
        let defaults=try #require(UserDefaults(suiteName: "nyx-home-area"))
        defaults.removePersistentDomain(forName: "nyx-home-area")
        let area=CachePreload.homeArea(fresh.parks, defaults: defaults, locale: Locale(identifier: "en_US")).map(\.id)
        #expect(area.contains("jotr") && !area.contains("acad"))
    }
}
