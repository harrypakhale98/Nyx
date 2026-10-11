import Foundation
import Testing
@testable import Nyx

/// G1, one kind of place: the parks read as places, and a record written before G1 still reads.
struct PlaceModelTests {
    /// A shared snapshot or a transfer from 1.4.1 and earlier carries `apiCode`, `state` and `hemisphere`.
    @Test func aRecordFromBeforeG1StillReads() throws {
        let parks=try ParkData.load()
        for park in parks {
            var old=try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(park)) as? [String: Any])
            old["apiCode"]=old.removeValue(forKey: "nps"); old["state"]=old.removeValue(forKey: "region")
            for key in ["countryCode", "kind", "curated"] { old.removeValue(forKey: key) }
            old["hemisphere"]=park.latitude<0 ? "south" : "north"
            let read=try JSONDecoder().decode(Park.self, from: JSONSerialization.data(withJSONObject: old))
            #expect(read==park, "\(park.id)")
        }
    }
    @Test func aPlaceRoundTrips() throws {
        for park in try ParkData.load() { #expect(try JSONDecoder().decode(Park.self, from: JSONEncoder().encode(park))==park) }
    }
    /// What holds for every catalogue place, whatever the catalogue's size.
    @Test func everyPlaceIsWhole() throws {
        let parks=try ParkData.load()
        #expect(Set(parks.map(\.id)).count==parks.count)
        #expect(parks.contains { $0.id==Park.defaultID })
        for park in parks {
            #expect(park.countryCode.count==2 && park.countryCode==park.countryCode.uppercased(), "\(park.id)")
            #expect(TimeZone(identifier: park.timeZoneID) != nil, "\(park.id)")
            #expect((-90...90).contains(park.latitude) && (-180...180).contains(park.longitude), "\(park.id)")
            #expect(!park.region.isEmpty && (1...9).contains(park.bortleEstimate), "\(park.id)")
            // The 63 parks keep their ids and their NPS codes.
            #expect(park.kind == .nationalPark && park.curated && park.nps != nil, "\(park.id)")
        }
    }
}
