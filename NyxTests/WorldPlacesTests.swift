import CryptoKit
import Foundation
import Testing
@testable import Nyx

/// The starting places cover the world (GeoNames cities15000 outside the US, CC BY 4.0) while
/// the 1,008 US rows stay exactly as they were, search stays fast and ranks US places as before,
/// and the nearest place gives a saved spot its zone and region offline.
struct WorldPlacesTests {
    let places=StartingPlaces.all
    var us: [StartingPlace] { places.filter { $0.countryCode=="US" } }
    /// The 1,008 Census rows, first in the file.
    var census: [StartingPlace] { Array(places.prefix(1008)) }
    /// The parks' gateway towns, last in the file (after the world, so the names files' indices hold).
    var gateways: [StartingPlace] { Array(places.reversed().prefix { $0.countryCode=="US" }.reversed()) }

    // MARK: The file

    /// The US rows, as bytes: the body of `"places":[…]` in places.json before 2.0 (commit c3dd33d,
    /// `git show c3dd33d:Nyx/Resources/places.json`), 54,110 bytes, must open the new array
    /// unchanged. A saved starting place matches its row by name and state, so not one byte moves.
    @Test func theUSRowsAreByteForByteUnchanged() throws {
        let url=try #require(Bundle.main.url(forResource: "places", withExtension: "json"))
        let data=try Data(contentsOf: url)
        let open=try #require(data.range(of: Data(#""places":["#.utf8)))
        let length=54_110
        try #require(data.count>open.upperBound+length)
        let body=data.subdata(in: open.upperBound..<open.upperBound+length)
        let digest=SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "ed7e062443cbc9c65ea0a42332f2fff9b034ca89234ca259a86f11946c102a08")
        #expect(data[open.upperBound+length] == UInt8(ascii: ","))
        // Decoded: the first 1,008 places are those rows; the only other US places are the gateway towns at the end.
        #expect(census.allSatisfy { $0.countryCode=="US" } && gateways.count>=80 && us.count == 1008+gateways.count)
        #expect(Set(us.map(\.label)).count == us.count)
        #expect(places.count>25_000)
    }
    /// Every row: a zone this OS knows (checked once per zone), a two-letter country, a point on
    /// Earth, a population to rank by, an id of its own and a region to show.
    @Test func everyRowIsWhole() throws {
        var zones: [String: Bool]=[:], bad: [String]=[]
        for place in places {
            let zone=place.timeZoneID ?? ""
            if zones[zone]==nil { zones[zone]=TimeZone(identifier: zone) != nil }
            let whole=zones[zone]==true && place.countryCode.count==2 && place.countryCode==place.countryCode.uppercased()
                && (-90...90).contains(place.latitude) && (-180...180).contains(place.longitude) && (place.population ?? -1)>=0
                && !place.name.isEmpty && !place.regionName.isEmpty && !place.label.isEmpty
            if !whole { bad.append(place.id) }
        }
        #expect(bad.isEmpty, "\(bad.prefix(20))")
        #expect(zones.count>300)
        #expect(Set(places.map(\.id)).count == places.count)
        // Largest first in each part, so ranking by population keeps the Census order in the US.
        let ranks=places.map { $0.population ?? 0 }
        #expect(zip(ranks.prefix(1008), ranks.prefix(1008).dropFirst()).allSatisfy { $0 >= $1 })
        let world=Array(ranks.dropFirst(1008).dropLast(gateways.count)), towns=Array(ranks.suffix(gateways.count))
        #expect(zip(world, world.dropFirst()).allSatisfy { $0 >= $1 } && zip(towns, towns.dropFirst()).allSatisfy { $0 >= $1 })
        // Names that fold to letters outside ASCII carry a plain spelling ("Lodz").
        let unspelled=places.filter { !StartingPlaces.normalized($0.name).allSatisfy(\.isASCII) && $0.asciiName.map { StartingPlaces.normalized($0).allSatisfy(\.isASCII) } != true }
        #expect(unspelled.isEmpty, "\(unspelled.prefix(20).map(\.id))")
    }

    // MARK: Search

    /// The search before 2.0 (`StartingPlace.score`), kept only as the oracle for US ranking.
    static func oldSearch(_ query: String, in places: [StartingPlace]) -> [String] {
        func normalized(_ text: String) -> String {
            Park.folded(text).split(separator: " ").map { ["st": "saint", "ft": "fort", "mt": "mount"][String($0)] ?? String($0) }.joined(separator: " ")
        }
        let needle=normalized(query)
        func score(_ place: StartingPlace) -> Int? {
            guard !needle.isEmpty else { return nil }
            let name=normalized(place.name), code=place.state.lowercased(), full=Park.folded(place.regionName)
            if name==needle { return 0 }
            for suffix in [code, full] where needle.hasSuffix(" "+suffix) {
                let city=String(needle.dropLast(suffix.count+1))
                if name==city { return 0 }
                if name.hasPrefix(city) { return 1 }
            }
            if name.hasPrefix(needle) { return 2 }
            if name.contains(needle) { return 3 }
            return nil
        }
        return places.enumerated().compactMap { index, place in score(place).map { (place.label, $0, index) } }.sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
    }
    /// The Census places come in the same order as before among themselves; the rest of the world
    /// and the gateway towns are interleaved by population. (The one deliberate change, a word start
    /// such as "New York" for "York" before a match inside a word, does not touch these queries.)
    @Test func usPlacesRankAsBefore() {
        let censusLabels=Set(census.map(\.label))
        for query in ["Spring", "Springfield", "Springfield, Illinois", "Columbus", "Chicago", "chicago il", "St. Paul", "Saint", "Lake", "Fort", "York", "Denver, CO", "Portland"] {
            let now=StartingPlaces.search(query, limit: 10_000).map(\.label).filter(censusLabels.contains)
            #expect(now == Self.oldSearch(query, in: census), "\(query)")
        }
        // The picker shows 12: Springfield, Illinois is still among them.
        let spring=StartingPlaces.search("Spring", limit: 12).map(\.label)
        #expect(spring.contains("Springfield, IL") && spring.contains("Springfield, MO"))
        #expect(StartingPlaces.search("Spring", limit: 12).filter { $0.countryCode=="US" }.prefix(7).map(\.label)
                == ["Springfield, MO", "Springfield, MA", "Springfield, IL", "Springdale, AR", "Springfield, OR", "Spring Hill, TN", "Springfield, OH"])
        #expect(StartingPlaces.search("Columbus").first?.label == "Columbus, OH")
        #expect(StartingPlaces.search("St. Paul").first?.label == "Saint Paul, MN")
        #expect(StartingPlaces.named("Denver")?.label == "Denver, CO")
        // "Helena, MT" read "mt" as "mount" and found nothing before 2.0; it finds Helena now.
        #expect(StartingPlaces.search("Helena, MT").first?.label == "Helena, MT")
    }
    @Test func theWorldIsSearchable() throws {
        let paris=try #require(StartingPlaces.search("Paris").first)
        #expect(paris.name == "Paris" && paris.countryCode == "FR" && paris.timeZoneID == "Europe/Paris")
        #expect(StartingPlaces.named("Paris") == paris)
        // Accents fold both ways.
        let saoPaulo=StartingPlaces.search("São Paulo")
        #expect(saoPaulo.first?.name == "São Paulo" && saoPaulo.first?.countryCode == "BR")
        #expect(StartingPlaces.search("Sao Paulo") == saoPaulo && StartingPlaces.search("SAO PAULO") == saoPaulo)
        // Letters folding cannot reach, through the plain spelling.
        #expect(StartingPlaces.search("Lodz").first?.name == "Łódź" && StartingPlaces.search("Łódź").first?.name == "Łódź")
        #expect(StartingPlaces.search("Diyarbakir").first?.name == "Diyarbakır")
        // Curly apostrophes read as straight ones.
        #expect(StartingPlaces.search("Xian").first?.name == "Xi’an" && StartingPlaces.search("Xi'an").first?.name == "Xi’an")
        // A region or a country narrows: by name, together, or by code.
        for query in ["Toronto Canada", "Toronto, Ontario", "toronto ontario canada", "Toronto CA"] {
            #expect(StartingPlaces.search(query).first?.label == "Toronto, \(StartingPlaces.countryName("CA"))", "\(query)")
        }
        #expect(StartingPlaces.search("London, Canada").first?.countryCode == "CA")
        #expect(StartingPlaces.search("London").first?.countryCode == "GB")
        // Same-named places in one country all stay, told apart by region.
        let cordoba=StartingPlaces.search("Cordoba").filter { $0.name=="Córdoba" }
        #expect(Set(cordoba.map(\.countryCode)).isSuperset(of: ["AR", "ES", "MX"]))
        #expect(StartingPlaces.search("").isEmpty && StartingPlaces.search("zzqx").isEmpty && StartingPlaces.named("Brigadoon") == nil)
    }
    /// A park's gateway town is a starting point, though it is far below the Census cut: Moab for
    /// Arches, Springdale for Zion, Estes Park for Rocky Mountain, each on its own state's time.
    @Test func gatewayTownsAreFound() throws {
        let moab=try #require(StartingPlaces.search("Moab").first)
        #expect(moab.label == "Moab, UT" && moab.timeZoneID == "America/Denver" && moab.countryCode == "US" && moab.regionName == "Utah")
        #expect(Park.distance(moab.latitude, moab.longitude, 38.573, -109.550) < 2_000)
        // Springdale, Arkansas is the larger town and comes first; Zion's is in the list beside it.
        #expect(StartingPlaces.search("Springdale", limit: 12).map(\.label).contains("Springdale, UT"))
        #expect(StartingPlaces.search("springdale utah").first?.label == "Springdale, UT")
        #expect(StartingPlaces.search("Estes Park").first?.label == "Estes Park, CO")
        #expect(StartingPlaces.named("Estes Park")?.timeZoneID == "America/Denver")
        #expect(StartingPlaces.search("West Yellowstone").first?.label == "West Yellowstone, MT")
        // A saved gateway town reads back as the bundled row.
        let saved=try JSONDecoder().decode(StartingPlace.self, from: JSONEncoder().encode(moab))
        #expect(saved == moab && saved.id == "Moab, UT")
        // Added after the world, so every translated town keeps its index: Tokyo is still 東京 in
        // Japanese, and Moab, which has no Japanese name in the file, keeps its own.
        let japanese=StartingPlaces.load(language: "ja")
        #expect(japanese.count == places.count)
        #expect(japanese.first { $0.countryCode=="JP" && $0.savedName=="Tokyo" }?.name.hasPrefix("東京") == true)
        #expect(japanese.first { $0.savedName=="Moab" && $0.state=="UT" }?.name == "Moab")
    }
    @Test func worldPlacesReadInTheReadersLanguage() throws {
        let france=StartingPlaces.countryName("FR")
        let paris=try #require(StartingPlaces.named("Paris"))
        #expect(paris.label == "Paris, \(france)" && paris.regionName == "Île-de-France, \(france)")
        // No region: the country alone. A region that is the country: the country alone.
        let singapore=try #require(places.first { $0.countryCode=="SG" && $0.state.isEmpty })
        #expect(singapore.regionName == StartingPlaces.countryName("SG"))
        #expect(StartingPlaces.regionName(countryCode: "RE", region: "Reunion") == StartingPlaces.countryName("RE"))
        // Population and spelling are not identity: a saved record equals the bundled row.
        let lodz=try #require(StartingPlaces.named("Lodz"))
        let saved=try JSONDecoder().decode(StartingPlace.self, from: JSONEncoder().encode(lodz))
        #expect(saved.population == nil && saved.asciiName == nil && saved == lodz && Set([saved]).contains(lodz))
        #expect(saved.timeZoneID == "Europe/Warsaw" && saved.countryCode == "PL" && saved.id == lodz.id)
        // A list that is not the bundled one is searched the same way.
        let mine=[lodz, paris]
        #expect(StartingPlaces.search("lodz", in: mine) == [lodz] && StartingPlaces.named("Paris, France", in: mine) == paris)
        #expect(lodz.matches("Łódź Poland") && !lodz.matches("Paris"))
    }

    // MARK: Nearest

    @Test func theNearestPlaceGivesASpotItsZone() throws {
        // Lake Tekapo, New Zealand: a Canterbury town, on New Zealand time.
        let tekapo=try #require(StartingPlaces.nearest(latitude: -44.004, longitude: 170.477))
        #expect(tekapo.countryCode == "NZ" && tekapo.timeZoneID == "Pacific/Auckland")
        #expect(Park.distance(-44.004, 170.477, tekapo.latitude, tekapo.longitude) < 150_000)
        #expect(StartingPlaces.nearestZone(latitude: -44.004, longitude: 170.477)?.identifier == "Pacific/Auckland")
        // The central Sahara: Tamanrasset, Algeria.
        let sahara=try #require(StartingPlaces.nearest(latitude: 23, longitude: 5))
        #expect(sahara.countryCode == "DZ" && sahara.timeZoneID == "Africa/Algiers")
        // A city is its own nearest place.
        #expect(StartingPlaces.nearest(latitude: 41.837, longitude: -87.685)?.label == "Chicago, IL")
        // Across the date line: Fiji from either side of 180°.
        #expect(StartingPlaces.nearest(latitude: -16.4, longitude: 179.99)?.countryCode == "FJ")
        #expect(StartingPlaces.nearest(latitude: -16.4, longitude: -179.99)?.countryCode == "FJ")
        // The open Pacific: the nearest town is far; a reach says so.
        #expect(StartingPlaces.nearest(latitude: 0, longitude: -140, within: 1_000_000) == nil)
        #expect(StartingPlaces.nearest(latitude: 0, longitude: -140) != nil)
        #expect(StartingPlaces.nearest(latitude: .nan, longitude: 0) == nil)
    }
    /// The cell search finds what reading every place finds, near the poles and the date line too.
    @Test func theNearestPlaceMatchesAFullScan() throws {
        var generator=SplitMix(seed: 2026)
        var points: [(Double, Double)]=[(90, 0), (-90, 0), (89.9, 179.9), (-77.8, 166.7), (0, 180), (0, -180), (64.8, -147.7), (-54.8, -68.3)]
        for _ in 0..<150 { points.append((Double(generator.next() % 18_000)/100-90, Double(generator.next() % 36_000)/100-180)) }
        var wrong: [String]=[]
        for (latitude, longitude) in points {
            let found=try #require(StartingPlaces.nearest(latitude: latitude, longitude: longitude))
            var scan=Double.infinity
            // The same set `nearest` reads: every locatable place, or the US ones for a point inside the US.
            let candidates=USOutline.contains(latitude: latitude, longitude: longitude) ? StartingPlaces.usLocatable : StartingPlaces.locatable
            for place in candidates { scan=min(scan, Park.distance(latitude, longitude, place.latitude, place.longitude)) }
            if abs(Park.distance(latitude, longitude, found.latitude, found.longitude)-scan) >= 0.001 { wrong.append("\(latitude), \(longitude)") }
        }
        #expect(wrong.isEmpty, "\(wrong)")
    }

    // MARK: Speed

    /// Typing "Springfield, Illinois" then "Paris": one search over all ~31,500 places per keystroke.
    /// Release builds take about a millisecond a keystroke on an M-series Mac; this Debug test
    /// build about 25 ms for the slowest (one letter, which matches thousands). 100 ms is where a
    /// list starts to lag behind typing, so the median must stay under it even unoptimized, and
    /// the slowest under 300 ms to allow for other tests running alongside.
    @Test(.enabled(if: Bench.enabled)) func searchKeepsUpWithTyping() {
        _=StartingPlaces.index
        let typed="Springfield, Illinois"
        let keystrokes=(1...typed.count).map { String(typed.prefix($0)) }+["P", "Pa", "Par", "Pari", "Paris", "São", "Lodz"]
        let clock=ContinuousClock()
        var times: [Duration]=[]
        for query in keystrokes { times.append(clock.measure { _=StartingPlaces.search(query, limit: 12) }) }
        times.sort()
        #expect(times[times.count/2] < .milliseconds(100))
        #expect(times.last ?? .zero < .milliseconds(300))
    }
}

/// A small deterministic generator, so the scan comparison checks the same points every run.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state=seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z=state
        z=(z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z=(z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A saved spot inside the United States takes a US town as its nearest, never one across the border.
struct NearestInsideTheUnitedStates {
    @Test func northernMaineStaysInMaine() throws {
        // Near Wallagrass, Maine (about 15 km south of New Brunswick): Eastern time, not Atlantic.
        let near=try #require(StartingPlaces.nearest(latitude: 47.1, longitude: -68.6))
        #expect(near.countryCode == "US" && near.timeZoneID == "America/New_York", "\(near.name)")
        #expect(USOutline.contains(latitude: 47.1, longitude: -68.6) && !USOutline.contains(latitude: 45.96, longitude: -66.64))  // and Fredericton, New Brunswick, is not
    }
    @Test func theOutlineKnowsTheStates() {
        #expect(USOutline.contains(latitude: 39.74, longitude: -104.99))      // Denver
        #expect(USOutline.contains(latitude: 61.2, longitude: -149.9))        // Anchorage
        #expect(USOutline.contains(latitude: 21.3, longitude: -157.85))       // Honolulu
        #expect(!USOutline.contains(latitude: 45.42, longitude: -75.7))       // Ottawa
        #expect(!USOutline.contains(latitude: 19.43, longitude: -99.13))      // Mexico City
        #expect(!USOutline.contains(latitude: 48.85, longitude: 2.35))        // Paris
    }
    @Test func puertoRicoKeepsAtlanticTime() throws {
        // San Juan: the territory's own towns, never a mainland one with New York's daylight saving.
        let near=try #require(StartingPlaces.nearest(latitude: 18.42, longitude: -66.06))
        #expect(near.timeZoneID == "America/Puerto_Rico", "\(near.name) \(near.timeZoneID ?? "-")")
        #expect(!USOutline.contains(latitude: 18.42, longitude: -66.06))
    }
    @Test func abroadTheNearestIsLocal() throws {
        let tekapo=try #require(StartingPlaces.nearest(latitude: -44.0, longitude: 170.48))
        #expect(tekapo.countryCode == "NZ" && tekapo.timeZoneID == "Pacific/Auckland")
    }
}
