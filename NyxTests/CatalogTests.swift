import Foundation
import Testing
@testable import Nyx

/// The world catalogue: every place decodes with a unique id, resolves by its `wd:` id, is
/// found by its 1° index exactly as by brute force and by a folded search, and is forecast only by
/// whole 10° tiles, never alone and never with the device's position.
struct CatalogTests {
    private static let kruger="wd:Q24451"
    private static let torres="wd:Q901646"
    private static let pitcairn="wd:Q35672"
    private static func catalog() throws -> [Park] { try CatalogData.load() }
    /// One hourly cloud series as Open-Meteo returns it, for `count` coordinates.
    private static func response(_ count: Int) -> String {
        let one="{\"hourly\":{\"time\":[1790000000,1790003600,1790007200],\"cloud_cover\":[10,20,null]}}"
        return count == 1 ? one : "["+Array(repeating: one, count: count).joined(separator: ",")+"]"
    }
    @MainActor private static func model(_ http: StubHTTP = StubHTTP([:])) -> PlanModel {
        PlanModel(weather: WeatherService(transport: http, persist: false), parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                  detail: ForecastDetailService(transport: StubHTTP([:]), persist: false))
    }
    private static func values(_ url: URL, _ name: String) -> [String] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value ?? "").split(separator: ",").map(String.init)
    }

    // MARK: The data

    @Test func everyPlaceDecodesWithAUniqueID() throws {
        let catalog=try Self.catalog(), parks=try ParkData.load()
        #expect(catalog.count == 3_359 && parks.count == 63)
        let ids=(catalog+parks).map(\.id)
        #expect(Set(ids).count == 3_422)
        for place in catalog {
            #expect(place.isCatalogPlace && !place.curated && place.nps == nil && place.viewingSpots.isEmpty, "\(place.id)")
            #expect(PlaceIDText.validated(place.id) == place.id, "\(place.id)")
            #expect((-90...90).contains(place.latitude) && (-180...180).contains(place.longitude), "\(place.id)")
            #expect(TimeZone(identifier: place.timeZoneID) != nil, "\(place.id)")
            #expect((1...9).contains(place.bortleEstimate) && place.countryCode.count == 2, "\(place.id)")
            #expect(place.sourceURL.hasPrefix("https://www.wikidata.org/wiki/Q"), "\(place.id)")
        }
        #expect(parks.allSatisfy { !$0.isCatalogPlace && $0.curated && $0.website == nil })
    }
    /// The catalogue build's rules: one record per place, a
    /// point of its own, an English name in the Latin script, and the corrections it lists.
    @Test func everyPlaceIsOnePlaceAtItsOwnPoint() throws {
        let catalog=try Self.catalog()
        var points=Set<String>()
        for place in catalog {
            #expect(points.insert("\(place.latitude),\(place.longitude)").inserted, "\(place.id) shares its point")
            let name=place.name
            #expect(name == name.trimmingCharacters(in: .whitespaces) && !name.contains("  ") && !name.contains("„") && !name.contains("\""), "\(place.id)")
            #expect(name.first?.isLowercase == false && !name.hasPrefix("Unnamed") && name != "National Park", "\(place.id)")
            #expect(!name.contains("Nationalpark") && !name.contains(" project"), "\(place.id)")
            #expect(name.unicodeScalars.allSatisfy { !(0x0400...0x04FF).contains($0.value) && !(0x3040...0x9FFF).contains($0.value) }, "\(place.id)")
        }
        let ids=Set(catalog.map(\.id))
        // Merged into the place they are part of, or not a place: Greater Kruger (Kruger), a proposal,
        // a synagogue, a placeholder, an umbrella over Tsavo East and West.
        for gone in ["wd:Q5600596", "wd:Q16945675", "wd:Q2916829", "wd:Q105805604", "wd:Q110541232"] { #expect(!ids.contains(gone), "\(gone)") }
        #expect(ids.isSuperset(of: [Self.kruger, "wd:Q1368818", "wd:Q1602738"]))
        func place(_ id: String) throws -> Park { try #require(catalog.first { $0.id == id }) }
        // NamibRand: its region and a point that is not a whole degree; Guanacaste off Rincón de la Vieja's point.
        let namibRand=try place("wd:Q1802857")
        #expect(namibRand.region == "Hardap Region" && namibRand.latitude != -25 && namibRand.longitude != 16)
        #expect(try place("wd:Q1587862").latitude != place("wd:Q1431228").latitude)
        // Broken Hill's clock is the Unincorporated Far West's only.
        #expect(try place("wd:Q1670728").timeZoneID == "Australia/Sydney" && place("wd:Q972962").timeZoneID == "Australia/Broken_Hill")
        // An Urban Night Sky Place is named as one.
        #expect(try place("wd:Q17108098").kind == .urbanNightSky)
        #expect(try place("wd:Q1703071").countryCode == "NL")
    }
    /// A kind a later build adds reads as `custom` in this one, never as an unreadable place.
    @Test func anUnknownKindDecodesAsCustom() throws {
        let place=try #require(try Self.catalog().first { $0.kind == .urbanNightSky })
        var object=try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(place)) as? [String: Any])
        #expect(object["kind"] as? String == "urbanNightSky")
        object["kind"]="aKindFromTheFuture"
        let later=try JSONDecoder().decode(Park.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(later.kind == .custom && later.id == place.id)
    }
    /// A website is linked only over HTTPS; one offered only over plain HTTP is left out.
    @Test func websitesAreHTTPSOnly() throws {
        let catalog=try Self.catalog()
        let linked=catalog.compactMap(\.website)
        #expect(linked.count == 548)
        #expect(linked.allSatisfy { $0.scheme == "https" && $0.host() != nil })
        #expect(Place.website("http://dilijanpark.am/") == nil && Place.website("https://example.org/a") != nil && Place.website("not a url") == nil)
        // A catalogue place round-trips whole, website included, and still writes the legacy keys.
        let linkedPlace=try #require(catalog.first { $0.website != nil })
        let data=try JSONEncoder().encode(linkedPlace)
        #expect(try JSONDecoder().decode(Park.self, from: data) == linkedPlace)
        let object=try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys=Set((object ?? [:]).keys)
        #expect(keys.isSuperset(of: ["state", "hemisphere", "region", "countryCode", "website"]))
    }

    // MARK: The planner

    @MainActor @Test func theCatalogueIsReadOffTheMainThreadAndResolves() async throws {
        let model=Self.model()
        await model.catalogReady()
        #expect(model.catalogIsReady && model.catalog.count == 3_359)
        #expect(model.park(Self.kruger)?.name == "Kruger National Park")
        #expect(model.park("wd:Q999999999999") == nil && model.park("jotr")?.curated == true)
        // The curated parks are never repeated in the catalogue.
        #expect(Set(model.catalog.map(\.id)).isDisjoint(with: model.parks.map(\.id)))
        // A night at a catalogue place is scored and kept like any park's.
        let place=try #require(model.park(Self.kruger))
        let night=model.night(place)
        #expect(night.park == place && (0...100).contains(night.score.value) && model.night(place).score.value == night.score.value)
    }
    @MainActor @Test func placesNearMatchesBruteForce() async throws {
        let model=Self.model()
        await model.catalogReady()
        let spot=Place(spotID: "pin:3f2a8c1e-5b7d-4e9a-8c6f-1d2e3f4a5b6c", name: "Spot", latitude: -24.2, longitude: 31.3, timeZoneID: "Africa/Johannesburg",
                       countryCode: "ZA", region: "Limpopo", grid: SkyGrid(bundle: .main, layers: []))
        model.setSpots(places: [spot])
        let everything=model.parks+model.catalog+model.spots
        var generator=CatalogRandom(seed: 2026)
        var points: [(Double, Double)]=[(-24.0, 31.5), (34.0, -116.2), (-17.8, 179.9), (-17.8, -179.9), (85.0, 0), (-89.5, 45), (0, 0), (51.5, -0.1), (64.8, -147.7)]
        for _ in 0..<12 { points.append((Double.random(in: -80...80, using: &generator), Double.random(in: -180...180, using: &generator))) }
        for (latitude, longitude) in points {
            for radius in [25_000.0, 300_000, 1_500_000, 6_000_000] {
                let found=model.places(near: latitude, longitude: longitude, radiusMeters: radius)
                let expected=Set(everything.filter { $0.distanceMeters(latitude: latitude, longitude: longitude) <= radius }.map(\.id))
                #expect(Set(found.map(\.id)) == expected, "\(latitude), \(longitude), \(radius)")
                #expect(found.count == expected.count)
                let distances=found.map { $0.distanceMeters(latitude: latitude, longitude: longitude) }
                #expect(zip(distances, distances.dropFirst()).allSatisfy { $0 <= $1 })
            }
        }
        #expect(model.places(near: -24.0, longitude: 31.5, radiusMeters: 50_000).contains { $0.id == spot.id })
        #expect(model.places(near: .nan, longitude: 0, radiusMeters: 1_000).isEmpty)
    }
    @MainActor @Test func searchFoldsAndPutsCuratedParksFirst() async throws {
        let model=Self.model()
        await model.catalogReady()
        #expect(model.searchPlaces("Kruger", limit: 5).first?.id == Self.kruger)
        #expect(model.searchPlaces("torres del paine", limit: 5).first?.id == Self.torres)
        // Diacritics and marks fold both ways.
        #expect(model.searchPlaces("Iguazu", limit: 5).contains { $0.name == "Iguazú National Park" })
        #expect(model.searchPlaces("galapagos", limit: 5).first?.name == "Galápagos National Park")
        #expect(model.searchPlaces("uluru kata tjuta", limit: 5).first?.name == "Uluṟu-Kata Tjuṯa National Park")
        #expect(model.searchPlaces("Pārk", limit: 20).map(\.id) == model.searchPlaces("park", limit: 20).map(\.id))
        // The same name in both: the curated park first.
        let glacier=model.searchPlaces("Glacier National Park", limit: 5)
        #expect(glacier.count >= 2 && glacier[0].id == "glac" && glacier[1].isCatalogPlace)
        // Curated aliases still work, and nothing is found for nothing.
        #expect(model.searchPlaces("Smokies", limit: 3).first?.id == "grsm")
        #expect(model.searchPlaces("   ", limit: 5).isEmpty && model.searchPlaces("Kruger", limit: 0).isEmpty)
        #expect(model.searchPlaces("park", limit: 7).count == 7)
    }
    /// The country is searched in the reader's language.
    @Test func searchReadsTheCountryName() throws {
        let catalog=PlaceCatalog(try Self.catalog(), locale: Locale(identifier: "en_US"))
        let chile=catalog.search(Park.folded("Chile")).map(\.0)
        #expect(chile.contains { $0.id == Self.torres } && chile.filter { $0.countryCode == "CL" }.count >= 10)
        let spanish=PlaceCatalog(try Self.catalog(), locale: Locale(identifier: "es_ES"))
        #expect(spanish.search(Park.folded("Sudáfrica")).contains { $0.0.id == Self.kruger })
    }

    // MARK: Forecasts by whole tiles

    @Test func tilesAreFixedAndCoverTheWorld() {
        #expect(CatalogForecast.Tile(latitude: -24.0, longitude: 31.5) == CatalogForecast.Tile(row: 6, column: 21))
        #expect(CatalogForecast.Tile(latitude: 90, longitude: 180) == CatalogForecast.Tile(row: 17, column: 0))
        #expect(CatalogForecast.Tile(latitude: -90, longitude: -180) == CatalogForecast.Tile(row: 0, column: 0))
        #expect(CatalogForecast.Tile(latitude: 0, longitude: -0.0001)?.corner == "0,-10")
        #expect(CatalogForecast.Tile(latitude: .nan, longitude: 0) == nil)
    }
    @Test func aDenseTileSplitsEvenlyAndDeterministically() {
        let places=(1...2_500).map { n in
            Place(id: "wd:Q\(n*7919 % 100_003)", nps: nil, name: "P\(n)", countryCode: "AU", region: "", kind: .nationalPark, curated: false,
                  latitude: -25, longitude: 135, timeZoneID: "Australia/Darwin", darkSkyDesignated: false, bortleEstimate: 2,
                  description: "", sourceURL: "", sourceNote: "", viewingSpots: [])
        }
        let parts=CatalogForecast.chunks(places)
        #expect(parts.map(\.count) == [834, 833, 833])
        #expect(Set(parts.joined().map(\.id)) == Set(places.map(\.id)))
        let numbers=parts.joined().map { CatalogForecast.itemNumber($0.id) }
        #expect(numbers == numbers.sorted())
        #expect(CatalogForecast.chunks(places.reversed()).map { $0.map(\.id) } == parts.map { $0.map(\.id) })
    }
    @Test func everyRequestIsAWholeRegion() throws {
        let catalog=try Self.catalog()
        let regions=CatalogForecast.Regions(catalog)
        // Every catalogue place is in exactly one request, and no request passes the cap.
        let all=regions.requests.joined().joined().map(\.id)
        #expect(all.count == catalog.count && Set(all).count == catalog.count)
        #expect(regions.requests.joined().allSatisfy { !$0.isEmpty && $0.count <= CatalogForecast.maxPointsPerRequest })
        // A dense tile is asked about on its own: every catalogue place in it, and nothing else.
        let kruger=try #require(catalog.first { $0.id == Self.kruger })
        let tile=try #require(CatalogForecast.Tile(kruger))
        let inTile=Set(catalog.filter { CatalogForecast.Tile($0) == tile }.map(\.id))
        #expect(inTile.count >= CatalogForecast.minimumPoints)
        let planned=regions.plan(wanted: [kruger])
        #expect(Set(planned.joined().map(\.id)) == inTile)
        #expect(regions.plan(wanted: [kruger]).map { $0.map(\.id) } == planned.map { $0.map(\.id) })
        // A lone island is never asked about alone: it goes with every other sparse tile's places.
        let pitcairn=try #require(catalog.first { $0.id == Self.pitcairn })
        let remote=regions.plan(wanted: [pitcairn]).joined().map(\.id)
        #expect(remote.contains(Self.pitcairn) && remote.count >= 100)
        #expect(regions.plan(wanted: [catalog.first { $0.id == Self.torres }].compactMap { $0 }).joined().map(\.id) == remote)
        // Curated parks and saved spots are never in a catalogue request; the budget holds.
        let parks=try ParkData.load()
        #expect(regions.plan(wanted: parks).isEmpty)
        let spread=regions.plan(wanted: catalog)
        #expect(spread.joined().count <= CatalogForecast.maxPointsPerRefresh && !spread.isEmpty)
    }
    @MainActor @Test func theTileRequestCarriesOnlyThatTile() async throws {
        let catalog=try Self.catalog()
        let regions=CatalogForecast.Regions(catalog)
        let kruger=try #require(catalog.first { $0.id == Self.kruger })
        let request=try #require(regions.plan(wanted: [kruger]).first)
        let http=StubHTTP(["/v1/forecast": Self.response(request.count)])
        let service=WeatherService(transport: http, persist: false)
        let result=await service.catalogForecasts([request], network: true, force: true)
        let urls=await http.urls
        #expect(urls.count == 1)
        let url=try #require(urls.first)
        #expect(url.scheme == "https" && url.host == "api.open-meteo.com" && url.path == "/v1/forecast" && SafeHTTP.hosts.contains(url.host ?? ""))
        #expect(url == CatalogForecast.url(for: request))
        #expect(Self.values(url, "latitude") == request.map { String($0.latitude) } && Self.values(url, "longitude") == request.map { String($0.longitude) })
        #expect(Self.values(url, "hourly") == ["cloud_cover"])
        for exact in ["wd", "Q24451", "Kruger", "Limpopo", "Johannesburg"] { #expect(!url.absoluteString.contains(exact)) }
        #expect(Set(result.keys) == Set(request.map(\.id)) && result[Self.kruger]?.clouds == [10, 20, nil])
        // Fresh now: asked again without force, nothing goes out; offline, the kept forecasts still come back.
        _=await service.catalogForecasts([request], network: true)
        #expect(await service.catalogForecasts([request], network: false).count == request.count)
        #expect(await http.urls.count == 1)
    }
    /// The planner asks for a catalogue place by its tile, apart from the parks' request, which stays as it was.
    @MainActor @Test func thePlannerAsksForWholeTiles() async throws {
        let catalog=try Self.catalog()
        let kruger=try #require(catalog.first { $0.id == Self.kruger })
        let request=try #require(CatalogForecast.Regions(catalog).plan(wanted: [kruger]).first)
        let http=StubHTTP(["/v1/forecast": Self.response(request.count)])
        let model=Self.model(http)
        await model.catalogReady()
        await model.refreshForecasts(for: [kruger], force: true)
        let urls=await http.urls
        let tiled=urls.filter { Self.values($0, "latitude").count == request.count }
        #expect(tiled.count == (model.weatherEnabled ? 1 : 0))
        if let url=tiled.first {
            #expect(url == CatalogForecast.url(for: request))
            #expect(model.forecasts[Self.kruger] != nil)
            // No curated park's point is in it.
            let curated=Set(model.parks.map { String($0.forecastPoint.latitude) })
            #expect(curated.isDisjoint(with: Self.values(url, "latitude")))
        }
        // The parks' request names no catalogue place.
        let krugerLatitude=String(kruger.latitude)
        for url in urls where url != tiled.first { #expect(!Self.values(url, "latitude").contains(krugerLatitude)) }
    }

    // MARK: Following a catalogue place

    /// A followed catalogue place reaches the widgets' snapshot and the watch whole: neither bundles the catalogue.
    @Test func aFollowedCatalogPlaceTravelsWhole() throws {
        let catalog=try Self.catalog()
        let kruger=try #require(catalog.first { $0.id == Self.kruger }), torres=try #require(catalog.first { $0.id == Self.torres })
        let context=WatchContext.make(savedParkIDs: ["deva", Self.kruger], homeParkID: "jotr", nightVision: false, forecasts: [:], places: [kruger, torres])
        #expect(context.places == [kruger])
        let sent=try #require(context.data)
        let received=try #require(WatchContext(data: sent))
        #expect(received.places == [kruger] && received == context)
        // The starting place travels too when it is a catalogue place.
        let home=WatchContext.make(savedParkIDs: [], homeParkID: Self.torres, nightVision: false, forecasts: [:], places: [torres])
        #expect(home.places == [torres])
        // The widgets' snapshot holds it whole, website and all.
        let snapshot=SavedSkySnapshot(parks: [kruger], forecasts: [:])
        let read=try JSONDecoder().decode(SavedSkySnapshot.self, from: try JSONEncoder().encode(snapshot))
        #expect(read.parks == [kruger] && read.nights(from: Date(timeIntervalSince1970: 1_790_000_000), count: 2).count == 2)
    }
    /// The trip planner weighs only places in range, and never more than it can plan quickly.
    @MainActor @Test func tripCandidatesAreLimited() async throws {
        let model=Self.model()
        await model.catalogReady()
        let near=model.tripCandidates(latitude: -24.0, longitude: 31.5, radiusMeters: 300_000)
        #expect(near.contains { $0.id == Self.kruger } && near.allSatisfy { $0.distanceMeters(latitude: -24.0, longitude: 31.5) <= 300_000 })
        #expect(near.map(\.id) == near.map(\.id).sorted())
        let wide=model.tripCandidates(latitude: -28, longitude: 150, radiusMeters: 2_000_000)
        #expect(wide.count == TripPlanner.maxCandidates)
        let inRange=model.places(near: -28, longitude: 150, radiusMeters: 2_000_000)
        let darkest=inRange.map(\.bortleEstimate).sorted().prefix(TripPlanner.maxCandidates).last ?? 0
        #expect(wide.allSatisfy { $0.bortleEstimate <= darkest })
    }
}

/// A small deterministic generator (SplitMix64), so the brute-force comparison covers the same points every run.
private struct CatalogRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state=seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z=state
        z=(z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z=(z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
