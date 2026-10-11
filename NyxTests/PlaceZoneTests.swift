import Foundation
import Testing
@testable import Nyx

/// G1: a starting place's time zone is data stored with the place (`places.json`, worked out by
/// `Scripts/build_places.py`), its region has a display name in any country, and links name any
/// kind of place.
struct PlaceZoneTests {
    let parks=(try? ParkData.load()) ?? []
    let places=StartingPlaces.all
    static func date(_ iso: String) throws -> Date { try Date(iso+"T21:00:00Z", strategy: .iso8601) }

    /// The state table the app used before G1 (`HomeSky.timeZone`), kept here only as the oracle
    /// for the stored zones: the split states divided by rough longitude and latitude lines.
    static func oldZone(state: String, latitude: Double, longitude: Double) -> String {
        switch state {
        case "HI": "Pacific/Honolulu"
        case "AK": "America/Anchorage"
        case "AZ": "America/Phoenix"
        case "CA", "WA", "NV": "America/Los_Angeles"
        case "OR": longitude > -117.25 && latitude < 44.5 ? "America/Boise" : "America/Los_Angeles"
        case "ID": latitude > 45.6 ? "America/Los_Angeles" : "America/Boise"
        case "CO", "MT", "NM", "UT", "WY": "America/Denver"
        case "TX": longitude < -104.5 ? "America/Denver" : "America/Chicago"
        case "KS": longitude < -101.5 ? "America/Denver" : "America/Chicago"
        case "NE": longitude < -101.0 ? "America/Denver" : "America/Chicago"
        case "SD": longitude < -100.5 ? "America/Denver" : "America/Chicago"
        case "ND": longitude < -101.0 && latitude < 47.5 ? "America/Denver" : "America/Chicago"
        case "FL": longitude < -85.0 && latitude > 29.6 ? "America/Chicago" : "America/New_York"
        case "IN": longitude < -86.9 && (latitude > 40.9 || latitude < 38.6) ? "America/Chicago" : "America/Indiana/Indianapolis"
        case "KY": longitude < -85.9 ? "America/Chicago" : "America/Kentucky/Louisville"
        case "TN": longitude > -85.4 ? "America/New_York" : "America/Chicago"
        case "MI": longitude < -87.6 && latitude > 45 && latitude < 46.6 ? "America/Chicago" : "America/Detroit"
        case "AL", "AR", "IL", "IA", "LA", "MN", "MS", "MO", "OK", "WI": "America/Chicago"
        case "AS": "Pacific/Pago_Pago"
        case "VI", "PR": "America/St_Thomas"
        default: "America/New_York"
        }
    }

    // MARK: Zones

    /// Every bundled place carries the zone the old table gave it: US behaviour is unchanged.
    @Test func storedZonesMatchTheOldTable() throws {
        // The US rows, from the Census list: the world rows carry GeoNames' own zones.
        let us=places.filter { $0.countryCode=="US" }
        #expect(us.count>=1000)
        var matched=0
        for place in us {
            let old=Self.oldZone(state: place.state, latitude: place.latitude, longitude: place.longitude)
            #expect(place.timeZoneID == old, "\(place.label)")
            if place.timeZoneID == old { matched+=1 }
        }
        #expect(matched == us.count)
    }
    /// The oracle itself, checked against every US park's own zone (winter and summer offsets).
    @Test func theOldTableAgreesWithTheParks() throws {
        func offsets(_ zone: TimeZone) throws -> [Int] { [zone.secondsFromGMT(for: try Self.date("2026-01-15")), zone.secondsFromGMT(for: try Self.date("2026-07-15"))] }
        for park in parks where park.countryCode == "US" {
            let zone=try #require(TimeZone(identifier: Self.oldZone(state: String(park.region.prefix(2)), latitude: park.latitude, longitude: park.longitude)))
            #expect(try offsets(zone) == offsets(park.timeZone), "\(park.id)")
        }
    }
    /// Whatever the list holds: unique labels, a real zone for each, a country code, a region.
    @Test func everyPlaceIsWhole() {
        #expect(Set(places.map(\.id)).count == places.count)
        for place in places {
            #expect(place.timeZoneID.flatMap(TimeZone.init(identifier:)) != nil, "\(place.label)")
            #expect(place.timeZone.identifier == place.timeZoneID, "\(place.label)")
            #expect(place.countryCode.count == 2 && (place.countryCode != "US" || !place.state.isEmpty) && !place.regionName.isEmpty, "\(place.label)")
            #expect((-90...90).contains(place.latitude) && (-180...180).contains(place.longitude), "\(place.label)")
        }
    }
    /// The split states' cities land on the right side of their lines.
    @Test func splitStatesFollowTheMap() throws {
        let expected: [String: String]=["El Paso, TX": "America/Denver", "Pensacola, FL": "America/Chicago", "Tallahassee, FL": "America/New_York",
            "Boise, ID": "America/Boise", "Coeur d'Alene, ID": "America/Los_Angeles", "Evansville, IN": "America/Chicago", "Gary, IN": "America/Chicago",
            "Louisville, KY": "America/Kentucky/Louisville", "Bowling Green, KY": "America/Chicago", "Nashville, TN": "America/Chicago",
            "Knoxville, TN": "America/New_York", "Chattanooga, TN": "America/New_York", "Rapid City, SD": "America/Denver", "Sioux Falls, SD": "America/Chicago",
            "Phoenix, AZ": "America/Phoenix", "Honolulu, HI": "Pacific/Honolulu", "Anchorage, AK": "America/Anchorage", "Detroit, MI": "America/Detroit"]
        for (name, zone) in expected {
            let place=try #require(StartingPlaces.named(name), "\(name)")
            #expect(place.timeZoneID == zone, "\(name)")
            #expect(HomeSky.origin(location: nil, place: place, park: nil)?.timeZone.identifier == zone, "\(name)")
        }
    }
    /// A place with no zone, or one this device does not know, uses the device's own zone.
    @Test func aPlaceWithoutAZoneUsesTheDevicesZone() {
        let bare=StartingPlace(name: "Nowhere", state: "", latitude: 10, longitude: 10, countryCode: "ZZ")
        #expect(bare.timeZoneID == nil && bare.timeZone == .current)
        #expect(StartingPlace(name: "Nowhere", state: "", latitude: 10, longitude: 10, countryCode: "ZZ", timeZoneID: "Mars/Olympus").timeZone == .current)
        #expect(HomeSky.origin(location: nil, place: bare, park: nil)?.timeZone == .current)
    }
    /// A home place saved before G1 (`{name, state, latitude, longitude}`) reads with its zone and
    /// still equals the list's row, so the picker's checkmark stays; a new record round-trips.
    @Test func aSavedHomeFromBeforeG1StillReads() throws {
        let chicago=try #require(StartingPlaces.named("Chicago, IL"))
        let old=Data(#"{"name":"Chicago","state":"IL","latitude":\#(chicago.latitude),"longitude":\#(chicago.longitude)}"#.utf8)
        let read=try JSONDecoder().decode(StartingPlace.self, from: old)
        #expect(read == chicago && read.timeZoneID == "America/Chicago" && read.countryCode == "US")
        #expect(try JSONDecoder().decode(StartingPlace.self, from: JSONEncoder().encode(chicago)) == chicago)
        // A saved place the list no longer has keeps its coordinates and uses the device's zone.
        let gone=try JSONDecoder().decode(StartingPlace.self, from: Data(#"{"name":"Atlantis","state":"IL","latitude":41,"longitude":-88}"#.utf8))
        #expect(gone.timeZoneID == nil && gone.timeZone == .current)
    }

    // MARK: Region names

    @Test func regionNames() throws {
        #expect(StartingPlaces.regionName(countryCode: "US", region: "IL") == "Illinois")
        #expect(StartingPlaces.regionName(countryCode: "US", region: "DC") == "District of Columbia")
        #expect(StartingPlaces.regionName(countryCode: "US", region: "ZZ") == "ZZ")
        let canada=try #require(Locale.current.localizedString(forRegionCode: "CA"))
        #expect(StartingPlaces.regionName(countryCode: "CA", region: "Ontario") == "Ontario, \(canada)")
        #expect(StartingPlaces.regionName(countryCode: "CA", region: "") == canada)
        #expect(try #require(StartingPlaces.named("Chicago, IL")).regionName == "Illinois")
        // Every US place has a state name to show, never the bare code.
        #expect(places.filter { $0.countryCode == "US" }.allSatisfy { $0.regionName != $0.state })
    }

    // MARK: Links

    @Test func linksNameAnyKindOfPlace() throws {
        func link(_ s: String) -> DeepLink? { URL(string: s).flatMap(DeepLink.init) }
        // Today's parks exactly as before.
        #expect(link("nyx://park/jotr") == .park("jotr") && link("nyx://park/JOTR") == .park("jotr"))
        for park in parks { #expect(link("nyx://park/\(park.id)") == .park(park.id), "\(park.id)") }
        // A Wikidata item, the colon plain or percent-encoded.
        #expect(link("nyx://park/wd:Q123456") == .park("wd:Q123456"))
        #expect(link("nyx://park/wd%3AQ123456") == .park("wd:Q123456"))
        #expect(link("nyx://park/WD:q42") == .park("wd:Q42"))
        // A saved spot: any case in, lowercase stored.
        let uuid=UUID()
        #expect(link("nyx://park/pin:\(uuid.uuidString)") == .park("pin:\(uuid.uuidString.lowercased())"))
        #expect(link("nyx://park/pin%3A\(uuid.uuidString.lowercased())") == .park("pin:\(uuid.uuidString.lowercased())"))
        // The same ids in every form that names a place.
        #expect(link("nyx://field/wd:Q42") == .field("wd:Q42"))
        #expect(link("nyx://calendar/wd:Q42?month=2027-05") == .calendar(park: "wd:Q42", year: 2027, month: 5))
        #expect(link("nyx://whatsup?date=2026-12-13&park=wd%3AQ42") == .whatsUp(park: "wd:Q42", day: TripDay(year: 2026, month: 12, day: 13)))
        // Anything else is still refused.
        for bad in ["nyx://park/wd:", "nyx://park/wd:Q", "nyx://park/wd:Q0123", "nyx://park/wd:Q12x", "nyx://park/wd:P31", "nyx://park/wd:Q1234567890123",
                    "nyx://park/pin:", "nyx://park/pin:not-a-uuid", "nyx://park/pin:\(uuid.uuidString)x", "nyx://park/geo:1,2", "nyx://park/:jotr",
                    "nyx://park/jotr:", "nyx://park/a", "nyx://park/abcdefghi", "nyx://park/../../etc", "nyx://park/%2E%2E", "nyx://park/j%20tr"] {
            #expect(link(bad) == nil, "\(bad)")
        }
        // Built links read back as themselves.
        for value in [DeepLink.park("wd:Q42"), .park("pin:\(uuid.uuidString.lowercased())"), .field("wd:Q42"), .calendar(park: "wd:Q42", year: 2027, month: 5),
                      .calendar(park: "pin:\(uuid.uuidString.lowercased())", year: nil, month: nil), .whatsUp(park: "wd:Q42", day: TripDay(year: 2027, month: 1, day: 3)), .park("jotr")] {
            #expect(value.url.flatMap(DeepLink.init) == value, "\(value)")
        }
    }
}
