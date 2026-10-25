import Foundation
import Testing
@testable import Nyx

/// The Little Dipper count: a dark moonless sky shows all seven, a city two at most, a full Moon
/// fewer, clouds hide it, and there is no reading where the asterism is not up.
struct LittleDipperTests {
    let parks: [Park]
    let engine = AstronomyEngine()
    init() throws { parks = try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    func count(latitude: Double = 36, bortle: Int, moonlight: Double = 0, cloud: Double? = nil, aerosol: Double? = nil) throws -> Int {
        try #require(LittleDipper.reading(latitude: latitude, bortle: bortle, moonlight: moonlight, darkHours: 8, cloud: cloud, aerosol: aerosol)).visible
    }

    @Test func bortleOneWithoutAMoonShowsAllSeven() throws {
        for latitude in [12.0, 25, 36, 48, 68] { #expect(try count(latitude: latitude, bortle: 1) == 7) }
        #expect(try count(bortle: 2) == 7)
    }
    @Test func aCityCentreShowsTwoAtMost() throws {
        for latitude in [12.0, 36, 68, 89] { #expect(try count(latitude: latitude, bortle: 9) <= 2) }
        // Polaris and Kochab, the ends of the handle and the bowl, are the city's two.
        let city = try #require(LittleDipper.reading(latitude: 41, bortle: 9, moonlight: 0, darkHours: 8, cloud: nil, aerosol: nil))
        #expect(LittleDipper.stars.filter(city.sees).map(\.name) == ["Polaris", "Kochab"])
    }
    @Test func theCountNeverRisesAsTheSkyBrightens() throws {
        var previous = 7
        for bortle in 1...9 { let n = try count(bortle: bortle); #expect(n <= previous); previous = n }
    }
    @Test func aFullMoonLowersTheCount() throws {
        #expect(try count(bortle: 1, moonlight: 1) < 7)
        #expect(try count(bortle: 1, moonlight: 1) <= 3)
        #expect(try count(bortle: 3, moonlight: 0.7) < count(bortle: 3))
        // A city's own glow already hides what the Moon would: it changes little there.
        #expect(try count(bortle: 9, moonlight: 1) >= 1)
        // From the engine: Great Basin under a new and a full Moon.
        let grba = try park("grba")
        func evening(_ iso: String) throws -> Date { try #require(TripDay(iso: iso)).evening(in: grba) }
        func reading(_ iso: String) throws -> LittleDipper.Reading {
            let sky = engine.conditions(for: grba, on: try evening(iso))
            return try #require(LittleDipper.reading(latitude: grba.latitude, bortle: grba.bortleEstimate, moonlight: sky.moonlight ?? 0,
                                                     darkHours: sky.darkHours, cloud: 0, aerosol: nil))
        }
        #expect(try reading("2026-11-09").visible == 7)
        #expect(try reading("2026-11-24").visible < 7)
    }
    @Test func smokeAndCloudsTakeStars() throws {
        #expect(try count(bortle: 4, aerosol: 1.5) < count(bortle: 4))
        let overcast = try #require(LittleDipper.reading(latitude: 36, bortle: 1, moonlight: 0, darkHours: 8, cloud: 90, aerosol: nil))
        #expect(overcast.cloudsHide && overcast.visible == 0)
        #expect(overcast.label == "Clouds likely hide the Little Dipper, an estimate")
        #expect(try count(bortle: 1, cloud: 50) == 7)
    }
    @Test func southernParksAndNightsWithoutDarknessHaveNoReading() throws {
        let npsa = try park("npsa")
        #expect(npsa.latitude < LittleDipper.minimumLatitude)
        #expect(LittleDipper.reading(latitude: npsa.latitude, bortle: npsa.bortleEstimate, moonlight: 0, darkHours: 8, cloud: nil, aerosol: nil) == nil)
        #expect(LittleDipper.reading(latitude: -33.9, bortle: 1, moonlight: 0, darkHours: 8, cloud: nil, aerosol: nil) == nil)
        #expect(LittleDipper.reading(latitude: 5, bortle: 1, moonlight: 0, darkHours: 8, cloud: nil, aerosol: nil) == nil)
        // Denali in June: no true darkness, so twilight decides and Nyx does not count.
        #expect(LittleDipper.reading(latitude: 63.3, bortle: 1, moonlight: 0, darkHours: 0, cloud: nil, aerosol: nil) == nil)
        // Every park far enough north does have one on a dark night.
        for park in parks where park.latitude >= LittleDipper.minimumLatitude {
            #expect(LittleDipper.reading(latitude: park.latitude, bortle: park.bortleEstimate, moonlight: 0, darkHours: 8, cloud: nil, aerosol: nil) != nil)
        }
    }
    @Test func labelSaysItIsAnEstimate() throws {
        let reading = try #require(LittleDipper.reading(latitude: 36, bortle: 6, moonlight: 0, darkHours: 8, cloud: nil, aerosol: nil))
        #expect(reading.label == "\(reading.visible) of 7 Little Dipper stars, an estimate")
        #expect(reading.sentence.contains("estimate"))
    }
    @Test func theShapeKeepsTheAsterism() {
        let shape = LittleDipper.shape
        #expect(shape.points.count == 7 && LittleDipper.stars.count == 7)
        #expect(shape.aspect > 1.8 && shape.aspect < 3)
        // Polaris leads on the left; Pherkad and Kochab end the bowl on the right.
        #expect(shape.points[0].x == shape.points.map(\.x).min())
        #expect(shape.points[6].x == shape.points.map(\.x).max())
        for point in shape.points { #expect(point.x >= 0 && point.x <= shape.aspect + 1e-9 && point.y >= 0 && point.y <= 1 + 1e-9) }
    }
}
