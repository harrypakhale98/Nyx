import Foundation
import Testing
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
        #expect(clock.now-start < .seconds(5))
        #expect(await SavedSkySync.run(within: .seconds(5)) {})
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
        let area=CachePreload.homeArea(fresh.parks, defaults: defaults).map(\.id)
        #expect(area.contains("jotr") && !area.contains("acad"))
    }
}
