import Foundation
import Testing
@testable import Nyx

/// The screens of the world catalogue: the Parks list's order by country and its lazy rows,
/// which places Tonight weighs, how a place abroad names itself and says what Nyx cannot check,
/// Siri's and Shortcuts' reach into the catalogue, and what Spotlight remembers.
@MainActor
struct CatalogScreensTests {
    /// A catalogue place as `catalog.json` writes it.
    private static func place(_ id: String, _ name: String, country: String, region: String = "", kind: String = "nationalPark",
                              latitude: Double = 45, longitude: Double = 5, bortle: Int = 3, designated: Bool = false, website: String? = nil) throws -> Park {
        var record: [String: Any] = ["id": id, "name": name, "countryCode": country, "region": region, "kind": kind, "curated": false,
                                     "latitude": latitude, "longitude": longitude, "timeZoneID": "Europe/Paris", "darkSkyDesignated": designated,
                                     "bortleEstimate": bortle, "description": "", "sourceURL": "https://www.wikidata.org/wiki/\(id.dropFirst(3))",
                                     "sourceNote": "Wikidata, CC0.", "viewingSpots": [] as [Any]]
        if let website { record["website"] = website }
        return try JSONDecoder().decode(Park.self, from: JSONSerialization.data(withJSONObject: record))
    }
    private static let names = ["AT": "Austria", "DE": "Germany", "FR": "France", "US": "United States", "ES": "Spain"]

    // MARK: The Parks list

    @Test func homeCountryLeadsThenTheRestByName() throws {
        let places = [try Self.place("wd:Q1", "Zugspitze", country: "DE"), try Self.place("wd:Q2", "Écrins", country: "FR"),
                      try Self.place("wd:Q3", "Cévennes", country: "FR"), try Self.place("wd:Q4", "Gesäuse", country: "AT"),
                      try Self.place("wd:Q5", "Westhavelland", country: "DE")]
        let groups = WorldBrowse.groups(places, home: "FR") { Self.names[$0] ?? $0 }
        #expect(groups.map(\.code) == ["FR", "AT", "DE"])
        // Within a country by name, accents folded: Cévennes before Écrins.
        #expect(groups[0].places.map(\.name) == ["Cévennes", "Écrins"])
        #expect(groups[2].places.map(\.name) == ["Westhavelland", "Zugspitze"])
        // A home country with no places leaves the alphabetical order alone.
        #expect(WorldBrowse.groups(places, home: "ES") { Self.names[$0] ?? $0 }.map(\.code) == ["AT", "FR", "DE"])
    }
    @Test func theHomeCountryComesFromTheStartingPoint() {
        // Before a starting point is chosen, this device's region; then the city's, or the park's.
        #expect(WorldBrowse.homeCountry(startChosen: false, place: nil, park: "US", region: "fr") == "FR")
        #expect(WorldBrowse.homeCountry(startChosen: true, place: "NZ", park: "US", region: "FR") == "NZ")
        #expect(WorldBrowse.homeCountry(startChosen: true, place: nil, park: "US", region: "FR") == "US")
        #expect(WorldBrowse.homeCountry(startChosen: false, place: nil, park: nil, region: nil) == "US")
    }
    @Test func aUSStartingPointListsTheCuratedParksAboveTheWorldNotInIt() throws {
        let parks = try ParkData.load()
        let abroad = try Self.place("wd:Q10973", "Albanyà", country: "ES", kind: "community", designated: true)
        let usDark = try Self.place("wd:Q99", "Cherry Springs", country: "US", region: "PA", kind: "darkSkyPark", designated: true)
        let groups = WorldBrowse.groups(parks + [abroad, usDark], home: "US") { Self.names[$0] ?? $0 }
        let fromUS = WorldBrowse.narrowed(groups, darkOnly: false, curated: false, hiding: [])
        #expect(fromUS.first?.code == "US" && fromUS.first?.places.map(\.id) == ["wd:Q99"])
        // From abroad the US group holds the national parks too; Dark Sky only narrows every group.
        let fromAbroad = WorldBrowse.narrowed(groups, darkOnly: false, curated: true, hiding: [])
        #expect(fromAbroad.first { $0.code == "US" }?.places.count == parks.count + 1)
        let dark = WorldBrowse.narrowed(groups, darkOnly: true, curated: true, hiding: ["wd:Q10973"])
        #expect(dark.allSatisfy { $0.places.allSatisfy(\.darkSkyDesignated) } && !dark.contains { $0.code == "ES" })
    }
    @Test func closedCountriesBuildNoRows() throws {
        let places = try (0..<300).map { try Self.place("wd:Q\($0)", "Place \($0)", country: $0 % 3 == 0 ? "FR" : "DE") }
        let groups = WorldBrowse.groups(places, home: "FR") { Self.names[$0] ?? $0 }
        // Nothing open: two country rows and not one place, so nothing is scored.
        #expect(WorldBrowse.rows(groups, open: []).count == 2)
        let open = WorldBrowse.rows(groups, open: ["FR"])
        #expect(open.count == 2 + 100)
        #expect(open.filter { if case .place = $0 { true } else { false } }.count == 100)
        #expect(Set(open.map(\.id)).count == open.count)
    }
    @Test func forecastsAreAskedOnlyForRowsOnScreen() throws {
        // A long country scrolled from top to bottom, ten rows on screen at a time.
        let rows = try (0..<880).map { try Self.place("wd:Q\($0)", "Place \($0)", country: "AU") }
        var screen = OnScreen(), asked: [String] = [], mostOnScreen = 0
        for (index, row) in rows.enumerated() {
            screen.appeared(row)
            if index >= 10 { screen.disappeared(rows[index-10].id) }
            mostOnScreen = max(mostOnScreen, screen.visible.count)
            // Scrolling settles every 25 rows; only then is anything asked for.
            if index % 25 == 24 { asked += screen.takeUnrequested().map(\.id) }
        }
        #expect(mostOnScreen <= 10)
        // Never a row twice, never more than were on screen when it settled, never a row scrolled past unseen.
        #expect(Set(asked).count == asked.count)
        #expect(asked.count <= (rows.count/25)*10)
        #expect(asked.allSatisfy { id in rows.firstIndex { $0.id == id }.map { $0 % 25 >= 15 } ?? false })
    }
    @Test func theListSummaryCountsPlacesAndCountries() throws {
        let groups = WorldBrowse.groups([try Self.place("wd:Q1", "A", country: "FR"), try Self.place("wd:Q2", "B", country: "DE"),
                                         try Self.place("wd:Q3", "C", country: "DE")], home: nil) { Self.names[$0] ?? $0 }
        #expect(WorldBrowse.summary(groups) == String(localized: "\(3) parks and dark-sky places in \(2) countries"))
    }

    // MARK: Tonight

    @Test func aUSStartWithOnlyUSPlacesInRangeIsUnchanged() throws {
        let parks = try ParkData.load().filter { ["jotr", "deva"].contains($0.id) }
        let usDark = try Self.place("wd:Q99", "Borrego Springs", country: "US", region: "CA", kind: "community", designated: true)
        #expect(TonightReach.candidates(parks: parks, places: parks + [usDark], originInUS: true) == parks)
        // Near the border, a place across it joins: then every place in range, ranked as the parks are.
        let canada = try Self.place("wd:Q98", "Waterton Lakes", country: "CA", region: "Alberta")
        #expect(TonightReach.candidates(parks: parks, places: parks + [canada], originInUS: true) == parks + [canada])
        // Abroad, or with no national park in reach, every place in range.
        #expect(TonightReach.candidates(parks: [], places: [usDark], originInUS: true) == [usDark])
        #expect(TonightReach.candidates(parks: [], places: [canada], originInUS: false) == [canada])
    }
    @Test func aCrowdedRadiusIsShortlistedByItsSky() throws {
        let parks = try ParkData.load().filter { $0.id == "jotr" }
        let bright = try (0..<60).map { try Self.place("wd:Q\($0)", "Bright \($0)", country: "FR", latitude: 45 + Double($0)/100, bortle: 6) }
        let dark = try Self.place("wd:Q500", "Far and dark", country: "FR", latitude: 47, bortle: 2)
        let list = TonightReach.shortlist(parks + bright + [dark], latitude: 45, longitude: 5, limit: 10)
        #expect(list.count == 10)
        // Curated parks and spots always; then the darkest sky, then the nearest.
        #expect(list.first?.id == "jotr" && list[1].id == "wd:Q500" && list[2].id == "wd:Q0")
        #expect(TonightReach.key(list) == TonightReach.key(list.reversed()))
    }

    // MARK: A place abroad

    @Test func aPlaceAbroadSaysWhatNyxCannotCheck() throws {
        let albanya = try Self.place("wd:Q10973", "Albanyà", country: "ES", region: "Catalonia", kind: "community", designated: true, website: "https://www.albanya.cat")
        #expect(albanya.isCatalogPlace && !albanya.isSavedSpot)
        #expect(albanya.unknownClosuresLine == String(localized: "Nyx can't check closures here. Check the park's own site before you go."))
        #expect(albanya.website?.absoluteString == "https://www.albanya.cat")
        #expect(albanya.wikidataURL?.absoluteString == "https://www.wikidata.org/wiki/Q10973")
        #expect(albanya.kindLabel == String(localized: "International Dark Sky Community"))
        let spain = StartingPlaces.countryName("ES")
        #expect(albanya.worldLocality == "Catalonia, \(spain)")
        #expect(albanya.worldEyebrow == "International Dark Sky Community · Catalonia, \(spain)")
        // A site offered only over plain HTTP is not linked; the line stands alone.
        let plain = try Self.place("wd:Q2", "Somewhere", country: "IS", website: "http://example.is")
        #expect(plain.website == nil && plain.worldLocality == StartingPlaces.countryName("IS"))
        // A curated park keeps the Park Service's alerts; a saved spot its own line.
        let jotr = try #require(ParkData.load().first { $0.id == "jotr" })
        #expect(!jotr.isCatalogPlace && jotr.wikidataURL == nil)
        let spot = Place(spotID: "pin:1", name: "Pullout", latitude: 34, longitude: -116, timeZoneID: "America/Los_Angeles", countryCode: "US", region: "CA", grid: SkyGrid(bundle: .main, layers: []))
        #expect(spot.unknownClosuresLine == String(localized: "Nyx has no alerts for this place. Check access, local rules and closures before you go."))
    }
    @Test func designationsKeepDarkSkyInternationalsNames() throws {
        let kinds = ["darkSkyPark": "International Dark Sky Park", "reserve": "International Dark Sky Reserve",
                     "sanctuary": "International Dark Sky Sanctuary", "community": "International Dark Sky Community",
                     "urbanNightSky": "Urban Night Sky Place", "nationalPark": "National park"]
        for (kind, label) in kinds {
            // The test plan runs in English.
            let place = try Self.place("wd:Q1", "X", country: "NZ", kind: kind, designated: kind != "nationalPark")
            #expect(place.kindLabel == label)
            // Siri, Shortcuts and Spotlight name the same designation, and only a designated place has one.
            #expect(ParkEntity(place).designation == (kind == "nationalPark" ? "" : label), "\(kind)")
        }
        // A curated park keeps its kind with the flag: an International Dark Sky Park.
        let jotr = try #require(ParkData.load().first { $0.id == "jotr" })
        #expect(jotr.designationName == "International Dark Sky Park" && ParkEntity(jotr).designation == "International Dark Sky Park")
        // Several US states read as a list, with the country.
        let us = try Self.place("wd:Q3", "X", country: "US", region: "CO,UT")
        #expect(us.worldLocality.hasPrefix("Colorado") && us.worldLocality.contains("Utah") && us.worldLocality.hasSuffix(StartingPlaces.countryName("US")))
    }

    // MARK: Siri, Shortcuts and Spotlight

    @Test func catalogueIdsResolveAndSearchReachesTheWorld() async throws {
        // In the app, which bundles the catalogue.
        guard !ParkLibrary.catalog().isEmpty else { return }
        #expect(ParkLibrary.place("wd:Q10973", snapshot: nil)?.name == "Albanyà")
        #expect(ParkLibrary.place("jotr", snapshot: nil)?.id == "jotr")
        #expect(ParkLibrary.place("wd:Q0", snapshot: nil) == nil)
        let query = ParkQuery()
        #expect(try await query.entities(for: ["wd:Q10973", "jotr", "wd:Q10973"]).map(\.id) == ["wd:Q10973", "jotr"])
        // Accents folded; the curated park first when both match.
        #expect(try await query.entities(matching: "albanya").contains { $0.id == "wd:Q10973" })
        #expect(ParkLibrary.search("albanya").first?.id == "wd:Q10973")
        #expect(ParkLibrary.search("", limit: 10).isEmpty && ParkLibrary.search("national", limit: 7).count == 7)
        let entity = ParkEntity(try #require(ParkLibrary.place("wd:Q10973", snapshot: nil)))
        #expect(entity.country == "ES" && !entity.nationalPark && entity.darkSky)
        #expect(entity.attributeSet.keywords?.contains("national park") == false)
    }
    @Test func followedPlacesAbroadAreSuggestedButNotTheWholeWorld() throws {
        let jotr = try #require(ParkData.load().first { $0.id == "jotr" })
        let abroad = try Self.place("wd:Q10973", "Albanyà", country: "ES", kind: "community", designated: true)
        let snapshot = SavedSkySnapshot(parks: [jotr, abroad], forecasts: [:])
        let suggested = try ParkLibrary.suggested(snapshot: snapshot)
        #expect(suggested.count == (try ParkData.load()).count + 1)
        #expect(suggested.prefix(2).map(\.id) == ["wd:Q10973", "jotr"])
        #expect(try ParkLibrary.places(snapshot: snapshot).last?.id == "wd:Q10973")
        // A followed place resolves from the snapshot, as the widgets (with no catalogue) need.
        #expect(ParkLibrary.place("wd:Q10973", snapshot: snapshot)?.name == "Albanyà")
    }
    @Test func spotlightRemembersAtMostItsRoomAndKeepsFollowedPlaces() {
        let list = (0..<137).map { "wd:Q\($0)" }
        let (kept, evicted) = SpotlightIndexer.remembered(list, adding: "wd:Q999", followed: ["wd:Q0"], room: 137)
        #expect(kept.count == 137 && kept.last == "wd:Q999")
        // The oldest that is not followed leaves; a followed place stays.
        #expect(evicted == ["wd:Q1"] && kept.contains("wd:Q0"))
        // Opening a remembered place again makes it the newest, and nothing leaves.
        let again = SpotlightIndexer.remembered(kept, adding: "wd:Q5", followed: [], room: 137)
        #expect(again.kept.last == "wd:Q5" && again.evicted.isEmpty && again.kept.count == 137)
        #expect(SpotlightIndexer.limit == 200)
    }
}
