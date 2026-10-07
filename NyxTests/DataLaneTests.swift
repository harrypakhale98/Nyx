import Foundation
import SwiftData
import Testing
@testable import Nyx

/// Records every request with its headers; answers by path, optionally after a pause, so tests
/// can hold one request open while another screen asks.
actor HeaderHTTP: HTTPTransport {
    struct Call: Sendable { let url: URL; let headers: [String: String]; let constrained: Bool }
    var calls: [Call]=[]
    var bodies: [String: [String]]
    var status: Int?
    var error: URLError?
    var delay: Duration?
    init(_ bodies: [String: [String]]) { self.bodies=bodies }
    func set(status: Int?) { self.status=status }
    func set(error: URLError?) { self.error=error }
    func set(delay: Duration?) { self.delay=delay }
    func get(_ url: URL) async throws -> Data { try await get(url, headers: [:], constrained: true) }
    func get(_ url: URL, headers: [String: String], constrained: Bool) async throws -> Data {
        calls.append(Call(url: url, headers: headers, constrained: constrained))
        if let delay { try? await Task.sleep(for: delay) }
        if let error { throw error }
        if let status { throw HTTPStatusError(status: status) }
        guard var queue=bodies[url.path], !queue.isEmpty else { throw URLError(.badServerResponse) }
        let body=queue.count>1 ? queue.removeFirst() : queue[0]
        bodies[url.path]=queue
        return Data(body.utf8)
    }
}
private func alert(_ id: String, _ title: String, _ category: String, _ code: String) -> String {
    "{\"id\":\"\(id)\",\"title\":\"\(title)\",\"description\":\"<p>Details</p>\",\"category\":\"\(category)\",\"parkCode\":\"\(code)\",\"url\":\"\"}"
}
private func query(_ url: URL, _ name: String) -> String? { URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value }

struct DataLaneTests {
    let parks: [Park]
    init() throws { parks=try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }

    // MARK: NPS alerts: one request for every park

    /// Every screen shares one alerts request naming all 63 parks; the key travels in the header,
    /// never in the URL; one response becomes each park's own list.
    @MainActor @Test func oneAlertsRequestServesEveryPark() async throws {
        let body="{\"total\":\"4\",\"limit\":\"500\",\"start\":\"0\",\"data\":["+[
            alert("a1","Gas Pumps at Panamint Springs Resort are Closed at Night","Information","deva"),
            alert("a2","Oasis of Mara Trail Partial Closure","Caution","jotr"),
            alert("a3","Generals Highway Closed","Park Closure","seki"),
            alert("a4","Shared Notice","Information","acad,ever"),
        ].joined(separator:",")+"]}"
        let http=HeaderHTTP(["/api/v1/alerts":[body]])
        let store=ParkStore(transport: http, persist: false)
        let update=await store.alerts(for: parks, key: "TESTKEY", network: true, force: false)
        let calls=await http.calls
        #expect(calls.count == 1)
        let call=try #require(calls.first)
        #expect(call.headers["X-Api-Key"] == "TESTKEY")
        #expect(!(call.url.absoluteString.contains("TESTKEY")) && query(call.url, "api_key") == nil)
        #expect(query(call.url, "limit") == "500")
        let codes=Set(query(call.url, "parkCode")?.split(separator: ",").map(String.init) ?? [])
        #expect(codes == Set(parks.map(\.apiCode)))
        let cache=try #require(update.cache)
        #expect(cache.alerts["deva"]?.map(\.id) == ["a1"])
        #expect(cache.alerts["acad"]?.map(\.id) == ["a4"] && cache.alerts["ever"]?.map(\.id) == ["a4"])
        // Checked and clear: present with no alerts.
        #expect(cache.alerts["grba"] == [])
        // Sequoia and Kings Canyon share one NPS code and so share its alerts.
        let model=PlanModel(weather: WeatherService(transport: http, persist: false), parkStore: store, detail: ForecastDetailService(transport: http, persist: false))
        model.npsEnabled=true
        await model.refreshParkUpdates([])
        #expect(model.enrichments["kica"]?.alerts.first?.id == "a3" && model.enrichments["sequ"]?.alerts.first?.id == "a3")
        #expect(model.enrichments["deva"]?.programs.isEmpty == true)
        // Asking again from another screen within six hours costs nothing.
        _=await store.alerts(for: parks, key: "TESTKEY", network: true, force: false)
        #expect(await http.calls.count == 1)
    }
    /// More alerts than one page holds are fetched with `start`; a page that fails keeps the old set.
    @Test func alertsArePaged() async throws {
        let first="{\"total\":\"3\",\"data\":["+alert("a","Road Closed","Park Closure","jotr")+","+alert("b","Trail Closed","Park Closure","jotr")+"]}"
        let second="{\"total\":\"3\",\"data\":["+alert("c","Campground Closed","Park Closure","deva")+"]}"
        let http=HeaderHTTP(["/api/v1/alerts":[first,second]])
        let update=await ParkStore(transport: http, persist: false).alerts(for: parks, key: "k", network: true, force: false)
        let starts=await http.calls.map { query($0.url, "start") }
        #expect(starts == ["0","2"])
        #expect(update.cache?.alerts["jotr"]?.count == 2 && update.cache?.alerts["deva"]?.count == 1)
    }
    /// A refusal is remembered on disk: a relaunch (a new store reading the same file) neither asks
    /// again nor forgets to say NPS is busy.
    @Test func backoffSurvivesRelaunch() async throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-backoff-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let http=HeaderHTTP(["/api/v1/alerts":["{\"data\":[]}"]])
        await http.set(status: 429)
        let refused=await ParkStore(transport: http, persist: false, backoff: HostBackoff(file: file)).alerts(for: parks, key: "k", network: true, force: true)
        #expect(refused.busy)
        await http.set(status: nil)
        let relaunched=ParkStore(transport: http, persist: false, backoff: HostBackoff(file: file))
        let later=await relaunched.alerts(for: parks, key: "k", network: true, force: true)
        #expect(later.busy && later.cache == nil)
        #expect(await http.calls.count == 1)
        #expect(HostBackoff(file: file).retryAfter(ParkStore.host) != nil)
        // An hour on, the host is asked again.
        let clock=Date.now.addingTimeInterval(3601)
        let afterwards=ParkStore(transport: http, persist: false, backoff: HostBackoff(file: file), clock: { clock })
        #expect(await afterwards.alerts(for: parks, key: "k", network: true, force: true).busy == false)
        #expect(await http.calls.count == 2)
    }
    /// A campground Wi-Fi sign-in page answers with a redirect: that is being offline, not the
    /// service refusing, so the next request goes out at once. Only 429 and 5xx wait.
    @Test func captivePortalRedirectIsNotABlackout() async throws {
        #expect(Backoff.delay(after: HTTPStatusError(status: 302)) == nil)
        #expect(Backoff.delay(after: HTTPStatusError(status: 307)) == nil)
        #expect(Backoff.delay(after: HTTPStatusError(status: 404)) == nil)
        #expect(Backoff.delay(after: HTTPStatusError(status: 500)) == 900)
        let http=HeaderHTTP(["/v1/forecast":["{\"hourly\":{\"time\":[1700000000,1700003600],\"cloud_cover\":[10,20]}}"]])
        await http.set(status: 302)
        let service=WeatherService(transport: http, persist: false)
        #expect(await service.forecasts(for: [try park("jotr")], network: true, force: true).isEmpty)
        await http.set(status: nil)
        #expect(await service.forecasts(for: [try park("jotr")], network: true, force: true)["jotr"]?.clouds == [10,20])
        #expect(await http.calls.count == 2)
    }
    /// A park page opened while Tonight's alerts request is still on its way still gets its programs,
    /// and the alerts request is never repeated by the waiter.
    @Test func waitersDecideAgainAfterTheRequestEnds() async throws {
        let tomorrow=Date.now.addingTimeInterval(86400).formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let http=HeaderHTTP(["/api/v1/alerts":["{\"data\":[]}"],
                             "/api/v1/events":["{\"total\":\"1\",\"data\":[{\"id\":\"s\",\"title\":\"Star party\",\"datestart\":\"\(tomorrow)\",\"description\":\"\"}]}"]])
        await http.set(delay: .milliseconds(200))
        let store=ParkStore(transport: http, persist: false), jotr=try park("jotr")
        async let tonight=store.alerts(for: parks, key: "k", network: true, force: false)
        try await Task.sleep(for: .milliseconds(50))
        async let detail=store.alerts(for: parks, key: "k", network: true, force: false)
        async let programs=store.programs(for: jotr, key: "k", network: true, force: false)
        let (a, b, p)=await (tonight, detail, programs)
        #expect(a.cache != nil && b.cache != nil)
        #expect(p?.programs.map(\.title) == ["Star party"])
        let paths=await http.calls.map(\.url.path)
        #expect(paths.filter { $0 == "/api/v1/alerts" }.count == 1)
        #expect(paths.filter { $0 == "/api/v1/events" }.count == 1)
    }

    // MARK: Alert meaning and wording

    /// Real NPS headlines (2026-10-07): closures of places stand beside the score; amenity notices never do.
    @Test func alertsAreClassified() {
        func kind(_ title: String, _ category: String) -> AlertKind { ParkAlert(id: "x", title: title, description: "", category: category).kind }
        #expect(kind("Gas Pumps at Panamint Springs Resort are Closed at Night", "Information") == .notice)
        #expect(kind("No Water or Bathrooms at Kīpahulu", "Park Closure") == .notice)
        #expect(kind("Elevator for Accessible Tour Out of Service", "Park Closure") == .notice)
        #expect(kind("EV charging station unavailable", "Information") == .notice)
        #expect(kind("Phones are Down in Rincon Mountain District", "Information") == .notice)
        #expect(kind("Overnight Lodging Suspended and Parkwide Stage 4 Water Restrictions", "Caution") == .caution)
        #expect(kind("Road Open To: Mile 30 (Teklanika River)", "Information") == .notice)
        #expect(kind("Glacier Point Road is temporarily closed due to the Dome Fire", "Park Closure") == .closure)
        #expect(kind("Sulphur Banks Bridge Closed; Boardwalk is Open", "Information") == .closure)
        #expect(kind("Oasis of Mara Trail Partial Closure", "Caution") == .closure)
        #expect(kind("Loop Drive closed in Tucson Mountain District due to storms.", "Danger") == .closure)
        #expect(kind("Juniper Lake Campground Closed", "Information") == .closure)
        #expect(kind("Green River Ferry Temporarily Out of Service", "Park Closure") == .closure)
        #expect(kind("Javelina Wash near Red Hills Visitor Center closed for safety", "Park Closure") == .closure)
        // NPS calls it a closure and it is not about an amenity: trusted, even without the word.
        #expect(kind("Dunes Drive Safety Corridor", "Park Closure") == .closure)
        #expect(kind("Crews Responding to Mount Tom Creek Fire", "Danger") == .danger)
        // The hero takes the closure even when a notice comes first; the list ranks closures first.
        let alerts=[ParkAlert(id: "1", title: "Gas Pumps at Panamint Springs Resort are Closed at Night", description: "", category: "Information"),
                    ParkAlert(id: "2", title: "Heat Danger", description: "", category: "Danger"),
                    ParkAlert(id: "3", title: "Badwater Road Closed", description: "", category: "Park Closure")]
        #expect(AlertRanking.closure(alerts)?.id == "3")
        #expect(AlertRanking.ranked(alerts).map(\.id) == ["3","2","1"])
        #expect(AlertRanking.closure(Array(alerts.prefix(2))) == nil)
    }
    @Test func headlinesReadAsSentences() throws {
        func sentence(_ title: String, _ park: String) throws -> String { ParkAlert(id: "x", title: title, description: "", category: "").displayTitle(park: try self.park(park)) }
        #expect(try sentence("Gas Pumps at Panamint Springs Resort are Closed at Night", "deva") == "Gas pumps at Panamint Springs Resort are closed at night")
        #expect(try sentence("Notch Trail Closure for Repairs", "badl") == "Notch Trail closure for repairs")
        #expect(try sentence("Keanakākoʻi Side of Kīlauea Volcano Closed Due to Volcanic Unrest", "havo") == "Keanakākoʻi side of Kīlauea Volcano closed due to volcanic unrest")
        #expect(try sentence("Mauna Loa Road Closed Past Second Cattle Guard for Tree Removal", "havo") == "Mauna Loa Road closed past second cattle guard for tree removal")
        #expect(try sentence("Eastern Section of Beech Mountain Loop Trail Closed for Repairs", "acad") == "Eastern section of Beech Mountain Loop Trail closed for repairs")
        #expect(try sentence("Highway 101 Closed at Hoh River Bridge", "olym") == "Highway 101 closed at Hoh River Bridge")
        #expect(try sentence("Shenandoah National Park Moved to Fully Cashless Fee Collection", "shen") == "Shenandoah National Park moved to fully cashless fee collection")
        #expect(try sentence("Road Open To: Mile 30 (Teklanika River)", "dena") == "Road open to: Mile 30 (Teklanika River)")
        #expect(try sentence("No Water or Bathrooms at Kīpahulu", "hale") == "No water or bathrooms at Kīpahulu")
        // Already a sentence, or all capitals: left exactly as NPS wrote it.
        #expect(try sentence("Glacier Point Road is temporarily closed due to the Dome Fire", "yose") == "Glacier Point Road is temporarily closed due to the Dome Fire")
        #expect(try sentence("INNER CANYON TRAIL CLOSURES", "grca") == "INNER CANYON TRAIL CLOSURES")
    }

    // MARK: Reminders

    func night(_ id: String, daysAhead: Int, from now: Date, score: Int=94, updated: Date?) throws -> Night {
        let p=try park(id), sky=AstronomyEngine().conditions(for: p, on: p.date(p.currentNight(at: now), addingDays: daysAhead))
        return Night(park: p, sky: sky, score: DarknessScore(value: score, moonPoints: 39, cloudPoints: 24, bortlePoints: 18, lengthPoints: 13), cloudCover: 4, forecastUpdated: updated)
    }
    /// A reminder fires only on a forecast it would still trust (at most 36 hours old when it
    /// fires), and only for a night at most five days ahead.
    @Test func reminderLeadTimeFollowsForecastAge() throws {
        let now=Date(timeIntervalSince1970: 1790899200) // 2026-10-02 00:00 UTC, the evening of Oct 1 in California
        let scheduler=NotificationScheduler(center: StubNotifications(), ledger: ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)"))
        // Tomorrow, on a forecast from now: fires tomorrow evening's eve, about a day on. Planned.
        #expect(scheduler.plans(nights: [try night("jotr", daysAhead: 1, from: now, updated: now)], now: now).count == 1)
        // Three nights out on today's forecast: it would be about three days old when it fires. Waits.
        #expect(scheduler.plans(nights: [try night("jotr", daysAhead: 3, from: now, updated: now)], now: now).isEmpty)
        // The same night once a background refresh has a forecast from two days on: planned.
        #expect(scheduler.plans(nights: [try night("jotr", daysAhead: 3, from: now, updated: now.addingTimeInterval(2*86400))], now: now).count == 1)
        // Beyond five nights, never, however fresh.
        #expect(scheduler.plans(nights: [try night("jotr", daysAhead: 6, from: now, updated: now.addingTimeInterval(5*86400))], now: now).isEmpty)
    }
    /// One score reminder per park in seven nights: the best of a run, the earliest on a tie; and a
    /// night already announced holds the park.
    @Test func oneReminderPerParkPerWeek() throws {
        let now=Date(timeIntervalSince1970: 1790899200)
        let scheduler=NotificationScheduler(center: StubNotifications(), ledger: ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)"))
        let fresh={ (days: Int) in now.addingTimeInterval(Double(days)*86400) }
        let run=[try night("jotr", daysAhead: 1, from: now, score: 92, updated: fresh(0)),
                 try night("jotr", daysAhead: 2, from: now, score: 96, updated: fresh(1)),
                 try night("jotr", daysAhead: 3, from: now, score: 96, updated: fresh(2)),
                 try night("deva", daysAhead: 1, from: now, score: 91, updated: fresh(0))]
        let plans=scheduler.plans(nights: run, now: now)
        #expect(plans.count == 2)
        let jotr=try #require(plans.first { $0.parkID == "jotr" })
        #expect(jotr.id == NotificationScheduler.identifier(park: run[1].park, night: run[1].id))
        // Tuesday's reminder was already seen: nothing else for Joshua Tree within the week.
        let seen=NotificationScheduler.identifier(park: run[0].park, night: run[0].id)
        #expect(scheduler.plans(nights: Array(run.dropFirst()), now: now, delivered: [seen]).map(\.parkID) == ["deva"])
    }
    /// The reminder names the night, its band and score in words, and a true reason; tapping it
    /// opens that night.
    @Test func reminderCopyAndRoute() throws {
        let now=Date(timeIntervalSince1970: 1790899200)
        let scheduler=NotificationScheduler(center: StubNotifications(), ledger: ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)"))
        let tonight=try night("jotr", daysAhead: 1, from: now, updated: now)
        let plan=try #require(scheduler.plans(nights: [tonight], now: now).first)
        var weekday=Date.FormatStyle.dateTime.weekday(.wide); weekday.timeZone=tonight.park.timeZone
        #expect(plan.title == "Pristine night at Joshua Tree, \(tonight.id.formatted(weekday))")
        #expect(plan.body.hasPrefix("94 out of 100. ") && plan.body.hasSuffix(". Check park alerts before you go."))
        #expect(!plan.body.contains("/"))
        #expect(plan.body.contains(NotificationScheduler.reason(tonight)))
        #expect(plan.userInfo["night"] == tonight.park.isoDay(tonight.id))
        let route=try #require(ReminderRoute(userInfo: plan.userInfo))
        #expect(route.parkID == "jotr" && !route.whatsUp)
        #expect(route.day?.evening(in: tonight.park) == tonight.id)
        // Reminders from 1.1 (7) carried only the park: they still open it.
        #expect(ReminderRoute(userInfo: ["parkID": "deva"]) == ReminderRoute(parkID: "deva"))
        #expect(ReminderRoute(userInfo: [:]) == nil)
    }

    // MARK: Widget snapshot and watch context across versions

    @Test func snapshotDecodesAcrossVersions() throws {
        let jotr=try park("jotr")
        // As 1.1 (7) wrote it: no version, no closures.
        let old=try JSONEncoder().encode(["parks": [jotr]])
        let decodedOld=try JSONDecoder().decode(SavedSkySnapshot.self, from: old)
        #expect(decodedOld.version == 1 && decodedOld.parks.map(\.id) == ["jotr"] && decodedOld.closures.isEmpty && decodedOld.forecasts.isEmpty)
        // Current: round trip with closures.
        let now=SavedSkySnapshot(parks: [jotr], forecasts: [:], closures: ["jotr": "Oasis of Mara Trail partial closure"])
        let decoded=try JSONDecoder().decode(SavedSkySnapshot.self, from: try JSONEncoder().encode(now))
        #expect(decoded.version == SavedSkySnapshot.currentVersion && decoded.closures["jotr"] == "Oasis of Mara Trail partial closure")
        // A park that no longer decodes (a field a later version requires) costs that park only.
        var parksJSON=try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode([jotr, try park("deva")])) as? [[String: Any]])
        parksJSON[1].removeValue(forKey: "latitude")
        let mixed=try JSONSerialization.data(withJSONObject: ["version": 3, "parks": parksJSON, "future": true])
        #expect(try JSONDecoder().decode(SavedSkySnapshot.self, from: mixed).parks.map(\.id) == ["jotr"])
    }
    /// A watch on 1.1 reads a newer phone's context, and a phone's v1 context still reads.
    @Test func contextDecodesAcrossVersions() throws {
        let v1="{\"version\":1,\"sent\":0,\"savedParkIDs\":[\"jotr\"],\"homeParkID\":\"jotr\",\"nightVision\":true,\"forecasts\":{\"jotr\":{\"updated\":0,\"start\":1791158400,\"clouds\":[10,null,30]}}}"
        let context=try #require(WatchContext(data: Data(v1.utf8)))
        #expect(context.savedParkIDs == ["jotr"] && context.nightVision && context.cloudForecasts["jotr"]?.clouds.count == 3)
        let newer="{\"version\":2,\"sent\":0,\"homeParkID\":\"deva\",\"fieldPark\":\"deva\",\"forecasts\":{\"jotr\":{\"shape\":\"new\"}}}"
        let read=try #require(WatchContext(data: Data(newer.utf8)))
        #expect(read.homeParkID == "deva" && read.savedParkIDs.isEmpty && !read.nightVision && read.forecasts.isEmpty)
    }

    // MARK: Journal store

    /// A store written by 1.1 (7), on disk, opens through the migration plan with every photo moved.
    @MainActor @Test func versionZeroStoreMigratesWithPhotos() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url=folder.appendingPathComponent("default.store")
        let photos=[Data([1,2,3]), Data(repeating: 7, count: 200_000)]
        var id=UUID()
        do {
            // Unversioned, exactly as build 7 opened it.
            let old=try ModelContainer(for: NyxSchemaV0.SavedPark.self, NyxSchemaV0.JournalEntry.self, configurations: ModelConfiguration(url: url))
            let context=ModelContext(old)
            let entry=NyxSchemaV0.JournalEntry(date: .now, parkID: "jotr", observedBortle: 2, notes: "Clear and still.", photos: photos)
            id=entry.id
            context.insert(entry); context.insert(NyxSchemaV0.SavedPark(parkID: "deva"))
            context.insert(NyxSchemaV0.JournalEntry(date: .now, parkID: "deva", notes: "No photos."))
            try context.save()
        }
        let opened=JournalStore.open(inMemory: false, url: url)
        #expect(!opened.failed)
        let container=try #require(opened.container)
        let context=ModelContext(container)
        let entries=try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 2)
        let moved=try #require(entries.first { $0.id == id })
        #expect(moved.photos == photos && moved.notes == "Clear and still." && moved.observedBortle == 2)
        #expect(entries.first { $0.id != id }?.photos.isEmpty == true)
        #expect(try context.fetch(FetchDescriptor<SavedPark>()).map(\.parkID) == ["deva"])
        #expect(JournalMigration.folder.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
    }
    /// A store that cannot be opened leaves the file untouched and the planner working.
    @MainActor @Test func unreadableStoreKeepsThePlannerWorking() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-bad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url=folder.appendingPathComponent("default.store")
        let junk=Data("not a database".utf8)
        try junk.write(to: url)
        let opened=JournalStore.open(inMemory: false, url: url)
        #expect(opened.failed && opened.container != nil)
        #expect(try Data(contentsOf: url) == junk)
        let model=PlanModel(weather: WeatherService(transport: StubHTTP([:]), persist: false), parkStore: ParkStore(transport: StubHTTP([:]), persist: false), detail: ForecastDetailService(transport: StubHTTP([:]), persist: false))
        model.journalUnavailable=opened.failed
        let home=try #require(model.home)
        #expect(model.night(home).score.value>0)
    }
    /// Export, then import into another device's journal: everything arrives once, and importing
    /// again adds nothing.
    @MainActor @Test func journalRoundTrips() throws {
        let schema=Schema(versionedSchema: NyxSchemaV1.self)
        let phone=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        let entry=JournalEntry(date: Date(timeIntervalSince1970: 1790899200), parkID: "jotr", observedBortle: 2, notes: "Saturn's rings.")
        phone.insert(entry); try phone.save()
        entry.photos=[Data([9,9,9]), Data([1])]
        entry.orderedPhotos.first?.altText="The Milky Way over Joshua trees."
        phone.insert(JournalEntry(date: Date(timeIntervalSince1970: 1790999200), parkID: "deva", notes: "Windy."))
        try phone.save()
        let archive=JournalArchive.make(from: try phone.fetch(FetchDescriptor<JournalEntry>()))
        let reread=try JournalArchive(wrapper: archive.fileWrapper())
        #expect(reread == archive)
        let ipad=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        ipad.insert(JournalEntry(date: Date(timeIntervalSince1970: 1790999200+3600), parkID: "deva", notes: "Same night, written here."))
        try ipad.save()
        let result=try reread.merge(into: ipad, parks: parks)
        #expect(result.added == 1 && result.skipped == 1)
        let imported=try #require(try ipad.fetch(FetchDescriptor<JournalEntry>()).first { $0.id == entry.id })
        #expect(imported.photos == [Data([9,9,9]), Data([1])] && imported.notes == "Saturn's rings.")
        #expect(imported.orderedPhotos.first?.altText == "The Milky Way over Joshua trees.")
        #expect(try reread.merge(into: ipad, parks: parks).added == 0)
        #expect(try ipad.fetch(FetchDescriptor<JournalEntry>()).count == 2)
    }

    // MARK: Forecasts

    /// Clouds are asked for where people stand under the sky (Haleakalā's summit, not the park's
    /// centre), sixteen days of hours in all, and forecast detail never uses Low Data Mode.
    @Test func forecastsUseViewingSpotsAndDetailAvoidsLowData() async throws {
        let hale=try park("hale")
        #expect(hale.forecastPoint.latitude == hale.viewingSpots[0].latitude && hale.forecastPoint.longitude == hale.viewingSpots[0].longitude)
        let http=HeaderHTTP(["/v1/forecast":["{\"hourly\":{\"time\":[1700000000],\"cloud_cover\":[5]}}"]])
        _=await WeatherService(transport: http, persist: false).forecasts(for: [hale], network: true, force: true)
        let call=try #require(await http.calls.first)
        #expect(query(call.url, "latitude") == String(hale.viewingSpots[0].latitude) && query(call.url, "forecast_days") == "15" && query(call.url, "past_days") == "1")
        #expect(call.constrained)
        let detail=HeaderHTTP([:])
        await detail.set(error: URLError(.notConnectedToInternet, userInfo: [NSURLErrorNetworkUnavailableReasonKey: URLError.NetworkUnavailableReason.constrained.rawValue]))
        let service=ForecastDetailService(transport: detail, persist: false)
        _=await service.details(for: [hale], weather: true, smoke: true, force: true)
        #expect(await detail.calls.allSatisfy { !$0.constrained })
        #expect(await service.pausedForLowData())
        // Held back by Low Data Mode is not a refusal: nothing waits.
        _=await service.details(for: [hale], weather: true, smoke: true, force: true)
        #expect(await detail.calls.count == 6)
    }

    // MARK: Field mode and diagnostics

    @MainActor @Test func fieldModeLetsTheScreenLockAfterTenQuietMinutes() {
        let touch=Date(timeIntervalSince1970: 1_790_000_000)
        #expect(!FieldSession.autoLockReturns(lastTouch: touch, now: touch.addingTimeInterval(599)))
        #expect(FieldSession.autoLockReturns(lastTouch: touch, now: touch.addingTimeInterval(600)))
    }
    @Test func diagnosticsKeepTheLastFive() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-diag-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for day in 0..<7 {
            DiagnosticsStore.save(DiagnosticRecord(id: "r\(day)", kind: day.isMultiple(of: 2) ? .crash : .hang, received: Date(timeIntervalSince1970: Double(day)*86400), json: "{}"), in: folder)
        }
        let kept=DiagnosticsStore.load(from: folder)
        #expect(kept.map(\.id) == ["r6","r5","r4","r3","r2"])
        let report=DiagnosticsStore.report(kept)
        #expect(report.hasPrefix("Nyx ") && report.contains("--- crash"))
    }
    @Test func ownKeysAreCleanedBeforeUse() {
        #expect(NPSKeyStore.clean(" abcDEF123 \n") == "abcDEF123")
        #expect(NPSKeyStore.plausible(String(repeating: "a1", count: 20)))
        #expect(!NPSKeyStore.plausible("short"))
    }
}
