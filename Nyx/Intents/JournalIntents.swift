import AppIntents
import CoreLocation
import Foundation
import GeoToolbox
import SwiftData
import UniformTypeIdentifiers

/// The journal for Siri, Shortcuts and Apple Intelligence (the iOS 18 journal schema): "Add to my
/// Nyx journal: Milky Way overhead from the dunes" keeps the screen dark. Entries stay in Nyx's own
/// store on this iPhone; nothing is sent anywhere. A place is the park's own coordinates and name,
/// from the bundled library: no geocoding, no network.
@AppEntity(schema: .journal.entry)
struct JournalEntryEntity {
    struct Query: EntityStringQuery {
        func entities(for identifiers: [UUID]) async throws -> [JournalEntryEntity] {
            try await JournalAccess.entries { entry in identifiers.contains(entry.id) }
        }
        func entities(matching string: String) async throws -> [JournalEntryEntity] {
            let needle=Park.folded(string)
            return try await JournalAccess.entries(limit: 20) { entry in
                Park.folded(entry.notes).contains(needle) || (JournalAccess.park(entry.parkID).map { $0.matches(string) } ?? false)
            }
        }
        func suggestedEntities() async throws -> [JournalEntryEntity] { try await JournalAccess.entries(limit: 5) { _ in true } }
    }
    static let defaultQuery=Query()
    let id: UUID
    var title: String?
    var message: AttributedString?
    var mediaItems: [IntentFile]
    var entryDate: Date?
    var location: PlaceDescriptor?
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title ?? String(localized: "Journal entry"))",
                              subtitle: entryDate.map { "\($0.formatted(date: .abbreviated, time: .omitted))" })
    }
}
extension JournalEntryEntity {
    @MainActor init(_ entry: JournalEntry) {
        let park=JournalAccess.park(entry.parkID)
        id=entry.id
        title=park?.shortName
        message=entry.notes.isEmpty ? nil : AttributedString(entry.notes)
        mediaItems=entry.orderedPhotos.enumerated().map { IntentFile(data: $1.data, filename: "night-\($0+1).jpg", type: .jpeg) }
        entryDate=entry.date
        location=park.map(JournalAccess.place)
    }
}

/// "Add to my Nyx journal": a new entry at the park of tonight's followed night or field mode,
/// else the starting park, with the park's estimated Bortle class as the observed default (the
/// editor's default too). Photos are kept as the editor keeps them: up to four, as JPEG.
@AppIntent(schema: .journal.createEntry)
struct AddJournalEntryIntent {
    var message: AttributedString
    var title: String?
    var entryDate: Date?
    var location: PlaceDescriptor?
    var mediaItems: [IntentFile]
    func perform() async throws -> some ReturnsValue<JournalEntryEntity> {
        let entry=try await JournalAccess.add(title: title, message: String(message.characters), date: entryDate ?? .now,
                                              location: location, photos: mediaItems.prefix(4).map(\.data))
        return .result(value: entry)
    }
}

/// The journal's store for intents, which may run before any window has opened it.
@MainActor enum JournalAccess {
    /// Set by the app as it opens the store, so intents and windows share one container.
    static var container: ModelContainer?
    private static var store: ModelContainer? {
        if let container { return container }
        container=JournalStore.open(inMemory: false).container
        return container
    }
    nonisolated static func park(_ id: String) -> Park? { (try? ParkData.load())?.first { $0.id == id } }
    /// The park's place for the journal schema: its coordinates and name, nothing looked up.
    nonisolated static func place(_ park: Park) -> PlaceDescriptor {
        PlaceDescriptor(representations: [.coordinate(CLLocationCoordinate2D(latitude: park.latitude, longitude: park.longitude))], commonName: park.name)
    }
    /// The park a spoken entry belongs to: tonight's night in progress (field mode or a followed
    /// night), else a place the person named that is within 50 km of a park, else the starting park.
    static func defaultParkID(location: PlaceDescriptor?, inProgress: String?, home: String?) -> String {
        if let inProgress { return inProgress }
        if let coordinate=location?.coordinate, let parks=try? ParkData.load(),
           let near=parks.min(by: { $0.distanceMeters(latitude: coordinate.latitude, longitude: coordinate.longitude) < $1.distanceMeters(latitude: coordinate.latitude, longitude: coordinate.longitude) }),
           near.distanceMeters(latitude: coordinate.latitude, longitude: coordinate.longitude) < 50_000 { return near.id }
        return home ?? "jotr"
    }
    static func entries(limit: Int? = nil, where keep: @escaping (JournalEntry) -> Bool) async throws -> [JournalEntryEntity] {
        guard let store else { return [] }
        let all=try store.mainContext.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        let kept=all.filter(keep)
        return (limit.map { Array(kept.prefix($0)) } ?? kept).map(JournalEntryEntity.init)
    }
    static func add(title: String?, message: String, date: Date, location: PlaceDescriptor?, photos: [Data]) async throws -> JournalEntryEntity {
        guard let store else { throw NyxIntentError.journalUnavailable }
        let inProgress=FieldActivities.current?.attributes.parkID
        let parkID=defaultParkID(location: location, inProgress: inProgress, home: UserDefaults.standard.string(forKey: "homePark"))
        let notes=[title, message].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        let scaled=await Task.detached(priority: .userInitiated) { photos.map { PhotoScaling.jpeg($0, maxPixels: 2400) ?? $0 } }.value
        let entry=JournalEntry(date: date, parkID: parkID, observedBortle: park(parkID)?.bortleEstimate ?? 3, notes: notes, photos: scaled)
        entry.thumbnail=scaled.first.flatMap { PhotoScaling.jpeg($0, maxPixels: 900) }
        let context=store.mainContext
        context.insert(entry)
        do { try context.save() } catch { context.rollback(); throw NyxIntentError.journalUnavailable }
        return JournalEntryEntity(entry)
    }
}
