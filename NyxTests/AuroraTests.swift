import Foundation
import Testing
@testable import Nyx

/// G1: the aurora note follows geomagnetic latitude (a centred dipole, pole 80.8° N 72.8° W), in
/// both hemispheres, on nights when the Sun gets at least 12° down; not a US state.
struct AuroraTests {
    let parks: [Park]
    init() throws { parks = try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    func evening(_ park: Park, _ iso: String) throws -> Date { try #require(TripDay(iso: iso)).evening(in: park) }
    /// A park moved to other coordinates and zone: the same record otherwise, so it stays whole as `Place` grows.
    func place(_ id: String, latitude: Double, longitude: Double, zone: String) throws -> Park {
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(try park("jotr"))) as? [String: Any])
        json["id"] = id; json["latitude"] = latitude; json["longitude"] = longitude; json["timeZoneID"] = zone
        json["countryCode"] = "NZ"; json["region"] = ""; json.removeValue(forKey: "nps")
        return try JSONDecoder().decode(Park.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// Hand-worked: φm = asin(sin φ sin φp + cos φ cos φp cos(λ − λp)).
    @Test func geomagneticLatitudeByHand() throws {
        let φp = Geomagnetic.poleLatitude, λp = Geomagnetic.poleLongitude
        #expect(abs(Geomagnetic.latitude(latitude: φp, longitude: λp) - 90) < 1e-6)
        #expect(abs(Geomagnetic.latitude(latitude: -φp, longitude: λp+180) + 90) < 1e-6)
        // On the equator, 180° from the pole's meridian: −(90 − 80.8); on its meridian: +9.2.
        #expect(abs(Geomagnetic.latitude(latitude: 0, longitude: λp+180) + (90-φp)) < 1e-9)
        #expect(abs(Geomagnetic.latitude(latitude: 0, longitude: λp) - (90-φp)) < 1e-9)
        // The geographic poles sit at ±80.8° geomagnetic, whatever the longitude.
        #expect(abs(Geomagnetic.latitude(latitude: 90, longitude: 10) - φp) < 1e-9)
        #expect(abs(Geomagnetic.latitude(latitude: -90, longitude: -120) + φp) < 1e-9)
        // Denali (63.3° N, 150.5° W) by hand: about 63.7°.
        #expect(abs(Geomagnetic.latitude(of: try park("dena")) - 63.7) < 0.1)
    }

    /// Reach never falls as |φm| rises, and is the same north and south.
    @Test func reachIsMonotonic() {
        var last = Geomagnetic.AuroraReach.none
        for tenth in 0...900 {
            let φm = Double(tenth)/10
            let reach = Geomagnetic.AuroraReach(geomagneticLatitude: φm)
            #expect(reach >= last, "\(φm)")
            #expect(reach == Geomagnetic.AuroraReach(geomagneticLatitude: -φm), "\(φm)")
            last = reach
        }
        #expect(Geomagnetic.AuroraReach(geomagneticLatitude: 51.9) == .none && Geomagnetic.AuroraReach(geomagneticLatitude: 52) == .storms)
        #expect(Geomagnetic.AuroraReach(geomagneticLatitude: 56) == .active && Geomagnetic.AuroraReach(geomagneticLatitude: 60) == .often)
    }

    /// The 63 parks: every Alaska park keeps a note; the northern tier gains one; the tropics have none.
    @Test func whichParksHaveANote() throws {
        let nps = parks.filter { $0.nps != nil && $0.kind == .nationalPark }
        let reach = Dictionary(uniqueKeysWithValues: nps.map { ($0.id, Geomagnetic.auroraReach($0)) })
        #expect(Set(reach.filter { $0.value == .often }.keys) == ["gaar", "kova", "dena", "wrst", "glba", "lacl", "kefj"])
        #expect(Set(reach.filter { $0.value == .active }.keys) == ["katm", "voya", "isro"])
        #expect(Set(reach.filter { $0.value == .storms }.keys) == ["glac", "thro", "noca", "acad", "olym", "mora"])
        for park in nps where park.region == "AK" {
            #expect(SkyNotes.aurora(park: park, evening: try evening(park, "2026-12-01")) != nil, "\(park.id)")
            #expect(SkyNotes.aurora(park: park, evening: try evening(park, "2026-10-15"))?.contains("Nyx does not forecast aurora") == true, "\(park.id)")
        }
        for id in ["npsa", "havo", "hale", "viis", "jotr", "yell"] {
            let p = try park(id)
            #expect(Geomagnetic.auroraReach(p) == .none, "\(id)")
            #expect(SkyNotes.aurora(park: p, evening: try evening(p, "2026-12-01")) == nil, "\(id)")
        }
    }

    /// Aurora needs a dark night: none under Alaska's bright June nights, but Glacier's June nights get dark enough.
    @Test func onlyOnNightsDarkEnough() throws {
        let dena = try park("dena"), katm = try park("katm"), glac = try park("glac")
        #expect(SkyNotes.aurora(park: dena, evening: try evening(dena, "2026-06-21")) == nil)
        #expect(SkyNotes.aurora(park: katm, evening: try evening(katm, "2026-06-21")) == nil)
        #expect(SkyNotes.aurora(park: katm, evening: try evening(katm, "2026-11-01"))?.contains("toward the north") == true)
        let june = try #require(SkyNotes.aurora(park: glac, evening: try evening(glac, "2026-06-21")))
        #expect(june.hasPrefix("Aurora reaches here only during strong solar storms, low toward the north."))
        // Lowest Sun at solar midnight: |φ + δ| − 90, near −3° at Denali on the solstice, near −50° in December.
        #expect(abs(SkyNotes.lowestSun(park: dena, evening: try evening(dena, "2026-06-21")) + 3.3) < 0.3)
        #expect(abs(SkyNotes.lowestSun(park: dena, evening: try evening(dena, "2026-12-21")) + 50.1) < 0.3)
    }

    /// The south: 45° S 170° E (New Zealand's South Island) sits at about −48.6° on the centred dipole,
    /// short of the storm tier; 54.5° S 159° E (Macquarie Island) at about −59.4°, aurora toward the south.
    @Test func southernHemisphere() throws {
        let nz = try place("test:nz", latitude: -45, longitude: 170, zone: "Pacific/Auckland")
        #expect(abs(Geomagnetic.latitude(of: nz) + 48.6) < 0.1)
        #expect(Geomagnetic.auroraReach(nz) == .none)
        #expect(SkyNotes.aurora(park: nz, evening: try evening(nz, "2026-06-21")) == nil)
        let macquarie = try place("test:macquarie", latitude: -54.5, longitude: 158.95, zone: "Australia/Hobart")
        #expect(abs(Geomagnetic.latitude(of: macquarie) + 59.4) < 0.1)
        #expect(Geomagnetic.auroraReach(macquarie) == .active)
        let winter = try #require(SkyNotes.aurora(park: macquarie, evening: try evening(macquarie, "2026-06-21")))
        #expect(winter.contains("toward the south"))
    }
}
