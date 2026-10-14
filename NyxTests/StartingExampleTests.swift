import Foundation
import Testing
@testable import Nyx

/// Before a starting point is chosen, Tonight's example is measured from a town in the device's time
/// zone (outside the US), and the picker suggests the largest towns of the country, from settings alone.
struct StartingExampleTests {
    private func zone(_ id: String) throws -> TimeZone { try #require(TimeZone(identifier: id)) }

    @Test func aZoneAbroadGivesItsLargestTown() throws {
        #expect(StartingPlaces.example(timeZone: try zone("Asia/Kolkata"), region: "IN")?.savedName == "Mumbai")
        #expect(StartingPlaces.example(timeZone: try zone("America/Toronto"), region: "CA")?.savedName == "Toronto")
        // Canada's zones each give their own city, which the region alone could not.
        let vancouver=StartingPlaces.example(timeZone: try zone("America/Vancouver"), region: "CA")
        #expect(vancouver?.savedName == "Vancouver" && vancouver?.countryCode == "CA")
    }
    /// The zone wins over the region: a phone set to India, travelling in Toronto, starts from Toronto.
    @Test func theZoneWinsOverTheRegion() throws {
        #expect(StartingPlaces.example(timeZone: try zone("America/Toronto"), region: "IN")?.savedName == "Toronto")
    }
    /// A zone with no bundled town (UTC) falls back to the region's largest town; neither gives nothing.
    @Test func aZoneWithoutTownsFallsBackToTheRegion() throws {
        #expect(StartingPlaces.example(timeZone: try zone("UTC"), region: "IN")?.savedName == "Mumbai")
        #expect(StartingPlaces.example(timeZone: try zone("UTC"), region: nil) == nil)
    }
    /// In the US the example stays a national park, as it always has.
    @Test func theUSKeepsItsPark() throws {
        #expect(StartingPlaces.example(timeZone: try zone("America/New_York"), region: "US") == nil)
        #expect(StartingPlaces.example(timeZone: try zone("America/Los_Angeles"), region: "CA") == nil)
    }
    @Test func suggestionsAreTheCountrysLargestTowns() {
        let canada=StartingPlaces.largest(in: "ca", limit: 5)
        #expect(canada.count == 5 && canada.allSatisfy { $0.countryCode == "CA" })
        #expect(canada.first?.savedName == "Toronto")
        #expect(zip(canada, canada.dropFirst()).allSatisfy { ($0.population ?? 0) >= ($1.population ?? 0) })
        #expect(StartingPlaces.largest(in: "IN", limit: 3).first?.savedName == "Mumbai")
    }
}
