import Foundation
import Testing
@testable import Nyx

/// Learn essays, the map of tonight, campgrounds and From home tonight.
struct ContentLaneTests {
    let parks: [Park]
    init() throws { parks=try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    static func date(_ iso: String) throws -> Date { try Date(iso+"T21:00:00Z", strategy: .iso8601) }

    // MARK: Learn

    /// Every essay has text (the catalog's, or the bundled English source until the catalog holds
    /// it), a title line that is not repeated as a paragraph, and the length of a short read.
    @MainActor @Test func everyEssayHasItsText() {
        for essay in Essay.allCases {
            let text=essay.content
            #expect(!text.hasPrefix("essay."), "\(essay) shows its key")
            let paragraphs=text.components(separatedBy: "\n\n")
            #expect(paragraphs.count>=5, "\(essay)")
            #expect(!text.contains("!"), "\(essay) has an exclamation mark")
            #expect(essay.minutes>=1 && essay.minutes<=3, "\(essay)")
        }
        #expect(Essay.allCases.first == .score)
        #expect(Essay.text("score").hasPrefix("Reading the darkness score\n\n"))
        #expect(Essay.text("no-such-essay").isEmpty)
    }
    /// The score essay's worked night is the engine's own arithmetic: four parts adding to 86,
    /// held to 64 by 40% cloud.
    @MainActor @Test func scoreEssayWorkedNightMatchesTheEngine() {
        let sky=SkyConditions(evening: .now, end: .now+86_400, sunset: nil, sunrise: nil, civilDusk: nil, nauticalDusk: nil, darkStart: .now, darkEnd: .now+9*3600,
                              state: .normal, moon: MoonPhase(fraction: 0.02), moonrise: nil, moonset: nil, moonBelowFraction: 1, darkHours: 9, moonlight: 0)
        let score=ScoreEngine().score(sky: sky, bortle: 2, cloud: 40, basis: .forecast, aerosol: nil)
        #expect(Int((score.moonPoints+(score.cloudPoints ?? 0)+score.bortlePoints+score.lengthPoints).rounded()) == 86)
        #expect(score.value == 64 && score.limit == .clouds(64) && score.band == .good)
        #expect(Essay.text("score").contains("The parts add up to 86") && Essay.text("score").contains("caps the night at 64"))
        #expect(ScoreEngine.cloudCap(50) == 55 && ScoreEngine.cloudCap(100) == 10 && ScoreEngine.glowCap(bortle: 3) == 89)
    }

    // MARK: Map of tonight

    func nights(on iso: String) throws -> [Night] {
        let now=try Self.date(iso), engine=AstronomyEngine()
        return parks.map { park in NightPlanner.night(park: park, sky: engine.conditions(for: park, on: park.evening(park.currentNight(at: now))), forecast: nil, detail: nil, now: now) }
    }
    /// VoiceOver meets the parks west to east across the lower 48, then the insets in the order
    /// they sit on the map, each west to east.
    @Test func mapReadsWestToEastWithInsetsLast() throws {
        let map=TonightMap(nights: try nights(on: "2026-10-09"))
        #expect(map.marks.count == 63)
        let regions=map.marks.map(\.region)
        let order: [SkyMap.Region]=[.lower48, .alaska, .hawaii, .samoa, .virginIslands]
        #expect(regions == regions.sorted { order.firstIndex(of: $0) ?? 0 < order.firstIndex(of: $1) ?? 0 })
        let byID=Dictionary(uniqueKeysWithValues: parks.map { ($0.id, $0) })
        for region in order {
            let longitudes=map.marks.filter { $0.region == region }.compactMap { byID[$0.id]?.longitude }
            #expect(longitudes == longitudes.sorted(), "\(region)")
        }
        #expect(map.marks.filter { $0.region == .alaska }.count == 8)
        #expect(map.marks.last?.id == "viis")
        #expect(map.marks.first(where: { $0.region == .samoa })?.id == "npsa")
    }
    /// The rotor and the named few follow the same ranking as every list: score, then the darker sky.
    @Test func mapRanksLikeEveryList() throws {
        let all=try nights(on: "2026-10-09")
        let map=TonightMap(nights: all)
        let ranked=all.sorted(by: NightPlanner.better).map(\.park.id)
        #expect(map.darkest.map(\.id) == ranked)
        #expect(map.labelled().map(\.id) == Array(ranked.prefix(3)))
        let scores=map.darkest.map(\.score)
        #expect(scores == scores.sorted(by: >))
    }
    /// Marks look like the calendar's night cells: the same size curve and fill, filled only with a forecast.
    @Test func mapMarksMatchNightCells() throws {
        #expect(TonightMap.radius(score: 0) == 1.5 && TonightMap.radius(score: 100) == 9.5)
        #expect(abs(TonightMap.radius(score: 50)-(1.5+8*pow(0.5, 1.5)))<1e-12)
        #expect(TonightMap.fillOpacity(score: 0) == 0.45 && TonightMap.fillOpacity(score: 100) == 0.95)
        for s in stride(from: 0, to: 100, by: 5) { #expect(TonightMap.radius(score: s+5)>TonightMap.radius(score: s)) }
        #expect(TonightMap.radius(score: 140) == TonightMap.radius(score: 100) && TonightMap.radius(score: -3) == TonightMap.radius(score: 0))
        // No forecast at all: every park's night rests on its usual clouds and is drawn hollow.
        let map=TonightMap(nights: try nights(on: "2026-10-09"), closures: ["deva": "Badwater Road closed"])
        #expect(map.marks.allSatisfy { $0.fill == .hollow })
        let deva=try #require(map.marks.first { $0.id == "deva" })
        #expect(deva.label.hasPrefix("Death Valley, \(deva.score), \(deva.band.label)"))
        #expect(deva.label.contains("No cloud forecast yet") && deva.label.hasSuffix("Closure: Badwater Road closed"))
        #expect(map.marks.filter { $0.closure != nil }.map(\.id) == ["deva"])
        #expect(map.summary.contains("1 parks have a closure") || map.summary.contains("1 park has a closure"))
    }

    // MARK: Campgrounds

    func fixture() throws -> Data {
        let url=try #require(Bundle(for: BundleAnchor.self).url(forResource: "campgrounds-fixture", withExtension: "json"))
        return try Data(contentsOf: url)
    }
    /// A recorded `/api/v1/campgrounds` response (2026-10-07, trimmed to seven campgrounds): counts
    /// arrive as strings, reservation links are kept only on recreation.gov or nps.gov, and each
    /// description becomes one clean first sentence.
    @Test func campgroundsParseFromARecordedResponse() throws {
        let page=try Campground.page(try fixture())
        #expect(page.count == 7 && page.campgrounds.count == 7 && page.total == 7)
        let byName=Dictionary(uniqueKeysWithValues: page.campgrounds.map { ($0.name, $0) })
        let cottonwood=try #require(byName["Cottonwood Campground"])
        #expect(cottonwood.parkCode == "jotr" && cottonwood.reservableSites == 62 && cottonwood.firstComeSites == 0 && cottonwood.totalSites == 62)
        #expect(cottonwood.reservationURL?.host() == "www.recreation.gov" && cottonwood.reservationSite == "Recreation.gov")
        #expect(cottonwood.summary == "The Cottonwood Campground is reservation only and has 62 sites, potable water and flush toilets.")
        #expect(cottonwood.wheelchairAccess == "Most campsites have uneven terrain.")
        #expect(cottonwood.pageURL?.host() == "www.nps.gov")
        let whiteTank=try #require(byName["White Tank Campground"])
        #expect(whiteTank.reservationURL == nil && whiteTank.firstComeSites == 15)
        // A concessioner's booking engine with tracking parameters is never linked.
        let trailer=try #require(byName["Trailer Village RV Park - South Rim"])
        #expect(trailer.reservationURL == nil && trailer.summary.hasPrefix("CLOSED as of August 31, 2026"))
        let douglas=try #require(page.campgrounds.first { $0.parkCode == "sagu" })
        #expect(!douglas.summary.hasPrefix("-") && !douglas.summary.contains("*") && douglas.summary.hasPrefix("4,800 feet elevation"))
        #expect(douglas.reservableSites == 0 && douglas.wheelchairAccess == nil)
        let risingSun=try #require(byName["Rising Sun Campground"])
        #expect(risingSun.summary == "Rising Sun Campground is located just west of St. Mary and halfway along St. Mary Lake.")
        // Reservable first, then by name.
        let cache=CampgroundsCache(updated: .now, campgrounds: ["jotr": page.campgrounds.filter { $0.parkCode == "jotr" }])
        #expect(cache.list(try park("jotr")).map(\.name) == ["Cottonwood Campground", "White Tank Campground"])
        #expect(cache.list(try park("cave")).isEmpty)
    }
    @Test func reservationLinksStayOnTwoSites() {
        #expect(Campground.allowed("http://www.recreation.gov/camping/campgrounds/1?utm_source=x")?.absoluteString == "https://www.recreation.gov/camping/campgrounds/1")
        #expect(Campground.allowed("https://recreation.gov/x#top")?.absoluteString == "https://recreation.gov/x")
        #expect(Campground.allowed("https://www.nps.gov/jotr/planyourvisit/camping.htm")?.host() == "www.nps.gov")
        for bad in ["", "  ", "https://gc.synxis.com/rez.aspx", "https://www.recreation.gov.example.com/", "javascript:alert(1)", "ftp://www.nps.gov/x", "https://evil.com/?u=recreation.gov"] {
            #expect(Campground.allowed(bad) == nil, "\(bad)")
        }
        #expect(Campground.firstSentence("Open approx. 5 months a year. Water on site.") == "Open approx. 5 months a year.")
        #expect(Campground.firstSentence(String(repeating: "word ", count: 80)).hasSuffix("…"))
        #expect(Campground.firstSentence("<p>Shaded sites.</p>") == "Shaded sites.")
    }
    /// One request names all 62 NPS park codes, carries the key in a header, may wait for an
    /// unconstrained network, and is not repeated for seven days.
    @Test func campgroundsAreOneWeeklyRequestForEveryPark() async throws {
        let body=String(decoding: try fixture(), as: UTF8.self)
        let http=CampHTTP(["/api/v1/campgrounds": [body]])
        let clock=CampClock()
        let store=ParkStore(transport: http, persist: false, clock: { clock.now })
        let first=await store.campgrounds(for: parks, key: "TESTKEY", network: true, force: false)
        var calls=await http.calls
        #expect(calls.count == 1)
        let call=try #require(calls.first)
        #expect(call.headers["X-Api-Key"] == "TESTKEY" && !call.url.absoluteString.contains("TESTKEY") && !call.constrained)
        let codes=URLComponents(url: call.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "parkCode" }?.value?.split(separator: ",") ?? []
        #expect(Set(codes.map(String.init)) == Set(parks.map(\.apiCode)) && codes.count == 62)
        #expect(first?.list(try park("jotr")).count == 2 && first?.campgrounds["cave"]?.isEmpty == true)
        // Within the week: the cache, no request (even when forced within ten minutes).
        clock.now+=6*86_400
        _=await store.campgrounds(for: parks, key: "TESTKEY", network: true, force: false)
        calls=await http.calls
        #expect(calls.count == 1)
        clock.now+=86_400+60
        _=await store.campgrounds(for: parks, key: "TESTKEY", network: true, force: false)
        calls=await http.calls
        #expect(calls.count == 2)
        // Updates switched off: no request, the last set kept.
        let off=await store.campgrounds(for: parks, key: "TESTKEY", network: false, force: true)
        calls=await http.calls
        #expect(calls.count == 2 && off?.campgrounds["jotr"]?.count == 2)
    }
    /// Low Data Mode holding the request back is not a refusal: nothing cached, no backoff.
    @Test func lowDataModeWaitsForCampgrounds() async throws {
        let http=CampHTTP([:])
        var info: [String: Any]=[:]
        info[NSURLErrorNetworkUnavailableReasonKey]=URLError.NetworkUnavailableReason.constrained.rawValue
        await http.set(error: URLError(.notConnectedToInternet, userInfo: info))
        let backoff=HostBackoff(file: nil)
        let store=ParkStore(transport: http, persist: false, backoff: backoff)
        #expect(await store.campgrounds(for: parks, key: "TESTKEY", network: true, force: false) == nil)
        #expect(backoff.allows(ParkStore.host, now: .now))
    }

    // MARK: From home tonight

    /// The device location only when Near me is in use, else the chosen city, else the starting park.
    @Test func fromHomeStartsWhereThePersonDoes() throws {
        let chicago=try #require(StartingPlaces.named("Chicago, IL"))
        let jotr=try park("jotr")
        #expect(HomeSky.origin(location: (40, -105), place: chicago, park: jotr)?.source == .device)
        let city=try #require(HomeSky.origin(location: nil, place: chicago, park: jotr))
        #expect(city.source == .place && city.name == "Chicago" && city.timeZone.identifier == "America/Chicago" && city.park == nil)
        let start=try #require(HomeSky.origin(location: nil, place: nil, park: jotr))
        #expect(start.source == .park && start.park?.id == "jotr" && start.timeZone == jotr.timeZone)
        #expect(HomeSky.origin(location: nil, place: nil, park: nil) == nil)
    }
    /// The state table, checked against all 63 parks' own time zones (summer and winter offsets) and
    /// the split states' cities.
    @Test func homeTimeZonesFollowTheMap() throws {
        func offsets(_ zone: TimeZone) throws -> [Int] { [zone.secondsFromGMT(for: try Self.date("2026-01-15")), zone.secondsFromGMT(for: try Self.date("2026-07-15"))] }
        for park in parks {
            let zone=HomeSky.timeZone(state: String(park.state.prefix(2)), latitude: park.latitude, longitude: park.longitude)
            #expect(try offsets(zone) == offsets(park.timeZone), "\(park.id)")
        }
        let expected: [String: String]=["El Paso, TX": "America/Denver", "Pensacola, FL": "America/Chicago", "Tallahassee, FL": "America/New_York",
            "Boise, ID": "America/Boise", "Coeur d'Alene, ID": "America/Los_Angeles", "Evansville, IN": "America/Chicago", "Gary, IN": "America/Chicago",
            "Louisville, KY": "America/Kentucky/Louisville", "Bowling Green, KY": "America/Chicago", "Nashville, TN": "America/Chicago",
            "Knoxville, TN": "America/New_York", "Chattanooga, TN": "America/New_York", "Rapid City, SD": "America/Denver", "Sioux Falls, SD": "America/Chicago",
            "Phoenix, AZ": "America/Phoenix", "Honolulu, HI": "Pacific/Honolulu", "Anchorage, AK": "America/Anchorage", "Detroit, MI": "America/Detroit"]
        for (name, zone) in expected {
            let place=try #require(StartingPlaces.named(name), "\(name)")
            #expect(HomeSky.timeZone(state: place.state, latitude: place.latitude, longitude: place.longitude).identifier == zone, "\(name)")
        }
        #expect(StartingPlaces.all.allSatisfy { HomeSky.timeZone(state: $0.state, latitude: $0.latitude, longitude: $0.longitude) != .gmt })
    }
    /// A city sky: the Moon, true darkness and planets, a shower on its peak night with rates for a
    /// suburban sky, and the Moon-free stretch inside the dark hours.
    @Test func fromHomeTonightInDenverOnGeminidNight() throws {
        let denver=try #require(StartingPlaces.named("Denver, CO"))
        let origin=try #require(HomeSky.origin(location: nil, place: denver, park: nil))
        let home=HomeSky(origin: origin, now: try Self.date("2026-12-13"))
        #expect(home.place.bortleEstimate == HomeSky.assumedBortle && home.place.timeZoneID == "America/Denver")
        #expect(home.hasDarkness && home.sky.darkHours>10 && home.sky.darkHours<13)
        #expect(home.shower?.title.contains("Geminid") == true)
        #expect(home.shower?.detail.contains("suburban sky") == true && home.shower?.detail.contains("park") == false)
        // Tonight's Moon times stop at sunrise: a rise late the next morning is not tonight's news.
        if let sunrise=home.sky.sunrise, let rise=home.sky.moonrise, rise>sunrise { #expect(!home.moonTimes.contains("Rises")) }
        #expect(home.moonPhase.contains("lit") && !home.moonTimes.isEmpty)
        #expect(!home.darkness.contains("No true darkness"))
        if let free=home.moonFree, let start=home.sky.darkStart, let end=home.sky.darkEnd { #expect(free.start>=start && free.end<=end) }
        #expect(home.summary.hasPrefix("Moon: ") && home.summary.contains("True darkness"))
        // The park version of the same sky uses the park's own Bortle estimate.
        let jotr=try #require(HomeSky.origin(location: nil, place: nil, park: try park("jotr")))
        #expect(HomeSky(origin: jotr, now: try Self.date("2026-12-13")).place.bortleEstimate == (try park("jotr")).bortleEstimate)
    }
    /// Polar summer and winter, and the tropics on both sides of the equator: explicit words, never NaN.
    @Test func fromHomeAtTheEdges() throws {
        func home(_ lat: Double, _ lon: Double, _ zone: String, _ iso: String) throws -> HomeSky {
            let origin=HomeSky.Origin(name: "Here", state: "", latitude: lat, longitude: lon, timeZone: try #require(TimeZone(identifier: zone)), source: .device)
            return HomeSky(origin: origin, now: try Self.date(iso))
        }
        let june=try home(71.29, -156.79, "America/Anchorage", "2026-06-21")
        #expect(!june.hasDarkness && june.darkness == SkyConditions.noDarknessMessage(tonight: true) && june.moonlightLine == nil && june.moonFree == nil)
        #expect(june.summary.contains(SkyConditions.noDarknessMessage(tonight: true)))
        let december=try home(71.29, -156.79, "America/Anchorage", "2026-12-21")
        #expect(december.sky.darkHours.isFinite && !december.darkness.isEmpty && !december.summary.contains("nan"))
        for (lat, lon, zone) in [(21.31, -157.86, "Pacific/Honolulu"), (-14.28, -170.70, "Pacific/Pago_Pago")] {
            for iso in ["2026-03-20", "2026-06-21", "2026-12-21"] {
                let tropic=try home(lat, lon, zone, iso)
                #expect(tropic.hasDarkness && tropic.sky.darkHours>7.5 && tropic.sky.darkHours<12, "\(lat) \(iso)")
                #expect(tropic.place.hemisphere == (lat<0 ? "south" : "north"))
            }
        }
    }
    /// Nothing about From home tonight leaves the device: a full refresh (clouds, detail, alerts,
    /// campgrounds) never carries the city's or the device's coordinates.
    @MainActor @Test func fromHomeSendsNothing() async throws {
        let place=try #require(StartingPlaces.named("Chicago, IL"))
        let origin=try #require(HomeSky.origin(location: (41.8781, -87.6298), place: place, park: nil))
        _=HomeSky(origin: origin, now: .now)
        let http=CampHTTP([:])
        let model=PlanModel(weather: WeatherService(transport: http, persist: false), parkStore: ParkStore(transport: http, persist: false),
                            detail: ForecastDetailService(transport: http, persist: false))
        await model.refresh(model.parks, force: true, programs: true)
        await model.refreshCampgrounds(force: true)
        let recorded=await http.calls
        let urls=recorded.map { $0.url.absoluteString }
        #expect(!urls.isEmpty)
        for coordinate in ["41.8781", "-87.6298", String(place.latitude), String(place.longitude)] {
            #expect(!urls.contains { $0.contains(coordinate) }, "\(coordinate)")
        }
    }
}
/// Records each request (URL, headers, whether it may use a constrained network) and answers by
/// path; an error, when set, answers every request.
private actor CampHTTP: HTTPTransport {
    struct Call: Sendable { let url: URL; let headers: [String: String]; let constrained: Bool }
    private(set) var calls: [Call]=[]
    private let bodies: [String: [String]]
    private var error: URLError?
    init(_ bodies: [String: [String]]) { self.bodies=bodies }
    func set(error: URLError?) { self.error=error }
    func get(_ url: URL) async throws -> Data { try await get(url, headers: [:], constrained: true) }
    func get(_ url: URL, headers: [String: String], constrained: Bool) async throws -> Data {
        calls.append(Call(url: url, headers: headers, constrained: constrained))
        if let error { throw error }
        guard let body=bodies[url.path]?.first else { throw URLError(.badServerResponse) }
        return Data(body.utf8)
    }
}
/// A settable clock for freshness tests.
private final class CampClock: @unchecked Sendable {
    var now=Date(timeIntervalSince1970: 1_790_000_000)
}
