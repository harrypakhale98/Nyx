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
    init(ids:[String]=[]) { self.ids=ids }
    func authorized() async -> Bool { true }
    func request() async -> Bool { true }
    func pendingIDs() async -> [String] { ids+requests.map(\.id) }
    func remove(_ values:[String]) async { ids.removeAll{values.contains($0)};requests.removeAll{values.contains($0.id)} }
    func add(_ reminder:NightReminder) async throws { requests.append(reminder) }
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
        let scheduler=NotificationScheduler(center:center)
        await scheduler.reschedule(nights:nights+nights,now:now)
        #expect(await center.requests.count==54)
        #expect(Set(await center.requests.map(\.id)).count==54)
        #expect(await center.ids.count==10)
        let noCloud=Night(park:p,sky:nights[0].sky,score:DarknessScore(value:94,moonPoints:53,cloudPoints:nil,bortlePoints:24,lengthPoints:17),cloudCover:nil,forecastUpdated:nil)
        #expect(scheduler.plans(nights:[noCloud],now:now).isEmpty)
    }
}
