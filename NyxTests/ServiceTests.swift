import AppIntents
import Foundation
import Testing
@testable import Nyx

actor StubHTTP:HTTPTransport {
    var urls:[URL]=[]
    var fail=false
    let responses:[String:Data]
    init(_ responses:[String:String]) { self.responses=responses.mapValues{Data($0.utf8)} }
    func setFailure() { fail=true }
    func get(_ url:URL) async throws -> Data {
        urls.append(url)
        if fail { throw URLError(.notConnectedToInternet) }
        guard let data=responses[url.path] else { throw URLError(.badServerResponse) };return data
    }
}
actor StubNotifications:LocalNotificationCenter {
    var requests:[NightReminder]=[]
    var ids:[String]
    var delivered:[String]=[]
    init(ids:[String]=[]) { self.ids=ids }
    func deliver(_ id:String) { delivered.append(id) }
    func authorized() async -> Bool { true }
    func request() async -> Bool { true }
    func pendingIDs() async -> [String] { ids+requests.map(\.id) }
    func deliveredIDs() async -> [String] { delivered }
    func remove(_ values:[String]) async { ids.removeAll{values.contains($0)};requests.removeAll{values.contains($0.id)} }
    func add(_ reminder:NightReminder) async throws { requests.removeAll{$0.id==reminder.id};requests.append(reminder) }
}
struct ServiceTests {
    func park() throws -> Park { try #require(try ParkData.load().first{$0.id=="jotr"}) }
    @Test func noNetworkWithoutConsent() async throws {
        let p=try park(),http=StubHTTP([:])
        let weather=WeatherService(transport:http,persist:false),store=ParkStore(transport:http,persist:false)
        #expect(await weather.forecast(for:p,network:false,force:true)==nil)
        #expect(await store.enrichment(for:p,key:"key",network:false,force:true)==nil)
        #expect(await store.enrichment(for:p,key:"",network:true,force:true)==nil)
        #expect(await http.urls.isEmpty)
    }
    @Test func cachedForecastSurvivesFailure() async throws {
        let p=try park(),http=StubHTTP(["/v1/forecast":"{\"hourly\":{\"time\":[1700000000,1700003600],\"cloud_cover\":[20,60]}}"])
        let service=WeatherService(transport:http,persist:false)
        let first=await service.forecast(for:p,network:true,force:true)
        #expect(first?.clouds == [20,60])
        await http.setFailure()
        #expect(await service.forecast(for:p,network:true,force:true)?.clouds == first?.clouds)
        #expect(await service.forecast(for:p,network:false,force:true)?.updated == first?.updated)
        #expect(await http.urls.allSatisfy{$0.host=="api.open-meteo.com"})
    }
    /// All parks share one request; each gets its own hours, in request order.
    @Test func manyParksInOneRequest() async throws {
        let parks=Array(try ParkData.load().prefix(3))
        let body="["+(0..<3).map { "{\"hourly\":{\"time\":[1700000000,1700003600],\"cloud_cover\":[\($0*10),\($0*10+5)]}}" }.joined(separator:",")+"]"
        let http=StubHTTP(["/v1/forecast":body])
        let result=await WeatherService(transport:http,persist:false).forecasts(for:parks,network:true,force:true)
        #expect(await http.urls.count==1)
        #expect(result[parks[2].id]?.clouds == [20,25])
        #expect(result[parks[0].id]?.clouds == [0,5])
        let query=try #require(await http.urls.first?.query)
        #expect(query.contains("past_days=1"))
    }
    @Test func closuresSurviveFailureAndEventsFilter() async throws {
        let p=try park()
        let tomorrow=Date.now.addingTimeInterval(86400).formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let http=StubHTTP([
            "/api/v1/alerts":"{\"data\":[{\"id\":\"closed\",\"title\":\"Road closed\",\"description\":\"Storm damage\",\"category\":\"Park Closure\"}]}",
            "/api/v1/events":"{\"total\":\"2\",\"data\":[{\"id\":\"stars\",\"title\":\"Astronomy evening\",\"datestart\":\"\(tomorrow)\",\"description\":\"<p>Bring a red light</p>\"},{\"id\":\"hike\",\"title\":\"Morning hike\",\"datestart\":\"\(tomorrow)\",\"description\":\"Walk\"}]}",
            "/api/v1/parks":"{\"data\":[{\"description\":\"Desert park\"}]}"
        ])
        let store=ParkStore(transport:http,persist:false)
        let first=await store.enrichment(for:p,key:"test",network:true,force:true)
        #expect(first?.alerts.first?.title == "Road closed")
        #expect(first?.programs.count==1);#expect(first?.programs.first?.description == "Bring a red light")
        await http.setFailure()
        #expect(await store.enrichment(for:p,key:"test",network:true,force:true)?.alerts.count==1)
    }
    /// A slow events endpoint must never hide a new closure.
    @Test func closuresArriveWhenEventsFail() async throws {
        let p=try park()
        let http=StubHTTP(["/api/v1/alerts":"{\"data\":[{\"id\":\"closed\",\"title\":\"Road closed\",\"description\":\"Storm damage\",\"category\":\"Park Closure\"}]}"])
        let result=await ParkStore(transport:http,persist:false).enrichment(for:p,key:"test",network:true,force:true)
        #expect(result?.alerts.first?.title == "Road closed")
        #expect(result?.programs.isEmpty == true)
    }
    @Test func rejectsOtherHosts() async {
        guard let url=URL(string:"https://example.com/forecast") else { Issue.record("Bad fixture URL");return }
        await #expect(throws:URLError.self) { try await SafeHTTP().get(url) }
    }
    @Test func reminderLimitAndForecastRequirement() async throws {
        let p=try park(),now=Date(timeIntervalSince1970:1790899200),engine=AstronomyEngine()
        var nights:[Night]=[]
        for offset in 1...90 {
            let sky=engine.conditions(for:p,on:p.date(now,addingDays:offset))
            let score=DarknessScore(value:94,moonPoints:39,cloudPoints:24,bortlePoints:18,lengthPoints:13)
            nights.append(Night(park:p,sky:sky,score:score,cloudCover:4,forecastUpdated:now))
        }
        let center=StubNotifications(ids:(0..<10).map{"unrelated-\($0)"}+["nyx-night-old"])
        let scheduler=NotificationScheduler(center:center,ledger:ReminderLedger(suite:"nyx-ledger-test-\(UUID().uuidString)"))
        await scheduler.reschedule(nights:nights+nights,now:now)
        #expect(await center.requests.count==54)
        #expect(Set(await center.requests.map(\.id)).count==54)
        #expect(await center.ids.count==10)
        let noCloud=Night(park:p,sky:nights[0].sky,score:DarknessScore(value:94,moonPoints:53,cloudPoints:nil,bortlePoints:24,lengthPoints:17),cloudCover:nil,forecastUpdated:nil)
        #expect(scheduler.plans(nights:[noCloud],now:now).isEmpty)
    }
    @Test func tonightStillGetsAReminderOnce() async throws {
        let p=try park(),engine=AstronomyEngine()
        let evening=p.evening(Date(timeIntervalSince1970:1790899200))
        let sky=engine.conditions(for:p,on:evening)
        let night=Night(park:p,sky:sky,score:DarknessScore(value:94,moonPoints:39,cloudPoints:24,bortlePoints:18,lengthPoints:13),cloudCover:4,forecastUpdated:evening)
        let afternoon=evening.addingTimeInterval(2*3600)
        let center=StubNotifications(),scheduler=NotificationScheduler(center:center,ledger:ReminderLedger(suite:"nyx-ledger-test-\(UUID().uuidString)"))
        let plan=try #require(scheduler.plans(nights:[night],now:afternoon).first)
        #expect(plan.fireDate==afternoon.addingTimeInterval(60))
        let dark=try #require(sky.darkStart)
        #expect(scheduler.plans(nights:[night],now:dark).isEmpty)
        await center.deliver(plan.id)
        await scheduler.reschedule(nights:[night],now:afternoon)
        #expect(await center.requests.isEmpty)
    }
    /// iOS forgets a notification once it is tapped or cleared; the ledger must still remember it.
    @Test func tappedReminderNeverReturns() async throws {
        let p=try park(),engine=AstronomyEngine()
        let evening=p.evening(Date(timeIntervalSince1970:1790899200))
        let sky=engine.conditions(for:p,on:evening)
        let night=Night(park:p,sky:sky,score:DarknessScore(value:94,moonPoints:39,cloudPoints:24,bortlePoints:18,lengthPoints:13),cloudCover:4,forecastUpdated:evening)
        let afternoon=evening.addingTimeInterval(2*3600)
        let center=StubNotifications(),scheduler=NotificationScheduler(center:center,ledger:ReminderLedger(suite:"nyx-ledger-test-\(UUID().uuidString)"))
        await scheduler.reschedule(nights:[night],now:afternoon)
        let first=try #require(await center.requests.first)
        // Opening Nyx again a moment later keeps the same fire time.
        await scheduler.reschedule(nights:[night],now:afternoon.addingTimeInterval(30))
        #expect(await center.requests.map(\.fireDate)==[first.fireDate])
        // Delivered and tapped: no longer pending, no longer delivered. It must not come back.
        await center.remove([first.id])
        await scheduler.reschedule(nights:[night],now:afternoon.addingTimeInterval(120))
        #expect(await center.requests.isEmpty)
    }
}
