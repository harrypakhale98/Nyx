import AppIntents
import Foundation
import Testing
@testable import Nyx

actor StubHTTP:HTTPTransport {
    var urls:[URL]=[]
    var fail=false
    var status:Int?
    var responses:[String:Data]
    init(_ responses:[String:String]) { self.responses=responses.mapValues{Data($0.utf8)} }
    func setFailure() { fail=true }
    /// The server answers with this status (429, 503…) instead of data.
    func setStatus(_ code:Int?) { status=code }
    func setResponse(_ path:String,_ body:String) { responses[path]=Data(body.utf8) }
    func get(_ url:URL) async throws -> Data {
        urls.append(url)
        if fail { throw URLError(.notConnectedToInternet) }
        if let status { throw HTTPStatusError(status:status) }
        guard let data=responses[url.path] else { throw URLError(.badServerResponse) };return data
    }
}
actor StubNotifications:LocalNotificationCenter {
    var requests:[NightReminder]=[]
    var ids:[String]
    var delivered:[String]=[]
    init(ids:[String]=[]) { self.ids=ids }
    func deliver(_ id:String) { delivered.append(id) }
    var allowed=true
    func setAllowed(_ value:Bool) { allowed=value }
    func authorized() async -> Bool { allowed }
    func request() async -> Bool { true }
    func pendingIDs() async -> [String] { ids+requests.map(\.id) }
    func deliveredIDs() async -> [String] { delivered }
    func remove(_ values:[String]) async { ids.removeAll{values.contains($0)};requests.removeAll{values.contains($0.id)} }
    private var added=0
    private var hook:(@Sendable (Int) async -> Void)?
    func onAdd(_ hook:@escaping @Sendable (Int) async -> Void) { self.hook=hook }
    func add(_ reminder:NightReminder) async throws {
        requests.removeAll{$0.id==reminder.id};requests.append(reminder)
        added+=1
        await hook?(added)
    }
}
struct ServiceTests {
    func park() throws -> Park { try #require(try ParkData.load().first{$0.id=="jotr"}) }
    @Test func noNetworkWithoutConsent() async throws {
        let p=try park(),http=StubHTTP([:])
        let weather=WeatherService(transport:http,persist:false),store=ParkStore(transport:http,persist:false)
        #expect(await weather.forecast(for:p,network:false,force:true)==nil)
        #expect(await store.alerts(for:[p],key:"key",network:false,force:true).cache==nil)
        #expect(await store.alerts(for:[p],key:"",network:true,force:true).cache==nil)
        #expect(await store.programs(for:p,key:"key",network:false,force:true)==nil)
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
            "/api/v1/alerts":"{\"total\":\"1\",\"data\":[{\"id\":\"closed\",\"title\":\"Road closed\",\"description\":\"Storm damage\",\"category\":\"Park Closure\",\"parkCode\":\"jotr\"}]}",
            "/api/v1/events":"{\"total\":\"2\",\"data\":[{\"id\":\"stars\",\"title\":\"Astronomy evening\",\"datestart\":\"\(tomorrow)\",\"description\":\"<p>Bring a red light</p>\"},{\"id\":\"hike\",\"title\":\"Morning hike\",\"datestart\":\"\(tomorrow)\",\"description\":\"Walk\"}]}"
        ])
        let store=ParkStore(transport:http,persist:false)
        let first=await store.alerts(for:[p],key:"test",network:true,force:true)
        #expect(first.cache?.alerts["jotr"]?.first?.title == "Road closed")
        let programs=await store.programs(for:p,key:"test",network:true,force:true)
        #expect(programs?.programs.count==1);#expect(programs?.programs.first?.description == "Bring a red light")
        await http.setFailure()
        #expect(await store.alerts(for:[p],key:"test",network:true,force:true).cache?.alerts["jotr"]?.count==1)
    }
    /// A slow events endpoint must never hide a new closure.
    @Test func closuresArriveWhenEventsFail() async throws {
        let p=try park()
        let http=StubHTTP(["/api/v1/alerts":"{\"data\":[{\"id\":\"closed\",\"title\":\"Road closed\",\"description\":\"Storm damage\",\"category\":\"Park Closure\",\"parkCode\":\"jotr\"}]}"])
        let store=ParkStore(transport:http,persist:false)
        let result=await store.alerts(for:[p],key:"test",network:true,force:true)
        #expect(result.cache?.alerts["jotr"]?.first?.title == "Road closed")
        #expect(await store.programs(for:p,key:"test",network:true,force:true) == nil)
    }
    /// The shared NPS key is spent carefully: one alerts request however many screens ask, no
    /// repeat within ten minutes even when forced, and programs only when a park's page asks.
    @Test func parkUpdatesAreThrottledAndShared() async throws {
        let p=try park()
        let http=StubHTTP(["/api/v1/alerts":"{\"data\":[]}","/api/v1/events":"{\"total\":\"0\",\"data\":[]}"])
        let store=ParkStore(transport:http,persist:false)
        async let first=store.alerts(for:[p],key:"test",network:true,force:true)
        async let second=store.alerts(for:[p],key:"test",network:true,force:true)
        _=await (first,second)
        #expect(await http.urls.map(\.path)==["/api/v1/alerts"])
        // Opening the park's page a moment later asks for its programs, and only for them.
        let programs=await store.programs(for:p,key:"test",network:true,force:true)
        #expect(programs != nil)
        #expect(await http.urls.map(\.path)==["/api/v1/alerts","/api/v1/events"])
        // Both parts are now fresh: nothing more within ten minutes, forced or not.
        _=await store.alerts(for:[p],key:"test",network:true,force:true)
        _=await store.programs(for:p,key:"test",network:true,force:true)
        #expect(await http.urls.count==2)
    }
    /// NPS caps a page of events at 50 whatever pageSize asks for, so pages are counted in fifties.
    @Test func eventsArePagedInFifties() async throws {
        let p=try park()
        let tomorrow=Date.now.addingTimeInterval(86400).formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let event={ (id:String,title:String) in "{\"id\":\"\(id)\",\"title\":\"\(title)\",\"datestart\":\"\(tomorrow)\",\"description\":\"\"}" }
        let page=(0..<50).map { event("e\($0)","Morning hike") }.joined(separator:",")
        let http=StubHTTP(["/api/v1/alerts":"{\"data\":[]}","/api/v1/events":"{\"total\":\"51\",\"data\":[\(page)]}"])
        _=await ParkStore(transport:http,persist:false).programs(for:p,key:"test",network:true,force:true)
        let events=await http.urls.filter { $0.path=="/api/v1/events" }
        #expect(events.count==2)
        #expect(events.allSatisfy { $0.query?.contains("pageSize=50") == true })
        #expect(events.last?.query?.contains("pageNumber=2") == true)
    }
    /// After the server refuses a request (the shared key's quota spent), nobody asks again for a
    /// while, even by pulling to refresh; being offline never waits.
    @Test func refusedRequestsBackOff() async throws {
        let p=try park()
        let http=StubHTTP(["/api/v1/alerts":"{\"data\":[]}"])
        let store=ParkStore(transport:http,persist:false)
        await http.setStatus(429)
        let refused=await store.alerts(for:[p],key:"test",network:true,force:true)
        #expect(refused.cache == nil && refused.busy)
        await http.setStatus(nil)
        let later=await store.alerts(for:[p],key:"test",network:true,force:true)
        #expect(later.cache == nil && later.busy)
        #expect(await http.urls.count==1)
        #expect(Backoff.delay(after:HTTPStatusError(status:429))==3600)
        #expect(Backoff.delay(after:HTTPStatusError(status:503))==900)
        #expect(Backoff.delay(after:URLError(.notConnectedToInternet))==nil)
        let weather=StubHTTP([:])
        await weather.setStatus(503)
        let service=WeatherService(transport:weather,persist:false)
        _=await service.forecasts(for:[p],network:true,force:true)
        _=await service.forecasts(for:[p],network:true,force:true)
        #expect(await weather.urls.count==1)
    }
    @Test func nightSkyProgramsAreRecognised() {
        #expect(ParkStore.isNightSky(title:"Space Explorations with NASA's James Webb Space Telescope",tags:[]))
        #expect(ParkStore.isNightSky(title:"Astronomical Society Star Party",tags:[]))
        #expect(ParkStore.isNightSky(title:"Evening program",tags:["Night Sky"]))
        #expect(!ParkStore.isNightSky(title:"Morning bird walk",tags:["birding"]))
    }
    /// Forecasts are always requested for every park, so the request never reflects where someone is.
    @MainActor @Test func forecastsAreRequestedForEveryPark() async throws {
        let http=StubHTTP([:])
        let model=PlanModel(weather:WeatherService(transport:http,persist:false),parkStore:ParkStore(transport:http,persist:false),detail:ForecastDetailService(transport:http,persist:false))
        model.weatherEnabled=true
        model.smokeEnabled=true
        let nearby=Array(model.parks.prefix(2))
        // A park page (programs) is what makes forecast detail wanted in a session.
        await model.refresh(nearby,parkUpdates:false,programs:true)
        // Clouds, model agreement, layers and smoke: each request kind covers every park.
        var counts:[String:Int]=[:]
        for url in await http.urls {
            let items=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
            let kind=(url.host ?? "")+(items.first { $0.name=="hourly" }?.value ?? "")+(items.first { $0.name=="models" }?.value ?? "")
            counts[kind,default:0]+=items.first { $0.name=="latitude" }?.value?.split(separator:",").count ?? 0
        }
        #expect(counts.count==4)
        #expect(counts.values.allSatisfy { $0==model.parks.count })
    }
    /// Switching reminders off while a reschedule is still running must not leave its cancelled
    /// reminders recorded as delivered, or those nights could never be announced again.
    @Test func remindersCancelledMidRescheduleStayPlannable() async throws {
        let all=try ParkData.load(), now=Date(timeIntervalSince1970:1790899200), engine=AstronomyEngine()
        // Two parks, so two reminders are added one after the other.
        let nights=try ["jotr","deva"].map { id in
            let p=try #require(all.first { $0.id==id })
            return Night(park:p,sky:engine.conditions(for:p,on:p.date(now,addingDays:1)),score:DarknessScore(value:94,moonPoints:39,cloudPoints:24,bortlePoints:18,lengthPoints:13),cloudCover:4,forecastUpdated:now)
        }
        let center=StubNotifications(),ledger=ReminderLedger(suite:"nyx-ledger-test-\(UUID().uuidString)")
        let scheduler=NotificationScheduler(center:center,ledger:ledger)
        // Reminders are switched off just after the first one is added.
        await center.onAdd { count in if count==1 { await scheduler.remove() } }
        await scheduler.reschedule(nights:nights,now:now)
        // The reminder cancelled by the switch was never seen, so it stays plannable.
        let cancelled=Set(nights.map { NotificationScheduler.identifier(park:$0.park,night:$0.id) }).subtracting(await center.requests.map(\.id))
        #expect(cancelled.count==1)
        #expect(cancelled.isDisjoint(with:ledger.ids))
    }
    /// With notifications off in Settings nothing new is added, but a reminder for a night that
    /// no longer qualifies is still cancelled, so it cannot fire when they are turned back on.
    @Test func remindersAreCancelledWithoutPermission() async throws {
        let p=try park(),now=Date(timeIntervalSince1970:1790899200),engine=AstronomyEngine()
        let night=Night(park:p,sky:engine.conditions(for:p,on:p.date(now,addingDays:2)),score:DarknessScore(value:94,moonPoints:39,cloudPoints:24,bortlePoints:18,lengthPoints:13),cloudCover:4,forecastUpdated:now)
        let center=StubNotifications(),ledger=ReminderLedger(suite:"nyx-ledger-test-\(UUID().uuidString)")
        let scheduler=NotificationScheduler(center:center,ledger:ledger)
        await scheduler.reschedule(nights:[night],now:now)
        #expect(await center.pendingIDs().count==1)
        await center.setAllowed(false)
        await scheduler.reschedule(nights:[],now:now)
        #expect(await center.pendingIDs().isEmpty)
        await scheduler.reschedule(nights:[night],now:now)
        #expect(await center.pendingIDs().isEmpty)
    }
    @Test func rejectsOtherHosts() async {
        guard let url=URL(string:"https://example.com/forecast") else { Issue.record("Bad fixture URL");return }
        await #expect(throws:URLError.self) { try await SafeHTTP().get(url) }
    }
    /// The 64-request budget holds with every park saved; nights without a forecast never qualify.
    @Test func reminderLimitAndForecastRequirement() async throws {
        let now=Date(timeIntervalSince1970:1790899200),engine=AstronomyEngine()
        var nights:[Night]=[]
        for p in try ParkData.load() {
            let sky=engine.conditions(for:p,on:p.date(p.currentNight(at:now),addingDays:1))
            guard sky.darkHours>0 else { continue }
            nights.append(Night(park:p,sky:sky,score:DarknessScore(value:94,moonPoints:39,cloudPoints:24,bortlePoints:18,lengthPoints:13),cloudCover:4,forecastUpdated:now))
        }
        #expect(nights.count>54)
        let center=StubNotifications(ids:(0..<10).map{"unrelated-\($0)"}+["nyx-night-old"])
        let scheduler=NotificationScheduler(center:center,ledger:ReminderLedger(suite:"nyx-ledger-test-\(UUID().uuidString)"))
        await scheduler.reschedule(nights:nights+nights,now:now)
        #expect(await center.requests.count==54)
        #expect(Set(await center.requests.map(\.id)).count==54)
        #expect(await center.ids.count==10)
        let noCloud=Night(park:nights[0].park,sky:nights[0].sky,score:DarknessScore(value:94,moonPoints:53,cloudPoints:nil,bortlePoints:24,lengthPoints:17),cloudCover:nil,forecastUpdated:nil)
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
