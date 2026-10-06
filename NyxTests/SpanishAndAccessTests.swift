import Foundation
import Testing
@testable import Nyx

/// Spanish shipped in the bundle, data-backed names, access notes and the map outline.
struct SpanishAndAccessTests {
    let parks=(try? ParkData.load()) ?? []
    func park(_ id:String) throws -> Park { try #require(parks.first { $0.id==id }) }
    /// The compiled Spanish table, read directly so the test does not depend on the device language.
    func spanish(_ key:String) throws -> String {
        let path=try #require(Bundle.main.path(forResource:"es",ofType:"lproj"))
        let bundle=try #require(Bundle(path:path))
        return bundle.localizedString(forKey:key,value:"<missing>",table:nil)
    }

    // MARK: Spanish

    @Test func spanishIsInTheBundle() throws {
        #expect(Bundle.main.localizations.contains("es"))
        #expect(try spanish("Tonight")=="Esta noche")
        // The Learn essays are catalog strings; Spanish comes from Research/localization/learn-es.
        #expect(try spanish("essay.access").hasPrefix("Un cielo para todos"))
        #expect(try spanish("essay.darkness").hasPrefix("Un cielo que vale la pena proteger"))
    }
    @Test func eclipseSentencesKeepTheMoonCapitalized() throws {
        for type in ["total","partial","penumbral"] {
            let text=try spanish("You were out for the \(type) lunar eclipse at %@.")
            #expect(text.contains("de Luna"),"\(type): \(text)")
        }
    }
    @Test func showerNamesComeFromTheCatalog() throws {
        let showers=SkyEvents.shared.meteorShowers
        #expect(showers.count==13)
        for shower in showers {
            // English devices see the bundled IMO name; Spanish has its own for every code.
            #expect(shower.localizedName==shower.name)
            #expect(try spanish("shower.\(shower.code)") != "<missing>","\(shower.code)")
        }
        #expect(try spanish("shower.GEM")=="Gemínidas")
        #expect(try spanish("shower.LYR")=="Líridas")
    }

    // MARK: Access

    @Test func roadlessParksSayHowToGetThere() throws {
        let boatOrPlane=["chis","drto","isro","gaar","kova","lacl","katm","glba","npsa","viis","bisc"]
        for id in boatOrPlane {
            let park=try park(id)
            #expect(!park.drivable,"\(id)")
            #expect(park.accessNote?.isEmpty == false,"\(id)")
        }
        for park in parks {
            guard let access=park.access else { #expect(park.drivable); continue }
            #expect(access.sourceURL.hasPrefix("https://www.nps.gov/\(park.apiCode)/"),"\(park.id)")
            #expect(access.note.count<=120 && !access.note.contains("!"),"\(park.id)")
            #expect(try spanish("access.\(park.id)") != "<missing>","\(park.id)")
        }
        // Parks with a note but a road in still count as drivable.
        #expect(try park("dena").drivable && park("dena").access != nil)
        #expect(try park("jotr").drivable && park("jotr").access == nil)
    }
    @Test func tripPlannerCanLeaveOutBoatParks() {
        // From Ventura: Channel Islands is in reach as the crow flies, but only by boat.
        let all=TripPlanner.candidates(parks,latitude:34.28,longitude:-119.29,radiusMiles:250).map(\.id)
        let drive=TripPlanner.candidates(parks,latitude:34.28,longitude:-119.29,radiusMiles:250,drivableOnly:true).map(\.id)
        #expect(all.contains("chis") && !drive.contains("chis"))
        #expect(drive.contains("jotr") && drive==drive.sorted())
        // From Key West, Dry Tortugas is left out and Everglades stays.
        let keys=TripPlanner.candidates(parks,latitude:24.56,longitude:-81.78,radiusMiles:150,drivableOnly:true).map(\.id)
        #expect(!keys.contains("drto") && keys.contains("ever"))
    }
    @Test func guideRecordsCarryTheAccessNote() throws {
        let lookup=NightLookup(parks:parks,forecasts:[:],now:Date(timeIntervalSince1970:1_791_000_000))
        let records=lookup.parksNear(park:"Channel Islands",radiusMiles:50)
        #expect(records.first { $0.hasPrefix("Channel Islands") }?.contains("getting there:")==true)
    }

    // MARK: Map outline

    @Test func outlineSitsInsideItsFrames() throws {
        let outlines=SkyMap.outlines
        #expect(Set(outlines.map(\.region))==[.lower48,.alaska,.hawaii])
        let lower=try #require(outlines.first { $0.region == .lower48 })
        let frame=SkyMap.inset(.lower48).frame.insetBy(dx:-0.005,dy:-0.005)
        #expect(lower.rings.joined().allSatisfy { frame.contains($0) })
        // Joshua Tree lies inside the outline's box, west of Acadia.
        let box=lower.rings.joined().reduce(CGRect.null) { $0.union(CGRect(origin:$1,size:.zero)) }
        #expect(try box.contains(SkyMap.position(park("jotr"))) && SkyMap.position(park("jotr")).x<SkyMap.position(park("acad")).x)
        // Hawaiʻi keeps the islands inside its inset (Maui, the Big Island), not Kauaʻi's fragments.
        let hawaii=try #require(outlines.first { $0.region == .hawaii })
        #expect(hawaii.rings.joined().allSatisfy { hawaii.clip.insetBy(dx:-0.02,dy:-0.02).contains($0) })
    }
}
