import Foundation
import Testing
@testable import Nyx

/// "With the lights out": which place is shown, from which sky, and what is said.
@Suite struct LightsOutTests {
    let engine = AstronomyEngine()
    func night(_ park: Park, _ day: String, score: Int) throws -> Night {
        let sky = engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
        return Night(park: park, sky: sky, score: DarknessScore(value: score, moonPoints: 30, cloudPoints: 20, bortlePoints: 16, lengthPoints: 10), cloudCover: 10, forecastUpdated: .now)
    }

    /// The darkest estimate wins, the nearer of equals; nothing unless two classes darker than the start.
    @Test func darkestPlaceInReachTwoClassesDarker() throws {
        let parks = TestData.parks.filter { ["jotr", "deva", "grba", "zion"].contains($0.id) }
        let vegas = (latitude: 36.17, longitude: -115.14)
        let pick = try #require(LightsOut.darkest(parks, latitude: vegas.latitude, longitude: vegas.longitude, homeClass: 8))
        let darkest = parks.map(\.bortleEstimate).min()
        #expect(pick.place.bortleEstimate == darkest)
        let equals = parks.filter { $0.bortleEstimate == darkest }
        let nearest = equals.min { $0.distanceMeters(latitude: vegas.latitude, longitude: vegas.longitude) < $1.distanceMeters(latitude: vegas.latitude, longitude: vegas.longitude) }
        #expect(pick.place.id == nearest?.id)
        #expect(abs(pick.meters - (nearest?.distanceMeters(latitude: vegas.latitude, longitude: vegas.longitude) ?? 0)) < 1)
        // A start already as dark as the place, or one class brighter: nothing to show.
        #expect(LightsOut.darkest(parks, latitude: vegas.latitude, longitude: vegas.longitude, homeClass: (darkest ?? 1)+1) == nil)
        #expect(LightsOut.darkest([], latitude: vegas.latitude, longitude: vegas.longitude, homeClass: 9) == nil)
    }
    /// A city's light comes from the satellite grid, and is bright; with no grid cell, the assumed suburban sky.
    @Test func homeClassFromTheGridElseSuburban() {
        let vegas = LightsOut.homeClass(latitude: 36.17, longitude: -115.14)
        #expect(vegas.known && vegas.bortle >= 7)
        let sea = LightsOut.homeClass(latitude: 0, longitude: -150)
        #expect(sea.bortle == HomeSky.assumedBortle || sea.known)
    }
    @Test func bestNightIsTheHighestAndSaidPlainly() throws {
        let grba = try park("grba")
        let nights = [try night(grba, "2026-10-24", score: 61), try night(grba, "2026-10-25", score: 88), try night(grba, "2026-10-26", score: 88)]
        let best = try #require(LightsOut.best(nights, closure: nil))
        // The highest score; between equals, whichever the shared ranking prefers (`NightPlanner.better`).
        #expect(best.score.value == 88)
        #expect(best.id == (NightPlanner.better(nights[1], nights[2], closures: [:]) ? nights[1] : nights[2]).id)
        #expect(LightsOut.bestLine(best).hasPrefix("Best night at \(grba.shortName) in the next two weeks: "))
        #expect(LightsOut.bestLine(best).hasSuffix(", 88."))
        let target = LightsOut.Target(place: grba, meters: 257_000, homeClass: 8, homeKnown: true, best: best)
        #expect(LightsOut.sentence(target).hasPrefix("That's the sky at \(grba.shortName), "))
        #expect(LightsOut.spoken(target, origin: "Las Vegas").contains("Class 8") && LightsOut.spoken(target, origin: "Las Vegas").contains("Class \(grba.bortleEstimate)"))
        let assumed = LightsOut.Target(place: grba, meters: 257_000, homeClass: 7, homeKnown: false)
        #expect(LightsOut.spoken(assumed, origin: "your location").contains("suburban"))
    }
}
