import Foundation
import SwiftData

// Saved spots (G3, `Research/global-plan.md`): a place the person saves themselves, from where they
// stand, typed coordinates or a pin. The record is `SavedSpot` (Persistence.swift, NyxSchemaV2); this
// file turns it into a `Place` the engine scores, and saves, unsaves and deletes it.
//
// One spot, two rows. The spot's own record says where it is. While it is saved, a `SavedPark` row
// with the same id (`pin:<uuid>`) stands beside the saved parks, so every path that already follows
// saved parks (reminders, the widgets' snapshot, the watch, Siri's list, Plan, the bookmark on a
// place's page) includes it unchanged, and resolves it through `PlanModel.park(_:)`. Unsaving (the
// bookmark) removes that row only: the spot stays known, so journal entries written there keep
// their place. Deleting the spot removes both.

nonisolated extension Place {
    /// A saved spot as a place: never curated, no NPS code, no viewing spots of its own. Its Bortle
    /// class comes from the bundled sky grid ("estimated from satellite data"); where the grid has
    /// nothing (at sea, or a build without tiles) a suburban sky is assumed, Bortle 7, and
    /// `sourceNote` says so, as From home tonight does.
    init(spot: SavedSpot, grid: SkyGrid = .shared) {
        self.init(spotID: spot.id, name: spot.name, latitude: spot.latitude, longitude: spot.longitude, timeZoneID: spot.timeZoneID,
                  countryCode: spot.countryCode, region: spot.region, note: spot.note, grid: grid)
    }
    init(spotID: String, name: String, latitude: Double, longitude: Double, timeZoneID: String, countryCode: String, region: String,
         note: String? = nil, grid: SkyGrid = .shared) {
        let magnitude=grid.skyBrightness(latitude: latitude, longitude: longitude)
        self.init(id: spotID, nps: nil, name: name, countryCode: countryCode, region: region, kind: .custom, curated: false,
                  latitude: latitude, longitude: longitude, timeZoneID: timeZoneID, darkSkyDesignated: false,
                  bortleEstimate: magnitude.map(SkyGrid.bortle(fromMagnitude:)) ?? HomeSky.assumedBortle,
                  description: note ?? "", sourceURL: "",
                  sourceNote: magnitude == nil ? Self.assumedSkyNote : Self.satelliteSkyNote, viewingSpots: [])
    }
    /// Where a spot's Bortle class came from, in the words From home tonight uses.
    static var satelliteSkyNote: String { String(localized: "Estimated from satellite data. A light close by can make your own sky brighter.") }
    static var assumedSkyNote: String { String(localized: "No light map reaches here, so Nyx assumes a suburban sky, Bortle \(HomeSky.assumedBortle).") }
    /// True for a place the person saved (`pin:<uuid>`).
    var isSavedSpot: Bool { id.hasPrefix(SavedSpots.prefix) }
}

@MainActor enum SavedSpots {
    nonisolated static let prefix="pin:"
    /// Beyond this from every bundled place, the nearest one says nothing about the spot's clock or
    /// country: the zone follows the Sun's meridian instead (`Etc/GMT±N`) and the country is left empty.
    nonisolated static let nearestReach: Double=1_000_000

    /// A new spot at these coordinates: its zone, country and region from the nearest bundled place
    /// (`StartingPlaces.nearest`), looked up on this device. Coordinates are kept exactly as given;
    /// only the forecast request rounds them (`SpotForecast`).
    nonisolated static func make(name: String, latitude: Double, longitude: Double, note: String? = nil, now: Date = .now) -> SavedSpot {
        let local=locality(latitude: latitude, longitude: longitude)
        return SavedSpot(name: name, latitude: latitude, longitude: longitude, timeZoneID: local.timeZoneID,
                         countryCode: local.countryCode, region: local.region, createdAt: now, note: note)
    }
    /// The zone, country and region for a point: the nearest bundled place's, within `nearestReach`
    /// (its limits near a border are `StartingPlaces.nearest`'s).
    nonisolated static func locality(latitude: Double, longitude: Double) -> (timeZoneID: String, countryCode: String, region: String) {
        guard let nearest=StartingPlaces.nearest(latitude: latitude, longitude: longitude, within: nearestReach) else { return (solarZone(longitude: longitude), "", "") }
        let zone=nearest.timeZoneID.flatMap { TimeZone(identifier: $0) == nil ? nil : $0 } ?? solarZone(longitude: longitude)
        return (zone, nearest.countryCode, nearest.state)
    }
    /// The whole-hour zone of a meridian, for a spot far from any town (open sea, the poles): IANA's
    /// `Etc/GMT` zones, whose sign is inverted ("Etc/GMT+8" is eight hours behind UTC).
    nonisolated static func solarZone(longitude: Double) -> String {
        guard longitude.isFinite else { return "Etc/GMT" }
        let hours=Int((longitude/15).rounded())
        let clamped=min(12, max(-12, hours))
        return clamped == 0 ? "Etc/GMT" : "Etc/GMT\(clamped>0 ? "-" : "+")\(abs(clamped))"
    }
    /// Saves a spot and follows it (its `SavedPark` row). A failed save leaves nothing behind.
    @discardableResult static func save(_ spot: SavedSpot, in context: ModelContext) throws -> SavedSpot {
        context.insert(spot)
        try follow(spot.id, in: context, save: false)
        do { try context.save() } catch { context.rollback(); throw error }
        return spot
    }
    /// Puts a spot beside the saved parks again (the bookmark), once.
    static func follow(_ id: String, in context: ModelContext, save: Bool = true) throws {
        let existing=try context.fetch(FetchDescriptor<SavedPark>(predicate: #Predicate { $0.parkID == id }))
        if existing.isEmpty { context.insert(SavedPark(parkID: id)) }
        if save { do { try context.save() } catch { context.rollback(); throw error } }
    }
    /// Deletes a spot and its `SavedPark` row. Journal entries written there keep their words and
    /// photos; their place reads as unknown, as for any place Nyx no longer has.
    static func delete(_ id: String, in context: ModelContext) throws {
        for row in try context.fetch(FetchDescriptor<SavedPark>(predicate: #Predicate { $0.parkID == id })) { context.delete(row) }
        for spot in try context.fetch(FetchDescriptor<SavedSpot>(predicate: #Predicate { $0.id == id })) { context.delete(spot) }
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
