import Foundation
import SwiftData
import Testing
@testable import Nyx

/// Saved spots: the store's new version, a spot as a place, and the one request that carries
/// a place the person chose, with its coordinates rounded to 0.1°, on its own, behind its own switch.
struct SavedSpotTests {
    private static let jotr="pin:3f2a8c1e-5b7d-4e9a-8c6f-1d2e3f4a5b6c"
    private static let other="pin:9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d"
    private static func spot(_ id: String=jotr, latitude: Double=34.0123, longitude: Double = -116.1789, note: String?=nil) -> SavedSpot {
        SavedSpot(id: id, name: "Pullout off Pinto Basin Road", latitude: latitude, longitude: longitude, timeZoneID: "America/Los_Angeles",
                  countryCode: "US", region: "CA", createdAt: Date(timeIntervalSince1970: 1_790_000_000), note: note)
    }
    private static func place(_ id: String, _ latitude: Double, _ longitude: Double) -> Park {
        Place(spotID: id, name: "Spot", latitude: latitude, longitude: longitude, timeZoneID: "America/Denver", countryCode: "US", region: "CO",
              grid: SkyGrid(bundle: .main, layers: []))
    }
    /// One hourly cloud series as Open-Meteo returns it, for `count` coordinates.
    private static func response(_ count: Int) -> String {
        let one="{\"hourly\":{\"time\":[1790000000,1790003600,1790007200],\"cloud_cover\":[10,20,null]}}"
        return count == 1 ? one : "["+Array(repeating: one, count: count).joined(separator: ",")+"]"
    }
    private static func suite() throws -> (name: String, defaults: UserDefaults) {
        let name="nyx-spots-\(UUID().uuidString)"
        return (name, try #require(UserDefaults(suiteName: name)))
    }

    // MARK: The store

    /// A store written by the previous version (V1), with journal entries, photos and saved parks,
    /// opens as the current version with everything in place and saved spots ready to use.
    @MainActor @Test func versionOneStoreMigratesKeepingTheJournal() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-v1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url=folder.appendingPathComponent("default.store")
        let photos=[Data([1,2,3]), Data(repeating: 9, count: 50_000)]
        var id=UUID()
        do {
            let schema=Schema(versionedSchema: NyxSchemaV1.self)
            let old=try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context=ModelContext(old)
            let entry=NyxSchemaV1.JournalEntry(date: Date(timeIntervalSince1970: 1_790_000_000), parkID: "jotr", observedBortle: 2, notes: "The core over the ridge.", photos: photos)
            id=entry.id
            context.insert(entry)
            context.insert(NyxSchemaV1.JournalEntry(date: Date(timeIntervalSince1970: 1_790_100_000), parkID: "deva", notes: "Wind."))
            context.insert(NyxSchemaV1.SavedPark(parkID: "deva")); context.insert(NyxSchemaV1.SavedPark(parkID: "grba"))
            try context.save()
            entry.orderedPhotos.first?.altText="Joshua trees under the Milky Way."
            try context.save()
        }
        let opened=JournalStore.open(inMemory: false, url: url)
        #expect(!opened.failed)
        let container=try #require(opened.container)
        let context=ModelContext(container)
        let entries=try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 2)
        let kept=try #require(entries.first { $0.id == id })
        #expect(kept.photos == photos && kept.notes == "The core over the ridge." && kept.observedBortle == 2)
        #expect(kept.orderedPhotos.first?.altText == "Joshua trees under the Milky Way.")
        #expect(Set(try context.fetch(FetchDescriptor<SavedPark>()).map(\.parkID)) == ["deva", "grba"])
        #expect(try context.fetch(FetchDescriptor<SavedSpot>()).isEmpty)
        // The new model works in the migrated store, and survives reopening it.
        try SavedSpots.save(Self.spot(), in: context)
        let reopened=try #require(JournalStore.open(inMemory: false, url: url).container)
        let again=ModelContext(reopened)
        #expect(try again.fetch(FetchDescriptor<SavedSpot>()).map(\.id) == [Self.jotr])
        #expect(Set(try again.fetch(FetchDescriptor<SavedPark>()).map(\.parkID)) == ["deva", "grba", Self.jotr])
        #expect(try again.fetch(FetchDescriptor<JournalEntry>()).count == 2)
    }
    /// Saving follows the spot; unsaving (the bookmark) keeps the spot; deleting removes both.
    @MainActor @Test func savingFollowsAndDeletingRemovesBoth() throws {
        let schema=Schema(versionedSchema: NyxSchemaV2.self)
        let context=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        try SavedSpots.save(Self.spot(), in: context)
        try SavedSpots.follow(Self.jotr, in: context)
        #expect(try context.fetch(FetchDescriptor<SavedPark>()).map(\.parkID) == [Self.jotr])
        for row in try context.fetch(FetchDescriptor<SavedPark>()) { context.delete(row) }
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SavedSpot>()).count == 1)
        try SavedSpots.follow(Self.jotr, in: context)
        try SavedSpots.delete(Self.jotr, in: context)
        #expect(try context.fetch(FetchDescriptor<SavedSpot>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SavedPark>()).isEmpty)
    }

    // MARK: A spot as a place

    @Test func aSpotIsAPlaceOfItsOwn() throws {
        let place=Place(spot: Self.spot(note: "Gate locks at 10."), grid: SkyGrid(bundle: .main, layers: []))
        #expect(place.id == Self.jotr && place.isSavedSpot && place.name == "Pullout off Pinto Basin Road")
        #expect(place.kind == .custom && !place.curated && place.nps == nil && !place.darkSkyDesignated)
        #expect(place.countryCode == "US" && place.region == "CA" && place.timeZoneID == "America/Los_Angeles")
        #expect(place.latitude == 34.0123 && place.longitude == -116.1789)
        #expect(place.viewingSpots.isEmpty && place.access == nil && place.aboveInversion == nil)
        #expect(place.description == "Gate locks at 10." && place.sourceURL.isEmpty)
        // No light map: a suburban sky is assumed, and said.
        #expect(place.bortleEstimate == HomeSky.assumedBortle && place.sourceNote == Place.assumedSkyNote)
        // Its forecast is asked for at its own point, not a viewing spot.
        #expect(place.forecastPoint.latitude == 34.0123 && place.forecastPoint.longitude == -116.1789)
        // It travels in the widgets' snapshot and reads back the same.
        let data=try JSONEncoder().encode(SavedSkySnapshot(parks: [place], forecasts: [:]))
        #expect(try JSONDecoder().decode(SavedSkySnapshot.self, from: data).parks == [place])
    }
    /// With the sky grid bundled, a spot's Bortle class is the grid's, "estimated from satellite data".
    @Test func aSpotReadsTheSkyGrid() throws {
        let grid=SkyGrid.shared
        guard let magnitude=grid.skyBrightness(latitude: 34.0123, longitude: -116.1789) else { return }
        let place=Place(spot: Self.spot(), grid: grid)
        #expect(place.bortleEstimate == SkyGrid.bortle(fromMagnitude: magnitude))
        #expect(place.sourceNote == Place.satelliteSkyNote)
    }
    /// Far from every town the zone follows the Sun's meridian, in IANA's inverted sign.
    @Test func solarZones() throws {
        #expect(SavedSpots.solarZone(longitude: -120) == "Etc/GMT+8")
        #expect(SavedSpots.solarZone(longitude: 135) == "Etc/GMT-9")
        #expect(SavedSpots.solarZone(longitude: 3) == "Etc/GMT")
        #expect(SavedSpots.solarZone(longitude: 179.9) == "Etc/GMT-12")
        #expect(SavedSpots.solarZone(longitude: .nan) == "Etc/GMT")
        let pacific=try #require(TimeZone(identifier: SavedSpots.solarZone(longitude: -120)))
        #expect(pacific.secondsFromGMT() == -8*3600)
    }
    /// A new spot takes its zone, country and region from the nearest bundled place, on this device;
    /// in the open ocean, the meridian's zone and no country.
    @Test func aNewSpotIsPlacedOnThisDevice() throws {
        let spot=SavedSpots.make(name: "Pinto Basin", latitude: 33.92, longitude: -115.88, now: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(spot.id.hasPrefix("pin:") && PlaceIDText.validated(spot.id) == spot.id)
        #expect(spot.latitude == 33.92 && spot.longitude == -115.88 && spot.createdAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(spot.timeZoneID == "America/Los_Angeles" && spot.countryCode == "US" && spot.region == "CA")
        let sea=SavedSpots.locality(latitude: 0, longitude: -140)
        #expect(sea.timeZoneID == "Etc/GMT+9" && sea.countryCode.isEmpty && sea.region.isEmpty)
    }
    /// The planner finds a spot by its id, scores it like a park and keeps the catalogue as it was.
    @MainActor @Test func thePlannerResolvesSpots() throws {
        let model=PlanModel(weather: WeatherService(transport: StubHTTP([:]), persist: false), parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                            detail: ForecastDetailService(transport: StubHTTP([:]), persist: false))
        let catalogue=model.parks
        let spot=Self.place(Self.jotr, 38.9, -106.9)
        model.setSpots(places: [spot])
        #expect(model.parks == catalogue && model.places.count == catalogue.count+1)
        #expect(model.park(Self.jotr) == spot && model.park(Self.other) == nil)
        #expect(model.park("jotr")?.id == "jotr")
        let night=model.night(spot)
        #expect(night.park == spot && (0...100).contains(night.score.value) && !night.score.hasForecast)
        model.setSpots(places: [])
        #expect(model.park(Self.jotr) == nil && model.places.count == catalogue.count)
    }

    /// The watch's bundled parks cannot hold a saved spot, so the hand-over carries it whole, only
    /// when it is saved, and an older context without it still reads.
    @Test func theWatchReceivesSavedSpotsWhole() throws {
        let spot=Self.place(Self.jotr, 38.9, -106.9), unsaved=Self.place(Self.other, 40, -105)
        let context=WatchContext.make(savedParkIDs: ["deva", Self.jotr], homeParkID: "jotr", nightVision: false, forecasts: [:], places: [spot, unsaved])
        #expect(context.places == [spot])
        let data=try #require(context.data)
        let received=try #require(WatchContext(data: data))
        #expect(received.places == [spot] && received == context)
        let old=try #require(WatchContext(data: Data("{\"version\":1,\"sent\":0,\"homeParkID\":\"jotr\",\"savedParkIDs\":[\"jotr\"]}".utf8)))
        #expect(old.places.isEmpty && old.savedParkIDs == ["jotr"])
    }

    // MARK: The request

    /// Every point is on the 0.1° grid, exactly, written from whole tenths.
    @Test func roundingIsExact() throws {
        func point(_ lat: Double, _ lon: Double) throws -> SpotForecast.Point { try #require(SpotForecast.Point(latitude: lat, longitude: lon)) }
        let a=try point(34.0123, -116.1789)
        #expect(a.latitudeTenths == 340 && a.longitudeTenths == -1162)
        #expect(SpotForecast.Point.text(a.latitudeTenths) == "34.0" && SpotForecast.Point.text(a.longitudeTenths) == "-116.2")
        #expect(a.latitude == 34.0 && a.longitude == -116.2)
        // Halves (exact in binary) round away from zero.
        #expect(try point(0.25, -116.25).latitudeTenths == 3 && (try point(0.25, -116.25)).longitudeTenths == -1163)
        // Near zero, the sign goes with the value: no "-0.0".
        #expect(SpotForecast.Point.text(try point(-0.04, 0.04).latitudeTenths) == "0.0")
        #expect(SpotForecast.Point.text(try point(-0.06, 0).latitudeTenths) == "-0.1")
        // Latitudes clamp; longitudes wrap into −180…180°.
        #expect(try point(95, 0).latitudeTenths == 900 && (try point(-91, 0)).latitudeTenths == -900)
        #expect(try point(0, 179.96).longitudeTenths == 1800)
        #expect(try point(0, 180.06).longitudeTenths == -1799)
        #expect(try point(0, -180.06).longitudeTenths == 1799)
        #expect(try point(0, 359.9).longitudeTenths == -1)
        #expect(SpotForecast.Point(latitude: .nan, longitude: 0) == nil)
        // Over a sweep of coordinates, the text is always one decimal and within 0.05° of the point.
        for i in 0..<2_000 {
            let lat = -89.9+Double(i)*0.0899, lon = -179.9+Double(i)*0.1799
            let p=try point(lat, lon)
            let text=SpotForecast.Point.text(p.latitudeTenths)
            #expect(text.split(separator: ".").last?.count == 1)
            #expect(abs((Double(text) ?? .nan)-lat) <= 0.0500001)
        }
    }
    /// Spots that round to the same point are asked about once; each still gets the forecast.
    @Test func samePointIsAskedOnce() {
        let spots=[Self.place(Self.jotr, 34.01, -116.01), Self.place(Self.other, 34.04, -116.04),
                   Self.place("pin:00000000-0000-4000-8000-000000000003", 36.5, -118.6)]
        let grid=SpotForecast.points(spots)
        #expect(grid.points.count == 2)
        #expect(grid.byID[Self.jotr] == grid.byID[Self.other] && grid.byID.count == 3)
    }
    /// The spots' request: the forecast host only, the rounded points only, clouds only, and
    /// nothing that names the spot. The parks' request is never mixed with it.
    @MainActor @Test func theRequestCarriesOnlyRoundedPoints() async throws {
        let (name, defaults)=try Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let spots=[Self.place(Self.jotr, 34.0123, -116.1789), Self.place(Self.other, 34.0234, -116.1555),
                   Self.place("pin:00000000-0000-4000-8000-000000000003", 36.4567, -118.6123)]
        let http=StubHTTP(["/v1/forecast": Self.response(2)])
        let service=WeatherService(transport: http, persist: false, suite: name)
        let result=await service.spotForecasts(for: spots, network: true, force: true)
        let urls=await http.urls
        #expect(urls.count == 1)
        let url=try #require(urls.first)
        #expect(url.scheme == "https" && url.host == "api.open-meteo.com" && url.path == "/v1/forecast")
        #expect(SafeHTTP.refusal(url, defaults: defaults) == nil)
        #expect(url.absoluteString == "https://api.open-meteo.com/v1/forecast?latitude=34.0,36.5&longitude=-116.2,-118.6&hourly=cloud_cover&forecast_days=15&past_days=1&timeformat=unixtime&timezone=GMT")
        for exact in ["34.0123", "116.1789", "34.0234", "116.1555", "36.4567", "118.6123", "pin", "Spot", "Denver"] { #expect(!url.absoluteString.contains(exact)) }
        // Every spot has its forecast, including the two that shared a point.
        #expect(Set(result.keys) == Set(spots.map(\.id)))
        #expect(result[Self.jotr]?.clouds == [10, 20, nil])
        // Fresh now: asked again without force, nothing goes out.
        _=await service.spotForecasts(for: spots, network: true)
        #expect(await http.urls.count == 1)
        // The parks' own request names no spot.
        _=await service.forecasts(for: try ParkData.load(), network: true, force: true)
        for park in await http.urls.dropFirst() { #expect(!park.absoluteString.contains("34.0,36.5") && !park.absoluteString.contains("-116.2,-118.6")) }
    }
    /// With the spots' switch off, or forecasts off altogether, no request is made; what was cached stays.
    @MainActor @Test func switchOffMeansNoSpotRequest() async throws {
        let (name, defaults)=try Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(SpotForecast.isOn(defaults))
        defaults.set(false, forKey: SpotForecast.key)
        #expect(!SpotForecast.isOn(defaults))
        let spots=[Self.place(Self.jotr, 34.0123, -116.1789)]
        let http=StubHTTP(["/v1/forecast": Self.response(1)])
        let off=WeatherService(transport: http, persist: false, suite: name)
        #expect(await off.spotForecasts(for: spots, network: true, force: true).isEmpty)
        #expect(await http.urls.isEmpty)
        defaults.set(true, forKey: SpotForecast.key)
        let noNetwork=WeatherService(transport: http, persist: false, suite: name)
        #expect(await noNetwork.spotForecasts(for: spots, network: false, force: true).isEmpty)
        #expect(await http.urls.isEmpty)
        // On again: one request; then off, the cached forecast is still returned, with no new request.
        #expect(await noNetwork.spotForecasts(for: spots, network: true, force: true)[Self.jotr] != nil)
        defaults.set(false, forKey: SpotForecast.key)
        #expect(await noNetwork.spotForecasts(for: spots, network: true, force: true)[Self.jotr] != nil)
        #expect(await http.urls.count == 1)
    }
    /// The planner asks for spots in their own request, after the parks', and only when both switches allow it.
    @MainActor @Test func thePlannerAsksForSpotsSeparately() async throws {
        let http=StubHTTP([:])
        let model=PlanModel(weather: WeatherService(transport: http, persist: false), parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                            detail: ForecastDetailService(transport: StubHTTP([:]), persist: false))
        model.setSpots(places: [Self.place(Self.jotr, 34.0123, -116.1789)])
        await model.refreshForecasts(watching: model.places, force: true)
        let urls=await http.urls
        let ofSpots=urls.filter { $0.absoluteString.contains("latitude=34.0&") }
        #expect(ofSpots.count == (model.weatherEnabled && model.spotForecastsEnabled ? 1 : 0))
        // No request mixes a spot with a park.
        for url in urls where !ofSpots.contains(url) { #expect(!url.absoluteString.contains("34.0,") && !url.absoluteString.contains(",34.0&")) }
        for url in ofSpots { #expect(url.absoluteString.contains("longitude=-116.2&")) }
    }

    // MARK: The journal archive

    /// Spots travel with the journal (format 2): an entry written at a spot arrives with its place,
    /// every spot arrives unfollowed (an archive never sets up reminders on its own), and importing
    /// twice adds nothing.
    @MainActor @Test func archiveCarriesSpots() throws {
        let schema=Schema(versionedSchema: NyxSchemaV2.self)
        let phone=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        try SavedSpots.save(Self.spot(note: "North pullout."), in: phone)
        phone.insert(Self.spot(Self.other, latitude: 47.5, longitude: 8.25))
        phone.insert(JournalEntry(date: Date(timeIntervalSince1970: 1_790_899_200), parkID: Self.jotr, observedBortle: 3, notes: "Zodiacal light."))
        phone.insert(JournalEntry(date: Date(timeIntervalSince1970: 1_790_999_200), parkID: "deva", notes: "Windy."))
        try phone.save()
        let archive=JournalArchive.make(from: try phone.fetch(FetchDescriptor<JournalEntry>()))
        #expect(archive.manifest.format == 2)
        let spots=try #require(archive.manifest.spots)
        #expect(spots.map(\.id) == [Self.jotr, Self.other])
        #expect(spots.map(\.saved) == [true, false] && spots.first?.note == "North pullout.")
        let reread=try JournalArchive(wrapper: archive.fileWrapper())
        #expect(reread == archive)
        let ipad=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        let result=try reread.merge(into: ipad)
        #expect(result.added == 2 && result.skipped == 0)
        let arrived=try ipad.fetch(FetchDescriptor<SavedSpot>()).sorted { $0.createdAt<$1.createdAt || ($0.createdAt == $1.createdAt && $0.id<$1.id) }
        #expect(arrived.map(\.id) == [Self.jotr, Self.other])
        let first=try #require(arrived.first)
        #expect(first.latitude == 34.0123 && first.longitude == -116.1789 && first.timeZoneID == "America/Los_Angeles" && first.note == "North pullout.")
        #expect(try ipad.fetch(FetchDescriptor<SavedPark>()).isEmpty)
        #expect(try ipad.fetch(FetchDescriptor<JournalEntry>()).contains { $0.parkID == Self.jotr })
        let again=try reread.merge(into: ipad)
        #expect(again.added == 0 && again.skipped == 2)
        #expect(try ipad.fetch(FetchDescriptor<SavedSpot>()).count == 2 && (try ipad.fetch(FetchDescriptor<SavedPark>())).isEmpty)
    }
    /// A journal without spots is written exactly as before (format 1, no spots key), and a
    /// format-1 archive from an earlier version still imports.
    @MainActor @Test func olderArchivesStillImport() throws {
        let schema=Schema(versionedSchema: NyxSchemaV2.self)
        let phone=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        phone.insert(JournalEntry(date: Date(timeIntervalSince1970: 1_790_899_200), parkID: "jotr", notes: "Saturn."))
        try phone.save()
        let plain=JournalArchive.make(from: try phone.fetch(FetchDescriptor<JournalEntry>()))
        #expect(plain.manifest.format == 1 && plain.manifest.spots == nil)
        let json=try #require(plain.fileWrapper().fileWrappers?["entries.json"]?.regularFileContents)
        #expect(!String(decoding: json, as: UTF8.self).contains("spots"))
        // Written by 1.4: format 1, no spots.
        let folder=FileWrapper(directoryWithFileWrappers: [:])
        let id=UUID().uuidString
        folder.addRegularFile(withContents: Data("{\"format\":1,\"exported\":\"2026-10-01T04:00:00Z\",\"entries\":[{\"id\":\"\(id)\",\"date\":\"2026-10-01T04:00:00Z\",\"parkID\":\"jotr\",\"observedBortle\":2,\"notes\":\"Clear.\",\"photos\":[]}]}".utf8), preferredFilename: "entries.json")
        let old=try JournalArchive(wrapper: folder)
        #expect(old.manifest.spots == nil)
        let ipad=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        #expect(try old.merge(into: ipad).added == 1)
        #expect(try ipad.fetch(FetchDescriptor<JournalEntry>()).map(\.id.uuidString) == [id])
        #expect(try ipad.fetch(FetchDescriptor<SavedSpot>()).isEmpty)
    }
    /// A spot whose id or coordinates are not well formed is left out; the entries still arrive.
    @MainActor @Test func malformedSpotsAreLeftOut() throws {
        let schema=Schema(versionedSchema: NyxSchemaV2.self)
        let night=Date(timeIntervalSince1970: 1_790_899_200)
        func spot(_ id: String, _ lat: Double, zone: String="America/Denver") -> JournalArchive.Spot {
            .init(id: id, name: "A", latitude: lat, longitude: -105, timeZoneID: zone, countryCode: "US", region: "CO", created: night, note: nil, saved: true)
        }
        let archive=JournalArchive(manifest: .init(format: 2, exported: night, entries: [.init(id: UUID(), date: night, parkID: "jotr", observedBortle: 2, notes: "Clear.", photos: [])],
                                                   spots: [spot("jotr", 40), spot("pin:not-a-uuid", 40), spot(Self.jotr.uppercased(), 40), spot(Self.other, 140),
                                                           spot(Self.jotr, 40, zone: "Not/AZone"), spot(Self.jotr, 41)]), photos: [:])
        let context=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        #expect(try archive.merge(into: context).added == 1)
        let spots=try context.fetch(FetchDescriptor<SavedSpot>())
        // Only the first well-formed spot with that id, its unknown zone replaced by the meridian's.
        #expect(spots.map(\.id) == [Self.jotr] && spots.first?.latitude == 40 && spots.first?.timeZoneID == "Etc/GMT+7")
    }
}
