import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The Moon as the iPhone draws it, for Apple Watch. SwiftUI's shader library is not on watchOS, so
/// the wrist cannot draw the photographic, park-tilted Moon itself: the iPhone shrinks the pictures
/// it already draws for its widgets (`SavedSkySync.renderWidgetMoons`) and hands them over as one
/// small file by WatchConnectivity, device to device. One file, replaced by each new one and never
/// added to; a night without a picture keeps the vector Moon (`MoonDisc`), never another night's.
nonisolated struct WatchMoons: Codable, Sendable, Equatable {
    static let currentVersion = 1
    /// Marks the file transfer in its metadata, so each side tells it from any other file.
    static let metadataKey = "nyx.watch.moons"
    /// Where the watch keeps the last set, in its App Group.
    static let fileName = "watch-moons.plist"
    /// The pictures' side in pixels: the dial's Moon is at most about 23 points (0.15 of a 150-point
    /// dial, `WatchGauge`) on a 2× screen, so 48 keeps it sharp at a few kilobytes a night.
    static let side = 48
    /// The nights the watch shows a place for: tonight and the week the Crown turns through.
    static let nights = 7
    /// No more places than the watch asks the iPhone to follow, and no more bytes than this (about
    /// five kilobytes a night): past either, later places keep the vector Moon.
    static let maxPlaces = WatchContext.maxWatchPlaces
    static let byteBudget = 200_000
    let version: Int
    /// When the iPhone made the set: a set that arrives late never replaces a newer one (`isNewer`).
    let sent: Date
    /// PNG pictures by `key(park:night:)`.
    let images: [String: Data]

    init(sent: Date, images: [String: Data]) {
        version = Self.currentVersion
        self.sent = sent; self.images = images
    }
    /// A night's key: the place's id and the night's evening (`Night.id`) in whole seconds, as the
    /// widgets' picture names it (`SharedSettings.moonImageURL`), so both sides name a night alike.
    static func key(park: String, night: Date) -> String { "\(park)-\(Int(night.timeIntervalSince1970))" }
    /// The night a key names, read from after its last hyphen (place ids may hold hyphens).
    static func night(of key: String) -> Date? {
        guard let dash = key.lastIndex(of: "-"), let seconds = Int(key[key.index(after: dash)...]) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
    /// The places whose Moons go to the watch, most wanted first and once each: those the watch asked
    /// for (the one kept on its Tonight leads), then the saved places its Tonight weighs, the starting
    /// park and Tonight's answer on the iPhone; at most `maxPlaces`.
    static func places(watch: [String], saved: [String], home: String, tonight: String?) -> [String] {
        var seen = Set<String>()
        return Array((watch + saved + [home] + (tonight.map { [$0] } ?? [])).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(maxPlaces))
    }
    /// The set for these places' nights, in order. A place's pictures travel together or not at all,
    /// so turning the Crown never flips between a photograph and the vector Moon; once one place does
    /// not fit, none after it is sent. `picture` gives a night's shrunk PNG, nil where there is none.
    /// Nil when there is nothing to send.
    static func pack(_ places: [(id: String, nights: [Date])], sent: Date, budget: Int = byteBudget, picture: (String, Date) -> Data?) -> WatchMoons? {
        var images: [String: Data] = [:], used = 0
        for place in places {
            let some = place.nights.compactMap { night in picture(place.id, night).map { (key(park: place.id, night: night), $0) } }
            let size = some.reduce(0) { $0 + $1.1.count + $1.0.utf8.count }
            guard used + size <= budget else { break }
            used += size
            for (key, png) in some { images[key] = png }
        }
        return images.isEmpty ? nil : WatchMoons(sent: sent, images: images)
    }
    /// Without the nights that ended before `cutoff`: the watch drops those it can no longer show.
    func pruned(before cutoff: Date) -> WatchMoons {
        WatchMoons(sent: sent, images: images.filter { (Self.night(of: $0.key) ?? .distantPast) >= cutoff })
    }
    /// Whether `moons` should replace `current`: only a set made later.
    static func isNewer(_ moons: WatchMoons, than current: WatchMoons?) -> Bool { current.map { moons.sent > $0.sent } ?? true }

    /// A binary property list: the pictures travel as raw bytes, not Base64 text.
    var data: Data? {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try? encoder.encode(self)
    }
    init?(data: Data) {
        guard let decoded = try? PropertyListDecoder().decode(WatchMoons.self, from: data), decoded.version >= 1 else { return nil }
        self = decoded
    }
    /// A night's picture, decoded, or nil: the caller then draws the vector Moon.
    func image(park: String, night: Date) -> CGImage? {
        guard let png = images[Self.key(park: park, night: night)], let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    /// A widget picture (180 pixels) shrunk to `side` pixels and encoded as PNG again; nil if it cannot be read.
    static func shrink(_ png: Data, side: Int = side) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: side,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, small, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
    /// The watch's copy, in its App Group (shared with nothing else; the complications draw symbols).
    static var storedURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedSettings.group)?.appendingPathComponent(fileName)
    }
    static func readStored() -> WatchMoons? { storedURL.flatMap { try? Data(contentsOf: $0) }.flatMap(WatchMoons.init(data:)) }
    /// Replaces the stored set in one write.
    func store() {
        guard let url = Self.storedURL, let data else { return }
        try? data.write(to: url, options: .atomic)
    }
}
