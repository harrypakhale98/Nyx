import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Nyx

/// The Moon pictures handed to Apple Watch (`WatchMoons`): one small file, keyed by night as the
/// widgets' pictures are, packed a place at a time within the budget, and pruned as nights pass.
struct WatchMoonsTests {
    let night = Date(timeIntervalSince1970: 1_792_000_800)
    func nights(_ count: Int = WatchMoons.nights) -> [Date] { (0..<count).map { night.addingTimeInterval(Double($0)*86400) } }

    @Test func keyNamesTheNightAsTheWidgetPictureDoes() throws {
        let key = WatchMoons.key(park: "pin:34.1-116.2", night: night)
        #expect(WatchMoons.night(of: key) == night)
        // The widget's file name is "moon-<key>.png", so both sides look a night up alike.
        let url = try #require(SharedSettings.moonImageURL(park: "jotr", night: night))
        #expect(url.lastPathComponent == "moon-\(WatchMoons.key(park: "jotr", night: night)).png")
    }

    @Test func packsWholePlacesInOrderWithinTheBudget() throws {
        let png = Data(repeating: 1, count: 1000)
        let places = [(id: "jotr", nights: nights()), (id: "deva", nights: nights()), (id: "grba", nights: nights())]
        // Room for one place's week and part of the next: the second place does not travel at all, nor any after it.
        let moons = try #require(WatchMoons.pack(places, sent: night, budget: 7*1100+3000) { _, _ in png })
        #expect(moons.images.count == 7)
        #expect(moons.images.keys.allSatisfy { $0.hasPrefix("jotr-") })
        // A night without a picture is simply absent; the place's other nights still go.
        let partial = try #require(WatchMoons.pack([(id: "jotr", nights: nights())], sent: night) { _, date in date == night ? nil : png })
        #expect(partial.images.count == 6)
        #expect(partial.image(park: "jotr", night: night) == nil)
        // Nothing drawn yet: nothing to send.
        #expect(WatchMoons.pack(places, sent: night) { _, _ in nil } == nil)
    }

    @Test func roundTripsAndPrunesPassedNights() throws {
        let png = try #require(Self.png(side: 180))
        let moons = try #require(WatchMoons.pack([(id: "jotr", nights: nights())], sent: night) { _, _ in png })
        let data = try #require(moons.data)
        #expect(WatchMoons(data: data) == moons)
        #expect(WatchMoons(data: Data("not a plist".utf8)) == nil)
        let pruned = moons.pruned(before: night.addingTimeInterval(2*86400))
        #expect(pruned.images.count == 5)
        #expect(pruned.sent == moons.sent)
        #expect(pruned.image(park: "jotr", night: night.addingTimeInterval(2*86400)) != nil)
    }

    @Test func onlyALaterSetReplacesTheStoredOne() {
        let older = WatchMoons(sent: night, images: [:]), newer = WatchMoons(sent: night.addingTimeInterval(60), images: [:])
        #expect(WatchMoons.isNewer(newer, than: older))
        #expect(!WatchMoons.isNewer(older, than: newer))
        #expect(!WatchMoons.isNewer(older, than: older))
        #expect(WatchMoons.isNewer(older, than: nil))
    }

    @Test func shrinksTheWidgetPictureForTheWrist() throws {
        let png = try #require(Self.png(side: 180))
        let small = try #require(WatchMoons.shrink(png))
        #expect(small.count < png.count)
        let moons = WatchMoons(sent: night, images: [WatchMoons.key(park: "jotr", night: night): small])
        let image = try #require(moons.image(park: "jotr", night: night))
        #expect(image.width == WatchMoons.side && image.height == WatchMoons.side)
        #expect(WatchMoons.shrink(Data("no image".utf8)) == nil)
    }

    @Test func placesPutTheWatchsOwnFirstOnceEachAndCapped() {
        let places = WatchMoons.places(watch: ["zion", "jotr"], saved: ["jotr", "deva", ""], home: "deva", tonight: "grba")
        #expect(places == ["zion", "jotr", "deva", "grba"])
        let many = WatchMoons.places(watch: [], saved: (0..<20).map { "p\($0)" }, home: "jotr", tonight: nil)
        #expect(many.count == WatchMoons.maxPlaces)
        #expect(!many.contains("jotr"))
    }

    /// The iPhone names a night by `park.evening(park.date(tonight, addingDays:))`, the watch by the
    /// sky it computes (`Night.id`, `sky.evening`): the same instant, so every picture is found.
    @Test func iPhoneAndWatchNameEachNightAlike() throws {
        let parks = try ParkData.load(), engine = AstronomyEngine(), now = Date(timeIntervalSince1970: 1_792_040_000)
        for id in ["jotr", "dena", "npsa", "gaar"] {
            let park = try #require(parks.first { $0.id == id })
            for offset in 0..<WatchMoons.nights {
                let day = park.date(park.currentNight(at: now), addingDays: offset)
                #expect(engine.conditions(for: park, on: day).evening == park.evening(day), "\(id) +\(offset)")
            }
        }
    }

    /// An opaque square with a lit disc, standing in for the widgets' 180-pixel picture.
    static func png(side: Int) -> Data? {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(red: 0.96, green: 0.94, blue: 0.9, alpha: 1))
        context.fillEllipse(in: CGRect(x: 4, y: 4, width: side-8, height: side-8))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
