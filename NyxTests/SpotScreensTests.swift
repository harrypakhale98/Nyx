import Foundation
import Testing
@testable import Nyx

/// The screens of saved spots (G3): reading coordinates as people type and paste them, the name a new
/// spot is offered, how a spot names itself beside the parks, and Siri's and the widgets' list of places.
@MainActor
struct SpotScreensTests {
    private static func spot(_ id: String="pin:3f2a8c1e-5b7d-4e9a-8c6f-1d2e3f4a5b6c", country: String="US", region: String="CA") -> Park {
        Place(spotID: id, name: "North pullout", latitude: 34.18, longitude: -116.05, timeZoneID: "America/Los_Angeles",
              countryCode: country, region: region, grid: SkyGrid(bundle: .main, layers: []))
    }
    private static func point(_ text: String) -> CoordinateText.Point? { CoordinateText.point(text) }
    private static func close(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0-b) < 1e-9 } ?? false }

    /// Return in a wrapping one-line field (a spot's name, search at accessibility sizes) puts the
    /// keyboard away; a pasted line break does not.
    @Test func returnKeyEndsAOneLineField() {
        #expect(ReturnKey.pressed(old:"Ridge",new:"Ridge\n"))
        #expect(ReturnKey.pressed(old:"Ridgepullout",new:"Ridge\npullout"))
        #expect(!ReturnKey.pressed(old:"Ridge",new:"Ridge\npullout"))
        #expect(!ReturnKey.pressed(old:"Ridge",new:"Ridges"))
        #expect(!ReturnKey.pressed(old:"",new:""))
    }

    // MARK: Coordinates

    @Test(arguments: ["34.01, -116.18", "34.01,-116.18", "34.01 -116.18", "  34.01 ,  -116.18  ", "34.01°, -116.18°",
                      "34.01° N, 116.18° W", "34.01N 116.18W", "N34.01 W116.18", "N 34.01, W 116.18",
                      "116.18 W, 34.01 N", "34.01, \u{2212}116.18", "34.01; -116.18", "+34.01, -116.18", "34.01/-116.18"])
    func pastedPairsRead(_ text: String) {
        let point=Self.point(text)
        #expect(Self.close(point?.latitude, 34.01), "\(text)")
        #expect(Self.close(point?.longitude, -116.18), "\(text)")
    }
    @Test func degreesMinutesAndSecondsRead() throws {
        let point=try #require(Self.point("34°0'45\"N 116°10'44\"W"))
        #expect(Self.close(point.latitude, 34+45.0/3600))
        #expect(Self.close(point.longitude, -(116+10.0/60+44.0/3600)))
        // Typographic primes, and degrees with decimal minutes.
        let typographic=try #require(Self.point("34°0′45″N 116°10′44″W"))
        #expect(typographic == point)
        let minutes=try #require(Self.point("34°0.75'N 116°10.5'W"))
        #expect(Self.close(minutes.latitude, 34.0125))
        #expect(Self.close(minutes.longitude, -116.175))
    }
    @Test func decimalCommasReadOnlyWhereNothingElseIsMeant() {
        #expect(Self.point("34,01; -116,18") == CoordinateText.Point(latitude: 34.01, longitude: -116.18))
        #expect(Self.point("34,01 -116,18") == CoordinateText.Point(latitude: 34.01, longitude: -116.18))
        // A comma between two whole numbers is the separator.
        #expect(Self.point("34, -116") == CoordinateText.Point(latitude: 34, longitude: -116))
    }
    @Test func southAndWestAreNegative() {
        #expect(Self.point("14.25 S, 170.68 W") == CoordinateText.Point(latitude: -14.25, longitude: -170.68))
        #expect(Self.point("-14.25, -170.68") == CoordinateText.Point(latitude: -14.25, longitude: -170.68))
        #expect(Self.point("45.88 N, 4.95 E") == CoordinateText.Point(latitude: 45.88, longitude: 4.95))
    }
    @Test func outOfRangeIsSaidApartFromUnreadable() {
        #expect(CoordinateText.pair("95, 10") == .outOfRange)
        #expect(CoordinateText.pair("34, 190") == .outOfRange)
        #expect(CoordinateText.pair("-90, 180") == .point(.init(latitude: -90, longitude: 180)))
    }
    @Test(arguments: ["", "Joshua Tree", "34.01", "34.01, -116.18, 5", "34.01 N, 35.2 S", "116 W 117 E", "-34.01 S, 116 W",
                      "34°75'N 116°W", "34.5°10'N 116°W", "34'N 116W", "LAT 34 LON 116", "34..01, 5", "1, 2, 3"])
    func unreadableTextIsRejected(_ text: String) {
        #expect(CoordinateText.pair(text) == .unreadable, "\(text)")
    }
    @Test func oneFieldReadsItsOwnAxis() {
        #expect(CoordinateText.reading("", axis: .latitude) == .empty)
        #expect(CoordinateText.reading("  ", axis: .longitude) == .empty)
        #expect(CoordinateText.reading("-116.18", axis: .longitude) == .value(-116.18))
        #expect(CoordinateText.reading("116.18 W", axis: .longitude) == .value(-116.18))
        #expect(CoordinateText.reading("\u{2212}33.9", axis: .latitude) == .value(-33.9))
        #expect(CoordinateText.reading("34 N", axis: .longitude) == .unreadable)
        #expect(CoordinateText.reading("91", axis: .latitude) == .outOfRange)
        #expect(CoordinateText.reading("180", axis: .longitude) == .value(180))
        #expect(CoordinateText.reading("-180.5", axis: .longitude) == .outOfRange)
        #expect(CoordinateText.reading("34.01, -116.18", axis: .latitude) == .unreadable)
        #expect(CoordinateText.reading("abc", axis: .latitude) == .unreadable)
    }
    @Test func aCoordinateIsWrittenBackSoItReadsAgain() {
        #expect(CoordinateText.field(34) == "34")
        #expect(CoordinateText.field(-116.178888888) == "-116.178889")
        #expect(CoordinateText.reading(CoordinateText.field(-116.178888888), axis: .longitude) == .value(-116.178889))
    }
    @Test func fieldProblemsAreWords() {
        #expect(SaveSpotView.problem(.empty, axis: .latitude) == nil)
        #expect(SaveSpotView.problem(.value(3), axis: .latitude) == nil)
        #expect(SaveSpotView.problem(.outOfRange, axis: .latitude) == String(localized: "Latitude runs from -90 to 90."))
        #expect(SaveSpotView.problem(.outOfRange, axis: .longitude) == String(localized: "Longitude runs from -180 to 180."))
        #expect(SaveSpotView.problem(.unreadable, axis: .longitude) == String(localized: "Use decimal degrees, such as -116.18."))
    }

    // MARK: Names

    @Test func aNearbyTownNamesTheSpot() {
        let town=StartingPlace(name: "Twentynine Palms", state: "CA", latitude: 34.14, longitude: -116.07, timeZoneID: "America/Los_Angeles")
        #expect(SpotNaming.defaultName(latitude: 34.18, longitude: -116.05, nearest: town) == String(localized: "Near \("Twentynine Palms")"))
        // Beyond 50 km the town says little: the coordinates name it.
        let far=SpotNaming.defaultName(latitude: 35.2, longitude: -116.05, nearest: town)
        #expect(far == SpotNaming.coordinates(latitude: 35.2, longitude: -116.05))
        #expect(SpotNaming.defaultName(latitude: -60, longitude: -40, nearest: nil) == SpotNaming.coordinates(latitude: -60, longitude: -40))
    }
    @Test func coordinatesNameTheirHemispheres() {
        let name=SpotNaming.coordinates(latitude: -14.25, longitude: -170.68)
        #expect(name.contains("S"))
        #expect(name.contains("W"))
        #expect(!name.contains("-"))
        let north=SpotNaming.coordinates(latitude: 45.88, longitude: 4.95)
        #expect(north.contains("N") && north.contains("E"))
    }
    @Test func theTypedNameWinsTrimmedAndCapped() {
        #expect(SpotNaming.finalName(typed: "  Backyard  ", offered: "Near Moab") == "Backyard")
        #expect(SpotNaming.finalName(typed: " \n ", offered: "Near Moab") == "Near Moab")
        #expect(SpotNaming.finalName(typed: String(repeating: "a", count: 90), offered: "x").count == SpotNaming.maxLength)
    }

    // MARK: A spot beside the parks

    @Test func aSpotSaysWhereItIs() throws {
        #expect(Self.spot().placeEyebrow == String(localized: "Your spot · \("California")"))
        #expect(Self.spot().regionLine == "California")
        let abroad=Self.spot(country: "FR", region: "Auvergne-Rhone-Alpes")
        #expect(abroad.spotLocality.hasPrefix("Auvergne-Rhone-Alpes, "))
        // Far from every town on the list: no country, no region, and the eyebrow says only what it is.
        let sea=Self.spot(country: "", region: "")
        #expect(sea.placeEyebrow == String(localized: "Your spot"))
        let jotr=try #require(ParkData.load().first { $0.id == "jotr" })
        #expect(jotr.regionLine == "CA")
        #expect(jotr.placeEyebrow == (jotr.darkSkyDesignated ? String(localized: "\("CA") · International Dark Sky Park") : "CA"))
    }

    // MARK: Siri and the widgets

    @Test func followedSpotsJoinTheParksForSiriAndWidgets() throws {
        let spot=Self.spot()
        let jotr=try #require(ParkData.load().first { $0.id == "jotr" })
        let snapshot=SavedSkySnapshot(parks: [jotr, spot], forecasts: [:])
        let places=try ParkLibrary.places(snapshot: snapshot)
        #expect(places.count == (try ParkData.load()).count+1)
        #expect(places.last?.id == spot.id)
        // Catalogue ids resolve as before; a spot by its pin: id.
        #expect(ParkLibrary.place("jotr", snapshot: snapshot)?.id == "jotr")
        #expect(ParkLibrary.place(spot.id, snapshot: snapshot)?.name == "North pullout")
        // Spots first, then the saved parks, then the rest.
        let suggested=try ParkLibrary.suggested(snapshot: snapshot)
        #expect(suggested.prefix(2).map(\.id) == [spot.id, "jotr"])
        #expect(suggested.count == places.count)
        let entity=ParkEntity(spot)
        #expect(entity.isSpot)
        #expect(!ParkEntity(jotr).isSpot)
    }
    @Test func aSpotNoLongerFollowedIsNotOffered() throws {
        let jotr=try #require(ParkData.load().first { $0.id == "jotr" })
        let snapshot=SavedSkySnapshot(parks: [jotr], forecasts: [:])
        #expect(ParkLibrary.place("pin:3f2a8c1e-5b7d-4e9a-8c6f-1d2e3f4a5b6c", snapshot: snapshot) == nil)
        #expect(try ParkLibrary.places(snapshot: snapshot).count == (try ParkData.load()).count)
        #expect(try ParkLibrary.places(snapshot: nil).count == (try ParkData.load()).count)
    }
}
